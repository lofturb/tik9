# Comprobación técnica: ¿puede la app de iOS 9 resolver vídeos de TikTok por sí sola?

**Fecha:** 18 de octubre de 2026.
**Método:** peticiones reales a TikTok desde el PC del proyecto (Caracas, VE),
más implementaciones de referencia de `f2` (Apache-2.0) y `gaplan/TikTok-X-Gorgon`.
Todo lo que sigue está **medido**, no supuesto.

---

## 1. Resumen en una línea

La app **puede firmar peticiones y obtener los datos del feed y de cada vídeo**
(probado), **y también puede reproducir los vídeos sin JavaScript, sin cookies y
sin relay**: la dirección firmada `aweme/v1/play/` que viene dentro del propio
feed redirige al CDN, que solo exige la cabecera `Referer`. (El análisis
histórico que llevó hasta aquí está en los puntos 2 a 4; el desbloqueo, en el
punto 4 ter.)

---

## 2. Lo que se probó, y qué salió

### 2.1 Vías sin firma — todas cerradas

| Petición | Resultado |
|---|---|
| `oembed?url=…` | **200**, pero solo título/autor/miniatura (**sin MP4**) |
| Página `@usuario/video/ID` | 200, pero **ya no** incluye `playAddr` (solo estrategias de UI) |
| `api/item/detail/` sin firma | 200 con **cuerpo vacío** |
| `api/recommend/item_list/` sin firma | 200 → `{"status_code":0}` |
| `embed/v2/ID` | **503** `overload-protect triggered` (luego 429) |
| `node/share/video` | 403 |
| API móvil `api16…tiktokv.com` sin firma | 200 **vacío** |

### 2.2 Con firma web X-Gnarly (validado en vivo)

Portado de `f2` y ejecutado desde este PC (`prototipo/probar.py`):

| Endpoint | Resultado |
|---|---|
| `api/item/detail/` | **200, 26 KB, `itemInfo.itemStruct` completo** ✔ |
| `api/recommend/item_list/` («Para ti») | **200, 261 KB, 12 vídeos** ✔ |
| `api/search/general/full/` | vacío, cabecera `tt_orcas_res: 1` (marcado) ✘ |
| `api/search/suggest/` (y `suggest_clean`, `suggest_words`, `general/suggest`, `word/suggest`, `suggestion`) | 200, 108 B, `{"status_code":0,"status_msg":"url doesn't match"}` ✘ |
| `api/post/item_list/` (perfil) | vacío ✘ |
| `api/comment/list/` | vacío ✘ |

### 2.3 El formato va a favor (medido)

* MP4 `ftypisom` + **`avc1` (H.264) + `mp4a` (AAC)**. Hay variantes `h265_hvc1`
  que **hay que evitar** (un chip de 32 bits no las decodifica).
* Calidad disponible por web: **h264 540p** (576×1024) y menores.
* El CDN responde **`206 Partial Content`**, `accept-ranges: bytes`
  (buscado con `Range`), y **sin cabeceras obligatorias**.
* Miniaturas: **JPEG**.

### 2.4 El muro: el CDN de reproducción

* Las URLs de `item/detail` y de `recommend` son del host
  **`v16-webapp-prime.tiktok.com`**, con `ply_type=2&policy=2&tk=tt_chain_token`.
* **403 «Access Denied»** en **todas** las combinaciones probadas: sin
  cabeceras, con UA, con `Referer`, con `ttwid`, con `tt_chain_token`, con
  `msToken` falso, quitando `tk`, quitando `ply_type/policy`, cambiando de host,
  y **desde dos pilas TLS distintas** (Python y el cliente del entorno).
* Obtener cookies reales por HTTP puro: `/explore` entrega `ttwid`,
  `tt_csrf_token` y `tt_chain_token`, **pero nunca `msToken`** (lo pone el
  JavaScript). Sin `msToken` válido, el CDN no sirve.

### 2.5 La API móvil (la que da URLs que sí funcionan)

