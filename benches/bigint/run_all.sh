#!/usr/bin/env bash
# Run BigInt benchmarks for mojo (decimo) / python / rust, then write a
# timestamped markdown report under reports/.
#
# Raw per-language CSV logs land in   logs/{lang}_{op}_{ts}.csv
# Aggregated markdown report lands in reports/bigint_report_{ts}.md
#
# BigInt is exact: there is NO precision parameter.
#
# Usage:
#   ./run_all.sh                          # all default ops
#   ./run_all.sh --ops multiply power     # subset of ops
#
# Default ops: add multiply floor_divide power shift sqrt from_string to_string
set -uo pipefail

cd "$(dirname "$0")"

OPS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ops) shift ;;
    --)    shift; break ;;
    -*)    echo "Unknown flag: $1" >&2; exit 2 ;;
    *)     OPS+=("$1"); shift ;;
  esac
done

if [ ${#OPS[@]} -eq 0 ]; then
  OPS=(add multiply floor_divide power shift sqrt from_string to_string)
fi

mkdir -p logs reports

# Always purge any prior *.csv so an old run's data does not leak into the
# aggregated report.
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

# ---- Build Rust harness ----
HAVE_RUST=0
if command -v cargo >/dev/null 2>&1; then
  echo ">>> Building Rust harness (release)..."
  if (cd rust && cargo build --release --quiet); then
    HAVE_RUST=1
    RUST_BIN="$(pwd)/rust/target/release/bench"
  else
    echo "!!! Rust build failed; skipping rust harness."
  fi
else
  echo ">>> cargo not found; skipping rust harness."
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

for op in "${OPS[@]}"; do
  echo
  echo "===== $op ====="

  if [ "$HAVE_MOJO" = "1" ]; then
    run_step "decimo (mojo)" \
      bash -c "cd mojo && $PIXI_RUN ./bench --op '$op' --cases-dir ../cases --logs-dir ../logs"
  fi
  if [ "$HAVE_PY" = "1" ]; then
    run_step "python int" \
      bash -c "cd python && $PIXI_RUN python3 bench.py --op '$op' --cases-dir ../cases --logs-dir ../logs"
  fi
  if [ "$HAVE_RUST" = "1" ]; then
    run_step "rust num-bigint" \
      "$RUST_BIN" --op "$op" --cases-dir "$(pwd)/cases" --logs-dir "$(pwd)/logs"
  fi
done

echo
echo ">>> Aggregating into report..."
$PIXI_RUN_TOP python3 ./aggregate.py \
    --logs-dir logs \
    --reports-dir reports \
    --langs mojo python rust \
    --ops "${OPS[@]}"
