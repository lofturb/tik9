/*
 * TTTunel.c -- peticiones por una pila TLS + HTTP/2 propia (BoringSSL + nghttp2).
 *
 * Ver TTTunel.h para el motivo.  En corto: la barrera de TikTok decide por la
 * huella de la CONEXION, y la de iOS 9 no la tiene por buena.  Aqui se arma una
 * conexion con las piezas de un Chrome de verdad:
 *
 *   TLS:  BoringSSL con la lista de cifrados y las curvas de Chrome, GREASE
 *         activado y las extensiones permutadas (como hace Chrome).
 *   HTTP/2: nghttp2, pero fijando los ajustes que manda Chrome (tabla de
 *         cabeceras, ventana inicial, ventana de conexion) en vez de los de
 *         Apple, y con las cabeceras en el orden de un navegador.
 *
 * La verificacion del certificado la hace el sistema: en iOS no hay forma de
 * montarle a BoringSSL las raices del aparato (Apple no las da), asi que se
 * termina el saludo TLS y despues se le pasa la cadena y el nombre del servidor
 * a SecTrustEvaluate, que es lo mismo que hace el sistema en cada conexion.
 * Ver tt_verificar_certificado en TTTunel.c.
 *
 * Todo esto se compila solo si la construccion ha preparado las bibliotecas
 * (TT_TUNEL=1); si no, quedan las funciones de abajo devolviendo "no hay".
 */

#include "TTTunel.h"

#include <stdio.h>
#include <string.h>

#ifdef TT_TUNEL

#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdlib.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>

#include <openssl/err.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

#if __has_include(<nghttp2/nghttp2.h>)
#include <nghttp2/nghttp2.h>
#else
#include <nghttp2.h>
#endif

#define TT_TUNEL_PUERTO        "443"
#define TT_TUNEL_ESPERA        25          /* segundos para toda la peticion */
#define TT_TUNEL_TOPE_CUERPO   (4 * 1024 * 1024)

/* Lo que se va juntando de la respuesta. */
typedef struct {
    SSL *tls;
    char *datos;
    size_t largo;
    int pasado_de_tope;
    long estado;
    char orcas[64];
    char ms_token[512];
    int cerrado;
    int fallo;
} tt_conexion;

/* --- callbacks de nghttp2 ------------------------------------------------- */

static ssize_t tt_enviar(nghttp2_session *sesion, const uint8_t *datos, size_t largo,
                         int banderas, void *usuario) {
    (void)sesion;
    (void)banderas;
    tt_conexion *c = (tt_conexion *)usuario;
    size_t hechos = 0;
    while (hechos < largo) {
        int n = SSL_write(c->tls, datos + hechos, (int)(largo - hechos));
        if (n <= 0) {
            c->fallo = 1;
            return NGHTTP2_ERR_CALLBACK_FAILURE;
        }
        hechos += (size_t)n;
    }
    return (ssize_t)largo;
}

static int tt_cabecera(nghttp2_session *sesion, const nghttp2_frame *marco,
                       const uint8_t *nombre, size_t largo_nombre,
                       const uint8_t *valor, size_t largo_valor,
                       uint8_t banderas, void *usuario) {
    (void)sesion;
    (void)marco;
    (void)banderas;
    tt_conexion *c = (tt_conexion *)usuario;

    if (largo_nombre == 7 && memcmp(nombre, ":status", 7) == 0) {
        char numero[8];
        size_t copiar = largo_valor < sizeof numero - 1 ? largo_valor : sizeof numero - 1;
        memcpy(numero, valor, copiar);
        numero[copiar] = '\0';
        c->estado = strtol(numero, NULL, 10);
        return 0;
    }
    if (largo_nombre == 12 && memcmp(nombre, "tt_orcas_res", 12) == 0) {
        size_t copiar = largo_valor < sizeof c->orcas - 1 ? largo_valor : sizeof c->orcas - 1;
        memcpy(c->orcas, valor, copiar);
        c->orcas[copiar] = '\0';
        return 0;
    }
    if (largo_nombre == 11 && memcmp(nombre, "x-ms-token", 11) == 0) {
        size_t copiar = largo_valor < sizeof c->ms_token - 1 ? largo_valor : sizeof c->ms_token - 1;
        memcpy(c->ms_token, valor, copiar);
        c->ms_token[copiar] = '\0';
    }
    return 0;
}

