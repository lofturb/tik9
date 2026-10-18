# -*- coding: utf-8 -*-
"""
feed_h1.py -- el feed "Para ti" funciona por HTTP/1.1?

Si el feed SI funciona por h1 y la busqueda NO, entonces el telefono (que carga
el feed pero no la busqueda) puede estar perfectamente hablando h1 -- que es lo
que apuntan las medidas.

Si el feed tambien exigiera h2, el telefono tendria que ir por h2 (carga el
feed), y el fallo de la busqueda seria otra cosa (por ejemplo la firma).

Uso:  python feed_h1.py
"""

import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xgnarly as X  # noqa: E402
from probar_busqueda_navegador import CAPTURA, dividir_crudo  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402

CAP = json.load(open(CAPTURA, encoding="utf-8-sig"))
UA = CAP["ua"]
FEED = "https://www.tiktok.com/api/recommend/item_list/"


def pares():
    return list(dividir_crudo(CAP["negocioRaw"])) + [("count", "6"), ("cursor", "0")]


def main():
    ttwid = ""
    consulta, _ = X.XGnarly(UA).sign(pares(), ms_token="")
    req = urllib.request.Request(FEED + "?" + consulta, headers={
        "User-Agent": UA, "Accept": "application/json, text/plain, */*",
        "Referer": "https://www.tiktok.com/"})
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            datos, est = r.read(), r.status
    except urllib.error.HTTPError as e:
        datos, est = e.read(), e.code
    print("h1 feed sin cookie       HTTP %s %8d B" % (est, len(datos)))

    # el mismo feed por h2, para comparar
    s = cf.Session(http_version=CurlHttpVersion.V2_0)
    s.headers.update({"User-Agent": UA})
    s.get("https://www.tiktok.com/foryou", timeout=40)
    ttwid = dict(s.cookies).get("ttwid", "")
    consulta, _ = X.XGnarly(UA).sign(pares(), ms_token="")
    r2 = s.get(FEED + "?" + consulta, headers={"User-Agent": UA}, timeout=40)
    print("h2 feed                  HTTP %s %8d B  orcas=%s" % (
        r2.status_code, len(r2.content), r2.headers.get("tt_orcas_res", "-")))

    # el feed por h1 con ttwid, por si le hiciera falta
    consulta, _ = X.XGnarly(UA).sign(pares(), ms_token="")
    req = urllib.request.Request(FEED + "?" + consulta, headers={
        "User-Agent": UA, "Accept": "application/json, text/plain, */*",
        "Referer": "https://www.tiktok.com/", "Cookie": "ttwid=" + ttwid})
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            datos, est = r.read(), r.status
    except urllib.error.HTTPError as e:
        datos, est = e.read(), e.code
    print("h1 feed con ttwid        HTTP %s %8d B" % (est, len(datos)))


if __name__ == "__main__":
    main()
