# M5 — Sync (Azure)

**Status:** Sketch, written ahead of the normal cadence (2026-09-04, on request). **M4 is not done and
the Azure spike is not done.** Only Phase 0 is safe to act on as written — everything past it is a plan
to *validate against the spike*, not a set of steps to follow blind. The runbook convention
(`README.md`) is that a milestone runbook is written when the previous one lands; treat every "DONE
when" and command below as provisional until Phase 0 has actually run and M4 has shipped.

**Prerequisite:** M4 complete — the app is a real macOS app (hardened runtime, sandbox, Keychain-backed
`HighWaterMarkStore`, optional Touch ID, concealed pasteboard, lock on sleep), `PassFort.entitlements`
+ `PassFort.entitlements.expected` exist and are diffed in `release.yml`, `DeviceIdentity.current()`
returns a stable Keychain-backed UUID, and `VaultSession.close()` makes lock-time zeroization
synchronous. See `m4-platform.md` "Where this leaves you" for what M5 inherits and the two `TODO(M5)`
markers it left (`com.apple.security.network.client`; the device id "wired, not yet meaningful").

**Spec:** `architecture.md` §9 (sync shape, conflicts, transport hardening, key rotation), §10 (the
Azure backend in full — footprint, storage model, the six-endpoint API, auth, anti-rollback, IaC),
§7.5 (`SyncEnvelope`, `VaultMeta.lastSyncedAt`), §5.5 + §10.5 (`seq` doubles as `vault_version`), §9.3
+ §7.2 (`AccountPayload.conflictOf`, the HLC), §5.1 (`k_index` / `auth_secret` in the key hierarchy),
§6.2 line 392 (`pf_blind_index` is the one M5 seam addition), §13.1 (the sync test matrix) and §13.2 /
§13.4 (the `cloud` CI job and the M5 deploy targets). ADR-0005 is the backend decision; ADR-0006 / §11
are the web client and stay in **M6**.

---

## What M5 delivers

`architecture.md` §12 M5 row: *"`Cloud/infra` Bicep → Storage + Functions; the §10.3 API; native HTTP
sync client; HLC conflict copies; blind indexes; key rotation. Done when: two machines converge through
Azure; conflicts surface in the UI; `az group delete` leaves no orphans."*

M5 is where the vault stops being single-device. It adds a **new project** (`Cloud/` — a TypeScript
Azure Functions app + Bicep) and a **new Swift subsystem** (`PassFortVault/Sync/`), and it makes the
one crypto-core change the whole milestone is allowed: `pf_blind_index`. **No vault-format change. No
change to seal/open, the header codec, or the manifest MAC.** The server never holds or inspects a
key — it moves `sealed` bytes byte-for-byte (§9.1) and enforces auth, `seq` monotonicity, and rate
limits, nothing more.

```
Cloud/                                   NEW — the Azure backend, no cryptography (§10)
├── openapi.yaml                         Phase 1   the sync contract; source of truth for all clients
├── infra/
│   ├── main.bicep                       Phase 10  Static Web App + Storage account + $5 budget alert
│   └── main.parameters.json             Phase 10
├── api/                                 Phases 2-4  TypeScript Functions
│   ├── src/functions/                   createVault · session · getRecords · putRecord · batch · getHeader
│   ├── src/{tableClient,auth,dto,seq}.ts
│   ├── test/                            Phase 4   contract tests against Azurite
│   ├── host.json  ·  package.json  ·  tsconfig.json
│   └── local.settings.json              dev only — git-ignored (§15 step 2)
└── README.md                            Phase 1   local loop (azurite + func + swa), deploy, teardown

Packages/PassFortKit/Sources/PFCrypto/
├── keyring/blind_index.{hpp,cpp}        Phase 5   HMAC(k_index, normalized input) → truncated tag
└── boundary/…                           Phase 5   pf_blind_index over the session handle

Packages/PassFortKit/Sources/PassFortCrypto/
└── VaultSession.swift                   Phase 5   +blindIndex(_:), +authResponse(challenge:)

Packages/PassFortKit/Sources/PassFortVault/
├── Sync/
│   ├── SyncClient.swift                 Phase 6   URLSession client against the §10.3 API
│   ├── SyncEngine.swift                 Phase 7   pull → reconcile (HLC) → push; conflict copies
│   ├── SyncEnvelope.swift               Phase 6   §7.5 DTO; `sealed` byte-identical to the local BLOB
│   ├── SyncCursor.swift                 Phase 8   highest `seq` seen; persisted via HighWaterMarkStore
│   └── PinnedTransport.swift            Phase 6   URLSessionDelegate — SPKI pinning, two pins (§9.4)
├── VaultRepository.swift                Phase 7   ingest remote records in one txn + manifest re-MAC
│                                        Phase 6   populate `idx_title` blind index on every write
│                                        Phase 8   `compact` gated on the sync cursor
│                                        Phase 9   DEK rotation: re-seal every record (§9.5)
└── VaultMeta.swift                      Phase 6   +lastSyncedAt, +syncCursor accessors

Packages/PassFortKit/Sources/passfort-cli/
└── PassFortCLI.swift                    Phase 6/9  `sync` subcommand; `rotate-dek`; `compact` un-stubbed

PassFort/  (the app)
├── PassFort.entitlements                Phase 6   + com.apple.security.network.client
├── PassFort.entitlements.expected       Phase 6   regenerated
├── Model/{AppModel,VaultService}.swift  Phase 12  sync state, trigger points, conflict surfacing
└── Features/{Sync,Settings}/            Phase 12  sync status UI; enable/configure sync

.github/workflows/
├── ci.yml                               Phase 4   NEW `cloud` job (Linux): npm ci · tsc · eslint · contract tests vs Azurite
└── release.yml                          Phase 10  + Azure infra deploy + SWA deploy (M5 targets, OIDC auth)
```

