# BigInt Enhancement Plan

> **Date**: 2026-06-19 (created)
> **Target**: decimo >=0.9.0
> **Mojo Version**: >=v1.0.0
> 子曰：工欲善其事，必先利其器。

This document is the single source of truth for the arbitrary-precision
**signed integer** (`decimo.BigInt`, base-2^64 since 2026-08-27) performance & correctness
effort. It supersedes `bigint2_benchmark_analysis.md` (2026-02-20), keeping
only the still-relevant historical work items; the full predecessor is
recoverable from git history.

## 1. Cross-Language Snapshot

Scope: **arbitrary-precision** signed integers. `BigInt10` (the legacy
base-10^18 integer) and `BigUInt` are out of scope here.

| Library           | Limb | Mul algorithm tier         | Div algorithm  | Sqrt                    |
| ----------------- | ---- | -------------------------- | -------------- | ----------------------- |
| decimo BigInt     | 2^64 | School → Kara → Toom → NTT | Knuth-D → B-Z  | Newton → prec-doubling  |
| Py `int` (C)      | 2^30 | School → Kara              | Knuth (school) | prec-doubling (`isqrt`) |
| Rust `num-bigint` | 2^64 | School → Kara → Toom-3     | Knuth (school) | Newton                  |
| Java `BigInteger` | 2^32 | School → Kara → Toom-3     | Knuth → B-Z    | Newton                  |
| GMP `mpz_t`       | 2^64 | School → Kara → Toom → FFT | Newton-recip.  | Newton-reciprocal       |

**Coverage.** `decimo.BigInt` already offers a complete integer API:
`+ - * // % **`, `<< >>`, `& | ^ ~`, `sqrt` (integer), `from_string`,
`to_string`, plus `gcd`/`extended_gcd`/`lcm`/`mod_pow`/`mod_inverse`
(`number_theory.mojo`). No API gaps versus Python `int` or Rust
`num-bigint`; the open work is purely performance, which is the harder half.

## 2. Baseline (authoritative, 2026-06-19)

Cross-language harness `benches/bigint/` — `decimo.BigInt` vs Python `int`
(oracle + timing) vs Rust `num-bigint`. Release build (`-O3 -g0 -D
ASSERT=none`), DCE-guarded (`keep`/`black_box`), best-of-N auto-tuned to
~50ms/case. Median ns/iter; `dm/py` = decimo÷python, `dm/rs` =
decimo÷rust (**< 1.00 = decimo faster**). 230 cases, 100% decimo-vs-Python
agreement.

| op           |   dm |   py |   rs | dm/py | dm/rs | dominant cost                                 |
| ------------ | ---: | ---: | ---: | ----: | ----: | --------------------------------------------- |
| add          |   48 |   31 |   41 |  1.5× |  1.2× | small-operand constant overhead               |
| multiply     |   50 |   42 |   31 |  1.2× |  1.6× | no Toom-3, no SIMD partial products vs Rust   |
| floor_divide |  230 |   59 |   41 |  3.9× |  5.6× | **per-call allocations (the worst op)**       |
| power        |  340 |  160 |  297 |  2.1× |  1.2× | square-and-multiply per-op overhead           |
| shift        |   42 |   39 |   26 |  1.1× |  1.6× | result-buffer allocation                      |
| sqrt         |  580 |  373 |  564 |  1.5× |  1.0× | medium-size division overhead                 |
| from_string  |  990 |  786 |  407 |  1.3× |  2.4× | base-10 → base-2^32 conversion (O(n²) medium) |
| to_string    |  893 |  266 |  350 |  3.4× |  2.6× | O(n²) repeated `/10^9` at 50–1000 digits      |

