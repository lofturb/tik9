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

**Conclusión:** no son las cookies, ni el X-Bogus, ni los parámetros. Lo único que
separa esta petición de la del navegador es **el `msToken` que genera su
JavaScript** (y el resto de la huella del SDK). Por eso la app **pide de verdad**
la búsqueda y aprovecha la sesión si se le da (`Ajustes → Cookies`); abrirla del
todo exigiría ejecutar el SDK dentro de la app.

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
* **Buscar, comentarios, perfiles:** bloqueados por TikTok para clientes que no
  son la app oficial (respuestas vacías). La app **sí** trae la lupa (para
  parecerse a la oficial), pero **no finge**: sugiere con retos, autores e
  historial local y busca **dentro del feed ya cargado**. Los comentarios se
  quedan fuera; el botón lo explica.
