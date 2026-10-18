# -*- coding: utf-8 -*-
"""Localiza EXACTAMENTE donde viene la URL /aweme/v1/play dentro del itemStruct
y en cuantos videos del feed aparece.  Decide como parsearla en la app.

Uso:  python prototipo/inspeccionar_play.py
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import peticion  # noqa: E402
from probar_listas import params_recomendados  # noqa: E402


def rutas_hacia(nodo, objetivo, ruta="", salida=None):
    if salida is None:
        salida = []
    if isinstance(nodo, dict):
        for k, v in nodo.items():
            rutas_hacia(v, objetivo, "%s.%s" % (ruta, k), salida)
    elif isinstance(nodo, list):
        for i, v in enumerate(nodo):
            rutas_hacia(v, objetivo, "%s[%d]" % (ruta, i), salida)
    elif isinstance(nodo, str) and objetivo in nodo:
        salida.append(ruta)
    return salida


def main():
    est, cuerpo, _, _ = peticion("/api/recommend/item_list/", params_recomendados())
    print("feed: estado=%s bytes=%d" % (est, len(cuerpo)))
    j = json.loads(cuerpo)
    items = j.get("itemList") or []
    print("items: %d\n" % len(items))

    con_play = 0
    for it in items:
        v = it.get("video") or {}
        rutas = rutas_hacia(v, "/aweme/v1/play/")
        if rutas:
            con_play += 1
        print("item %s  videoID=%s" % (it.get("id"), v.get("videoID")))
        for r in sorted(set(rutas)):
            print("    ", r)
    print("\nvideos con /aweme/v1/play: %d de %d" % (con_play, len(items)))

    # Forma de un nodo bitrateInfo
    if items:
        v = items[0].get("video") or {}
        bi = v.get("bitrateInfo") or []
        print("\nbitrateInfo: %d entradas" % len(bi))
        if bi:
            entrada = bi[0]
            print("claves de bitrateInfo[0]:", sorted(entrada.keys()))
            pa = entrada.get("PlayAddr") or {}
            print("claves de PlayAddr:", sorted(pa.keys()))
            print("PlayAddr.Uri:", pa.get("Uri"))
            print("PlayAddr.UrlList (%d):" % len(pa.get("UrlList") or []))
            for u in (pa.get("UrlList") or []):
                print("     ", u[:110])
            print("PlayAddr.DataSize:", pa.get("DataSize"),
                  " Height:", pa.get("Height"), " Width:", pa.get("Width"))
            print("CodecType:", entrada.get("CodecType"),
                  " GearName:", entrada.get("GearName"),
                  " QualityType:", entrada.get("QualityType"))
        print("\nvideo.playAddr:", (v.get("playAddr") or "")[:120])
        print("video.downloadAddr:", (v.get("downloadAddr") or "")[:120])


if __name__ == "__main__":
    main()
