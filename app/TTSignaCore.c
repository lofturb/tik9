/*
 * TTSignaCore.c -- firma web de TikTok (X-Dynosaur + X-Gnarly), en C puro.
 *
 * Portado a C de la implementacion de referencia de f2 (xgnarly.py,
 * Apache-2.0), que se comprobo en vivo contra la API real de TikTok.  Todas
 * las constantes (alfabeto, estado inicial de ChaCha, FNV, versiones del SDK,
 * codigos de entorno) estan copiadas de esa referencia y documentadas.
 *
 * Cuidado con dos detalles que no son "estarndar" y que hay que respetar o la
 * firma deja de valer:
 *   1. La funcion de ronda no es ChaCha20: el numero de rondas va de 5 a 20 y
 *      puede quedar impar (sale tras las columnas).  Ademas la tercera ronda
 *      diagonal es (2, 7, 12, 13) y no (2, 7, 8, 13).
 *   2. El alfabeto base64 es propio, y el relleno es '='.
 */

#include "TTSignaCore.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#if !defined(_WIN32)
#include <sys/time.h>   /* ausente en la compilacion de pruebas con TCC */
#endif

#define MASK32 0xFFFFFFFFu

/* ---------------------------- constantes ------------------------------- */

static const char ALFABETO[] =
    "u09tbS3UvgDEe6r-ZVMXzLpsAohTn7mdINQlW412GqBjfYiyk8JORCF5/xKHwacP";

static const uint32_t CHACHA_INIT[4] = {
    1196819126u, 600974999u, 3863347763u, 1451689750u
};

#define FNV_OFFSET   2166136260u
#define FNV_PRIME    16777619u
#define SDK_VERSION  "5.3.2"
#define SCM_VERSION  "2.0.0.561"
#define ENV_CODE     65
#define UB_CODE      8
#define VM_STATE_HASH 0xC46CE353u
#define CANVAS_HASH  "-1"
#define PAGE_VALOR   "www.tiktok.com/"
#define TEXTO_WEBGL  "0"
#define TEXTO_COMP   "0"
#define TEXTO_DEV    "0"
#define ENVELOPE_TAG 0x4B
#define SECUENCIA    1

typedef struct {
    int xor_base, add_base, pre_xor, rotate, post_add;
} Codificador;

static const Codificador ENC_A = { 103, 1, -1, 2, 1 };
static const Codificador ENC_B = { 102, 0, 165, 1, 0 };

/* ------------------------------- MD5 ----------------------------------- */

