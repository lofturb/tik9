// TTCliente.m
#import "TTCliente.h"
#import "TTSesion.h"
#import "TTSignaCore.h"
#import "TTResolvedor.h"
#import "TTTunel.h"
#import <Security/Security.h>
#import <CFNetwork/CFNetwork.h>
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <stdlib.h>
#import <string.h>

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

// Mira quien firma el certificado de la conexion.  Sirve para saber si hay un
// intermediario (un proxy, una VPN, un bloqueador) cortando el trafico: si la
// cadena no la firma una autoridad publica conocida, ese es el problema -- y su
// nombre suele salir en la lista.  La implementacion esta al final del fichero.
@interface TTCertificados : NSObject <NSURLSessionDelegate>
@property (nonatomic, strong) NSMutableArray *apuntes;
@end

// Metodos internos, declarados antes de usarlos para no depender del orden del
// fichero.
@interface TTCliente ()
// Se pone a SI en cuanto una prueba de la bateria trae videos: entonces ya no
// hace falta seguir probando variantes (y el diagnostico dura mucho menos).
@property (nonatomic) BOOL bateriaLograda;
- (NSString *)firmarPares:(NSArray *)pares;
- (NSString *)firmarPares:(NSArray *)pares conUA:(NSString *)ua;
- (NSString *)cabecera:(NSString *)nombre de:(NSHTTPURLResponse *)respuesta;
- (NSString *)msTokenDeRespuesta:(NSHTTPURLResponse *)respuesta;
- (NSInteger)estadoDeBusqueda:(NSDictionary *)json;
- (NSArray *)paresDeBusqueda:(NSString *)palabra;
- (NSArray *)paresDeBusqueda:(NSString *)palabra conBase:(NSArray *)base;
- (NSArray *)paresBaseDeIPad;
- (NSString *)uaDeSafariDelAparato;
- (void)bateriaDeBusqueda:(NSString *)palabra
                   lineas:(NSMutableArray *)lineas
               completado:(void (^)(void))completado;
- (void)casoDeBateria:(NSArray *)casos
                indice:(NSInteger)indice
                lineas:(NSMutableArray *)lineas
            completado:(void (^)(void))completado;
- (void)intentoDeCaso:(NSDictionary *)caso
              intento:(NSInteger)intento
                pasos:(NSMutableArray *)pasos
               lineas:(NSMutableArray *)lineas
           completado:(void (^)(void))completado;
- (void)intentoDeTunel:(NSDictionary *)caso
               intento:(NSInteger)intento
                 pasos:(NSMutableArray *)pasos
                lineas:(NSMutableArray *)lineas
            completado:(void (^)(void))completado;
// Las cabeceras de un navegador de verdad (el mismo Chrome/Edge que dice el
// User-Agent), en el orden en que las manda, como parejas nombre/valor.
- (NSArray *)cabecerasDeNavegadorConUA:(NSString *)ua
                               referer:(NSString *)referer
                                cookie:(NSString *)cookie;
// Una peticion por el tunel, ya resuelta a objetos de Objective-C.  Bloquea:
// se llama desde una cola de fondo.
- (NSDictionary *)pedirPorElTunelHost:(NSString *)host
                                 ruta:(NSString *)ruta
                           cabeceras:(NSArray *)cabeceras;
// Un texto apto para ir en una dirección (la palabra buscada, por ejemplo).
- (NSString *)escapadoDeURL:(NSString *)texto;
// Un recorte del cuerpo, en una linea, para ver que contesta el borde cuando
// dice que no (un 403 de Akamai o de TikTok se entiende leyendolo).
- (NSString *)recorteDeCuerpo:(NSData *)datos;
// La misma peticion barata con el saludo completo y quitando una pieza cada
// vez: aisla cual de las extensiones nuevas hace saltar el 403.
- (void)casoDeSondasPorElTunel:(NSMutableArray *)lineas
                    completado:(void (^)(void))completado;
// Mide la huella del tunel contra el oraculo publico tls.peet.ws y la compara
// con la de un Chrome que si entra.
- (void)casoDeHuellaPorElTunel:(NSMutableArray *)lineas
                    completado:(void (^)(void))completado;
// Pide una identidad nueva (ttwid) por el propio tunel y repite la busqueda con
// ella: sirve para saber si la barrera ata la identidad a la conexion.
- (void)casoDeIdentidadPorElTunel:(NSString *)palabra
                           lineas:(NSMutableArray *)lineas
                       completado:(void (^)(void))completado;
- (NSArray *)videosDeRespuestaDeBusqueda:(NSDictionary *)json;
- (void)pedirRuta:(NSString *)ruta
            pares:(NSArray *)pares
       completado:(void (^)(NSDictionary *json, NSError *error))completado;
- (void)pedirRuta:(NSString *)ruta
            pares:(NSArray *)pares
     conRespuesta:(void (^)(NSDictionary *json, NSHTTPURLResponse *respuesta,
                            NSError *error))completado;
- (void)pedirRutaCrudo:(NSString *)ruta
                 pares:(NSArray *)pares
            completado:(void (^)(NSData *datos, NSHTTPURLResponse *respuesta,
                                 NSError *error))completado;
- (void)pedirRutaCrudo:(NSString *)ruta
                 pares:(NSArray *)pares
                    ua:(NSString *)ua
                omitir:(NSArray *)omitir
            completado:(void (^)(NSData *datos, NSHTTPURLResponse *respuesta,
                                 NSError *error))completado;
- (void)buscarPalabra:(NSString *)palabra
               intento:(NSInteger)intento
            completado:(TTBloqueFeed)completado;
- (NSArray *)paresDeFeedConCursor:(NSString *)cursor conLosDeBusqueda:(BOOL)conBusqueda;
- (void)sonda:(NSString *)etiqueta
         ruta:(NSString *)ruta
        pares:(NSArray *)pares
       lineas:(NSMutableArray *)lineas
   completado:(void (^)(void))completado;
- (void)sonda:(NSString *)etiqueta
         ruta:(NSString *)ruta
        pares:(NSArray *)pares
       intento:(NSInteger)intento
         pasos:(NSMutableArray *)pasos
       lineas:(NSMutableArray *)lineas
   completado:(void (^)(void))completado;
- (void)ecoDeProtocolo:(NSMutableArray *)lineas completado:(void (^)(void))completado;
- (void)sondaDeCertificado:(NSMutableArray *)lineas completado:(void (^)(void))completado;
- (void)sondaDeIntermediario:(NSMutableArray *)lineas completado:(void (^)(void))completado;
- (void)sondaDeProxy:(NSMutableArray *)lineas completado:(void (^)(void))completado;
- (void)sondaDeRelay:(NSMutableArray *)lineas completado:(void (^)(void))completado;
- (void)rematarInforme:(NSMutableArray *)lineas;
@end

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
        // La cabecera Cookie la pone la app (TTSesion cookieDeSesion); asi se
        // manda exactamente la que la firma espera.  Las Set-Cookie de TikTok
        // se siguen guardando en el almacen compartido (de ahi sale ttwid).
        cfg.HTTPShouldSetCookies = NO;
        sesion = [NSURLSession sessionWithConfiguration:cfg];
    });
    return sesion;
}

#pragma mark - Firma

// Firma la lista de pares con el port en C y devuelve la cadena de consulta.
// Los objetos NSString se retienen durante la llamada: UTF8String solo es
// valido mientras viven.
- (NSString *)firmarPares:(NSArray *)pares {
    return [self firmarPares:pares conUA:[[TTSesion compartida] userAgent]];
}

// La firma cubre el User-Agent, asi que cuando se prueba con otro UA (el de
// Safari, sin ir mas lejos) hay que firmar con ese mismo.
- (NSString *)firmarPares:(NSArray *)pares conUA:(NSString *)ua {
    TTSesion *ses = [TTSesion compartida];
    if (ua.length == 0) ua = [ses userAgent];
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

    [self pedirRuta:ruta pares:pares
       conRespuesta:^(NSDictionary *json, NSHTTPURLResponse *respuesta, NSError *error) {
        (void)respuesta;
        completado(json, error);
    }];
}

// Firma, manda y devuelve los bytes tal cual (sin interpretarlos).  La usan
// pedirRuta:conRespuesta: y el diagnostico de la busqueda, que necesita contar
// bytes y mirar cabeceras.
- (void)pedirRutaCrudo:(NSString *)ruta
                 pares:(NSArray *)pares
            completado:(void (^)(NSData *datos, NSHTTPURLResponse *respuesta,
                                 NSError *error))completado {
    [self pedirRutaCrudo:ruta pares:pares ua:nil omitir:nil completado:completado];
}

// Igual, pero eligiendo con que User-Agent se firma y que cabeceras se dejan
// fuera.  Lo usa la bateria del diagnostico para probar variantes sin tocar la
// busqueda de verdad.
- (void)pedirRutaCrudo:(NSString *)ruta
                 pares:(NSArray *)pares
                    ua:(NSString *)ua
                omitir:(NSArray *)omitir
            completado:(void (^)(NSData *datos, NSHTTPURLResponse *respuesta,
                                 NSError *error))completado {

    NSString *uaUsado = ua.length ? ua : [[TTSesion compartida] userAgent];
    NSString *firmado = [self firmarPares:pares conUA:uaUsado];
    if (firmado.length == 0) {
        completado(nil, nil, TTError(TTErrorFirma, @"No se pudo firmar la peticion"));
        return;
    }

    NSString *texto = [NSString stringWithFormat:@"https://www.tiktok.com%@?%@", ruta, firmado];
    NSURL *url = [NSURL URLWithString:texto];
    if (!url) {
        completado(nil, nil, TTError(TTErrorFirma, @"La direccion firmada no es valida"));
        return;
    }

    NSMutableURLRequest *peticion = [NSMutableURLRequest requestWithURL:url];
    peticion.HTTPMethod = @"GET";
    peticion.timeoutInterval = 25.0;
    NSMutableDictionary *cabeceras = [NSMutableDictionary dictionaryWithDictionary:
                                      [[TTSesion compartida] cabecerasBase]];
    cabeceras[@"User-Agent"] = uaUsado;
    for (NSString *clave in omitir) [cabeceras removeObjectForKey:clave];
    for (NSString *clave in cabeceras) {
        [peticion setValue:cabeceras[clave] forHTTPHeaderField:clave];
    }

    NSURLSessionDataTask *tarea = [[self sesion]
        dataTaskWithRequest:peticion
          completionHandler:^(NSData *datos, NSURLResponse *respuesta, NSError *error) {
        NSHTTPURLResponse *http = [respuesta isKindOfClass:[NSHTTPURLResponse class]]
                                  ? (NSHTTPURLResponse *)respuesta : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completado(nil, http, TTError(TTErrorRed, error.localizedDescription));
            } else {
                completado(datos ?: [NSData data], http, nil);
            }
        });
    }];
    [tarea resume];
}

