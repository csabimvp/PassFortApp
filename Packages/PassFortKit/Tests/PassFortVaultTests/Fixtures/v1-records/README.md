# Fixture: schema v1, with records

`vault.sqlite` — a synthetic vault at schema version 1, **with a header and sealed records**. The
upgrade-path fixture for every migration from v2 on (`MigrationTests`). **Synthetic data only.**

## What's in it

| Record | `version` | State |
|---|---|---|
| "Example Mail" (`alice@example.com`) | 1 | live |
| "Example Bank" (`alice`), notes edited once | 2 | live |
| "Old Forum" (`alice`) | 2 | tombstone |

`vault_version` is 5 (three creates, one update, one delete), with a manifest MAC over all three rows.
`updated_at` holds HLC wall-clock milliseconds only, as v1 did. KDF parameters are the tests' cheap
ones (8 MiB, t = 1, p = 1, zero salt), so unlocking it takes milliseconds. The `.hw` high-water
sidecar is not checked in (`*.hw` is git-ignored); a test that needs it writes `5`.

## Test password

`fixture-v1-password` — in the clear, on purpose. It protects nothing real.

## How it was generated

Once, on 2026-10-23, with the schema-v1 build (commit `3e35ae5`), by a throwaway test that was then
deleted -- a generator kept in the tree would produce the current schema, not v1:

```swift
let repo = try await Vault.create(
  databasePath: path, password: Data("fixture-v1-password".utf8),
  params: KdfParameters(kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1,
                        salt: Data(count: 16)),
  deviceID: UUID(uuidString: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")!)
_ = try await repo.create(AccountPayload(title: "Example Mail", username: "alice@example.com",
                                         password: "correct-horse-1"))
let edited = try await repo.create(AccountPayload(title: "Example Bank", username: "alice",
                                                  password: "battery-staple-2"))
try await repo.update(id: edited.id) { $0.notes = "edited once -- version 2" }
let gone = try await repo.create(AccountPayload(title: "Old Forum", username: "alice"))
try await repo.delete(id: gone.id)
// then PRAGMA wal_checkpoint(TRUNCATE) and remove -wal / -shm
```

SHA-256 of `vault.sqlite`: `ef058f5b20cacc9fd1d1b4e9cfd6d16785047094b5cb6a608834571de6bec4cf`.

## Rule

**Never regenerated** (see `../v1/README.md`). Regenerating it with a later build would stop testing
the real upgrade path.
