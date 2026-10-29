#ifndef PF_LINUX_TLS_H
#define PF_LINUX_TLS_H

// Sync's TLS on Linux (ADR-0011): one HTTPS request through libcurl with OpenSSL's normal chain
// verification plus an SPKI pin check, and SHA-256 / HMAC from libcrypto. Apple platforms use
// URLSession, SecTrust and CryptoKit instead; there this target compiles to nothing.
//
// No key material passes through here: request bodies carry k_auth, tokens and sealed blobs, as
// they do through URLSession on the Mac, and the HMAC key is a TOTP seed (record payload).

#include <stddef.h>
#include <stdint.h>

/// The outcome of pf_tls_send.
typedef enum {
    PF_TLS_OK = 0,          ///< a response came back, whatever its HTTP status
    PF_TLS_OFFLINE = 1,     ///< DNS, connect, handshake, timeout or a dropped connection
    PF_TLS_UNTRUSTED = 2,   ///< the chain failed verification, matched no pin, or the host is wrong
    PF_TLS_UNSUPPORTED = 3, ///< this libcurl can't run the pin check (not built on OpenSSL)
    PF_TLS_CANCELLED = 4,   ///< pf_tls_cancel_set was called
    PF_TLS_TOO_LARGE = 5,   ///< the response passed PF_TLS_MAX_RESPONSE
    PF_TLS_BAD_INPUT = 6,   ///< a NULL, a header with CR or LF, or pinning without https/pins
    PF_TLS_INTERNAL = 7     ///< out of memory, or libcurl refused an option
} pf_tls_status;

/// The most a response (headers and body together) may hold before the request fails.
#define PF_TLS_MAX_RESPONSE (64u * 1024u * 1024u)

/// A flag another thread sets to stop a request in flight.
typedef struct pf_tls_cancel pf_tls_cancel;
pf_tls_cancel *pf_tls_cancel_new(void);
void pf_tls_cancel_set(pf_tls_cancel *cancel);
void pf_tls_cancel_free(pf_tls_cancel *cancel);

typedef struct {
    const char *method;         ///< "GET", "POST", "PUT" or "DELETE"
    const char *url;            ///< absolute http(s) URL
    const char *const *headers; ///< "Name: value" lines, without CR or LF
    size_t header_count;
    int has_body; ///< 0: no body; otherwise body/body_len (which may be 0)
    const uint8_t *body;
    size_t body_len;
    const uint8_t *pins; ///< pin_count SHA-256 SPKI hashes, 32 bytes each
    size_t pin_count;
    int skip_pinning;      ///< loopback only: system trust, no pins (as on the Mac)
    long timeout_seconds;  ///< connect timeout, and the longest a transfer may stall
    pf_tls_cancel *cancel; ///< may be NULL
} pf_tls_request;

typedef struct {
    long status;
    uint8_t *body; ///< owned; release with pf_tls_response_free
    size_t body_len;
    char *headers; ///< the final response's raw header lines, not NUL-terminated
    size_t headers_len;
} pf_tls_response;

/// One request. Unless skip_pinning, the server's chain must pass OpenSSL's verification and
/// contain a pinned key, the hostname must match, and TLS 1.3 is the floor; a request that ends
/// without the pin check having passed is PF_TLS_UNTRUSTED. Redirects are never followed (a 3xx
/// comes back as the response). Fills `response` only on PF_TLS_OK.
pf_tls_status pf_tls_send(const pf_tls_request *request, pf_tls_response *response);
void pf_tls_response_free(pf_tls_response *response);

/// The pin check pf_tls_send runs, offline, for tests: `certs[0]` is the leaf, the rest are
/// intermediates as a server would send them. `anchor` (DER, or NULL for none) is the only trust
/// anchor. Verified for `host` at `verify_time` (Unix seconds). Returns 1 if trusted and pinned.
int pf_tls_verify_chain(const uint8_t *const *certs, const size_t *cert_lens, size_t cert_count,
                        const uint8_t *anchor, size_t anchor_len, const char *host,
                        int64_t verify_time, const uint8_t *pins, size_t pin_count);

/// SHA-256 of `data` into `out` (32 bytes). Returns 1, or 0 on bad input.
int pf_sha256(const uint8_t *data, size_t len, uint8_t *out);

/// HMAC with `alg` 1 (SHA-1), 256 or 512. Returns the MAC's length, or 0 on bad input. `out_cap`
/// must be at least 64.
size_t pf_hmac(int alg, const uint8_t *key, size_t key_len, const uint8_t *message,
               size_t message_len, uint8_t *out, size_t out_cap);

#endif
