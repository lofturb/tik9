// TTVideoCell.m
#import "TTVideoCell.h"
#import "TTTheme.h"
#import "TTCliente.h"
#import "TTFavoritos.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@implementation TTVideoCell {
    UIView *_velo;                 // degradado inferior para leer el texto
    CAGradientLayer *_degradado;
    UIImageView *_portada;         // miniatura hasta que el video esta listo

    UIButton *_botonMeGusta;
    UILabel  *_cuentaMeGusta;
    UIButton *_botonComentario;
    UILabel  *_cuentaComentario;
    UIButton *_botonCompartir;
    UILabel  *_cuentaCompartir;
    UIImageView *_discoMusica;
    UIView      *_aroDisco;

    UIImageView *_avatar;
    UILabel *_usuario;
    UILabel *_descripcion;
    UIView  *_filaMusica;
    UILabel *_textoMusica;

    UIImageView *_iconoCentral;    // play / pausa al tocar
    UIActivityIndicatorView *_rueda;
    UIView  *_cajaError;
    UILabel *_textoError;
    UIButton *_botonReintentar;

    NSString *_urlAvatarPendiente;
    BOOL _portadaPuesta;
}

#pragma mark - Construccion

- (instancetype)initWithStyle:(UITableViewCellStyle)estilo
              reuseIdentifier:(NSString *)identificador {
    self = [super initWithStyle:estilo reuseIdentifier:identificador];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.contentView.backgroundColor = [UIColor blackColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.clipsToBounds = YES;

        // Contenedor del video.
        _contenedorVideo = [[UIView alloc] init];
        _contenedorVideo.backgroundColor = [UIColor blackColor];
        _contenedorVideo.layer.masksToBounds = YES;
        [self.contentView addSubview:_contenedorVideo];

        // Portada (hasta que el video esta listo).
        _portada = [[UIImageView alloc] init];
        _portada.contentMode = UIViewContentModeScaleAspectFill;
        _portada.clipsToBounds = YES;
        _portada.backgroundColor = [UIColor blackColor];
        [self.contentView addSubview:_portada];

        // Degradado inferior.
        _velo = [[UIView alloc] init];
        _velo.userInteractionEnabled = NO;
        _degradado = [CAGradientLayer layer];
        _degradado.colors = @[ (id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
                               (id)[UIColor colorWithWhite:0.0 alpha:0.55].CGColor ];
        _degradado.locations = @[ @0.0, @1.0 ];
        [_velo.layer addSublayer:_degradado];
        [self.contentView addSubview:_velo];

        // Icono central (play/pausa).
        _iconoCentral = [[UIImageView alloc] init];
        _iconoCentral.image = [TTTheme icono:@"pausa" lado:64];
        _iconoCentral.tintColor = [UIColor colorWithWhite:1.0 alpha:0.85];
        _iconoCentral.alpha = 0.0;
        _iconoCentral.userInteractionEnabled = NO;
        [self.contentView addSubview:_iconoCentral];

        // Rueda de carga.
        _rueda = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
                  UIActivityIndicatorViewStyleWhiteLarge];
        _rueda.hidesWhenStopped = YES;
        [self.contentView addSubview:_rueda];

        [self montarRailDerecho];
        [self montarPieDeTexto];
        [self montarCajaDeError];

        // Tocar el fondo = pausa / reanudar.
        UITapGestureRecognizer *toque =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tocarFondo)];
        [self.contentView addGestureRecognizer:toque];
    }
    return self;
}

