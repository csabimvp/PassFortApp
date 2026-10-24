# Sync API contract

The wire contract between PassFort clients and a sync server. The server is not part of this
repository; the client treats whatever answers at the endpoint as untrusted (`architecture.md` §9).

- `openapi.yaml` is the source of truth. Every object schema is closed
  (`additionalProperties: false`), so a request that carries a key, a password or a DEK is invalid
  by contract rather than by promise.
- `fixtures/dto/` holds one JSON file per message. The hand-written Swift DTOs are checked against
  them (`SyncDTOTests`), and a server implementation checks its validators against the same files,
  so the two sides can't drift apart silently (`m5-sync.md` 7.1).

| Files | Swift (`SyncDTOTests`) | Server |
|---|---|---|
| `dto/*.request.json` | decodes each into its DTO and re-encodes it to the same JSON | its closed-schema validators accept each one |
| `dto/*.response.json`, `*.conflict.json`, `error.json` | decodes each into its DTO | its responses have each one's shape |

Synthetic values only: the byte fields are counting patterns of the right lengths (a 296- and a
552-byte sealed blob, a 32-byte auth key, a 133-byte header), the token is not a JWT, and the
timestamps carry milliseconds the way the server writes them (`toISOString()`).

When the contract changes, change `openapi.yaml`, then these files, then both sides until both
suites pass.