### What is **not** in M5 (do not build it here)

| Deferred to | What |
|---|---|
| **M6** | the web client — `Web/`, `pfcrypto.wasm`, the SWA static bundle, cross-origin isolation, the three-core agreement test. M5 stands up the API the web client will call; it does not call it. |
| **M7** | the real notarized+stapled release; the nightly long-run fuzz job; SPKI pin rotation drills. |
| **format v2 / a later ADR** | attachments (§7.7 — `sealed` file rows + Blob Storage); OPAQUE/SRP auth (§10.4, §14.8 — `auth_secret` challenge-response is M5); strict multi-writer anti-rollback under genuine concurrency (§10.5 caveat). |
| **not at all** | any server-side crypto, any server-side decrypt, any endpoint that requires a key. A test that the server *rejects* a key-shaped request is in Phase 4. |

### The M5 rules

- **`Cloud/` contains no cryptography** (§4 note 5). If you find yourself importing a crypto library
  into `Cloud/api`, stop — the design is wrong. The framing check on `sealed` (Phase 3) is a length
  check, not a crypto check.
- **The sync layer adds no crypto of its own** (§9.1). `SyncEnvelope.sealed` is `Data` copied verbatim
  from the SQLite BLOB. Sync moves exactly what storage holds.
- **`PassFortVault/Sync/` stays in the `PassFortVault` target** (§4 tree) — no new SwiftPM product. It
  may use `Foundation` `URLSession` and may call `PassFortCrypto` (for `pf_blind_index` /
  `pf_auth_response`, exactly as `VaultManifest` already calls it); it still may not import `PFCrypto`.
- **Every ingest of remote records is one transaction covering the rows *and* the manifest re-MAC**
  (the §8.2 invariant, unchanged) — plus the §10.5 `seq`-floor assertion before the transaction
  commits. A pull that would move `seq` backwards is refused, not applied.
- **`passfort-cli` gets `sync` before the GUI does.** M1–M2 were CLI-first; M5's protocol work is too.
  Two `passfort-cli` instances converging through a local Azurite host is the Phase 6/7 checkpoint; the
  GUI (Phase 12) is a front end onto an already-tested engine.

> **Path note:** `architecture.md` §4 draws the CLI at `Tools/passfort-cli/`; it actually lives at
> `Packages/PassFortKit/Sources/passfort-cli/` (M1 deviation, already logged). Same for `Sync/` —
> `Packages/PassFortKit/Sources/PassFortVault/Sync/`.

---

## Phase 0 — The Azure spike, and the decisions it settles

**This is `architecture.md` §15 step 6, and it is the gate on the rest of the milestone.** Same move as
M0 retiring the interop risk and M1 being the C++ go/no-go: prove the protocol and the cost model
locally and cheaply *before* M5 is on the board. Nothing below Phase 0 is real until this runs.

### 0.1 The spike

One throwaway branch, deleted when done. Build the minimum that answers "is the custom backend a
second project wearing a trench coat, or not":

- **One HTTP Function** (`PUT` a record, `GET` records since a cursor) + **Table Storage**, running on
  **Azurite** + `func start` — entirely local, entirely free.
- The `$changes` counter entity per partition, bumped with an **ETag retry loop** (§10.2). Prove the
  `seq` cursor: write three records, `GET ?since=0` returns all three with a `seq`, `GET ?since=<that>`
  returns nothing.
- `passfort-cli` (a scratch `sync` subcommand) **pushes and pulls sealed blobs** through that shape —
  `SyncEnvelope.sealed` is the SQLite BLOB, unmodified, and a pulled blob still `pf_open`s.
- Measure: cold-start latency of a Consumption Function, Table Storage transaction cost at 1000
  writes, and confirm the whole loop needs no always-on resource.

**Spike exit:** you can state, from having done it, how many days the real `Cloud/` project is and
whether ADR-0005's "keep CloudKit as the fallback" clause should fire. If the spike says the backend
costs more attention than it teaches, **stop and switch to CloudKit** (ADR-0005 alternatives) — that is
a real, sanctioned outcome, and this runbook is then wrong.

### 0.2 Decision: pin down the auth handshake — maybe **ADR-0009**

§10.4 is a *sketch*, not a spec, and it has an under-specified spot: it says the server does a
"constant-time compare of 32 bytes" against `auth_verifier = HMAC(serverPepper, auth_secret)` **and**
that the client sends "a challenge-response HMAC over `auth_secret`, never the secret itself". Those
two together don't fully close — a challenge-response the server can verify means the server can
reconstruct the expected response, i.e. it holds `auth_secret` (or a value the response is computed
over). Resolve it concretely in the spike. Recommended shape:

- **Registration** (`POST /v1/vaults`): client sends `auth_secret` (32 B) **once**, over TLS. Server
  computes `auth_verifier = HMAC(serverPepper, auth_secret)`, stores *that*, discards the raw value.
  `serverPepper` is a Function app-setting, never in the DB.
