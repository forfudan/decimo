# TODO

The one ranked list of what to do next. Everything else points here: the
enhancement plans in `docs/plans/` carry the detail and the reasoning, and
`internal_notes.md` carries the measurements, but neither keeps its own
ranking. There were four such lists in August 2026 and they had already
drifted apart, so there is now one.

Last reviewed 2026-08-28 (sixth pass).

## Goal, round one: met (20260826)

Beat libmpdec on every operation at 1000 digits. Measured side by side in one
`benchdoc` run at 06bafb7:

| operation | decimo   | libmpdec |                  |
| --------- | -------- | -------- | ---------------- |
| add       | 83.5 ns  | 113.2 ns | **1.36x faster** |
| subtract  | 87.4 ns  | 88.8 ns  | parity           |
| multiply  | 2.81 us  | 8.94 us  | **3.18x faster** |
| divide    | 13.86 us | 14.38 us | parity           |
| round     | 82.0 ns  | 97.7 ns  | **1.19x faster** |
| parse     | 1.10 us  | 1.41 us  | **1.28x faster** |

Nothing is slower. Divide started the day 1.68x behind and add 1.12x behind.
Three changes did it, and all three carried to the larger sizes as well:

1. The add and subtract word kernels vectorized a block at a time.
2. Knuth D's multiply-subtract taken off its carry chain, 2.9x on schoolbook
   division.
3. The Burnikel-Ziegler base case taking the remainder schoolbook already had,
   instead of rebuilding it with a multiply.

Both cutoffs were re-swept after each of those, because a cheaper base case
moves every crossover above it. That happened three times in one day.

## Goal, round two: met for everything but division (20260827)

Be no more than 1.2x of CPython's `decimal` from Python at 28 digits, now
that `BigUInt` keeps small values inline. Measured with
`python/benchmarks/compare.py`, which runs the same source file under both:

| operation  | decimo | decimal |                  |
| ---------- | ------ | ------- | ---------------- |
| `a + b`    | 45.8   | 42.7    | 1.07x            |
| `a * b`    | 52.8   | 47.3    | 1.12x            |
| `a / b`    | 138.8  | 100.3   | 1.38x            |
| `a < b`    | 21.9   | 18.8    | 1.16x            |
| `a + 2`    | 57.2   | 65.6    | **1.15x faster** |
| `quantize` | 42.6   | 61.8    | **1.45x faster** |

At 9 digits: add 1.06x, subtract 1.17x, multiply 1.09x, divide 1.24x.

Whole programs: compound interest **1.12x faster**, sqrt by Newton at parity,
e from its series 1.17x, pi by Machin 1.30x, and 1000-digit arithmetic 1.59x
faster. The day started at 4.8x on the four operators and 4.1x on compound
interest.

Against libmpdec directly, without the Python call in the way, decimo is now
faster at **every operation at 1000 digits** and 3.4x faster at addition at 9.
See `docs/benchmarks.md`.

Division is the one left outside the bar, and it is item 1 below.

## Goal, round three: `BigInt` against GMP (20260827)

`BigInt` had only ever been measured against CPython's `int`, which is not an
opponent: it is reached through the interpreter, so it loses on call overhead
before the arithmetic starts. Against GMP, timed in C, GMP wins most rows.
Ratios, decimo against GMP, bold where decimo is ahead (20260827, after the
Knuth D work):

| digits | add       | multiply  | floor divide | sqrt      |
| ------ | --------- | --------- | ------------ | --------- |
| 10     | **3.98x** | **2.41x** | **1.82x**    | **5.65x** |
| 100    | **2.39x** | 2.35x     | 2.46x        | 2.04x     |
| 1 000  | 1.86x     | 1.75x     | 1.52x        | 5.96x     |
| 10 000 | 2.27x     | 2.63x     | 2.00x        | 3.33x     |
| 10^6   | 2.08x     | 4.25x     | 6.77x        | 5.77x     |

The small end is ours only since inline storage: an `mpz_t` always goes to the
heap, and 10 of GMP's 14.6 ns at a hundred digits is `malloc` and `free`. An
immutable value type cannot use GMP's reuse idiom, so this is the one place
where the shape of the API works for us.

