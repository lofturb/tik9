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

OBJETIVO="-target $ARQUITECTURA-apple-ios$MINIMO -isysroot $SDK -miphoneos-version-min=$MINIMO -Wno-error"
TRABAJO="$(pwd)/.tunel"

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
        git clone --depth 1 https://boringssl.googlesource.com/boringssl \
            "$TRABAJO/boringssl"
    fi
    echo "commit de BoringSSL: $(git -C "$TRABAJO/boringssl" rev-parse --short HEAD)"

    rm -rf "$TRABAJO/boringssl/build"
    cmake -S "$TRABAJO/boringssl" -B "$TRABAJO/boringssl/build" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_SYSTEM_PROCESSOR=arm \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        -DCMAKE_C_COMPILER="$CLANG" \
        -DCMAKE_CXX_COMPILER="$CLANGXX" \
        -DCMAKE_ASM_COMPILER="$CLANG" \
        -DCMAKE_C_FLAGS="$OBJETIVO" \
        -DCMAKE_CXX_FLAGS="$OBJETIVO" \
        -DCMAKE_BUILD_TYPE=Release \
        -DOPENSSL_NO_ASM=1 \
        -DOPENSSL_NO_TESTS=1 \
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
        -DCMAKE_C_COMPILER="$CLANG" \
        -DCMAKE_CXX_COMPILER="$CLANGXX" \
        -DCMAKE_C_FLAGS="$OBJETIVO" \
        -DCMAKE_CXX_FLAGS="$OBJETIVO" \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_SHARED_LIB=OFF \
        -DENABLE_STATIC_LIB=ON \
        -DENABLE_LIB_ONLY=ON \
        -DENABLE_APP=OFF \
        -DENABLE_EXAMPLES=OFF \
        -DENABLE_HPACK_TOOLS=OFF \
        -DENABLE_TESTS=OFF \
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
    echo "nghttp2 listo: $(ls -l "$DESTINO/lib/libnghttp2.a" | awk '{print $5}') bytes"
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