- **Login** (`POST /v1/vaults/{id}/session`): server sends a random 32-B `challenge`; client returns
  `response = HMAC(auth_verifier_input, challenge)` where the client computes the same
  `auth_verifier`-equivalent locally… — **this is the part to nail in the spike.** The clean version:
  the server stores `auth_secret` encrypted-at-rest under `serverPepper` (AES-GCM, pepper as key),
  decrypts it in-Function to verify `HMAC(auth_secret, challenge)` in constant time, never logs it. A
  full Azure breach (DB + app settings) then exposes `auth_secret` as an offline Argon2-cost target —
  **exactly the limitation §10.4 and §14.8 already own.** OPAQUE removes it and stays deferred.
- The core exposes this without widening "keys never leave C++": `auth_secret` is explicitly *the one
  value shown to a server* (§5.1). Add `pf_session_auth_response(Session*, challenge*, len) -> 32B`
  (login) and `pf_session_auth_secret(Session*) -> 32B` (registration only). Both go through the seam
  fuzz suite in Phase 5.

**Deliverable:** if the handshake you land on is a literal reading of §10.4, note it in the `Cloud/`
README and move on. If it deviates in any load-bearing way (and "the server holds `auth_secret`
decryptable" *is* load-bearing), write **`docs/adr/0009-sync-auth-handshake.md`**, status Accepted, and
add a §3.4 bullet: *"the sync server stores a value from which `auth_secret` is recoverable given a
breach of both Table Storage and the Function app settings; offline-crackable at Argon2 cost; OPAQUE
deferred (§14.8)."*

### 0.3 Decisions the milestone resolves in `architecture.md` §14 (doc edits, not ADRs)

M5 turns four "leaning X" open decisions into resolved ones — do this as part of the phases that touch
them, and update §14 + the rev line at the end:

| §14 # | Resolve to | In phase |
|---|---|---|
| 8 — server auth | `auth_secret` challenge-response for M5; OPAQUE stays deferred | 0.2 / 4 |
| 12 — Table vs Blob | Table Storage (records only; Blob only if attachments land) | 2 |
| 13 — thin API vs SAS | the thin Functions API | 3 |
| 14 — Bicep vs Terraform | Bicep (already folded into ADR-0005; just close the entry) | 10 |

### 0.4 Calibrate

- **`Cloud/` is a genuinely separate skill tree** — Functions programming model, Table Storage, Bicep,
  Static Web Apps, OIDC federation, an OpenAPI contract, teardown discipline. §1.1 goal 6 says that is
  *the point*, not a tax. Budget it like a milestone, because it is.
- **Local-only until Phase 10.** Azurite + `func` + `swa` run the entire M5 loop offline and free
  (§10.6). The cloud enters exactly once, at deploy, behind a `$5` budget alert.
- **The web client is M6.** Resist building `Web/` here. M5's job is the API and the native client; a
  second consumer of the API is the next milestone's proof that the contract was right.

**Checkpoint:** the spike branch demonstrates a `seq` cursor and a round-tripped sealed blob on
Azurite; 0.2 is decided (and ADR-0009 written if it deviated); you can defend "custom backend, not
CloudKit" from experience, or you have invoked the fallback. Delete the spike branch. Everything below
is now real work.

---

## Phase 1 — `Cloud/` skeleton, the contract, and the local loop

Stand up the project structure and the offline development loop before any endpoint logic.

### 1.1 `.gitignore` and secret hygiene first (§15 step 2)

Add, and confirm the pre-commit secret hook + `secrets` CI job cover the first two:

```
Cloud/api/local.settings.json      # Storage connection string + JWT signing key + serverPepper
Cloud/api/node_modules/
Cloud/**/dist/
.azure/
```

`local.settings.json` holds the dev JWT key and `serverPepper`. It must never be committed; production
values are written to Function app settings by the Bicep deploy from a GitHub secret (§14, last
bullet). Run `gitleaks detect --config .gitleaks.toml` locally once after adding the file to prove the
config catches it.

### 1.2 `Cloud/openapi.yaml` — the contract, written first

The six §10.3 endpoints, request/response schemas, error codes (`401`, `409` on create-collision,
`412` on stale `If-Match`, `429`). This file is the **single source of truth** for the API, the native
`SyncEnvelope` DTO, and (M6) the web client's DTO. Generate the TypeScript types from it
(`openapi-typescript`) so `Cloud/api/src/dto.ts` is not hand-maintained. Do not let the implementation
and the contract drift — Phase 4's contract tests are generated from this file.

```
POST /v1/vaults                          { authSecret, header }                 -> 201 { vaultId }
POST /v1/vaults/{id}/session             { challenge? } then { response }       -> 200 { token, seq }
GET  /v1/vaults/{id}/records?since={seq}  —                                      -> 200 { records[], seq }
PUT  /v1/vaults/{id}/records/{rid}        { version, hlc, sealed, isDeleted }    -> 200 { seq } | 412
POST /v1/vaults/{id}/records:batch        { records[] }  (≤100, one Table txn)   -> 200 { seq } | 412
GET  /v1/vaults/{id}/header               —                                      -> 200 { header }
```

### 1.3 The Functions app + local loop

`Cloud/api`: Node LTS (pin the version at first use, §4 toolchain table), TypeScript, the v4
programming model, one dependency — `@azure/data-tables`. `host.json`, `package.json`, `tsconfig.json`
with `strict: true`. `Cloud/README.md` documents the loop verbatim (mirror it into the top-level
README's Commands section, per `~/.claude/rules/readme.md`):

```bash
azurite --silent --location .azurite &     # local Table/Blob emulator
cd Cloud/api && npm ci && func start        # the API on http://localhost:7071
swa start http://localhost:4280 --api-location http://localhost:7071   # M6 ties the web bundle in here
```

**Checkpoint:** `func start` serves a health route against Azurite; `npm run build` (`tsc --noEmit`)
and ESLint are clean; `openapi.yaml` lints; `Cloud/api/local.settings.json` is git-ignored and the
secret scan flags a planted fake key in it. Commit: `Cloud: Functions skeleton + openapi.yaml + local
loop (architecture.md §10.3)`.

---

## Phase 2 — Storage model and the `seq` change feed

`Cloud/api/src/tableClient.ts` + `seq.ts`. One table (§10.2), resolves §14 decision 12.

```
PartitionKey = vaultId            (UUID string)
RowKey       = recordId           (UUID string; "$header" for the vault header; "$changes" for the counter)
properties   : version:Int64, hlc:string, sealed:Uint8Array, isDeleted:boolean, seq:Int64, deviceId:string
```

- `PartitionKey eq {vaultId}` returns the whole vault in one query. A sealed login record is far under
  the 64 KiB/property and 1 MiB/entity limits; attachments (§7.7) would go to Blob — not now.
- **`seq` is the change feed.** One `$changes` entity per partition holds the current counter. Every
  write: read `$changes` (with its ETag) → compute `next = seq + 1` → write the record entity with
  `seq = next` **and** update `$changes` to `next` with `If-Match: <etag>` → on `412`, retry the whole
  read-compute-write (bounded, e.g. 5 attempts, then `503`). A batch write takes one `seq` for the
  whole batch or one per record — decide in Phase 3, match `openapi.yaml`.
- **ETags are the §9.3 conflict trigger.** `PUT` with `If-Match` on the record entity's ETag → `412`
  on a stale write. The client, not the server, then reconciles.
- The server does a **framing check** on `sealed` on every write: length ≥ 40 and shape
  `nonce(24) ‖ ciphertext ‖ tag(16)` (§5.4). This is a client-bug tripwire, **not** a crypto check —
  the server cannot and must not validate the tag.

**Checkpoint:** unit tests against Azurite: three sequential writes get `seq` 1/2/3; a forced
concurrent bump (two writers, same starting ETag) — one wins, one retries, both land, `$changes` ends
at the right value, no `seq` is reused or skipped; a `sealed` of 39 bytes is rejected `400`.

---

## Phase 3 — The six endpoints

`Cloud/api/src/functions/`. Each is thin: validate against the DTO, authorize, touch the table, return.

| Endpoint | Notes |
|---|---|
| `POST /v1/vaults` | body `{ authSecret, header }`; `409` if `vaultId` (derived from the header's `vault_uuid`, §5.3) already exists; stores `auth_verifier` (Phase 4), the `$header` row, and `$changes = 0`. |
| `POST /v1/vaults/{id}/session` | two-step challenge-response (Phase 4). Returns a short-TTL JWT + the current `seq` so the client can immediately check its `seq` floor (§10.5). |
| `GET /v1/vaults/{id}/records?since={seq}` | `PartitionKey eq {id} and seq gt {since}`, `$changes`/`$header` filtered out of the record list (`$header` has its own endpoint); returns the max `seq` in the response so the client advances its cursor even when the page is empty. Paginate if a vault ever exceeds a Table query page (personal scale won't). |
| `PUT /v1/vaults/{id}/records/{rid}` | body `{ version, hlc, sealed, isDeleted }`; `If-Match` header carries the client's known ETag (or `*` for a create); framing check; bump `seq`; return `{ seq }` or `412`. |
| `POST /v1/vaults/{id}/records:batch` | ≤100 records, **one Table transaction** (`submitTransaction`) — all-or-nothing (§13.1 "batch atomicity"); one `seq` bump for the batch. |
| `GET /v1/vaults/{id}/header` | the `$header` blob, for a new device / the M6 web client to bootstrap: fetch → Argon2id → `pf_session_open`. |

- **The server never requires, accepts, or stores a key.** A request carrying anything key-shaped
  (e.g. a `dek` or `password` field) is a `400` — and there is a Phase 4 test asserting exactly that.
- JWT: signed with the app-setting key, short TTL (e.g. 15 min), `jose` or Node `crypto`. First
  `/session` success also registers the caller's `deviceId` (from `DeviceIdentity`, §Phase 6) so
  routine sync never re-touches the password path (§10.4 step 4).
- Rate-limit per vault (a simple in-Function token bucket keyed on `vaultId` in Table Storage, or SWA's
  built-in throttling) — enough to blunt credential stuffing, not a full WAF.

**Checkpoint:** all six endpoints answer against Azurite; a `passfort-cli` scratch call creates a
vault, opens a session, `PUT`s a record, `GET`s it back byte-identical. Commit per endpoint or per
logical group.

---

## Phase 4 — Contract tests + the `cloud` CI job

§13.1 sync-API row: *"contract tests generated from `openapi.yaml`, run against Azurite: `412` on
stale `If-Match`, `seq` monotonicity, auth rejection, oversized / misframed `sealed` rejection, batch
atomicity. The server must never require or accept a key."*

`Cloud/api/test/` — a test runner (`vitest` or `node:test`) that spins Azurite as a fixture and drives
the real Functions host. Cases, at minimum:

| Test | Asserts |
|---|---|
| `staleIfMatchIs412` | second `PUT` with the first's ETag → `412`, first write intact |
| `seqIsStrictlyMonotonic` | N concurrent writes → `seq` values are `1..N`, no gaps, no repeats |
| `sinceCursorExcludesSeen` | `GET ?since={max}` → empty list, same `seq` echoed back |
| `authRejectsBadResponse` | wrong challenge-response → `401`, no token |
| `authRejectsExpiredJWT` | a token past its TTL → `401` |
| `misframedSealedRejected` | `sealed` of 12 bytes → `400`; 40 bytes of zeros → accepted (framing only) |
| `batchIsAtomic` | a 100-record batch with one bad entity → whole batch rejected, `$changes` unmoved |
| `serverRejectsKeyShapedRequest` | a create body with an extra `dek` field → `400` (the "never accept a key" guarantee) |
| `createCollisionIs409` | same `vault_uuid` twice → `409` |

**CI (`ci.yml`, new `cloud` job, Linux, §13.2 table):**

```yaml
  cloud:
    runs-on: ubuntu-latest
    services:
      azurite:
        image: mcr.microsoft.com/azure-storage/azurite
        ports: ['10000:10000', '10002:10002']
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version-file: 'Cloud/api/.nvmrc', cache: 'npm', cache-dependency-path: 'Cloud/api/package-lock.json' }
      - working-directory: Cloud/api
        run: |
          npm ci
          npx tsc --noEmit
          npx eslint .
          npm test          # contract tests against the azurite service container
```

`package-lock.json` is committed and checked for drift the same way `Package.resolved` is (the `deps`
job pattern) — a Node dependency bump lands as its own reviewed commit (§3.2 A7).

**Checkpoint:** `npm test` green locally against Azurite and in CI; the `cloud` job is green on `main`;
`ci.yml`'s job list is `swift` / `native` / `deps` / `lint` / `secrets` / **`cloud`**. Update the
`ci.yml` header comment enumerating the suites.

---

## Phase 5 — `pf_blind_index` (+ the auth seam), the one crypto-core change

§6.2 line 392: *"`pf_blind_index` (M5)."* This is the **only** addition to `PFCrypto` in the milestone,
plus the two auth functions from Phase 0.2. No change to seal/open, the header, or the MAC.

### 5.1 C++ — `keyring/blind_index.{hpp,cpp}` + `boundary/`

`k_index` already exists in the hierarchy (`DEK -HKDF info='idx'-> k_index`, §5.1) — it is derived at
`pf_session_open` and lives in the session handle. Blind index of a field:

```
blind_index(field_bytes) = HMAC-SHA-256(k_index, normalize(field_bytes))[0..15]   // 16-byte tag
```

- **`normalize`** = Unicode NFKC + lowercase + trim. Defined in exactly one place (C++), so the Swift
  and (M6) WASM callers cannot disagree — same discipline as the AAD living in C++ (§5.4).
- **Truncate to 16 bytes.** Enough to make collisions negligible at personal scale; short enough that
  the column stays small. Record the length in a comment as a format-ish constant even though it never
  hits the header.
- **Determinism is the point and the cost.** Two records with the same normalized title produce the
  same blind index — that equality is visible to anyone with file/DB access. That is inherent to a
  blind index; it is why only *title* (not username or password) gets one for now. Add a §3.4 bullet:
  *"blind indexes (`idx_title`) leak title equality across records to an attacker with database
  access; usernames and passwords have no blind index."*

Seam surface:

```
pf_blind_index(Session*, field*, len)              -> BytesResult   // 16B
pf_session_auth_response(Session*, challenge*, len) -> BytesResult   // 32B  (Phase 0.2)
pf_session_auth_secret(Session*)                    -> BytesResult   // 32B  (registration only)
```

All `noexcept`, `try { … } catch (...) { return Status::Internal; }`, POD-only (§6.1).

### 5.2 Native + seam-fuzz tests (§13.1)

- `native-tests/` (Catch2): a **known-answer test** for `blind_index` — a fixed `k_index`, a fixed
  input, a checked-in expected 16-byte output, so a future refactor or the WASM build can't silently
  change the mapping. NFKC normalization cases (`"Café"` vs `"Café"` → same index; `"GitHub"` vs
  `"github"` → same). Same for `auth_response` against a fixed challenge.
- **Seam fuzz** (`PFCryptoBoundaryTests` + the same suite re-run against `pfcrypto.wasm` in M6): each
  new function with null pointer, zero length, huge length, closed session, double free → `BadInput`,
  never a trap.

### 5.3 Swift wrapper

`VaultSession.swift` gains `func blindIndex(_ field: Data) async throws -> Data`,
`func authResponse(challenge: Data) async throws -> Data`, `func authSecret() async throws -> Data` —
each one boundary hop, `PFStatus` → Swift error, exactly like `seal`/`open`.

**Checkpoint:** `swift test --filter PFCryptoBoundaryTests` and `ctest --test-dir native-tests/build`
green, including under ASan/UBSan; the blind-index KAT is checked in. Commit: `PFCrypto: pf_blind_index
+ auth response over the session handle (architecture.md §5.1, §10.4)`.

---

## Phase 6 — `PassFortVault/Sync/`: the native sync client

The first Swift consumer of the API. CLI-first — the GUI is Phase 12.

### 6.1 `SyncEnvelope.swift` (§7.5)

```swift
public struct SyncEnvelope: Sendable, Codable {
  public var recordID: UUID
  public var version: UInt64
  public var hlc: HLC                       // (wall_ms, counter, device_id) — SubModels.swift, exists
  public var sealed: Data                   // byte-identical to the SQLite BLOB — sync adds no crypto
  public var isDeleted: Bool
  public var seq: Int64                     // server-assigned; the cursor and the anti-rollback counter
  public var deviceID: UUID
}
```

`Codable` conformance matches `openapi.yaml` field-for-field (`sealed` as base64). Add
`VaultMeta.lastSyncedAt: Date?` and a `syncCursor` accessor (Phase 8 persists the cursor).

### 6.2 `SyncClient.swift` — the transport

`URLSession`-based, one method per §10.3 endpoint, returning typed results / throwing typed errors
(`.stale` for `412`, `.unauthorized` for `401`, `.rateLimited` for `429`). Holds the JWT from
`/session` and refreshes it on `401`. `deviceID` comes from `DeviceIdentity.current()` (M4) — this is
where the M4 "wired, not yet meaningful" device id **becomes meaningful**.

### 6.3 `PinnedTransport.swift` — SPKI pinning (§9.4)

`URLSessionDelegate.urlSession(_:didReceive:completionHandler:)`: extract the server cert's
SubjectPublicKeyInfo, SHA-256 it, compare against **two** pinned base64 values (current + next, so
certificate rotation doesn't brick the app). Pins are build config, not code. The web client cannot do
this (M6, §11.4) — one more reason the native app is the higher-trust client. Pinning is off against
`localhost`/Azurite (dev) — gate it on the endpoint host.

### 6.4 The app entitlement

`PassFort.entitlements` gains `com.apple.security.network.client` (the M4 `TODO(M5)`). Regenerate
`PassFort.entitlements.expected` and confirm `release.yml`'s entitlements diff (M4 Phase 8) still
passes with exactly that one key added.

### 6.5 Blind index on write

`VaultRepository` — on every `create` / `update`, compute `session.blindIndex(normalizedTitle)` and
write it to the `idx_title` column (already in the schema, `V1_initial.swift:26`, `BLOB`, currently
always `NULL`). Tombstones clear it. This is a local column for query-without-unlock and sync dedup; it
is **not** sent to the server (the server only sees `sealed`).

**Checkpoint:** `passfort-cli sync --endpoint http://localhost:7071 <vault>` against a local
`func`+Azurite host: push a 3-record vault, wipe the local DB, `sync` again → the 3 records come back
and `pf_open`. `idx_title` is populated for every non-deleted row. The app still builds unsigned in CI
with the new entitlement. Commit: `PassFortVault: Sync/ — SyncEnvelope, SyncClient, SPKI pinning
(architecture.md §9, §10.3)`.

---

## Phase 7 — `SyncEngine`: HLC reconciliation and conflict copies

`Sync/SyncEngine.swift` — the pull → reconcile → push loop. §9.3, §7.2 (`conflictOf`).

### 7.1 The loop

1. `GET /records?since={cursor}` → remote envelopes.
2. **Assert `response.seq ≥ cursor`** (§10.5) — if not, the server rolled the vault back: abort, do
   not touch local state, surface `SyncError.serverRollback`.
3. For each remote record, in **one write transaction** (§8.2):
   - not present locally → insert.
   - present, same `version` → no-op.
   - present, remote `hlc > local.hlc` → the remote wins: overwrite local, and if the local copy had
     **unsynced local edits** (a local `version` the server hasn't seen), preserve them as a
     **conflict copy** — a *new* record, new UUID, `payload.conflictOf = <original UUID>`, the losing
     payload, its own HLC.
   - present, local `hlc > remote.hlc` → local wins: leave local, mark it for push.
   - `HLC.receive(remote.hlc)` advances the local logical clock each time (add this method to `HLC`:
     `counter = (max(localWall, remoteWall, nowWall) == localWall) ? counter+1 : 0`, wall updated).
4. Recompute the manifest MAC over the new row set (`VaultManifest`, unchanged) inside the same
   transaction; commit row-set + MAC + cursor together or not at all.
5. Push every locally-changed record via `PUT` (or `:batch` for >1); on `412`, re-pull that record,
   re-run the rule, push the conflict copy.

### 7.2 The server never merges

§9.3: the server only *detects* the race (the `412`). All HLC logic is client-side and identical
across the native app and (M6) the web client — which is why it lives in `PassFortVault`, shared by
both, not in a view model (§14 decision 9).

**Checkpoint:** two `passfort-cli` instances, two DB files, one Azurite host, distinct
`--device-id`s:

- A edits record X, syncs; B syncs → B sees A's edit.
- A and B both edit X offline; both sync → last HLC wins, the loser is a `conflictOf` copy visible in
  `passfort-cli list` on **both** after they converge.
- `AccountHistoryTests`-style: a conflict copy has its own version timeline and doesn't corrupt the
  original's.

Tests in `PassFortVaultTests` drive `SyncEngine` against a **fake `SyncClient`** (an in-memory table +
`seq` counter) so they run headless in CI — no Azurite in the `swift` job.

---

## Phase 8 — Anti-rollback against a real server; `compact`

§10.5. The `seq` floor is the same high-water mark M4 put in the Keychain — `seq` *is* the
`vault_version` counter once sync is on (§9.1).

### 8.1 `SyncCursor.swift`

The highest `seq` ever seen, persisted through the **existing `HighWaterMarkStore`** (M4 Phase 3) —
`KeychainHighWaterMark` in the app, `FileHighWaterMark` for the CLI. No new storage mechanism. On every
sync:

- `seq` returned by `/session` and `/records` must be `≥ cachedMax`, or `SyncError.serverRollback`
  (the server dropped writes or replayed an old snapshot).
- After ingesting, rebuild local state and **recompute the manifest MAC through the crypto core**,
  compare against the last-known-good MAC — catches the server dropping or swapping individual records
  even when `seq` looks fine (§10.5).
- Only on both checks passing: advance the cached `seq`.

### 8.2 A simulated malicious server (§13.1 anti-rollback row)

`PassFortVaultTests`: the fake `SyncClient` gains adversarial modes — *drops a record from the
`/records` response*, *replays an old `seq`*, *returns a `sealed` blob with a flipped bit*. Assert the
native client catches each: `serverRollback`, `serverRollback`, `AuthFailed` from `pf_open`
respectively — never silent acceptance.

### 8.3 `compact` un-stubbed

`VaultRepository.compact` (currently "M2 has no sync, so 'acked by every device' is just 'deleted'",
`VaultRepository.swift:238`) now purges a tombstone only when its `seq` is `≤` the minimum cursor
across known devices — for the single-user two-device case, `≤` the local cursor after a successful
round-trip with every registered device. Conservative: if unsure, don't purge.

**Checkpoint:** the simulated-malicious-server tests pass; `compact` on a synced vault removes only
fully-propagated tombstones; `passfort-cli verify` still passes post-sync. The
`restore-an-old-DB-file` M2 test is unaffected (that path is `vault_version` from the header, which
still works offline).

---

## Phase 9 — Key rotation

§9.5. Master-password rotation already exists (`pf_session_rewrap` / `Vault.recover`, M2). M5 adds
**DEK rotation**, CLI-driven.

- `passfort-cli rotate-dek <vault>`: generate a new DEK, keep **both** generations live in the session,
  re-`pf_seal` every record under the new `k_record`, rewrite the header slot(s) to wrap the new DEK,
  bump every record's `version`, re-MAC, and push the lot via `:batch`. One transaction per batch;
  resumable if interrupted (records carry which DEK generation sealed them until the migration
  completes).
- This is the first operation that rewrites the whole vault — it is deliberately CLI-only and not in
  the GUI for M5. It is also a good stress test of `:batch` atomicity and the `seq` cursor under a
  large push.

**Checkpoint:** `rotate-dek` on a 100-record vault → every record re-seals, `verify` passes, a second
device `sync`s and opens every record under the new DEK; killing `rotate-dek` mid-run and re-running
completes cleanly.

---

## Phase 10 — Bicep infra + the deploy targets

The cloud enters here — behind a `$5` budget alert. §10.1, §10.6, §14 decision 14.

### 10.1 `Cloud/infra/main.bicep`

Provisions: a **Static Web App** (Free tier — hosts the M6 web bundle and the managed Functions API,
terminates TLS), a **Storage account** (Standard LRS, Hot — the one table), and a **budget alert at
$5** on the resource group. JWT signing key and `serverPepper` are written to the SWA/Function app
settings **from GitHub secrets by the deploy**, never committed, never via `local.settings.json`
(§14 last bullet). `main.parameters.json` for the non-secret knobs.

### 10.2 `release.yml` (extends the M4 file)

Tag-triggered (`v*.*.*`), never a push (§13.3). Two new M5 jobs, **OIDC federated credentials** — the
job trades its GitHub identity token for a short-lived Azure token, no long-lived cloud secret in the
repo (§14):

| Job | Does | Gate |
|---|---|---|
| `azure-infra` | `az deployment group create` from `main.bicep` — idempotent; the budget alert is in the template | M5 |
| `sync-api-web` | the Static Web Apps deploy action publishes `Cloud/api` (+ the built `Web/` bundle in M6); records the deployed bundle hash on the Release | M5 / M6 |

### 10.3 Teardown discipline (the M5 "done when")

§10.6 / §14: `az group delete` must leave **no orphan resources**, and *teardown-then-redeploy from the
same tag* must reproduce the environment with no manual step. Do this at least once for real before
calling the milestone done. Document both directions in `Cloud/README.md`.

**Checkpoint:** a real deploy from a throwaway tag stands up the RG; `passfort-cli sync` against the
real `*.azurestaticapps.net` endpoint (SPKI-pinned) round-trips a vault; `az group delete` removes
everything; a redeploy from the same tag reproduces it; the Azure cost page shows ~$0 and the budget
alert exists.

---

## Phase 11 — GUI sync integration

Now that the engine is CLI-proven, wire it into the app. §12 "conflicts surface in the UI".

- **`VaultService` / `AppModel`:** a `SyncState` (`.idle` / `.syncing` / `.error(SyncError)` /
  `.offline`), a `sync()` method, and automatic triggers — on unlock, on app foreground, on a write
  (debounced), and a periodic timer while unlocked. Sync only while `state == .unlocked` (it needs the
  session for `authResponse` and the MAC recompute).
- **Settings:** enable/disable sync, set the endpoint, show the device id and registered devices,
  "sync now", last-synced time. Enabling sync the first time = register the vault
  (`POST /v1/vaults`) — requires a live unlocked session.
- **Conflict surfacing:** a record with `payload.conflictOf != nil` renders with a badge in the list
  and a banner in the detail view ("Conflicting copy — created from a sync conflict on <date>"), with
  "keep this / keep the other / merge manually" actions. `AccountSummary.isConflict` already exists
  (`Account.swift:46`).
- **Never block the UI on the network.** Sync is a background `Task`; a failure is a dismissible
  status, not a modal. Offline is normal and silent.

**Checkpoint:** two Macs (or one Mac + `passfort-cli`), same vault, same real endpoint: an edit on one
appears on the other within the periodic interval; an offline edit on both surfaces a conflict badge on
both after reconnect; airplane mode shows `.offline`, not an error; `AppModelTests` gains
`syncErrorDoesNotDropTheSession` and `conflictCopyAppearsInSummaries` against the fake client.

---

## Phase 12 — Tests, CI, and the doc sweep

### Coverage summary (§13.1)

| Where | Test | Asserts |
|---|---|---|
| `native-tests/` | `blindIndexKAT`, `authResponseKAT`, NFKC cases | the field→index and challenge→response maps are pinned |
| `PFCryptoBoundaryTests` | `pf_blind_index` / `pf_session_auth_*` fuzz | null / zero / huge / closed / double-free → `BadInput` |
| `Cloud/api/test` | the Phase 4 contract suite | `412`, `seq` monotonicity, auth, framing, batch atomicity, never-accept-a-key, `409` |
| `PassFortVaultTests` | `SyncEngine` against the fake client | HLC last-writer-wins, conflict copies, `HLC.receive` advances |
| `PassFortVaultTests` | simulated malicious server | dropped record / replayed `seq` / flipped bit → `serverRollback` / `serverRollback` / `AuthFailed` |
| `PassFortVaultTests` | `compact` gated on the cursor | only fully-propagated tombstones purged |
| `AppModelTests` | `syncErrorDoesNotDropTheSession`, `conflictCopyAppearsInSummaries` | sync failure is non-fatal; conflicts reach the list |
| manual / real endpoint | two-device convergence; teardown-redeploy | the §12 M5 "done when" |

CI: the `cloud` job (Phase 4) rides `ci.yml`; the `swift` job's package + app suites pick up the new
`PassFortVaultTests` / `AppModelTests` cases with no new job; `release.yml` gets the two deploy jobs
(Phase 10). Keep the `ci.yml` comment enumerating suites honest.

### Doc sweep (part of the milestone, not a follow-up)

- **`architecture.md`:** §14 decisions 8, 12, 13, 14 → resolved (Phase 0.3); §3.4 gains the
  blind-index-equality bullet (Phase 5) and, if ADR-0009 happened, the auth-breach bullet (Phase 0.2);
  the rev line moves.
- **`docs/adr/`:** `0009-sync-auth-handshake.md` if Phase 0.2 deviated; update `docs/adr/README.md`.
- **`docs/runbooks/README.md`:** M5 row → done; add a retrospective link if you write one.
- **`README.md` (top level):** Architecture section gains a sync paragraph + the ADR-0005/0009 links;
  Project structure gains `Cloud/`; Getting started gains the Node/Azure toolchain (pin versions);
  Commands/Testing gains the `Cloud/` local loop and `npm test`; add the CI status badge (it has been
  earned since M1, §13.3).
- **`CLAUDE.md`:** the "Project status" line moves to "M0–M5 done, M6 (web client) next".

---

## Where this leaves you

- **The vault is multi-device.** Two machines converge through a custom Azure backend that holds only
  ciphertext, assigns `seq`, and merges nothing. Conflicts become visible conflict copies, never
  silent data loss.
- **A new project you own end to end:** `Cloud/` — TypeScript Functions, Table Storage, an OpenAPI
  contract, `auth_secret` challenge-response auth, Bicep-provisioned infra with a budget alert, an
  OIDC-federated deploy, and teardown that leaves no orphans. §1.1 goal 6, delivered.
- **One crypto-core change, contained:** `pf_blind_index` (+ the auth seam). No vault-format change, no
  change to seal/open or the manifest MAC. The format stayed language-agnostic, which is what makes M6
  possible.
- **The `seq` floor reuses M4's Keychain `HighWaterMarkStore`** — `seq` *is* `vault_version` once sync
  is on. Anti-rollback now covers a hostile server (dropped writes, replayed snapshots), verified with
  a simulated-malicious-server test suite.
- **Deferred, tracked:** the web client and everything WASM (M6 — it calls the API M5 built);
  attachments (Blob Storage, a later ADR); OPAQUE/SRP auth (§14.8); strict multi-writer anti-rollback
  under genuine concurrency (§10.5 caveat); SPKI pin-rotation drills (M7).
- **Next:** M6 — the web client. `PFCrypto` → `pfcrypto.wasm` via Emscripten (`scripts/build_wasm.sh`,
  ADR-0006), `Web/src/crypto/session.ts` mirroring `VaultSession.swift`, a Lit UI, the IndexedDB
  cache, and the same `seq` cursor + HLC rules this milestone built — against the same API. Write
  `m6-web.md` once M5 has actually shipped and you know what the contract really looks like.
