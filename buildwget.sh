#!/bin/bash
#
# buildwget.sh — Compila un GNU wget moderno, universal (arm64 + x86_64) y
# autónomo para empaquetarlo dentro de CocoaWget en macOS actual (incl. Tahoe / 26).
#
# Por qué: el binario `wget` que históricamente venía en este repo es un Mach-O
# i386 + PowerPC que NO se ejecuta en macOS 10.15+. Este script genera un binario
# que enlaza OpenSSL ESTÁTICAMENTE (sin dependencias de dylibs de Homebrew), de modo
# que funciona en Apple Silicon e Intel y puede firmarse y notarizarse.
#
# Requisitos: Xcode Command Line Tools (clang, make), curl, lipo (todo de serie en
# macOS) y conexión a internet. NO requiere Homebrew.
#
# Uso:
#   ./buildwget.sh                      # universal: arm64 + x86_64 (por defecto)
#   ARCHS="arm64" ./buildwget.sh        # solo una arquitectura (build local rápido)
#   WGET_VERSION=1.25.0 OPENSSL_VERSION=3.4.1 ./buildwget.sh
#   ./buildwget.sh /ruta/a/CocoaWget.app # además, instala el binario en el bundle
#
# Variables de entorno admitidas (con sus valores por defecto):
#   WGET_VERSION=1.25.0
#   OPENSSL_VERSION=3.4.1
#   ARCHS="arm64 x86_64"
#   MACOSX_DEPLOYMENT_TARGET=13.0   # debe coincidir con el deployment target de la app
#
# Verificación de integridad de las fuentes:
#   WGET_SHA256=<hash>      sha256 esperado del tarball de wget (recomendado: fíjalo).
#   OPENSSL_SHA256=<hash>   sha256 esperado del tarball de OpenSSL.
#   STRICT_VERIFY=1         aborta si una fuente no se puede verificar (por defecto: avisa).
#   Si no fijas los hashes, el script intenta: el checksum .sha256 publicado por OpenSSL
#   y la firma GPG de wget contra el llavero oficial de GNU (si hay gpg/gpgv instalado).
#
# Instalar en un .app ya compilado:
#   APP_BUNDLE=/ruta/a/CocoaWget.app    (o pásalo como primer argumento posicional)
#
set -euo pipefail

# --------------------------------------------------------------------------- #
# Configuración
# --------------------------------------------------------------------------- #
WGET_VERSION="${WGET_VERSION:-1.25.0}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.4.1}"
ARCHS="${ARCHS:-arm64 x86_64}"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"

WGET_SHA256="${WGET_SHA256:-}"
OPENSSL_SHA256="${OPENSSL_SHA256:-}"
STRICT_VERIFY="${STRICT_VERIFY:-0}"
APP_BUNDLE="${APP_BUNDLE:-${1:-}}"  # .app opcional donde instalar el binario

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
SRC_DIR="${BUILD_DIR}/src"
OUT_DIR="${BUILD_DIR}/out"          # binarios wget por arquitectura
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

WGET_URL="https://ftp.gnu.org/gnu/wget/wget-${WGET_VERSION}.tar.gz"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
GNU_KEYRING_URL="https://ftp.gnu.org/gnu/gnu-keyring.gpg"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mAviso:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# Comprueba herramientas necesarias
for tool in clang make curl lipo tar codesign otool; do
    command -v "$tool" >/dev/null 2>&1 || die "no se encuentra '$tool' (instala las Command Line Tools de Xcode)."
done
[ "$(uname -s)" = "Darwin" ] || die "este script solo funciona en macOS."

# --------------------------------------------------------------------------- #
# Descarga de las fuentes
# --------------------------------------------------------------------------- #
download() {  # download <url> <destino>
    local url="$1" dest="$2"
    if [ -f "$dest" ]; then
        log "Ya descargado: $(basename "$dest")"
    else
        log "Descargando $(basename "$dest")"
        curl -fL --retry 3 -o "$dest" "$url"
    fi
}

# Descarga opcional: no falla si el recurso no existe (devuelve !=0).
download_optional() {  # download_optional <url> <destino>
    curl -fsL --retry 2 -o "$2" "$1" 2>/dev/null
}

sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# Trata un fallo de verificación según STRICT_VERIFY.
unverified() {  # unverified <mensaje>
    if [ "$STRICT_VERIFY" = "1" ]; then
        die "$1 (STRICT_VERIFY=1)."
    else
        warn "$1 — continuando (fija el sha256 o usa STRICT_VERIFY=1 para abortar)."
    fi
}

