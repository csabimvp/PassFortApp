# M2 — Vault + storage

**Status:** In progress — Phases 1–8 landed (GRDB, `Database.swift`, schema v1 + fixture harness, model
types with JSON + 256-byte padding, `VaultManifest`/`VaultMeta` + verify-at-unlock, `VaultRepository`
CRUD + `HighWaterMark`, `Vault` facades + mid-write kill test, recovery-key header slot +
`pf_recovery_wrap`/`open`, `RecoveryKey` + Crockford Base32 + `Vault.createWithRecovery`/`recover`, plaintext export +
`pf_session_vault_uuid`).
**Phase 10 (`passfort-cli` full CRUD + restore-from-backup — the CLI moves from header-file to SQLite
semantics, and the recovery/export UX lands here) is next.** Phases 10–11 remain. Open decisions
resolved 2026-09-01:
recovery key folds into header format v1 (ADR-0007), `usedAt` stays `nil` in M2 (§14.11), recovery key
rendered Crockford Base32, `verify --accept-restore` for legitimate restores. Open finding:
`is_deleted` is not in the manifest MAC (Phase 6 note) — decide before M5.
**Spec:** `architecture.md` §7 (data models), §8 (storage), §5.6 (recovery), §7.6 (export), §13.1.

---

## What M2 delivers

`architecture.md` §12: *"GRDB schema, migrations, repository, manifest wiring, recovery key, plaintext
export. Done when the CLI does full CRUD and restore-from-backup is verified."*

Everything in `PassFortVault` — the Swift storage/model layer that **cannot import `PFCrypto`** (§4).
It talks to the crypto core only through `PassFortCrypto`'s `VaultSession` / `ManifestBuilder`, and it
owns the SQLite database, the record models, and the one invariant that makes or breaks correctness:
**every write is a single transaction covering the row and the manifest MAC** (§8.2).

```
Sources/PassFortVault/
├── Database.swift          Phase 2   GRDB setup, WAL, pragmas, file location + perms
├── Migrations/
│   └── V1_initial.swift    Phase 3   records / vault_meta / schema_version
├── Model/
│   ├── SealedRecord.swift  Phase 4   the envelope (§7.1)
│   ├── AccountPayload.swift Phase 4  the sealed body + sub-models (§7.2, §7.3)
│   ├── Account.swift       Phase 4   the two halves joined (§7.2)
│   ├── VaultModels.swift   Phase 4   HLC, ManifestState, AccountSummary (§7.4, §7.5)
│   └── PayloadCodec.swift  Phase 4   JSON encode/decode + padding + the `unknown` bag
├── VaultManifest.swift     Phase 5   streams rows through ManifestBuilder
├── VaultRepository.swift   Phase 6   CRUD, every write one transaction
├── Recovery.swift          Phase 8   recovery-key wrap/unwrap + rendering
└── PlaintextExport.swift   Phase 9   the escape hatch
```

---

## Phase 1 — Add GRDB

`architecture.md` §8 / open decision 6: GRDB over raw `libsqlite3`. GRDB gives explicit SQL, real
migrations, and no opinion about a BLOB-shaped schema.

```swift
// Package.swift
.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),  // resolved to 7.11.1

.target(
    name: "PassFortVault",
    dependencies: [
        "PassFortCrypto",
        .product(name: "GRDB", package: "GRDB.swift"),
    ]
),
```

Commit `Package.resolved`. The `deps` CI job (added in M1 Phase 10 for swift-argument-parser) now
covers GRDB too — `swift package resolve && git diff --exit-code Package.resolved`.

> **`PassFortVault` still must not gain `.interoperabilityMode(.Cxx)`.** GRDB is a pure-Swift package;
> adding it changes nothing about the §4 layering guarantee. After this phase, re-verify: uncommenting
> `import PFCrypto` in a `PassFortVault` file still fails to compile.

**Checkpoint:** `swift build` resolves and compiles GRDB. Commit: `Add GRDB dependency (architecture
§8, decision 6)`.

---

## Phase 2 — `Database.swift`: connection, pragmas, location

```swift
import GRDB
import Foundation

public struct VaultDatabase {
    let dbQueue: DatabaseQueue

    public init(path: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = FULL")     // §8.2 — durability over speed
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        self.dbQueue = try DatabaseQueue(path: path, configuration: config)
        try Self.migrator.migrate(dbQueue)
    }
}
```

**What this sets up.** `DatabaseQueue` is GRDB's serialized connection: every read and write goes
through one SQLite connection on one private dispatch queue, so there's never a concurrent-writer
problem to reason about (SQLite allows only one writer anyway). `Configuration.prepareDatabase` runs
its closure once, right after the connection opens, before any query — the right place for `PRAGMA`s.
`migrator.migrate` (Phase 3) then brings the schema up to date.

The two durability pragmas:

- **`journal_mode = WAL`** (write-ahead logging): instead of writing changes into the main `.sqlite`
  file and keeping a rollback journal, SQLite appends them to a `-wal` sidecar and folds them back in
  later ("checkpoint"). A reader never blocks a writer, and a crash mid-write leaves the main file
  intact — the half-written transaction is just an unreferenced tail of the `-wal`.
