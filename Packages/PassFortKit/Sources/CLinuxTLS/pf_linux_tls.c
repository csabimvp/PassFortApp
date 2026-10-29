#include "pf_linux_tls.h"

#if defined(__linux__)

#include <curl/curl.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/sha.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/x509_vfy.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

// MARK: - Cancellation

struct pf_tls_cancel {
    atomic_int set;
};

pf_tls_cancel *pf_tls_cancel_new(void) {
    pf_tls_cancel *cancel = malloc(sizeof *cancel);
    if (cancel)
        atomic_init(&cancel->set, 0);
    return cancel;
}

void pf_tls_cancel_set(pf_tls_cancel *cancel) {
    if (cancel)
        atomic_store(&cancel->set, 1);
}

void pf_tls_cancel_free(pf_tls_cancel *cancel) { free(cancel); }

// MARK: - The pin check

typedef struct {
    const uint8_t *pins;
    size_t pin_count;
    int passed; // set once the verified chain contained a pinned key
    int failed; // set when the chain failed verification or matched no pin
} pin_check;

static int spki_sha256(X509 *cert, uint8_t out[32]) {
    unsigned char *der = NULL;
    int len = i2d_X509_PUBKEY(X509_get_X509_PUBKEY(cert), &der);
    if (len <= 0)
        return 0;
    int ok = SHA256(der, (size_t)len, out) != NULL;
    OPENSSL_free(der);
    return ok;
}

static int chain_has_pin(STACK_OF(X509) * chain, const uint8_t *pins, size_t pin_count) {
    if (!chain || !pins || pin_count == 0) // an empty pin set trusts nothing
        return 0;
    for (int i = 0; i < sk_X509_num(chain); i++) {
        uint8_t hash[32];
        if (!spki_sha256(sk_X509_value(chain, i), hash))
            continue;
        for (size_t j = 0; j < pin_count; j++)
            if (memcmp(hash, pins + 32 * j, 32) == 0)
                return 1;
    }
    return 0;
}

/// Replaces OpenSSL's chain verification: run it unchanged first (anchors, validity, purpose, the
/// hostname when one is set), then require a pinned key anywhere in the verified chain, root
/// included -- what PinnedTransport.evaluate does with SecTrust on the Mac.
static int verify_with_pins(X509_STORE_CTX *store, void *arg) {
    pin_check *check = arg;
    if (X509_verify_cert(store) == 1 &&
        chain_has_pin(X509_STORE_CTX_get0_chain(store), check->pins, check->pin_count)) {
        check->passed = 1;
        return 1;
    }
    check->failed = 1;
    if (X509_STORE_CTX_get_error(store) == X509_V_OK)
        X509_STORE_CTX_set_error(store, X509_V_ERR_APPLICATION_VERIFICATION);
    return 0;
}

static CURLcode install_pin_check(CURL *curl, void *ssl_ctx, void *arg) {
    (void)curl;
    SSL_CTX_set_cert_verify_callback((SSL_CTX *)ssl_ctx, verify_with_pins, arg);
    return CURLE_OK;
}

// MARK: - Buffers

typedef struct {
    uint8_t *data;
    size_t len;
    size_t cap;
    size_t *total; // headers and body together, against PF_TLS_MAX_RESPONSE
    int too_large;
} buffer;

static int buffer_append(buffer *b, const void *bytes, size_t n) {
    if (n > PF_TLS_MAX_RESPONSE - *b->total) {
        b->too_large = 1;
        return 0;
    }
    if (n > b->cap - b->len) {
        size_t cap = b->cap ? b->cap : 4096;
        while (cap - b->len < n)
            cap *= 2;
        uint8_t *grown = realloc(b->data, cap);
        if (!grown)
            return 0;
        b->data = grown;
        b->cap = cap;
    }
    memcpy(b->data + b->len, bytes, n);
    b->len += n;
    *b->total += n;
    return 1;
}

static size_t on_body(char *bytes, size_t size, size_t count, void *arg) {
    size_t n = size * count; // libcurl passes size 1
    return buffer_append(arg, bytes, n) ? n : 0;
}

static size_t on_header(char *bytes, size_t size, size_t count, void *arg) {
    buffer *b = arg;
    size_t n = size * count;
    if (n >= 5 && memcmp(bytes, "HTTP/", 5) == 0) { // a new response after a 1xx: keep the last
        *b->total -= b->len;
        b->len = 0;
    }
    return buffer_append(b, bytes, n) ? n : 0;
}

static int on_progress(void *arg, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal,
                       curl_off_t ulnow) {
    (void)dltotal;
    (void)dlnow;
    (void)ultotal;
    (void)ulnow;
    pf_tls_cancel *cancel = arg;
    return cancel && atomic_load(&cancel->set) ? 1 : 0; // non-zero aborts the transfer
}

// MARK: - The request

static pthread_once_t curl_once = PTHREAD_ONCE_INIT;
static CURLcode curl_init_result = CURLE_FAILED_INIT;

static void init_curl(void) { curl_init_result = curl_global_init(CURL_GLOBAL_DEFAULT); }

