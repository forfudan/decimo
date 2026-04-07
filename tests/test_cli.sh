#!/bin/bash
set -e  # Exit immediately if any command fails

# ── Unit tests ─────────────────────────────────────────────────────────────
for f in tests/cli/*.mojo; do
    pixi run mojo run -I src -I src/cli -D ASSERT=all --debug-level=line-tables "$f"
done

# ── Integration tests (exercise the compiled binary) ───────────────────────
BINARY="./decimo"

if [[ ! -x "$BINARY" ]]; then
    echo "SKIP: CLI integration tests ($BINARY not found)"
    exit 0
fi

PASS=0
FAIL=0

assert_output() {
    local description="$1"
    shift
    local expected="$1"
    shift
    local actual
    actual=$("$@" 2>&1)
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $description"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

# Basic expression
assert_output "basic addition" "5" "$BINARY" "2+3"

# Precision flag (-p)
assert_output "precision -p 10" "0.3333333333" "$BINARY" "1/3" -p 10

# Scientific notation (--scientific / -s)
assert_output "scientific notation" "1.2345678E+4" "$BINARY" "12345.678" --scientific

# Engineering notation (--engineering / -e)
assert_output "engineering notation" "12.345678E+3" "$BINARY" "12345.678" --engineering

# Delimiter flag (-d)
assert_output "delimiter underscore" "1_234_567.89" "$BINARY" "1234567.89" -d "_"

# Rounding mode (--rounding-mode / -r)
assert_output "rounding mode ceiling" "0.33334" "$BINARY" "1/3" -p 5 -r ceiling

# Pad flag (--pad / -P)
assert_output "pad trailing zeros" "0.33333" "$BINARY" "1/3" -p 5 --pad

echo ""
echo "CLI integration tests: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
