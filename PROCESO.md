# Cómo se compila el `.ipa` de Tik9

Este documento es el **manual del proceso**: qué herramientas se usan, en qué
orden, por qué, y qué hacer cuando algo falla. Sirve para repetirlo en el futuro
(o para montar otra app igual desde cero). El camino de compilar y empaquetar
es el mismo que usa **Tube9**; lo que cambia es la capa de servicio (TikTok en
vez de YouTube).

---

## 0. Por qué compilar un `.ipa` así es tan rápido y sencillo

Corta respuesta: **porque no usamos la cadena oficial de Apple por ningún lado**.
Nada de Xcode, nada de Swift, nada de firma con certificado, nada de *asset
catalogs*. Solo un compilador de C/Objective-C, un enlazador y un ZIP.

| Paso | Un `.apk` de Android | Este `.ipa` |
|---|---|---|
| Herramienta de construcción | Gradle (una máquina virtual de Java arrancando en cada `build`) | `make` (un programa de 1976, arranca al instante) |
| Compilación del código | `javac`/Kotlin → bytecode → **D8/R8** (`dex`) → optimización → `dex` | `clang`: código máquina directo, **una sola pasada** |
| Empaquetado | `aapt2` (compila todos los recursos XML, PNG...) + `zipalign` | Copiar `Resources/` tal cual y `zip` |
| Firma | `apksigner` con un almacén de claves | `ldid` (una firma falsa de 10 ms; va sin certificado) |
| Recursos gráficos | `aapt2` compila cada XML a binario | Ninguno: los iconos ya son PNG y los dibuja un script una vez |
| Dependencias | Se descarga medio Maven la primera vez | Theos + SDK ya están en la caché del CI |
| Tamaño del código | Miles de clases | 13 ficheros `.m` + 1 `.c` (la firma), ~270 KB de binario |
| **Tiempo real aquí** | 1–5 minutos de media | **~40 segundos** |

La parte que casi nunca se dice: **es rápido porque nos saltamos el
"sistema de verdad"**. Un iOS moderno con Xcode tarda bastante más (Swift, IB,
firma, *app thinning*), y una app distribuida legalmente necesita la firma de
Apple (y pagar los 99 $/año del programa de desarrolladores). Aquí no hay ni
una cosa ni la otra:

* **No hay firma de Apple.** `ldid -S` mete una firma *falsa* (ad-hoc). El
  dispositivo la acepta solo porque tiene **jailbreak + AppSync Unified**, que
  desactiva la comprobación. En un iPhone sin jailbreak este `.ipa` **no se
  instala**.
* **No hay Xcode.** Usamos `clang` a pelo contra un SDK copiado. Es lo que hace
  Theos, y es legal para uso personal/educativo.
* **No hay storyboards ni Swift.** Todo el interfaz es código Objective-C
  (`[[UIView alloc] init]` y a mano). Eso quita decenas de pasos del proceso.

Resumen: un APK pasa por una fábrica; esto es una calculadora. De ahí la
diferencia de tiempo.

---

## 1. Las piezas

| Pieza | Para qué | De dónde sale | Precio |
|---|---|---|---|
| **GitHub Actions** (`ubuntu-22.04`) | La máquina que compila | Repositorios públicos: minutos ilimitados | 0 € |
| **Theos** | Los ficheros `Makefile` que saben de iOS (TARGET, ARCHS, `.ipa`) | `github.com/theos/theos` | 0 € |
| **clang + toolchain LLVM** | El compilador. Hay que usar uno que sepa generar **armv7** | release `test-210562a` de `github.com/L1ghtmann/llvm-project` (`iOSToolchain-x86_64.tar.xz`) | 0 € |
| **iPhoneOS9.3.sdk** | Las cabeceras y librerías de iOS 9.3 | `github.com/theos/sdks` (subcarpeta `iPhoneOS9.3.sdk`) | 0 € |
| **ldid** | Firma falsa (la trae Theos) | dentro de Theos | 0 € |
| **Python 3** | Generar iconos, imágenes de arranque y certificados | ya viene en Ubuntu | 0 € |
| **Python (local)** | `tools/verificar_ipa.py`: comprobar el `.ipa` sin Mac | tu PC | 0 € |

Nada de esto requiere un Mac, ni Xcode, ni cuenta de desarrollador de Apple.

---

## 2. El flujo, paso a paso

Lo hace todo `.github/workflows/build-ipa.yml`. Cada paso, y **por qué está**:

### 2.1 Sistema: `ubuntu-22.04` (y no una versión más nueva)

