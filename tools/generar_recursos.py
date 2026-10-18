# -*- coding: utf-8 -*-
"""
Genera los recursos graficos de Tik9 sin dependencias externas.

Escribe PNGs a mano (zlib + struct, ambos de la biblioteca estandar), asi que
funciona en Windows 7 con Python 3.8 sin instalar Pillow ni nada.

La marca es la de la app: la nota musical en blanco con el desfase de color
(cian y rosa) de TikTok, sobre un cuadrado negro redondeado.

Produce:
  app/Resources/             -> iconos del sistema e imagenes de arranque
  app/recursos-generados.txt -> resumen de lo creado

Uso:
    python tools/generar_recursos.py
"""

import io
import os
import struct
import zlib

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(RAIZ, "app", "Resources")

# Paleta (coincide con TTTheme.m)
FONDO = (0x0B, 0x0B, 0x0D, 255)     # negro de TikTok
BLANCO = (0xFF, 0xFF, 0xFF, 255)
ROSA = (0xFE, 0x2C, 0x55, 255)      # acento por defecto
CIAN = (0x25, 0xF4, 0xEE, 255)      # el otro color de la marca
TRANSPARENTE = (0, 0, 0, 0)


def escribir_png(ruta, ancho, alto, pixeles):
    """pixeles: bytearray RGBA de ancho*alto*4."""
    filas = []
    for y in range(alto):
        inicio = y * ancho * 4
        filas.append(b"\x00" + bytes(pixeles[inicio:inicio + ancho * 4]))
    crudo = b"".join(filas)

    def bloque(tipo, datos):
        return (struct.pack(">I", len(datos)) + tipo + datos
                + struct.pack(">I", zlib.crc32(tipo + datos) & 0xFFFFFFFF))

    cabecera = struct.pack(">IIBBBBB", ancho, alto, 8, 6, 0, 0, 0)
    contenido = (b"\x89PNG\r\n\x1a\n"
                 + bloque(b"IHDR", cabecera)
                 + bloque(b"IDAT", zlib.compress(crudo, 9))
                 + bloque(b"IEND", b""))
    with io.open(ruta, "wb") as f:
        f.write(contenido)


def dentro_del_redondeo(x, y, ancho, alto, radio):
    """Esquinas redondeadas estilo iOS."""
    cx = min(max(x, radio), ancho - radio)
    cy = min(max(y, radio), alto - radio)
    dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= radio * radio