- (void)montarRailDerecho {
    // Avatar del autor.
    _avatar = [[UIImageView alloc] init];
    _avatar.contentMode = UIViewContentModeScaleAspectFill;
    _avatar.clipsToBounds = YES;
    _avatar.layer.cornerRadius = 23.0;
    _avatar.layer.borderWidth = 1.5;
    _avatar.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.9].CGColor;
    _avatar.backgroundColor = [TTTheme colorHex:0x2A2A2E];
    [self.contentView addSubview:_avatar];

    _botonMeGusta = [self botonRail:@"corazonLleno" accion:@selector(tocarMeGusta)];
    _cuentaMeGusta = [self etiquetaRail];
    _botonComentario = [self botonRail:@"comentario" accion:@selector(tocarComentario)];
    _cuentaComentario = [self etiquetaRail];
    _botonCompartir = [self botonRail:@"compartir" accion:@selector(tocarCompartir)];
    _cuentaCompartir = [self etiquetaRail];

    // Disco de musica girando.
    _aroDisco = [[UIView alloc] init];
    _aroDisco.backgroundColor = [TTTheme colorHex:0x1A1A1D];
    _aroDisco.layer.cornerRadius = 21.0;
    _aroDisco.layer.borderWidth = 1.0;
    _aroDisco.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    _aroDisco.clipsToBounds = YES;
    [self.contentView addSubview:_aroDisco];

    _discoMusica = [[UIImageView alloc] init];
    _discoMusica.image = [TTTheme icono:@"musica" lado:22];
    _discoMusica.tintColor = [UIColor whiteColor];
    _discoMusica.contentMode = UIViewContentModeCenter;
    [_aroDisco addSubview:_discoMusica];
}

- (UIButton *)botonRail:(NSString *)forma accion:(SEL)accion {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:[TTTheme icono:forma lado:34 trazo:2.0] forState:UIControlStateNormal];
    b.tintColor = [UIColor whiteColor];
    [b addTarget:self action:accion forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:b];
    return b;
}

- (UILabel *)etiquetaRail {
    UILabel *l = [[UILabel alloc] init];
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = [UIColor whiteColor];
    l.font = [TTTheme fuenteDato];
    [TTTheme aplicarSombraDeTexto:l];
    [self.contentView addSubview:l];
    return l;
}

- (void)montarPieDeTexto {
    _usuario = [[UILabel alloc] init];
    _usuario.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightBold];
    _usuario.textColor = [UIColor whiteColor];
    [TTTheme aplicarSombraDeTexto:_usuario];
    [self.contentView addSubview:_usuario];

    _descripcion = [[UILabel alloc] init];
    _descripcion.numberOfLines = 2;
    _descripcion.font = [UIFont systemFontOfSize:13.5];
    _descripcion.textColor = [UIColor colorWithWhite:0.97 alpha:1.0];
    [TTTheme aplicarSombraDeTexto:_descripcion];
    [self.contentView addSubview:_descripcion];

    _filaMusica = [[UIView alloc] init];
    [self.contentView addSubview:_filaMusica];

    UIImageView *nota = [[UIImageView alloc] init];
    nota.image = [TTTheme icono:@"musica" lado:14 trazo:1.8];
    nota.tintColor = [UIColor whiteColor];
    nota.tag = 71;
    [_filaMusica addSubview:nota];

    _textoMusica = [[UILabel alloc] init];
    _textoMusica.font = [UIFont systemFontOfSize:12.5];
    _textoMusica.textColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    _textoMusica.lineBreakMode = NSLineBreakByTruncatingTail;
    [TTTheme aplicarSombraDeTexto:_textoMusica];
    _textoMusica.tag = 72;
    [_filaMusica addSubview:_textoMusica];
}

- (void)montarCajaDeError {
    _cajaError = [[UIView alloc] init];
    _cajaError.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.72];
    _cajaError.layer.cornerRadius = 14.0;
    _cajaError.hidden = YES;
    [self.contentView addSubview:_cajaError];

    _textoError = [[UILabel alloc] init];
    _textoError.numberOfLines = 0;
    _textoError.textAlignment = NSTextAlignmentCenter;
    _textoError.textColor = [UIColor whiteColor];
    _textoError.font = [UIFont systemFontOfSize:13.5];
    [_cajaError addSubview:_textoError];

    _botonReintentar = [UIButton buttonWithType:UIButtonTypeSystem];
    [_botonReintentar setTitle:@"Reintentar" forState:UIControlStateNormal];
    [_botonReintentar setTitleColor:[TTTheme acento] forState:UIControlStateNormal];
    _botonReintentar.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [_botonReintentar addTarget:self action:@selector(tocarReintentar)
               forControlEvents:UIControlEventTouchUpInside];
    [_cajaError addSubview:_botonReintentar];
}

#pragma mark - Configuracion

