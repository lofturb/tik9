// TTVideo.m
#import "TTVideo.h"
#include <stdarg.h>
#include <limits.h>

static NSString *TTTexto(id nodo, NSString *clave) {
    if (![nodo isKindOfClass:[NSDictionary class]]) return nil;
    id v = nodo[clave];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

static long long TTEntero(id nodo) {
    if ([nodo isKindOfClass:[NSNumber class]]) return [nodo longLongValue];
    if ([nodo isKindOfClass:[NSString class]]) return [nodo longLongValue];
    return 0;
}

static NSString *TTPorClave(NSDictionary *d, NSString *clave) {
    id v = [d isKindOfClass:[NSDictionary class]] ? d[clave] : nil;
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

// Acceso seguro a anidados: TikTok cambia el tipo de un nodo (objeto, cadena,
// nulo) de una respuesta a otra, y un subindice sobre el tipo equivocado
// revienta.  Devuelve nil si algun tramo no existe o no es diccionario.
static id TTSeguro(id nodo, ...) {
    id actual = nodo;
    va_list args;
    va_start(args, nodo);
    NSString *clave;
    while ((clave = va_arg(args, NSString *)) != nil) {
        if (![actual isKindOfClass:[NSDictionary class]]) { actual = nil; break; }
        actual = ((NSDictionary *)actual)[clave];
    }
    va_end(args);
    return actual;
}

// Numero a partir de lo que sea: NSNumber, cadena numerica o nada.
static long long TTNumero(id nodo) {
    if ([nodo isKindOfClass:[NSNumber class]]) return [nodo longLongValue];
    if ([nodo isKindOfClass:[NSString class]]) return [nodo longLongValue];
    return LLONG_MAX;   // al ordenar, "sin altura" se va al final
}

// Marca las direcciones del endpoint firmado /aweme/v1/play/.  Son las unicas
// que entregan un MP4 reproducible: devuelven 302 al CDN bueno
// (v16/v19-web-newkey.tiktokcdn.com) y basta con mandar Referer de
// www.tiktok.com.  Las de v16-webapp-prime.tiktok.com dan 403.
static BOOL TTSerPlataforma(NSString *url) {
    return [url rangeOfString:@"/aweme/v1/play/"].location != NSNotFound;
}

// Extrae las direcciones de video, la MAS util primero.  Se descartan las
// variantes h265/hvc1/hev1 porque un chip de 32 bits no las decodifica.
static NSArray *TTUrlsH264(NSDictionary *video) {
    NSMutableArray *plataforma = [NSMutableArray array];   // /aweme/v1/play/ primero
    NSMutableArray *resto = [NSMutableArray array];

    void (^aniadir)(NSString *) = ^(NSString *u) {
        if (![u isKindOfClass:[NSString class]] || u.length == 0) return;
        if (TTSerPlataforma(u)) {
            if (![plataforma containsObject:u]) [plataforma addObject:u];
        } else if (![resto containsObject:u]) {
            [resto addObject:u];
        }
    };

    NSArray *bitrates = video[@"bitrateInfo"];
    if ([bitrates isKindOfClass:[NSArray class]]) {
        // Se ordenan por altura: la primera es la mas ligera que sirva.  La
        // lectura del nodo es defensiva (el tipo cambia entre respuestas).
        NSArray *ordenados = [bitrates sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            long long ha = TTNumero(TTSeguro(a, @"PlayAddr", @"Height", nil));
            long long hb = TTNumero(TTSeguro(b, @"PlayAddr", @"Height", nil));
            if (ha < hb) return NSOrderedAscending;
            if (ha > hb) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        for (id nodo in ordenados) {
            if (![nodo isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *bi = nodo;
            NSString *codec = [TTTexto(bi, @"CodecType") lowercaseString];
            if (codec.length && ![codec hasPrefix:@"h264"] && ![codec hasPrefix:@"avc"]) continue;
            id urls = TTSeguro(bi, @"PlayAddr", @"UrlList", nil);
            if ([urls isKindOfClass:[NSArray class]]) {
                for (NSString *u in urls) aniadir(u);
            }
        }
    }

    // Copia de las mismas direcciones a nivel de video, por si no hubiera
    // bitrateInfo.
    id urlStruct = TTSeguro(video, @"PlayAddrStruct", @"UrlList", nil);
    if ([urlStruct isKindOfClass:[NSArray class]]) {
        for (NSString *u in urlStruct) aniadir(u);
    }

    // La direccion "oficial" de reproduccion y la de descarga, si no estaban.
    for (NSString *clave in @[ @"playAddr", @"downloadAddr" ]) {
        aniadir(TTPorClave(video, clave));
    }

    [plataforma addObjectsFromArray:resto];
    return plataforma;
}

@implementation TTVideo

+ (instancetype)desdeItemStruct:(NSDictionary *)item {
    if (![item isKindOfClass:[NSDictionary class]]) return nil;
    NSString *ident = TTTexto(item, @"id");
    if (ident.length == 0) return nil;

    TTVideo *v = [[TTVideo alloc] init];
    v.identificador = ident;
    v.descripcion   = TTTexto(item, @"desc") ?: @"";

    NSDictionary *autor = item[@"author"];
    v.autorUsuario = TTTexto(autor, @"uniqueId");
    v.autorNombre  = TTTexto(autor, @"nickname");
    v.autorId      = TTTexto(autor, @"secUid") ?: TTTexto(autor, @"id");
    v.autorAvatar  = TTTexto(autor, @"avatarThumb") ?: TTTexto(autor, @"avatarMedium");

    NSDictionary *musica = item[@"music"];
    v.musica      = TTTexto(musica, @"title");
    v.musicaAutor = TTTexto(musica, @"authorName");

    NSDictionary *video = item[@"video"];
    v.portada        = TTTexto(video, @"cover") ?: TTTexto(video, @"originCover");
    v.portadaAnimada = TTTexto(video, @"dynamicCover");
    v.videoId        = TTTexto(video, @"videoID");
    v.segundos = (NSInteger)TTEntero(video[@"duration"]);
    v.ancho    = (NSInteger)TTEntero(video[@"width"]);
    v.alto     = (NSInteger)TTEntero(video[@"height"]);
    v.urlsDirectas = TTUrlsH264(video);

    // Las cuentas vienen en stats y tambien en statsV2 (a veces como cadena).
    NSDictionary *stats = item[@"statsV2"] ?: item[@"stats"];
    if (![stats isKindOfClass:[NSDictionary class]]) stats = item[@"stats"];
    v.meGusta       = TTEntero(stats[@"diggCount"]);
    v.comentarios   = TTEntero(stats[@"commentCount"]);
    v.compartidos   = TTEntero(stats[@"shareCount"]);
    v.reproducciones= TTEntero(stats[@"playCount"]);
    v.guardados     = TTEntero(stats[@"collectCount"]);

    NSArray *retos = item[@"challenges"];
    if ([retos isKindOfClass:[NSArray class]]) {
        NSMutableArray *titulos = [NSMutableArray array];
        for (NSDictionary *c in retos) {
            NSString *t = TTTexto(c, @"title");
            if (t.length) [titulos addObject:t];
        }
        v.retos = titulos;
    }

    return v;
}

+ (NSArray *)listDesdeItemList:(NSArray *)items {
    NSMutableArray *salida = [NSMutableArray array];
    if ([items isKindOfClass:[NSArray class]]) {
        for (NSDictionary *it in items) {
            TTVideo *v = [TTVideo desdeItemStruct:it];
            if (v) [salida addObject:v];
        }
    }
    return salida;
}

#pragma mark - Favoritos

- (NSDictionary *)aDiccionario {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    #define PON(clave, valor) if (valor) d[(clave)] = (valor)
    PON(@"id", self.identificador);
    PON(@"desc", self.descripcion);
    PON(@"usuario", self.autorUsuario);
    PON(@"nombre", self.autorNombre);
    PON(@"autorId", self.autorId);
    PON(@"avatar", self.autorAvatar);
    PON(@"musica", self.musica);
    PON(@"musicaAutor", self.musicaAutor);
    PON(@"portada", self.portada);
    PON(@"portadaAnimada", self.portadaAnimada);
    PON(@"videoId", self.videoId);
    PON(@"urls", self.urlsDirectas);
    PON(@"retos", self.retos);
    #undef PON
    d[@"segundos"] = @(self.segundos);
    d[@"ancho"] = @(self.ancho);
    d[@"alto"] = @(self.alto);
    d[@"meGusta"] = @(self.meGusta);
    d[@"comentarios"] = @(self.comentarios);
    d[@"compartidos"] = @(self.compartidos);
    d[@"reproducciones"] = @(self.reproducciones);
    d[@"guardados"] = @(self.guardados);
    return d;
}

+ (instancetype)desdeDiccionario:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    NSString *ident = d[@"id"];
    if (![ident isKindOfClass:[NSString class]] || ident.length == 0) return nil;

    TTVideo *v = [[TTVideo alloc] init];
    v.identificador = ident;
    v.descripcion   = d[@"desc"] ?: @"";
    v.autorUsuario  = d[@"usuario"];
    v.autorNombre   = d[@"nombre"];
    v.autorId       = d[@"autorId"];
    v.autorAvatar   = d[@"avatar"];
    v.musica        = d[@"musica"];
    v.musicaAutor   = d[@"musicaAutor"];
    v.portada       = d[@"portada"];
    v.portadaAnimada= d[@"portadaAnimada"];
    v.videoId       = d[@"videoId"];
    v.urlsDirectas  = [d[@"urls"] isKindOfClass:[NSArray class]] ? d[@"urls"] : @[];
    v.retos         = [d[@"retos"] isKindOfClass:[NSArray class]] ? d[@"retos"] : nil;
    v.segundos      = [d[@"segundos"] integerValue];
    v.ancho         = [d[@"ancho"] integerValue];
    v.alto          = [d[@"alto"] integerValue];
    v.meGusta       = [d[@"meGusta"] longLongValue];
    v.comentarios   = [d[@"comentarios"] longLongValue];
    v.compartidos   = [d[@"compartidos"] longLongValue];
    v.reproducciones= [d[@"reproducciones"] longLongValue];
    v.guardados     = [d[@"guardados"] longLongValue];
    return v;
}

#pragma mark - Textos

+ (NSString *)textoDeCuenta:(long long)cuenta {
    if (cuenta < 0) cuenta = 0;
    if (cuenta < 1000) return [NSString stringWithFormat:@"%lld", cuenta];
    if (cuenta < 1000000) return [NSString stringWithFormat:@"%.1fK", cuenta / 1000.0];
    if (cuenta < 1000000000) return [NSString stringWithFormat:@"%.1fM", cuenta / 1000000.0];
    return [NSString stringWithFormat:@"%.1fB", cuenta / 1000000000.0];
}

- (NSString *)textoMeGusta      { return [TTVideo textoDeCuenta:self.meGusta]; }
- (NSString *)textoComentarios  { return [TTVideo textoDeCuenta:self.comentarios]; }
- (NSString *)textoCompartidos  { return [TTVideo textoDeCuenta:self.compartidos]; }

- (NSURL *)urlPortada {
    NSString *u = self.portada.length ? self.portada : self.portadaAnimada;
    return u.length ? [NSURL URLWithString:u] : nil;
}

- (NSString *)mejorUrlDirecta {
    return self.urlsDirectas.count ? self.urlsDirectas[0] : nil;
}

- (BOOL)tieneVideo {
    return self.urlsDirectas.count > 0;
}

@end
