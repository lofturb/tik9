# -*- coding: utf-8 -*-
"""Prueba el relay local: /api/health, /api/stream y /api/video (con Range).
Saca una direccion firmada real del feed y comprueba que el relay la resuelve y
sirve bytes.

Uso:  python prototipo/probar_relay.py [http://127.0.0.1:8791]
"""

import json
import os
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import peticion  # noqa: E402
from probar_listas import params_recomendados  # noqa: E402

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8791"


def firmada():
    _, cuerpo, _, _ = peticion("/api/recommend/item_list/", params_recomendados())
    j = json.loads(cuerpo)
    it = (j.get("itemList") or [])[0]
    v = it.get("video") or {}
    for b in v.get("bitrateInfo") or []:
        for u in ((b.get("PlayAddr") or {}).get("UrlList") or []):
            if "/aweme/v1/play/" in u:
                return it.get("id"), u
    return None, None


def get(url, rango=None):
    req = urllib.request.Request(url)
    if rango:
        req.add_header("Range", rango)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.getcode(), dict(r.headers), r.read(2048)


def main():
    print("relay:", BASE)
    cod, cab, cuerpo = get(BASE + "/api/health")
    print("health -> %s %s" % (cod, cuerpo[:160].decode("utf-8", "replace")))

    item_id, u = firmada()
    print("\nitem:", item_id)
    print("firmada:", u[:100], "...")

    q = urllib.parse.urlencode({"id": item_id or "", "u": u})
    cod, cab, cuerpo = get(BASE + "/api/stream?" + q)
    print("\nstream -> %s" % cod)
    datos = json.loads(cuerpo.decode("utf-8", "replace"))
    print(json.dumps(datos, indent=2, ensure_ascii=False)[:700])

    if not datos.get("ok"):
        return
    proxy = datos["url_proxy"]
    print("\nURL del proxy:", proxy[:120], "...")

    cod, cab, cuerpo = get(proxy, rango="bytes=0-2047")
    print("\nvideo (Range 0-2047) -> %s" % cod)
    print("   tipo=%s content-range=%s" % (cab.get("Content-Type"),
                                            cab.get("Content-Range")))
    print("   primeros bytes: %r" % cuerpo[:16])


if __name__ == "__main__":
    main()
