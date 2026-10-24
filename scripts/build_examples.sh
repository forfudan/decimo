#!/bin/bash
# ===----------------------------------------------------------------------=== #
# Compile every example under `examples/`, to catch one that stopped building.
#
# `pixi run format` covers `examples/`, and nothing built it, so an example
# could be reformatted into a release without ever being compiled. The output
# binaries go to `temp/examples/` and are not run: an example's printed values
# are checked by `pixi run docexamples` where they appear in a document.
#
# `examples_on_mpf.mojo` is skipped. It links the MPFR C wrapper, which needs
# `pixi run buildgmp` and MPFR on the system; `bash examples/run_mpf.sh
# examples/examples_on_mpf.mojo` builds and runs that one.
# ===----------------------------------------------------------------------=== #

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p temp/examples

failed=0
for source in examples/*.mojo; do
    name="$(basename "$source" .mojo)"
    if [[ "$name" == "examples_on_mpf" ]]; then
        echo "skip  $source (needs the MPFR wrapper)"
        continue
    fi
    if pixi run mojo build -I src -o "temp/examples/$name" "$source"; then
        echo "ok    $source"
    else
        echo "FAIL  $source" >&2
        failed=1
    fi
done

if [[ "$failed" -ne 0 ]]; then
    echo "at least one example did not compile" >&2
    exit 1
fi
echo "every example compiles"