// Igual que pedirRuta:completado:, pero ademas entrega la respuesta HTTP.  La
// busqueda lo necesita: cuando TikTok rechaza la peticion (200 con el cuerpo
// vacio) regala un msToken nuevo en la cabecera x-ms-token, y sin verlo no se
// puede reintentar.
- (void)pedirRuta:(NSString *)ruta
            pares:(NSArray *)pares
     conRespuesta:(void (^)(NSDictionary *json, NSHTTPURLResponse *respuesta,
                            NSError *error))completado {

    [self pedirRutaCrudo:ruta pares:pares
              completado:^(NSData *datos, NSHTTPURLResponse *http, NSError *error) {
        if (error) { completado(nil, http, error); return; }

        if (datos.length == 0) {
            // TikTok contesta 200 con cuerpo vacio cuando marca la peticion
            // (cabecera tt_orcas_res: 1).  Se dice tal cual para no despistar,
            // pero se entrega la respuesta: suele traer un msToken nuevo.
            NSString *orcas = [self cabecera:@"tt_orcas_res" de:http];
            completado(nil, http, TTError(TTErrorVacio,
                [NSString stringWithFormat:@"TikTok respondio vacio (HTTP %ld, 0 B%@).",
                 (long)(http ? http.statusCode : 0),
                 orcas.length ? [NSString stringWithFormat:@", orcas=%@", orcas] : @""]));
            return;
        }

        NSError *jerror = nil;
        id json = [NSJSONSerialization JSONObjectWithData:datos options:0 error:&jerror];
        if (![json isKindOfClass:[NSDictionary class]]) {
            completado(nil, http, TTError(TTErrorFormato,
                [NSString stringWithFormat:@"La respuesta no era JSON (%lu B).",
                 (unsigned long)datos.length]));
            return;
        }
        completado(json, http, nil);
    }];
}

#pragma mark - Cabeceras de la respuesta

// Lee una cabecera sin importar con que caja venga el nombre.
- (NSString *)cabecera:(NSString *)nombre de:(NSHTTPURLResponse *)respuesta {
    if (!respuesta) return @"";
    for (NSString *clave in respuesta.allHeaderFields) {
        if ([clave caseInsensitiveCompare:nombre] == NSOrderedSame) {
            id valor = respuesta.allHeaderFields[clave];
            if ([valor isKindOfClass:[NSString class]]) return valor;
        }
    }
    return @"";
}

// El msToken que TikTok regala cuando rechaza una peticion.
- (NSString *)msTokenDeRespuesta:(NSHTTPURLResponse *)respuesta {
    return [self cabecera:@"x-ms-token" de:respuesta];
}

#pragma mark - Feed

- (void)feedParaTiCursor:(NSString *)cursor completado:(TTBloqueFeed)completado {
    NSMutableArray *pares = [NSMutableArray arrayWithArray:[[TTSesion compartida] paresBase]];
    [pares addObject:@[ @"count", @"12" ]];
    [pares addObject:@[ @"cursor", cursor.length ? cursor : @"0" ]];

    [self pedirRuta:@"/api/recommend/item_list/" pares:pares completado:^(NSDictionary *json, NSError *error) {
        if (error) { completado(nil, nil, NO, error); return; }
        NSArray *items = json[@"itemList"];
        NSArray *todos = [TTVideo listDesdeItemList:items];
        // El feed mezcla videos con publicaciones de solo fotos (imagePost), que
        // NO traen direccion de reproduccion.  Se descartan aqui mismo: asi el
        // feed nunca muestra una tarjeta que no se puede reproducir.
        NSMutableArray *videos = [NSMutableArray arrayWithCapacity:todos.count];
        for (TTVideo *v in todos) {
            if ([v tieneVideo]) [videos addObject:v];
        }
        NSString *siguiente = [json[@"cursor"] isKindOfClass:[NSString class]] ? json[@"cursor"] : nil;
        if (!siguiente && [json[@"cursor"] isKindOfClass:[NSNumber class]]) {
            siguiente = [(NSNumber *)json[@"cursor"] stringValue];
        }
        BOOL hayMas = [json[@"hasMore"] boolValue];
        if (videos.count == 0 && !hayMas) hayMas = NO;
        completado(videos, siguiente, hayMas, nil);
    }];
}

#pragma mark - Busqueda

- (void)buscarPalabra:(NSString *)palabra completado:(TTBloqueFeed)completado {
    NSString *limpia = [palabra stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (limpia.length == 0) {
        completado(@[], nil, NO, TTError(TTErrorVacio, @"Escribe algo para buscar."));
        return;
    }

    // La busqueda necesita dos cosas que el feed no: la cookie ttwid (identidad
    // anonima) y un msToken valido dentro de la firma.  prepararIdentidad carga
    // una pagina publica una sola vez; el msToken lo aprende el reintento.
    [[TTSesion compartida] prepararIdentidad:^(BOOL lograda) {
        (void)lograda;   // si no se logro, se prueba igual y el error lo dira
        [self buscarPalabra:limpia intento:0 completado:completado];
    }];
}

- (void)buscarPalabra:(NSString *)palabra
               intento:(NSInteger)intento
            completado:(TTBloqueFeed)completado {

    [self pedirRuta:@"/api/search/general/full/" pares:[self paresDeBusqueda:palabra]
       conRespuesta:^(NSDictionary *json, NSHTTPURLResponse *respuesta, NSError *error) {

        // 1) TikTok ha mirado la peticion y no la ha dado por buena: contesta 200
        //    con el cuerpo vacio y la cabecera tt_orcas_res: 1 (o un status 2483).
        //    En la misma respuesta regala un msToken nuevo, que se guarda.
        //
        //    Medido desde el PC: la PRIMERA peticion de una identidad recien
        //    estrenada vuelve vacia y la siguiente, identica, ya trae resultados;
        //    pero solo si se deja pasar un momento.  Reintentar pegado no sirve,
        //    asi que se repite hasta tres veces con una pausa de por medio.
        NSString *nuevoMs = [self msTokenDeRespuesta:respuesta];
        NSString *orcas = [self cabecera:@"tt_orcas_res" de:respuesta];
        NSInteger estadoAhora = [self estadoDeBusqueda:json];
        BOOL vacia = (error && [error.domain isEqualToString:TTErrorDominio] &&
                      error.code == TTErrorVacio);
        BOOL rechazada = (orcas.length > 0) || vacia || (estadoAhora == 2483);

        if (intento < 3 && rechazada) {
            if (nuevoMs.length) [[TTSesion compartida] guardarMsTokenAprendido:nuevoMs];
            // Un 2483 sin msToken nuevo significa que falta la identidad anonima:
            // se olvida la vieja y se pide otra antes de reintentar.
            BOOL sinIdentidad = (estadoAhora == 2483 && nuevoMs.length == 0);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (sinIdentidad) {
                    [[TTSesion compartida] olvidarIdentidad];
                    [[TTSesion compartida] prepararIdentidad:^(BOOL lograda) {
                        (void)lograda;
                        [self buscarPalabra:palabra intento:intento + 1 completado:completado];
                    }];
                } else {
                    [self buscarPalabra:palabra intento:intento + 1 completado:completado];
                }
            });
            return;
        }

        if (error) { completado(nil, nil, NO, error); return; }

        // Si TikTok contesta con un codigo propio (p.ej. 2483 "inicia sesion"),
        // se dice tal cual en vez de aparentar que no hay resultados.
        NSInteger estado = [self estadoDeBusqueda:json];
        if (estado != 0) {
            NSString *msg = [json[@"status_msg"] isKindOfClass:[NSString class]]
                            ? json[@"status_msg"] : @"";
            completado(nil, nil, NO, TTError(TTErrorFormato,
                [NSString stringWithFormat:@"TikTok contesto %ld: %@", (long)estado, msg]));
            return;
        }

        NSArray *videos = [self videosDeRespuestaDeBusqueda:json];
        NSString *siguiente = [json[@"cursor"] isKindOfClass:[NSString class]] ? json[@"cursor"] : nil;
        if (!siguiente && [json[@"cursor"] isKindOfClass:[NSNumber class]]) {
            siguiente = [(NSNumber *)json[@"cursor"] stringValue];
        }
        // La busqueda usa has_more (el feed usa hasMore); se aceptan los dos.
        id mas = json[@"has_more"] ?: json[@"hasMore"];
        completado(videos, siguiente, [mas boolValue], nil);
    }];
}

// Parametros de la busqueda: los de siempre mas lo que la ruta espera.
- (NSArray *)paresDeBusqueda:(NSString *)palabra {
    return [self paresDeBusqueda:palabra conBase:[[TTSesion compartida] paresBase]];
}

- (NSArray *)paresDeBusqueda:(NSString *)palabra conBase:(NSArray *)base {
    NSMutableArray *pares = [NSMutableArray arrayWithArray:base];
    [pares addObject:@[ @"count", @"12" ]];
    [pares addObject:@[ @"offset", @"0" ]];
    [pares addObject:@[ @"is_filter_search", @"0" ]];
    [pares addObject:@[ @"query_correct_type", @"1" ]];
    [pares addObject:@[ @"search_source", @"normal_search" ]];
    [pares addObject:@[ @"keyword", palabra ]];
    return pares;
}

