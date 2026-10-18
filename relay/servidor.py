# -*- coding: utf-8 -*-
"""
Tik9 Relay  --  puente OPCIONAL entre la app de iOS 9.3.5 y el CDN de TikTok.

No es obligatorio.  La app reproduce sola: usa la direccion firmada
/aweme/v1/play/ que viene dentro del feed y el CDN, que solo pide la cabecera
Referer.  Este programa sirve para dos casos concretos:

  1. iOS 9.3.5 (agosto de 2016) puede no confiar en el certificado del CDN de
     TikTok.  El relay va por HTTP plano dentro de tu red y es el (con TLS
     moderno) quien habla con el CDN.
  2. Redes que cortan la conexion con el CDN: el relay la reintenta desde tu PC.

Solo usa la biblioteca estandar de Python 3.8.  No necesita pip ni instalar
nada, y NO firma peticiones: la app le pasa la direccion firmada que ya tiene.

Uso:
    python servidor.py
    python servidor.py --puerto 8787 --token m1clave

Endpoints (todos bajo /api):
    GET /api/health                       -> estado del servicio
    GET /api/diag[?u=URL]                 -> pruebas y diagnostico
    GET /api/stream?id=ID&u=URL_FIRMADA   -> direccion final + url del proxy (JSON)
    GET /api/video?id=ID&u=URL_FIRMADA    -> el MP4 en si (soporta Range)
    GET /                                -> pagina HTML de estado

Con --token, todas las llamadas a /api deben llevar ?t=ELTOKEN
(o la cabecera X-Tik9-Token).
"""

import argparse
import json
import os
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "1.0.0"

# Cabeceras que exige el CDN de TikTok: el Referer es imprescindible (sin el
# devuelve 403).  El UA puede ser cualquiera.
UA_NAVEGADOR = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0"
)
REFERER = "https://www.tiktok.com/"

# Solo se deja pasar a hosts de TikTok (el relay no es un proxy abierto).
HOSTS_PERMITIDOS = (
    ".tiktok.com",
    ".tiktokcdn.com",
    ".tiktokcdn-us.com",
    ".tiktokv.com",
    ".byteoversea.com",
)

CONFIG = {
    "puerto": 8787,
    "token": "",
    "verbose": False,
}


def log(*a):
    if CONFIG["verbose"]:
        print("  [depuracion]", *a)


def host_permitido(url):
    try:
        partes = urllib.parse.urlparse(url)
    except Exception:  # noqa: BLE001
        return False
    if partes.scheme not in ("https", "http"):
        return False
    host = (partes.hostname or "").lower()
    if not host:
        return False
    return any(host == s.lstrip(".") or host.endswith(s) for s in HOSTS_PERMITIDOS)


# --------------------------------------------------------------------------
#  Resolucion: seguir el 302 de /aweme/v1/play/ hasta el CDN bueno.
# --------------------------------------------------------------------------
def resolver(u):
    """Devuelve (url_final, codigo, cabeceras) siguiendo el redirect."""
    cabeceras = {
        "User-Agent": UA_NAVEGADOR,
        "Referer": REFERER,
        "Accept": "video/mp4,video/*;q=0.9,*/*;q=0.8",
        "Range": "bytes=0-0",
    }
    req = urllib.request.Request(u, headers=cabeceras)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.geturl(), r.getcode(), dict(r.headers)
    except urllib.error.HTTPError as e:
        return u, e.code, dict(e.headers)


