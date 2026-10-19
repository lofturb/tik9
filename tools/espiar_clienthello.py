# -*- coding: utf-8 -*-
"""
espiar_clienthello.py -- escucha en un puerto TLS y cuenta lo que trae el saludo
del cliente (ClientHello).

Sirve para una pregunta que desde el telefono no se puede contestar: ?ofrece
HTTP/2 este aparato?  El protocolo HTTP se pacta en ALPN, dentro del saludo TLS,
asi que el propio saludo lo dice.  Da igual que despues la conexion falle por el
certificado: el saludo llega antes de que nadie mire certificados.

Uso:
    python tools/espiar_clienthello.py            # escucha en el 443
    python tools/espiar_clienthello.py --puerto 8443

Y desde el aparato se abre https://<ip-de-este-PC>/ (aunque el navegador avise
del certificado: el aviso sale DESPUES del saludo, que ya estara apuntado).

Lo que imprime, por cada visita:

    ALPN ofrecido     : h2, http/1.1   <-- ?esta h2?
    versiones TLS     : TLS1.3, TLS1.2
    grupos            : x25519, secp256r1
    cifrados          : 17 (AEAD 12, CBC 5)
    nombre pedido     : 192.168.1.7

Referencia rapida de lo que significa:
  * Si NO aparece 'h2' en ALPN, ese cliente no va a hablar HTTP/2 con nadie:
    el servidor no puede elegirlo aunque quiera.
  * Si aparece 'h2' y aun asi las respuestas de TikTok traen la cabecera
    Connection (que en HTTP/2 no existe), entonces el que elige HTTP/1.1 es el
    otro lado (o algo que se mete por medio).
"""

import argparse
import socket
import struct
import sys
import threading
import time

VERSIONES = {0x0304: "TLS1.3", 0x0303: "TLS1.2", 0x0302: "TLS1.1", 0x0301: "TLS1.0"}
GRUPOS = {0x001D: "x25519", 0x0017: "secp256r1(P-256)", 0x0018: "secp384r1",
          0x0019: "secp521r1", 0x0100: "ffdhe2048", 0x0101: "ffdhe3072"}

# Unos cuantos cifrados, los que importan para ATS y para HTTP/2 (que prohibe los
# CBC y los RC4: el protocolo exige cifrado autenticado).
CIFRADOS = {
    0x1301: "TLS_AES_128_GCM_SHA256", 0x1302: "TLS_AES_256_GCM_SHA384",
    0x1303: "TLS_CHACHA20_POLY1305_SHA256",
    0xC02B: "ECDHE_ECDSA_AES_128_GCM", 0xC02F: "ECDHE_RSA_AES_128_GCM",
    0xC02C: "ECDHE_ECDSA_AES_256_GCM", 0xC030: "ECDHE_RSA_AES_256_GCM",
    0xCCA8: "ECDHE_RSA_CHACHA20", 0xCCA9: "ECDHE_ECDSA_CHACHA20",
    0xC009: "ECDHE_ECDSA_AES_128_CBC", 0xC013: "ECDHE_RSA_AES_128_CBC",
    0xC00A: "ECDHE_ECDSA_AES_256_CBC", 0xC014: "ECDHE_RSA_AES_256_CBC",
    0x009C: "RSA_AES_128_GCM", 0x009D: "RSA_AES_256_GCM",
    0x002F: "RSA_AES_128_CBC", 0x0035: "RSA_AES_256_CBC",
    0x000A: "RSA_3DES_CBC", 0x0005: "RSA_RC4_128_SHA",
}
AEAD = ("_GCM", "CHACHA20", "TLS_AES_")


def leer_exacto(sock, cuantos):
    datos = b""
    while len(datos) < cuantos:
        trozo = sock.recv(cuantos - len(datos))
        if not trozo:
            return None
        datos += trozo
    return datos


def trocear_extensiones(blob):
    """Devuelve {tipo: datos} de la lista de extensiones del saludo."""
    salida = {}
    i = 0
    while i + 4 <= len(blob):
        tipo, largo = struct.unpack(">HH", blob[i:i + 4])
        salida[tipo] = blob[i + 4:i + 4 + largo]
        i += 4 + largo
    return salida


