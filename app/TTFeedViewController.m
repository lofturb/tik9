// TTFeedViewController.m -- el feed "Para ti".
//
// Un UITableView paginado (una celda por pantalla) con un solo AVPlayer que se
// muda a la celda visible.  Deslizar = cambiar de video, tocar = pausa.
#import "TTFeedViewController.h"
#import "TTVideoCell.h"
#import "TTVideo.h"
#import "TTCliente.h"
#import "TTResolvedor.h"
#import "TTPlayer.h"
#import "TTTheme.h"
#import "TTFavoritos.h"
#import "TTBusquedaViewController.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface TTFeedViewController () <UITableViewDataSource, UITableViewDelegate, TTBusquedaDelegado>
@end

@implementation TTFeedViewController {
    UITableView *_tabla;
    UIView *_barraSuperior;
    UILabel *_tituloBarra;
    UIButton *_botonSonido;
    UIButton *_botonBuscar;   // la lupa, arriba a la derecha

    NSMutableArray *_videos;
    NSMutableSet *_ids;
    NSString *_cursor;
    BOOL _hayMas;
    BOOL _cargando;
    BOOL _primeraCargaHecha;

    NSInteger _indiceActual;
    NSInteger _indiceEnReproduccion;   // -1 = ninguno
    NSString *_idResolviendo;
    CGFloat _altoCelda;
    NSMutableDictionary *_intentos;    // id -> reintentos por fallo de red

    UILabel *_aviso;      // "desliza para empezar" o el error de carga
    UIButton *_reintentar;
}

#pragma mark - Ciclo de vida

- (instancetype)initParaTi {
    self = [super init];
    if (self) {
        self.title = @"Para ti";
        _videos = [NSMutableArray array];
        _ids = [NSMutableSet set];
        _indiceActual = 0;
        _indiceEnReproduccion = -1;
        _altoCelda = 0.0;
        _intentos = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    _tabla = [[UITableView alloc] initWithFrame:self.view.bounds
                                          style:UITableViewStylePlain];
    _tabla.dataSource = self;
    _tabla.delegate = self;
    _tabla.pagingEnabled = YES;
    _tabla.showsVerticalScrollIndicator = NO;
    _tabla.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tabla.backgroundColor = [UIColor blackColor];
    _tabla.contentInset = UIEdgeInsetsZero;
    _tabla.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // En iOS 9/10 el ajuste se hace con automaticallyAdjustsScrollViewInsets; en
    // iOS 11+ esa propiedad se ignora y hay que usar contentInsetAdjustmentBehavior.
    // La segunda no existe en el SDK 9.3, asi que se busca en tiempo de ejecucion.
    if ([_tabla respondsToSelector:NSSelectorFromString(@"setContentInsetAdjustmentBehavior:")]) {
        [_tabla setValue:@(2) forKey:@"contentInsetAdjustmentBehavior"];   // nunca (iOS 11+)
    } else {
        self.automaticallyAdjustsScrollViewInsets = NO;   // iOS 9/10
    }
    [self.view addSubview:_tabla];

    [self montarBarraSuperior];
    [self montarAviso];

    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(alVolverActiva)
            name:UIApplicationDidBecomeActiveNotification object:nil];

    [self cargarPaginaInicial];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[TTPlayer compartido] activarSesionAudio];
    [[TTPlayer compartido] setSilenciado:NO];
    [self actualizarIconoSonido];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self ponerAlDia];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[TTPlayer compartido] pausar];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    TTPlayer *p = [TTPlayer compartido];
    [p parar];
    p.alListo = nil;
    p.alFallar = nil;
    [[TTPlayer compartido] desactivarSesionAudio];
    _indiceEnReproduccion = -1;
}