static int tt_datos(nghttp2_session *sesion, uint8_t banderas, int32_t flujo,
                    const uint8_t *datos, size_t largo, void *usuario) {
    (void)sesion;
    (void)banderas;
    (void)flujo;
    tt_conexion *c = (tt_conexion *)usuario;
    if (c->largo + largo > TT_TUNEL_TOPE_CUERPO) {
        c->pasado_de_tope = 1;
        return 0;
    }
    char *nuevo = realloc(c->datos, c->largo + largo + 1);
    if (!nuevo) {
        c->pasado_de_tope = 1;
        return 0;
    }
    c->datos = nuevo;
    memcpy(c->datos + c->largo, datos, largo);
    c->largo += largo;
    c->datos[c->largo] = '\0';
    return 0;
}

static int tt_cerrado(nghttp2_session *sesion, int32_t flujo, uint32_t codigo,
                      void *usuario) {
    (void)sesion;
    (void)flujo;
    (void)codigo;
    ((tt_conexion *)usuario)->cerrado = 1;
    return 0;
}

/* --- certificados --------------------------------------------------------- */

/*
 * Comprueba el certificado del servidor contra las raices del sistema.
 *
 * En iOS no se puede montar un almacen de raices para BoringSSL: Apple no da
 * acceso a los certificados de las raices (SecTrustCopyAnchorCertificates esta
 * marcada como "not available on iOS" en su propia cabecera).  Lo que si hay es
 * lo que usa el sistema en cada conexion: SecTrustCreateWithCertificates +
 * SecTrustEvaluate.  Se le pasa la cadena tal cual la mando el servidor y el
 * nombre del servidor, y decide el sistema, con sus raices y sus reglas.
 *
 * Devuelve 1 si el sistema da la cadena por buena, 0 si no, y en 'detalle' deja
 * el motivo en castellano.
 */
static int tt_verificar_certificado(SSL *tls, const char *host,
                                    char *detalle, size_t tam) {
    detalle[0] = '\0';

    STACK_OF(X509) *cadena = SSL_get_peer_full_cert_chain(tls);
    if (!cadena || sk_X509_num(cadena) == 0) {
        snprintf(detalle, tam, "el servidor no mando certificado");
        return 0;
    }

    CFMutableArrayRef certificados =
        CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    if (!certificados) {
        snprintf(detalle, tam, "sin memoria para la comprobacion");
        return 0;
    }
    for (int i = 0; i < sk_X509_num(cadena); i++) {
        X509 *x = sk_X509_value(cadena, i);
        int largo = i2d_X509(x, NULL);
        if (largo <= 0) continue;
        unsigned char *der = malloc((size_t)largo);
        if (!der) continue;
        unsigned char *p = der;
        i2d_X509(x, &p);
        CFDataRef datos = CFDataCreate(NULL, der, largo);
        free(der);
        if (!datos) continue;
        SecCertificateRef certificado = SecCertificateCreateWithData(NULL, datos);
        CFRelease(datos);
        if (certificado) {
            CFArrayAppendValue(certificados, certificado);
            CFRelease(certificado);
        }
    }

    CFStringRef nombre = CFStringCreateWithCString(NULL, host, kCFStringEncodingUTF8);
    /* 1 = es un servidor (la politica tambien comprueba el nombre). */
    SecPolicyRef politica = SecPolicyCreateSSL(1, nombre);
    if (nombre) CFRelease(nombre);

    SecTrustRef confianza = NULL;
    OSStatus fallo = SecTrustCreateWithCertificates(certificados, politica, &confianza);
    CFRelease(certificados);
    if (politica) CFRelease(politica);

    int bien = 0;
    if (fallo != errSecSuccess) {
        snprintf(detalle, tam, "no se pudo montar la comprobacion (%d)", (int)fallo);
    } else {
        SecTrustResultType resultado = kSecTrustResultInvalid;
        fallo = SecTrustEvaluate(confianza, &resultado);
        if (fallo != errSecSuccess) {
            snprintf(detalle, tam, "el sistema no pudo evaluar la cadena (%d)",
                     (int)fallo);
        } else if (resultado == kSecTrustResultProceed ||
                   resultado == kSecTrustResultUnspecified) {
            bien = 1;
        } else {
            snprintf(detalle, tam, "el sistema no da por buena la cadena (resultado %d)",
                     (int)resultado);
        }
    }
    if (confianza) CFRelease(confianza);
    return bien;
}

