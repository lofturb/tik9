/*
 * prueba_vector.c -- comparación del port en C con el oráculo de Python.
 *
 * Usa entradas fijas (tiempo, nonces y claves de 12 palabras) para que la
 * salida sea reproducible, y escribe por stdout exactamente el mismo formato
 * que genera prototipo/vector_referencia.py.  La comparación la hace
 * prototipo/comparar_vectores.py, que ejecuta ambos y difunde las líneas.
 *
 * Compilar (TCC, 32 bits, como la app):
 *     tcc -o prueba_vector.exe prueba_vector.c ..\TTSignaCore.c
 */

#include "../TTSignaCore.h"
#include <stdio.h>
#include <string.h>

#define UA \
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0"

static const uint32_t CLAVE1[TT_SIGNA_KEY_WORDS] = {
    305419896u, 2596069104u, 19088743u, 2309737967u, 3735928559u, 3405691582u,
    4275878552u, 1431655765u, 2863311530u, 4294967295u, 1u, 0u
};
static const uint32_t CLAVE2[TT_SIGNA_KEY_WORDS] = {
    16u, 32u, 48u, 64u, 80u, 96u, 112u, 128u, 144u, 160u, 176u, 192u
};

static const uint32_t TS = 1700000000u;
static const uint32_t NONCE = 123456789u;
static const uint32_t NONCE2 = 3600000000u;

/* ---------------------------------------------------------------- casos -- */

static const char *const K0[] = {
    "aid", "app_language", "browser_version", "device_id", "itemId",
    "os", "region", "screen_height"
};
static const char *const V0[] = {
    "1988", "en-US",
    "5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0",
    "7123456789012345678", "7106594312292453675", "windows", "US", "1080"
};

static const char *const K1[] = { "cursor", "count", "secUid" };
static const char *const V1[] = { "0", "16", "MS4wLjABAAAA-not-a-real-sec-uid" };

static const char *const K2[] = { "q", "unicode", "plus", "percent" };
static const char *const V2[] = {
    "a b\"c<d>e`f#g/h:i,j(k)l", "caf\xc3\xa9 \xe4\xb8\xad\xe6\x96\x87",
    "a+b=c&d", "100%"
};

static void emite_firma(const char *nombre, const char *const k[], const char *const v[],
                        int n, const char *ms) {
    char salida[8192];
    int r = tt_firmar_determinista(k, v, n, UA, ms, TS, NONCE, NONCE2,
                                   CLAVE1, CLAVE2, salida, sizeof salida);
    if (r < 0) { printf("firma %s = ERROR\n", nombre); return; }
    printf("firma %s len = %d\n", nombre, r);
    printf("firma %s = %s\n", nombre, salida);
}

int main(void) {
    char hex[33];

    tt_md5_hex("", 0, hex);
    printf("md5 vacio    = %s\n", hex);
    tt_md5_hex("abc", 3, hex);
    printf("md5 abc      = %s\n", hex);
    tt_md5_hex("The quick brown fox jumps over the lazy dog", 43, hex);
    printf("md5 pangrama = %s\n", hex);
    tt_md5_hex("0123456789012345678901234567890123456789012345678901234567890123456789",
               70, hex);
    printf("md5 largo    = %s\n", hex);

    printf("hash vacio   = %u\n", tt_hash_state(""));
    printf("hash abc     = %u\n", tt_hash_state("abc"));
    printf("hash ua      = %u\n", tt_hash_state(UA));

    emite_firma("0", K0, V0, 8, "");
    emite_firma("1", K0, V0, 8, "Fk9xQ2mN7pL4vR8tY1wZ3bC6dE0gH5jK");
    emite_firma("2", K1, V1, 3, "");
    emite_firma("3", K2, V2, 4, "");
    return 0;
}
