// TTPlayer.h -- un unico reproductor para todo el feed.
//
// En vez de un AVPlayer por celda (que en un telefono de 32 bits se nota), hay
// uno solo que se va "mudando" a la celda visible: la capa se reengancha al
// contenedor de la celda que toca.  Eso, ademas, hace que solo suene un video.
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface TTPlayer : NSObject

+ (instancetype)compartido;

@property (nonatomic, readonly) AVPlayer *jugador;
@property (nonatomic, readonly) AVPlayerLayer *capa;

// Silencio del video (el icono de la bocina del feed).
@property (nonatomic, assign) BOOL silenciado;

// Se avisa cuando el item esta listo para pintar y cuando falla.
@property (nonatomic, copy) void (^alListo)(void);
@property (nonatomic, copy) void (^alFallar)(NSError *error);

- (void)cargarURL:(NSURL *)url cabeceras:(NSDictionary *)cabeceras;
- (void)reproducir;
- (void)pausar;
- (void)parar;
- (BOOL)estaReproduciendo;

- (void)activarSesionAudio;
- (void)desactivarSesionAudio;

@end
