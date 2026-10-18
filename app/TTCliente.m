// TTCliente.m
#import "TTCliente.h"
#import "TTSesion.h"
#import "TTSignaCore.h"
#import <stdlib.h>

NSString * const TTErrorDominio = @"Tik9";

typedef NS_ENUM(NSInteger, TTCodigoError) {
    TTErrorRed = 1,
    TTErrorVacio,
    TTErrorFormato,
    TTErrorFirma
};

static NSError *TTError(TTCodigoError codigo, NSString *texto) {
    return [NSError errorWithDomain:TTErrorDominio code:codigo
                           userInfo:@{ NSLocalizedDescriptionKey : texto }];
}

@implementation TTCliente

+ (instancetype)compartido {
    static TTCliente *una = nil;
    static dispatch_once_t vez;
    dispatch_once(&vez, ^{ una = [[TTCliente alloc] init]; });
    return una;
}

#pragma mark - Sesion HTTP

- (NSURLSession *)sesion {
    return [TTCliente sesionCompartida];
}

+ (NSURLSession *)sesionCompartida {
    static NSURLSession *sesion = nil;
    static dispatch_once_t vez;
    dispatch_once(&vez, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 25.0;
        cfg.timeoutIntervalForResource = 60.0;
        cfg.HTTPMaximumConnectionsPerHost = 4;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        sesion = [NSURLSession sessionWithConfiguration:cfg];
    });
    return sesion;
}

#pragma mark - Firma

// Firma la lista de pares con el port en C y devuelve la cadena de consulta.
// Los objetos NSString se retienen durante la llamada: UTF8String solo es
// valido mientras viven.
- (NSString *)firmarPares:(NSArray *)pares {
    TTSesion *ses = [TTSesion compartida];
    NSString *ua = [ses userAgent];
    NSString *ms = [ses msToken];

    int n = (int)pares.count;
    const char **claves  = (const char **)malloc(sizeof(char *) * (size_t)n);
    const char **valores = (const char **)malloc(sizeof(char *) * (size_t)n);
    NSMutableArray *retenidos = [NSMutableArray arrayWithCapacity:(NSUInteger)(n * 2)];
    for (int i = 0; i < n; i++) {
        NSArray *par = pares[(NSUInteger)i];
        NSString *k = par.count > 0 ? par[0] : @"";
        NSString *v = par.count > 1 ? par[1] : @"";
        [retenidos addObject:k];
        [retenidos addObject:v];
        claves[i]  = [k UTF8String];
        valores[i] = [v UTF8String];
    }

    char salida[8192];
    int r = tt_firmar(claves, valores, n, [ua UTF8String], [ms UTF8String],
                      salida, sizeof salida);
    free(claves);
    free(valores);
    if (r < 0) return nil;
    return [NSString stringWithUTF8String:salida];
}

#pragma mark - Peticion

- (void)pedirRuta:(NSString *)ruta
            pares:(NSArray *)pares
       completado:(void (^)(NSDictionary *json, NSError *error))completado {

    NSString *firmado = [self firmarPares:pares];
    if (firmado.length == 0) {
        completado(nil, TTError(TTErrorFirma, @"No se pudo firmar la peticion"));
        return;
    }

    NSString *texto = [NSString stringWithFormat:@"https://www.tiktok.com%@?%@", ruta, firmado];
    NSURL *url = [NSURL URLWithString:texto];
    if (!url) {
        completado(nil, TTError(TTErrorFirma, @"La direccion firmada no es valida"));
        return;
    }

    NSMutableURLRequest *peticion = [NSMutableURLRequest requestWithURL:url];
    peticion.HTTPMethod = @"GET";
    peticion.timeoutInterval = 25.0;
    NSDictionary *cabeceras = [[TTSesion compartida] cabecerasBase];
    for (NSString *clave in cabeceras) {
        [peticion setValue:cabeceras[clave] forHTTPHeaderField:clave];
    }

    NSURLSessionDataTask *tarea = [[self sesion]
        dataTaskWithRequest:peticion
          completionHandler:^(NSData *datos, NSURLResponse *respuesta, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completado(nil, TTError(TTErrorRed, error.localizedDescription));
            });
            return;
        }
        NSInteger codigo = [respuesta isKindOfClass:[NSHTTPURLResponse class]]
                           ? [(NSHTTPURLResponse *)respuesta statusCode] : 0;
        if (datos.length == 0) {
            // TikTok contesta 200 con cuerpo vacio cuando marca la peticion
            // (cabecera tt_orcas_res: 1).  Se dice tal cual para no despistar.
            dispatch_async(dispatch_get_main_queue(), ^{
                completado(nil, TTError(TTErrorVacio,
                    [NSString stringWithFormat:
                     @"TikTok respondio vacio (codigo %ld). La ruta esta marcada.", (long)codigo]));
            });
            return;
        }
        NSError *jerror = nil;
        id json = [NSJSONSerialization JSONObjectWithData:datos options:0 error:&jerror];
        if (![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completado(nil, TTError(TTErrorFormato, @"La respuesta no era JSON"));
            });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completado(json, nil);
        });
    }];
    [tarea resume];
}

#pragma mark - Feed

