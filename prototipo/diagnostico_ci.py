# -*- coding: utf-8 -*-
"""Cuenta por que fallo la ultima construccion de GitHub Actions.

Baja la lista de trabajos y pasos (que dice cual cayo) y el archivo de
registros en zip, y enseña el final del paso que fallo.

Uso:
    python prototipo/diagnostico_ci.py            ultima ejecucion
    python prototipo/diagnostico_ci.py 12345678   una ejecucion concreta
"""

import io
import json
import os
import re
import sys
import urllib.request
import zipfile

REPO = "lofturb/tik9"


def token():
    ruta = os.path.join(os.environ.get("APPDATA", ""), "GitHub CLI", "hosts.yml")
    with open(ruta, "r", encoding="utf-8", errors="replace") as f:
        return re.search(r"oauth_token:\s*(\S+)", f.read()).group(1)


def api(url, aceptar="application/vnd.github+json"):
    pet = urllib.request.Request(url)
    pet.add_header("User-Agent", "tik9-diag")
    pet.add_header("Authorization", "token " + token())
    pet.add_header("Accept", aceptar)
    with urllib.request.urlopen(pet, timeout=120) as r:
        return r.read()


def main():
    if len(sys.argv) > 1:
        ejecucion = int(sys.argv[1])
    else:
        ejecuciones = json.loads(api("https://api.github.com/repos/%s/actions/runs?per_page=5"
                                     % REPO).decode("utf-8"))["workflow_runs"]
        ejecucion = ejecuciones[0]["id"]
    print("ejecucion %s" % ejecucion)

    trabajos = json.loads(api("https://api.github.com/repos/%s/actions/runs/%s/jobs"
                             % (REPO, ejecucion)).decode("utf-8"))["jobs"]
    for trabajo in trabajos:
        print("trabajo %s: %s (%s)" % (trabajo["name"], trabajo["conclusion"],
                                       trabajo["html_url"]))
        for paso in trabajo["steps"]:
            marca = "  " if paso["conclusion"] == "success" else "!!"
            print("%s %-55s %s" % (marca, paso["name"], paso["conclusion"]))

    datos = api("https://api.github.com/repos/%s/actions/runs/%s/logs"
                % (REPO, ejecucion), "application/vnd.github+json")
    z = zipfile.ZipFile(io.BytesIO(datos))
    malos = [n for n in z.namelist()
             if any(p["conclusion"] == "failure" for t in trabajos for p in t["steps"]
                    if t["name"].split(" / ")[-1] in n or True)]
    # Se enseña el final del registro de cada paso que fallo.
    for nombre in z.namelist():
        texto = z.read(nombre).decode("utf-8", "replace")
        if "error" not in texto.lower() and "Error" not in texto:
            continue
        # Solo los pasos que fallaron: el registro trae los grupos "##[error]".
        if "##[error]" not in texto:
            continue
        print("=== %s ===" % nombre)
        lineas = [l for l in texto.splitlines() if "ld: warning" not in l]
        for i, linea in enumerate(lineas):
            if "##[error]" in linea or "Error" in linea or "error:" in linea:
                for seguida in lineas[max(0, i - 45):i + 6]:
                    print("  %s" % seguida)
                print("  ...")
                break


if __name__ == "__main__":
    main()
