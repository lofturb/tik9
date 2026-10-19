#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  compilar_tunel.sh -- compila las dos bibliotecas del "tunel".
#
#  Por que hacen falta: la busqueda de TikTok no la deja pasar la pila de red
#  de iOS 9 (SecureTransport + su HTTP/2 de 2015).  Esta medido que la misma
#  peticion, firmada igual, entra con una pila moderna; lo que decide es la
#  huella de la conexion (saludo TLS + ajustes de HTTP/2).
#
#    * BoringSSL: la biblioteca TLS de Chrome.  Es la que da el saludo TLS que
#      TikTok tiene por bueno; con OpenSSL pelado no entra.
#    * nghttp2:   la parte de HTTP/2, con la que se pueden fijar los ajustes
#      (SETTINGS, ventanas) que manda un navegador de verdad.
#
#  Sin ensamblador (OPENSSL_NO_ASM): el ensamblador no cambia nada de lo que se
#  ve por el cable y evita depender del montador de Apple.  Go solo hace falta
#  para generar tablas de errores.
#
#  Deja todo en $DESTINO (por defecto deps/):
#     lib/libssl.a lib/libcrypto.a lib/libnghttp2.a
#     include/openssl/*.h include/nghttp2/*.h
#
#  Uso:  bash tools/compilar_tunel.sh [destino]
# ---------------------------------------------------------------------------

set -euo pipefail

DESTINO="${1:-deps}"
THEOS="${THEOS:-$PWD/theos}"
SDK="${SDK:-$THEOS/sdks/iPhoneOS9.3.sdk}"
CLANG="$THEOS/toolchain/linux/iphone/bin/clang"
CLANGXX="$THEOS/toolchain/linux/iphone/bin/clang++"
ARQUITECTURA="${ARQUITECTURA:-armv7}"
MINIMO="${MINIMO:-9.0}"
# BoringSSL cambia deprisa.  Esta fecha es el ultimo dia del que se coge el
# codigo, y esta elegida a proposito: a partir del 2025-10-15 bssl::Span pasa a
# tener tamano fijo en el tipo y el compilador del toolchain (LLVM 11) no lo
# digiere.  Antes de esa fecha esta todo lo que hace falta: GREASE, extensiones
# permutadas, TLS 1.3 y las curvas de Chrome.
BORINGSSL_FECHA="${BORINGSSL_FECHA:-2025-09-01}"
BORINGSSL_DESDE="${BORINGSSL_DESDE:-2025-05-01}"

OBJETIVO="-target $ARQUITECTURA-apple-ios$MINIMO -isysroot $SDK -miphoneos-version-min=$MINIMO -Wno-error"
TRABAJO="$(pwd)/.tunel"

# Empacadores del propio toolchain (los de Linux tambien valen, pero estos son
# los que entienden los objetos de Apple sin sorpresas).
AR="$(dirname "$CLANG")/llvm-ar"
RANLIB="$(dirname "$CLANG")/llvm-ranlib"
EMPACADORES=()
[ -x "$AR" ] && EMPACADORES+=("-DCMAKE_AR=$AR")
[ -x "$RANLIB" ] && EMPACADORES+=("-DCMAKE_RANLIB=$RANLIB")

if [ ! -x "$CLANG" ]; then
    echo "No encuentro el compilador de Theos en $CLANG"
    echo "THEOS=$THEOS"
    exit 1
fi

mkdir -p "$DESTINO/lib" "$DESTINO/include" "$TRABAJO"

echo "=== herramientas ==="
"$CLANG" --version | head -n 2
cmake --version | head -n 1
if command -v go >/dev/null 2>&1; then
    echo "go: $(go version)"
else
    echo "AVISO: no hay go; si BoringSSL lo pide, la construccion fallara"
fi