/// libcurl must be on OpenSSL for the verify callback to mean anything.
static int curl_uses_openssl(void) {
    const curl_version_info_data *info = curl_version_info(CURLVERSION_NOW);
    return info && info->ssl_version && strncmp(info->ssl_version, "OpenSSL/", 8) == 0;
}

static int valid_request(const pf_tls_request *rq) {
    if (!rq->method || !rq->url || (rq->header_count && !rq->headers) ||
        (rq->has_body && rq->body_len && !rq->body) || rq->timeout_seconds <= 0)
        return 0;
    // Pinned means https: refuse before sending, rather than notice afterwards that the pin check
    // never ran (redirects are off, so the scheme can't change on the way).
    if (!rq->skip_pinning &&
        (rq->pin_count == 0 || !rq->pins || strncasecmp(rq->url, "https://", 8) != 0))
        return 0;
    for (size_t i = 0; i < rq->header_count; i++)
        if (!rq->headers[i] || strpbrk(rq->headers[i], "\r\n"))
            return 0;
    return 1;
}

static pf_tls_status status_for(CURLcode rc, const pin_check *check, const buffer *body,
                                const buffer *headers) {
    if (check->failed)
        return PF_TLS_UNTRUSTED;
    switch (rc) {
    case CURLE_ABORTED_BY_CALLBACK:
        return PF_TLS_CANCELLED;
    case CURLE_WRITE_ERROR:
        return body->too_large || headers->too_large ? PF_TLS_TOO_LARGE : PF_TLS_INTERNAL;
    case CURLE_PEER_FAILED_VERIFICATION:
    case CURLE_SSL_CACERT_BADFILE:
    case CURLE_SSL_ISSUER_ERROR:
    case CURLE_SSL_PINNEDPUBKEYNOTMATCH:
        return PF_TLS_UNTRUSTED;
    case CURLE_UNSUPPORTED_PROTOCOL:
    case CURLE_URL_MALFORMAT:
        return PF_TLS_BAD_INPUT;
    case CURLE_OUT_OF_MEMORY:
        return PF_TLS_INTERNAL;
    default:
        return PF_TLS_OFFLINE;
    }
}

pf_tls_status pf_tls_send(const pf_tls_request *rq, pf_tls_response *response) {
    if (!rq || !response || !valid_request(rq))
        return PF_TLS_BAD_INPUT;
    memset(response, 0, sizeof *response);
    pthread_once(&curl_once, init_curl);
    if (curl_init_result != CURLE_OK)
        return PF_TLS_INTERNAL;
    if (!rq->skip_pinning && !curl_uses_openssl())
        return PF_TLS_UNSUPPORTED;

    CURL *curl = curl_easy_init();
    if (!curl)
        return PF_TLS_INTERNAL;

    size_t total = 0;
    buffer body = {.total = &total};
    buffer headers = {.total = &total};
    pin_check check = {.pins = rq->pins, .pin_count = rq->pin_count};
    struct curl_slist *lines = NULL;
    pf_tls_status status = PF_TLS_INTERNAL;
    int ok = 1;

    for (size_t i = 0; ok && i < rq->header_count; i++) {
        struct curl_slist *next = curl_slist_append(lines, rq->headers[i]);
        ok = next != NULL;
        lines = next ? next : lines;
    }
    if (ok) { // one round trip, as URLSession: no "Expect: 100-continue" before a body
        struct curl_slist *next = curl_slist_append(lines, "Expect:");
        ok = next != NULL;
        lines = next ? next : lines;
    }

#define SET(option, value) (ok = ok && curl_easy_setopt(curl, option, value) == CURLE_OK)
    SET(CURLOPT_URL, rq->url);
    SET(CURLOPT_CUSTOMREQUEST, rq->method);
    if (rq->has_body) {
        SET(CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)rq->body_len);
        SET(CURLOPT_POSTFIELDS, rq->body_len ? (const char *)rq->body : "");
    }
    SET(CURLOPT_HTTPHEADER, lines);
    SET(CURLOPT_FOLLOWLOCATION, 0L);
    SET(CURLOPT_NOSIGNAL, 1L);
    SET(CURLOPT_CONNECTTIMEOUT, rq->timeout_seconds);
    SET(CURLOPT_LOW_SPEED_LIMIT, 1L);
    SET(CURLOPT_LOW_SPEED_TIME, rq->timeout_seconds);
    SET(CURLOPT_SSL_VERIFYPEER, 1L);
    SET(CURLOPT_SSL_VERIFYHOST, 2L);
    SET(CURLOPT_SSLVERSION, (long)CURL_SSLVERSION_TLSv1_3);
    SET(CURLOPT_SSL_SESSIONID_CACHE, 0L); // a resumed session would skip the verify callback
    SET(CURLOPT_WRITEFUNCTION, on_body);
    SET(CURLOPT_WRITEDATA, &body);
    SET(CURLOPT_HEADERFUNCTION, on_header);
    SET(CURLOPT_HEADERDATA, &headers);
    SET(CURLOPT_NOPROGRESS, 0L);
    SET(CURLOPT_XFERINFOFUNCTION, on_progress);
    SET(CURLOPT_XFERINFODATA, rq->cancel);
    if (ok && !rq->skip_pinning) {
        SET(CURLOPT_SSL_CTX_DATA, &check);
        if (ok && curl_easy_setopt(curl, CURLOPT_SSL_CTX_FUNCTION, install_pin_check) != CURLE_OK) {
            status = PF_TLS_UNSUPPORTED; // fail closed: never send unpinned
            ok = 0;
        }
    }
