# -*- coding: utf-8 -*-
"""
Prueba la API MOVIL de TikTok con firma X-Gorgon + X-Khronos.
Si devuelve el detalle del video y una url_list de tiktokcdn-us.com que
baje, entonces la app puede ser autonoma (portando X-Gorgon a C).
"""

import json
import os
import random
import string
import sys
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def _cargar_clase():
    """Carga la clase xgorgon sin ejecutar la demo del final del fichero."""
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "xgorgon.py"),
              encoding="utf-8") as f:
        fuente = f.read()
    corte = fuente.index("gorg = xgorgon(")
    espacio = {}
    exec(compile(fuente[:corte], "xgorgon.py", "exec"), espacio)  # noqa: S102
    return espacio["xgorgon"]


xgorgon = _cargar_clase()

AID = "1233"
VC = "300904"
UA = ("com.zhiliaoapp.musically/2023009040 (Linux; U; Android 9; en_US; "
      "Pixel; Build/PQ3A.190801.002; Cronet/58.0.2991.0)")


def aleatorio(n, alfabeto=string.hexdigits.lower()):
    return "".join(random.choice(alfabeto) for _ in range(n))


def udid():
    return aleatorio(16)


def main():
    aweme = sys.argv[1] if len(sys.argv) > 1 else "7106594312292453675"
    device_id = str(random.randint(7000000000000000000, 7999999999999999999))
    iid = str(random.randint(7000000000000000000, 7999999999999999999))
    install = str(random.randint(1000000000000000000, 7999999999999999999))

    params = [
        ("aweme_id", aweme),
        ("aid", AID),
        ("version_code", VC),
        ("version_name", "30.9.4"),
        ("device_platform", "android"),
        ("os", "android"),
        ("os_version", "9"),
        ("device_type", "Pixel"),
        ("device_brand", "google"),
        ("device_model", "Pixel"),
        ("resolution", "1080*1920"),
        ("dpi", "420"),
        ("channel", "googleplay"),
        ("app_name", "musical_ly"),
        ("manifest_version_code", VC),
        ("update_version_code", VC + "0"),
        ("device_id", device_id),
        ("iid", iid),
        ("install_id", install),
        ("openudid", udid()),
        ("uuid", udid()),
        ("_rticket", str(int(__import__("time").time() * 1000))),
        ("ts", str(int(__import__("time").time()))),
    ]
    query = "&".join("%s=%s" % (k, v) for k, v in params)
    ruta = "/aweme/v1/aweme/detail/?" + query

    firma = xgorgon(ruta, None, None).calc_gorg()
    print("X-Khronos:", firma["X-Khronos"])
    print("X-Gorgon :", firma["X-Gorgon"])
    print()

    cab = {
        "User-Agent": UA,
        "Accept-Encoding": "gzip",
        "X-Gorgon": firma["X-Gorgon"],
        "X-Khronos": firma["X-Khronos"],
        "X-SS-REQ-TICKET": str(int(__import__("time").time() * 1000)),
        "sdk-version": "2",
        "Connection": "keep-alive",
    }
    for host in ["api16-normal-c-useast1a.tiktokv.com",
                 "api22-normal-c-useast2a.tiktokv.com",
                 "api.tiktokv.com"]:
        url = "https://%s%s" % (host, ruta)
        req = urllib.request.Request(url, headers=cab)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                cuerpo = r.read().decode("utf-8", "replace")
            j = json.loads(cuerpo) if cuerpo.strip().startswith(("{", "[")) else None
            print("[%s] estado=%s bytes=%d" % (host, r.status, len(cuerpo)))
            if j is not None:
                print("   status_code=%s claves=%s" % (j.get("status_code"), list(j.keys())[:10]))
                for contenedor in ("aweme_detail",):
                    d = j.get(contenedor)
                    if d:
                        v = d.get("video") or {}
                        urls = (v.get("play_addr") or {}).get("url_list") or []
                        print("   host video:", urls[0].split("/")[2] if urls else None)
                        print("   url_list:", len(urls))
                        alta = (v.get("bit_rate") or [])
                        print("   calidades:", [b.get("gear_name") for b in alta])
                        if urls:
                            cab2 = {"User-Agent": UA, "Range": "bytes=0-262143"}
                            with urllib.request.urlopen(
                                    urllib.request.Request(urls[0], headers=cab2), timeout=40) as rr:
                                d2 = rr.read()
                            print("   DESCARGA: estado=%s ct=%s avc1=%s hvc1=%s" % (
                                rr.status, rr.headers.get("Content-Type"),
                                b"avc1" in d2, b"hvc1" in d2))
            else:
                print("   (no json)", cuerpo[:160].replace("\n", " "))
        except urllib.error.HTTPError as e:
            print("[%s] HTTP %s %s" % (host, e.code, e.read(120)))
        except Exception as e:  # noqa: BLE001
            print("[%s] EXC %r" % (host, e))
        print()


if __name__ == "__main__":
    main()
