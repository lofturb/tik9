# -*- coding: utf-8 -*-
"""
longitud_token.py -- en busca de una senal que distinga HTTP/1.1 de HTTP/2 en
la respuesta RECHAZADA de la busqueda (200, 0 B, tt_orcas_res: 1).

La duda: en el telefono la busqueda da ese rechazo con ttwid y msToken, que es
lo que le pasa a HTTP/1.1.  Si las respuestas de rechazo de h1 y h2 se
diferencian en algo medible (por ejemplo la longitud del msToken que regalan, o
alguna cabecera), el informe del telefono puede decir el protocolo.

Uso:  python longitud_token.py
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xgnarly as X  # noqa: E402
from probar_busqueda_navegador import CAPTURA, URL_BASE, dividir_crudo  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402

CAP = json.load(open(CAPTURA, encoding="utf-8-sig"))
UA = CAP["ua"]
PAL = "auron"


def pares():
    return [(k, urllib.parse.quote(PAL, safe="") if k == "keyword" else v)
            for k, v in dividir_crudo(CAP["negocioRaw"])]


def identidad():
    """Una sesion h2 con ttwid y un msToken valido (el de una respuesta rechazada)."""
    s = cf.Session(http_version=CurlHttpVersion.V2_0)
    s.headers.update({"User-Agent": UA})
    s.get("https://www.tiktok.com/foryou", timeout=40)
    consulta, _ = X.XGnarly(UA).sign([("aid", "1988"), ("keyword", PAL)], ms_token="")
    r = s.get(URL_BASE + "?" + consulta, headers={"User-Agent": UA}, timeout=40)
    ttwid = dict(s.cookies).get("ttwid", "")
    return ttwid, r.headers.get("x-ms-token") or ""


def describir(etiqueta, r, con_bytes):
    cabeceras = {k.lower(): v for k, v in r.headers.items()}
    token = cabeceras.get("x-ms-token", "")
    cookies = cabeceras.get("set-cookie", "")
    ms_cookie = ""
    if "msToken=" in cookies:
        ms_cookie = cookies.split("msToken=")[1].split(";")[0]
    print("%-34s %s %8s B  orcas=%-4s  x-ms-token=%d car.  msToken(cookie)=%d car." % (
        etiqueta, r.status_code, con_bytes, cabeceras.get("tt_orcas_res", "-"),
        len(token), len(ms_cookie)))
    return cabeceras, token


def main():
    ttwid, ms_bueno = identidad()
    print("identidad: ttwid=%d car.  msToken valido=%d car.\n" % (len(ttwid), len(ms_bueno)))

    # 1) la busqueda BUENA por h2 (control): tiene que traer datos
    s = cf.Session(http_version=CurlHttpVersion.V2_0)
    s.cookies.set("ttwid", ttwid, domain=".tiktok.com")
    consulta, _ = X.XGnarly(UA).sign(pares(), ms_token=ms_bueno)
    r = s.get(URL_BASE + "?" + consulta, headers={"User-Agent": UA}, timeout=40)
    describir("h2  ttwid + msToken bueno", r, len(r.content))

    # 2) RECHAZO por h2: ttwid y msToken vacio
    s2 = cf.Session(http_version=CurlHttpVersion.V2_0)
    s2.cookies.set("ttwid", ttwid, domain=".tiktok.com")
    consulta, _ = X.XGnarly(UA).sign(pares(), ms_token="")
    r2 = s2.get(URL_BASE + "?" + consulta, headers={"User-Agent": UA}, timeout=40)
    cab2, tok2 = describir("h2  ttwid + msToken VACIO", r2, len(r2.content))

    # 3) RECHAZO por h1: el mismo caso con urllib
    consulta, _ = X.XGnarly(UA).sign(pares(), ms_token="")
    req = urllib.request.Request(URL_BASE + "?" + consulta, headers={
        "User-Agent": UA, "Accept": "application/json, text/plain, */*",
        "Cookie": "ttwid=" + ttwid})
    try:
        with urllib.request.urlopen(req, timeout=40) as rr:
            datos, cab1 = rr.read(), {k.lower(): v for k, v in rr.headers.items()}
            est = rr.status
    except urllib.error.HTTPError as e:
        datos, cab1, est = e.read(), {k.lower(): v for k, v in e.headers.items()}, e.code

    class Falso:
        status_code = est
        headers = cab1
    describir("h1  ttwid + msToken VACIO", Falso, len(datos))

    # 4) Y con el msToken bueno por h1 (para ver si h1 lo rechaza igual)
    consulta, _ = X.XGnarly(UA).sign(pares(), ms_token=ms_bueno)
    req = urllib.request.Request(URL_BASE + "?" + consulta, headers={
        "User-Agent": UA, "Accept": "application/json, text/plain, */*",
        "Cookie": "ttwid=" + ttwid})
    try:
        with urllib.request.urlopen(req, timeout=40) as rr:
            datos, cab3 = rr.read(), {k.lower(): v for k, v in rr.headers.items()}
            est = rr.status
    except urllib.error.HTTPError as e:
        datos, cab3, est = e.read(), {k.lower(): v for k, v in e.headers.items()}, e.code
    Falso.status_code, Falso.headers = est, cab3
    describir("h1  ttwid + msToken BUENO", Falso, len(datos))

    # 5) diferencias de cabeceras entre el rechazo de h2 y el de h1
    print("\ncabeceras del rechazo:")
    for clave in sorted(set(cab2) | set(cab1)):
        a = str(cab2.get(clave, "-"))[:60]
        b = str(cab1.get(clave, "-"))[:60]
        marca = "  <-- DISTINTA" if a != b else ""
        print("  %-22s h2=%-42s h1=%s%s" % (clave, a, b, marca))


if __name__ == "__main__":
    main()
