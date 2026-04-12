#!/bin/bash
# ===----------------------------------------------------------------------=== #
# CLI Calculator Benchmarks — Correctness & Performance
#
# Compares decimo against bc and python3 on every expression:
#   1. Correctness — first 15 significant digits must agree
#   2. Performance — average wall-clock latency over $ITERATIONS runs
#
# Usage:
#   bash benches/cli/bench_cli.sh
#   ITERATIONS=20 bash benches/cli/bench_cli.sh
#
# Requirements:
#   - ./decimo binary (pixi run mojo build -I src -I src/cli src/cli/main.mojo -o decimo)
#   - perl with Time::HiRes (standard on macOS)
#   - bc (standard on macOS / Linux)
#   - python3 with mpmath for function comparisons (pip install mpmath)
# ===----------------------------------------------------------------------=== #

set -euo pipefail
export LC_ALL=C  # consistent decimal formatting

BINARY="${BINARY:-./decimo}"
export ITERATIONS="${ITERATIONS:-10}"
PREVIEW=35  # max chars of result preview

# ── Prerequisites ──────────────────────────────────────────────────────────

if ! [[ -x "$BINARY" ]]; then
    echo "Error: $BINARY not found or not executable."
    echo "Build first: pixi run mojo build -I src -I src/cli src/cli/main.mojo -o decimo"
    exit 1
fi

HAS_BC=false;  command -v bc      &>/dev/null && HAS_BC=true
HAS_PY=false;  command -v python3 &>/dev/null && HAS_PY=true

# ── Counters ───────────────────────────────────────────────────────────────

COMPARISONS=0
MATCHES=0
MISMATCHES=0
ERRORS=0

# ── Helpers ────────────────────────────────────────────────────────────────

# Time a command over $ITERATIONS runs, return average ms.
elapsed_ms() {
    perl -MTime::HiRes=time -e '
        my $n = $ENV{ITERATIONS};
        my @cmd = @ARGV;
        open(my $oldout, ">&", \*STDOUT);
        open(my $olderr, ">&", \*STDERR);
        # Warm-up (untimed)
        open(STDOUT, ">/dev/null"); open(STDERR, ">/dev/null");
        system(@cmd);
        open(STDOUT, ">&", $oldout); open(STDERR, ">&", $olderr);
        # Timed
        my $t0 = time();
        for (1 .. $n) {
            open(STDOUT, ">/dev/null"); open(STDERR, ">/dev/null");
            system(@cmd);
            open(STDOUT, ">&", $oldout); open(STDERR, ">&", $olderr);
        }
        printf "%.2f\n", (time() - $t0) * 1000.0 / $n;
    ' -- "$@"
}

