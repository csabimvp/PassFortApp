# ADR-0005: Custom Azure sync backend, not CloudKit

**Status:** Accepted
**Date:** 2026-08-28

## Context

Sync (architecture §9) needs a server that stores per-record ciphertext blobs, returns the ones
that changed since a cursor, and rejects stale writes. The rev-3 plan named CloudKit private
database as the starting point and called a custom HTTPS backend "a second project wearing a
trench coat" — a fair risk assessment, but the wrong fit for what this project is *for*.

Two things changed the calculus:

- **Standing up cloud infrastructure is now an explicit learning goal** (§1.1 goal 6), on par with
  the cryptography and the interop. A managed backend that hides auth, storage, and ops teaches
  nothing about any of them.
- **A web client is in scope** (ADR-0006, §11). CloudKit's browser story (CloudKit JS) ties the
  web client to an Apple ID and Apple's JS SDK; a plain HTTPS API serves the native app, the
  browser, and the CLI from one contract.

The server's trust position is unchanged either way: it is adversary A2, it holds only ciphertext,
and the manifest MAC (§5.5) plus per-record AEAD (§5.4) already assume it is hostile. So this
decision is about *who operates the store and what it costs to learn*, not about security
properties.

The constraint that shapes the design is cost and dependency minimalism. It must run at
approximately zero dollars at personal scale and add as little as possible to the dependency
surface the rest of the project guards so carefully.

## Decision

The reference sync backend is a **custom Azure deployment**, provisioned as code, with the
smallest footprint that does the job:

- **Azure Static Web Apps (Free tier)** hosts the web client and the managed Functions API,
  terminates TLS with a managed certificate, and can gate the API behind a built-in login.
- **Azure Table Storage** — one table, partitioned by vault — is the record store. ETags give
  optimistic concurrency; a per-partition `seq` counter is the change cursor and doubles as the
  anti-rollback `vault_version` (§5.5).
- **Azure Functions (Consumption / SWA-managed), in TypeScript**, expose six endpoints (§10.3).
  The API moves sealed bytes and enforces auth, `seq` monotonicity, and rate limits. It never
  holds or inspects a key.
- **Auth reuses `auth_secret`** (§5.1) as a challenge-response verifier, compared in constant time
  against `HMAC(pepper, auth_secret)` — no server-side KDF, no identity provider on the critical
  path.
- **Bicep** provisions all of it, including a budget alert. Local development runs entirely on
  Azurite + `func` + `swa`, offline and free.

TypeScript for the Functions because the web client is unavoidably TypeScript, and sharing the
language gives one set of DTOs generated from `openapi.yaml` and one toolchain. The Azure learning
value is identical in C#, so code sharing is the tie-breaker.

CloudKit is not deleted from the design — it remains the documented fallback if the custom backend
ever costs more attention than it returns.

## Consequences

- **The sync backend becomes a real, ownable thing to learn:** Functions, Table Storage, Bicep,
  Static Web Apps, Entra ID, a hand-written auth flow, rate limiting, an OpenAPI contract, CI/CD,
  and teardown discipline.
- **Cost is effectively zero** at personal scale — Static Web Apps Free, Functions under the
  perpetual free grant, Table Storage in the pennies. A $5 budget alert is the safety net. This
  stops being true only if an always-on resource is added, which the design forbids.
- **Sync leaves the Apple ecosystem.** No CloudKit entitlement, no Apple Developer Program
  dependency for sync, and the same API is reachable from any future non-Apple client.
- **We now own the boring, security-relevant parts:** auth, device registration, rate limiting,
  rotation of the JWT signing key, log hygiene, and not leaking `auth_verifier`. Architecture
  §10.4 and §14.8 track the `auth_secret`-vs-OPAQUE limitation.
- **The dependency surface grows by:** Node.js, one Table Storage SDK package (or raw REST),
  Azure CLI + Bicep, Functions Core Tools, the SWA CLI, and Azurite — all build/deploy-time, none
  in the app binary.
- **Anti-rollback needs the client to cache a high-water mark** outside the server's reach
  (Keychain on macOS; weaker in the browser, §11.4). The server assigns `seq`; the client refuses
  to move backwards.
- **Concurrent multi-writer anti-rollback is not fully solved** and is explicitly out of scope for
  the expected usage (§10.5).

## Alternatives considered

- **CloudKit private database.** Removes auth, device registration, and server ops entirely, and
  Apple genuinely cannot read the data. Rejected as primary: it teaches none of the stated cloud
  goal, ties the web client to Apple ID + CloudKit JS, and needs the Apple Developer Program. Kept
  as the fallback.
- **Clients talk directly to Table/Blob Storage with short-lived SAS tokens; one Function only
  mints tokens.** The most minimal option. Rejected: SAS can't enforce `seq` monotonicity or rate
  limits, browser CORS + SAS is fiddly, and the thin API is the part actually worth practising
  (§14.13).
- **Azure Cosmos DB (serverless).** Native change feed, clean cursor semantics. Rejected: more
  expensive, a heavier dependency, and overkill for a single-partition-per-vault key/value
  workload.
- **Azure Container Apps / App Service.** Rejected: either always-on cost or more orchestration
  than six functions need. Consumption Functions scale to zero.
- **A non-Azure backend (Cloudflare Workers + KV/D1, Supabase, a VPS).** Cheaper or simpler in
  places, but Azure is the environment being practised. Noted and set aside.
- **Terraform instead of Bicep.** Portable across clouds, larger ecosystem. Rejected: a separate
  binary, a state backend to operate, and there is no second cloud. Bicep ships in `az` and is
  Azure-native (§14.14).
