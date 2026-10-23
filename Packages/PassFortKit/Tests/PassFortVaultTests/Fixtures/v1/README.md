# Fixture: schema v1

`vault.sqlite` — a synthetic vault at schema version 1. **Synthetic data only.**

## What's in it

An empty vault: schema v1 applied (`records`, `vault_meta`, `schema_version`
tables), `schema_version.version = 1`, no records, no header. The `grdb_migrations`
table records `v1` as applied.

## How it was generated

```
PF_REGEN_FIXTURES=1 swift test --filter regenerateV1Fixture
```

(`MigrationTests.regenerateV1Fixture`, gated on the env var, runs
`VaultDatabase(path:)` on this path, checkpoints the WAL with
`PRAGMA wal_checkpoint(TRUNCATE)`, and removes the `-wal` / `-shm` sidecars.)
That generator was removed when schema v2 landed (M5 Phase 6): it ran the current
migrator, so from then on it would have written a v2 file here.

## Rule

This file is **never regenerated**. Every future schema version `vN` adds its own
`Fixtures/vN/vault.sqlite`; `checkedInV1FixtureStillMigrates` (and its future
siblings) open each one with the current build and assert the migrator brings it
to the current schema with records still intact. Regenerating an old fixture
defeats the point — it would stop testing the real upgrade path.

## Test password

There is none — this fixture has no header and no sealed records. The fixture with
records is `../v1-records/`; its password is in its README.
