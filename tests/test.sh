#!/bin/bash
# tests/test.sh — Unified test runner for all Decimo test suites.
#
# Called via pixi:
#   pixi run test                Run ALL test suites
#   pixi run test <suite>        Run one test suite
#   pixi run test --list         List available suites
#
# Can also be called directly:
#   bash tests/test.sh
#   bash tests/test.sh bigdecimal
#   bash tests/test.sh --list
#
# Suite aliases (case-insensitive):
#   bigdecimal  bdec  decimal   → BigDecimal tests
#   bigint      bint            → BigInt tests
#   biguint     buint uint      → BigUint tests
#   bigint10    bint10 int10    → BigInt10 tests
#   decimal128  dec128 d128     → Decimal128 tests
#   rational    rat   frac      → Rational number tests
#   expression  expr  eval      → Expression engine tests
#   numerals    numeral chinese → Numeral system tests
#   traits      numeric num     → Trait conformance tests (`Numeric`,
#                                 `Parsable`, `Rootable`)
#   bigfloat    bfloat float    → BigFloat tests (requires MPFR)
#   toml                        → TOML parser tests
#   cli                         → CLI calculator tests
#   python      py              → Python binding tests
#   decimo      core            → All core suites (bigdecimal+bigint+biguint+bigint10+
#                                 decimal128+rational+expression+numerals+traits)
#   all                         → Everything (decimo + toml + cli)
#
# Environment:
#   DECIMO_TEST_JOBS=N   Run up to N Mojo test files concurrently. Defaults to
#                        the number of logical CPUs locally, and to 1 when CI
#                        is set. Output is buffered per file and replayed in
#                        the original order either way.
#   DECIMO_TEST_NO_CACHE=1
#                        Do not keep the built test binaries in `temp/tests`
#                        (see the binary cache below).
#
# On where the time goes: almost none of it is the tests. The five suites that
# compare against Python report the largest numbers in the harness output, but
# those numbers are milliseconds -- the rounding suite runs 106 cases in 58 ms,
# and one Mojo-to-Python round trip through `decimal` costs 0.675 us. What the
# wall clock measures is Mojo compiling each test file: 5.4 s cold and 1.4 s
# warm, against 58 ms of running. That is why this file precompiles the package
# to `decimo.mojoc`, runs the files concurrently, and asks for the cheaper
# debug level below.

set -eo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$REPO_ROOT"

# ── Parallelism ──────────────────────────────────────────────────────────────
# Every Mojo test file is its own compile-and-run, and on a warm compile
# cache that process spends far more time compiling than running tests: the
# whole core suite is ~0.8 s of test bodies inside ~71 s of wall clock, i.e.
# ~99% fixed per-file overhead (the binary cache below removes it on re-runs). The files are independent, so they can run
# concurrently, and doing so is the only lever that matters: 67 s sequentially
# against 11 s on 14 cores.
#
# Locally the default is therefore one job per logical CPU. The parallel path
# buffers each file's output and replays it whole, in the original order, so a
# failing run reads exactly like a sequential one - it just arrives all at once
# at the end of the suite rather than incrementally.
#
# CI keeps the sequential default: each suite is already its own job there, the
# runners have few cores to share, and a serialized transcript is easier to
# attribute a crash to when the only evidence is a log. `CI` is set by GitHub
# Actions and by essentially every other CI provider.
detect_cpu_count() {
    local n=""
    if command -v nproc >/dev/null 2>&1; then
        n=$(nproc 2>/dev/null)
    elif command -v sysctl >/dev/null 2>&1; then
        n=$(sysctl -n hw.logicalcpu 2>/dev/null)
    fi
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 )); then
        printf '%s' "$n"
    else
        printf '1'
    fi
}

if [[ -n "${DECIMO_TEST_JOBS:-}" ]]; then
    :
elif [[ -n "${CI:-}" ]]; then
    DECIMO_TEST_JOBS=1
else
    DECIMO_TEST_JOBS=$(detect_cpu_count)
fi

