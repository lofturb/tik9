// AppDelegate.m -- monta la interfaz (todo por codigo, sin storyboards)
#import "AppDelegate.h"
#import "TTTheme.h"
#import "TTCliente.h"
#import "TTFeedViewController.h"
#import "TTFavoritosViewController.h"
#import "TTAjustesViewController.h"

@implementation AppDelegate {
    NSTimer *_rebote;   // espera corta antes de rehacer las pestanas
}

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    [TTTheme prepararAparienciaGlobal];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [self montarPestanas];
    // El "tint" del sistema (alertas, botones de barra...) va con el acento, que
    // es lo que hace que el tema se note tambien fuera de las pantallas propias.
    self.window.tintColor = [TTTheme acento];
    [self.window makeKeyAndVisible];

    // Cuando cambia el tema, se vuelven a montar las pestanas enteras. Es mas
    // simple (y mas seguro) que ir repintando pantalla por pantalla.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(alCambiarTema:)
                                                 name:TTThemaCambio
                                               object:nil];
    return YES;
}

#pragma mark - Interfaz

- (UITabBarController *)montarPestanas {
    // --- Pestana 1: Para ti -------------------------------------------------
    // El feed "Para ti" de TikTok (api/recommend/item_list), firmado en el
    // propio telefono con el port en C.  Es la pantalla principal: video a
    // pantalla completa y deslizar hacia arriba, como en la app oficial.
    TTFeedViewController *parati = [[TTFeedViewController alloc] initParaTi];
    UINavigationController *navParati =
        [[UINavigationController alloc] initWithRootViewController:parati];
    navParati.navigationBarHidden = YES;   // el feed va a pantalla completa
    navParati.tabBarItem = [[UITabBarItem alloc]
        initWithTitle:@"Para ti"
                image:[TTTheme icono:@"casa" lado:26]
        selectedImage:nil];

    // --- Pestana 2: Favoritos -----------------------------------------------
    // Guardados en el propio telefono.  Funciona sin red: se apunta el video
    // entero (no solo el identificador) para poder seguir viendo la ficha
    // aunque TikTok cambie o borre el video.
    TTFavoritosViewController *favoritos =
        [[TTFavoritosViewController alloc] init];
    UINavigationController *navFavoritos =
        [[UINavigationController alloc] initWithRootViewController:favoritos];
    navFavoritos.tabBarItem = [[UITabBarItem alloc]
        initWithTitle:@"Favoritos"
                image:[TTTheme icono:@"corazon" lado:26]
        selectedImage:nil];

    // --- Pestana 3: Ajustes -------------------------------------------------
    TTAjustesViewController *ajustes = [[TTAjustesViewController alloc] init];
    UINavigationController *navAjustes =
        [[UINavigationController alloc] initWithRootViewController:ajustes];
    navAjustes.tabBarItem = [[UITabBarItem alloc]
        initWithTitle:@"Ajustes"
                image:[TTTheme icono:@"ajustes" lado:26]
        selectedImage:nil];

    UITabBarController *tabs = [[UITabBarController alloc] init];
    tabs.viewControllers = @[ navParati, navFavoritos, navAjustes ];
    [TTTheme aplicarEstiloTabBar:tabs.tabBar];
    return tabs;
}

#pragma mark - Cambio de tema

- (void)alCambiarTema:(NSNotification *)aviso {
    // Se aplaza un poco a proposito: el aviso llega desde una pantalla que vive
    // DENTRO de las pestanas (el selector de temas). Desmontarlas en mitad de
    // ese toque seria pedir problemas, asi que se deja terminar primero.
    [_rebote invalidate];
    _rebote = [NSTimer scheduledTimerWithTimeInterval:0.15
                                               target:self
                                             selector:@selector(rehacerPestanas)
                                             userInfo:nil
                                              repeats:NO];
}

- (void)rehacerPestanas {
    UITabBarController *viejas = (UITabBarController *)self.window.rootViewController;
    NSInteger cual = 0;
    if ([viejas isKindOfClass:[UITabBarController class]]) {
        cual = viejas.selectedIndex;   // no perder la pestana en la que estabas
    }
    if (viejas.presentedViewController) {
        [viejas dismissViewControllerAnimated:NO completion:nil];
    }

    [TTTheme prepararAparienciaGlobal];
    UITabBarController *nuevas = [self montarPestanas];
    nuevas.selectedIndex = (cual >= 0 && cual < (NSInteger)nuevas.viewControllers.count) ? cual : 0;
    self.window.rootViewController = nuevas;
    self.window.tintColor = [TTTheme acento];
    [self.window makeKeyAndVisible];
}

@end