# --------------------------------------------------------------------------
#  Servidor HTTP
# --------------------------------------------------------------------------
class Manejador(BaseHTTPRequestHandler):
    server_version = "Tik9Relay/" + VERSION
    protocol_version = "HTTP/1.1"

    # ---- utilidades de respuesta ----
    def _json(self, objeto, codigo=200):
        cuerpo = json.dumps(objeto, ensure_ascii=False).encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(cuerpo)

    def _token_ok(self, parametros):
        if not CONFIG["token"]:
            return True
        recibido = (parametros.get("t", [""])[0]
                    or self.headers.get("X-Tik9-Token", ""))
        return recibido == CONFIG["token"]

    def _base_publica(self):
        host = self.headers.get("Host") or ("%s:%d" % (ip_local(), CONFIG["puerto"]))
        return "http://%s" % host

    def log_message(self, formato, *args):
        if CONFIG["verbose"]:
            sys.stderr.write("  %s - %s\n" % (self.address_string(), formato % args))

    def _url_de_la_peticion(self, parametros):
        """La direccion firmada que manda la app (parametro u=)."""
        u = (parametros.get("u", [""])[0] or "").strip()
        if not u:
            return None, "falta el parametro u (la direccion firmada del video)"
        if not host_permitido(u):
            return None, "la direccion no es de TikTok"
        return u, None

    # ---- GET ----
    def do_GET(self):
        partes = urllib.parse.urlparse(self.path)
        ruta = partes.path.rstrip("/") or "/"
        parametros = urllib.parse.parse_qs(partes.query)

        if ruta == "/":
            return self._pagina_estado()

        if not ruta.startswith("/api"):
            return self._json({"ok": False, "error": "ruta desconocida"}, 404)

        if not self._token_ok(parametros):
            return self._json({"ok": False, "error": "token incorrecto"}, 403)

        try:
            if ruta == "/api/health":
                return self._json({
                    "ok": True, "servicio": "tik9-relay", "version": VERSION,
                    "hora": int(time.time()), "python": sys.version.split()[0],
                })

            if ruta == "/api/diag":
                return self._json(self.diagnostico(parametros))

            if ruta in ("/api/stream", "/api/resolver"):
                u, error = self._url_de_la_peticion(parametros)
                if error:
                    return self._json({"ok": False, "error": error})
                final, codigo, cabeceras = resolver(u)
                if codigo not in (200, 206):
                    return self._json({
                        "ok": False,
                        "error": "el CDN respondio %s" % codigo,
                        "url_final": final,
                    })
                proxy = "%s/api/video?u=%s" % (self._base_publica(),
                                               urllib.parse.quote(u, safe=""))
                if CONFIG["token"]:
                    proxy += "&t=" + urllib.parse.quote(CONFIG["token"], safe="")
                return self._json({
                    "ok": True,
                    "id": (parametros.get("id", [""])[0] or None),
                    "url": final,           # CDN directo (por si la app puede con TLS)
                    "url_proxy": proxy,     # por HTTP plano a traves del relay
                    "motor": "relay",
                    "tipo": cabeceras.get("Content-Type"),
                    "bytes": cabeceras.get("Content-Length"),
                })

            if ruta == "/api/video":
                u, error = self._url_de_la_peticion(parametros)
                if error:
                    return self._json({"ok": False, "error": error})
                return self._servir_video(u)

            return self._json({"ok": False, "error": "ruta desconocida"}, 404)

        except urllib.error.HTTPError as e:
            return self._json({"ok": False, "error": "HTTP %s de origen" % e.code})
        except Exception as e:  # noqa: BLE001
            return self._json({"ok": False, "error": str(e)})

    # ---- el MP4, con soporte de Range (AVPlayer lo pide) ----
    def _servir_video(self, u):
        cabeceras = {
            "User-Agent": UA_NAVEGADOR,
            "Referer": REFERER,
            "Accept": "video/mp4,video/*;q=0.9,*/*;q=0.8",
            "Accept-Encoding": "identity",
        }
        peticion_rango = self.headers.get("Range")
        if peticion_rango:
            cabeceras["Range"] = peticion_rango

        try:
            req = urllib.request.Request(u, headers=cabeceras)
            with urllib.request.urlopen(req, timeout=30) as origen:
                codigo = origen.getcode()
                tipo = origen.headers.get("Content-Type", "video/mp4")
                self.send_response(codigo if codigo in (200, 206) else 200)
                self.send_header("Content-Type", tipo)
                enviado_largo = False
                for cabecera in ("Content-Length", "Content-Range"):
                    valor = origen.headers.get(cabecera)
                    if valor:
                        self.send_header(cabecera, valor)
                        if cabecera == "Content-Length":
                            enviado_largo = True
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Cache-Control", "no-store")
                if not enviado_largo:
                    # Sin longitud conocida: se cierra al terminar.
                    self.send_header("Connection", "close")
                    self.close_connection = True
                self.end_headers()
                while True:
                    trozo = origen.read(65536)
                    if not trozo:
                        break
                    self.wfile.write(trozo)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except urllib.error.HTTPError as e:
            try:
                self._json({"ok": False, "error": "el CDN respondio %s" % e.code})
            except Exception:  # noqa: BLE001
                pass

    # ---- pagina de estado, para comprobar el relay desde el navegador ----
    def _pagina_estado(self):
        ip = ip_local()
        html = """<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tik9 Relay</title>
<style>
 body{font-family:-apple-system,'Segoe UI',sans-serif;background:#0b0b0d;color:#ececf1;
      margin:0;padding:32px;line-height:1.5}
 .caja{max-width:640px;margin:0 auto;background:#161618;border:1px solid #26262b;
      border-radius:16px;padding:28px}
 h1{margin:0 0 4px;font-size:22px;letter-spacing:-.02em}
 .ok{display:inline-block;background:#3a1e2a;color:#fe2c55;border-radius:999px;
     padding:3px 12px;font-size:13px;font-weight:600}
 code{background:#000;padding:2px 7px;border-radius:6px;font-size:13px;color:#25f4ee}
 input{width:100%%;box-sizing:border-box;background:#000;border:1px solid #2a2a30;color:#ececf1;
       padding:11px 13px;border-radius:10px;font-size:14px;margin:10px 0}
 button{background:#fe2c55;color:#fff;border:0;border-radius:10px;padding:11px 20px;font-size:15px;font-weight:600}
 pre{background:#000;padding:12px;border-radius:10px;overflow:auto;font-size:12px;max-height:340px}
</style></head><body><div class="caja">
<h1>Tik9 Relay</h1><p><span class="ok">ACTIVO</span> &nbsp;escuchando en el puerto %(puerto)d</p>
<p style="color:#9a9aa2;font-size:14px">Pon <b>esta direccion</b> en Ajustes dentro de la app (es opcional):</p>
<p><code>http://%(ip)s:%(puerto)d</code></p>
<p style="color:#9a9aa2;font-size:14px">Para probar, pega aqui una direccion firmada
<code>https://www.tiktok.com/aweme/v1/play/?...</code> (la trae cada video del feed):</p>
<input id="u" placeholder="https://www.tiktok.com/aweme/v1/play/?...">
<button onclick="probar()">Resolver</button>
<pre id="salida">esperando...</pre>
</div>
<script>
function probar(){
  var u=document.getElementById('u').value.trim();
  document.getElementById('salida').textContent='resolviendo...';
  fetch('/api/stream?u='+encodeURIComponent(u))
   .then(function(r){return r.json()})
   .then(function(d){document.getElementById('salida').textContent=JSON.stringify(d,null,2);})
   .catch(function(e){document.getElementById('salida').textContent='FALLO: '+e});
}
</script></body></html>""" % {"ip": ip, "puerto": CONFIG["puerto"]}
        cuerpo = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)


