# BigInt Enhancement Plan

> **Date**: 2026-06-19 (created)
> **Target**: decimo >=0.9.0
> **Mojo Version**: >=v1.0.0
> 子曰：工欲善其事，必先利其器。

This document is the single source of truth for the arbitrary-precision
**signed integer** (`decimo.BigInt`, base-2^32) performance & correctness
effort. It supersedes `bigint2_benchmark_analysis.md` (2026-02-20), keeping
only the still-relevant historical work items; the full predecessor is
recoverable from git history.

## 1. Cross-Language Snapshot

Scope: **arbitrary-precision** signed integers. `BigInt10` (the legacy
base-10^9 integer) and `BigUInt` are out of scope here.

| Library           | Limb | Mul algorithm tier         | Div algorithm  | Sqrt                    |
| ----------------- | ---- | -------------------------- | -------------- | ----------------------- |
| decimo BigInt     | 2^32 | School  Kara               | Knuth-D → B-Z  | Newton → prec-doubling  |
| Py `int` (C)      | 2^30 | School → Kara              | Knuth (school) | prec-doubling (`isqrt`) |
| Rust `num-bigint` | 2^64 | School → Kara → Toom-3     | Knuth (school) | Newton                  |
| Java `BigInteger` | 2^32 | School → Kara → Toom-3     | Knuth → B-Z    | Newton                  |
| GMP `mpz_t`       | 2^64 | School → Kara → Toom → FFT | Newton-recip.  | Newton-reciprocal       |

**Coverage.** `decimo.BigInt` already offers a complete integer API:
`+ - * // % **`, `<< >>`, `& | ^ ~`, `sqrt` (integer), `from_string`,
`to_string`, plus `gcd`/`extended_gcd`/`lcm`/`mod_pow`/`mod_inverse`
(`number_theory.mojo`). No API gaps versus Python `int` or Rust
`num-bigint`; the open work is purely performance (but the most difficult :D)

## 2. Baseline (authoritative, 2026-06-19)

Cross-language harness `benches/bigint/` — `decimo.BigInt` vs Python `int`
(oracle + timing) vs Rust `num-bigint`. Release build (`-O3 -g0 -D
ASSERT=none`), DCE-guarded (`keep`/`black_box`), best-of-N auto-tuned to
~50ms/case. Median ns/iter; `dm/py` = decimo÷python, `dm/rs` =
decimo÷rust (**< 1.00 = decimo faster**). 230 cases, 100% decimo-vs-Python
agreement.

| op           |   dm |   py |   rs | dm/py | dm/rs | dominant cost                                  |
| ------------ | ---: | ---: | ---: | ----: | ----: | ---------------------------------------------- |
| add          |   48 |   31 |   41 |  1.5× |  1.2× | small-operand constant overhead                |
| multiply     |   50 |   42 |   31 |  1.2× |  1.6× | no Toom-3 / no SIMD partial products vs Rust   |
| floor_divide |  230 |   59 |   41 |  3.9× |  5.6× | **Knuth-D base-case overhead (worst op)**      |
| power        |  340 |  160 |  297 |  2.1× |  1.2× | square-and-multiply per-op overhead            |
| shift        |   42 |   39 |   26 |  1.1× |  1.6× | result-buffer allocation                       |
| sqrt         |  580 |  373 |  564 |  1.5× |  1.0× | medium-size division overhead (tied to divide) |
| from_string  |  990 |  786 |  407 |  1.3× |  2.4× | base-10→base-2^32 conversion (O(n²) medium)    |
| to_string    |  893 |  266 |  350 |  3.4× |  2.6× | O(n²) repeated `/10^9` at 50–1000 digits       |

> **Methodology note.** These supersede the 2026-02-20 per-op numbers
> (which reported decimo *faster* than Python). That harness discarded
> results (`_ = a + b`) with no DCE guard, timed a single pass, and ran on
> different hardware — its absolute ratios are not comparable. **Treat the
> 2026-06-19 figures as the baseline.** Ratios fluctuate ±10–20% run to run.

## 3. Change History — Done

Condensed from `bigint2_benchmark_analysis.md` (v0.8.0 effort). All items
verified and merged; kept here as the algorithmic record.

