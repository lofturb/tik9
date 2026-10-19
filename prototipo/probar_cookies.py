# -*- coding: utf-8 -*-
"""
probar_cookies.py -- mide si a la busqueda le falta alguna cookie.

La identidad anonima de TikTok no es solo `ttwid`: /foryou tambien deja
`tt_chain_token` (el testigo de la cadena anti-bot) y `tt_csrf_token`.  El feed
pasa sin nada de eso, pero la busqueda puede exigirlo.  Aqui se pide la misma
busqueda (mismos parametros y misma firma) cambiando solo el juego de cookies.

Uso:  python prototipo/probar_cookies.py [palabra]
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


def main():
    palabra = sys.argv[1] if len(sys.argv) > 1 else "auron"

    sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
    sesion.headers.update({"User-Agent": UA_APP})
    sesion.get("https://www.tiktok.com/foryou", timeout=40)
    galletas = dict(sesion.cookies)
    ms = galletas.get("msToken", "")
    print("cookies del PC y su tamano:")
    for nombre in sorted(galletas):
        print("   %-16s %3d car." % (nombre, len(galletas[nombre])))
    print("   (la app dice: cookie 174 car. y msToken 120 car.)\n")

    pares = [(k, v) for k, v in pares_app(palabra)]
    consulta, _ = X.XGnarly(UA_APP).sign(pares, ms_token=ms)

    def peticion(etiqueta, cookies):
        cabeceras = {
            "User-Agent": UA_APP,
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "https://www.tiktok.com/",
            "Origin": "https://www.tiktok.com",
        }
        if cookies:
            cabeceras["Cookie"] = "; ".join("%s=%s" % (k, v) for k, v in cookies)
        r = sesion.get(URL_BASE + "?" + consulta, headers=cabeceras, timeout=40)
        datos, estado = -1, "?"
        try:
            j = json.loads(r.content.decode("utf-8", "replace"))
            datos, estado = len(j.get("data") or []), j.get("status_code")
        except Exception:  # noqa: BLE001
            pass
        print("  %-38s HTTP %s %8d B  orcas=%-5s status=%s data=%s  (cookie %d car.)" % (
            etiqueta, r.status_code, len(r.content),
            r.headers.get("tt_orcas_res") or "-", estado, datos,
            len(cabeceras.get("Cookie", ""))))

    ordenadas = sorted(galletas.items())
    peticion("todas las cookies", ordenadas)
    peticion("solo ttwid", [("ttwid", galletas.get("ttwid", ""))])
    peticion("solo ttwid + msToken",
             [("ttwid", galletas.get("ttwid", "")), ("msToken", ms)])
    peticion("todas menos tt_chain_token",
             [c for c in ordenadas if c[0] != "tt_chain_token"])
    peticion("sin ninguna cookie", [])

    # Y el msToken de la firma: con uno vacio o inventado, ¿que contesta?
    print()
    for etiqueta, token in [("firma con el msToken bueno", ms),
                            ("firma con msToken vacio", ""),
                            ("firma con msToken inventado", "a" * len(ms))]:
        consulta2, _ = X.XGnarly(UA_APP).sign(pares, ms_token=token)
        r = sesion.get(URL_BASE + "?" + consulta2,
                       headers={"User-Agent": UA_APP,
                                "Accept": "application/json, text/plain, */*",
                                "Referer": "https://www.tiktok.com/",
                                "Cookie": "; ".join("%s=%s" % (k, v) for k, v in ordenadas)},
                       timeout=40)
        datos, estado = -1, "?"
        try:
            j = json.loads(r.content.decode("utf-8", "replace"))
            datos, estado = len(j.get("data") or []), j.get("status_code")
        except Exception:  # noqa: BLE001
            pass
        print("  %-38s HTTP %s %8d B  orcas=%-5s status=%s data=%s" % (
            etiqueta, r.status_code, len(r.content),
            r.headers.get("tt_orcas_res") or "-", estado, datos))


if __name__ == "__main__":
    main()
