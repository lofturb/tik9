// TTBusquedaViewController.m -- la pantalla de la lupa (el icono de arriba a la
// derecha, como en la app oficial).
//
// QUE SE MIDIO (ver HALLAZGOS.md, seccion 4 quinquies):
//
//   * La busqueda de TikTok se pide a /api/search/general/full/ y SI responde.
//     Lo que faltaba no era la firma, que ya era correcta, sino dos cosas:
//       1. la cookie ttwid (identidad anonima: se consigue cargando una pagina
//          publica, sin cuenta; sin ella contesta 2483 "inicia sesion");
//       2. un msToken valido dentro de la firma (TikTok lo regala en la cabecera
//          x-ms-token de una respuesta rechazada; la app lo aprende y reintenta).
//     Ademas la ruta exige HTTP/2, que NSURLSession ya usa por su cuenta.
//   * Las rutas de sugerencias contestan {"status_code":0,"status_msg":"url
//     doesn't match"} y la pagina /search?q= es un armazon de JavaScript.
//   * La API movil exige X-Argus + X-Ladon (sin portar).
//
// Asi que la pantalla hace tres cosas, sin fingir ninguna:
//
//   1. PIDE de verdad, y si vienen resultados los pinta ("De TikTok").
//   2. Mientras llegan, busca **dentro de los videos ya cargados**.
//   3. Ofrece **sugerencias reales** (tus busquedas recientes + los retos y
//      autores de esos videos) y explica lo que pasa en vez de dejar la lista
//      vacia.
#import "TTBusquedaViewController.h"
#import "TTCliente.h"
#import "TTTheme.h"

static NSString * const kDefHistorial = @"tik9_busquedas";
static const NSUInteger TTHistorialMaximo   = 12;
static const NSUInteger TTSugerenciasMaximo = 8;

// Celda de video: guarda el identificador para no pintar una miniatura que ya no
// toca cuando la celda se reutiliza.
@interface TTCeldaResultado : UITableViewCell
@property (nonatomic, copy) NSString *videoId;
@end

@implementation TTCeldaResultado
@end

@interface TTBusquedaViewController () <UISearchBarDelegate,
                                        UITableViewDataSource,
                                        UITableViewDelegate>
@end

@implementation TTBusquedaViewController {
    UISearchBar *_buscador;
    UITableView *_tabla;
    NSMutableArray *_sugerencias;    // cadenas
    NSMutableArray *_enElFeed;       // TTVideo que coinciden con el termino
    NSArray *_deTikTok;              // TTVideo que devolvio TikTok (casi siempre 0)
    NSString *_termino;
    NSString *_avisoTikTok;          // por que no vinieron resultados
    BOOL _hayHistorial;
    BOOL _busquedaHecha;             // ya se pulso Buscar con este termino
    BOOL _buscando;
}

#pragma mark - Historial (lo unico que se guarda, y solo en el telefono)

+ (NSArray *)historial {
    NSArray *h = [[NSUserDefaults standardUserDefaults] arrayForKey:kDefHistorial];
    return [h isKindOfClass:[NSArray class]] ? h : @[];
}

+ (void)recordarTermino:(NSString *)termino {
    NSString *t = [termino stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length == 0) return;
    NSMutableArray *h = [NSMutableArray arrayWithArray:[self historial]];
    [h removeObject:t];                       // si ya estaba, sube al principio
    [h insertObject:t atIndex:0];
    while (h.count > TTHistorialMaximo) [h removeLastObject];
    [[NSUserDefaults standardUserDefaults] setObject:h forKey:kDefHistorial];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Ciclo de vida

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Buscar";
    self.view.backgroundColor = [TTTheme fondo];
    self.automaticallyAdjustsScrollViewInsets = NO;

    _sugerencias = [NSMutableArray array];
    _enElFeed    = [NSMutableArray array];
    _deTikTok    = @[];
    _termino     = @"";

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Cerrar" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(cerrar)];

    _buscador = [[UISearchBar alloc] initWithFrame:CGRectZero];
    _buscador.delegate = self;
    _buscador.placeholder = @"Buscar";
    _buscador.barTintColor = [TTTheme superficie];
    _buscador.tintColor = [TTTheme acento];
    [self.view addSubview:_buscador];

    _tabla = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tabla.dataSource = self;
    _tabla.delegate = self;
    _tabla.backgroundColor = [TTTheme fondo];
    _tabla.separatorColor = [TTTheme borde];
    [self.view addSubview:_tabla];

    UINavigationBar *barra = self.navigationController.navigationBar;
    if (barra) {
        barra.barTintColor = [TTTheme superficie];
        barra.tintColor = [TTTheme acento];
        barra.titleTextAttributes = @{ NSForegroundColorAttributeName : [TTTheme textoPrimario] };
    }

    [self recalcular];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat ancho = CGRectGetWidth(self.view.bounds);
    CGFloat alto  = CGRectGetHeight(self.view.bounds);
    CGFloat y = self.topLayoutGuide.length;
    CGFloat altoBuscador = 44.0;
    _buscador.frame = CGRectMake(0, y, ancho, altoBuscador);
    _tabla.frame = CGRectMake(0, y + altoBuscador, ancho, MAX(0.0, alto - y - altoBuscador));
}