> **Methodology note.** These numbers replace the 2026-02-20 per-op
> figures, which reported decimo *faster* than Python. That harness threw
> the result away (`_ = a + b`) with no DCE guard, timed a single pass, and
> ran on different hardware, so its ratios are not comparable. Treat the
> 2026-06-19 figures as the baseline. They fluctuate ±10–20% run to run.

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

   3a. **A cross-language gap is usually decimo's own overhead, not the
   limb width.** When I first saw the 5.6× Rust floor_divide gap I blamed
   the representation (decimo is base-2^32, num-bigint is base-2^64). The
   benchmark says otherwise. Python uses base-2^30 limbs, even narrower
   than decimo's, and still divides 3.9× faster; sqrt is multiply- and
   divide-heavy yet already at parity with Rust. So a wider limb is not why
   decimo trails. Look for the real cost first: redundant copies, per-call
   allocations, branches in the inner loop. Only reach for the limb width
   once those are gone (T-W1).

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
   cheaper than division** (the NTT regime). Re-measured after T-M1/T-M2: at
   100 000 digits B-Z divides in 9.2 ms against 3.4 ms for the same-size
   multiply — still 2.7×, the ratio has not moved. A reciprocal-Newton rewrite
   would be a wash. Neither Toom-3 nor Comba unblocks it; NTT would.

10. **A fast quadratic kernel moves the crossovers a long way, so re-tune
    them together.** After T-M2 the old `CUTOFF_KARATSUBA = 48` cost 27% at
    11 000 words: schoolbook was still winning at 256 words against a
    Karatsuba whose leaves were capped at 48. Any change to the base case
    invalidates every cutoff above it.

## 5. Open Items

> Ranked by urgency in `docs/internal/todo.md`. This section holds the
> detail, not the ordering.

Worked in priority order. There is one real outlier, floor_divide; the
rest are smaller. The limb-width question sits at the end, because the
benchmark shows it is not why decimo trails today.

### floor_divide / truncate_divide — the outlier (3.9× py, 5.6× rs)

floor_divide is the only op that trails badly. add and multiply are within
1.2–1.5×, but divide is 3.9× Python and 5.6× Rust. Two facts rule out the
easy explanations:

- It is not the algorithm. decimo and num-bigint both run Knuth Algorithm D
  below the Burnikel-Ziegler cutoff (64 words).
- It is not the limb width. Python's `int` uses base-2^30 limbs, narrower
  than decimo's base-2^32, and still divides 3.9× faster. A wider limb
  would help Python, not decimo.

The cause is decimo's per-call overhead on small and medium operands. A
small divide such as `-7 // 2` does three or four heap allocations in
decimo and almost none in Python or Rust:

- `floor_divide` copies the quotient and remainder out of the divmod tuple
  with `.copy()`, two allocations it does not need, then allocates a third
  time through `_add_magnitudes(q, 1)` on the negative-floor branch.
- `_divmod_magnitudes` normalises both operands with `_shift_left_words` on
  every multi-word call, two more allocations, even when the operands are
  tiny.
- The Knuth-D inner loop recomputes `len(u)` and re-checks `idx < len(u)`
  on every step and takes a branchy manual borrow. num-bigint walks a slice
  with a branchless offset-carry.

**T-D1 — remove the redundant allocations.** Move the quotient and
remainder out of the divmod tuple instead of copying them. Increment in
place on the negative-floor branch. Fold the Knuth-D normalisation shift
into the base case so it stops allocating two fresh buffers per call.

**T-D2 — tighten the inner loop.** Hoist `len(u)` and the `u`/`v` data
pointers out of the multiply-subtract loop (Lesson 7, two buffers) and
replace the manual borrow with num-bigint's branchless offset-carry.

**T-D3 — re-tune `CUTOFF_BURNIKEL_ZIEGLER`.** Re-measure 32/48/64 once the
base case is cheaper. The 2n-by-n / 4n-by-n / 8n-by-n slowdown already
noted for `BigUInt` in `todo.md` may share this root and should be checked
together.

**T-D4 — reciprocal / Barrett divide. Deferred.** Not worth it before
Toom-3 (Lesson 9).

### to_string, 50–1000 digits (3.4× py)

The 1- and 2-word fast paths and the D&C path above 128 words are done. The
50–1000-digit band still runs the O(n²) simple path of repeated division by
10^9, with the `InlineArray` chunked emit already in place.

**T-T1 — lower the D&C entry threshold** once divide is cheaper (D&C is
gated on divide cost). Re-measure entry = 64 / 96.

