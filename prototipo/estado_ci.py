# -*- coding: utf-8 -*-
"""Mira como va la construccion de GitHub Actions y, si se pide, descarga el IPA.

En este PC (Windows 7) PowerShell se atasca con api.github.com, asi que la
consulta se hace desde Python, que ya se usa para todo lo demas.

Uso:
    python prototipo/estado_ci.py            mira la ultima ejecucion
    python prototipo/estado_ci.py --espera   espera a que acabe (hasta 40 min)
    python prototipo/estado_ci.py --bajar    descarga el IPA de la ultima
                                             construccion terminada bien y lo
                                             deja en entrega/Tik9.ipa
"""

import json
import os
import re
import sys
import time
import urllib.request

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "lofturb/tik9"


def token():
    ruta = os.path.join(os.environ.get("APPDATA", ""), "GitHub CLI", "hosts.yml")
    with open(ruta, "r", encoding="utf-8", errors="replace") as f:
        texto = f.read()
    m = re.search(r"oauth_token:\s*(\S+)", texto)
    if not m:
        raise SystemExit("No hay oauth_token en hosts.yml")
    return m.group(1)


def pedir(url, crudo=False, destino=None):
    pet = urllib.request.Request(url)
    pet.add_header("User-Agent", "tik9-ci")
    pet.add_header("Authorization", "token " + token())
    if destino:
        # El binario del Release: sin este Accept, la API devuelve el JSON del
        # activo (1,6 kB) en vez del .ipa.
        pet.add_header("Accept", "application/octet-stream")
    elif crudo:
        pet.add_header("Accept", "application/vnd.github+json")
    with urllib.request.urlopen(pet, timeout=60) as r:
        datos = r.read()
    if destino:
        with open(destino, "wb") as f:
            f.write(datos)
        return len(datos)
    if crudo:
        return json.loads(datos.decode("utf-8"))
    return datos


def ultima():
    d = pedir("https://api.github.com/repos/%s/actions/runs?per_page=5" % REPO, crudo=True)
    return d["workflow_runs"]


def resumen(ejecucion):
    return "%s  %s  %s  %s" % (
        ejecucion["id"], ejecucion["head_sha"][:7],
        ejecucion["status"], ejecucion.get("conclusion") or "-")


def main():
    argumentos = sys.argv[1:]
    esperar = "--espera" in argumentos
    bajar = "--bajar" in argumentos

    limite = time.time() + 40 * 60
    while True:
        ejecuciones = ultima()
        if not ejecuciones:
            raise SystemExit("No hay ejecuciones")
        actual = ejecuciones[0]
        print(resumen(actual), flush=True)
        if actual["status"] == "completed" or not esperar:
            if actual["status"] == "completed" and actual.get("conclusion") == "success":
                print("terminada bien: %s" % actual["html_url"])
            elif actual["status"] == "completed":
                print("terminada MAL: %s" % actual["html_url"])
            break
        if time.time() > limite:
            print("se acabo el tiempo de espera")
            break
        time.sleep(20)

    if not bajar:
        return

    # Se baja TODO lo que deja la ultima Release: el .ipa y el .deb.
    publicaciones = pedir("https://api.github.com/repos/%s/releases?per_page=5" % REPO,
                          crudo=True)
    if not publicaciones:
        print("no hay Releases")
        return
    publicacion = publicaciones[0]
    print("Release %s  (commit de la ejecucion de arriba: %s)"
          % (publicacion["tag_name"], ultima()[0]["head_sha"][:7]))
    for activo in publicacion.get("assets", []):
        nombre = activo["name"]
        if nombre.endswith(".ipa"):
            destino = os.path.join(RAIZ, "entrega", "Tik9.ipa")
        elif nombre.endswith(".deb"):
            destino = os.path.join(RAIZ, "entrega", "Tik9.deb")
        else:
            continue
        pedir(activo["url"], destino=destino)
        print("  %s -> %s (%d bytes)" % (nombre, os.path.basename(destino),
                                         os.path.getsize(destino)))


if __name__ == "__main__":
    main()