# ── Preflight: ensure tests/decimo.mojoc exists ─────────────────────────────
# All Mojo test invocations below use `-I tests` to pick up the prebuilt
# `decimo.mojoc` (`mojo run` cannot resolve `decimo.X.Y.foo` qualified
# references when re-traversing source via `-I src`). On a fresh checkout the
# package may not exist yet, so build it on demand. CI normally stages a
# prebuilt artifact via the `setup-decimo` action, in which case this is a
# no-op.
ensure_decimo_package() {
    # Rebuild when the artifact is missing *or older than any source file*.
    # Only checking for existence meant that editing `src/` and running the
    # tests would quietly test the previous build: this is how a merged branch
    # once reached CI green while the package did not compile, and how a
    # mutation test can pass against code that is no longer there.
    if [[ -f tests/decimo.mojoc ]] \
        && [[ -z $(find src/decimo -name '*.mojo' -newer tests/decimo.mojoc -print -quit) ]]; then
        return 0
    fi
    if [[ -f tests/decimo.mojoc ]]; then
        echo "tests/decimo.mojoc is older than src/decimo; rebuilding..."
    else
        echo "tests/decimo.mojoc not found; building it now..."
    fi
    pixi run mojo precompile src/decimo -o tests/decimo.mojoc
}

# ── Suite definitions ────────────────────────────────────────────────────────

# ── Binary cache ─────────────────────────────────────────────────────────────
# What a test file costs is compiling it, not running it: a warm `mojo run` is
# about 1.1 s per file and the tests inside take milliseconds. Each file is
# therefore built once to `temp/tests/<name>` and the binary is reused until
# the file or `decimo.mojoc` is newer than it. A re-run with nothing changed
# drops from about 8 s to about 1 s. It does nothing for the first run after an
# edit (a warm `mojo build` costs the same as `mojo run`), and nothing after a
# `src` change, which rebuilds the package and so every binary.
# `DECIMO_TEST_NO_CACHE=1` builds under a name of its own and removes it
# again, so the run neither trusts nor leaves a cached binary.
TEST_BIN_DIR="temp/tests"

test_binary_path() {
    printf '%s/%s' "$TEST_BIN_DIR" "$(printf '%s' "${1%.mojo}" | tr '/' '_')"
}

test_binary_is_fresh() {
    local bin="$1" f="$2"
    [[ -x "$bin" && "$bin" -nt "$f" && "$bin" -nt tests/decimo.mojoc ]]
}

run_one_mojo_file() {
    local f="$1"
    local bin
    bin=$(test_binary_path "$f")
    if [[ -z "${DECIMO_TEST_NO_CACHE:-}" ]]; then
        if test_binary_is_fresh "$bin" "$f"; then
            "$bin"
            return $?
        fi
        build_and_run_mojo_file "$f" "$bin"
        return $?
    fi
    # `DECIMO_TEST_NO_CACHE`: build under a name of its own, so the run
    # neither trusts nor replaces a cached binary, and take it away again
    # whether the test passed or failed.
    bin="$bin.nocache.$$"
    build_and_run_mojo_file "$f" "$bin"
    local nocache_rc=$?
    # `mojo build --debug-level=line-tables` writes a `.dSYM` bundle next to
    # the binary on macOS; that belongs to the build too.
    rm -rf "$bin" "$bin.dSYM"
    return $nocache_rc
}

build_and_run_mojo_file() {
    local f="$1"
    local bin="$2"
    mkdir -p "$TEST_BIN_DIR"
    # Retry once on transient Python init crash (libpython sporadic load failure).
    local attempt=1
    local max_attempts=2
    while (( attempt <= max_attempts )); do
        # `&&` rather than `if`: after an `if ... fi` whose condition was
        # false, `$?` is the `if` statement's own status, which is 0. The
        # `return $rc` below would then hand back success for a suite that
        # failed to compile, and the whole run would exit green.
        # `line-tables` rather than `full`. On a warm cache the whole suite
        # takes 13.0 s with `full` and 8.0 s with this, two runs each, and the
        # two produce identical output on a failing assertion -- the file and
        # line in an assert message come from the assert, not from the debug
        # info. See the note above `DECIMO_TEST_JOBS`.
        pixi run mojo build -I tests -D ASSERT=all --debug-level=line-tables \
            -o "$bin" "$f" \
            && "$bin" \
            && break
        local rc=$?
        if (( attempt < max_attempts )); then
            echo "WARN: $f failed (rc=$rc), retrying (attempt $((attempt + 1))/$max_attempts)..."
            attempt=$((attempt + 1))
        else
            echo "ERROR: $f failed after $max_attempts attempts"
            return $rc
        fi
    done
}

