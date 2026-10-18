# -*- coding: utf-8 -*-
"""
Igual que probar_video.py, pero con una sesion real: cookie jar, visita
previa a tiktok.com para recoger ttwid/msToken, y luego item/detail + CDN
con esas mismas cookies.  Imprime tambien el host de cada direccion, que es
la pista de por que unas dan 403 y otras no.
"""

import http.cookiejar
import json
import os
import sys
import urllib.request
import urllib.error
from urllib.parse import urlparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from probar import params_item_detalle, UA  # noqa: E402
from xgnarly import XGnarly  # noqa: E402


def main():
    item_id = sys.argv[1] if len(sys.argv) > 1 else "7106594312292453675"
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    hdr = {"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9",
           "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8"}

    def get(url, extra=None, limite=400000):
        h = dict(hdr)
        if extra:
            h.update(extra)
        req = urllib.request.Request(url, headers=h)
        try:
            with opener.open(req, timeout=40) as r:
                return r.status, r.read(limite), dict(r.headers)
        except urllib.error.HTTPError as e:
            return e.code, e.read(400), dict(e.headers)
        except Exception as e:  # noqa: BLE001
            return None, ("EXC %r" % (e,)).encode(), {}

    print("1) visita a tiktok.com (recoger cookies)")
    est, _, _ = get("https://www.tiktok.com/")
    print("   estado=%s cookies=%s" % (est, [(c.name, len(c.value)) for c in jar]))
    print()

    ms_token = next((c.value for c in jar if c.name == "msToken"), "")
    print("2) item/detail firmado (msToken cookie = %d chars)" % len(ms_token))
    firmado, _ = XGnarly(UA).sign(params_item_detalle(item_id), ms_token=ms_token)
    est, cuerpo, _ = get("https://www.tiktok.com/api/item/detail/?" + firmado,
                         {"Accept": "application/json, text/plain, */*",
                          "Referer": "https://www.tiktok.com/"})
    print("   estado=%s bytes=%d" % (est, len(cuerpo)))
    try:
        v = json.loads(cuerpo)["itemInfo"]["itemStruct"]["video"]
    except Exception as e:  # noqa: BLE001
        print("   no hay itemStruct:", e, cuerpo[:200])
        print("   cookies ahora:", [(c.name, len(c.value)) for c in jar])
        return
    print("   cookies ahora:", [(c.name, len(c.value)) for c in jar])
    print()

    cands = [("playAddr", v.get("playAddr")), ("downloadAddr", v.get("downloadAddr"))]
    for bi in (v.get("bitrateInfo") or []):
        if (bi.get("CodecType") or "").lower() == "h264":
            u = ((bi.get("PlayAddr") or {}).get("UrlList") or [None])[0]
            cands.append(("h264/" + str(bi.get("GearName")), u))
    print("3) hosts ==")
    for nota, u in cands:
        if u:
            print("   %-22s %s" % (nota, urlparse(u).netloc))
    print()

    print("4) descarga con cookies de la sesion")
    for nota, u in cands:
        if not u:
            continue
        for etiqueta, extra in [("con Referer", {"Referer": "https://www.tiktok.com/",
                                                 "Range": "bytes=0-262143"}),
                                ("sin Referer", {"Range": "bytes=0-262143"})]:
            est, datos, cab = get(u, extra)
            marca = "?"
            if est == 206 or est == 200:
                marca = "avc1=%s hvc1=%s" % (b"avc1" in datos, b"hvc1" in datos)
            print("   %-22s %-12s -> %s ct=%s cr=%s %s" % (
                nota, etiqueta, est, cab.get("Content-Type"), cab.get("Content-Range"), marca))
    print()


if __name__ == "__main__":
    main()
