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
CDNs de TLS flojo), y con ese permiso iOS desactiva las comprobaciones extendidas
de TLS. Así que se pasó a **exigir ATS en `www.tiktok.com`** (TLS 1.2 + secreto
hacia adelante) dejando el permiso global para el resto. **No sirvió**: la
búsqueda siguió saliendo con `connection: keep-alive` (o sea, HTTP/1.1).

**El informe del 18/10/2026 (build con sonda de certificados).** Ya no hay que
adivinar: el teléfono contesta con estos hechos.

```
sistema: Version 9.3.6 (Build 13G37)
proxy del sistema: ninguno
eco de protocolo: http=http/1.1 tls=TLSv1.3 kex=X25519
certificado de www.tiktok.com:
  3 certificados en la cadena
    [0] *.www.tiktok.com
    [1] RapidSSL TLS ECC CA G1
    [2] DigiCert Global Root G3
    huella de la hoja: 02662ed741155db2
pagina con certificado falso: rechazado por certificado no confiable -- bien
busqueda(20): 1) HTTP 200, 0 B orcas=1 conn=keep-alive regala=120 car.  -> ... 2) igual
feed(16): 1) HTTP 200, 134215 B conn=keep-alive regala=120 car. videos=6
feed+busqueda(20): 1) HTTP 200, 131300 B ... videos=6
```

**Qué descarta (y por qué).**

* **No hay intermediario en la conexión con TikTok.** La cadena de certificados
  es la auténtica —la firma RapidSSL/DigiCert, y la huella de la hoja
  `02662ed741155db2` es **idéntica** a la que se ve desde el PC—, no hay proxy
  configurado y `self-signed.badssl.com` se **rechaza** como debe. Nadie está
  cortando el TLS.
* **Por lo tanto, el HTTP/1.1 lo elige el teléfono, no un tercero.** ALPN viaja
  *dentro* del TLS: si la sesión con `www.tiktok.com` es de extremo a extremo y
  auténtica (lo es), el h1/h2 lo pactan el teléfono y TikTok a solas; nadie en
  medio puede cambiarlo. **El que no ofrece h2 es CFNetwork.**
* **La firma queda descartada del todo**: el feed *con los 20 parámetros de la
  búsqueda encima* trae 131 KB y 6 vídeos. Y el reintento de `msToken` se ve
  funcionar en el informe (`1) ... regala 120 car. -> 2) igual`).

**El dato raro, y por qué no cambia nada.** La traza de Cloudflare dice
`tls=TLSv1.3 kex=X25519`, que es lo que negocia un cliente moderno… exactamente
lo mismo que contesta a un cliente de Python **por defecto** (medido desde el PC:
una pila con TLS 1.3 y sin ALPN `h2` produce `http=http/1.1 tls=TLSv1.3
kex=X25519`). Es decir: la traza *retrata* al que no pide h2. Cómo llega ahí un
iOS 9 (que no sabe TLS 1.3) queda abierto, y por eso el diagnóstico ahora pide la
traza **sin caché y con un número al azar en la dirección** (una copia guardada
en el teléfono o en un caché del camino daría un dato viejo): lo importante es
que el `conn=keep-alive` de las respuestas de TikTok ya demuestra el h1, sin
depender de esa traza.

**La palanca siguiente.** Con los CDNs medidos y todos cumpliendo ATS de sobra
(`v16m.tiktokcdn.com`, `v16-webapp.tiktok.com`, `sf16-ies-music-sg.tiktokcdn.com`:
TLS 1.2 + ECDHE-ECDSA), ya no hay que elegir entre HTTPS y vídeo: el
`Info.plist` pasa a **`NSAllowsArbitraryLoads = false`** (ATS de verdad en toda la
app) dejando relajados solo los CDNs de TikTok. Es el cambio que queda por probar
de verdad, porque la excepción por dominio **no** bastaba mientras el permiso
global siguiera puesto.

**La causa (18/10/2026, medida): un parche de TLS del propio aparato.**
Como desde dentro del sistema no se puede ver qué ALPN se ofrece, se puso un
**espía de saludos TLS** en el PC (`tools/espiar_clienthello.py`, escucha en un
puerto y cuenta lo que trae el ClientHello; el certificado no hace falta, porque
el saludo llega antes de que nadie lo mire):

```powershell
python tools\espiar_clienthello.py --puerto 8443     # y en el aparato: https://<ip-del-PC>:8443/
```

Y al abrir esa dirección desde el **Safari del iPad** (iOS 9.3.6, iPad mini 1)
llegaron **dos saludos distintos** desde la misma IP:

