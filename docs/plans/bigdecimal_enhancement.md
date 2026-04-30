# BigDecimal Enhancement Plan

> **Date**: 2026-02-21 (created), 2026-04-30 (last consolidated)
> **Target**: decimo >=0.9.0
> **Mojo Version**: >=0.26.2
>
> 子曰：學而時習之，不亦說乎。

This document tracks the BigDecimal performance & correctness work
started on 2026-02-21. It is the single source of truth for the
arbitrary-precision decimal hot-path optimisation effort. The earlier
verbose form (1439 lines) is preserved at `bigdecimal_enhancement.md.bak`.

---

## 1. Cross-Language Snapshot

Scope: **arbitrary-precision** decimal types. Out of scope: 128-bit
fixed-precision (covered by `decimal128_enhancement.md`).

| Library                 | Limb base           | Mul algorithm tier               | Div algo           | Sqrt              |
| ----------------------- | ------------------- | -------------------------------- | ------------------ | ----------------- |
| **decimo BigDecimal**   | 10^9 (UInt32 LE)    | School → Karatsuba → Toom-3      | B-Z (Knuth-D base) | reciprocal-Newton |
| Python `decimal`/libmpd | 10^9 / 10^19        | School → Karatsuba → **NTT**     | reciprocal-Newton  | reciprocal-Newton |
| Rust `bigdecimal` 0.4   | 10^9 (num-bigint)   | School → Karatsuba → Toom-3      | schoolbook (slow)  | Newton with div   |
| Java `BigDecimal`       | binary `BigInteger` | School → Kara → Toom → Schönhage | Burnikel-Ziegler   | Newton (binary)   |
| GMP `mpz_t` / MPFR      | 2^64                | School → Kara → Toom → **FFT**   | reciprocal-Newton  | reciprocal-Newton |
| JS `decimal.js`         | 10^7 (Number arr)   | School only                      | schoolbook         | Newton            |
| Go `math/big.Float`     | 2^64 (binary)       | School → Karatsuba               | reciprocal-Newton  | Newton            |

**Coverage matrix.** decimo offers the broadest decimal API: `add`,
`subtract`, `multiply`, `divide`, `sqrt`, `cbrt`, `root(x,n)`, `exp`,
`ln`, `log10`, `log(x,b)`, `power`, `round`, `compare`, `from_string`,
`to_string`. The Rust crate lacks `exp`/`ln`/`root`/`round`. JS
`decimal.js` covers all but is single-language. Java covers all but
loses I/O speed to binary internal storage.

---

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

| Date     | Tag | Item                                                                               |
| -------- | --- | ---------------------------------------------------------------------------------- |
| 20260221 | T1  | Asymmetric divide truncation: `extra_words = ceil(P/9)+2 - diff_n_words`           |
| 20260223 | T2  | Balanced divide also truncates; quotient near constant time vs operand size        |
| 20260222 | T3a | `MathCache` for `ln(2)`/`ln(1.25)` — log() shares 2 internal ln() calls            |
| 20260222 | T3b | UInt32 division in Taylor series (was full BigDecimal divide per term)             |
| 20260222 | T3c | `get_ln10()` in MathCache (reuses cached `ln(2)` & `ln(1.25)`)                     |
| 20260224 | T3d | Aggressive halving range reduction for exp: $M \approx \sqrt{3.322p}$              |
| 20260222 | T4  | sqrt via reciprocal-Newton with precision doubling at BigDecimal level (no divide) |
| 20260222 | T7a | `integer_root` via direct Newton (was `exp(ln(x)/n)`)                              |
| 20260223 | T8  | BigDecimal in-place ops applied across exp/ln/sin/cos/arctan Taylor loops          |
| 20260224 | T6  | Toom-3 multiplication, cutoff 128 words; +14–29% over Karatsuba for ≥256 words     |

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