// La misma base, pero declarando un iPad.  Si el rechazo viniera de que la app
// dice ser un PC con Windows y se conecta con la pila de un iPad viejo, esta es
// la variante que lo arreglaria.
- (NSArray *)paresBaseDeIPad {
    NSMutableArray *pares = [NSMutableArray array];
    for (NSArray *par in [[TTSesion compartida] paresBase]) {
        NSString *clave = par.count > 1 ? par[0] : @"";
        NSString *valor = par.count > 1 ? par[1] : @"";
        if ([clave isEqualToString:@"browser_platform"]) valor = @"iPad";
        else if ([clave isEqualToString:@"device_platform"]) valor = @"web_mobile";
        else if ([clave isEqualToString:@"os"]) valor = @"ios";
        [pares addObject:@[ clave, valor ]];
    }
    return pares;
}

// El User-Agent que manda Safari en este aparato, armado como lo arma el
// sistema.  La firma cubre el UA tal cual, asi que tiene que ser el mismo que
// se manda en la cabecera.
- (NSString *)uaDeSafariDelAparato {
    char modelo[64] = {0};
    size_t tam = sizeof modelo;
    if (sysctlbyname("hw.machine", modelo, &tam, NULL, 0) != 0) modelo[0] = '\0';
    char compilacion[64] = {0};
    tam = sizeof compilacion;
    if (sysctlbyname("kern.osversion", compilacion, &tam, NULL, 0) != 0) compilacion[0] = '\0';

    NSString *maquina = modelo[0] ? [NSString stringWithUTF8String:modelo]
                                  : @"iPad2,5";
    NSSet *minis = [NSSet setWithObjects:@"iPad2,5", @"iPad2,6", @"iPad2,7",
                    @"iPad4,4", @"iPad4,5", @"iPad4,6", @"iPad5,1", @"iPad5,2", nil];
    NSString *aparato;
    if ([minis containsObject:maquina])            aparato = @"iPad mini";
    else if ([maquina hasPrefix:@"iPad"])          aparato = @"iPad";
    else if ([maquina hasPrefix:@"iPhone"])        aparato = @"iPhone";
    else if ([maquina hasPrefix:@"iPod"])          aparato = @"iPod touch";
    else                                           aparato = @"iPad";

    NSString *version = [[[UIDevice currentDevice] systemVersion]
                         stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSString *build = compilacion[0] ? [NSString stringWithUTF8String:compilacion] : @"13G37";
    return [NSString stringWithFormat:
        @"Mozilla/5.0 (%@; CPU OS %@ like Mac OS X) AppleWebKit/601.1.46 "
        @"(KHTML, like Gecko) Version/9.0 Mobile/%@ Safari/601.1",
        aparato, version, build];
}

#pragma mark - Bateria del diagnostico

// Prueba de una pasada todas las variantes que quedan.  Misma palabra, misma
// ruta, mismo aparato: solo cambia el User-Agent, las cabeceras, los parametros
// o la ruta.  Cada variante se reintenta con una pausa, porque en el PC esta
// medido que la primera peticion de una identidad recien estrenada vuelve vacia
// y la siguiente ya no.
- (void)bateriaDeBusqueda:(NSString *)palabra
                   lineas:(NSMutableArray *)lineas
               completado:(void (^)(void))completado {

    NSString *uaSafari = [self uaDeSafariDelAparato];
    self.bateriaLograda = NO;
    [lineas addObject:[NSString stringWithFormat:@"UA de Safari del aparato: %@", uaSafari]];

    char descripcion[128] = {0};
    tt_tunel_descripcion(descripcion, sizeof descripcion);
    [lineas addObject:[NSString stringWithFormat:@"tunel: %@ (%s)",
                       tt_tunel_hay() ? @"disponible" : @"NO compilado", descripcion]];

    // La bateria para en cuanto una variante trae videos.  La G va la primera
    // porque es la que se esta probando: si el tunel entra, el diagnostico
    // termina en un par de peticiones en vez de en una docena.
    //
    //  G: el tunel tal cual, ya con el saludo TLS afinado y las cabeceras de un
    //     Chrome de verdad (que es lo que TikTok tiene por bueno).
    //  H: la identidad se pide por el propio tunel y se repite la busqueda con
    //     ella.  Si el tunel funciona solo con identidad nueva, la barrera ata
    //     la identidad a la conexion que la emitio.
    //  I: se mide la huella del tunel en tls.peet.ws y se compara con la de un
    //     Chrome que si entra (JA4 y la huella de HTTP/2 de Akamai).
    NSMutableArray *casos = [NSMutableArray array];
    if (tt_tunel_hay()) {
        //  G: el tunel con el saludo de Chrome sin OCSP (15 extensiones).  Con
        //     OCSP, medido: Akamai contesta 403 a todo.
        //  G2: el saludo de la 1.3.0 (14 extensiones), que ya hablaba con
        //     TikTok, para comparar sin la extension nueva.
        [casos addObject:@{ @"etq": @"G por el tunel, saludo de Chrome sin OCSP",
                            @"intentos": @2,
                            @"ruta": @"/api/search/general/full/",
                            @"pares": [self paresDeBusqueda:palabra],
                            @"palabra": palabra,
                            @"navegador": @YES,
                            @"tunel": @YES,
                            @"estiloTunel": @3 }];
        [casos addObject:@{ @"etq": @"G2 por el tunel, saludo de la 1.3.0",
                            @"intentos": @2,
                            @"ruta": @"/api/search/general/full/",
                            @"pares": [self paresDeBusqueda:palabra],
                            @"palabra": palabra,
                            @"navegador": @YES,
                            @"tunel": @YES,
                            @"estiloTunel": @2 }];
        [casos addObject:@{ @"etq": @"H identidad nueva pedida por el tunel",
                            @"identidadPorElTunel": palabra }];
        [casos addObject:@{ @"etq": @"I huella del tunel",
                            @"huella": @YES }];
    }
    [casos addObjectsFromArray:@[
        @{ @"etq": @"A tal cual (como la app)", @"intentos": @3,
           @"ruta": @"/api/search/general/full/",
           @"pares": [self paresDeBusqueda:palabra] },
        @{ @"etq": @"F ruta search/user", @"intentos": @2,
           @"ruta": @"/api/search/user/full/",
           @"pares": [self paresDeBusqueda:palabra] },
    ]];
    [self casoDeBateria:casos indice:0 lineas:lineas completado:completado];
}

- (void)casoDeBateria:(NSArray *)casos
                indice:(NSInteger)indice
                lineas:(NSMutableArray *)lineas
            completado:(void (^)(void))completado {
    if (indice >= (NSInteger)casos.count) { completado(); return; }
    if (self.bateriaLograda) { completado(); return; }
    NSDictionary *caso = casos[(NSUInteger)indice];
    [self intentoDeCaso:caso intento:1 pasos:[NSMutableArray array] lineas:lineas
             completado:^{
        [self casoDeBateria:casos indice:indice + 1 lineas:lineas completado:completado];
    }];
}

- (void)intentoDeCaso:(NSDictionary *)caso
              intento:(NSInteger)intento
                pasos:(NSMutableArray *)pasos
               lineas:(NSMutableArray *)lineas
           completado:(void (^)(void))completado {

    // Las variantes que van por el tunel (pila TLS + HTTP/2 propia) no usan
    // NSURLSession, asi que tienen su propio camino.
    if (caso[@"identidadPorElTunel"]) {
        [self casoDeIdentidadPorElTunel:caso[@"identidadPorElTunel"]
                                 lineas:lineas completado:completado];
        return;
    }
    if ([caso[@"huella"] boolValue]) {
        [self casoDeHuellaPorElTunel:lineas completado:completado];
        return;
    }
    if ([caso[@"sondas"] boolValue]) {
        [self casoDeSondasPorElTunel:lineas completado:completado];
        return;
    }
    if ([caso[@"tunel"] boolValue]) {
        [self intentoDeTunel:caso intento:intento pasos:pasos lineas:lineas
                  completado:completado];
        return;
    }

    NSInteger maximo = [caso[@"intentos"] integerValue];
    [self pedirRutaCrudo:caso[@"ruta"] pares:caso[@"pares"] ua:caso[@"ua"]
                  omitir:caso[@"omitir"]
              completado:^(NSData *datos, NSHTTPURLResponse *respuesta, NSError *error) {

        NSInteger estado = 0;
        NSDictionary *json = nil;
        if (datos.length) {
            id j = [NSJSONSerialization JSONObjectWithData:datos options:0 error:NULL];
            if ([j isKindOfClass:[NSDictionary class]]) {
                json = j;
                estado = [self estadoDeBusqueda:json];
            }
        }
        NSUInteger videos = 0;
        if (json[@"data"] || json[@"itemList"]) {
            videos = [self videosDeRespuestaDeBusqueda:json].count;
            id lista = json[@"itemList"];
            if (!videos && [lista isKindOfClass:[NSArray class]]) {
                videos = [(NSArray *)lista count];
            }
        }
        NSString *orcas = [self cabecera:@"tt_orcas_res" de:respuesta];
        NSString *nuevo = [self msTokenDeRespuesta:respuesta];
        NSMutableString *paso = [NSMutableString stringWithFormat:
            @"%ld) HTTP %ld, %lu B", (long)intento,
            (long)(respuesta ? respuesta.statusCode : 0), (unsigned long)datos.length];
        if (orcas.length) [paso appendFormat:@" orcas=%@", orcas];
        if (estado != 0) [paso appendFormat:@" status=%ld", (long)estado];
        if (nuevo.length) [paso appendFormat:@" regala=%lu", (unsigned long)nuevo.length];
        if (json) [paso appendFormat:@" videos=%lu", (unsigned long)videos];
        if (error) [paso appendFormat:@" error=%@", error.localizedDescription];
        [pasos addObject:paso];

        BOOL salioBien = (videos > 0);
        if (!salioBien && intento < maximo && (error || datos.length == 0 || estado == 2483)) {
            if (nuevo.length) [[TTSesion compartida] guardarMsTokenAprendido:nuevo];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self intentoDeCaso:caso intento:intento + 1 pasos:pasos lineas:lineas
                         completado:completado];
            });
            return;
        }
        if (salioBien) self.bateriaLograda = YES;
        [lineas addObject:[NSString stringWithFormat:@"bateria %@: %@",
                           caso[@"etq"], [pasos componentsJoinedByString:@"   "]]];
        dispatch_async(dispatch_get_main_queue(), ^{ completado(); });
    }];
}

