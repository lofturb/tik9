# -*- coding: utf-8 -*-
"""Mira por dentro un paquete .deb (de los que instala Cydia o Filza).

Un .deb es un archivo "ar" con tres piezas: debian-binary, control.tar.* y
data.tar.*.  Aqui interesa sobre todo verificar que la app va a /Applications,
que el ejecutable esta, y que el postinst (el que refresca LaunchServices)
viaja dentro; y comprobar que dpkg no va a atragantarse por el formato.

Uso:
    python tools/verificar_deb.py entrega/Tik9.deb
"""

import io
import os
import sys
import tarfile

FICHERO_MAGICO = b"!<arch>\n"


def trozos_ar(datos):
    """Devuelve [(nombre, contenido)] de un archivo ar."""
    if not datos.startswith(FICHERO_MAGICO):
        raise ValueError("no empieza por !<arch>")
    pos = len(FICHERO_MAGICO)
    trozos = []
    while pos + 60 <= len(datos):
        cabecera = datos[pos:pos + 60]
        nombre = cabecera[0:16].decode("utf-8", "replace").strip()
        try:
            tam = int(cabecera[48:58].decode("ascii").strip())
        except ValueError:
            break
        inicio = pos + 60
        contenido = datos[inicio:inicio + tam]
        trozos.append((nombre, contenido))
        pos = inicio + tam + (tam % 2)     # los trozos van a pares de bytes
    return trozos


def abrir_tar(contenido):
    """data.tar puede venir en gz, xz o sin comprimir."""
    for modo in ("r:gz", "r:xz", "r:"):
        try:
            return tarfile.open(fileobj=io.BytesIO(contenido), mode=modo)
        except Exception:
            continue
    raise ValueError("no se pudo abrir el tar del paquete")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    ruta = sys.argv[1]
    with open(ruta, "rb") as f:
        datos = f.read()
    print("=== Paquete ===")
    print("  fichero : %s (%d bytes)" % (os.path.basename(ruta), len(datos)))

    trozos = trozos_ar(datos)
    print("  piezas  : %s" % ", ".join(n for n, _ in trozos))

    control = None
    datos_tar = None
    for nombre, contenido in trozos:
        if nombre.startswith("control.tar"):
            control = contenido
        elif nombre.startswith("data.tar"):
            datos_tar = contenido
    if datos_tar is None:
        print("  ERROR: no hay data.tar")
        return 1

    if control is not None:
        print("=== control ===")
        with abrir_tar(control) as tar_control:
            for miembro in tar_control.getmembers():
                # Dentro del paquete las rutas van como ./postinst
                nombre = miembro.name.rsplit("/", 1)[-1]
                if nombre == "control":
                    texto = tar_control.extractfile(miembro).read().decode("utf-8", "replace")
                    for linea in texto.splitlines():
                        print("  %s" % linea)
                elif nombre in ("postinst", "preinst", "prerm", "postrm"):
                    ejecutable = (miembro.mode & 0o111) != 0
                    print("  guion %s: si (permisos %o, %s)"
                          % (nombre, miembro.mode,
                             "ejecutable" if ejecutable else "NO EJECUTABLE"))

    print("=== contenido (nombres importantes) ===")
    with abrir_tar(datos_tar) as tar:
        nombres = [m.name for m in tar.getmembers()]
        interesantes = [n for n in nombres
                        if n.endswith("Tik9") or n.endswith("Info.plist")
                        or n.endswith("PkgInfo") or n.rstrip("/").endswith("Tik9.app")]
        for n in sorted(set(interesantes)):
            print("  /%s" % n.strip("/"))
        ejecutable = [n for n in nombres if n.endswith("/Tik9") and "Tik9.app" in n]
        print("=== resumen ===")
        print("  entradas          : %d" % len(nombres))
        print("  se instala en     : %s"
              % ("/Applications" if any("Applications/Tik9.app" in n for n in nombres)
                 else "NO se ve /Applications"))
        print("  ejecutable        : %s" % (", ".join("/" + e.strip("/") for e in ejecutable) or "NO"))
        tienen_permiso = [e for e in ejecutable
                          if [m for m in tar.getmembers() if m.name == e][0].mode & 0o111]
        print("  permiso de ejec.  : %s" % ("si" if tienen_permiso else "NO"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
