# -*- coding: utf-8 -*-
"""
Extrae del itemStruct la direccion del MP4 y comprueba la descarga real
(Range), el codec (avc1/hvc1) y los contenedores.  Prueba de punta a punta
del camino que usara la app: firmar -> obtener metadatos -> reproducir.
"""

import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from probar import peticion, params_item_detalle, UA, resumen  # noqa: E402


def probe_mp4(url, nota):
    req = urllib.request.Request(url, headers={"Range": "bytes=0-262143"})
    with urllib.request.urlopen(req, timeout=40) as r:
        datos = r.read()
        return {
            "nota": nota,
            "estado": r.status,
            "content_type": r.headers.get("Content-Type"),
            "content_range": r.headers.get("Content-Range"),
            "accept_ranges": r.headers.get("Accept-Ranges"),
            "bytes_leidos": len(datos),
            "ftyp": b"ftyp" in datos,
            "marca": datos[datos.find(b"ftyp"):datos.find(b"ftyp") + 12] if b"ftyp" in datos else None,
            "avc1": b"avc1" in datos,
            "hvc1": b"hvc1" in datos,
            "hev1": b"hev1" in datos,
            "mp4a": b"mp4a" in datos,
        }


def main():
    item_id = sys.argv[1] if len(sys.argv) > 1 else "7106594312292453675"
    estado, cuerpo, _, _ = peticion("/api/item/detail/", params_item_detalle(item_id))
    j = json.loads(cuerpo)
    it = j["itemInfo"]["itemStruct"]
    v = it["video"]
    print("== itemStruct ==")
    print("desc      :", (it.get("desc") or "")[:80])
    print("autor     :", it.get("author", {}).get("uniqueId"))
    print("duracion  :", v.get("duration"))
    print("tamano px :", v.get("width"), "x", v.get("height"))
    print("videoID   :", v.get("videoID"))
    print("claves v  :", sorted(v.keys()))
    print()

    print("== bitrateInfo ==")
    for bi in (v.get("bitrateInfo") or []):
        pa = (bi.get("PlayAddr") or {})
        urls = pa.get("UrlList") or []
        print("  codec=%-6s gear=%-6s %sx%s  urls=%d" % (
            bi.get("CodecType"), bi.get("GearName"), pa.get("Width"), pa.get("Height"), len(urls)))
    print()

    candidatos = []
    if v.get("playAddr"):
        candidatos.append(("playAddr", v["playAddr"]))
    if v.get("downloadAddr"):
        candidatos.append(("downloadAddr", v["downloadAddr"]))
    for bi in (v.get("bitrateInfo") or []):
        if (bi.get("CodecType") or "").lower() in ("h264", "avc"):
            for u in ((bi.get("PlayAddr") or {}).get("UrlList") or []):
                candidatos.append(("bitrateInfo/h264", u))
                break

    for nota, url in candidatos[:4]:
        print("== probe %s ==" % nota)
        try:
            r = probe_mp4(url, nota)
            for k, val in r.items():
                print("  %-15s %s" % (k, val))
        except Exception as e:  # noqa: BLE001
            print("  ERROR:", repr(e))
        print()


if __name__ == "__main__":
    main()
