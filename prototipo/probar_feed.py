# -*- coding: utf-8 -*-
"""
Comprueba si los itemStruct de /api/recommend/item_list/ (el feed "Para ti")
traen direcciones de video que se puedan descargar, o si son del host
protegido v16-webapp-prime como las de item/detail.
"""

import json
import os
import sys
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import peticion  # noqa: E402
from probar_listas import params_recomendados  # noqa: E402

UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 9_3_5 like Mac OS X) AppleWebKit/601.1.46 "
      "(KHTML, like Gecko) Version/9.0 Mobile/13G36 Safari/601.1")


def hosts_de(v):
    salida = []
    for nombre, u in (("playAddr", v.get("playAddr")), ("downloadAddr", v.get("downloadAddr"))):
        if u:
            salida.append((nombre, u.split("/")[2]))
    for i, br in enumerate(v.get("bit_rate") or []):
        ul = (br.get("play_addr") or {}).get("url_list") or []
        if ul:
            salida.append(("bit_rate[%d]/%s" % (i, br.get("gear_name")), ul[0].split("/")[2]))
    return salida


def probe(url):
    req = urllib.request.Request(url, headers={"Range": "bytes=0-262143", "User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            d = r.read()
        return "estado=%s ct=%s cr=%s bytes=%d avc1=%s hvc1=%s" % (
            r.status, r.headers.get("Content-Type"), r.headers.get("Content-Range"),
            len(d), b"avc1" in d, b"hvc1" in d)
    except urllib.error.HTTPError as e:
        return "HTTP %s" % e.code
    except Exception as e:  # noqa: BLE001
        return "EXC %r" % (e,)


def main():
    est, cuerpo, _, _ = peticion("/api/recommend/item_list/", params_recomendados())
    j = json.loads(cuerpo)
    items = j.get("itemList") or []
    print("items:", len(items))
    print()
    for it in items[:3]:
        v = it.get("video") or {}
        print("id=%s  autor=%s  %sx%s" % (
            it.get("id"), (it.get("author") or {}).get("uniqueId"),
            v.get("width"), v.get("height")))
        print("   calidades:", [(b.get("gear_name"), b.get("quality_type")) for b in (v.get("bit_rate") or [])][:5])
        for nombre, host in hosts_de(v):
            print("   %-24s %s" % (nombre, host))
        # probar la primera direccion disponible
        u = v.get("playAddr") or ((v.get("bit_rate") or [{}])[0].get("play_addr") or {}).get("url_list", [None])[0]
        if u:
            print("   PROBE playAddr ->", probe(u))
        print()


if __name__ == "__main__":
    main()