# Extract a canonical comparison key from a numeric string:
# adjusted base-10 exponent + first 15 significant digits.
# This ensures values that differ only by exponent (e.g. 1E+10 vs 1E+11)
# are correctly detected as a MISMATCH.
sig_digits() {
    local s="${1#-}"            # strip sign; check_match handles sign separately
    local explicit_exp=0
    local mantissa="$s"

    # Split off explicit exponent (e.g. 1.23E+45 → mantissa=1.23, exp=45)
    if [[ "$mantissa" =~ ^([^eE]+)[eE]([+-]?[0-9]+)$ ]]; then
        mantissa="${BASH_REMATCH[1]}"
        explicit_exp="${BASH_REMATCH[2]}"
    fi

    local int_part frac_part digits int_len adjusted_exp first_nonzero

    if [[ "$mantissa" == *.* ]]; then
        int_part="${mantissa%%.*}"
        frac_part="${mantissa#*.}"
        # Strip trailing zeros from fractional part — they are not significant
        frac_part=$(echo "$frac_part" | sed 's/0*$//')
    else
        int_part="$mantissa"
        frac_part=""
    fi

    digits="${int_part}${frac_part}"
    digits=$(echo "$digits" | sed 's/^0*//; s/0*$//')

    if [[ -z "$digits" ]]; then
        echo "ZERO"
        return 0
    fi

    # Compute adjusted exponent so the key is position-independent
    if [[ "$int_part" =~ [1-9] ]]; then
        int_part=$(echo "$int_part" | sed 's/^0*//')
        int_len=${#int_part}
        adjusted_exp=$(( explicit_exp + int_len - 1 ))
    else
        first_nonzero=$(echo "$frac_part" | sed -n 's/^\(0*\)[1-9].*$/\1/p' | wc -c | tr -d ' ')
        first_nonzero=$(( first_nonzero - 1 ))
        adjusted_exp=$(( explicit_exp - first_nonzero - 1 ))
    fi

    echo "${adjusted_exp}:$(echo "$digits" | cut -c1-15)"
}

# Compare two results by leading significant digits.
check_match() {
    local a="$1" b="$2"
    local sign_a="" sign_b=""
    if [[ "$a" == -* ]]; then sign_a="-"; fi
    if [[ "$b" == -* ]]; then sign_b="-"; fi
    if [[ "$sign_a" != "$sign_b" ]]; then echo "MISMATCH"; return 0; fi
    local sa sb
    sa=$(sig_digits "$a")
    sb=$(sig_digits "$b")
    if [[ "$sa" == "$sb" ]]; then echo "MATCH"; else echo "MISMATCH"; fi
    return 0
}

# Truncate a result string for display.
preview() {
    if (( ${#1} > PREVIEW )); then echo "${1:0:$PREVIEW}..."; else echo "$1"; fi
}

# Record a comparison result.
record() {
    local tag="$1"
    if [[ "$tag" == "ERROR" ]]; then
        ERRORS=$((ERRORS + 1))
    else
        COMPARISONS=$((COMPARISONS + 1))
        if [[ "$tag" == "MATCH" ]]; then
            MATCHES=$((MATCHES + 1))
        else
            MISMATCHES=$((MISMATCHES + 1))
        fi
    fi
    return 0
}

# ── Main comparison driver ─────────────────────────────────────────────────
#
# bench_compare LABEL PREC DECIMO_EXPR [BC_EXPR] [PY_CODE]
#
# BC_EXPR:  expression piped to "bc -l".  "scale=PREC; " is prepended.
#           Pass "" to skip bc.
# PY_CODE:  full python3 -c code.  "__P__" is replaced with PREC.
#           Pass "" to skip python3.

bench_compare() {
    local label="$1" prec="$2" d_expr="$3"
    local bc_expr="${4:-}" py_code="${5:-}"

    printf "  %s (P=%s)\n" "$label" "$prec"

    # ── decimo ──
    local d_result d_ms
    d_result=$("$BINARY" "$d_expr" -P "$prec" 2>/dev/null || echo "ERROR")
    d_ms=$(elapsed_ms "$BINARY" "$d_expr" -P "$prec")
    printf "    %-10s %-38s %8s ms\n" "decimo:" "$(preview "$d_result")" "$d_ms"
    if [[ "$d_result" == "ERROR" ]]; then
        record "ERROR"
        echo ""
        return
    fi

    # ── bc ──
    if [[ -n "$bc_expr" ]] && $HAS_BC; then
        local full_bc="scale=$prec; $bc_expr"
        local b_result b_ms tag
        # tr -d '\\\n' removes bc's backslash line-continuations
        b_result=$(echo "$full_bc" | bc -l 2>/dev/null | tr -d '\\\n' || echo "ERROR")
        b_ms=$(elapsed_ms bash -c "echo '$full_bc' | bc -l")
        if [[ "$b_result" == "ERROR" ]]; then
            tag="ERROR"
        else
            tag=$(check_match "$d_result" "$b_result")
        fi
        printf "    %-10s %-38s %8s ms   %s\n" "bc:" "$(preview "$b_result")" "$b_ms" "$tag"
        record "$tag"
    fi

    # ── python3 ──
    if [[ -n "$py_code" ]] && $HAS_PY; then
        local full_py="${py_code//__P__/$prec}"
        local p_result p_ms tag
        p_result=$(python3 -c "$full_py" 2>/dev/null || echo "ERROR")
        p_ms=$(elapsed_ms python3 -c "$full_py")
        if [[ "$p_result" == "ERROR" ]]; then
            tag="ERROR"
        else
            tag=$(check_match "$d_result" "$p_result")
        fi
        printf "    %-10s %-38s %8s ms   %s\n" "python3:" "$(preview "$p_result")" "$p_ms" "$tag"
        record "$tag"
    fi

    echo ""
}

# ── Python expression templates (__P__ → precision) ────────────────────────

PY_DEC="from decimal import Decimal as D,getcontext as gc;gc().prec=__P__"
PY_MP="from mpmath import mp;mp.dps=__P__"

# ── Header ─────────────────────────────────────────────────────────────────

echo "============================================================"
echo " Decimo CLI Benchmark — Correctness & Performance"
echo "============================================================"
echo "Binary:       $BINARY"
echo "Iterations:   $ITERATIONS per expression"
echo "Tools:        decimo$(${HAS_BC} && echo ', bc')$(${HAS_PY} && echo ', python3')"
echo "Date:         $(date '+%Y-%m-%d %H:%M')"
echo ""

# ── 1. Arithmetic ──────────────────────────────────────────────────────────

echo "--- 1. Arithmetic -------------------------------------------"
echo ""

bench_compare "1 + 1" 50 \
    "1+1" \
    "1+1" \
    "print(1+1)"

bench_compare "100*12 - 23/17" 50 \
    "100*12-23/17" \
    "100*12-23/17" \
    "${PY_DEC};print(D('100')*12-D('23')/D('17'))"

bench_compare "2^256" 50 \
    "2^256" \
    "2^256" \
    "print(2**256)"

bench_compare "1/7" 50 \
    "1/7" \
    "1/7" \
    "${PY_DEC};print(D(1)/D(7))"

bench_compare "(1+2) * (3+4)" 50 \
    "(1+2)*(3+4)" \
    "(1+2)*(3+4)" \
    "print((1+2)*(3+4))"

# ── 2. Functions ───────────────────────────────────────────────────────────

echo "--- 2. Functions (P=50) -------------------------------------"
echo ""

bench_compare "sqrt(2)" 50 \
    "sqrt(2)" \
    "sqrt(2)" \
    "${PY_DEC};print(D(2).sqrt())"

bench_compare "ln(2)" 50 \
    "ln(2)" \
    "l(2)" \
    "${PY_MP};print(mp.log(2))"

bench_compare "exp(1)" 50 \
    "exp(1)" \
    "e(1)" \
    "${PY_MP};print(mp.exp(1))"

bench_compare "sin(3.1415926535897932384626433833)" 50 \
    "sin(3.1415926535897932384626433833)" \
    "s(3.1415926535897932384626433833)" \
    "${PY_MP};print(mp.sin(3.1415926535897932384626433833))"

bench_compare "cos(0)" 50 \
    "cos(0)" \
    "c(0)" \
    "${PY_MP};print(mp.cos(0))"

bench_compare "root(27, 3)" 50 \
    "root(27, 3)" \
    "" \
    "${PY_MP};print(mp.cbrt(27))"

bench_compare "log(256, 2)" 50 \
    "log(256, 2)" \
    "" \
    "${PY_MP};print(mp.log(256,2))"

# ── 3. Precision scaling — sqrt(2) ────────────────────────────────────────

echo "--- 3. Precision scaling — sqrt(2) --------------------------"
echo ""

for p in 50 100 200 500 1000; do
    bench_compare "sqrt(2)" "$p" \
        "sqrt(2)" \
        "sqrt(2)" \
        "${PY_DEC};print(D(2).sqrt())"
done

# ── 4. Precision scaling — pi ─────────────────────────────────────────────

echo "--- 4. Precision scaling — pi -------------------------------"
echo ""

for p in 50 100 200 500 1000; do
    bench_compare "pi" "$p" \
        "pi" \
        "4*a(1)" \
        "${PY_MP};print(mp.pi)"
done

# ── 5. Complex expressions ────────────────────────────────────────────────

echo "--- 5. Complex expressions ----------------------------------"
echo ""

bench_compare "ln(exp(1))" 50 \
    "ln(exp(1))" \
    "" \
    "${PY_MP};print(mp.log(mp.exp(1)))"

bench_compare "sin(pi/4) + cos(pi/4)" 50 \
    "sin(pi/4)+cos(pi/4)" \
    "s(4*a(1)/4)+c(4*a(1)/4)" \
    "${PY_MP};print(mp.sin(mp.pi/4)+mp.cos(mp.pi/4))"

bench_compare "2^256 + 3^100" 50 \
    "2^256+3^100" \
    "2^256+3^100" \
    "print(2**256+3**100)"

# ── 6. Pipe mode (decimo only) ────────────────────────────────────────────

echo "--- 6. Pipe mode (decimo only) ------------------------------"
echo "  No bc/python3 equivalent for multi-line pipe processing."
echo ""

for entry in \
    "3 simple exprs|printf '1+2\n3*4\n5/6\n' | $BINARY" \
    "5 mixed exprs|printf '1+2\nsqrt(2)\npi\nln(10)\n2^64\n' | $BINARY"; do
    desc="${entry%%|*}"
    cmd="${entry#*|}"
    ms=$(elapsed_ms bash -c "$cmd")
    printf "  %-42s %8s ms\n" "pipe: $desc" "$ms"
done
echo ""

# ── Summary ────────────────────────────────────────────────────────────────

echo "============================================================"
printf " Summary: %d comparisons — %d MATCH, %d MISMATCH" \
    "$COMPARISONS" "$MATCHES" "$MISMATCHES"
if (( ERRORS > 0 )); then
    printf ", %d ERROR (tool missing or failed)" "$ERRORS"
fi
echo ""
echo "============================================================"

if (( MISMATCHES > 0 )); then
    exit 1
fi
