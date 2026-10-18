/*
 * prueba_vivo.c -- firma una peticion REAL con el port en C y la imprime.
 *
 * Lo usa prototipo/probar_c.py: ejecuta este programa para obtener la cadena
 * de consulta firmada con el port de C (no con Python) y la envia a TikTok.
 * Es la prueba de punta a punta: si TikTok responde con datos, el port es
 * correcto y sirve tal cual dentro de la app.
 *
 * Uso:  prueba_vivo.exe itemDetail 7106594312292453675
 *       prueba_vivo.exe recommend
 */

#include "../TTSignaCore.h"
#include <stdio.h>
#include <string.h>

static const char *const UA =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0";

#define MAXP 32

static int base_comun(const char *claves[], const char *valores[]) {
    int n = 0;
    claves[n] = "aid";             valores[n++] = "1988";
    claves[n] = "app_language";    valores[n++] = "en-US";
    claves[n] = "app_name";        valores[n++] = "tiktok_web";
    claves[n] = "browser_language";valores[n++] = "en-US";
    claves[n] = "browser_name";    valores[n++] = "Mozilla";
    claves[n] = "browser_online";  valores[n++] = "true";
    claves[n] = "browser_platform";valores[n++] = "Win32";
    claves[n] = "channel";         valores[n++] = "tiktok_web";
    claves[n] = "cookie_enabled";  valores[n++] = "true";
    claves[n] = "device_id";       valores[n++] = "7311111111111111111";
    claves[n] = "device_platform"; valores[n++] = "web_pc";
    claves[n] = "os";              valores[n++] = "windows";
    claves[n] = "region";          valores[n++] = "US";
    claves[n] = "tz_name";         valores[n++] = "America/New_York";
    return n;
}

int main(int argc, char **argv) {
    const char *modo = argc > 1 ? argv[1] : "itemDetail";
    const char *item = argc > 2 ? argv[2] : "7106594312292453675";

    const char *claves[MAXP];
    const char *valores[MAXP];
    int n = base_comun(claves, valores);

    if (strcmp(modo, "recommend") == 0) {
        claves[n] = "count";  valores[n++] = "12";
    } else if (strcmp(modo, "search") == 0) {
        claves[n] = "count";          valores[n++] = "12";
        claves[n] = "cursor";         valores[n++] = "0";
        claves[n] = "keyword";        valores[n++] = argc > 2 ? argv[2] : "minecraft";
        claves[n] = "search_source";  valores[n++] = "normal_search";
    } else { /* itemDetail */
        claves[n] = "coverFormat";    valores[n++] = "2";
        claves[n] = "itemId";         valores[n++] = item;
    }

    char salida[8192];
    int r = tt_firmar(claves, valores, n, UA, "", salida, sizeof salida);
    if (r < 0) { fprintf(stderr, "no cabe\n"); return 1; }
    printf("%s\n", salida);
    return 0;
}
