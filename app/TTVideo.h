// TTVideo.h -- un video del feed, ya interpretado.
//
// Se construye a partir del "itemStruct" de la API web (recommend/item_list o
// item/detail).  Guarda lo justo para pintar el feed y para poder guardarlo en
// Favoritos sin volver a pedirlo a TikTok.
#import <Foundation/Foundation.h>

@interface TTVideo : NSObject

@property (nonatomic, copy)   NSString *identificador;   // item id
@property (nonatomic, copy)   NSString *descripcion;     // pie de video
@property (nonatomic, copy)   NSString *autorUsuario;    // @uniqueId
@property (nonatomic, copy)   NSString *autorNombre;     // nombre visible
@property (nonatomic, copy)   NSString *autorId;         // secUid
@property (nonatomic, copy)   NSString *autorAvatar;     // URL de la foto
@property (nonatomic, copy)   NSString *musica;          // titulo del sonido
@property (nonatomic, copy)   NSString *musicaAutor;
@property (nonatomic, copy)   NSString *portada;         // URL de la miniatura
@property (nonatomic, copy)   NSString *portadaAnimada;  // URL del WebP animado
@property (nonatomic, copy)   NSString *videoId;         // identificador interno ("v14...")
@property (nonatomic, copy)   NSString *textoFecha;      // cuenta de tiempo (opcional)

@property (nonatomic, assign) NSInteger segundos;
@property (nonatomic, assign) NSInteger ancho;
@property (nonatomic, assign) NSInteger alto;

@property (nonatomic, assign) long long meGusta;
@property (nonatomic, assign) long long comentarios;
@property (nonatomic, assign) long long compartidos;
@property (nonatomic, assign) long long reproducciones;
@property (nonatomic, assign) long long guardados;

@property (nonatomic, copy)   NSArray *retos;            // hashtags (sin #)

// Direcciones de video del propio itemStruct, en orden de preferencia: primero
// las del endpoint firmado /aweme/v1/play/ (las unicas que dan un MP4
// reproducible), luego las de v16-webapp-prime.  Solo las variantes H.264 (un
// chip de 32 bits no decodifica HEVC).
@property (nonatomic, copy)   NSArray *urlsDirectas;

// La mejor candidata (o nil).  Es la que se manda al relay si hace falta.
- (NSString *)mejorUrlDirecta;

// SI o NO: el elemento trae alguna direccion de video.  Las publicaciones de
// SOLO FOTOS (el "modo foto" de TikTok, el nodo imagePost) no traen ninguna, y
// por eso salian sin direccion de reproduccion: no son videos.  La app las
// salta en vez de ofrecerlas.
- (BOOL)tieneVideo;

+ (instancetype)desdeItemStruct:(NSDictionary *)item;
+ (NSArray *)listDesdeItemList:(NSArray *)items;

// Guardar / leer de Favoritos.
- (NSDictionary *)aDiccionario;
+ (instancetype)desdeDiccionario:(NSDictionary *)d;

// "1,2 M" / "568" / "3,4 B", al estilo de la app oficial.
+ (NSString *)textoDeCuenta:(long long)cuenta;
- (NSString *)textoMeGusta;
- (NSString *)textoComentarios;
- (NSString *)textoCompartidos;

- (NSURL *)urlPortada;   // URL, o la del WebP animado, o nil

@end
