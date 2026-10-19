# -*- coding: utf-8 -*-
"""
probar_device_id.py -- mide si el `device_id` es lo que gatea la busqueda.

Hallazgo de la comunidad (Evil0ctal/dtk, 2026-09-08): a TikTok le falta
`device_id` y contesta 200 con cuerpo vacio y la cabecera tt_orcas_res: 1, sin
decir nada mas.  Unos endpoints lo verifican y otros no.  Aqui se pide la
busqueda con la lista EXACTA de la app variando solo ese parametro.

Se hace una peticion de calentamiento antes (la primera busqueda de una
identidad nueva sale gateada siempre) y un control con device_id bueno entre
variantes, para no confundir el gate permanente con el transitorio.

Uso:  python prototipo/probar_device_id.py [palabra]
"""

import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)

import xgnarly as X  # noqa: E402
from confianza_app import UA_APP  # noqa: E402
from probar_busqueda_navegador import URL_BASE  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402

BUENO = "7532140987654321098"   # 19 digitos, el primero no cero


def pares_con(palabra, device_id=None, borrar=False):
    """Copia literal de TTSesion.paresBase + TTCliente.paresDeBusqueda."""
    pares = [
        ("aid", "1988"), ("app_language", "en-US"), ("app_name", "tiktok_web"),
        ("browser_language", "en-US"), ("browser_name", "Mozilla"),
        ("browser_online", "true"), ("browser_platform", "Win32"),
        ("channel", "tiktok_web"), ("cookie_enabled", "true"),
        ("device_id", BUENO if device_id is None else device_id),
        ("device_platform", "web_pc"),
        ("os", "windows"), ("region", "US"), ("tz_name", "America/New_York"),
        ("count", "12"), ("offset", "0"), ("is_filter_search", "0"),
        ("query_correct_type", "1"), ("search_source", "normal_search"),
        ("keyword", palabra),
    ]
    if borrar:
        pares = [p for p in pares if p[0] != "device_id"]
    return pares


def main():
    palabra = sys.argv[1] if len(sys.argv) > 1 else "auron"

    sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
    sesion.headers.update({"User-Agent": UA_APP})
    sesion.get("https://www.tiktok.com/foryou", timeout=40)
    galletas = dict(sesion.cookies)
    ms = galletas.get("msToken", "")
    cabeceras = {
        "User-Agent": UA_APP,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://www.tiktok.com/",
        "Origin": "https://www.tiktok.com",
        "Cookie": "; ".join("%s=%s" % (k, v) for k, v in sorted(galletas.items())),
    }

    def pedir(etiqueta, pares):
        # La firma cubre la cadena de consulta exacta, asi que se firma cada vez.
        consulta, _ = X.XGnarly(UA_APP).sign(pares, ms_token=ms)
        r = sesion.get(URL_BASE + "?" + consulta, headers=cabeceras, timeout=40)
        datos = -1
        try:
            datos = len(json.loads(r.content.decode("utf-8", "replace")).get("data") or [])
        except Exception:  # noqa: BLE001
            pass
        print("  %-36s HTTP %s %7d B orcas=%-4s data=%s" % (
            etiqueta, r.status_code, len(r.content),
            r.headers.get("tt_orcas_res") or "-", datos))

    print("identidad: %s   msToken=%d car." % (
        ", ".join("%s(%d)" % (k, len(v)) for k, v in sorted(galletas.items())), len(ms)))

    print("\ncalentamiento (se espera gateada):")
    pedir("1a busqueda (device_id bueno)", pares_con(palabra))

    print("\nvarios, dos veces cada uno:")
    variantes = [
        ("device_id bueno (control)", pares_con(palabra)),
        ("device_id vacio", pares_con(palabra, device_id="")),
        ("sin el parametro device_id", pares_con(palabra, borrar=True)),
        ("device_id corto (5 digitos)", pares_con(palabra, device_id="75321")),
        ("device_id de letras", pares_con(palabra, device_id="abcdefghijklmnopqrs")),
    ]
    for vuelta in range(2):
        for etiqueta, pares in variantes:
            pedir("%s%s" % (etiqueta, "" if vuelta == 0 else " (2a)"), pares)


if __name__ == "__main__":
    main()
