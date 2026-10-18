# -*- coding: utf-8 -*-
"""
firma_mala.py -- como responde TikTok cuando la FIRMA esta mal, comparado con el
rechazo por HTTP/1.1 (200, 0 B, tt_orcas_res: 1).

Sirve para saber si el fallo del telefono (0 B + orcas, con ttwid y msToken) es
"firma invalida" o "protocolo".  Si las dos cosas dan respuestas distintas, la
respuesta del telefono ya dice cual es.

Uso:  python firma_mala.py
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
PAL = "auron"
FEED = "https://www.tiktok.com/api/recommend/item_list/"


def pares_busqueda():
    return [(k, urllib.parse.quote(PAL, safe="") if k == "keyword" else v)
            for k, v in dividir_crudo(CAP["negocioRaw"])] + [
        ("count", "12"), ("offset", "0"), ("is_filter_search", "0"),
        ("query_correct_type", "1"), ("search_source", "normal_search"),
        ("keyword", PAL)]


def pares_feed(extra=False):
    p = list(dividir_crudo(CAP["negocioRaw"]))
    p += [("count", "6"), ("cursor", "0")]
    if extra:   # el feed con los parametros de la busqueda encima
        p += [("is_filter_search", "0"), ("query_correct_type", "1"),
              ("search_source", "normal_search"), ("keyword", PAL)]
    return p


def sesion(ttwid):
    s = cf.Session(http_version=CurlHttpVersion.V2_0)
    s.cookies.set("ttwid", ttwid, domain=".tiktok.com")
    return s


def identidad():
    s = cf.Session(http_version=CurlHttpVersion.V2_0)
    s.headers.update({"User-Agent": UA})
    s.get("https://www.tiktok.com/foryou", timeout=40)
    c, _ = X.XGnarly(UA).sign([("aid", "1988")], ms_token="")
    r = s.get(URL_BASE + "?" + c, headers={"User-Agent": UA}, timeout=40)
    return dict(s.cookies).get("ttwid", ""), (r.headers.get("x-ms-token") or "")


def ensena(nombre, r):
    orcas = r.headers.get("tt_orcas_res", "-")
    pista = ""
    if 0 < len(r.content) < 400:
        pista = r.content.decode("utf-8", "replace")[:120]
    print("%-52s HTTP %s %8d B  orcas=%-3s %s" % (nombre, r.status_code,
                                                  len(r.content), orcas, pista))


def romper(consulta):
    """Rompe la firma sellada (X-Dynosaur) sin tocar el resto."""
    trozos = consulta.split("&")
    fuera = []
    for t in trozos:
        if t.startswith("X-Dynosaur=") and len(t) > 40:
            v = t.split("=", 1)[1]
            t = "X-Dynosaur=" + v[:-6] + "AAAAAA"
        fuera.append(t)
    return "&".join(fuera)


def main():
    ttwid, ms = identidad()
    print("ttwid=%d car.  msToken=%d car.\n" % (len(ttwid), len(ms)))

    s = sesion(ttwid)
    print("--- con la firma correcta ---")
    c, _ = X.XGnarly(UA).sign(pares_feed(), ms_token=ms)
    ensena("feed (16 params)", s.get(FEED + "?" + c, headers={"User-Agent": UA}, timeout=40))
    c, _ = X.XGnarly(UA).sign(pares_busqueda(), ms_token=ms)
    ensena("busqueda (20 params)",
           s.get(URL_BASE + "?" + c, headers={"User-Agent": UA}, timeout=40))

    print("\n--- con la firma ROTA (X-Dynosaur cambiado) ---")
    c, _ = X.XGnarly(UA).sign(pares_feed(), ms_token=ms)
    ensena("feed (16 params)", s.get(FEED + "?" + romper(c), headers={"User-Agent": UA}, timeout=40))
    c, _ = X.XGnarly(UA).sign(pares_busqueda(), ms_token=ms)
    ensena("busqueda (20 params)",
           s.get(URL_BASE + "?" + romper(c), headers={"User-Agent": UA}, timeout=40))

    print("\n--- el feed con 20 params (firma correcta) ---")
    c, _ = X.XGnarly(UA).sign(pares_feed(extra=True), ms_token=ms)
    ensena("feed con los 4 params de la busqueda",
           s.get(FEED + "?" + c, headers={"User-Agent": UA}, timeout=40))

    print("\n--- la ruta de busqueda con 16 params (sin los de busqueda) ---")
    c, _ = X.XGnarly(UA).sign(pares_feed(), ms_token=ms)
    ensena("busqueda con params de feed",
           s.get(URL_BASE + "?" + c, headers={"User-Agent": UA}, timeout=40))

    print("\n--- HTTP/1.1 con firma correcta (control del rechazo de siempre) ---")
    c, _ = X.XGnarly(UA).sign(pares_busqueda(), ms_token=ms)
    s1 = cf.Session(http_version=CurlHttpVersion.V1_1)
    s1.cookies.set("ttwid", ttwid, domain=".tiktok.com")
    ensena("h1 busqueda", s1.get(URL_BASE + "?" + c, headers={"User-Agent": UA}, timeout=40))


if __name__ == "__main__":
    main()