```
visita desde 192.168.1.2
  ALPN ofrecido : h2, h2-16, h2-15, h2-14, spdy/3.1, spdy/3, http/1.1
  versiones TLS : TLS1.2      grupos: secp256r1, secp384r1, secp521r1
  --> OFRECE HTTP/2          <-- la pila del sistema: SI sabe HTTP/2

visita desde 192.168.1.2
  ALPN ofrecido : (ninguno)
  versiones TLS : TLS1.3, TLS1.2, TLS1.1, TLS1.0
  grupos        : x25519, secp256r1, x448, secp521r1, secp384r1
  cifrados      : 31 (TLS_AES_256_GCM_SHA384, ChaCha20, ...)
  --> NO ofrece HTTP/2       <-- pila moderna (OpenSSL), SIN ALPN
```

De ahí sale todo lo demás:

* **iOS 9 sí ofrece h2** (`h2`, borradores `h2-16/15/14` y SPDY: la pila de 2015).
  El "el sistema no negocia h2" nunca fue verdad.
* **El que no puede hablar h2 es el otro**: sin ALPN, el protocolo no se puede
  pactar, y el servidor tiene que contestar HTTP/1.1. Ese saludo es exactamente
  lo que describía la traza de Cloudflare (`tls=TLSv1.3 kex=X25519 http=http/1.1`,
  que es lo mismo que contesta a cualquier cliente sin ALPN: medido desde el PC
  con el Python por defecto).
* **Es un parche de TLS instalado en el aparato, no un proxy.** En Cydia están
  `tlsfix` y `safarifix` (los instaló el dueño). Un parche así le da TLS moderno
  a un iOS viejo —de ahí el `TLSv1.3` imposible— pero **no implementa ALPN**, así
  que todo el HTTPS del iPad baja a HTTP/1.1. Encaja con lo demás: la cadena de
  certificados de TikTok es la auténtica y `self-signed.badssl.com` se rechaza
  (no hay nadie firmando certificados: es la propia pila del cliente, sustituida),
  y el arranque con volumen-arriba (que desactiva tweaks de Substrate) **no** lo
  quita, porque es un paquete que parchea el sistema, no un tweak.
* **Firma para reconocerlo sin espía**: en iOS 9, un `tls=TLSv1.3` en la traza es
  imposible; si aparece, hay un parche de TLS poniéndose en medio (y el
  `conn=keep-alive` de las respuestas de TikTok es la consecuencia).

Arreglo: **desinstalar `tlsfix`** (y `safarifix` si va con él) y reiniciar. Sin
él, el iPad negocia TLS 1.2 + h2 por su cuenta y la búsqueda tiene la ruta que
necesita. La app no pierde nada: los CDNs de vídeo y la API cumplen ATS de sobra
(medido arriba), así que no necesita el parche.

**Confirmado el mismo día:** tras desinstalar `tlsfix` y reiniciar, la traza de
Cloudflare abierta en el Safari del iPad pasa de
`http=http/1.1 tls=TLSv1.3` a **`http=http/2 tls=TLSv1.2`** — es decir, el
dispositivo negocia HTTP/2 con su propia pila en cuanto el parche deja de
ponerse en medio.

**Plan B si aun así no hubiera h2.** Dos salidas sin depender de CFNetwork: pedir
la búsqueda desde un `WKWebView` (WebKit trae su propia pila), o el **relay** (que
sí hace h2 desde Python y devuelve el resultado al teléfono por HTTP/1.1). Ojo:
con ATS estricto el relay por **HTTP plano deja de valer en iOS 9**
(`NSAllowsLocalNetworking` solo existe de iOS 10 en adelante), así que en ese
camino el relay tendría que ir por HTTPS con un certificado de confianza — lo que
ya monta `tools/generar_certificados.py` — o quedarse como está en dispositivos
nuevos.

---

## 4 septies. **La búsqueda sigue vetada con h2: la barrera mira la huella de la conexión** (medido el 2026-10-19)

Con `tlsfix` desinstalado el iPad ya negocia **h2 + TLS 1.2** (confirmado en el
eco de protocolo del propio aparato), y la búsqueda **seguía vacía**. El informe
de la batería de la versión 1.1.0 (seis variantes, con reintento y pausa cada
una) lo deja medido:

| Variante en el iPad | Resultado |
|---|---|
| A · la de la app, tal cual | 3 intentos: `200`, 0 B, `orcas=1` |
| B · sin `Referer` ni `Origin` | 2 intentos: `200`, 0 B, `orcas=1` |
| C · User-Agent de Safari | 2 intentos: `200`, 0 B, `orcas=1` |
| D · UA de Safari y declarándose iPad | 2 intentos: `200`, 0 B, `orcas=1` |
| E · ruta vieja `/api/search/item/full/` | 2 intentos: `200`, 0 B, `orcas=1` |
| F · `/api/search/user/full/` | 2 intentos: `200`, 0 B, sin datos |
| feed (testigo) | `200`, 126 106 B, **6 vídeos** |