# ---------------------------------------------------------------------------
#  BoringSSL
# ---------------------------------------------------------------------------
if [ ! -f "$DESTINO/lib/libssl.a" ]; then
    echo "=== BoringSSL ==="
    if [ ! -d "$TRABAJO/boringssl/.git" ]; then
        # Se trae solo la historia desde mayo, que es de donde sale el commit
        # elegido: menos descarga y sigue permitiendo clavar la fecha.
        git clone --shallow-since="$BORINGSSL_DESDE" --single-branch \
            https://boringssl.googlesource.com/boringssl "$TRABAJO/boringssl"
    fi
    COMITE="$(git -C "$TRABAJO/boringssl" log --before="$BORINGSSL_FECHA" -1 --format=%H)"
    if [ -z "$COMITE" ]; then
        echo "No hay commits de BoringSSL anteriores a $BORINGSSL_FECHA"
        exit 1
    fi
    git -C "$TRABAJO/boringssl" checkout -q "$COMITE"
    echo "BoringSSL: $COMITE  ($(git -C "$TRABAJO/boringssl" log -1 --format=%ad --date=short))"

    # El SDK 9.3 trae CommonRandom.h sin la cabecera de la que toma sus tipos
    # (CCCryptorStatus vive en CommonCryptor.h); se incluye antes a la fuerza.
    # En los SDK nuevos CommonRandom.h ya la trae y esto no estorba.
    INCLUIR_COMUN="-include CommonCrypto/CommonCryptor.h"

    # Ajustes para compilar C++ moderno contra iOS 9:
    #
    #   _LIBCPP_DISABLE_AVAILABILITY  el libc++ de Apple marca con "solo desde
    #     iOS 11" cosas como std::optional::value().  Esa marca es para saber
    #     contra que sistema se puede enlazar, no para prohibir el codigo; aqui
    #     las bibliotecas se enlazan dentro de la app y lo que falta del sistema
    #     se pone a mano (ver app/TTTunelCompat.cc).  Sin esto no compila.
    #   -fno-exceptions, -fno-sized-deallocation, -fno-aligned-allocation
    #     hacen que el compilador no genere llamadas a piezas de libc++ que iOS 9
    #     no trae (liberacion con tamano, reserva alineada) y que BoringSSL no
    #     necesita porque no usa excepciones.
    CXX_VIEJO="-D_LIBCPP_DISABLE_AVAILABILITY -fno-exceptions -fno-sized-deallocation -fno-aligned-allocation"

    # Que lo que usa el tunel exista en ese commit: si no, mejor saberlo aqui
    # que en un error de compilacion a mitad.
    for SIMBOLO in SSL_CTX_set_grease_enabled SSL_CTX_set_permute_extensions \
                   SSL_CTX_set_strict_cipher_list SSL_set1_host; do
        if ! grep -q "$SIMBOLO" "$TRABAJO/boringssl/include/openssl/ssl.h"; then
            echo "A BoringSSL le falta $SIMBOLO en ese commit"
            exit 1
        fi
    done

    rm -rf "$TRABAJO/boringssl/build"
    cmake -S "$TRABAJO/boringssl" -B "$TRABAJO/boringssl/build" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_SYSTEM_PROCESSOR=arm \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        -DCMAKE_C_COMPILER_WORKS=1 \
        -DCMAKE_CXX_COMPILER_WORKS=1 \
        "${EMPACADORES[@]}" \
        -DCMAKE_C_COMPILER="$CLANG" \
        -DCMAKE_CXX_COMPILER="$CLANGXX" \
        -DCMAKE_ASM_COMPILER="$CLANG" \
        -DCMAKE_C_FLAGS="$OBJETIVO $INCLUIR_COMUN" \
        -DCMAKE_CXX_FLAGS="$OBJETIVO $INCLUIR_COMUN $CXX_VIEJO" \
        -DCMAKE_BUILD_TYPE=Release \
        -DOPENSSL_NO_ASM=1 \
        -DBUILD_TESTING=OFF \
        -DBUILD_SHARED_LIBS=0 \
        -DCMAKE_POSITION_INDEPENDENT_CODE=0
    cmake --build "$TRABAJO/boringssl/build" --target ssl crypto -j "$(nproc)"

    cp "$TRABAJO/boringssl/build/libssl.a" "$TRABAJO/boringssl/build/libcrypto.a" \
       "$DESTINO/lib/"
    cp -R "$TRABAJO/boringssl/include/openssl" "$DESTINO/include/"
    echo "BoringSSL listo: $(ls -l "$DESTINO/lib/libssl.a" | awk '{print $5}') bytes"
