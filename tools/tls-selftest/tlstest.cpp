/*
 * End-to-end TLS check for the locally built x64 pjproject.
 *
 * It links against exactly the same static pjproject library (and therefore
 * the same OpenSSL archives) that MicroSIP links against, and asks pjsua to
 * create a real SIP-over-TLS transport. Creating that transport is what
 * builds the OpenSSL SSL_CTX inside pjlib's ssl_sock_ossl.c, so a failure
 * here means the TLS backend is not actually usable.
 *
 * Build/run it with tools\verify-tls.ps1.
 */
#include <pjsua2.hpp>
#include <cstdio>

int main()
{
    pj::Endpoint ep;
    int rc = 0;

    ep.libCreate();

    try {
        pj::TransportConfig tcfg;
        tcfg.port = 5061;

        pj::TransportId id = ep.transportCreate(PJSIP_TRANSPORT_TLS, tcfg);
        pj::TransportInfo info = ep.transportGetInfo(id);

        printf("TLS transport   : created (id=%d)\n", (int)id);
        printf("type            : %s\n", info.typeName.c_str());
        printf("info            : %s\n", info.info.c_str());
    } catch (pj::Error &e) {
        printf("TLS transport   : FAILED\n");
        printf("  status        : %d\n", e.status);
        printf("  title         : %s\n", e.title.c_str());
        printf("  reason        : %s\n", e.reason.c_str());
        printf("  info          : %s\n", e.info().c_str());
        rc = 1;
    }

    ep.libDestroy();

    printf("RESULT          : %s\n", rc ? "FAILED" : "OK");
    return rc;
}
