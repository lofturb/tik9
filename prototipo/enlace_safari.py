# -*- coding: utf-8 -*-
"""
enlace_safari.py -- genera la prueba de la busqueda EN SAFARI con URLs bien firmadas.

La prueba anterior no valia: la URL estaba firmada con el User-Agent de la app,
y Safari manda el suyo.  La firma de TikTok cubre el UA, asi que esa peticion no
podia validarse por construccion.  Aqui se firma con el UA real del aparato (se
lee de entrega/agentes.txt, que lo apunta el servidor de instalacion cuando se
abre /ua en Safari).

Cada URL se comprueba primero DESDE EL PC con el mismo UA y la misma firma: si
desde el PC trae resultados, entonces cualquier pagina en blanco que se vea en
Safari es cosa de la conexion del aparato, no de la firma.

Uso:
    python prototipo/enlace_safari.py [palabra] [--ua "Mozilla/5.0 ..."]
"""

import html
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
sys.path.insert(0, AQUI)

import xgnarly as X  # noqa: E402
from confianza_app import UA_APP  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402

BASE_WEB = "https://www.tiktok.com"
RUTA_BUSQUEDA = "/api/search/general/full/"
RUTA_FEED = "/api/recommend/item_list/"
SALIDA = os.path.join(RAIZ, "entrega", "prueba_safari2.html")
AGENTES = os.path.join(RAIZ, "entrega", "agentes.txt")

DISPONIBLE = "7150243986172025341"     # 19 cifras, como los de TikTok

# El UA que manda Safari en un iPad mini 1 con iOS 9.3.6, por si aun no hay
# ninguno apuntado en agentes.txt.
UA_IPAD9 = ("Mozilla/5.0 (iPad; CPU OS 9_3_6 like Mac OS X) "
            "AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 "
            "Mobile/13G37 Safari/601.1")


def ua_del_aparato():
    """El ultimo User-Agent de navegador que ha pedido algo al servidor."""
    try:
        with open(AGENTES, encoding="utf-8") as f:
            lineas = f.read().splitlines()
    except OSError:
        return "", UA_IPAD9
    ultimo = ""
    for linea in lineas:
        if linea.lower().startswith("user-agent:") and "mozilla" in linea.lower():
            ultimo = linea.split(":", 1)[1].strip()
    return ultimo, (ultimo or UA_IPAD9)


def base_como_la_app():
    return [
        ("aid", "1988"), ("app_language", "en-US"), ("app_name", "tiktok_web"),
        ("browser_language", "en-US"), ("browser_name", "Mozilla"),
        ("browser_online", "true"), ("browser_platform", "Win32"),
        ("channel", "tiktok_web"), ("cookie_enabled", "true"),
        ("device_id", DISPONIBLE), ("device_platform", "web_pc"),
        ("os", "windows"), ("region", "US"), ("tz_name", "America/New_York"),
    ]


def base_como_un_ipad():
    """La misma base, pero declarando un iPad: si el problema fuera que la app
    dice ser un PC con Windows y se conecta como un iPad viejo, esto lo arregla."""
    return [
        ("aid", "1988"), ("app_language", "en-US"), ("app_name", "tiktok_web"),
        ("browser_language", "en-US"), ("browser_name", "Mozilla"),
        ("browser_online", "true"), ("browser_platform", "iPad"),
        ("channel", "tiktok_web"), ("cookie_enabled", "true"),
        ("device_id", DISPONIBLE), ("device_platform", "web_mobile"),
        ("os", "ios"), ("region", "US"), ("tz_name", "America/New_York"),
    ]


def pares_de_busqueda(palabra, base):
    pares = list(base) + [("count", "12")]
    pares += [("offset", "0"), ("is_filter_search", "0"),
              ("query_correct_type", "1"), ("search_source", "normal_search"),
              ("keyword", palabra)]
    return pares


def pares_de_feed(base):
    return list(base) + [("count", "12"), ("cursor", "0")]


