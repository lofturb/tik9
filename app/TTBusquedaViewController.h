// TTBusquedaViewController.h -- la pantalla de la lupa.
#import <UIKit/UIKit.h>
#import "TTVideo.h"

// El feed se entera de que el usuario ha elegido un video para saltar a el.
@protocol TTBusquedaDelegado <NSObject>
- (void)busquedaElegirVideo:(TTVideo *)video;
@end

@interface TTBusquedaViewController : UIViewController

@property (nonatomic, weak) id<TTBusquedaDelegado> delegado;

// Los videos que el feed ya tiene cargados.  De aqui salen las sugerencias
// (retos y autores) y los resultados de la busqueda local.
@property (nonatomic, copy) NSArray *videos;

@end
