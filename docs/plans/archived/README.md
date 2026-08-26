# Archived plans

Documents here describe work that is finished. They are kept because they
record *why* things are shaped the way they are, which is the part that is
expensive to reconstruct and easy to lose.

Nothing here is active. If a document moves back out of this folder, it is
because work on it has restarted.

| Document                        | Closed     | What it covers                                                                                                                       |
| ------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `big_binary_integer.md`         | 2026-08-26 | Why `BigInt` is base-2^32, and how the limb size was chosen. The renaming plan in it was carried out.                                |
| `bigint2_benchmark_analysis.md` | 2026-08-26 | The February 2026 analysis that led to that type. Every task in its roadmap is done; the last, Toom-Cook and NTT, closed 2026-08-26. |
| `cli_calculator.md`             | 2026-08-26 | Design of the `decimo` calculator. Built, shipped, 58 integration tests. One minor item outstanding: the `:vars` meta-command.       |
| `decimal128_enhancement.md`     | 2026-08-26 | `Decimal128` parity and performance work, executed by 2026-05-06. Two micro-optimisations were deliberately left.                    |

Benchmark tables inside these documents are snapshots of their own date and are
not maintained. Current figures are generated into `docs/benchmarks.md` by
`pixi run benchdoc`.

Older references to these files may still use their previous `docs/plans/`
paths. Those references are historical statements and were correct when
written; they have not been rewritten.