- (void)alVolverActiva {
    if (self.view.window) [self ponerAlDia];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Interfaz

- (void)montarBarraSuperior {
    _barraSuperior = [[UIView alloc] init];
    _barraSuperior.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_barraSuperior];

    _tituloBarra = [[UILabel alloc] init];
    _tituloBarra.text = @"Para ti";
    _tituloBarra.textColor = [UIColor whiteColor];
    _tituloBarra.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    [TTTheme aplicarSombraDeTexto:_tituloBarra];
    [_barraSuperior addSubview:_tituloBarra];

    _botonSonido = [UIButton buttonWithType:UIButtonTypeCustom];
    _botonSonido.tintColor = [UIColor whiteColor];
    [_botonSonido addTarget:self action:@selector(alternarSonido)
           forControlEvents:UIControlEventTouchUpInside];
    [_barraSuperior addSubview:_botonSonido];

    // La lupa, arriba a la derecha, como en la app oficial.
    _botonBuscar = [UIButton buttonWithType:UIButtonTypeCustom];
    _botonBuscar.tintColor = [UIColor whiteColor];
    [_botonBuscar setImage:[TTTheme icono:@"buscar" lado:26] forState:UIControlStateNormal];
    [_botonBuscar addTarget:self action:@selector(abrirBusqueda)
           forControlEvents:UIControlEventTouchUpInside];
    [_barraSuperior addSubview:_botonBuscar];
}

- (void)montarAviso {
    _aviso = [[UILabel alloc] init];
    _aviso.numberOfLines = 0;
    _aviso.textAlignment = NSTextAlignmentCenter;
    _aviso.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    _aviso.font = [UIFont systemFontOfSize:14.0];
    _aviso.hidden = YES;
    [self.view addSubview:_aviso];

    _reintentar = [UIButton buttonWithType:UIButtonTypeSystem];
    [_reintentar setTitle:@"Reintentar" forState:UIControlStateNormal];
    _reintentar.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [_reintentar addTarget:self action:@selector(cargarPaginaInicial)
          forControlEvents:UIControlEventTouchUpInside];
    _reintentar.hidden = YES;
    [self.view addSubview:_reintentar];
}

- (void)actualizarIconoSonido {
    BOOL silenciado = [TTPlayer compartido].silenciado;
    [_botonSonido setImage:[TTTheme icono:(silenciado ? @"silencio" : @"sonido") lado:26]
                  forState:UIControlStateNormal];
}

- (void)alternarSonido {
    TTPlayer *p = [TTPlayer compartido];
    p.silenciado = !p.silenciado;
    [self actualizarIconoSonido];
}

#pragma mark - Buscar (la lupa)

- (void)abrirBusqueda {
    TTBusquedaViewController *busqueda = [[TTBusquedaViewController alloc] init];
    busqueda.delegado = self;
    busqueda.videos = _videos;
    UINavigationController *marco =
        [[UINavigationController alloc] initWithRootViewController:busqueda];
    [self presentViewController:marco animated:YES completion:nil];
}

// Lo llama la pantalla de busqueda cuando el usuario elige un video.
- (void)busquedaElegirVideo:(TTVideo *)video {
    NSInteger fila = (NSInteger)[_videos indexOfObject:video];
    if (fila == NSNotFound) {
        // No estaba en el feed (seria un resultado de verdad de TikTok): se mete
        // arriba del todo y se salta a el.
        [_videos insertObject:video atIndex:0];
        if (video.identificador.length) [_ids addObject:video.identificador];
        fila = 0;
        [_tabla reloadData];
    }
    NSInteger destino = fila;
    __weak TTFeedViewController *deb = self;
    [self dismissViewControllerAnimated:YES completion:^{
        TTFeedViewController *yo = deb;
        if (!yo) return;
        if (yo->_altoCelda > 0.0) {
            [yo->_tabla setContentOffset:CGPointMake(0.0, (CGFloat)destino * yo->_altoCelda)
                                animated:NO];
        }
        yo->_indiceEnReproduccion = -1;
        [yo ponerAlDia];
    }];
}

