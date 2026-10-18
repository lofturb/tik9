// TTBusquedaViewController.m -- la pantalla de la lupa (el icono de arriba a la
// derecha, como en la app oficial).
//
// ESTO ESTA MEDIDO EN VIVO (ver HALLAZGOS.md): TikTok NO da busqueda a los
// clientes que no son la app oficial.
//
//   /api/search/general/full/  -> 200 con el cuerpo VACIO y la cabecera
//                                 tt_orcas_res: 1 (bloqueado).
//   /api/search/suggest/ (y sus variantes) -> 200 con
//                                 {"status_code":0,"status_msg":"url doesn't match"}.
//   La pagina HTML /search?q=... es solo un armazon de JavaScript: no trae
//   ningun dato de videos incrustado.
//
// Asi que esta pantalla hace lo que SI se puede hacer con lo que la app ya
// tiene, sin inventarse nada:
//
//   * SUGIERE con material real: lo que el usuario ha buscado antes (historial
//     del propio telefono) y los retos y autores de los videos que ya estan
//     cargados en el feed.
//   * BUSCA dentro de esos videos ya cargados (por descripcion, retos y autor).
//   * Si el termino no aparece en nada, lo dice claro y explica por que.
//
// Si algun dia TikTok abre la busqueda, aqui es donde hay que anadir la llamada
// a /api/search/general/full/ (el resto de la pantalla ya vale tal cual).
#import "TTBusquedaViewController.h"
#import "TTCliente.h"
#import "TTTheme.h"

static NSString * const kDefHistorial = @"tik9_busquedas";
static const NSUInteger TTHistorialMaximo  = 12;
static const NSUInteger TTSugerenciasMaximo = 8;