**T-T2 — wider radix per chunk.** Batching the repeated `/10^9` into a
larger radix only helps if it avoids the software-emulated 128-bit divide.
PR4d rejected 10^18 chunks for exactly this reason; re-verify on current
hardware before trying again.

### multiply — T-M5 (NTT) done (2026-08-25)

**T-M6 — the transform is now shared with `BigUInt`. DONE (2026-08-26).**
`biguint/ntt.mojo` multiplies base-10^18 magnitudes with the same field
arithmetic, twiddle tables and transforms. Those work on residues and do not
depend on the base, so they lost their leading underscore and are imported
rather than duplicated; only the packing differs, because a base-billion
magnitude is not a bit string. See the BigDecimal plan, H#26.

**T-M5 — number-theoretic transform. DONE.** `bigint/ntt.mojo`, over the
Goldilocks prime `2^64 - 2^32 + 1`: one prime, no CRT, and reduction of a
128-bit product in a shift, a subtract and two conditional fixups. Against the
Toom-3 path it displaces:

| words   | Toom-3   | NTT      | speedup |
| ------- | -------- | -------- | ------- |
| 3 072   | 267 µs   | 244 µs   | 1.09    |
| 6 144   | 735      | 574      | 1.28    |
| 10 400  | 1 746    | 1 201    | 1.45    |
| 20 000  | 4 755    | 2 388    | 1.99    |
| 65 536  | 25 424   | 11 477   | 2.22    |
| 104 200 | 54 748   | 24 030   | 2.28    |

Two design points carried most of the win, and neither is the transform.

*The chunk width is a free variable, not 16 bits.* A magnitude is a bit string;
nothing forces the transform to see it in half-words. Since the transform
length must be a power of two, a fixed width leaves the rounding-up as pure
waste — at 10 400 words a 16-bit cut needs 41 599 coefficients and so a
transform of 65 536, where 25 bits needs 26 623 and fits in 32 768. Letting the
width float subject to the modulus bound (the planner lands on 22-26 bits)
recovers that 2× wherever the fixed width overshoots and costs nothing where it
does not.

*The dispatch cannot be a word count.* The transform's cost steps at powers of
two while Toom-3's climbs smoothly, so the winner alternates: at a quarter of
the transform slots filled the transform loses at 4 096 words, ties at 8 192
and wins from 16 384 up. `should_multiply_ntt()` compares the two fitted cost
models — `L log2(L)` against `(len_a * len_b)^0.7325` — which predicts every
measured crossover from 512 to 104 200 words. No flat cutoff can.

One trap worth remembering: `_multiply_magnitudes_slices()` is a *second*
dispatcher, and Burnikel-Ziegler reaches its multiplications only through it.
Wiring the transform into `_multiply_magnitudes()` alone left division and
base conversion entirely on Toom-3, and the division benchmark barely moved
until both were done.

### multiply — T-M1 done (2026-08-24)

**T-M1 — Toom-3 multiplication. DONE.** `_multiply_magnitudes_toom3()`,
points `0 / 1 / -1 / 2 / inf`, one sign flag per operand for `a(-1)` and
`b(-1)` (every other intermediate is non-negative, so the unsigned in-place
subtractions hold). Against the Karatsuba path:

| words | Karatsuba | Toom-3 | speedup |
| ----- | --------- | ------ | ------- |
| 300   | 24 µs     | 27 µs  | 0.89    |
| 400   | 45        | 40     | 1.15    |
| 5 000 | 2 460     | 1 950  | 1.26    |
| 22 000| 28 300    | 18 700 | 1.51    |

`CUTOFF_TOOM3 = 384`. The crossover is soft, not sharp — Toom-3 loses a few
percent from ~260 to ~320 words — and 384 is just above that band.

With T-M2 and T-M3 on top, `BigInt` is ahead of CPython `int` on every large
op. At 100 000 decimal digits (decimo / CPython, ms):

| op           | decimo | CPython | ratio |
| ------------ | ------ | ------- | ----- |
| multiply     |   3.44 |    9.37 | 2.7×  |
| floor_divide |   9.20 |   19.35 | 2.1×  |
| to_string    |  13.12 |   18.56 | 1.4×  |
| from_string  |   5.07 |    9.32 | 1.8×  |

