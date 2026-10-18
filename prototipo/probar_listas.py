# -*- coding: utf-8 -*-
"""
Mide la autonomia real de la app: con X-Gnarly (web), prueba los endpoints
de LISTAS.  Si item_list / search devuelven contenido, la app puede navegar
sola (portada, perfil, busqueda) y solo la reproduccion necesitaria ayuda.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import peticion, params_item_detalle, params_item_list, device_id, UA  # noqa: E402


def params_busqueda(kw):
    return [
        ("aid", "1988"), ("app_language", "en-US"), ("app_name", "tiktok_web"),
        ("browser_language", "en-US"), ("browser_name", "Mozilla"), ("browser_online", "true"),
        ("browser_platform", "Win32"), ("channel", "tiktok_web"), ("cookie_enabled", "true"),
        ("count", "12"), ("cursor", "0"), ("device_id", device_id()),
        ("device_platform", "web_pc"), ("keyword", kw), ("os", "windows"),
        ("region", "US"), ("search_source", "normal_search"), ("tz_name", "America/New_York"),
    ]


def params_recomendados():
    return [
        ("aid", "1988"), ("app_language", "en-US"), ("app_name", "tiktok_web"),
        ("browser_language", "en-US"), ("browser_name", "Mozilla"), ("browser_online", "true"),
        ("browser_platform", "Win32"), ("channel", "tiktok_web"), ("cookie_enabled", "true"),
        ("count", "12"), ("device_id", device_id()), ("device_platform", "web_pc"),
        ("os", "windows"), ("region", "US"), ("tz_name", "America/New_York"),
    ]


def prueba(nombre, ruta, params):
    est, cuerpo, dt, cab = peticion(ruta, params)
    info = "bytes=%d" % len(cuerpo)
    try:
        j = json.loads(cuerpo)
        claves = list(j.keys())[:10]
        n_items = len(j.get("itemList") or [])
        n_data = len(j.get("data") or [])
        info += "  status_code=%s itemList=%d data=%d" % (j.get("status_code"), n_items, n_data)
        info += "  claves=%s" % claves
    except Exception:  # noqa: BLE001
        info += "  (no json) " + cuerpo[:100].replace("\n", " ")
    print("[%s]\n   %s\n   tt_orcas_res=%s  %.2fs\n" % (
        nombre, info, cab.get("tt-orcas-res") or cab.get("tt_orcas_res") or "-", dt))


def main():
    item_id = sys.argv[1] if len(sys.argv) > 1 else "7106594312292453675"
    _, cuerpo, _, _ = peticion("/api/item/detail/", params_item_detalle(item_id))
    try:
        autor = json.loads(cuerpo)["itemInfo"]["itemStruct"]["author"]
        sec = autor.get("secUid")
        print("secUid de prueba:", sec, "\n")
    except Exception as e:  # noqa: BLE001
        print("no se pudo obtener secUid:", e)
        return

    prueba("post/item_list  (videos del perfil)", "/api/post/item_list/", params_item_list(sec))
    prueba("search/general/full (busqueda)", "/api/search/general/full/", params_busqueda("minecraft"))
    prueba("recommend/item_list (para ti)", "/api/recommend/item_list/", params_recomendados())
    prueba("comment/list", "/api/comment/list/",
           [("aid", "1988"), ("app_language", "en-US"), ("app_name", "tiktok_web"),
            ("aweme_id", item_id), ("count", "20"), ("cursor", "0"),
            ("device_platform", "web_pc"), ("os", "windows")])


if __name__ == "__main__":
    main()
