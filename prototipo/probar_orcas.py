# -*- coding: utf-8 -*-
"""
probar_orcas.py -- fotografia de la respuesta con orcas=1 frente a la buena.

El fallo (200 con 0 bytes y cabecera tt_orcas_res: 1) es intermitente: parece
caer en la PRIMERA busqueda despues de estrenar identidad.  Aqui se repite eso
muchas veces con sesiones nuevas y se vuelcan TODAS las cabeceras de respuesta,
para ver que dice TikTok cuando flaggea y en que se diferencia de cuando sirve.

Uso:  python prototipo/probar_orcas.py [palabra] [intentos]
"""

import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)

import xgnarly as X  # noqa: E402
from confianza_app import UA_APP, pares_app  # noqa: E402
from probar_busqueda_navegador import URL_BASE  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402


def una_busqueda(sesion, consulta, galletas, etiqueta, volcar=False):
    cabeceras = {
        "User-Agent": UA_APP,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://www.tiktok.com/",
        "Origin": "https://www.tiktok.com",
        "Cookie": "; ".join("%s=%s" % (k, v) for k, v in sorted(galletas.items())),
    }
    r = sesion.get(URL_BASE + "?" + consulta, headers=cabeceras, timeout=40)
    datos = -1
    try:
        datos = len(json.loads(r.content.decode("utf-8", "replace")).get("data") or [])
    except Exception:  # noqa: BLE001
        pass
    print("  %-28s HTTP %s %7d B orcas=%-4s data=%s" % (
        etiqueta, r.status_code, len(r.content),
        r.headers.get("tt_orcas_res") or "-", datos))
    if volcar:
        for nombre in sorted(r.headers):
            print("        %-28s %s" % (nombre.lower(), r.headers[nombre][:90]))
    return datos


def main():
    palabra = sys.argv[1] if len(sys.argv) > 1 else "auron"
    intentos = int(sys.argv[2]) if len(sys.argv) > 2 else 4

    vacios = 0
    for intento in range(intentos):
        sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
        sesion.headers.update({"User-Agent": UA_APP})
        sesion.get("https://www.tiktok.com/foryou", timeout=40)
        galletas = dict(sesion.cookies)
        ms = galletas.get("msToken", "")
        consulta, _ = X.XGnarly(UA_APP).sign(
            [(k, v) for k, v in pares_app(palabra)], ms_token=ms)
        print("identidad nueva %d: %s  msToken=%d" % (
            intento + 1, ", ".join("%s(%d)" % (k, len(v)) for k, v in sorted(galletas.items())), len(ms)))
        primera = una_busqueda(sesion, consulta, galletas, "1a busqueda (nueva identidad)",
                              volcar=True)
        segunda = una_busqueda(sesion, consulta, galletas, "2a busqueda", volcar=primera <= 0)
        if primera <= 0:
            vacios += 1
        _ = segunda

    print("\nresumen: %d de %d primeras busquedas salieron vacias" % (vacios, intentos))


if __name__ == "__main__":
    main()
