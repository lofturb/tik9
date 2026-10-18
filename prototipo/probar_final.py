# -*- coding: utf-8 -*-
"""Confirma que la URL FINAL tras el redirect (v16-web-newkey) sirve el MP4 por
si sola con UA+Referer, y que el sondeo con Range: bytes=0-0 la descubre.

Uso:  python prototipo/probar_final.py
"""

import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import peticion, UA  # noqa: E402
from probar_listas import params_recomendados  # noqa: E402

CAB = {"User-Agent": UA, "Referer": "https://www.tiktok.com/",
       "Accept": "video/mp4,video/*;q=0.9,*/*;q=0.8"}


def aweme_url_del_feed():
    _, cuerpo, _, _ = peticion("/api/recommend/item_list/", params_recomendados())
    import json
    j = json.loads(cuerpo)
    it = (j.get("itemList") or [])[0]
    v = it.get("video") or {}
    for b in v.get("bitrateInfo") or []:
        for u in ((b.get("PlayAddr") or {}).get("UrlList") or []):
            if "/aweme/v1/play/" in u:
                return it.get("id"), u
    return None, None


def get(url, extra=None):
    cab = dict(CAB)
    if extra:
        cab.update(extra)
    req = urllib.request.Request(url, headers=cab)
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            leer = r.read(64)
            return r.status, r.geturl(), dict(r.headers), leer
    except urllib.error.HTTPError as e:
        return e.code, url, dict(e.headers), b""
    except Exception as e:  # noqa: BLE001
        return None, url, {}, ("EXC %r" % e).encode()


def main():
    item_id, aweme = aweme_url_del_feed()
    print("item:", item_id)
    print("aweme:", aweme[:120], "...\n")

    # 1) sondeo tipo app: Range 0-0 -> descubre la URL final
    est, final, cab, _ = get(aweme, {"Range": "bytes=0-0"})
    print("1) aweme + Range 0-0      -> %s" % est)
    print("   final: %s" % final[:150])
    print("   tipo=%s len=%s ranges=%s" % (cab.get("Content-Type"),
                                            cab.get("Content-Length"),
                                            cab.get("Accept-Ranges")))

    if est not in (200, 206):
        print("   el sondeo no dio 200/206; se corta")
        return

    # 2) la URL final por si sola
    est2, _, cab2, leer2 = get(final)
    print("\n2) URL final (sin Range)  -> %s  tipo=%s len=%s" % (
        est2, cab2.get("Content-Type"), cab2.get("Content-Length")))
    print("   primeros bytes: %r" % leer2[:16])

    # 3) la URL final con Range como hace AVPlayer
    est3, _, cab3, _ = get(final, {"Range": "bytes=0-65535"})
    print("\n3) URL final + Range 64K  -> %s  content-range=%s" % (
        est3, cab3.get("Content-Range")))

    # 4) la URL final SIN Referer (por si AVPlayer lo pierde)
    est4, _, _, _ = get(final, {})  # CAB ya lleva referer; probamos sin el
    cab4 = {"User-Agent": UA}
    req = urllib.request.Request(final, headers=cab4)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            est4 = r.status
    except urllib.error.HTTPError as e:
        est4 = e.code
    except Exception as e:  # noqa: BLE001
        est4 = "EXC %r" % e
    print("\n4) URL final solo con UA   -> %s" % est4)


if __name__ == "__main__":
    main()