- (void)configurarCon:(TTVideo *)video indice:(NSInteger)indice {
    _video = video;
    _portada.image = nil;
    _portada.alpha = 1.0;
    _portadaPuesta = NO;

    _usuario.text = video.autorUsuario.length
        ? [@"@" stringByAppendingString:video.autorUsuario] : video.autorNombre;

    // El pie: la descripcion.  Si viene vacia, se pone el nombre del autor.
    NSString *desc = video.descripcion.length ? video.descripcion : video.autorNombre;
    _descripcion.text = desc;

    NSString *musica = video.musica.length ? video.musica : video.musicaAutor;
    _textoMusica.text = musica.length ? musica : @"Sonido original";

    _cuentaMeGusta.text = [video textoMeGusta];
    _cuentaComentario.text = [video textoComentarios];
    _cuentaCompartir.text = [video textoCompartidos];

    [self marcarMeGusta:[[TTFavoritos compartida] estaGuardado:video.identificador]];

    // Portada.
    if (video.portada.length) {
        __weak TTVideoCell *deb = self;
        [TTCliente cargarImagen:video.portada completado:^(UIImage *imagen) {
            if (imagen && deb && deb->_video == video) deb->_portada.image = imagen;
        }];
    }

    // Avatar.
    _avatar.image = [TTTheme icono:@"canal" lado:30 trazo:2.0];
    _avatar.tintColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    _avatar.contentMode = video.autorAvatar.length ? UIViewContentModeScaleAspectFill
                                                   : UIViewContentModeCenter;
    _urlAvatarPendiente = video.autorAvatar;
    if (video.autorAvatar.length) {
        __weak TTVideoCell *deb = self;
        [TTCliente cargarImagen:video.autorAvatar completado:^(UIImage *imagen) {
            if (imagen && deb && [deb->_urlAvatarPendiente isEqualToString:video.autorAvatar]) {
                deb->_avatar.image = imagen;
                deb->_avatar.contentMode = UIViewContentModeScaleAspectFill;
            }
        }];
    }

    [self mostrarError:nil];
    [self arrancarDisco];
}

#pragma mark - Estados

- (void)ponerPortadaVisible:(BOOL)visible {
    if (visible) {
        if (!_portadaPuesta) {
            _portada.alpha = 1.0;
            _portadaPuesta = YES;
        }
    } else {
        _portada.alpha = 0.0;
    }
}

- (void)mostrarCargando:(BOOL)cargando {
    if (cargando) [_rueda startAnimating]; else [_rueda stopAnimating];
}

- (void)mostrarError:(NSString *)texto {
    if (texto.length == 0) {
        _cajaError.hidden = YES;
        return;
    }
    _textoError.text = texto;
    _cajaError.hidden = NO;
    [self setNeedsLayout];
}

- (void)mostrarIconoPausa:(BOOL)pausado {
    _iconoCentral.image = [TTTheme icono:(pausado ? @"reproducir" : @"pausa") lado:64];
    _iconoCentral.alpha = 0.0;
    [UIView animateWithDuration:0.12 animations:^{
        self->_iconoCentral.alpha = 0.9;
    } completion:^(BOOL fin) {
        [UIView animateWithDuration:0.4 delay:0.35 options:0 animations:^{
            self->_iconoCentral.alpha = 0.0;
        } completion:nil];
    }];
}

- (void)marcarMeGusta:(BOOL)gusta {
    _botonMeGusta.tintColor = gusta ? [TTTheme acento] : [UIColor whiteColor];
}

#pragma mark - Disco girando

- (void)arrancarDisco {
    if ([_aroDisco.layer animationForKey:@"giro"]) return;
    CABasicAnimation *giro = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    giro.fromValue = @0.0;
    giro.toValue = @(2.0 * M_PI);
    giro.duration = 4.0;
    giro.repeatCount = HUGE_VALF;
    [_aroDisco.layer addAnimation:giro forKey:@"giro"];
}

- (void)pararDisco {
    [_aroDisco.layer removeAnimationForKey:@"giro"];
}

