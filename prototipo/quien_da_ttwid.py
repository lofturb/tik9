# -*- coding: utf-8 -*-
"""
quien_da_ttwid.py -- que peticion entrega la cookie ttwid (la identidad anonima
que search necesita).  Si la da el feed, la app ya la recibe gratis.

Uso:  python quien_da_ttwid.py
"""

import json
import os
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xgnarly as X  # noqa: E402
from probar_busqueda_navegador import CAPTURA, URL_BASE, dividir_crudo  # noqa: E402
from probar_listas import params_recomendados  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402

CAP = json.load(open(CAPTURA, encoding="utf-8-sig"))
UA = CAP["ua"]


def cookies(r, s):
    puestas = [v.split(";")[0].split("=")[0] for k, v in r.headers.multi_items()
               if k.lower() == "set-cookie"] if hasattr(r.headers, "multi_items") else []
    return puestas, ", ".join(sorted(s.cookies.keys())) or "(ninguna)"


def main():
    objetivos = [
        ("portada", "https://www.tiktok.com/"),
        ("explore", "https://www.tiktok.com/explore"),
        ("search html", "https://www.tiktok.com/search?q=gatos"),
        ("foryou", "https://www.tiktok.com/foryou"),
        ("tag", "https://www.tiktok.com/tag/gatos"),
    ]
    for nombre, url in objetivos:
        s = cf.Session(http_version=CurlHttpVersion.V2_0)
        s.headers.update({"User-Agent": UA})
        try:
            r = s.get(url, timeout=40)
        except Exception as e:  # noqa: BLE001
            print("%-12s ERROR %s" % (nombre, str(e)[:50]))
            continue
        puestas, todas = cookies(r, s)
        print("%-12s HTTP %s  %7d B  Set-Cookie=%s  jar=%s" % (
            nombre, r.status_code, len(r.content), puestas, todas))

    # el feed, que la app ya pide
    s = cf.Session(http_version=CurlHttpVersion.V2_0)
    s.headers.update({"User-Agent": UA})
    consulta, _ = X.XGnarly(UA).sign(params_recomendados(), ms_token="")
    r = s.get("https://www.tiktok.com/api/recommend/item_list/?" + consulta,
              headers={"Accept": "application/json, text/plain, */*",
                       "Referer": "https://www.tiktok.com/"}, timeout=40)
    puestas, todas = cookies(r, s)
    print("%-12s HTTP %s  %7d B  Set-Cookie=%s  jar=%s" % (
        "feed api", r.status_code, len(r.content), puestas, todas))


if __name__ == "__main__":
    main()
