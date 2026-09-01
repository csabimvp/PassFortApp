# M2 — Vault + storage

**Status:** Drafted. Start when `m1-crypto-core.md` is complete (the whole §6.2 surface driven from
Swift, KATs/tamper/fuzz green). Expect to revise this as M1 lands — anything below marked *(confirm
against M1)* depends on choices you'll have made by then.
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
.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),  // confirm current major

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

- **JSON for M2** (open decision 5) — zero dependencies, and `schema_version` in the AAD makes it
  swappable for CBOR later.
- **Padding** (open decision 7 — the recommendation is *yes*): pad the JSON to the next multiple of
  256 bytes before sealing, so `sealed.count` stops leaking note length. Prefix the plaintext with a
  `u32` length, pad with zeros, strip on decode. Cheap; closes the metadata leak from §3.1.
- `usedAt` is a **write-amplification trap** (§7.2). For M2, either debounce it to once/day or leave it
  `nil` and defer "last used" to a local sidecar (open decision 11 leans sidecar) — do **not** touch it
  on every `open`.

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

## Phase 5 — `VaultManifest.swift`: wire the streaming MAC

```swift
import PassFortCrypto

struct VaultManifest {
    /// Recompute the manifest MAC over every row, in UUID order (§5.5).
    static func compute(session: VaultSession, db: Database) async throws -> ManifestState {
        let rows = try SealedRecord
            .order(Column("uuid"))           // Swift decides the order; C++ hashes (§5.5)
            .fetchAll(db)
        let builder = try await session.manifestBuilder()
        for r in rows {
            try await builder.update(uuid: r.id, version: r.version, sealed: r.sealed)
        }
        let vaultVersion = try Self.readVaultVersion(db)
        let mac = try await builder.finish(vaultVersion: vaultVersion)
        return ManifestState(vaultVersion: vaultVersion, mac: mac)
    }

    /// At unlock: recompute, compare to vault_meta['manifest_mac'], AND check
    /// vault_version >= the high-water mark cached outside the DB.
    static func verifyAtUnlock(session: VaultSession, db: Database, highWater: UInt64) async throws
}
```

**What this function does.** `SealedRecord.order(Column("uuid")).fetchAll(db)` is GRDB's query builder
— it emits `SELECT * FROM records ORDER BY uuid` and decodes each row into a `SealedRecord`. The
`ORDER BY` is not cosmetic: the MAC folds rows in `uuid` order (§5.5), and the *same set of rows in a
different order produces a different MAC*, so verify and compute must both sort. Then it's the
streaming pattern from M1 Phase 7 — one `builder.update` per row (each `await`s a `pf_mac_update` hop
into C++), then `builder.finish` folds in `vault_version` and returns the 32-byte tag. `k_manifest`
never leaves the C++ session.

- **Include tombstoned rows** (`is_deleted = 1`) in the MAC — they're still real rows and dropping one
  must be detected. Only `compact` (Phase 6) actually removes them.
- The **`vault_version` high-water mark** lives *outside* the vault file (§5.5). M4 puts it in the
  Keychain; for the M2 CLI, a sidecar file `~/Library/Application Support/PassFort/.vault_hw` (mode
  `0600`) is enough. On unlock: if `vault_meta['vault_version']` < the sidecar value, the file was
  rolled back → refuse to open.

**Checkpoint:** `tests/…` — build a 3-record vault, compute the MAC, store it; delete a row directly
with SQL, `verifyAtUnlock` throws; restore an older copy of the whole `.sqlite`, `verifyAtUnlock`
throws on the `vault_version` check. Commit: `PassFortVault: manifest MAC compute + verify-at-unlock
(architecture §5.5)`.

---

## Phase 6 — `VaultRepository.swift`: CRUD, one transaction per write

This is the heart of M2 and the one place the §8.2 invariant is enforced.

```swift
public actor VaultRepository {
    private let db: VaultDatabase
    private let session: VaultSession

    // READ: pf_open each row, pair plaintext with envelope identity -> Account (§7.2)
    public func account(id: UUID) async throws -> Account?
    public func summaries() async throws -> [AccountSummary]     // the in-memory index (§8.3)

    // WRITE: serialize payload -> pf_seal -> bump version -> restamp updatedAt(HLC)
    //        -> write row -> recompute + write manifest_mac -> bump vault_version
    //        ALL IN ONE db.write { } TRANSACTION (§8.2)
    public func create(_ payload: AccountPayload) async throws -> Account
    public func update(id: UUID, _ mutate: (inout AccountPayload) -> Void) async throws -> Account
    public func delete(id: UUID) async throws                    // tombstone: is_deleted = 1
    public func compact() async throws                           // purge acked tombstones
}
```