Las direcciones que **sí** descargan son del host **`v19.tiktokcdn-us.com`**
(comprobado con la resolución de un tercero): `206`, `video/mp4`, `avc1`.
Esa es la CDN de la **app móvil**. Pero:

* `/aweme/v1/aweme/detail/` con **X-Gorgon + X-Khronos** (portado y probado,
  `prototipo/movil/`) devuelve **200 vacío**: hoy hacen falta además
  **`X-Argus` y `X-Ladon`** (algoritmos nativos, más complejos).

---

## 3. Consecuencia para la arquitectura

Para **reproducir** vídeos sin un tercero de por medio hay que ejecutar la
misma cadena que resuelve TikTok, y eso exige **uno** de estos dos caminos:

1. **JavaScriptCore en el dispositivo.** Aquí `LEEME.md` **se equivoca**: iOS 9
   **sí** trae motor de JavaScript (`JavaScriptCore`, API pública desde iOS 7).
   La app podría cargar el `webmssdk` de TikTok en un `JSContext` y pedirle la
   firma y el `msToken`. Es el camino que hacen NewPipe (con Rhino) y yt-dlp
   (con Node).
2. **Portar a C toda la firma móvil** (X-Gorgon + X-Argus + X-Ladon + SM3 +
   Simon + protobuf). Es grande y frágil, pero es cálculo puro y se puede.

O bien **aceptar un resolvedor** (relay propio o servicio de terceros) **solo
para la URL del vídeo**, y hacer todo lo demás en la app.

---

## 4. Qué hay ya escrito (todo reutilizable)

```
prototipo/
  xgnarly.py            Firma web X-Gnarly + X-Dynosaur (de f2, Apache-2.0)  ← PORTAR A C
  xbogus.py             Firma X-Bogus de referencia (de f2)
  f2/                   Shim de la dependencia de traduccion
  probar.py             Firma y pide item/detail  ← FUNCIONA
  probar_listas.py      Prueba item_list / search / recommend / comments
  probar_feed.py        Inspecciona el feed "Para ti"
  inspeccion.py         Saca playAddr/downloadAddr y mira el codec
  probar_video.py       Prueba cabeceras sobre el CDN
  probar_sesion.py      Flujo con cookie jar
  probar_cookies.py     Intenta obtener msToken por HTTP puro
  probar_flujo.py       Flujo completo explore -> item/detail -> CDN
  diagnostico.py        Analiza el feed (fotos sin URL) y prueba búsqueda/sugerencias
  probar_busqueda.py    Matriz de intentos para abrir la búsqueda (cookies/X-Bogus/params)
  dump_url.py           Guarda las URLs en urls.json
  urls.json             Ultimas URLs obtenidas (caducan)
  movil/
    xgorgon.py          Firma X-Gorgon + X-Khronos (de gaplan)  ← PORTAR A C
    probar_movil.py     Prueba la API movil con X-Gorgon
```

**Lo que ya está listo para portar a C:** el algoritmo X-Gnarly completo
(~350 líneas útiles: ChaCha variante, FNV-1a, MD5, base64 propio) y X-Gorgon
(~60 líneas). MD5 lo da iOS en `CommonCrypto`; el resto es aritmética.

---

## 4 bis. Validación del camino JavaScriptCore (con navegador real)

Se abrió la página del vídeo en un Chrome real y se inspeccionó la red:

* El navegador pide **el mismo host** `v16-webapp-prime.tiktok.com/video/tos/…`
  y recibe **`200`, `content-type: video/mp4`, `content-length: 1681331`,
  `accept-ranges: bytes`**. → **No es bloqueo de IP: es la sesión.**
* La petición lleva cabecera **`cookie`** (que a nosotros nos falta) y `referer`.
* El `<video>` reproduce (`paused:false`, 24,5 s) con fuente `blob:` (Media Source).
* Cookies que establece la página (legibles):
  * **`msToken` (124 caracteres)** ← la clave, y **no es HttpOnly**
  * `x-web-secsdk-uid` (36), `tiktok_webapp_theme`, `delay_guest_mode_vid`
