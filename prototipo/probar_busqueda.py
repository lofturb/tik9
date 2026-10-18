# -*- coding: utf-8 -*-
"""
probar_busqueda.py -- intenta abrir la busqueda de TikTok sin ser la app oficial.

En el navegador la busqueda funciona SIN iniciar sesion.  La diferencia entre el
navegador y esta peticion solo puede estar en una de estas tres cosas, y aqui se
prueban por separado para no quedarse en "no se puede":

  A) las COOKIES de sesion (ttwid / tt_chain_token, que si se consiguen por HTTP
     puro entrando en /explore), o
  B) el X-Bogus de verdad (el SDK web manda el literal "1", pero el X-Bogus
     calculado puede ser lo que valida esta ruta), o
  C) el juego COMPLETO de parametros que manda el navegador (webid, engine_name,
     pantalla, version de navegador...).

Se prueba la matriz entera y se dice, por cada combinacion, que contesta.

Uso:  python probar_busqueda.py [palabra]
"""

import http.cookiejar
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import device_id, UA  # noqa: E402
from xgnarly import XGnarly       # noqa: E402
from xbogus import XBogus         # noqa: E402

PAL = sys.argv[1] if len(sys.argv) > 1 else "gatos"
NAV = {
    "User-Agent": UA,
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://www.tiktok.com/",
}


def cookies_de_explore():
    """Entra en /explore como un navegador y devuelve 'a=b; c=d'."""
    jar = http.cookiejar.CookieJar()
    abridor = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    req = urllib.request.Request("https://www.tiktok.com/explore", headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        "sec-fetch-dest": "document", "sec-fetch-mode": "navigate",
        "sec-fetch-site": "none", "upgrade-insecure-requests": "1"})
    try:
        abridor.open(req, timeout=40).read(20000)
    except Exception:  # noqa: BLE001
        pass
    trozos = ["%s=%s" % (c.name, c.value) for c in jar]
    return "; ".join(trozos), {"ttwid": next((c.value for c in jar if c.name == "ttwid"), ""),
                               "tt_chain_token": next((c.value for c in jar if c.name == "tt_chain_token"), "")}


def params_base(extra):
    p = [("aid", "1988"), ("app_language", "en-US"), ("app_name", "tiktok_web"),
         ("browser_language", "en-US"), ("browser_name", "Mozilla"),
         ("browser_online", "true"), ("browser_platform", "Win32"),
         ("channel", "tiktok_web"), ("cookie_enabled", "true")]
    p += extra
    p += [("device_platform", "web_pc"), ("os", "windows"),
          ("region", "US"), ("tz_name", "America/New_York")]
    return p


def params_busqueda(completo=False):
    extra = [("device_id", device_id()), ("keyword", PAL)]
    if completo:
        extra = [
            ("WebIdLastTime", "1789000000"),
            ("abTestVersion", "{}"),
            ("browser_version", "5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                                "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"),
            ("cpu_core_num", "8"),
            ("device_memory", "8"),
            ("downlink", "10"),
            ("effective_type", "4g"),
            ("engine_name", "Blink"),
            ("engine_version", "122.0.0.0"),
            ("round_trip_time", "50"),
            ("from_group_id", ""),
            ("hot_search", "0"),
            ("is_filter_search", "0"),
            ("offset", "0"),
            ("count", "12"),
            ("query_correct_type", "1"),
            ("search_source", "tab_search"),
            ("screen_height", "1080"),
            ("screen_width", "1920"),
            ("webcast_language", "en-US"),
            ("webid", ""),
        ] + extra
    else:
        extra = extra + [("search_source", "normal_search")]
    return params_base(extra)


def firmar(params):
    """Devuelve (consulta firmada, trozo_business, trozo_dynosaur)."""
    firmado, _ = XGnarly(UA).sign(params, ms_token="")
    biz = firmado.split("&X-Dynosaur=")[0]
    resto = firmado.split("&X-Dynosaur=")[1]
    dynosaur = resto.split("&msToken=")[0]
    sin_bogus = firmado.replace("&X-Bogus=1", "", 1)          # biz+dynosaur+msToken
    sin_gnarly = sin_bogus.split("&X-Gnarly=")[0]
    return firmado, biz, dynosaur, sin_gnarly


def pide(url, cookie=""):
    cab = dict(NAV)
    if cookie:
        cab["Cookie"] = cookie
    req = urllib.request.Request(url, headers=cab)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, r.read().decode("utf-8", "replace"), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), dict(e.headers)
    except Exception as e:  # noqa: BLE001
        return None, "EXC %r" % (e,), {}


