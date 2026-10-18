// TTSesion.m
#import "TTSesion.h"
#import "TTSignaCore.h"

static NSString * const kDefDispositivo = @"tik9_dispositivo";
static NSString * const kDefCookies     = @"tik9_cookies";
static NSString * const kDefMsToken     = @"tik9_mstoken";

// Una pagina publica que entrega la cookie ttwid (la identidad anonima que la
// busqueda exige).  La portada no la da: hay que pedir una pagina de contenido.
static NSString * const kUrlIdentidad   = @"https://www.tiktok.com/foryou";

@implementation TTSesion

+ (instancetype)compartida {
    static TTSesion *una = nil;
    static dispatch_once_t vez;
    dispatch_once(&vez, ^{
        una = [[TTSesion alloc] init];
        // Las cookies que TikTok manda en sus respuestas (ttwid, msToken...) se
        // guardan siempre: son la identidad anonima con la que trabaja la app.
        [[NSHTTPCookieStorage sharedHTTPCookieStorage]
            setCookieAcceptPolicy:NSHTTPCookieAcceptPolicyAlways];
    });
    return una;
}

#pragma mark - Dispositivo

- (NSString *)dispositivoId {
    NSUserDefaults *ajustes = [NSUserDefaults standardUserDefaults];
    NSString *guardado = [ajustes stringForKey:kDefDispositivo];
    if (guardado.length == 19) return guardado;

    // 7 + 18 cifras, como los identificadores de dispositivo de TikTok.
    NSMutableString *id = [NSMutableString stringWithString:@"7"];
    for (int i = 0; i < 18; i++) {
        [id appendFormat:@"%d", arc4random_uniform(10)];
    }
    [ajustes setObject:id forKey:kDefDispositivo];
    [ajustes synchronize];
    return id;
}

#pragma mark - Cookies y token

- (NSString *)cookiesManuales {
    NSString *crudo = [[NSUserDefaults standardUserDefaults] stringForKey:kDefCookies];
    return crudo.length ? crudo : @"";
}