# Verifica un archivo contra un sha256 esperado (si se proporciona).
verify_sha256() {  # verify_sha256 <archivo> <hash_esperado> <etiqueta>
    local file="$1" expected="$2" label="$3" actual
    actual="$(sha256_of "$file")"
    if [ "$actual" = "$expected" ]; then
        log "[verify] $label: sha256 OK"
        return 0
    fi
    die "[verify] $label: sha256 NO coincide.
  esperado: $expected
  obtenido: $actual"
}

# OpenSSL: sha256 fijado por el usuario, o el .sha256 publicado en el release.
verify_openssl() {
    if [ -n "$OPENSSL_SHA256" ]; then
        verify_sha256 "$OPENSSL_TGZ" "$OPENSSL_SHA256" "openssl"
        return
    fi
    local sumfile="${OPENSSL_TGZ}.sha256"
    if download_optional "${OPENSSL_URL}.sha256" "$sumfile"; then
        local published
        published="$(tr -d '\r' < "$sumfile" | awk '{print $1}' | head -n1)"
        if [ -n "$published" ]; then
            verify_sha256 "$OPENSSL_TGZ" "$published" "openssl (.sha256 publicado)"
            return
        fi
    fi
    unverified "no se pudo verificar el tarball de OpenSSL (sin OPENSSL_SHA256 ni .sha256 publicado)"
}

# wget: sha256 fijado por el usuario, o firma GPG contra el llavero oficial de GNU.
verify_wget() {
    if [ -n "$WGET_SHA256" ]; then
        verify_sha256 "$WGET_TGZ" "$WGET_SHA256" "wget"
        return
    fi
    local sig="${WGET_TGZ}.sig" keyring="${SRC_DIR}/gnu-keyring.gpg"
    if download_optional "${WGET_URL}.sig" "$sig"; then
        download_optional "$GNU_KEYRING_URL" "$keyring" || true
        if command -v gpgv >/dev/null 2>&1 && [ -s "$keyring" ]; then
            if gpgv --keyring "$keyring" "$sig" "$WGET_TGZ" 2>/dev/null; then
                log "[verify] wget: firma GPG OK (llavero GNU)"; return
            fi
            unverified "la firma GPG de wget no se pudo validar"; return
        elif command -v gpg >/dev/null 2>&1 && [ -s "$keyring" ]; then
            if gpg --no-default-keyring --keyring "$keyring" --verify "$sig" "$WGET_TGZ" 2>/dev/null; then
                log "[verify] wget: firma GPG OK (llavero GNU)"; return
            fi
            unverified "la firma GPG de wget no se pudo validar"; return
        fi
        unverified "hay firma .sig de wget pero no hay 'gpg'/'gpgv' para verificarla"
        return
    fi
    unverified "no se pudo verificar el tarball de wget (sin WGET_SHA256 ni firma .sig accesible)"
}

mkdir -p "$SRC_DIR" "$OUT_DIR"

OPENSSL_TGZ="${SRC_DIR}/openssl-${OPENSSL_VERSION}.tar.gz"
WGET_TGZ="${SRC_DIR}/wget-${WGET_VERSION}.tar.gz"
download "$OPENSSL_URL" "$OPENSSL_TGZ"
download "$WGET_URL"    "$WGET_TGZ"

log "Verificando integridad de las fuentes"
verify_openssl
verify_wget

# --------------------------------------------------------------------------- #
# Mapeo de arquitectura -> triple de host y target de OpenSSL
# --------------------------------------------------------------------------- #
host_for_arch()    { case "$1" in arm64) echo "aarch64-apple-darwin";; x86_64) echo "x86_64-apple-darwin";; *) die "arch no soportada: $1";; esac; }
openssl_target()   { case "$1" in arm64) echo "darwin64-arm64-cc";;    x86_64) echo "darwin64-x86_64-cc";;  *) die "arch no soportada: $1";; esac; }

