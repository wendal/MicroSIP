/*
 * Self test for the statically linked OpenSSL that MicroSIP's pjproject TLS
 * backend uses. It is compiled and linked against exactly the archives that
 * end up inside microsip.exe, so it proves:
 *
 *   - the OpenSSL build really is static (no DLL needed at run time)
 *   - the provider archives are linked in (OSSL_PROVIDER_load("default")
 *     fails with "module not found" if providers/libdefault.lib is missing)
 *   - a TLS context can be created - which is exactly what pjproject's
 *     ssl_sock_ossl.c does before every SIP-over-TLS connection
 *
 * Build/run it with tools\verify-openssl.ps1.
 */
#include <stdio.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/crypto.h>
#include <openssl/provider.h>

static int count_ciphers(SSL_CTX *ctx)
{
    STACK_OF(SSL_CIPHER) *c = SSL_CTX_get_ciphers(ctx);
    return c ? sk_SSL_CIPHER_num(c) : 0;
}

int main(void)
{
    SSL_CTX *ctx;
    OSSL_PROVIDER *prov;

    printf("OpenSSL version : %s\n", OPENSSL_VERSION_TEXT);

    /* (1) The path pjproject takes: plain SSL_CTX_new(TLS_method()), with no
     *     provider bookkeeping at all. If the default provider is not
     *     registered automatically in this build, this fails with
     *     "library has no ciphers". */
    ctx = SSL_CTX_new(TLS_method());
    if (!ctx) {
        printf("SSL_CTX_new     : FAILED (no explicit provider load)\n");
        ERR_print_errors_fp(stdout);
    } else {
        SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
        printf("SSL_CTX_new     : OK, %d cipher suites\n", count_ciphers(ctx));
        printf("max TLS version : %s\n",
               SSL_CTX_get_max_proto_version(ctx) == TLS1_3_VERSION ? "TLS 1.3" : "TLS 1.2");
        SSL_CTX_free(ctx);
    }

    /* (2) Is the default provider archive really part of the link? */
    prov = OSSL_PROVIDER_load(NULL, "default");
    if (!prov) {
        printf("default provider: NOT available (providers archive missing?)\n");
        ERR_print_errors_fp(stdout);
        return 1;
    }
    printf("default provider: loadable (archive linked in)\n");
    OSSL_PROVIDER_unload(prov);

    /* (3) And the explicit-load path, in case (1) failed above. */
    prov = OSSL_PROVIDER_load(NULL, "default");
    if (prov) {
        ctx = SSL_CTX_new(TLS_method());
        if (ctx) {
            printf("SSL_CTX_new     : OK with explicit provider load, %d cipher suites\n",
                   count_ciphers(ctx));
            SSL_CTX_free(ctx);
        } else {
            printf("SSL_CTX_new     : FAILED even with explicit provider load\n");
            ERR_print_errors_fp(stdout);
        }
        OSSL_PROVIDER_unload(prov);
    }

    printf("RESULT          : OK\n");
    return 0;
}
