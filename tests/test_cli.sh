#!/bin/bash
set -e  # Exit immediately if any command fails

# Derive repo root from the script's own location so the tests work
# regardless of the caller's working directory.
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

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

# ── Pipe mode (stdin) ────────────────────────────────────────────────────
assert_pipe_output() {
    local description="$1"
    local input="$2"
    local expected="$3"
    shift 3
    local actual
    actual=$(printf '%s' "$input" | "$BINARY" "$@" 2>&1)
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $description"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_pipe_output "pipe single expression" "1+2" "3"
assert_pipe_output "pipe sqrt" "sqrt(2)" "1.4142135623730950488016887242096980785696718753769"
assert_pipe_output "pipe with precision" "1/3" "0.3333333333" -P 10
assert_pipe_output "pipe multiple lines" \
    "$(printf '1+2\nsqrt(4)\npi')" \
    "$(printf '3\n2\n3.1415926535897932384626433832795028841971693993751')"
assert_pipe_output "pipe skip comments" \
    "$(printf '# comment\n1+2\n\n# another\nsqrt(4)')" \
    "$(printf '3\n2')"
assert_pipe_output "pipe skip blank lines" \
    "$(printf '\n\n1+2\n\n')" \
    "3"
assert_pipe_output "pipe with scientific" "12345.678" "1.2345678E+4" -S
assert_pipe_output "pipe with engineering" "12345.678" "12.345678E+3" -E
assert_pipe_output "pipe with delimiter" "1234567.89" "1_234_567.89" -D "_"

# ── File mode (-F/--file flag) ────────────────────────────────────────────
# All test files live in tests/cli/test_data/ — no temp files needed.
DATA="tests/cli/test_data"

# --- basic.dm: constants, functions, arithmetic ---
assert_output "file mode basic.dm" \
    "$(printf '3.1415926535897932384626433832795028841971693993751\n2.7182818284590452353602874713526624977572470937000\n1.4142135623730950488016887242096980785696718753769\n1198.6470588235294117647058823529411764705882352941')" \
    "$BINARY" -F "$DATA/basic.dm"

assert_output "file mode basic.dm -P 10" \
    "$(printf '3.141592654\n2.718281828\n1.414213562\n1198.647059')" \
    "$BINARY" -F "$DATA/basic.dm" -P 10

# --- comments.txt: comments, blank lines, inline comments, whitespace ---
assert_output "file mode comments.txt" \
    "$(printf '2\n4\n6')" \
    "$BINARY" -F "$DATA/comments.txt"

# --- edge_cases.dm: zeros, negatives, nested parens, powers ---
assert_output "file mode edge_cases.dm" \
    "$(printf '0\n-0\n42\n-42\n0.001\n-0.001\n-6\n0\n-50\n6\n1\n1\n1\n10000000000')" \
    "$BINARY" -F "$DATA/edge_cases.dm"

assert_output "file mode edge_cases.dm -P 10" \
    "$(printf '0\n-0\n42\n-42\n0.001\n-0.001\n-6\n0\n-50\n6\n1\n1\n1\n1.000000000E+10')" \
    "$BINARY" -F "$DATA/edge_cases.dm" -P 10

# --- torture: deeply nested functions, trig, multi-arg, long chains ---
assert_output "file mode torture (no ext)" \
    "$(printf '1.0713523668582555369923173752696402459121546287121\n1.0538965678284563733480142148872799027597789207696\n1.1579208923731619542357098500868790785326998466564E+77\n515377520732011331036461129765621272702107522001\n11.796081289703860754690015480540861635182913811879\n3\n1E+1\n10\n10.000000000000000000000000000000000000000000000000\n3.1415926535897932384626433832795028841971693993751\n2.0000000000000000000000000000000000000000000000000\n2.0000000000000000000000000000000000000000000000000\n-4.0085856587109635320394984475849874956541040162735\n-3.2563470670302936892264646109942871401480252761141\n53.631111111111111111111111111111111111111111111111\n1.1579208923731619542357098500920328537400190717884E+77\n19')" \
    "$BINARY" -F "$DATA/torture"

# --- precision.dm: high-precision stress (repeating decimals, near-integers) ---
assert_output "file mode precision.dm" \
    "$(printf '0.14285714285714285714285714285714285714285714285714\n-2.6676418906242231236893288649633380405195232780734E-7\n2.0000000000000000000000000000000000000000000000000\n262537412640768743.99999999999925007259719818568888\n0.00022627290348967980473191579710694220169153814440402')" \
    "$BINARY" -F "$DATA/precision.dm"

# --- File mode with formatting flags ---
assert_output "file mode basic.dm -S" \
    "$(printf '3.1415926535897932384626433832795028841971693993751E0\n2.7182818284590452353602874713526624977572470937E0\n1.4142135623730950488016887242096980785696718753769E0\n1.1986470588235294117647058823529411764705882352941E+3')" \
    "$BINARY" -F "$DATA/basic.dm" -S

assert_output "file mode basic.dm -D _" \
    "$(printf '3.141_592_653_589_793_238_462_643_383_279_502_884_197_169_399_375_1\n2.718_281_828_459_045_235_360_287_471_352_662_497_757_247_093_700_0\n1.414_213_562_373_095_048_801_688_724_209_698_078_569_671_875_376_9\n1_198.647_058_823_529_411_764_705_882_352_941_176_470_588_235_294_1')" \
    "$BINARY" -F "$DATA/basic.dm" -D _

# --- Error cases ---
# File mode: nonexistent file gives a clear error
NONEXIST_OUTPUT=$("$BINARY" -F "nonexistent_file.dm" 2>&1 || true)
if echo "$NONEXIST_OUTPUT" | grep -qi "cannot read file"; then
    PASS=$((PASS + 1))
else
    echo "FAIL: file mode nonexistent should report 'cannot read file'"
    echo "  actual: $NONEXIST_OUTPUT"
    FAIL=$((FAIL + 1))
fi

# File mode + positional expr should be rejected
BOTH_OUTPUT=$("$BINARY" -F "nonexistent_file.dm" "1+2" 2>&1 || true)
if echo "$BOTH_OUTPUT" | grep -qi "cannot use both"; then
    PASS=$((PASS + 1))
else
    echo "FAIL: -F + positional expr should be rejected"
    echo "  actual: $BOTH_OUTPUT"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "CLI integration tests: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