static void md5_bloque(uint32_t h[4], const uint8_t bloque[64]) {
    static const uint32_t K[64] = {
        0xd76aa478u,0xe8c7b756u,0x242070dbu,0xc1bdceeeu,0xf57c0fafu,0x4787c62au,
        0xa8304613u,0xfd469501u,0x698098d8u,0x8b44f7afu,0xffff5bb1u,0x895cd7beu,
        0x6b901122u,0xfd987193u,0xa679438eu,0x49b40821u,0xf61e2562u,0xc040b340u,
        0x265e5a51u,0xe9b6c7aau,0xd62f105du,0x02441453u,0xd8a1e681u,0xe7d3fbc8u,
        0x21e1cde6u,0xc33707d6u,0xf4d50d87u,0x455a14edu,0xa9e3e905u,0xfcefa3f8u,
        0x676f02d9u,0x8d2a4c8au,0xfffa3942u,0x8771f681u,0x6d9d6122u,0xfde5380cu,
        0xa4beea44u,0x4bdecfa9u,0xf6bb4b60u,0xbebfbc70u,0x289b7ec6u,0xeaa127fau,
        0xd4ef3085u,0x04881d05u,0xd9d4d039u,0xe6db99e5u,0x1fa27cf8u,0xc4ac5665u,
        0xf4292244u,0x432aff97u,0xab9423a7u,0xfc93a039u,0x655b59c3u,0x8f0ccc92u,
        0xffeff47du,0x85845dd1u,0x6fa87e4fu,0xfe2ce6e0u,0xa3014314u,0x4e0811a1u,
        0xf7537e82u,0xbd3af235u,0x2ad7d2bbu,0xeb86d391u
    };
    static const int S[64] = {
        7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
        5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
        4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
        6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21
    };
    uint32_t M[16];
    for (int i = 0; i < 16; i++) {
        M[i] = (uint32_t)bloque[i*4] | ((uint32_t)bloque[i*4+1] << 8) |
               ((uint32_t)bloque[i*4+2] << 16) | ((uint32_t)bloque[i*4+3] << 24);
    }
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
    for (int i = 0; i < 64; i++) {
        uint32_t f; int g;
        if (i < 16)      { f = (b & c) | (~b & d); g = i; }
        else if (i < 32) { f = (d & b) | (~d & c); g = (5*i + 1) % 16; }
        else if (i < 48) { f = b ^ c ^ d;          g = (3*i + 5) % 16; }
        else             { f = c ^ (b | ~d);       g = (7*i) % 16; }
        uint32_t tmp = d; d = c; c = b;
        uint32_t x = a + f + K[i] + M[g];
        b = b + ((x << S[i]) | (x >> (32 - S[i])));
        a = tmp;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
}

void tt_md5_hex(const void *datos, size_t n, char salida[33]) {
    uint32_t h[4] = { 0x67452301u, 0xefcdab89u, 0x98badcfeu, 0x10325476u };
    const uint8_t *p = (const uint8_t *)datos;
    size_t i = 0;
    for (; i + 64 <= n; i += 64) md5_bloque(h, p + i);
    uint8_t buf[128];
    size_t r = n - i;
    memcpy(buf, p + i, r);
    buf[r] = 0x80;
    size_t total = (r + 1 + 8 <= 64) ? 64 : 128;
    memset(buf + r + 1, 0, total - 8 - (r + 1));
    uint64_t bits = (uint64_t)n * 8u;
    for (int k = 0; k < 8; k++) buf[total - 8 + k] = (uint8_t)((bits >> (8*k)) & 0xFF);
    for (size_t b = 0; b < total; b += 64) md5_bloque(h, buf + b);
    static const char hex[] = "0123456789abcdef";
    for (int k = 0; k < 4; k++) {
        for (int j = 0; j < 4; j++) {
            int v = (int)((h[k] >> (8*j)) & 0xFF);
            salida[(k*4 + j)*2]     = hex[(v >> 4) & 0xF];
            salida[(k*4 + j)*2 + 1] = hex[v & 0xF];
        }
    }
    salida[32] = 0;
}

/* --------------------------- utilidades -------------------------------- */

/* El User-Agent por defecto, para que Objective-C no lo repita. */
const char *tt_ua_por_defecto(void) {
    return TT_SIGNA_UA_POR_DEFECTO;
}

uint32_t tt_hash_state(const char *texto) {
    uint32_t valor = FNV_OFFSET;
    for (const unsigned char *p = (const unsigned char *)texto; *p; ++p) {
        uint32_t paso = ((valor ^ (uint32_t)*p) * FNV_PRIME) & MASK32;
        valor = (paso + ((paso * 32u) & MASK32)) & MASK32;
    }
    return valor;
}

static size_t codificar_bytes(const char *texto, Codificador e, uint8_t *salida) {
    size_t len = strlen(texto);
    size_t tam = len + 2;
    if (tam < 6) tam = 6;
    for (size_t i = 0; i < len; ++i) {
        uint32_t v = ((uint32_t)(uint8_t)texto[i] ^ (uint32_t)(e.xor_base + (int)i)) & MASK32;
        v = (v + (uint32_t)e.add_base + (uint32_t)(170 & (int)i)) % 256u;
        if (e.pre_xor >= 0) v ^= (uint32_t)e.pre_xor;
        v = ((v << e.rotate) | (v >> (8 - e.rotate))) & 0xFFu;
        salida[i] = (uint8_t)(((v ^ 187u) + (uint32_t)e.post_add) % 256u);
    }
    for (size_t i = len; i < tam - 2; ++i) salida[i] = (uint8_t)((221u + i) & 0xFFu);
    salida[tam - 2] = 0;
    salida[tam - 1] = (uint8_t)len;
    return tam;
}

static void be32(uint32_t v, uint8_t *o) {
    o[0] = (uint8_t)(v >> 24); o[1] = (uint8_t)(v >> 16);
    o[2] = (uint8_t)(v >> 8);  o[3] = (uint8_t)v;
}
static void be16(uint32_t v, uint8_t *o) {
    o[0] = (uint8_t)(v >> 8); o[1] = (uint8_t)v;
}

static uint32_t mezclar(uint32_t ts, uint32_t nonce, uint32_t env) {
    uint32_t plegado = ((ts >> 16) ^ (nonce >> 16) ^ ts ^ nonce) & 0xFFFFu;
    return plegado | (env << 16);
}

typedef struct { int es_texto; uint32_t num; const char *txt; } Valor;

static uint32_t suma_control(const Valor *v, int n, int modo) {
    uint32_t acc = MASK32;
    for (int i = 0; i < n; i++) {
        uint32_t numero;
        if (v[i].es_texto) {
            if (modo == 1) numero = 0;
            else {
                const unsigned char *p = (const unsigned char *)v[i].txt;
                size_t L = strlen(v[i].txt);
                if (L > 4) L = 4;
                numero = 0;
                for (size_t k = 0; k < L; k++) numero = (numero << 8) | p[k];
            }
        } else numero = v[i].num;
        acc ^= numero & MASK32;
    }
    return acc & MASK32;
}

typedef struct { uint8_t clave; uint8_t bytes[80]; uint8_t largo; } Campo;

static size_t empaquetar(Campo *c, int n, int con_cuenta, uint8_t *salida) {
    for (int i = 1; i < n; i++) { /* orden por clave, estable e simple */
        Campo t = c[i]; int j = i - 1;
        while (j >= 0 && c[j].clave > t.clave) { c[j+1] = c[j]; j--; }
        c[j+1] = t;
    }
    size_t pos = 0;
    if (con_cuenta) salida[pos++] = (uint8_t)n;
    for (int i = 0; i < n; i++) {
        salida[pos++] = c[i].clave;
        salida[pos++] = 0;
        salida[pos++] = c[i].largo;
        memcpy(salida + pos, c[i].bytes, c[i].largo);
        pos += c[i].largo;
    }
    return pos;
}

/* ---------------------------- ChaCha variante -------------------------- */

static void ronda(uint32_t *s, int a, int b, int c, int d) {
    s[a] += s[b]; s[d] ^= s[a]; s[d] = (s[d] << 16) | (s[d] >> 16);
    s[c] += s[d]; s[b] ^= s[c]; s[b] = (s[b] << 12) | (s[b] >> 20);
    s[a] += s[b]; s[d] ^= s[a]; s[d] = (s[d] << 8)  | (s[d] >> 24);
    s[c] += s[d]; s[b] ^= s[c]; s[b] = (s[b] << 7)  | (s[b] >> 25);
}

static void flujo(const uint32_t *estado, int rondas, uint32_t *salida) {
    uint32_t w[16];
    memcpy(w, estado, sizeof(w));
    int hechas = 0;
    while (hechas < rondas) {
        ronda(w, 0, 4, 8, 12); ronda(w, 1, 5, 9, 13);
        ronda(w, 2, 6, 10, 14); ronda(w, 3, 7, 11, 15);
        hechas++;
        if (hechas >= rondas) break;
        ronda(w, 0, 5, 10, 15); ronda(w, 1, 6, 11, 12);
        ronda(w, 2, 7, 12, 13); ronda(w, 3, 4, 13, 14); /* el 12 doble es del SDK */
        hechas++;
    }
    for (int i = 0; i < 16; i++) salida[i] = w[i] + estado[i];
}

static void criptar(const uint32_t *clave, int rondas,
                    const uint8_t *carga, size_t largo, uint8_t *salida) {
    uint32_t estado[16];
    estado[0] = CHACHA_INIT[0]; estado[1] = CHACHA_INIT[1];
    estado[2] = CHACHA_INIT[2]; estado[3] = CHACHA_INIT[3];
    for (int i = 0; i < TT_SIGNA_KEY_WORDS; i++) estado[4 + i] = clave[i];
    size_t palabras = (largo + 3) / 4;
    uint32_t *w = (uint32_t *)calloc(palabras + 1, sizeof(uint32_t));
    for (size_t i = 0; i < palabras; i++) {
        uint32_t v = 0;
        for (int k = 0; k < 4; k++) {
            size_t idx = 4*i + (size_t)k;
            if (idx < largo) v |= (uint32_t)carga[idx] << (8*k);
        }
        w[i] = v;
    }
    size_t off = 0;
    uint32_t bloque[16];
    while (off + 16 < palabras) {
        flujo(estado, rondas, bloque);
        estado[12] += 1;
        for (int i = 0; i < 16; i++) w[off + i] ^= bloque[i];
        off += 16;
    }
    flujo(estado, rondas, bloque);
    for (size_t i = 0; i < palabras - off; i++) w[off + i] ^= bloque[i];
    for (size_t i = 0; i < palabras; i++) {
        salida[4*i + 0] = (uint8_t)(w[i] & 0xFF);
        salida[4*i + 1] = (uint8_t)((w[i] >> 8) & 0xFF);
        salida[4*i + 2] = (uint8_t)((w[i] >> 16) & 0xFF);
        salida[4*i + 3] = (uint8_t)((w[i] >> 24) & 0xFF);
    }
    free(w);
}

static size_t base64_propio(const uint8_t *d, size_t n, char *salida) {
    size_t o = 0, i = 0;
    while (i + 3 <= n) {
        uint32_t v = ((uint32_t)d[i] << 16) | ((uint32_t)d[i+1] << 8) | d[i+2];
        salida[o++] = ALFABETO[(v >> 18) & 63];
        salida[o++] = ALFABETO[(v >> 12) & 63];
        salida[o++] = ALFABETO[(v >> 6) & 63];
        salida[o++] = ALFABETO[v & 63];
        i += 3;
    }
    if (n - i == 1) {
        uint32_t v = (uint32_t)d[i] << 16;
        salida[o++] = ALFABETO[(v >> 18) & 63];
        salida[o++] = ALFABETO[(v >> 12) & 63];
        salida[o++] = '='; salida[o++] = '=';
    } else if (n - i == 2) {
        uint32_t v = ((uint32_t)d[i] << 16) | ((uint32_t)d[i+1] << 8);
        salida[o++] = ALFABETO[(v >> 18) & 63];
        salida[o++] = ALFABETO[(v >> 12) & 63];
        salida[o++] = ALFABETO[(v >> 6) & 63];
        salida[o++] = '=';
    }
    salida[o] = 0;
    return o;
}

static size_t sellar(const uint8_t *carga, size_t n, const uint32_t *clave, char *salida) {
    int rondas = 0;
    for (int i = 0; i < TT_SIGNA_KEY_WORDS; i++) rondas += (int)(clave[i] & 0xF);
    rondas = (rondas & 0xF) + 5;

    uint8_t *cifrado = (uint8_t *)malloc(n + 8);
    criptar(clave, rondas, carga, n, cifrado);

    uint8_t clave_bytes[TT_SIGNA_KEY_WORDS * 4];
    for (int i = 0; i < TT_SIGNA_KEY_WORDS; i++) {
        uint32_t w = clave[i];
        clave_bytes[4*i + 0] = (uint8_t)(w & 0xFF);
        clave_bytes[4*i + 1] = (uint8_t)((w >> 8) & 0xFF);
        clave_bytes[4*i + 2] = (uint8_t)((w >> 16) & 0xFF);
        clave_bytes[4*i + 3] = (uint8_t)((w >> 24) & 0xFF);
    }
    unsigned sk = 0;
    for (size_t i = 0; i < sizeof(clave_bytes); i++) sk += clave_bytes[i];
    unsigned sc = 0;
    for (size_t i = 0; i < n; i++) sc += cifrado[i];
    size_t pos = ((size_t)sk + sc) % (n + 1);

    uint8_t *bruto = (uint8_t *)malloc(1 + n + sizeof(clave_bytes));
    bruto[0] = ENVELOPE_TAG;
    memcpy(bruto + 1, cifrado, pos);
    memcpy(bruto + 1 + pos, clave_bytes, sizeof(clave_bytes));
    memcpy(bruto + 1 + pos + sizeof(clave_bytes), cifrado + pos, n - pos);

    size_t L = base64_propio(bruto, 1 + n + sizeof(clave_bytes), salida);
    free(bruto);
    free(cifrado);
    return L;
}

/* ------------------------- codificacion de consulta -------------------- */

static size_t escapar(const char *s, char *salida) {
    static const char hex[] = "0123456789ABCDEF";
    size_t o = 0;
    for (const unsigned char *p = (const unsigned char *)s; *p; ++p) {
        unsigned char c = *p;
        const char *rep = NULL;
        switch (c) {
            case ' ':  rep = "%20"; break;
            case '"':  rep = "%22"; break;
            case '<':  rep = "%3C"; break;
            case '>':  rep = "%3E"; break;
            case '`':  rep = "%60"; break;
            case '#':  rep = "%23"; break;
            default: break;
        }
        if (rep) { while (*rep) salida[o++] = *rep++; }
        else if (c > ' ' && c <= '~') salida[o++] = (char)c;
        else {
            salida[o++] = '%';
            salida[o++] = hex[(c >> 4) & 0xF];
            salida[o++] = hex[c & 0xF];
        }
    }
    salida[o] = 0;
    return o;
}

static size_t codificar_consulta(const char *const claves[], const char *const valores[],
                                 int n, char *salida) {
    size_t o = 0;
    for (int i = 0; i < n; i++) {
        if (i) salida[o++] = '&';
        o += escapar(claves[i], salida + o);
        salida[o++] = '=';
        o += escapar(valores[i], salida + o);
    }
    salida[o] = 0;
    return o;
}

/* ----------------------------- cargas ---------------------------------- */

static void anade_texto(Campo *c, int *n, uint8_t clave, const char *texto, Codificador e) {
    c[*n].clave = clave;
    c[*n].largo = (uint8_t)codificar_bytes(texto, e, c[*n].bytes);
    (*n)++;
}

static void anade_bytes(Campo *c, int *n, uint8_t clave, const uint8_t *datos, size_t largo) {
    c[*n].clave = clave;
    c[*n].largo = (uint8_t)largo;
    memcpy(c[*n].bytes, datos, largo);
    (*n)++;
}

/* 25 campos TLV de 0x20 a 0x38 (el informe de entorno) */
static size_t carga_dynosaur(const char *consulta, const char *ua,
                             uint32_t timestamp, uint32_t nonce, int secuencia,
                             uint8_t *salida) {
    Campo c[26];
    int n = 0;
    char tmp[32];
    uint8_t cuatro[4];

    anade_texto(c, &n, 0x21, "1", ENC_B);
    anade_texto(c, &n, 0x22, "1", ENC_B);
    anade_texto(c, &n, 0x23, "0", ENC_A);
    snprintf(tmp, sizeof tmp, "%u", mezclar(timestamp, nonce, ENV_CODE));
    anade_texto(c, &n, 0x24, tmp, ENC_A);
    snprintf(tmp, sizeof tmp, "%d", secuencia);
    anade_texto(c, &n, 0x25, tmp, ENC_A);
    snprintf(tmp, sizeof tmp, "%d", ENV_CODE);
    anade_texto(c, &n, 0x26, tmp, ENC_A);
    snprintf(tmp, sizeof tmp, "%u", timestamp);
    anade_texto(c, &n, 0x27, tmp, ENC_A);
    anade_texto(c, &n, 0x28, TEXTO_WEBGL, ENC_A);
    anade_texto(c, &n, 0x29, "0", ENC_A);
    anade_texto(c, &n, 0x2A, SDK_VERSION, ENC_A);
    be32(tt_hash_state(""), cuatro);            anade_bytes(c, &n, 0x2B, cuatro, 4);
    anade_texto(c, &n, 0x2C, CANVAS_HASH, ENC_A);
    anade_texto(c, &n, 0x2D, "0", ENC_A);
    be32(tt_hash_state(consulta), cuatro);      anade_bytes(c, &n, 0x2E, cuatro, 4);
    snprintf(tmp, sizeof tmp, "%d", secuencia);
    anade_texto(c, &n, 0x2F, tmp, ENC_A);
    be32(tt_hash_state(ua), cuatro);            anade_bytes(c, &n, 0x30, cuatro, 4);
    anade_texto(c, &n, 0x31, SCM_VERSION, ENC_A);
    anade_texto(c, &n, 0x32, TEXTO_COMP, ENC_A);
    anade_texto(c, &n, 0x33, TEXTO_DEV, ENC_A);
    snprintf(tmp, sizeof tmp, "%u", nonce);
    anade_texto(c, &n, 0x34, tmp, ENC_A);
    anade_texto(c, &n, 0x35, PAGE_VALOR, ENC_A);
    snprintf(tmp, sizeof tmp, "%d", UB_CODE);
    anade_texto(c, &n, 0x36, tmp, ENC_A);
    anade_texto(c, &n, 0x37, "0", ENC_A);
    be32(VM_STATE_HASH, cuatro);                anade_bytes(c, &n, 0x38, cuatro, 4);
    /* marcador del 0x20: cualquier cadena de un caracter vale, porque el
       segundo byte de un campo de un caracter es siempre el relleno */
    anade_texto(c, &n, 0x20, "0", ENC_A);

    uint32_t control = 0;
    for (int i = 0; i < n; i++) control ^= c[i].bytes[1];
    snprintf(tmp, sizeof tmp, "%u", control);
    c[n - 1].largo = (uint8_t)codificar_bytes(tmp, ENC_B, c[n - 1].bytes);

    return empaquetar(c, n, 0, salida);
}

/* 16 campos X-Gnarly */
static size_t carga_gnarly(const char *consulta_firmada, const char *ua,
                           const uint8_t *cuerpo, size_t cuerpo_len,
                           uint32_t timestamp, uint32_t nonce, uint32_t nonce2,
                           int secuencia, uint8_t *salida) {
    char q_md5[33], b_md5[33], a_md5[33];
    tt_md5_hex(consulta_firmada, strlen(consulta_firmada), q_md5);
    tt_md5_hex(cuerpo, cuerpo_len, b_md5);
    tt_md5_hex(ua, strlen(ua), a_md5);
    uint32_t mixed = mezclar(timestamp, nonce, ENV_CODE);

    Valor cubierto[17];
    cubierto[0]  = (Valor){ 0, 0, NULL };
    cubierto[1]  = (Valor){ 0, ENV_CODE, NULL };
    cubierto[2]  = (Valor){ 0, UB_CODE, NULL };
    cubierto[3]  = (Valor){ 1, 0, q_md5 };
    cubierto[4]  = (Valor){ 1, 0, b_md5 };
    cubierto[5]  = (Valor){ 1, 0, a_md5 };
    cubierto[6]  = (Valor){ 0, timestamp, NULL };
    cubierto[7]  = (Valor){ 0, 0, NULL };
    cubierto[8]  = (Valor){ 0, nonce, NULL };
    cubierto[9]  = (Valor){ 1, 0, SDK_VERSION };
    cubierto[10] = (Valor){ 1, 0, SCM_VERSION };
    cubierto[11] = (Valor){ 0, SECUENCIA, NULL };
    cubierto[12] = (Valor){ 0, (uint32_t)secuencia, NULL };
    cubierto[13] = (Valor){ 0, (uint32_t)secuencia, NULL };
    cubierto[14] = (Valor){ 0, mixed, NULL };
    cubierto[15] = (Valor){ 0, nonce2, NULL };
    uint32_t primero = suma_control(cubierto, 16, 2);
    cubierto[16] = (Valor){ 0, primero, NULL };
    uint32_t segundo = suma_control(cubierto, 17, 1);

    Campo c[16];
    int n = 0;
    uint8_t x[4];

    be32(segundo, x);                      anade_bytes(c, &n, 0x00, x, 4);
    be16(ENV_CODE, x);                     anade_bytes(c, &n, 0x01, x, 2);
    be16(UB_CODE, x);                      anade_bytes(c, &n, 0x02, x, 2);
    anade_bytes(c, &n, 0x03, (const uint8_t *)q_md5, 32);
    anade_bytes(c, &n, 0x04, (const uint8_t *)b_md5, 32);
    anade_bytes(c, &n, 0x05, (const uint8_t *)a_md5, 32);
    be32(timestamp, x);                    anade_bytes(c, &n, 0x06, x, 4);
    be32(nonce, x);                        anade_bytes(c, &n, 0x08, x, 4);
    anade_bytes(c, &n, 0x09, (const uint8_t *)SDK_VERSION, strlen(SDK_VERSION));
    anade_bytes(c, &n, 0x0A, (const uint8_t *)SCM_VERSION, strlen(SCM_VERSION));
    be16(SECUENCIA, x);                    anade_bytes(c, &n, 0x0B, x, 2);
    be16((uint32_t)secuencia, x);          anade_bytes(c, &n, 0x0C, x, 2);
    be16((uint32_t)secuencia, x);          anade_bytes(c, &n, 0x0D, x, 2);
    be32(mixed, x);                        anade_bytes(c, &n, 0x0E, x, 4);
    be32(nonce2, x);                       anade_bytes(c, &n, 0x0F, x, 4);
    be32(primero, x);                      anade_bytes(c, &n, 0x10, x, 4);

    return empaquetar(c, n, 1, salida);
}

/* ------------------------------- azar ---------------------------------- */

static uint32_t azar32(void) {
#ifdef __APPLE__
    return arc4random();
#else
    static uint32_t s = 0;
    if (!s) s = (uint32_t)time(NULL) ^ 0x9E3779B9u;
    s ^= s << 13; s ^= s >> 17; s ^= s << 5;
    return s;
#endif
}

static uint32_t reloj_micro(void) {
#if defined(_WIN32)
    /* Solo se usa en la compilacion de pruebas con TCC; el valor no importa. */
    return (uint32_t)((uint64_t)clock() * 1000u);
#else
    struct timeval tv;
    gettimeofday(&tv, NULL);
    uint64_t us = (uint64_t)tv.tv_sec * 1000000ull + (uint64_t)tv.tv_usec;
    return (uint32_t)(us & MASK32);
#endif
}

/* ----------------------------- publico --------------------------------- */

static int firmar_nucleo(const char *const claves[], const char *const valores[], int n_pares,
                         const char *ua, const char *ms,
                         uint32_t timestamp, uint32_t nonce, uint32_t nonce2,
                         const uint32_t clave1[TT_SIGNA_KEY_WORDS],
                         const uint32_t clave2[TT_SIGNA_KEY_WORDS],
                         char *salida, size_t tam_salida) {
    char consulta[4096];
    codificar_consulta(claves, valores, n_pares, consulta);

    uint8_t carga1[2048];
    size_t n1 = carga_dynosaur(consulta, ua, timestamp, nonce, SECUENCIA, carga1);
    char firma1[4096];
    sellar(carga1, n1, clave1, firma1);

    char sellada[6144];
    snprintf(sellada, sizeof sellada, "%s&X-Dynosaur=%s&msToken=%s", consulta, firma1, ms ? ms : "");

    uint8_t carga2[2048];
    size_t n2 = carga_gnarly(sellada, ua, (const uint8_t *)"", 0,
                             timestamp, nonce, nonce2, SECUENCIA, carga2);
    char firma2[4096];
    sellar(carga2, n2, clave2, firma2);

    int r = snprintf(salida, tam_salida, "%s&X-Bogus=1&X-Gnarly=%s", sellada, firma2);
    if (r < 0 || (size_t)r >= tam_salida) return -1;
    return r;
}

int tt_firmar(const char *const claves[], const char *const valores[], int n_pares,
              const char *ua, const char *ms,
              char *salida, size_t tam_salida) {
    if (!ua || !*ua) ua = TT_SIGNA_UA_POR_DEFECTO;
    uint32_t clave1[TT_SIGNA_KEY_WORDS], clave2[TT_SIGNA_KEY_WORDS];
    for (int i = 0; i < TT_SIGNA_KEY_WORDS; i++) clave1[i] = azar32();
    for (int i = 0; i < TT_SIGNA_KEY_WORDS; i++) clave2[i] = azar32();
    return firmar_nucleo(claves, valores, n_pares, ua, ms,
                         (uint32_t)time(NULL), reloj_micro(),
                         (~reloj_micro()) & MASK32, clave1, clave2,
                         salida, tam_salida);
}

int tt_firmar_determinista(const char *const claves[], const char *const valores[], int n_pares,
                           const char *ua, const char *ms,
                           uint32_t timestamp, uint32_t nonce, uint32_t nonce2,
                           const uint32_t clave1[TT_SIGNA_KEY_WORDS],
                           const uint32_t clave2[TT_SIGNA_KEY_WORDS],
                           char *salida, size_t tam_salida) {
    if (!ua || !*ua) ua = TT_SIGNA_UA_POR_DEFECTO;
    return firmar_nucleo(claves, valores, n_pares, ua, ms,
                         timestamp, nonce, nonce2, clave1, clave2, salida, tam_salida);
}
