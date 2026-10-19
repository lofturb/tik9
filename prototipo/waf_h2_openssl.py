# -*- coding: utf-8 -*-
"""
waf_h2_openssl.py -- que pide TikTok para dejar pasar una busqueda.

Medido hasta ahora: la misma direccion, con la misma firma y el mismo
User-Agent, entra desde el PC y no entra desde el iPad.  La unica diferencia
que queda es la conexion, asi que aqui se prueba la conexion del PC pero con
dos pilas TLS distintas y HTTP/2 escrito a mano, para saber si la barrera
distingue entre pilas modernas o solo rechaza la de Apple de 2015:

  --tls openssl    OpenSSL pelado (el de Python) + HTTP/2 con la libreria h2
  --tls boringssl  la de curl_cffi (BoringSSL), que es la que si pasa

Si OpenSSL tambien pasa, el arreglo es facil (cualquier pila moderna vale).
Si no pasa, hay que llevar dentro de la app una pila de las "reconocidas"
(la de curl/BoringSSL es la que se ha medido que entra).

Uso:  python prototipo/waf_h2_openssl.py [palabra] [--tls openssl|boringssl]
"""

import json
import os
import socket
import ssl
import sys
import urllib.parse

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)

import xgnarly as X  # noqa: E402
from confianza_app import UA_APP, pares_app  # noqa: E402
from probar_busqueda_navegador import URL_BASE  # noqa: E402

from curl_cffi import requests as cf  # noqa: E402
from curl_cffi.const import CurlHttpVersion  # noqa: E402

import h2.connection  # noqa: E402
import h2.config  # noqa: E402
import h2.events  # noqa: E402

HOST = "www.tiktok.com"
PUERTO = 443


def resumen(datos, cabeceras):
    orcas = ""
    for nombre, valor in cabeceras:
        if nombre == b"tt_orcas_res":
            orcas = valor.decode()
    items = -1
    try:
        items = len(json.loads(datos.decode("utf-8", "replace")).get("data") or [])
    except Exception:  # noqa: BLE001
        pass
    return orcas, items


def pedir_http2(ruta_con_consulta, cabeceras, galletas, envolver=None):
    """Peticion HTTP/2 a mano sobre un socket TLS de Python (OpenSSL)."""
    contexto = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    contexto.check_hostname = True
    contexto.verify_mode = ssl.CERT_REQUIRED
    contexto.set_alpn_protocols(["h2"])
    if envolver:
        envolver(contexto)

    with socket.create_connection((HOST, PUERTO), timeout=40) as bruto:
        with contexto.wrap_socket(bruto, server_hostname=HOST) as tls:
            alpn = tls.selected_alpn_protocol()
            cifra = tls.cipher()
            config = h2.config.H2Configuration(client_side=True, header_encoding="utf-8")
            conexion = h2.connection.H2Connection(config=config)
            conexion.initiate_connection()
            tls.sendall(conexion.data_to_send())

            orden = [
                (":method", "GET"),
                (":authority", HOST),
                (":scheme", "https"),
                (":path", ruta_con_consulta),
                ("user-agent", cabeceras["User-Agent"]),
                ("accept", cabeceras["Accept"]),
                ("accept-language", cabeceras["Accept-Language"]),
                ("accept-encoding", "identity"),
                ("referer", cabeceras["Referer"]),
                ("origin", cabeceras["Origin"]),
                ("cookie", "; ".join("%s=%s" % (k, v) for k, v in sorted(galletas.items()))),
            ]
            conexion.send_headers(1, orden, end_stream=True)
            tls.sendall(conexion.data_to_send())

            cuerpo = b""
            cabeceras_respuesta = []
            fin = False
            tls.settimeout(30)
            while not fin:
                try:
                    trozo = tls.recv(65535)
                except socket.timeout:
                    break
                if not trozo:
                    break
                for evento in conexion.receive_data(trozo):
                    if isinstance(evento, h2.events.ResponseReceived):
                        cabeceras_respuesta = evento.headers
                    elif isinstance(evento, h2.events.DataReceived):
                        cuerpo += evento.data
                        conexion.acknowledge_received_data(evento.flow_controlled_length,
                                                           evento.stream_id)
                    elif isinstance(evento, h2.events.StreamEnded):
                        fin = True
                    elif isinstance(evento, h2.events.ConnectionTerminated):
                        fin = True
                pendiente = conexion.data_to_send()
                if pendiente:
                    tls.sendall(pendiente)
            return alpn, cifra, cabeceras_respuesta, cuerpo


def pedir_curl(consulta, cabeceras, galletas):
    """La misma peticion, pero con la pila que se sabe que entra."""
    sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
    r = sesion.get(URL_BASE + "?" + consulta, headers=cabeceras or dict(
        (k, v) for k, v in [
            ("User-Agent", UA_APP),
            ("Accept", "application/json, text/plain, */*"),
            ("Accept-Language", "en-US,en;q=0.9"),
            ("Referer", "https://www.tiktok.com/"),
            ("Origin", "https://www.tiktok.com"),
            ("Cookie", "; ".join("%s=%s" % (k, v) for k, v in sorted(galletas.items()))),
        ]), timeout=40)
    cabeceras_respuesta = [(k.lower().encode(), v.encode()) for k, v in r.headers.items()]
    return "h2", None, cabeceras_respuesta, r.content


def main():
    palabra = "auron"
    pila = "openssl"
    argumentos = sys.argv[1:]
    for i, a in enumerate(argumentos):
        if a == "--tls" and i + 1 < len(argumentos):
            pila = argumentos[i + 1]
        elif not a.startswith("--"):
            palabra = a

    # Identidad y cookies: las consigue curl, que es lo unico que se sabe hacer.
    print("consiguiendo identidad con curl...")
    sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
    sesion.headers.update({"User-Agent": UA_APP})
    sesion.get("https://www.tiktok.com/foryou", timeout=40)
    galletas = dict(sesion.cookies)
    print("  cookies: %s" % ", ".join(sorted(galletas)))
    ms = galletas.get("msToken", "")

    pares = [(k, v) for k, v in pares_app(palabra)]
    consulta, _ = X.XGnarly(UA_APP).sign(pares, ms_token=ms)
    ruta = "/api/search/general/full/?" + consulta

    cabeceras = {
        "User-Agent": UA_APP,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://www.tiktok.com/",
        "Origin": "https://www.tiktok.com",
    }

    print("pila: %s" % pila)
    for intento in (1, 2):
        if pila == "boringssl":
            alpn, cifra, cabeceras_r, cuerpo = pedir_curl(consulta, cabeceras, galletas)
        elif pila == "openssl":
            alpn, cifra, cabeceras_r, cuerpo = pedir_http2(ruta, cabeceras, galletas)
        else:
            print("pila desconocida: %s" % pila)
            return 2
        orcas, items = resumen(cuerpo, cabeceras_r)
        print("  intento %d: alpn=%s cifra=%s  HTTP %d B  orcas=%s  data=%s" % (
            intento, alpn,
            (cifra[0] if cifra else "?"),
            len(cuerpo), orcas or "-", items))
        if cuerpo and items == 0:
            for nombre, valor in cabeceras_r[:12]:
                print("      %s: %s" % (nombre.decode(), valor.decode()[:70]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
