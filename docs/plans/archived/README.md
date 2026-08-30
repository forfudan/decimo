# Archived plans

Documents here describe work that is finished. They are kept because they
record *why* things are shaped the way they are, which is the part that is
expensive to reconstruct and easy to lose.

Nothing here is active. If a document moves back out of this folder, it is
because work on it has restarted.

| Document                        | Closed     | What it covers                                                                                                                       |
| ------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `inline_storage.md`             | 2026-08-30 | Why `BigUInt` keeps its words inside the struct, and the measurements. Done the day it was written; the capacity is a parameter now.  |
| `gmp_integration.md`            | 2026-08-30 | The GMP/MPFR survey and prototype. Phase 1 shipped as `BigFloat`; the `gmp=True` sugar was never started and is no longer wanted.        |
| `big_binary_integer.md`         | 2026-08-26 | Why `BigInt` is binary rather than decimal, and how the limb size was chosen. It moved from 2^32 to 2^64 in #286.                    |
| `advanced_math_optimization.md` | 2026-08-30 | February 2026 notes on the trigonometric functions and `pi()`. The buffer-digit and base items are done; three smaller ones moved to `docs/internal/todo.md`.            |
| `bigint2_benchmark_analysis.md` | 2026-08-26 | The February 2026 analysis that led to that type. Every task in its roadmap is done; the last, Toom-Cook and NTT, closed 2026-08-26. |
| `cli_calculator.md`             | 2026-08-26 | Design of the `decimo` calculator. Built, shipped, 58 integration tests. Nothing outstanding.                                        |
| `decimal128_enhancement.md`     | 2026-08-26 | `Decimal128` parity and performance work, executed by 2026-05-06. Two micro-optimisations were deliberately left.                    |

Benchmark tables inside these documents are snapshots of their own date and are
not maintained. Current figures are generated into `docs/benchmarks.md` by
`pixi run benchdoc`.

Older references to these files may still use their previous `docs/plans/`
paths. Those references are historical statements and were correct when
written; they have not been rewritten.
