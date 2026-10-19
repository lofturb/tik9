# -*- coding: utf-8 -*-
"""
waf_tls.py -- mide si el WAF de la busqueda de TikTok mira la version de TLS.

Desde el PC la busqueda funciona (curl_cffi, TLS 1.3).  El iPad, con iOS 9, no
puede pasar de TLS 1.2.  Este guion pide la misma busqueda varias veces cambiando
SOLO la forma de conectarse (misma firma, mismo UA, mismas cabeceras), que es la
unica diferencia que queda entre el PC y el aparato.

Se usa el API de bajo nivel de curl_cffi porque el de alto nivel no deja fijar la
version *maxima* de TLS (libcurl la lleva en los bits altos de CURLOPT_SSLVERSION:
CURL_SSLVERSION_MAX_TLSv1_2 = 6 << 16).

Uso:  python prototipo/waf_tls.py [palabra]
"""

import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)

import xgnarly as X  # noqa: E402
from confianza_app import UA_APP, pares_app  # noqa: E402
from probar_busqueda_navegador import URL_BASE  # noqa: E402

from curl_cffi import Curl, CurlInfo, CurlOpt  # noqa: E402
from curl_cffi.const import CurlHttpVersion, CurlSslVersion  # noqa: E402

TLS12 = (CurlSslVersion.TLSv1_2 << 16) | CurlSslVersion.TLSv1_2   # solo 1.2
TLS13 = (CurlSslVersion.TLSv1_3 << 16) | CurlSslVersion.TLSv1_3   # solo 1.3

# Lo que ofrece iOS 9: TLS 1.2, curva P-256 y su lista de cifrados (sin ChaCha20).
CURVAS_IOS9 = "prime256v1"
CIFRADOS_IOS9 = ":".join([
    "ECDHE-ECDSA-AES256-GCM-SHA384", "ECDHE-ECDSA-AES128-GCM-SHA256",
    "ECDHE-ECDSA-AES256-SHA384", "ECDHE-ECDSA-AES128-SHA256",
    "ECDHE-ECDSA-AES256-SHA", "ECDHE-ECDSA-AES128-SHA",
    "ECDHE-RSA-AES256-GCM-SHA384", "ECDHE-RSA-AES128-GCM-SHA256",
    "ECDHE-RSA-AES256-SHA384", "ECDHE-RSA-AES128-SHA256",
    "ECDHE-RSA-AES256-SHA", "ECDHE-RSA-AES128-SHA",
    "AES256-GCM-SHA384", "AES128-GCM-SHA256", "AES256-SHA256", "AES128-SHA256",
    "AES256-SHA", "AES128-SHA",
])


def pedir(url, cabeceras, sslversion=None, h2=True, curvas=None, cifrados=None,
          etiqueta="", esperar_cuerpo=True):
    """Una peticion cruda, con control total de la conexion."""
    mango = Curl()
    trozos = bytearray()
    cabeceras_respuesta = {}
    try:
        mango.setopt(CurlOpt.URL, url.encode("utf-8"))
        mango.setopt(CurlOpt.HTTP_VERSION,
                     CurlHttpVersion.V2_0 if h2 else CurlHttpVersion.V1_1)
        mango.setopt(CurlOpt.HTTPHEADER,
                     [("%s: %s" % (k, v)).encode("utf-8") for k, v in cabeceras.items()])
        if sslversion is not None:
            mango.setopt(CurlOpt.SSLVERSION, int(sslversion))
        if curvas:
            mango.setopt(CurlOpt.SSL_EC_CURVES, curvas.encode("utf-8"))
        if cifrados:
            mango.setopt(CurlOpt.SSL_CIPHER_LIST, cifrados.encode("utf-8"))

        def recibir(datos):
            trozos.extend(datos)
            return len(datos)

        def guardar_cabecera(linea):
            texto = linea.decode("utf-8", "replace").strip()
            if ":" in texto and not texto.startswith("HTTP/"):
                nombre, valor = texto.split(":", 1)
                cabeceras_respuesta[nombre.strip().lower()] = valor.strip()
            return len(linea)

        mango.setopt(CurlOpt.WRITEFUNCTION, recibir)
        mango.setopt(CurlOpt.HEADERFUNCTION, guardar_cabecera)
        mango.perform()
        codigo = mango.getinfo(CurlInfo.RESPONSE_CODE)
    except Exception as e:  # noqa: BLE001
        print("  %-42s ERROR %s: %s" % (etiqueta, type(e).__name__, str(e)[:80]))
        return None
    finally:
        try:
            mango.close()
        except Exception:  # noqa: BLE001
            pass

    datos, estado = -1, "?"
    try:
        j = json.loads(bytes(trozos).decode("utf-8", "replace"))
        datos = len(j.get("data") or [])
        estado = j.get("status_code")
    except Exception:  # noqa: BLE001
        pass
    print("  %-42s HTTP %s %8d B  orcas=%-5s status=%s data=%s" % (
        etiqueta, codigo, len(trozos), cabeceras_respuesta.get("tt_orcas_res", "-"),
        estado, datos))
    return bytes(trozos)


