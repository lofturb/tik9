# -*- coding: utf-8 -*-
"""
Intenta obtener cookies reales (ttwid, msToken) por HTTP puro, que es lo que
le falta a la URL del CDN.  Prueba varias puertas y muestra los Set-Cookie.
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

NAV = {
    "User-Agent": UA,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "sec-ch-ua": '"Chromium";v="122", "Not(A:Brand";v="24", "Google Chrome";v="122"',
    "sec-ch-ua-mobile": "?0",
    "sec-ch-ua-platform": '"Windows"',
    "sec-fetch-dest": "document",
    "sec-fetch-mode": "navigate",
    "sec-fetch-site": "none",
    "sec-fetch-user": "?1",
    "upgrade-insecure-requests": "1",
}


def main():
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    def get(url, h, metodo="GET", datos=None):
        req = urllib.request.Request(url, headers=h, method=metodo, data=datos)
        try:
            with opener.open(req, timeout=40) as r:
                return r.status, r.read(200000), r.headers.get_all("Set-Cookie") or []
        except urllib.error.HTTPError as e:
            return e.code, e.read(500), e.headers.get_all("Set-Cookie") or []
        except Exception as e:  # noqa: BLE001
            return None, ("EXC %r" % (e,)).encode(), []

    puertas = [
        ("home", "https://www.tiktok.com/"),
        ("explore", "https://www.tiktok.com/explore"),
        ("ttwid register", "https://ttwid.bytedance.com/ttwid/union/register/"),
        ("mssdk config", "https://mssdk.bytedance.com/web/login/setting/v1?aid=1988"),
    ]
    for nombre, url in puertas:
        est, cuerpo, sc = get(url, NAV)
        print("[%s] estado=%s bytes=%d" % (nombre, est, len(cuerpo)))
        for c in sc:
            print("    Set-Cookie:", c[:140])
        print("    cookies jar ahora:", [(c.name, len(c.value), c.domain) for c in jar])
        print()

    ms = next((c.value for c in jar if c.name == "msToken"), "")
    print("msToken obtenido: %d caracteres" % len(ms))
    if ms:
        firmado, _ = XGnarly(UA).sign(params_item_detalle("7106594312292453675"), ms_token=ms)
        est, cuerpo, _ = get("https://www.tiktok.com/api/item/detail/?" + firmado,
                             dict(NAV, Accept="application/json, text/plain, */*",
                                  **{"Referer": "https://www.tiktok.com/"}))
        print("item/detail con msToken real: estado=%s bytes=%d" % (est, len(cuerpo)))
        try:
            v = json.loads(cuerpo)["itemInfo"]["itemStruct"]["video"]
            u = v.get("playAddr")
            print("playAddr host:", u.split("/")[2] if u else None)
            cab = dict(NAV, Range="bytes=0-262143", **{"Referer": "https://www.tiktok.com/"})
            est2, datos, _ = get(u, cab)
            print("CDN con cookies reales: estado=%s bytes=%d avc1=%s" % (
                est2, len(datos), b"avc1" in datos))
        except Exception as e:  # noqa: BLE001
            print("  sin itemStruct:", e, cuerpo[:200])


if __name__ == "__main__":
    main()