// Celda de resultado: guarda el identificador del video para no pintar una
// miniatura que ya no toca cuando la celda se reutiliza.
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
    NSMutableArray *_sugerencias;   // cadenas
    NSMutableArray *_resultados;    // TTVideo
    NSString *_termino;
    BOOL _hayHistorial;
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
    self.automaticallyAdjustsScrollViewInsets = NO;   // iOS 9/10; el iOS 11+ no existe en este SDK

    _sugerencias = [NSMutableArray array];
    _resultados  = [NSMutableArray array];
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
        barra.titleTextAttributes =
            @{ NSForegroundColorAttributeName : [TTTheme textoPrimario] };
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
    _tabla.frame = CGRectMake(0, y + altoBuscador, ancho,
                              MAX(0.0, alto - y - altoBuscador));
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
    [self recalcular];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)buscador {
    [buscador resignFirstResponder];
    [TTBusquedaViewController recordarTermino:_termino];
    [self recalcular];
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
    [_resultados removeAllObjects];

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
        for (NSString *s in unicos) {
            if ([s rangeOfString:t options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [_sugerencias addObject:s];
                if (_sugerencias.count >= TTSugerenciasMaximo) break;
            }
        }
        for (TTVideo *v in self.videos) {
            if ([self video:v pareceDe:t]) [_resultados addObject:v];
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

- (BOOL)soloAviso {
    return (_sugerencias.count == 0 && _resultados.count == 0);
}

- (BOOL)seccionEsDeResultados:(NSInteger)seccion {
    if (_sugerencias.count == 0) return (_resultados.count > 0);
    return (seccion == 1 && _resultados.count > 0);
}

- (NSString *)textoDeAviso {
    if (_termino.length == 0) {
        return @"Escribe arriba para filtrar.\n\n"
                "Las sugerencias salen de tus busquedas recientes y de los temas y autores "
                "de los videos que ya has cargado.";
    }
    return [NSString stringWithFormat:
        @"No hay nada en el feed cargado que coincida con \u00ab%@\u00bb.\n\n"
         "La busqueda global de TikTok esta cerrada a los clientes que no son la app "
         "oficial (sus rutas contestan vacio), asi que por ahora la lupa busca dentro "
         "de los videos que ya tienes.", _termino];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tabla {
    (void)tabla;
    if (_sugerencias.count && _resultados.count) return 2;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tabla numberOfRowsInSection:(NSInteger)seccion {
    (void)tabla;
    if ([self soloAviso]) return 1;
    if ([self seccionEsDeResultados:seccion]) return (NSInteger)_resultados.count;
    return (NSInteger)_sugerencias.count;
}

- (NSString *)tableView:(UITableView *)tabla titleForHeaderInSection:(NSInteger)seccion {
    (void)tabla;
    if ([self soloAviso]) return nil;
    if ([self seccionEsDeResultados:seccion]) return @"En el feed";
    if (_termino.length) return @"Sugerencias";
    return _hayHistorial ? @"Recientes y del feed" : @"Del feed";
}

- (CGFloat)tableView:(UITableView *)tabla heightForRowAtIndexPath:(NSIndexPath *)ruta {
    if ([self soloAviso]) {
        CGSize limite = CGSizeMake(MAX(80.0, CGRectGetWidth(tabla.bounds) - 44.0), CGFLOAT_MAX);
        CGRect r = [[self textoDeAviso] boundingRectWithSize:limite
                                                     options:NSStringDrawingUsesLineFragmentOrigin
                                                  attributes:@{ NSFontAttributeName : [TTTheme fuenteMenuda] }
                                                     context:nil];
        return MAX(90.0, ceil(r.size.height) + 34.0);
    }
    return [self seccionEsDeResultados:ruta.section] ? 58.0 : 46.0;
}

#pragma mark - Celdas

- (UITableViewCell *)tableView:(UITableView *)tabla cellForRowAtIndexPath:(NSIndexPath *)ruta {
    if ([self soloAviso]) {
        UITableViewCell *c = [tabla dequeueReusableCellWithIdentifier:@"Aviso"];
        if (!c) {
            c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Aviso"];
            c.textLabel.numberOfLines = 0;
            c.textLabel.font = [TTTheme fuenteMenuda];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        c.backgroundColor = [TTTheme superficie];
        c.textLabel.textColor = [TTTheme textoSecundario];
        c.textLabel.text = [self textoDeAviso];
        return c;
    }

    if ([self seccionEsDeResultados:ruta.section]) {
        TTCeldaResultado *c = (TTCeldaResultado *)[tabla dequeueReusableCellWithIdentifier:@"Resultado"];
        if (!c) {
            c = [[TTCeldaResultado alloc] initWithStyle:UITableViewCellStyleSubtitle
                                        reuseIdentifier:@"Resultado"];
            c.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
            c.detailTextLabel.font = [TTTheme fuenteMenuda];
            c.detailTextLabel.numberOfLines = 1;
        }
        TTVideo *v = _resultados[(NSUInteger)ruta.row];
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
                if (![fuerte.videoId isEqualToString:v.identificador]) return;  // la celda ya es de otro
                fuerte.imageView.image = imagen;
            }];
        }
        return c;
    }

    UITableViewCell *c = [tabla dequeueReusableCellWithIdentifier:@"Sugerencia"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Sugerencia"];
        c.textLabel.font = [UIFont systemFontOfSize:16.0];
    }
    c.backgroundColor = [TTTheme superficie];
    c.textLabel.textColor = [TTTheme textoPrimario];
    c.textLabel.text = _sugerencias[(NSUInteger)ruta.row];
    c.imageView.tintColor = [TTTheme textoSecundario];
    c.imageView.image = [TTTheme icono:@"buscar" lado:17];
    return c;
}

- (void)tableView:(UITableView *)tabla didSelectRowAtIndexPath:(NSIndexPath *)ruta {
    [tabla deselectRowAtIndexPath:ruta animated:YES];
    if ([self soloAviso]) return;

    if ([self seccionEsDeResultados:ruta.section]) {
        TTVideo *v = _resultados[(NSUInteger)ruta.row];
        [TTBusquedaViewController recordarTermino:_termino];
        [_buscador resignFirstResponder];
        if ([self.delegado respondsToSelector:@selector(busquedaElegirVideo:)]) {
            [self.delegado busquedaElegirVideo:v];
        }
        return;
    }

    // Una sugerencia: se pone en el buscador y se muestran sus resultados.
    NSString *s = _sugerencias[(NSUInteger)ruta.row];
    _buscador.text = s;
    _termino = s;
    [_buscador resignFirstResponder];
    [TTBusquedaViewController recordarTermino:s];
    [self recalcular];
}

@end
