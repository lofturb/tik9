# -*- coding: utf-8 -*-
"""Verifica un .ipa: arquitectura, version minima de iOS, Info.plist y recursos.

Uso:
    python tools/verificar_ipa.py app/packages/Tik9.ipa

Lee la cabecera Mach-O del ejecutable, asi que no hace falta ni un Mac ni
otool: sirve para comprobar que el paquete es de verdad armv7 y para iOS 9.
"""

import os
import plistlib
import struct
import sys
import zipfile

CPU_TIPOS = {7: "x86", 12: "ARM", 16777223: "x86_64", 16777228: "arm64"}

SUBTIPOS_ARM = {
    0: "arm (generico)",
    5: "armv4t",
    6: "armv6",
    7: "armv5tej",
    8: "armv7 (xscale)",
    9: "armv7",
    10: "armv7f",
    11: "armv7s",
    12: "armv7k",
    13: "armv8",
}

LC_VERSION_MIN_IPHONEOS = 0x25
LC_CODE_SIGNATURE = 0x1D
LC_LOAD_DYLIB = 0x0C
LC_SEGMENT = 0x01
LC_SEGMENT_64 = 0x19
LC_BUILD_VERSION = 0x32
LC_ENCRYPTION_INFO = 0x21


def descomponer_version(valor):
    """El formato de Apple: X.Y.Z empaquetado en 32 bits."""
    x = (valor >> 16) & 0xFFFF
    y = (valor >> 8) & 0xFF
    z = valor & 0xFF
    return "%d.%d.%d" % (x, y, z)