#pragma mark - Disposicion

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat alto = CGRectGetHeight(self.view.bounds);
    CGFloat ancho = CGRectGetWidth(self.view.bounds);

    _barraSuperior.frame = CGRectMake(0, 0, ancho, 76.0);
    _tituloBarra.frame = CGRectMake(18.0, 34.0, 160.0, 22.0);
    _botonBuscar.frame = CGRectMake(ancho - 50.0, 28.0, 40.0, 34.0);
    _botonSonido.frame = CGRectMake(ancho - 94.0, 30.0, 40.0, 30.0);

    _aviso.frame = CGRectMake(30.0, alto / 2.0 - 60.0, ancho - 60.0, 70.0);
    _reintentar.frame = CGRectMake(30.0, alto / 2.0 + 16.0, ancho - 60.0, 34.0);

    if (fabs(alto - _altoCelda) > 0.5 && alto > 0.0) {
        _altoCelda = alto;
        _tabla.rowHeight = alto;
        [_tabla reloadData];
        [self ponerAlDia];
    } else {
        _tabla.frame = self.view.bounds;
    }
}

#pragma mark - Carga

- (void)cargarPaginaInicial {
    [_videos removeAllObjects];
    [_ids removeAllObjects];
    _cursor = nil;
    _hayMas = YES;
    _primeraCargaHecha = NO;
    _indiceActual = 0;
    _indiceEnReproduccion = -1;
    [_intentos removeAllObjects];
    [_tabla reloadData];

    _aviso.hidden = NO;
    _aviso.text = @"Cargando el feed...";
    _reintentar.hidden = YES;

    [self cargarSiguientePagina];
}

- (void)cargarSiguientePagina {
    if (_cargando) return;
    if (_primeraCargaHecha && !_hayMas) return;
    _cargando = YES;

    __weak TTFeedViewController *deb = self;
    [[TTCliente compartido] feedParaTiCursor:_cursor
        completado:^(NSArray *videos, NSString *cursor, BOOL hayMas, NSError *error) {
        TTFeedViewController *yo = deb;
        if (!yo) return;
        yo->_cargando = NO;
        yo->_primeraCargaHecha = YES;

        if (error) {
            if (yo->_videos.count == 0) {
                yo->_aviso.hidden = NO;
                yo->_aviso.text = [NSString stringWithFormat:@"No se pudo cargar el feed.\n%@",
                                   [TTCliente explicarError:error]];
                yo->_reintentar.hidden = NO;
            }
            return;
        }

        NSInteger antes = (NSInteger)yo->_videos.count;
        for (TTVideo *v in videos) {
            if ([yo->_ids containsObject:v.identificador]) continue;
            [yo->_ids addObject:v.identificador];
            [yo->_videos addObject:v];
        }
        yo->_cursor = cursor;
        yo->_hayMas = hayMas;
        if (yo->_videos.count > 0) {
            yo->_aviso.hidden = YES;
            yo->_reintentar.hidden = YES;
        } else {
            yo->_aviso.hidden = NO;
            yo->_aviso.text = @"TikTok no devolvio videos.";
        }
        if ((NSInteger)yo->_videos.count != antes) {
            if (antes == 0) {
                [yo->_tabla reloadData];
            } else {
                // Se anaden solo las filas nuevas: recargar la tabla entera a
                // mitad de un deslizamiento es lo que hacia que se notara el tiron.
                NSMutableArray *rutas = [NSMutableArray array];
                for (NSInteger i = antes; i < (NSInteger)yo->_videos.count; i++) {
                    [rutas addObject:[NSIndexPath indexPathForRow:i inSection:0]];
                }
                [yo->_tabla beginUpdates];
                [yo->_tabla insertRowsAtIndexPaths:rutas
                                  withRowAnimation:UITableViewRowAnimationNone];
                [yo->_tabla endUpdates];
            }
        }
        // Solo se arranca la reproduccion si no habia ninguna: si llega una
        // pagina mientras se mira un video, no se le corta.
        if (yo->_indiceEnReproduccion < 0) [yo ponerAlDia];
    }];
}

