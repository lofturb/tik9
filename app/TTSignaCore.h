/*
 * TTSignaCore.h -- firma web de TikTok, en C puro.
 *
 * Implementa X-Dynosaur + X-Gnarly (el esquema de firma que usa la web de
 * TikTok, webmssdk), mas el parametro fijo X-Bogus=1.
 *
 * Es la version portada a C de la implementacion de referencia de f2
 * (xgnarly.py, Apache-2.0), que se valido en vivo contra la API de TikTok.
 *
 * Este fichero NO depende de Objective-C ni de CommonCrypto: trae su propio
 * MD5.  Asi compila igual en iOS (Theos/clang) que con un compilador de
 * escritorio, que es lo que permite compararlo con el oraculo de Python.
 *
 * Aviso: la firma cubre la cadena de consulta EXACTA y el User-Agent EXACTO.
 * La cadena devuelta hay que enviarla tal cual, sin volver a codificar, y con
 * el mismo User-Agent.
 */

#ifndef TT_SIGNA_CORE_H
#define TT_SIGNA_CORE_H

#include <stddef.h>
#include <stdint.h>

#define TT_SIGNA_KEY_WORDS 12

/* User-Agent por defecto: el mismo que usa la referencia de f2 y con el que
 * se comprobo que la firma funciona.  Debe coincidir con el de la peticion. */
#define TT_SIGNA_UA_POR_DEFECTO \
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0"

/* Firma una peticion y devuelve la cadena de consulta firmada.
 *
 * claves/valores:  n_pares parametros de negocio, en el orden de la web.
 * user_agent:      el UA que se enviara (0 o "" usa el de por defecto).
 * ms_token:        cookie msToken o "" (nunca inventarla).
 * salida/tam:      destino.  Con 8192 hay de sobra.
 *
 * Devuelve la longitud escrita (sin el '\0'), o -1 si no cabe. */
int tt_firmar(const char *const claves[], const char *const valores[], int n_pares,
              const char *user_agent, const char *ms_token,
              char *salida, size_t tam_salida);

/* Igual, pero con todos los valores variables fijados.  Para pruebas: con las
 * mismas entradas debe dar exactamente la misma salida que la referencia de
 * Python. */
int tt_firmar_determinista(const char *const claves[], const char *const valores[], int n_pares,
                           const char *user_agent, const char *ms_token,
                           uint32_t timestamp, uint32_t nonce, uint32_t nonce2,
                           const uint32_t clave1[TT_SIGNA_KEY_WORDS],
                           const uint32_t clave2[TT_SIGNA_KEY_WORDS],
                           char *salida, size_t tam_salida);

/* Utilidad expuesta para las pruebas. */
void tt_md5_hex(const void *datos, size_t n, char salida[33]);

/* Huella FNV-1a (variante del SDK), expuesta para las pruebas. */
uint32_t tt_hash_state(const char *texto);

/* El User-Agent por defecto, para que Objective-C no tenga que repetirlo: la
 * firma cubre el UA, asi que el de la peticion tiene que ser este mismo. */
const char *tt_ua_por_defecto(void);

#endif /* TT_SIGNA_CORE_H */