- **`synchronous = FULL`**: SQLite issues an `fsync` at every commit, so once a write returns, the
  bytes are actually on disk — it survives a power cut. `NORMAL` (the WAL default) only fsyncs at
  checkpoint, which is faster but can lose the last few commits on power loss. A password manager
  takes the fsync cost. The mid-write kill test (Phase 7) proves this holds together with the manifest
  update.

Default vault location and hardening (§8.2):

- `~/Library/Application Support/PassFort/vault.sqlite`
- file mode `0600` (`FileManager` `setAttributes` `.posixPermissions`)
- exclude the directory from Spotlight: set `com.apple.metadata:com_apple_backup_excludeItem`, or drop
  a `.metadata_never_index` file in it
- the `-wal` and `-shm` sidecars inherit the directory; they're already git-ignored (bootstrap Phase 1)

**Checkpoint:** `VaultDatabase(path:)` on a temp path creates a WAL-mode SQLite file with mode `0600`.
Commit: `PassFortVault: database connection, WAL, FULL sync, 0600 (architecture §8.2)`.

---

## Phase 3 — Migrations + schema v1

`architecture.md` §8.1:

```swift
extension VaultDatabase {
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.eraseDatabaseOnSchemaChange = false        // NEVER true — forward-only (§8.2)

        m.registerMigration("v1") { db in
            try db.create(table: "records") { t in
                t.column("uuid", .blob).primaryKey().notNull()        // 16B
                t.column("version", .integer).notNull()               // monotonic; in the AAD
                t.column("sealed", .blob).notNull()                   // nonce ‖ ct ‖ tag
                t.column("is_deleted", .integer).notNull().defaults(to: 0)
                t.column("updated_at", .integer).notNull()            // HLC-encoded
                t.column("idx_title", .blob)                          // blind index — M5
                t.column("idx_url", .blob)
            }
            try db.create(table: "vault_meta") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .blob).notNull()
            }
            try db.create(table: "schema_version") { t in
                t.column("version", .integer).notNull()
            }
            try db.execute(sql: "INSERT INTO schema_version (version) VALUES (1)")
        }
        return m
    }
}
```

**How `DatabaseMigrator` works.** You register named migrations in order; GRDB runs each one exactly
once inside its own transaction and records the names it has applied in a `grdb_migrations` table. On
the next launch it runs only the ones not yet recorded. The model is **forward-only**: you never edit
a migration that has shipped (some vault has already run it) — a schema change is always a *new*
`registerMigration("v2") { … }`. `db.create(table:) { t in … }` is GRDB's schema DSL; it generates the
`CREATE TABLE` so column types and constraints are checked at compile time. `eraseDatabaseOnSchemaChange
= true` would make GRDB drop and rebuild the whole database whenever it detects a mismatch — a
convenience for throwaway app data and a catastrophe for a password vault, hence the explicit `false`.

`vault_meta` is the typed key/value store from §7.4 — keys `header`, `manifest_mac`, `vault_version`,
`kdf_calibration`. `schema_version` is **one vault-wide value** for M2 (§7.1) — a format/schema change
re-seals every record in one migration and steps this number, rather than a per-row column.

### Migration-fixture testing (the M2 CI addition, §13.4)

The rule from §8.2: *"each migration is tested against a checked-in fixture vault."* Set up the harness
now, even with one version:

```
Tests/PassFortVaultTests/Fixtures/
└── v1/
    ├── vault.sqlite          # a tiny synthetic vault at schema v1 — SYNTHETIC DATA ONLY
    └── README.md             # how it was generated, expected row count, the test password
```

The test: open every fixture with the current build, run `migrator.migrate`, assert it reaches the
current schema and the records still decrypt. Every future `vN` adds a fixture; none are ever
regenerated (that would defeat the point).

> **Fixture vaults are the one exception to "`*.sqlite` is git-ignored."** Add a negation to
> `.gitignore`: `!Tests/PassFortVaultTests/Fixtures/**/*.sqlite`. Every byte in them must be synthetic —
> the test password is in the fixture README, in the clear, on purpose.

**Checkpoint:** `swift test` runs the migrator against `Fixtures/v1/vault.sqlite` and it opens. Commit:
`PassFortVault: schema v1 + migration-fixture harness (architecture §8.1)`.

---

## Phase 4 — The model types

Transcribe §7 into `Sources/PassFortVault/Model/`. All `Sendable` value types; `Account` and
`AccountPayload` never reach `PassFortCrypto`.

### `SealedRecord` (§7.1) — the envelope

```swift
struct SealedRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    var id: UUID              // records PRIMARY KEY == account_id
    var version: UInt64
    var schemaVersion: UInt16 // §7.1: for M2, mirror the vault-wide schema_version value
    var sealed: Data
    var isDeleted: Bool
    var updatedAt: HLC
    var blindTitle: Data?     // nil until M5
    var blindURL: Data?

    static let databaseTableName = "records"
    // GRDB column mapping: uuid<->id, updated_at<->updatedAt.encoded, ...
}
```

