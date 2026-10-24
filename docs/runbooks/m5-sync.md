# M5 — Sync (Azure)

**Status:** Detailed design, written ahead of the normal cadence (first sketch 2026-09-04; reworked to
low-level detail 2026-10-21, on request). The design decisions are **ratified** — ADR-0009 and
`architecture.md` rev 12 (2026-10-21). The Azure spike (Phase 0.1) is **half run**: the local half
passed on 2026-10-21 (A.3 holds on Azurite, real sealed blobs round-trip), and the deploy half hasn't
run yet. Part A is the
design every phase builds against; the spike can still overturn it, and then the ADR gets amended and
this runbook rewritten. Treat every "Checkpoint", command and number below as provisional until the
spike has run.

**Prerequisite:** M3 done (the SwiftUI app does full CRUD; `AppModel` is the lock-state spine). M4 was
scaled back on 2026-10-21 — **no Keychain, no Touch ID, no notarization** — and this runbook no longer
depends on any of it: the rollback mark stays the `<db>.hw` sidecar, the device id becomes a per-install
file (Phase 6), and the app stays "Sign to Run Locally". The one M4 leftover M5 needs is outgoing
network access for the sandboxed app (Phase 13.1).

**Spec:** `architecture.md` §9 (sync shape, conflicts, transport), §10 (the Azure backend), §5.1 (key
hierarchy — changed by ADR-0009), §5.5 + §10.5 (anti-rollback), §7.2 (`conflictOf`), §7.5
(`SyncEnvelope`), §13.1–§13.4 (tests, the `cloud` CI job, deploy targets). ADR-0005 is the backend
decision; ADR-0006 / §11 are the web client (M6); `m7-ios.md` is the second consumer of this API.

---

## What M5 delivers

`architecture.md` §12 M5 row: *"`Cloud/infra` Bicep → Storage + Functions; the §10.3 API; native HTTP
sync client; HLC conflict copies; blind indexes; key rotation. Done when: two machines converge through
Azure; conflicts surface in the UI; `az group delete` leaves no orphans."* (Rev 12 moved blind indexes
and DEK rotation out — see the changes table and open decision 20.)

**Sync in one paragraph.** Every device keeps its own complete SQLite vault, exactly as today. The
server is a dumb, untrusted mailbox: one Azure Table partition per vault, holding each record's
`sealed` blob byte-for-byte plus a plaintext envelope (`version`, `hlc`, `isDeleted`), and a per-vault
counter `seq` that it bumps on every write. A device syncs by (1) authenticating with a 32-byte **auth
key** that only a device holding the DEK can derive, (2) **pulling** every record with `seq` greater
than its cursor, verifying each one decrypts, and merging them into its local DB in one transaction,
(3) **pushing** every local row the server hasn't confirmed, as one atomic batch the server accepts
only if each record's `baseVersion` still matches. A concurrent edit makes the push fail with `409`;
the device pulls, resolves by **hybrid logical clock** (last writer wins), keeps the loser as a visible
**conflict copy**, and pushes again. The server never decrypts, merges or chooses anything.

### Changes from the rev-11 architecture — ratified by ADR-0009 + rev 12 (2026-10-21)

These started as this runbook's proposals and are now the architecture (§5.1, §9, §10, §12, §14). The
table stays as the record of what changed and why. Each makes M5 smaller or safer.

