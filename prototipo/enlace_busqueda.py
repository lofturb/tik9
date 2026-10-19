# -*- coding: utf-8 -*-
"""
enlace_busqueda.py -- fabrica una peticion de busqueda YA FIRMADA (los mismos
parametros, la misma firma y el mismo User-Agent que usa la app) y deja un enlace
para abrirla desde el navegador del propio aparato.

Para que sirve: separa dos cosas que desde el informe se ven iguales.

  * Si al abrir el enlace en Safari del aparato SALE UN JSON LLENO (con
    "data"/"itemList" y videos), entonces el aparato SI puede pedir la busqueda:
    el problema esta en como pregunta la app (cabeceras, huella de la conexion).
  * Si al abrirlo NO sale nada util (pagina vacia, o un JSON con "status_code":0
    y sin datos), entonces TikTok esta rechazando a ese aparato por su conexion
    (por ejemplo, porque no llega a TLS 1.3), y no hay retoque en la app que lo
    arregle.

Uso:
    python prototipo/enlace_busqueda.py [palabra] [--cuenta 1]

Escribe entrega/prueba_busqueda.html (que el instalador ya sirve en
http://<ip>/entrega/prueba_busqueda.html) e imprime lo que ha visto el PC al
verificar el enlace, para saber que la firma es buena antes de molestarte.
"""

import argparse
import html
import json
import os
import sys
import urllib.parse

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
sys.path.insert(0, AQUI)

import xgnarly as X  # noqa: E402
from confianza_app import UA_APP, pares_app  # noqa: E402
from probar_busqueda_navegador import URL_BASE  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402


def preparar_sesion():
    """Identidad anonima (ttwid) y un msToken, igual que hace la app."""
    sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
    sesion.headers.update({"User-Agent": UA_APP})
    r = sesion.get("https://www.tiktok.com/foryou", timeout=40)
    galletas = dict(sesion.cookies)
    ms = galletas.get("msToken", "")
    print("identidad: HTTP %s  cookies=%s" % (r.status_code, ", ".join(sorted(galletas))))
    if not ms:
        consulta, _ = X.XGnarly(UA_APP).sign([("aid", "1988"), ("keyword", "a")], ms_token="")
        r = sesion.get(URL_BASE + "?" + consulta, timeout=40)
        ms = r.headers.get("x-ms-token") or ""
    print("msToken: %d caracteres" % len(ms))
    return sesion, ms, "; ".join("%s=%s" % (k, v) for k, v in sorted(galletas.items()) if v)


def firmar(palabra, cuenta, ms):
    # Mismos pares que la app y en el mismo orden; solo se cambia el valor de
    # "count" (para poder pedir una respuesta corta) porque la firma cubre la
    # cadena de consulta exacta.
    pares = [(clave, str(cuenta) if clave == "count" else valor)
             for clave, valor in pares_app(palabra)]
    consulta, _ = X.XGnarly(UA_APP).sign(pares, ms_token=ms)
    return URL_BASE + "?" + consulta


def mirar(sesion, url, cabeceras, etiqueta):
    """Pide la direccion ya firmada y cuenta lo que trae (como en el informe)."""
    r = sesion.get(url, headers=cabeceras, timeout=40)
    texto = r.content.decode("utf-8", "replace")
    datos, estado, aviso = -1, "?", ""
    try:
        j = json.loads(texto)
        datos = len(j.get("data") or [])
        estado = j.get("status_code")
        aviso = (j.get("status_msg") or "")[:40]
    except Exception:  # noqa: BLE001
        pass
    print("  %-40s HTTP %s %8d B  orcas=%-5s status=%s data=%s %s" % (
        etiqueta, r.status_code, len(r.content), r.headers.get("tt_orcas_res") or "-",
        estado, datos, aviso))
    return r.content


def main():
    analizador = argparse.ArgumentParser(description="enlace de busqueda firmado")
    analizador.add_argument("palabra", nargs="?", default="auron")
    analizador.add_argument("--cuenta", type=int, default=1,
                            help="cuantos resultados pedir (1 = respuesta corta)")
    args = analizador.parse_args()

    sesion, ms, galletas = preparar_sesion()
    cabeceras = {
        "User-Agent": UA_APP,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://www.tiktok.com/",
        "Origin": "https://www.tiktok.com",
        "Cookie": galletas,
    }

    print("\ncomprobacion en el PC (curl_cffi, HTTP/2, TLS 1.3):")
    url_corta = firmar(args.palabra, args.cuenta, ms)
    cuerpo_corto = mirar(sesion, url_corta, cabeceras, "busqueda count=%d" % args.cuenta)
    url_larga = firmar(args.palabra, 12, ms)
    mirar(sesion, url_larga, cabeceras, "busqueda count=12 (la de la app)")

    # Pagina que se sirve desde el instalador, con los enlaces para el aparato.
    destino = os.path.join(RAIZ, "entrega", "prueba_busqueda.html")
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    hay_datos = len(cuerpo_corto) > 1000
    pagina = """<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Prueba de busqueda (Tik9)</title>
<style>
  body {{ font-family: -apple-system, sans-serif; margin: 16px; line-height: 1.5; }}
  h1 {{ font-size: 20px; }}
  a.boton {{ display: block; margin: 14px 0; padding: 14px; text-align: center;
             background: #fe2c55; color: #fff; text-decoration: none;
             border-radius: 10px; font-weight: 600; }}
  code {{ font-size: 12px; word-break: break-all; }}
  .nota {{ background: #f4f4f4; padding: 10px; border-radius: 8px; font-size: 13px; }}
</style></head>
<body>
<h1>Prueba de búsqueda de TikTok</h1>
<p>Palabra: <b>%s</b>. Los enlaces piden la búsqueda <b>firmada igual que la app</b>
(mismos parámetros, misma firma, mismo User-Agent), pero lanzada por Safari del
dispositivo. Así se ve si el aparato puede pedirla o si TikTok lo rechaza.</p>

<a class="boton" href="%s">1. Pedir la búsqueda (respuesta corta)</a>
<a class="boton" href="%s">2. Pedir la búsqueda tal cual la pide la app (count=12)</a>
<a class="boton" href="https://www.cloudflare.com/cdn-cgi/trace?tik9=prueba"
   style="background:#333">3. Ver la traza de protocolo (control)</a>

<div class="nota">
<p><b>Qué mirar en la primera página:</b></p>
<p>· Si aparece un texto largo que empieza por <code>{"status_code":0,...}</code> y
más adelante trae <code>"data":[</code> con vídeos dentro → <b>el aparato sí puede</b>,
el problema está en la app.</p>
<p>· Si la página sale <b>en blanco</b>, o trae <code>"data":[]</code> o
<code>"itemList":[]</code>, o un <code>status_code</code> raro sin vídeos →
<b>TikTok está rechazando al aparato</b> (por su conexión), y la app lo tiene
difícil: habría que pasar por el relay.</p>
</div>

<p class="nota">Estado en el PC al generar este enlace: %s</p>
<p><code>%s</code></p>
</body></html>
""" % (html.escape(args.palabra), html.escape(url_corta, quote=True),
       html.escape(url_larga, quote=True),
       "el PC SÍ recibe datos (%d B)" % len(cuerpo_corto) if hay_datos
       else "OJO: el PC tampoco recibe datos (%d B)" % len(cuerpo_corto),
       html.escape(url_corta))
    with open(destino, "w", encoding="utf-8") as f:
        f.write(pagina)
    print("\npagina escrita en %s" % destino)
    print("se sirve en http://192.168.1.7/entrega/prueba_busqueda.html")


if __name__ == "__main__":
    main()