**`db.dbQueue.write { db in … }` is the transaction.** GRDB opens a SQLite transaction, runs your
closure, and `COMMIT`s if it returns normally or `ROLLBACK`s if it throws. Everything inside — the row
`update`, both `vault_meta` writes — either all lands or none of it does. That is the §8.2 invariant
("every write is one transaction covering the row *and* the manifest MAC") enforced structurally: there
is no code path where the row changes but the MAC doesn't, because they're in the same `write` block.
The only thing *not* covered by it is the sidecar file (it's not in SQLite) — hence the ordering
callout below.

The write path, precisely (§7.2 "a save runs the reverse"):

```swift
public func update(id: UUID, _ mutate: ...) async throws -> Account {
    try await db.dbQueue.write { db in                     // ← ONE transaction
        guard var rec = try SealedRecord.fetchOne(db, key: id.data) else { throw PassFortError.notFound }
        var payload = try PayloadCodec.decode(await session.open(recordID: id, version: rec.version,
                                                                 schema: rec.schemaVersion, sealed: rec.sealed))
        mutate(&payload)
        rec.version    += 1                                 // monotonic; goes into the new AAD
        rec.updatedAt   = HLC.now(device: deviceID)
        rec.sealed      = try await session.seal(recordID: id, version: rec.version,
                                                 schema: rec.schemaVersion,
                                                 plaintext: PayloadCodec.encode(payload))
        try rec.update(db)
        let manifest = try await VaultManifest.compute(session: session, db: db)   // over the NEW row set
        try writeMeta(db, "manifest_mac", manifest.mac)
        try writeMeta(db, "vault_version", manifest.vaultVersion + 1)
        bumpHighWater(manifest.vaultVersion + 1)            // sidecar, AFTER the transaction commits
        return Account(envelope: rec, payload: payload)
    }
}
```

> **The ordering subtlety that will bite you.** The sidecar high-water bump must happen *after* the
> SQLite transaction commits — if you bump it first and the transaction rolls back, the next unlock
> sees `vault_version` < high-water and refuses to open a perfectly good vault. Bump inside `write { }`
> and it's not durable with the row. The safe order: commit the transaction, then bump the sidecar; on
> unlock, tolerate sidecar being exactly one behind (a crash in that window) but not ahead.

Recomputing the full manifest on every write is O(n) — fine at hobby scale (§8.3), and it's the
*correct* thing (the MAC is over the whole set). Note it as a known cost; incremental MAC update is a
future optimization, not an M2 concern.

**Checkpoint:** `tests/…` full CRUD — create returns an `Account`; update bumps `version` and changes
`sealed`; the manifest verifies after every operation; delete leaves a tombstone that still MACs;
`compact` removes it. Commit: `PassFortVault: VaultRepository CRUD, one transaction per write
(architecture §8.2)`.

---

## Phase 7 — The mid-write kill test

`architecture.md` §8.2: *"it needs a test that kills the process mid-write."* This is the single most
important test in M2 — the row and the manifest MAC must **never** diverge.

Approach: a helper executable (or a `passfort-cli __faultinject` hidden subcommand) that performs one
`update` with a `_exit(1)` forced at a chosen point.

**Why `_exit`, not `exit` or a thrown error.** `_exit(2)` terminates the process *immediately* — no
`atexit` handlers, no stdio flush, no C++/Swift destructors, no GRDB cleanup. That's what a power cut
or `kill -9` does, and it's the only way to test that SQLite's own crash-recovery (the WAL) plus your
transaction boundaries actually hold. `exit()` or `throw` would run cleanup paths that don't exist in a
real crash and would mask exactly the bug you're hunting. The fault points:

| Kill point | After reopen, expect |
|---|---|
| after `rec.update(db)`, before `manifest_mac` write, **inside the txn** | txn rolled back → old row, old MAC, consistent |
| after the txn commits, before the sidecar bump | row + MAC consistent; sidecar one behind → unlock tolerates it, then repairs |
| between `manifest_mac` write and `vault_version` write (if you split them) | **must be impossible** — they're in one txn; the test proves it |

The parent process runs the child, waits for the non-zero exit, then opens the vault with a fresh
`VaultRepository` and asserts `VaultManifest.verifyAtUnlock` succeeds (or fails *only* in the tolerated
sidecar-lag case, which then self-heals).

**Checkpoint:** the kill test passes at every fault point. If it doesn't, that's a real bug — fix it
and commit the fix with this test (`git-and-commits.md`). Commit: `PassFortVault: mid-write kill test —
row and manifest never diverge (architecture §8.2)`.

---

## Phase 8 — Recovery key (§5.6)

A second `wrapped_dek` slot in the header. **Whether the header already has room for it was decided in
M1 Phase 5** *(confirm against M1)*:

- **If M1 built `slot_count` into `format_version = 1`:** M2 just implements
  `pf_recovery_wrap` / `pf_recovery_unwrap` in `PFCrypto` (`keyring/header.cpp`) to fill/read slot 1.
  No format bump, no migration.
- **If M1's header has no slot concept:** this needs `format_version = 2`, a new ADR (format change,
  §5.3), and a re-seal migration that rewrites every vault header. Heavier — write the ADR first.