| Tag  | Item                                                                                             |
| ---- | ------------------------------------------------------------------------------------------------ |
| PR0  | sqrt correctness: overestimate-seeded Newton + CPython precision-doubling (was wrong ≥1000 d)    |
| PR1  | Karatsuba multiply (`CUTOFF_KARATSUBA = 48` words); slice-based, offset assembly, ptr loops      |
| PR2  | Slice-based Burnikel-Ziegler divide (`CUTOFF_BURNIKEL_ZIEGLER = 64`); ≤4-word divisor fast paths |
| PR3  | Divide-and-conquer `to_string` base conversion (entry ≥128 words, leverages B-Z)                 |
| PR4a | SIMD `parse_numeric_string` (two-pass, `vectorize[16]` digit extraction)                         |
| PR4b | D&C `from_string` base conversion (entry > 10000 digits)                                         |
| PR4c | `from_string` micro-opts (≤9/≤19-digit fast paths, pre-alloc, raw ptrs, balanced split)          |
| PR4d | `to_string` micro-opts (1-/2-word fast paths, `InlineArray` byte buffer, raw ptrs)               |
| PR5  | True in-place arithmetic for all 11 `__i*__` dunders (`add_inplace`, …)                          |
| PR6  | Bitwise AND / OR / XOR / NOT with two's-complement semantics                                     |
| PR7  | `gcd`, `extended_gcd`, `lcm`, `mod_pow`, `mod_inverse` (`number_theory.mojo`)                    |
| PR8  | `BInt`/`BigInt` alias bound to the base-2^32 type (legacy → `BigInt10`)                          |

## 4. Lessons Learnt

Items 1–3 are BigInt-specific. Items 4–9 transfer from
`bigdecimal_enhancement.md §4` / `decimal128_enhancement.md` — they hold
unchanged for the variable-length signed case.

1. **Newton sqrt must converge from above.** An underestimate seed lets
   Newton settle on the wrong quadratic residue at ≥1000 digits (PR0). Seed
   with a ceiling-rounded hardware sqrt of the top words; for huge inputs use
   CPython precision-doubling — total work O(M(n)), not O(M(n)·log n).

2. **Base-2^32 carries are shift/mask, not division — so the BigDecimal
   "deferred-carry / Comba" multiply win does NOT transfer.** The base-10^9
   Comba trick (T-9) existed to amortise the `% 10^9` / `/ 10^9` on every
   inner-product step. In base-2^32 the carry is already `>> 32` + `&
   0xFFFFFFFF` (no divide), so the multiply gap versus Rust is **Toom-3 +
   SIMD partial-product accumulation**, not carry amortisation. Measure
   before porting any base-10^9 micro-opt.

3. **Slice-based recursion is mandatory for B-Z.** The first copy-based
   Burnikel-Ziegler regressed (excess `List[UInt32]` allocation per level);
   passing `(list, start, end)` bounds and materialising only at the Knuth-D
   base case is what made it a net win (PR2). Any new D&C kernel must follow
   the same no-copy-until-base-case discipline.

4. **`debug_assert` does NOT lazy-evaluate its message** under `-D
   ASSERT=none`; a `String.format(...)` argument still allocates in the hot
   loop. Use plain string literals (or the variadic `debug_assert(cond,
   "msg ", value)` form) only.

5. **Hot path first.** The count of branches *before* the fast arm matters
   more than the fast arm's body. Route rare cases (zero operand, sign
   mismatch, differing length) to a cold tail of the same function.

6. **`@no_inline` the body of every `raise … .format(...)` helper** so
   `@always_inline` can fire on the parent and icache pressure at inline
   raise edges drops.

7. **Hoist a raw data pointer in multi-buffer / O(n²) inner loops.** A
   `List[i]` access reloads `List._data` every element. Hoisting
   (`var p = lst.unsafe_ptr()`) is a stable win when an iteration touches
   ≥2 buffers or is an O(n²) inner loop; it does **not** clear the ~3% bar
   for single-buffer single-pass O(n) loops that are arithmetic-bound.
   Safety: the buffer must not be resized while the pointer is live.

8. **Precision doubling is the lever for Newton-style methods** (sqrt, and
   any future reciprocal divide): start small and double, total work ≈ 3×
   the final iteration instead of `log n` full-width iterations.