### How much of this was the 32-bit limb? (answered 20260828)

The model said a 64-bit limb halves the limb count but pays two instructions
per product (`MUL` plus `UMULH`) where a 32-bit one pays one, so for work
growing as `L^e` the penalty is `2^e * (1/2) = 2^(e-1)`: 2.0x for schoolbook
and Knuth D, 1.50x for Karatsuba, 1.38x for Toom-3, ~1.0x for the transform.
Addition was excluded, because the kernels already read two words as one
base-2^64 limb.

Measured, after moving the magnitude to base 2^64:

| operation      | predicted | measured |
| -------------- | --------- | -------- |
| add            | 1.0x      | 1.0-1.1x |
| multiply, 1000 | 1.5x      | 1.18x    |
| divide, 1000   | 2.0x      | 1.86x    |
| divide, 10     | 2.0x      | 1.99x    |
| multiply, 10^6 | ~1.0x     | 1.04x    |

The prediction held at the ends and was optimistic in the middle, where the
cutoffs moved: Karatsuba and Toom-3 both start sooner in *digits* than they
did, so a thousand-digit multiply is no longer the same algorithm it was.
Division is the row that got what was promised, and it is also the row that
had the most to gain. What is left:

| operation      | against GMP | was   |
| -------------- | ----------- | ----- |
| add, 10^6      | 2.08x       | 2.00x |
| multiply, 100  | 2.35x       | 2.66x |
| multiply, 10^6 | 4.25x       | 3.90x |
| divide, 100    | 2.46x       | 3.01x |
| divide, 1000   | 1.52x       | 2.87x |
| divide, 10^6   | 6.77x       | 7.00x |
| sqrt, 1000     | 5.96x       | 8.14x |

There is no limb-width excuse left in any of these. The 10^6 rows never had
one -- a transform packs bits into coefficients and barely cares what the
limbs were -- and the smaller ones have spent theirs.

### Division and sqrt are not separate problems

Both decompose into multiplication. Measure each library's division against
*its own* multiplication and the gap splits cleanly in two:

|            | our mul | GMP mul | ratio | our div/mul | GMP div/mul | div gap |
| ---------- | ------- | ------- | ----- | ----------- | ----------- | ------- |
| 1 000      | 1.20 us | 608 ns  | 1.97x | 2.9x        | 2.0x        | 2.9x    |
| 10^6       | 24.4 ms | 6.25 ms | 3.90x | 4.7x        | 2.6x        | 7.0x    |

The gap is our multiplication being slow, times our division not being
multiplication-bound. At 1000 digits the second factor is now only 1.45x and
the first is the whole story; at 10^6 both are. Neither needs a new division
algorithm: Barrett would cost about `4 * M(n)`, which is what we already pay.

`sqrt` sits on top of the same stack, so it can never get ahead of the
division underneath it. Its three levels at 1000 digits, timed separately:

    level      division    squaring
    m = 104     1199 ns      224 ns
    m =  52      450 ns       96 ns
    m =  26      245 ns       22 ns

which is 2.24 us of the 2.94 the whole `sqrt` takes. The bottom levels do not
shrink the way the recursion says they should -- level 26's division is 0.54
of level 52's, not 0.25 -- because a division carries about 137 ns of fixed
cost whatever its size, and at a 26-word divisor that is most of it.

Ordered by what actually moves:

