// TTFavoritosViewController.m
#import "TTFavoritosViewController.h"
#import "TTFavoritos.h"
#import "TTVideo.h"
#import "TTTheme.h"
#import "TTCliente.h"
#import "TTVideoCell.h"
#import "TTResolvedor.h"
#import "TTPlayer.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Reproductor de un solo video

// Se abre al tocar un favorito: una celda a pantalla completa con el mismo
// motor que el feed, mas un boton de cerrar.
@interface TTUnicoViewController : UIViewController
@property (nonatomic, strong) TTVideo *video;
@end

@implementation TTUnicoViewController {
    TTVideoCell *_celda;
    UIButton *_cerrar;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    _celda = [[TTVideoCell alloc] initWithStyle:UITableViewCellStyleDefault
                                reuseIdentifier:nil];
    _celda.frame = self.view.bounds;
    _celda.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_celda configurarCon:self.video indice:0];
    [self.view addSubview:_celda];

    _cerrar = [UIButton buttonWithType:UIButtonTypeCustom];
    [_cerrar setImage:[TTTheme icono:@"cerrar" lado:24 trazo:2.2] forState:UIControlStateNormal];
    _cerrar.tintColor = [UIColor whiteColor];
    [_cerrar addTarget:self action:@selector(cerrar) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cerrar];
    [self.view bringSubviewToFront:_cerrar];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _celda.frame = self.view.bounds;
    [_celda setNeedsLayout];
    _cerrar.frame = CGRectMake(CGRectGetWidth(self.view.bounds) - 50.0, 30.0, 40.0, 40.0);
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[TTPlayer compartido] activarSesionAudio];
    [self reproducir];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    TTPlayer *p = [TTPlayer compartido];
    [p parar];
    p.alListo = nil;
    p.alFallar = nil;
    [p desactivarSesionAudio];
}
- (void)reproducir {
    [_celda ponerPortadaVisible:YES];
    [_celda mostrarCargando:YES];
    [_celda mostrarError:nil];

    TTPlayer *p = [TTPlayer compartido];
    [p parar];
    AVPlayerLayer *capa = p.capa;
    [capa removeFromSuperlayer];
    [_celda.contenedorVideo.layer addSublayer:capa];
    capa.frame = _celda.contenedorVideo.bounds;

    __weak TTUnicoViewController *deb = self;
    [[TTResolvedor compartido] resolverVideo:self.video
        completado:^(NSDictionary *resultado, NSError *error) {
        TTUnicoViewController *yo = deb;
        if (!yo) return;
        TTPlayer *p2 = [TTPlayer compartido];
        if (error || !resultado) {
            [yo->_celda mostrarCargando:NO];
            [yo->_celda mostrarError:[error localizedDescription]];
            return;
        }
        p2.alListo = ^{
            [yo->_celda mostrarCargando:NO];
            [yo->_celda ponerPortadaVisible:NO];
        };
        p2.alFallar = ^(NSError *e) {
            (void)e;
            [yo->_celda mostrarCargando:NO];
            [yo->_celda mostrarError:@"No se pudo reproducir el video."];
        };
        [p2 cargarURL:resultado[@"url"] cabeceras:resultado[@"cabeceras"]];
        [p2 reproducir];
    }];
}
- (void)cerrar {
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (BOOL)prefersStatusBarHidden { return YES; }
@end

#pragma mark - Lista de favoritos

@interface TTFavoritosViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation TTFavoritosViewController {
    UITableView *_tabla;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Favoritos";
    self.view.backgroundColor = [TTTheme fondo];

    UITableView *tabla = [[UITableView alloc] initWithFrame:self.view.bounds
                                                     style:UITableViewStylePlain];
    tabla.dataSource = self;
    tabla.delegate = self;
    tabla.rowHeight = 84.0;
    tabla.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tabla.tableFooterView = [[UIView alloc] init];
    [self.view addSubview:tabla];
    _tabla = tabla;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_tabla reloadData];
    [self actualizarBoton];
}