/* --- conexion ------------------------------------------------------------- */

static int tt_conectar(const char *host, char *error, size_t tam) {
    struct addrinfo pistas;
    struct addrinfo *lista = NULL;
    memset(&pistas, 0, sizeof pistas);
    pistas.ai_family = AF_UNSPEC;
    pistas.ai_socktype = SOCK_STREAM;

    int r = getaddrinfo(host, TT_TUNEL_PUERTO, &pistas, &lista);
    if (r != 0) {
        snprintf(error, tam, "no se pudo resolver %s (%s)", host, gai_strerror(r));
        return -1;
    }

    int elegido = -1;
    for (struct addrinfo *a = lista; a; a = a->ai_next) {
        int fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
        if (fd < 0) continue;

        int banderas = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, banderas | O_NONBLOCK);
        int conectado = (connect(fd, a->ai_addr, a->ai_addrlen) == 0);
        if (!conectado && errno == EINPROGRESS) {
            fd_set escritura;
            FD_ZERO(&escritura);
            FD_SET(fd, &escritura);
            struct timeval espera;
            espera.tv_sec = 12;
            espera.tv_usec = 0;
            if (select(fd + 1, NULL, &escritura, NULL, &espera) > 0) {
                int guardado = 0;
                socklen_t largo = sizeof guardado;
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &guardado, &largo);
                conectado = (guardado == 0);
            }
        }
        fcntl(fd, F_SETFL, banderas);

        if (conectado) {
            int uno = 1;
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &uno, sizeof uno);
            elegido = fd;
            break;
        }
        close(fd);
    }
    freeaddrinfo(lista);

    if (elegido < 0) {
        snprintf(error, tam, "no se pudo abrir la conexion con %s:%s (%s)",
                 host, TT_TUNEL_PUERTO, strerror(errno));
    }
    return elegido;
}

/* Arma el contexto TLS con la huella de Chrome. */
static SSL_CTX *tt_contexto(void) {
    SSL_CTX *ctx = SSL_CTX_new(TLS_method());
    if (!ctx) return NULL;

    /* Solo TLS 1.2 y 1.3, como un navegador de hoy. */
    SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
    SSL_CTX_set_max_proto_version(ctx, TLS1_3_VERSION);

    /* Lista de cifrados de Chrome (TLS 1.2).  Las suites de TLS 1.3 no se
       tocan: el orden de fabrica de BoringSSL es el de Chrome
       (AES128-GCM, AES256-GCM, ChaCha20). */
    SSL_CTX_set_strict_cipher_list(ctx,
        "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:"
        "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:"
        "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:"
        "ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:"
        "AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA:AES256-SHA");

    /* Curvas de Chrome. */
    SSL_CTX_set1_groups_list(ctx, "X25519:P-256:P-384");

    /* GREASE y extensiones permutadas: sin esto el saludo TLS se delata como
       "no es un navegador".  Son cosas de BoringSSL, la biblioteca de Chrome. */
#ifdef OPENSSL_IS_BORINGSSL
    SSL_CTX_set_grease_enabled(ctx, 1);
    SSL_CTX_set_permute_extensions(ctx, 1);
#endif

    /* ALPN: h2 primero, como un navegador. */
    static const unsigned char protocolos[] = { 2, 'h', '2', 8, 'h', 't', 't', 'p', '/', '1', '.', '1' };
    SSL_CTX_set_alpn_protos(ctx, protocolos, sizeof protocolos);

    /* La comprobacion del certificado la hace el sistema despues del saludo
       (ver tt_verificar_certificado): aqui no se le pide a BoringSSL, que no
       tiene las raices del aparato. */
    SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);
    return ctx;
}