At 1 000 digits multiply is 2.9× and divide is at parity; `to_string` and
`from_string` are still behind below ~10 000 digits (T-T1, T-F1).

**T-M2 — product-scanning schoolbook base case. DONE (2026-08-24).** Not the
SIMD form originally planned. The old kernel was operand-scanning: it read and
wrote the result array on every one of the `n_x · n_y` partial products and
carried serially along each row. Comba walks the result one word at a time and
sums the whole column `sum(a[i]·b[k-i])` in a `UInt128` before emitting a word,
so the column stays in registers and there is no carry chain. Unrolled over
four accumulators, because one serialises on the 128-bit add.

| words | operand-scanning | Comba ×1 | Comba ×4 |
| ----- | ---------------- | -------- | -------- |
| 8     | 71 ns            | 57       | 57       |
| 16    | 154              | 114      | 108      |
| 48    | 1 074            | 701      | 520      |
| 64    | 1 989            | 1 298    | 848      |

**T-M3 — re-tune the cutoffs. DONE (2026-08-24).** A quadratic kernel at well
under a cycle per partial product moves both crossovers a long way up:
`CUTOFF_KARATSUBA` 48 → 128, `CUTOFF_TOOM3` 384 → 512. At 11 000 words the
dispatcher went 4 754 → 3 743 µs on the cutoffs alone. T-M4 moved them again,
to 256 / 768.

**T-M4 — 64-bit limbs in the base case. DONE (2026-08-24).** T-M2 left the
kernel at 0.19 ns per word pair, about 0.85 cycles — there was nothing left to
win per pair, only in the number of pairs. So the base case now packs both
operands into base-2^64 limbs, quartering the pairs, and writes each result
limb straight back out as two words. Below `CUTOFF_PACK_64 = 32` words the
packing costs more than it saves and `_multiply_magnitudes_comba32()` runs
instead.

A column of 64-bit products overflows 128 bits, and a three-word accumulator
with a carry chain gives most of the gain back. Splitting each product at the
word boundary into two `UInt128` accumulators avoids that: each half is below
`2^64`, so neither overflows until a column is `2^64` limbs long, and on arm64
`mul`/`umulh` deliver the two halves already separated.

| words | Comba ×4 (T-M2) | packed 64-bit |
| ----- | --------------- | ------------- |
| 38    | 387 ns          | 270           |
| 75    | 1 230           | 676           |
| 113   | 2 530           | 1 320         |
| 182   | 6 630           | 3 400         |

A 100 000-digit multiply went 3.44 → 2.30 ms, and `pi(100000)` 78 → 55 ms.
GMP does the same multiply in 0.39 ms, so it is still 5.9× ahead. Measuring
its exponent across sizes splits that gap: GMP moves to FFT at ~1 600 limbs
(≈32 000 digits), which is worth 3.7× to it at 100 000 digits, leaving only
1.6× for base case, glue and assembly. See `internal/internal_notes.md`.

Watch out for Mojo's ASAP destruction here: the packed operands are only
touched through raw pointers, so without an explicit `_ = limbs_a^` the
compiler destroys them at the point the pointer is taken and the loop reads
freed memory. That is a silent heap corruption, not a crash at the fault.

### power (2.1× py) and add (1.5× py)

**T-P1 — power inner loop.** General (non-2^N) power pays for a fresh
temporary on every multiply. Route the loop through `multiply_inplace` and
add a dedicated `square()` that exploits symmetry, roughly half the partial
products. The 2^N shift fast path is already excellent; Rust loses to it.

**T-A1 — add/sub dispatch. DONE 2026-08-25.** The same-sign case now comes
first, and the mixed-sign cases no longer route through `subtract(x1, -x2)` /
`add(x1, -x2)`: negating an operand copied its whole magnitude before the
kernel ever ran.