#pragma mark - Reproductor

- (void)ponerAlDia {
    if (_altoCelda <= 0.0 || _videos.count == 0) return;
    NSInteger indice = (NSInteger)floor((_tabla.contentOffset.y + _altoCelda / 2.0) / _altoCelda);
    if (indice < 0) indice = 0;
    if (indice >= (NSInteger)_videos.count) indice = (NSInteger)_videos.count - 1;
    _indiceActual = indice;

    if (indice == _indiceEnReproduccion) {
        // Ya esta: solo hay que asegurarse de que la capa esta donde toca.
        [self engancharCapaAlIndice:indice];
        if (![[TTPlayer compartido] estaReproduciendo]) [[TTPlayer compartido] reproducir];
        return;
    }
    _indiceEnReproduccion = indice;
    [self reproducirIndice:indice];
    [self cargarMasSiHaceFalta];
}

- (void)cargarMasSiHaceFalta {
    if (_hayMas && !_cargando &&
        _indiceActual >= (NSInteger)_videos.count - 3) {
        [self cargarSiguientePagina];
    }
}

- (TTVideoCell *)celdaEnIndice:(NSInteger)indice {
    NSIndexPath *ruta = [NSIndexPath indexPathForRow:indice inSection:0];
    return (TTVideoCell *)[_tabla cellForRowAtIndexPath:ruta];
}

- (void)engancharCapaAlIndice:(NSInteger)indice {
    TTVideoCell *celda = [self celdaEnIndice:indice];
    if (!celda) return;
    AVPlayerLayer *capa = [TTPlayer compartido].capa;
    if (capa.superlayer != celda.contenedorVideo.layer) {
        [capa removeFromSuperlayer];
        [celda.contenedorVideo.layer addSublayer:capa];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    capa.frame = celda.contenedorVideo.bounds;
    [CATransaction commit];
}

- (void)reproducirIndice:(NSInteger)indice {
    [self reproducirIndice:indice ignorarCache:NO];
}

- (void)reproducirIndice:(NSInteger)indice ignorarCache:(BOOL)ignorar {
    if (indice < 0 || indice >= (NSInteger)_videos.count) return;
    TTVideo *video = _videos[(NSUInteger)indice];
    _indiceEnReproduccion = indice;
    if (ignorar) [[TTResolvedor compartido] olvidarVideo:video];

    TTVideoCell *celda = [self celdaEnIndice:indice];
    [celda ponerPortadaVisible:YES];
    [celda mostrarError:nil];
    [celda mostrarCargando:YES];
    [self engancharCapaAlIndice:indice];

    [[TTPlayer compartido] parar];
    _idResolviendo = video.identificador;

    __weak TTFeedViewController *deb = self;
    NSString *clave = video.identificador.length ? video.identificador : @"";
    [[TTResolvedor compartido] resolverVideo:video
        completado:^(NSDictionary *resultado, NSError *error) {
        TTFeedViewController *yo = deb;
        if (!yo) return;
        // Si mientras se resolvia el usuario paso a otro video, se descarta.
        if (![yo->_idResolviendo isEqualToString:video.identificador]) return;
        if (yo->_indiceEnReproduccion != indice) return;
        // La celda pudo reutilizarse: se vuelve a buscar.
        TTVideoCell *c = [yo celdaEnIndice:indice];
        if (!c) return;

        if (error || !resultado) {
            [yo falloEnIndice:indice];
            return;
        }

        TTPlayer *p = [TTPlayer compartido];
        p.alListo = ^{
            [deb marcarListoEnIndice:indice clave:clave];
        };
        p.alFallar = ^(NSError *e) {
            (void)e;
            [deb falloEnIndice:indice];
        };
        [p cargarURL:resultado[@"url"] cabeceras:resultado[@"cabeceras"]];
        [yo engancharCapaAlIndice:indice];
        [p reproducir];
    }];

    [self precargarDesde:indice];
}

- (void)marcarListoEnIndice:(NSInteger)indice clave:(NSString *)clave {
    if (clave.length) [_intentos removeObjectForKey:clave];
    TTVideoCell *celda = [self celdaEnIndice:indice];
    [celda mostrarCargando:NO];
    [celda ponerPortadaVisible:NO];
}

// Un fallo NO quiere decir que el video este roto: casi siempre es un tropiezo de
// red o una direccion que se quedo vieja.  Por eso se reintenta solo, pidiendo
// una direccion nueva, y solo si vuelve a fallar se le dice algo al usuario.  La
// caja de error era lo que aparecia "de vez en cuando" sin motivo.
- (void)falloEnIndice:(NSInteger)indice {
    if (indice < 0 || indice >= (NSInteger)_videos.count) return;
    if (_indiceEnReproduccion != indice) return;

    TTVideo *video = _videos[(NSUInteger)indice];
    NSString *clave = video.identificador.length ? video.identificador : @"";
    NSInteger intentos = [_intentos[clave] integerValue];
    TTVideoCell *celda = [self celdaEnIndice:indice];

    if (intentos < 2) {
        _intentos[clave] = @(intentos + 1);
        [celda mostrarError:nil];
        [celda mostrarCargando:YES];
        [celda ponerPortadaVisible:YES];
        __weak TTFeedViewController *deb = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            TTFeedViewController *yo = deb;
            if (!yo) return;
            if (yo->_indiceEnReproduccion != indice) return;
            [yo reproducirIndice:indice ignorarCache:YES];
        });
        return;
    }

    [celda mostrarCargando:NO];
    [celda ponerPortadaVisible:YES];
    [celda mostrarError:@"Este video no se pudo abrir (puede estar retirado o ser de "
                        "otra region). Toca Reintentar. Si le pasa a varios seguidos, "
                        "activa el relay en Ajustes."];
}