/* Hace el saludo TLS sobre un descriptor ya conectado. */
static SSL *tt_saludo(SSL_CTX *ctx, int fd, const char *host, char *error, size_t tam) {
    SSL *tls = SSL_new(ctx);
    if (!tls) {
        snprintf(error, tam, "no se pudo crear la sesion TLS");
        return NULL;
    }
    SSL_set_fd(tls, fd);
    SSL_set_tlsext_host_name(tls, host);
    int r = SSL_connect(tls);
    if (r != 1) {
        unsigned long cola = ERR_get_error();
        char texto[160] = "";
        if (cola) ERR_error_string_n(cola, texto, sizeof texto);
        snprintf(error, tam, "el saludo TLS fallo (%s)", texto);
        SSL_free(tls);
        ERR_clear_error();
        return NULL;
    }
    return tls;
}

/* --- peticion ------------------------------------------------------------- */

#define TT_NV(nombre, valor) \
    ((nghttp2_nv){ (uint8_t *)(nombre), (uint8_t *)(valor), \
                   strlen(nombre), strlen(valor), NGHTTP2_NV_FLAG_NONE })

static int tt_pedir_con(SSL *tls, const char *host, const char *ruta,
                        const char *ua, const char *aceptar, const char *idioma,
                        const char *referer, const char *origen, const char *cookie,
                        tt_conexion *c, char *error, size_t tam) {
    c->tls = tls;

    nghttp2_session_callbacks *llamadas = NULL;
    if (nghttp2_session_callbacks_new(&llamadas) != 0) {
        snprintf(error, tam, "sin memoria para HTTP/2");
        return -1;
    }
    nghttp2_session_callbacks_set_send_callback(llamadas, tt_enviar);
    nghttp2_session_callbacks_set_on_header_callback(llamadas, tt_cabecera);
    nghttp2_session_callbacks_set_on_data_chunk_recv_callback(llamadas, tt_datos);
    nghttp2_session_callbacks_set_on_stream_close_callback(llamadas, tt_cerrado);

    nghttp2_session *sesion = NULL;
    if (nghttp2_session_client_new(&sesion, llamadas, c) != 0) {
        nghttp2_session_callbacks_del(llamadas);
        snprintf(error, tam, "no se pudo crear la sesion HTTP/2");
        return -1;
    }
    nghttp2_session_callbacks_del(llamadas);

    /* Ajustes de Chrome, no los de Apple. */
    nghttp2_settings_entry ajustes[] = {
        { NGHTTP2_SETTINGS_HEADER_TABLE_SIZE,      65536 },
        { NGHTTP2_SETTINGS_ENABLE_PUSH,            0 },
        { NGHTTP2_SETTINGS_INITIAL_WINDOW_SIZE,    6291456 },
        { NGHTTP2_SETTINGS_MAX_HEADER_LIST_SIZE,   262144 },
    };
    nghttp2_submit_settings(sesion, NGHTTP2_FLAG_NONE, ajustes,
                            sizeof ajustes / sizeof ajustes[0]);
    /* Ventana de conexion de Chrome (15728640 menos los 65535 de fabrica). */
    nghttp2_submit_window_update(sesion, NGHTTP2_FLAG_NONE, 0, 15663105);

    nghttp2_nv cabeceras[12];
    size_t cuantas = 0;
    cabeceras[cuantas++] = TT_NV(":method", "GET");
    cabeceras[cuantas++] = TT_NV(":authority", host);
    cabeceras[cuantas++] = TT_NV(":scheme", "https");
    cabeceras[cuantas++] = TT_NV(":path", ruta);
    if (ua)      cabeceras[cuantas++] = TT_NV("user-agent", ua);
    if (aceptar) cabeceras[cuantas++] = TT_NV("accept", aceptar);
    if (idioma)  cabeceras[cuantas++] = TT_NV("accept-language", idioma);
    if (referer) cabeceras[cuantas++] = TT_NV("referer", referer);
    if (origen)  cabeceras[cuantas++] = TT_NV("origin", origen);
    if (cookie && cookie[0]) cabeceras[cuantas++] = TT_NV("cookie", cookie);

    int32_t flujo = nghttp2_submit_request(sesion, NULL, cabeceras, cuantas, NULL, NULL);
    if (flujo < 0) {
        nghttp2_session_del(sesion);
        snprintf(error, tam, "no se pudo armar la peticion HTTP/2 (%d)", flujo);
        return -1;
    }
    if (nghttp2_session_send(sesion) != 0) {
        nghttp2_session_del(sesion);
        snprintf(error, tam, "no se pudo enviar la peticion HTTP/2");
        return -1;
    }

    /* Bucle de lectura con plazo. */
    struct timeval comienzo;
    gettimeofday(&comienzo, NULL);
    char buzon[16384];
    int salida = 0;

    while (!c->cerrado && !c->fallo) {
        struct timeval ahora;
        gettimeofday(&ahora, NULL);
        double pasado = (double)(ahora.tv_sec - comienzo.tv_sec) +
                        (double)(ahora.tv_usec - comienzo.tv_usec) / 1000000.0;
        if (pasado > TT_TUNEL_ESPERA) {
            snprintf(error, tam, "se acabo el tiempo esperando la respuesta");
            salida = -1;
            break;
        }

        fd_set lectura;
        FD_ZERO(&lectura);
        FD_SET(SSL_get_fd(tls), &lectura);
        struct timeval espera;
        espera.tv_sec = 2;
        espera.tv_usec = 0;
        // Si ya hay datos descifrados esperando, no se espera al socket.
        if (SSL_pending(tls) <= 0) {
            int listo = select(SSL_get_fd(tls) + 1, &lectura, NULL, NULL, &espera);
            if (listo < 0) {
                if (errno == EINTR) continue;
                snprintf(error, tam, "fallo esperando datos (%s)", strerror(errno));
                salida = -1;
                break;
            }
            if (listo == 0) continue;
        }

        int n = SSL_read(tls, buzon, sizeof buzon);
        if (n > 0) {
            ssize_t usado = nghttp2_session_mem_recv(sesion, (const uint8_t *)buzon, (size_t)n);
            if (usado < 0) {
                snprintf(error, tam, "respuesta HTTP/2 invalida (%ld)", (long)usado);
                salida = -1;
                break;
            }
            if (nghttp2_session_send(sesion) != 0) {
                snprintf(error, tam, "no se pudo confirmar la respuesta");
                salida = -1;
                break;
            }
            continue;
        }
        int motivo = SSL_get_error(tls, n);
        if (motivo == SSL_ERROR_WANT_READ || motivo == SSL_ERROR_WANT_WRITE) continue;
        if (motivo == SSL_ERROR_ZERO_RETURN) break;   /* cierre ordenado */
        if (c->largo > 0) break;                      /* lo recibido ya vale */
        unsigned long cola = ERR_get_error();
        char texto[120] = "";
        if (cola) ERR_error_string_n(cola, texto, sizeof texto);
        snprintf(error, tam, "se corto la conexion (%s)", texto);
        salida = -1;
        break;
    }

    nghttp2_session_del(sesion);
    return salida;
}