1. **Both the divisions and the fixed cost, done (20260827).** The diagnosis
   below was wrong and is kept for the correction: the cost was never
   Burnikel-Ziegler's per-level overhead, it was the Knuth D base case at the
   bottom of it. Measured at 500 digits, where the whole division is one Knuth
   D call, it took 2.50 us against 0.42 for the 52x52 schoolbook multiply
   underneath it -- the same number of word products at six times the price,
   3.3 cycles a word against 0.55. The multiply-subtract now runs two words at
   a time, and the remainder is unnormalized in the buffer it is already in
   rather than into a fifth allocation. Division is 1.2x to 2x faster, `sqrt`
   1.0x to 1.4x, and both cutoffs above the base case moved
   (`CUTOFF_BURNIKEL_ZIEGLER` 64 -> 96, `_sqrtrem()`'s base 32 -> 16).

   ~~**Burnikel-Ziegler's per-level cost.** Our division costs 5.2 of its own
   multiplications where GMP's costs 2.0. The recursion is not too shallow:
   cutoffs of 8, 16 and 24 words are all *worse* than 64, so each level is
   paying too much -- allocations, `_shift_left_words_inplace`,
   `_add_at_offset_inplace` and a fresh result out of
   `_multiply_magnitudes_slices` every call.~~ Those cutoffs were worse
   because a smaller block means a smaller base case, and the base case was
   the thing that was slow. With it fixed, the cutoff moved *up*.

   It is now 2.9 of its own multiplications at 1000 digits against GMP's 2.0,
   and the Knuth D loop is within about 1.4x of what a 32-bit limb allows.
   The limb width was the rest of it, and that is done too (20260828): the
   magnitude is base 2^64 now, which halved the quotient word count and with
   it the estimate and the loop entry every quotient word pays. Division at a
   thousand digits went 2.87x of GMP to 1.52x, and at ten digits it is 1.82x
   *faster* than GMP. `sqrt` followed to 5.96x, still the worst row.
2. **The NTT butterfly**, where the honest answer is that we are close to
   the floor for the transform we chose, and GMP is winning by choosing a
   different one. 4x on multiplication at 10^6, with no limb-width
   excuse -- a transform packs bits, not limbs -- and division and `sqrt`
   inherit all of it. But the butterfly is already 5 cycles, and 94% of the
   multiplication is the three transforms (14.0 ms forward, 7.6 ms inverse,
   1.4 ms for everything else at 10^6). Two things measured neutral there and
   are not to be retried: branchless `mod_add`/`mod_sub`, which the compiler
   already emits as `CSEL`, and there is no cheap win in the packing or the
   pointwise product. What is left is radix-4 and Shoup twiddles, worth maybe
   1.7x to 2x together -- not 4x. GMP is ahead here because Schonhage-Strassen
   multiplies by a root of unity with a bit shift, where we do a modular
   multiply. See item 7 of `Now`, which wants the same thing for `pi()`.

   Measured facts about the butterfly, so the next attempt starts from them:

   - It costs about 4.7 cycles for roughly 21 operations, which is an IPC of
     4.5 on an 8-wide core. There is no stall to remove.
   - It is *not* memory-bound. 2^15 costs 1.29 ns a butterfly and 2^19 costs
     1.40, a 9% spread over 16x the working set, so radix-4's halving of the
     passes buys little. What it does buy is a quarter of the multiplies,
     because for this prime `2^96 = -1`, so the fourth root of unity is
     `2^48` and multiplying by it is a shift. Worth perhaps 1.2x to 1.3x.
   - **Shoup twiddles do not work here and must not be tried again.** The
     factor itself is cheap despite needing `floor(w * 2^64 / P)`: since
     `2^64 = P + (2^32 - 1)` the quotient folds into 64-bit steps, verified
     exact over 200 010 values. But Shoup's remainder lives in `[0, 2P)`, and
     with `P` this close to `2^64` that overflows a `UInt64` in 25% of cases,
     measured. The trick needs `P < 2^63`.

   Which leaves lazy reduction -- keeping residues in `[0, 2^64)` and
   canonicalizing rarely -- as the only cheap idea left, worth maybe 1.15x,
   and Schonhage-Strassen as the only one that would actually close the gap.
3. **Break the carry chain in add and subtract.** We are latency-bound on it,
   not throughput-bound: 1038 words at 10 000 digits is 519 limbs and 271 ns,
   which is 1.8 cycles a limb, where GMP's `ADCS` chain runs at 1.0. Widen the
   words into 64-bit SIMD lanes to manufacture the slack that base 10^9 gives
   `BigUInt` for free, sum ignoring carry, then propagate. A lane only
   propagates when its digit is all ones, so the second pass can be a mask
   test that almost never fires rather than `BigUInt`'s serial walk.
4. **Multiplication thresholds.** `CUTOFF_KARATSUBA` is 256 words, which is
   2466 decimal digits; GMP switches around 500. Our Comba is good enough that
   schoolbook at 104 words is only 1.91x of GMP's Karatsuba, so this is worth
   measuring rather than assuming.

`math.sqrt` on an integer is a trap. It resolves to a software integer
square root, not the hardware instruction: 21.3 ns against 0.45 ns for
`math.sqrt(Float64(...))`, measured with a varying operand. Five places asked
for it that way. `decimo.utility.isqrt_uint64()` is now the one place that
answers the question -- it takes the float root and corrects it -- and small
`BigUInt.sqrt()` went from 10.8 ns to 2.2 at one word and 26.4 to 2.1 at two.
Correcting is not optional: `Float64` carries 53 bits, and for a value just
under `2^64` it rounds up to `2^64`, whose root does not fit the answer.

Benchmarks that reuse one operand cannot see any of this. A pure function of
a loop-invariant value gets hoisted out of the timing loop, and once the
correcting walks were provably bounded that is exactly what happened -- small
`BigUInt.sqrt()` read 0.225 ns, which is nothing at all. Vary the operand,
and sink something value-dependent rather than a sign that is always false.

Three things measured the wrong way round here, so they are not retried:

- **Dropping the `UInt128` phase of `_sqrt_precision_doubling_fast()`.** A
  128-bit divide is a software helper, and item 8 of `Now` says to hunt those
  down -- but here it still beats the word-list path it would fall back to.
  100-digit `sqrt` goes from 155 ns to 204 without it.

- **A branchless borrow in Knuth D.** Biasing by 2^32 and reading the borrow
  out of bit 32 puts the loaded word in the loop-carried carry chain. The
  branch is worth 1.38x at 1000 digits.
- **A `UInt128` accumulator for the paired add and subtract.** It does not
  become `ADDS`/`ADCS`; add at 10 000 digits went 279 ns to 391, subtract 275
  to 503. The comparison-based carry that is there is the fast one.
- **A precomputed reciprocal for Knuth D's quotient estimate.** Moller and
  Granlund's `udiv_qrnnd_preinv`, replacing the 64-by-32 `UDIV` with one
  multiply and two corrections. Slower at every size, two alternating builds
  each way: 27 ns against 35 at 10 digits, 3.4 us against 3.7 at 1000.
  arm64's `UDIV` is cheaper than what it takes to avoid it.

  **This holds only while the limb is 32 bits**, and the reason is the whole
  of it: 64-by-32 is one hardware instruction. A 64-bit limb needs 128-by-64,
  which no arm64 or x86-64 instruction does, so the compiler emits a software
  helper -- and there the reciprocal stops being an optimization and becomes
  the only way to estimate a quotient digit. Do not read this entry as an
  argument against it in that setting.

## Now

Ordered by value. Three things are still behind CPython's `decimal`, and
they are the first three.

1. **`divide`, 1.24x at 9 digits and 1.38x at 28.** The only operator still
   outside 1.2x. 138.8 ns against 100.3, of which ~109 is Mojo and ~30 the
   call. Inside the Mojo half: 4.6 ns padding, 15.7 normalizing, ~60 in
   Knuth D over five quotient words, ~15 rounding and construction. Four
   things were tried and did not help -- calling Knuth D without the second
   dispatch (neutral; the compiler had already inlined it), padding by digits
   instead of whole words (worse, because `multiply_by_power_of_base` only
   prepends zero words while `multiply_by_power_of_ten` walks the number),
   hoisting the estimator's invariants (neutral), and raising the inline
   capacity past ten (no gain). What is left is either Newton reciprocal
   division or base 10^18.
2. **`subtract` at 1000 digits and above, 1.11x to 1.32x slower than
   CPython's `decimal`**, where `add` at the same sizes is 1.18x to 1.73x
   *faster*. The only operation still behind at any size against `decimal`,
   together with `round`. Isolated to the
   kernels: `_add_words_vectorized` runs 100 000 digits in ~3.9 us and
   `_subtract_words_vectorized` in ~4.6-5.1 us, from code that looks
   symmetric instruction for instruction. Flattening subtract's carry walk to
   match add's measured neutral inside a ~10% noise band. Not yet explained.
3. **`round` at 100 000 and 10^6, 1.11x and 1.33x slower.** Improved once
   today by taking the pointer out of two shift loops; whatever is left is
   elsewhere.
4. **`parse`, 1.37x slower than libmpdec at 9 digits** (was 2.65x). What
   remains is the digit list: `parse_numeric_string()` returns one `UInt8`
   per digit, so a 9-digit number is allocated for and walked twice before
   any packing happens. Parsing straight from the string into words would
   remove both.
5. **Newton reciprocal division**, worth ~115 ms of `pi(10^6)` as well as
   item 1. See `bigint_enhancement.md` T-D4.
6. **`subtract_inplace()`** builds a negated copy of its right operand to flip
   a sign: `x -= y` is 5.2x slower than libmpdec in place, where `x += y` is
   1.3x *faster*. See `bigdecimal_enhancement.md` H#21.
7. **A cheaper NTT butterfly** -- precomputed (Shoup) twiddles and radix-4.
   Needed for goal 1: `pi(10^6)` at 1.2x of mpmath+GMP wants roughly 2.5x here
   on top of item 5.
8. **Audit the remaining `UInt128` and `UInt256` uses.** Three of the day's
   biggest wins were removing one. The rule: 128-bit as an *accumulator* is
   fine, because a 64x64 multiply is one instruction; 128-bit or 256-bit as
   the *left side of a divide by a variable* is a call to a software helper,
   20-40 ns. Known remaining: `decimal128/`, `rational/`,
   `bigint/exponential.mojo`.

   **A constant divisor is not in that class** (20260828). LLVM expands
   `UInt128 // <constant>` into multiply-high, so the `% BASE` and `// BASE`
   in the wide Comba path are not calls. Marginal cost measured against an
   empty loop, arm64:

   | operation                                      | ns   |
   | ---------------------------------------------- | ---- |
   | `UInt64 // 10^9`, constant                     | 0.06 |
   | `UInt128 // 10^9`, constant                    | 0.32 |
   | `UInt128 // 10^18`, constant                   | 0.40 |
   | `UInt128 // 10^18`, Moller-Granlund reciprocal | 0.50 |

   The hand-rolled reciprocal is *slower* than what the compiler emits for a
   constant. Reach for it only when the divisor is a runtime value.
9. **Base 10^18 for `BigUInt`.** The honest answer to "why is division still
   behind": for a 28-digit value libmpdec holds two words and decimo holds
   four, so every loop runs twice as long. Nothing above closes that.

   `BigInt` answered the same question for itself on 20260828 by moving to
   base 2^64, and what that cost is now known rather than guessed. The
   arithmetic was the easy half; the traps were all in code the type checker
   was happy with. In order of how long each took to find: a decimal chunk
   base that had to stay a power of `10^9` because `to_biguint()` reads the
   chunks as `BigUInt` words; `String(Int(word))` printing every value at or
   above `2^63` as negative; a borrow taken from the sign bit of a widened
   subtraction, which a word of exactly `2^63` sets with no borrow at all; a
   `>>= 64` that is a no-op on arm64 and so an infinite allocating loop; and
   Toom-3's exact division by three carrying `(2^32 - 1) / 3`.

   `BigUInt` is a smaller job -- base 10^18 is still a decimal base, so the
   conversion paths do not move -- but every partial product needs 128-bit
   accumulation.

   **Measured on a prototype (20260828), and it is worth doing.** The two
   bases written the same way, same digit count, results cross-checked
   against each other. Ratios are 10^9 over 10^18, so above 1.00 means the
   wider word wins:

   | digits | add   | Comba multiply | Knuth D multiply-subtract |
   | ------ | ----- | -------------- | ------------------------- |
   | 18     | 1.26x | 0.52x          | 0.71x                     |
   | 36     | 1.19x | 0.94x          | 1.46x                     |
   | 72-90  | 1.43x | 1.24x          | 1.58x                     |
   | 288    | 1.15x | 2.41x          | 1.66x                     |
   | 1 000  | 1.49x | 2.59x          | 1.67x                     |
   | 9 000  | 1.48x | ~3.0x          | 1.69x                     |
   | 10^6   | 1.10x | (transform)    | --                        |

   Three things the numbers say that the model did not. Multiply passes 2x
   and keeps going, because base 10^9's wide path pays a 128-bit *add* per
   partial product and there are four times as many of them. Add gains from
   the second pass of `_add_words_vectorized`, which walks every word
   serially and so halves; the SIMD pass moves the same bytes either way, and
   at 10^6 the whole thing is memory-bound and the gain falls to 1.10x. And
   the wider word *loses* below about 36 digits, where the existing narrow
   `UInt64` column path is strong and base 10^18 has no equivalent -- a
   partial product is `10^36` and needs 128 bits whatever the operands are.
   That is exactly where item 1 lives, so small-operand paths would have to
   be written by hand rather than inherited.

   Ground laid (20260828): `DIGITS_PER_WORD` now names the digits in a word,
   `BASE` and friends are derived from it, `*_power_of_billion` is
   `*_power_of_base`, and the `BigUInt` docstring lists what a base change
   still has to rewrite by hand. A guard-digit count of 9 is not a word width
   and was deliberately left alone.
10. ~~**`floor_divide()` 2n-by-n scaling** in `BigUInt`~~ -- answered below.

## Blocked on the language

Nothing to do here until Mojo grows the feature.

- [x] (20260827) ~~When Mojo supports **global variables**~~ — **no longer
      blocked.** `std.ffi._Global` gives a pointer to one heap cell that
      outlives the call, which is a global by another name; the stdlib uses it
      for the Python runtime handle and the random state. `decimo.Decimal` in
      Python now has a real `getcontext().prec` built on it, and every operator
      reads it. Reading costs 14 ns, measured.

      What is *not* done is a `Context` in the Mojo library itself. The Mojo
      API stays explicit on purpose — every operation takes its precision as an
      argument, the way MPFR does — so the context lives in the Python binding,
      where the `decimal` API asks for it. See `docs/plans/api_roadmap.md`
      Part 0. If a Mojo-side context is ever wanted, `_Global` is how.

- [ ] When Mojo supports **enum types**, implement an enum type for the rounding
      mode.

## Features, not yet started

- [ ] Implement a complex number class `BigComplex` that uses `Decimal` for the
      real and imaginary parts. This will allow users to perform high-precision
      complex number arithmetic.

- [ ] Implement different methods for adding decimo types with `Int` types so
      that an implicit conversion is not required.

## Investigations

- [x] (20260826) Check the `floor_divide()` function of `BigUInt`: 2n-by-n,
      4n-by-n and 8n-by-n divisions looked as though they slowed down
      disproportionally, and the suspicion was Burnikel-Ziegler's segmentation
      of the dividend. **They do not.** Sweeping the dividend across a block
      boundary with a fixed 112-word divisor costs 3.9% to cross it, not the
      whole extra block the segmentation suggests — the first block division
      only takes the real top slice of the dividend, so the cost tracks the
      dividend's actual length. The `+2` guard words that `true_divide()` adds,
      which happen to push a 1000-digit division from two blocks to three, are
      worth about 4%.

      What the investigation did turn up is that the base-case size was
      mistuned, which did not come from segmentation either. It was retuned
      twice the same day and ended where it started: 32 to 24 once the word
      kernels were vectorized, then 24 back to 32 once the Knuth D
      multiply-subtract came off its carry chain. Each change made the base
      case cheaper, but the first favoured a smaller base and the second a
      larger one. See `BURNIKEL_ZIEGLER_BLOCK_WORDS` for the measurements;
      `CUTOFF_BURNIKEL_ZIEGLER`, the separate question of whether the
      recursion runs at all, went 32 to 48.

- [x] (20260828) **Why the test suite is slow.** The suspicion was the Python
      interpreter, since several cross-check tests build a `PythonObject` and
      compare against CPython's `int`. It is not that, and the numbers that
      suggested it were misread: what the harness prints per test is
      **milliseconds, not seconds**.

      The whole suite *executes* in 1.5 s. Everything else is Mojo compiling
      test files, one compilation unit per file, cold in CI:

      | job                 | executing | wall  |
      | ------------------- | --------- | ----- |
      | whole suite, local  | 1.5 s     | 11 s  |
      | Test Decimal128, CI | 0.11 s    | 470 s |
      | Test BigDecimal, CI | 0.35 s    | 365 s |
      | Test BigInt, CI     | 0.61 s    | 203 s |

      Python interop costs about a microsecond per cross-check -- `py.int(str)`
      219 ns, a 100-digit `pa * pb` 95 ns against decimo's 81, `str()` of the
      product 1.00 us against 0.47. Replacing it with a directly linked
      libmpdec, or the GMP wrapper already in the tree, would save well under
      a second across the whole suite. Worth doing if a second *oracle* is
      wanted, since CPython `int` and libmpdec are the same code decimo is
      measured against. Not worth doing for speed.

- [ ] (20260828) **Cache the Mojo compilation cache in CI.** Mojo keeps a
      content-addressed cache at `$MODULAR_HOME/cache/.mojo_cache`, which
      under pixi lives inside `.pixi/envs/`. `setup-pixi` caches the
      environment's *packages*; nothing caches this, so every CI job compiles
      from cold. Measured on one test file, dependencies already warm:

      | state                        | wall   |
      | ---------------------------- | ------ |
      | file not in cache            | 24.6 s |
      | file in cache                | 2.7 s  |

      Decimal128 is nine files and 470 s of CI, about 52 s a file on a macOS
      runner, so a hit rate near one should take that job to well under two
      minutes.

      Three things that make it practical. One test file adds two entries and
      47 MB, so a whole run's working set is a couple of GB -- inside GitHub's
      10 GB per repository. Entries are flat, content-addressed files with no
      absolute path in them, so they should restore onto a fresh runner. And
      the toolchain hash is already in the directory name
      (`1.0.<hash>-production`), which is the cache key.

      Not yet proven: that a restored cache actually *hits* on another
      machine. Verify with a spike before building anything on it.

      **The cache never evicts**, and there is no size cap: `mojo`'s only
      controls are `--print-cache-location` and `--clear-cache`, which is all
      or nothing. 9,234 entries and 81 GB accumulated in eight days locally,
      34.5 GB of it on one busy day. That is ordinary use rather than a leak
      -- any change to `src/decimo` invalidates the package, so a full suite
      run recompiles every test file, one to three GB a time, and a day of
      library work is a dozen of those. A trivial edit recompiled five times
      adds two entries and 1 MB, so it is not per-edit.

      A CI cache therefore needs a pruning step or a rolling key, or it will
      pass 10 GB the same way. Locally `mojo --clear-cache -f` empties it
      without touching the environment, which `pixi clean` would also remove
      but only by deleting `.pixi/` entirely.

## Done

Kept as a record; the detail is in the plans.

- [x] (20260827) **Small operations stopped being allocation.** `BigUInt.words`
      is a `WordList` that keeps ten words in the struct. A four-word add was
      40 ns of which 38 was the allocator; in place it was 1.2 ns. Ten words
      because that is what a division's intermediates need -- eight allocated
      twice per division, twelve only made every value bigger. See
      `docs/plans/inline_storage.md`.

- [x] (20260827) **Three 128-bit divisions removed, worth 2-3x each.**
      `floor_divide_by_uint128` (written in `UInt256`, so two software
      256-bit divides per four dividend words), Knuth D's quotient estimate
      (a 128-bit divide per quotient word, replaced by Knuth's own step D3 in
      64 bits), and Comba's column accumulator (a 128-bit divide by a constant
      per result word, now 64-bit for a shorter operand). A 28-digit division
      went 619 -> 112 ns in Mojo and a 4x4-word multiply 24.7 -> 12.2.