- (UIBarButtonItem *)botonVaciar {
    if ([[TTFavoritos compartida] cuantos] == 0) return nil;
    return [[UIBarButtonItem alloc] initWithTitle:@"Vaciar"
                                            style:UIBarButtonItemStylePlain
                                           target:self
                                           action:@selector(confirmarVaciar)];
}

- (void)confirmarVaciar {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Vaciar favoritos"
                         message:@"Se quitaran todos los videos guardados."
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Vaciar" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *accion) {
        [[TTFavoritos compartida] vaciar];
        [self->_tabla reloadData];
        [self actualizarBoton];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)actualizarBoton {
    self.navigationItem.rightBarButtonItem = [self botonVaciar];
}

#pragma mark UITableView

- (NSInteger)tableView:(UITableView *)tabla numberOfRowsInSection:(NSInteger)seccion {
    NSUInteger n = [[TTFavoritos compartida] cuantos];
    return n == 0 ? 1 : (NSInteger)n;   // 1 fila = el texto de "vacio"
}

- (UITableViewCell *)tableView:(UITableView *)tabla
         cellForRowAtIndexPath:(NSIndexPath *)ruta {
    if ([[TTFavoritos compartida] cuantos] == 0) {
        UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                    reuseIdentifier:nil];
        c.textLabel.text = @"Todavia no has guardado ningun video.\nToca el corazon en el feed.";
        c.textLabel.numberOfLines = 0;
        c.textLabel.textAlignment = NSTextAlignmentCenter;
        c.textLabel.textColor = [TTTheme textoSecundario];
        c.textLabel.font = [UIFont systemFontOfSize:14.0];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        c.backgroundColor = [TTTheme fondo];
        return c;
    }

    static NSString *reutilizar = @"TTFav";
    UITableViewCell *c = [tabla dequeueReusableCellWithIdentifier:reutilizar];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                   reuseIdentifier:reutilizar];
    }
    TTVideo *v = [[TTFavoritos compartida] todos][(NSUInteger)ruta.row];
    c.textLabel.text = v.descripcion.length ? v.descripcion : v.autorUsuario;
    c.textLabel.numberOfLines = 2;
    c.textLabel.font = [TTTheme fuenteTituloLista];
    c.textLabel.textColor = [TTTheme textoPrimario];
    c.detailTextLabel.text = [NSString stringWithFormat:@"@%@  ·  %@",
                              v.autorUsuario ?: @"?", [v textoMeGusta]];
    c.detailTextLabel.textColor = [TTTheme textoSecundario];
    c.backgroundColor = [TTTheme fondo];
    c.imageView.image = [TTTheme icono:@"marca" lado:34];
    c.imageView.tintColor = [TTTheme acento];
    return c;
}

- (void)tableView:(UITableView *)tabla didSelectRowAtIndexPath:(NSIndexPath *)ruta {
    [tabla deselectRowAtIndexPath:ruta animated:YES];
    if ([[TTFavoritos compartida] cuantos] == 0) return;
    TTVideo *v = [[TTFavoritos compartida] todos][(NSUInteger)ruta.row];
    TTUnicoViewController *unico = [[TTUnicoViewController alloc] init];
    unico.video = v;
    unico.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:unico animated:YES completion:nil];
}

- (NSArray *)tableView:(UITableView *)tabla
    editActionsForRowAtIndexPath:(NSIndexPath *)ruta {
    if ([[TTFavoritos compartida] cuantos] == 0) return nil;
    TTVideo *v = [[TTFavoritos compartida] todos][(NSUInteger)ruta.row];
    UITableViewRowAction *quitar = [UITableViewRowAction
        rowActionWithStyle:UITableViewRowActionStyleDestructive
                     title:@"Quitar"
                   handler:^(UITableViewRowAction *accion, NSIndexPath *indice) {
        [[TTFavoritos compartida] quitar:v.identificador];
        [tabla reloadData];
        [self actualizarBoton];
    }];
    return @[ quitar ];
}

@end
