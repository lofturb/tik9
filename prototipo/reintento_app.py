# -*- coding: utf-8 -*-
"""
reintento_app.py -- reproduce el reintento EXACTO de la app:

  1) primera busqueda con el msToken que ya tenia guardado (uno caducado),
  2) TikTok la rechaza (200, 0 B, orcas=1) y regala un msToken en x-ms-token,
  3) la app guarda ESE token y repite la busqueda.

La duda: el token que regalan en un rechazo provocado por un token malo, vale
para la repeticion?  En receta_final.py el token se pedia con un token VACIO.

Uso:  python reintento_app.py
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


def pares():
    return [(k, urllib.parse.quote(PAL, safe="") if k == "keyword" else v)
            for k, v in dividir_crudo(CAP["negocioRaw"])]


def sesion_h2(ttwid):
    s = cf.Session(http_version=CurlHttpVersion.V2_0)
    s.cookies.set("ttwid", ttwid, domain=".tiktok.com")
    return s


def buscar(s, ms, etiqueta):
    consulta, _ = X.XGnarly(UA).sign(pares(), ms_token=ms)
    r = s.get(URL_BASE + "?" + consulta, headers={"User-Agent": UA}, timeout=40)
    devuelto = r.headers.get("x-ms-token") or ""
    print("%-40s %s %8d B  orcas=%-3s  x-ms-token=%d car." % (
        etiqueta, r.status_code, len(r.content), r.headers.get("tt_orcas_res", "-"),
        len(devuelto)))
    return devuelto


def identidad():
    s = sesion_h2("")
    s.get("https://www.tiktok.com/foryou", timeout=40)
    ttwid = dict(s.cookies).get("ttwid", "")
    return ttwid


def main():
    ttwid = identidad()
    print("ttwid=%d car.\n" % len(ttwid))

    # --- el caso de la app: token guardado que ya no vale ---------------------
    # Un token caducado de verdad: uno que regalo TikTok hace rato.  Se imita con
    # uno inventado, que el servidor rechaza igual (orcas=1).
    caducado = "t" * 120

    s = sesion_h2(ttwid)
    print("CASO 1: el reintento de la app (token caducado -> token que regalan)")
    nuevo = buscar(s, caducado, "  intento 0 con el token caducado")
    buscar(s, nuevo, "  intento 1 con el token regalado")

    print("\nCASO 2: la receta que SI funciona (token vacio -> token que regalan)")
    s2 = sesion_h2(ttwid)
    nuevo2 = buscar(s2, "", "  intento 0 con token vacio")
    buscar(s2, nuevo2, "  intento 1 con el token regalado")

    print("\nCASO 3: el token se reutiliza en OTRA sesion (lo hace la app al "
          "reintentar con la sesion de la app, no la compartida)")
    s3 = sesion_h2(ttwid)
    buscar(s3, nuevo, "  otra sesion, mismo token regalado")

    print("\nCASO 4: token caducado pero SIN cabecera que regale nada "
          "(se quita el ttwid para ver el rechazo 2483)")
    s4 = cf.Session(http_version=CurlHttpVersion.V2_0)
    buscar(s4, caducado, "  sin ttwid, token caducado")


if __name__ == "__main__":
    main()
