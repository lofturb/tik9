// TTVideoCell.h -- una celda = un video a pantalla completa.
//
// La capa del reproductor la engancha el controlador del feed dentro de
// "contenedorVideo": asi hay un solo AVPlayer para todo el feed.
#import <UIKit/UIKit.h>
#import "TTVideo.h"

@interface TTVideoCell : UITableViewCell

@property (nonatomic, strong) TTVideo *video;
@property (nonatomic, strong) UIView *contenedorVideo;   // donde va la capa

@property (nonatomic, copy) void (^alTocarFondo)(TTVideoCell *celda);   // pausa / sigue
@property (nonatomic, copy) void (^alTocarMeGusta)(TTVideo *video);
@property (nonatomic, copy) void (^alTocarComentario)(TTVideo *video);
@property (nonatomic, copy) void (^alTocarCompartir)(TTVideo *video);
@property (nonatomic, copy) void (^alTocarReintentar)(TTVideo *video);

- (void)configurarCon:(TTVideo *)video indice:(NSInteger)indice;

// La portada se oculta en cuanto el video se pinta, y vuelve al pausar.
- (void)ponerPortadaVisible:(BOOL)visible;
- (void)mostrarCargando:(BOOL)cargando;
- (void)mostrarError:(NSString *)texto;
- (void)mostrarIconoPausa:(BOOL)pausado;
- (void)marcarMeGusta:(BOOL)gusta;

@end