* El SDK se carga de
  `…/tiktok_web_login_static/webmssdk/1.0.0.417/webmssdk.js` (+ `webmssdk_ex.js`).
  Ambos descargados en `prototipo/js/sdk/` (243 KB y 347 KB).

**Conclusión de la validación:** el camino funciona *en concepto* (iOS 9 tiene
JavaScriptCore y el CDN acepta la sesión), pero el SDK es una **VM de bytecode
ofuscada anti-bot** pensada para detectar entornos que no son un navegador.
Hacerla funcionar en cabeza es un proyecto de investigación, no una tarde.

---

## 4 ter. El desbloqueo: **la reproducción directa sí funciona** (medido)

El muro del punto 2.4 (`v16-webapp-prime.tiktok.com` → 403) tenía una vuelta
por detrás que se encontró **dentro del propio feed**:

* Cada elemento del feed (`itemStruct`) trae, además de las direcciones de la
  API web, una dirección **`https://www.tiktok.com/aweme/v1/play/?…` ya
  firmada** (está en `video.bitrateInfo[i].PlayAddr.UrlList[2]` y en
  `video.PlayAddrStruct.UrlList[2]`).
* Esa dirección **redirige (302)** a un MP4 reproducible en el CDN
  `v16/v19-web-newkey.tiktokcdn.com`, que **sí descarga**.
* Lo único que exige ese CDN es la cabecera **`Referer: https://www.tiktok.com/`**:
  * sin `Referer` → **403**;
  * con `Referer` → **200** `video/mp4` (`ftypisom`), y **206** con `Range`;
  * el **`User-Agent` da igual**.

Comprobado en vivo (`prototipo/probar_play.py`, `probar_final.py`,
`probar_cabeceras_cdn.py`, `inspeccionar_play.py`). Y el relay también quedó
probado sirviendo el vídeo con `Range` → `206`
(`prototipo/probar_relay.py`).

**Consecuencia:** no hacen falta ni `msToken` de JavaScript, ni cookies, ni un
servidor. **La app reproduce sola**; el relay pasa a ser un **plan B opcional**
(para cuando iOS 9 no confía en el certificado del CDN, o la red corta la
conexión). En la app, el resolvedor (`TTResolvedor.m`) sigue el 302 y le entrega
al reproductor la **dirección final del CDN** con sus cabeceras, para que
`AVPlayer` no las pierda al saltar de host.

---

## 4 quater. Dos medidas que cambiaron la app

**a) El retardo al cambiar de vídeo estaba en el salto 302.** Medido en vivo
(`prototipo/diagnostico.py`), por vídeo:

| Paso | Tiempo |
|---|---|
| Resolver: `Range: bytes=0-0` a la dirección firmada y seguir el 302 | **~1,0–1,2 s** |
| Pedir el mismo vídeo ya en el CDN (`v19-web-newkey`) | **~0,26–0,31 s** |

Lo caro es el salto por `www.tiktok.com`. La app **ya no lo espera al deslizar**:
al empezar un vídeo resuelve por adelantado los dos siguientes
(`TTResolvedor prepararVideo:`) y guarda las direcciones **10 minutos** en una
caché. Así, llegar a un vídeo precargado cuesta solo el ~0,3 s del CDN, y volver
a uno ya visto es inmediato.

**b) Los vídeos «sin dirección de reproducción» eran publicaciones de fotos.**
De los 12 elementos del feed analizado, **2 no traían ninguna URL de vídeo**, y en
los dos el motivo era el mismo: **`imagePost`** (el «modo foto»), con `images` y
**sin nodo `video`**. No son vídeos, así que ahora se **saltan** al leer el feed
(`TTCliente feedParaTiCursor:`) en vez de aparecer como tarjeta que no reproduce.

**c) La búsqueda no se puede abrir, y no es cosa de la firma.** Probado a fondo
(`prototipo/probar_busqueda.py`), con la palabra `gatos`:

| Combinación | Resultado |
|---|---|
| control (`X-Bogus=1`, sin cookies) | `200`, **0 B**, `tt_orcas_res: 1` |
| + cookies reales de `/explore` (`ttwid`, `tt_chain_token`) | `200`, **0 B**, `tt_orcas_res: 1` |
| + **X-Bogus calculado de verdad** (sobre los parámetros) | `200`, **0 B**, `tt_orcas_res: 1` |
| + X-Bogus real + cookies | `200`, **0 B**, `tt_orcas_res: 1` |
| + X-Bogus real (sobre `biz`+`X-Dynosaur`+`msToken`) + cookies | `200`, **0 B**, `tt_orcas_res: 1` |
| + **juego completo** de parámetros del navegador (`webid`, `engine_name`, pantalla, `browser_version`, `search_source`…) + X-Bogus real + cookies | `200`, **0 B**, `tt_orcas_res: 1` |

Lo mismo en `/api/search/item/full/`. Las **seis** variantes de ruta de
sugerencias contestan todas `{"status_code":0,"status_msg":"url doesn't match"}`, y
la página `/search?q=…` es un armazón de JavaScript sin ningún dato de vídeos
incrustado. La API **móvil** tampoco: `/aweme/v1/…` con X-Gorgon devuelve vacío
porque hacen falta además `X-Argus` y `X-Ladon` (ver 2.5).

**Conclusión:** (corregida el 2026-10-19; ver **4 quinquies**) se descartaron las
cookies, el X-Bogus y los parámetros, pero el experimento **no podía acertar**: los
parámetros del «juego completo» eran **inventados** (medidos en otra captura) y todas
las pruebas salían por **HTTP/1.1** de Python, que es justo lo que la ruta rechaza.

---

## 4 quinquies. **La búsqueda sí responde** (medido el 2026-10-19)

La conclusión de 4 quater (c) era falsa. Se volvió a medir **capturando la petición
real del navegador** (`prototipo/busqueda_navegador.json`: UA, cookies, los 38
parámetros de negocio tal cual, y los cuatro valores firmados) y repitiéndola con
nuestra propia firma. Lo que separaba a la app de los resultados **no era la firma**:

| Prueba | Resultado |
|---|---|
| Reenviar **la firma exacta del navegador** desde Python | `200`, **0 B**, `tt_orcas_res: 1` |
| Nuestra firma sobre los **mismos 38 parámetros** | `200`, **0 B**, `tt_orcas_res: 1` |
| … con `ub_code`/`SCM_VERSION`/`WebGL`/canvas/`DEVICE_HASH` **actualizados** a los del navegador | `200`, **0 B**, `tt_orcas_res: 1` |
| … con la **huella TLS y HTTP/2 de Chrome** (`curl_cffi impersonate`) | `200`, **273–320 KB**, `status_code: 0`, 12–13 vídeos |
| … con **HTTP/2 genérico** (curl normal, sin imitar a nadie) | `200`, **320 KB**, 13 vídeos |
| … con HTTP/2 de Chrome pero **forzando HTTP/1.1** | `200`, **0 B**, `tt_orcas_res: 1` |
| … con **HTTP/1.1** y todas las cabeceras de Chrome, en su orden | `200`, **0 B**, `tt_orcas_res: 1` |

De ahí salen **las tres condiciones reales** (y las tres las cumple la app sola):

1. **HTTP/2 obligatorio.** Es lo único que cambia entre la fila que funciona (320 KB)
   y las dos que devuelven vacío con las mismas cabeceras y la misma firma.
   `NSURLSession` ya negocia HTTP/2 (desde iOS 9), así que en el teléfono viene dado.
2. **Cookie `ttwid` (identidad anónima).** Se consigue **sin cuenta** cargando una
   página pública (`/foryou`, `/explore`, `/search?q=…`; la portada no la da).
   Sin ella la respuesta deja de ser vacía y pasa a ser
   `{"status_code":2483,"status_msg":"Por favor, inicia sesión primero"}` (127 B):
   otra vez idéntico a lo que ve el navegador anónimo… porque el navegador **la tiene**.