El toolchain LLVM de 2023 está compilado contra glibc 2.35 (la de Ubuntu 22.04).
En 24.04 las librerías del sistema son más nuevas y algunos binarios se quejan.
Además 22.04 todavía tiene `libtinfo5`, que ciertos binarios del toolchain
necesitan.

```yaml
runs-on: ubuntu-22.04
```

Paquetes que se instalan:

```
build-essential fakeroot rsync curl perl zip unzip git
libxml2 xz-utils libz3-dev libtinfo6 libtinfo5
```

* `fakeroot` → Theos lo usa para empaquetar con los permisos correctos
  (`update-alternatives --set fakeroot /usr/bin/fakeroot-sysv`).
* `libz3-dev` → la librería de *solver* que necesita `clang`.
* `libtinfo5` → puede no existir en el repositorio; por eso va con `|| echo`.

### 2.2 Caché de Theos

Theos + SDK + toolchain son **~1,5 GB**. Se cachean:

```yaml
key: theos-${{ runner.os }}-${{ env.TOOLCHAIN_TAG }}-sdk9.3-v2
```

> **Importante:** si algún día subes la versión del toolchain, **cambia
> `TOOLCHAIN_TAG` en el workflow**, porque la clave de la caché lo incluye y se
> volverá a descargar todo solo.

### 2.3 Instalar Theos + el toolchain

```bash
git clone --recursive --depth 1 https://github.com/theos/theos.git "$THEOS"
curl -fL -o /tmp/iOSToolchain.tar.xz \
  "https://github.com/L1ghtmann/llvm-project/releases/download/test-210562a/iOSToolchain-x86_64.tar.xz"
tar -xJf /tmp/iOSToolchain.tar.xz -C "$THEOS/toolchain/"
```

Con esto queda `$THEOS/toolchain/linux/iphone/bin/clang`, que es el compilador
que sabe hacer `armv7-apple-darwin`.

### 2.4 Instalar el SDK de iOS 9.3

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks.git /tmp/theos-sdks
git -C /tmp/theos-sdks sparse-checkout set iPhoneOS9.3.sdk
cp -a /tmp/theos-sdks/iPhoneOS9.3.sdk "$THEOS/sdks/"
```

El `--sparse` importa: el repositorio entero son muchos GB de SDKs y solo
hacemos falta uno.

### 2.5 **Las trampas gordas**: los `.tbd` que el SDK 9.3 no trae

El SDK 9.3 tiene **dos huecos** que se tapan copiando el `.tbd` equivalente del
SDK 10.3 (el nombre de instalación es el mismo y los símbolos también). Los dos
han hecho perder tiempo de verdad, así que conviene arreglarlos **antes** de
compilar.

**a) `liblaunch.tbd`.** `libSystem.B.tbd` dice que re-exporta
`/usr/lib/system/liblaunch.dylib`, pero **ese fichero no se generó nunca**
(incidencia conocida: `theos/sdks#10`). El enlazador falla con:

```
ld: file not found: /usr/lib/system/liblaunch.dylib
```

**b) `libsystem_c.tbd`.** No declara los **símbolos públicos de memoria**
(`_memcpy`, `_memset`, `_memmove`, `_bzero`): solo trae los internos
(`__platform_mem*`) y los `___memcpy_chk`. Lo destapa **cualquier fichero C**
que use `memcpy`/`memset` (en Tik9, `TTSignaCore.c`), con:

```
Undefined symbols for architecture armv7:
  "_memcpy", referenced from: ...
  "_memset", referenced from: ...
```

Se copian los dos:

```bash
SDK="$THEOS/sdks/iPhoneOS9.3.sdk"
REF="https://raw.githubusercontent.com/theos/sdks/master/iPhoneOS10.3.sdk"
curl -fsSL -o "$SDK/usr/lib/system/liblaunch.tbd"   "$REF/usr/lib/system/liblaunch.tbd"
curl -fsSL -o "$SDK/usr/lib/system/libsystem_c.tbd" "$REF/usr/lib/system/libsystem_c.tbd"
```

Sin el paso (a), **nada enlaza** contra el SDK 9.3. Sin el (b), solo enlazan las
apps de Objective-C puro; en cuanto entre un `.c` con `memcpy`, falla. El
*workflow* del repositorio aplica los dos solo.

### 2.6 Generar iconos e imágenes de arranque

```bash
python3 tools/generar_recursos.py
```

Produce en `app/Resources/` los `Icon-*.png` y `LaunchImage-*.png` en los
tamaños que pide iOS 9 (60@2x, 76, 76@2x, Small-40@2x/3x, 568h...). Así no hay
que guardar binarios en el repositorio.

