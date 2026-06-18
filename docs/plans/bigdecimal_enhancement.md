# BigDecimal Enhancement Plan

> **Date**: 2026-02-21 (created), 2026-04-30 (last consolidated)
> **Target**: decimo >=0.9.0
> **Mojo Version**: >=0.26.2
>
> 子曰：學而時習之，不亦說乎。

This document tracks the BigDecimal performance & correctness work
started on 2026-02-21. It is the single source of truth for the
arbitrary-precision decimal hot-path optimisation effort. The earlier
predecessor (`bigdecimal_biguint_benchmark_analysis.md`) was
removed in PR #232; its content is recoverable from git history if a
fuller historical view is needed.

## 1. Cross-Language Snapshot

Scope: **arbitrary-precision** decimal types. Out of scope: 128-bit
fixed-precision (covered by `decimal128_enhancement.md`).

| Library             | Limb base           | Mul algorithm tier               | Div algo           | Sqrt              |
| ------------------- | ------------------- | -------------------------------- | ------------------ | ----------------- |
| decimo BigDecimal   | 10^9 (UInt32 LE)    | School → Karatsuba → Toom-3      | B-Z (Knuth-D base) | reciprocal-Newton |
| Py `decimal`/libmpd | 10^9 / 10^19        | School → Karatsuba → **NTT**     | reciprocal-Newton  | reciprocal-Newton |
| Rust `bigdecimal`   | 10^9 (num-bigint)   | School → Karatsuba → Toom-3      | schoolbook (slow)  | Newton with div   |
| Java `BigDecimal`   | binary `BigInteger` | School → Kara → Toom → Schönhage | Burnikel-Ziegler   | Newton (binary)   |
| GMP `mpz_t` / MPFR  | 2^64                | School → Kara → Toom → **FFT**   | reciprocal-Newton  | reciprocal-Newton |
| JS `decimal.js`     | 10^7 (Number arr)   | School only                      | schoolbook         | Newton            |
| Go `math/big.Float` | 2^64 (binary)       | School → Karatsuba               | reciprocal-Newton  | Newton            |

**Coverage matrix.** decimo offers the broadest decimal API: `add`,
`subtract`, `multiply`, `divide`, `sqrt`, `cbrt`, `root(x,n)`, `exp`,
`ln`, `log10`, `log(x,b)`, `power`, `round`, `compare`, `from_string`,
`to_string`. The Rust crate lacks `exp`/`ln`/`root`/`round`. JS
`decimal.js` covers all but is single-language. Java covers all but
loses I/O speed to binary internal storage.

## 2. Change History — Done

Dated by report file under `benches/bigdecimal/reports/`. Append-only.

### 2.1 Correctness

| Date     | Item                                                                                  |
| -------- | ------------------------------------------------------------------------------------- |
| 20260222 | `to_string` rewritten to match CPython `Decimal.__str__` exactly (sci-notation rules) |
| 20260222 | `sqrt` rewritten with CPython exact integer algorithm — 0 warnings on 70 cases        |
| 20260223 | `root()` strips trailing fractional zeros for exact results (`cbrt(8) → "2"`)         |
| 20260223 | `round()` with `ROUND_UP` now returns 1 (at target scale) when all digits removed     |
| 20260224 | `exp` exact `2^M` division via `coef *= 5^M; scale += M` (no rounding error)          |

### 2.2 Performance utility

| Date     | Item                                                                                  |
| -------- | ------------------------------------------------------------------------------------- |
| 20260222 | `MathCache` struct: caches `ln(2)`, `ln(1.25)`, `ln(10)` with precision-upgrade logic |
| 20260222 | `true_divide_inexact_by_uint32()` — single-word division wraps `BigUInt.fdiv_uint32`  |
| 20260223 | BigDecimal `multiply_inplace`, `add_inplace`, `subtract_inplace`                      |
| 20260223 | `__iadd__` / `__isub__` / `__imul__` route through inplace versions                   |
| 20260224 | Toom-3 helpers: `_exact_divide_by_{2,3,6}_inplace` (carry-based, no BigUInt division) |

### 2.3 Performance — arithmetic & analytic ops

| Date     | Tag  | Item                                                                               |
| -------- | ---- | ---------------------------------------------------------------------------------- |
| 20260221 | T1   | Asymmetric divide truncation: `extra_words = ceil(P/9)+2 - diff_n_words`           |
| 20260223 | T2   | Balanced divide also truncates; quotient near constant time vs operand size        |
| 20260222 | T3a  | `MathCache` for `ln(2)`/`ln(1.25)` — log() shares 2 internal ln() calls            |
| 20260222 | T3b  | UInt32 division in Taylor series (was full BigDecimal divide per term)             |
| 20260222 | T3c  | `get_ln10()` in MathCache (reuses cached `ln(2)` & `ln(1.25)`)                     |
| 20260224 | T3d  | Aggressive halving range reduction for exp: $M \approx \sqrt{3.322p}$              |
| 20260222 | T4   | sqrt via reciprocal-Newton with precision doubling at BigDecimal level (no divide) |
| 20260222 | T7a  | `integer_root` via direct Newton (was `exp(ln(x)/n)`)                              |
| 20260223 | T8   | BigDecimal in-place ops applied across exp/ln/sin/cos/arctan Taylor loops          |
| 20260224 | T6   | Toom-3 multiplication, cutoff 128 words; +14–29% over Karatsuba for ≥256 words     |
| 20260516 | T-R2 | `round_to_precision_inplace` routed through fully in-place BigUInt path;           |
|          |      | 6 callsites converted + free function/method renamed; `round()` rewritten as       |
|          |      | copy+inplace; `BigUInt.remove_trailing_digits_with_rounding` de-duplicated to      |
|          |      | thin wrapper                                                                       |

### 2.4 Performance tracking — absolute decimo median ns/iter (ascending precision)

Best-of-5, `-D ASSERT=none`. Append-only. Where a precision is omitted
the operation only runs at p=100 in that snapshot.

| Date     | op   | p=100 | p=1000 | p=10000 | p=100000 | note                                       |
| -------- | ---- | ----: | -----: | ------: | -------: | ------------------------------------------ |
| 20260221 | div  |   ~7M |    ~6M |   ~480M |   444M\* | pre-T1 asymmetric (\*65536w/32768w)        |
| 20260221 | div  |   614 |   3.2k |     25k |     245k | post-T1 asymmetric (614 ns at 32768/65536) |
| 20260224 | sqrt |  8.6k |   166k |      7M |        — | post-T4 reciprocal-Newton                  |
| 20260224 | exp  |   24k |   1.7M |       — |        — | post-T3d aggressive halving                |
| 20260224 | ln   |  104k |    38M |       — |        — | post-T3a/b/c (far-from-1 still slow)       |
| 20260430 | add  |   276 |    280 |     290 |      269 | latest 60-case sweep                       |
| 20260430 | sub  |   211 |    203 |     220 |      210 | latest 50-case sweep                       |
| 20260430 | mul  |   140 |    140 |     140 |      130 | latest 50-case sweep                       |
| 20260430 | div  |   805 |   3.2k |     25k |     245k | latest 64-case sweep                       |
| 20260430 | cmp  |   9.4 |    8.7 |     9.5 |        — | independent of precision                   |

### 2.5 Performance tracking — decimo / python ratio (>1 = decimo slower)

