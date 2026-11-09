#!/bin/bash
set -euo pipefail
export MACOSX_DEPLOYMENT_TARGET=26.0
ROOT="$(cd "$(dirname "$0")/../.work/media" && pwd)"
cd "$ROOT/ghostscript/ghostscript-10.08.0"
./configure CFLAGS="-O2 -mmacosx-version-min=26.0" LDFLAGS="-mmacosx-version-min=26.0" --prefix="$ROOT/prefix-gs" --without-x --disable-cups --disable-gtk --without-tesseract --disable-dbus --disable-fontconfig
make -j 6