def resumen(cuerpo):
    if not cuerpo:
        return "cuerpo VACIO"
    try:
        j = json.loads(cuerpo)
    except Exception:  # noqa: BLE001
        return "no-JSON (%d B)" % len(cuerpo)
    n = 0
    for k, v in j.items():
        if isinstance(v, list):
            n += len(v)
        elif isinstance(v, dict):
            for vv in v.values():
                if isinstance(vv, list):
                    n += len(vv)
    msg = j.get("status_msg") or j.get("message") or ""
    return "elem=%d status_code=%s %s" % (n, j.get("status_code"), msg)


def main():
    print("palabra: %r\n" % PAL)
    galletas, sueltas = cookies_de_explore()
    print("cookies de /explore: ttwid=%d chars, tt_chain_token=%s chars, msToken=%s"
          % (len(sueltas["ttwid"]), len(sueltas["tt_chain_token"]),
             "SI" if "msToken=" in galletas else "NO (como estaba documentado)"))
    print()

    ruta = "/api/search/general/full/"
    for nombre, completo, usa_cookies, modo_bogus in [
        ("1) control (X-Bogus=1, sin cookies)",            False, False, "uno"),
        ("2) control + cookies de /explore",               False, True,  "uno"),
        ("3) X-Bogus real (sobre los parametros)",         False, False, "biz"),
        ("4) X-Bogus real + cookies",                      False, True,  "biz"),
        ("5) X-Bogus real (sobre biz+dynosaur+msToken) + cookies", False, True, "todo"),
        ("6) parametros completos del navegador + X-Bogus real + cookies", True, True, "biz"),
    ]:
        firmado, biz, dynosaur, sin_gnarly = firmar(params_busqueda(completo))
        if modo_bogus == "biz":
            xb = XBogus(user_agent=UA).getXBogus(biz)[1]
            consulta = firmado.replace("&X-Bogus=1", "&X-Bogus=" + xb, 1)
        elif modo_bogus == "todo":
            xb = XBogus(user_agent=UA).getXBogus(sin_gnarly)[1]
            consulta = firmado.replace("&X-Bogus=1", "&X-Bogus=" + xb, 1)
        else:
            consulta = firmado
        est, cuerpo, cab = pide("https://www.tiktok.com%s?%s" % (ruta, consulta),
                                galletas if usa_cookies else "")
        print("[%s]" % nombre)
        print("    estado=%s bytes=%d  tt_orcas_res=%s" % (
            est, len(cuerpo), cab.get("tt_orcas_res") or "-"))
        print("    %s\n" % resumen(cuerpo)[:150])

    print("(Y lo mismo en /api/search/item/full/, por si la ruta general fuera la cerrada)")
    firmado, biz, dynosaur, sin_gnarly = firmar(params_busqueda())
    xb = XBogus(user_agent=UA).getXBogus(biz)[1]
    consulta = firmado.replace("&X-Bogus=1", "&X-Bogus=" + xb, 1)
    est, cuerpo, cab = pide("https://www.tiktok.com/api/search/item/full/?" + consulta, galletas)
    print("    estado=%s bytes=%d orcas=%s  %s" % (est, len(cuerpo),
          cab.get("tt_orcas_res") or "-", resumen(cuerpo)[:120]))


if __name__ == "__main__":
    main()
