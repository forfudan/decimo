#!/bin/bash
# CLI dispatch for Decimo benchmarks
# Usage: pixi run bench <type> [operation]
#
# Types: bigint (bint), biguint (buint), decimal128 (dec), bigdecimal (bdec)
# Operations: add, multiply, subtract, floor_divide, truncate_divide, etc.
#             (varies by type — omit to get interactive menu)
#
# Examples:
#   pixi run bench bigint add
#   pixi run bench dec sqrt
#   pixi run bench biguint          # interactive menu
#   pixi run bench                  # show help

set -e

TYPE="$1"
OP="$2"

# --- Help ---
if [[ -z "$TYPE" ]]; then
    echo "Usage: pixi run bench <type> [operation]"
    echo ""
    echo "Types:"
    echo "  bigint   (int)        BigInt benchmarks (BigInt10 vs BigInt vs Python int)"
    echo "  biguint  (uint)       BigUInt benchmarks (BigUInt vs Python int)"
    echo "  decimal128 (dec128)   Decimal128 benchmarks (Decimal128 vs Python decimal)"
    echo "  bigdecimal (dec)      BigDecimal benchmarks (BigDecimal vs Python decimal)"
    echo "  cli                   CLI calculator end-to-end latency benchmarks"
    echo ""
    echo "Omit operation to get interactive menu for that type."
    echo ""
    echo "Examples:"
    echo "  pixi run bench bigint add"
    echo "  pixi run bench dec sqrt"
    echo "  pixi run bench biguint"
    echo "  pixi run bench cli"
    exit 0
fi

# --- Map short names ---
case "$TYPE" in
    int)  TYPE="bigint" ;;
    uint) TYPE="biguint" ;;
    dec128)   TYPE="decimal128" ;;
    dec)  TYPE="bigdecimal" ;;
esac

# --- CLI benchmarks (special case — shell script, not Mojo) ---
if [[ "$TYPE" == "cli" ]]; then
    exec bash benches/cli/bench_cli.sh
fi

DIR="benches/$TYPE"

if [[ ! -d "$DIR" ]]; then
    echo "Error: Unknown type '$TYPE'"
    echo "Available: bigint (int), biguint (uint), decimal128 (dec128), bigdecimal (dec)"
    exit 1
fi

# --- decimal128: cross-language pipeline (decimo + rust + csharp + vbnet) ---
# When OP is empty, run the full suite via run_all.sh and produce a
# timestamped report under benches/decimal128/reports/. The .NET (csharp,
# vbnet) harnesses are built and run only if the `dotnet` SDK is on PATH;
# otherwise the pipeline silently runs with the available languages.
# When OP is given, dispatch to the single-op cross-lang run_all.sh too.
if [[ "$TYPE" == "decimal128" ]]; then
    if [[ -z "$OP" ]]; then
        exec bash "$DIR/run_all.sh"
    else
        exec bash "$DIR/run_all.sh" "$OP"
    fi
fi

# --- Interactive mode (no operation specified) ---
if [[ -z "$OP" ]]; then
    cd "$DIR"
    pixi run mojo run -I ../ bench.mojo
    exit 0
fi

# --- Direct operation mode ---
cd "$DIR"

# Find a .mojo file matching the operation name
# Try patterns: bench_<type>_<op>.mojo, bench_<op>.mojo
FILE=""
for pattern in "bench_${TYPE}_${OP}.mojo" "bench_${OP}.mojo"; do
    if [[ -f "$pattern" ]]; then
        FILE="$pattern"
        break
    fi
done

if [[ -z "$FILE" ]]; then
    echo "Error: No bench file found for type='$TYPE', operation='$OP'"
    echo ""
    echo "Available operations in $TYPE/:"
    ls bench_*.mojo 2>/dev/null | grep -v '^bench\.mojo$' | sed "s/bench_${TYPE}_//;s/bench_//;s/\.mojo$//" | sort
    exit 1
fi

echo "Running: $FILE"
pixi run mojo run -I ../ "$FILE"