// Las cabeceras de un navegador de verdad, en el orden en que las manda
// (alfabetico salvo las cuatro pseudo-cabeceras, que las pone el tunel).
//
// El User-Agent de la app dice Edge 122 sobre Windows, asi que lo que se manda
// tiene que ser coherente con eso: los sec-ch-ua con la misma version y la
// misma plataforma, sec-fetch-* como una peticion de la propia pagina, y nada
// de Origin (un GET de la misma pagina no lo lleva).  Una cabecera que se
// contradice con el User-Agent es una de las cosas que mas canta.
- (NSArray *)cabecerasDeNavegadorConUA:(NSString *)ua
                               referer:(NSString *)referer
                                cookie:(NSString *)cookie {
    NSMutableArray *pares = [NSMutableArray array];
    [pares addObject:@[ @"accept", @"*/*" ]];
    // gzip y deflate son lo que sabemos leer de verdad (zlib).  Chrome 122
    // manda ademas "br", pero iOS 9 no trae brotli y no se va a decir que se
    // sabe leer lo que no se sabe leer.
    [pares addObject:@[ @"accept-encoding", @"gzip, deflate" ]];
    [pares addObject:@[ @"accept-language", @"en-US,en;q=0.9" ]];
    if (cookie.length) [pares addObject:@[ @"cookie", cookie ]];
    [pares addObject:@[ @"priority", @"u=1, i" ]];
    if (referer.length) [pares addObject:@[ @"referer", referer ]];
    NSString *marca = [ua rangeOfString:@"Edg/"].location != NSNotFound
                      ? @"Microsoft Edge" : @"Google Chrome";
    [pares addObject:@[ @"sec-ch-ua", [NSString stringWithFormat:
        @"\"Chromium\";v=\"122\", \"Not(A:Brand\";v=\"24\", \"%@\";v=\"122\"", marca] ]];
    [pares addObject:@[ @"sec-ch-ua-mobile", @"?0" ]];
    [pares addObject:@[ @"sec-ch-ua-platform", @"\"Windows\"" ]];
    [pares addObject:@[ @"sec-fetch-dest", @"empty" ]];
    [pares addObject:@[ @"sec-fetch-mode", @"cors" ]];
    [pares addObject:@[ @"sec-fetch-site", @"same-origin" ]];
    [pares addObject:@[ @"user-agent", ua ]];
    return pares;
}

- (NSString *)escapadoDeURL:(NSString *)texto {
    NSCharacterSet *validos = [NSCharacterSet URLQueryAllowedCharacterSet];
    return [texto stringByAddingPercentEncodingWithAllowedCharacters:validos] ?: @"";
}

- (NSString *)recorteDeCuerpo:(NSData *)datos {
    if (!datos.length) return @"";
    NSString *texto = [[NSString alloc] initWithData:datos
                                            encoding:NSUTF8StringEncoding];
    if (!texto.length) {
        texto = [[NSString alloc] initWithData:datos
                                      encoding:NSISOLatin1StringEncoding];
    }
    if (!texto.length) return @"(no es texto)";
    NSUInteger tope = MIN((NSUInteger)220, texto.length);
    NSMutableString *limpio = [NSMutableString string];
    unichar previo = 0;
    for (NSUInteger i = 0; i < tope; i++) {
        unichar ch = [texto characterAtIndex:i];
        if (ch == '\n' || ch == '\r' || ch == '\t') ch = ' ';
        if (ch < 32) continue;
        if (ch == ' ' && previo == ' ') continue;
        [limpio appendFormat:@"%C", ch];
        previo = ch;
    }
    return limpio;
}

// Una peticion por el tunel, ya resuelta a objetos de Objective-C.  Bloquea:
// se llama desde una cola de fondo.  Las cadenas de las cabeceras tienen que
// seguir vivas mientras dura la llamada, y lo estan (las lleva el arreglo).
- (NSDictionary *)pedirPorElTunelHost:(NSString *)host
                                 ruta:(NSString *)ruta
                           cabeceras:(NSArray *)cabeceras {
    NSUInteger cuantas = cabeceras.count;
    tt_cabecera *lista = (tt_cabecera *)calloc(cuantas ? cuantas : 1,
                                               sizeof(tt_cabecera));
    if (!lista) return @{ @"error": @"sin memoria", @"datos": [NSData data] };

    for (NSUInteger i = 0; i < cuantas; i++) {
        NSArray *par = cabeceras[i];
        lista[i].nombre = [par[0] UTF8String];
        lista[i].valor = [(par.count > 1 ? par[1] : @"") UTF8String];
    }

    tt_tunel_respuesta r;
    memset(&r, 0, sizeof r);
    int resultado = tt_tunel_pedir(host.UTF8String, ruta.UTF8String,
                                   lista, cuantas, &r);

    NSMutableDictionary *salida = [NSMutableDictionary dictionary];
    salida[@"ok"] = @(resultado == 0);
    salida[@"estado"] = @(r.estado);
    salida[@"verificado"] = @(r.verificado != 0);
    salida[@"datos"] = (r.largo > 0 && r.cuerpo)
                       ? [NSData dataWithBytes:r.cuerpo length:(NSUInteger)r.largo]
                       : [NSData data];
    salida[@"orcas"] = r.orcas[0] ? [NSString stringWithUTF8String:r.orcas] : @"";
    salida[@"ms_token"] = r.ms_token[0] ? [NSString stringWithUTF8String:r.ms_token] : @"";
    salida[@"cookie"] = r.cookie[0] ? [NSString stringWithUTF8String:r.cookie] : @"";
    salida[@"tls"] = r.tls[0] ? [NSString stringWithUTF8String:r.tls] : @"";
    salida[@"huella"] = r.huella[0] ? [NSString stringWithUTF8String:r.huella] : @"";
    salida[@"ecos"] = r.ecos[0] ? [NSString stringWithUTF8String:r.ecos] : @"";
    salida[@"error"] = r.error[0] ? [NSString stringWithUTF8String:r.error] : @"";

    tt_tunel_soltar(&r);
    free(lista);
    return salida;
}

// Una pasada por el tunel.  La firma se rehace en cada intento (con el msToken
// que TikTok haya regalado en el anterior), igual que en la busqueda de verdad.
- (void)intentoDeTunel:(NSDictionary *)caso
               intento:(NSInteger)intento
                 pasos:(NSMutableArray *)pasos
                lineas:(NSMutableArray *)lineas
            completado:(void (^)(void))completado {

    NSInteger maximo = [caso[@"intentos"] integerValue];
    NSString *ua = caso[@"ua"] ?: [[TTSesion compartida] userAgent];
    NSString *firmado = [self firmarPares:caso[@"pares"] conUA:ua];
    if (firmado.length == 0) {
        [lineas addObject:[NSString stringWithFormat:@"bateria %@: no se pudo firmar",
                           caso[@"etq"]]];
        dispatch_async(dispatch_get_main_queue(), ^{ completado(); });
        return;
    }

    NSString *ruta = [NSString stringWithFormat:@"%@?%@", caso[@"ruta"], firmado];
    NSString *referer = [NSString stringWithFormat:@"https://www.tiktok.com/search?q=%@",
                         [self escapadoDeURL:caso[@"palabra"] ?: @""]];
    NSString *cookie = [[TTSesion compartida] cabecerasBase][@"Cookie"];
    NSArray *cabeceras = [self cabecerasDeNavegadorConUA:ua referer:referer
                                                  cookie:cookie];
    // Que partes del saludo se mandan (ver TTTunel.h).  Por defecto, todas; las
    // pruebas de busqueda usan 3 (sin OCSP) porque medido en el aparato: con
    // OCSP, Akamai contesta 403 a todo.
    int estilo = caso[@"estiloTunel"] ? [caso[@"estiloTunel"] intValue] : 0;

    // El tunel bloquea (hace su propia conexion y espera), asi que va fuera de
    // la cola principal: si no, la app se quedaria congelada mientras prueba.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        tt_tunel_estilo(estilo);
        NSDictionary *r = [self pedirPorElTunelHost:@"www.tiktok.com" ruta:ruta
                                          cabeceras:cabeceras];
        tt_tunel_estilo(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSData *datos = r[@"datos"];
            NSInteger estadoHTTP = [r[@"estado"] integerValue];
            NSString *orcas = r[@"orcas"];
            NSString *nuevo = r[@"ms_token"];
            NSString *ttwid = r[@"cookie"];
            NSString *tls = r[@"tls"];
            NSString *huella = r[@"huella"];
            NSString *fallo = r[@"error"];
            BOOL verificado = [r[@"verificado"] boolValue];

            NSInteger estado = 0;
            NSDictionary *json = nil;
            if (datos.length) {
                id j = [NSJSONSerialization JSONObjectWithData:datos options:0 error:NULL];
                if ([j isKindOfClass:[NSDictionary class]]) {
                    json = j;
                    estado = [self estadoDeBusqueda:json];
                }
            }
            NSUInteger videos = 0;
            if (json) {
                videos = [self videosDeRespuestaDeBusqueda:json].count;
                id lista = json[@"itemList"];
                if (!videos && [lista isKindOfClass:[NSArray class]]) {
                    videos = [(NSArray *)lista count];
                }
            }

            NSMutableString *paso = [NSMutableString stringWithFormat:
                @"%ld) HTTP %ld, %lu B", (long)intento, (long)estadoHTTP,
                (unsigned long)datos.length];
            if (orcas.length) [paso appendFormat:@" orcas=%@", orcas];
            if (estado != 0) [paso appendFormat:@" status=%ld", (long)estado];
            if (nuevo.length) [paso appendFormat:@" regala=%lu", (unsigned long)nuevo.length];
            if (ttwid.length) [paso appendFormat:@" ttwid=%lu", (unsigned long)ttwid.length];
            if (json) [paso appendFormat:@" videos=%lu", (unsigned long)videos];
            if (huella.length) [paso appendFormat:@"  huella=%@", huella];
            // Cuando el borde dice que no, lo util es lo que dice y con que
            // cabeceras: un 403 sin cuerpo no dice nada, y con el se sabe si
            // es Akamai, TikTok o el propio TLS.
            if (estadoHTTP >= 400 || (datos.length && !json)) {
                NSString *recorte = [self recorteDeCuerpo:datos];
                if (recorte.length) [paso appendFormat:@"  «%@»", recorte];
            }
            NSString *ecos = r[@"ecos"];
            if (ecos.length && estadoHTTP >= 400) {
                if (ecos.length > 500) ecos = [ecos substringToIndex:500];
                [paso appendFormat:@"  [%@]", ecos];
            }
            if (tls.length) [paso appendFormat:@"  [%@%@]", tls,
                             verificado ? @"" : @", SIN VERIFICAR"];
            if (fallo.length) [paso appendFormat:@" error=%@", fallo];
            [pasos addObject:paso];

            BOOL salioBien = (videos > 0);
            if (salioBien) self.bateriaLograda = YES;
            if (!salioBien && intento < maximo) {
                if (nuevo.length) [[TTSesion compartida] guardarMsTokenAprendido:nuevo];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(1.2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [self intentoDeTunel:caso intento:intento + 1 pasos:pasos
                                  lineas:lineas completado:completado];
                });
                return;
            }
            [lineas addObject:[NSString stringWithFormat:@"bateria %@: %@",
                               caso[@"etq"], [pasos componentsJoinedByString:@"   "]]];
            completado();
        });
    });
}