- (void)cerrar {
    [_buscador resignFirstResponder];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)vaciarHistorial {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefHistorial];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self recalcular];
}

#pragma mark - Buscador

- (void)searchBar:(UISearchBar *)buscador textDidChange:(NSString *)texto {
    (void)buscador;
    _termino = texto ?: @"";
    // Al cambiar el termino, una busqueda anterior ya no vale.
    _busquedaHecha = NO;
    _deTikTok = @[];
    _avisoTikTok = nil;
    [self recalcular];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)buscador {
    [buscador resignFirstResponder];
    [self buscarDeVerdad];
}

- (void)buscarDeVerdad {
    NSString *t = [_termino stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length == 0) return;

    [TTBusquedaViewController recordarTermino:t];
    _busquedaHecha = YES;
    _buscando = YES;
    _deTikTok = @[];
    _avisoTikTok = nil;
    [self recalcular];

    __weak TTBusquedaViewController *deb = self;
    [[TTCliente compartido] buscarPalabra:t
        completado:^(NSArray *videos, NSString *cursor, BOOL hayMas, NSError *error) {
        (void)cursor;
        (void)hayMas;
        TTBusquedaViewController *yo = deb;
        if (!yo) return;
        // Si el usuario ya escribio otra cosa, se descarta.
        if (![yo->_termino isEqualToString:t]) return;

        yo->_buscando = NO;
        if (error) {
            yo->_avisoTikTok = [TTCliente explicarError:error];
            yo->_deTikTok = @[];
        } else {
            yo->_deTikTok = videos ?: @[];
            yo->_avisoTikTok = yo->_deTikTok.count ? nil
                : @"TikTok devolvio la busqueda vacia.";
        }
        [yo recalcular];
    }];
}

#pragma mark - Armar la lista

- (NSArray *)retosFrecuentes {
    NSMutableDictionary *cuenta = [NSMutableDictionary dictionary];
    for (TTVideo *v in self.videos) {
        if (![v.retos isKindOfClass:[NSArray class]]) continue;
        for (NSString *r in v.retos) {
            if (![r isKindOfClass:[NSString class]] || r.length == 0) continue;
            cuenta[r] = @([cuenta[r] integerValue] + 1);
        }
    }
    NSArray *claves = [cuenta.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger ca = [cuenta[a] integerValue];
        NSInteger cb = [cuenta[b] integerValue];
        if (ca != cb) return (ca > cb) ? NSOrderedAscending : NSOrderedDescending;
        return [a localizedCaseInsensitiveCompare:b];
    }];
    return claves ?: @[];
}

