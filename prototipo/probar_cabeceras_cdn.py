# -*- coding: utf-8 -*-
"""Minimiza las cabeceras que exige el CDN final: UA, Referer o Accept.
Si basta con Accept, AVPlayer lo manda solo y la reproduccion es solida.

Uso:  python prototipo/probar_cabeceras_cdn.py
"""

import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import peticion, UA  # noqa: E402
from probar_listas import params_recomendados  # noqa: E402

UA_APPLE = ("AppleCoreMedia/1.0.0.13G36 (iPhone; U; CPU OS 9_3_5 like Mac OS X; "
            "en_us)")


def url_final():
    _, cuerpo, _, _ = peticion("/api/recommend/item_list/", params_recomendados())
    j = json.loads(cuerpo)
    it = (j.get("itemList") or [])[0]
    v = it.get("video") or {}
    aweme = None
    for b in v.get("bitrateInfo") or []:
        for u in ((b.get("PlayAddr") or {}).get("UrlList") or []):
            if "/aweme/v1/play/" in u:
                aweme = u
                break
        if aweme:
            break
    req = urllib.request.Request(aweme, headers={
        "User-Agent": UA, "Referer": "https://www.tiktok.com/", "Range": "bytes=0-0"})
    with urllib.request.urlopen(req, timeout=25) as r:
        return r.geturl()


def codigo(url, cab):
    req = urllib.request.Request(url, headers=dict(cab, **{"Range": "bytes=0-0"}))
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception as e:  # noqa: BLE001
        return "EXC %r" % e


def main():
    final = url_final()
    print("CDN final:", final[:100], "...\n")
    pruebas = [
        ("solo UA chrome", {"User-Agent": UA}),
        ("solo UA apple", {"User-Agent": UA_APPLE}),
        ("UA chrome + Accept", {"User-Agent": UA, "Accept": "*/*"}),
        ("UA apple + Accept", {"User-Agent": UA_APPLE, "Accept": "*/*"}),
        ("UA chrome + Referer", {"User-Agent": UA, "Referer": "https://www.tiktok.com/"}),
        ("UA apple + Referer", {"User-Agent": UA_APPLE, "Referer": "https://www.tiktok.com/"}),
        ("UA apple + Accept + Referer",
         {"User-Agent": UA_APPLE, "Accept": "*/*", "Referer": "https://www.tiktok.com/"}),
        ("sin UA", {}),
    ]
    for nombre, cab in pruebas:
        print("  %-34s -> %s" % (nombre, codigo(final, cab)))


if __name__ == "__main__":
    main()
