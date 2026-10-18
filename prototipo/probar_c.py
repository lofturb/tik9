# -*- coding: utf-8 -*-
"""
probar_c.py -- prueba de punta a punta del port de firma en C.

Compila app/pruebas/prueba_vivo.c, le pide la cadena de consulta firmada
(con el port en C, no con Python) y la envia a la API web de TikTok. Si la
respuesta trae datos, el port de C es correcto y sirve tal cual en la app.

Uso:  python probar_c.py [itemId]
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PRUEBAS = os.path.join(RAIZ, "app", "pruebas")
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
TCC = os.environ.get("TCC", r"C:\Users\Loftur\AppData\Local\Temp\opencode\tcc\tcc\tcc.exe")

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0")

RUTAS = {
    "itemDetail": "/api/item/detail/",
    "recommend": "/api/recommend/item_list/",
    "search": "/api/search/general/full/",
}


def firmar(modo, item=""):
    exe = os.path.join(PRUEBAS, "prueba_vivo.exe")
    subprocess.run([TCC, "-o", exe, os.path.join(PRUEBAS, "prueba_vivo.c"),
                    os.path.join(RAIZ, "app", "TTSignaCore.c")], cwd=PRUEBAS, check=True)
    out = subprocess.run([exe, modo, item], cwd=PRUEBAS, capture_output=True, env=ENV)
    if out.returncode != 0:
        raise SystemExit("prueba_vivo fallo: " + out.stderr.decode("utf-8", "replace"))
    return out.stdout.decode("utf-8").strip()


def pedir(ruta, firmado):
    url = "https://www.tiktok.com%s?%s" % (ruta, firmado)
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://www.tiktok.com/",
    })
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode("utf-8", "replace"), time.time() - t0, dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), time.time() - t0, dict(e.headers)
    except Exception as e:  # noqa: BLE001
        return None, "EXCEPCION: %r" % (e,), time.time() - t0, {}


def main():
    item = sys.argv[1] if len(sys.argv) > 1 else "7106594312292453675"
    for modo in ("itemDetail", "recommend"):
        firmado = firmar(modo, item)
        estado, cuerpo, dt, cab = pedir(RUTAS[modo], firmado)
        print("=" * 72)
        print("[%s]  /%s" % (modo, RUTAS[modo].strip("/")))
        print("  firma (C): %s..." % firmado[:90])
        print("  estado=%s  bytes=%d  %.2fs" % (estado, len(cuerpo), dt))
        try:
            j = json.loads(cuerpo)
            print("  status_code=%s  claves=%s" % (j.get("status_code"), list(j.keys())[:8]))
            if modo == "itemDetail":
                it = (j.get("itemInfo") or {}).get("itemStruct")
                print("  itemStruct=%s  desc=%r" % (
                    bool(it), ((it or {}).get("desc") or "")[:60]))
            else:
                print("  itemList=%d" % len(j.get("itemList") or []))
        except Exception:  # noqa: BLE001
            print("  (no json) %s" % cuerpo[:160].replace("\n", " "))
        print()


if __name__ == "__main__":
    main()
