# PassFort Cloud

The sync backend: an Azure Functions API over one Azure Table, and nothing else. It stores sealed
records byte-for-byte and hands out a per-vault sequence number. It never decrypts, merges or holds a
vault key.

Status: M5 Phase 2 -- contract, Functions skeleton and the storage layer (`src/lib/`: the A.3
push/pull and validation). Only `GET /api/v1/health` exists as an endpoint; the vault endpoints and a
local dev server arrive in Phase 3 (`docs/runbooks/m5-sync.md`).

## Overview

`openapi.yaml` is the contract and the source of truth: the server's TypeScript DTOs are generated
from it, the Swift client's DTOs are contract-tested against it, and the M6 web client will use it
too. Every object schema is closed (`additionalProperties: false`), which is how "the server never
accepts a key, a password or a DEK" is enforced rather than promised.

The local footprint is deliberately small: **Node and npm are the only local prerequisites**, and the
npm tree is two runtime dependencies (`@azure/functions`, `@azure/data-tables`) plus three dev ones
(`typescript`, `@types/node`, `openapi-typescript`). Storage logic sits behind a `VaultStore`
interface, so the tests run on an in-memory store with nothing else installed; CI re-runs them against
a real Table endpoint (Azurite as a Docker service container). The Azure CLI and Bicep are used from
Azure Cloud Shell and the deploy workflow, not installed locally. The cloud (Static Web Apps managed
Functions + Table Storage, behind a $5 budget) enters at M5 Phase 12. The design, the API table and
the reasoning are in `docs/runbooks/m5-sync.md` Part A, ADR-0005 (Azure, not CloudKit) and ADR-0009
(the DEK-derived auth key).

## Project structure

```text
Cloud/
├── openapi.yaml                  # the API contract (m5-sync.md A.3) -- edit this first, then `npm run gen`
└── api/                          # Azure Functions v4, TypeScript, ESM
    ├── src/functions/            # one file per endpoint (health.ts so far)
    ├── src/lib/                  # store.ts (the VaultStore seam), table.ts (Table Storage), seq.ts (A.3 push/pull), validate.ts
    ├── src/dto.ts                # GENERATED from ../openapi.yaml -- never hand-edit
    ├── test/                     # node:test suites; support/memory-store.ts is the in-memory VaultStore
    ├── host.json                 # Functions host config; routes are prefixed /api by the host
    ├── local.settings.example.json  # template for local.settings.json (git-ignored): the app settings
    ├── .nvmrc                    # Node 22 -- the one major both SWA and Functions v4 support (CI and deploy)
    └── package.json              # exact-pinned dependencies; a new one or a bump is its own commit
```

## Getting started

### Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Node.js + npm | 22 or newer | CI and Azure run Node 22 (`.nvmrc`); local typechecking and tests also run on newer majors. Nothing else is installed locally. |

```bash
cd Cloud/api && npm ci
cd Cloud/api && cp local.settings.example.json local.settings.json && chmod 600 local.settings.json
```

Then replace the two `replace-with-` values in `local.settings.json`: `PASSFORT_JWT_KEY` with the
output of `openssl rand -base64 32`, `PASSFORT_ENROLL_SECRET` with any value.

## Usage

There is no local HTTP host yet: Phase 3 adds `npm run dev`, which serves the handlers on `node:http`
at `http://localhost:7071/api/v1` over the in-memory store -- no Functions Core Tools, no emulator.

## Configuration

App settings: `local.settings.json` locally, SWA app settings in the cloud (set by Bicep, Phase 12).

| Name | Purpose | Local value | Required |
|---|---|---|---|
| `TABLES_CONNECTION_STRING` | Table Storage access | unused locally (in-memory store); a scratch account's string to hit real Table Storage | Y in the cloud |
| `PASSFORT_TABLE` | table name | `vaults` | Y |
| `PASSFORT_JWT_KEY` | HS256 key for session tokens, at least 32 random bytes, base64 | `openssl rand -base64 32` | Y |
| `PASSFORT_ENROLL_SECRET` | gate on `POST /vaults` | any value | Y |
| `PASSFORT_JWT_TTL_SECONDS` | session-token lifetime | `900` | N (default 900) |

`PASSFORT_JWT_KEY`, `PASSFORT_ENROLL_SECRET` and Storage account keys have dedicated gitleaks rules
(`.gitleaks.toml`); the stock ruleset does not recognise them. The scan runs in CI only, and the
`secrets` job self-tests these three rules against fake secrets it generates at run time.

## Testing

```bash
cd Cloud/api && npm run gen && git diff --exit-code src/dto.ts    # generated DTOs not stale
cd Cloud/api && npm run typecheck                                  # tsc --noEmit, strict + noUnused*
cd Cloud/api && npm test                                           # build, then node:test
```

`npm test` needs no setup: the storage suites run on the in-memory `VaultStore`. Set
`PASSFORT_TEST_TABLES` to a Table connection string and they run a second time against it -- the CI
`cloud` job does exactly that with `UseDevelopmentStorage=true` and an Azurite service container.
That second run matters: it is what caught the SDK's pooled-`Buffer` bug (m5-sync.md Phase 2). The
suites compile into `dist/test/`; the deploy package (Phase 12) must leave that folder out. Contract
tests over HTTP arrive in M5 Phase 4.

## Further documentation

- `docs/runbooks/m5-sync.md` -- the M5 runbook: Part A is the design (resources, data model, API,
  auth, sync algorithm); Phase 0.1 records the spike results.
- `docs/architecture.md` §9 (sync) and §10 (the Azure backend).
- `docs/adr/0005-azure-sync-backend.md`, `docs/adr/0009-sync-auth-key.md`.