3. **`msToken` válido dentro de la firma.** Sin él, `200` + **0 B** + `tt_orcas_res: 1`;
   con él (el de la propia sesión, o el que TikTok **regala en la cabecera
   `x-ms-token`** de una respuesta rechazada), 300 KB de resultados. No hace falta
   ejecutar el SDK: el token lo da el servidor y se firma con él.

Comprobaciones que cierran el caso:

* **La firma ya era correcta.** Al abrir con `unseal()` el `X-Dynosaur`/`X-Gnarly`
  capturados del navegador y compararlos campo a campo
  (`prototipo/comparar_con_navegador.py`): `hash_state` de la consulta y del UA
  **coinciden exactamente**; las únicas diferencias son valores de entorno
  (`ub_code` 8→14, `SCM_VERSION` 2.0.0.561→1.0.0.417, WebGL/canvas/`DEVICE_HASH`
  reales, `PAGE` `/search`), y **ninguno de ellos decide nada**: con los valores
  viejos también devuelve resultados.
* **La huella TLS no importa.** Basta HTTP/2 *genérico*: no hace falta imitar a
  ningún navegador, así que el TLS de Apple sirve.
* **Los parámetros tampoco.** Funciona igual el juego de 38 del navegador, uno de
  26, y el de 21 que ya mandaba la app (`prototipo/params_app.py`).

**Lo que hace ahora la app** (`TTSesion`, `TTCliente`):

* `prepararIdentidad:` carga **una vez** `https://www.tiktok.com/foryou` y deja que
  el sistema guarde `ttwid`/`tt_chain_token`; `cookieDeSesion` manda además cualquier
  cookie pegada a mano en Ajustes (que sigue siendo posible, ya sin ser necesaria).
* `buscarPalabra:` firma con el `msToken` que haya y, si la respuesta viene vacía o
  con `2483`, guarda el `x-ms-token` que venga en la respuesta —o vuelve a pedir la
  identidad— y **repite la búsqueda una vez**. En el primer arranque, sin nada, eso
  es: pedir identidad → primera búsqueda vacía que regala el token → segunda búsqueda
  con resultados.
* El mismo camino se comprobó con el **UA literal de la app** y sus parámetros
  (`prototipo/confianza_app.py`): 273 KB y 12 vídeos.

Reproducir: `pip install "curl_cffi<0.8"` y luego
`python prototipo/receta_final.py` (receta completa) y
`python prototipo/confianza_app.py` (lo que hará la app).

---

## 4 sexies. **El teléfono hablaba HTTP/1.1** (medido el 2026-10-19)

En el teléfono la búsqueda seguía fallando (`200`, 0 B, `tt_orcas_res: 1`) aunque
el feed cargaba sin problema. Eso apuntaba a una sola cosa, y se comprobó en
Python:

| Prueba | Resultado |
|---|---|
| `/api/recommend/item_list/` (el feed) por **HTTP/1.1** | `200`, **313–325 KB** de datos |
| `/api/recommend/item_list/` por HTTP/2 | `200`, 344 KB |
| `/api/search/general/full/` por **HTTP/2** | `200`, 300 KB, 13 vídeos |
| `/api/search/general/full/` por **HTTP/1.1** | `200`, **0 B**, `tt_orcas_res: 1` |
| `/api/search/item/full/`, `/api/search/video/full/`, en `m.tiktok.com`… por HTTP/1.1 | todas `0 B` (o `url doesn't match`) |

O sea: **el feed funciona igual por h1, y la búsqueda no**. Un móvil que hable
HTTP/1.1 carga el feed perfectamente y la búsqueda le devuelve vacío, que es
exactamente lo que se veía. La afirmación de **4 quinquies** («`NSURLSession` ya
negocia HTTP/2… viene dado») era el error: en este teléfono no lo estaba haciendo.

