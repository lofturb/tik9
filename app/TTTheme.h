// TTTheme.h -- paleta y estilos de la interfaz.
//
// Igual que en Tube9, hay dos fondos (oscuro y claro) y, dentro de cada uno,
// siete colores de botones: catorce combinaciones en total.  Para Tik9 el
// fondo por defecto es negro puro y el acento por defecto es el rosa de TikTok,
// pero se puede cambiar a gusto.
#import <UIKit/UIKit.h>

// Aviso de que el tema acaba de cambiar. Lo escucha AppDelegate, que vuelve a
// montar las pestanas: es la forma segura de repintarlo todo de una vez (si no,
// habria que repasar pantalla por pantalla).
extern NSString *const TTThemaCambio;

@interface TTTheme : NSObject

#pragma mark Elegir tema

+ (NSString *)fondoClave;        // @"oscuro" (por defecto) o @"claro"
+ (NSString *)acentoClave;       // @"rosa" (por defecto), @"cian", @"morado"...
+ (void)guardarFondo:(NSString *)fondo acento:(NSString *)acento;

// Listas para el selector, con su clave, su titulo y (los acentos) su color.
+ (NSArray *)fondosDisponibles;
+ (NSArray *)acentosDisponibles;

// El color de fondo de una opcion concreta, aunque no sea la elegida. Solo lo
// usa el selector de temas, para dibujar las muestras.
+ (UIColor *)fondoDeClave:(NSString *)clave;

// Nombre de la opcion elegida ("Oscuro", "Rosa"), para enseñarlo en Ajustes.
+ (NSString *)tituloDeFondo:(NSString *)clave;
+ (NSString *)tituloDeAcento:(NSString *)clave;

#pragma mark Colores

+ (UIColor *)fondo;              // fondo general
+ (UIColor *)superficie;         // tarjetas y celdas
+ (UIColor *)superficieAlta;     // campos de texto y "chips"
+ (UIColor *)borde;              // separadores suaves
+ (UIColor *)acento;             // color de los botones (ya ajustado al fondo)
+ (UIColor *)acentoSuave;        // relleno tenue del acento
+ (UIColor *)textoPrimario;
+ (UIColor *)textoSecundario;
+ (UIColor *)textoSobreAcento;   // blanco o negro, segun lo claro que sea el acento

#pragma mark Tipografia

+ (UIFont *)fuenteTituloFila;     // titulo de una fila ("Favoritos")
+ (UIFont *)fuenteTituloLista;    // titulo de una fila grande
+ (UIFont *)fuenteCuerpo;
+ (UIFont *)fuenteMenuda;
+ (UIFont *)fuenteDato;           // numeros junto a los iconos del feed

#pragma mark Helpers de dibujo

+ (UIColor *)colorHex:(NSUInteger)hex;
+ (UIColor *)colorHex:(NSUInteger)hex alpha:(CGFloat)alpha;
+ (UIImage *)imagenRedondeada:(UIImage *)imagen radio:(CGFloat)radio;

// Iconos vectoriales dibujados al vuelo (no hacen falta ficheros de imagen).
//   Formas: casa, corazon, corazonLleno, comentario, compartir, marcador,
//           marcadorLleno, musica, ajustes, chevron, cerrar, reproducir, pausa,
//           marca, canal, lista, sonido, silencio
+ (UIImage *)icono:(NSString *)forma lado:(CGFloat)lado;
+ (UIImage *)icono:(NSString *)forma lado:(CGFloat)lado trazo:(CGFloat)trazo;

// Pastilla ("chip") de filtro.
+ (void)aplicarEstiloChip:(UIButton *)boton seleccionado:(BOOL)seleccionado;

// Sombra de texto para que el titulo se lea sobre cualquier fotograma.
+ (void)aplicarSombraDeTexto:(UILabel *)etiqueta;

#pragma mark Apariencia global

+ (void)prepararAparienciaGlobal;
+ (void)aplicarEstiloTabBar:(UITabBar *)tabBar;

@end
