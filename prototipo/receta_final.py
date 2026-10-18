# -*- coding: utf-8 -*-
"""
receta_final.py -- fija la receta: identidad anonima (ttwid/tt_chain_token) +
msToken valido + (con huella de Chrome) y comprueba si la huella es necesaria.

Hipotesis a confirmar:
  1) ttwid + tt_chain_token  = identidad anonima; sin ella, status_code 2483
     ("inicia sesion primero")
  2) msToken valido           = pasa el WAF; sin el, 200 vacio + orcas
  3) huella TLS/HTTP2 de Chrome = ? (aqui se mide: urllib vs curl_cffi)

Uso:  python receta_final.py [palabra]

Requiere curl_cffi (para la huella TLS/HTTP2 de Chrome):
      python -m pip install "curl_cffi<0.8"
"""

import http.cookiejar
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

SALIDA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "search_respuesta.json")


def params(cap, pal):
    return [(k, urllib.parse.quote(pal, safe="") if k == "keyword" else v)
            for k, v in dividir_crudo(cap["negocioRaw"])]


def resumen(texto):
    try:
        j = json.loads(texto)
    except Exception:  # noqa: BLE001
        return "(no json)"
    return "status=%s data=%d msg=%s" % (j.get("status_code"), len(j.get("data") or []),
                                         (j.get("status_msg") or "")[:40])


def identidad_anonima(pal, ua):
    """Visita /search y devuelve (cookies, msToken) como un visitante anonimo."""
    s = cf.Session(impersonate="chrome")
    s.headers.update({"User-Agent": ua,
                      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                      "Accept-Language": "es-ES,es;q=0.9,en;q=0.8"})
    r = s.get("https://www.tiktok.com/search?q=%s" % urllib.parse.quote(pal), timeout=40)
    galletas = dict(s.cookies)
    ms = galletas.get("msToken", "")
    if not ms:
        # una peticion al API con msToken vacio devuelve uno nuevo en x-ms-token
        consulta, _ = X.XGnarly(ua).sign(params(cap_global, pal), ms_token="")
        rr = s.get(URL_BASE + "?" + consulta,
                   headers={"User-Agent": ua, "Accept": "application/json, text/plain, */*",
                            "Referer": "https://www.tiktok.com/search?q=%s" % urllib.parse.quote(pal)},
                   timeout=40)
        ms = rr.headers.get("x-ms-token") or ""
        print("  (msToken de una respuesta rechazada: %d car.)" % len(ms))
    return galletas, ms, r.status_code


def con_curl_cffi(pal, ua, galletas, ms, etiqueta, usar=("ttwid", "tt_chain_token", "msToken")):
    s = cf.Session(impersonate="chrome")
    for k in usar:
        if k in galletas:
            s.cookies.set(k, galletas[k], domain=".tiktok.com")
    consulta, _ = X.XGnarly(ua).sign(params(cap_global, pal), ms_token=ms)
    r = s.get(URL_BASE + "?" + consulta,
              headers={"User-Agent": ua, "Accept": "application/json, text/plain, */*",
                       "Referer": "https://www.tiktok.com/search?q=%s" % urllib.parse.quote(pal)},
              timeout=40)
    t = r.content.decode("utf-8", "replace")
    print("%-40s HTTP %s %8d B orcas=%-4s %s" % (
        etiqueta, r.status_code, len(r.content), r.headers.get("tt_orcas_res") or "-", resumen(t)))
    if len(r.content) > 1000:
        open(SALIDA, "w", encoding="utf-8").write(t)
        print("    guardado en %s" % os.path.basename(SALIDA))
    return r


def con_urllib(pal, ua, galletas, ms, etiqueta):
    pares = [(k, galletas.get(k, "")) for k in ("ttwid", "tt_chain_token", "msToken") if galletas.get(k)]
    consulta, _ = X.XGnarly(ua).sign(params(cap_global, pal), ms_token=ms)
    req = urllib.request.Request(URL_BASE + "?" + consulta, headers={
        "User-Agent": ua, "Accept": "application/json, text/plain, */*",
        "Referer": "https://www.tiktok.com/search?q=%s" % urllib.parse.quote(pal),
        "Cookie": "; ".join("%s=%s" % (k, v) for k, v in pares)})
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            datos, estado, orcas = r.read(), r.status, r.headers.get("tt_orcas_res")
    except urllib.error.HTTPError as e:
        datos, estado, orcas = e.read(), e.code, e.headers.get("tt_orcas_res")
    t = datos.decode("utf-8", "replace")
    print("%-40s HTTP %s %8d B orcas=%-4s %s" % (
        etiqueta, estado, len(datos), orcas or "-", resumen(t)))


cap_global = json.load(open(CAPTURA, encoding="utf-8-sig"))


def main():
    pal = sys.argv[1] if len(sys.argv) > 1 else "gatos"
    ua = cap_global["ua"]
    galletas, ms, estado = identidad_anonima(pal, ua)
    print("identidad anonima: pagina HTTP %s  cookies=%s  msToken=%d car." % (
        estado, ", ".join(sorted(galletas)), len(ms)))
    print()

    print("== con huella de Chrome (curl_cffi) ==")
    con_curl_cffi(pal, ua, galletas, ms, "ttwid+chain+msToken+msTokenCookie")
    con_curl_cffi(pal, ua, galletas, ms, "sin cookies (solo firma)", usar=())
    con_curl_cffi(pal, ua, galletas, ms, "solo ttwid", usar=("ttwid",))
    con_curl_cffi(pal, ua, galletas, ms, "solo tt_chain_token", usar=("tt_chain_token",))
    con_curl_cffi(pal, ua, galletas, ms, "cookies pero msToken vacio",
                  usar=("ttwid", "tt_chain_token")) if False else None
    # msToken vacio con cookies: re-firmar a mano
    s = cf.Session(impersonate="chrome")
    for k in ("ttwid", "tt_chain_token"):
        s.cookies.set(k, galletas[k], domain=".tiktok.com")
    consulta, _ = X.XGnarly(ua).sign(params(cap_global, pal), ms_token="")
    r = s.get(URL_BASE + "?" + consulta,
              headers={"User-Agent": ua, "Accept": "application/json, text/plain, */*",
                       "Referer": "https://www.tiktok.com/search?q=%s" % urllib.parse.quote(pal)},
              timeout=40)
    print("%-40s HTTP %s %8d B orcas=%-4s %s" % (
        "ttwid+chain, msToken vacio", r.status_code, len(r.content),
        r.headers.get("tt_orcas_res") or "-", resumen(r.content.decode("utf-8", "replace"))))

    print("\n== con urllib (Python estandar, HTTP/1.1) ==")
    con_urllib(pal, ua, galletas, ms, "urllib ttwid+chain+msToken")


if __name__ == "__main__":
    main()
