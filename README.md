# Tik9 — cliente de TikTok para iOS 9.3.5 (armv7)

Cliente de TikTok ligero, **gratis y con interfaz plana moderna**, para
dispositivos de 32 bits que se quedaron en **iOS 9.3.5**:
iPhone 4S, iPhone 5, iPhone 5C, iPad 2, iPad 3, iPad 4, iPad mini 1 y iPod touch 5G.

Todo el proceso (compilar, empaquetar el `.ipa`) ocurre en **GitHub Actions,
gratis**, así que **no hace falta un Mac ni instalar un compilador en tu PC**.
El resultado es un `.ipa` que se descarga y se instala en el dispositivo.

> **Descargar el `.ipa`.** Está en
> **[Releases](https://github.com/lofturb/tik9/releases)**: la **última
> entrada** de la lista, con el fichero adjunto. No hace falta cuenta de GitHub
> ni saber nada del proyecto. Para instalarlo, mira la
> [Parte C](#parte-c--instalar-la-app); antes hay que hacer los pasos de la
> [Parte B](#parte-b--preparar-el-dispositivo) (jailbreak y certificados).

> **Nota legal.** Tik9 no es una app oficial de TikTok ni está afiliada a
> ByteDance. Accede al contenido a través de los mismos servicios web que usa la
> propia web de TikTok, por lo que siguen aplicándose las
> [Condiciones de Servicio de TikTok](https://www.tiktok.com/legal/terms-of-service).
> Es un proyecto educativo y de uso personal.

> **Lo esencial de esta entrega (y lo que la hace distinta de otros intentos).**
>
> * **El feed «Para ti» funciona sin relay y sin PC.** TikTok firma sus
>   peticiones internas con JavaScript, y en iOS 9 no hay dónde ejecutarlo. La
>   solución: el algoritmo **X-Gnarly** está **portado a C** y compila dentro de
>   la app, así que **el propio teléfono firma** lo que pide. No hace falta
>   ningún servidor encendido para ver vídeos.
> * **El vídeo se reproduce directo.** Cada vídeo del feed ya trae, dentro de su
>   ficha, una dirección `https://www.tiktok.com/aweme/v1/play/?…` **firmada**;
>   esa dirección redirige al MP4 del CDN de TikTok, que sólo pide la cabecera
>   `Referer: https://www.tiktok.com/`. La app la resuelve aquí mismo y le
>   entrega al reproductor la dirección final del CDN, ya sin redirecciones.
> * **El relay es OPCIONAL** (ver más abajo). Existe como plan B para cuando
>   iOS 9 no confía en el certificado del CDN o la red corta la conexión, pero
>   **no es obligatorio en ningún caso**.

---

## Índice

1. [Qué hace](#1-qué-hace)
2. [Cómo funciona por dentro](#2-cómo-funciona-por-dentro)
3. [Parte A — Conseguir el `.ipa`](#parte-a--conseguir-el-ipa)
4. [Parte B — Preparar el dispositivo](#parte-b--preparar-el-dispositivo)
5. [Parte C — Instalar la app](#parte-c--instalar-la-app)
6. [Ajustes de la app](#ajustes-de-la-app)
7. [Modo relay (opcional)](#modo-relay-opcional)
8. [Problemas frecuentes](#problemas-frecuentes)
9. [Estructura del repositorio](#estructura-del-repositorio)
10. [Compilar en tu propio ordenador (opcional)](#compilar-en-tu-propio-ordenador-opcional)

---

## 1. Qué hace

| Pantalla | Qué ofrece |
|---|---|
| **Para ti** | El feed de TikTok **vertical a pantalla completa**: **un vídeo por pantalla**, deslizar arriba y abajo cambia de vídeo, un toque lo pausa y lo reanuda. La lista se **pagina sola**: cuando llegas a los últimos, pide más. |
| **Favoritos** | Los vídeos que has guardado con el corazón, guardados **en el propio teléfono**. Se abren **a pantalla completa** y se quitan deslizando o con el botón *Vaciar*. Funciona sin red. |
| **Ajustes** | Modo de reproducción, relay, cookies, tema, diagnóstico y *Cómo funciona*. |

### La tarjeta de vídeo, en detalle

Cada vídeo ocupa toda la pantalla, como en la aplicación oficial:

| Elemento | Qué hace |
|---|---|
| **Deslizar arriba/abajo** | Pasa al vídeo siguiente o al anterior. |
| **Un toque en el vídeo** | Pausa o reanuda (aparece un icono grande un instante). |
| **Corazón** | Guarda o quita el vídeo de **Favoritos**. Se pone del color del tema. |
| **Comentario** | Muestra el aviso de que TikTok bloquea los comentarios (ver abajo). |
| **Compartir** | Manda el enlace (`https://www.tiktok.com/@usuario/video/…`) y la descripción con cualquier app instalada. |
| **Disco de música** | Gira mientras suena el vídeo, con el nombre del sonido debajo. |
| **Pie de texto** | Autor (`@usuario`), descripción y el sonido, con un degradado por detrás para que se lea sobre el vídeo. |
| **Botón de sonido** | Arriba a la derecha: silencia o devuelve el sonido. |

Si un vídeo no carga, **no se queda en «Cargando…» para siempre**: sale el error
con un botón **Reintentar** en la propia tarjeta.

Diseño: **reproductor vertical 9:16**, estilos planos, tipografía del sistema y
**todos los iconos dibujados por código** (vectoriales, sin ficheros de imagen).
Cero desenfoques y cero animaciones caras: todo eso funciona mal en un chip A5.
El único degradado de la app es el sombreado del pie de texto, para que se lea
sobre cualquier imagen.

### Lo que TikTok no da sin ser la app oficial

TikTok **cierra la puerta a los clientes que no son la aplicación oficial**. No
es cosa de Tik9: es cómo están montados sus servicios hoy.

* **Buscar** devuelve respuestas vacías para quien no trae la firma de la app
  oficial. Por eso **no hay pestaña de búsqueda**.
* **Comentarios** lo mismo. El botón existe para no dejar un hueco raro, pero
  al tocarlo lo explica sin rodeos en lugar de fingir.
* **Perfiles** tampoco se sirven. No hay pantalla de perfil.
* El **feed** y los **vídeos** sí funcionan, y es en lo que se centra la app.

---

## 2. Cómo funciona por dentro

```
                 ┌──────────────────────────────────┐
   iPhone 4S     │  Tik9 (Objective-C, armv7)       │
   iPad 2   ───► │  firma X-Gnarly (C) ─┐           │
   iPod 5G       │  AVPlayer ◄── MP4 ◄──┘           │
                 └───────────┬──────────────────────┘
                             │
              MODO DIRECTO   │   MODO RELAY (opcional)
       (recomendado, HTTPS)  │   (HTTP plano en tu red)
                             ▼
              ┌──────────────────────────────┐        ┌────────────────────┐
              │  api/recommend/item_list     │        │  relay/servidor.py │
              │  www.tiktok.com (firmado)    │  ◄──►  │  en tu PC          │
              │  CDN (v16/v19-web-newkey)    │        │  (o un servidor)   │
              └──────────────────────────────┘        └────────────────────┘
```

* **La firma X-Gnarly, en C.** TikTok exige a sus peticiones web una firma
  (`X-Gnarly`, y antes `X-Bogus`) que se calcula **con JavaScript**. En iOS 9 no
  hay motor de JavaScript donde ejecutarla. La salida de este proyecto: el
  algoritmo está **reproducido en C puro** (`app/TTSignaCore.c`) y se compila
  dentro de la app. Trae su propio MD5, así que no depende de `CommonCrypto` ni
  de Objective-C, y eso permitió **compararlo línea a línea con un oráculo en
  Python** (`prototipo/`) hasta que coincidió bit a bit. Por eso el teléfono
  puede pedir el feed **él solo**.
* **La reproducción, directa.** La respuesta del feed (`item_list`) trae, por
  cada vídeo, una dirección **ya firmada** `https://www.tiktok.com/aweme/v1/play/?…`.
  La app la pide con `Range: bytes=0-0`, sigue el `302` y obtiene la dirección
  final del CDN (`v16/v19-web-newkey.tiktokcdn.com`), que responde `206 Partial
  Content` y `accept-ranges: bytes`. **Se comprobó en vivo** que al CDN le basta
  la cabecera `Referer: https://www.tiktok.com/` (sin ella, `403`) y que el
  `User-Agent` da igual.
* **`AVPlayer`** reproduce esa dirección final. Se le pasan las cabeceras
  (`AVURLAssetHTTPHeaderFieldsKey`) con el `Referer`; entregarle la URL **final**
  del CDN (no la que redirige) evita que esas cabeceras se pierdan en el salto.
* **Modo relay.** Para cuando no se quieren tocar certificados: la app habla por
  **HTTP plano** con un pequeño servidor propio (`relay/servidor.py`, sólo
  biblioteca estándar de Python) que es quien habla con el CDN. La app le manda
  la dirección ya firmada, así que **el relay no firma nada**.

---

## Parte A — Conseguir el `.ipa`

El repositorio ya trae un *workflow* que compila el IPA automáticamente.

### Opción 1: desde el navegador

1. Entra en **https://github.com/lofturb/tik9/actions**.
2. Pulsa **«Construir IPA (iOS 9.3.5 / armv7)»** → **Run workflow**.
3. Espera 3-6 minutos (la primera vez tarda más porque descarga el *toolchain*).
4. Descarga el resultado de dos formas:
   * **Actions → ejecución terminada → Artifacts → `Tik9-ipa-armv7`**
     (requiere tener sesión iniciada en GitHub), o
   * **Releases** → la última entrada `build-AAAAMMDD-…` → descarga el `.ipa`
     adjunto **sin necesidad de iniciar sesión**.

### Opción 2: desde tu PC con `gh`

```powershell
# Lanzar la compilación
gh workflow run "Construir IPA (iOS 9.3.5 / armv7)" --repo lofturb/tik9

# Ver el estado
gh run list --repo lofturb/tik9

# Descargar el IPA de la última ejecución (se descomprime solo)
gh run download --repo lofturb/tik9 --name Tik9-ipa-armv7
```

### Comprobar el `.ipa` descargado (opcional)

```powershell
python tools\verificar_ipa.py entrega\Tik9.ipa
```

Te dice la arquitectura, la versión mínima de iOS y si va firmado. Debe poner
`armv7`, `minimo 9.0` y `pseudo-firmado`.

---

## Parte B — Preparar el dispositivo

Son **dos cosas de una sola vez**: el *jailbreak* y los certificados.

### B.1 Jailbreak

El dispositivo necesita **jailbreak** (es la vía para instalar apps que no están
firmadas por Apple).

* Para iOS 9.3.5 en dispositivos de 32 bits, la ruta habitual está en
  **https://ios.cfw.guide/** (busca tu modelo y versión). Herramientas conocidas
  para esta versión: **Phoenix** y **JailbreakMe 4.0**.
* Si tu dispositivo ya tiene Cydia instalado, este paso ya está hecho.

### B.2 Certificados actualizados ← **este es el paso clave**

iOS 9.3.5 es de 2016 y **no incluye las autoridades de certificación modernas**.
Por eso Safari, Cydia y cualquier app fallan hoy con errores de certificado
(`NSURLErrorServerCertificateUntrusted`, `-1202`).

No es un fallo de Tik9: es que iOS 9 no conoce a Let's Encrypt ni a las raíces
nuevas de Google, Amazon o DigiCert. Se arregla instalando las raíces modernas,
y **el repositorio ya trae el perfil hecho**:
`certificados/CertificadosModernos.mobileconfig`, que instala de una sola vez

* **ISRG Root X1** y **ISRG Root X2** (Let's Encrypt)
* **DigiCert Global Root G2** y **DigiCert Global Root CA**
* **GTS Root R1** y **GTS Root R4** (Google)
* **Amazon Root CA 1** y **Amazon Root CA 3**
* **Baltimore CyberTrust Root**

> **Aviso: el círculo vicioso.** El dispositivo **todavía no puede descargar
> nada por HTTPS**, da igual que sea desde GitHub o desde la web de Let's
> Encrypt. Así que el perfil hay que **pasarle el fichero desde el PC**, no
> intentar descargarlo con el propio dispositivo.

Dos formas de pasarlo, de más cómoda a más manual:

**1. Por la red local, sin cables ni correo (recomendada).** En el PC, dentro de
la carpeta del repositorio:

```powershell
cd certificados
python -m http.server 8000
```

Averigua la IP del PC con `ipconfig` (por ejemplo `192.168.1.50`) y abre en
**Safari del dispositivo**:

```
http://192.168.1.50:8000/CertificadosModernos.mobileconfig
```

Es HTTP plano dentro de tu propia red, así que funciona aunque el dispositivo no
confíe todavía en ningún certificado.

**2. Por correo.** Adjunta el `.mobileconfig` en un correo a ti mismo y ábrelo
desde la app Mail del dispositivo.

Después, en el dispositivo: **Ajustes → General → Perfil** (en iOS 9 aparece al
final de la lista) → *Instalar* → código de acceso si lo pide → *Instalar* otra
vez.

* En iOS 9 una raíz instalada así queda **de confianza para SSL
  automáticamente**: no hay que activar nada más.
* Si tu dispositivo fuera iOS 10.3 o superior, aparecería además
  *Ajustes → General → Información → Ajustes de confianza de certificados*;
  activa ahí el interruptor de cada certificado.

Con esto la app habla con TikTok directamente por HTTPS desde tu conexión de
casa (una IP residencial, que TikTok trata mucho mejor que las IP de centro de
datos).

*(El perfil se puede regenerar cuando quieras con
`python tools/generar_certificados.py`.)*

> ¿Prefieres no tocar certificados? Usa el **modo relay** (ver más abajo): la app
> habla por HTTP plano con un servidor tuyo y el problema de TLS desaparece.

---

## Parte C — Instalar la app

El `.ipa` que genera Theos está **pseudo-firmado** (`ldid`), así que el
dispositivo lo aceptará sólo si tiene **AppSync Unified**.

1. En Cydia, añade el repositorio de AppSync Unified:
   * `https://cydia.akemi.ai/` (repositorio de Karen/akemi), o
   * `https://lukezed.github.io/repo/`
   e instala **AppSync Unified**.
2. Instala el `.ipa` de cualquiera de estas formas:
   * **Filza** (o iFile): copia el `.ipa` al dispositivo, tócalo y elige
     *Instalar*.
   * **Por SSH**: `ipainstaller Tik9_1.0.0.ipa`
     (el paquete `ipainstaller` está en Cydia).
3. Abre **Tik9** desde la pantalla de inicio.

---

## Ajustes de la app

### Modo de reproducción

* **Automático** (por defecto): reproduce **directo** y, sólo si eso falla,
  prueba el **relay**.
* **Solo directo**: nunca usa el relay.
* **Solo relay**: va siempre por el relay configurado.

### Relay (opcional)

Activa este modo e introduce la dirección del servidor, por ejemplo
`http://192.168.1.50:8787`. Si el relay se arranca con `--token`, escríbelo
también. El botón **Probar el relay** comprueba que responde.

Recuerda: **el relay no es obligatorio**. Sólo lo necesitas si iOS 9 no confía
en el certificado del CDN de TikTok o si tu red corta esa conexión.

### Cookies y sesión (opcional)

**Ajustes → Cookies de TikTok.** La reproducción directa **ya funciona sin
cookies** (el CDN sólo pide el `Referer`). Las cookies sólo hacen falta si
quieres pedir el feed con tu propia sesión de `www.tiktok.com`. Se pegan como
texto (`msToken=…; ttwid=…`).

**Ajustes → Olvidar dispositivo y cookies** borra el identificador de
dispositivo y las cookies: TikTok te verá como un teléfono nuevo.

### Diagnóstico

**Ajustes → Probar el feed** recorre la conexión y dice, con el error real, si
algo falla (red, DNS, certificados o firma). **Ajustes → Probar el relay**
comprueba el servidor opcional.

### Tema y color

**Ajustes → Fondo** y **Ajustes → Color de botones.** Hay **dos fondos**
(**Oscuro** y **Claro**) y **siete colores** (**Rosa** —el de TikTok—, **Cian**,
**Rojo**, **Azul**, **Verde**, **Morado** y **Ámbar**): **catorce
combinaciones**. El color de los botones se ajusta de brillo para que se lea
sobre el fondo elegido, y el tema se aplica al instante.

---

## Modo relay (opcional)

Sólo hace falta si **no** quieres (o no puedes) instalar las raíces en el
dispositivo, o si prefieres que todo el tráfico de vídeo pase por un servidor.

`relay/servidor.py` es un servidor de **sólo biblioteca estándar de Python 3**
(sin `pip install`), pensado para arrancarse en Windows o Linux. **No firma
nada**: la app le pasa la dirección firmada que ya tiene.

```powershell
# Arrancarlo en tu PC (Python 3.8 funciona)
python relay\servidor.py

# Con otro puerto, token obligatorio y registro detallado
python relay\servidor.py --puerto 8787 --token MiClaveSecreta --verbose
```

Endpoints que expone:

| Ruta | Para qué |
|---|---|
| `/` | Página de estado en HTML (con un probador). |
| `/api/health` | Comprobación rápida (`{"ok": true, …}`). |
| `/api/diag` | Diagnóstico del lado del servidor (acepta `?u=`). |
| `/api/stream?u=URL_FIRMADA` | Resuelve el `302` y devuelve `url` (CDN directo) y `url_proxy`. |
| `/api/video?u=URL_FIRMADA` | Sirve el MP4 (soporta `Range`, imprescindible para AVPlayer). |

Con `--token`, hay que añadir `?t=ELTOKEN` (o la cabecera `X-Tik9-Token`).

En el dispositivo, pon en Ajustes la IP **de tu PC en la red local**
(`ipconfig` en Windows) y el mismo puerto.

> **Ojo:** el relay sólo funciona mientras tu PC esté encendido, y ambos
> dispositivos tienen que estar en la misma red. Por eso **el modo directo es el
> recomendado** y el relay es el plan B.

---

## Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| «Certificado TLS no valido: iOS 9 no confia en la CA moderna» | Falta el paso **B.2**. Instala `certificados/CertificadosModernos.mobileconfig` una sola vez. |
| El feed sale vacío o da error | Pulsa **Reintentar**. Si sigue, **Ajustes → Probar el feed** para ver el error real (red, DNS, certificados o firma). |
| Un vídeo concreto no carga | Toca **Reintentar** en la tarjeta. Algunos vídeos pueden estar retirados o restringidos por región. |
| El vídeo no se reproduce aunque el feed sí | Prueba a activar el **relay** en Ajustes (modo *Solo relay*): es el caso de iOS 9 sin las raíces instaladas. |
| La app no se instala / «no está firmada» | Falta **AppSync Unified** (ver Parte C). |
| La app se ve con barras negras arriba y abajo | Faltan imágenes de arranque; se generan con `tools/generar_recursos.py` (el CI ya lo hace). |
| **Buscar** no existe en la app | Es a propósito: TikTok devuelve vacío a los clientes que no son la app oficial. |
| Los comentarios no se abren | Igual: están bloqueados para clientes no oficiales. El botón lo explica. |
| El modo relay da «No se puede conectar» | PC apagado, IP distinta, o el firewall de Windows bloquea Python. |

---

## Estructura del repositorio

```
.
├── .github/
│   ├── workflows/build-ipa.yml       Compilación y empaquetado en la nube
│   └── notas-release.md              Texto de las Releases
├── app/                              Proyecto Theos (Objective-C, armv7)
│   ├── Makefile                      TARGET iphone:clang:9.3:9.0, ARCHS armv7
│   ├── control                       Metadatos del paquete (nombre del .ipa)
│   ├── main.m                        Punto de entrada
│   ├── AppDelegate.{h,m}             Monta las pestañas (sin storyboards)
│   ├── TTSignaCore.{c,h}             Firma web de TikTok (X-Gnarly) en C puro
│   ├── TTTheme.{h,m}                 Paleta, estilos planos e iconos vectoriales
│   ├── TTVideo.{h,m}                 Modelo de un vídeo (lee el itemStruct)
│   ├── TTSesion.{h,m}                device_id, msToken y cookies
│   ├── TTCliente.{h,m}               Feed firmado + carga de imágenes
│   ├── TTResolvedor.{h,m}            Reproducción directa (relay como plan B)
│   ├── TTPlayer.{h,m}                AVPlayer compartido y su capa
│   ├── TTVideoCell.{h,m}             Tarjeta de vídeo a pantalla completa
│   ├── TTFeedViewController.{h,m}    Feed «Para ti» (paginado, vertical)
│   ├── TTFavoritos.{h,m}             Guardado en el teléfono
│   ├── TTFavoritosViewController.{h,m}  Lista + reproductor de un favorito
│   ├── TTAjustesViewController.{h,m} Ajustes, tema y diagnóstico
│   ├── pruebas/                      Programas de prueba del firmador (C)
│   └── Resources/                    Info.plist, iconos, imágenes de arranque
├── certificados/
│   └── CertificadosModernos.mobileconfig   Perfil listo para las raíces nuevas
├── relay/
│   └── servidor.py                   Relay opcional (Python 3, sin dependencias)
├── prototipo/                        Comprobaciones en vivo (Python) y oráculo
│   ├── xgnarly.py                    Firma X-Gnarly de referencia (Python)
│   ├── comparar_vectores.py          Compara el C contra el oráculo
│   ├── probar_play.py / probar_final.py / probar_cabeceras_cdn.py
│   ├── inspeccionar_play.py          Muestra la dirección firmada del feed
│   └── probar_relay.py               Prueba el relay
└── tools/
    ├── generar_recursos.py           Genera iconos y arranques (PNG a mano)
    ├── generar_certificados.py       Genera el perfil .mobileconfig
    └── verificar_ipa.py              Comprueba arquitectura y versión del .ipa
```

---

## Compilar en tu propio ordenador (opcional)

No es necesario: GitHub Actions ya lo hace. Pero si quieres reproducirlo en
Linux (o en Windows con WSL), Theos necesita:

* Ubuntu 22.04 con `build-essential fakeroot rsync curl perl zip git libtinfo5`
* El *toolchain* `L1ghtmann/llvm-project` → `test-210562a` → `iOSToolchain-x86_64.tar.xz`,
  descomprimido en `$THEOS/toolchain/` (queda `$THEOS/toolchain/linux/iphone/bin/clang`)
* Los parches de `.tbd` que faltan en el SDK 9.3 (`liblaunch.tbd` y
  `libsystem_c.tbd`, con los símbolos de memoria; el workflow los aplica solo)
* El SDK `iPhoneOS9.3.sdk` del repositorio `theos/sdks`

```bash
export THEOS=/opt/theos
cd app
make package FINALPACKAGE=1 PACKAGE_FORMAT=ipa
# → app/packages/com.lofturb.tik9_1.0.0_iphoneos-arm.ipa
```

> La guía completa del proceso (herramientas, los comandos de preparación, los
> parches de `.tbd` del SDK 9.3, los errores típicos y cómo se publica en
> Releases) está en **[`PROCESO.md`](PROCESO.md)**.

---

## Créditos y licencia

* Hecho con [Theos](https://github.com/theos/theos) y el
  [toolchain de L1ghtmann](https://github.com/L1ghtmann/llvm-project).
* La firma web de TikTok está reproducida en C a partir del análisis del
  algoritmo `X-Gnarly`/`X-Bogus`, con un oráculo en Python para comprobarla
  bit a bit.
* Uso educativo y personal. Respeta las condiciones de servicio de TikTok y los
  derechos de autor del contenido que veas.
