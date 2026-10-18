# -*- coding: utf-8 -*-
"""
confianza_app.py -- replicacion exacta de lo que hara la app: su UA, su juego
minimo de parametros, HTTP/2 generico y la identidad anonima + msToken.

Uso:  python confianza_app.py [palabra]

Requiere curl_cffi:
      python -m pip install "curl_cffi<0.8"
"""

import json
import os
import random
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xgnarly as X  # noqa: E402
from probar_busqueda_navegador import URL_BASE  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402

# el UA literal de app/TTSignaCore.h
UA_APP = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
          "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0")

DISPOSITIVO = "7" + "".join(random.choice("0123456789") for _ in range(18))


def pares_app(pal, cursor="0"):
    # el juego minimo que ya manda hoy la app (TTSesion paresBase + busqueda)
    return [
        ("aid", "1988"), ("app_language", "en-US"), ("app_name", "tiktok_web"),
        ("browser_language", "en-US"), ("browser_name", "Mozilla"),
        ("browser_online", "true"), ("browser_platform", "Win32"),
        ("channel", "tiktok_web"), ("cookie_enabled", "true"),
        ("device_id", DISPOSITIVO), ("device_platform", "web_pc"),
        ("os", "windows"), ("region", "US"), ("tz_name", "America/New_York"),
        ("count", "12"), ("cursor", cursor), ("offset", cursor),
        ("is_filter_search", "0"), ("query_correct_type", "1"),
        ("search_source", "normal_search"), ("keyword", pal),
    ]


def ver(etq, r):
    t = r.content.decode("utf-8", "replace")
    n, stat, msg = -1, "?", ""
    try:
        j = json.loads(t)
        n, stat, msg = len(j.get("data") or []), j.get("status_code"), (j.get("status_msg") or "")[:30]
    except Exception:  # noqa: BLE001
        pass
    print("%-44s HTTP %s %8d B orcas=%-4s status=%s data=%d %s" % (
        etq, r.status_code, len(r.content), r.headers.get("tt_orcas_res") or "-", stat, n, msg))
    return t


def main():
    pal = sys.argv[1] if len(sys.argv) > 1 else "gatos"
    s = cf.Session(http_version=CurlHttpVersion.V2_0)
    s.headers.update({"User-Agent": UA_APP})

    # 1) identidad anonima
    r = s.get("https://www.tiktok.com/foryou", timeout=40)
    g = dict(s.cookies)
    print("1) /foryou -> HTTP %s  cookies=%s  ttwid=%s..." % (
        r.status_code, ", ".join(sorted(g)), (g.get("ttwid") or "")[:20]))

    # 2) msToken: primero el que deje la sesion; si no hay, sondeo
    ms = g.get("msToken", "")
    if not ms:
        consulta, _ = X.XGnarly(UA_APP).sign([("aid", "1988"), ("keyword", pal)], ms_token="")
        r = s.get(URL_BASE + "?" + consulta, headers={"User-Agent": UA_APP}, timeout=40)
        ms = r.headers.get("x-ms-token") or ""
        print("2) sondeo -> HTTP %s  %d B  msToken=%d car." % (r.status_code, len(r.content), len(ms)))

    # 3) la busqueda, con el msToken sellado dentro
    for cursor in ("0", "12"):
        consulta, _ = X.XGnarly(UA_APP).sign(pares_app(pal, cursor), ms_token=ms)
        r = s.get(URL_BASE + "?" + consulta,
                  headers={"User-Agent": UA_APP,
                           "Accept": "application/json, text/plain, */*",
                           "Referer": "https://www.tiktok.com/"}, timeout=40)
        t = ver("3) busqueda cursor=%s" % cursor, r)
        if len(r.content) > 1000:
            j = json.loads(t)
            for d in (j.get("data") or [])[:4]:
                v = d.get("aweme_info") or {}
                au = (v.get("author") or {}).get("uniqueId", "?")
                print("      %s | %r | %s" % (au, (v.get("desc") or "")[:34],
                                               ((v.get("video") or {}).get("playAddr") or "")[:46]))


if __name__ == "__main__":
    main()
