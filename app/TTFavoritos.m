// TTFavoritos.m
#import "TTFavoritos.h"

static NSString *TTRutaFavoritos(void) {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
                                                       NSUserDomainMask, YES);
    NSString *base = dirs.firstObject ?: NSTemporaryDirectory();
    return [base stringByAppendingPathComponent:@"tik9-favoritos.json"];
}

@implementation TTFavoritos {
    NSMutableArray *_videos;   // NSDictionary (ya serializado)
    NSMutableSet *_ids;
}

+ (instancetype)compartida {
    static TTFavoritos *una = nil;
    static dispatch_once_t vez;
    dispatch_once(&vez, ^{ una = [[TTFavoritos alloc] init]; });
    return una;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _videos = [NSMutableArray array];
        _ids = [NSMutableSet set];
        [self leer];
    }
    return self;
}

#pragma mark - Disco

- (void)leer {
    NSData *datos = [NSData dataWithContentsOfFile:TTRutaFavoritos()];
    if (datos.length == 0) return;
    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:datos options:0 error:&error];
    if (![json isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *d in (NSArray *)json) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        NSString *ident = d[@"id"];
        if (![ident isKindOfClass:[NSString class]] || ident.length == 0) continue;
        if ([_ids containsObject:ident]) continue;
        [_videos addObject:[d mutableCopy]];
        [_ids addObject:ident];
    }
}

- (void)escribir {
    NSData *datos = [NSJSONSerialization dataWithJSONObject:_videos options:0 error:NULL];
    if (datos) [datos writeToFile:TTRutaFavoritos() atomically:YES];
}

#pragma mark - Consulta

- (NSArray *)todos {
    NSMutableArray *salida = [NSMutableArray arrayWithCapacity:_videos.count];
    for (NSDictionary *d in _videos) {
        TTVideo *v = [TTVideo desdeDiccionario:d];
        if (v) [salida addObject:v];
    }
    return salida;
}

- (NSUInteger)cuantos {
    return _videos.count;
}

- (BOOL)estaGuardado:(NSString *)identificador {
    return identificador.length ? [_ids containsObject:identificador] : NO;
}

#pragma mark - Cambios

- (BOOL)alternar:(TTVideo *)video {
    if (!video.identificador.length) return NO;
    if ([_ids containsObject:video.identificador]) {
        [self quitar:video.identificador];
        return NO;
    }
    [self guardar:video];
    return YES;
}

- (void)guardar:(TTVideo *)video {
    if (!video.identificador.length) return;
    if ([_ids containsObject:video.identificador]) return;
    [_videos insertObject:[[video aDiccionario] mutableCopy] atIndex:0];
    [_ids addObject:video.identificador];
    [self escribir];
}

- (void)quitar:(NSString *)identificador {
    if (!identificador.length) return;
    NSUInteger indice = NSNotFound;
    for (NSUInteger i = 0; i < _videos.count; i++) {
        NSString *ident = _videos[i][@"id"];
        if ([ident isKindOfClass:[NSString class]] && [ident isEqualToString:identificador]) {
            indice = i;
            break;
        }
    }
    if (indice != NSNotFound) [_videos removeObjectAtIndex:indice];
    [_ids removeObject:identificador];
    [self escribir];
}

- (void)vaciar {
    [_videos removeAllObjects];
    [_ids removeAllObjects];
    [self escribir];
}

@end