**What `FetchableRecord, PersistableRecord` give you.** They're GRDB protocols. `FetchableRecord` =
"can be built from a database row" — you get `SealedRecord.fetchAll(db)`, `.fetchOne(db, key: id)`,
`.filter(…)`, `.order(…)`. `PersistableRecord` = "can be written back" — you get `record.insert(db)`,
`record.update(db)`, `record.delete(db)`. Column names come from the property names unless you map
them (`updated_at` ↔ `updatedAt`). Net effect: no hand-written SQL for CRUD, but `sealed` is still just
an opaque `Data` blob GRDB stores and returns without looking inside.

GRDB note: `UUID` ↔ `BLOB` needs a custom `DatabaseValueConvertible` that stores the 16 raw bytes
(`withUnsafeBytes(of: id.uuid)`), not GRDB's default 36-character string. `UInt64` version ↔ SQLite
`INTEGER` is a signed 64-bit column — fine up to 2^63, document the ceiling.

### `AccountPayload` (§7.2, §7.3) — the sealed body

Transcribe the full struct from §7.2 including sub-models (§7.3: `TOTPConfig`, `SecurityQuestion`,
`PasswordHistoryEntry`, `CustomField`, `PasswordStrength`, the enums). Two things that are **format**,
not code:

1. **`CodingKeys` are snake_case and pinned.** Swift's `Codable` uses the property names as JSON keys
   by default, so renaming `memorableWord` → `memWord` in a refactor would silently change the on-disk
   key and every existing record would fail to decode that field. An explicit `enum CodingKeys: String,
   CodingKey` on every struct freezes the wire names (`memorable_word`, `security_questions`,
   `password_history`) independent of the Swift identifiers. Renaming a property is then free; renaming
   a *key* is a deliberate format change (ADR + re-seal migration). Don't use a global
   `.convertToSnakeCase` strategy — that's one flag a future change could flip for the whole payload.
2. **The `unknown: [String: JSONValue]` bag** (§7.2, the A6 defence). The decoder collects
   unrecognised keys into it; the encoder writes them back verbatim. This makes the decoder
   *permissive* — a device one schema version behind must round-trip a newer record without dropping
   fields. `JSONValue` is a small enum over the JSON value space (`.string/.number/.bool/.null/.array/.object`).

### `PayloadCodec.swift` — encode/decode/pad

```swift
enum PayloadCodec {
    static func encode(_ p: AccountPayload) throws -> Data      // JSON, then pad
    static func decode(_ data: Data) throws -> AccountPayload   // unpad, then JSON, gather unknown
}
```

- **JSON for M2** (open decision 5) — done in Phase 4: zero dependencies, and `schema_version` in the
  AAD makes it swappable for CBOR later.
- **Padding** (open decision 7) — done in Phase 4: `u32` BE length ‖ JSON ‖ zero padding to the next
  multiple of 256 bytes before sealing, so `sealed.count` stops leaking note length (§3.1).
- `usedAt` is a **write-amplification trap** (§7.2). **Decided (§14.11): M2 leaves it `nil` and never
  writes it** — `PayloadCodec` round-trips the field if a newer writer set it, but no M2 code path
  touches it. "Last used" becomes a local-only sidecar table when the M3 GUI first needs it.

### `VaultModels.swift`

`HLC` (§7.4, `Comparable` — wall millis, then counter, then deviceID), `KdfParameters` (already exists
in `PassFortCrypto` — re-export or keep a parallel `Sendable` copy in `PassFortVault`), `ManifestState`
(`vaultVersion` + 32B `mac`), `AccountSummary` (§7.5 — **holds no secret**: id, title, username, host,
tags, favorite, flags).

**Checkpoint:** `swift test` — a hand-built `AccountPayload` encodes to JSON, decodes back equal;
a payload with an extra unknown key round-trips with the key preserved; padded ciphertext length is a
multiple of 256. Commit: `PassFortVault: record models + payload codec with forward-compat bag
(architecture §7)`.

---

## Phase 5 — `VaultManifest.swift`: wire the streaming MAC — DONE (2026-09-01)

Landed as `Sources/PassFortVault/VaultManifest.swift` + `VaultMeta.swift`, tested in
`VaultManifestTests.swift` (6 tests). What actually shipped, and how it differs from the sketch
below:

```swift
public enum VaultManifest {
    public enum Failure: Error, Equatable {
        case macMismatch
        case rollbackDetected(vaultVersion: UInt64, highWater: UInt64)
    }

    /// Reads a consistent row snapshot off the queue, then streams it through the
    /// session. For `passfort-cli verify` and tests.
    public static func compute(session: VaultSession, database: VaultDatabase,
                               vaultVersion: UInt64) async throws -> ManifestState

    /// Version check first (cheap, rejects a rolled-back file), then MAC recompute.
    @discardableResult
    public static func verifyAtUnlock(session: VaultSession, database: VaultDatabase,
                                      highWater: UInt64) async throws -> ManifestState
}
```