def dentro_poligono(x, y, puntos):
    """Prueba del rayo (even-odd) para un poligono."""
    dentro = False
    n = len(puntos)
    j = n - 1
    for i in range(n):
        xi, yi = puntos[i]
        xj, yj = puntos[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
            dentro = not dentro
        j = i
    return dentro


def dentro_nota(x, y):
    """Nota musical (x, y en 0..1).  Cabeza + plica + banderola."""
    # Descarte rapido por caja envolvente (evita el resto en 8 de cada 10
    # muestras, que es lo que hace lenta la generacion de los iconos grandes).
    if x < 0.185 or x > 0.805 or y < 0.185 or y > 0.855:
        return False
    # Cabeza (elipse).
    if ((x - 0.365) / 0.165) ** 2 + ((y - 0.705) / 0.135) ** 2 <= 1.0:
        return True
    # Plica (barra vertical).
    if 0.485 <= x <= 0.535 and 0.205 <= y <= 0.735:
        return True
    # Banderola (cuadrilatero inclinado hacia arriba a la derecha).
    if x < 0.535 or x > 0.790 or y < 0.205 or y > 0.470:
        return False
    bandera = [(0.535, 0.205), (0.790, 0.300), (0.790, 0.455), (0.535, 0.470)]
    return dentro_poligono(x, y, bandera)


def icono(ancho, alto, con_fondo=True):
    """Cuadrado redondeado con la nota y su desfase de color (cian/rosa).
    Supermuestreo para que los bordes queden suaves: 3x en los iconos normales
    y 2x en los grandes (arranque), donde la diferencia no se ve y el coste en
    Python si se nota."""
    sup = 3 if ancho <= 128 else 2
    radio = 0.2237 * ancho
    desfase = 0.022 * ancho
    pixeles = bytearray(ancho * alto * 4)

    for y in range(alto):
        for x in range(ancho):
            acumulado = [0.0, 0.0, 0.0, 0.0]
            for sy in range(sup):
                for sx in range(sup):
                    px = x + (sx + 0.5) / sup
                    py = y + (sy + 0.5) / sup
                    if con_fondo and not dentro_del_redondeo(px, py, ancho, alto, radio):
                        color = TRANSPARENTE
                    else:
                        # La nota se dibuja tres veces con un pequeno desfase:
                        # blanco en el centro, rosa hacia abajo-derecha y cian
                        # hacia arriba-izquierda.  Se prueba en ese orden (el
                        # blanco gana) para que los colores solo asomen por los
                        # bordes, como en TikTok.
                        if dentro_nota(px / ancho, py / alto):
                            color = BLANCO
                        elif dentro_nota((px - desfase) / ancho, (py - desfase) / alto):
                            color = ROSA
                        elif dentro_nota((px + desfase) / ancho, (py + desfase) / alto):
                            color = CIAN
                        else:
                            color = FONDO if con_fondo else TRANSPARENTE
                    for i in range(4):
                        acumulado[i] += color[i]
            n = sup * sup
            base = (y * ancho + x) * 4
            for i in range(4):
                pixeles[base + i] = int(round(acumulado[i] / n))
    return pixeles


def arranque(ancho, alto):
    """Imagen de arranque: fondo negro con la marca pequena y centrada.

    El fondo se rellena por filas (constante) y solo se pinta encima el
    recuadro de la marca: asi no se recorre a mano cada pixel del lienzo, que
    en las imagenes de iPad (2048x1536) se nota mucho."""
    lado = int(min(ancho, alto) * 0.30)
    ox = (ancho - lado) // 2
    oy = (alto - lado) // 2
    fila_fondo = bytes(FONDO) * ancho
    pixeles = bytearray(fila_fondo * alto)

    marca = icono(lado, lado)   # con esquinas redondeadas
    for y in range(lado):
        destino = ((oy + y) * ancho + ox) * 4
        origen = y * lado * 4
        pixeles[destino:destino + lado * 4] = marca[origen:origen + lado * 4]
    return pixeles


ICONOS = [
    ("Icon-Small.png", 29),
    ("Icon-Small@2x.png", 58),
    ("Icon-Small-40.png", 40),
    ("Icon-Small-40@2x.png", 80),
    ("Icon-Small-40@3x.png", 120),
    ("Icon-60@2x.png", 120),
    ("Icon-60@3x.png", 180),
    ("Icon-76.png", 76),
    ("Icon-76@2x.png", 152),
    ("iTunesArtwork", 512),
]

ARRANQUES = [
    ("LaunchImage.png", 320, 480),
    ("LaunchImage@2x.png", 640, 960),
    ("LaunchImage-568h@2x.png", 640, 1136),
    ("LaunchImage-700.png", 320, 480),
    ("LaunchImage-700@2x.png", 640, 960),
    ("LaunchImage-700-568h@2x.png", 640, 1136),
    ("LaunchImage-700-Portrait@2x.png", 1536, 2048),
    ("LaunchImage-700-Landscape@2x.png", 2048, 1536),
]


def main():
    if not os.path.isdir(DESTINO):
        os.makedirs(DESTINO)
    hechos = []

    for nombre, lado in ICONOS:
        escribir_png(os.path.join(DESTINO, nombre), lado, lado,
                     icono(lado, lado, con_fondo=(nombre != "iTunesArtwork")))
        hechos.append("%s  %dx%d" % (nombre, lado, lado))

    for nombre, ancho, alto in ARRANQUES:
        escribir_png(os.path.join(DESTINO, nombre), ancho, alto, arranque(ancho, alto))
        hechos.append("%s  %dx%d" % (nombre, ancho, alto))

    resumen = os.path.join(RAIZ, "app", "recursos-generados.txt")
    with io.open(resumen, "w", encoding="utf-8") as f:
        f.write("Recursos generados por tools/generar_recursos.py\n\n")
        f.write("\n".join(hechos) + "\n")

    print("Generados %d archivos en app/Resources" % len(hechos))
    for h in hechos:
        print("   ", h)


if __name__ == "__main__":
    main()
