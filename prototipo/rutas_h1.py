# -*- coding: utf-8 -*-
"""
rutas_h1.py -- busca una ruta de busqueda que responda por HTTP/1.1.

La ruta de siempre (/api/search/general/full/) exige HTTP/2: con HTTP/1.1
devuelve 200 con el cuerpo vacio y tt_orcas_res: 1, aunque lleve ttwid y un
msToken valido.  Si el telefono esta hablando HTTP/1.1 (que es lo que apuntan
las medidas), hace falta una ruta que acepte HTTP/1.1 -- o confirmar que no hay
ninguna.

Uso:  python rutas_h1.py
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xgnarly as X  # noqa: E402
from probar_busqueda_navegador import CAPTURA, dividir_crudo  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402

CAP = json.load(open(CAPTURA, encoding="utf-8-sig"))
UA = CAP["ua"]
UA_MOVIL = ("Mozilla/5.0 (iPhone; CPU iPhone OS 9_3_5 like Mac OS X) "
            "AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13G36 Safari/601.1")
PAL = "auron"


def negocio(extra=None):
    pares = [(k, v) for k, v in dividir_crudo(CAP["negocioRaw"])]
    pares += [("count", "12"), ("offset", "0"), ("is_filter_search", "0"),
              ("query_correct_type", "1"), ("search_source", "normal_search"),
              ("keyword", urllib.parse.quote(PAL, safe=""))]
    if extra:
        pares += extra
    return pares


def identidad():
    s = cf.Session(http_version=CurlHttpVersion.V2_0)
    s.headers.update({"User-Agent": UA})
    s.get("https://www.tiktok.com/foryou", timeout=40)
    consulta, _ = X.XGnarly(UA).sign([("aid", "1988"), ("keyword", PAL)], ms_token="")
    r = s.get("https://www.tiktok.com/api/search/general/full/?" + consulta,
              headers={"User-Agent": UA}, timeout=40)
    return dict(s.cookies).get("ttwid", ""), (r.headers.get("x-ms-token") or "")


def por_h1(nombre, url, ms, ttwid, ua):
    consulta, _ = X.XGnarly(ua).sign(negocio(), ms_token=ms)
    sep = "&" if "?" in url else "?"
    req = urllib.request.Request(url + sep + consulta, headers={
        "User-Agent": ua, "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9", "Referer": "https://www.tiktok.com/",
        "Cookie": "ttwid=" + ttwid})
    try:
        with urllib.request.urlopen(req, timeout=40) as rr:
            datos, est = rr.read(), rr.status
    except urllib.error.HTTPError as e:
        datos, est = e.read(), e.code
    except Exception as e:  # noqa: BLE001
        print("%-56s ERROR %s" % (nombre, e))
        return
    pista = ""
    try:
        j = json.loads(datos.decode("utf-8", "replace") or "{}")
        if isinstance(j, dict):
            pista = "status=%s data=%s" % (j.get("status_code"),
                                           len(j.get("data") or []) if isinstance(
                                               j.get("data"), list) else j.get("status_msg", ""))
    except ValueError:
        pista = datos[:40].decode("utf-8", "replace")
    print("%-56s HTTP %s %8d B  %s" % (nombre, est, len(datos), pista))


def por_h2(nombre, url, ms, ttwid, ua):
    s = cf.Session(http_version=CurlHttpVersion.V2_0)
    s.cookies.set("ttwid", ttwid, domain=".tiktok.com")
    consulta, _ = X.XGnarly(ua).sign(negocio(), ms_token=ms)
    r = s.get(url + "?" + consulta, headers={"User-Agent": ua}, timeout=40)
    print("%-56s HTTP %s %8d B  orcas=%s" % (nombre, r.status_code, len(r.content),
                                             r.headers.get("tt_orcas_res", "-")))


def main():
    ttwid, ms = identidad()
    print("ttwid=%d car.  msToken=%d car.\n" % (len(ttwid), len(ms)))
    print("=== por HTTP/1.1 (urllib) ===")
    for nombre, url in [
        ("/api/search/general/full/ (la de siempre)", "https://www.tiktok.com/api/search/general/full/"),
        ("/api/search/item/full/", "https://www.tiktok.com/api/search/item/full/"),
        ("/api/search/general/single/", "https://www.tiktok.com/api/search/general/single/"),
        ("/api/search/video/full/", "https://www.tiktok.com/api/search/video/full/"),
        ("/api/search/general/full/ (movil)", "https://www.tiktok.com/api/search/general/full/"),
        ("m.tiktok.com/api/search/general/full/", "https://m.tiktok.com/api/search/general/full/"),
    ]:
        ua = UA_MOVIL if "movil" in nombre else UA
        extra = [("device_platform", "web_mobile"), ("os", "ios")] if "movil" in nombre else None
        # negocio() ya esta armado; para el movil se firma con los extras dentro
        consulta, _ = X.XGnarly(ua).sign(negocio(extra), ms_token=ms)
        sep = "&" if "?" in url else "?"
        req = urllib.request.Request(url + sep + consulta, headers={
            "User-Agent": ua, "Accept": "application/json, text/plain, */*",
            "Referer": "https://www.tiktok.com/", "Cookie": "ttwid=" + ttwid})
        try:
            with urllib.request.urlopen(req, timeout=40) as rr:
                datos, est = rr.read(), rr.status
        except urllib.error.HTTPError as e:
            datos, est = e.read(), e.code
        except Exception as e:  # noqa: BLE001
            print("%-56s ERROR %s" % (nombre, e))
            continue
        pista = ""
        try:
            j = json.loads(datos.decode("utf-8", "replace") or "{}")
            if isinstance(j, dict):
                d = j.get("data")
                pista = "status=%s data=%s %s" % (j.get("status_code"),
                                                  len(d) if isinstance(d, list) else "-",
                                                  j.get("status_msg", ""))
        except ValueError:
            pista = datos[:40].decode("utf-8", "replace")
        print("%-56s HTTP %s %8d B  %s" % (nombre, est, len(datos), pista))

    print("\n=== por HTTP/2 (referencia) ===")
    por_h2("/api/search/general/full/", "https://www.tiktok.com/api/search/general/full/",
           ms, ttwid, UA)
    por_h2("/api/search/item/full/", "https://www.tiktok.com/api/search/item/full/",
           ms, ttwid, UA)
    por_h2("/api/search/general/single/", "https://www.tiktok.com/api/search/general/single/",
           ms, ttwid, UA)


if __name__ == "__main__":
    main()