| Date     | op     | p=100 | p=1000 | p=10000 | Comments |
| -------- | ------ | ----: | -----: | ------: | -------- |
| 20260224 | add    |  4.7× |   4.9× |    4.9× |          |
| 20260224 | sub    |  3.6× |   3.5× |    3.8× |          |
| 20260224 | mul    |  2.3× |   2.4× |    2.4× |          |
| 20260224 | div    |  5.4× |   5.8× |    5.0× |          |
| 20260224 | cmp    |  0.2× |      — |       — |          |
| 20260224 | sqrt   |  2.1× |   0.7× |    0.3× |          |
| 20260224 | exp    |  1.8× |   0.4× |       — |          |
| 20260224 | ln     |  4.6× |   9.2× |       — |          |
| 20260224 | root   |  0.3× |   0.0× |       — |          |
| 20260224 | frmstr |  1.2× |   1.2× |    1.2× |          |
| 20260224 | tostr  |  1.3× |   1.3× |    1.2× |          |
| 20260224 | round  |  1.9× |   2.1× |    2.2× |          |
| 20260430 | add    |  4.9× |   5.4× |    5.0× |          |
| 20260430 | sub    |  3.7× |   3.7× |    3.3× |          |
| 20260430 | mul    |  2.6× |   2.3× |    2.4× |          |
| 20260430 | div    |  6.5× |   5.3× |    5.1× |          |
| 20260430 | cmp    |  0.2× |      — |       — |          |
| 20260430 | sqrt   |  2.1× |   0.7× |    0.3× |          |
| 20260430 | exp    |  1.6× |   0.4× |       — |          |
| 20260430 | ln     |  4.3× |   8.9× |       — |          |
| 20260430 | root   |  0.2× |   0.0× |       — |          |
| 20260430 | frmstr |  1.4× |      — |       — |          |
| 20260430 | tostr  |  1.0× |      — |       — |          |
| 20260430 | round  |  2.2× |   2.2× |    2.3× |          |