### 2.7 Compilar y empaquetar

```bash
cd app
make clean
make package FINALPACKAGE=1 PACKAGE_FORMAT=ipa
```

Esto lee `app/Makefile`:

```makefile
TARGET = iphone:clang:9.3:9.0   # SDK 9.3, mínimo iOS 9.0
ARCHS  = armv7                  # 32 bits (iPhone 4S/5/5C, iPad 2/3/4...)
PACKAGE_FORMAT = ipa            # saca un .ipa, no un .deb
```

y hace tres cosas: compila cada `.m` (y el `TTSignaCore.c` de la firma) con
`clang -fobjc-arc`, enlaza el binario, y lo coloca dentro de
`Payload/Tik9.app/` junto a `Resources/` y el `Info.plist`.

El resultado aparece en `app/packages/com.lofturb.tik9_1.0.0.ipa`.

### 2.8 Comprobar que el `.ipa` es de verdad para iOS 9 / armv7

```bash
otool -hv "$BIN"                                   # armv7
unzip -l "$IPA" | grep 'Payload/Tik9.app/Tik9'      # el ejecutable está
unzip -l "$IPA" | grep 'Payload/Tik9.app/Info.plist'
```

### 2.9 Publicarlo

1. **Artefacto** (`actions/upload-artifact`): caduca a los 90 días y para
   descargarlo hay que tener sesión en GitHub.
2. **Release** (tag `build-AAAAMMDD-HHMMSS`): descargable desde cualquier
   navegador, **incluso desde el propio iPhone**. Esta es la que se usa para
   instalarlo en el dispositivo.
   Las notas del Release no van escritas dentro del *workflow* sino en
   **`.github/notas-release.md`**, y se marca con `--latest` para que sea la
   entrada que se vea la primera: así, quien llegue al repositorio sin saber
   nada puede leer qué es, qué trae la versión y cómo se instala sin abrir
   siquiera el README.

---

## 3. Cómo lanzarlo

* **Automático**: cualquier `push` a `main` (o `master`).
* **A mano, desde la web**: Actions → *Construir IPA* → *Run workflow*.
* **A mano, con `gh`**:

```bash
gh workflow run build-ipa.yml
gh run list --limit 3
gh run watch
```

Al terminar, la lista de Releases:

```bash
gh release list --limit 5
```

En Windows 7, `gh release download` da problemas (msys); la alternativa que
funciona:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$rel = Invoke-RestMethod -Uri "https://api.github.com/repos/lofturb/tik9/releases/tags/build-XXXX" -Headers @{ "User-Agent" = "ps" }
Invoke-WebRequest -Uri $rel.assets[0].url -Headers @{ "User-Agent" = "ps"; "Accept" = "application/octet-stream" } -OutFile Tik9.ipa
```

---

## 4. Comprobar el `.ipa` sin Mac

```bash
python tools/verificar_ipa.py Tik9.ipa
```

Lee el Mach-O y el `Info.plist` **dentro** del `.ipa` y dice:

* arquitectura (`ARM / armv7`, 32 bits) y `LC_VERSION_MIN_IPHONEOS`;
* si está firmado y con qué (`ldid`, no Apple);
* las librerías de las que depende;
* `CFBundleIdentifier`, versión, `MinimumOSVersion`, `UIDeviceFamily`;
* la lista de recursos.

Si algo no cuadra, el veredicto final lo dice en una línea.

---

## 5. Instalarlo en el dispositivo

1. **Jailbreak** en iOS 9.3.5 (Phoenix, p0sixspwn, etc.).
2. **AppSync Unified** desde Cydia (permite instalar apps sin firma de Apple).
3. Copiar el `.ipa` al dispositivo y abrirlo con **Filza**, o:

```bash
ipainstaller Tik9.ipa
```

> **Ojo:** este `.ipa` va firmado con `ldid` (firma falsa). **No se instala en
> un iPhone sin jailbreak**, y no sirve firmarlo con AltStore/Sideloadly para
> iOS 9 desde Windows sin un certificado válido de Apple.

---

## 6. Compilar en tu propio ordenador (si algún día quieres)

No hace falta, pero se puede. Windows 7 **no puede ejecutar WSL2**, así que la
opción es una máquina virtual (VirtualBox) con **Ubuntu 22.04**.

```bash
# 1. dependencias
sudo apt-get update
sudo apt-get install -y build-essential fakeroot rsync curl perl zip unzip git \
  libxml2 xz-utils libz3-dev libtinfo6 libtinfo5
