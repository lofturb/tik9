# -*- coding: utf-8 -*-
"""
diagnostico.py -- dos averiguaciones en vivo, con datos reales:

  1. FEED: por que algunos elementos del feed no traen direccion de reproduccion.
     Se firma recommend/item_list con los mismos parametros que usa la app y se
     mira, elemento por elemento, que clase de publicacion es y de donde sale
     (o no sale) una URL de video.

  2. BUSQUEDA: que endpoints de la web contestan de verdad con la firma web
     (X-Gnarly): resultados y sugerencias.

Uso:  python diagnostico.py [palabra]
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import peticion, device_id  # noqa: E402

AQUI = os.path.dirname(os.path.abspath(__file__))
PAL = sys.argv[1] if len(sys.argv) > 1 else "gatos"


def base_web(extra):
    """Parametros base que envia la web, en su orden."""
    p = [
        ("aid", "1988"),
        ("app_language", "en-US"),
        ("app_name", "tiktok_web"),
        ("browser_language", "en-US"),
        ("browser_name", "Mozilla"),
        ("browser_online", "true"),
        ("browser_platform", "Win32"),
        ("channel", "tiktok_web"),
        ("cookie_enabled", "true"),
    ]
    p += extra
    p += [
        ("device_platform", "web_pc"),
        ("os", "windows"),
        ("region", "US"),
        ("tz_name", "America/New_York"),
    ]
    return p


def params_feed():
    return base_web([("count", "12"), ("cursor", "0"), ("device_id", device_id())])


def urls_de_video(it):
    """Todas las URLs http(s) que el elemento ofrece para el video."""
    urls = []
    v = it.get("video") or {}
    if isinstance(v, dict):
        ba = v.get("bitrateInfo") or []
        if isinstance(ba, list):
            for b in ba:
                pa = (b or {}).get("PlayAddr") or {}
                for u in (pa.get("UrlList") or []):
                    if isinstance(u, str) and u.startswith("http"):
                        urls.append(u)
        pas = v.get("PlayAddrStruct") or {}
        for u in (pas.get("UrlList") or []):
            if isinstance(u, str) and u.startswith("http"):
                urls.append(u)
        for campo in ("playAddr", "downloadAddr"):
            u = v.get(campo)
            if isinstance(u, str) and u.startswith("http"):
                urls.append(u)
    return urls


def analizar_feed():
    print("=" * 74)
    print("1) FEED  --  por que falta la direccion de reproduccion")
    print("=" * 74)
    estado, cuerpo, dt, _ = peticion("/api/recommend/item_list/", params_feed())
    print("estado=%s  bytes=%d  %.2fs" % (estado, len(cuerpo), dt))
    try:
        j = json.loads(cuerpo)
    except Exception:  # noqa: BLE001
        print("  respuesta no-JSON:", cuerpo[:200])
        return
    items = j.get("itemList") or []
    print("elementos: %d\n" % len(items))

    with open(os.path.join(AQUI, "feed_crudo.json"), "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=1)
    print("(volcado completo en prototipo/feed_crudo.json)\n")

    sin_url = 0
    for i, it in enumerate(items):
        urls = urls_de_video(it)
        v = it.get("video") or {}
        ba = v.get("bitrateInfo") if isinstance(v, dict) else None
        img = it.get("imagePost")
        marcas = []
        if it.get("isAd"): marcas.append("ANUNCIO")
        if isinstance(img, dict): marcas.append("FOTO/CARRUSEL")
        if not v: marcas.append("SIN video")
        if isinstance(ba, list) and not ba: marcas.append("bitrateInfo vacio")
        if not urls:
            sin_url += 1
            marcas.append("<< SIN URL >>")
        ids = [u for u in urls if "/aweme/v1/play/" in u]
        print("%2d  id=%s" % (i, it.get("id")))
        print("    tipo=%s  bitrateInfo=%s  playAddr=%s  downloadAddr=%s  fotos=%s" % (
            v.get("format") if isinstance(v, dict) else "-",
            len(ba) if isinstance(ba, list) else "no",
            "si" if isinstance(v, dict) and v.get("playAddr") else "no",
            "si" if isinstance(v, dict) and v.get("downloadAddr") else "no",
            len((img or {}).get("images") or []) if isinstance(img, dict) else "-"))
        print("    urls=%d  de ellas /aweme/v1/play=%d   %s" % (
            len(urls), len(ids), " ".join(marcas)))
        if urls:
            print("    ejemplo: %s" % urls[0][:110])
    print("\nRESUMEN: %d de %d elementos SIN ninguna URL de video" % (sin_url, len(items)))


RUTAS_BUSQUEDA = [
    ("resultados  /api/search/general/full/", "/api/search/general/full/"),
    ("resultados  /api/search/item/full/",    "/api/search/item/full/"),
    ("sugerencias /api/search/suggest/",      "/api/search/suggest/"),
    ("sugerencias /api/search/suggest_clean/", "/api/search/suggest_clean/"),
]


def analizar_busqueda():
    print("\n" + "=" * 74)
    print("2) BUSQUEDA  --  palabra: %r" % PAL)
    print("=" * 74)
    for nombre, ruta in RUTAS_BUSQUEDA:
        extra = [("device_id", device_id()), ("keyword", PAL), ("search_source", "normal_search")]
        estado, cuerpo, dt, cab = peticion(ruta, base_web(extra))
        orcas = cab.get("tt_orcas_res") or cab.get("tt-orcas-res") or "-"
        info = ""
        try:
            j = json.loads(cuerpo)
            claves = sorted(j.keys())
            cuantos = 0
            for k in ("data", "itemList", "sug_list", "suggest_list", "global", "user_list"):
                v = j.get(k)
                if isinstance(v, list):
                    cuantos += len(v)
                elif isinstance(v, dict):
                    for kk, vv in v.items():
                        if isinstance(vv, list):
                            cuantos += len(vv)
            info = "claves=%s  elementos=%d  status=%s" % (
                claves[:8], cuantos, j.get("status_code"))
        except Exception:  # noqa: BLE001
            info = "no-json: %s" % cuerpo[:90].replace("\n", " ")
        print("\n[%s]" % nombre)
        print("  estado=%s  bytes=%d  %.2fs  tt_orcas_res=%s" % (estado, len(cuerpo), dt, orcas))
        print("  %s" % info)


if __name__ == "__main__":
    analizar_feed()
    analizar_busqueda()