9. **Reciprocal-Newton divide only wins once multiplication is much
   cheaper than division** (the NTT regime). With Karatsuba, a B-Z divide is
   ~2–3× a same-size multiply, so a reciprocal-Newton rewrite would be a
   *regression* today — gate it behind Toom-3/NTT (H#1).

## 5. Open Items / Future Improvements (priority ordered)

Each task is justified by §2 and a lesson in §4.

### floor_divide / truncate_divide (3.9× py, 5.6× rs → target ≤1.5×)

The single biggest gap. B-Z is only entered above 64 words; the 1–64-word
band (the common case, and every sqrt inner iteration) runs the Knuth-D
base case, whose per-call setup (normalise, estimate-correct loop) dominates
at small sizes.

- **T-D1: Knuth-D base-case overhead audit.** Profile the ≤64-word path;
  hoist data pointers in the estimate/multiply-subtract inner loops
  (Lesson #7 — two buffers), and reorder so the single-/double-word divisor
  fast paths are reached with the fewest branches (Lesson #5). Rust's plain
  schoolbook divide is 5.6× faster here, so the headroom is in constants,
  not the algorithm.
- **T-D2: Lower `CUTOFF_BURNIKEL_ZIEGLER` re-tune.** Re-measure 32/48/64
  now that the base case is faster; the medium band may benefit from earlier
  B-Z entry.
- **T-D3: Reciprocal/Barrett divide.** DEFERRED — not beneficial before
  Toom-3/NTT (Lesson #9).

### to_string medium sizes (3.4× py → target ≤1.5×)

Fast paths (≤2 words) and D&C (≥128 words) are done; the 50–1000-digit band
still runs the O(n²) simple path (`InlineArray` chunked emit already in
place).

- **T-T1: Lower the D&C entry threshold** once T-D1 makes the recursive
  divisions cheaper (D&C is gated on divide cost). Re-measure entry=64/96.
- **T-T2: Batch the repeated `/10^9` with a wider radix** only if it does
  not hit the UInt128-divide-is-software-emulated trap (PR4d rejected 10^18
  chunks for exactly this reason — re-verify on current hardware).

### multiply (1.2× py, 1.6× rs → target ≤1.0×)

- **T-M1: Toom-3 multiplication.** Rust's Toom-3 is what makes it 1.6×
  faster at scale; decimo stops at Karatsuba. Port Toom-3 above
  ~256 words (the BigDecimal/BigUInt cutoff ratio) — see H#1.
- **T-M2: SIMD partial-product accumulation** in the schoolbook base case
  (NEON `4×UInt32`), the base for both Karatsuba and a future Toom-3. This
  (not Comba) is the base-2^32 analogue of the BigDecimal multiply win
  (Lesson #2).

### power (2.1× py → target ≤1.2×) and add (1.5× py)

- **T-P1: square-and-multiply overhead.** General (non-2^N) power is
  bottlenecked by per-multiply temporaries; route the inner loop through
  `multiply_inplace` and the squaring through a dedicated `square()` that
  exploits symmetry (~2× fewer partial products). The 2^N shift fast path is
  already excellent (Rust loses to it).
- **T-A1: add/sub small-operand constant overhead.** Apply Lesson #5 (hot
  path first: same-length same-sign branch first) and audit for stray
  `debug_assert .format` (Lesson #4). SIMD add is already present; the gap is
  dispatch, not the kernel.

### from_string / shift (compiled-peer gap)

- **T-F1: from_string base conversion.** O(n²) base-10→base-2^32 in the
  50–10000-digit band; lower the D&C entry threshold after T-M1 (D&C uses
  multiply). > 20000-digit gap closes only with Toom-3/NTT (H#1).
- **T-SH1: shift allocation.** Extreme shifts (`1 << 100000`) are
  allocation-bound; pre-size the result buffer with
  `resize(unsafe_uninit_length=…)` (O(1) capacity + memset) instead of
  growth.

### Execution plan

| Label | Hypothesis                                            | Status                                         |
| ----- | ----------------------------------------------------- | ---------------------------------------------- |
| T-M1  | Toom-3 (then NTT) multiply for ≥256 / extreme words   | OPEN — unlocks mul, from_str, divide-via-recip |
| T-D1  | Knuth-D base-case constants dominate small/medium div | OPEN — T-D1; Rust schoolbook 5.6× faster       |
| T-D1  | Pointer hoisting in inner loop                        | OPEN — T-D1 (Lesson #7, two buffers)           |
| T-M2  | SIMD partial-product accumulation in schoolbook base  | OPEN — T-M2 (base-2^32 analogue of Comba)      |
| T-P1  | `square()` exploiting symmetry for power inner loop   | OPEN — T-P1                                    |
| T-T1  | Lower D&C entry thresholds once divide is faster      | OPEN — T-T1, T-F1, T-D2                        |
| T-D3  | Reciprocal-Newton divide                              | DEFERRED — needs H#1 (Lesson #9)               |