**The async/sync boundary shaped the API — worth internalising before Phase 6.** GRDB's
`dbQueue.read`/`write` closures are **synchronous** `@Sendable (Database) throws -> T`; you cannot
`await` inside one, and the `Database` handle must not escape it. But `session.makeManifestBuilder`
is actor-isolated (`await`), and so are `session.seal` / `session.open`. So every function here
splits in two: **(1)** a synchronous `dbQueue.read { }` that pulls out a plain-value snapshot
(`[SealedRecord]` sorted by `uuid`, plus `vault_version` and the stored MAC), then **(2)** the
`await` MAC streaming *outside* the closure. `ManifestBuilder.update` / `.finish` are themselves
synchronous (the builder is a standalone `@unchecked Sendable` object) — only *making* the builder
costs one actor hop. So the per-row cost is n plain C calls, **not** n `await`s — the runbook's
earlier "each `await`s a `pf_mac_update` hop" was wrong about the shipped seam.

- **Tombstoned rows** (`is_deleted = 1`) are included in the MAC — `SealedRecord.order(Column("uuid"))
  .fetchAll` has no `is_deleted` filter. Only `compact` removes a row.
- **`vault_version` is a parameter to `compute`, never read from the row inside it** — the MAC binds
  it (`HMAC(k, vault_version ‖ Σrows)`), so the caller passes the exact version the stored MAC was
  made at (verify) or the one about to be stored (write). The earlier sketch read it internally and
  the Phase 6 sketch then stored `vaultVersion + 1` — that mismatch would have broken every verify.
- **`vault_version` stored as 8 raw big-endian bytes** in `vault_meta` (`VaultMeta.writeVaultVersion`)
  — same canonical-int convention as the header codec.
- **The high-water mark** lives outside the file (§5.5): a `0600` sidecar `.vault_hw` for the M2 CLI,
  the Keychain from M4. `verifyAtUnlock` takes it as `highWater:` and throws `.rollbackDetected`
  before spending a MAC recompute.

**O(n)-per-write cost — decided, not deferred silently.** A full recompute on every write is correct
(the MAC is over the whole set) and cheap at this project's scale — the crypto runs at GB/s; even
10k rows is single-digit ms of hashing. If `passfort-cli bench` (extend it in Phase 10) ever shows it
biting, the fix is a **batched seam call** (`pf_mac_update_batch` over one contiguous buffer) —
same format, same tests, no ADR. An incremental multiset-hash combiner (LtHash-style, O(1) per write)
is a real format change and out of scope; note it and move on.

**Checkpoint (met):** `verifyPassesOnAnUntouchedVault`; `deletingARowBehindTheAppFailsTheMACCheck` and
`editingSealedBytesBehindTheAppFailsTheMACCheck` → `.macMismatch`;
`restoringAnOlderWholeFileFailsTheRollbackCheck` + `rollbackCheckRunsBeforeTheMACRecompute` →
`.rollbackDetected`; `macIsDeterministicAndBoundToVaultVersion`. `Package.swift`:
`PassFortVaultTests` gained a `PassFortCrypto` dep (live `VaultSession` in tests) — `Package.resolved`
unchanged (local target). Commit: `PassFortVault: manifest MAC compute + verify-at-unlock
(architecture §5.5)`.

---

## Phase 6 — `VaultRepository.swift`: CRUD, one transaction per write — DONE (2026-09-01)

The heart of M2 and the one place the §8.2 invariant is enforced. Landed as
`Sources/PassFortVault/VaultRepository.swift` + `HighWaterMark.swift`, 8 tests in
`VaultRepositoryTests.swift`.

```swift
public actor VaultRepository {
    // lifecycle -- session must already be open on the header
    static func bootstrap(database:session:header:deviceID:highWater:) async throws -> VaultRepository
    static func open(database:session:deviceID:highWater:) async throws -> VaultRepository  // verifyAtUnlock + repair
    func header() async throws -> Data

    func account(id: UUID) async throws -> Account?             // pf_open one row (tombstone flagged, not hidden)
    func summaries() async throws -> [AccountSummary]           // the in-memory index (§8.3)

    func create(_ payload: AccountPayload) async throws -> Account
    @discardableResult func update(id: UUID, _ mutate: (inout AccountPayload) -> Void) async throws -> Account
    func delete(id: UUID) async throws                          // tombstone, re-sealed at the bumped version
    func compact() async throws                                 // purge tombstones; no-op + no bump when none
}
```

**What differs from the original sketch:**

- **Lifecycle is explicit.** `bootstrap` seeds a new vault (stores the header in `vault_meta['header']`,
  writes `vault_version = 0`, MACs the empty set); `open` runs `VaultManifest.verifyAtUnlock` and
  repairs the sidecar forward if the file is ahead of it. `VaultDatabase` gained `: Sendable` so it can
  cross into the actor.
