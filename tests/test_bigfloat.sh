#!/bin/bash
# ===----------------------------------------------------------------------=== #
# BigFloat test runner.
#
# BigFloat tests require the C wrapper (libdecimo_gmp_wrapper) and MPFR.
# This script:
#   1. Builds the C wrapper (if not already built)
#   2. Compiles each test file as a binary (mojo run can't link .dylib/.so)
#   3. Runs each binary with the library path set
#
# Usage:
#   bash tests/test_bigfloat.sh
#
# Prerequisites:
#   MPFR installed (brew install mpfr / apt install libmpfr-dev)
# ===----------------------------------------------------------------------=== #

set -e

# Build C wrapper if needed
WRAPPER_DIR="src/decimo/gmp"
if [[ "$(uname)" == "Darwin" ]]; then
    WRAPPER_LIB="$WRAPPER_DIR/libdecimo_gmp_wrapper.dylib"
else
    WRAPPER_LIB="$WRAPPER_DIR/libdecimo_gmp_wrapper.so"
fi

if [ ! -f "$WRAPPER_LIB" ]; then
    echo "Building C wrapper..."
    bash "$WRAPPER_DIR/build_gmp_wrapper.sh"
fi

# Compile and run each test file
for f in tests/bigfloat/*.mojo; do
    echo "=== $f ==="
    TMPBIN="/tmp/decimo_test_bigfloat_$$"
    pixi run mojo build -I src \
        -Xlinker -L./"$WRAPPER_DIR" -Xlinker -ldecimo_gmp_wrapper \
        -o "$TMPBIN" "$f"
    DYLD_LIBRARY_PATH="./$WRAPPER_DIR" LD_LIBRARY_PATH="./$WRAPPER_DIR" "$TMPBIN"
    rm -f "$TMPBIN"
done