| # | `architecture.md` up to rev 11 | Now (rev 12) | Why |
|---|---|---|---|
| D1 | `auth_secret` = HKDF(Argon2 output, `'auth'`) — password-derived; server verifier is an offline-cracking target at Argon2 cost (§5.1, §10.4, §14.8) | **`k_auth` = HKDF(DEK, `'sync-auth'`)** — DEK-derived. Server stores `SHA-256(k_auth)`. | A server breach yields a hash of a 256-bit random value: **nothing to crack**, so the §10.4 limitation disappears without OPAQUE. Survives master-password changes and recovery (the DEK doesn't change), so no "re-register the verifier" flow. A new device can only authenticate after unwrapping the DEK, so a forged header can't extract anything. |
| D2 | `POST /session` is a challenge-response (§10.4) | Client sends `k_auth` once per session over pinned TLS, gets a 15-min JWT | A challenge-response the server can verify needs the server to hold the secret (the old sketch's unresolved spot). With a high-entropy key, sending it under TLS and storing only its hash is simpler and strictly stronger at rest. |
| D3 | Device token registered at first login (§10.4 step 4) | No refresh/device tokens. A device row records name + cursor; auth is always `k_auth` → JWT | Sync only runs while unlocked (it needs the session for `pf_open` anyway), and while unlocked the device can always re-derive `k_auth`. No long-lived bearer secret on disk. |
| D4 | Six endpoints incl. single-record `PUT` with `If-Match` (§10.3) | Nine vault endpoints plus health; **one push endpoint** (batch, 1–99 records) with per-record `baseVersion`; header `GET`/`PUT`; devices; vault delete; health | One write path to test. `baseVersion` in the body replaces client-held ETags; the server still uses ETags internally. |
| D5 | Blind indexes in M5 (§12) | **Deferred** — no M5 feature reads `idx_title` | Search is the in-memory index (§8.3); the server never sees `idx_*`. Building it now adds a seam function, a KAT and a §3.4 leak for no user-visible gain. |
| D6 | DEK rotation in M5 (§9.5, §12) | **Deferred** to a later milestone with its own ADR | With sync, a rotated DEK means devices receiving records sealed under a key they don't have yet → `AuthFailed` storms. Doing it right needs a key-generation id in the header/AAD — a **format change** (ADR + re-seal migration). Master-password changes and recovery-key rotation (DEK unchanged) *are* in M5 (Phase 9). |
| D7 | `seq` "is" `vault_version` once sync is on (old sketch) | They stay **separate**: `vault_version` is the local per-commit counter guarded by `<db>.hw`; the server `seq` is a remote cursor stored in `vault_meta` | Different counters on different machines. Every ingest is a local commit, so the cursor inherits the local rollback protection for free. |
| D8 | `seq` floor in the Keychain (§10.5, old sketch) | `sync_cursor` in `vault_meta` | The Keychain was dropped (§14.18); see D7. |

### What gets built

```
Cloud/                                    NEW — the Azure backend; no vault cryptography (§10)
├── openapi.yaml                          Phase 1   the contract; source of truth for Swift, TS and (M6) web DTOs
├── README.md                             Phase 1   local loop, deploy, teardown — verbatim commands
├── site/index.html                       Phase 12  placeholder static content (SWA requires an app; M6 replaces it)
├── staticwebapp.config.json              Phase 12  routes, headers, apiRuntime pin
├── infra/
│   ├── main.bicep                        Phase 12  Storage + table + Static Web App + app settings + $5 budget
│   ├── main.parameters.json              Phase 12  non-secret knobs (location, names, budget email)
│   └── bootstrap-oidc.sh                 Phase 12  one-time: Entra app + federated credential + role assignment
└── api/                                  Phases 1–4  TypeScript, Azure Functions v4 programming model
    ├── src/handlers/                     Phase 3   health · vault (create, session, delete) · header · changes · devices
    ├── src/routes.ts                     Phase 3   the A.3 route table + `serve` (logging, 500s, 413) -- shared by both hosts
    ├── src/functions/api.ts              Phase 3   the deployed host: registers every route with `app.http`, over TableStore
    ├── src/lib/                          store.ts · table.ts · memory-store.ts · seq.ts · purge.ts · auth.ts · jwt.ts
    │                                     validate.ts · errors.ts · log.ts · config.ts · http.ts
    ├── src/dev-server.ts                 Phase 3   `npm run dev`: the handlers on node:http + the memory store
    ├── src/dto.ts                        generated from openapi.yaml (openapi-typescript), never hand-edited
    ├── test/                             node:test; storage suites run in memory and, in CI, on Azurite
    ├── host.json · package.json · package-lock.json · tsconfig.json · .nvmrc
    └── local.settings.json               dev only — git-ignored (Phase 1.1)

Packages/PassFortKit/Sources/PFCrypto/
├── keyring/hkdf.{hpp,cpp}                Phase 5   + k_auth = HKDF-Expand(DEK, "sync-auth"); drop the Argon2-side auth_secret
└── boundary/…                            Phase 5   pf_session_auth_key(session, out[32])

Packages/PassFortKit/Sources/PassFortCrypto/
└── VaultSession.swift                    Phase 5   + authKey() -> Data

Packages/PassFortKit/Sources/PassFortVault/
├── Migrations/V2_sync.swift              Phase 6   full HLC columns + sync bookkeeping columns
├── Model/SealedRecord.swift              Phase 6   full HLC round-trip; syncedVersion / syncedSeq
├── HLCClock.swift                        Phase 6   monotonic tick() / receive(_:)
├── DeviceIdentity.swift                  Phase 6   per-install UUID + name, stored outside the vault file
├── VaultMeta.swift                       Phase 6   + sync_config, sync_cursor, sync_header_version, header_dirty, pending_header
├── VaultRepository.swift                 Phases 6, 8, 10  dirty tracking, applyRemote(_:), markPushed(_:), compact gated on sync
└── Sync/
    ├── SyncDTO.swift                     Phase 7   Codable mirrors of openapi.yaml
    ├── SyncAPI.swift                     Phase 7   protocol: one method per endpoint
    ├── HTTPSyncAPI.swift                 Phase 7   URLSession implementation; JWT cache; error mapping
    ├── PinnedTransport.swift             Phase 7   URLSessionDelegate — SPKI pin set (§9.4)
    ├── Reconciler.swift                  Phase 8   pure function: (local row, remote record) -> Decision
    ├── SyncEngine.swift                  Phase 8   actor: session → pull → reconcile → push → header
    ├── SyncError.swift                   Phase 8   the error taxonomy (Part A.11)
    └── (FakeSyncServer.swift)            Phase 8   in-memory server for tests; adversarial modes (Phase 10) — lives in Tests/PassFortVaultTests/

Packages/PassFortKit/Sources/passfort-cli/
└── SyncCommands.swift                    Phase 11  sync enable · join · now · status · devices · disable

PassFort/                                 Phase 13  (the macOS app)
├── Model/{AppModel,VaultService}.swift   SyncController wiring, device identity, join flow, pending-header unlock
├── Model/SyncController.swift            @MainActor @Observable — status, triggers, actions
├── Features/Sync/                        SyncSettingsSection · DevicesList · AddDeviceSheet · SyncStatusFooter
│                                         SyncProblemSheet
├── Features/Join/JoinVaultView.swift     first-run "Join a synced vault"
└── Features/Conflicts/                   ConflictBanner · ConflictCompareView

.github/workflows/
├── ci.yml                                Phase 2   NEW `cloud` job (Linux): npm ci · tsc · DTO check · tests (memory + Azurite container)
└── deploy.yml                            Phase 12  NEW, tag-triggered: OIDC login → Bicep → SWA deploy
```

### What is **not** in M5 (do not build it here)

| Deferred to | What |
|---|---|
| **M6** | the web client — `Web/`, `pfcrypto.wasm`, the real SWA static bundle. M5 deploys a placeholder page so SWA has something to serve. |
| **M7** | the iPhone client (`m7-ios.md`). It joins through this API unchanged. |
| **M8** | hardening: the nightly fuzz job, SPKI pin-rotation drills, threat-model review of the backend. |
| **a later ADR (format change)** | DEK rotation (D6), attachments (§7.7 — Blob Storage), blind indexes (D5). |
| **not at all** | any server-side decrypt or merge; any endpoint that accepts a vault key, password or DEK; background sync while locked; push notifications (paid Apple program). |

### The M5 rules

- **`Cloud/` contains no vault cryptography.** Nothing there seals, opens, wraps or derives a vault key.
  Node's built-in `crypto` for `SHA-256` of the auth key, `timingSafeEqual` and JWT HMAC is auth
  plumbing and is allowed; importing a crypto *library* into `Cloud/api` is a design error.
- **The sync layer adds no crypto of its own** (§9.1). `sealed` crosses the wire base64-encoded and
  lands in SQLite byte-identical to what `pf_seal` produced on the writing device.
- **Every ingest is one local commit** — rows, conflict copies, manifest re-MAC, `vault_version` bump
  and the new `sync_cursor` together, or nothing (§8.2). Sync bookkeeping columns that are outside the
  MAC (`synced_version`, `synced_seq`) may be written in a plain transaction; anything the MAC covers
  (`uuid`, `version`, `sealed`) only through `commit`.
- **Sync runs only while unlocked.** It needs the session for `k_auth`, for `pf_open` on every pulled
  record and for the MAC. Locking cancels an in-flight sync; transactions make that safe.
- **Losing data is worse than showing two.** Every ambiguous case resolves toward keeping both copies
  or re-uploading — never toward deleting on the server's word (Part A.9).
- **CLI first.** Two `passfort-cli` instances converge through the API (Phase 11) before the GUI
  (Phase 13) is wired. The GUI is a front end onto an already-tested engine.
- **Nothing to install locally beyond Node and npm, and a minimal npm tree** (2026-10-22). No
  Azurite, `func`, `swa` or gitleaks on the dev Mac: storage logic is tested against an in-memory
  `VaultStore`; the Table-backed run, the secret scan and anything Azure-shaped happen in CI or in
  the dev resource group, which sits behind the $5 budget. `Cloud/api` keeps two runtime
  dependencies (`@azure/functions`, `@azure/data-tables`) and three dev ones (`typescript`,
  `@types/node`, `openapi-typescript`); adding one is its own reviewed commit.

> **Path note:** `architecture.md` §4 draws the CLI at `Tools/passfort-cli/`; it lives at
> `Packages/PassFortKit/Sources/passfort-cli/` (M1 deviation, already logged). `Sync/` is
> `Packages/PassFortKit/Sources/PassFortVault/Sync/`.

---

## Part A — The design

Reference material for every phase. Phases say *when* to build each piece; this part says *what* it is.

### A.1 Azure resources

One resource group per environment: **`rg-passfort-dev`** (Phases 12–13 development, torn down freely)
and **`rg-passfort-prod`** (the real vault). Region: the nearest region where Static Web Apps is
available (e.g. `westeurope`); Storage goes in the same region.

| Resource (Bicep symbol) | Type / SKU | Purpose | Cost at personal scale |
|---|---|---|---|
| `storage` | `Microsoft.Storage/storageAccounts`, StorageV2, **Standard_LRS**, Hot | holds the one table | storage: a few MB → well under $0.01/mo; transactions: fractions of a cent per 10k — confirm on the pricing page in Phase 0 |
| `storage::tableService::vaults` | `…/tableServices/tables`, name `vaults` | every vault, device and record entity (A.2) | included above |
| `site` | `Microsoft.Web/staticSites`, **Free** | serves the placeholder (M6: the web app) **and hosts the API as SWA managed Functions**; terminates TLS with a managed cert | $0 |
| `site::appsettings` | `Microsoft.Web/staticSites/config` `appsettings` | the API's settings (table below) | $0 |
| `budget` | `Microsoft.Consumption/budgets`, RG scope | $5/month, email at 50 / 80 / 100 % | $0 |
| *(optional)* `insights` + `workspace` | App Insights + Log Analytics, daily cap 0.1 GB | Function logs. **Off by default** (`enableInsights=false`) — a logging pipeline is also a place a secret could leak (§13.1) | ~$0 under the cap |

Storage account settings: `minimumTlsVersion: 'TLS1_2'`, `supportsHttpsTrafficOnly: true`,
`allowBlobPublicAccess: false`. `allowSharedKeyAccess` stays **true** and public network access stays
on: SWA managed Functions have **no managed identity and no VNet integration**, so the API reaches
Table Storage with a connection string. That connection string is computed inside Bicep
(`storage.listKeys()`) and written straight into the SWA app settings — it never touches GitHub or a
file.

**Deliberately not provisioned:** a standalone Function App / App Service plan (SWA hosts the API),
Cosmos DB, Key Vault (SWA app settings can't reference it from managed Functions; the two secrets live
in app settings, encrypted at rest by the platform), Front Door / CDN, a custom domain (optional later;
it would change the pinned chain — A.4), anything always-on. Any of these is what would turn "rounds to
$0" into a bill (§10.1).

**SWA managed Functions constraints** (verify current values in Phase 0): HTTP triggers only (fine — no
timers needed; purging is opportunistic, A.10); a short per-request timeout; the Node runtime is chosen
by `platform.apiRuntime` in `staticwebapp.config.json` from the versions SWA supports; the API is
mounted under `/api`. The local dev server (`npm run dev`, Phase 3) serves under `/api` too, so local
and deployed URLs have the same shape.

**App settings** (SWA config in the cloud, `local.settings.json` locally):

| Name | Purpose | Source in the cloud | Local value |
|---|---|---|---|
| `TABLES_CONNECTION_STRING` | Table Storage access | Bicep `listKeys()` | unused by `npm run dev` (memory store); a scratch account's string to point it at real Table Storage |
| `PASSFORT_TABLE` | table name | Bicep (`vaults`) | `vaults` |
| `PASSFORT_JWT_KEY` | HS256 signing key for session tokens, ≥ 32 random bytes, base64 | GitHub secret → `@secure()` Bicep param | any random dev value |
| `PASSFORT_ENROLL_SECRET` | gate on creating a vault (A.4) | GitHub secret → `@secure()` Bicep param | any dev value |
| `PASSFORT_JWT_TTL_SECONDS` | token lifetime | Bicep (`900`) | `900` |

**Identity for deploys** (one-time, outside Bicep, `Cloud/infra/bootstrap-oidc.sh`): an Entra app
registration with a **federated credential** for `repo:<owner>/PassFortApp:ref:refs/tags/*` (or a
GitHub environment), and a **Contributor** role assignment scoped to the resource group only. No client
secret exists anywhere. The app registration lives outside the RG — the teardown section says to
delete it explicitly if the project is retired.

### A.2 Server data model — one table, one partition per vault

Table `vaults`. `PartitionKey = vaultId` (lower-case UUID string). Everything a vault owns is in its
partition, so **one Table transaction (≤ 100 operations, ≤ 4 MiB) can update records and the counter
atomically**.

| RowKey | Entity | Properties |
|---|---|---|
| `meta` | the vault's control row | `seq: Int64` (last assigned), `headerVersion: Int64`, `header: Binary` (§5.3 blob), `authKeyHash: Binary(32)` (SHA-256 of `k_auth`), `purgedThroughSeq: Int64`, `failedAuthCount: Int32`, `lockedUntil: DateTime?`, `createdAt: DateTime` |
| `rec_<recordId>` | one sealed record | `version: Int64`, `hlcWall: Int64`, `hlcCounter: Int32`, `hlcDevice: String`, `sealed: Binary`, `isDeleted: Boolean`, `seq: Int64` (seq of this version), `writer: String` (deviceId) |
| `dev_<deviceId>` | one registered device | `name: String`, `platform: String` (`macos` / `ios` / `cli` / `web`), `lastSeq: Int64` (highest seq it has confirmed pulling), `lastSeenAt: DateTime` |

- **Limits that shape the API:** a Binary property is ≤ 64 KiB, so `sealed` is capped at **65,320
  bytes** (`40 + 256·255`, the largest padded size that fits — §5.4 + the 256-byte bucket). A sealed
  login record is ~0.5–4 KB; a record that outgrows the cap is a client error (`413`), and chunking is a
  later problem. A transaction is ≤ 100 ops ≤ 4 MiB, so a push carries **≤ 99 records** (+ the `meta`
  update) and the client also keeps a batch under **3 MiB**.
- **Framing check** on every `sealed`: length ≥ 296 and `(length − 40) % 256 == 0` (24-byte nonce ‖
  256·k ciphertext ‖ 16-byte tag). A client-bug tripwire, not a crypto check.
- **Queries:** "changes since s" is `PartitionKey eq '<vaultId>' and seq gt s` plus a RowKey range
  covering the `rec_` prefix — a partition scan filtered server-side; personal scale (≤ thousands of
  rows) makes that a single page. The Function sorts by `seq` and returns the lowest `limit` (A.3).

### A.3 The API

Base: `https://<site>.azurestaticapps.net/api/v1` (deployed), `http://localhost:7071/api/v1` (local).
JSON bodies; binary fields base64 (standard alphabet); UUIDs lower-case; times RFC 3339. Every
authenticated call carries `Authorization: Bearer <jwt>`; the JWT's `sub` is the vaultId and `dev` the
deviceId, and a token for vault A is rejected on vault B's routes.

| # | Method + path | Auth | Request | Success | Errors |
|---|---|---|---|---|---|
| 1 | `GET /health` | none | — | `200 { ok, apiVersion }` — touches no storage | — |
| 2 | `POST /vaults` | `X-PassFort-Enroll` | `{ vaultId, header, authKey, device: { id, name, platform } }` | `201 { seq: 0, headerVersion: 1 }` | `403` bad enroll secret · `409` vault exists · `400` |
| 3 | `POST /vaults/{vaultId}/session` | body | `{ authKey, device: { id, name, platform } }` | `200 { token, expiresAt, seq, headerVersion, purgedThroughSeq }` | `401` (bad key *or* unknown vault — same body, no existence oracle) · `429` + `Retry-After` |
| 4 | `GET /vaults/{vaultId}/header` | none | — | `200 { header, headerVersion }` | `404` · `429` |
| 5 | `PUT /vaults/{vaultId}/header` | JWT | `{ header, baseHeaderVersion }` | `200 { headerVersion }` | `409 { headerVersion }` stale base |
| 6 | `GET /vaults/{vaultId}/changes?since={seq}&limit={n≤500}` | JWT | — | `200 { records: [Record], seq, hasMore, headerVersion, purgedThroughSeq }` | `410` — `since > 0` and `since < purgedThroughSeq`: full resync needed |
| 7 | `POST /vaults/{vaultId}/changes` | JWT | `{ records: [Push] }` (1–99, ≤ 3 MiB) | `200 { applied: [{ id, version, seq }], seq }` | `409 { conflicts: [{ id, serverVersion }] }` — **nothing written** · `400` framing / version · `413` |
| 8 | `GET /vaults/{vaultId}/devices` | JWT | — | `200 { devices: [{ id, name, platform, lastSeq, lastSeenAt }] }` | — |
| 9 | `DELETE /vaults/{vaultId}/devices/{deviceId}` | JWT | — | `204` | `404` |
| 10 | `DELETE /vaults/{vaultId}` | JWT | — | `204` — deletes the whole partition | — |

(Nine vault endpoints plus health.)

```jsonc
// Record (pull)                              // Push (one element of a push batch)
{ "id": "…uuid…",                             { "id": "…uuid…",
  "version": 7,                                 "baseVersion": 6,      // 0 = "must not exist yet"
  "hlc": { "wallMillis": 1792540800123,         "version": 7,          // must be > baseVersion
           "counter": 0,                        "hlc": { … },
           "deviceId": "…uuid…" },              "sealed": "base64…",
  "sealed": "base64…",                          "isDeleted": false }
  "isDeleted": false,
  "seq": 41,
  "writer": "…deviceId…" }
```

**Server semantics, exactly:**

- **`changes` pull** returns records with `seq > since`, ascending by `seq`, at most `limit`;
  `hasMore` tells the client to call again with `since = last seq returned`. The response's `seq` is
  `meta.seq` (the server's high-water mark), returned even when `records` is empty. Side effect: the
  caller's `dev_<id>.lastSeq = since` and `lastSeenAt = now` (pulling *from* `since` proves the device
  holds everything up to it).
- **`changes` push** — the only write path for records:

  ```
  repeat up to 5 times:
    meta    ← point-read "meta"                                   (keep its ETag)
    current ← point-read "rec_<id>" for each pushed id            (keep their ETags)
    conflicts ← pushed records where (current?.version ?? 0) ≠ baseVersion
    if conflicts: return 409 { conflicts }                        — nothing written
    s ← meta.seq
    ops ← for each pushed record r (in request order):
            s ← s + 1
            current exists ? update rec_<r.id> If-Match current.etag : create rec_<r.id>
                              with { version, hlc…, sealed, isDeleted, seq: s, writer: jwt.dev }
          + update meta { seq: s } If-Match meta.etag
    submitTransaction(ops) → success: return 200 { applied, seq: s }
                          → 412 / 409 from Storage (someone raced us):
                              sleep (20 + rand·60) ms × attempt; loop
  return 503 + Retry-After: 1
  ```

  Each record gets its own `seq`; the batch is all-or-nothing; a racing writer can never interleave
  half a batch; `seq` is gap-free and never reused. The jittered sleep is a spike finding (Phase 0.1):
  without it, 2–3 of 10 concurrent pushers exhausted all five tries on every run; with it, none did
  across five runs. A 503 is still safe — nothing was written — but it shouldn't be the common path.
- **Validation** on push: `version > baseVersion`, framing (A.2), size, ids are UUIDs, no duplicate ids
  in one batch, at most 99 records, **no unknown fields** (a body with `dek`, `password`, `key` or any
  field not in the schema is `400` — the "never accept a key" guarantee is the schema being closed).
- **`header` PUT** compares `baseHeaderVersion` with `meta.headerVersion`, writes `header` and
  `headerVersion + 1` with `If-Match` on `meta`. Header changes don't consume a `seq`.
- **Errors** are `{ "error": "<code>", "message": "<human text>" }` with stable codes
  (`bad_request`, `unauthorized`, `rate_limited`, `conflict`, `gone`, `too_large`, `not_found`,
  `unavailable`). Messages never echo request bodies.
- **Logging:** method, route template, status, latency, vaultId prefix (8 chars). Never headers, never
  bodies, never the auth key or a token. A unit test asserts the logger rejects objects containing
  `authKey`, `token` or `sealed`.

### A.4 Authentication and abuse limits

- **The auth key.** `k_auth = HKDF-Expand(DEK, "sync-auth", 32)` inside the C++ session (D1); the seam
  hands Swift exactly these 32 bytes and nothing else (Phase 5). The server stores
  `authKeyHash = SHA-256(k_auth)` at vault creation and compares with `crypto.timingSafeEqual`. Same
  DEK on every device → same `k_auth` → no per-device credentials to manage.
- **Session tokens.** `openSession` returns an HS256 JWT `{ sub: vaultId, dev: deviceId, iat, exp }`,
  `exp = iat + 900 s`. The client caches it in memory only (never on disk) and simply opens a new
  session on `401`. Lock = forget the token.
- **Enrollment secret.** `POST /vaults` requires `X-PassFort-Enroll` = `PASSFORT_ENROLL_SECRET`
  (constant-time compare). You type it once when enabling sync. Without it, anyone who finds the URL
  can fill your storage account with junk vaults.
- **Brute-force / abuse.** `openSession` failures increment `meta.failedAuthCount`; from the 5th
  consecutive failure the vault locks for `2^(n−5)` minutes (capped at 1 h) via `lockedUntil` →
  `429 Retry-After`. A success resets it. Guessing a 256-bit key is hopeless anyway; this stops log
  spam and cost. `GET /header` is unauthenticated by necessity (a joining device needs the KDF salt
  before it has the DEK); the **vaultId is a 122-bit random capability**, and the header is exactly
  the offline-cracking target A2 already holds (§3.1).
- **Transport.** TLS from the platform; SPKI pinning in the native client (Phase 7.3). Azure's managed
  certificate renews on Azure's schedule, so pin the **CA keys in the served chain** (intermediate +
  root, two or three SPKI hashes recorded from `openssl s_client -showcerts` in Phase 0), not the leaf —
  and on a pin failure, sync stops with a clear `pinningFailed` problem rather than silently falling
  back. Pinning is skipped for `localhost` only. `passfort-cli sync … --pins <file>` lets you update
  pins without a rebuild. **No plaintext HTTP off loopback:** the client refuses a non-`https`
  endpoint unless the host is loopback, in code rather than relying on ATS, which doesn't cover the
  CLI (Phase 7.2).

### A.5 Client data model

**Schema migration `v2`** (`Migrations/V2_sync.swift`, forward-only, a GRDB migration — **not** a
format change: no sealed byte changes, `schema_version` stays `1`, no re-seal):

```sql
ALTER TABLE records ADD COLUMN hlc_counter    INTEGER NOT NULL DEFAULT 0;
ALTER TABLE records ADD COLUMN hlc_device     BLOB    NOT NULL DEFAULT x'00000000000000000000000000000000';
ALTER TABLE records ADD COLUMN synced_version INTEGER;   -- version the server last confirmed; NULL = never on the server
ALTER TABLE records ADD COLUMN synced_seq     INTEGER;   -- server seq of that version
```

Today `updated_at` keeps only the HLC wall time and `SealedRecord.init(row:)` fills `counter: 0` and an
all-zero device (`SealedRecord.swift` "M5 sync adds the counter + device_id in a schema bump") — this is
that bump. **Dirty** ≡ `synced_version IS NULL OR synced_version != version`. A pre-sync vault has every
row dirty, which is exactly right: enabling sync pushes everything.

**`vault_meta` keys** added (`VaultMetaKey`):

| Key | Value | Written by |
|---|---|---|
| `sync_config` | JSON `{ endpoint, vaultId, enabledAt }` — no secrets | enable / join / disable |
| `sync_cursor` | u64 BE — highest server `seq` fully ingested | every ingest commit |
| `sync_header_version` | u64 BE — server `headerVersion` this device's header corresponds to | header push / adopt |
| `header_dirty` | `0x01` when the local header changed and the server hasn't got it | `rotateRecoveryKey`, `recover` while sync is on |
| `pending_header` | `u64 BE headerVersion ‖ header bytes` — newer server header not yet adopted | pull (Phase 9) |

`sync_cursor` lives inside the vault file, so a rolled-back file also rolls back the cursor — and that
is already caught by `vault_version` vs `<db>.hw` at unlock (D7). Accepted gap: an attacker who can
edit the local file *and* controls the server could lower the cursor in place; that pairing is beyond
A2 + A5 individually and is recorded in §3.4 at the doc sweep.

**Device identity** (`DeviceIdentity.swift`): `{ id: UUID, name: String }`, created on first use and
stored **outside the vault file** — the app at `Application Support/PassFort/device.json` (inside the
sandbox container), the CLI at `~/.config/passfort/device.json` or `--device-id`. Outside, because a
vault file copied or restored onto another machine must not clone the device. It replaces the
zero-UUID `VaultService.deviceID` and feeds both the HLC and the server's device row.

**HLC clock** (`HLCClock.swift`, an actor owned by the repository), seeded at open with the max HLC in
the DB:

```
tick()          wall = max(now_ms, last.wall); counter = (wall == last.wall) ? last.counter + 1 : 0
receive(remote) wall = max(now_ms, last.wall, remote.wall)
                counter = wall == last.wall == remote.wall ? max(last.counter, remote.counter) + 1
                        : wall == last.wall   ? last.counter + 1
                        : wall == remote.wall ? remote.counter + 1 : 0
```

Every local `create` / `update` / `delete` stamps `tick()` instead of `HLC.now`; every pulled record
passes through `receive`. Ordering is the existing `HLC: Comparable` (wall, counter, device).

### A.6 The sync run

`SyncEngine.run()` — one run, start to finish. Single-flight: a trigger while a run is active sets
"run again when done" rather than starting a second run.

```
0. preconditions: unlocked; sync_config present; not already running
1. session      token ← POST /session { authKey: session.authKey(), device }
                assert response.seq ≥ sync_cursor                    else → serverRollback (A.9)
2. pull loop    page ← GET /changes?since=cursor&limit=500
                  410 → full resync (A.10), then continue at 3
                  assert page.seq ≥ cursor                            else → serverRollback
                  for each record: pf_open(id, version, sealed) must succeed   else → tamperedRecord
                  plan ← Reconciler over the page (A.7)              — pure, testable
                  seal any conflict copies / re-sealed winners (async, outside the transaction)
                  repo.applyRemote(plan, cursor: last seq in page)   — ONE commit (§8.2)
                until !hasMore
3. header       if page.headerVersion > sync_header_version → Phase 9 flow (A.8)
                if header_dirty → PUT /header
4. push loop    dirty ← rows where synced_version IS NULL OR synced_version != version
                batch them (≤ 99 records, ≤ 3 MiB) → POST /changes
                  200 → repo.markPushed(applied)                       — plain transaction
                  409 → back to step 2 (pull resolves the conflicts), then push again; max 3 rounds
4b. compaction  repo.compactSynced()   — purge clean tombstones locally (A.10)
5. status       lastSyncedAt ← now; publish SyncStatus
```

Pushed records come back on the next pull as echoes with `version == local version`; the Reconciler
ignores them (rule 2) and records their `seq`.

### A.7 Reconciliation rules

`Reconciler.decide(local: SealedRecord?, remote: Record) -> Decision`. Let `base = local.syncedVersion`
and `dirty = local.version != base`.

| # | Situation | Decision |
|---|---|---|
| 1 | no local row | **insert** remote as-is, clean (`synced_version = remote.version`) |
| 2 | local clean, `remote.version ≤ local.version` | **ignore** (echo or stale replay) — just record `synced_seq` if versions are equal |
| 3 | local clean, `remote.version > local.version` | **fast-forward**: overwrite local with remote, clean |
| 4 | local dirty, `remote.version ≤ base` | **ignore** (the server hasn't moved past our base; our push will win) |
| 5 | local dirty, `remote.version > base` | **conflict** — both changed since the common base. Go to 5a–5e. |
| 5a | …decrypted payloads equal (ignoring `revisionHistory`, `updatedAt`) | take remote, clean — same edit on both sides, no copy |
| 5b | …`remote.hlc > local.hlc` (remote wins) | overwrite local with remote, clean. If local was **live**, save local's payload as a **conflict copy**. If local was a tombstone, no copy (the record simply survives). |
| 5c | …`local.hlc > remote.hlc` (local wins) | **re-seal** local's payload at `version = remote.version + 1`; set `synced_version = remote.version` so the next push's `baseVersion` matches. If remote was **live**, save remote's payload as a conflict copy. If remote was a tombstone, no copy. |
| 5d | …winner is a tombstone, loser live | the delete wins, and the loser's payload survives as a **conflict copy** — an edit is never lost to a concurrent delete |
| 5e | …both tombstones | take the higher version, clean |

A **conflict copy** is a brand-new record: new UUID, `version 1`, `HLC tick()`, the loser's payload
with `conflictOf = <original id>` and a revision entry `["conflict copy"]`. It is a normal dirty row,
so the next push uploads it and every device sees it. `AccountSummary.isConflict` already exists
(`Account.swift`), so the list can badge it without new plumbing.

Rule 5c re-seals because the AEAD binds `version` into the AAD (§5.4): a payload can't move to a new
version without a new seal. That's why reconciliation needs the session, and why sealing happens
*before* the transaction opens (the same pattern as `commit` and its `ManifestBuilder`).

### A.8 Header changes: recovery-key rotation and recovery

The DEK never changes in M5 (D6), so a header change only re-wraps it. Two existing flows change the
header: **`rotateRecoveryKey`** (app Settings + CLI) and **`Vault.recover`** (recovery key → new master
password, CLI). With sync on, each also sets `header_dirty`.

- **Push (step 3):** `PUT /header { header, baseHeaderVersion: sync_header_version }` → `200` stores the
  new `sync_header_version` and clears `header_dirty`. `409` → another device changed it first: store
  the server's as `pending_header`, clear `header_dirty`, and raise `headerChangedElsewhere`.
- **Pull:** `headerVersion > sync_header_version` and no local change → `GET /header` →
  `pending_header`. Nothing is adopted while unlocked: this device keeps working on its open session
  (same DEK, same `k_auth`).
- **Adopt at the next unlock** (`Vault.unlock` gains this): with a `pending_header` present, try the
  typed password against the pending header first. Opens and its vault UUID equals the local one →
  replace `header`, set `sync_header_version`, clear `pending_header`. Fails → try the local header; if
  that opens, unlock and show *"The master password or recovery key was changed on another device.
  Unlock with the new password to finish updating this Mac."* Both fail → the usual `AuthFailed`.
- **Why the old password keeps working on a stale device until it adopts:** the device's own header
  still wraps the DEK under it. That is inherent to offline-capable devices. It is also why a leaked
  old password plus the server copy still opens every record until a DEK rotation exists (D6) — a
  §3.4 line at the doc sweep.

### A.9 What a hostile server can and cannot do (and how each is caught)

| Server behaviour | Effect | Caught by |
|---|---|---|
| forge or alter a record | — | `pf_open` fails → `tamperedRecord`; the whole page is rejected, nothing applied |
| replay an older version of a record you already have | — | rule 2 (`remote.version ≤ local.version` ignored) |
| roll the whole vault back | — | `seq < sync_cursor` at session or pull → `serverRollback`; sync stops |
| drop records from its table | a *new* device won't get them | existing devices never delete on absence; on a full resync they **re-upload** what the server lacks (A.10) |
| withhold or delay other devices' writes | staleness | **not detectable** — a freshness limit of any untrusted relay; recorded in §3.4 |
| serve a forged header to a joining device | — | the DEK unwrap fails before `k_auth` exists, so nothing is sent (D1) |
| learn things | record count, sizes (bucketed to 256 B), timestamps, HLC device ids, write frequency | accepted (§3.4) |

`serverRollback` is a hard stop surfaced in the UI (A.11) with one recovery action: **"Re-upload this
Mac's vault"** — `DELETE /vaults/{id}`, then the enable-sync flow with the same vaultId — offered only
after a confirmation that explains the server's copy will be replaced.

### A.10 Tombstones, compaction and full resync

- **Server purge** (opportunistic, inside `openSession`): `minSeq = min(dev.lastSeq over all devices)`;
  delete `rec_*` entities with `isDeleted && seq ≤ minSeq` (batched, ≤ 99 per transaction); raise
  `meta.purgedThroughSeq` to the highest purged `seq`. Every registered device has pulled those
  tombstones, so none of them needs it any more. A new device joins with `since=0` and doesn't need
  tombstones either.
- **Local compaction** (`compactSynced`, replaces `compact` while sync is on): purge local tombstones
  that are **clean** — the server has them, and other devices learn about deletions from the server,
  not from us. With sync off, `compact` keeps today's behaviour.
- **Full resync** (on `410`, after joining, after accepting a restored backup): pull everything with
  `since=0`, reconcile as usual, then for every local row the server didn't return: **dirty or never
  synced → push it; clean → push it too** (re-upload). A record deleted on another device while this
  device was unregistered can therefore reappear. That is the deliberate trade: the alternative,
  "deleting locally because the server says it's gone", lets a hostile or buggy server delete your
  passwords (A.9).
- **Removing a device** (Settings → Devices → Remove) stops it blocking purges. If it ever syncs again
  it gets `410` and resyncs as above. The UI says so in the confirmation.
- **Restoring a backup on a synced Mac:** `acceptRestoredBackup` additionally resets `sync_cursor` to 0
  so the next run is a full resync; rule 5a keeps that from producing spurious conflict copies for rows
  that already match the server.

### A.11 The app: functions, views and errors

**`SyncController`** (`PassFort/Model/SyncController.swift`, `@MainActor @Observable`, owned by
`AppModel`, alive only while unlocked; moves to `PassFortAppCore` in M7):

| Member | Does |
|---|---|
| `status: SyncStatus` | `.off` · `.idle(lastSyncedAt)` · `.syncing(phase)` · `.offline` · `.problem(SyncProblem)` |
| `devices: [DeviceInfo]` | last fetched device list |
| `enable(endpoint:enrollSecret:) async throws` | `POST /vaults` with the local header + `authKey`, then a full push; writes `sync_config` |
| `join(endpoint:vaultID:password:) async throws` | *before* a local vault exists: `GET /header` → `Vault.unlock` on it → bootstrap an empty local DB with that header → session → full pull. Lives on `AppModel` because it runs from the first-run state. |
| `syncNow()` | trigger a run (single-flight) |
| `disable(deleteServerCopy:) async` | optionally `DELETE /vaults/{id}`; clears `sync_config`, cursor and sync columns |
| `removeDevice(_:) async` | `DELETE …/devices/{id}` |
| `resolveConflict(copyID:keep:) async` | `.thisVersion` (copy's payload overwrites the original, copy deleted), `.otherVersion` (copy deleted), `.both` (copy's `conflictOf` cleared — it becomes an ordinary record) |

**Triggers** (all no-ops when sync is off or locked): after unlock; 2 s after the last local write
(debounced); every 60 s while unlocked and the app is active; on network-path change to satisfied
(`NWPathMonitor`); on wake; manual. **Never** while locked. Lock cancels the run task.

**Views:**

| View | Where | Content |
|---|---|---|
| `SyncSettingsSection` | Settings form, new "Sync" section (after "Security") | **Off:** endpoint field, enrollment secret (`SecureField`), "Enable sync" — explains what the server sees. **On:** status line + "Sync now", endpoint, this device's name (editable), `DevicesList`, "Add a device…", "Turn off sync…" (keep / delete the server copy). |
| `DevicesList` | inside the Sync section | name, platform icon, "last synced …", "This Mac" marker; Remove (with the A.10 explanation) |
| `AddDeviceSheet` | from "Add a device…" | the endpoint and vaultId as copyable text **and a QR code** (Core Image `CIQRCodeGenerator`; consumed by M7's join screen). Contains no secret — the joining device still needs the master password. |
| `SyncStatusFooter` | sidebar footer, beside the Settings button | small icon + "Synced 2 min ago" / "Syncing…" / "Offline" / "Sync problem"; click → popover with detail and "Sync now" |
| `JoinVaultView` | first-run screen, a second choice beside "Create vault" | endpoint, vaultId (paste), master password → progress: *Fetching header → Unlocking → Downloading N records* → done |
| Conflict badge + `ConflictBanner` | list row / detail top | "Conflicting copy — created by a sync conflict on <date>" + Keep this / Keep the other / Keep both / Compare |
| `ConflictCompareView` | sheet from the banner | two columns of fields that differ; passwords masked with a reveal toggle |
| Sidebar "Conflicts" group | sidebar, only when any exist | every conflict copy, so none goes unnoticed |
| `SyncProblemSheet` | when `status` becomes a hard problem | explanation + the one sensible action per problem (table below) |
| Unlock banner | Unlock screen | the A.8 "changed on another device" message |

**`SyncProblem` → UI:**

| Problem | Cause | Shown as | Action |
|---|---|---|---|
| `offline` | no network / DNS / timeout | footer "Offline" — silent, normal | retries on the next trigger |
| `unauthorized` | `401` after a fresh session | sheet | "Turn sync off and on again" (the server's key hash doesn't match this vault — e.g. the vault was recreated) |
| `rateLimited(until)` | `429` | footer | waits |
| `serverRollback` | A.9 | sheet, sync paused | "Re-upload this Mac's vault" (confirm) |
| `tamperedRecord(id)` | `pf_open` failed on a pulled record | sheet, sync paused | "Retry" — never applied; repeated → treat the server as compromised |
| `pinningFailed` | SPKI mismatch | sheet, sync paused | update the app / pins; never "continue anyway" |
| `headerChangedElsewhere` | A.8 | unlock banner | unlock with the new password |
| `tooLarge(id)` | a record over 65,320 B sealed | footer + the record's detail | shorten notes / history |
| `server(code)` | `5xx`, `503` after retries | footer | retries with backoff (30 s → 10 min) |

---

## Phase 0 — The Azure spike, and the decisions it settles

**`architecture.md` §15 step 6, and the gate on everything below.** Same move as M0 and M1: prove the
protocol and the cost locally and cheaply before the milestone is on the board.

### 0.1 The spike (throwaway branch, deleted when done)

- **One HTTP Function** (the A.3 push and pull, nothing else) + Table Storage on **Azurite** + `func
  start`. Implement the A.3 push algorithm literally — `meta` + records in one `submitTransaction`
  with ETags — and prove it: three pushes give seqs 1/2/3; two concurrent pushes from the same base
  give one `200` and one `409`; `GET ?since=0` returns all, `?since=3` returns none.
- A scratch `passfort-cli` subcommand pushes a real vault's `sealed` blobs and pulls them into a second
  DB file; every pulled blob still `pf_open`s.
- **Deploy once to a scratch RG** by hand (`az staticwebapp create`, a Free SWA, portal-set app
  settings) to measure what Azurite can't: cold-start latency of a managed Function, the per-request
  timeout, which Node versions `apiRuntime` accepts, and the served certificate chain
  (`openssl s_client -connect <site>.azurestaticapps.net:443 -showcerts`) for the pin set. Read the
  actual Table Storage prices for your region. Then `az group delete` it.

**Local half — DONE (2026-10-21), branch `spike/m5-azure`.** Run without `func` (see below): the A.3
push and pull written literally against `@azure/data-tables` + Azurite (`azurite-table`), plus a
round-trip of real blobs. Results:

- Three pushes → seqs 1/2/3; `since=0` → all three, byte-identical; `since=3` → none, `seq` 3.
- Same-record race from the same base → exactly one `200`, one `409 { serverVersion: 2 }`.
- 10-way race on different records → seqs always gap-free and unique. **But** with no backoff 2–3 of
  the 10 hit `503` every run; jittered backoff fixed it (now in A.3).
- 99 records + `meta` (100 ops) lands as one transaction. 100 records (101 ops) is refused (`400`),
  with nothing written. A 65,320-byte `sealed` fits; 65,576 is refused (`400`). **Azurite enforces both
  Table limits**, so the Phase 2 checkpoints can test them locally.
- The Int64 filter `seq gt <n>L` plus the `rec_` ≤ RowKey < ``rec` `` prefix range works as A.2 says.
- **Real blobs:** a synthetic vault's `pf_seal` output (3 records, one at version 2) was pushed as one
  batch and pulled back. A second vault was rebuilt from the pull (records table replaced, `.hw`
  copied). `passfort-cli verify` → OK and `list` / `get` open every record. Negative control: one
  flipped bit in one pulled blob → `manifest MAC mismatch`. No Swift subcommand was needed: Node's
  built-in `node:sqlite` read and wrote the vault files.
- **Tooling:** npm 11 holds back install scripts by default, and the `azure-functions-core-tools`
  npm wrapper (4.16.0) downloads a 620 MB zip, then fails to extract it with no error message on
  Node 26. Phase 1.3 installs `func` from Homebrew (`brew tap azure/functions && brew install
  azure-functions-core-tools@4`) instead. Whether the Functions host and SWA `apiRuntime` accept
  Node 26 is **unverified**. Node 26 is the local default; `Cloud/api/.nvmrc` may need to pin an
  older LTS.

**Deploy half — not run.** It needs `az`, an Azure login and a scratch RG -- run it from **Azure Cloud
Shell** in the browser (`az` and Bicep preinstalled), so nothing Azure is installed on the Mac
(2026-10-22). Its measurements (cold start, per-request timeout, `apiRuntime` Node versions, the cert
chain for the pin set, regional Table prices) are still open.

**Spike exit:** you can state from experience how many days `Cloud/` is, and whether ADR-0005's
CloudKit fallback should fire. "The custom backend costs more attention than it teaches" is a
sanctioned outcome — then this runbook is wrong and gets rewritten around CloudKit.

### 0.2 Decision: the auth design — **DONE (2026-10-21), ADR-0009**

`docs/adr/0009-sync-auth-key.md`: D1 + D2 + D3 — the DEK-derived `k_auth`, hash-at-rest, JWT sessions,
no device tokens, the enrollment secret. ADR-0005's auth bullet carries an amendment pointing at it.
**Spike follow-up:** if 0.1 finds anything that breaks the design (e.g. SWA managed Functions can't do
what A.3 assumes), amend ADR-0009 rather than quietly diverging.

### 0.3 Decision: scope — D4–D8 — **DONE (2026-10-21), `architecture.md` rev 12**

All eight rows accepted and folded into §3.4, §5.1, §6.2, §7.4, §7.5, §8.1, §9, §10, §12, §13 and §14
(decisions 8, 12, 13, 14 resolved; 20 added for DEK rotation and blind indexes). The spike checks the
numbers behind them (limits, timeouts, prices), not the decisions.

### 0.4 Open decisions closed by rev 12 (`architecture.md` §14)

Closed on paper in rev 12; the phase column is where each one is proven in code.

| §14 # | Resolved to | Proven in phase |
|---|---|---|
| 8 — server auth | ADR-0009 (DEK-derived auth key; OPAQUE no longer needed for the at-rest problem) | 0.2 |
| 12 — Table vs Blob | Table Storage, one partition per vault | 2 |
| 13 — thin API vs SAS | the thin Functions API | 3 |
| 14 — Bicep vs Terraform | Bicep (ADR-0005) | 12 |
| 20 — DEK rotation, blind indexes | *opened* by rev 12: both deferred past M5 | — |

**Checkpoint:** spike results written into `Cloud/README.md` (latency, timeout, Node version, pins,
prices); ADR-0009 and rev 12 still hold (or are amended); spike branch and scratch RG deleted.

---

## Phase 1 — `Cloud/` skeleton, the contract, and the local loop

### 1.1 Secret hygiene first (§15 step 2)

`.gitignore` additions:

```
Cloud/api/local.settings.json
Cloud/api/node_modules/
Cloud/api/dist/
.azure/
```

The stock gitleaks rules don't recognise the backend's secrets, so `.gitleaks.toml` adds three
(Storage account key, `PASSFORT_JWT_KEY`, `PASSFORT_ENROLL_SECRET`). The scan runs **in CI only**;
there is no local hook. The `secrets` job proves the rules on every push: it generates a fake secret
of each kind into a temp folder at run time and fails unless each rule fires, so no planted key is
ever committed.

### 1.2 `Cloud/openapi.yaml` — written before any endpoint

Exactly A.3: every path, request/response schema with `additionalProperties: false` (that closure *is*
the never-accept-a-key guarantee), every error code, the `bearerAuth` scheme, the `X-PassFort-Enroll`
header. Generate `src/dto.ts` with `openapi-typescript`; `npm run gen` regenerates, and CI fails if
the generated file is stale. The Swift DTOs (Phase 7) are hand-written but contract-tested against the
same file (Phase 11).

### 1.3 The Functions app and the local loop

Node LTS pinned in `.nvmrc` (match a version SWA's `apiRuntime` supports — Phase 0), TypeScript
`strict` plus `noUnused*`, `noImplicitReturns` and `noPropertyAccessFromIndexSignature` (standing in
for a linter), `@azure/functions` v4 and **`@azure/data-tables`** as the only runtime dependencies.
Session tokens are HS256 over `node:crypto` (Phase 3), not a JWT library. No ESLint and no OpenAPI
linter: `openapi-typescript` already fails on a broken spec, and the closure of every schema is
checked by the contract tests.

```bash
cd Cloud/api && npm ci && npm run typecheck && npm test
```

**Checkpoint:** `tsc --noEmit` is clean, the generated DTOs match `openapi.yaml`, and the `secrets`
job's self-test passes. Commit: `Cloud: Functions skeleton, openapi.yaml (§10.3)`.

---

## Phase 2 — Server storage layer

`src/lib/store.ts` (the `VaultStore` seam), `src/lib/table.ts` (`TableStore`: typed entity mappers for
`meta` / `rec_` / `dev_`, A.2), `src/lib/seq.ts` (the A.3 push algorithm, transaction + bounded retry,
storage-agnostic), `src/lib/validate.ts` (framing, sizes, UUIDs, version rules). Pure functions where
possible, so unit tests can run them without the Functions host.

**Checkpoint (unit tests, in memory and against a Table endpoint):** seqs 1/2/3 for three pushes; two concurrent pushes from the
same base → exactly one wins, `meta.seq` correct, no seq reused or skipped; a 99-record push is one
transaction and lands whole; a 100th record is `400`; a 295-byte or 297-byte `sealed` is rejected and a
296-byte one accepted; a 65,321-byte `sealed` is `413`.

**Done (2026-10-22).** All of the checkpoint above passes on both stores -- `MemoryStore` (every
`npm test`) and `TableStore` on Azurite (the CI `cloud` job; run locally once before Azurite left the
dev dependencies) -- plus: a conflicting record anywhere in a batch writes nothing; a rival that wins
every attempt ends in `unavailable` with nothing written; a pull never crosses partitions. Findings:

- **`@azure/data-tables` 13.3.2 returns Int64 as `bigint`** (Int32 as `number`, Binary as a pooled
  `Buffer`). The spike's `num()` hid this. `readNumber` takes `bigint` and refuses anything past 2^53
  rather than rounding.
- **A Binary read must be copied before it is written back.** The SDK's `Buffer` is a slice of a
  shared pool, and writing a view of it serializes the whole pool: re-creating a vault from a read
  `meta` failed with `PropertyValueTooLarge`. Only the Table-backed run caught it -- the in-memory
  store can't -- which is why CI keeps one.
- `MemoryStore` honours the same ETag contract as Table Storage and yields between calls, so the
  race tests interleave for real. Tests use the built-in `node:test`.
- `@azure/data-tables` pinned exactly at 13.3.2 (the spike's resolved version); `npm audit` is clean.

**Dependency trim (2026-10-22).** `Cloud/api` went from 435 installed packages (308 MB) to 54 (65 MB):
`azurite` (371 packages -- now a CI service container), ESLint + typescript-eslint (~95) and
`@redocly/cli` (26 MB) were removed, and `jose` dropped from the plan.

---

## Phase 3 — The endpoints

`src/functions/*.ts`, one file per A.3 row. Each is thin: parse → validate against the DTO → authorize
→ call `lib/` → map to the response. `src/lib/auth.ts` (key hash compare, lockout), `src/lib/jwt.ts`
(sign/verify, vault/route binding), `src/lib/errors.ts` (the stable codes), `src/lib/log.ts` (the
redacting logger). The purge (A.10) is a function in `lib/` called from `openSession`.

Handlers are plain functions (`request → response`) over a `VaultStore`, so they run in three hosts:
the Functions programming model (`src/functions/*.ts`, deployed), **`src/dev-server.ts`** (`npm run
dev` -- `node:http`, the memory store, `http://localhost:7071/api/v1`, no install), and direct calls
from tests.

**Checkpoint:** with `curl` against `npm run dev`: create a vault, open a session, push a record, pull
it back byte-identical, read the header, list devices, delete the vault. The same sequence against the
dev resource group once it exists (Phase 12). Commit per endpoint group.

**Done (2026-10-23).** The `curl` sequence above passes against `npm run dev` (sealed blob and header
byte-identical, log lines carry only the route template and an 8-character vault prefix), and
`test/api.test.ts` runs the same sequence in-process plus the auth, closure, lockout, purge/`410` and
device rules; `test/store.test.ts` covers the new store methods on both stores. The deployed-RG half
waits for Phase 12. Where it differs from the text above:

- **Layout.** Handlers live in `src/handlers/` (one file per endpoint group), the route table in
  `src/routes.ts`, and `src/functions/api.ts` registers every route -- instead of one `src/functions/`
  file per row. `app.http` outside the Functions host prints a "test mode" warning per call, so the dev
  server and tests must not import registration code; one adapter per host keeps them from drifting.
  `MemoryStore` moved from `test/support/` to `src/lib/` because the dev server uses it.
- **Pull reads `meta` on both sides of the scan** (`seq.ts`); a Table scan is not a snapshot.
  *Before:* only records with `seq ≤` that `meta.seq` are returned -- each was committed before the
  scan began, so it can't be missed; otherwise a push landing mid-scan could be skipped while a later
  one is returned, and the client's cursor would jump past it for good. *After:* `purgedThroughSeq`
  comes from this read, so a purge landing mid-scan always shows up as `410`, never as a silently
  missed tombstone.
- **Purge guard.** `@azure/data-tables`' array-form transaction `delete` can't carry an ETag (always
  `If-Match: *`). The `meta` ETag covers it: a tombstone only changes through a push, and every push
  rewrites `meta`.
- **A vanished vault behind a valid token is `401`** on every JWT route (push, pull, header PUT,
  devices) -- the client opens a new session, gets `401`, and surfaces `unauthorized` (A.11).
  `DELETE /vaults/{id}` is idempotent (`204` again), and deletes `meta` first so no push can land
  mid-sweep.
- **Lockout:** the failure that reaches 5 still answers `401`; later attempts get `429` until the lock
  expires, even with the right key. `GET /header` answers `429` while locked (the contract lists it).
- **Sessions:** a device row is created by `POST /vaults` and refreshed by every session (`lastSeq`
  kept); a pull updates `lastSeq` only if the row exists, so a removed device stays removed until its
  next session. Body cap 3 MiB on every route (`413`). Unexpected errors are `500` with the
  `unavailable` code, logged by class name only.

---

## Phase 4 — Contract tests and the `cloud` CI job

`Cloud/api/test/` with `node:test` (no extra dependency), driving the handlers over HTTP through the
dev server -- on the memory store locally, on the Azurite service container in CI. At minimum:

| Test | Asserts |
|---|---|
| `pushIsAllOrNothing` | a batch with one stale `baseVersion` → `409` listing it; `meta.seq` unmoved; no record changed |
| `seqIsGapFreeUnderRace` | 20 concurrent single-record pushes on distinct ids → seqs `1..20`, no repeats |
| `staleBaseIs409` | two devices push from the same base → one `200`, one `409 { serverVersion }` |
| `pullPagination` | 1,200 records, `limit=500` → three pages, `hasMore` false on the last, ascending seq, nothing missed |
| `sinceAtHeadIsEmpty` | `?since=<meta.seq>` → `[]` with the same `seq` echoed |
| `goneAfterPurge` | two devices, a tombstone both pulled, session triggers purge → `?since=<below purged>` is `410`; `since=0` still works |
| `authRejectsWrongKey` | wrong key → `401`, same body as unknown vault |
| `lockoutBacksOff` | 5 failures → `429 Retry-After`; success after expiry resets the counter |
| `tokenBoundToVault` | a token for vault A on vault B's routes → `401`; an expired token → `401` |
| `enrollSecretRequired` | create without / with a wrong `X-PassFort-Enroll` → `403` |
| `serverRejectsKeyShapedFields` | a create or push body with `dek` / `password` / an unknown field → `400` |
| `framingAndSize` | the Phase 2 size cases through HTTP |
| `headerOptimisticConcurrency` | two `PUT /header` from the same base → one `200`, one `409` |
| `loggerRedacts` | no log line contains the auth key, a token or a `sealed` value (capture stdout) |

**CI** — the `cloud` job in `ci.yml` (Linux, §13.2) already exists from Phase 2: `npm ci`, `tsc
--noEmit`, the DTO staleness check, then `npm test` with `PASSFORT_TEST_TABLES=UseDevelopmentStorage=true`
against `mcr.microsoft.com/azure-storage/azurite:3.37.0` as a service container. Phase 4 adds the
contract tests to the same `npm test`.

`package-lock.json` is committed and drift-checked like `Package.resolved`; a Node dependency bump is
its own reviewed commit (§3.2 A7).

**Checkpoint:** `npm test` green locally and in CI; the `ci.yml` header comment lists `cloud`.

**Done (2026-10-23), CI run pending.** `test/contract.test.ts` has one test per row above, by name, plus
a check that every response is JSON with `Cache-Control: no-store`. It runs locally on the memory
store (76 tests in all, green); the Azurite run happens on the next CI push. Where it differs from the
text above:

- **Over HTTP, in-process.** The dev server's request handling moved into `src/server.ts`
  (`createApiServer`), and the suite starts it on an ephemeral `127.0.0.1` port with `fetch` as the
  client -- real sockets, headers and JSON, with no child process. That also lets the tests inject
  the clock (`lockoutBacksOff`, the expired token) and the log sink, so `loggerRedacts` captures the
  sink rather than stdout. `dev-server.ts` is now only settings + `listen`.
- **`seqIsGapFreeUnderRace` retries `503`.** A `503` writes nothing and the contract says retry
  (A.3), so the test's client does, and asserts the landed seqs are exactly `1..20`. On Table
  Storage, 20 pushers can outlast the server's five tries.
- **Extra cases:** `framingAndSize` also checks 296 and 65,320 bytes are accepted, 100 records is `400`,
  and a body over 3 MiB is `413`. `serverRejectsKeyShapedFields` also covers a session body with
  `dek`. `loggerRedacts` checks failures (wrong key, forged token, a body with `dek`) as well as the
  happy path, and that every line has only the allowed fields.
- Shared helpers (`newVault`, `create`, `session`, `push`) moved to `test/support/vaults.ts`;
  `test/api.test.ts` keeps the in-process suite.

---

## Phase 5 — The crypto-core change: `k_auth`

The only `PFCrypto` change in M5 (D1, D5).

- `keyring/hkdf.cpp`: add `k_auth = expand(dek, "sync-auth")` beside `k_record` / `k_index` /
  `k_manifest`; remove `auth_secret` from the Argon2-side `RootKeys` (nothing uses it yet). Lives in
  the session handle, zeroized on close like the others.
- `boundary/`: `pf_session_auth_key(PFSession*, uint8_t* out, size_t out_len) -> PFStatus` — `out_len`
  must be 32, same out-buffer convention as `pf_session_vault_uuid`; `noexcept`, catch-all →
  `Internal`.
- `VaultSession.authKey() throws -> Data` — one boundary hop, status → Swift error.
- **Tests:** a native KAT (fixed DEK → checked-in 32-byte `k_auth`, computed independently with
  Python's `hmac`/HKDF-Expand so the C++ isn't checking itself); a test that two different DEKs give
  different keys and that `k_auth` differs from `k_record`/`k_manifest` for the same DEK; seam fuzz
  (null session, null out, wrong length, closed session, double close → `BadInput`, never a trap) in
  `PFCryptoBoundaryTests`.

**Checkpoint:** `ctest` (incl. ASan/UBSan) and `swift test --filter PFCryptoBoundaryTests` green.
Commit: `PFCrypto: k_auth under the DEK + pf_session_auth_key (ADR-0009)`.

**Done (2026-10-23).** `ctest` green (62 cases; 59 under ASan/UBSan, which skips the use-after-free
cases as before), `swift test` green, clang-format clean. `k_auth` is a fourth `DekSubkeys` field,
derived and scrubbed with the others; `RootKeys` keeps only the KEK, and the expand still reads all 64
Argon2 bytes, so no existing vault's KEK changes. Where it differs from the text above:

- **The label is `"sync-auth"`**, exactly as ADR-0009 and `openapi.yaml` say, not the `pf-*-v1`
  pattern of the other labels. It isn't vault format (nothing on disk depends on it), but the server
  holds `SHA-256(k_auth)`, so changing it later locks every device out.
- **A closed session returns `Locked`**, like every other boundary function, not `BadInput`; a null
  session, null `out` or any `out_len` other than 32 is `BadInput`, and a failed call writes nothing.
  Double close isn't tested: it is a use-after-free, as for the existing functions.
- **Where the tests live:** the KAT (`46e9c595…`, from Python's `hmac`) and domain separation in
  `native-tests/tests/test_keyring.cpp`; the seam fuzz in `test_seam_fuzz.cpp` with the rest of the
  fuzz suite (`PFCryptoBoundaryTests` calls no `pf_*` directly); "same key after rewrap, after a
  fresh open on the new password and via the recovery slot, another key for another vault" in
  `test_recovery.cpp` and again through `VaultSession.authKey()` in `PFCryptoBoundaryTests`.
- **A recovery-opened session can now sync** -- the old "rewrap before sync" comments came from the
  password-derived `auth_secret`. It still has to rewrap before `pf_recovery_wrap`.

---

## Phase 6 — Local schema v2, HLC clock, device identity, dirty tracking

1. **`V2_sync` migration** exactly as A.5. Check in a **v1 fixture vault** (already the M2 pattern) and
   a test that a v2 build opens it, every row reads back dirty with `hlc_counter 0`, and the manifest
   still verifies — the migration touched no MAC-covered column.
2. **`SealedRecord`** round-trips the full HLC (`updated_at` = wall, + counter, + device) and exposes
   `syncedVersion` / `syncedSeq`; delete the `m2Device` placeholder.
3. **`HLCClock`** per A.5, seeded from `MAX` over the table at `VaultRepository.open`; `create` /
   `update` / `delete` use `tick()`.
4. **`DeviceIdentity`** per A.5; `VaultService.deviceID` and the CLI's device id come from it.
5. **`VaultMeta`** gains the A.5 keys with typed accessors (cursor as u64 BE like `vault_version`).
6. **Repository additions** (signatures; bodies in Phase 8):

   ```swift
   public func dirtyRecords() async throws -> [SealedRecord]
   public func applyRemote(_ plan: ReconcilePlan, cursor: UInt64) async throws   // one commit
   public func markPushed(_ applied: [PushedRecord]) async throws                // plain transaction
   public func compactSynced() async throws
   ```

**Checkpoint:** `swift test` green including the fixture-migration test; an `update` on two quick
successive edits yields strictly increasing HLCs even with a frozen clock (inject the clock).

**Done (2026-10-23).** `swift test` green (177 + 15 tests), `xcodebuild` build and test green. The
v2 migration is the A.5 SQL verbatim; `schema_version` stays 1. Where it differs from the text above:

- **A new fixture, `Fixtures/v1-records/`.** The checked-in `v1` fixture is an empty schema (no header,
  no rows), so it can't show rows surviving. `v1-records` is a real v1 vault -- three synthetic
  records (versions 1 and 2, one tombstone), `vault_version` 5, password `fixture-v1-password` --
  made once by the v1 build from a throwaway generator (the recipe is in its README; a generator kept
  in the tree would write the current schema). `v1RecordsFixtureMigratesWithEveryRowDirtyAndTheManifestIntact`
  unlocks it with the v2 build: the MAC and the mark verify, every row is dirty with counter 0 and the
  zero device, every record opens, and a new write is stamped after the v1 stamps.
  `MigrationTests.regenerateV1Fixture` is gone for the same reason.
- **The clock is injected as `WallClock`** (`HLCClock.swift`), a `wallClock:` parameter on
  `VaultRepository.bootstrap` / `open`, default `.system`. Phases 8 and 10 reuse it for two-device
  tests. A counter at `UInt32.max` carries into the wall time rather than wrapping.
- **`applyRemote` waits for Phase 8**, where `ReconcilePlan` is defined -- no stub. `dirtyRecords`,
  `markPushed` and `compactSynced` are built and tested. `markPushed` records the pushed version even
  if the row moved on during the push (it stays dirty, with the right base for its next push), and
  ignores a version the row never reached.
- **Device identity:** the app's lives at `Application Support/PassFort/device.json` (in its
  container); if the file can't be read or written, that run stamps with an unsaved random id rather
  than failing to unlock -- Phase 13 makes sync require the stored one. The CLI's is
  `~/.config/passfort/device.json`, named `"<Mac name> (CLI)"`; `--device-id` is Phase 11. A
  file that exists but doesn't decode is an error, never silently replaced.
- **Importing from another vault** (`VaultImport`) still refuses an older-schema source, as it was
  designed to: a v1 vault must be opened once by this build (which migrates it) before it can be
  imported from.

---

## Phase 7 — The transport: DTOs, `SyncAPI`, pinning

### 7.1 `SyncDTO.swift`

`Codable` structs mirroring A.3 one-for-one (`RecordDTO`, `PushDTO`, `SessionResponse`,
`ChangesResponse`, `PushResponse`, `ConflictResponse`, `DeviceDTO`, `ErrorDTO`). `Data` fields as
base64 (the `JSONEncoder` default), UUIDs lower-cased on encode. **No `Codable` on `SealedRecord`
itself** — the DTO is the wire boundary.

### 7.2 `SyncAPI` + `HTTPSyncAPI`

```swift
public protocol SyncAPI: Sendable {
  func createVault(_ req: CreateVaultRequest, enrollSecret: String) async throws -> CreateVaultResponse
  func openSession(vaultID: UUID, _ req: SessionRequest) async throws -> SessionResponse
  func header(vaultID: UUID) async throws -> HeaderResponse
  func putHeader(vaultID: UUID, header: Data, base: UInt64, token: String) async throws -> UInt64
  func changes(vaultID: UUID, since: UInt64, limit: Int, token: String) async throws -> ChangesResponse
  func push(vaultID: UUID, _ records: [PushDTO], token: String) async throws -> PushResponse
  func devices(vaultID: UUID, token: String) async throws -> [DeviceDTO]
  func removeDevice(vaultID: UUID, deviceID: UUID, token: String) async throws
  func deleteVault(vaultID: UUID, token: String) async throws
}
```

`HTTPSyncAPI` maps status codes to `SyncError` (`409` → `.conflicts([…])`, `410` → `.resyncRequired`,
`401` → `.unauthorized`, `429` → `.rateLimited(retryAfter)`, transport errors → `.offline`), sets a
15 s request timeout, and never logs bodies. The engine owns the token (memory only); `HTTPSyncAPI`
is stateless.

**HTTPS only, enforced in code.** `HTTPSyncAPI.init` rejects any endpoint whose scheme isn't `https`
unless its host is loopback (`localhost`, `127.0.0.1`, `::1` -- the same set that skips pinning), and
`passfort-cli sync` validates `--endpoint` the same way before it prompts for a password. App Transport
Security already blocks plain HTTP in the app, but ATS only applies to app bundles: without this check
the CLI would send `k_auth` in cleartext to a mistyped `http://` endpoint. Redirects are refused
outright (`urlSession(_:task:willPerformHTTPRedirection:…)` returns `nil`; the API never redirects),
so a `30x` can't downgrade the scheme or move the request to another host. The rule lives in
`PassFortVault`, so both hosts get it.

### 7.3 `PinnedTransport.swift`

`URLSessionDelegate` handling `NSURLAuthenticationMethodServerTrust`: evaluate the trust normally first
(`SecTrustEvaluateWithError`), then require at least one certificate in the chain whose SPKI SHA-256 is
in the pin set (A.4). Pins come from build configuration (an `Info.plist` key for the app, a file for
the CLI) — never hard-coded in Swift. Skipped only when the host is loopback (`localhost` /
`127.0.0.1` / `::1`).

**Checkpoint:** DTO round-trip tests against JSON fixtures copied from `openapi.yaml` examples; a pinning
unit test with a test chain (pin match passes, mismatch fails, localhost skipped); a scheme test
(`http://localhost` / `http://127.0.0.1` / `http://[::1]` accepted, `http://example.com` and
`http://10.0.0.5` rejected before any request is made, `https://` accepted) and a redirect test (a `30x`
fails the request instead of following it).

**Done (2026-10-23).** `swift test` green (202 + 15 tests); `npm test` green (81). Everything lives in
`PassFortVault/Sync/`. Where it differs from the text above:

- **Shared fixtures instead of `openapi.yaml` examples** (the contract has none). `Cloud/fixtures/dto/`
  holds one JSON file per message. `SyncDTOTests` decodes every one and re-encodes each request to
  the same JSON; `Cloud/api/test/fixtures.test.ts` runs the request files through the server's own
  validators. A field renamed on either side now fails a suite.
- **Dates:** the server writes `toISOString()` (milliseconds), which `JSONDecoder`'s `.iso8601`
  rejects; `SyncCoding.decoder` takes RFC 3339 with or without fractional seconds. UUIDs are
  encoded lower-case by hand (`JSONEncoder` writes upper-case, which the server refuses).
- **`SyncError` is here, not in Phase 8:** the transport maps onto it. It names every status the
  contract uses (`409` per endpoint: `vaultExists`, `conflicts`, `headerConflict`), plus
  `insecureEndpoint`, `noPins`, `pinningFailed`, `redirectRefused`, `invalidResponse`, `offline`.
- **The endpoint rule** is `HTTPSyncAPI.init`: `https` with a non-empty pin set, or `http`/`https` to
  `localhost` / `127.0.0.1` / `::1`. An `https` endpoint with no pins is refused (`noPins`) rather than
  falling back to plain trust. TLS minimum is 1.3 (§9.4) -- **Phase 12 must confirm SWA negotiates it.**
- **Pinning:** `PinnedTransport` handles trust at the task level, so a pin failure is reported as
  `pinningFailed`, not as a cancellation. The SPKI is cut from the certificate's DER by a small
  reader (any key type) and checked against pins computed with OpenSSL, using a throwaway chain in
  `Fixtures/pinning` (public certificates only; the README has the recipe). `SecTrust` evaluation
  is tested with that chain as the only anchor: a pinned root, intermediate or leaf passes; an
  unrelated pin, an empty pin set, an unknown root or the wrong hostname fails. **Not yet seen
  against a real TLS server** -- the Phase 11 drill against the dev resource group is the first.
- **`HTTPSyncAPI` is a final class**, not a struct: its `URLSession` holds the delegate strongly and
  must be invalidated in `deinit`. Calls use `dataTask` (not `data(for:)`) to keep the task
  identifier a pin failure is recorded under. No cache, cookies or credential storage; nothing logged.

---

## Phase 8 — `Reconciler` and `SyncEngine`

1. **`Reconciler`** — pure, synchronous, no I/O: `decide(local:remote:payloads:) -> Decision`
   implementing A.7 rows 1–5e; payload equality (5a) is a function of decoded payloads, so the engine
   decrypts both sides only for rule-5 cases. **Table-driven tests: one test per A.7 row**, plus
   "tombstone beats edit leaves a copy" and "re-seal bumps to `remote.version + 1`".
2. **`ReconcilePlan`** — what `applyRemote` writes: rows to insert/overwrite (already sealed), conflict
   copies (already sealed), `synced_*` updates, the new cursor.
3. **`VaultRepository.applyRemote`** — the generalised `commit`: open the `ManifestBuilder` at
   `vault_version + 1` before the transaction; inside it, write every row of the plan, set
   `sync_cursor`, fold the post-write row set, write MAC + `vault_version`; after it, bump `<db>.hw`.
   Exactly the existing `commit` contract — re-use it rather than duplicating it.
4. **`SyncEngine`** (actor) runs A.6. It owns: the `SyncAPI`, the repository, the session, the device
   identity, the in-memory token, a `runAgain` flag. It publishes progress through an
   `AsyncStream<SyncStatus>` that `SyncController` consumes.
5. **`FakeSyncServer`** (test target) implements A.3's semantics in memory — the same push algorithm,
   seq, purge and `410` — so `PassFortVaultTests` exercise the engine headless in the `swift` CI job.

**Checkpoint (all against the fake server):** two repositories (two DB files, two device ids):
A creates 3 records and syncs → B joins and has 3; A edits X, B edits X offline, both sync → both end
with the HLC winner **and** one conflict copy, identical on both sides; A deletes Y while B edits Y →
both keep Y's edit as a copy; 2,000 records sync in pages; cancelling mid-run leaves both DBs verifying.

**Done (2026-10-24).** `swift test` green (233 + 15 tests), `xcodebuild` build and test green. Every
checkpoint scenario is a `SyncEngineTests` test, ending with both vaults reopened and verified
(manifest + mark). The A.7 rows are `ReconcilerTests`. Where it differs from the text above:

- **`FakeSyncServer` is in the test target** (`Tests/PassFortVaultTests/`), not `Sync/`. It follows
  `Cloud/api`'s semantics: the all-or-nothing push, one `seq` per record, `lastSeq` on pull, the purge
  in `openSession`, `410`. An `onRequest` hook runs inside the engine's task, so a test can cancel the
  run at an exact call.
- **The `Reconciler` API** is `isConflict(local:remote:)` plus
  `decide(local:remote:payloads:) -> Decision` (`insert`, `ignore`, `confirm`, `fastForward`,
  `takeRemote(copyLocal:)`, `keepLocal(copyRemote:)`). The engine decrypts the local row only when
  `isConflict` is true. A conflict without payloads skips 5a and keeps a copy, the safe direction.
- **5a "same edit"** also ignores `passwordChangedAt` and each password-history entry's
  `replacedAt`, both stamped "now" by the editing device; the replaced password values must still
  match. It also requires the same deletion state, because a delete is an edit too. **5e** always
  takes the server's tombstone, clean: both sides deleted, so pushing one tombstone over another
  gains nothing.
- **`applyRemote`** goes through `commit(basedOn:)`. The plan carries the `vault_version` it was
  built against, so a local write made while a page is being planned makes the commit `staleWrite`,
  and the engine plans the page again (up to 3 times). A page of nothing but echoes changes only
  bookkeeping outside the MAC (`synced_*`, the cursor), so it takes a plain transaction and
  `vault_version` doesn't move.
- **The vaultId is a fresh random UUID** chosen by `SyncEngine.enable`, not the header's vault
  UUID. `enable` (`POST /vaults`, `sync_config`, `sync_header_version`) and `join` (`sync_config`
  for a vault already built on the server's header) are on the engine. The rest of the join flow
  (fetch the header, unlock it, bootstrap the vault) is Phase 11 / 13.
- **Built now because A.6 needs them; Phase 10 tests the rest:** the `seq ≥ sync_cursor` floor at
  session and on every page (`serverRollback`); a record that fails `pf_open` rejects its whole page
  (`tamperedRecord(id)`, nothing applied); a page must be ascending, after the cursor, within its
  own `seq`, one entry per id, or it is `invalidResponse`. The fake has `loseNextPushResponse`,
  `rewind` and `flipBit` for these; Phase 10 adds the other adversarial modes.
- **Not wired yet:** step 3 (header, Phase 9). A `410` ends the run with `resyncRequired` (full
  resync is Phase 10).
- **Run behaviour:** a `409` pulls again and re-pushes, up to 3 rounds, then throws `conflicts`; a
  `401` mid-run opens one fresh session. `run()` is single-flight: a call during a run sets
  run-again and returns immediately. `SyncStatus.problem` carries the `SyncError`; Phase 13 maps it to
  `SyncProblem`.
- **A lost push response** (stored, but the client saw `offline`) is handled by 5a: the echo is the
  same edit, so no copy is made and nothing is pushed twice. Accepted edge case: if the record is
  edited again before the next run, the echo no longer matches and a spurious conflict copy appears,
  which is the safe direction. *(Fixed in Phase 10 by the descent rule.)*

---

## Phase 9 — Header sync (recovery-key rotation, recovery)

A.8 in code: `header_dirty` set by `rotateRecoveryKey` / `recover` when `sync_config` exists; the push and
pull halves in `SyncEngine` step 3; `pending_header` adoption inside `Vault.unlock` (try pending, then
local, with the vault-UUID equality check); `headerChangedElsewhere` surfaced.

**Checkpoint (fake server):** A rotates its recovery key → B pulls a pending header → B's next unlock
with the same password adopts it (the header differs only in slot 1) → `sync_header_version` equal on
both. A runs `recover` with a new password → B unlocks with the **new** password and adopts; with the
**old** password it unlocks and shows the banner. Both rotate concurrently → one `409`, that device
ends with the server's header pending.

**Done (2026-10-24).** `swift test` green (241 + 16 tests), native tests green (64; 61 under ASan),
`xcodebuild` build and test green. Each checkpoint scenario is a test in `SyncHeaderTests`. Where it
differs from the text above:

- **A seam addition, `pf_header_vault_uuid`** (its own commit). It reads a header's vault UUID
  through the existing prefix parser without opening the header. The field is unauthenticated and
  used only to compare identities. Unlock still costs one Argon2 run, and Swift duplicates none of
  the header layout.
- **A password change marks the header dirty too.** A.8 names `rotateRecoveryKey` and `recover`,
  but `changePassword` also rewrites the header. Without this, a device joining later would need
  the old password. All three go through `VaultMeta.writeLocalHeader`, which marks the header dirty
  only when `sync_config` exists. An adopted header is written plainly and is not marked dirty.
- **Adoption** (`Vault.unlock`): first compare the pending header's UUID with the local one (before
  any Argon2), then open the pending header with the typed password, then require the manifest to
  verify under it, which proves the same DEK. If any step fails, the stored header is used as before.
  A rollback is rethrown, since it has nothing to do with the header. A wrong password with a header
  pending costs two Argon2 runs. Adopting clears `header_dirty`: a local change made on top of the
  old header loses to the server's, the same outcome as a `409`.
- **Surfacing:** after a `409` the run finishes the records, then throws `headerChangedElsewhere`
  (status `.problem`). `VaultRepository.headerChangedElsewhere()` stays true while a pending header
  survives an unlock, which is the A.8 banner. Phase 13 adds the UI.
- **Edges:** `headerPushed` clears `header_dirty` only if the stored header is still the one sent; a
  header rotated again during the PUT stays dirty and is pushed next run. A pending header is stored
  only if it is newer than both `sync_header_version` and any header already pending.
  `Vault.recover` works on the local header and ignores a pending one; its result is pushed like
  any other header change (a `409` if it is stale).
- **For §3.4 at the doc sweep:** a hostile server can serve an old but genuine header as "pending".
  If the user then unlocks with that header's old password, it is adopted, which reverts a password
  change on that device. This is the same class of risk as A.8's "the old password keeps working
  until a DEK rotation (D6)".
- The two-device test harness moved to `SyncTestSupport.swift`, shared by `SyncEngineTests` and
  `SyncHeaderTests`.

---

## Phase 10 — Anti-rollback, the hostile server, compaction, full resync

1. **Floors:** session and every page assert `seq ≥ sync_cursor` (A.6) → `serverRollback`.
2. **Adversarial modes in `FakeSyncServer`:** `dropRecord(id)`, `replayOldVersion(id)`,
   `rewindSeq(to:)`, `flipBit(id)`, `forgeHeader`. Expected: re-upload on resync; ignored by rule 2;
   `serverRollback`; `tamperedRecord` with nothing applied; join fails at unwrap with **no** session
   call made.
3. **Purge + `410`** in the fake; `compactSynced` locally (clean tombstones only).
4. **Full resync** per A.10, including the re-upload of rows the server lacks.
5. **Restore interplay:** `acceptRestoredBackup` resets `sync_cursor`; a restored-then-synced vault
   ends equal to the server with no spurious conflict copies.

**Checkpoint:** every adversarial mode produces exactly the expected outcome and never a silent
acceptance or a local deletion; `passfort-cli verify` passes on both devices after each scenario.

**Done (2026-10-24).** `swift test` green (253 + 16 tests), `xcodebuild` build and test green.
Every scenario ends with each vault reopened and verified: the same manifest and mark check that
`passfort-cli verify` runs. The adversarial modes are `SyncHostileServerTests`; purge, `410`,
resync and restore are `SyncResyncTests`. Where it differs from the text above:

- **Adversarial modes** in `FakeSyncServer`: `dropRecord`, `replayOldVersion` (the fake now keeps
  every pushed version), `rewind`, `flipBit`, `forgeHeader`, plus `purge(through:)` and `unregister`
  to drive a `410`. The floors and the tampered-page rejection were built in Phase 8. Their tests
  moved here, with one new case: a `seq` rewound mid-run, caught on the page.
- **`Vault.join`** (`Sync/VaultJoin.swift`) replaces Phase 8's `SyncEngine.join`. It fetches the
  header, unlocks it, bootstraps the vault and writes `sync_config`. A forged header fails at the
  unlock, after a `GET /header` and nothing else, and nothing is written. **`SyncEngine` no longer
  takes a session:** `k_auth` comes from the repository, so the CLI and the app can build an engine
  from whatever `Vault.unlock` / `Vault.join` returns.
- **Full resync = any pull from cursor 0:** after a join, after accepting a restore, or after a
  `410` (which resets the cursor first). The stored cursor stays at 0 until the last page has
  landed, so a resync that is cut short is redone, not left half-finished. Then every synced row
  the server didn't return goes back to never-synced and is pushed with `baseVersion` 0. Nothing
  is deleted. The resync finishes at `max(last seq, purgedThroughSeq)`. Without the mark, a vault
  whose newest entries were purged tombstones would `410` on every run. Nothing is skipped: while
  this device pulls from 0, the server's minimum `lastSeq` is 0, so nothing can be purged under it.
- **A rule added to A.7, descent:** if one side's revision history already contains the other
  side's newest entry, it is a later state of the same record, and it wins with no copy. The
  history is sealed, so a server can't fake it. This keeps a restored backup's dirty rows from
  making spurious copies (A.10's "no spurious copies" needed more than 5a) and fixes the Phase 8
  lost-push edge case. An edit that records no revision entry (it changed only derived fields:
  `strength`, `breach`, `usedAt`) counts as no edit.
- **`Vault.acceptRestoredBackup`** resets `sync_cursor` (only if sync is on) and then the mark. The
  app's `VaultService` and `passfort-cli verify --accept-restore` both call it.
- **Accepted, for §3.4 at the doc sweep:** a replayed old version is ignored (rule 2), but the
  server goes on serving it to new devices. Existing devices don't push over it, and a resync
  doesn't either, because the record was returned. The same class as "withhold or delay" in A.9.
- A page that says `hasMore` with no records is `invalidResponse`.

---

## Phase 11 — CLI `sync`, and the two-device drill

`SyncCommands.swift`:

```bash
passfort-cli sync enable  --db A.sqlite --endpoint http://localhost:7071/api/v1 --enroll-secret dev
passfort-cli sync join    --db B.sqlite --endpoint http://localhost:7071/api/v1 --vault-id <uuid>
passfort-cli sync now     --db A.sqlite
passfort-cli sync status  --db A.sqlite        # cursor, dirty count, header version, last run, device
passfort-cli sync devices --db A.sqlite [--remove <deviceId>]
passfort-cli sync disable --db A.sqlite [--delete-server-copy]
```

(Flags follow the existing `passfort-cli` conventions; the password prompt is the same as `unlock`.)
`--device-id` overrides the device file so two CLI "devices" can share one machine.

**The drill** (scripted in `scripts/sync_drill.sh`, run by hand, output pasted into the runbook as M2's
CLI guide does): enable on A → join on B → edit on A, sync both → offline edits of the same record on
both, sync both → `list` shows the conflict copy on both → delete on A, edit on B → copy survives →
rotate the recovery key on A → B adopts at next unlock → `verify` on both. Plus the **contract check**:
the Swift client's requests validated against `openapi.yaml` (record real request/response pairs during
the drill and validate them with the OpenAPI schema in a Node test — catches Swift/TS drift).

**Checkpoint:** the drill passes end to end against `npm run dev`, then against the dev resource group.
Commit the script.

**Local half done (2026-10-24).** `scripts/sync_drill.sh` passes against a dev server it starts
itself, and the recorded traffic passes the contract check. `swift test` green (257 + 16 tests),
`npm test` green (81), `xcodebuild` build and test green, `shellcheck` clean. **The dev-resource-group
half waits for Phase 12**, which builds and deploys that resource group. Run it as
`scripts/sync_drill.sh --endpoint https://<site>/api/v1 --pins <file>`; it prompts for the enrollment
secret and deletes its server copy at the end. Where it differs from the text above:

- **Commands take the vault as an argument**, like every other `passfort-cli` command:
  `sync enable <vault> --endpoint … [--enroll-secret …]`, `sync join <new vault> --endpoint …
  --vault-id …`, `sync now|status <vault>`, `sync devices <vault> [--remove <id>]`,
  `sync disable <vault> [--delete-server-copy] [--yes]`. The enrollment secret is prompted for when
  `--enroll-secret` is omitted, which keeps it out of `ps` and the shell history. The endpoint is
  checked (https with pins, or loopback) before any prompt. Pins come from `--pins <file>` or
  `~/.config/passfort/pins`: one base64 SHA-256 per line.
- **`PASSFORT_DEVICE_FILE` instead of `--device-id`.** The device id stamps every write, so a second
  CLI "device" has to apply to `add` and `edit`, not only to `sync`. An environment variable that
  points every command at another identity file does that; a flag on the sync commands would have
  left B's edits stamped as A's.
- **Added for the drill and the CLI:** `passfort-cli recovery-key <vault>` (rotate the recovery key;
  the app already had it in Settings). `SyncEngine.run()` returns a `SyncReport` (pulled, pushed,
  conflict copies, full resync and re-uploads). The engine gained `devices`, `removeDevice` and
  `deleteServerCopy`; the repository gained `syncState()` and `disableSync()`; and a
  `sync_last_synced` meta key holds the time of the last run for `sync status`. Any unlock that leaves a
  pending header prints the A.8 note.
- **The contract check uses the shared fixtures, not `openapi.yaml`.** The dev server records each
  exchange when `PASSFORT_RECORD_DIR` is set. `test/recording.test.ts` then runs every recorded
  request through the server's closed validators and checks each response's shape against its
  `Cloud/fixtures/dto` file, which `SyncDTOTests` decodes on the Swift side. A real OpenAPI
  validator would mean a new npm dependency (rev 13); the fixtures already pin both ends. Tested by
  tampering: an extra request field and an extra response key each fail it.
- **Passwords** reach the CLI only through its terminal prompt, which is unchanged. The script answers
  the prompts with `expect(1)`, which ships with macOS, using a random throwaway drill password.

Transcript of the local run (step and check lines; each command's own output is omitted):

```
== building passfort-cli
== starting the dev server (in-memory store, recording on)
== A: a new vault with three accounts
== A: enable sync
   ok: A pushed all three
== B: join
   ok: B pulled all three
== an edit on A reaches B
   ok: B has A's edit
== both edit Email offline, then sync
   ok: B made a conflict copy
   ok: one conflict copy of Email on both
== B edits GitHub, then A deletes it, then both sync
   ok: the delete won and B's edit survives as a copy on both
== A rotates its recovery key; B adopts the new header at its next unlock
   ok: A pushed header version 2
   ok: B adopted header version 2
== verify both
   ok: A verifies
   ok: A has nothing left to push
   ok: B verifies
   ok: B has nothing left to push
== A lists the devices, then turns sync off and deletes the drill's server copy
   ok: A is marked as this device
   ok: the server copy is gone
   ok: A's sync is off
== the contract check over the recorded traffic
   40 exchanges recorded
   ok: every request passes the validators, every response has its fixture's shape
DRILL PASSED
```

---

## Phase 12 — Bicep, deploy, teardown

### 12.1 `Cloud/infra/main.bicep` (resource-group scope)

Exactly A.1: storage account (+ table service + `vaults` table), Static Web App (Free, no repo link —
the deploy action pushes content), its `appsettings` config (connection string from `listKeys()`, the
two `@secure()` params, table name, TTL), the budget (`amount: 5`, monthly, notifications at 50/80/100 %
to `budgetEmail`), and optional insights behind `enableInsights`. Outputs: the site's default hostname
(the endpoint), the storage account name. `main.parameters.json` holds `location`, `namePrefix`,
`budgetEmail`, `enableInsights` — nothing secret.

### 12.2 `Cloud/staticwebapp.config.json` and the placeholder site

`platform.apiRuntime` pinned to the Node version from Phase 0; `globalHeaders` with a strict CSP and
`X-Content-Type-Options: nosniff`; `/api/*` allowed anonymously (auth is the API's own). `Cloud/site/`
holds a one-line `index.html` until M6.

### 12.3 One-time setup (`Cloud/README.md`, verbatim)

Run in Azure Cloud Shell, not on the Mac -- `az` stays off the dev machine; `gh` works there too
(`gh auth login`).

```bash
az login
az group create --name rg-passfort-prod --location westeurope
Cloud/infra/bootstrap-oidc.sh rg-passfort-prod <github-owner>/PassFortApp   # Entra app + federated credential + Contributor on the RG
gh secret set AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_SUBSCRIPTION_ID     # ids, not secrets — still kept out of the repo
gh secret set PASSFORT_JWT_KEY       --body "$(openssl rand -base64 32)"
gh secret set PASSFORT_ENROLL_SECRET --body "$(openssl rand -base64 24)"
```

### 12.4 `.github/workflows/deploy.yml` (tag-triggered, `v*`)

1. `azure/login` with OIDC (`permissions: id-token: write`).
2. `az deployment group create -g rg-passfort-prod -f Cloud/infra/main.bicep -p @Cloud/infra/main.parameters.json -p jwtKey=… enrollSecret=…` (secrets from GitHub, masked).
3. Fetch the SWA deployment token with `az staticwebapp secrets list` (masked), build `Cloud/api`, run
   `Azure/static-web-apps-deploy` with `app_location: Cloud/site`, `api_location: Cloud/api`.
4. Smoke test: `curl https://<host>/api/v1/health`.

`ci.yml` never holds Azure credentials (§13.2).

### 12.5 Teardown discipline (the M5 "done when")

`az group delete --name rg-passfort-dev --yes` must leave **nothing** in the subscription for that
environment (check `az resource list`), and re-running `deploy.yml` from the same tag must reproduce it
with no manual step beyond 12.3. The Entra app registration is the one thing outside the RG; retiring
the project deletes it with `az ad app delete`.

**Checkpoint:** deploy `rg-passfort-dev` from a throwaway tag; run the Phase 11 drill against the real
endpoint **with pinning on**; `az group delete`; redeploy from the same tag; drill again; the cost page
shows ~$0 and the budget exists.

---

## Phase 13 — The app

### 13.1 Network access for the sandboxed app

The app target has `ENABLE_APP_SANDBOX = YES`. In Xcode → target → Signing & Capabilities → App Sandbox,
tick **Outgoing Connections (Client)** (sets `ENABLE_OUTGOING_NETWORK_CONNECTIONS`; never hand-edit
`project.pbxproj`). Not a restricted entitlement — "Sign to Run Locally" still works. No ATS exception:
the app only ever talks HTTPS to a deployed endpoint; local HTTP work is the CLI's job (Phase 11).

### 13.2 Model

`DeviceIdentity` replaces `VaultService.deviceID`. `SyncController` per A.11, created by `AppModel` on
entering `.unlocked` when `sync_config` exists, torn down on lock. `AppModel` gains `joinVault(...)`
for the first-run state and the pending-header unlock path (A.8). Write paths (`create` / `update` /
`delete` in `AppModel`) poke the debounced trigger. `AppModelTests` against `FakeSyncServer`:
`syncErrorDoesNotLockOrDropTheSession`, `conflictCopyAppearsInSummaries`, `lockCancelsSync`,
`joinBootstrapsAndPulls`.

### 13.3 Views

Everything in the A.11 view table, built in this order (each its own commit): `SyncStatusFooter` →
`SyncSettingsSection` (enable / disable / sync now) → `JoinVaultView` → conflict badge +
`ConflictBanner` + sidebar "Conflicts" group → `ConflictCompareView` → `DevicesList` →
`AddDeviceSheet` (QR) → `SyncProblemSheet` → the unlock banner.

**Checkpoint:** two Macs (or the Mac + `passfort-cli` as the second device) on `rg-passfort-dev`: enable
on one, join on the other; an edit appears on the other within a minute while both are unlocked; an
offline edit on both surfaces a badged copy on both, resolvable from either; airplane mode shows
"Offline", not an error; locking mid-sync leaves a vault that unlocks and verifies.

---

## Phase 14 — Tests, CI, and the doc sweep

### Coverage summary (§13.1)

| Where | Suite | Asserts |
|---|---|---|
| `native-tests/` | `k_auth` KAT, domain separation | the DEK → auth-key map is pinned |
| `PFCryptoBoundaryTests` | `pf_session_auth_key` fuzz | null / wrong length / closed / double close → `BadInput` |
| `Cloud/api/test` | Phase 4 table | atomic push, gap-free seq, pagination, `410`, auth, lockout, closed schema, redaction |
| `PassFortVaultTests` | transport scheme + redirects | non-loopback `http://` rejected before any request; `30x` never followed |
| `PassFortVaultTests` | migration v1 → v2 fixture | rows readable, all dirty, MAC verifies |
| `PassFortVaultTests` | `Reconciler` table tests | every A.7 row |
| `PassFortVaultTests` | `SyncEngine` vs `FakeSyncServer` | convergence, conflict copies, delete-vs-edit, paging, cancel safety |
| `PassFortVaultTests` | header sync | pending → adopt, banner path, concurrent rotation |
| `PassFortVaultTests` | hostile server | each A.9 row → its expected outcome, never silent, never a local delete |
| `AppModelTests` | sync wiring | the Phase 13.2 cases |
| Node contract check | Swift requests vs `openapi.yaml` | no client/server drift |
| manual | Phase 11 drill, Phase 12 teardown/redeploy, Phase 13 two-Mac checkpoint | the §12 "done when" |

CI: `cloud` (Phase 4) is the only new job; the Swift-side suites ride the existing `swift` job;
`deploy.yml` is separate and tag-only.

### Doc sweep (part of the milestone, not a follow-up)

- `architecture.md`: rev 12 confirmed against what shipped (a new rev for anything the build changed);
  §3.4's sync bullets re-read; §13.3's Azure rows marked live; open decision 16 (CI runners) revisited
  now that `cloud` joins the pipeline.
- ADR-0009 (already written): amend it if the build diverged; ADR-0005 gets a second amendment line
  only if the spike changed the backend choice itself.
- `m3-vault-management.md` Phase 6 (Azure backup): unblock note — it reuses `k_auth` sessions and gets
  its own endpoint (`PUT /vaults/{id}/backups`) in a follow-up, *not* in M5.
- `m7-ios.md`: confirm its Phase 5 join flow matches what shipped (`JoinVaultView` is the template).
- `README.md`: Architecture gains a sync paragraph + ADR-0005/0009 links; Project structure gains
  `Cloud/`; Getting started gains Node (the only local prerequisite; Azure tooling runs in Cloud
  Shell and CI); Testing gains `npm test`; Usage gains `passfort-cli sync …`.
- `CLAUDE.md`: Commands block gains the `Cloud/` loop; Project status line moves on.
- `docs/runbooks/README.md`: M5 → done.

---

## Where this leaves you

- **The vault is multi-device.** Every device keeps a complete local vault; Azure holds only sealed
  blobs, a counter and a hash of a key it can't use. Concurrent edits become visible conflict copies,
  never silent loss — including the delete-versus-edit case.
- **Auth with nothing to crack.** The server's credential store is `SHA-256` of a DEK-derived 256-bit
  key: a full Azure breach yields ciphertext and useless hashes. The §10.4 offline-cracking caveat is
  gone without implementing OPAQUE (ADR-0009).
- **A new project you own end to end:** `Cloud/` — TypeScript Functions on SWA, one Table partition
  per vault with transactional seq allocation, a closed OpenAPI contract, Bicep with a $5 budget,
  OIDC-federated deploys, and teardown that leaves no orphans. §1.1 goal 6, delivered.
- **One crypto-core change:** `pf_session_auth_key`. No vault-format change; one GRDB schema migration
  (v2) with a fixture test.
- **Honest limits, written down:** a hostile server can withhold updates (freshness), the old master
  password opens the server copy until DEK rotation exists, and a re-registered device may resurrect
  a record deleted while it was away.
- **Deferred, tracked:** DEK rotation and blind indexes (a format-change ADR), attachments + Azure
  backup destination, pin-rotation drills (M8).
- **Next:** M6 (web client) or M7 (iOS) — both consume this API unchanged. Whichever comes first is
  the proof that the contract was right.
