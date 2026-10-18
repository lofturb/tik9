# -*- coding: utf-8 -*-
"""
servidor_instalador.py -- sirve la pagina de instalacion de Tik9 y recoge el
informe del diagnostico.

Es el servidor que se abre en el telefono (http://<ip-de-este-PC>/) para
descargar el .ipa y los certificados.  Ademas del servidor de ficheros de
siempre (SimpleHTTPRequestHandler, tal cual), atiende dos cosas mas:

    POST /informe    Recibe el texto que se pega en la pagina (el informe de
                     Ajustes -> Probar la busqueda en Tik9) y lo guarda en
                     entrega/informes.txt.  Asi el informe llega al PC sin
                     copiarlo a mano: se pega en el navegador del movil.

    GET  /informes   Devuelve lo guardado en texto plano, para mirarlo desde el
                     propio navegador (o desde consola).

Uso:
    python tools/servidor_instalador.py            # puerto 80, toda la red
    python tools/servidor_instalador.py 8080       # otro puerto

La raiz que sirve es la carpeta del repositorio (la de arriba), para que
/certificados/... y /entrega/Tik9.ipa caigan donde toca.
"""

import datetime
import http.server
import os
import socketserver
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INFORMES = os.path.join(RAIZ, "entrega", "informes.txt")
TOPE_BYTES = 200 * 1024


def guardar_informe(texto, origen):
    """Apunta el informe al final del fichero, con fecha y desde donde vino."""
    os.makedirs(os.path.dirname(INFORMES), exist_ok=True)
    cuando = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(INFORMES, "a", encoding="utf-8") as f:
        f.write("\n%s\n===== informe de %s =====\n" % ("-" * 60, cuando))
        f.write("(desde %s)\n" % origen)
        f.write(texto.strip() + "\n")
    return len(texto)


class Manejador(http.server.SimpleHTTPRequestHandler):
    """Ficheros de siempre (para instalar) mas el buzon de informes."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=RAIZ, **kwargs)

    def _ruta(self):
        return self.path.split("?")[0].rstrip("/") or "/"

    def do_POST(self):  # noqa: N802  (lo pide la clase base)
        if self._ruta() != "/informe":
            self.send_error(404, "Solo se puede enviar en /informe")
            return
        try:
            largo = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            largo = 0
        if largo <= 0 or largo > TOPE_BYTES:
            self.send_error(400, "Informe vacio o demasiado largo")
            return
        texto = self.rfile.read(largo).decode("utf-8", "replace")
        if not texto.strip():
            self.send_error(400, "Informe vacio")
            return
        try:
            cuantos = guardar_informe(texto, self.client_address[0])
        except OSError as fallo:
            self.send_error(500, "No se pudo guardar: %s" % fallo)
            return
        print("informe guardado: %d caracteres desde %s"
              % (cuantos, self.client_address[0]))
        self.responder_texto("Guardado en el ordenador (%d caracteres).\n" % cuantos)

    def do_GET(self):  # noqa: N802
        if self._ruta() == "/informes":
            try:
                with open(INFORMES, encoding="utf-8") as f:
                    contenido = f.read()
            except OSError:
                contenido = "(todavia no hay ningun informe guardado)\n"
            self.responder_texto(contenido)
            return
        super().do_GET()

    def responder_texto(self, texto):
        datos = texto.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(datos)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(datos)

    def log_message(self, formato, *args):
        # Igual que el de serie, pero tambien en horario local y mas corto.
        print("%s  %s" % (self.log_date_time_string(), formato % args))


class Servidor(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    puerto = 80
    if len(sys.argv) > 1:
        puerto = int(sys.argv[1])
    servidor = Servidor(("0.0.0.0", puerto), Manejador)
    print("Tik9: sirviendo %s" % RAIZ)
    print("  instalacion : http://<ip-de-este-PC>%s/"
          % ("" if puerto == 80 else ":%d" % puerto))
    print("  informes    : http://<ip-de-este-PC>%s/informes"
          % ("" if puerto == 80 else ":%d" % puerto))
    print("  se guardan en %s" % INFORMES)
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        print("\nparando")


if __name__ == "__main__":
    main()
