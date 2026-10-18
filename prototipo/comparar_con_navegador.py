# -*- coding: utf-8 -*-
"""
comparar_con_navegador.py -- abre la firma capturada del navegador y la compara
campo por campo con la que genera NUESTRO signer para la misma consulta.

Objetivo: buscar que cambio en el entorno (Chrome 122 -> 152) y que campos
valida ahora el endpoint de search.  Los campos 0x26 (env_code) y 0x36
(ub_code) del X-Dynosaur y 0x01/0x02 del X-Gnarly son los unicos que el
servidor valida; si el navegador actual reporta otros valores, ahi esta el
rechazo (200 vacio con tt_orcas_res: 1).

Uso:  python comparar_con_navegador.py
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xgnarly as X  # noqa: E402

CAPTURA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "busqueda_navegador.json")

_ENCODER_A = X._ENCODER_A
_ENCODER_B = X._ENCODER_B


def decodificar(crudo, config):
    """Inversa exacta de _encode_bytes para valores _ENCODER_A/_ENCODER_B."""
    xor_base, add_base, pre_xor, rotate, post_add = config
    n = crudo[len(crudo) - 1]
    letras = []
    for index in range(n):
        v = (crudo[index] - post_add) % 256
        v ^= 187
        v = ((v >> rotate) | (v << (8 - rotate))) & 0xFF
        if pre_xor is not None:
            v ^= pre_xor
        v = (v - add_base - (170 & index)) % 256
        v ^= (xor_base + index) & 0xFF
        letras.append(chr(v))
    return "".join(letras)


def partir(payload):
    """Parte un payload TLV en {clave: bytes}."""
    campos = {}
    i = 0
    if payload and len(payload) > 1 and payload[0] < 0x20:
        # X-Gnarly lleva un conteo inicial de campos delante
        i = 1
    while i < len(payload):
        k = payload[i]
        n = payload[i + 2]
        campos[k] = payload[i + 3:i + 3 + n]
        i += 3 + n
    return campos


def mostrar(nombre, campos, claves_codificadas, claves_enteras):
    print("--- %s (%d campos)" % (nombre, len(campos)))
    for k in sorted(campos):
        crudo = campos[k]
        if k in claves_enteras:
            print("  0x%02X  %d  (%d B)" % (k, int.from_bytes(crudo, "big"), len(crudo)))
        elif k in claves_codificadas:
            cfg = _ENCODER_B if k in (0x20, 0x21, 0x22) else _ENCODER_A
            print("  0x%02X  %-28r  (%d B)" % (k, decodificar(crudo, cfg).encode("ascii", "backslashreplace").decode(), len(crudo)))
        else:
            print("  0x%02X  %s  (%d B)" % (k, crudo.decode("ascii", "replace"), len(crudo)))


def diferir(nombre, browser, nuestro, claves_codificadas, claves_enteras, saltar):
    print("--- diferencias %s" % nombre)
    difs = 0
    for k in sorted(set(browser) | set(nuestro)):
        if k in saltar:
            continue
        b = browser.get(k)
        n = nuestro.get(k)
        if b == n:
            continue
        difs += 1
        def fmt(v):
            if v is None:
                return "<falta>"
            if k in claves_enteras:
                return str(int.from_bytes(v, "big"))
            if k in claves_codificadas:
                cfg = _ENCODER_B if k in (0x20, 0x21, 0x22) else _ENCODER_A
                return repr(decodificar(v, cfg)).encode("ascii", "backslashreplace").decode()
            return v.decode("ascii", "replace")
        print("  0x%02X  navegador=%s  nuestro=%s" % (k, fmt(b), fmt(n)))
    if difs == 0:
        print("  (identicos fuera de los excluidos)")
    return difs


def main():
    cap = json.load(open(CAPTURA, encoding="utf-8-sig"))
    ua = cap["ua"]
    negocio = cap["negocioRaw"]

    print("abriendo X-Dynosaur del navegador (%d car.)..." % len(cap["dynosaur"]))
    payload_b, clave_b = X.unseal(cap["dynosaur"])
    campos_b = partir(payload_b)

    print("abriendo X-Gnarly del navegador (%d car.)..." % len(cap["xGnarly"]))
    payload_g, clave_g = X.unseal(cap["xGnarly"])
    campos_g = partir(payload_g)

    COD_DYN = {0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A,
               0x2C, 0x2D, 0x2E, 0x2F, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37}
    ENT_DYN = {0x2B, 0x2E, 0x30, 0x38}
    COD_GN = set()
    ENT_GN = {0x00, 0x01, 0x02, 0x06, 0x08, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10}

    mostrar("X-Dynosaur del NAVEGADOR", campos_b, COD_DYN, ENT_DYN)
    mostrar("X-Gnarly del NAVEGADOR", campos_g, COD_GN, ENT_GN)

    # valores que reporta el navegador de verdad (0x27/0x34/0x25 van CODIFICADOS)
    ts = int(decodificar(campos_b[0x27], _ENCODER_A))
    nonce = int(decodificar(campos_b[0x34], _ENCODER_A))
    secuencia = int(decodificar(campos_b[0x25], _ENCODER_A))
    env_b = int(decodificar(campos_b[0x26], _ENCODER_A))
    ub_b = int(decodificar(campos_b[0x36], _ENCODER_A))
    nonce2 = int.from_bytes(campos_g[0x0F], "big")
    env_g = int.from_bytes(campos_g[0x01], "big")
    ub_g = int.from_bytes(campos_g[0x02], "big")
    print()
    print("NAVEGADOR: timestamp=%d nonce=%d secuencia=%d" % (ts, nonce, secuencia))
    print("NAVEGADOR: env_code dynosaur=%d gnarly=%d   ub_code dynosaur=%d gnarly=%d"
          % (env_b, env_g, ub_b, ub_g))
    print("NOSOTROS : env_code=%d ub_code=%d" % (X.ENV_CODE, X.UB_CODE))

    # validacion de la consulta: hash_state del negocioRaw contra el 0x2E capturado
    hs = X.hash_state(negocio)
    print("hash_state(negocioRaw)=0x%08X  navegador=0x%08X  %s" % (
        hs, int.from_bytes(campos_b[0x2E], "big"),
        "COINCIDE" if hs == int.from_bytes(campos_b[0x2E], "big") else "DIFIERE"))
    hua = X.hash_state(ua)
    print("hash_state(UA)        =0x%08X  navegador=0x%08X  %s" % (
        hua, int.from_bytes(campos_b[0x30], "big"),
        "COINCIDE" if hua == int.from_bytes(campos_b[0x30], "big") else "DIFIERE"))

    # nuestro dynosaur para la misma consulta con los mismos ts/nonce/secuencia
    nuestro_dyn = X.dynosaur_payload(negocio, ua, timestamp=ts, nonce=nonce, sequence=secuencia)
    campos_n = partir(nuestro_dyn)
    mostrar("X-Dynosaur NUESTRO (mismos ts/nonce)", campos_n, COD_DYN, ENT_DYN)
    diferir("X-Dynosaur", campos_b, campos_n, COD_DYN, ENT_DYN, saltar={0x20})

    # nuestro gnarly sobre la consulta sellada tal cual la mando el navegador
    sellada = "%s&%s=%s&%s=%s" % (negocio, X.DYNOSAUR_PARAM, cap["dynosaur"],
                                  X.MS_TOKEN_PARAM, cap["msTokenConsulta"])
    nuestro_gn = X.gnarly_fields(sellada, ua, timestamp=ts, nonce=nonce, nonce2=nonce2,
                                 sequence=secuencia)
    diferir("X-Gnarly", campos_g, nuestro_gn, COD_GN, ENT_GN, saltar={0x00, 0x10})


if __name__ == "__main__":
    main()