- (void)guardarCookiesManuales:(NSString *)crudo {
    NSUserDefaults *ajustes = [NSUserDefaults standardUserDefaults];
    NSString *limpio = [crudo stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (limpio.length) {
        // Si el usuario pega una linea "Cookie: a=b; c=d", se deja solo lo de
        // despues de los dos puntos.
        NSRange dosPuntos = [limpio rangeOfString:@":"];
        if (dosPuntos.location != NSNotFound &&
            dosPuntos.location < 10) {
            limpio = [[limpio substringFromIndex:dosPuntos.location + 1]
                      stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        [ajustes setObject:limpio forKey:kDefCookies];
    } else {
        [ajustes removeObjectForKey:kDefCookies];
    }
    [ajustes synchronize];
}

- (BOOL)hayCookies {
    return [self cookiesManuales].length > 0;
}

// Busca "clave=valor" dentro de la cabecera Cookie cruda.
- (NSString *)valorDeCookie:(NSString *)clave {
    NSString *crudo = [self cookiesManuales];
    if (crudo.length == 0) return @"";
    for (NSString *trozo in [crudo componentsSeparatedByString:@";"]) {
        NSString *limpio = [trozo stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceCharacterSet]];
        NSRange igual = [limpio rangeOfString:@"="];
        if (igual.location == NSNotFound) continue;
        NSString *nombre = [limpio substringToIndex:igual.location];
        if ([nombre isEqualToString:clave]) {
            return [limpio substringFromIndex:igual.location + 1];
        }
    }
    return @"";
}

- (NSString *)msToken {
    NSString *pegada = [self valorDeCookie:@"msToken"];
    if (pegada.length) return pegada;

    // El ultimo que regalo TikTok en una cabecera x-ms-token.
    NSString *aprendida = [[NSUserDefaults standardUserDefaults] stringForKey:kDefMsToken];
    if (aprendida.length) return aprendida;

    // Por si una sesion web previa dejo la cookie en el almacen del sistema.
    NSString *delAlmacen = [self valorDeCookieDelAlmacen:@"msToken"];
    if (delAlmacen.length) return delAlmacen;
    return @"";
}

- (void)guardarMsTokenAprendido:(NSString *)token {
    NSString *limpio = [token stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (limpio.length == 0) return;
    NSUserDefaults *ajustes = [NSUserDefaults standardUserDefaults];
    [ajustes setObject:limpio forKey:kDefMsToken];
    [ajustes synchronize];
}

#pragma mark - Identidad anonima (ttwid)

// Busca una cookie en el almacen del sistema (las que guarda NSURLSession).
- (NSString *)valorDeCookieDelAlmacen:(NSString *)clave {
    for (NSHTTPCookie *c in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if ([c.name isEqualToString:clave] && c.value.length &&
            [c.domain rangeOfString:@"tiktok"].location != NSNotFound) {
            return c.value;
        }
    }
    return @"";
}

- (BOOL)hayIdentidad {
    return [self valorDeCookieDelAlmacen:@"ttwid"].length > 0 ||
           [self valorDeCookie:@"ttwid"].length > 0;
}

- (void)prepararIdentidad:(void (^)(BOOL))completado {
    if ([self hayIdentidad]) { completado(YES); return; }

    // Una sola carga a la vez, aunque varias pantallas la pidan.
    static BOOL preparando = NO;
    static NSMutableArray *pendientes = nil;
    if (preparando) {
        if (!pendientes) pendientes = [NSMutableArray array];
        [pendientes addObject:[completado copy]];
        return;
    }
    preparando = YES;
    if (!pendientes) pendientes = [NSMutableArray array];
    [pendientes addObject:[completado copy]];

    NSURL *url = [NSURL URLWithString:kUrlIdentidad];
    NSMutableURLRequest *peticion = [NSMutableURLRequest requestWithURL:url];
    peticion.HTTPMethod = @"GET";
    peticion.timeoutInterval = 25.0;
    [peticion setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
    [peticion setValue:@"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
     forHTTPHeaderField:@"Accept"];
    [peticion setValue:@"es-ES,es;q=0.9,en;q=0.8" forHTTPHeaderField:@"Accept-Language"];

    // sharedSession guarda las Set-Cookie en el almacen compartido, que es de
    // donde las lee hayIdentidad y cookieDeSesion.
    NSURLSessionDataTask *tarea = [[NSURLSession sharedSession]
        dataTaskWithRequest:peticion
          completionHandler:^(NSData *datos, NSURLResponse *respuesta, NSError *error) {
        (void)datos; (void)respuesta; (void)error;
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL lograda = [self hayIdentidad];
            NSArray *esperando = [pendientes copy];
            [pendientes removeAllObjects];
            preparando = NO;
            for (void (^bloque)(BOOL) in esperando) bloque(lograda);
        });
    }];
    [tarea resume];
}

- (void)olvidarIdentidad {
    NSHTTPCookieStorage *almacen = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *c in [almacen cookies]) {
        if ([c.domain rangeOfString:@"tiktok"].location != NSNotFound) {
            [almacen deleteCookie:c];
        }
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefMsToken];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Une las cookies del almacen (ttwid, tt_chain_token, msToken...) con las
// pegadas a mano, que mandan si coinciden en el nombre.
- (NSString *)cookieDeSesion {
    NSMutableDictionary *porNombre = [NSMutableDictionary dictionary];
    for (NSHTTPCookie *c in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if (c.value.length && [c.domain rangeOfString:@"tiktok"].location != NSNotFound) {
            porNombre[c.name] = c.value;
        }
    }
    for (NSString *trozo in [[self cookiesManuales] componentsSeparatedByString:@";"]) {
        NSString *limpio = [trozo stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceCharacterSet]];
        NSRange igual = [limpio rangeOfString:@"="];
        if (igual.location == NSNotFound || igual.location == 0) continue;
        porNombre[[limpio substringToIndex:igual.location]] =
            [limpio substringFromIndex:igual.location + 1];
    }

    NSMutableArray *pares = [NSMutableArray array];
    for (NSString *nombre in porNombre) {
        [pares addObject:[NSString stringWithFormat:@"%@=%@", nombre, porNombre[nombre]]];
    }
    return [pares componentsJoinedByString:@"; "];
}

#pragma mark - Cabeceras

- (NSString *)userAgent {
    // El mismo literal que usa el firmador en C: la firma cubre el UA.
    return [NSString stringWithUTF8String:tt_ua_por_defecto()];
}

- (NSDictionary *)cabecerasBase {
    NSMutableDictionary *c = [NSMutableDictionary dictionary];
    c[@"User-Agent"] = [self userAgent];
    c[@"Accept"] = @"application/json, text/plain, */*";
    c[@"Accept-Language"] = @"en-US,en;q=0.9";
    c[@"Referer"] = @"https://www.tiktok.com/";
    c[@"Origin"] = @"https://www.tiktok.com";
    NSString *cookies = [self cookieDeSesion];
    if (cookies.length) c[@"Cookie"] = cookies;
    return c;
}

#pragma mark - Parametros de negocio

- (NSArray *)paresBase {
    // Copiados de la web (ver prototipo/probar_listas.py: params_recomendados).
    // Es el conjunto exacto con el que se comprobo que el feed "Para ti"
    // responde.  El orden importa: la firma cubre la cadena de consulta exacta.
    return @[
        @[ @"aid",              @"1988" ],
        @[ @"app_language",     @"en-US" ],
        @[ @"app_name",         @"tiktok_web" ],
        @[ @"browser_language", @"en-US" ],
        @[ @"browser_name",     @"Mozilla" ],
        @[ @"browser_online",   @"true" ],
        @[ @"browser_platform", @"Win32" ],
        @[ @"channel",          @"tiktok_web" ],
        @[ @"cookie_enabled",   @"true" ],
        @[ @"device_id",        [self dispositivoId] ],
        @[ @"device_platform",  @"web_pc" ],
        @[ @"os",               @"windows" ],
        @[ @"region",           @"US" ],
        @[ @"tz_name",          @"America/New_York" ]
    ];
}

- (void)olvidarTodo {
    NSUserDefaults *ajustes = [NSUserDefaults standardUserDefaults];
    [ajustes removeObjectForKey:kDefDispositivo];
    [ajustes removeObjectForKey:kDefCookies];
    [ajustes removeObjectForKey:kDefMsToken];
    [ajustes synchronize];
    [self olvidarIdentidad];
}

@end