| Date     | op     | p=100 | p=1000 | p=10000 | p=100000 |
| -------- | ------ | ----: | -----: | ------: | -------: |
| 20260224 | add    |  4.7× |   4.9× |    4.9× |     4.6× |
| 20260224 | sub    |  3.6× |   3.5× |    3.8× |     3.6× |
| 20260224 | mul    |  2.3× |   2.4× |    2.4× |     2.2× |
| 20260224 | div    |  5.4× |   5.8× |    5.0× |     4.9× |
| 20260224 | cmp    |  0.2× |   0.1× |    0.2× |        — |
| 20260224 | sqrt   |  2.1× |   0.7× |    0.3× |        — |
| 20260224 | exp    |  1.8× |   0.4× |       — |        — |
| 20260224 | ln     |  4.6× |   9.2× |       — |        — |
| 20260224 | root   |  0.3× |   0.0× |       — |        — |
| 20260224 | frmstr |  1.2× |   1.2× |    1.2× |        — |
| 20260224 | tostr  |  1.3× |   1.3× |    1.2× |        — |
| 20260224 | round  |  1.9× |   2.1× |    2.2× |        — |

Latest sweep (2026-04-30, `bigdec_report_20260429_222750.md`).

### 2.6 Performance tracking — decimo / rust ratio

Rust `bigdecimal` lacks `exp`, `ln`, `root`, `round`; `divide` skipped
because the crate's naive long division is unusably slow at p≥1000.

| Date     | op     | p=100 | p=1000 | p=10000 | p=100000 |
| -------- | ------ | ----: | -----: | ------: | -------: |
| 20260224 | add    |  5.1× |   6.7× |    6.6× |     6.0× |
| 20260224 | sub    |  4.8× |   5.1× |    5.8× |     5.3× |
| 20260224 | mul    |  6.5× |   5.3× |    5.5× |     6.0× |
| 20260224 | cmp    |  4.4× |   3.9× |    4.3× |        — |
| 20260224 | sqrt   |  4.3× |   4.6× |    2.8× |        — |
| 20260224 | frmstr |  2.4× |   2.1× |    2.3× |        — |
| 20260224 | tostr  |  1.2× |   1.5× |    1.4× |        — |

---

## 3. Hypothesis Ledger

