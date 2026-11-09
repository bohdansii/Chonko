#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.work/media" && pwd)"
PREFIX="$ROOT/prefix"
CMAKE="$ROOT/cmake/cmake-4.4.5-macos-universal/CMake.app/Contents/bin/cmake"
"$CMAKE" -S "$ROOT/jpeg/libjpeg-turbo-3.1.2" -B "$ROOT/jpeg-turbo-build" -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DENABLE_SHARED=OFF -DENABLE_STATIC=ON
"$CMAKE" --build "$ROOT/jpeg-turbo-build" -j 4
"$CMAKE" --install "$ROOT/jpeg-turbo-build"
"$CMAKE" -S "$ROOT/qpdf/qpdf-12.4.2" -B "$ROOT/qpdf-build" -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_DOC=OFF -DBUILD_TESTING=OFF -DUSE_IMPLICIT_CRYPTO=OFF -DREQUIRE_CRYPTO_NATIVE=ON -DSTATIC_JPEG=ON -DLIBJPEG_LIB_PATH="$PREFIX/lib/libjpeg.a" -DLIBJPEG_H_PATH="$PREFIX/include"
"$CMAKE" --build "$ROOT/qpdf-build" --target qpdf -j 4