- [x] (20260827) **The Python operators became real C slots.** `a + b` was
      reaching Mojo through `slot_nb_add`, which looks `__add__` up in the
      type dictionary on every operation -- so the operator cost *more* than
      the method call it wrapped. `+ - * /` and all six comparisons are now
      function pointers in the type spec, and the slots read their operands
      in place instead of taking references. Also: `Decimal(int)` and
      `Decimal + int` no longer format the integer and parse it back, and the
      optional-argument methods use vectorcall instead of packing a tuple.

- [x] (20260827) **`decimo.Decimal` is a drop-in replacement for `decimal`.**
      Context, hashing, `//` `%` `divmod` `**`, `int`/`float`/`round`/`floor`/
      `ceil`/`trunc`, `quantize`, `sqrt`/`exp`/`ln`/`log10`, `as_tuple`,
      `as_integer_ratio`, `format`, `copy`, `pickle`, and `ZeroDivisionError`
      where a program expects it. `python/benchmarks/compare.py` runs the same
      source file under both libraries and checks every answer matches.

      Three real differences turned up on the way and were fixed in the Mojo
      core, not papered over in the binding:

      1. Rounding that carried into a new leading digit kept one significant
         digit too many: at precision 5, `0.99999999 + 0` gave `1.00000`
         instead of `1.0000`. `add`, `subtract`, `multiply` and the two
         in-place forms now pass `remove_extra_digit_due_to_rounding=True`,
         which the division and exponential paths were already doing.
      2. `to_eng_string()` stripped trailing zeros and forced an exponent
         where CPython prints plainly. It now matches CPython on every case
         tried: engineering notation changes only the *choice* of exponent.
      3. Unary `+` did not round. In `decimal` it does, and `+value` is the
         standard way to bring a wide intermediate back to the working
         precision — the `pi` benchmark depends on it. Added
         `BigDecimal.round_to_precision(precision)` for this.

