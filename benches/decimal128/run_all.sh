#!/usr/bin/env bash
# Run all decimal128 benchmarks in all available languages, then write a
# timestamped markdown report under reports/.
#
# Raw per-language CSV logs land in   logs/{lang}_{op}_{ts}.csv
# Aggregated markdown report lands in reports/dec128_report_{ts}.md
#
# Usage:  ./run_all.sh [op1 op2 ...]
#         (with no args, runs the full op set)
set -euo pipefail

cd "$(dirname "$0")"

OPS=("$@")
if [ ${#OPS[@]} -eq 0 ]; then
  OPS=(add subtract multiply divide comparison from_string to_string)
fi

mkdir -p logs reports

# ---- Build Rust harness once ----
echo ">>> Building Rust harness..."
(cd rust && cargo build --release --quiet)
RUST_BIN="$(pwd)/rust/target/release/bench"

# ---- Build C# harness once (if dotnet is available) ----
DOTNET_BIN=""
if command -v dotnet >/dev/null 2>&1; then
  DOTNET_BIN="$(command -v dotnet)"
elif [ -x /opt/homebrew/opt/dotnet/bin/dotnet ]; then
  DOTNET_BIN="/opt/homebrew/opt/dotnet/bin/dotnet"
fi
if [ -n "$DOTNET_BIN" ]; then
  echo ">>> Building C# harness..."
  (cd csharp && "$DOTNET_BIN" build -c Release --nologo --verbosity quiet)
  echo ">>> Building VB.NET harness..."
  (cd vbnet && "$DOTNET_BIN" build -c Release --nologo --verbosity quiet)
else
  echo ">>> dotnet not found; skipping C# and VB.NET harnesses."
fi

for op in "${OPS[@]}"; do
  echo
  echo "===== $op ====="

  echo "--- rust_decimal ---"
  "$RUST_BIN" --op "$op" --cases-dir "$(pwd)/cases" --logs-dir "$(pwd)/logs"

  if [ -n "$DOTNET_BIN" ]; then
    echo "--- System.Decimal (C#) ---"
    (cd csharp && "$DOTNET_BIN" run -c Release --no-build -- \
        --op "$op" --cases-dir ../cases --logs-dir ../logs)
    echo "--- System.Decimal (VB.NET) ---"
    (cd vbnet && "$DOTNET_BIN" run -c Release --no-build -- \
        --op "$op" --cases-dir ../cases --logs-dir ../logs)
  fi

  echo "--- decimo.Decimal128 ---"
  (cd mojo && pixi run --manifest-path ../../../pixi.toml mojo run \
       -I ../../../src --debug-level=line-tables -D ASSERT=none \
       ./bench.mojo --op "$op" \
       --cases-dir ../cases --logs-dir ../logs)
done

echo
echo ">>> Aggregating into report..."
python3 ./aggregate.py \
    --logs-dir logs \
    --reports-dir reports \
    --ops "${OPS[@]}"
