# Fixture: a test certificate chain for SPKI pinning

Public certificates only -- **no private keys are checked in** (they were generated in a scratch
directory and discarded). Nothing here is trusted by any system; the tests pass `root.der` to
`SecTrust` as the only anchor.

| File | Subject | Key | Valid |
|---|---|---|---|
| `root.der` | CN=PassFort Test Root (self-signed CA) | EC P-256 | 2026-01-01 .. 2036-01-01 |
| `int.der` | CN=PassFort Test Intermediate (CA, pathlen 0) | EC P-256 | 2026-01-01 .. 2036-01-01 |
| `leaf.der` | CN=sync.test, SAN `DNS:sync.test`, serverAuth | EC P-256 | 2026-10-01 .. 2028-01-01 |

The leaf's validity stays under Apple's 825-day limit for TLS server certificates, so
`SecPolicyCreateSSL` accepts it. Tests evaluate at a fixed date inside it.

## Expected SPKI pins

SHA-256 of each certificate's DER `SubjectPublicKeyInfo`, base64 -- computed with OpenSSL, not by
the code under test:

```bash
openssl x509 -inform der -in leaf.der -pubkey -noout \
  | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
```

| Certificate | Pin |
|---|---|
| root | `wYv+2XJZODvpQGEdrdNF/YPobcweZUdlpXSz8PnQbcU=` |
| intermediate | `M1AWPj3AZEniRAxIO4lxAIEtRyVX2LOoj7MHpuzGpDU=` |
| leaf | `PCClOeEVI70kyhMRHlM0Ey9Ab6qASnZCpuismnykSMg=` |
| (an unrelated key, for "mismatch") | `ZfrT1aasVhxA4K/WebS2zC/1ET4G9W9rBgbWcHqHchQ=` |

## How it was generated

OpenSSL 3.6.4, on 2026-10-23: four `ecparam -name prime256v1` keys; the root self-signed with
`basicConstraints=critical,CA:true`; the intermediate signed by it with `CA:true,pathlen:0`; the leaf
signed by the intermediate with `CA:false`, `keyUsage=digitalSignature`,
`extendedKeyUsage=serverAuth`, `subjectAltName=DNS:sync.test`; all `-sha256`. `openssl verify` passes
for the chain. Regenerating it changes every pin above -- update this table and the tests together.
