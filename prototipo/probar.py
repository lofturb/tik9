# -*- coding: utf-8 -*-
"""
Banco de pruebas: firma una peticion real a la API web de TikTok con el
algoritmo X-Gnarly (portado de f2, Apache-2.0) y la envia usando solo la
biblioteca estandar de Python 3.  Sirve para dos cosas:

  1. Comprobar que la firma funciona desde este PC (oraculo de pruebas).
  2. Servir de referencia para el port a C que hara la app de iOS.

Uso:  python probar.py [item_id]
"""

import os
import random
import string
import sys
import time
import urllib.request
import urllib.error
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from xgnarly import XGnarly  # noqa: E402

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0"
)

ALFABETO = string.ascii_letters + string.digits


def azar(n):
    return "".join(random.choice(ALFABETO) for _ in range(n))


def device_id():
    return "7" + "".join(random.choice(string.digits) for _ in range(18))


def params_item_detalle(item_id):
    """Parametros de negocio que envia la web, en el orden que usa la web."""
    return [
        ("aid", "1988"),
        ("app_language", "en-US"),
        ("app_name", "tiktok_web"),
        ("browser_language", "en-US"),
        ("browser_name", "Mozilla"),
        ("browser_online", "true"),
        ("browser_platform", "Win32"),
        ("browser_version", "5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                            "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0"),
        ("channel", "tiktok_web"),
        ("cookie_enabled", "true"),
        ("coverFormat", "2"),
        ("device_id", device_id()),
        ("device_platform", "web_pc"),
        ("itemId", str(item_id)),
        ("os", "windows"),
        ("priority_region", "US"),
        ("referer", ""),
        ("region", "US"),
        ("screen_height", "1080"),
        ("screen_width", "1920"),
        ("tz_name", "America/New_York"),
        ("webcast_language", "en-US"),
    ]


def params_item_list(sec_uid):
    return [
        ("aid", "1988"),
        ("app_language", "en-US"),
        ("app_name", "tiktok_web"),
        ("browser_language", "en-US"),
        ("browser_name", "Mozilla"),
        ("browser_online", "true"),
        ("browser_platform", "Win32"),
        ("channel", "tiktok_web"),
        ("cookie_enabled", "true"),
        ("count", "16"),
        ("coverFormat", "2"),
        ("cursor", "0"),
        ("device_id", device_id()),
        ("device_platform", "web_pc"),
        ("os", "windows"),
        ("region", "US"),
        ("secUid", sec_uid),
        ("tz_name", "America/New_York"),
    ]


def peticion(ruta, params, ua=UA, cookie="", extra=None):
    firmado, _ = XGnarly(ua).sign(params, ms_token="")
    url = "https://www.tiktok.com%s?%s" % (ruta, firmado)
    cabeceras = {
        "User-Agent": ua,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://www.tiktok.com/",
    }
    if cookie:
        cabeceras["Cookie"] = cookie
    if extra:
        cabeceras.update(extra)
    req = urllib.request.Request(url, headers=cabeceras)
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            cuerpo = r.read().decode("utf-8", "replace")
            return r.status, cuerpo, time.time() - t0, dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), time.time() - t0, dict(e.headers)
    except Exception as e:  # noqa: BLE001
        return None, "EXCEPCION: %r" % (e,), time.time() - t0, {}


def resumen(cuerpo):
    try:
        j = json.loads(cuerpo)
    except Exception:  # noqa: BLE001
        return "no-json"
    claves = list(j.keys())[:8]
    tiene_item = bool(j.get("itemInfo", {}).get("itemStruct"))
    tiene_lista = bool(j.get("itemList"))
    return "claves=%s itemStruct=%s itemList=%s" % (claves, tiene_item, tiene_lista)


def main():
    item_id = sys.argv[1] if len(sys.argv) > 1 else "7106594312292453675"
    print("Python", sys.version.split()[0])
    print("item_id =", item_id)
    print("UA      =", UA[:60], "...")
    print("-" * 70)

    pruebas = [
        ("item/detail  [sin cookie]", "/api/item/detail/", params_item_detalle(item_id), ""),
        ("item/detail  [ttwid]", "/api/item/detail/", params_item_detalle(item_id),
         "ttwid=" + azar(80)),
    ]
    for nombre, ruta, params, cookie in pruebas:
        estado, cuerpo, dt, cab = peticion(ruta, params, cookie=cookie)
        print("[%s]" % nombre)
        print("  estado=%s  bytes=%d  %.2fs  tt_orcas_res=%s" % (
            estado, len(cuerpo), dt, cab.get("tt_orcas_res") or cab.get("tt_orcas_res".title()) or "-"))
        print("  %s" % resumen(cuerpo))
        print("  inicio: %s" % cuerpo[:200].replace("\n", " "))
        print()


if __name__ == "__main__":
    main()
