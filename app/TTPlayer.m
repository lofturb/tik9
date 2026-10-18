// TTPlayer.m
#import "TTPlayer.h"

// Clave privada de AVURLAsset para enviar cabeceras al CDN (la usa todo el
// mundo desde iOS 7; es la unica forma de que el CDN de TikTok no corte).
static NSString * const TTClaveCabeceras = @"AVURLAssetHTTPHeaderFieldsKey";

@implementation TTPlayer {
    AVPlayerItem *_item;
    id _observadorEstado;
    id _observadorFin;
    BOOL _tieneObservadores;
}

+ (instancetype)compartido {
    static TTPlayer *una = nil;
    static dispatch_once_t vez;
    dispatch_once(&vez, ^{ una = [[TTPlayer alloc] init]; });
    return una;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _jugador = [[AVPlayer alloc] init];
        _jugador.actionAtItemEnd = AVPlayerActionAtItemEndNone;   // para repetir
        _capa = [AVPlayerLayer playerLayerWithPlayer:_jugador];
        _capa.videoGravity = AVLayerVideoGravityResizeAspectFill;
        _capa.backgroundColor = [UIColor blackColor].CGColor;
        _silenciado = NO;
    }
    return self;
}

- (void)dealloc {
    [self quitarObservadores];
}

#pragma mark - Carga

- (void)cargarURL:(NSURL *)url cabeceras:(NSDictionary *)cabeceras {
    if (!url) return;
    [self quitarObservadores];

    AVURLAsset *activo = [AVURLAsset URLAssetWithURL:url
        options:(cabeceras.count ? @{ TTClaveCabeceras : cabeceras } : nil)];
    _item = [AVPlayerItem playerItemWithAsset:activo];
    [_jugador replaceCurrentItemWithPlayerItem:_item];
    [self ponerObservadores];
}

- (void)ponerObservadores {
    if (_item) {
        [_item addObserver:self forKeyPath:@"status"
                   options:NSKeyValueObservingOptionNew context:NULL];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(terminoElVideo:)
            name:AVPlayerItemDidPlayToEndTimeNotification
          object:_item];
    _tieneObservadores = YES;
}

- (void)quitarObservadores {
    if (_tieneObservadores && _item) {
        @try {
            [_item removeObserver:self forKeyPath:@"status"];
        } @catch (__unused NSException *e) { }
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    _tieneObservadores = NO;
}

- (void)observeValueForKeyPath:(NSString *)ruta
                      ofObject:(id)objeto
                        change:(NSDictionary *)cambio
                       context:(void *)contexto {
    if (![ruta isEqualToString:@"status"]) return;
    AVPlayerItemStatus estado = _item.status;
    // El aviso de KVO puede llegar en segundo plano; quien lo escucha toca
    // interfaz, asi que se pasa al hilo principal.
    if (estado == AVPlayerItemStatusReadyToPlay) {
        void (^alListo)(void) = self.alListo;
        if (alListo) dispatch_async(dispatch_get_main_queue(), alListo);
    } else if (estado == AVPlayerItemStatusFailed) {
        void (^alFallar)(NSError *) = self.alFallar;
        NSError *e = _item.error;
        if (alFallar) dispatch_async(dispatch_get_main_queue(), ^{ alFallar(e); });
    }
}

- (void)terminoElVideo:(NSNotification *)aviso {
    // TikTok repite el video en bucle.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_jugador seekToTime:kCMTimeZero];
        if (self->_jugador.rate > 0.01f) [self->_jugador play];
    });
}

#pragma mark - Control

- (void)reproducir {
    [_jugador play];
}

- (void)pausar {
    [_jugador pause];
}

- (void)parar {
    [_jugador pause];
    [self quitarObservadores];
    [_jugador replaceCurrentItemWithPlayerItem:nil];
    _item = nil;
}

- (BOOL)estaReproduciendo {
    return _jugador.rate > 0.01f;
}

- (void)setSilenciado:(BOOL)silenciado {
    _silenciado = silenciado;
    _jugador.muted = silenciado;
}

#pragma mark - Sesion de audio

- (void)activarSesionAudio {
    AVAudioSession *sesion = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [sesion setCategory:AVAudioSessionCategoryPlayback error:&error];
    [sesion setActive:YES error:&error];
}

- (void)desactivarSesionAudio {
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setActive:NO
        withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
}

@end