def main():
    palabra = "auron"
    ua_forzado = ""
    argumentos = sys.argv[1:]
    i = 0
    while i < len(argumentos):
        if argumentos[i] == "--ua" and i + 1 < len(argumentos):
            ua_forzado = argumentos[i + 1]
            i += 2
            continue
        palabra = argumentos[i]
        i += 1

    guardado, ua_safari = ua_del_aparato()
    if ua_forzado:
        ua_safari = ua_forzado
    print("UA del aparato (de agentes.txt): %s" % (guardado or "(todavia nada)"))
    print("UA que se va a usar para firmar: %s\n" % ua_safari)

    # Identidad solo para tener un msToken de verdad con el que firmar.
    sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
    sesion.headers.update({"User-Agent": UA_APP})
    sesion.get(BASE_WEB + "/foryou", timeout=40)
    ms = dict(sesion.cookies).get("msToken", "")

    # Calentamiento: la primera peticion de una identidad recien estrenada sale
    # gateada siempre (medido).  Se gasta aqui, para que la comprobacion de las
    # cuatro variantes no confunda ese gate con un fallo de la firma.
    caliente = pares_de_busqueda(palabra, base_como_la_app())
    consulta_caliente, _ = X.XGnarly(ua_safari).sign(caliente, ms_token=ms)
    try:
        sesion.get(BASE_WEB + RUTA_BUSQUEDA + "?" + consulta_caliente, timeout=40)
    except Exception:  # noqa: BLE001
        pass

    variantes = [
        ("1. Control: el feed (la app si lo ve bien)", RUTA_FEED,
         pares_de_feed(base_como_la_app()), ua_safari),
        ("2. Busqueda con la firma de la APP (esta era la prueba en blanco)",
         RUTA_BUSQUEDA, pares_de_busqueda(palabra, base_como_la_app()), UA_APP),
        ("3. Busqueda firmada con el UA de Safari", RUTA_BUSQUEDA,
         pares_de_busqueda(palabra, base_como_la_app()), ua_safari),
        ("4. Busqueda firmada como Safari Y declarandose iPad", RUTA_BUSQUEDA,
         pares_de_busqueda(palabra, base_como_un_ipad()), ua_safari),
    ]

    preparadas = []
    print("comprobacion desde el PC (mismo UA y misma firma que usara Safari):")
    for etiqueta, ruta, pares, ua in variantes:
        consulta, _ = X.XGnarly(ua).sign(pares, ms_token=ms)
        url = BASE_WEB + ruta + "?" + consulta
        try:
            r = sesion.get(url, headers={"User-Agent": ua,
                                         "Accept": "application/json, text/plain, */*"},
                           timeout=40)
            datos = -1
            try:
                datos = len(json.loads(r.content.decode("utf-8", "replace")).get("data")
                            or json.loads(r.content.decode("utf-8", "replace")).get("itemList")
                            or [])
            except Exception:  # noqa: BLE001
                pass
            vista = "HTTP %s  %d B  orcas=%s  items=%s" % (
                r.status_code, len(r.content), r.headers.get("tt_orcas_res") or "-", datos)
        except Exception as fallo:  # noqa: BLE001
            vista = "ERROR %s: %s" % (type(fallo).__name__, str(fallo)[:60])
        print("  %-52s %s" % (etiqueta[:52], vista))
        preparadas.append((etiqueta, url))

    filas = []
    for etiqueta, url in preparadas:
        filas.append(
            '  <a class="tarjeta" href="%s">\n'
            '    <div class="paso">%s</div>\n'
            '    <div class="detalle">%s caracteres de URL firmada</div>\n'
            '  </a>\n' % (html.escape(url, quote=True), html.escape(etiqueta),
                          len(url)))

    pagina = """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tik9: la busqueda desde Safari, bien firmada</title>
<style>
  body { font-family: -apple-system, sans-serif; margin: 0; padding: 18px;
         background: #f6f6f8; color: #16181d; }
  h1 { font-size: 20px; margin: 0 0 6px; }
  p { font-size: 14px; line-height: 1.45; color: #3b3f46; }
  code { background: #e8e8ee; padding: 1px 4px; border-radius: 4px; }
  .tarjeta { display: block; background: #fff; border-radius: 12px;
             padding: 14px 16px; margin: 12px 0; text-decoration: none;
             color: inherit; box-shadow: 0 1px 3px rgba(0,0,0,.12); }
  .paso { font-size: 15px; font-weight: 600; margin-bottom: 4px; }
  .detalle { font-size: 13px; color: #5b616b; }
  .aviso { background: #fff6e5; border-left: 4px solid #e8a33d;
           padding: 10px 12px; border-radius: 8px; font-size: 14px; }
</style>
</head>
<body>
<h1>La busqueda desde Safari, firmada de verdad</h1>
<p>La prueba anterior no valia: la firma era la de la app y Safari manda otro
User-Agent. Aqui cada enlace va <b>firmado con el User-Agent de Safari</b>.</p>
<div class="aviso">
  Toca <b>en orden</b>, del 1 al 4. Si alguna se queda <b>en blanco</b>,
  tocala <b>otra vez 2 o 3 veces</b>: la primera peticion de una identidad
  nueva suele salir vacia (esta medido) y la siguiente ya trae datos.<br><br>
  Apunta lo que sale en cada una:
  <b>1</b> control del feed &middot; <b>2</b> firma de la app &middot;
  <b>3</b> firma de Safari &middot; <b>4</b> como iPad.
</div>
%s
<p>Lo que <b>deberia</b> salir: un texto largo de JSON con <code>"data":[</code>
y videos dentro. En blanco significa que TikTok no ha querido contestar a este
aparato.</p>
</body>
</html>
""" % "".join(filas)

    os.makedirs(os.path.dirname(SALIDA), exist_ok=True)
    with open(SALIDA, "w", encoding="utf-8") as f:
        f.write(pagina)
    print("\nescrita %s" % SALIDA)


if __name__ == "__main__":
    main()