- [x] (20260827) **A self-contained wheel.** `pixi run release` builds it,
      `--testpypi` / `--pypi` upload it. The extension loads three Mojo
      runtime libraries through an `@rpath` pointing into the local pixi
      environment, so they are copied in beside it and the paths rewritten to
      `@loader_path`; about 1.6 MB. Editing a Mach-O file invalidates its
      signature and macOS answers that with SIGKILL and no message, so each
      touched file is re-signed ad-hoc. Verified by installing the wheel into
      a venv built from a Homebrew Python with pixi nowhere in sight.

- [x] (20260825) Use debug mode to check for unnecessary zero words before all
      arithmetic operations. `BigUInt.assert_invariant()` and
      `BigInt.assert_invariant()` check that the words are non-empty and carry
      no leading zero word. They are `debug_assert`, so they cost nothing in a
      normal build and run in the test suite.
      `remove_leading_empty_words()` carries the check as a post-condition,
      which covers all thirty repair sites at once.

- [x] Consider using `Decimal` as the struct name instead of `BigDecimal`, and
      use `comptime BigDecimal = Decimal` to create an alias for the `Decimal`
      struct. This just switches the alias and the struct name, but it may be
      more intuitive to use `Decimal` as the struct name since it is more
      consistent with Python's `decimal.Decimal`. Moreover, hovering over
      `Decimal` will show the docstring of the struct, which is more intuitive
      than hovering over `BigDecimal` to see the docstring of the struct.