// Adelanta la resolucion de los dos videos siguientes.  Lo que cuesta cerca de
// un segundo es el salto 302 por www.tiktok.com, y se hace mientras se ve el
// video actual: al deslizar, la direccion ya esta lista y sale casi al momento.
- (void)precargarDesde:(NSInteger)indice {
    for (NSInteger i = indice + 1; i <= indice + 2; i++) {
        if (i < 0 || i >= (NSInteger)_videos.count) break;
        [[TTResolvedor compartido] prepararVideo:_videos[(NSUInteger)i]];
    }
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tabla numberOfRowsInSection:(NSInteger)seccion {
    return (NSInteger)_videos.count;
}

- (CGFloat)tableView:(UITableView *)tabla heightForRowAtIndexPath:(NSIndexPath *)ruta {
    return _altoCelda > 0.0 ? _altoCelda : CGRectGetHeight(tabla.bounds);
}

- (UITableViewCell *)tableView:(UITableView *)tabla
         cellForRowAtIndexPath:(NSIndexPath *)ruta {
    static NSString *reutilizar = @"TTVideoCell";
    TTVideoCell *celda = (TTVideoCell *)[tabla dequeueReusableCellWithIdentifier:reutilizar];
    if (!celda) {
        celda = [[TTVideoCell alloc] initWithStyle:UITableViewCellStyleDefault
                                   reuseIdentifier:reutilizar];
    }
    TTVideo *video = _videos[(NSUInteger)ruta.row];
    [celda configurarCon:video indice:ruta.row];
    [self enlazarAccionesDeCelda:celda];
    return celda;
}

- (void)enlazarAccionesDeCelda:(TTVideoCell *)celda {
    __weak TTFeedViewController *deb = self;
    celda.alTocarFondo = ^(TTVideoCell *c) {
        TTFeedViewController *yo = deb;
        if (!yo) return;
        TTPlayer *p = [TTPlayer compartido];
        if ([p estaReproduciendo]) {
            [p pausar];
            [c mostrarIconoPausa:YES];
        } else {
            [p reproducir];
            [c mostrarIconoPausa:NO];
        }
    };
    celda.alTocarMeGusta = ^(TTVideo *v) {
        BOOL guardado = [[TTFavoritos compartida] alternar:v];
        TTVideoCell *c = [deb celdaParaVideo:v];
        [c marcarMeGusta:guardado];
    };
    celda.alTocarComentario = ^(TTVideo *v) {
        (void)v;
        [deb mostrarMensaje:@"Comentarios" texto:@"TikTok bloquea los comentarios para clientes que no son la app oficial. El feed y los videos si funcionan."];
    };
    celda.alTocarCompartir = ^(TTVideo *v) {
        [deb compartir:v];
    };
    celda.alTocarReintentar = ^(TTVideo *v) {
        TTFeedViewController *yo = deb;
        NSInteger i = [yo->_videos indexOfObject:v];
        if (i != NSNotFound) {
            // Reintento a mano: se le devuelve el margen de reintentos y se pide
            // una direccion nueva, por si la anterior se quedo vieja.
            if (v.identificador.length) [yo->_intentos removeObjectForKey:v.identificador];
            [yo reproducirIndice:(NSInteger)i ignorarCache:YES];
        }
    };
}

- (TTVideoCell *)celdaParaVideo:(TTVideo *)video {
    NSInteger i = [_videos indexOfObject:video];
    if (i == NSNotFound) return nil;
    return [self celdaEnIndice:i];
}

#pragma mark - Desplazamiento

- (void)scrollViewDidScroll:(UITableView *)tabla {
    if (_altoCelda <= 0.0) return;
    NSInteger indice = (NSInteger)floor((tabla.contentOffset.y + _altoCelda / 2.0) / _altoCelda);
    if (indice < 0) indice = 0;
    if (_videos.count && indice >= (NSInteger)_videos.count) indice = (NSInteger)_videos.count - 1;
    if (indice == _indiceActual) return;
    _indiceActual = indice;

    // Durante el arrastre NO se toca el reproductor.  El video cambia cuando el
    // dedo suelta y la lista se asienta (scrollViewDidEndDecelerating): asi el
    // paso de un video a otro es suave, que era lo que se notaba a tirones.
    // Aqui solo se adelanta trabajo barato: pedir mas paginas y resolver los
    // videos que vienen (eso no toca ni el reproductor ni las celdas).
    [self cargarMasSiHaceFalta];
    [self precargarDesde:indice];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scroll willDecelerate:(BOOL)decelerando {
    if (!decelerando) [self ponerAlDia];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scroll {
    [self ponerAlDia];
}

#pragma mark - Compartir

- (void)compartir:(TTVideo *)video {
    NSString *enlace = video.autorUsuario.length
        ? [NSString stringWithFormat:@"https://www.tiktok.com/@%@/video/%@",
           video.autorUsuario, video.identificador]
        : [NSString stringWithFormat:@"https://www.tiktok.com/video/%@", video.identificador];

    NSMutableArray *elementos = [NSMutableArray arrayWithObject:enlace];
    if (video.descripcion.length) [elementos addObject:video.descripcion];

    UIActivityViewController *hoja =
        [[UIActivityViewController alloc] initWithActivityItems:elementos applicationActivities:nil];
    // En iPad hay que anclar la hoja o se cae.
    if ([hoja respondsToSelector:@selector(popoverPresentationController)]) {
        hoja.popoverPresentationController.sourceView = self.view;
        hoja.popoverPresentationController.sourceRect =
            CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    }
    [self presentViewController:hoja animated:YES completion:nil];
}

#pragma mark - Avisos

- (void)mostrarMensaje:(NSString *)titulo texto:(NSString *)texto {
    UIAlertController *alerta =
        [UIAlertController alertControllerWithTitle:titulo
                                            message:texto
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alerta addAction:[UIAlertAction actionWithTitle:@"Vale" style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alerta animated:YES completion:nil];
}

@end
