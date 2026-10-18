# -*- coding: utf-8 -*-
"""
Flujo completo tal como lo hara la app, en orden:

  1. visitar /explore para recoger cookies (ttwid, tt_chain_token, csrf)
  2. firmar y pedir item/detail CON esas cookies
  3. reproducir la playAddr con las MISMAS cookies

Si el paso 3 da 206 y avc1, el camino web sirve y la app es autonoma.
"""

import http.cookiejar
import json
import os
import sys
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import params_item_detalle  # noqa: E402
from xgnarly import XGnarly  # noqa: E402

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36")


def main():
    item_id = sys.argv[1] if len(sys.argv) > 1 else "7106594312292453675"
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    def get(url, h, rango=None):
        hh = dict(h)
        if rango:
            hh["Range"] = rango
        req = urllib.request.Request(url, headers=hh)
        try:
            with opener.open(req, timeout=45) as r:
                return r.status, r.read(400000), dict(r.headers)
        except urllib.error.HTTPError as e:
            return e.code, e.read(400), dict(e.headers)
        except Exception as e:  # noqa: BLE001
            return None, ("EXC %r" % (e,)).encode(), {}

    nav = {"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9",
           "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"}
    api = {"User-Agent": UA, "Accept": "application/json, text/plain, */*",
           "Referer": "https://www.tiktok.com/"}

    print("1) /explore")
    est, _, _ = get("https://www.tiktok.com/explore", nav)
    print("   estado=%s cookies=%s" % (est, [(c.name, len(c.value)) for c in jar]))

    ms = next((c.value for c in jar if c.name == "msToken"), "")
    print("   msToken=%d chars" % len(ms))

    print("2) item/detail firmado (usa el jar)")
    firmado, _ = XGnarly(UA).sign(params_item_detalle(item_id), ms_token=ms)
    est, cuerpo, _ = get("https://www.tiktok.com/api/item/detail/?" + firmado, api)
    print("   estado=%s bytes=%d" % (est, len(cuerpo)))
    try:
        v = json.loads(cuerpo)["itemInfo"]["itemStruct"]["video"]
    except Exception as e:  # noqa: BLE001
        print("   sin itemStruct:", e, cuerpo[:200])
        return
    print("   cookies tras item/detail:", [(c.name, len(c.value)) for c in jar])
    print("   hosts:", v["playAddr"].split("/")[2])

    print("3) CDN con el jar completo")
    for nota, u in [("playAddr", v.get("playAddr")), ("downloadAddr", v.get("downloadAddr"))]:
        if not u:
            continue
        for etiqueta, extra in [("jar+Range+Referer", api), ("jar+Range", {"User-Agent": UA})]:
            est, datos, cab = get(u, extra, rango="bytes=0-262143")
            print("   %-13s %-18s -> %s ct=%s cr=%s avc1=%s hvc1=%s" % (
                nota, etiqueta, est, cab.get("Content-Type"), cab.get("Content-Range"),
                b"avc1" in datos, b"hvc1" in datos))


if __name__ == "__main__":
    main()