- [x] (PR #127, #128, #131) Make all default constructor "safe", which means
      that the words are checked and normalized to ensure that there are no zero
      words and that the number is in a valid state. This will help prevent bugs
      and ensure that all `BigUInt` instances are in a consistent state. Also
      allow users to create "unsafe" `BigUInt` instances if they want to, but
      there must be a key-word only argument, e.g., `raw_words`.

- [x] (#31) The `exp()` function performs slower than Python's counterpart in
      specific cases. Detailed investigation reveals the bottleneck stems from
      multiplication operations between decimals with significant fractional
      components. These operations currently rely on UInt256 arithmetic, which
      introduces performance overhead. Optimization of the `multiply()` function
      is required to address these performance bottlenecks, particularly for
      high-precision decimal multiplication with many digits after the decimal
      point. Internally, also use `Decimal` instead of `BigDecimal` or `BDec` to
      be consistent.

- [x] Implement different methods for augmented arithmetic assignments to
      improve memory-efficiency and performance.

- [x] Implement a method `remove_leading_zeros` for `BigUInt`, which removes the
      zero words from the most significant end of the number.

- [x] Use debug mode to check for uninitialized `BigUInt` before all arithmetic
      operations. This will help ensure that there are no uninitialized
      `BigUInt`.

## Roadmap for Decimo

- [x] Re-implement some methods of `BigUInt` to improve the performance, since
      it is the building block of `BigDecimal` and `BigInt10`.
- [x] Refine the methods of `BigDecimal` to improve the performance.
- [x] Implement the big **binary** integer type (`BigInt`) using base-2^32
      internal representation. The new `BigInt` (alias `BInt`) replaces the
      previous base-10^9 implementation (now `BigInt10`) and delivers
      significantly improved performance.
