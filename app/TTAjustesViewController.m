// TTAjustesViewController.m
#import "TTAjustesViewController.h"
#import "TTTheme.h"
#import "TTSesion.h"
#import "TTCliente.h"
#import "TTResolvedor.h"
#import "TTFavoritos.h"

@interface TTAjustesViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation TTAjustesViewController {
    UITableView *_tabla;
    UIAlertController *_espera;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ajustes";
    self.view.backgroundColor = [TTTheme fondo];

    UITableView *tabla = [[UITableView alloc] initWithFrame:self.view.bounds
                                                     style:UITableViewStyleGrouped];
    tabla.dataSource = self;
    tabla.delegate = self;
    tabla.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tabla.backgroundColor = [TTTheme fondo];
    [self.view addSubview:tabla];
    _tabla = tabla;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_tabla reloadData];
}

#pragma mark - Tabla

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tabla { return 4; }

- (NSString *)tableView:(UITableView *)tabla titleForHeaderInSection:(NSInteger)seccion {
    switch (seccion) {
        case 0: return @"Reproduccion";
        case 1: return @"Sesion";
        case 2: return @"Tema";
        case 3: return @"Acerca de";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tabla titleForFooterInSection:(NSInteger)seccion {
    if (seccion == 0) {
        return @"Todo funciona en el propio telefono: el feed va firmado aqui y el "
               "video se reproduce solo.  El relay es OPCIONAL y solo hace falta si "
               "iOS 9 no confia en el certificado del CDN o si la red corta la "
               "conexion.";
    }
    if (seccion == 2) {
        return @"El tema se aplica al instante.";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tabla numberOfRowsInSection:(NSInteger)seccion {
    switch (seccion) {
        case 0: return 3;   // modo, relay, probar relay
        case 1: return 3;   // cookie, probar feed, olvidar
        case 2: return 2;   // fondo, acento
        case 3: return 2;   // version, como funciona
    }
    return 0;
}

- (UITableViewCell *)celdaValorConTitulo:(NSString *)titulo
                                  detalle:(NSString *)detalle
                                     tabla:(UITableView *)tabla {
    static NSString *reutilizar = @"valor";
    UITableViewCell *c = [tabla dequeueReusableCellWithIdentifier:reutilizar];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                      reuseIdentifier:reutilizar];
    c.textLabel.text = titulo;
    c.textLabel.textColor = [TTTheme textoPrimario];
    c.detailTextLabel.text = detalle;
    c.detailTextLabel.textColor = [TTTheme textoSecundario];
    c.backgroundColor = [TTTheme superficie];
    c.accessoryType = UITableViewCellAccessoryNone;
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tabla
         cellForRowAtIndexPath:(NSIndexPath *)ruta {
    if (ruta.section == 0) {
        if (ruta.row == 0) {
            return [self celdaValorConTitulo:@"Modo"
                                     detalle:[self tituloDelModo:tabla]
                                        tabla:tabla];
        }
        if (ruta.row == 1) {
            NSString *base = [TTResolvedor relayBase];
            return [self celdaValorConTitulo:@"Relay"
                                     detalle:(base.length ? base : @"sin configurar")
                                        tabla:tabla];
        }
        return [self celdaValorConTitulo:@"Probar el relay" detalle:@"" tabla:tabla];
    }
    if (ruta.section == 1) {
        if (ruta.row == 0) {
            BOOL hay = [[TTSesion compartida] hayCookies];
            NSString *ms = [[TTSesion compartida] msToken];
            NSString *detalle = hay ? (ms.length ? @"con msToken" : @"pegada") : @"vacia";
            return [self celdaValorConTitulo:@"Cookies de TikTok" detalle:detalle tabla:tabla];
        }
        if (ruta.row == 1) {
            return [self celdaValorConTitulo:@"Probar el feed" detalle:@"" tabla:tabla];
        }
        return [self celdaValorConTitulo:@"Olvidar dispositivo y cookies" detalle:@"" tabla:tabla];
    }
    if (ruta.section == 2) {
        if (ruta.row == 0) {
            return [self celdaValorConTitulo:@"Fondo"
                                     detalle:[TTTheme tituloDeFondo:[TTTheme fondoClave]]
                                        tabla:tabla];
        }
        return [self celdaValorConTitulo:@"Color de botones"
                                 detalle:[TTTheme tituloDeAcento:[TTTheme acentoClave]]
                                    tabla:tabla];
    }
    // Acerca de
    if (ruta.row == 0) {
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        return [self celdaValorConTitulo:@"Version" detalle:(version ?: @"1.0.0") tabla:tabla];
    }
    static NSString *reutilizar = @"info";
    UITableViewCell *c = [tabla dequeueReusableCellWithIdentifier:reutilizar];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:reutilizar];
    c.textLabel.text = @"Como funciona";
    c.textLabel.textColor = [TTTheme acento];
    c.backgroundColor = [TTTheme superficie];
    return c;
}

- (void)tableView:(UITableView *)tabla didSelectRowAtIndexPath:(NSIndexPath *)ruta {
    [tabla deselectRowAtIndexPath:ruta animated:YES];

    if (ruta.section == 0 && ruta.row == 0)   { [self elegirModo]; return; }
    if (ruta.section == 0 && ruta.row == 1)   { [self editarRelay]; return; }
    if (ruta.section == 0 && ruta.row == 2)   { [self probarRelay]; return; }
    if (ruta.section == 1 && ruta.row == 0)   { [self editarCookies]; return; }
    if (ruta.section == 1 && ruta.row == 1)   { [self probarFeed]; return; }
    if (ruta.section == 1 && ruta.row == 2)   { [self olvidar]; return; }
    if (ruta.section == 2 && ruta.row == 0)   { [self elegirFondo]; return; }
    if (ruta.section == 2 && ruta.row == 1)   { [self elegirAcento]; return; }
    if (ruta.section == 3 && ruta.row == 1)   { [self explicar]; return; }
}

#pragma mark - Reproduccion

- (NSString *)tituloDelModo:(UITableView *)tabla {
    (void)tabla;
    NSString *m = [TTResolvedor modo];
    if ([m isEqualToString:@"directo"]) return @"Solo directo";
    if ([m isEqualToString:@"relay"])   return @"Solo relay";
    return @"Automatico";
}

- (void)elegirModo {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Modo de reproduccion"
                         message:@"Automatico reproduce directo y, solo si falla, "
                                  "prueba el relay."
                  preferredStyle:UIAlertControllerStyleActionSheet];
    void (^poner)(NSString *, NSString *) = ^(NSString *clave, NSString *titulo) {
        [a addAction:[UIAlertAction actionWithTitle:titulo style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *accion) {
            [TTResolvedor guardarModo:clave];
            [[TTResolvedor compartido] vaciarCache];
            [self->_tabla reloadData];
        }]];
    };
    poner(@"auto", @"Automatico (recomendado)");
    poner(@"directo", @"Solo directo");
    poner(@"relay", @"Solo relay");
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self anclar:a];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)editarRelay {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Relay"
                         message:@"Direccion del programa relay/servidor.py en tu red "
                                  "(p.ej. http://192.168.1.50:8787) y, si lo pusiste, su token."
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *campo) {
        campo.placeholder = @"http://192.168.1.50:8787";
        campo.text = [TTResolvedor relayBase];
        campo.keyboardType = UIKeyboardTypeURL;
        campo.autocapitalizationType = UITextAutocapitalizationTypeNone;
        campo.autocorrectionType = UITextAutocorrectionTypeNo;
        campo.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *campo) {
        campo.placeholder = @"token (opcional)";
        campo.text = [TTResolvedor relayToken];
        campo.autocapitalizationType = UITextAutocapitalizationTypeNone;
        campo.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Guardar" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *accion) {
        [TTResolvedor guardarRelay:a.textFields[0].text token:a.textFields[1].text];
        [[TTResolvedor compartido] vaciarCache];
        [self->_tabla reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)probarRelay {
    [self mostrarEspera:@"Probando el relay..."];
    [[TTResolvedor compartido] probarRelay:^(NSString *informe, BOOL correcto) {
        [self ocultarEspera];
        [self mostrarAlerta:correcto ? @"Relay" : @"El relay no responde" texto:informe];
    }];
}

#pragma mark - Sesion

- (void)editarCookies {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Cookies de TikTok"
                         message:@"Opcional.  La reproduccion directa ya funciona sin "
                                  "cookies (el CDN solo pide el Referer).  Solo hacen "
                                  "falta si quieres pedir el feed con tu propia sesion "
                                  "de www.tiktok.com."
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *campo) {
        campo.placeholder = @"msToken=...; ttwid=...";
        campo.text = [[TTSesion compartida] cookiesManuales];
        campo.autocapitalizationType = UITextAutocapitalizationTypeNone;
        campo.autocorrectionType = UITextAutocorrectionTypeNo;
        campo.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Borrar" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *accion) {
        [[TTSesion compartida] guardarCookiesManuales:@""];
        [self->_tabla reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Guardar" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *accion) {
        [[TTSesion compartida] guardarCookiesManuales:a.textFields[0].text];
        [self->_tabla reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)probarFeed {
    [self mostrarEspera:@"Consultando el feed..."];
    [[TTCliente compartido] probarConexion:^(NSString *informe, BOOL correcto) {
        [self ocultarEspera];
        [self mostrarAlerta:correcto ? @"El feed funciona" : @"No se pudo cargar el feed"
                      texto:informe];
    }];
}

- (void)olvidar {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Olvidar"
                         message:@"Se borran el identificador de dispositivo y las cookies. "
                                  "TikTok te vera como un telefono nuevo."
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Olvidar" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *accion) {
        [[TTSesion compartida] olvidarTodo];
        [TTCliente vaciarCacheImagenes];
        [self->_tabla reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Tema

- (void)elegirFondo {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Fondo" message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *f in [TTTheme fondosDisponibles]) {
        [a addAction:[UIAlertAction actionWithTitle:f[@"titulo"] style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *accion) {
            [TTTheme guardarFondo:f[@"clave"] acento:[TTTheme acentoClave]];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self anclar:a];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)elegirAcento {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Color de botones" message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *acc in [TTTheme acentosDisponibles]) {
        [a addAction:[UIAlertAction actionWithTitle:acc[@"titulo"] style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *accion) {
            [TTTheme guardarFondo:[TTTheme fondoClave] acento:acc[@"clave"]];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self anclar:a];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Acerca de

- (void)explicar {
    NSString *texto =
        @"Todo ocurre en el telefono: la app firma las peticiones a TikTok con el "
        "algoritmo web (X-Gnarly) portado a C, y reproduce el video con la "
        "direccion firmada que ya viene en el propio feed.\n\n"
        @"El relay (relay/servidor.py) es OPCIONAL: solo sirve de puente por HTTP "
        "plano si iOS 9 no confia en el certificado del CDN o si tu red bloquea la "
        "conexion.  Sin relay, el feed y los videos siguen funcionando.\n\n"
        @"Buscar, comentarios y perfiles: TikTok los tiene bloqueados para clientes "
        "que no son la app oficial, asi que no se incluyen.";
    [self mostrarAlerta:@"Como funciona" texto:texto];
}

#pragma mark - Utilidades de interfaz

- (void)anclar:(UIAlertController *)hoja {
    if (![hoja respondsToSelector:@selector(popoverPresentationController)]) return;
    hoja.popoverPresentationController.sourceView = self.view;
    hoja.popoverPresentationController.sourceRect =
        CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
}

- (void)mostrarAlerta:(NSString *)titulo texto:(NSString *)texto {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:titulo
                                                              message:texto
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Vale" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)mostrarEspera:(NSString *)texto {
    if (_espera) return;
    _espera = [UIAlertController alertControllerWithTitle:nil message:texto
                                          preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:_espera animated:YES completion:nil];
}

- (void)ocultarEspera {
    if (!_espera) return;
    [_espera dismissViewControllerAnimated:YES completion:nil];
    _espera = nil;
}

@end
