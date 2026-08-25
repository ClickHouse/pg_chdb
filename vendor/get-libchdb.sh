#!/bin/bash

# Based on
# https://github.com/chdb-io/chdb-io.github.io/blob/main/install_libchdb.sh
#
# Environment variables:
#
# INSTALL_VERSION: Version to install; defaults to latest release
# DESTDIR: Directory in which to install; defaults to /usr/local
# STATIC: If true, install the static library and not the dynamic

set -e

# Check for necessary tools
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but it's not installed. Aborting."; exit 1; }
command -v tar >/dev/null 2>&1 || { echo >&2 "tar is required but it's not installed. Aborting."; exit 1; }

# Function to download and extract the file
download_and_extract() {
    local url="$1"
    local file="libchdb.tar.gz"

    echo "Attempting to download $file from $url"

    # Download the file with a retry logic
    if curl -L -o "$file" "$url"; then
        echo "Download successful."

        # Optional: Verify download integrity here, if checksums are provided

        # Untar the file
        if tar -xzf "$file"; then
            rm libchdb.tar.gz
            echo "Extraction successful."
            return 0
        fi
    fi
    return 1
}

INSTALL_VERSION="${INSTALL_VERSION:-$(curl --silent "https://api.github.com/repos/chdb-io/chdb-core/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')}"

# Select the correct package based on OS and architecture
case "$(uname -s)" in
    Linux)
        OS=linux
        if [[ $(uname -m) == "aarch64" ]]; then
            ARCH=aarch64
        else
            ARCH=x86_64
        fi
        ;;
    Darwin)
        OS=macos
        if [[ $(uname -m) == "arm64" ]]; then
            ARCH=arm64
        else
            ARCH=x86_64
        fi
        ;;
    *)
        echo "Unsupported platform"
        exit 1
        ;;
esac

FILE="${OS}-${ARCH}-libchdb"
if [ -n "$STATIC" ]; then
    FILE+=-static
fi

# Main download URL
DOWNLOAD_URL="https://github.com/chdb-io/chdb-core/releases/download/$INSTALL_VERSION/$FILE.tar.gz"
FALLBACK_URL="https://github.com/chdb-io/chdb-core/releases/latest/download/$FILE.tar.gz"

# Try the main download URL first
if ! download_and_extract "$DOWNLOAD_URL"; then
    echo "Retrying with fallback URL..."
    if ! download_and_extract "$FALLBACK_URL"; then
        echo "Both primary and fallback downloads failed. Aborting."
        exit 1
    fi
fi

DESTDIR="${DESTDIR:-/usr/local}"

# Install the library and headers.
mkdir -p "${DESTDIR}/lib" "${DESTDIR}/include" || true
/bin/cp libchdb.* "${DESTDIR}/lib/"
/bin/cp chdb.h* "${DESTDIR}/include/"

if [ -z "$STATIC" ]; then
    # Set execute permission for libchdb.so.
    chmod +x "${DESTDIR}/lib/libchdb.so"
fi

# Clean up
rm -f libchdb.* chdb.h*
printf 'Installed into %s\n' "$DESTDIR"