def analizar_macho(datos):
    """Devuelve un diccionario con lo interesante de la cabecera Mach-O."""
    if len(datos) < 28:
        raise ValueError("El ejecutable es demasiado corto")

    magia = struct.unpack_from("<I", datos, 0)[0]
    if magia in (0xFEEDFACE, 0xFEEDFACF):
        orden = "<"
        cabecera = 32 if magia == 0xFEEDFACF else 28
    elif magia in (0xCEFAEDFE, 0xCFFAEDFE):
        orden = ">"
        cabecera = 32 if magia == 0xCFFAEDFE else 28
    else:
        raise ValueError("No parece un Mach-O (magia 0x%08X)" % magia)

    es_64 = cabecera == 32
    (cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags) = struct.unpack_from(
        orden + "IIIIII", datos, 4)

    resultado = {
        "64_bits": es_64,
        "cpu": CPU_TIPOS.get(cputype, "cputype=%d" % cputype),
        "subtipo": SUBTIPOS_ARM.get(cpusubtype & 0xFFFFFF,
                                    "subtype=%d" % (cpusubtype & 0xFFFFFF)),
        "filetype": {2: "executable", 6: "dylib", 8: "bundle"}.get(filetype, filetype),
        "versiones_minimas": [],
        "dependencias": [],
        "firmado": False,
        "encriptado": False,
        "flags": flags,
    }

    pos = cabecera
    for _ in range(ncmds):
        if pos + 8 > len(datos):
            break
        cmd, cmdsize = struct.unpack_from(orden + "II", datos, pos)
        if cmdsize < 8:
            break
        cuerpo = datos[pos + 8:pos + cmdsize]

        if cmd == LC_VERSION_MIN_IPHONEOS and len(cuerpo) >= 8:
            version, sdk = struct.unpack_from("<II", cuerpo, 0)
            resultado["versiones_minimas"].append(
                ("LC_VERSION_MIN_IPHONEOS", descomponer_version(version),
                 descomponer_version(sdk)))
        elif cmd == LC_BUILD_VERSION and len(cuerpo) >= 12:
            plataforma, minos, sdk = struct.unpack_from("<III", cuerpo, 0)
            resultado["versiones_minimas"].append(
                ("LC_BUILD_VERSION(plataforma=%d)" % plataforma,
                 descomponer_version(minos), descomponer_version(sdk)))
        elif cmd == LC_CODE_SIGNATURE:
            resultado["firmado"] = True
        elif cmd == LC_ENCRYPTION_INFO and len(cuerpo) >= 12:
            cripto = struct.unpack_from("<I", cuerpo, 8)[0]
            resultado["encriptado"] = cripto != 0
        elif cmd == LC_LOAD_DYLIB and len(cuerpo) >= 4:
            desplazamiento = struct.unpack_from("<I", cuerpo, 0)[0]
            if desplazamiento < len(cuerpo):
                nombre = cuerpo[desplazamiento:].split(b"\x00")[0]
                resultado["dependencias"].append(nombre.decode("utf-8", "replace"))
        pos += cmdsize

    return resultado


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    ruta = sys.argv[1]
    if not os.path.isfile(ruta):
        print("No existe el fichero: %s" % ruta)
        return 1

    with zipfile.ZipFile(ruta) as paquete:
        nombres = paquete.namelist()
        apps = sorted({n.split("/")[1] for n in nombres
                       if n.startswith("Payload/") and n.count("/") >= 2
                       and n.split("/")[1].endswith(".app")})
        print("=== Contenedor ===")
        print("  fichero      : %s (%d bytes)" % (os.path.basename(ruta),
                                                  os.path.getsize(ruta)))
        print("  aplicaciones : %s" % (", ".join(apps) or "(ninguna)"))
        print("  entradas     : %d" % len(nombres))

        if not apps:
            print("  !! El IPA no contiene ninguna app en Payload/")
            return 1
        app = apps[0]
        prefijo = "Payload/%s/" % app

        # --- Ejecutable -------------------------------------------------
        info = None
        if prefijo + "Info.plist" in nombres:
            info = plistlib.loads(paquete.read(prefijo + "Info.plist"))
        ejecutable = (info or {}).get("CFBundleExecutable", app)
        ruta_bin = prefijo + ejecutable
        if ruta_bin not in nombres:
            print("  !! Falta el ejecutable %s" % ruta_bin)
            return 1

        print("\n=== Ejecutable ===")
        datos = paquete.read(ruta_bin)
        cab = analizar_macho(datos)
        print("  ruta         : %s" % ruta_bin)
        print("  tamano       : %d bytes" % len(datos))
        print("  arquitectura : %s / %s (%s)" % (
            cab["cpu"], cab["subtipo"], "64 bits" if cab["64_bits"] else "32 bits"))
        for etiqueta, version, sdk in cab["versiones_minimas"]:
            print("  %s: minimo %s (SDK %s)" % (etiqueta, version, sdk))
        print("  firmado      : %s (ldid, no es firma de Apple)" % cab["firmado"])
        print("  encriptado   : %s" % cab["encriptado"])

        print("\n  dependencias:")
        for d in cab["dependencias"]:
            print("     %s" % d)

        # --- Info.plist -------------------------------------------------
        print("\n=== Info.plist ===")
        for clave in ("CFBundleIdentifier", "CFBundleName", "CFBundleDisplayName",
                      "CFBundleShortVersionString", "CFBundleVersion",
                      "MinimumOSVersion", "UIDeviceFamily",
                      "UIRequiredDeviceCapabilities"):
            if info and clave in info:
                print("  %-28s %s" % (clave, info[clave]))

        # --- Recursos ---------------------------------------------------
        print("\n=== Recursos ===")
        imagenes = [n.split("/")[-1] for n in nombres
                    if n.startswith(prefijo) and n.lower().endswith(".png")]
        print("  imagenes (%d): %s" % (len(imagenes), ", ".join(sorted(imagenes))))

        # --- Veredicto --------------------------------------------------
        print("\n=== Veredicto ===")
        problemas = []
        if cab["cpu"] != "ARM":
            problemas.append("no es ARM")
        if cab["subtipo"] != "armv7":
            problemas.append("el subtipo no es armv7 (%s)" % cab["subtipo"])
        if cab["64_bits"]:
            problemas.append("es de 64 bits")
        minimos = [v for _, v, _ in cab["versiones_minimas"]]
        if minimos and not any(v.startswith("9.") or v.startswith("8.") or v.startswith("7.")
                               for v in minimos):
            problemas.append("la version minima es %s" % ", ".join(minimos))
        if not cab["firmado"]:
            problemas.append("no lleva firma (necesita AppSync Unified al instalar)")

        if problemas:
            print("  ATENCION: %s" % "; ".join(problemas))
            return 2
        print("  Correcto: armv7, iOS 9 y pseudo-firmado (listo para AppSync).")
        return 0


if __name__ == "__main__":
    sys.exit(main())
