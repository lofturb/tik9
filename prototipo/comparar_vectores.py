# -*- coding: utf-8 -*-
"""
comparar_vectores.py -- ejecuta el port en C y el oraculo de Python y difunde.

Compila prueba_vector.c con TCC (si se le pasa la ruta del compilador por la
variable TCC o como primer argumento), lo ejecuta, ejecuta
vector_referencia.py y compara linea a linea.  Devuelve 0 si coinciden.

Uso:  python comparar_vectores.py [ruta\\a\\tcc.exe]
"""

import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PRUEBAS = os.path.join(RAIZ, "app", "pruebas")
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")


def tcc():
    for ruta in (sys.argv[1] if len(sys.argv) > 1 else None, os.environ.get("TCC")):
        if ruta and os.path.isfile(ruta):
            return ruta
    for ruta in (
        r"C:\Users\Loftur\AppData\Local\Temp\opencode\tcc\tcc\tcc.exe",
        "tcc", "tcc.exe",
    ):
        return ruta
    return "tcc"


def ejecuta(cmd, cwd):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, env=ENV)
    if p.returncode != 0:
        sys.stderr.write(p.stderr.decode("utf-8", "replace"))
        raise SystemExit("fallo: %r" % (cmd,))
    return p.stdout.decode("utf-8", "replace").replace("\r\n", "\n").strip()


def main():
    compilador = tcc()
    exe = os.path.join(PRUEBAS, "prueba_vector.exe")
    print("compilador:", compilador)
    subprocess.run(
        [compilador, "-o", exe, os.path.join(PRUEBAS, "prueba_vector.c"),
         os.path.join(RAIZ, "app", "TTSignaCore.c")],
        cwd=PRUEBAS, check=True,
    )

    c = ejecuta([exe], PRUEBAS).split("\n")
    py = ejecuta([sys.executable, os.path.join(AQUI, "vector_referencia.py")], AQUI).split("\n")

    ok = True
    for i in range(max(len(c), len(py))):
        a = c[i] if i < len(c) else "<falta en C>"
        b = py[i] if i < len(py) else "<falta en Python>"
        if a == b:
            print("OK   %s" % a[:100])
        else:
            ok = False
            print("DIF  C      : %s" % a[:160])
            print("     Python : %s" % b[:160])

    print("-" * 70)
    print("VECTORES COINCIDEN" if ok else "HAY DIFERENCIAS")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
