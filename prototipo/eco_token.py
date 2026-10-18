# -*- coding: utf-8 -*-
"""
eco_token.py -- comprueba tres cosas que explicarian el fallo del telefono:

  A) Si a la busqueda se le manda un msToken cualquiera (no valido), TikTok
     devuelve en la cabecera x-ms-token EL MISMO que le mandaste (eco) o regala
     uno nuevo.  Si es un eco, el reintento de la app no sirve: aprende el mismo
     token malo y vuelve a fallar.

  B) Si el msToken hace falta tambien como COOKIE (no solo dentro de la firma).
     La app manda las cookies a mano y nunca guarda la cookie msToken, asi que
     este caso hay que descartarlo o confirmarlo.

  C) Lo mismo que A pero por HTTP/1.1, para ver si el eco depende del protocolo.

Uso:  python eco_token.py
"""

import os
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import json  # noqa: E402

import xgnarly as X  # noqa: E402
from probar_busqueda_navegador import CAPTURA, URL_BASE, dividir_crudo  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402

CAP = json.load(open(CAPTURA, encoding="utf-8-sig"))
UA = CAP["ua"]
PAL = "auron"
BASURA = "A" * 32 + "b" * 32 + "C" * 32 + "d" * 28   # 124 caracteres, inventado


def pares():
    return [(k, urllib.parse.quote(PAL, safe="") if k == "keyword" else v)
            for k, v in dividir_crudo(CAP["negocioRaw"])]


def identidad():
    """ttwid y un msToken bueno (regalado en una respuesta rechazada)."""
    s = cf.Session(http_version=CurlHttpVersion.V2_0)
    s.headers.update({"User-Agent": UA})
    s.get("https://www.tiktok.com/foryou", timeout=40)
    consulta, _ = X.XGnarly(UA).sign([("aid", "1988"), ("keyword", PAL)], ms_token="")
    r = s.get(URL_BASE + "?" + consulta, headers={"User-Agent": UA}, timeout=40)
    return dict(s.cookies).get("ttwid", ""), (r.headers.get("x-ms-token") or "")


def una_peticion(ttwid, ms, con_cookie_ms=False, cookie_ms="", etiqueta="", h2=True):
    s = cf.Session(http_version=CurlHttpVersion.V2_0 if h2 else CurlHttpVersion.V1_1)
    s.cookies.set("ttwid", ttwid, domain=".tiktok.com")
    if con_cookie_ms and cookie_ms:
        s.cookies.set("msToken", cookie_ms, domain=".tiktok.com")
    consulta, _ = X.XGnarly(UA).sign(pares(), ms_token=ms)
    r = s.get(URL_BASE + "?" + consulta, headers={"User-Agent": UA}, timeout=40)
    devuelto = r.headers.get("x-ms-token") or ""
    print("%-46s %s %8d B  orcas=%-3s  x-ms-token=%d car. %s" % (
        etiqueta, r.status_code, len(r.content),
        r.headers.get("tt_orcas_res", "-"), len(devuelto),
        ("== eco" if devuelto == ms and ms else ("nuevo" if devuelto else "sin cabecera"))))
    return r, devuelto


def main():
    ttwid, bueno = identidad()
    print("identidad: ttwid=%d car.  msToken bueno=%d car.\n" % (len(ttwid), len(bueno)))
    print("A) eco del token (HTTP/2)")
    una_peticion(ttwid, "", etiqueta="  h2  token vacio")
    una_peticion(ttwid, BASURA, etiqueta="  h2  token inventado")
    una_peticion(ttwid, bueno, etiqueta="  h2  token bueno (control)")
    r, devuelto = una_peticion(ttwid, BASURA, etiqueta="  h2  token inventado (2a vez)")

    print("\nB) hace falta la cookie msToken? (HTTP/2, solo cookie ttwid)")
    # token regalado en un rechazo, obtenido en una sesion APARTE (como hace la app)
    s2 = cf.Session(http_version=CurlHttpVersion.V2_0)
    s2.cookies.set("ttwid", ttwid, domain=".tiktok.com")
    consulta, _ = X.XGnarly(UA).sign(pares(), ms_token="")
    r2 = s2.get(URL_BASE + "?" + consulta, headers={"User-Agent": UA}, timeout=40)
    regalado = r2.headers.get("x-ms-token") or ""
    print("  token regalado en otra sesion: %d car." % len(regalado))
    una_peticion(ttwid, regalado, etiqueta="  h2  ttwid + token regalado, sin cookie ms")
    una_peticion(ttwid, regalado, con_cookie_ms=True, cookie_ms=regalado,
                 etiqueta="  h2  ttwid + token regalado + cookie ms")

    print("\nC) eco por HTTP/1.1")
    una_peticion(ttwid, BASURA, etiqueta="  h1  token inventado", h2=False)
    una_peticion(ttwid, bueno, etiqueta="  h1  token bueno", h2=False)


if __name__ == "__main__":
    main()
