// TTResolvedor.m
#import "TTResolvedor.h"
#import "TTSesion.h"
#import "TTCliente.h"

static NSString * const kDefModo  = @"tik9_res_modo";
static NSString * const kDefRelay = @"tik9_res_relay";
static NSString * const kDefToken = @"tik9_res_token";

// Escapa un valor para meterlo en una cadena de consulta (deja solo lo que
// nunca necesita escaparse).
static NSString *TTEscapar(NSString *texto) {
    NSCharacterSet *permitidos = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [texto stringByAddingPercentEncodingWithAllowedCharacters:permitidos] ?: @"";
}

// Todas las respuestas salen por el hilo principal: quien las recibe toca
// interfaz (celdas, botones) y NSURLSession contesta en segundo plano.
static void TTResponder(void (^completado)(NSDictionary *, NSError *),
                        NSDictionary *resultado, NSError *error) {
    if (!completado) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completado(resultado, error); });
}

// Cuanto dura una direccion ya resuelta antes de volver a pedirla.  La direccion
// del CDN lleva dentro su propio token de caducidad (horas), asi que diez
// minutos es prudente y suficiente para ir y volver por el feed.
static const NSTimeInterval TTCacheSegundos = 600.0;
static const NSUInteger TTCacheMaximo = 60;

@interface TTResolvedor ()
@property (nonatomic, strong) NSMutableDictionary *cache;     // id -> resultado
@property (nonatomic, strong) NSMutableDictionary *enCurso;   // id -> cola de bloques
@end

@implementation TTResolvedor

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSMutableDictionary dictionary];
        _enCurso = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (instancetype)compartido {
    static TTResolvedor *una = nil;
    static dispatch_once_t vez;
    dispatch_once(&vez, ^{ una = [[TTResolvedor alloc] init]; });
    return una;
}

#pragma mark - Configuracion

+ (NSString *)modo {
    NSString *m = [[NSUserDefaults standardUserDefaults] stringForKey:kDefModo];
    if ([m isEqualToString:@"directo"] || [m isEqualToString:@"relay"]) return m;
    return @"auto";
}

+ (void)guardarModo:(NSString *)modo {
    NSUserDefaults *a = [NSUserDefaults standardUserDefaults];
    [a setObject:(modo ?: @"auto") forKey:kDefModo];
    [a synchronize];
}

+ (NSString *)relayBase {
    NSString *b = [[NSUserDefaults standardUserDefaults] stringForKey:kDefRelay];
    b = [b stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([b hasSuffix:@"/"]) b = [b substringToIndex:b.length - 1];
    if (b.length && ![b hasPrefix:@"http://"] && ![b hasPrefix:@"https://"]) {
        b = [@"http://" stringByAppendingString:b];
    }
    return b ?: @"";
}

+ (NSString *)relayToken {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kDefToken] ?: @"";
}

+ (BOOL)hayRelay {
    return [self relayBase].length > 8;   // algo mas que "http://"
}