Y en el mismo informe: cadena de certificados auténtica, **sin proxy**, `ttwid` y
`msToken` del tamaño que toca. O sea: **no queda nada de la petición que
cambiar** —ni UA, ni cabeceras, ni parámetros, ni ruta, ni reintentos— y el
aparato habla h2. La misma dirección, firmada igual, pasa desde un cliente de
pila moderna con la misma IP pública.

Conclusión: `tt_orcas_res: 1` no es "esta petición no me gusta", es **"esta
conexión no la tengo por buena"**. Akamai (la barrera que pone TikTok delante de
la API) clasifica por **huella TLS + HTTP/2**, y la de iOS 9 (2015) no está en su
lista de clientes conocidos. Además la barrera es **por ruta**: medido desde el
PC, `/api/challenge/detail` responde sin `orcas` y `/api/challenge/item_list` no;
las páginas `/search` y `/tag` traen 386 KB de HTML pero **sin los vídeos dentro**
(los carga el JavaScript desde la API vetada), así que por HTML no hay puerta.

**El arreglo, sin relay:** que la app hable con TikTok con una pila propia, con
las piezas de un navegador de verdad. Eso es el **túnel** (`app/TTTunel.c`):

* **BoringSSL**, la biblioteca TLS de Chrome, con su lista de cifrados, sus
  curvas, GREASE y las extensiones permutadas: el saludo TLS de un Chrome real.
  Con OpenSSL pelado no entra (es lo que les pasa a los proyectos que no
  "impersonan" un navegador).
* **nghttp2**, para armar HTTP/2 con los ajustes de Chrome (tabla de cabeceras de
  64 kB, ventana inicial de 6 MB, ventana de conexión de 15,7 MB) en vez de con
  los de Apple.
* Solo se usa para las rutas vetadas. El feed, el detalle y las páginas siguen
  por `NSURLSession`, que funciona y trae caché, ATS y certificados del sistema.

Las dos bibliotecas se compilan para armv7/iOS 9 en la construcción
(`tools/compilar_tunel.sh`, con caché) y se enlazan dentro de la app: no hay
nada fuera del aparato ni ningún proceso aparte. La versión 1.2.0 estrena el
caso **G** de la batería, que pide la búsqueda por el túnel y dice en el informe
si entra.

---

## 4 octies. **Compilar una biblioteca de 2025 contra un sistema de 2015** (lo que costó)

El túnel funciona (la app compila, enlaza y se empaqueta), pero meter BoringSSL
(agosto de 2025) y nghttp2 en armv7/iOS 9 costó siete vueltas de construcción.
Queda anotado, porque cada tropiezo es una cosa que **no** hay que volver a
descubrir:

1. **El compilador no prueba nada.** El SDK de armv7/iOS 9 no puede ejecutar sus
   propias pruebas de CMake; se le dice que no las haga
   (`CMAKE_C_COMPILER_WORKS`, `CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY`) y se
   usan `llvm-ar`/`llvm-ranlib`.
2. **La fecha de BoringSSL importa.** El `bssl::Span` de tamaño fijo llegó en
   octubre de 2025 y el LLVM 11 de este toolchain no lo compila: se fija un
   commit **anterior a septiembre de 2025**, que ya tiene GREASE, extensiones
   permutadas y TLS 1.3.
3. **`std::optional::value()` está marcado «solo desde iOS 11»** en el libc++
   de Apple. Esa marca dice contra qué sistema se puede enlazar, no qué código se
   puede escribir: se compila con `_LIBCPP_DISABLE_AVAILABILITY` y, para no
   generar llamadas a piezas que iOS 9 no trae, sin excepciones, sin liberación
   con tamaño y sin reserva alineada.
4. **`__throw_bad_optional_access` no existe en el libc++ de iOS 9** (llegó con
   la marca anterior). Se pone el nuestro en `app/TTTunelCompat.cc`: en ese
   camino de BoringSSL no se entra nunca, y es un seguro que aborta si algún día
   se llamara.
5. **Las tablas de C++ viven en `libc++abi`**, y el `libc++.tbd` que trae este
   SDK no las reexporta (el de Apple de verdad sí). Se pide `-lc++abi` a mano.