| H#  | Hypothesis                                                       | Outcome                                                             |
| --- | ---------------------------------------------------------------- | ------------------------------------------------------------------- |
| 1   | Asymmetric divide pads quotient unnecessarily                    | DONE (T1) — 0.11→76× py at 65536w/32768w                            |
| 2   | Balanced divide also wastes work for high-precision req          | DONE (T2) — quotient near-constant time (8–915× py)                 |
| 3a  | `ln(2)`/`ln(1.25)` recomputed per call                           | DONE (T3a) — `MathCache`; 3×–4.5× speedup for repeated `ln()`       |
| 3b  | Per-Taylor-term BigDecimal divide is wasteful                    | DONE (T3b) — UInt32 divide path; +20–130% near-1 ln                 |
| 3c  | `log10()`/`log()` re-compute `ln(10)`                            | DONE (T3c) — cached via `MathCache`                                 |
| 3d  | exp Taylor series too long; weak halving                         | DONE (T3d) — $M=\sqrt{3.322p}$; exp 0.4×→2.6× py at p=1000          |
| 3e  | Binary splitting for ln Taylor series                            | OPEN — diminishing returns for exp post-T3d; ln still O(p) terms    |
| 3f  | `atanh` reformulation for ln (3× fewer terms)                    | OPEN — easy win; estimated 3× near-1                                |
| 3g  | AGM-based ln for very high precision                             | OPEN — long-term, complex                                           |
| 4   | sqrt via Newton-with-division is slow                            | DONE (T4) — reciprocal-Newton + precision doubling; 20× improvement |
| 5   | NTT multiplication for n ≥ 1024 words                            | OPEN — single biggest long-term gap vs libmpdec                     |
| 6   | Toom-3 between Karatsuba and NTT                                 | DONE (T6) — +14–29% for ≥256w                                       |
| 7a  | `integer_root` via direct Newton (was exp(ln(x)/n))              | DONE (T7a) — 0.14×→25× py at p=1000 for cbrt                        |
| 7b  | Reciprocal-Newton for nth root (no divide)                       | OPEN — estimated 1.5–2×                                             |
| 7c  | Rational decomposition $x^{a/b}$ → root then power               | OPEN — fractional roots still 0.2–0.4× py                           |
| 8   | BigDecimal-level inplace ops in Taylor loops                     | DONE (T8) — +15–27% exp/ln, +9% sqrt                                |
| 9   | SIMD schoolbook multiply base                                    | OPEN — 1.5–2× constant-factor                                       |
| 10  | `debug_assert(..., "{}".format(...))` eager allocation           | OPEN — sweep BigUInt + BigDecimal hot paths (Lesson #7)             |
| 11  | Hot-path-first switch reorder in BigDecimal `add`/`sub`          | OPEN — same-scale & same-sign branch first (Lesson #12)             |
| 12  | `@no_inline` raise helpers in BigDecimal/BigUInt                 | OPEN — sweep `from_string`, `from_uint32`, etc. (Lesson #10)        |
| 13  | `from_string` digit batching (UInt64 chunks of 9 or 19)          | OPEN — borrowed from decimal128 H#17 follow-up                      |
| 14  | `to_string` `InlineArray` right-aligned chunked emit             | OPEN — borrowed from decimal128 §2.4                                |
| 15  | Single-pass rounding in BigDecimal `multiply` / `divide`         | OPEN — borrowed from decimal128 H#16                                |
| 16  | Short-divisor fast path in `divide` (single-word loop)           | OPEN — `BigUInt.floor_divide_by_uint32` exists; lift to BigDecimal  |
| 17  | Add/sub `multiply_by_power_of_ten` allocates oversized           | OPEN — root cause of 4.7× py on small-precision add                 |
| 18  | Small-coefficient mul fast path (bypass Karatsuba dispatch)      | OPEN — borrowed from decimal128 H#4 dispatch-overhead lesson        |
| 19  | `precision` arg on `add`/`sub`/`multiply` (truncate ops upfront) | OPEN — structural; foundation for T-A2/T-M1 (see T-API1)            |

---

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

---

## 5. Open Items / Future Improvements

### 5.1 Worst-case ratios still > 1.5× python (latest sweep 2026-04-30)

The new bench harness exposes that **all small-to-medium-precision
arithmetic ops sit at 2–5× python**, not the previously reported 2–4×
on a smaller corpus. Closing these is the path to the ≤1.5× target.

| Op          | Worst case (p=100)                     | decimo | python | rust | dm/py | Likely cause                                    |
| ----------- | -------------------------------------- | -----: | -----: | ---: | ----: | ----------------------------------------------- |
| add         | Add of 2000-digit dec with carries     |   3116 |    222 | 63.8 | 14.0× | scale-align + per-call overhead                 |
| add         | Fib-like large dec add (1100 d)        |   2021 |    128 | 90.4 | 15.8× | same                                            |
| add         | Addition at precision boundary         |    524 |   57.5 | 38.2 |  9.1× | over-allocation at boundary                     |
| sub         | (similar long-decimal cases)           |  ~2000 |   ~120 |  ~70 |  ~14× | same                                            |
| mul         | High precision multiply small operands |    140 |     61 | 21.7 |  2.3× | dispatch overhead, no small-coef fast path      |
| div         | Repeating-decimal div                  |    805 |  149.6 |    — |  5.4× | full Burnikel-Ziegler even for short divisor    |
| div (p=10k) | Long decimal divide                    |    25k |   5.0k |    — |  5.0× | same                                            |
| sqrt(p=100) | √(small irrational)                    |   8.6k |   4.1k | 2.0k |  2.1× | reciprocal-Newton overhead at tiny size         |
| ln(p=100)   | far-from-1 (`ln(10)`, `ln(0.1)`)       |   104k |  22.5k |    — |  4.6× | recompute from scratch (no global ln(10) cache) |
| ln(p=1000)  | far-from-1                             |    38M |   4.2M |    — |  9.2× | same; gap widens with precision                 |
| from_string | (many long-decimal cases)              |    170 |    140 |   72 |  1.2× | already close; finish via digit batching        |
| to_string   | (many cases)                           |    200 |    160 |  140 |  1.3× | finish via right-aligned `InlineArray`          |
| round       | Various                                |    200 |     90 |    — |  2.2× | likely `debug_assert .format`                   |

**Where decimo already wins.** `comparison` is 5–10× *faster* than
python (0.1–0.2×). `sqrt` at p≥1000 is 0.3–0.7× py. `exp` at p=1000
is 0.4× py. `root` at any precision is 0.0–0.3× py. These ops need no
further work.

### 5.2 New optimisation tasks (priority ordered)

Each task below is justified by the bench data in §5.1 and one or more
lessons in §4. All borrow patterns proven on the Decimal128 hot path.

P0 — Structural API change (foundation for most P1 wins)

- **T-API1: Add `precision: Int = 0` argument to `add`, `subtract`,
  `multiply`** (and the `__add__`/`__sub__`/`__mul__` overloads).
  Today these ops produce the full exact result regardless of how many
  digits the user actually wants. Python `decimal` and Java
  `BigDecimal` round to context precision after every op; that is a
  large part of why Python is 4.7× / 3.6× / 2.3× faster on add/sub/mul
  at p=100. With a precision hint:

  - **add/sub:** when one operand's scale is so small relative to the
    other that its low-order digits would round away (the 14× py
    "Add of 2000-digit dec with carries" worst case), truncate it via
    `floor_divide_by_power_of_billion()` *before* the SIMD addition.
    Same trick that drove T1 (asymmetric divide) to 76× py.
  - **multiply:** when `digits(a) + digits(b) > precision + guard`,
    truncate the longer operand by `excess` words upfront. The product
    of two 1000-digit operands at p=100 currently does the full
    2000-digit Karatsuba then discards 1900 digits.
  - **divide:** already takes precision; no change.
  - **comparison / from_string / to_string:** unaffected.

  **Default `precision=0` preserves current exact-result behaviour for
  back-compat.** When non-zero it acts as the rounding context for the
  return value *and* as a hint for upfront operand truncation.
  **Estimated:** 30–70% on every long-decimal arithmetic case; the
  single highest-leverage change open today. Foundation that T-A2,
  T-M1, T-D1 plug into.

P1 — Add/Sub small-precision target (currently 4.7× / 3.6× py → target ≤2×)

- **T-A1: `debug_assert .format` sweep.** Audit `BigDecimal.add`,
  `subtract`, `multiply`, `divide`, `round`, and the BigUInt primitives
  they call (`add_inplace`, `subtract_inplace`,
  `multiply_by_power_of_ten`, `floor_divide_by_power_of_billion`).
  Replace every `debug_assert(cond, "msg {}".format(x))` with a plain
  literal. (Lesson #7.) **Estimated:** 10–30% on every hot op.

- **T-A2: `multiply_by_power_of_ten` allocation audit (H#17).** Most
  add/sub cases require scale alignment via this primitive. Profile
  whether it allocates a fresh BigUInt per call, whether trailing-zero
  word insertion is `O(n)` memcpy or `O(1)` reservation + memset, and
  whether the result is reused or discarded. Add an inplace variant if
  missing. **Estimated:** 30–50% on long-decimal add/sub (the 14× py
  worst cases).

- **T-A3: Hot-path-first switch reorder in `add`/`subtract` (H#11).**
  Mirror Decimal128 H#11. Make the `same scale & same sign` branch the
  first arm; route diff-scale and zero-with-different-scale into the
  cold tail. **Estimated:** 1–3 ns / call.

- **T-A4: `@no_inline` raise helpers (H#12).** Extract every
  `raise Error(String.format(...))` from `BigDecimal` and `BigUInt` hot
  inline functions into `@no_inline _raise_*` helpers. Most relevant in
  `from_string`, `from_int`, scale-overflow checks. (Lesson #10.)
  **Estimated:** unblocks `@always_inline` on ~5 hot paths.

- **T-A5: `is_zero` / `is_integer` branch removal (H#3.1).** Audit
  `add`/`subtract` for `is_zero(other) → return self.copy()` style
  early-outs. **For BigDecimal the `is_integer()` probe is a full
  multi-word `coef % 10^scale`** — strictly more expensive than the
  Decimal128 bitmask version that was already shown to be a net loss
  even when triggered. Remove unless benchmarked positive on a
  realistic input mix. (Lesson #9.)

P2 — Multiply small-precision (2.3× py → target ≤1.5×)

- **T-M1: Small-coefficient fast path (H#18).** When both operands fit
  in a single UInt64 (≤ 18 decimal digits) and the result fits in
  UInt128, bypass the BigUInt Karatsuba dispatch entirely — do one
  `UInt64 × UInt64 → UInt128` multiply, build a single-word BigUInt,
  apply scale arithmetic, round. **Estimated:** 50–70% on the small-
  operand path.

- **T-M2: Single-pass rounding in `multiply` (H#15, Lesson #16).** When
  the result needs both fit-rounding (coefficient too large) and
  scale-rounding (combined scale > requested precision), compute the
  total drop in one shot. (Decimal128 §2.4 saved 5 ns this way.)

P3 — Divide all precisions (5× py → target ≤2×)

- **T-D1: Short-divisor fast path (H#16).** When the divisor fits in
  UInt32 (most "round to N decimal places", "halve", "tenth" cases),
  call `BigUInt.floor_divide_by_uint32` directly instead of constructing
  a single-word divisor and entering Burnikel-Ziegler. **Estimated:**
  3–10× on short-divisor cases.

- **T-D2: Trailing-zero detection allocation.** Profile the
  `_strip_trailing_zeros` call after every divide. Likely allocates a
  copy; rewrite to scan in-place and adjust scale.

- **T-D3: Reciprocal-Newton divide (legacy Task 2).** For balanced
  large operands, invert the divisor once and multiply. `2× mul` per
  Newton step beats the `1× div` of B-Z. (Lesson #3.) Long-term;
  combine with NTT (Task 5) for full benefit.

P4 — sqrt at p=100 (2.1× py → target ≤1.0×)

- **T-S1: Small-coefficient short-circuit before `fast_isqrt`.** When
  the coefficient fits in UInt128, use a hardware-friendly integer
  isqrt (Newton on UInt128) and skip the reciprocal-Newton dance
  entirely. The 8.6 µs / call at p=100 is dominated by float64 setup +
  precision doubling overhead that is wasted at this size.

P5 — ln far-from-1 (4.6×–9.2× py → target ≤2×)

- **T-L1: atanh reformulation (T3f / H#3f).** Replace `ln(1+z)` Taylor
  with `2·atanh((x-1)/(x+1))`. Series rate goes from 1/2 to 1/9 → 3×
  fewer terms. Easy implementation; no algorithmic risk.

- **T-L2: Process-wide `ln(10)` cache (workaround for missing global
  vars).** When Mojo gains module-level mutable state, install a
  process-wide MathCache. Until then, document the recipe for users
  to construct one cache and pass it across calls.

- **T-L3: AGM ln (T3g / H#3g).** Long-term, only worth implementing
  alongside or after NTT (Task 5).

P6 — `from_string` / `to_string` (1.2–1.3× py → target ≤1.0×)

- **T-IO1: Digit batching in `from_string` (H#13).** Accumulate up to
  9 digits in a UInt32 (or 19 in a UInt64), then
  `coef = coef * 10^k + batch`. Drops per-digit BigUInt-mul-by-10 to
  amortised single-word multiply. (Decimal128 H#17 saw 41→22 ns; the
  arbitrary-precision case will see a larger absolute saving on long
  inputs.)

- **T-IO2: Chunked `to_string` via small staging InlineArray (H#14).**
  Note: BigDecimal's coefficient is unbounded (up to 100000+ digits in
  the bench), so the *whole* digit buffer cannot be a fixed-size
  `InlineArray` — unlike Decimal128 where the 32-byte buffer holds the
  entire 29-digit max. The applicable adaptation: pre-`reserve` a
  `String` (or write directly into the `Writer`) sized to the
  precomputed digit count, then loop `BigUInt // 10^9` outer + `UInt32
  // 10` inner, staging each 9-digit chunk into a 9-byte `InlineArray`
  and emitting it as a single `StringSlice` write per chunk. (Lesson
  #15.) Reduces allocations by a factor of `digits / 9` and avoids
  per-byte `writer.write`.

P7 — `round` (2× py → target ≤1.0×)

- **T-R1: `debug_assert .format` sweep specific to rounding modes.**
  The round dispatcher likely has one assert per mode branch.

### 5.3 Long-term tasks not on the active roadmap

| #   | Task                                                           | Effort |
| --- | -------------------------------------------------------------- | ------ |
| 5   | NTT multiplication (≥1024 words). Closes the gap with libmpdec | XL     |
| 9   | SIMD-optimised schoolbook mul kernel                           | M      |
| 3e  | Binary splitting for ln Taylor series                          | L      |
| 3g  | AGM-based ln for p ≥ 1000                                      | XL     |
| 7b  | Reciprocal-Newton for nth root                                 | M      |
| 7c  | Rational $x^{a/b}$ decomposition                               | S      |

---

## 6. Result-Equivalence vs Python / Rust

The 2026-04-30 sweep flags zero `match py` / `match rs` failures across
all numeric ops. The only acknowledged differences:

| Op    | Source                       | Notes                                                                                     |
| ----- | ---------------------------- | ----------------------------------------------------------------------------------------- |
| root  | Python `da ** (1/n)` oracle  | Python rounds `1/n` to working precision before exponentiation; 1–3 ulp differences are   |
|       |                              | expected and **not bugs**. Negative-base nth roots additionally raise `InvalidOperation`. |
| div   | rust `bigdecimal` skipped    | Crate uses naive long division; p=100000 takes ~700 ms / iter. Skipped at harness level.  |
| exp/  | rust `bigdecimal` not avail. | Crate does not implement these ops. `match rs` column shown as `-`.                       |
| ln/   |                              |                                                                                           |
| root/ |                              |                                                                                           |
| round |                              |                                                                                           |

decimo follows IEEE 754-2008 §3.3 preferred-exponent rules for the
trailing-zero shape of multiply/divide results, matching Python
`decimal` and .NET. See `decimal128_enhancement.md §6` for the same
issue at fixed precision.

---

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

---

## 8. Priority Summary

Open items in priority order (target: dm/py ≤ 1.5× across the board,
some ops < 1.0×):

| #      | Issue                                              | Effort | Priority | Target gain             |
| ------ | -------------------------------------------------- | ------ | -------- | ----------------------- |
| T-API1 | `precision` arg on `add`/`sub`/`multiply`          | M      | **P0**   | 30–70% long-dec arith   |
| T-A1   | `debug_assert .format` sweep across BigDecimal     | S      | **P1**   | 10–30% all ops          |
| T-A2   | `multiply_by_power_of_ten` audit + inplace variant | M      | **P1**   | 30–50% long-dec add/sub |
| T-A3   | Hot-path-first switch in `add`/`sub`               | S      | **P1**   | 1–3 ns / call           |
| T-A4   | `@no_inline` raise helpers in BigDecimal/BigUInt   | S      | **P1**   | unblocks always-inline  |
| T-A5   | `is_zero`/`is_integer` branch audit                | S      | P2       | small                   |
| T-M1   | Small-coefficient mul fast path                    | M      | **P1**   | 50–70% small-mul        |
| T-M2   | Single-pass rounding in `multiply`                 | S      | P2       | ~5 ns / call            |
| T-D1   | Short-divisor fast path in `divide`                | M      | **P1**   | 3–10× short-divisor     |
| T-D2   | Trailing-zero strip allocation in divide           | S      | P2       | 5–15%                   |
| T-D3   | Reciprocal-Newton divide (legacy Task 2)           | XL     | P3       | 2× large balanced       |
| T-S1   | Small-coef short-circuit in `sqrt` p=100           | S      | P2       | ~50% at p=100           |
| T-L1   | atanh reformulation for ln (T3f)                   | M      | **P1**   | 3× ln near-1            |
| T-L2   | Process-wide ln(10) cache recipe                   | S      | P3       | doc                     |
| T-L3   | AGM ln for p ≥ 1000 (T3g)                          | XL     | P4       | 10–50× p≥1000           |
| T-IO1  | `from_string` digit batching                       | M      | P2       | 30–50%                  |
| T-IO2  | `to_string` right-aligned InlineArray              | M      | P2       | 20–40%                  |
| T-R1   | `round` `.format` sweep                            | S      | P2       | small                   |
| T-7b   | Reciprocal-Newton nth root                         | M      | P3       | 1.5–2×                  |
| T-7c   | Rational $x^{a/b}$ decomposition                   | S      | P2       | 5–10× frac roots        |
| T-5    | NTT multiplication                                 | XL     | P4       | 2–10×                   |
| T-9    | SIMD schoolbook mul base                           | M      | P3       | 1.5–2×                  |
| T-3e   | Binary splitting for ln Taylor                     | L      | P4       | 2–4× p≥500              |