def analizar_saludo(registro):
    """Saca lo interesante del ClientHello.  Devuelve un diccionario."""
    if len(registro) < 5 or registro[0] != 22:          # 22 = handshake
        return None
    cuerpo = registro[5:]
    if len(cuerpo) < 4 or cuerpo[0] != 1:               # 1 = ClientHello
        return None
    largo = int.from_bytes(cuerpo[1:4], "big")
    hola = cuerpo[4:4 + largo]

    version_cliente = struct.unpack(">H", hola[0:2])[0]
    i = 2 + 32                                          # version + random
    i += 1 + hola[i]                                    # session_id
    cifrados_largo = struct.unpack(">H", hola[i:i + 2])[0]
    i += 2
    cifrados = [struct.unpack(">H", hola[j:j + 2])[0]
                for j in range(i, i + cifrados_largo, 2)]
    i += cifrados_largo
    i += 1 + hola[i]                                    # compresion
    extensiones = {}
    if i + 2 <= len(hola):
        largo_ext = struct.unpack(">H", hola[i:i + 2])[0]
        extensiones = trocear_extensiones(hola[i + 2:i + 2 + largo_ext])

    alpn, versiones, grupos, nombre = [], [], [], ""
    # ALPN (0x0010): 2 bytes de largo + lista de (largo + nombre)
    if 0x0010 in extensiones:
        blob = extensiones[0x0010]
        j = 2
        while j < len(blob):
            n = blob[j]
            alpn.append(blob[j + 1:j + 1 + n].decode("ascii", "replace"))
            j += 1 + n
    # supported_versions (0x002b): en el saludo, lista con largo de 1 byte
    if 0x002b in extensiones:
        blob = extensiones[0x002b]
        j = 1
        while j + 2 <= len(blob):
            versiones.append(struct.unpack(">H", blob[j:j + 2])[0])
            j += 2
    else:
        versiones = [version_cliente]
    # supported_groups (0x000a)
    if 0x000A in extensiones:
        blob = extensiones[0x000A]
        j = 2
        while j + 2 <= len(blob):
            grupos.append(struct.unpack(">H", blob[j:j + 2])[0])
            j += 2
    # server_name (0x0000)
    if 0x0000 in extensiones:
        blob = extensiones[0x0000]
        n = struct.unpack(">H", blob[3:5])[0] if len(blob) >= 5 else 0
        nombre = blob[5:5 + n].decode("ascii", "replace")

    return {"alpn": alpn, "versiones": versiones, "grupos": grupos,
            "cifrados": cifrados, "nombre": nombre,
            "extensiones": sorted(extensiones.keys()),
            "largo": len(registro)}


def contar_cifrados(cifrados):
    aead = sum(1 for c in cifrados
               if any(t in CIFRADOS.get(c, "") for t in AEAD))
    return len(cifrados), aead, len(cifrados) - aead


def atender(conexion, direccion, puerto):
    try:
        conexion.settimeout(10)
        cabecera = leer_exacto(conexion, 5)
        if not cabecera:
            return
        tipo, version, largo = cabecera[0], struct.unpack(">H", cabecera[1:3])[0], \
            struct.unpack(">H", cabecera[3:5])[0]
        cuerpo = leer_exacto(conexion, largo) or b""
        registro = cabecera + cuerpo
        datos = analizar_saludo(registro)
        print("\n%s  visita desde %s:%d" % (
            time.strftime("%Y-%m-%d %H:%M:%S"), direccion[0], direccion[1]))
        if not datos:
            print("  (no es un ClientHello; tipo de registro %d)" % tipo)
        else:
            total, aead, resto = contar_cifrados(datos["cifrados"])
            versiones = ", ".join(VERSIONES.get(v, hex(v)) for v in datos["versiones"])
            grupos = ", ".join(GRUPOS.get(g, hex(g)) for g in datos["grupos"]) or "(sin decir)"
            print("  ALPN ofrecido   : %s" % (", ".join(datos["alpn"]) or "(ninguno)"))
            print("  versiones TLS   : %s" % versiones)
            print("  grupos          : %s" % grupos)
            print("  cifrados        : %d (AEAD %d, no-AEAD %d)" % (total, aead, resto))
            nombres = [CIFRADOS.get(c, hex(c)) for c in datos["cifrados"][:6]]
            print("  primeros        : %s" % ", ".join(nombres))
            print("  nombre pedido   : %s" % (datos["nombre"] or "(sin SNI)"))
            print("  extensiones     : %d" % len(datos["extensiones"]))
            print("  bytes del saludo: %d" % datos["largo"])
            print("  --> %s" % ("OFRECE HTTP/2" if "h2" in datos["alpn"]
                                 else "NO ofrece HTTP/2 (no hay 'h2' en ALPN)"))
        # Se contesta un aviso de fallo de mano (15 = alert, 2 = fatal,
        # 40 = handshake_failure) para que el cliente termine limpio.
        try:
            conexion.sendall(b"\x15\x03\x03\x00\x02\x02\x28")
        except OSError:
            pass
    except (OSError, socket.timeout) as fallo:
        print("  (visita interrumpida: %s)" % fallo)
    finally:
        conexion.close()
        sys.stdout.flush()


def main():
    analizador = argparse.ArgumentParser(description="espia de ClientHello")
    analizador.add_argument("--puerto", type=int, default=443)
    args = analizador.parse_args()

    servidor = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    servidor.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    servidor.bind(("0.0.0.0", args.puerto))
    servidor.listen(16)
    print("escuchando en 0.0.0.0:%d -- abre https://<ip-de-este-PC>/ en el aparato"
          % args.puerto)
    sys.stdout.flush()
    while True:
        try:
            conexion, direccion = servidor.accept()
        except KeyboardInterrupt:
            print("\nparando")
            return
        threading.Thread(target=atender, args=(conexion, direccion, args.puerto),
                         daemon=True).start()


if __name__ == "__main__":
    main()