def version_negociada(etiqueta, **extra):
    """Que TLS se negocia de verdad: lo dice un servicio publico que lo refleja."""
    mango = Curl()
    trozos = bytearray()
    try:
        mango.setopt(CurlOpt.URL, b"https://tls.peet.ws/api/all")
        mango.setopt(CurlOpt.HTTP_VERSION, CurlHttpVersion.V2_0)
        if extra.get("sslversion") is not None:
            mango.setopt(CurlOpt.SSLVERSION, int(extra["sslversion"]))
        if extra.get("curvas"):
            mango.setopt(CurlOpt.SSL_EC_CURVES, extra["curvas"].encode("utf-8"))
        if extra.get("cifrados"):
            mango.setopt(CurlOpt.SSL_CIPHER_LIST, extra["cifrados"].encode("utf-8"))

        def recibir(d):
            trozos.extend(d)
            return len(d)

        mango.setopt(CurlOpt.WRITEFUNCTION, recibir)
        mango.perform()
        j = json.loads(bytes(trozos).decode("utf-8", "replace"))
        tls = j.get("tls") or {}
        h2 = j.get("http2") or {}
        version = (tls.get("tls_version_negotiated") or tls.get("tls_version_record")
                   or tls.get("version") or ("?" + ",".join(list(tls)[:6])))
        print("  %-42s -> %s / ALPN %s / h2 %s" % (
            etiqueta, version, j.get("http_version"),
            (h2.get("akamai_fingerprint") or "")[:32]))
    except Exception as e:  # noqa: BLE001
        print("  %-42s -> ERROR %s: %s" % (etiqueta, type(e).__name__, str(e)[:70]))
    finally:
        mango.close()


def preparar(palabra, cuenta=12):
    from curl_cffi import requests as cf

    sesion = cf.Session(http_version=CurlHttpVersion.V2_0)
    sesion.headers.update({"User-Agent": UA_APP})
    sesion.get("https://www.tiktok.com/foryou", timeout=40)
    galletas = dict(sesion.cookies)
    ms = galletas.get("msToken", "")
    if not ms:
        # A veces el msToken no viene en cookie: la propia respuesta lo trae en
        # la cabecera x-ms-token.  Se pide la ruta con un token vacio solo para
        # que TikTok regale uno (es lo mismo que hace la app cuando "regala").
        pares = [("aid", "1988"), ("app_name", "tiktok_web")]
        consulta, _ = X.XGnarly(UA_APP).sign(pares, ms_token="")
        r = sesion.get(URL_BASE + "?" + consulta, timeout=40)
        ms = r.headers.get("x-ms-token") or ""
        galletas = dict(sesion.cookies)
    pares = [(k, str(cuenta) if k == "count" else v) for k, v in pares_app(palabra)]
    consulta, _ = X.XGnarly(UA_APP).sign(pares, ms_token=ms)
    cabeceras = {
        "User-Agent": UA_APP,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://www.tiktok.com/",
        "Origin": "https://www.tiktok.com",
        "Cookie": "; ".join("%s=%s" % (k, v) for k, v in sorted(galletas.items())),
    }
    print("identidad: cookies=%s  msToken=%d car." % (", ".join(sorted(galletas)), len(ms)))
    return URL_BASE + "?" + consulta, cabeceras


def main():
    palabra = sys.argv[1] if len(sys.argv) > 1 else "auron"

    print("== que TLS se negocia de verdad ==")
    version_negociada("h2, TLS por defecto")
    version_negociada("h2, solo TLS 1.2", sslversion=TLS12)
    version_negociada("h2, solo TLS 1.3", sslversion=TLS13)
    version_negociada("h2, TLS 1.2 + curvas y cifrados de iOS 9",
                      sslversion=TLS12, curvas=CURVAS_IOS9, cifrados=CIFRADOS_IOS9)

    url, cabeceras = preparar(palabra)
    print("\n== la misma busqueda, cambiando solo la conexion ==")
    pedir(url, cabeceras, None, True, etiqueta="h2 + TLS por defecto (1.3)")
    pedir(url, cabeceras, TLS12, True, etiqueta="h2 + solo TLS 1.2")
    pedir(url, cabeceras, TLS13, True, etiqueta="h2 + solo TLS 1.3 (control)")
    pedir(url, cabeceras, TLS12, True, curvas=CURVAS_IOS9, cifrados=CIFRADOS_IOS9,
          etiqueta="h2 + TLS 1.2 + huella de iOS 9")
    pedir(url, cabeceras, None, False, etiqueta="h1 (control, ya se sabia que falla)")


if __name__ == "__main__":
    main()