// Sondas baratas contra una ruta publica de TikTok (`/api/challenge/detail/`,
// que no es la de busqueda y contesta 366 B): la misma peticion con el saludo
// completo y quitando una pieza cada vez.  En la 1.3.1, anadir OCSP y ALPS
// convirtio el 200 vacio de la busqueda en un 403 en TODAS las rutas, asi que
// hay que saber cual de las dos es la que el borde no quiere ver.
- (void)casoDeSondasPorElTunel:(NSMutableArray *)lineas
                    completado:(void (^)(void))completado {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *ua = [[TTSesion compartida] userAgent];
        NSString *cookie = [[TTSesion compartida] cabecerasBase][@"Cookie"] ?: @"";
        NSArray *conCookie = [self cabecerasDeNavegadorConUA:ua
                                                     referer:@"https://www.tiktok.com/"
                                                      cookie:cookie];
        NSArray *sinCookie = [self cabecerasDeNavegadorConUA:ua
                                                     referer:@"https://www.tiktok.com/"
                                                      cookie:@""];
        NSArray *plan = @[
            @[ @"J1 saludo completo (ocsp+alps), con cookie", @0, conCookie ],
            @[ @"J2 sin ALPS, con cookie", @1, conCookie ],
            @[ @"J3 sin ALPS ni OCSP (el de la 1.3.0), con cookie", @2, conCookie ],
            @[ @"J4 sin OCSP, con cookie", @3, conCookie ],
            @[ @"J5 saludo completo, sin cookie", @0, sinCookie ],
        ];
        NSMutableArray *trozos = [NSMutableArray array];
        for (NSArray *paso in plan) {
            tt_tunel_estilo([paso[1] intValue]);
            NSDictionary *r = [self pedirPorElTunelHost:@"www.tiktok.com"
                ruta:@"/api/challenge/detail/?challengeName=auron"
                cabeceras:paso[2]];
            NSData *datos = r[@"datos"];
            NSMutableString *linea = [NSMutableString stringWithFormat:@"sonda %@: HTTP %@, %lu B",
                paso[0], r[@"estado"], (unsigned long)datos.length];
            NSString *orcas = r[@"orcas"];
            if (orcas.length) [linea appendFormat:@" orcas=%@", orcas];
            NSString *recorte = [self recorteDeCuerpo:datos];
            if (recorte.length && ![r[@"estado"] isEqual:@200]) {
                [linea appendFormat:@" «%@»", recorte];
            }
            NSString *ecos = r[@"ecos"];
            if (ecos.length && [r[@"estado"] integerValue] >= 400) {
                if (ecos.length > 420) ecos = [ecos substringToIndex:420];
                [linea appendFormat:@"  [%@]", ecos];
            }
            [trozos addObject:linea];
        }

        // Dos sondas mas, de otra clase: si el 403 alcanza tambien a las
        // paginas, y si la pagina de resultados trae algo aprovechable por si
        // misma (la web es de JavaScript, pero se comprueba en vez de suponer).
        tt_tunel_estilo(0);
        NSDictionary *portada = [self pedirPorElTunelHost:@"www.tiktok.com" ruta:@"/"
                                                cabeceras:conCookie];
        [trozos addObject:[NSString stringWithFormat:
            @"sonda J6 portada / con el saludo completo: HTTP %@, %lu B",
            portada[@"estado"], (unsigned long)[(NSData *)portada[@"datos"] length]]];

        tt_tunel_estilo(2);
        NSDictionary *pagina = [self pedirPorElTunelHost:@"www.tiktok.com"
            ruta:@"/search?q=auron" cabeceras:conCookie];
        NSData *cuerpoPagina = pagina[@"datos"];
        NSString *textoPagina = [[NSString alloc] initWithData:cuerpoPagina
                                                      encoding:NSUTF8StringEncoding];
        NSMutableArray *marcas = [NSMutableArray array];
        for (NSString *marca in @[ @"itemStruct", @"aweme_list", @"webapp.search",
                                   @"SIGI_STATE", @"__UNIVERSAL_DATA_FOR_REHYDRATION__" ]) {
            if (textoPagina && [textoPagina rangeOfString:marca].location != NSNotFound) {
                [marcas addObject:marca];
            }
        }
        [trozos addObject:[NSString stringWithFormat:
            @"sonda J7 pagina de resultados (saludo de la 1.3.0): HTTP %@, %lu B, marcas=%@",
            pagina[@"estado"], (unsigned long)cuerpoPagina.length,
            marcas.count ? [marcas componentsJoinedByString:@","] : @"ninguna"]];

        tt_tunel_estilo(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            [lineas addObjectsFromArray:trozos];
            completado();
        });
    });
}

// Mide la huella del tunel contra el oraculo publico tls.peet.ws, que devuelve
// lo que ve el servidor: el JA4 de TLS y la huella de HTTP/2 que usa Akamai.
// Se compara con la de un Chrome que si entra en TikTok (medida el 19/10/2026):
//   ja4    t13d1516h2_8daaf6152771_02713d6af862
//   akamai 1:65536;2:0;4:6291456;6:262144|15663105|0|m,a,s,p
//          (hash 52d84b11737d980aef856699f885ca86)
- (void)casoDeHuellaPorElTunel:(NSMutableArray *)lineas
                    completado:(void (^)(void))completado {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *ua = [[TTSesion compartida] userAgent];
        NSArray *cabeceras = [self cabecerasDeNavegadorConUA:ua
                                                     referer:@"https://tls.peet.ws/"
                                                      cookie:@""];
        NSDictionary *r = [self pedirPorElTunelHost:@"tls.peet.ws" ruta:@"/api/all"
                                          cabeceras:cabeceras];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSData *datos = r[@"datos"];
            id json = datos.length
                      ? [NSJSONSerialization JSONObjectWithData:datos options:0 error:NULL]
                      : nil;
            NSString *referenciaJA4 = @"t13d1516h2_8daaf6152771_02713d6af862";
            NSString *referenciaHash = @"52d84b11737d980aef856699f885ca86";

            NSMutableString *linea = [NSMutableString stringWithFormat:
                @"huella del tunel: HTTP %@, %lu B",
                r[@"estado"], (unsigned long)datos.length];
            if ([json isKindOfClass:[NSDictionary class]]) {
                NSDictionary *j = json;
                id tls = j[@"tls"];
                id h2 = j[@"http2"];
                NSString *ja4 = [tls isKindOfClass:[NSDictionary class]] ? tls[@"ja4"] : nil;
                NSString *receta = [tls isKindOfClass:[NSDictionary class]] ? tls[@"ja4_r"] : nil;
                NSString *hash = [h2 isKindOfClass:[NSDictionary class]] ? h2[@"akamai_fingerprint_hash"] : nil;
                NSString *crudo = [h2 isKindOfClass:[NSDictionary class]] ? h2[@"akamai_fingerprint"] : nil;
                if (ja4.length) {
                    [linea appendFormat:@"  ja4=%@", ja4];
                    [linea appendString:[ja4 isEqualToString:referenciaJA4]
                                        ? @" (igual al Chrome que entra)"
                                        : @" (DISTINTO del Chrome que entra)"];
                }
                // La receta en crudo: cifrados, extensiones y algoritmos de
                // firma, para ver pieza a pieza que sobra o que falta.
                if (receta.length) [linea appendFormat:@"  receta=%@", receta];
                // El peetprint es otra huella (la de peet.ws), mas completa:
                // incluye grupos y compresion de certificado.  La referencia se
                // midio con el mismo Chrome; si difiere, dice por donde.
                NSString *peet = [tls isKindOfClass:[NSDictionary class]] ? tls[@"peetprint_hash"] : nil;
                if (peet.length) [linea appendFormat:@"  peetprint=%@ (referencia b8ce945a4d9a7a9b5b6132e3658fe033)", peet];
                if (hash.length) {
                    [linea appendFormat:@"  akamai=%@", hash];
                    [linea appendString:[hash isEqualToString:referenciaHash]
                                        ? @" (igual)" : @" (DISTINTO)"];
                }
                if (crudo.length) [linea appendFormat:@"  (%@)", crudo];
            } else {
                [linea appendString:@"  no trajo el JSON del oraculo"];
            }
            NSString *huella = r[@"huella"];
            NSString *tls = r[@"tls"];
            if (huella.length) [linea appendFormat:@"  ajustes=%@", huella];
            if (tls.length) [linea appendFormat:@"  [%@%@]", tls,
                             [r[@"verificado"] boolValue] ? @"" : @", SIN VERIFICAR"];
            NSString *fallo = r[@"error"];
            if (fallo.length) [linea appendFormat:@"  error=%@", fallo];
            [lineas addObject:linea];
            completado();
        });
    });
}

