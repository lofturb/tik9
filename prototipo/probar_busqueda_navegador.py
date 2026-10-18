# -*- coding: utf-8 -*-
"""
probar_busqueda_navegador.py -- repite la peticion de busqueda EXACTA del navegador.

2026-10-18: se capturo desde el navegador la peticion real que si funciona
(busqueda "gatos" sin iniciar sesion, 200 con ~297 KB y 15 resultados).  La prueba
vieja (probar_busqueda.py, prueba 6) usaba un juego de parametros INVENTADO, por
eso concluyo mal.  Aqui se usan los parametros de negocio exactos, partidos tal
cual llegan (ya codificados, sin re-codificar nada) y firmados con NUESTRO signer.

Matriz:
  control   : se repite tal cual la consulta firmada capturada (comprueba que las
              firmas no son de un solo uso y que nuestro HTTP no estorba)
  a) firma nuestra, msToken = ""            (sin cookie)
  b) firma nuestra, msToken = ""            (con cookie del navegador)
  c) firma nuestra, msToken = real 124 car. (sin cookie)
  d) firma nuestra, msToken = real 124 car. (con cookie del navegador)

Uso:  python probar_busqueda_navegador.py
"""

import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xgnarly import XGnarly  # noqa: E402

CAPTURA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "busqueda_navegador.json")
URL_BASE = "https://www.tiktok.com/api/search/general/full/"


def dividir_crudo(cadena):
    """Parte 'a=1&b=2' en pares crudos: sin decodificar ni re-codificar nada.

    Los valores ya vienen codificados por el navegador (%20, %28...) y _escape
    deja intactas las secuencias %XX, asi que pueden firmarse tal cual.
    """
    pares = []
    for trozo in cadena.split("&"):
        k, _, v = trozo.partition("=")
        pares.append((k, v))
    return pares


def pedir(consulta, cabeceras, etiqueta):
    """Manda la consulta y resume la respuesta: estado, tamano, orcas, resultados."""
    req = urllib.request.Request(URL_BASE + "?" + consulta, headers=cabeceras)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            datos = r.read()
            estado = r.status
    except urllib.error.HTTPError as e:
        datos = e.read()
        estado = e.code
    except Exception as e:  # noqa: BLE001
        print("%-46s EXCEPCION %s" % (etiqueta, e))
        return None

    texto = datos.decode("utf-8", "replace")
    orcas = '"tt_orcas_res":1' in texto
    n_resultados = texto.count('"aweme_info"')
    n_users = texto.count('"user_info"')
    vacio = datos == b"" or texto.strip() in ("", "{}")
    print("%-46s HTTP %s  %7d B  orcas=%s  videos=%d users=%d" % (
        etiqueta, estado, len(datos), orcas, n_resultados, n_users))
    if vacio or estado != 200:
        print("    cuerpo: %r" % texto[:200])
    return texto


def main():
    cap = json.load(open(CAPTURA, encoding="utf-8-sig"))
    ua = cap["ua"]
    cookie = cap["cookie"]
    negocio = dividir_crudo(cap["negocioRaw"])
    ms_real = cap["msTokenConsulta"]

    base = {
        "User-Agent": ua,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
        "Referer": "https://www.tiktok.com/",
    }
    con_cookie = dict(base, Cookie=cookie)

    print("parametros de negocio: %d pares (captura %s, keyword=%s)" % (
        len(negocio), os.path.basename(CAPTURA),
        dict(negocio).get("keyword", "?")))
    print("URL: %s\n" % URL_BASE)

    # 0) control: la consulta firmada capturada, tal cual
    pedir(cap["firmadaCompleta"], con_cookie, "0 control: firma del navegador + cookie")

    # a..d) nuestra firma sobre los mismos parametros de negocio
    for ms, nombre in (("", "msToken=''"), (ms_real, "msToken=real(124)")):
        consulta, _ = XGnarly(ua).sign(negocio, ms_token=ms)
        pedir(consulta, base, "a/b firma nuestra %s sin cookie" % nombre)
        pedir(consulta, con_cookie, "c/d firma nuestra %s con cookie" % nombre)


if __name__ == "__main__":
    main()
