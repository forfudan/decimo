# BigInt cross-language benchmarks

This harness benchmarks `decimo.BigInt` against two arbitrary-precision
integer implementations:

| Lang     | Library              | Role                                                      |
| -------- | -------------------- | --------------------------------------------------------- |
| `mojo`   | `decimo.BigInt`      | System under test.                                        |
| `python` | `int` (stdlib)       | Correctness oracle (drives `match` flag) + timing column. |
| `rust`   | `num-bigint::BigInt` | Static-compiled peer (timing column).                     |

BigInt arithmetic is exact, so — unlike the BigDecimal harness — there is
**no precision parameter**. The report shows one timings table per op.

## Layout

```txt
    cases/            # source-of-truth TOML test cases (one file per op)
    mojo/   bench.mojo   +  bench   (release-built binary)
    python/ bench.py
    rust/   Cargo.toml  +  src/main.rs   (num-bigint harness)
    aggregate.py      # logs/*.csv  ->  reports/bigint_report_utc_<ts>.md
    run_all.sh        # build all available, run all ops, aggregate
    logs/             # per-language CSV bench logs (generated)
    reports/          # generated markdown reports
```

Log filenames embed the op so multiple runs can coexist:

```txt
    logs/<lang>_<op>_<YYYYMMDD>_<HHMMSS>.csv
```

## Quick start

```sh
./run_all.sh                          # all default ops
./run_all.sh --ops multiply power     # subset of ops
```

Direct invocation of any single harness:

```sh
# Mojo
cd mojo
pixi run --manifest-path ../../../pixi.toml ./bench \
    --op multiply --cases-dir ../cases --logs-dir ../logs

# Python
cd python
pixi run --manifest-path ../../../pixi.toml python3 bench.py \
    --op multiply --cases-dir ../cases --logs-dir ../logs

# Rust
cd rust
cargo run --release --quiet -- \
    --op multiply --cases-dir ../cases --logs-dir ../logs
```

## Ops

`add`, `multiply`, `floor_divide` (`//`), `power`, `shift` (`<<`), `sqrt`
(integer square root), `from_string`, `to_string`.

For `power` and `shift` the `b` field encodes a small integer (the exponent
or shift count); all other binary ops take `b` as the second operand.

## Adding a new test case

Edit the appropriate `cases/<op>.toml` file:

```toml
[config]
iterations = 500           # auto-tuner cap; actual count targets ~50ms

[[cases]]
name = "Large integer multiply"
a    = "{9,100}"           # {C,N} repeats C, N times → 100 nines
b    = "{9,100}"
```

## Report

The aggregator emits a markdown report with three sections:

1. **Cross-op overview** — one row per op showing median ns/iter per
   language plus `dm/py` and `dm/rs` ratios.
2. **Per-op detail** — for each op, one timings table. Each row carries a
   `match py` flag (`OK` / `DIFF`) comparing `decimo` against Python.
   Every `DIFF` is expanded inline as a collapsible `<details>` block
   listing every language's full result string.
3. **Agreement summary** — `decimo`-vs-Python match rate per op.

Ratios are `decimo ÷ peer`, so **a value below `1.00x` means `decimo` is
faster** than that peer.