// Pide una identidad nueva (ttwid) por el propio tunel -- una ruta publica, sin
// cookies -- y repite la busqueda con ella y la misma conexion de Chrome.  Si
// asi entra, la barrera ata la identidad a la conexion que la emitio y la
// solucion es pedirla siempre por el tunel.  Si no entra, no es eso.
- (void)casoDeIdentidadPorElTunel:(NSString *)palabra
                           lineas:(NSMutableArray *)lineas
                       completado:(void (^)(void))completado {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Sin OCSP: con el, Akamai contesta 403 (medido, prueba J).
        tt_tunel_estilo(3);
        NSString *ua = [[TTSesion compartida] userAgent];
        NSArray *sinCookie = [self cabecerasDeNavegadorConUA:ua
                                                    referer:@"https://www.tiktok.com/"
                                                     cookie:@""];
        // 1) Una ruta publica (el detalle de un reto no esta vetado) para que
        //    TikTok emita una identidad a ESTA conexion.
        NSDictionary *identidad = [self pedirPorElTunelHost:@"www.tiktok.com"
            ruta:@"/api/challenge/detail/?challengeName=auron"
            cabeceras:sinCookie];
        NSString *ttwid = identidad[@"cookie"];
        if (!ttwid.length) {
            // Si esa no la dio, la portada: cualquier respuesta del borde vale.
            identidad = [self pedirPorElTunelHost:@"www.tiktok.com"
                                           ruta:@"/" cabeceras:sinCookie];
            ttwid = identidad[@"cookie"];
        }

        NSMutableString *linea = [NSMutableString stringWithFormat:
            @"bateria H identidad nueva por el tunel: 1) HTTP %@, %lu B",
            identidad[@"estado"],
            (unsigned long)[(NSData *)identidad[@"datos"] length]];
        [linea appendString:ttwid.length ? @" (ttwid nuevo)" : @" (NO dio ttwid)"];

        BOOL logrado = NO;
        if (ttwid.length) {
            NSString *referer = [NSString stringWithFormat:
                @"https://www.tiktok.com/search?q=%@", [self escapadoDeURL:palabra ?: @""]];
            NSString *cookie = [NSString stringWithFormat:@"ttwid=%@", ttwid];
            for (NSInteger intento = 1; intento <= 2; intento++) {
                NSString *firmado = [self firmarPares:[self paresDeBusqueda:palabra] conUA:ua];
                if (firmado.length == 0) {
                    [linea appendString:@"   2) no se pudo firmar"];
                    break;
                }
                NSDictionary *r = [self pedirPorElTunelHost:@"www.tiktok.com"
                    ruta:[NSString stringWithFormat:@"/api/search/general/full/?%@", firmado]
                    cabeceras:[self cabecerasDeNavegadorConUA:ua referer:referer cookie:cookie]];

                NSData *datos = r[@"datos"];
                NSInteger estado = 0;
                NSDictionary *json = nil;
                if (datos.length) {
                    id j = [NSJSONSerialization JSONObjectWithData:datos options:0 error:NULL];
                    if ([j isKindOfClass:[NSDictionary class]]) {
                        json = j;
                        estado = [self estadoDeBusqueda:json];
                    }
                }
                NSUInteger videos = json ? [self videosDeRespuestaDeBusqueda:json].count : 0;
                NSString *orcas = r[@"orcas"];
                NSString *nuevo = r[@"ms_token"];
                [linea appendFormat:@"   %ld) HTTP %@, %lu B", (long)(intento + 1),
                 r[@"estado"], (unsigned long)datos.length];
                if (orcas.length) [linea appendFormat:@" orcas=%@", orcas];
                if (estado != 0) [linea appendFormat:@" status=%ld", (long)estado];
                if (nuevo.length) [linea appendFormat:@" regala=%lu", (unsigned long)nuevo.length];
                if (json) [linea appendFormat:@" videos=%lu", (unsigned long)videos];
                NSString *fallo = r[@"error"];
                if (fallo.length) [linea appendFormat:@" error=%@", fallo];

                if (videos > 0) { logrado = YES; break; }
                // Si regala un msToken, se firma otra vez con el (la otra mitad
                // de la identidad) y se repite con el mismo ttwid.
                if (nuevo.length) {
                    [[TTSesion compartida] guardarMsTokenAprendido:nuevo];
                    continue;
                }
                break;
            }
        } else {
            [linea appendString:@"   2) sin ttwid nuevo, no se repite"];
        }

        tt_tunel_estilo(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (logrado) self.bateriaLograda = YES;
            [lineas addObject:linea];
            completado();
        });
    });
}

// Saca los videos de la respuesta.  Mezcla tipos: interesa data[i].item, que es
// el propio itemStruct (a veces va envuelto en item["itemStruct"]).
- (NSArray *)videosDeRespuestaDeBusqueda:(NSDictionary *)json {
    NSMutableArray *videos = [NSMutableArray array];
    NSArray *datos = json[@"data"];
    if (![datos isKindOfClass:[NSArray class]]) return videos;
    for (id nodo in datos) {
        if (![nodo isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *estructura = nil;
        id item = ((NSDictionary *)nodo)[@"item"];
        if ([item isKindOfClass:[NSDictionary class]]) {
            estructura = [item[@"itemStruct"] isKindOfClass:[NSDictionary class]]
                         ? item[@"itemStruct"] : item;
        } else if ([nodo[@"itemStruct"] isKindOfClass:[NSDictionary class]]) {
            estructura = nodo[@"itemStruct"];
        }
        if (![estructura isKindOfClass:[NSDictionary class]]) continue;
        TTVideo *v = [TTVideo desdeItemStruct:estructura];
        if (v && [v tieneVideo]) [videos addObject:v];
    }
    return videos;
}

// status_code de la respuesta, o 0 cuando no hay JSON que mirar.
- (NSInteger)estadoDeBusqueda:(NSDictionary *)json {
    id estado = json[@"status_code"];
    return [estado isKindOfClass:[NSNumber class]] ? [estado integerValue] : 0;
}

#pragma mark - Diagnostico de la busqueda

// Parametros del feed, con o sin los de la busqueda encima.  El sondeo con los
// 20 parametros de la busqueda sirve para comprobar que la firma aguanta ese
// juego: el feed ya funciona, asi que si con esos parametros encima sigue
// trayendo datos, la firma no es el problema.
- (NSArray *)paresDeFeedConCursor:(NSString *)cursor conLosDeBusqueda:(BOOL)conBusqueda {
    NSMutableArray *pares = [NSMutableArray arrayWithArray:[[TTSesion compartida] paresBase]];
    [pares addObject:@[ @"count", @"6" ]];
    [pares addObject:@[ @"cursor", cursor ]];
    if (conBusqueda) {
        [pares addObject:@[ @"is_filter_search", @"0" ]];
        [pares addObject:@[ @"query_correct_type", @"1" ]];
        [pares addObject:@[ @"search_source", @"normal_search" ]];
        [pares addObject:@[ @"keyword", @"auron" ]];
    }
    return pares;
}

// Una sonda con el mismo reintento que la busqueda real, resumida en UNA linea
// por prueba (asi el informe se lee entero de un vistazo): codigo y bytes, la
// cabecera tt_orcas_res, el status_code, la cabecera Connection (que es la que
// delata HTTP/1.1: en HTTP/2 no existe), el msToken que regalen y los videos
// que salgan.
- (void)sonda:(NSString *)etiqueta
         ruta:(NSString *)ruta
        pares:(NSArray *)pares
       lineas:(NSMutableArray *)lineas
   completado:(void (^)(void))completado {
    NSMutableArray *pasos = [NSMutableArray array];
    [self sonda:etiqueta ruta:ruta pares:pares intento:1 pasos:pasos lineas:lineas
     completado:completado];
}

- (void)sonda:(NSString *)etiqueta
         ruta:(NSString *)ruta
        pares:(NSArray *)pares
       intento:(NSInteger)intento
         pasos:(NSMutableArray *)pasos
       lineas:(NSMutableArray *)lineas
   completado:(void (^)(void))completado {

    [self pedirRutaCrudo:ruta pares:pares
              completado:^(NSData *datos, NSHTTPURLResponse *respuesta, NSError *error) {
        NSInteger estado = 0;
        NSString *mensaje = @"";
        NSDictionary *json = nil;
        if (datos.length) {
            id j = [NSJSONSerialization JSONObjectWithData:datos options:0 error:NULL];
            if ([j isKindOfClass:[NSDictionary class]]) {
                json = j;
                estado = [self estadoDeBusqueda:json];
                mensaje = [json[@"status_msg"] isKindOfClass:[NSString class]]
                          ? json[@"status_msg"] : @"";
            }
        }
        NSUInteger videos = 0;
        if (json[@"data"] || json[@"itemList"]) {
            videos = [self videosDeRespuestaDeBusqueda:json].count;
            id lista = json[@"itemList"];
            if (!videos && [lista isKindOfClass:[NSArray class]]) {
                videos = [(NSArray *)lista count];
            }
        }
        NSString *orcas = [self cabecera:@"tt_orcas_res" de:respuesta];
        NSString *conn  = [self cabecera:@"connection" de:respuesta];
        NSString *nuevo = [self msTokenDeRespuesta:respuesta];
        NSMutableString *paso = [NSMutableString stringWithFormat:
            @"%ld) HTTP %ld, %lu B", (long)intento,
            (long)(respuesta ? respuesta.statusCode : 0), (unsigned long)datos.length];
        if (orcas.length) [paso appendFormat:@" orcas=%@", orcas];
        if (estado != 0) [paso appendFormat:@" status=%ld", (long)estado];
        if (conn.length) [paso appendFormat:@" conn=%@", conn];
        if (nuevo.length) [paso appendFormat:@" regala=%lu car.", (unsigned long)nuevo.length];
        if (json) [paso appendFormat:@" videos=%lu", (unsigned long)videos];
        if (mensaje.length) [paso appendFormat:@" \"%@\"", mensaje];
        if (error) [paso appendFormat:@" error=%@", error.localizedDescription];
        [pasos addObject:paso];

        // El mismo reintento que hace la busqueda de verdad, contado en la misma
        // linea: sin el, un rechazo por msToken caducado parece un fallo.
        if (intento == 1 && nuevo.length && (error || estado == 2483 || datos.length == 0)) {
            [[TTSesion compartida] guardarMsTokenAprendido:nuevo];
            [lineas addObject:[NSString stringWithFormat:@"%@: %@   -> regala un msToken y se repite",
                               etiqueta, paso]];
            [pasos removeAllObjects];
            [self sonda:etiqueta ruta:ruta pares:pares intento:2 pasos:pasos lineas:lineas
             completado:completado];
            return;
        }
        [lineas addObject:[NSString stringWithFormat:@"%@: %@", etiqueta,
                           [pasos componentsJoinedByString:@"   "]]];
        completado();
    }];
}

// Pregunta a un servicio de fuera por el protocolo y el TLS que ha negociado
// esta app.  Desde dentro no hay forma de verlo, y es la diferencia que explica
// que la busqueda falle: la ruta exige HTTP/2.  Se pide sin cache y con un
// numero al azar en la direccion, porque una copia guardada (en el telefono o en
// un cache del camino) daria un resultado viejo y enganoso.  Ademas se apunta la
// misma direccion para probarla en Safari: si en Safari sale http/2 y aqui
// http/1.1, la diferencia esta en la app; si en los dos sale http/1.1, esta en el
// sistema.
- (void)ecoDeProtocolo:(NSMutableArray *)lineas completado:(void (^)(void))completado {
    NSString *direccion = [NSString stringWithFormat:
        @"https://www.cloudflare.com/cdn-cgi/trace?tik9=%u", arc4random()];
    NSMutableURLRequest *peticion = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:direccion]];
    peticion.timeoutInterval = 15.0;
    peticion.cachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    [[[NSURLSession sessionWithConfiguration:cfg]
        dataTaskWithRequest:peticion
        completionHandler:^(NSData *datos, NSURLResponse *respuesta, NSError *error) {
        (void)respuesta;
        if (error) {
            [lineas addObject:[NSString stringWithFormat:@"eco de protocolo: error %@",
                               error.localizedDescription]];
        } else {
            NSString *texto = [[NSString alloc] initWithData:datos
                                                    encoding:NSUTF8StringEncoding] ?: @"";
            NSMutableArray *trozos = [NSMutableArray array];
            for (NSString *linea in [texto componentsSeparatedByString:@"\n"]) {
                if ([linea hasPrefix:@"http="] || [linea hasPrefix:@"tls="]
                    || [linea hasPrefix:@"kex="] || [linea hasPrefix:@"ts="]
                    || [linea hasPrefix:@"ip="]) {
                    [trozos addObject:linea];
                }
            }
            [lineas addObject:[NSString stringWithFormat:@"eco de protocolo: %@",
                               trozos.count ? [trozos componentsJoinedByString:@" "]
                                            : @"(sin datos)"]];
            [lineas addObject:@"   (para comparar, abre lo mismo en Safari del "
                             "telefono: https://www.cloudflare.com/cdn-cgi/trace?tik9=safari)"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completado(); });
    }] resume];
}