**T-A2 — 64-bit limb pairs in the add/sub kernels. DONE 2026-08-25.** The
words are little-endian, so a pair of them is already a base-2^64 limb: one
64-bit add does the work of two 32-bit ones, and the carry out is the unsigned
overflow of that add, recovered by a comparison instead of a shift-and-mask.
`_add_word_pairs()` and `_subtract_word_pairs()` load with `alignment=4`, so
the two operands and the destination may each start at any word offset — which
is what lets the Karatsuba and Toom-3 helpers, whose slices start anywhere,
share the kernel. All six loops use it: the two out-of-place magnitude
operations, the two in-place ones, `_add_slices()` and
`_add_at_offset_inplace()`.

0.71 → 0.25 ns/word (about 3.2 → 1.1 cycles), flat from 1 000 to 100 000
words. The recursions are add/sub-heavy at every level and inherit most of it:
multiply 1.26× and divide 1.22× at 10 400 words, `pi(100000)` 44.2 → 36.1 ms.

**T-A4 — exact divide-by-3 off the carry chain. DONE 2026-08-25.** Found by
listing every `O(n)` helper's ns/word and looking for the outlier:
`_exact_divide_by_3_inplace()` was 2.03 against 0.23-0.25 for its neighbours,
because `//3` and `%3` both lower to multiply-high and both sat on the
loop-carried chain.

`2^32 = 3T + 1` with `T = 0x5555_5555`, so writing `word = 3d + m`:

    quotient      = remainder * T + d + (remainder + m >= 3)
    new remainder = (remainder + m) mod 3

`d` and `m` depend only on `word`, so the surviving division is off the chain;
what stays on it is an add and a reduction of a value below five. 2.03 → 1.17
ns/word. `BigUInt` uses the same identity — `10^9` is also `1 mod 3` — and goes
2.50 → 1.13.

Worth having, but small: Toom-3 calls it once per node, so it is about 4% of a
large multiply and the ~2% it returns is at the edge of the benchmark's noise.
The remaining carry-select candidates in the codebase are all this size or
smaller — the carry domain has to be tiny to enumerate, and multiply, division
and base conversion all carry full-width values.

### from_string and shift

**T-F1 — from_string base conversion.** The 50–10000-digit band runs an
O(n²) base-10 → base-2^32 conversion. Lower the D&C entry threshold once
multiply is faster; the 20000-digit-and-up gap only closes with Toom-3
(T-M1).

**T-SH1 — shift allocation.** Extreme shifts such as `1 << 100000` are
allocation-bound. Pre-size the result buffer with
`resize(unsafe_uninit_length=…)` (O(1) capacity plus memset) instead of
letting it grow.

### Base-2^64 limbs (done 2026-08-27, #286; the survey that led to it)

num-bigint stores base-2^64 limbs on 64-bit targets; decimo stores
base-2^32. For the same number num-bigint holds half the limbs, so its
schoolbook multiply and Knuth-D base case run over half the words. This is
worth keeping in mind for the large-operand multiply and from_string cases.

It is not why decimo trails today, and I want to be clear about that. sqrt
is multiply- and divide-heavy yet already sits at parity with Rust (1.0×),
and Python beats decimo at divide with even narrower limbs. So I treat a
wider limb as a later, large bet, and only after the per-call overhead
above is gone.

Feasibility (probed 2026-06-19, Mojo v1.0.0b1). The Rust `cfg_digit!` idea
ports. Mojo rejects a ternary on the types themselves
(`UInt64 if is_64bit() else UInt32`), but a ternary on `DType` values is
accepted, so one comptime block selects the limb per target:

```mojo
comptime BASE_DT: DType = DType.uint64 if is_64bit() else DType.uint32
comptime DOUBLE_DT: DType = DType.uint128 if is_64bit() else DType.uint64
comptime BigBase = Scalar[BASE_DT]          # UInt64 on 64-bit
comptime DoubleBigBase = Scalar[DOUBLE_DT]  # UInt128 on 64-bit
comptime BITS: Int = 64 if is_64bit() else 32
```

