#!/bin/bash
# ===----------------------------------------------------------------------=== #
# Build script for the Decimo GMP/MPFR C wrapper.
#
# This compiles gmp_wrapper.c into a shared library. The wrapper uses
# dlopen/dlsym to load MPFR at runtime, so it does NOT need -lmpfr or -lgmp
# at compile time. Any system with a C compiler can build this.
#
# Usage:
#   bash src/decimo/gmp/build_gmp_wrapper.sh
#
# Output:
#   src/decimo/gmp/libdecimo_gmp_wrapper.dylib  (macOS)
#   src/decimo/gmp/libdecimo_gmp_wrapper.so      (Linux)
#
# Prerequisites:
#   - A C compiler (cc, gcc, or clang)
#   - For actual MPFR use at runtime: brew install mpfr (macOS)
#     or apt install libmpfr-dev (Linux)
# ===----------------------------------------------------------------------=== #

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/gmp_wrapper.c"

OS="$(uname)"
if [[ "$OS" == "Darwin" ]]; then
    OUT="$SCRIPT_DIR/libdecimo_gmp_wrapper.dylib"
    cc -shared -O2 -o "$OUT" "$SRC"
    # Set install name so the loader finds it via rpath
    install_name_tool -id @rpath/libdecimo_gmp_wrapper.dylib "$OUT"
    echo "Built: $OUT"
elif [[ "$OS" == "Linux" ]]; then
    OUT="$SCRIPT_DIR/libdecimo_gmp_wrapper.so"
    cc -shared -O2 -fPIC -o "$OUT" "$SRC" -ldl
    echo "Built: $OUT"
else
    echo "Unsupported OS: $OS"
    exit 1
fi
