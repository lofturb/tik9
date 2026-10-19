# -*- coding: utf-8 -*-
"""
log_ci.py -- baja el registro de la ultima construccion y ensena lo que importa.

La API de GitHub no entrega el registro directamente: contesta con una redireccion
a un almacen externo, y alli la cabecera Authorization sobra (incluso rompe la
peticion).  Python la reenvia al seguir la redireccion y se come un 403, asi que
aqui se quita en el salto.

Uso:
    python prototipo/log_ci.py                      lo que parece un error
    python prototipo/log_ci.py --buscar "CMake Error"   lineas alrededor de eso
    python prototipo/log_ci.py --paso "BoringSSL"       solo el trozo de ese paso
    python prototipo/log_ci.py --todo                    todo el registro
"""

import re
import sys
import urllib.request

import estado_ci as E

# Lo que suele delatar un fallo de verdad en un registro de GitHub Actions.
SOSPECHOSO = re.compile(
    r"(error:|Error |ERROR|fatal|Fatal|FAILED|failed|No such file|not found|"
    r"undefined|Undefined|cannot|Can't|CMake Error|Segmentation)", re.I)


class SinAutorizacionAlSaltar(urllib.request.HTTPRedirectHandler):
    """Sigue la redireccion sin la cabecera Authorization."""

    def redirect_request(self, req, fp, codigo, mensaje, cabeceras, nueva):
        peticion = super().redirect_request(req, fp, codigo, mensaje, cabeceras, nueva)
        if peticion is not None:
            peticion.remove_header("Authorization")
            peticion.add_header("User-Agent", "tik9-ci")
        return peticion


def registro(direccion):
    abridor = urllib.request.build_opener(SinAutorizacionAlSaltar)
    peticion = urllib.request.Request(direccion)
    peticion.add_header("User-Agent", "tik9-ci")
    peticion.add_header("Authorization", "token " + E.token())
    with abridor.open(peticion, timeout=90) as r:
        return r.read().decode("utf-8", "replace")


def limpiar(linea):
    """Quita la fecha/hora que GitHub pone delante de cada linea."""
    return re.sub(r"^\d{4}-\d\d-\d\dT[\d:.]+Z\s?", "", linea).rstrip()


def main():
    argumentos = sys.argv[1:]
    todo = "--todo" in argumentos
    buscar = None
    paso = None
    guardar = None
    for i, a in enumerate(argumentos):
        if a == "--buscar" and i + 1 < len(argumentos):
            buscar = argumentos[i + 1]
        elif a == "--paso" and i + 1 < len(argumentos):
            paso = argumentos[i + 1].lower()
        elif a == "--guardar" and i + 1 < len(argumentos):
            guardar = argumentos[i + 1]

    ejecucion = E.ultima()[0]
    print("ejecucion %s  %s  %s" % (ejecucion["id"], ejecucion["head_sha"][:7],
                                    ejecucion.get("conclusion")))
    trabajos = E.pedir("https://api.github.com/repos/%s/actions/runs/%s/jobs"
                       % (E.REPO, ejecucion["id"]), crudo=True)

    for trabajo in trabajos["jobs"]:
        print("\n--- trabajo: %s ---" % trabajo["name"])
        for cual in trabajo["steps"]:
            print("    %-55s %s" % (cual["name"], cual.get("conclusion") or "-"))

        lineas = [limpiar(l) for l in
                  registro("https://api.github.com/repos/%s/actions/jobs/%s/logs"
                           % (E.REPO, trabajo["id"])).splitlines()]

        if guardar:
            with open(guardar, "w", encoding="utf-8") as f:
                f.write("\n".join(lineas))
            print("registro guardado en %s (%d lineas)" % (guardar, len(lineas)))

        # Trozo del paso pedido: desde su "Run" hasta el siguiente grupo.
        if paso:
            dentro = False
            recorte = []
            for linea in lineas:
                if not dentro and "##[group]" in linea and paso in linea.lower():
                    dentro = True
                    continue
                if dentro and "##[endgroup]" in linea:
                    break
                if dentro:
                    recorte.append(linea)
            lineas = recorte
            print("\n=== paso %r: %d lineas ===" % (paso, len(lineas)))

        if todo:
            for linea in lineas:
                print(linea)
            continue

        patron = re.compile(re.escape(buscar), re.I) if buscar else SOSPECHOSO
        vistas = 0
        for i, linea in enumerate(lineas):
            if not patron.search(linea):
                continue
            if linea.strip() in ("", "##[endgroup]"):
                continue
            desde = max(0, i - 2)
            hasta = min(len(lineas), i + 3)
            print("\n  ...")
            for j in range(desde, hasta):
                print("  " + lineas[j][:240])
            vistas += 1
            if vistas >= 40:
                print("\n  (cortado a 40 coincidencias)")
                break
    return 0


if __name__ == "__main__":
    sys.exit(main())
