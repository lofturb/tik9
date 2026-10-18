# -*- coding: utf-8 -*-
"""
Comprueba si el CDN acepta un msToken SIEMPRE que la firma y la cookie lo
lleven igual (es decir, si msToken se valida por coherencia o por su origen).
Si funcionara, no haria falta ejecutar el SDK de TikTok.
"""

import json
import os
import random
import string
import sys
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import params_item_detalle, UA, azar  # noqa: E402
from xgnarly import XGnarly  # noqa: E402


def get(url, h, rango=None):
    hh = dict(h)
    if rango:
        hh["Range"] = rango
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=hh), timeout=45) as r:
            return r.status, r.read(400000), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(400), dict(e.headers)
    except Exception as e:  # noqa: BLE001
        return None, ("EXC %r" % (e,)).encode(), {}


def main():
    item_id = sys.argv[1] if len(sys.argv) > 1 else "7106594312292453675"

    for etiqueta, ms in [
        ("msToken vacio (control)", ""),
        ("msToken falso 107 chars", "".join(random.choice(string.ascii_letters + string.digits + "-_") for _ in range(107))),
    ]:
        ttwid = azar(80)
        cookie = "ttwid=" + ttwid + ("; msToken=" + ms if ms else "")
        firmado, _ = XGnarly(UA).sign(params_item_detalle(item_id), ms_token=ms)
        est, cuerpo, _ = get("https://www.tiktok.com/api/item/detail/?" + firmado,
                             {"User-Agent": UA, "Accept": "application/json, text/plain, */*",
                              "Referer": "https://www.tiktok.com/", "Cookie": cookie})
        print("[%s]" % etiqueta)
        print("   item/detail -> estado=%s bytes=%d" % (est, len(cuerpo)))
        try:
            v = json.loads(cuerpo)["itemInfo"]["itemStruct"]["video"]
        except Exception:  # noqa: BLE001
            print("   sin itemStruct; fin de esta rama\n")
            continue
        u = v.get("playAddr")
        est2, datos, cab = get(u, {"User-Agent": UA, "Referer": "https://www.tiktok.com/",
                                   "Cookie": cookie}, rango="bytes=0-262143")
        print("   CDN -> estado=%s ct=%s cr=%s avc1=%s" % (
            est2, cab.get("Content-Type"), cab.get("Content-Range"), b"avc1" in datos))
        print()


if __name__ == "__main__":
    main()
