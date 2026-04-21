# Decimal128 cross-language benchmarks

Compares **decimo.Decimal128** (Mojo) against alternative 128-bit decimal
implementations on the *same* test cases, for both **result equivalence** and
**performance**.

| Folder    | Implementation                | Status  |
| --------- | ----------------------------- | ------- |
| `mojo/`   | `decimo.Decimal128`           | enabled |
| `rust/`   | `rust_decimal` 1.x            | enabled |
| `csharp/` | .NET 10 `System.Decimal` (C#) | enabled |
| `vbnet/`  | .NET 10 `System.Decimal` (VB) | enabled |

The previous suite compared `decimo.Decimal128` to Python's `decimal.Decimal`,
which is architecturally different (arbitrary-precision BigDecimal under the
hood). Comparing against fixed-width 128-bit decimals (rust_decimal,
System.Decimal) is the apples-to-apples reference.

## Layout

```txt
benches/decimal128/
├── cases/                      # shared TOML test cases (source of truth)
│   ├── add.toml                # [config] iterations + [[cases]] {name, a, b}
│   ├── subtract.toml
│   ├── multiply.toml
│   ├── divide.toml
│   ├── comparison.toml
│   ├── from_string.toml
│   └── to_string.toml
├── mojo/
│   └── bench.mojo              # single dispatcher: --op {add|subtract|...}
├── rust/
│   ├── Cargo.toml
│   └── src/main.rs             # single dispatcher: --op {...}
├── csharp/
│   ├── bench.csproj
│   └── Program.cs              # single dispatcher: --op {...}
├── vbnet/
│   ├── bench.vbproj
│   └── Program.vb              # single dispatcher: --op {...}
├── logs/                       # per-(lang,op,timestamp) CSV records
├── reports/                    # aggregated markdown reports
├── aggregate.py                # joins per-lang CSVs into a comparison table
├── run_all.sh                  # build + run all langs + aggregate
└── README.md
```

## TOML case format

```toml
[config]
iterations = 10000        # per-case iteration count

[[cases]]
name = "Mid-scale"
a    = "12345.67890123456789012345"
b    = "98765.43210987654321098765"   # omit for unary ops
```

The `{C,N}` macro (e.g. `0.{0,28}1`) repeats string `C` exactly `N` times and
is supported by both the Mojo loader (`decimo.tests.expand_value`) and the
Rust loader (`expand()` in `rust/src/main.rs`).

## CSV log schema

Each per-language run appends one CSV per op to `logs/`:

```txt
timestamp,language,op,case_name,result,ns_per_iter
20250420_134812,rust,add,Mid-scale,111111.11101111111111111111110,22.420
```

The aggregator joins on `(op, case_name)` to produce the comparison report.

## Running

```bash
# Build + run every language on every op + aggregate report
./run_all.sh

# Or just one op, one language
(cd rust  && cargo run --release --quiet -- --op multiply \
                --cases-dir ../cases --logs-dir ../logs)
(cd mojo  && pixi run --manifest-path ../../../pixi.toml mojo run \
                -I ../../../src --debug-level=line-tables -D ASSERT=none \
                ./bench.mojo --op multiply \
                --cases-dir ../cases --logs-dir ../logs)

# Re-run aggregator only (uses latest log per (lang, op))
python3 ./aggregate.py --logs-dir logs --reports-dir reports \
    --ops add subtract multiply divide comparison from_string to_string
```

The aggregator emits `reports/dec128_report_<timestamp>.md` with a system &
toolchain header, a cross-op overview table, per-op detail tables (split into
*results* and *timings*), and a result-equivalence summary across all
languages. Sample (multiply op):

| case      | match | decimo | rust | csharp | vbnet | dm/rs | dm/cs | dm/vb |
| --------- | ----- | ------ | ---- | ------ | ----- | ----- | ----- | ----- |
| Mid-scale | OK    | 4.00   | 2.54 | 1.38   | 0.92  | 1.6x  | 2.9x  | 4.3x  |

A `DIFF` in the **match** column means the implementations produced different
result strings — investigate before trusting any perf delta on that case.

## Adding a new language

1. Create `<lang>/` with whatever build system the language wants.
2. Implement a binary that takes `--op X --cases-dir D --logs-dir D`.
3. Read `cases/X.toml`, expand `{C,N}` patterns, run `iterations` reps per
   case (best-of-5), and append CSV rows matching the schema above.
4. Add the build + run lines to `run_all.sh`.
5. Pass `--langs mojo rust csharp vbnet <lang>` to `aggregate.py` (or update
   the default list at the top of `aggregate.py`).

## Caveats / known divergences

- `rust_decimal::FromStr` rejects scientific notation; Rust harness routes
  `e`/`E` strings through `Decimal::from_scientific`.
- Mojo's `Decimal128("...")` path can produce slightly different trailing-zero
  output than rust_decimal's `to_string()` even when the numeric value is
  equal. The `match` column flags those cases for inspection.
- The Mojo harness has no `black_box`-equivalent yet; on `comparison` (whose
  body is a deterministic constant) the optimizer fully folds the inner loop
  and reports `0.00 ns/iter`. Treat that op's perf numbers as "below
  measurement floor". Result-equivalence (`match` column) is still meaningful.
  Rust's `std::hint::black_box` keeps its numbers honest.