# --------------------------------------------------------------------------
#  Diagnostico
# --------------------------------------------------------------------------
def diagnostico(parametros=None):
    parametros = parametros or {}
    pruebas = []
    u = (parametros.get("u", [""])[0] or "").strip()
    if u and host_permitido(u):
        t0 = time.time()
        final, codigo, cabeceras = resolver(u)
        pruebas.append({
            "prueba": "resolver u",
            "codigo": codigo,
            "url_final": final,
            "tipo": cabeceras.get("Content-Type"),
            "bytes": cabeceras.get("Content-Length"),
            "ms": int((time.time() - t0) * 1000),
        })
    return {
        "ok": True,
        "servicio": "tik9-relay",
        "version": VERSION,
        "python": sys.version.split()[0],
        "token": bool(CONFIG["token"]),
        "consejo": ("Pasa ?u=<direccion firmada> para probar la resolucion.  La app "
                    "manda ese parametro en /api/stream y /api/video."),
        "pruebas": pruebas,
    }


def ip_local():
    """IP de esta maquina dentro de la red local (la que debe usar el iPhone)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:  # noqa: BLE001
        return "127.0.0.1"
    finally:
        s.close()


# --------------------------------------------------------------------------
def main():
    analizador = argparse.ArgumentParser(description="Tik9 Relay (opcional)")
    analizador.add_argument("--puerto", type=int, default=8787)
    analizador.add_argument("--token", default="", help="clave opcional que debe enviar la app")
    analizador.add_argument("--verbose", action="store_true")
    args = analizador.parse_args()

    CONFIG["puerto"] = args.puerto
    CONFIG["token"] = args.token
    CONFIG["verbose"] = args.verbose

    ip = ip_local()
    print("")
    print("  Tik9 Relay %s   Python %s" % (VERSION, sys.version.split()[0]))
    print("  " + "-" * 52)
    print("  Escuchando en   0.0.0.0:%d" % CONFIG["puerto"])
    print("  En este PC      http://127.0.0.1:%d" % CONFIG["puerto"])
    print("  En el iPhone    http://%s:%d" % (ip, CONFIG["puerto"]))
    if CONFIG["token"]:
        print("  Token           %s" % CONFIG["token"])
    print("  " + "-" * 52)
    print("  Es OPCIONAL: la app reproduce sola.  Deja esto abierto solo si lo usas.")
    print("  Para parar: Ctrl+C")
    print("")

    servidor = ThreadingHTTPServer(("0.0.0.0", CONFIG["puerto"]), Manejador)
    servidor.daemon_threads = True
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        print("\n  Relay detenido.")
        servidor.shutdown()


if __name__ == "__main__":
    main()