- (BOOL)video:(TTVideo *)v pareceDe:(NSString *)t {
    if (t.length == 0) return NO;
    NSMutableArray *campos = [NSMutableArray array];
    if (v.descripcion.length)  [campos addObject:v.descripcion];
    if (v.autorUsuario.length) [campos addObject:v.autorUsuario];
    if (v.autorNombre.length)  [campos addObject:v.autorNombre];
    if ([v.retos isKindOfClass:[NSArray class]]) [campos addObjectsFromArray:v.retos];
    for (NSString *c in campos) {
        if (![c isKindOfClass:[NSString class]]) continue;
        if ([c rangeOfString:t options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

- (void)recalcular {
    [_sugerencias removeAllObjects];
    [_enElFeed removeAllObjects];

    NSString *t = [_termino stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *historial = [TTBusquedaViewController historial];
    _hayHistorial = (historial.count > 0);

    // Pozo de sugerencias: primero lo buscado antes, luego los retos que mas se
    // repiten en el feed cargado y, al final, sus autores.
    NSMutableArray *pozo = [NSMutableArray array];
    [pozo addObjectsFromArray:historial];
    [pozo addObjectsFromArray:[self retosFrecuentes]];
    for (TTVideo *v in self.videos) {
        if (v.autorUsuario.length == 0) continue;
        [pozo addObject:[@"@" stringByAppendingString:v.autorUsuario]];
    }

    NSMutableArray *unicos = [NSMutableArray array];
    for (NSString *s in pozo) {
        if (![s isKindOfClass:[NSString class]] || s.length == 0) continue;
        if (![unicos containsObject:s]) [unicos addObject:s];
    }

    if (t.length == 0) {
        NSUInteger cuantas = MIN(TTSugerenciasMaximo, unicos.count);
        if (cuantas) {
            [_sugerencias addObjectsFromArray:[unicos subarrayWithRange:NSMakeRange(0, cuantas)]];
        }
    } else {
        if (!_busquedaHecha) {
            for (NSString *s in unicos) {
                if ([s rangeOfString:t options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    [_sugerencias addObject:s];
                    if (_sugerencias.count >= TTSugerenciasMaximo) break;
                }
            }
        }
        for (TTVideo *v in self.videos) {
            if ([self video:v pareceDe:t]) [_enElFeed addObject:v];
        }
    }

    // El boton de vaciar solo tiene sentido con historial y sin estar escribiendo.
    if (t.length == 0 && _hayHistorial) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"Vaciar" style:UIBarButtonItemStylePlain
                                            target:self action:@selector(vaciarHistorial)];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }

    [_tabla reloadData];
}

#pragma mark - Forma de la tabla

// El plan dice que secciones salen y en que orden.  Nunca esta vacio: cuando no
// hay nada, queda una sola seccion con el aviso.
- (NSArray *)plan {
    NSMutableArray *p = [NSMutableArray array];
    if (_deTikTok.count)               [p addObject:@"tiktok"];
    if (_enElFeed.count)               [p addObject:@"feed"];
    if (!_busquedaHecha && _sugerencias.count) [p addObject:@"sug"];
    return p;
}

- (NSArray *)filasDeSeccion:(NSString *)tipo {
    if ([tipo isEqualToString:@"tiktok"]) return _deTikTok;
    if ([tipo isEqualToString:@"feed"])   return _enElFeed;
    return _sugerencias;
}

- (NSString *)textoDeAviso {
    if (_buscando) return @"Buscando en TikTok...";

    NSString *t = [_termino stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length == 0) {
        return @"Escribe arriba para filtrar.\n\n"
                "Las sugerencias salen de tus busquedas recientes y de los temas y autores "
                "de los videos que ya has cargado.";
    }
    if (_busquedaHecha) {
        return [NSString stringWithFormat:
            @"Nada que coincida con \u00ab%@\u00bb.\n\n"
             "%@\n\n"
             "TikTok no devolvio resultados (puede que no haya ninguno para ese "
             "termino). Mientras tanto, aqui tienes lo que coincide entre los videos "
             "que ya estan cargados.", t, _avisoTikTok ?: @"TikTok no devolvio resultados."];
    }
    return [NSString stringWithFormat:
        @"No hay nada en el feed cargado que coincida con \u00ab%@\u00bb.\n\n"
         "Pulsa Buscar para preguntar tambien a TikTok.", t];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tabla {
    (void)tabla;
    NSInteger n = (NSInteger)[[self plan] count];
    return n > 0 ? n : 1;
}

- (NSInteger)tableView:(UITableView *)tabla numberOfRowsInSection:(NSInteger)seccion {
    (void)tabla;
    NSArray *plan = [self plan];
    if (plan.count == 0) return 1;                       // el aviso
    return (NSInteger)[self filasDeSeccion:plan[(NSUInteger)seccion]].count;
}

- (NSString *)tableView:(UITableView *)tabla titleForHeaderInSection:(NSInteger)seccion {
    (void)tabla;
    NSArray *plan = [self plan];
    if (plan.count == 0) return nil;
    NSString *tipo = plan[(NSUInteger)seccion];
    if ([tipo isEqualToString:@"tiktok"]) return @"De TikTok";
    if ([tipo isEqualToString:@"feed"])   return @"En tus videos cargados";
    return _termino.length ? @"Sugerencias"
                           : (_hayHistorial ? @"Recientes y del feed" : @"Del feed");
}

- (CGFloat)tableView:(UITableView *)tabla heightForRowAtIndexPath:(NSIndexPath *)ruta {
    NSArray *plan = [self plan];
    if (plan.count == 0) {
        CGSize limite = CGSizeMake(MAX(80.0, CGRectGetWidth(tabla.bounds) - 44.0), CGFLOAT_MAX);
        CGRect r = [[self textoDeAviso] boundingRectWithSize:limite
                                                     options:NSStringDrawingUsesLineFragmentOrigin
                                                  attributes:@{ NSFontAttributeName : [TTTheme fuenteMenuda] }
                                                     context:nil];
        return MAX(110.0, ceil(r.size.height) + 34.0);
    }
    return [plan[(NSUInteger)ruta.section] isEqualToString:@"sug"] ? 46.0 : 58.0;
}

#pragma mark - Celdas

- (void)ponerVideo:(TTVideo *)v enCelda:(TTCeldaResultado *)c {
    c.videoId = v.identificador;
    c.backgroundColor = [TTTheme superficie];
    c.textLabel.textColor = [TTTheme textoPrimario];
    c.detailTextLabel.textColor = [TTTheme textoSecundario];
    c.textLabel.text = v.autorUsuario.length
        ? [NSString stringWithFormat:@"@%@  ·  %@ me gusta", v.autorUsuario, v.textoMeGusta]
        : [NSString stringWithFormat:@"%@ me gusta", v.textoMeGusta];
    c.detailTextLabel.text = v.descripcion.length ? v.descripcion : @"(sin descripcion)";
    c.imageView.image = nil;

    NSString *portada = v.portada.length ? v.portada : v.portadaAnimada;
    if (portada.length) {
        __weak TTCeldaResultado *deb = c;
        [TTCliente cargarImagen:portada completado:^(UIImage *imagen) {
            TTCeldaResultado *fuerte = deb;
            if (!fuerte || !imagen) return;
            if (![fuerte.videoId isEqualToString:v.identificador]) return;   // ya no toca
            fuerte.imageView.image = imagen;
        }];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tabla cellForRowAtIndexPath:(NSIndexPath *)ruta {
    NSArray *plan = [self plan];

    if (plan.count == 0) {
        UITableViewCell *c = [tabla dequeueReusableCellWithIdentifier:@"Aviso"];
        if (!c) {
            c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:@"Aviso"];
            c.textLabel.numberOfLines = 0;
            c.textLabel.font = [TTTheme fuenteMenuda];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        c.backgroundColor = [TTTheme superficie];
        c.textLabel.textColor = [TTTheme textoSecundario];
        c.textLabel.text = [self textoDeAviso];
        return c;
    }

    NSString *tipo = plan[(NSUInteger)ruta.section];

    if ([tipo isEqualToString:@"sug"]) {
        UITableViewCell *c = [tabla dequeueReusableCellWithIdentifier:@"Sugerencia"];
        if (!c) {
            c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:@"Sugerencia"];
            c.textLabel.font = [UIFont systemFontOfSize:16.0];
        }
        c.backgroundColor = [TTTheme superficie];
        c.textLabel.textColor = [TTTheme textoPrimario];
        c.textLabel.text = _sugerencias[(NSUInteger)ruta.row];
        c.imageView.tintColor = [TTTheme textoSecundario];
        c.imageView.image = [TTTheme icono:@"buscar" lado:17];
        return c;
    }

    TTCeldaResultado *c = (TTCeldaResultado *)[tabla dequeueReusableCellWithIdentifier:@"Resultado"];
    if (!c) {
        c = [[TTCeldaResultado alloc] initWithStyle:UITableViewCellStyleSubtitle
                                    reuseIdentifier:@"Resultado"];
        c.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        c.detailTextLabel.font = [TTTheme fuenteMenuda];
        c.detailTextLabel.numberOfLines = 1;
    }
    [self ponerVideo:[self filasDeSeccion:tipo][(NSUInteger)ruta.row] enCelda:c];
    return c;
}

- (void)tableView:(UITableView *)tabla didSelectRowAtIndexPath:(NSIndexPath *)ruta {
    [tabla deselectRowAtIndexPath:ruta animated:YES];
    NSArray *plan = [self plan];
    if (plan.count == 0) return;

    NSString *tipo = plan[(NSUInteger)ruta.section];

    if (![tipo isEqualToString:@"sug"]) {
        TTVideo *v = [self filasDeSeccion:tipo][(NSUInteger)ruta.row];
        [TTBusquedaViewController recordarTermino:_termino];
        [_buscador resignFirstResponder];
        if ([self.delegado respondsToSelector:@selector(busquedaElegirVideo:)]) {
            [self.delegado busquedaElegirVideo:v];
        }
        return;
    }

    // Una sugerencia: se pone en el buscador y se pregunta a TikTok.
    NSString *s = _sugerencias[(NSUInteger)ruta.row];
    _buscador.text = s;
    _termino = s;
    [_buscador resignFirstResponder];
    [self buscarDeVerdad];
}

@end
