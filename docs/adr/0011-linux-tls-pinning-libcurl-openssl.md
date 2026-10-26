# ADR-0011: On Linux, sync pins through libcurl with an OpenSSL verify callback

**Status:** Accepted
**Date:** 2026-10-26

## Context

ADR-0010 makes `passfort-cli` run on Linux, and on Windows through WSL2, with the same sync
protocol and the same §9.4 transport rules: TLS 1.3, normal trust evaluation, then at least one
pinned SPKI hash among the CA keys of the served chain, and a pin failure that stops sync. On
Apple platforms `PinnedTransport` does this in a `URLSession` delegate with `SecTrust`. It also
needs SHA-256 for the pin hash, and `OneTimeCode` needs HMAC-SHA-1/256/512, both from `CryptoKit`.

The M6 spike (`docs/runbooks/m6-portable-cli.md` 0.1, 0.2; CI on Ubuntu 24.04 with Swift 6.3.3)
established what Linux offers:

- **`URLSession` can't pin on Linux.** swift-corelibs-foundation marks
  `NSURLAuthenticationMethodServerTrust` and `URLProtectionSpace.serverTrust` unavailable and never
  issues a server-trust challenge. Its one CA override (`URLSessionCertificateAuthorityInfoFile`) is
  compiled for Android only, and `tlsMinimumSupportedProtocolVersion` doesn't exist there.
- **libcurl's `CURLOPT_PINNEDPUBLICKEY` checks only the leaf.** Pinning the intermediate fails.
  §9.4 pins CA keys precisely because Azure renews the leaf, so this option can't express our pins.
  ADR-0010 had named it the likely fit; the spike showed it isn't.
- **libcurl with `CURLOPT_SSL_CTX_FUNCTION` works.** It installs an OpenSSL
  `SSL_CTX_set_cert_verify_callback` that runs OpenSSL's normal chain verification, then requires a
  pinned SPKI hash anywhere in the verified chain, root included: the same rule as
  `PinnedTransport.evaluate`. libcurl still checks the hostname. Against a live chain, all ten
  cases came out as expected (intermediate, root and leaf pins pass; a bogus pin, a wrong hostname
  and a self-signed server with its own key pinned fail).
- **libcurl and OpenSSL are already in the process.** Foundation's networking on Linux is built on
  libcurl, so the release CLI already loads `libcurl.so.4`, `libssl.so.3` and `libcrypto.so.3`.
- **libcrypto passes the RFC 6238 vectors** for HMAC-SHA-1, SHA-256 and SHA-512, the same ones
  `OneTimeCodeTests` uses.

## Decision

1. **On Linux, sync traffic goes through libcurl, not `URLSession`,** in a small C target
   (working name `CLinuxTLS`) compiled for Linux only and linked against the system libcurl and
   OpenSSL. It sets:
   - a verify callback that calls `X509_verify_cert` unchanged and then requires a pinned SPKI hash
     (SHA-256 of the DER `SubjectPublicKeyInfo`, the `PinSet` format) in the verified chain. An empty
     pin set trusts nothing, as on the Mac;
   - TLS 1.3 as the floor (`CURLOPT_SSLVERSION`), host verification left on, no redirects, the
     same 15 s request timeout, and the same loopback exception for the local dev server;
   - a mapping of a pin failure to `SyncError.pinningFailed`, never to a generic network error and
     never to a retry without pins.
2. **It fails closed if libcurl isn't built on OpenSSL.** `CURLOPT_SSL_CTX_FUNCTION` exists only
   for some TLS backends. If setting it fails, sync refuses to run rather than continuing unpinned.
3. **SHA-256 and HMAC on Linux come from libcrypto through the same C target.** Apple platforms
   keep `CryptoKit`. `OneTimeCode` and the pin hash choose by `#if canImport(CryptoKit)`.
4. **`HTTPSyncAPI` sends through a transport protocol** with two implementations: `URLSession` +
   `PinnedTransport` on Apple, `CLinuxTLS` on Linux. Request building, response decoding and
   error mapping stay shared, and the tests stub the protocol so they run on both platforms.
5. **Keys stay out of it.** The C target handles TLS (whose session keys stay inside OpenSSL, as they
   stay inside the system TLS stack on the Mac), the TOTP seed (record payload, not key material,
   per `OneTimeCode`), and public certificate data. It never sees the KEK, the DEK or an HKDF
   subkey, so ADR-0004's boundary holds: only `PFCrypto` holds keys.

## Consequences

- **The Linux CLI keeps every §9.4 rule,** including CA-key pinning with a hard stop on failure.
  The Mac and Linux read the same pin file format.
- **No new package dependency.** `Package.resolved` doesn't change, and nothing is added to the Mac
  build. Building on Linux needs `libcurl4-openssl-dev` and `libssl-dev`.
- **There are two HTTPS transports to keep in step.** The shared transport protocol and tests
  limit the drift, but the Linux one is our code: request and response plumbing, timeouts, and the
  error mapping.
- **Offline pinning tests on Linux** drive the verify function with the checked-in
  `Fixtures/pinning/{leaf,int,root}.der`, mirroring `PinningTests`' `SecTrust` cases.
- **libcurl and OpenSSL are the distribution's, not pinned by us.** Security updates arrive
  through `apt` without a commit here. The cost is that their behaviour can change under us,
  which matters less here than for Botan because they don't touch the vault format.
- **No revocation checking on Linux.** OpenSSL's default verification doesn't fetch CRLs or OCSP.
  `SecTrust` on the Mac uses the system's revocation policy. Pinning to the CA keys narrows what a
  revoked certificate could do; §3.4 records the difference.
- **The C target is new C code in the client.** It's small, but it parses certificates through
  OpenSSL and handles network input, so it gets the same review standard as `PFCrypto`'s seam and
  runs under ASan in CI.

## Alternatives considered

- **`URLSession` with a pinning hook.** Doesn't exist on Linux (see Context).
- **libcurl's `CURLOPT_PINNEDPUBLICKEY`.** Checks the leaf only, so it would pin the one
  certificate Azure rotates, breaking sync at every renewal or forcing leaf pins.
- **Trusting only the pinned CA certificates as anchors (`CURLOPT_CAINFO_BLOB`).** It needs whole
  certificates rather than SPKI hashes, so the pin format would differ between the Mac and Linux,
  and it drops the system-trust step the Mac keeps. Kept in reserve if the callback ever proves
  fragile.
- **No pinning on Linux.** Contradicts §9.4's "never a silent fallback". It would have been the
  quickest port, at the cost of the CLI being a weaker client than the apps.
- **swift-crypto for SHA-256 and HMAC.** Works unchanged (`import Crypto`) and passes the vectors,
  but adds swift-crypto and swift-asn1, resolved on every platform including the Mac, and about 70 s
  of BoringSSL compilation on a cold build. It isn't needed once the C target exists for pinning.
- **swift-nio-ssl and async-http-client.** Pinning-capable, but a large package graph with its own
  BoringSSL, against the minimal-dependencies rule.
- **Botan's TLS client in `PFCrypto`.** Would move networking into C++, against ADR-0004's
  "C++ owns only keys", and grow both the seam and the amalgamation.
