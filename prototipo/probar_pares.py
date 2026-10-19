# -*- coding: utf-8 -*-
"""
probar_pares.py -- mide si a la busqueda le falta el parametro `cursor`.

La receta del PC (la que SI trae resultados) manda base + count + cursor + offset
+ ... ; la app manda base + count + offset + ... (sin cursor).  Todo lo demas es
identico: misma ruta, mismo UA, misma firma, mismas cabeceras, misma conexion.

Uso:  python prototipo/probar_pares.py [palabra]
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

SIN_CURSOR = 0


def pares_de_la_app(pal, con_cursor):
    """Copia literal de TTSesion.paresBase + TTCliente.paresDeBusqueda."""
    base = [
        ("aid", "1988"), ("app_language", "en-US"), ("app_name", "tiktok_web"),
        ("browser_language", "en-US"), ("browser_name", "Mozilla"),
        ("browser_online", "true"), ("browser_platform", "Win32"),
        ("channel", "tiktok_web"), ("cookie_enabled", "true"),
        ("device_id", "7" + "0" * 18), ("device_platform", "web_pc"),
        ("os", "windows"), ("region", "US"), ("tz_name", "America/New_York"),
        ("count", "12"),
    ]
    if con_cursor:
        base.append(("cursor", "0"))
    base += [
        ("offset", "0"), ("is_filter_search", "0"),
        ("query_correct_type", "1"), ("search_source", "normal_search"),
        ("keyword", pal),
    ]
    return base


def main():
    palabra = sys.argv[1] if len(sys.argv) > 1 else "auron"

    sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
    sesion.headers.update({"User-Agent": UA_APP})
    sesion.get("https://www.tiktok.com/foryou", timeout=40)
    galletas = dict(sesion.cookies)
    ms = galletas.get("msToken", "")
    if not ms:
        consulta, _ = X.XGnarly(UA_APP).sign([("aid", "1988")], ms_token="")
        r = sesion.get(URL_BASE + "?" + consulta, timeout=40)
        ms = r.headers.get("x-ms-token") or ""
    cabeceras = {
        "User-Agent": UA_APP,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://www.tiktok.com/",
        "Origin": "https://www.tiktok.com",
        "Cookie": "; ".join("%s=%s" % (k, v) for k, v in sorted(galletas.items())),
    }
    print("cookies: %s   msToken=%d car.\n" % (", ".join(sorted(galletas)), len(ms)))

    pruebas = [
        ("receta del PC (cursor + offset)", pares_app(palabra)),
        ("la app tal cual (sin cursor)", pares_de_la_app(palabra, False)),
        ("la app + cursor", pares_de_la_app(palabra, True)),
    ]
    for etiqueta, pares in pruebas:
        consulta, _ = X.XGnarly(UA_APP).sign(pares, ms_token=ms)
        r = sesion.get(URL_BASE + "?" + consulta, headers=cabeceras, timeout=40)
        datos, estado = -1, "?"
        try:
            j = json.loads(r.content.decode("utf-8", "replace"))
            datos, estado = len(j.get("data") or []), j.get("status_code")
        except Exception:  # noqa: BLE001
            pass
        print("  %-34s HTTP %s %8d B  orcas=%-5s status=%s data=%s" % (
            etiqueta, r.status_code, len(r.content),
            r.headers.get("tt_orcas_res") or "-", estado, datos))


if __name__ == "__main__":
    main()