- **`HighWaterMark`** — the anti-rollback mark, a `0600` sidecar `<dbPath>.hw` (8 big-endian bytes;
  `.vault_hw` in the runbook was a guess — keyed to the db path is cleaner for >1 vault). `.reset()` is
  the `verify --accept-restore` hook (Phase 10). M4 swaps the backing store for the Keychain.
- **One private `commit(_ rowChange:)`** is the §8.2 core, shared by all four writers: read the current
  `vault_version` → open the `ManifestBuilder` at `version + 1` (the one actor hop) → in a single
  `db.write`, apply the row change, fold every row through the builder, write `manifest_mac` and
  `vault_version`. Then bump the sidecar *after* the commit. A `staleWrite` guard re-checks
  `vault_version` inside the transaction.
- **`delete` re-seals** the payload at the bumped version, so the row and its blob stay AAD-consistent
  and the manifest covers the tombstone transition via the version bump.

> **Finding to note (not a Phase 6 bug): `is_deleted` is not in the manifest MAC.** §5.5 folds
> `uuid ‖ version ‖ SHA-256(ciphertext)` per row — not `is_deleted`. Flipping only that column behind
> the app's back (hiding a live record, or resurrecting a tombstone without a version change) is
> undetected. `VaultRepository` always bumps `version` on a delete so its *own* deletes are covered,
> but an attacker editing the column directly is not. Closing this is a §5.5 change (add `is_deleted`
> to the MAC input) — an ADR + the cross-impl vector updated. Worth a decision before M5 sync, when
> tombstones start crossing the wire.

