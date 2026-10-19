# -*- coding: utf-8 -*-
"""
ip_limpia.py -- dice si la IP publica esta en el reto del WAF de TikTok.

Cuando TikTok marca la red entera (por volumen de sondeos, por ruta o por lo
que sea), **todo** lo que sale de casa vuelve con el reto «Please wait...»
(1,4 KB de HTML con `wafchallengeid`) y la API de busqueda contesta
`200` con 0 B y `tt_orcas_res: 1`, venga del iPad o del PC, con la pila que sea.
Medido asi el 2026-10-19: incluso `curl_cffi` imitando a Chrome devolvia vacio.

Por eso, antes de gastar una instalacion en el iPad, se mira desde el PC:

    python prototipo/ip_limpia.py          # vuelve 0 si la IP esta limpia
    python prototipo/confianza_app.py      # y remata: busca como la app

No necesita cookies ni firma: el reto se ve en la portada.
"""

import sys

from curl_cffi import requests

MARCAS = (b"wafchallengeid", b"Please wait", b"slardar_us_waf")


def main():
    r = requests.get("https://www.tiktok.com/", impersonate="chrome124", timeout=30)
    cuerpo = r.content
    print("portada: HTTP %s, %d B, server=%s" % (
        r.status_code, len(cuerpo), r.headers.get("server", "-")))
    reto = any(m in cuerpo for m in MARCAS)
    if reto:
        print("reto del WAF: SI -- la IP publica esta marcada.")
        print("No tiene sentido medir la app hasta que se limpie:")
        print("  - otra red (por ejemplo, datos del movil), o")
        print("  - esperar (el reto se cae solo) y volver a probar esto.")
        return 1
    print("reto del WAF: no -- la portada trae HTML de verdad (%d B)." % len(cuerpo))
    print("IP limpia: se puede medir la app.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
