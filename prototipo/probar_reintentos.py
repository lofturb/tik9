# -*- coding: utf-8 -*-
"""
probar_reintentos.py -- que hace falta para que la busqueda deje de salir vacia.

Medido: con identidad recien estrenada, la PRIMERA busqueda sale 200 con 0 bytes
y tt_orcas_res=1 (sello de Akamai Bot Manager); la siguiente, con los mismos
parametros y la misma firma, trae resultados.  La app hace: (1) pedir con el
msToken viejo, (2) al ver el vacio, re-firmar con el msToken que TikTok regala y
pedir otra vez.  Aqui se reproduce ese baile paso a paso para ver que paso falla.

Uso:  python prototipo/probar_reintentos.py [palabra] [sesiones]
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


def pedir(sesion, consulta, galletas, etiqueta):
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
    print("   %-46s HTTP %s %7d B orcas=%-4s data=%s" % (
        etiqueta, r.status_code, len(r.content),
        r.headers.get("tt_orcas_res") or "-", datos))
    return r, r.headers.get("x-ms-token") or ""


def main():
    palabra = sys.argv[1] if len(sys.argv) > 1 else "auron"
    sesiones = int(sys.argv[2]) if len(sys.argv) > 2 else 3

    for vuelta in range(sesiones):
        print("sesion nueva %d" % (vuelta + 1))
        sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
        sesion.headers.update({"User-Agent": UA_APP})
        sesion.get("https://www.tiktok.com/foryou", timeout=40)
        galletas = dict(sesion.cookies)
        ms = galletas.get("msToken", "")

        pares = [(k, v) for k, v in pares_app(palabra)]
        consulta, _ = X.XGnarly(UA_APP).sign(pares, ms_token=ms)

        r1, ms_nuevo = pedir(sesion, consulta, galletas, "1) con msToken viejo (%d car.)" % len(ms))
        if ms_nuevo:
            consulta2, _ = X.XGnarly(UA_APP).sign(pares, ms_token=ms_nuevo)
        else:
            consulta2 = consulta
        pedir(sesion, consulta2, galletas, "2) re-firmada con el regalado (como la app)")
        pedir(sesion, consulta2, galletas, "3) la misma otra vez (sin cambios)")
        pedir(sesion, consulta, galletas, "4) la firma original, sin re-firmar")
        print()


if __name__ == "__main__":
    main()