/* --- API publica ---------------------------------------------------------- */

int tt_tunel_hay(void) {
    return 1;
}

void tt_tunel_descripcion(char *salida, size_t tam) {
    if (!salida || tam == 0) return;
    const nghttp2_info *info = nghttp2_version(0);
    snprintf(salida, tam, "BoringSSL + nghttp2 %s",
             info && info->version_str ? info->version_str : "?");
}

void tt_tunel_soltar(tt_tunel_respuesta *respuesta) {
    if (!respuesta) return;
    free(respuesta->cuerpo);
    respuesta->cuerpo = NULL;
    respuesta->largo = 0;
}

int tt_tunel_pedir(const char *host, const char *ruta,
                   const char *ua, const char *aceptar, const char *idioma,
                   const char *referer, const char *origen, const char *cookie,
                   tt_tunel_respuesta *salida) {
    if (!salida) return -1;
    memset(salida, 0, sizeof *salida);
    if (!host || !ruta) {
        snprintf(salida->error, sizeof salida->error, "faltan host o ruta");
        return -1;
    }

    ERR_clear_error();
    SSL_CTX *ctx = tt_contexto();
    if (!ctx) {
        snprintf(salida->error, sizeof salida->error, "no se pudo crear el contexto TLS");
        return -1;
    }

    int fd = tt_conectar(host, salida->error, sizeof salida->error);
    if (fd < 0) {
        SSL_CTX_free(ctx);
        return -1;
    }

    SSL *tls = tt_saludo(ctx, fd, host, salida->error, sizeof salida->error);
    SSL_CTX_free(ctx);

    if (!tls) {
        if (fd >= 0) close(fd);
        return -1;
    }

    /* El saludo TLS ya esta hecho (BoringSSL no comprueba certificados: no
       tiene las raices del aparato).  La comprobacion de verdad la hace ahora
       el sistema, con la cadena que mando el servidor y su nombre.  Si no da la
       cadena por buena, se sigue con la peticion -- en esta version el objetivo
       es medir si la conexion pasa la barrera, y el informe lo dice en voz
       alta -- pero NI SE DA POR BUENA: la app lo marca como no verificado y lo
       cuenta en el informe.  Cuando el tunel pase a usarse para la busqueda de
       verdad, sin certificado verificado no se mandara nada (ni la cookie). */
    char motivo[200] = "";
    salida->verificado = tt_verificar_certificado(tls, host, motivo, sizeof motivo);
    if (!salida->verificado) {
        snprintf(salida->error, sizeof salida->error,
                 "sin verificar el certificado: %s", motivo);
    }

    const unsigned char *negociado = NULL;
    unsigned int largo_negociado = 0;
    SSL_get0_alpn_selected(tls, &negociado, &largo_negociado);
    const char *cifra = SSL_get_cipher_name(tls);
    snprintf(salida->tls, sizeof salida->tls, "%s %s alpn=%.*s",
             SSL_get_version(tls), cifra ? cifra : "?",
             (int)largo_negociado, negociado ? (const char *)negociado : "-");

    tt_conexion conexion;
    memset(&conexion, 0, sizeof conexion);
    int r = tt_pedir_con(tls, host, ruta, ua, aceptar, idioma, referer, origen,
                         cookie, &conexion, salida->error, sizeof salida->error);

    salida->estado = conexion.estado;
    salida->largo = (long)conexion.largo;
    salida->cuerpo = conexion.datos;
    snprintf(salida->orcas, sizeof salida->orcas, "%s", conexion.orcas);
    snprintf(salida->ms_token, sizeof salida->ms_token, "%s", conexion.ms_token);
    if (conexion.pasado_de_tope) {
        snprintf(salida->error, sizeof salida->error,
                 "la respuesta pasaba de %d MB y se corto", TT_TUNEL_TOPE_CUERPO / (1024 * 1024));
    }

    SSL_shutdown(tls);
    SSL_free(tls);
    if (fd >= 0) close(fd);
    ERR_clear_error();

    if (salida->estado == 0 && salida->error[0] == '\0') {
        snprintf(salida->error, sizeof salida->error, "la respuesta no traia estado HTTP");
    }
    return (salida->estado != 0 || salida->largo > 0) ? 0 : (r == 0 ? -1 : r);
}

#else  /* !TT_TUNEL: la version no trae las bibliotecas */

int tt_tunel_hay(void) {
    return 0;
}

void tt_tunel_descripcion(char *salida, size_t tam) {
    if (salida && tam) snprintf(salida, tam, "no compilado");
}

void tt_tunel_soltar(tt_tunel_respuesta *respuesta) {
    if (!respuesta) return;
    respuesta->cuerpo = NULL;
    respuesta->largo = 0;
}

int tt_tunel_pedir(const char *host, const char *ruta,
                   const char *ua, const char *aceptar, const char *idioma,
                   const char *referer, const char *origen, const char *cookie,
                   tt_tunel_respuesta *salida) {
    (void)host; (void)ruta; (void)ua; (void)aceptar; (void)idioma;
    (void)referer; (void)origen; (void)cookie;
    if (salida) {
        memset(salida, 0, sizeof *salida);
        snprintf(salida->error, sizeof salida->error,
                 "esta version no trae el tunel compilado");
    }
    return -1;
}

#endif /* TT_TUNEL */
