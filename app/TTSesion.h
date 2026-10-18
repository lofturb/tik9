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

// Token de sesion web.  Cadena vacia cuando no hay (es lo normal sin pegar
// cookies): la firma y la navegacion funcionan igual.
- (NSString *)msToken;

// El User-Agent que se firma.  TIENE que ser el mismo que se envia.
- (NSString *)userAgent;

// Cabecera Cookie cruda (p.ej. "msToken=...; ttwid=...").  Puede estar vacia.
- (NSString *)cookiesManuales;
- (void)guardarCookiesManuales:(NSString *)crudo;
- (BOOL)hayCookies;

// Cabeceras base de toda peticion a la API web de TikTok.
- (NSDictionary *)cabecerasBase;

// Pares de negocio comunes a todos los endpoints (aid, idioma, plataforma...).
- (NSArray *)paresBase;

- (void)olvidarTodo;

@end