sudo update-alternatives --set fakeroot /usr/bin/fakeroot-sysv

# 2. theos + toolchain
export THEOS="$HOME/theos"
git clone --recursive --depth 1 https://github.com/theos/theos.git "$THEOS"
curl -fL -o /tmp/tc.tar.xz \
  "https://github.com/L1ghtmann/llvm-project/releases/download/test-210562a/iOSToolchain-x86_64.tar.xz"
tar -xJf /tmp/tc.tar.xz -C "$THEOS/toolchain/"

# 3. sdk 9.3
git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks.git /tmp/sdks
git -C /tmp/sdks sparse-checkout set iPhoneOS9.3.sdk
cp -a /tmp/sdks/iPhoneOS9.3.sdk "$THEOS/sdks/"

# 4. los parches de .tbd del SDK 9.3 (liblaunch + libsystem_c)
SDK="$THEOS/sdks/iPhoneOS9.3.sdk"
REF="https://raw.githubusercontent.com/theos/sdks/master/iPhoneOS10.3.sdk"
curl -fsSL -o "$SDK/usr/lib/system/liblaunch.tbd"   "$REF/usr/lib/system/liblaunch.tbd"
curl -fsSL -o "$SDK/usr/lib/system/libsystem_c.tbd" "$REF/usr/lib/system/libsystem_c.tbd"