#pragma mark - Disposicion

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat ancho = CGRectGetWidth(self.contentView.bounds);
    CGFloat alto = CGRectGetHeight(self.contentView.bounds);

    _contenedorVideo.frame = self.contentView.bounds;
    _portada.frame = self.contentView.bounds;

    CGFloat altoVelo = MIN(360.0, alto * 0.6);
    _velo.frame = CGRectMake(0, alto - altoVelo, ancho, altoVelo);
    _degradado.frame = _velo.bounds;

    CGFloat centroY = alto * 0.42;
    _iconoCentral.frame = CGRectMake((ancho - 64.0) / 2.0, centroY - 32.0, 64.0, 64.0);
    _rueda.center = CGPointMake(ancho / 2.0, centroY);

    // --- Rail derecho ---
    CGFloat margen = 12.0;
    CGFloat x = ancho - margen - 50.0;
    CGFloat y = alto - margen - 260.0;

    _avatar.frame = CGRectMake(x, y, 46.0, 46.0);
    y += 46.0 + 16.0;

    CGFloat altoBoton = 34.0;
    _botonMeGusta.frame = CGRectMake(x + 8.0, y, 34.0, altoBoton);
    _cuentaMeGusta.frame = CGRectMake(x, y + altoBoton, 50.0, 15.0);
    y += altoBoton + 16.0;

    _botonComentario.frame = CGRectMake(x + 8.0, y, 34.0, altoBoton);
    _cuentaComentario.frame = CGRectMake(x, y + altoBoton, 50.0, 15.0);
    y += altoBoton + 16.0;

    _botonCompartir.frame = CGRectMake(x + 8.0, y, 34.0, altoBoton);
    _cuentaCompartir.frame = CGRectMake(x, y + altoBoton, 50.0, 15.0);
    y += altoBoton + 18.0;

    _aroDisco.frame = CGRectMake(x + 4.0, y, 42.0, 42.0);
    _discoMusica.frame = _aroDisco.bounds;

    // --- Pie de texto ---
    CGFloat anchoTexto = ancho - 14.0 - 74.0;
    CGFloat pie = alto - margen;

    BOOL hayMusica = _textoMusica.text.length > 0;
    CGFloat altoMusica = hayMusica ? 20.0 : 0.0;
    CGFloat altoDesc = _descripcion.text.length ? 36.0 : 0.0;
    CGFloat altoUsuario = 20.0;

    pie -= altoMusica;
    _filaMusica.frame = CGRectMake(14.0, pie, anchoTexto, 20.0);
    UIImageView *nota = (UIImageView *)[_filaMusica viewWithTag:71];
    nota.frame = CGRectMake(0, 3.0, 14.0, 14.0);
    _textoMusica.frame = CGRectMake(20.0, 0, anchoTexto - 20.0, 20.0);

    pie -= altoDesc + 4.0;
    _descripcion.frame = CGRectMake(14.0, pie, anchoTexto, altoDesc);

    pie -= altoUsuario;
    _usuario.frame = CGRectMake(14.0, pie, anchoTexto, altoUsuario);

    // --- Caja de error ---
    CGFloat anchoCaja = MIN(ancho - 48.0, 320.0);
    CGFloat altoCaja = 104.0;
    _cajaError.frame = CGRectMake((ancho - anchoCaja) / 2.0,
                                  centroY - altoCaja / 2.0, anchoCaja, altoCaja);
    _textoError.frame = CGRectMake(16.0, 14.0, anchoCaja - 32.0, 52.0);
    _botonReintentar.frame = CGRectMake(0, altoCaja - 42.0, anchoCaja, 34.0);
}

#pragma mark - Acciones

- (void)tocarFondo      { if (self.alTocarFondo) self.alTocarFondo(self); }
- (void)tocarMeGusta    { if (self.alTocarMeGusta && _video) self.alTocarMeGusta(_video); }
- (void)tocarComentario { if (self.alTocarComentario && _video) self.alTocarComentario(_video); }
- (void)tocarCompartir  { if (self.alTocarCompartir && _video) self.alTocarCompartir(_video); }
- (void)tocarReintentar { if (self.alTocarReintentar && _video) self.alTocarReintentar(_video); }

#pragma mark - Reutilizacion

- (void)prepareForReuse {
    [super prepareForReuse];
    [self pararDisco];
    _video = nil;
    _urlAvatarPendiente = nil;
    _portada.image = nil;
    _portada.alpha = 1.0;
    _portadaPuesta = NO;
    _usuario.text = nil;
    _descripcion.text = nil;
    _textoMusica.text = nil;
    _cuentaMeGusta.text = nil;
    _cuentaComentario.text = nil;
    _cuentaCompartir.text = nil;
    _cajaError.hidden = YES;
    _iconoCentral.alpha = 0.0;
}

@end