**`db.dbQueue.write { db in … }` is the transaction.** GRDB opens a SQLite transaction, runs your
closure, and `COMMIT`s if it returns normally or `ROLLBACK`s if it throws. Everything inside — the row
`update`, both `vault_meta` writes — either all lands or none of it does. That is the §8.2 invariant
("every write is one transaction covering the row *and* the manifest MAC") enforced structurally: there
is no code path where the row changes but the MAC doesn't, because they're in the same `write` block.
The only thing *not* covered by it is the sidecar file (it's not in SQLite) — hence the ordering
callout below.

The write path, precisely (§7.2 "a save runs the reverse"). **The async crypto happens *before* the
transaction; only synchronous SQLite work happens inside it** — GRDB's `write { db in … }` closure is
synchronous and cannot `await` (Phase 5 note). The one thing that must be inside: making the
`ManifestBuilder` costs an `await`, so open it before the closure and fold rows through it (sync)
inside:

```swift
public func update(id: UUID, _ mutate: (inout AccountPayload) -> Void) async throws -> Account {
    // --- async, before the transaction ---
    let (old, oldVersion) = try await db.dbQueue.read { db -> (SealedRecord, UInt64) in
        guard let rec = try SealedRecord.fetchOne(db, key: id.rawData) else { throw VaultError.notFound }
        return (rec, try VaultMeta.readVaultVersion(db))
    }
    var payload = try PayloadCodec.decode(
        await session.open(recordID: id, version: old.version, schema: old.schemaVersion, sealed: old.sealed))
    mutate(&payload)

    var rec = old
    rec.version  += 1
    rec.updatedAt = .now(device: deviceID)
    rec.sealed    = try await session.seal(recordID: id, version: rec.version,
                                           schema: rec.schemaVersion, plaintext: PayloadCodec.encode(payload))

    let newVaultVersion = oldVersion + 1
    let builder = try await session.makeManifestBuilder(vaultVersion: newVaultVersion)   // the one hop

    // --- synchronous, ONE transaction (§8.2) ---
    try await db.dbQueue.write { db in
        // guard against an interleaved writer (belt-and-suspenders: the actor + the
        // serialized queue already exclude one on this machine)
        guard try VaultMeta.readVaultVersion(db) == oldVersion else { throw VaultError.staleWrite }
        try rec.update(db)
        for r in try SealedRecord.order(Column("uuid")).fetchAll(db) {   // the post-write set
            try builder.update(recordID: r.id, version: r.version, sealed: r.sealed)
        }
        try VaultMeta.write(db, .manifestMAC, try builder.finish())
        try VaultMeta.writeVaultVersion(db, newVaultVersion)
    }
    bumpHighWater(newVaultVersion)                                  // sidecar, AFTER commit
    return Account(envelope: rec, payload: payload)
}
```

Note `VaultManifest.compute` is **not** used here — it opens its own read snapshot, which would be a
different transaction from the row write. The write path folds rows through its own builder inside the
one transaction instead. `compute` is for `passfort-cli verify` and tests.

> **The ordering subtlety that will bite you.** The sidecar high-water bump must happen *after* the
> SQLite transaction commits — if you bump it first and the transaction rolls back, the next unlock
> sees `vault_version` < high-water and refuses to open a perfectly good vault. Bump inside `write { }`
> and it's not durable with the row. The safe order: commit the transaction, then bump the sidecar; on
> unlock, tolerate sidecar being exactly one behind (a crash in that window) but not ahead.

Recomputing the full manifest on every write is O(n) — fine at hobby scale (§8.3), and it's the
*correct* thing (the MAC is over the whole set). The cost is n row fetches + n plain `pf_mac_update` C
calls (not n `await`s — Phase 5 note); the crypto runs at GB/s. If `passfort-cli bench` ever shows it
biting, the lever is a batched `pf_mac_update_batch` seam call — same format, no ADR. An incremental
multiset-hash combiner (O(1) per write) is a format change and out of scope for M2.

**Checkpoint (met):** `createRoundTripsThroughAccount`; `updateBumpsVersionAndResealsAndStaysVerifiable`
(version 1→2, `sealed` changes, reopen re-verifies); `summariesCoverEveryRowAndCarryNoSecret`;
`deleteHidesFromLiveReadsButStillVerifies` (tombstone flagged, `update` on it → `.notFound`, manifest
still verifies); `compactRemovesTombstonesAndKeepsTheManifestConsistent`; `compactIsANoOpWithNothingToPurge`
(no version bump); `restoringAnOlderDatabaseFileIsRejectedAtOpen` → `.rollbackDetected(2, 3)`;
`aFreshVaultOpensClean`. Commit: `PassFortVault: VaultRepository CRUD, one transaction per write
(architecture §8.2)`.

---

## Phase 7 — The mid-write kill test — DONE (2026-09-01)

`architecture.md` §8.2: *"it needs a test that kills the process mid-write."* The single most important
test in M2 — the row and the manifest MAC must **never** diverge.

**What shipped:**

- **`Sources/pf-killtest/`** — a real executable target (not a product), `pf-killtest <db-path>
  <fault-point>`. It `Vault.unlock`s the vault and does **one** `repo.update`, with a `FaultHook` that
  calls `_exit(1)` the instant the write reaches the named point. `_exit`, not `exit`/`throw`: no
  `atexit`, no flush, no destructors, no GRDB cleanup — exactly a power cut, so the test actually
  exercises SQLite's WAL recovery + the transaction boundary rather than a tidy unwind.
- **`FaultPoint` / `FaultHook`** on `VaultRepository` (`public`, defaulted `nil`, reachable only by
  whoever constructs the repo — inert in production). Three points in `commit(_:)`:
  `.afterRowWrite` and `.afterMetaWrite` (both *inside* the `db.write` closure, before COMMIT),
  `.afterCommit` (closure returned, COMMIT done, sidecar not yet bumped).
- **`Vault.unlock` / `Vault.create`** facades (`Vault.swift`) — wire `VaultDatabase` + `VaultSession`
  (header read from `vault_meta['header']`) + `VaultRepository` so the helper and the Phase 10 CLI
  don't re-implement the dance.
- **`MidWriteKillTests`** — parameterised over `FaultPoint.allCases`. Parent sets up a 2-record vault,
  **releases every connection**, spawns the child, asserts `_exit(1)`, then `Vault.unlock`s fresh
  (which runs `verifyAtUnlock`) and checks:

| Kill point | Result proven |
|---|---|
| `.afterRowWrite` | txn rolled back → `vault_version` unchanged, row still v1, notes `nil`, sidecar unchanged, manifest verifies |
| `.afterMetaWrite` | same — `manifest_mac` + `vault_version` written but not committed, so the whole txn is discarded |
| `.afterCommit` | txn committed → `vault_version` +1, row v2, notes set; sidecar was one behind, `Vault.unlock` repaired it forward; manifest verifies |

A broken transaction boundary would surface as `VaultManifest.Failure.macMismatch` on the reopen —
the test would fail loudly. The helper is located via `PF_KILLTEST_BIN` or `<package>/.build/debug/
pf-killtest`; `swift test` builds it automatically. Commit: `PassFortVault: mid-write kill test — row
and manifest never diverge (architecture §8.2)`.

---

## Phase 8 — Recovery key (§5.6)

**Split:** 8a — the C++ crypto core — **DONE (2026-09-01)**. 8b — the Swift `RecoveryKey` /
Crockford Base32 layer + CLI `recover` — **still to do**.

### 8a — header codec + seam (DONE)

**Decided — ADR-0007.** `format_version = 1` redefined: a 53-byte prefix (magic .. `slot_count`),
then `slot_count` × 72-byte slots, then the 8-byte `created_at`. No v2 bump, no migration — nothing
had shipped.

- **`keyring/header.{hpp,cpp}` rewritten** around `put_prefix` / `append_slot` / `unwrap_slot` /
  `parse_prefix` helpers. `kHeaderLen = 133` (1 slot), `kHeaderLenWithRecovery = 205` (2 slots), both
  `static_assert`ed against `header_size(slot_count)`. `parse_prefix` bounds-checks against the actual
  `slot_count` before reading `created_at` or any slot. `HeaderInfo` gained `slot_count`.
- **`slot_count` is the last AAD byte**, so both slots' tags authenticate it — `header_decode` on a
  forged 1-slot header cut down from a 2-slot one returns `AuthFailed` (test: *recovery: stripping
  slot 1 fails the tag on slot 0*).
- **`hkdf`**: `kInfoRecoveryKek = "pf-rk-v1"`, `derive_recovery_kek(rk[32]) = HKDF-Expand(rk, that
  label)` — no Argon2. Frozen cross-impl vector in `test_keyring.cpp`
  (`a160d1e4…dd754d1`), cross-checked against an independent HKDF call.
- **Seam** (`boundary/session.cpp`, `PFSession.hpp`): `pf_recovery_wrap(Session*, const uint8_t*
  recovery_key)` → new 2-slot header (re-wraps slot 0 under the session's password KEK, no Argon2;
  `BadInput` on a recovery-opened session with no password KEK); `pf_recovery_open(header, len, const
  uint8_t* recovery_key)` → `SessionResult` (`NotFound` if `slot_count != 2`, `AuthFailed` for a wrong
  key — no oracle; the session carries no password `RootKeys`).
- **`VaultSession`** (Swift): `func addRecoverySlot(recoveryKey: Data) throws -> Data` and
  `static func openWithRecovery(header:recoveryKey:) throws -> VaultSession` (both guard
  `recoveryKey.count == 32`).
- **Tests**: `test_recovery.cpp` (12 cases: keyring round-trip, wrong key, missing slot, slot-strip,
  `pf_recovery_wrap`/`open` end to end incl. reading a password-sealed record via recovery,
  recovery-session re-wrap rejection, null-ptr fuzz; closed-handle case `#ifndef PF_ASAN_BUILD`).
  Native 58 / ASan-UBSan 55 green. `BoundaryTest.swift` +2. `test_tamper.cpp` `kCreatedAt` is now
  `header.size() - 8`.

### 8b — Swift RecoveryKey + Crockford — DONE (2026-09-01)

- **`CrockfordBase32.swift`** — `encode` / `decode(_:outputByteCount:)` / `checkSymbol(for:)` /
  `decodeChecked`. Alphabet `0-9A-Z` minus `I L O U`; decode is tolerant (any case, `I`/`L` → `1`,
  `O` → `0`, hyphens and spaces skipped); check symbol is the value mod 37 through the extended
  alphabet (`…*~$=U`).
- **`RecoveryKey.swift`** — `struct RecoveryKey { let raw: Data /* 32B */ }`. `generate()` uses
  `SystemRandomNumberGenerator` (crypto-secure on-platform). `grouped` = 52 symbols in 13 hyphen
  groups of 4 + `-` + check symbol. `init(grouped:)` verifies the check symbol → `.malformed` on a
  one-symbol slip. `init(raw:)` guards `count == 32`.
- **`Vault.createWithRecovery(...) -> (repository, RecoveryKey)`** — `create` + `addRecoverySlot`
  before `bootstrap`, stores the two-slot header. **`Vault.recover(databasePath:recoveryKey:
  newPassword:deviceID:)`** — `openWithRecovery` → `rewrap` to the new password → write the new
  (password-only) header → `VaultRepository.open`. The recovery slot is consumed; rotate a fresh one
  after.
- **`VaultRepository.rotateRecoveryKey() -> RecoveryKey`** — `addRecoverySlot` + rewrite the stored
  header; DEK / records / `vault_version` untouched.
- **Tests** (`RecoveryKeyTests` 8, `VaultRecoveryTests` 4): Crockford round-trip / tolerance /
  bad-symbol / check-symbol slip; grouped-form shape KAT (all-zero → `0000-…-0`); `recover` rotates
  the password and keeps records, wrong key → `.authFailed`, no slot → `.notFound`; `rotateRecoveryKey`
  invalidates the old key. Swift suite 52 green.

**CLI (`passfort-cli recover` / recovery-key banner on create) is deferred to Phase 10**, where the
whole CLI moves from header-file to SQLite-vault semantics — piecemeal SQLite commands now would be
throwaway.

Commits: `PFCrypto: recovery-key header slot + pf_recovery_wrap/open (ADR-0007, §5.6)` /
`PassFortVault: RecoveryKey + Crockford Base32 + Vault.createWithRecovery/recover (§5.6)`.

**Why 256 bits and no Argon2 / why Crockford** — see ADR-0007. A recovery key *is* 256 CSPRNG bits,
already full-strength, so it feeds straight into HKDF; Crockford's alphabet and check symbol are
built for a human writing a key on paper and typing it back.

---

## Phase 9 — Plaintext export (§7.6) — DONE (2026-09-01)

The escape hatch from §1.3 — "escaping the format is always possible."

- **`PlaintextExport.swift`** — `PlaintextExport { schemaVersion, exportedAt, vaultUUID, accounts }`
  and `ExportedAccount { id, version, updatedAt, isDeleted, payload }`. `jsonData()` →
  pretty-printed, `.sortedKeys`, `.withoutEscapingSlashes`, ISO-8601 dates, snake_case
  (`schema_version`, `vault_uuid`, `is_deleted`, `updated_at`). Tombstones are included so an export
  is a complete snapshot.
- **`ExportConfirmation`** — the typed gate lives in the library, not just the CLI: `init(phrase:)`
  throws `VaultError.exportNotConfirmed` unless `phrase == "EXPORT PLAINTEXT"` exactly (trailing space
  rejected). `VaultRepository.exportPlaintext(confirmed:)` takes the token, so the ceremony cannot be
  skipped by a caller. The CLI (Phase 10) reads the phrase back and constructs the token.
- **`pf_session_vault_uuid(Session*, uint8_t out[16]) -> Status`** — a new read-only seam accessor for
  the plaintext §5.3 vault_uuid (needed by the export and by M5 sync). `VaultSession.vaultUUID()`
  wraps it. Native test in `test_header_codec.cpp` cross-checks it against `header_decode`.
- The output file is `.json` (not covered by the `*.pfvault` / `*.sqlite` git-ignore), so the writer
  must `0600` it and warn — that's a Phase 10 CLI responsibility.

**Checkpoint (met):** `PlaintextExportTests` (3) — the gate rejects `"export plaintext"` /
`"EXPORT PLAINTEXT "` / `""` and accepts the exact phrase; a 2-account vault (one tombstoned) exports
every decrypted field, the JSON has the snake_case keys and round-trips back to an equal
`PlaintextExport`; `vaultUUID` is stable across reopens. Swift suite 55, native 59 / ASan 56.
Commit: `PassFortVault: plaintext export behind a typed confirmation + pf_session_vault_uuid
(§1.3, §7.6)`.

---

## Phase 10 — `passfort-cli` full CRUD + restore-from-backup

Extend the M1 CLI (`bench`/`init`/`unlock`/`seal`/`open`) with the vault-level commands:

```
passfort-cli add    <vault> --title T [--username U] [--url ...] [--note ...]   # create
passfort-cli list   <vault> [--search Q]                                        # AccountSummary index
passfort-cli get    <vault> <id|title>                                          # one Account, secrets to stdout
passfort-cli edit   <vault> <id> --set password=...                             # update
passfort-cli rm     <vault> <id>                                                # tombstone
passfort-cli dump   <vault>                                                     # every record, decrypted (debug)
passfort-cli export <vault> -o file.json                                        # Phase 9
passfort-cli recover <vault> --key GROUPED                                      # Phase 8
passfort-cli verify <vault>                                                     # manifest + vault_version check only
```

- `list` builds the in-memory index (§8.3): one `pf_open` per record, `(id, title, username, host)`,
  search and sort in Swift. Drop it when the command exits.
- `get`/`dump` write secrets to stdout — fine for a CLI the user drives, but note it in `--help` and
  never log the values (§13.1: "no secret ever reaches a log").

### Restore-from-backup verification (the M2 "done when")

```bash
passfort-cli add  vault.sqlite --title github --username me
cp vault.sqlite vault.backup                    # a "backup"
passfort-cli add  vault.sqlite --title gitlab --username me
passfort-cli edit vault.sqlite <github-id> --set password=rotated

cp vault.backup vault.sqlite                    # "restore" — a whole-file rollback
passfort-cli verify vault.sqlite                # MUST FAIL: vault_version < high-water mark
```

The restore is indistinguishable from an attacker rolling the file back, and the `vault_version`
high-water check (Phase 5) is what catches it. **Decided:** a legitimate restore clears the sidecar
high-water mark via an explicit `passfort-cli verify --accept-restore` — a conscious act, no separate
`restore` subcommand.

**Checkpoint:** the full sequence above runs; `verify` fails on the rolled-back file and succeeds after
`--accept-restore`. This is the §12 M2 exit criterion. Commit: `passfort-cli: full CRUD + restore
verification`.

---

## Phase 11 — CI

- **migration-fixture job** (§13.4): already added in Phase 3 — the `swift` job now runs the fixture
  tests. Every future schema version adds a fixture and never regenerates the old ones.
- **anti-rollback tests** in the `swift` job: the Phase 5 delete-a-row and restore-old-file tests, and
  the Phase 7 kill test (it forks a subprocess — make sure the CI runner allows that; it does).
- the **`deps` job** now guards both swift-argument-parser and GRDB lockfiles.

**Checkpoint:** `swift` / `native` / `lint` / `secrets` / `deps` all green on a fresh checkout.

---

## Where this leaves you

- **Full CRUD through `passfort-cli`** against a real encrypted SQLite vault.
- **Every write is one transaction**; row and manifest MAC proven never to diverge, including under a
  mid-write kill.
- **Recovery key** and **plaintext export** both work — losing the master password is survivable, and
  escaping the format is always possible.
- **Restore-from-backup** is verified: a whole-file rollback is detected.
- **Next:** M3 — the SwiftUI GUI. That runbook folds in `bootstrap.md` Phase 6 (creating
  `PassFort.xcodeproj`) as its first phase, then builds Unlock / List / Detail / Edit against
  `VaultRepository`, with auto-lock and the in-memory search index. Ask for `m3-gui.md` when you get
  here.
