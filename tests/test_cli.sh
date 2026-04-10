#!/bin/bash
set -e  # Exit immediately if any command fails

# ── Unit tests ─────────────────────────────────────────────────────────────
for f in tests/cli/*.mojo; do
    pixi run mojo run -I src -I src/cli -D ASSERT=all --debug-level=full "$f"
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

# Precision flag (-P)
assert_output "precision -P 10" "0.3333333333" "$BINARY" "1/3" -P 10

# Scientific notation (--scientific / -S)
assert_output "scientific notation" "1.2345678E+4" "$BINARY" "12345.678" --scientific

# Engineering notation (--engineering / -E)
assert_output "engineering notation" "12.345678E+3" "$BINARY" "12345.678" --engineering

# Delimiter flag (-D)
assert_output "delimiter underscore" "1_234_567.89" "$BINARY" "1234567.89" -D "_"

# Rounding mode (--rounding-mode / -R)
assert_output "rounding mode ceiling" "0.33334" "$BINARY" "1/3" -P 5 -R ceiling

# Pad flag (--pad)
assert_output "pad trailing zeros" "0.33333" "$BINARY" "1/3" -P 5 --pad

# ── Negative expressions (allow_hyphen) ───────────────────────────────────
assert_output "negative number" "-3.14" "$BINARY" "-3.14"
assert_output "negative integer" "-42" "$BINARY" "-42"
assert_output "negative expression" "-6" "$BINARY" "-3*2"
assert_output "negative expression with pi" "-9.424777961" "$BINARY" "-3*pi" -P 10
assert_output "negative expr with abs()" "-3" "$BINARY" "-abs(3)" -P 10
assert_output "negative expression complex" "17.32428719" "$BINARY" "-3*pi/sin(10)" -P 10
assert_output "negative expression with parens" "-7.9306771922443685366581979690091558499739419154171" "$BINARY" "-3*pi*(sin(1))" -P 50
assert_output "negative zero" "-0" "$BINARY" "-0"
assert_output "negative minus negative" "1" "$BINARY" "-1*-1"
assert_output "negative power" "-8" "$BINARY" "-2^3"
assert_output "negative cancel out" "0" "$BINARY" "-1+1"
assert_output "negative subtraction" "-50" "$BINARY" "-100+50"

# ── Option/positional ordering ────────────────────────────────────────────
assert_output "options before expr" "0.3333333333" "$BINARY" -P 10 "1/3"
assert_output "options after expr" "0.3333333333" "$BINARY" "1/3" -P 10
assert_output "multiple options before expr" "1.732428719E+1" "$BINARY" -S -P 10 "-3*pi/sin(10)"
assert_output "mixed order: flag expr option" "1.732428719E+1" "$BINARY" -S "-3*pi/sin(10)" -P 10
assert_output "mixed order: option expr flag" "1.732428719E+1" "$BINARY" -P 10 "-3*pi/sin(10)" -S
assert_output "engineering before expr" "-12.345678E+3" "$BINARY" -E "-12345.678"
assert_output "engineering after expr" "-12.345678E+3" "$BINARY" "-12345.678" -E
assert_output "delimiter before expr" "3.141_592_654" "$BINARY" -D _ -P 10 "pi"
assert_output "delimiter after expr" "3.141_592_654" "$BINARY" "pi" -P 10 -D _
assert_output "rounding before expr" "0.33334" "$BINARY" -P 5 -R ceiling "1/3"
assert_output "all options before expr" "0.33334" "$BINARY" -P 5 -R ceiling --pad "1/3"
assert_output "all options after expr" "0.33334" "$BINARY" "1/3" -P 5 -R ceiling --pad

# ── Double-dash separator ─────────────────────────────────────────────────
assert_output "-- with negative expr" "-6" "$BINARY" -- "-3*2"
assert_output "-- with negative number" "-3.14" "$BINARY" -- "-3.14"
assert_output "-- with -e as expr" "-2.7182818284590452353602874713526624977572470937000" "$BINARY" -- "-e"

# ── Expressions that previously collided with short flags ─────────────────
assert_output "-e as expr (no --)" "-2.7182818284590452353602874713526624977572470937000" "$BINARY" "-e"
assert_output "-pi as expr" "-3.1415926535897932384626433832795028841971693993751" "$BINARY" "-pi"
assert_output "-sin(1) as expr" "-0.84147098480789650665250232163029899962256306079837" "$BINARY" "-sin(1)"

# ── Bare hyphen rejection ─────────────────────────────────────────────────
if "$BINARY" -- - >/dev/null 2>&1; then
    echo "FAIL: bare hyphen should be rejected"
    FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

echo ""
echo "CLI integration tests: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
