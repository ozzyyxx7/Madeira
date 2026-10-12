#!/bin/bash
# Rebuild the iOS ARM64 melonDS DS libretro core shipped inside Madeira.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/build/melonds-ds/source"
BUILD="$ROOT/build/melonds-ds/ios-build"
DEST="$ROOT/app/Madeira/NintendoDS"
UPSTREAM="https://github.com/JesseTG/melonds-ds.git"
COMMIT="f394adbacb5722ee97c1b37c8064da9a25818310" # v1.4.0

command -v cmake >/dev/null
command -v ninja >/dev/null
if [ ! -d "$SOURCE/.git" ]; then
    git clone --depth 1 --branch v1.4.0 --recurse-submodules "$UPSTREAM" "$SOURCE"
fi
ACTUAL="$(git -C "$SOURCE" rev-parse HEAD)"
if [ "$ACTUAL" != "$COMMIT" ]; then
    echo "Unexpected melonDS DS revision: $ACTUAL (expected $COMMIT)" >&2
    exit 1
fi
git -C "$SOURCE" submodule update --init --recursive

cmake -S "$SOURCE" -B "$BUILD" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$SOURCE/cmake/toolchain/ios.toolchain.cmake" \
    -DPLATFORM=OS64 -DDEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_AS_SHARED_LIBRARY=ON -DENABLE_JIT=OFF -DENABLE_OPENGL=OFF
cmake --build "$BUILD" --target melondsds_libretro -j "$(sysctl -n hw.ncpu)"

mkdir -p "$DEST"
cp "$BUILD/src/libretro/melondsds_libretro.dylib" "$DEST/melondsds_libretro.dylib"
cp "$BUILD/_deps/libretro-common-src/include/libretro.h" "$DEST/libretro.h"
cp "$SOURCE/LICENSE" "$ROOT/app/Madeira/legal/LICENSE-melonDS-DS-GPL-3.0.txt"
echo "melonDS DS core ready: $DEST/melondsds_libretro.dylib"