#undef SET

    if (ok) {
        CURLcode rc = curl_easy_perform(curl);
        if (rc != CURLE_OK) {
            status = status_for(rc, &check, &body, &headers);
        } else if (!rq->skip_pinning && !check.passed) {
            status = PF_TLS_UNTRUSTED; // e.g. plain http: the pin check never ran
        } else if (curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response->status) == CURLE_OK) {
            response->body = body.data;
            response->body_len = body.len;
            response->headers = (char *)headers.data;
            response->headers_len = headers.len;
            body.data = NULL;
            headers.data = NULL;
            status = PF_TLS_OK;
        }
    }

    free(body.data);
    free(headers.data);
    curl_slist_free_all(lines);
    curl_easy_cleanup(curl);
    if (status != PF_TLS_OK)
        memset(response, 0, sizeof *response);
    return status;
}

void pf_tls_response_free(pf_tls_response *response) {
    if (!response)
        return;
    free(response->body);
    free(response->headers);
    memset(response, 0, sizeof *response);
}

// MARK: - The offline pin check

static X509 *parse_der(const uint8_t *der, size_t len) {
    if (!der || len == 0 || len > 1024 * 1024)
        return NULL;
    const unsigned char *cursor = der;
    X509 *cert = d2i_X509(NULL, &cursor, (long)len);
    if (cert && cursor != der + len) { // trailing bytes: not one certificate
        X509_free(cert);
        return NULL;
    }
    return cert;
}

int pf_tls_verify_chain(const uint8_t *const *certs, const size_t *cert_lens, size_t cert_count,
                        const uint8_t *anchor, size_t anchor_len, const char *host,
                        int64_t verify_time, const uint8_t *pins, size_t pin_count) {
    if (!certs || !cert_lens || cert_count == 0 || !host || (pin_count && !pins))
        return 0;
    int trusted = 0;
    X509 *leaf = parse_der(certs[0], cert_lens[0]);
    X509 *root = anchor ? parse_der(anchor, anchor_len) : NULL;
    STACK_OF(X509) *intermediates = sk_X509_new_null();
    X509_STORE *store = X509_STORE_new();
    X509_STORE_CTX *ctx = X509_STORE_CTX_new();
    if (!leaf || (anchor && !root) || !intermediates || !store || !ctx)
        goto done;
    if (root && X509_STORE_add_cert(store, root) != 1)
        goto done;
    for (size_t i = 1; i < cert_count; i++) {
        X509 *cert = parse_der(certs[i], cert_lens[i]);
        if (!cert || !sk_X509_push(intermediates, cert)) {
            X509_free(cert);
            goto done;
        }
    }
    if (X509_STORE_CTX_init(ctx, store, leaf, intermediates) != 1 ||
        X509_STORE_CTX_set_default(ctx, "ssl_server") != 1) // what libssl sets for a client
        goto done;
    X509_VERIFY_PARAM *param = X509_STORE_CTX_get0_param(ctx);
    X509_VERIFY_PARAM_set_time(param, (time_t)verify_time);
    if (X509_VERIFY_PARAM_set1_host(param, host, 0) != 1)
        goto done;
    pin_check check = {.pins = pins, .pin_count = pin_count};
    trusted = verify_with_pins(ctx, &check);

done:
    X509_STORE_CTX_free(ctx);
    X509_STORE_free(store);
    sk_X509_pop_free(intermediates, X509_free);
    X509_free(root);
    X509_free(leaf);
    return trusted;
}

// MARK: - SHA-256 and HMAC

int pf_sha256(const uint8_t *data, size_t len, uint8_t *out) {
    static const uint8_t empty[1] = {0};
    if ((!data && len) || !out)
        return 0;
    return SHA256(data ? data : empty, len, out) != NULL;
}

size_t pf_hmac(int alg, const uint8_t *key, size_t key_len, const uint8_t *message,
               size_t message_len, uint8_t *out, size_t out_cap) {
    static const uint8_t empty[1] = {0};
    const EVP_MD *md = alg == 1     ? EVP_sha1()
                       : alg == 256 ? EVP_sha256()
                       : alg == 512 ? EVP_sha512()
                                    : NULL;
    if (!md || (!key && key_len) || (!message && message_len) || !out ||
        out_cap < EVP_MAX_MD_SIZE || key_len > INT32_MAX)
        return 0;
    unsigned int len = 0;
    if (!HMAC(md, key ? key : empty, (int)key_len, message ? message : empty, message_len, out,
              &len))
        return 0;
    return len;
}

#else

// Apple platforms: URLSession, SecTrust and CryptoKit. Keeps the translation unit non-empty.
typedef int pf_linux_tls_unused;

#endif
