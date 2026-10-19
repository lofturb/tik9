# -*- coding: utf-8 -*-
"""
probar_estabilidad.py -- ¿el orcas=1 de la busqueda es estable o va y viene?

En dos tandas anteriores la MISMA peticion (mismos parametros, misma firma,
mismas cookies) una vez devolvio 0 B con orcas=1 y otras veces 13 resultados.
Aqui se pide varias veces alternando dos juegos de cookies para ver si la
diferencia es real y repetible, o si es algo transitorio (limite por IP, estado
de la cadena anti-bot, etc.).

Uso:  python prototipo/probar_estabilidad.py [palabra] [repeticiones]
"""

import json
import os
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)

import xgnarly as X  # noqa: E402
from confianza_app import UA_APP, pares_app  # noqa: E402
from probar_busqueda_navegador import URL_BASE  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402


def main():
    palabra = sys.argv[1] if len(sys.argv) > 1 else "auron"
    veces = int(sys.argv[2]) if len(sys.argv) > 2 else 5

    sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
    sesion.headers.update({"User-Agent": UA_APP})
    sesion.get("https://www.tiktok.com/foryou", timeout=40)
    galletas = dict(sesion.cookies)
    ms = galletas.get("msToken", "")
    print("cookies: %s" % ", ".join("%s(%d)" % (k, len(v)) for k, v in sorted(galletas.items())))

    pares = [(k, v) for k, v in pares_app(palabra)]
    consulta, _ = X.XGnarly(UA_APP).sign(pares, ms_token=ms)

    juegos = [
        ("solo ttwid", [("ttwid", galletas.get("ttwid", ""))]),
        ("ttwid + tt_chain_token (la app)",
         [("ttwid", galletas.get("ttwid", "")),
          ("tt_chain_token", galletas.get("tt_chain_token", ""))]),
        ("las tres del PC", sorted(galletas.items())),
    ]

    recuento = {etiqueta: 0 for etiqueta, _ in juegos}
    for vuelta in range(veces):
        for etiqueta, cookies in juegos:
            cabeceras = {
                "User-Agent": UA_APP,
                "Accept": "application/json, text/plain, */*",
                "Accept-Language": "en-US,en;q=0.9",
                "Referer": "https://www.tiktok.com/",
                "Origin": "https://www.tiktok.com",
                "Cookie": "; ".join("%s=%s" % (k, v) for k, v in cookies if v),
            }
            r = sesion.get(URL_BASE + "?" + consulta, headers=cabeceras, timeout=40)
            datos, estado = -1, "?"
            try:
                j = json.loads(r.content.decode("utf-8", "replace"))
                datos, estado = len(j.get("data") or []), j.get("status_code")
            except Exception:  # noqa: BLE001
                pass
            bien = datos > 0
            recuento[etiqueta] += 1 if bien else 0
            print("  vuelta %d  %-30s HTTP %s %8d B orcas=%-4s data=%-3s %s" % (
                vuelta + 1, etiqueta, r.status_code, len(r.content),
                r.headers.get("tt_orcas_res") or "-", datos,
                "bien" if bien else "VACIO"))
            time.sleep(1.2)

    print("\nresumen:")
    for etiqueta, aciertos in recuento.items():
        print("  %-30s %d de %d" % (etiqueta, aciertos, veces))


if __name__ == "__main__":
    main()