- (void)feedParaTiCursor:(NSString *)cursor completado:(TTBloqueFeed)completado {
    NSMutableArray *pares = [NSMutableArray arrayWithArray:[[TTSesion compartida] paresBase]];
    [pares addObject:@[ @"count", @"12" ]];
    [pares addObject:@[ @"cursor", cursor.length ? cursor : @"0" ]];

    [self pedirRuta:@"/api/recommend/item_list/" pares:pares completado:^(NSDictionary *json, NSError *error) {
        if (error) { completado(nil, nil, NO, error); return; }
        NSArray *items = json[@"itemList"];
        NSArray *videos = [TTVideo listDesdeItemList:items];
        NSString *siguiente = [json[@"cursor"] isKindOfClass:[NSString class]] ? json[@"cursor"] : nil;
        if (!siguiente && [json[@"cursor"] isKindOfClass:[NSNumber class]]) {
            siguiente = [(NSNumber *)json[@"cursor"] stringValue];
        }
        BOOL hayMas = [json[@"hasMore"] boolValue];
        if (videos.count == 0 && !hayMas) hayMas = NO;
        completado(videos, siguiente, hayMas, nil);
    }];
}

#pragma mark - Detalle

- (void)detalleDeVideo:(NSString *)itemId
            completado:(void (^)(TTVideo *, NSError *))completado {
    if (itemId.length == 0) {
        completado(nil, TTError(TTErrorFormato, @"Falta el identificador del video"));
        return;
    }
    // Mismo conjunto de parametros que prototipo/probar.py (el endpoint que se
    // comprobo en vivo).
    NSMutableArray *pares = [NSMutableArray arrayWithArray:[[TTSesion compartida] paresBase]];
    [pares addObject:@[ @"browser_version", [[TTSesion compartida] userAgent] ]];
    [pares addObject:@[ @"coverFormat", @"2" ]];
    [pares addObject:@[ @"itemId", itemId ]];
    [pares addObject:@[ @"priority_region", @"US" ]];
    [pares addObject:@[ @"referer", @"" ]];
    [pares addObject:@[ @"screen_height", @"1080" ]];
    [pares addObject:@[ @"screen_width", @"1920" ]];
    [pares addObject:@[ @"webcast_language", @"en-US" ]];

    [self pedirRuta:@"/api/item/detail/" pares:pares completado:^(NSDictionary *json, NSError *error) {
        if (error) { completado(nil, error); return; }
        NSDictionary *item = json[@"itemInfo"][@"itemStruct"];
        TTVideo *v = [TTVideo desdeItemStruct:item];
        if (!v) {
            completado(nil, TTError(TTErrorVacio, @"La ficha del video vino sin datos"));
            return;
        }
        completado(v, nil);
    }];
}

#pragma mark - Diagnostico

- (void)probarConexion:(void (^)(NSString *, BOOL))completado {
    [self feedParaTiCursor:nil completado:^(NSArray *videos, NSString *cursor, BOOL hayMas, NSError *error) {
        if (error) {
            completado([NSString stringWithFormat:@"Fallo: %@", [TTCliente explicarError:error]], NO);
            return;
        }
        completado([NSString stringWithFormat:
            @"Correcto: el feed devolvio %lu videos (firmado en el telefono).",
            (unsigned long)videos.count], YES);
    }];
}

#pragma mark - Imagenes

static NSCache *TTCacheImagenes(void) {
    static NSCache *cache = nil;
    static dispatch_once_t vez;
    dispatch_once(&vez, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 120;
    });
    return cache;
}

+ (void)cargarImagen:(NSString *)url completado:(void (^)(UIImage *))completado {
    if (url.length == 0) { completado(nil); return; }
    UIImage *guardada = [TTCacheImagenes() objectForKey:url];
    if (guardada) { completado(guardada); return; }

    NSURL *u = [NSURL URLWithString:url];
    if (!u) { completado(nil); return; }

    NSMutableURLRequest *peticion = [NSMutableURLRequest requestWithURL:u];
    peticion.timeoutInterval = 20.0;
    // Las imagenes de TikTok no exigen firma; basta con un UA de navegador
    // para que el CDN no las corte.
    [peticion setValue:[[TTSesion compartida] userAgent] forHTTPHeaderField:@"User-Agent"];
    [peticion setValue:@"https://www.tiktok.com/" forHTTPHeaderField:@"Referer"];

    NSURLSessionDataTask *t = [[[TTCliente compartido] sesion]
        dataTaskWithRequest:peticion
          completionHandler:^(NSData *datos, NSURLResponse *respuesta, NSError *error) {
        UIImage *imagen = nil;
        if (datos.length && !error) {
            imagen = [UIImage imageWithData:datos];
        }
        if (imagen) [TTCacheImagenes() setObject:imagen forKey:url];
        dispatch_async(dispatch_get_main_queue(), ^{ completado(imagen); });
    }];
    [t resume];
}

+ (void)vaciarCacheImagenes {
    [TTCacheImagenes() removeAllObjects];
}

#pragma mark - Errores

+ (NSString *)explicarError:(NSError *)error {
    if (!error) return @"Error desconocido";
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorNotConnectedToInternet:
                return @"Sin conexion a Internet.";
            case NSURLErrorTimedOut:
                return @"TikTok tardo demasiado. Prueba otra vez.";
            case NSURLErrorCannotFindHost:
            case NSURLErrorCannotConnectToHost:
                return @"No se pudo llegar a TikTok (revisa la red o los certificados).";
            case NSURLErrorSecureConnectionFailed:
            case NSURLErrorServerCertificateUntrusted:
                return @"iOS 9 no confia en el certificado de TikTok. Instala las raices modernas (ver README).";
            default:
                break;
        }
    }
    return error.localizedDescription ?: @"Error desconocido";
}

@end
