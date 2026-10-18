// TTSesion.h -- identidad del telefono: dispositivo, cookies y cabeceras.
//
// TikTok no pide cuenta para ver el feed, pero si un identificador de
// dispositivo estable.  Las cookies (msToken) son OPCIONALES: la reproduccion
// directa ya funciona sin ellas, porque el CDN solo exige el Referer.  Pegarlas
// en Ajustes sirve para pedir el feed con tu propia sesion de navegador.
#import <Foundation/Foundation.h>

@interface TTSesion : NSObject

+ (instancetype)compartida;

// Identificador de dispositivo: 19 cifras que empiezan por 7.  Se genera una
// vez y se conserva, para que TikTok vea siempre al mismo "telefono".
- (NSString *)dispositivoId;

// Token de sesion web.  Cadena vacia cuando no hay.  Se busca, en este orden,
// en las cookies pegadas a mano, en el ultimo que regalo una respuesta de
// TikTok (cabecera x-ms-token) y en el almacen de cookies del sistema.
- (NSString *)msToken;

// El User-Agent que se firma.  TIENE que ser el mismo que se envia.
- (NSString *)userAgent;

// Cabecera Cookie cruda (p.ej. "msToken=...; ttwid=...").  Puede estar vacia.
- (NSString *)cookiesManuales;
- (void)guardarCookiesManuales:(NSString *)crudo;
- (BOOL)hayCookies;

// Identidad anonima.  La busqueda exige la cookie ttwid: sin ella TikTok
// contesta 200 con {"status_code":2483,"status_msg":"Por favor, inicia sesion
// primero"}.  Se consigue cargando una pagina publica (no hace falta cuenta).
- (BOOL)hayIdentidad;
- (void)prepararIdentidad:(void (^)(BOOL lograda))completado;
- (void)olvidarIdentidad;

// msToken que vino en la cabecera x-ms-token de alguna respuesta.  Se guarda y
// la siguiente firma lo usa; asi la app se levanta sola en el primer arranque.
- (void)guardarMsTokenAprendido:(NSString *)token;

// Cookies que la app manda: las automaticas de tiktok.com (ttwid, tt_chain_token,
// msToken...) y encima las pegadas a mano.  Es lo que va en la cabecera Cookie.
- (NSString *)cookieDeSesion;

// Cabeceras base de toda peticion a la API web de TikTok.
- (NSDictionary *)cabecerasBase;

// Pares de negocio comunes a todos los endpoints (aid, idioma, plataforma...).
- (NSArray *)paresBase;

- (void)olvidarTodo;

@end