// ¿Sigue funcionando el HTTP plano del relay?  ATS lo corta en seco, asi que
// despues de tocar ATS hay que comprobarlo.
- (void)sondaDeRelay:(NSMutableArray *)lineas completado:(void (^)(void))completado {
    NSString *base = [TTResolvedor relayBase];
    if (base.length == 0) {
        [lineas addObject:@"relay: sin configurar"];
        completado();
        return;
    }
    NSMutableURLRequest *peticion = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:base]];
    peticion.timeoutInterval = 8.0;
    [[[NSURLSession sharedSession] dataTaskWithRequest:peticion
        completionHandler:^(NSData *datos, NSURLResponse *respuesta, NSError *error) {
        NSString *resumen;
        if (error) {
            resumen = [NSString stringWithFormat:@"error %@", error.localizedDescription];
        } else {
            resumen = [NSString stringWithFormat:@"HTTP %ld, %lu B",
                       (long)([(NSHTTPURLResponse *)respuesta statusCode]),
                       (unsigned long)datos.length];
        }
        [lineas addObject:[NSString stringWithFormat:@"relay %@: %@", base, resumen]];
        dispatch_async(dispatch_get_main_queue(), ^{ completado(); });
    }] resume];
}

// Mira el certificado con el que responde www.tiktok.com: cuantos certificados
// trae la cadena, quien es cada uno y la huella del de la hoja.  En una conexion
// normal la cadena la firma una autoridad publica (DigiCert, Let's Encrypt...);
// si aparece otra cosa, ahi esta el intermediario.
- (void)sondaDeCertificado:(NSMutableArray *)lineas completado:(void (^)(void))completado {
    TTCertificados *vidente = [[TTCertificados alloc] init];
    vidente.apuntes = [NSMutableArray array];
    NSURLSession *sesion = [NSURLSession sessionWithConfiguration:
                            [NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                        delegate:vidente
                                                   delegateQueue:nil];
    NSMutableURLRequest *peticion = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://www.tiktok.com/favicon.ico"]];
    peticion.timeoutInterval = 15.0;
    [[sesion dataTaskWithRequest:peticion
        completionHandler:^(NSData *datos, NSURLResponse *respuesta, NSError *error) {
        (void)datos; (void)respuesta;
        dispatch_async(dispatch_get_main_queue(), ^{
            [lineas addObject:@"certificado de www.tiktok.com:"];
            [lineas addObjectsFromArray:vidente.apuntes];
            if (error) {
                [lineas addObject:[NSString stringWithFormat:@"  error: %@",
                                   error.localizedDescription]];
            }
            [sesion finishTasksAndInvalidate];
            completado();
        });
    }] resume];
}

// Pide una pagina con certificado que no firma nadie (self-signed.badssl.com).
// Por HTTP normal eso no puede salir bien; si sale bien, hay alguien firmando
// certificados en medio.
- (void)sondaDeIntermediario:(NSMutableArray *)lineas completado:(void (^)(void))completado {
    NSMutableURLRequest *peticion = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://self-signed.badssl.com/"]];
    peticion.timeoutInterval = 15.0;
    [[[NSURLSession sharedSession] dataTaskWithRequest:peticion
        completionHandler:^(NSData *datos, NSURLResponse *respuesta, NSError *error) {
        (void)datos;
        NSString *resumen;
        if (!error) {
            resumen = [NSString stringWithFormat:
                @"HTTP %ld -- LO HA ACEPTADO: hay un intermediario firmando certificados",
                (long)([(NSHTTPURLResponse *)respuesta statusCode])];
        } else if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == -1202) {
            resumen = @"rechazado por certificado no confiable -- bien (sin intermediario)";
        } else {
            resumen = [NSString stringWithFormat:@"no se pudo probar: %@",
                       error.localizedDescription];
        }
        [lineas addObject:[NSString stringWithFormat:@"pagina con certificado falso: %@", resumen]];
        dispatch_async(dispatch_get_main_queue(), ^{ completado(); });
    }] resume];
}

// El proxy del sistema (Ajustes -> Wi-Fi -> Proxy).  Si hay uno, explica muchas
// cosas: iOS no hace HTTP/2 a traves de un proxy HTTP normal.
- (void)sondaDeProxy:(NSMutableArray *)lineas completado:(void (^)(void))completado {
    CFDictionaryRef ajustes = CFNetworkCopySystemProxySettings();
    NSDictionary *dic = ajustes ? CFBridgingRelease(ajustes) : nil;
    NSMutableArray *trozos = [NSMutableArray array];
    for (NSString *clave in @[ @"HTTPEnable", @"HTTPProxy", @"HTTPPort",
                               @"HTTPSEnable", @"HTTPSProxy", @"HTTPSPort",
                               @"SOCKSEnable", @"SOCKSProxy", @"SOCKSProxy",
                               @"ProxyAutoConfigEnable", @"ProxyAutoConfigURLString" ]) {
        id valor = dic[clave];
        if (valor) [trozos addObject:[NSString stringWithFormat:@"%@=%@", clave, valor]];
    }
    [lineas addObject:[NSString stringWithFormat:@"proxy del sistema: %@",
                       trozos.count ? [trozos componentsJoinedByString:@" "] : @"ninguno"]];
    completado();
}