`UInt128` `*`, `//`, `%`, `>>`, `&` all compute correctly; the `u128 ÷ u64`
divide is software-emulated on arm64 but gives the right answer, same as
num-bigint. The aliasing is trivial. The migration is not: base-2^32 is
hard-coded across `src/decimo/bigint/` — the `List[UInt32]` field and every
signature, the `1 << 32` / `0xFFFF_FFFF` / `>> 32` literals, the 4×UInt32
NEON width, `_count_leading_zeros`, the base-10 ↔ base-2^k chunking in
`from_string` / `to_string` (9 vs 19 digits per limb, the hard part), and
`BigInt10` bit-layout interop. One place actually gets *simpler*:
`from_integral_scalar` today branches per input dtype
(uint8/16/32/64/128/256, signed variants) only because the word extraction
is hard-coded to 32 bits. With a `BITS`-parametric limb it collapses to one
generic peel loop over `N_LIMBS = ceil(bitwidthof(dtype) / BITS)`,
`@parameter for`-unrolled, that works for any input dtype and either limb
width. The one care point is the input-width == limb-width boundary (e.g.
a `UInt64` input with 64-bit limbs): guard the mask with `~0` and skip the
final `>> BITS` so it never shifts by the full width, and take the
magnitude via an unsigned negate so `Int.MIN` does not overflow. Probed
2026-06-19: the loop compiles and gives correct limbs for `u8`, `u64`,
`u128`, and negative `i64` at both `BITS = 32` and `BITS = 64`. If I do the
migration, I will first introduce `BigBase` / `DoubleBigBase` / `BITS` /
`BASE` / `MASK` and replace every literal while keeping the limb at uint32,
a pure and testable refactor with no behaviour change, then flip to uint64
and fix the base-conversion and SIMD fallout behind the test suite.

**T-W1 — base-2^64 limbs. Open, low priority, unproven.**

### Plan

| Label | Item                                               | Status                                 |
| ----- | -------------------------------------------------- | -------------------------------------- |
| T-D1  | Remove redundant `.copy()` /                       | OPEN — the floor_divide outlier (P0)   |
|       | normalise allocs in divide                         |                                        |
| T-D2  | Hoist Knuth-D inner loop;                          | OPEN — Lesson 7 (two buffers)          |
|       | branchless offset-carry                            |                                        |
| T-D3  | Re-tune `CUTOFF_BURNIKEL_ZIEGLER`                  | OPEN — pair with the BigUInt todo      |
| T-T1  | Lower to_string D&C entry threshold                | OPEN — after T-D1 / T-D2               |
| T-M1  | Toom-3 multiply above 384 words                    | DONE 2026-08-24                        |
| T-M2  | Product-scanning (Comba) schoolbook base case      | DONE 2026-08-24 — ~2× at the cutoff    |
| T-M3  | Re-tune `CUTOFF_KARATSUBA` / `CUTOFF_TOOM3`        | DONE 2026-08-24 — 48→128→256, →768     |
| T-M4  | Pack the base case into base-2^64 limbs            | DONE 2026-08-24 — 1.9× at the cutoff   |
| T-P1  | `square()` plus inplace loop for power             | OPEN                                   |
| T-A1  | add/sub dispatch reorder                           | DONE 2026-08-25                        |
| T-A2  | 64-bit limb pairs in the add/sub kernels           | DONE 2026-08-25 — 2.8× at every size   |
| T-A4  | Exact divide-by-3 off the carry chain              | DONE 2026-08-25 — 1.7×, but ~2% of mul |
| T-SH1 | Pre-size the shift result buffer                   | OPEN                                   |
| T-W1  | Base-2^64 limbs throughout                         | PARTLY — T-M4 does it in the kernel    |
| T-E1  | `reciprocal_sqrt_fixed_point()` binary recip. sqrt | DONE 2026-08-24 — enables T-PI4        |
| T-M5  | NTT multiply over `2^64 - 2^32 + 1`                | DONE 2026-08-25 — 2.3× at 104 200w     |
| T-M6  | Share the transform with base-10^9                 | DONE 2026-08-26 — `biguint/ntt.mojo`   |
| T-D4  | Reciprocal-Newton divide                           | NEXT — NTT landed; B-Z now 4.9× mul    |