New seam functions (`architecture.md` §6.2, "later additions, same shape"):

```cpp
// header/recovery — recovery_key is 32 random bytes, NOT password-derived (no Argon2)
BytesResult pf_recovery_wrap(Session *s, const uint8_t recovery_key[32]) noexcept;  // -> new header
SessionResult pf_recovery_open(const uint8_t *header, size_t hlen,
                               const uint8_t recovery_key[32]) noexcept;            // parallel to pf_session_open
```

Swift side:

```swift
struct RecoveryKey: Sendable {
    var raw: Data                     // 32B, from system RNG at vault creation
    var grouped: String               // Base32, 4-char groups: "A2B4-9K7M-...". Crockford or RFC 4648 — pick, document
}
extension VaultSession {
    static func createWithRecovery(password: Data, params: KdfParameters) throws -> (header: Data, recovery: RecoveryKey)
    static func openWithRecovery(header: Data, recoveryKey: RecoveryKey) throws -> VaultSession
}
```

- The recovery key is **shown once**, at vault creation, and never stored (§5.6). `passfort-cli init`
  prints it with a "write this down, it will not be shown again" banner.
- `passfort-cli recover <vault> --key <grouped>` opens via the recovery slot and immediately forces a
  `rewrap` to a new password.
- **Why 256 bits and no Argon2.** A password is low-entropy, so it must be stretched by an expensive
  KDF before it's fit to be a key — that's what Argon2id buys. A recovery key *is* 256 bits of CSPRNG
  output, already a full-strength key, so it's fed straight into HKDF (`info="pf-rk-v1"`) → a KEK that
  wraps the **same** DEK as the password slot. A recovered session is byte-identical to a password
  session because it unwraps the identical DEK.
- **Why Base32 for the display form.** Base32 uses `A–Z` and `2–7` only — no lowercase, no `0/1/8/9`,
  nothing that's ambiguous when handwritten or read aloud. 256 bits is 52 Base32 characters; grouping
  them `XXXX-XXXX-…` is purely to make transcription errors visible. Pick RFC 4648 or Crockford Base32
  and write the choice down — they differ in alphabet and checksum.

**Checkpoint:** create a vault with recovery; open it with the password; open it with the recovery key;
both sessions seal/open the same record identically; `recover` rotates to a new password and the old
one stops working. Commit: `Recovery key: second DEK slot, wrap/unwrap, CLI recover (architecture
§5.6)`.

---

## Phase 9 — Plaintext export (§7.6)

The escape hatch from §1.3 — "escaping the format is always possible."

```swift
struct PlaintextExport: Codable {
    var schemaVersion: UInt16
    var exportedAt: Date
    var vaultUUID: UUID
    var accounts: [ExportedAccount]        // AccountPayload + { id, version, updatedAt }
}
```

- Behind an **explicit typed confirmation** (§5.6). The CLI:
  `passfort-cli export <vault> -o accounts.json` prompts *"Type EXPORT PLAINTEXT to confirm"* and reads
  it back before writing.
- Output is readable JSON that "a human, or a five-line import script, can actually read" (§7.6) —
  pretty-printed, snake_case keys matching the payload format.
- The output file is **not** git-ignored by pattern (it's `.json`), so the CLI writes it `0600` and
  prints a reminder that it's plaintext secrets on disk.

**Checkpoint:** `export` on a 3-account vault produces JSON with all payload fields decrypted plus
envelope identity; the confirmation gate rejects anything but the exact phrase. Commit: `Plaintext
export behind typed confirmation (architecture §1.3, §7.6)`.

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
high-water check (Phase 5) is what catches it. A *legitimate* restore requires clearing the sidecar
high-water mark — make that an explicit `passfort-cli verify --accept-restore` so it's a conscious act.

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
