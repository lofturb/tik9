// TTCliente.h -- habla con la API web de TikTok desde el propio telefono.
//
// Firma cada peticion en el dispositivo con TTSignaCore (el port a C de
// X-Dynosaur + X-Gnarly), asi que no necesita ni relay ni PC para navegar.
#import <UIKit/UIKit.h>
#import "TTVideo.h"

// (videos, cursor siguiente, hay mas, error)
typedef void (^TTBloqueFeed)(NSArray *videos, NSString *cursor, BOOL hayMas, NSError *error);

@interface TTCliente : NSObject

+ (instancetype)compartido;

#pragma mark Red

// Sesion HTTPS compartida (una sola para toda la app).
+ (NSURLSession *)sesionCompartida;

#pragma mark Datos

// Feed "Para ti" (api/recommend/item_list).  cursor nil = primera pagina.
- (void)feedParaTiCursor:(NSString *)cursor completado:(TTBloqueFeed)completado;

// Ficha de un video concreto (api/item/detail).  Puede venir vacia: TikTok ya
// no la da para muchos videos; el feed trae todo lo necesario.
- (void)detalleDeVideo:(NSString *)itemId
            completado:(void (^)(TTVideo *video, NSError *error))completado;

// Prueba rapida para Ajustes: cuenta cuantos videos devuelve el feed.
- (void)probarConexion:(void (^)(NSString *informe, BOOL correcto))completado;

#pragma mark Imagenes (con cache en memoria)

+ (void)cargarImagen:(NSString *)url completado:(void (^)(UIImage *imagen))completado;
+ (void)vaciarCacheImagenes;

#pragma mark Errores

+ (NSString *)explicarError:(NSError *)error;

@end
