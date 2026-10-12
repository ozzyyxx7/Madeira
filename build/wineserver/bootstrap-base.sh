#!/bin/bash
# Compile the unmodified Wine server files needed before build.sh replaces its
# iOS-specific files. The original build.sh required an unpublished base archive.
set -euo pipefail

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$BUILD_DIR/../.." && pwd)"
WINE_SRC="$REPO_ROOT/wine"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
OBJ_DIR="$BUILD_DIR/obj"
BASE_DIR="$OBJ_DIR/base"

test -f "$WINE_SRC/build-macos/include/config.h" || {
    echo "Configure wine/build-macos before building wineserver" >&2
    exit 1
}
mkdir -p "$BASE_DIR"

# These are the server/Makefile.in C sources not replaced in build.sh.
SOURCES=(
    atom change clipboard completion console d3dkmt debugger device directory
    file hook mailslot mutex named_pipe procfs ptrace registry serial signal
    symlink timer token trace
)

CC_FLAGS=(
    -arch arm64 -isysroot "$SDK" -miphoneos-version-min=17.0 -O2
    -I"$WINE_SRC/include" -I"$WINE_SRC/include/wine"
    -I"$WINE_SRC/build-macos/include" -I"$BUILD_DIR" -I"$WINE_SRC/server"
    -I"$BUILD_DIR/../ntdll-unix/shims" -I"$BUILD_DIR/../madsync"
    -DHAVE_LINUX_NTSYNC_H=1
    -include "$BUILD_DIR/config_ios.h" -include stdarg.h
    -include "$BUILD_DIR/unicode_fix.h"
    -include "$BUILD_DIR/wineserver_ios_kill.h"
    -DBINDIR=\"/usr/local/bin\" -DDATADIR=\"/usr/local/share\"
    -D__WINESRC__ -DWINE_IOS=1 -Dmain=wineserver_main
    -Wno-implicit-function-declaration
)

for name in "${SOURCES[@]}"; do
    printf '  %s... ' "$name"
    if xcrun -sdk iphoneos clang "${CC_FLAGS[@]}" -c "$WINE_SRC/server/$name.c" \
        -o "$BASE_DIR/$name.o" 2>"$BASE_DIR/$name.err"; then
        echo OK
    else
        echo FAILED
        cat "$BASE_DIR/$name.err" >&2
        exit 1
    fi
done

xcrun -sdk iphoneos ar rcs "$OBJ_DIR/libwineserver.a" "$BASE_DIR"/*.o
echo "Base wineserver archive: $OBJ_DIR/libwineserver.a"
