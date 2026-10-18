# -*- coding: utf-8 -*-
"""
http2_variantes.py -- con ttwid + msToken ya garantizados, mide que clientes
pasan: HTTP/2 generico (sin imitar navegador) y varias huellas de navegador.
Lo importante: si el HTTP/2 generico pasa, la app de iOS (NSURLSession, que
habla HTTP/2 desde iOS 9) tambien deberia pasar.

Uso:  python http2_variantes.py [palabra]

Requiere curl_cffi:
      python -m pip install "curl_cffi<0.8"
"""

import json
import os
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xgnarly as X  # noqa: E402
from probar_busqueda_navegador import CAPTURA, URL_BASE, dividir_crudo  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402

CAP = json.load(open(CAPTURA, encoding="utf-8-sig"))
UA = CAP["ua"]


def params(pal):
    return [(k, urllib.parse.quote(pal, safe="") if k == "keyword" else v)
            for k, v in dividir_crudo(CAP["negocioRaw"])]


def identidad(pal):
    s = cf.Session(impersonate="chrome")
    s.headers.update({"User-Agent": UA})
    s.get("https://www.tiktok.com/search?q=%s" % urllib.parse.quote(pal), timeout=40)
    g = dict(s.cookies)
    ms = g.get("msToken", "")
    if not ms:
        c, _ = X.XGnarly(UA).sign(params(pal), ms_token="")
        r = s.get(URL_BASE + "?" + c, headers={"User-Agent": UA}, timeout=40)
        ms = r.headers.get("x-ms-token") or ""
        g = dict(s.cookies)
    return g, ms


def probar(etq, pal, ttwid, ms, **opciones):
    try:
        s = cf.Session(**opciones)
    except Exception as e:  # noqa: BLE001
        print("%-42s NO EXISTE (%s)" % (etq, str(e)[:50]))
        return
    s.cookies.set("ttwid", ttwid, domain=".tiktok.com")
    consulta, _ = X.XGnarly(UA).sign(params(pal), ms_token=ms)
    try:
        r = s.get(URL_BASE + "?" + consulta, headers={
            "User-Agent": UA, "Accept": "application/json, text/plain, */*",
            "Referer": "https://www.tiktok.com/search?q=%s" % urllib.parse.quote(pal)},
            timeout=40)
    except Exception as e:  # noqa: BLE001
        print("%-42s ERROR %s" % (etq, str(e)[:60]))
        return
    t = r.content.decode("utf-8", "replace")
    n = -1
    msg = ""
    try:
        j = json.loads(t)
        n, msg = len(j.get("data") or []), (j.get("status_msg") or "")[:30]
    except Exception:  # noqa: BLE001
        pass
    print("%-42s HTTP %s %8d B orcas=%-4s data=%d %s" % (
        etq, r.status_code, len(r.content), r.headers.get("tt_orcas_res") or "-", n, msg))


def main():
    pal = sys.argv[1] if len(sys.argv) > 1 else "gatos"
    g, ms = identidad(pal)
    ttwid = g.get("ttwid", "")
    print("ttwid=%s...  msToken=%d car.\n" % (ttwid[:24], len(ms)))

    probar("http2 generico (sin imitar)", pal, ttwid, ms, http_version=CurlHttpVersion.V2_0)
    probar("http2 + http1.1 (control)", pal, ttwid, ms, http_version=CurlHttpVersion.V1_1)
    for nombre in ("safari15_3", "safari15_5", "safari17_0", "chrome99", "chrome116",
                   "chrome120", "chrome124", "edge101", "firefox133"):
        probar(nombre, pal, ttwid, ms, impersonate=nombre)


if __name__ == "__main__":
    main()