# --------------------------------------------------------------------------- #
# Compilación por arquitectura
# --------------------------------------------------------------------------- #
build_arch() {
    local arch="$1"
    local host openssl_tgt ssl_prefix wget_build
    host="$(host_for_arch "$arch")"
    openssl_tgt="$(openssl_target "$arch")"
    ssl_prefix="${BUILD_DIR}/openssl-${arch}"
    wget_build="${BUILD_DIR}/wget-${arch}"

    log "[$arch] Compilando OpenSSL ${OPENSSL_VERSION} (estático)"
    rm -rf "${BUILD_DIR}/openssl-src-${arch}" "$ssl_prefix"
    mkdir -p "${BUILD_DIR}/openssl-src-${arch}"
    tar xzf "$OPENSSL_TGZ" -C "${BUILD_DIR}/openssl-src-${arch}" --strip-components=1
    (
        cd "${BUILD_DIR}/openssl-src-${arch}"
        ./Configure "$openssl_tgt" no-shared no-tests no-docs \
            --prefix="$ssl_prefix" \
            -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET}"
        make -j"$JOBS"
        make install_sw
    )

    log "[$arch] Compilando wget ${WGET_VERSION} (enlazando OpenSSL estático)"
    rm -rf "${BUILD_DIR}/wget-src-${arch}" "$wget_build"
    mkdir -p "${BUILD_DIR}/wget-src-${arch}"
    tar xzf "$WGET_TGZ" -C "${BUILD_DIR}/wget-src-${arch}" --strip-components=1
    (
        cd "${BUILD_DIR}/wget-src-${arch}"
        CC="clang -arch ${arch}" \
        CPPFLAGS="-I${ssl_prefix}/include -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}" \
        LDFLAGS="-L${ssl_prefix}/lib -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}" \
        PKG_CONFIG_PATH="${ssl_prefix}/lib/pkgconfig" \
        ./configure \
            --host="$host" \
            --with-ssl=openssl \
            --without-libpsl \
            --disable-dependency-tracking \
            --prefix="$wget_build"
        make -j"$JOBS"
        make install
    )

    cp "${wget_build}/bin/wget" "${OUT_DIR}/wget-${arch}"
    log "[$arch] Listo: ${OUT_DIR}/wget-${arch}"
}

for arch in $ARCHS; do
    build_arch "$arch"
done

# --------------------------------------------------------------------------- #
# Unir las arquitecturas (lipo) e instalar en la raíz del proyecto
# --------------------------------------------------------------------------- #
log "Creando binario universal con lipo"
SLICES=()
for arch in $ARCHS; do SLICES+=("${OUT_DIR}/wget-${arch}"); done
lipo -create "${SLICES[@]}" -output "${ROOT_DIR}/wget"

# Firma ad-hoc para que pueda ejecutarse localmente en Apple Silicon.
# Para distribuir, vuelve a firmar con tu certificado Developer ID al notarizar la app.
log "Firmando ad-hoc el binario"
codesign --force --sign - "${ROOT_DIR}/wget"

# --------------------------------------------------------------------------- #
# Verificación
# --------------------------------------------------------------------------- #
log "Verificación"
file "${ROOT_DIR}/wget"
echo
echo "Dependencias dinámicas (deberían ser solo /usr/lib y /System):"
otool -L "${ROOT_DIR}/wget"
echo

# Solo podemos ejecutar la slice de la arquitectura actual de la máquina.
HOST_ARCH="$(uname -m)"
if printf '%s\n' $ARCHS | grep -qx "$HOST_ARCH"; then
    "${ROOT_DIR}/wget" --version | head -n 3
else
    log "La arquitectura del host ($HOST_ARCH) no está entre las compiladas; se omite --version."
fi

# --------------------------------------------------------------------------- #
# (Opcional) Instalar el binario en un .app ya compilado
# --------------------------------------------------------------------------- #
if [ -n "$APP_BUNDLE" ]; then
    case "$APP_BUNDLE" in
        *.app) ;;
        *) die "APP_BUNDLE debe apuntar a un bundle .app (recibido: $APP_BUNDLE)." ;;
    esac
    [ -d "$APP_BUNDLE" ] || die "no existe el bundle: $APP_BUNDLE"
    RES_DIR="${APP_BUNDLE}/Contents/Resources"
    mkdir -p "$RES_DIR"
    log "Instalando wget en ${RES_DIR}/wget"
    cp "${ROOT_DIR}/wget" "${RES_DIR}/wget"
    # Re-firma ad-hoc la copia (lipo invalida la firma). Para distribuir, firma todo
    # el bundle con Developer ID y notarízalo.
    codesign --force --sign - "${RES_DIR}/wget"
    log "Instalado en el bundle."
fi

log "Hecho. Si no usaste APP_BUNDLE, copia ${ROOT_DIR}/wget a Contents/Resources del bundle (la fase de recursos de Xcode lo hace)."
