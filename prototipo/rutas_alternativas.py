# -*- coding: utf-8 -*-
"""
rutas_alternativas.py -- busca una puerta que NO pase por la API de busqueda.

La API de busqueda (/api/search/...) esta vetada para la pila de red del iPad,
pero las PAGINAS si cargan (prepararIdentidad lee /foryou sin problema).  Este
guion mira desde el PC, que para el CONTENIDO vale igual, si alguna de esas
paginas o rutas trae los videos dentro:

  A) https://www.tiktok.com/search?q=<palabra>      la pagina de busqueda
  B) https://www.tiktok.com/tag/<palabra>           la pagina de una etiqueta
  C) /api/challenge/detail/?challengeName=<palabra> la ficha de la etiqueta
  D) /api/challenge/item_list/?challengeID=<id>     los videos de la etiqueta

Si A o B traen "itemStruct" en el HTML, el iPad puede buscar sin tocar la API
vetada.  Si no, C y D dicen si al menos las etiquetas se pueden listar.

Uso:  python prototipo/rutas_alternativas.py [palabra]
"""

import json
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)

import xgnarly as X  # noqa: E402
from confianza_app import UA_APP  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402

URL_API = "https://www.tiktok.com/api/challenge/%s/"

# Lo que delata que una pagina trae los videos dentro.
MARCAS = ["itemStruct", "__UNIVERSAL_DATA_FOR_REHYDRATION__", "playAddr",
          "authorUniqueId", "webapp.search", "search-video"]


def nueva_sesion():
    sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
    sesion.headers.update({"User-Agent": UA_APP})
    sesion.get("https://www.tiktok.com/foryou", timeout=40)
    return sesion


def mirar_pagina(sesion, url, etiqueta):
    r = sesion.get(url, timeout=40, allow_redirects=True)
    texto = r.content.decode("utf-8", "replace")
    print("  %-34s HTTP %s %7d B  %s" % (etiqueta, r.status_code, len(r.content),
                                         "  ".join(
                                             "%s=%d" % (m, texto.count(m)) for m in MARCAS)))
    return texto


def mirar_api(sesion, nombre, pares):
    galletas = dict(sesion.cookies)
    ms = galletas.get("msToken", "")
    consulta, _ = X.XGnarly(UA_APP).sign([(k, v) for k, v in pares], ms_token=ms)
    url = URL_API % nombre + "?" + consulta
    cabeceras = {
        "Accept": "application/json, text/plain, */*",
        "Referer": "https://www.tiktok.com/",
        "Origin": "https://www.tiktok.com",
        "Cookie": "; ".join("%s=%s" % (k, v) for k, v in sorted(galletas.items())),
    }
    r = sesion.get(url, headers=cabeceras, timeout=40)
    datos, codigo, total = -1, "", "-"
    try:
        j = json.loads(r.content.decode("utf-8", "replace"))
        codigo = j.get("status_code")
        de = j.get("data") or {}
        if isinstance(de, dict):
            total = len(de.get("itemList") or de.get("challengeInfoList") or [])
            if not total:
                total = "claves=%s" % ",".join(sorted(de)[:6])
        elif isinstance(de, list):
            total = len(de)
    except Exception:  # noqa: BLE001
        pass
    print("  %-34s HTTP %s %7d B orcas=%-3s status=%-5s items=%s" % (
        "api/" + nombre, r.status_code, len(r.content),
        r.headers.get("tt_orcas_res") or "-", codigo, total))
    return r


def main():
    palabra = sys.argv[1] if len(sys.argv) > 1 else "auron"
    print("palabra: %s" % palabra)
    sesion = nueva_sesion()
    print("=== paginas (lo que puede leer el iPad) ===")
    mirar_pagina(sesion, "https://www.tiktok.com/search?q=%s" % palabra, "pagina /search")
    mirar_pagina(sesion, "https://www.tiktok.com/tag/%s" % palabra, "pagina /tag")
    mirar_pagina(sesion, "https://www.tiktok.com/tag/%s?lang=es" % palabra, "/tag?lang=es")

    print("=== api de etiquetas (por si acaso pasara) ===")
    mirar_api(sesion, "detail", [("challengeName", palabra), ("aid", "1988")])
    # El id de la etiqueta, para poder pedir sus videos.
    galletas = dict(sesion.cookies)
    ms = galletas.get("msToken", "")
    consulta, _ = X.XGnarly(UA_APP).sign(
        [("challengeName", palabra), ("aid", "1988")], ms_token=ms)
    r = sesion.get((URL_API % "detail") + "?" + consulta, timeout=40,
                   headers={"Referer": "https://www.tiktok.com/",
                            "Cookie": "; ".join("%s=%s" % (k, v) for k, v in sorted(galletas.items()))})
    ident = ""
    try:
        ident = json.loads(r.content.decode("utf-8", "replace"))["challengeInfo"]["challenge"]["id"]
    except Exception:  # noqa: BLE001
        pass
    if ident:
        print("  id de la etiqueta %s: %s" % (palabra, ident))
        mirar_api(sesion, "item_list",
                  [("challengeID", ident), ("count", "12"), ("cursor", "0"),
                   ("aid", "1988")])
    else:
        print("  no se pudo sacar el id de la etiqueta (no hay ficha: la API tambien veta)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