Baseline sweep `bigdecimal_report_20260430_192858.md`.
**Note (2026-04-30):** the cross-language harness was simplified to
`decimo` vs `python` only. The previous Rust `bigdecimal` reference was
dropped — it lacked `exp`/`ln`/`root`/`round`, used naive long-division,
and its add/sub/mul timed kernels were initially measuring the wrong
path (PR #232). `from_string`/`to_string` numbers shifted vs the
20260224 baseline because precision rounding was removed from those
kernels (parse/render are precision-insensitive ops).

## 3. Hypothesis Ledger

| H#  | Hypothesis                                    | Outcome                                                       |
| --- | --------------------------------------------- | ------------------------------------------------------------- |
| 1   | Asymmetric divide pads quotient unnecessarily | DONE (T1) — 0.11→76× py at 65536w/32768w                      |
| 2   | Balanced divide also wastes work for          | DONE (T2) — quotient near-constant time (8–915× py)           |
|     | high-precision req                            |                                                               |
| 3a  | `ln(2)`/`ln(1.25)` recomputed per call        | DONE (T3a) — `MathCache`; 3×–4.5× speedup for repeated `ln()` |
| 3b  | Per-Taylor-term BigDecimal divide is wasteful | DONE (T3b) — UInt32 divide path; +20–130% near-1 ln           |
| 3c  | `log10()`/`log()` re-compute `ln(10)`         | DONE (T3c) — cached via `MathCache`                           |
| 3d  | exp Taylor series too long; weak halving      | DONE (T3d) — $M=\sqrt{3.322p}$; exp 0.4×→2.6× py at p=1000    |
| 3e  | Binary splitting for ln Taylor series         | GOAL met by T-3e (exact-reciprocal divide, NOT binary         |
|     |                                               | splitting); ln 3–21× p>=1000. Binary splitting → §5.3         |
| 3f  | `atanh` reformulation for ln (3× fewer terms) | DONE (T-L1) — hybrid Taylor/atanh in `ln_series_expansion`;   |
|     |                                               | near-1 already 0.9–1.8× py                                    |
| 3g  | AGM-based ln for very high precision          | OPEN — long-term, complex                                     |
| 4   | sqrt via Newton-with-division is slow         | DONE (T4) — reciprocal-Newton + precision doubling;           |
|     |                                               | 20× improvement                                               |
| 5   | NTT multiplication for n ≥ 1024 words         | OPEN — single biggest long-term gap vs libmpdec               |
| 6   | Toom-3 between Karatsuba and NTT              | DONE (T6) — +14–29% for ≥256w                                 |
| 7a  | `integer_root` via direct Newton              | DONE (T7a) — 0.14×→25× py at p=1000 for cbrt                  |
|     | (was exp(ln(x)/n))                            |                                                               |
| 7b  | Reciprocal-Newton for nth root (no divide)    | DEFERRED (T-7b) — break-even at current mul speed             |
|     |                                               | (div ~2.7× mul); root already 0.2× py                         |
| 8   | BigDecimal-level inplace ops in Taylor loops  | DONE (T8) — +15–27% exp/ln, +9% sqrt                          |
| 9   | deferred-carry schoolbook multiply            | DONE (T-9) — deferred-carry (product-scanning);               |
|     |                                               | 32w 2×, 48w 2.4×, 64w 2.9× faster                             |
| 10  | `debug_assert(..., "{}".format(...))`         | OPEN — sweep BigUInt + BigDecimal hot paths (Lesson #7)       |
|     | eager allocation                              |                                                               |
| 11  | Hot-path-first switch reorder in BigDecimal   | OPEN — same-scale & same-sign branch first (Lesson #12)       |
|     | `add`/`sub`                                   |                                                               |
| 12  | `@no_inline` raise helpers in                 | OPEN — sweep `from_string`, `from_uint32`, etc. (Lesson #10)  |
|     | BigDecimal/BigUInt                            |                                                               |
| 13  | `from_string` digit batching                  | OPEN — borrowed from decimal128 H#17 follow-up                |
|     | (UInt64 chunks of 9 or 19)                    |                                                               |
| 14  | `to_string` `InlineArray` right-aligned       | OPEN — borrowed from decimal128 §2.4                          |
|     | chunked emit                                  |                                                               |
| 15  | Single-pass rounding in BigDecimal            | OPEN — borrowed from decimal128 H#16                          |
|     | `multiply` / `divide`                         |                                                               |
| 16  | Short-divisor fast path in `divide`           | OPEN — `BigUInt.floor_divide_by_uint32` exists;               |
|     | (single-word loop)                            | lift to BigDecimal                                            |
| 17  | Add/sub `multiply_by_power_of_ten` allocates  | OPEN — root cause of 4.7× py on small-precision add           |
|     | oversized                                     |                                                               |
| 18  | Small-coefficient mul fast path               | OPEN — borrowed from decimal128 H#4 dispatch-overhead lesson  |
|     | (bypass Karatsuba dispatch)                   |                                                               |
| 19  | `precision` arg on `add`/`sub`/`multiply`     | DONE (PR #233) — see T-API3                                   |
| 20  | Private functions with `_`; Replace raises    | OPEN — improves runtime performance by avoiding               |
|     | with debug asserts                            | unnecessary checks                                            |
| 21  | More inplace variants for `BigUInt`           | OPEN — further reduces allocations and improves performance   |
|     | and `BigDecimal`                              |                                                               |
| 22  | Zero-copy scale alignment via word-offset     | DISPROVEN — see T-API2                                        |
|     | add/sub                                       |                                                               |
| 23  | Drop multiply pre-scaling; adjust scale       | OPEN — see T-API2.M                                           |
|     | on result                                     |                                                               |
| 24  | `round_to_precision` in-place audit           | DONE (T-R2) — code-quality cleanup; divide bench unchanged    |
|     |                                               | (saved allocs lost in noise vs total divide cost;             |
|     |                                               | will compound on rounding-dominated ops)                      |
| 25  | Data-pointer over list indexing across        | DONE (T-U1) — only the two-buffer divide kernel won (4-8%)    |
|     | BigUInt hot kernels                           | at ≥256w; single-pass O(n) loops within noise, reverted       |

## 4. Lessons Learnt (the reusable bits)

Items 1–6 are BigDecimal-specific (learned during the work tracked in
§2). Items 7–17 are transferred from `decimal128_enhancement.md §4`
because the lesson generalises to the variable-length case unchanged.

1. **Precision-matched bench is non-negotiable.** The 2026-02-22 audit
   found `exp` and `root` benches running Mojo at 28–36 digits while
   Python ran at 10000 — silently inflating Mojo's apparent speedup
   by ~3× and burying real regressions. Always pass `precision` from
   one TOML field through to both `getcontext().prec` and the Mojo
   call site.

2. **Precision doubling is the lever for Newton-style methods.** Old
   sqrt ran every iteration at full 5000 digits → 10× slower than
   necessary. New sqrt starts at 20 digits and doubles → total work
   ≈ 3× the final iteration. **20× win** with no algorithmic change.

3. **Reciprocal Newton beats divide-Newton when multiplication is
   fast.** Each iteration costs `2× mul` instead of `1× div`; with
   Karatsuba a divide is ~2–3× a multiply, so reciprocal Newton is
   a strict win above small operands. Drives T4 (sqrt), guides T7b.

4. **Aggressive range reduction cuts series-term count by `√p`.** For
   exp at p=1000 the natural Taylor needs ~2.5p terms; halving by
   $M=\sqrt{3.322p}$ cuts to ~M terms plus M squarings, total
   $2\sqrt{3.322p}$ multiplies. **2.6× py at p=1000.**

5. **Repeated-sqrt range reduction for ln REGRESSES** by 100×.
   `sqrt_reciprocal` per call costs more than the Taylor terms it
   saves. Use `atanh` reformulation (T3f) instead.

6. **Wasted quotient words dominate asymmetric division.** The T1 fix
   was 2 lines (`extra_words = ceil(P/9)+2 - diff_n_words`) but
   eliminated 99.8% of the work for skewed operand sizes. **Always
   truncate to needed precision before invoking the heavy algorithm.**

7. **`debug_assert` does NOT lazy-evaluate its message argument** under
   `-D ASSERT=none`. `String.format` allocates and runs inside the hot
   loop anyway. Use plain string literals only.

8. **`urem` lowers to `sub(a, mul(udiv, b))` and CSE-deduplicates with
   the explicit `// + %`.** Use the natural `// + %` form.

9. **Branches that test a non-trivial predicate to skip a moderately-
   priced fall-through are often anti-optimisations.** Always measure
   the dispatch cost separately from the body cost. Note for
   BigDecimal: `is_integer()` here costs a multi-word `coef % 10^scale`
   probe (much pricier than Decimal128's `(low & ((1<<scale)-1))`), so
   if the branch was a net loss on Decimal128 it is almost certainly
   one here too.

10. **For raises functions on the hot path, extract each `raise … .format(...)`
    into a `@no_inline` helper.** Lets `@always_inline` actually fire on
    the parent.

11. **Granlund-Möller needs ceiling division** for the magic constant.
    Floor failed 17/2000 at small `k`. (Less directly relevant for
    BigDecimal where divisors are variable, but applies if any inner
    primitive ever specialises a fixed divisor.)

12. **The count of branches before the fast arm matters more than the
    body of the fast arm.** Hot path first; rare cases routed to the
    cold tail of the same function.

13. **Helper-function decomposition costs ~1 ns over a well-ordered
    monolith.** Reserve helpers for genuinely shared code paths.

14. **`from_string`-style state-machine parsers benefit hugely from
    reordering the per-byte switch so the digit branch comes first.**

15. **For `to_string`, accumulate digits into a small fixed-size
    staging buffer (9- or 18-byte `InlineArray`) one chunk at a time,
    then write each chunk into the writer.** For variable-length
    BigDecimal the *whole* buffer cannot be `InlineArray` (coefficient
    can be 100000+ digits) — only the per-chunk staging is. The win is
    the same: avoid per-byte `writer.write` calls and avoid an
    intermediate per-digit `String` builder.

16. **For multi-pass rounding, compute the total drop count in one shot
    when both constraints are independent.** Re-round must use the
    **original** value, not the already-rounded one.

17. **In hot O(n²) loops over `List` buffers, hoist a raw data pointer
    once (`var p = some_list.unsafe_ptr()`) and index through `p`
    instead of through `some_list[i]`.** A `List` access reloads the
    `_data` field from the List struct on every element access (the
    compiler usually cannot prove `_data` is loop-invariant), whereas a
    hoisted pointer stays in a register, saving one memory load per
    iteration. Measured **~8% at 64-word operands** in
    `multiply_slices_deferred_carry` (20260616), and this is *not* a
    bounds-check effect — under `-D ASSERT=none` the `List.__getitem__`
    bounds check (`debug_assert[assert_mode="safe"]`) is already compiled
    out, and `List.unsafe_get`/`unsafe_set` measured identical to plain
    `[]` there. Safety preconditions: the buffer must not be resized
    while the pointer is live (only element-mutated) and indices must be
    provably in-bounds. The owner does **not** need a manual lifetime
    extension — `List.unsafe_ptr()` returns an origin-parameterized
    `UnsafePointer` tied to the List's origin, so Mojo's lifetime
    tracking keeps the List alive for as long as the pointer is used
    (verified 20260616). **The win scales with the number of `List._data`
    reloads removed per iteration.** A T-U1 sweep (20260618) confirmed this:
    hoisting helps in O(n²) inner loops (`multiply_slices_deferred_carry`,
    ~8%) and in single-pass loops that touch **two or more** buffers per
    element (`floor_divide_by_uint32` reads `x` and writes `result` →
    +4-8% at ≥256 words). It does **not** clear the ≥3% bar for
    single-buffer single-pass O(n) loops (`multiply_by_uint32_inplace`,
    `floor_divide_by_uint32_inplace`, `multiply_by_power_of_ten_inplace`):
    those are arithmetic-bound (the base-10⁹ `% / //` dominates), the one
    saved address reload is hidden, and the variants even regressed small
    operands — so they were reverted.

## 5. Open Items / Future Improvements

### 5.1 Worst-case ratios still > 1.5× python (latest sweep 2026-05-01, post-T-API1)

The T-API1 sweep (`bigdecimal_report_20260501_115440.md`) shows the
add/sub/mul kernels are now within ~2–3× python on every case;
long-decimal add/sub worst cases dropped from 10–15× py down to
1.4–4× py.

| Op          | Worst case (p=100)                     | decimo | python | dm/py | Likely cause                                    |
| ----------- | -------------------------------------- | -----: | -----: | ----: | ----------------------------------------------- |
| add         | Add of 1000-digit decimals             |    660 |    140 |  4.7× | residual scale-align overhead post-truncation   |
| add         | Fib-like large dec add (1100 d)        |    662 |    147 |  4.5× | same                                            |
| add         | Add of 2000-digit dec with carries     |    644 |    215 |  3.0× | exact path retained for cancellation guard      |
| sub         | (similar long-decimal cases)           |   ~650 |   ~200 |   ~3× | same                                            |
| mul         | High precision multiply small operands |    105 |     51 |  2.0× | dispatch overhead, no small-coef fast path      |
| div         | Repeating-decimal div                  |    805 |  149.6 |  5.4× | full Burnikel-Ziegler even for short divisor    |
| div (p=10k) | Long decimal divide                    |    25k |   5.0k |  5.0× | same                                            |
| sqrt(p=100) | √(small irrational)                    |   8.6k |   4.1k |  2.1× | reciprocal-Newton overhead at tiny size         |
| ln(p=100)   | far-from-1 (`ln(10)`, `ln(0.1)`)       |   104k |  22.5k |  4.6× | recompute from scratch (no global ln(10) cache) |
| ln(p=1000)  | far-from-1                             |    38M |   4.2M |  9.2× | same; gap widens with precision                 |
| from_string | (many long-decimal cases)              |    170 |    140 |  1.2× | already close; finish via digit batching        |
| to_string   | (many cases)                           |    200 |    160 |  1.3× | finish via right-aligned `InlineArray`          |
| round       | Various                                |    200 |     90 |  2.2× | likely `debug_assert .format`                   |

**Where decimo already wins.** `comparison` is 5–10× *faster* than
python (0.1–0.2×). `sqrt` at p≥1000 is 0.3–0.7× py. `exp` at p=1000
is 0.4× py. `root` at any precision is 0.0–0.3× py. These ops need no
further work.

### 5.2 New optimisation tasks (priority ordered)

Each task below is justified by the bench data in §5.1 and one or more
lessons in §4. All borrow patterns proven on the Decimal128 hot path.

P0 — Structural API change (foundation for most P1 wins)

- **T-API1 — DONE.** Added `precision: Int = 0` to the free
  functions `add`, `subtract`, `multiply`. When `precision > 0` the
  function computes the **exact** result and rounds HALF_EVEN. The
  Python-facing surface follows `decimal.Decimal`:
  `__add__`/`__sub__`/`__mul__` (and the reflected variants) round to
  `PRECISION` (28) significant digits, while the explicit
  `BigDecimal.add` / `subtract` / `multiply` methods default to
  `precision=0` (exact) so callers can opt out of rounding without
  reaching for the free function. The upfront-operand-truncation
  strategy that originally motivated the API is tracked separately
  as T-API3.

- **T-API2 - DISPROVEN.** Zero-copy scale alignment for add/sub/mul.  
  Disproven as the performance gain is limited.

- **T-API3 — DISPROVEN.** `add`/`sub`/`multiply` with `precision > 0`:
  correct pre-truncation  
  Disproven as it is trivial.

P1 — Add/Sub small-precision target (currently 4.7× / 3.6× py → target ≤2×)

- **T-A1: `debug_assert .format` sweep. DONE (20260606).** Audited
  `BigDecimal.add`, `subtract`, `multiply`, `divide`, `round`, and the
  BigUInt primitives they call. No `.format()`-style `debug_assert`
  calls remain in any hot path; all 12 surviving `debug_assert` sites
  in `src/` already use either a plain string literal or the variadic
  `debug_assert(cond, "msg ", value)` pattern (e.g.
  `biguint/arithmetics.mojo:1630`).

- **T-A2: `multiply_by_power_of_ten` allocation audit (H#17). SUBSTANTIALLY DONE (20260606).**
  The inplace variant
  [`multiply_by_power_of_ten_inplace`](../../src/decimo/biguint/arithmetics.mojo)
  exists, uses `words.resize(unsafe_uninit_length=...)` (O(1)
  capacity + memset, not O(n) memcpy), and has a multiple-of-9 fast
  path that delegates to `multiply_by_power_of_billion_inplace`. The
  hot mutating callers (`add_inplace`, `subtract_inplace` in
  `bigdecimal/arithmetics.mojo`, plus the new `bigdecimal.mojo:2562`
  site) already use the inplace form. Residual: the public
  `add`/`subtract` at `bigdecimal/arithmetics.mojo:94-95,176-177`
  still call the allocating variant on both operands (one operand
  always has `scale_factor == 0`, where it degenerates to `x.copy()`).
  Switching to inplace here would save only the redundant copy, not
  the alignment allocation — a sub-1% micro-optimisation; the bulk
  30–50% win projected by this task was already captured by the
  inplace variant.

- **T-A3: Hot-path-first switch reorder in `add`/`subtract` (H#11).**
  **DONE (20260610).** `bigdecimal/arithmetics.mojo`: `add` and
  `subtract` now check `x1.scale == x2.scale` first (same-sign for add,
  both sign-branches for subtract). Zero-operand handling and
  `multiply_by_power_of_ten` alignment moved to the cold tail.
  Measured on Apple M4 Pro (`bench add subtract --precisions 100 1000`):
  - `subtract @ p1000`: 141 → 89 ns (−37%), dm/py 2.5x → 1.5x
  - `subtract @ p100`:  124 → 95 ns (−24%), dm/py 2.1x → 1.7x
  - `add @ p1000`:      140 → 122 ns (−13%), dm/py 2.3x → 2.0x
  - `add @ p100`:       125 → 126 ns (noise), dm/py 2.2x → 2.1x
  All 220 bench cases still match Python `decimal.Decimal` bit-for-bit.

- **T-A4: `@no_inline` raise helpers (H#12).** **DONE (20260610).**
  Targeted minimal-but-broad change in `errors.mojo`: split
  `_shorten_path` into an `@always_inline` shim plus a `@no_inline`
  `_shorten_path_implementation` that holds the multi-`rfind` + string-slicing
  body. Because `DecimoError.__init__` is `@always_inline` and runs at
  every `raise` site library-wide, this shrinks the inlined raise body
  everywhere without changing call-site code or stack-trace semantics.
  No measurable hot-path delta on the non-raising add/subtract bench
  (expected — hot paths never raise); the win is icache pressure on
  inline call sites with raise edges. Aggressive per-callsite raise
  extraction was deferred because it would shift `call_location()` from
  the caller to the helper, degrading tracebacks.

- **T-A5: `is_zero` / `is_integer` branch removal (H#3.1).**
  **DONE — audited, no removal (20260611).** `add`/`subtract` contain no
  `is_integer()` probes (grep-confirmed), so the expensive multi-word
  `coef % 10^scale` concern does not apply. The remaining `is_zero()`
  early-outs (post-T-A3 these live only in the differing-scale cold
  tail) were benchmarked: removing them regressed the zero-operand
  cases ~3x — "a + 0" 46 → 132 ns (0.8x → 2.8x py), "a - 0" 44 → 138 ns
  (0.7x → 2.4x py). `is_zero()` is a cheap single-word probe gating a
  much cheaper path, so per Lesson #9 ("remove unless benchmarked
  positive") they are **kept**, now with a comment recording the audit.

P2 — Multiply small-precision (2.3× py → target ≤1.5×)

- **T-M1: Small-coefficient fast path (H#18).** **DISPROVEN — reverted
  (20260611).** Borrowed from Decimal128 H#4, but the lesson does **not**
  transfer to BigUInt's base-10⁹ limb representation. A `UInt64 × UInt64
  → UInt128` product must be converted back into base-10⁹ words, which
  costs up to four 128-bit `divmod` by 10⁹. A focused micro-bench on
  2-word × 2-word operands (M4 Pro) measured the UInt128 path at
  **130 ns/op vs 45.9 ns/op for the existing schoolbook path** — ~3x
  slower. (Decimal128 stores binary UInt128 natively, so it pays no
  conversion; BigUInt does.) The single-word UInt32 dispatch already
  covers 1-word operands optimally, and schoolbook is already optimal
  for 2-word. This is a Lesson #9 anti-optimisation; no headroom here.

- **T-M2: Single-pass rounding in `multiply` (H#15, Lesson #16).**
  **DONE — already single-pass; cleaned up (20260611).** BigDecimal has
  no fixed-width container, so the "fit-rounding + scale-rounding" double
  pass that motivated the Decimal128 fix does not exist here: the exact
  product is computed once and rounded once to `precision`. The free
  `multiply` was tidied to drop the redundant `multiply(x1, x2, 0)`
  recursion and the duplicate zero probe (BigUInt.multiply already
  returns a single-word zero), computing the product inline and rounding
  once. Multiply median improved 90 → 80 ns (1.7x → 1.5x py @ p100,
  1.8x → 1.7x @ p1000); all 100 multiply cases still match Python.

- **T-9: Deferred-carry (product-scanning) schoolbook multiply (H#9).**
  **DONE (20260615).** The scalar `multiply_slices_schoolbook` normalized a
  base-10^9 carry (`% BASE` + `// BASE`) on *every* inner step — `n_x ·
  n_y` divisions. Added `multiply_slices_deferred_carry`, which
  accumulates each column sum in a `UInt64` buffer and normalizes only
  every `SAFE_ROWS = 15` rows (overflow-safe: 15·(10^9)^2 < 2^64),
  cutting the division count ~8×. (This is the column-accumulation /
  product-scanning idea historically called "Comba multiplication" —
  P. G. Comba, IBM Systems Journal 29(4), 1990; the docstring carries
  the full citation.) `multiply_slices_schoolbook` now dispatches to it when
  `n_x · n_y >= CUTOFF_DEFERRED_CARRY_PRODUCT` (200 — a *product*, not a
  word count, so it is reached for operands ≥ ~15 words within the
  ≤64-word schoolbook range and as the Karatsuba/Toom-3 base; benchmarked
  crossover ~144).
  This speeds up every schoolbook base case (direct multiply ≤64 words
  *and* Karatsuba/Toom-3 recursion bases). Measured (M4 Pro, integrated):
  32-word 1175 → 595 ns (~2×), 48-word 2874 → 1185 (~2.4×), 64-word
  5544 → 1918 (~2.9×); small operands (≤~11 words) stay on the scalar
  path with no regression. Correctness: 196/196 standalone cases (incl.
  64-word all-nines overflow stress) plus the full biguint / bigint /
  bigdecimal / bigint10 suites (0 failures) and 100% cross-language
  multiply match. (Pure SIMD vectorisation of the partial-product loop
  on top of this is a possible future follow-up; the deferred-carry
  restructuring alone already captures the targeted 1.5–2×, exceeding it
  at larger sizes.) **Downstream impact (anything that multiplies large
  coefficients internally).** The standard cross-language report
  originally showed no change because its multiply cases used
  small-coefficient operands (the `precision` knob rounds the *result*,
  not the operand size). Large-coefficient cases were therefore added to
  `cases/multiply.toml` (150/450/900-digit operands) and
  `cases/divide.toml` (balanced ~67w/34w, ~134w/67w) so the existing
  report exercises the deferred-carry path. With it, the 450-digit
  multiply is 0.8× py and the 900-digit multiply 0.6× py (both now
  *faster* than Python, vs ~2.3–2.5× *slower* before). Measured
  before/after on large operands: multiply 450-digit 2.5×, 900-digit
  2.3×, 4500-digit 2.1×;
  divide (Burnikel-Ziegler) 1.3–1.6×; sqrt p5000 1.67×; exp p1000 2.4×;
  ln p5000 1.9×; cbrt p5000 1.65×. Small operands (≤~90 digits)
  unchanged.
  **Cutoff re-tuning follow-up (20260616).** Since deferred-carry only
  speeds up the schoolbook *base* (which Karatsuba and Toom-3 both
  recurse into), it does not shift the Karatsuba/Toom-3 boundary, and it
  moved the schoolbook→Karatsuba crossover only marginally (~64 → ~72
  words), so `CUTOFF_KARATSUBA = 64` was left as-is. Direct-comparison
  benchmarks did expose a *pre-existing* mistuning, though: Toom-3 (5
  evaluation points + interpolation) only beats Karatsuba at ≥ ~256–384
  words — it was ~9% *slower* than Karatsuba at 160w and equal at 256w —
  so the old `CUTOFF_TOOM3 = 128` routed the 128–256 band to Toom-3
  prematurely. Raised `CUTOFF_TOOM3` to **256** (~4× `CUTOFF_KARATSUBA`,
  the usual ratio): dispatcher before/after shows multiply −7.6% @150w,
  −4.2% @192w, −2% @224w, neutral at 256w and ≥384w; biguint/bigint
  suites still pass (0 failures).

- **T-U1: Cross-kernel data-pointer (H#25).**
  A/B-benched the hoisted-`unsafe_ptr` vs `List[i]` indexing form of every
  candidate single-word BigUInt kernel, both as isolated loops
  (`local/bench_tu1.mojo`) and in-situ on the real struct-field functions
  (`local/bench_tu1_insitu.mojo`), best-of-7 at 4-1024 words under
  `-O3 -g0 -D ASSERT=none`.
  **Kept:** `floor_divide_by_uint32` — its inner loop reads `x.words[i]` *and*
  writes `result.words[i]` every iteration, so the indexed form reloads **two**
  `List._data` fields per element; hoisting both pointers is a stable **+4-8%**
  at >=256 words across 3 runs with no small-input regression (the small-n path
  is allocation-bound, so it stays neutral). This is the same mechanism as
  `multiply_slices_deferred_carry` (Lesson #17), amplified by two buffers.
  **Reverted (no stable win / small-input regressions):**
  `multiply_by_uint32_inplace` (mixed; -3..-8% at 16-64w),
  `floor_divide_by_uint32_inplace` (single buffer; +3% only at large n,
  -5..-10% at 4-8w),
  `multiply_by_power_of_ten_inplace` (clear -5..-11% at 8-16w, the common
  BigDecimal scale-align size). These are all **single-buffer single-pass**
  O(n) loops that are arithmetic-bound (the base-10^9 `% / //` dominates), so
  removing one address reload per element does not clear the >=3% bar.
  **Takeaway:** pointer hoisting pays off when an iteration touches *multiple*
  List buffers (>=2 `_data` reloads/element) or runs an O(n^2) inner loop;
  for single-buffer O(n) passes the div/mod hides the saved load. Correctness:
  BigUInt (incl. random truncate-divide vs Python), BigInt, and BigDecimal
  arithmetic suites all pass; package builds clean.

P3 — Divide all precisions (5× py → target ≤2×)

- **T-D1: Short-divisor fast path (H#16).** **DONE — already covered by
  the BigUInt dispatch (20260611).** `BigUInt.floor_divide` (invoked by
  `//` inside `true_divide_general`) already routes single-word divisors
  to `floor_divide_by_uint32`, two-word to `_by_uint64`, and ≤4-word to
  `_by_uint128`; Burnikel-Ziegler is entered only for divisors > 4 words
  (> 36 digits). So the short-divisor primitive (the actual algorithmic
  win) is active end-to-end; the §5.1 "full Burnikel-Ziegler even for
  short divisor" premise is outdated. A dedicated **BigDecimal**-level
  branch was prototyped (digit-granular buffer + direct
  `floor_divide_by_uint32` + matching exact/HALF_EVEN handling) and
  **DISPROVEN — reverted.** A focused micro-bench (M4 Pro, 2M iters) was
  mixed and net-negative on the common case: 100/4 @p50 dedicated 317 vs
  general 358 ns (+41), 355/113 @p50 +13, but **1/7 @p100 dedicated 376
  vs general 303 ns (−73)** and noise elsewhere. Root cause: the
  digit-granular `multiply_by_power_of_ten(118)` buffer does a partial-
  word multiply + word insertion, costing more than the general path's
  word-granular `multiply_by_power_of_billion` (a whole-word zero
  prepend) — buffer construction outweighs the few saved quotient
  digits, and high-precision non-terminating quotients (the typical
  "repeating decimal" divide) regress. No BigDecimal-level headroom.

- **T-D2: Trailing-zero detection allocation.** **DONE (20260611).**
  The exact-division branch of `true_divide_general` stripped trailing
  zeros with the allocating `floor_divide_by_power_of_ten` (the long-
  standing `# TODO: Make a in-place version of this`). Swapped to the
  existing `floor_divide_by_power_of_ten_inplace`, eliminating one
  BigUInt allocation on every terminating divide. A/B micro-bench (M4
  Pro, 3M iters): 100/4 @p50 388 → 320 ns (−17.5%), 9/1 388 → 303
  (−21%), 123456/1000 305 → 254 (−17%), 1/8 346 → 292 (−16%); divide
  still 100% match vs Python. (The truncated-path strip in
  `_true_divide_general_truncated` keeps its copy — it needs the
  unmodified `result` for the multiply-back exactness verification.)

- **T-D3: Reciprocal-Newton divide (legacy Task 2).** **DEFERRED —
  not beneficial before NTT; measured (20260615).** Reciprocal-Newton
  trades one divide for several multiplies, so it only wins when
  multiplication is much cheaper than division. A micro-bench of the
  current primitives (M4 Pro, non-structured balanced operands) confirms
  `floor_divide` (Burnikel-Ziegler) costs **~2.1–3.1× a same-size
  multiply** (64w 2.2×, 128w 2.7×, 256w 3.1×, 512w 2.6×, 1024w 2.5×) —
  exactly the Karatsuba regime of Lesson #3. Cost model for a
  reciprocal-Newton divide at this multiply speed: precision-doubled
  reciprocal ≈ 3× a full multiply, plus `a·r` (1×) plus an exactness
  correction `a − q·b` (1×) ≈ **~5× multiply**, i.e. ~1.7–2× *slower*
  than today's B-Z divide, before accounting for the extra floor/
  remainder-correction complexity. The crossover requires NTT
  (O(n log n) multiply, T-5) to make multiplies cheap enough; until then
  this XL rewrite of a core op would be a regression. Correctly gated on
  T-5; left deferred.

P4 — sqrt at p=100 (2.1× py → target ≤1.0×)

- **T-S1: Small-coefficient short-circuit before `fast_isqrt`.**
  **INVALID — already handled, and the premise is false (20260611).**
  `sqrt_exact` already short-circuits the reciprocal-Newton dance:
  `if len(c.words) <= 20: n = biguint_exponential.sqrt(c)` (direct
  integer Newton) else `fast_isqrt`. Two problems with the task as
  written: (1) at p=100 the coefficient is rescaled so `isqrt(c)` has
  `prec` (101) digits, making `c` ~202 digits (~23 words) — it never
  fits UInt128, so a "UInt128 isqrt" cannot apply. (2) The claim that
  the float64 setup + precision doubling is "wasted" at this size is
  empirically false: raising the direct-Newton threshold to 30 words so
  p=100 takes the direct path **regressed** sqrt@p100 from 8,370 →
  15,125 ns (1.8× → 3.8× py). `fast_isqrt` is the faster choice at ~23
  words; the existing threshold of 20 is well-tuned. sqrt@p1000 is
  already 0.7× py.

P5 — ln far-from-1 (4.6×–9.2× py → target ≤2×)

- **T-L1: atanh reformulation (T3f / H#3f).** **DONE — already
  implemented (20260611).** `ln_series_expansion` is a hybrid: it uses
  `2·atanh(u)` with `u = z/(2+z) = (x-1)/(x+1)` (exactly the T-L1 form,
  rate u² ≤ 1/9 vs Taylor's |z| ≤ 1/2 → ~3× fewer terms) for `z` with
  many significant digits, and falls back to direct `ln(1+z)` Taylor
  for small-coefficient `z`. The benched near-1 cases (T-L1's target)
  are already at parity: ln(0.99) 0.9× py, ln(1.01) 1.2×, ln(0.9) 1.0×,
  ln(1.1) 1.8×. The `z_digits`-based threshold is well-tuned: an
  experiment forcing atanh universally **improved** p100 near-1 ~13%
  but **regressed p1000 near-1 by 5–6×** (ln(0.99) 626k → 4.10M ns),
  because at high precision Taylor's O(n·z_digits) small-coefficient
  multiply beats atanh's O(n²) full multiply despite ~2× more terms.
  The hybrid correctly prioritises the high-precision Taylor path, so
  the threshold was left at 10. The residual far-from-1 slowness
  (ln(10)/ln(100)/ln(0.001) ~400× py) is **T-L2** — fresh
  `ln(2)`/`ln(1.25)` recomputation per call, blocked on process-wide
  cache state, not addressable by T-L1.

- **T-L2: Process-wide `ln(10)` cache (workaround for missing global
  vars).** **DONE for the implementable part; remainder blocked on Mojo
  (20260615).** The `MathCache` struct already caches `ln(2)`,
  `ln(1.25)` **and `ln(10)`** with automatic precision-upgrade logic, is
  accepted by `ln(x, precision, mut cache)`, `log`, and `log10`, and
  carries a copy-pasteable usage recipe in its own docstring (construct
  one `MathCache`, pass it across calls). So the user-facing recipe and
  the cache-passing API both exist today. The only outstanding piece —
  an *automatic* process-wide cache that callers get for free without
  threading a `MathCache` through — requires module-level mutable state,
  which Mojo does not yet provide; it cannot be implemented in library
  code. Nothing actionable until the language gains global mutable
  state.

- **T-3e: Faster ln constant series (H#3e). DONE (20260618).** The
  cached constants `ln(2)` and `ln(1.25)` drive every far-from-1 `ln`
  (range reduction uses `ln(x) = ln(m) + a·ln(2) + b·ln(1.25)`).
  `compute_ln2` evaluated `ln(2) = 2·Σ (1/3)^(2k+1)/(2k+1)` with a *full*
  per-term multiply `term *= x²` where `x = 1/3` was built as a
  full-precision `0.333…` — i.e. an O(M(n)) Karatsuba multiply every one
  of the ~p iterations, giving super-quadratic O(p·M(p)) scaling
  (measured p=100→67µs, p=500→2.5ms, p=1000→16.9ms, p=2000→147ms).
  **Key insight:** `x = 1/3` is an *exact reciprocal*, so `x² = 1/9`
  exactly and `term *= x²` is just a divide by 9 — an O(n) single-word
  divide. Folding the `1/9` and the `1/(2k+1)` factors into one divide
  by `9·(k+2)` (and applying `×k` at the coefficient level) makes each
  iteration O(n), so the whole series is O(p·n) = O(p²/9), and it is also
  *more* accurate (exact `1/9` vs a truncated `0.111…` multiplier).
  Measured `compute_ln2` (M4 Pro, best-of-5): p=100 67→34µs (2.0×),
  p=200 253→97µs (2.6×), p=500 2.52ms→445µs (5.7×), p=1000
  16.9ms→1.81ms (9.3×), p=2000 147ms→6.9ms (**21×**). The same trick
  applies to `ln(1.25) = 2·atanh(1/9)` (since `(1+1/9)/(1−1/9) = 1.25`):
  `compute_ln1d25` was rewritten from the generic
  `ln_series_expansion(0.25)` Taylor path to a dedicated atanh(1/9)
  loop with `x² = 1/81` → divide by `81·(k+2)`. The atanh form also needs
  ~3× fewer terms than the `z = 0.25` Taylor series. Measured: p=100
  73→17µs (4.3×), p=200 187→51µs (3.7×), p=500 736→230µs (3.2×), p=1000
  2.75ms→868µs (3.2×), p=2000 10.3ms→3.4ms (3.0×). Correctness: both
  constants verified prefix-correct vs reference, and the full
  BigDecimal suite (arithmetics, exponential, exponential_toml, methods,
  rounding, trigonometric — which exercise `ln`/`log`/`log10` vs Python)
  passes with 0 failures. **This is not the textbook "binary splitting"**
  (which would target a generic rational hypergeometric series via a
  product tree of big integers, with a better O(M(p)·log p) asymptotic);
  the exact-reciprocal divide captures the bulk of the win here for far
  less code and risk, because both constant arguments happen to be unit
  fractions (`1/3`, `1/9`). Full binary splitting remains a future
  option if the constants ever dominate at very high precision.

- **T-L3: AGM ln (T3g / H#3g). DEFERRED — gated on NTT; assessed during
  the P4 sweep (20260618).** AGM-based `ln` converges quadratically
  (~log₂p iterations) but each iteration costs a full-precision multiply
  **plus a sqrt** (itself reciprocal-Newton = several multiplies), so the
  per-iteration constant is heavy. By the same cost-model logic that
  deferred T-D3 (reciprocal-Newton divide), AGM only overtakes the
  current series-based `ln` once multiplication is much cheaper than it
  is under Karatsuba/Toom-3 — i.e. after NTT (T-5). Until then it would
  regress the practical precisions. Correctly gated on T-5; left
  deferred. (The far-from-1 `ln` cost it targeted is in any case now
  largely addressed by T-3e, which removed the dominant constant-series
  cost.)

- **T-5: NTT multiplication. Assessed during the P4 sweep — valid but
  out of scope for an incremental change (20260618).** NTT is the single
  biggest long-term item and the enabler for T-D3 / T-L3 / T-7b. It is
  beneficial only for very large operands (≳1024 words ≈ 9000+ digits),
  i.e. the p≥10000 tail. Implementing a correct base-10⁹ NTT (prime
  selection, forward/inverse transforms, CRT recombination, carry
  handling) is a multi-session XL effort with substantial correctness
  risk and is not a safe single-pass edit; it remains tracked in §5.3 as
  dedicated future work rather than something to land inline.

P6 — `from_string` / `to_string` (1.2–1.3× py → target ≤1.0×)

- **T-IO1: Digit batching in `from_string` (H#13).** **DONE — batching
  already present; slice removed (20260611).** The projected 30–50% win
  assumed a per-digit `BigUInt`-mul-by-10 loop, but both
  `BigDecimal.from_string` and `BigUInt.from_string` already accumulate
  9 digits into a `UInt32` word directly (no BigUInt arithmetic), and
  `parse_numeric_string` is already a two-pass SIMD parser — so the big
  win was unavailable. The remaining inefficiency was the per-word
  `coef[start:end]` slice (a sub-`List` copy per 9-digit chunk),
  replaced with index iteration `for i in range(start, end)`. A/B
  micro-bench (M4 Pro, 3M iters): 90-digit int 230 → 222 ns, 90-digit
  frac 235 → 220 ns, short 141 → 138 ns; cross-language from_string
  150 → 142 ns (1.4× → 1.2× py), 100% match. Applied to both
  `from_string` sites.

- **T-IO2: Chunked `to_string` via small staging InlineArray (H#14).**
  **DONE (20260611).** `BigUInt.to_string` built the digit string with a
  per-word `String(UInt32)` + `rjust` + repeated `+=`, which dominated
  long-number rendering. Rewrote the long-number branch to precompute
  the exact output length `(n_words - 1) * 9 + msb_digits`, allocate a
  `List[UInt8](unsafe_uninit_length=...)` of that exact size, and write
  the digits straight into it through the pointer (no per-byte `append`,
  no reallocation, no over-allocation), then move it into the result via
  `String(unsafe_from_utf8=buf^)`. Kept as a **hybrid**: a 5-word
  crossover (`_BUFFER_PATH_MIN_WORDS`) retains the naive loop for short
  numbers, where the buffer's fixed `List`+`String` cost otherwise
  regressed them ~3x (a buffer-only version pushed "Tiny integer" 24 →
  64 ns — unavoidable even with direct pointer writes). Cross-language
  bench (M4 Pro): 50-digit 274 → 158 ns, 100-digit fraction 492 → 180
  (2.5× → 0.8× py), 200-digit 746 → 226 (2.9× → 0.8× py); short cases
  unchanged; 100% match plus a spot-check on internal-zero-word /
  trailing-zero / boundary inputs. The exact-size direct-write buffer
  beat an earlier `append`-based staging variant by a further ~28%
  on the 200-digit case (312 → 226 ns). Two follow-up ideas
  were tested: (a) special-casing a single word to a direct `String(word)`
  (plus a `String(capacity=9*n_words)` reserve for 2–4 words) improved
  the most common case ~20% (1-word 16.8 → 12.6 ns) and is **kept**;
  (b) replacing the buffer path's `//10` loop with per-word
  `String(UInt32)` + `memcpy` was **disproven** — the per-word
  allocation/call overhead made it ~2x slower at 23 words (167 → 361 ns),
  so the tight `//10` loop stands.

P7 — `round` (2× py → target ≤1.0×)

- **T-R1: `debug_assert .format` sweep specific to rounding modes.**
  **INVALID — no such asserts; dispatch swap perf-neutral (20260615).**
  The premise (one `.format` `debug_assert` per mode branch in the round
  dispatcher) does not match the code: neither `bigdecimal/rounding.mojo`
  `round` / `round_to_precision_inplace` nor
  `BigUInt.remove_trailing_digits_with_rounding_inplace` contains any
  `.format` (the only `.format` raises live in `decimal128/` and
  `str.mojo`), and the mode dispatch raises only on the cold
  unknown-mode fallback with plain concatenation. As a speculative
  micro-opt the dispatch's `== RoundingMode.down()` (`def`-factory)
  comparisons were swapped for the comptime `RoundingMode.ROUND_*`
  aliases; an A/B micro-bench (M4 Pro, 3M iters/mode) showed **no
  measurable difference** (~96–106 ns either way — the optimiser already
  folds the trivial factories, and the dispatch is dwarfed by the
  `copy()` + `number_of_digits()` + digit ops). Reverted to keep the
  diff minimal. `round` is 2.1× py @p100 driven by the per-call copy and
  digit scans, not the mode dispatch.

- **T-R2: `round_to_precision_inplace` variant.** DONE (20260516).
  The free function `round_to_precision` and the
  `BigDecimal.round_to_precision` method were renamed to
  `..._inplace` to make their mutating semantics explicit. The
  underlying `BigUInt.remove_trailing_digits_with_rounding_inplace`
  already existed and is genuinely allocation-free; the public
  `round()` was rewritten as `copy + inplace`. Six callsites in
  `arithmetics.mojo` / `exponential.mojo` were converted from
  out-of-place to in-place (saving one `BigUInt` allocation + buffer
  copy each). The out-of-place
  `BigUInt.remove_trailing_digits_with_rounding` was de-duplicated
  into a thin `copy + inplace` wrapper (~110 lines removed).
  Additionally, a `ndigits_before_removal: Int = -1` parameter was
  added to the inplace path so callers that already computed
  `number_of_digits()` (the public `round()`,
  `round_to_precision_inplace`, all 3 divide callsites, and the 1
  exp callsite) can skip the redundant inner `number_of_digits()`
  pass. As part of the audit the inplace function's primary
  parameter was also renamed from `ndigits` to `ndigits_to_remove`
  for self-documenting clarity (the public Python-compatible
  `round(ndigits=...)` API is unchanged).
  **Measured impact on divide bench (p=100/1000/10000):** ~0% in
  every run — the per-call alloc and `number_of_digits()` savings
  are dominated by the cost of the divide itself and stay inside
  run-to-run noise (±1%). The cleanup is kept for code quality
  (~110 LOC removed, mutating semantics now visible in the name)
  and because the saving will compound on future
  rounding-dominated fast paths (e.g. small-coefficient `add` /
  `subtract` / `multiply` with `precision > 0`).

### 5.3 Long-term tasks not on the active roadmap

| #   | Task                                                            | Effort |
| --- | --------------------------------------------------------------- | ------ |
| 5   | NTT multiplication (≥1024 words). Closes the gap with libmpdec  | XL     |
| 9   | SIMD-optimised schoolbook mul kernel                            | M      |
| 3e  | Full binary splitting for ln (generic rational series).         |        |
|     | Bulk already captured by T-3e exact-reciprocal divide.          | L      |
| 3g  | AGM-based ln for p ≥ 1000                                       | XL     |
| 7b  | Reciprocal-Newton for nth root                                  | M      |
| 7c  | Rational $x^{a/b}$ decomposition                                | S      |
| 11  | Make `BigUInt.remove_trailing_digits_with_rounding` private and |        |
|     | replace its runtime `raise` with a debug assert                 |        |
|     | (saves one `raises` propagation across all callers).            | S      |

## 6. Result-Equivalence vs Python

The 2026-04-30 sweep flags zero `match py` failures across all numeric
ops. The only acknowledged differences:

| Op   | Source                      | Notes                                            |
| ---- | --------------------------- | ------------------------------------------------ |
| root | Python `da ** (1/n)` oracle | Python rounds `1/n` to working precision         |
|      |                             | before exponentiation; 1–3 ulp differences are   |
|      |                             | expected and **not bugs**. Negative-base         |
|      |                             | nth roots additionally raise `InvalidOperation`. |

decimo follows IEEE 754-2008 §3.3 preferred-exponent rules for the
trailing-zero shape of multiply/divide results, matching Python
`decimal` and .NET. See `decimal128_enhancement.md §6` for the same
issue at fixed precision.

## 7. Architectural Reference

### 7.1 Why base-10^9, not 2^32

`libmpdec` itself uses base-10^9 (32-bit) or base-10^19 (64-bit) and
implements NTT directly on decimal limbs. The strongest evidence that
**staying with base-10^9 is correct** for a decimal library:

- I/O is `O(n)` trivial — no expensive base conversion at every
  `to_string`. A 34× advantage on `to_string` at 10000 digits over a
  binary-internal design (Java `BigDecimal`) is real and matters for
  financial / engineering users.
- Scale arithmetic is exact word-insert / word-remove. No multiplication
  by powers of 10 needed for shifting.
- Truncating to `p` significant digits = keeping `⌈p/9⌉` words.
- The NTT $O(n \log n)$ advantage works in any base. Base-10^9 NTT
  primes can be chosen so the transform operates on `[0, 10^9)`.

The performance gap vs `libmpdec` is **not** the base choice; it is the
algorithm tier for large operands (NTT, reciprocal-Newton division,
binary splitting). All implementable in base-10^9.

### 7.2 Algorithm tier comparison

| Feature            | decimo BigDecimal          | Python `libmpdec`              | Status        |
| ------------------ | -------------------------- | ------------------------------ | ------------- |
| Base               | 10^9 (UInt32)              | 10^9 / 10^19                   | parity        |
| Small mul          | Schoolbook                 | Schoolbook                     | parity        |
| Medium mul         | Karatsuba (cutoff 64w)     | Karatsuba                      | parity        |
| Large mul          | Toom-3 (cutoff 128w)       | **NTT** $O(n \log n)$          | **gap**       |
| Small div          | Specialised UInt64/128/256 | Schoolbook                     | decimo faster |
| Large balanced div | Burnikel-Ziegler           | **Reciprocal-Newton**          | gap           |
| Asymmetric div     | B-Z + truncation (T1/T2)   | GMP-style recursive            | parity        |
| Sqrt               | Reciprocal-Newton (T4)     | Reciprocal-Newton              | parity        |
| Exp                | Aggressive halving (T3d)   | Taylor + binary splitting      | small gap     |
| Ln near-1          | UInt32-divide Taylor (T3b) | Taylor + cached ln(10) + NTT   | small gap     |
| Ln far-from-1      | Recompute ln(2) + ln(1.25) | Cached `ln(10)` + range-reduce | **gap**       |
| Rounding           | Word-level truncation      | Similar                        | decimo faster |

## 8. Priority Summary

Open items in priority order (target: dm/py ≤ 1.5× across the board,
some ops < 1.0×):

| #      | Issue                                     | Effort | Priority | Target gain                                    |
| ------ | ----------------------------------------- | ------ | -------- | ---------------------------------------------- |
| T-API1 | `precision` arg on `add`/`sub`/`multiply` | S      | **DONE** | exact-then-round; foundation for T-API2/T-API3 |
| T-R2   | `round_to_precision_inplace` audit        | S      | **DONE** | code-quality; ~0% on divide bench (noise)      |
| T-A1   | `debug_assert .format` sweep across       | S      | **DONE** | sweep complete (20260606);                     |
|        |                                           |        |          | no .format asserts remain                      |
|        | BigDecimal                                |        |          |                                                |
| T-A2   | `multiply_by_power_of_ten` audit          | M      | **DONE** | inplace + multiple-of-9 fast path in use;      |
|        | + inplace variant                         |        |          | minor residual in non-inplace add/sub          |
| T-A3   | Hot-path-first switch in `add`/`sub`      | S      | **DONE** | subtract −37%@p1000, −24%@p100;                |
|        |                                           |        |          | add −13%@p1000; add@p100 noise                 |
| T-A4   | `@no_inline` raise helpers in             | S      | **DONE** | `_shorten_path` `@no_inline`;                  |
|        | BigDecimal/BigUInt                        |        |          | shrinks every inlined raise site               |
| T-A5   | `is_zero`/`is_integer` branch audit       | S      | **DONE** | kept; removal = 3x regression on zero          |
| T-M1   | Small-coefficient mul fast path           | M      | **NO**   | UInt128 path 130 vs 46 ns (base-10⁹)           |
| T-M2   | Single-pass rounding in `multiply`        | S      | **DONE** | already single-pass; 90→80 ns                  |
| T-D1   | Short-divisor fast path in `divide`       | M      | **DONE** | already via BigUInt dispatch                   |
| T-D2   | Trailing-zero strip allocation in divide  | S      | **DONE** | inplace strip; −16–21% exact-divide            |
| T-D3   | Reciprocal-Newton divide (legacy Task 2)  | XL     | **WAIT** | div only 2.1–3.1× mul →                        |
|        |                                           |        |          | recip-Newton ~5× mul (slower); gated on NTT    |
| T-S1   | Small-coef short-circuit in `sqrt` p=100  | S      | **NO**   | already short-circuits                         |
| T-L1   | atanh reformulation for ln (T3f)          | M      | **DONE** | already a hybrid; near-1 0.9–1.8× py           |
| T-L2   | Process-wide ln(10) cache recipe          | S      | **DONE** | `MathCache` (ln2/ln1.25/ln10) + recipe exist;  |
|        |                                           |        |          | auto-cache blocked on Mojo                     |
| T-L3   | AGM ln for p ≥ 1000 (T3g)                 | XL     | **WAIT** | gated on NTT (heavy per-iter sqrt);            |
|        |                                           |        |          | far-from-1 ln now addressed by T-3e            |
| T-IO1  | `from_string` digit batching              | M      | **DONE** | batching already present;                      |
|        |                                           |        |          | slice removed, 1.4×→1.2×                       |
| T-IO2  | `to_string` right-aligned InlineArray     | M      | **DONE** | hybrid exact-size direct-write;                |
|        |                                           |        |          | long 2.5–2.9×→0.8×                             |
| T-R1   | `round` `.format` sweep                   | S      | **NO**   | no `.format` asserts in round; great           |
| T-7b   | Reciprocal-Newton nth root                | M      | **WAIT** | break-even at current mul speed                |
|        |                                           |        |          | (div ~2.7× mul); root already 0.2× py          |
| T-5    | NTT multiplication                        | XL     | **WAIT** | valid; multi-session XL, tracked in §5.3       |
| T-9    | deferred-carry schoolbook mul             | M      | **DONE** | deferred-carry (product-scanning);             |
|        |                                           |        |          | Definitely worth bringing it to `BigInt` too   |
| T-3e   | Faster ln constant series                 | L      | **DONE** | exact-reciprocal divide; ln(2) 9–21×,          |
|        |                                           |        |          | ln(1.25) 3–4× at p≥1000                        |
| T-U1   | Use pointers rather than list indexing    | M      | **DONE** | kept 2-buffer divide (+4-8% >=256w)            |