// Hace la busqueda paso a paso y devuelve un informe de texto.  Es lo que
// contesta Ajustes -> Probar la busqueda.  Lo primero que prueba es la busqueda
// de verdad, para que salga arriba y no haya que desplazar la pantalla.
- (void)informeDeBusqueda:(NSString *)palabra
               completado:(void (^)(NSString *informe))completado {

    NSString *limpia = [palabra stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (limpia.length == 0) limpia = @"auron";

    TTSesion *ses = [TTSesion compartida];
    NSMutableArray *lineas = [NSMutableArray array];
    NSString *msAntes = [ses msToken];
    // La version va la primera: los informes se pegan en el ordenador y hay que
    // poder saber de que compilacion salieron.
    [lineas addObject:[NSString stringWithFormat:@"app: Tik9 %@ (compilacion %@)",
                       [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?",
                       [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?"]];
    [lineas addObject:[NSString stringWithFormat:@"palabra: %@", limpia]];
    [lineas addObject:[NSString stringWithFormat:
        @"ttwid antes: %@   cookie antes: %lu car.   msToken antes: %lu car.%@",
        [ses hayIdentidad] ? @"si" : @"NO",
        (unsigned long)[ses cookieDeSesion].length, (unsigned long)msAntes.length,
        msAntes.length > 8 ? [NSString stringWithFormat:@" (%@...)", [msAntes substringToIndex:8]] : @""]];

    [ses prepararIdentidad:^(BOOL lograda) {
        [lineas addObject:[NSString stringWithFormat:@"sistema: %@",
                           [NSProcessInfo processInfo].operatingSystemVersionString]];
        [lineas addObject:[NSString stringWithFormat:@"identidad: %@ (ttwid %@)  msToken: %lu car.",
                           lograda ? @"lograda" : @"NO",
                           [[TTSesion compartida] hayIdentidad] ? @"si" : @"NO",
                           (unsigned long)[[TTSesion compartida] msToken].length]];

        // Primero lo que explica el fallo (protocolo, certificado, proxy), y
        // despues la busqueda, para que todo salga en el mismo orden en que se
        // lee: de la causa al sintoma.
        [self ecoDeProtocolo:lineas completado:^{
        [self sondaDeCertificado:lineas completado:^{
        [self sondaDeIntermediario:lineas completado:^{
        [self sondaDeProxy:lineas completado:^{
        [self sonda:@"busqueda(20)" ruta:@"/api/search/general/full/"
               pares:[self paresDeBusqueda:limpia] lineas:lineas completado:^{
        [self sonda:@"feed(16)" ruta:@"/api/recommend/item_list/"
               pares:[self paresDeFeedConCursor:@"0" conLosDeBusqueda:NO]
              lineas:lineas completado:^{
        [self sonda:@"feed+busqueda(20)" ruta:@"/api/recommend/item_list/"
               pares:[self paresDeFeedConCursor:@"0" conLosDeBusqueda:YES]
              lineas:lineas completado:^{
        [self sondaDeRelay:lineas completado:^{
        [self bateriaDeBusqueda:limpia lineas:lineas completado:^{
            [self rematarInforme:lineas];
            completado([lineas componentsJoinedByString:@"\n"]);
        }]; }]; }]; }]; }]; }]; }]; }]; }];
    }];
}

// Pone delante lo que se deduce de todo el informe.  Es lo primero que se lee
// (y lo primero que se pega), asi que va en una linea y sin adornos.
- (void)rematarInforme:(NSMutableArray *)lineas {
    NSString *todo = [lineas componentsJoinedByString:@"\n"];

    // Si alguna prueba DE BUSQUEDA trajo videos, no hay nada que diagnosticar.
    // Ojo: el feed tambien trae videos y no cuenta; su linea empieza por "feed",
    // asi que solo se miran las lineas de la bateria y de las busquedas.
    BOOL salieron = NO;
    NSString *variante = nil;
    BOOL ganoSinVerificar = NO;
    for (NSString *linea in lineas) {
        BOOL esBusqueda = [linea hasPrefix:@"bateria "] || [linea hasPrefix:@"busqueda("];
        if (!esBusqueda) continue;
        NSRange videos = [linea rangeOfString:@"videos="];
        if (videos.location == NSNotFound) continue;
        if ([linea substringFromIndex:videos.location + 7].integerValue <= 0) continue;
        salieron = YES;
        ganoSinVerificar = ([linea rangeOfString:@"SIN VERIFICAR"].location != NSNotFound);
        if ([linea hasPrefix:@"bateria "]) {
            NSRange dosPuntos = [linea rangeOfString:@":"];
            if (dosPuntos.location != NSNotFound && dosPuntos.location > 8) {
                variante = [[linea substringWithRange:NSMakeRange(8, dosPuntos.location - 8)]
                            stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceCharacterSet]];
            }
        }
        break;
    }

    // Lo que dijo la prueba del tunel (el caso G), que es la que se investiga.
    NSString *lineaTunel = nil;
    NSString *lineaIdentidad = nil;
    NSString *lineaHuella = nil;
    for (NSString *linea in lineas) {
        if ([linea hasPrefix:@"bateria G"]) lineaTunel = linea;
        if ([linea hasPrefix:@"bateria H"]) lineaIdentidad = linea;
        if ([linea hasPrefix:@"huella del tunel:"]) lineaHuella = linea;
    }

    // ¿La huella medida es la de un Chrome que si entra?
    BOOL huellaIgual = lineaHuella &&
        [lineaHuella rangeOfString:@"(igual al Chrome que entra)"].location != NSNotFound &&
        [lineaHuella rangeOfString:@"(DISTINTO)"].location == NSNotFound &&
        [lineaHuella rangeOfString:@"(DISTINTO del Chrome que entra)"].location == NSNotFound;

    NSString *veredicto;
    if (salieron) {
        BOOL fueElTunel = (variante.length > 0 && [variante hasPrefix:@"G"]);
        BOOL fueLaIdentidad = (variante.length > 0 && [variante hasPrefix:@"H"]);
        NSMutableString *texto = [NSMutableString stringWithFormat:
            @"La busqueda devuelve videos con la variante «%@».",
            variante.length ? variante : @"?"];
        if (fueElTunel) {
            [texto appendString:@" El tunel (BoringSSL + HTTP/2) es la pieza que hacia "
                                 @"falta: la barrera miraba la huella de la conexion, no lo "
                                 @"que se pide."];
        }
        if (fueLaIdentidad) {
            [texto appendString:@" Y lo que faltaba era la identidad: TikTok ata el ttwid a "
                                 @"la conexion que lo emite, asi que hay que pedirlo por el "
                                 @"mismo tunel antes de buscar."];
        }
        if (ganoSinVerificar) {
            [texto appendString:@" OJO: esa conexion no se pudo comprobar contra las raices "
                                 @"del sistema; antes de darla por buena hay que mirar por que."];
        }
        veredicto = texto;
    } else if ([todo rangeOfString:@"certificado falso: HTTP"].location != NSNotFound) {
        veredicto = @"Hay un intermediario (proxy, VPN o bloqueador) firmando los "
                    @"certificados; la busqueda no puede funcionar hasta quitarlo.";
    } else if (lineaTunel && [lineaTunel rangeOfString:@"error="].location != NSNotFound) {
        veredicto = @"El tunel no llego a responder (mira el error de la prueba G, abajo): "
                    @"eso apunta a la conexion en si (red, DNS, saludo TLS), no a la "
                    @"barrera de TikTok.";
    } else if (lineaTunel && [lineaTunel rangeOfString:@"HTTP 403"].location != NSNotFound) {
        veredicto = @"El borde contesta 403 al tunel. En la 1.3.0 (14 extensiones) contestaba "
                    @"200 vacio en la busqueda y servia las paginas; al anadir OCSP y ALPS "
                    @"(16 extensiones, JA4 identico a Chrome) paso a 403 en todas las rutas de "
                    @"TikTok. Las sondas J dicen cual de las dos extensiones lo dispara y el "
                    @"cuerpo y las cabeceras del 403 dicen quien lo firma.";
    } else if (lineaTunel && huellaIgual) {
        veredicto = @"El tunel presenta la misma huella TLS y de HTTP/2 que un Chrome, y la "
                    @"busqueda sigue volviendo vacia. Antes de tocar la app, comprueba desde el "
                    @"PC si la MISMA busqueda trae resultados (prototipo/receta_final.py): el "
                    @"2026-10-19 TikTok puso a esta IP publica en su reto del WAF y devolvia "
                    @"vacio a todo el mundo, tambien al PC con Chrome de verdad. Si el PC "
                    @"tambien vuelve vacio, no hay nada que arreglar en el aparato: hay que "
                    @"cambiar de red o esperar a que se caiga el reto.";
    } else if (lineaTunel) {
        veredicto = @"El tunel no entra todavia, pero ya se puede medir: la linea «huella del "
                    @"tunel» (prueba I) trae el JA4 y la huella de HTTP/2 de Akamai, y la "
                    @"receta en crudo dice que pieza sobra o falta respecto al Chrome que si "
                    @"entra (cifrados, extensiones o algoritmos de firma).";
    } else if ([todo rangeOfString:@"conn=keep-alive"].location != NSNotFound) {
        veredicto = @"Las peticiones van por HTTP/1.1 y la busqueda necesita HTTP/2. "
                    @"Compara el eco de protocolo con la misma direccion en Safari del "
                    @"telefono: si alli sale http/2 y aqui http/1.1, el problema esta en "
                    @"la app; si sale http/1.1 en los dos, esta en el sistema.";
    } else if ([todo rangeOfString:@"orcas=1"].location != NSNotFound) {
        veredicto = @"TikTok rechaza TODAS las variantes en este aparato (orcas=1): da "
                    @"por sospechosa la huella de su conexion (el TLS y el HTTP/2 de "
                    @"iOS 9). La misma direccion, con la misma firma, funciona desde un "
                    @"ordenador moderno.";
    } else {
        veredicto = @"No se pudo medir el protocolo de las peticiones.";
    }
    [lineas insertObject:[NSString stringWithFormat:@"VEREDICTO: %@", veredicto] atIndex:0];
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

#pragma mark - Certificados

// Se pone de delegado de una sesion de usar y tirar solo para mirar la cadena de
// certificados que presenta el servidor.  Deja lo que ve en 'apuntes' y deja que
// la evaluacion siga su curso de siempre.
@implementation TTCertificados

- (void)URLSession:(NSURLSession *)sesion
didReceiveChallenge:(NSURLAuthenticationChallenge *)reto
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))terminar {
    (void)sesion;
    if ([reto.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]
        && reto.protectionSpace.serverTrust) {
        SecTrustRef confianza = reto.protectionSpace.serverTrust;
        CFIndex cuantos = SecTrustGetCertificateCount(confianza);
        [self.apuntes addObject:[NSString stringWithFormat:@"  %ld certificados en la cadena",
                                 (long)cuantos]];
        for (CFIndex i = 0; i < cuantos; i++) {
            SecCertificateRef visto = SecTrustGetCertificateAtIndex(confianza, i);
            NSString *asunto = visto ? CFBridgingRelease(SecCertificateCopySubjectSummary(visto)) : nil;
            [self.apuntes addObject:[NSString stringWithFormat:@"    [%ld] %@",
                                     (long)i, asunto.length ? asunto : @"(sin nombre)"]];
        }
        if (cuantos > 0) {
            SecCertificateRef hoja = SecTrustGetCertificateAtIndex(confianza, 0);
            NSData *der = hoja ? CFBridgingRelease(SecCertificateCopyData(hoja)) : nil;
            if (der.length) {
                // Huella casera (FNV-1a de 64 bits): no hace falta criptografia
                // de verdad, solo poder decir si es el mismo certificado que se
                // ve desde un ordenador.
                uint64_t huella = 14695981039346656037ULL;
                const unsigned char *bytes = der.bytes;
                for (NSUInteger i = 0; i < der.length; i++) {
                    huella ^= bytes[i];
                    huella *= 1099511628211ULL;
                }
                [self.apuntes addObject:[NSString stringWithFormat:@"    huella de la hoja: %016llx",
                                         huella]];
            }
        }
    }
    terminar(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

@end
