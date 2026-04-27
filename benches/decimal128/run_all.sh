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
  OPS=(add subtract multiply divide comparison from_string to_string ln log10 exp)
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

# ---- Build Mojo harness once (release: -O3, no debug info, asserts off) ----
echo ">>> Building Mojo harness (release: -O3, no debug, no asserts)..."
(cd mojo && pixi run --manifest-path ../../../pixi.toml mojo build \
     -I ../../../src -O3 -g0 -D ASSERT=none ./bench.mojo -o ./bench)

for op in "${OPS[@]}"; do
  echo
  echo "===== $op ====="

  echo "--- rust_decimal ---"
  "$RUST_BIN" --op "$op" --cases-dir "$(pwd)/cases" --logs-dir "$(pwd)/logs"

  # System.Decimal (C# and VB.NET) only implements the basic arithmetic ops.
  # ln / log10 / exp are not in the .NET BCL, so skip those harnesses for
  # those ops rather than failing the whole pipeline (set -e would abort
  # before aggregate.py runs).
  case "$op" in
    add|subtract|multiply|divide|comparison|from_string|to_string)
      DOTNET_SUPPORTS_OP=1 ;;
    *)
      DOTNET_SUPPORTS_OP=0 ;;
  esac

  if [ -n "$DOTNET_BIN" ] && [ "$DOTNET_SUPPORTS_OP" = "1" ]; then
    echo "--- System.Decimal (C#) ---"
    (cd csharp && "$DOTNET_BIN" run -c Release --no-build -- \
        --op "$op" --cases-dir ../cases --logs-dir ../logs)
    echo "--- System.Decimal (VB.NET) ---"
    (cd vbnet && "$DOTNET_BIN" run -c Release --no-build -- \
        --op "$op" --cases-dir ../cases --logs-dir ../logs)
  elif [ -n "$DOTNET_BIN" ]; then
    echo "--- System.Decimal: skipping (op '$op' not in .NET BCL) ---"
  fi

  echo "--- decimo.Decimal128 ---"
  (cd mojo && pixi run --manifest-path ../../../pixi.toml \
       ./bench --op "$op" --cases-dir ../cases --logs-dir ../logs)

  # For ln/log10/exp, also run a high-precision BigDecimal reference
  # (work=40, target=28) so the report has an oracle column showing the
  # numerically "more correct" value to compare decimo / rust against.
  case "$op" in
    ln|log10|exp)
      echo "--- decimo.BigDecimal (oracle, work=40, target=28) ---"
      (cd mojo && pixi run --manifest-path ../../../pixi.toml mojo run \
           -I ../../../src --debug-level=line-tables -D ASSERT=none \
           ./bigdec_ref.mojo --op "$op" \
           --cases-dir ../cases --logs-dir ../logs)
      ;;
  esac
done

echo
echo ">>> Aggregating into report..."
python3 ./aggregate.py \
    --logs-dir logs \
    --reports-dir reports \
    --langs mojo rust csharp vbnet bigdec \
    --ops "${OPS[@]}"