6. **`SecTrustCopyAnchorCertificates` no existe en iOS.** Lo dice su propia
   cabecera: «certificate data for system-trusted roots is currently unavailable
   on that platform». O sea que a BoringSSL **no se le pueden dar las raíces del
   aparato**: el saludo TLS se termina sin comprobar y después el sistema valida
   la cadena con `SecTrustEvaluate` (ver `tt_verificar_certificado`).
7. **Un fichero con marca de orden de bytes (BOM) tumba el paquete.** `app/control`
   empezaba por BOM y el generador del `.deb` no veía `Package:` en la primera
   línea; el flujo ahora lo detecta y lo dice.

---

## 4 nonies. **La huella exacta que TikTok tiene por buena** (medido el 2026-10-19)

El caso **G** de la 1.2.0 contestó la pregunta que faltaba: el túnel ya hablaba
como un navegador por debajo (TLS 1.3 con ChaCha20, ALPN `h2`, HTTP/2 y el
certificado validado por el sistema, sin `SIN VERIFICAR`), y aun así TikTok
devolvía `HTTP 200`, `0 B` y `tt_orcas_res: 1`. O sea: **no basta con "TLS
moderno"; la barrera compara la huella entera de la conexión**.

Para dejar de adivinar se buscó un oráculo que devuelve lo que ve el servidor.
`https://tls.peet.ws/api/all` publica, para cada conexión, el JA3, el **JA4** y
la huella de **HTTP/2 de Akamai** (ajustes, ventana, prioridades y orden de las
pseudo-cabeceras). Desde este ordenador —cuya conexión sí pasa— se pidió la
receta con `curl_cffi` impersonando a Chrome, y salió esto:

| Qué | Valor medido |
| --- | --- |
| JA4 | `t13d1516h2_8daaf6152771_02713d6af862` |
| Cifrados (15, ordenados) | `002f,0035,009c,009d,1301,1302,1303,c013,c014,c02b,c02c,c02f,c030,cca8,cca9` |
| Extensiones (16, sin GREASE) | `0000,0005,000a,000b,000d,0010,0012,0017,001b,0023,002b,002d,0033,4469,fe0d,ff01` |
| Algoritmos de firma (8, en orden) | `0403,0804,0401,0503,0805,0501,0806,0601` |
| Grupos | `25497 (X25519Kyber768Draft00), 29 (X25519), 23 (P-256), 24 (P-384)` |
| HTTP/2 (Akamai) | `1:65536;2:0;4:6291456;6:262144\|15663105\|0\|m,a,s,p` |
| Hash de esa huella | `52d84b11737d980aef856699f885ca86` |

Tres cosas que enseña la tabla y que no eran obvias:

1. **JA4, no JA3.** Chrome permuta las extensiones y manda valores GREASE, así
   que el JA3 cambia en cada conexión; el JA4 ordena y quita el ruido, y por eso
   es el que se puede exigir. La parte que más se olvida es la última: **los
   algoritmos de firma, en su orden**, que van dentro del hash.
2. **El grupo post-cuántico va primero.** El 25497 (`X25519Kyber768Draft00`)
   abre la lista de curvas. Un saludo sin él ya no es el de un Chrome de 2024.
3. **HTTP/2 tiene una huella sorprendentemente corta:** cuatro ajustes
   (`HEADER_TABLE_SIZE 65536`, `ENABLE_PUSH 0`, `INITIAL_WINDOW_SIZE 6291456`,
   `MAX_HEADER_LIST_SIZE 262144`), una ventana de conexión de `15663105`, **sin
   tramas de prioridad**, y las pseudo-cabeceras en el orden `:method,
   :authority, :scheme, :path`. El túnel ya mandaba exactamente eso desde la
   1.2.0.

Con eso, la 1.3.0 hace dos cosas: afina el saludo hasta ese detalle (firma,
curvas, ECH de relleno, sellos de tiempo, compresión de certificado con zlib y
las cabeceras completas de un Edge 122 coherente con su User-Agent) y, sobre
todo, **mide**: la prueba **I** pide `tls.peet.ws` *a través del túnel* y escribe
en el informe el JA4, la huella de Akamai y la receta en crudo, comparadas con
las de arriba. Así, si algo no cuadra, se ve qué pieza es en vez de suponerlo.

La prueba **H** cubre la otra hipótesis, la que no tiene que ver con el TLS: que
TikTok **ate la identidad (`ttwid`) a la conexión que la emitió**. Si es así, no
basta con presentar el saludo de Chrome: hay que pedirle la identidad al borde
por esa misma conexión y buscar después con ella. La H lo hace y lo cuenta.

### 4 decies. Lo que midió la 1.3.0 en el aparato (2026-10-19)

