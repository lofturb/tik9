# -*- coding: utf-8 -*-
"""
El itemStruct da la URL del MP4, pero el CDN responde 403 sin cabeceras.
Este script prueba combinaciones de cabeceras/cookies hasta dar con la que
funciona, que es la que tendra que mandar AVPlayer.
"""

import json
import os
import sys
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from probar import params_item_detalle, UA, azar  # noqa: E402
from xgnarly import XGnarly  # noqa: E402


def firmar_y_pedir(ruta, params, cookie=""):
    firmado, _ = XGnarly(UA).sign(params, ms_token="")
    url = "https://www.tiktok.com%s?%s" % (ruta, firmado)
    cab = {"User-Agent": UA, "Accept": "application/json, text/plain, */*",
           "Referer": "https://www.tiktok.com/"}
    if cookie:
        cab["Cookie"] = cookie
    req = urllib.request.Request(url, headers=cab)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace"), dict(r.headers), r.headers.get_all("Set-Cookie") or []


def probar(url, cabeceras):
    req = urllib.request.Request(url, headers=cabeceras)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            d = r.read(300000)
            return "OK %s ct=%s cr=%s bytes=%d avc1=%s hvc1=%s" % (
                r.status, r.headers.get("Content-Type"), r.headers.get("Content-Range"),
                len(d), b"avc1" in d, b"hvc1" in d)
    except urllib.error.HTTPError as e:
        return "HTTP %s %s" % (e.code, e.read(120))
    except Exception as e:  # noqa: BLE001
        return "EXC %r" % (e,)


def main():
    item_id = sys.argv[1] if len(sys.argv) > 1 else "7106594312292453675"
    cuerpo, cab_resp, set_cookie = firmar_y_pedir("/api/item/detail/", params_item_detalle(item_id))
    print("Set-Cookie de item/detail:", set_cookie)
    print()
    v = json.loads(cuerpo)["itemInfo"]["itemStruct"]["video"]

    # elegir la mejor variante H.264 (evitar h265_hvc1)
    elegido = None
    for bi in v.get("bitrateInfo") or []:
        if (bi.get("CodecType") or "").lower() == "h264":
            pa = bi.get("PlayAddr") or {}
            urls = pa.get("UrlList") or []
            if urls:
                elegido = (bi.get("GearName"), pa.get("Width"), pa.get("Height"), urls[0])
                break
    print("variante h264 elegida:", elegido[:3])
    url = elegido[3]

    combos = [
        ("sin cabeceras", {}),
        ("solo UA", {"User-Agent": UA}),
        ("solo Referer", {"Referer": "https://www.tiktok.com/"}),
        ("UA+Referer", {"User-Agent": UA, "Referer": "https://www.tiktok.com/"}),
        ("UA+Referer+Cookie ttwid", {"User-Agent": UA, "Referer": "https://www.tiktok.com/",
                                     "Cookie": "ttwid=" + azar(80)}),
        ("UA+Referer+ttwid real respuesta", {"User-Agent": UA, "Referer": "https://www.tiktok.com/",
                                             "Cookie": "; ".join(c.split(";")[0] for c in set_cookie) or "ttwid=" + azar(80)}),
        ("Range+UA+Referer", {"User-Agent": UA, "Referer": "https://www.tiktok.com/",
                              "Range": "bytes=0-262143"}),
    ]
    for nombre, cab in combos:
        print("%-34s -> %s" % (nombre, probar(url, cab)))


if __name__ == "__main__":
    main()
