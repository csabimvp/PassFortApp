# Contract fixtures

One JSON file per sync API message (`../openapi.yaml`), shared by both sides of the contract so the
hand-written Swift DTOs and the TypeScript server can't drift apart silently (`m5-sync.md` 7.1):

| Files | Swift (`SyncDTOTests`) | Server (`Cloud/api/test/fixtures.test.ts`) |
|---|---|---|
| `dto/*.request.json` | decodes each into its DTO and re-encodes it to the same JSON | its closed-schema validators accept each one |
| `dto/*.response.json`, `*.conflict.json`, `error.json` | decodes each into its DTO | -- (the handlers' bodies are typed by the generated `dto.ts`) |

Synthetic values only: the byte fields are counting patterns of the right lengths (a 296- and a
552-byte sealed blob, a 32-byte auth key, a 133-byte header), the token is not a JWT, and the
timestamps carry milliseconds the way the server writes them (`toISOString()`).

When the contract changes, change `openapi.yaml`, then these files, then both sides until both
suites pass.
