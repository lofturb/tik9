# ---------------------------------------------------------------------------
#  Tik9 -- cliente de TikTok para iOS 9.3.5 (32 bits, armv7)
#  Compilado con Theos + iPhoneOS9.3.sdk en Linux (GitHub Actions, gratis).
#  Ver README.md en la raiz del repositorio.
# ---------------------------------------------------------------------------

# plataforma:compilador:sdk_del_sistema:version_minima
#   9.3 -> usa $THEOS/sdks/iPhoneOS9.3.sdk
#   9.0 -> -miphoneos-version-min=9.0 (todo dispositivo con 9.3.5 lo cumple)
TARGET = iphone:clang:9.3:9.0

# iPhone 4S/5/5C, iPad 2/3/4, iPad mini 1 y iPod touch 5G son de 32 bits.
ARCHS = armv7

# Empaquetado directo a .ipa (requiere el fichero 'control' de al lado).
PACKAGE_FORMAT = ipa

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Tik9

# TTSignaCore.c es el port a C de la firma web de TikTok (X-Dynosaur +
# X-Gnarly).  Es C puro y trae su propio MD5, asi que no necesita CommonCrypto
# ni Objective-C: compila igual aqui que en el ordenador de pruebas, que es lo
# que permite compararlo linea a linea con el oraculo de Python.
Tik9_FILES = \
	main.m \
	AppDelegate.m \
	TTTheme.m \
	TTVideo.m \
	TTSesion.m \
	TTCliente.m \
	TTResolvedor.m \
	TTFavoritos.m \
	TTFavoritosViewController.m \
	TTPlayer.m \
	TTVideoCell.m \
	TTFeedViewController.m \
	TTBusquedaViewController.m \
	TTAjustesViewController.m \
	TTSignaCore.c

# QuartzCore para las capas (esquinas redondeadas, sombreado del texto) y
# AVFoundation para reproducir.  MediaPlayer solo para el mando del sistema
# (los botones +/-10 s de la pantalla de bloqueo).  Security es para mirar la
# cadena de certificados del diagnostico, y CFNetwork para el proxy del sistema.
Tik9_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore AVFoundation MediaPlayer Security CFNetwork
Tik9_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-parameter
Tik9_RESOURCE_DIRS = Resources

# Todo lo que hay en Resources/ (Info.plist, iconos, imagenes de arranque) se
# copia a la raiz del .app.  Theos hace esto automaticamente.
Tik9_LDFLAGS = -Wl,-dead_strip

include $(THEOS_MAKE_PATH)/application.mk
