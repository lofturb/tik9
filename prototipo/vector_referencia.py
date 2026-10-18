# -*- coding: utf-8 -*-
"""
vector_referencia.py -- genera los vectores de referencia desde xgnarly.py.

Produce por stdout el mismo formato que app/pruebas/prueba_vector.c, con las
mismas entradas fijas, para que comparar_vectores.py pueda difundir ambos.

Uso:  python vector_referencia.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hashlib  # noqa: E402

from xgnarly import hash_state, sign  # noqa: E402

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0"
)

CLAVE1 = (
    305419896, 2596069104, 19088743, 2309737967, 3735928559, 3405691582,
    4275878552, 1431655765, 2863311530, 4294967295, 1, 0,
)
CLAVE2 = (16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192)

TS = 1700000000
NONCE = 123456789
NONCE2 = 3600000000

K0 = ["aid", "app_language", "browser_version", "device_id", "itemId",
      "os", "region", "screen_height"]
V0 = ["1988", "en-US",
      "5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0",
      "7123456789012345678", "7106594312292453675", "windows", "US", "1080"]

K1 = ["cursor", "count", "secUid"]
V1 = ["0", "16", "MS4wLjABAAAA-not-a-real-sec-uid"]

K2 = ["q", "unicode", "plus", "percent"]
V2 = ["a b\"c<d>e`f#g/h:i,j(k)l", "café 中文", "a+b=c&d", "100%"]


def emite_firma(nombre, claves, valores, ms):
    firmado, _ = sign(
        list(zip(claves, valores)), UA, ms_token=ms,
        timestamp=TS, nonce=NONCE, nonce2=NONCE2, key=CLAVE1, key2=CLAVE2,
    )
    linea = "firma %s = %s" % (nombre, firmado)
    print("firma %s len = %d" % (nombre, len(firmado)))
    print(linea)


def main():
    print("md5 vacio    = %s" % hashlib.md5(b"").hexdigest())
    print("md5 abc      = %s" % hashlib.md5(b"abc").hexdigest())
    print("md5 pangrama = %s" % hashlib.md5(
        b"The quick brown fox jumps over the lazy dog").hexdigest())
    print("md5 largo    = %s" % hashlib.md5(b"0123456789" * 7).hexdigest())

    print("hash vacio   = %d" % hash_state(""))
    print("hash abc     = %d" % hash_state("abc"))
    print("hash ua      = %d" % hash_state(UA))

    emite_firma("0", K0, V0, "")
    emite_firma("1", K0, V0, "Fk9xQ2mN7pL4vR8tY1wZ3bC6dE0gH5jK")
    emite_firma("2", K1, V1, "")
    emite_firma("3", K2, V2, "")


if __name__ == "__main__":
    main()