# Log path for one test file inside a scratch directory. `/` is not legal in a
# filename, so flatten the path rather than recreating the tree.
mojo_log_path() {
    printf '%s/%s.log' "$1" "$(printf '%s' "$2" | tr '/' '_')"
}

run_mojo_files() {
    ensure_decimo_package

    if (( DECIMO_TEST_JOBS <= 1 )); then
        local f
        for f in "$@"; do
            echo "=== $f ==="
            run_one_mojo_file "$f" || return $?
        done
        return 0
    fi

    # Nothing is printed until the batch finishes, so say up front how many
    # workers are running - otherwise a parallel run looks like a hang.
    echo "--- running $# file(s) on $DECIMO_TEST_JOBS parallel job(s) ---"

    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/decimo-tests.XXXXXX")

    # `--run-one` always exits 0 and records failure as a marker file, so xargs
    # never aborts the batch early; the verdict is collected in the replay loop
    # below, which also keeps the output in the caller's order.
    printf '%s\n' "$@" \
        | xargs -P "$DECIMO_TEST_JOBS" -I{} bash "$SELF" --run-one {} "$tmpdir" \
        || true

    local rc=0 f log
    for f in "$@"; do
        echo "=== $f ==="
        log=$(mojo_log_path "$tmpdir" "$f")
        if [[ -f "$log" ]]; then
            cat "$log"
        else
            echo "ERROR: $f produced no output (worker did not run)"
            rc=1
        fi
        if [[ -f "$log.fail" ]]; then
            rc=1
        fi
    done

    rm -rf "$tmpdir"
    return $rc
}