else
    echo "=== BoringSSL (ya compilado, de la cache) ==="
fi

# ---------------------------------------------------------------------------
#  nghttp2
# ---------------------------------------------------------------------------
if [ ! -f "$DESTINO/lib/libnghttp2.a" ]; then
    echo "=== nghttp2 ==="
    if [ ! -d "$TRABAJO/nghttp2/.git" ]; then
        git clone --depth 1 --branch v1.61.0 https://github.com/nghttp2/nghttp2.git \
            "$TRABAJO/nghttp2"
    fi
    echo "commit de nghttp2: $(git -C "$TRABAJO/nghttp2" rev-parse --short HEAD)"

    rm -rf "$TRABAJO/nghttp2/build"
    cmake -S "$TRABAJO/nghttp2" -B "$TRABAJO/nghttp2/build" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_SYSTEM_PROCESSOR=arm \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        -DCMAKE_C_COMPILER_WORKS=1 \
        -DCMAKE_CXX_COMPILER_WORKS=1 \
        "${EMPACADORES[@]}" \
        -DCMAKE_C_COMPILER="$CLANG" \
        -DCMAKE_CXX_COMPILER="$CLANGXX" \
        -DCMAKE_C_FLAGS="$OBJETIVO" \
        -DCMAKE_CXX_FLAGS="$OBJETIVO" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_STATIC_LIBS=ON \
        -DENABLE_LIB_ONLY=ON \
        -DENABLE_APP=OFF \
        -DENABLE_EXAMPLES=OFF \
        -DENABLE_HPACK_TOOLS=OFF \
        -DBUILD_TESTING=OFF \
        -DENABLE_FAILING_TESTS=OFF \
        -DENABLE_PYTHON_BINDINGS=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=0
    cmake --build "$TRABAJO/nghttp2/build" --target nghttp2_static -j "$(nproc)"

    # El nombre del fichero cambia entre versiones: se busca y se copia.
    ESTATICA="$(find "$TRABAJO/nghttp2/build" -name 'libnghttp2*.a' | head -n 1)"
    if [ -z "$ESTATICA" ]; then
        echo "No encuentro la biblioteca estatica de nghttp2"
        find "$TRABAJO/nghttp2/build" -name '*.a' | head
        exit 1
    fi
    cp "$ESTATICA" "$DESTINO/lib/libnghttp2.a"
    cp -R "$TRABAJO/nghttp2/lib/includes/nghttp2" "$DESTINO/include/"
    # nghttp2ver.h no esta en el codigo: lo genera CMake al configurar, asi que
    # vive en el arbol de compilacion.  Sin el, no compila ni una linea que use
    # nghttp2.h.
    VERSION_H="$(find "$TRABAJO/nghttp2" -name 'nghttp2ver.h' | head -n 1)"
    if [ -z "$VERSION_H" ]; then
        echo "No encuentro nghttp2ver.h, que se genera al configurar"
        exit 1
    fi
    cp "$VERSION_H" "$DESTINO/include/nghttp2/"
    echo "nghttp2 listo: $(ls -l "$DESTINO/lib/libnghttp2.a" | awk '{print $5}') bytes"
    ls "$DESTINO/include/nghttp2"
else
    echo "=== nghttp2 (ya compilado, de la cache) ==="
fi

echo "=== resultado ==="
ls -l "$DESTINO/lib"
echo "cabeceras:"
ls "$DESTINO/include"
# Que las bibliotecas sean de verdad para armv7/iOS: si no, el enlace de la app
# fallaria mas tarde y sin decir por que.
"$THEOS/toolchain/linux/iphone/bin/otool" -hv "$DESTINO/lib/libssl.a" 2>/dev/null | head -n 5 || true
"$THEOS/toolchain/linux/iphone/bin/otool" -hv "$DESTINO/lib/libnghttp2.a" 2>/dev/null | head -n 5 || true