El informe de la 1.3.0 trajo por fin la comparación pieza a pieza, y fue útil
porque dejó el problema reducido a dos extensiones:

* **Cifrados**: `8daaf6152771`, iguales ✓
* **Algoritmos de firma**: `0403,0804,0401,0503,0805,0501,0806,0601`, iguales
  y en el mismo orden ✓
* **HTTP/2 de Akamai**: `52d84b11737d980aef856699f885ca86`, **idéntico** ✓
* **JA4**: `t13d1514h2_…` frente al `t13d1516h2_…` de Chrome ✗ — el número del
  medio es la cuenta de extensiones: **14 frente a 16**. La receta en crudo
  enseñó cuáles faltaban: `0005` (status_request, pedir el OCSP) y `4469`
  (17513, ALPS, los ajustes de HTTP/2 dentro del saludo).

Y la prueba **H** descartó la identidad: con un `ttwid` nuevo pedido **por el
túnel** y usado en la búsqueda, la respuesta siguió siendo `HTTP 200`, `0 B`,
`orcas=1`. La identidad no está atada a la conexión que la emite; lo que pesa es
la conexión en sí.

La 1.3.1 pone esas dos extensiones con la API de BoringSSL —`SSL_enable_ocsp_stapling`
y `SSL_add_application_settings("h2", <ajustes de SETTINGS>)`— y añade al
informe el `peetprint_hash`, otra huella independiente (la de peet.ws, que sí
incluye grupos y compresión de certificado) para no depender de una sola
medida. Si con 16 extensiones el JA4 sale `t13d1516h2_8daaf6152771_02713d6af862`,
la huella queda clavada y la prueba G responde si eso era la barrera.

### 4 undecies. La huella quedó clavada y el borde dijo 403 (2026-10-19)

La 1.3.1 consiguió exactamente lo que buscaba: `ja4=t13d1516h2_8daaf6152771_02713d6af862`,
idéntico al Chrome de referencia, con la receta completa
(`0005…4469…ff01`), el Akamai igual (`52d84b11…`) y TLS 1.3 ChaCha20 con el
certificado verificado. Y aun así **no entró**: el síntoma cambió de `200` con
`0 B` y `orcas=1` a **`403` con 411 B en todas las rutas de TikTok**, incluida
`/api/challenge/detail/` (que en la 1.3.0 contestaba 200 y hasta servía la
portada, 88 KB). Las rutas de otros dominios (tls.peet.ws) siguen contestando
200: el túnel no está roto.

Eso descarta que las dos extensiones fueran la pieza que faltaba y convierte el
problema en otro: **el borde tiene una regla que prefiere catorce extensiones a
dieciséis**, o que detecta algo del saludo completo que un Chrome real no
presenta así. El `peetprint` difiere (`0c67a524…` frente a `b8ce945a…`), y una
de las diferencias conocidas es la compresión de certificado: Chrome ofrece
brotli y zlib (`1|2`), el túnel solo zlib (`1`), porque iOS 9 no trae brotli.

La 1.3.2 no adivina: deja elegir por conexión qué extensiones se mandan
(`tt_tunel_estilo`) y hace cinco sondas baratas contra
`/api/challenge/detail/` —saludo completo, sin ALPS, sin ALPS ni OCSP, sin OCSP,
y sin la cookie— más dos sobre páginas (la portada y la página de resultados).
Cada sonda escribe el código, el cuerpo recortado y las cabeceras de la
respuesta. Con eso se sabe qué extensión dispara el 403 y quién lo firma, y se
puede volver al saludo de la 1.3.0 —el que sí hablaba con TikTok— sin perder lo
medido.

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
* **Buscar:** la petición está resuelta (firma, parámetros, `ttwid`, `msToken`,
  reintento con el token que TikTok regala). Lo que falta es la conexión: la
  barrera decide por la huella (ver **4 septies** y **4 nonies**) y rechaza la
  de iOS 9. El arreglo es el **túnel**: BoringSSL + nghttp2 dentro de la app,
  con el saludo TLS y el HTTP/2 de un Chrome. La 1.3.0 lo afina hasta la huella
  medida y añade tres pruebas (G, H, I) para saber qué pieza falta si aún no
  entra; la 1.3.1 clava el JA4 de Chrome y la 1.3.2 mide qué extensión hace
  saltar el 403 del borde (ver **4 decies** y **4 undecies**). Sin relay ni nada
  fuera del aparato.
* **Comentarios y perfiles:** pendientes. Se sabe que la API móvil exige
  `X-Argus`/`X-Ladon` (ver 2.5); no se han vuelto a medir sobre HTTP/2. Los
  comentarios se quedan fuera por ahora; el botón lo explica.