Comprobaciones que descartan las otras explicaciones:

* **No es el `msToken` caducado.** `prototipo/reintento_app.py` reproduce el
  reintento exacto de la app (token viejo → TikTok regala otro en `x-ms-token` →
  repetir): por **HTTP/2** da **254 940 B** de resultados. Por h1, con cualquier
  token, `0 B`.
* **No es un eco del token.** `prototipo/eco_token.py`: TikTok nunca devuelve el
  mismo token que recibe; siempre regala uno nuevo (de 120, 124, 128 o 132
  caracteres, según el caso), y ese token sirve incluso desde otra sesión.
* **No hace falta la cookie `msToken`**, solo la firma (`eco_token.py`, caso B).
* **No es la firma de la búsqueda.** `prototipo/firma_mala.py`: una firma rota da
  **0 B** en la búsqueda (igual que h1, no distingue) pero **18 B**
  (`{"status_code": 0}`) en el feed; como el feed de la app trae 93 KB, su firma
  está bien. Además el mismo juego de 20 parámetros en el feed devuelve 316 KB.
* **Faltaba un dato del informe del teléfono** (el del intento 2), así que el
  diagnóstico ahora lo enseña todo: la búsqueda primero, el `connection` de la
  respuesta (`close` = HTTP/1.1; en HTTP/2 esa cabecera no existe), el feed con
  los 20 parámetros de la búsqueda encima, el protocolo/TLS negociados
  (`https://www.cloudflare.com/cdn-cgi/trace`) y una sonda al relay.

**La palanca: App Transport Security.** El `Info.plist` tenía
`NSAllowsArbitraryLoads = true` (para poder hablar HTTP plano con el relay y con
CDNs de TLS flojo). Apple documenta que, con ese permiso, «las comprobaciones
extendidas —como exigir una versión mínima de TLS— quedan desactivadas», y
**HTTP/2 exige TLS 1.2**. La excepción por dominio es la que evita elegir entre
una cosa y la otra (documentado en el mismo sitio: «los dominios que
especifiques en ese diccionario no se ven afectados por el valor de esa clave»,
aunque el diccionario esté vacío). Así que el `Info.plist` ahora **exige ATS en
`www.tiktok.com`** (TLS 1.2 + secreto hacia adelante) y deja el permiso global
para el resto. Si aun así no llegara HTTP/2, el informe dirá qué protocolo y qué
TLS se negociaron, y quedan dos planes: quitar el permiso global (rompe el relay
por HTTP plano) o pedir la búsqueda desde un `WKWebView` (WebKit sí negocia
HTTP/2 y no le afecta ATS en iOS 9).

---

## 5. Estado de la decisión

* **Navegar (feed, miniaturas, ficha de vídeo en el feed):** resuelto y
  autónomo, con **X-Gnarly portado a C** (`app/TTSignaCore.c`). Sin PC, sin
  relay.
* **Reproducir:** resuelto y autónomo. La dirección **firmada** que viene en el
  feed redirige al CDN, que solo pide el `Referer`. **Sin cookies, sin relay,
  sin JavaScript.**
* **Relay:** **opcional**, solo como plan B (certificado del CDN no confiado en
  iOS 9, o red que corta la conexión). No firma nada: la app le pasa la
  dirección ya firmada.
* **Buscar:** resuelto en Python y en la app, con un matiz importante: la ruta
  exige **HTTP/2**, la cookie `ttwid` (identidad anónima, de una página pública)
  y un `msToken` válido. La app consigue las tres sola, pero iOS 9 no le daba
  HTTP/2 con el `Info.plist` que tenía; ahora se exige ATS en `www.tiktok.com`
  para que lo negocie. Ver **4 quinquies** y **4 sexies**.
* **Comentarios y perfiles:** pendientes. Se sabe que la API móvil exige
  `X-Argus`/`X-Ladon` (ver 2.5); no se han vuelto a medir sobre HTTP/2. Los
  comentarios se quedan fuera por ahora; el botón lo explica.