# 5. compilar
cd app && make clean && make package FINALPACKAGE=1 PACKAGE_FORMAT=ipa
```

---

## 7. Empezar de cero con otra app (la receta)

1. **Estructura mínima**

   ```
   app/
     Makefile
     control
     main.m
     AppDelegate.h / AppDelegate.m
     Resources/Info.plist
   ```

2. **`Makefile`** — esto es todo lo que hace falta:

   ```makefile
   TARGET = iphone:clang:9.3:9.0
   ARCHS  = armv7
   PACKAGE_FORMAT = ipa
   include $(THEOS)/makefiles/common.mk

   APPLICATION_NAME = MiApp
   MiApp_FILES = main.m AppDelegate.m
   MiApp_FRAMEWORKS = UIKit Foundation
   MiApp_CFLAGS = -fobjc-arc
   MiApp_RESOURCE_DIRS = Resources

   include $(THEOS_MAKE_PATH)/application.mk
   ```

3. **`main.m`**: `UIApplicationMain(argc, argv, nil, @"AppDelegate")` y nada más.
   Interfaz **por código** (nada de storyboards: son un mundo aparte y en
   iOS 9 con Theos dan más problemas que ventajas).

4. **`Info.plist`**: las claves que iOS 9 pide para que la app arranque sin
   barras negras y no la mate el sistema:

   * `CFBundleIdentifier`, `CFBundleExecutable`, `CFBundleName`,
     `CFBundleDisplayName`, `CFBundleVersion`, `CFBundleShortVersionString`
   * `MinimumOSVersion` = `9.0`
   * `LSRequiresIPhoneOS`
   * `UIDeviceFamily` = `[1, 2]` (iPhone + iPad)
   * `UIRequiredDeviceCapabilities` = `armv7`
   * `UILaunchImages` (si no, la app se ve con barras negras: literalmente iOS
     la ejecuta a 320×480 y luego la escala)
   * `UISupportedInterfaceOrientations`

5. **Limitaciones reales de iOS 9 con este método**

   * **Objective-C o C.** Nada de Swift (necesita el runtime de Swift, que no
     existe en iOS 9) ni de bibliotecas dinámicas propias.
   * **Vídeo: H.264 en MP4.** Es lo que reproducen los chips de 32 bits (A5/A6)
     y lo que sirve TikTok por web (**hasta 540p**). Hay que **evitar las
     variantes `h265_hvc1`**: no se decodifican en hardware.
   * **Nada de WebP**: `UIImage` de iOS 9 no lo entiende (en Tube9 esto costó
     el bug de las miniaturas; en TikTok las miniaturas son JPEG, así que no
     aplica).
   * TLS: iOS 9 solo trae raíces antiguas. O se instalan las modernas en el
     dispositivo, o se usa un relay con certificados propios.
   * **Firmas anti-bot**: TikTok cierra sus servicios a los clientes que no son
     la app oficial. La firma web (`X-Gnarly`) se puede reproducir **en C**
     dentro de la app (es lo que hace Tik9 con `TTSignaCore.c`), y la dirección
     de vídeo que llega en el feed **ya viene firmada**; el CDN solo pide el
     `Referer`. Buscar, comentarios y perfiles, en cambio, devuelven vacío: no
     se pueden fingir.

---

## 8. Errores que ya nos han pasado (y su arreglo)

| Error en el log | Qué significa | Arreglo |
|---|---|---|
| `ld: file not found: /usr/lib/system/liblaunch.dylib` | Falta el `.tbd` en el SDK 9.3 (`theos/sdks#10`) | Paso 2.5 (copiarlo del SDK 10.3) |
| `Undefined symbols: _memcpy / _memset` (al enlazar) | El `libsystem_c.tbd` del SDK 9.3 **no declara los símbolos de memoria** (solo los internos `__platform_mem*` y los `___memcpy_chk`); el del SDK 10.3 sí. Lo destapa **cualquier código C** que use `memcpy`/`memset` (p. ej. `TTSignaCore.c`); una app solo-Objective-C puede no toparse con ello nunca | Mismo arreglo que `liblaunch.tbd`: copiar el `libsystem_c.tbd` del SDK 10.3 (el CI ya lo hace solo) |
| `error: no visible @interface ... declares the selector 'x:y:'` | Se llama a un método con menos parámetros de los que tiene | Pasar todos los parámetros (en Tik9 fue `celdaValorConTitulo:detalle:tabla:`) |
| `error: dereferencing a __weak pointer is not allowed` (`-Werror`) | Con ARC no se puede acceder a un `ivar` a través de un puntero `__weak` | Asignarlo antes a una variable local fuerte (`MiClase *x = deb;`) dentro del bloque |
| `error: assigning to 'id<UITableViewDataSource>' from incompatible type` (`-Werror`) | Se asigna `self` a `dataSource`/`delegate` **sin declarar conformidad** con el protocolo | Añadir `@interface MiControlador () <UITableViewDataSource, UITableViewDelegate>` en el `.m` |
| `error: property 'x' not found on object of type 'UITableView *'` | Se usa una propiedad que **no existe en el SDK 9.3** (p. ej. `contentInsetAdjustmentBehavior`, de iOS 11) | Buscarla por selector en tiempo de ejecución o usar la equivalente antigua (`automaticallyAdjustsScrollViewInsets`) |
| `fatal error: 'UIKit/UIKit.h' file not found` | El SDK no está donde Theos lo busca | `ls $THEOS/sdks/` → debe haber `iPhoneOS9.3.sdk`; comprobar `TARGET` |
| `error: unknown argument: '-miphoneos-version-min'` o "no soporta armv7" | Toolchain equivocado (uno arm64) | Usar el de `L1ghtmann/llvm-project`, tag `test-210562a` |
| `error: no known class method for selector 'player'` | `[AVPlayer player]` se inventó; en iOS 9 no existe | `[[AVPlayer alloc] init]` |
| `null passed to a callee that requires a non-null argument` | `-Werror -Wnonnull`: un bloque/parámetro que no admite `nil` | Pasar un bloque vacío (`completionHandler:^(BOOL f){}`) |
| `Package format 'ipa' not supported` | Falta `PACKAGE_FORMAT = ipa` o el `control` | Ver sección 7 |
| La app **arranca y se cierra sola** | Entitlements raros (`platform-application`, etc.) | No ponerlos: con `ldid` a secas basta |
| Se ve **con barras negras** arriba y abajo | Faltan `UILaunchImages` | `python3 tools/generar_recursos.py` |
| El CI **vuelve a descargar** 1,5 GB cada vez | Cambió la clave de caché | Es normal si cambia `TOOLCHAIN_TAG`; si no, revisar `key:` |

---

## 9. Cambiar la versión

La versión aparece en **dos** sitios y hay que tocar los dos:

* `app/Resources/Info.plist` → `CFBundleShortVersionString` y `CFBundleVersion`
* `app/control` → `Version`

> Subir la versión (sin cambiar `CFBundleIdentifier`) hace que al reinstalar se
> **sobrescriba** la app conservando los ajustes. Cambiar el identificador la
> convierte en otra app distinta y se instala al lado.

---

## 10. Chuleta

```bash
# lanzar la compilación y verla
gh workflow run build-ipa.yml && gh run watch

# última release y su IPA
gh release list --limit 3

# comprobar el IPA descargado, sin Mac
python tools/verificar_ipa.py Tik9.ipa

# regenerar iconos e imágenes de arranque
python tools/generar_recursos.py

# compilar a mano (Linux/WSL)
cd app && make clean && make package FINALPACKAGE=1 PACKAGE_FORMAT=ipa
```

---

*Última revisión: octubre de 2026 (Tik9 1.0.0).*