run_mojo_suite() {
    run_mojo_files tests/"$1"/*.mojo
}

run_bigdecimal()  { run_mojo_suite bigdecimal; }
run_bigint()      { run_mojo_suite bigint; }
run_biguint()     { run_mojo_suite biguint; }
run_bigint10()    { run_mojo_suite bigint10; }
run_decimal128()  { run_mojo_suite decimal128; }
run_rational()    { run_mojo_suite rational; }
run_expression()  { run_mojo_suite expression; }
run_numerals()    { run_mojo_suite numerals; }
run_traits()      { run_mojo_suite traits; }
run_toml()        { run_mojo_suite toml; }

run_bigfloat() {
    # BigFloat tests require the C wrapper (libdecimo_gmp_wrapper) and MPFR.
    ensure_decimo_package
    local WRAPPER_DIR="src/decimo/gmp"
    local WRAPPER_LIB
    if [[ "$(uname)" == "Darwin" ]]; then
        WRAPPER_LIB="$WRAPPER_DIR/libdecimo_gmp_wrapper.dylib"
    else
        WRAPPER_LIB="$WRAPPER_DIR/libdecimo_gmp_wrapper.so"
    fi

    if [ ! -f "$WRAPPER_LIB" ]; then
        echo "Building C wrapper..."
        bash "$WRAPPER_DIR/build_gmp_wrapper.sh"
    fi

    local TMPBIN
    cleanup() { rm -f "$TMPBIN"; }
    trap cleanup EXIT

    for f in tests/bigfloat/*.mojo; do
        echo "=== $f ==="
        TMPBIN=$(mktemp /tmp/decimo_test_bigfloat_XXXXXX)
        pixi run mojo build -I tests --debug-level=line-tables \
            -Xlinker -L./"$WRAPPER_DIR" -Xlinker -ldecimo_gmp_wrapper \
            -o "$TMPBIN" "$f"
        DYLD_LIBRARY_PATH="./$WRAPPER_DIR" LD_LIBRARY_PATH="./$WRAPPER_DIR" "$TMPBIN"
        rm -f "$TMPBIN"
    done
}

run_cli() {
    # CLI tests need the extra -I src/cli include path
    ensure_decimo_package
    for f in tests/cli/*.mojo; do
        pixi run mojo run -I tests -I src/cli -D ASSERT=all --debug-level=line-tables "$f"
    done

    # Integration tests (exercise the compiled binary)
    local BINARY="./decimo"
    if [[ ! -x "$BINARY" ]]; then
        echo "SKIP: CLI integration tests ($BINARY not found)"
        return 0
    fi

    local PASS=0
    local FAIL=0

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

    # Basic expression
    assert_output "basic addition" "5" "$BINARY" "2+3"

    # Precision flag (-P)
    assert_output "precision -P 10" "0.3333333333" "$BINARY" "1/3" -P 10

    # Scientific notation (--scientific / -S)
    assert_output "scientific notation" "1.2345678E+4" "$BINARY" "12345.678" --scientific

    # Engineering notation (--engineering / -E)
    assert_output "engineering notation" "12.345678E+3" "$BINARY" "12345.678" --engineering

    # Delimiter flag (--delimiter)
    assert_output "delimiter underscore" "1_234_567.89" "$BINARY" "1234567.89" --delimiter "_"

    # Rounding mode (--rounding-mode / -R)
    assert_output "rounding mode ceiling" "0.33334" "$BINARY" "1/3" -P 5 -R ceiling

    # Pad flag (--pad)
    assert_output "pad trailing zeros" "0.33333" "$BINARY" "1/3" -P 5 --pad

    # ── Negative expressions (allow_hyphen) ───────────────────────────────
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

    # ── Option/positional ordering ────────────────────────────────────────
    assert_output "options before expr" "0.3333333333" "$BINARY" -P 10 "1/3"
    assert_output "options after expr" "0.3333333333" "$BINARY" "1/3" -P 10
    assert_output "multiple options before expr" "1.732428719E+1" "$BINARY" -S -P 10 "-3*pi/sin(10)"
    assert_output "mixed order: flag expr option" "1.732428719E+1" "$BINARY" -S "-3*pi/sin(10)" -P 10
    assert_output "mixed order: option expr flag" "1.732428719E+1" "$BINARY" -P 10 "-3*pi/sin(10)" -S
    assert_output "engineering before expr" "-12.345678E+3" "$BINARY" -E "-12345.678"
    assert_output "engineering after expr" "-12.345678E+3" "$BINARY" "-12345.678" -E
    assert_output "delimiter before expr" "3.141_592_654" "$BINARY" --delimiter _ -P 10 "pi"
    assert_output "delimiter after expr" "3.141_592_654" "$BINARY" "pi" -P 10 --delimiter _
    assert_output "rounding before expr" "0.33334" "$BINARY" -P 5 -R ceiling "1/3"
    assert_output "all options before expr" "0.33334" "$BINARY" -P 5 -R ceiling --pad "1/3"
    assert_output "all options after expr" "0.33334" "$BINARY" "1/3" -P 5 -R ceiling --pad

    # ── Double-dash separator ─────────────────────────────────────────────
    assert_output "-- with negative expr" "-6" "$BINARY" -- "-3*2"
    assert_output "-- with negative number" "-3.14" "$BINARY" -- "-3.14"
    assert_output "-- with -e as expr" "-2.7182818284590452353602874713526624977572470937000" "$BINARY" -- "-e"

    # ── Expressions that previously collided with short flags ─────────────
    assert_output "-e as expr (no --)" "-2.7182818284590452353602874713526624977572470937000" "$BINARY" "-e"
    assert_output "-pi as expr" "-3.1415926535897932384626433832795028841971693993751" "$BINARY" "-pi"
    assert_output "-sin(1) as expr" "-0.84147098480789650665250232163029899962256306079837" "$BINARY" "-sin(1)"

    # ── Bare hyphen rejection ─────────────────────────────────────────────
    if "$BINARY" -- - >/dev/null 2>&1; then
        echo "FAIL: bare hyphen should be rejected"
        FAIL=$((FAIL + 1))
    else
        PASS=$((PASS + 1))
    fi

    # ── Pipe mode (stdin) ────────────────────────────────────────────────
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
    assert_pipe_output "pipe with delimiter" "1234567.89" "1_234_567.89" --delimiter "_"

    # ── File mode (-F/--file flag) ────────────────────────────────────────
    local DATA="tests/cli/test_data"

    assert_output "file mode basic.dm" \
        "$(printf '3.1415926535897932384626433832795028841971693993751\n2.7182818284590452353602874713526624977572470937000\n1.4142135623730950488016887242096980785696718753769\n1198.6470588235294117647058823529411764705882352941')" \
        "$BINARY" -F "$DATA/basic.dm"

    assert_output "file mode basic.dm -P 10" \
        "$(printf '3.141592654\n2.718281828\n1.414213562\n1198.647059')" \
        "$BINARY" -F "$DATA/basic.dm" -P 10

    assert_output "file mode comments.txt" \
        "$(printf '2\n4\n6')" \
        "$BINARY" -F "$DATA/comments.txt"

    assert_output "file mode edge_cases.dm" \
        "$(printf '0\n-0\n42\n-42\n0.001\n-0.001\n-6\n0\n-50\n6\n1\n1\n1\n10000000000')" \
        "$BINARY" -F "$DATA/edge_cases.dm"

    assert_output "file mode edge_cases.dm -P 10" \
        "$(printf '0\n-0\n42\n-42\n0.001\n-0.001\n-6\n0\n-50\n6\n1\n1\n1\n1.000000000E+10')" \
        "$BINARY" -F "$DATA/edge_cases.dm" -P 10

    assert_output "file mode torture (no ext)" \
        "$(printf '1.0713523668582555369923173752696402459121546287121\n1.0538965678284563733480142148872799027597789207696\n1.1579208923731619542357098500868790785326998466564E+77\n515377520732011331036461129765621272702107522001\n11.796081289703860754690015480540861635182913811879\n3\n1E+1\n10\n10.000000000000000000000000000000000000000000000000\n3.1415926535897932384626433832795028841971693993751\n2.0000000000000000000000000000000000000000000000000\n2.0000000000000000000000000000000000000000000000000\n-4.0085856587109635320394984475849874956541040162735\n-3.2563470670302936892264646109942871401480252761141\n53.631111111111111111111111111111111111111111111111\n1.1579208923731619542357098500920328537400190717884E+77\n19')" \
        "$BINARY" -F "$DATA/torture"

    assert_output "file mode precision.dm" \
        "$(printf '0.14285714285714285714285714285714285714285714285714\n-2.6676418906242231236893288649633380405195232780734E-7\n2.0000000000000000000000000000000000000000000000000\n262537412640768743.99999999999925007259719818568888\n0.00022627290348967980473191579710694220169153814440402')" \
        "$BINARY" -F "$DATA/precision.dm"

    assert_output "file mode basic.dm -S" \
        "$(printf '3.1415926535897932384626433832795028841971693993751E0\n2.7182818284590452353602874713526624977572470937E0\n1.4142135623730950488016887242096980785696718753769E0\n1.1986470588235294117647058823529411764705882352941E+3')" \
        "$BINARY" -F "$DATA/basic.dm" -S

    assert_output "file mode basic.dm --delimiter _" \
        "$(printf '3.141_592_653_589_793_238_462_643_383_279_502_884_197_169_399_375_1\n2.718_281_828_459_045_235_360_287_471_352_662_497_757_247_093_700_0\n1.414_213_562_373_095_048_801_688_724_209_698_078_569_671_875_376_9\n1_198.647_058_823_529_411_764_705_882_352_941_176_470_588_235_294_1')" \
        "$BINARY" -F "$DATA/basic.dm" --delimiter _

    # Error cases
    local NONEXIST_OUTPUT
    NONEXIST_OUTPUT=$("$BINARY" -F "nonexistent_file.dm" 2>&1 || true)
    if echo "$NONEXIST_OUTPUT" | grep -qi "cannot read file"; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: file mode nonexistent should report 'cannot read file'"
        echo "  actual: $NONEXIST_OUTPUT"
        FAIL=$((FAIL + 1))
    fi

    local BOTH_OUTPUT
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
        return 1
    fi
}

run_python() {
    pixi run python python/tests/test_decimo.py
}

# Composite suites
run_decimo() {
    # One batch rather than nine sequential ones: with DECIMO_TEST_JOBS > 1 a
    # per-suite batch drains to a handful of stragglers before the next suite
    # can start, so the pool sits half idle. Sequentially this is the same
    # ordering as before, since the directories are listed in the same order.
    run_mojo_files \
        tests/bigdecimal/*.mojo \
        tests/bigint/*.mojo \
        tests/biguint/*.mojo \
        tests/bigint10/*.mojo \
        tests/decimal128/*.mojo \
        tests/rational/*.mojo \
        tests/expression/*.mojo \
        tests/numerals/*.mojo \
        tests/traits/*.mojo
}

run_all() {
    run_decimo
    run_toml
    run_cli
}

# ── Suite resolution (name → function) ───────────────────────────────────────

resolve() {
    local name
    name=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$name" in
        bigdecimal|bdec|decimal)  echo "run_bigdecimal" ;;
        bigint|bint)              echo "run_bigint" ;;
        biguint|buint|uint)       echo "run_biguint" ;;
        bigint10|bint10|int10)    echo "run_bigint10" ;;
        decimal128|dec128|d128)   echo "run_decimal128" ;;
        rational|rat|frac)        echo "run_rational" ;;
        expression|expr|eval)     echo "run_expression" ;;
        numerals|numeral|chinese) echo "run_numerals" ;;
        traits|numeric|num)      echo "run_traits" ;;
        bigfloat|bfloat|float)    echo "run_bigfloat" ;;
        toml)                     echo "run_toml" ;;
        cli)                      echo "run_cli" ;;
        python|py)                echo "run_python" ;;
        decimo|core)              echo "run_decimo" ;;
        all)                      echo "run_all" ;;
        *)                        return 1 ;;
    esac
}

list_suites() {
    echo "Available test suites:"
    echo ""
    printf "  %-28s %s\n" "SUITE (aliases)" "DESCRIPTION"
    printf "  %-28s %s\n" "---" "---"
    printf "  %-28s %s\n" "bigdecimal, bdec, decimal"   "BigDecimal tests"
    printf "  %-28s %s\n" "bigint, bint"                "BigInt tests"
    printf "  %-28s %s\n" "biguint, buint, uint"        "BigUint tests"
    printf "  %-28s %s\n" "bigint10, bint10, int10"     "BigInt10 tests"
    printf "  %-28s %s\n" "decimal128, dec128, d128"    "Decimal128 tests"
    printf "  %-28s %s\n" "rational, rat, frac"         "Rational number tests"
    printf "  %-28s %s\n" "expression, expr, eval"      "Expression engine tests"
    printf "  %-28s %s\n" "numerals, numeral, chinese"  "Numeral system tests"
    printf "  %-28s %s\n" "traits, numeric, num"        "Trait conformance tests"
    printf "  %-28s %s\n" "bigfloat, bfloat, float"     "BigFloat tests (requires MPFR)"
    printf "  %-28s %s\n" "toml"                        "TOML parser tests"
    printf "  %-28s %s\n" "cli"                         "CLI calculator tests"
    printf "  %-28s %s\n" "python, py"                  "Python binding tests"
    printf "  %-28s %s\n" "decimo, core"                "All core suites (bdec+bint+buint+bint10+dec128+rational+expression+traits)"
    printf "  %-28s %s\n" "all"                         "Everything (decimo + toml + cli)"
}

# ── Main ─────────────────────────────────────────────────────────────────────

# Internal: run one test file into a log under a scratch directory. Used by the
# parallel path in `run_mojo_files`; always exits 0 so the batch is not aborted.
if [ "${1:-}" = "--run-one" ]; then
    log=$(mojo_log_path "$3" "$2")
    if ! run_one_mojo_file "$2" > "$log" 2>&1; then
        : > "$log.fail"
    fi
    exit 0
fi

if [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
    list_suites
    exit 0
fi

if [ $# -ge 1 ]; then
    fn=$(resolve "$1" 2>/dev/null) || {
        echo "Error: unknown test suite '$1'" >&2
        echo "" >&2
        list_suites >&2
        exit 1
    }
    "$fn"
    exit 0
fi

# No arguments → run all
run_all
