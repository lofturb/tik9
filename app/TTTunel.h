/*
 * TTTunel.h -- peticiones por una pila TLS + HTTP/2 propia.
 *
 * La busqueda de TikTok no la deja pasar la pila de red de iOS 9 (la de 2015):
 * la barrera decide por la huella de la conexion, no por lo que se pide.  Lo
 * medido esta en HALLAZGOS.md: misma direccion, misma firma, mismo User-Agent,
 * misma IP publica; entra desde una pila moderna y no entra desde el iPad.
 *
 * Este modulo habla con TikTok usando:
 *   - BoringSSL, la biblioteca TLS de Chrome, con el saludo de un Chrome de
 *     verdad: su lista de cifrados, sus curvas (incluido el grupo post-cuantico
 *     X25519Kyber768Draft00), sus algoritmos de firma, GREASE, las extensiones
 *     permutadas, ECH de relleno y la compresion de certificados;
 *   - nghttp2, para armar HTTP/2 con los ajustes exactos de Chrome (tabla de
 *     cabeceras de 64 kB, ventana inicial de 6 MB, ventana de conexion de
 *     15 663 105, sin tramas de prioridad) y no con los de Apple de 2015.
 *
 * La referencia esta medida: la huella de un Chrome que si entra es
 * ja4 t13d1516h2_8daaf6152771_02713d6af862 y, en HTTP/2, la de Akamai
 * 1:65536;2:0;4:6291456;6:262144|15663105|0|m,a,s,p (ver HALLAZGOS.md 4 nonies).
 *
 * La comprobacion del certificado no la puede hacer BoringSSL: en iOS no hay
 * acceso a las raices del sistema (SecTrustCopyAnchorCertificates esta marcada
 * como no disponible en iOS).  Asi que se termina el saludo TLS y se le pasa la
 * cadena y el nombre del servidor a SecTrustEvaluate, que es exactamente lo que
 * hace el sistema en cada conexion.
 *
 * Solo se usa para las rutas vetadas (la busqueda).  El feed, el detalle y las
 * paginas siguen yendo por NSURLSession, que funciona bien y trae todas las
 * ventajas del sistema (caché, ATS, certificados).
 *
 * El modulo se compila solo cuando la construccion ha podido preparar BoringSSL
 * y nghttp2 (ver tools/compilar_tunel.sh y el Makefile).  Si no estan,
 * tt_tunel_hay() devuelve 0 y la app funciona como antes.
 */

#ifndef TT_TUNEL_H
#define TT_TUNEL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Una cabecera de la peticion, tal cual se manda (sin los dos puntos). */
typedef struct {
    const char *nombre;
    const char *valor;
} tt_cabecera;

typedef struct {
    long estado;         /* codigo HTTP (:status) o 0 si no se llego a hablar */
    long largo;          /* bytes del cuerpo */
    char *cuerpo;        /* cuerpo en crudo (malloc); se suelta con tt_tunel_soltar */
    char orcas[64];      /* cabecera tt_orcas_res, si vino */
    char ms_token[512];  /* cabecera x-ms-token, si vino (TikTok la regala al rechazar) */
    char cookie[512];    /* ttwid que venga en set-cookie, si viene */
    char error[256];     /* que fallo, en castellano, si algo fallo */
    char tls[96];        /* version de TLS y cifrado negociados, para el informe */
    char huella[192];    /* que partes del saludo de Chrome se pudieron poner */
    int verificado;      /* 1 si el certificado se comprobo contra las raices del sistema */
} tt_tunel_respuesta;

/* 1 si esta version trae el tunel compilado, 0 si no. */
int tt_tunel_hay(void);

/* Texto corto con las versiones (BoringSSL / nghttp2), para el informe. */
void tt_tunel_descripcion(char *salida, size_t tam);

/*
 * Pide host+ruta por el tunel.  Devuelve 0 si hubo respuesta HTTP (mire
 * salida->estado), -1 si no se pudo ni conectar.  En los dos casos rellena
 * salida->error cuando hay algo que contar.
 *
 * Las cabeceras van en el orden en que se mandan: los cuatro pseudo-cabeceras
 * (":method", ":authority", ":scheme", ":path") los pone el modulo, y despues
 * van las que se pasen aqui, tal cual y en este orden.
 */
int tt_tunel_pedir(const char *host, const char *ruta,
                   const tt_cabecera *cabeceras, size_t cuantas,
                   tt_tunel_respuesta *salida);

/* Libera el cuerpo de una respuesta.  Se puede llamar dos veces sin problema. */
void tt_tunel_soltar(tt_tunel_respuesta *respuesta);

#ifdef __cplusplus
}
#endif

#endif /* TT_TUNEL_H */
