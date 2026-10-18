// TTResolvedor.h -- obtiene una URL REPRODUCIBLE para un video.
//
// Pieza enchufable.  Hay dos motores:
//
//   directo  Usa la direccion firmada /aweme/v1/play/ que viene DENTRO del
//            itemStruct del feed.  Se probo en vivo: responde 302 al CDN bueno
//            (v16/v19-web-newkey.tiktokcdn.com) y sirve el MP4 sin cookies; lo
//            unico que exige el CDN es la cabecera Referer de www.tiktok.com.
//            Es el camino normal y no necesita nada externo.
//
//   relay    Le pide a un pequeno programa de Python (relay/servidor.py) que
//            haga de puente por HTTP plano.  NO es obligatorio: sirve cuando
//            iOS 9 no confia en el certificado del CDN o cuando el CDN corta
//            la conexion.  La app sigue navegando el feed entera sin el.
//
// El modo "auto" (por defecto) prueba directo y, solo si falla, el relay.
#import <Foundation/Foundation.h>
#import "TTVideo.h"

@interface TTResolvedor : NSObject

+ (instancetype)compartido;

#pragma mark Configuracion

+ (NSString *)modo;                       // @"auto" | @"directo" | @"relay"
+ (void)guardarModo:(NSString *)modo;

+ (NSString *)relayBase;                  // p.ej. http://192.168.1.50:8787
+ (NSString *)relayToken;
+ (BOOL)hayRelay;
+ (void)guardarRelay:(NSString *)base token:(NSString *)token;

#pragma mark Resolver

// resultado: @{ @"url": NSURL, @"cabeceras": NSDictionary, @"motor": NSString }
- (void)resolverVideo:(TTVideo *)video
           completado:(void (^)(NSDictionary *resultado, NSError *error))completado;

// Deja resuelta la direccion del video en segundo plano y sin avisar a nadie.
// La app lo usa para adelantar los siguientes videos del feed: resolver cuesta
// cerca de un segundo (es un salto 302 por www.tiktok.com) y, al adelantarlo,
// deslizar al video siguiente ya sale casi al instante.  Si ya estaba resuelta
// (o se esta resolviendo), no hace nada.
- (void)prepararVideo:(TTVideo *)video;

// Tira la cache de direcciones resueltas (al cambiar de motor o de relay).
- (void)vaciarCache;

// Olvida la direccion ya resuelta de UN video.  La app lo usa tras un fallo de
// reproduccion: asi el reintento pide una direccion nueva en vez de repetir la
// que no funciono (que puede haber caducado).
- (void)olvidarVideo:(TTVideo *)video;

// Prueba el relay configurado (para el boton de Ajustes).
- (void)probarRelay:(void (^)(NSString *informe, BOOL correcto))completado;

@end
