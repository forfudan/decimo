#!/usr/bin/env bash
# Run BigDecimal benchmarks across precisions for mojo (decimo) / python,
# then write a timestamped markdown report under reports/.
#
# Raw per-language CSV logs land in   logs/{lang}_{op}_p{prec}_{ts}.csv
# Aggregated markdown report lands in reports/bigdec_report_{ts}.md
#
# Usage:
#   ./run_all.sh                               # all default ops + per-op precs
#   ./run_all.sh --ops multiply exp            # subset of ops, per-op precs
#   ./run_all.sh --precisions 100 1000         # custom precs (apply to all ops)
#   ./run_all.sh --ops sqrt --precisions 100   # both
#
# When --precisions is NOT supplied, per-op default precisions are used:
#   - exp / ln / root            -> 100, 1000             (heavy transcendentals)
#   - add / subtract / multiply / divide
#                                -> 100, 1000, 10000      (cheap, stress)
#   - everything else            -> 100, 1000, 10000      (default sweep)
#
# Default ops: add subtract multiply divide comparison from_string to_string
#              sqrt exp ln root round.
set -uo pipefail

cd "$(dirname "$0")"

OPS=()
PRECS=()
mode=ops
while [ $# -gt 0 ]; do
  case "$1" in
    --ops)        mode=ops;  shift ;;
    --precisions) mode=prec; shift ;;
    --)           shift; break ;;
    -*)
      echo "Unknown flag: $1" >&2; exit 2 ;;
    *)
      if [ "$mode" = "ops" ]; then OPS+=("$1"); else PRECS+=("$1"); fi
      shift ;;
  esac
done

if [ ${#OPS[@]} -eq 0 ]; then
  OPS=(add subtract multiply divide comparison from_string to_string \
       sqrt exp ln root round)
fi

# Per-op precision picker. Returns space-separated list on stdout.
precs_for_op() {
  local op="$1"
  if [ ${#PRECS[@]} -gt 0 ]; then
    echo "${PRECS[@]}"
    return
  fi
  case "$op" in
    exp|ln|root)                            echo "100 1000" ;;
    add|subtract|multiply|divide)           echo "100 1000 10000" ;;
    # Precision-insensitive ops: run once. The kernels do no rounding at
    # `precision`, so additional precisions just duplicate the work.
    comparison|from_string|to_string)       echo "100" ;;
    *)                                      echo "100 1000 10000" ;;
  esac
}

mkdir -p logs reports

# Always purge any prior *.csv so an old run's data does not
# leak into the aggregated report
rm -f logs/*.csv 2>/dev/null || true

PIXI_RUN="pixi run --manifest-path ../../../pixi.toml"
PIXI_RUN_TOP="pixi run --manifest-path ../../pixi.toml"

# ---- Build Mojo harness ----
HAVE_MOJO=0
echo ">>> Building Mojo harness (release: -O3, no debug, no asserts)..."
if (cd mojo && $PIXI_RUN mojo build \
     -I ../../../src -O3 -g0 -D ASSERT=none ./bench.mojo -o ./bench); then
  HAVE_MOJO=1
else
  echo "!!! Mojo build failed; skipping mojo harness."
fi

# ---- Check Python (needs tomllib OR tomli) ----
HAVE_PY=0
if $PIXI_RUN_TOP python3 -c 'import tomllib' 2>/dev/null \
   || $PIXI_RUN_TOP python3 -c 'import tomli' 2>/dev/null; then
  HAVE_PY=1
else
  echo ">>> python (with tomllib >=3.11 or tomli) not available; skipping python harness."
fi

run_step() {
  local label="$1"; shift
  echo "--- $label ---"
  "$@" || echo "!!! $label failed (continuing)"
}

# Track every (op, prec) we actually run, for the aggregator.
COMBOS=()

for op in "${OPS[@]}"; do
  read -r -a op_precs <<<"$(precs_for_op "$op")"
  for prec in "${op_precs[@]}"; do
    COMBOS+=("$op:$prec")
    echo
    echo "===== $op @ precision=$prec ====="

    if [ "$HAVE_MOJO" = "1" ]; then
      run_step "decimo (mojo)" \
        bash -c "cd mojo && $PIXI_RUN ./bench --op '$op' --precision '$prec' --cases-dir ../cases --logs-dir ../logs"
    fi
    if [ "$HAVE_PY" = "1" ]; then
      run_step "python decimal.Decimal" \
        bash -c "cd python && $PIXI_RUN python3 bench.py --op '$op' --precision '$prec' --cases-dir ../cases --logs-dir ../logs"
    fi
  done
done

echo
echo ">>> Aggregating into report..."
$PIXI_RUN_TOP python3 ./aggregate.py \
    --logs-dir logs \
    --reports-dir reports \
    --langs mojo python \
    --combos "${COMBOS[@]}"
