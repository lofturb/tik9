# -*- coding: utf-8 -*-
"""
Prueba la URL firmada /aweme/v1/play/ que viene DENTRO del itemStruct
(la que usa la propia web).  Si resuelve sin cookies, la reproduccion directa
en la app es viable y el relay solo hace falta para el TLS de iOS 9.

Uso:  python prototipo/probar_play.py
"""

import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import peticion, UA  # noqa: E402
from probar_listas import params_recomendados  # noqa: E402

UA_MOVIL = ("com.zhiliaoapp.musically/2022600030 (Linux; U; Android 12; "
            "en_US; Pixel 4) Cronet/58.0.2991.0")


def urls_del_feed():
    est, cuerpo, _, _ = peticion("/api/recommend/item_list/", params_recomendados())
    print("feed: estado=%s bytes=%d" % (est, len(cuerpo)))
    j = json.loads(cuerpo)
    salida = []
    for it in (j.get("itemList") or [])[:12]:
        v = it.get("video") or {}
        play = []

        def rec(nodo):
            if isinstance(nodo, dict):
                for k, val in nodo.items():
                    if k in ("UrlList",) and isinstance(val, list):
                        for u in val:
                            if isinstance(u, str) and u.startswith("http"):
                                play.append(u)
                    elif k in ("playAddr", "downloadAddr") and isinstance(val, str):
                        play.append(val)
                    else:
                        rec(val)
            elif isinstance(nodo, list):
                for x in nodo:
                    rec(x)

        rec(v)
        salida.append((it.get("id"), v.get("videoID"), play))
    return salida


def probar_url(nombre, url, cabeceras):
    req = urllib.request.Request(url, headers=cabeceras)
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            cuerpo = r.read(2000)
            print("[%s] %s  bytes-leidos=%d" % (nombre, r.status, len(cuerpo)))
            print("    final: %s" % r.geturl()[:180])
            print("    tipo : %s  content-length=%s  ranges=%s" % (
                r.headers.get("Content-Type"), r.headers.get("Content-Length"),
                r.headers.get("Accept-Ranges")))
            return r.geturl()
    except urllib.error.HTTPError as e:
        print("[%s] HTTP %s %s" % (nombre, e.code, e.reason))
        try:
            print("    cuerpo: %s" % e.read(200))
        except Exception:  # noqa: BLE001
            pass
    except Exception as e:  # noqa: BLE001
        print("[%s] EXC %r" % (nombre, e))
    return None


def main():
    videos = urls_del_feed()
    if not videos:
        print("feed vacio")
        return
    item_id, video_id, play = videos[0]
    print("\nprimer item:", item_id, video_id, "-> %d urls" % len(play))
    for u in play:
        print("   ", u[:130])

    aweme = [u for u in play if "/aweme/v1/play/" in u]
    if not aweme:
        print("no vino la url aweme/v1/play")
        return

    url = aweme[0]
    print("\n--- probando la URL firmada aweme/v1/play (sin cookies) ---")
    probar_url("navegador", url, {"User-Agent": UA, "Referer": "https://www.tiktok.com/"})
    print("\n--- con UA movil ---")
    probar_url("movil", url, {"User-Agent": UA_MOVIL})
    print("\n--- con Range: bytes=0-1023 ---")
    probar_url("range", url, {"User-Agent": UA, "Referer": "https://www.tiktok.com/",
                              "Range": "bytes=0-1023"})


if __name__ == "__main__":
    main()
