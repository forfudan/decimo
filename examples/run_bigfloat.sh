#!/bin/bash
# examples/run_bigfloat.sh — Quick build & run for a single BigFloat-using Mojo file.
#
# Usage (via pixi):
#   pixi run bf <file.mojo>
# Or directly:
#   bash examples/run_bigfloat.sh <file.mojo>
#
# What it does:
#   1. Ensures the GMP/MPFR C wrapper (libdecimo_gmp_wrapper) is built.
#   2. Ensures tests/decimo.mojoc is available (built on demand).
#   3. Builds <file.mojo> with `-I tests`, debug info, and ASSERT=all,
#      linking against the C wrapper. Output binary goes to temp/<name>.
#   4. Executes the binary with DYLD_LIBRARY_PATH / LD_LIBRARY_PATH set
#      so it can locate the wrapper at runtime.

set -eo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: pixi run bf <file.mojo>" >&2
    exit 2
fi

SRC="$1"
if [[ ! -f "$SRC" ]]; then
    echo "ERROR: file not found: $SRC" >&2
    exit 1
fi

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

WRAPPER_DIR="src/decimo/gmp"
if [[ "$(uname)" == "Darwin" ]]; then
    WRAPPER_LIB="$WRAPPER_DIR/libdecimo_gmp_wrapper.dylib"
else
    WRAPPER_LIB="$WRAPPER_DIR/libdecimo_gmp_wrapper.so"
fi

# 1. Build the C wrapper if missing.
if [[ ! -f "$WRAPPER_LIB" ]]; then
    echo "==> Building GMP/MPFR C wrapper..."
    bash "$WRAPPER_DIR/build_gmp_wrapper.sh"
fi

# 2. Ensure decimo.mojoc exists for `-I tests`.
if [[ ! -f tests/decimo.mojoc ]]; then
    echo "==> Building tests/decimo.mojoc..."
    pixi run mojo precompile src/decimo -o tests/decimo.mojoc
fi

# 3. Build the user's .mojo file into temp/<basename>.
mkdir -p temp
BIN_NAME=$(basename "$SRC" .mojo)
BIN_PATH="temp/$BIN_NAME"

echo "==> Building $SRC -> $BIN_PATH"
pixi run mojo build -I tests -D ASSERT=all --debug-level=full \
    -Xlinker -L./"$WRAPPER_DIR" -Xlinker -ldecimo_gmp_wrapper \
    -o "$BIN_PATH" "$SRC"

# 4. Run it with the wrapper on the dynamic loader path.
echo "==> Running $BIN_PATH"
DYLD_LIBRARY_PATH="$REPO_ROOT/$WRAPPER_DIR:${DYLD_LIBRARY_PATH:-}" \
LD_LIBRARY_PATH="$REPO_ROOT/$WRAPPER_DIR:${LD_LIBRARY_PATH:-}" \
    "$BIN_PATH"