+ (void)guardarRelay:(NSString *)base token:(NSString *)token {
    NSUserDefaults *a = [NSUserDefaults standardUserDefaults];
    NSString *b = [base stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (b.length) [a setObject:b forKey:kDefRelay]; else [a removeObjectForKey:kDefRelay];
    if (token.length) [a setObject:token forKey:kDefToken]; else [a removeObjectForKey:kDefToken];
    [a synchronize];
}

#pragma mark - Cabeceras del CDN

// Cabeceras que exige el CDN de TikTok.  Medido en vivo: lo UNICO
// imprescindible es el Referer de www.tiktok.com (sin el, 403); el UA puede ser
// cualquiera.  Se manda tambien un UA de navegador por si acaso.
- (NSDictionary *)cabecerasDeVideo {
    NSMutableDictionary *c = [NSMutableDictionary dictionary];
    c[@"User-Agent"] = [[TTSesion compartida] userAgent];
    c[@"Referer"] = @"https://www.tiktok.com/";
    c[@"Accept"] = @"video/mp4,video/*;q=0.9,*/*;q=0.8";
    c[@"Accept-Language"] = @"en-US,en;q=0.9";
    NSString *cookies = [[TTSesion compartida] cookiesManuales];
    if (cookies.length) c[@"Cookie"] = cookies;
    return c;
}

#pragma mark - Directo

- (void)resolverDirecto:(TTVideo *)video
              completado:(void (^)(NSDictionary *resultado, NSError *error))completado {
    NSArray *urls = video.urlsDirectas;
    if (urls.count == 0) {
        TTResponder(completado, nil, [self error:@"El video no trae direccion de reproduccion"]);
        return;
    }

    // Casi siempre acierta la primera (las /aweme/v1/play/ van delante); se
    // prueban unas pocas por si alguna caduca.
    NSArray *aProbar = urls.count > 4 ? [urls subarrayWithRange:NSMakeRange(0, 4)] : urls;
    [self probarDirecto:aProbar indice:0 completado:completado];
}

- (void)probarDirecto:(NSArray *)urls
               indice:(NSUInteger)indice
           completado:(void (^)(NSDictionary *, NSError *))completado {
    if (indice >= urls.count) {
        TTResponder(completado, nil, [self error:
            @"TikTok no entrego el video (puede que la direccion haya caducado). "
             "Vuelve a deslizar; si sigue igual, configura el relay en Ajustes."]);
        return;
    }
    NSString *urlTexto = urls[indice];
    NSURL *url = [NSURL URLWithString:urlTexto];
    if (!url) {
        [self probarDirecto:urls indice:indice + 1 completado:completado];
        return;
    }

    NSDictionary *cabeceras = [self cabecerasDeVideo];
    NSMutableURLRequest *peticion = [NSMutableURLRequest requestWithURL:url];
    peticion.timeoutInterval = 12.0;
    // Solo un byte: basta para leer el codigo y, sobre todo, para SEGUIR EL
    // REDIRECT y capturar la direccion final del CDN (que es la que se le da a
    // AVPlayer).  Asi AVPlayer no sigue el 302 ni se le pierde el Referer.
    [peticion setValue:@"bytes=0-0" forHTTPHeaderField:@"Range"];
    for (NSString *c in cabeceras) [peticion setValue:cabeceras[c] forHTTPHeaderField:c];

    __weak TTResolvedor *deb = self;
    NSURLSessionDataTask *t = [[TTCliente sesionCompartida]
        dataTaskWithRequest:peticion
          completionHandler:^(NSData *datos, NSURLResponse *respuesta, NSError *error) {
        TTResolvedor *yo = deb;
        if (!yo) return;
        NSInteger codigo = [respuesta isKindOfClass:[NSHTTPURLResponse class]]
                           ? [(NSHTTPURLResponse *)respuesta statusCode] : 0;
        if (!error && (codigo == 200 || codigo == 206)) {
            // respuesta.URL ya es la direccion final tras los redirects.
            NSURL *final = respuesta.URL ?: url;
            TTResponder(completado, @{ @"url"        : final,
                                       @"url_origen" : url,
                                       @"cabeceras"  : cabeceras,
                                       @"motor"      : @"directo" }, nil);
            return;
        }
        [yo probarDirecto:urls indice:indice + 1 completado:completado];
    }];
    [t resume];
}

#pragma mark - Relay

- (NSURL *)urlRelay:(NSString *)recurso parametros:(NSString *)parametros {
    NSString *base = [TTResolvedor relayBase];
    if (base.length == 0) return nil;
    NSString *texto = [NSString stringWithFormat:@"%@/api/%@", base, recurso];
    if (parametros.length) texto = [texto stringByAppendingString:parametros];
    return [NSURL URLWithString:texto];
}

- (void)pedirJSONAlRelay:(NSString *)recurso
              parametros:(NSString *)parametros
              completado:(void (^)(NSDictionary *json, NSError *error))completado {
    NSURL *url = [self urlRelay:recurso parametros:parametros];
    if (!url) {
        TTResponder(completado, nil, [self error:@"No hay relay configurado"]);
        return;
    }
    NSMutableURLRequest *peticion = [NSMutableURLRequest requestWithURL:url];
    peticion.timeoutInterval = 30.0;
    NSString *token = [TTResolvedor relayToken];
    if (token.length) [peticion setValue:token forHTTPHeaderField:@"X-Tik9-Token"];

    NSURLSessionDataTask *t = [[TTCliente sesionCompartida]
        dataTaskWithRequest:peticion
          completionHandler:^(NSData *datos, NSURLResponse *respuesta, NSError *error) {
        if (error) {
            TTResponder(completado, nil, [NSError errorWithDomain:@"Tik9" code:2 userInfo:@{
                NSLocalizedDescriptionKey :
                    [NSString stringWithFormat:@"No se pudo llegar al relay: %@",
                     error.localizedDescription] }]);
            return;
        }
        NSError *jerror = nil;
        id json = [NSJSONSerialization JSONObjectWithData:datos options:0 error:&jerror];
        if (![json isKindOfClass:[NSDictionary class]]) {
            TTResponder(completado, nil, [self error:@"El relay no devolvio JSON"]);
            return;
        }
        TTResponder(completado, json, nil);
    }];
    [t resume];
}

- (void)resolverRelay:(TTVideo *)video
           completado:(void (^)(NSDictionary *resultado, NSError *error))completado {
    // Se le pasa al relay el identificador y, si la app lo tiene, la direccion
    // firmada del propio feed: asi el relay NO necesita firmar nada (es Python
    // puro, sin dependencias) y solo hace de puente por HTTP plano.
    NSMutableString *parametros = [NSMutableString stringWithFormat:@"?id=%@",
                                   TTEscapar(video.identificador)];
    NSString *u = [video mejorUrlDirecta];
    if (u.length) [parametros appendFormat:@"&u=%@", TTEscapar(u)];

    __weak TTResolvedor *deb = self;
    [self pedirJSONAlRelay:@"stream" parametros:parametros completado:^(NSDictionary *json, NSError *error) {
        TTResolvedor *yo = deb;
        if (!yo) return;
        if (error) { TTResponder(completado, nil, error); return; }
        if (![json[@"ok"] boolValue]) {
            NSString *mensaje = [json[@"error"] isKindOfClass:[NSString class]]
                                ? json[@"error"] : @"El relay no pudo resolver el video";
            TTResponder(completado, nil, [yo error:mensaje]);
            return;
        }
        // Se prefiere el proxy: pasa por el relay, que pone las cabeceras y el
        // TLS correctos, y va por HTTP plano (sin lios de certificados en iOS 9).
        NSString *proxy = json[@"url_proxy"];
        if ([proxy isKindOfClass:[NSString class]] && proxy.length) {
            TTResponder(completado, @{ @"url"     : [NSURL URLWithString:proxy],
                                       @"cabeceras": @{},
                                       @"motor"   : @"relay" }, nil);
            return;
        }
        NSString *directa = json[@"url"];
        if ([directa isKindOfClass:[NSString class]] && directa.length) {
            TTResponder(completado, @{ @"url"     : [NSURL URLWithString:directa],
                                       @"cabeceras": [yo cabecerasDeVideo],
                                       @"motor"   : @"relay-directo" }, nil);
            return;
        }
        TTResponder(completado, nil, [yo error:@"El relay respondio sin direccion de video"]);
    }];
}

#pragma mark - Cache y precarga

// Clave del video: el identificador y, si no lo hubiera, la direccion firmada.
- (NSString *)claveDe:(TTVideo *)video {
    if (video.identificador.length) return video.identificador;
    return [video mejorUrlDirecta] ?: @"";
}

- (NSDictionary *)resultadoCacheadoPara:(NSString *)clave {
    if (clave.length == 0) return nil;
    NSDictionary *entrada = self.cache[clave];
    if (![entrada isKindOfClass:[NSDictionary class]]) return nil;
    NSDate *fecha = entrada[@"fecha"];
    // timeIntervalSinceNow es positivo cuando la fecha ya quedo atras.
    if (![fecha isKindOfClass:[NSDate class]] || -[fecha timeIntervalSinceNow] > TTCacheSegundos) {
        [self.cache removeObjectForKey:clave];
        return nil;
    }
    NSDictionary *guardado = entrada[@"resultado"];
    return [guardado isKindOfClass:[NSDictionary class]] ? guardado : nil;
}

- (void)guardar:(NSDictionary *)resultado para:(NSString *)clave {
    if (clave.length == 0 || ![resultado isKindOfClass:[NSDictionary class]]) return;
    if (self.cache.count >= TTCacheMaximo) {
        NSMutableArray *fuera = [NSMutableArray array];
        for (NSString *k in self.cache) {
            NSDictionary *e = self.cache[k];
            NSDate *f = [e isKindOfClass:[NSDictionary class]] ? e[@"fecha"] : nil;
            if (![f isKindOfClass:[NSDate class]] || -[f timeIntervalSinceNow] > TTCacheSegundos) {
                [fuera addObject:k];
            }
        }
        if (fuera.count) [self.cache removeObjectsForKeys:fuera];
    }
    self.cache[clave] = @{ @"fecha": [NSDate date], @"resultado": resultado };
}

- (void)vaciarCache {
    [self.cache removeAllObjects];
}

- (void)olvidarVideo:(TTVideo *)video {
    NSString *clave = [self claveDe:video];
    if (clave.length) [self.cache removeObjectForKey:clave];
}

- (void)prepararVideo:(TTVideo *)video {
    if (!video) return;
    NSString *clave = [self claveDe:video];
    if (clave.length == 0) return;
    if ([self resultadoCacheadoPara:clave]) return;   // ya esta
    if (self.enCurso[clave]) return;                  // ya se esta pidiendo
    // A quien llama no le interesa el resultado: queda guardado en la cache.
    [self resolverVideo:video completado:^(NSDictionary *resultado, NSError *error) {
        (void)resultado;
        (void)error;
    }];
}

#pragma mark - Entrada

- (void)resolverVideo:(TTVideo *)video
           completado:(void (^)(NSDictionary *, NSError *))completado {
    if (!video) {
        TTResponder(completado, nil, [self error:@"No hay video que resolver"]);
        return;
    }
    NSString *clave = [self claveDe:video];

    // 1) Resuelta hace poco: se contesta al momento.  Esto es lo que hace que
    //    ir y volver por el feed (o llegar a un video precargado) sea inmediato.
    NSDictionary *guardado = [self resultadoCacheadoPara:clave];
    if (guardado) { TTResponder(completado, guardado, nil); return; }

    // 2) El mismo video ya se esta resolviendo (la precarga del feed y el
    //    usuario llegando a el a la vez): se apunta a la cola, y cuando llegue
    //    el resultado se avisa a todos.  Una sola peticion para todos.
    NSMutableArray *esperando = self.enCurso[clave];
    if (esperando) {
        if (completado) [esperando addObject:[completado copy]];
        return;
    }
    NSMutableArray *cola = [NSMutableArray array];
    if (completado) [cola addObject:[completado copy]];
    self.enCurso[clave] = cola;

    __weak TTResolvedor *deb = self;
    [self resolverDeVerdad:video completado:^(NSDictionary *resultado, NSError *error) {
        TTResolvedor *yo = deb;
        if (!yo) return;
        NSArray *pendientes = yo.enCurso[clave];
        [yo.enCurso removeObjectForKey:clave];
        if (resultado) [yo guardar:resultado para:clave];
        for (id nodo in pendientes) {
            void (^bloque)(NSDictionary *, NSError *) = (void (^)(NSDictionary *, NSError *))nodo;
            TTResponder(bloque, resultado, error);
        }
    }];
}

// El motor de verdad: directo y, solo si falla, el relay.  Sin cache ni colas.
- (void)resolverDeVerdad:(TTVideo *)video
              completado:(void (^)(NSDictionary *, NSError *))completado {
    NSString *modo = [TTResolvedor modo];
    BOOL hayRelay = [TTResolvedor hayRelay];

    if ([modo isEqualToString:@"relay"]) {
        if (hayRelay) { [self resolverRelay:video completado:completado]; return; }
        TTResponder(completado, nil, [self error:@"Modo relay elegido pero no hay relay configurado."]);
        return;
    }

    // Directo primero (es el camino normal: el itemStruct ya trae la direccion
    // firmada y el CDN solo pide el Referer).  Si falla, se prueba el relay.
    __weak TTResolvedor *deb = self;
    [self resolverDirecto:video completado:^(NSDictionary *resultado, NSError *error1) {
        TTResolvedor *yo = deb;
        if (!yo) return;
        if (resultado) { TTResponder(completado, resultado, nil); return; }
        if ([modo isEqualToString:@"directo"] || !hayRelay) {
            TTResponder(completado, nil, error1);
            return;
        }
        [yo resolverRelay:video completado:completado];
    }];
}

#pragma mark - Diagnostico

- (void)probarRelay:(void (^)(NSString *, BOOL))completado {
    if (![TTResolvedor hayRelay]) {
        if (completado) dispatch_async(dispatch_get_main_queue(), ^{ completado(@"No hay relay configurado.", NO); });
        return;
    }
    [self pedirJSONAlRelay:@"health" parametros:@"" completado:^(NSDictionary *json, NSError *error) {
        NSString *texto;
        BOOL bien = (error == nil);
        if (error) {
            texto = [error localizedDescription];
        } else {
            NSString *servicio = [json[@"servicio"] isKindOfClass:[NSString class]]
                                 ? json[@"servicio"] : @"relay";
            NSString *version = [json[@"version"] isKindOfClass:[NSString class]]
                                ? json[@"version"] : @"?";
            texto = [NSString stringWithFormat:@"Relay OK: %@ %@", servicio, version];
        }
        if (completado) dispatch_async(dispatch_get_main_queue(), ^{ completado(texto, bien); });
    }];
}

#pragma mark - Auxiliar

- (NSError *)error:(NSString *)texto {
    return [NSError errorWithDomain:@"Tik9" code:3
                           userInfo:@{ NSLocalizedDescriptionKey : texto }];
}

@end
