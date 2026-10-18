// TTSesion.m
#import "TTSesion.h"
#import "TTSignaCore.h"

static NSString * const kDefDispositivo = @"tik9_dispositivo";
static NSString * const kDefCookies     = @"tik9_cookies";

@implementation TTSesion

+ (instancetype)compartida {
    static TTSesion *una = nil;
    static dispatch_once_t vez;
    dispatch_once(&vez, ^{ una = [[TTSesion alloc] init]; });
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
    NSString *deCookie = [self valorDeCookie:@"msToken"];
    if (deCookie.length) return deCookie;

    // Por si una sesion web previa dejo la cookie en el almacen del sistema.
    NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies];
    for (NSHTTPCookie *c in cookies) {
        if ([c.name isEqualToString:@"msToken"] && c.value.length) return c.value;
    }
    return @"";
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
    NSString *cookies = [self cookiesManuales];
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
    [ajustes synchronize];
}

@end
