// TTFavoritos.h -- videos guardados en el propio telefono.
//
// Se guarda el video entero (no solo el identificador), para poder ver la
// ficha, la portada y el audio aunque TikTok cambie o borre el video.  Es
// tambien la lista de "me gusta" del feed.
#import <Foundation/Foundation.h>
#import "TTVideo.h"

@interface TTFavoritos : NSObject

+ (instancetype)compartida;

- (NSArray *)todos;                          // NSArray<TTVideo*>, reciente primero
- (NSUInteger)cuantos;
- (BOOL)estaGuardado:(NSString *)identificador;

// Devuelve YES si el video QUEDO guardado, NO si se quito.
- (BOOL)alternar:(TTVideo *)video;
- (void)guardar:(TTVideo *)video;
- (void)quitar:(NSString *)identificador;
- (void)vaciar;

@end
