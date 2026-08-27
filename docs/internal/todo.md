# TODO

The one ranked list of what to do next. Everything else points here: the
enhancement plans in `docs/plans/` carry the detail and the reasoning, and
`internal_notes.md` carries the measurements, but neither keeps its own
ranking. There were four such lists in August 2026 and they had already
drifted apart, so there is now one.

Last reviewed 2026-08-27 (third pass).

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
before the arithmetic starts. Against GMP, timed in C, GMP wins nearly every
row. Ratios, decimo against GMP, bold where decimo is ahead:

| digits | add       | multiply  | floor divide | sqrt      |
| ------ | --------- | --------- | ------------ | --------- |
| 10     | **2.45x** | **1.94x** | 1.60x        | **1.50x** |
| 100    | **1.33x** | 3.14x     | 4.36x        | 2.76x     |
| 1 000  | 2.13x     | 1.91x     | 6.98x        | 11.49x    |
| 10^6   | 2.04x     | 3.98x     | 7.56x        | 12.28x    |

The small end is ours only since inline storage: an `mpz_t` always goes to the
heap, and 10 of GMP's 14.6 ns at a hundred digits is `malloc` and `free`. An
immutable value type cannot use GMP's reuse idiom, so this is the one place
where the shape of the API works for us.

### How much of this is the 32-bit limb?

Less than it looks. A 64-bit limb halves the limb count, but a 64x64 product
costs *two* instructions on arm64 (`MUL` plus `UMULH`) where a 32x32 product
costs one, so the widening pays back half of what the count costs. For work
that grows as `L^e` in the limb count:

    penalty = 2^e * (cost per 32-bit op / cost per 64-bit op) = 2^(e-1)

| algorithm                    | e     | penalty |
| ---------------------------- | ----- | ------- |
| schoolbook, Knuth D          | 2     | 2.0x    |
| Karatsuba                    | 1.585 | 1.50x   |
| Toom-3                       | 1.465 | 1.38x   |
| NTT                          | ~1    | ~1.0x   |

Addition is not on that list, because `_add_word_pairs()` already reads two
words as one base-2^64 limb -- the array *is* a base-2^64 magnitude on a
little-endian target. So its penalty is 1.0x, and everything above the floor
is ours:

| operation      | against GMP | floor | ours to fix |
| -------------- | ----------- | ----- | ----------- |
| add, 10^6      | 2.04x       | 1.0x  | 2.0x        |
| multiply, 100  | 3.14x       | 2.0x  | 1.6x        |
| multiply, 10^6 | 3.98x       | ~1.0x | 4.0x        |
| divide, 100    | 4.36x       | 2.0x  | 2.2x        |
| divide, 10^6   | 7.56x       | ~1.0x | 7.6x        |
| sqrt, 1000+    | ~11x        | ~1.5x | 7x          |

The NTT rows have no limb width to hide behind: a transform packs bits into
coefficients and barely cares what the limbs were.

### Division and sqrt are not separate problems

Both decompose into multiplication. Measure each library's division against
*its own* multiplication and the gap splits cleanly in two:

|            | our mul | GMP mul | ratio | our div/mul | GMP div/mul | div gap |
| ---------- | ------- | ------- | ----- | ----------- | ----------- | ------- |
| 1 000      | 1.16 us | 605 ns  | 1.91x | 5.2x        | 2.0x        | 5.0x    |
| 10^6       | 24.1 ms | 6.06 ms | 3.98x | 4.9x        | 2.6x        | 7.6x    |

`1.91 * 2.6 = 5.0` and `3.98 * 1.9 = 7.6`, which is the whole of it. So the
division gap is our multiplication being slow, times our division not being
multiplication-bound. Neither factor needs a new division algorithm at 10^6:
Barrett would cost about `4 * M(n)`, which is what we already pay.

`sqrt` sits on top of the same stack -- profiled at 1000 and 10 000 digits it
is 60% to 67% the one division at its last precision-doubling step, 10% to 20%
the verifying squaring, and the rest driver. Even with the division and the
squaring free it would still be 7.6x. Zimmermann's recursion is worth having,
but it cannot get ahead of the division underneath it, so it comes after.

Ordered by what actually moves:

1. **The NTT butterfly.** 4x on multiplication at 10^6, with no limb-width
   excuse -- a transform packs bits, not limbs -- and division and `sqrt`
   inherit all of it. Precomputed (Shoup) twiddles and radix-4; see item 7 of
   `Now`, which wants the same thing for `pi()`.
2. **Burnikel-Ziegler's per-level cost.** Our division costs 5.2 of its own
   multiplications where GMP's costs 2.0. The recursion is not too shallow:
   cutoffs of 8, 16 and 24 words are all *worse* than 64 (10.1 us, 7.2 us and
   7.6 us against 6.0 at 1000 digits), so each level is paying too much --
   allocations, `_shift_left_words_inplace`, `_add_at_offset_inplace` and a
   fresh result out of `_multiply_magnitudes_slices` every call. The cutoff
   itself is flat from 32 to 96 and there is nothing to win by moving it.
3. **Karatsuba square root**, once 1 and 2 have landed. Zimmermann's recursion
   halves the division at the last step and returns the remainder, which also
   deletes the verifying squaring.
4. **Break the carry chain in add and subtract.** We are latency-bound on it,
   not throughput-bound: 1038 words at 10 000 digits is 519 limbs and 271 ns,
   which is 1.8 cycles a limb, where GMP's `ADCS` chain runs at 1.0. Widen the
   words into 64-bit SIMD lanes to manufacture the slack that base 10^9 gives
   `BigUInt` for free, sum ignoring carry, then propagate. A lane only
   propagates when its digit is all ones, so the second pass can be a mask
   test that almost never fires rather than `BigUInt`'s serial walk.
5. **Multiplication thresholds.** `CUTOFF_KARATSUBA` is 256 words, which is
   2466 decimal digits; GMP switches around 500. Our Comba is good enough that
   schoolbook at 104 words is only 1.91x of GMP's Karatsuba, so this is worth
   measuring rather than assuming.

Two things measured the wrong way round here, so they are not retried:

- **A branchless borrow in Knuth D.** Biasing by 2^32 and reading the borrow
  out of bit 32 puts the loaded word in the loop-carried carry chain. The
  branch is worth 1.38x at 1000 digits.
- **A `UInt128` accumulator for the paired add and subtract.** It does not
  become `ADDS`/`ADCS`; add at 10 000 digits went 279 ns to 391, subtract 275
  to 503. The comparison-based carry that is there is the fast one.

## Now

Ordered by value. Three things are still behind CPython's `decimal`, and
they are the first three.

1. **`divide`, 1.24x at 9 digits and 1.38x at 28.** The only operator still
   outside 1.2x. 138.8 ns against 100.3, of which ~109 is Mojo and ~30 the
   call. Inside the Mojo half: 4.6 ns padding, 15.7 normalizing, ~60 in
   Knuth D over five quotient words, ~15 rounding and construction. Four
   things were tried and did not help -- calling Knuth D without the second
   dispatch (neutral; the compiler had already inlined it), padding by digits
   instead of whole words (worse, because `multiply_by_power_of_billion` only
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
   the *left side of a divide* is a call to a software helper, 20-40 ns.
   Known remaining: `decimal128/`, `rational/`, `bigint/exponential.mojo`.
9. **Base 10^18.** The honest answer to "why is division still behind": for a
   28-digit value libmpdec holds two words and decimo holds four, so every
   loop runs twice as long. Nothing above closes that. It is a change to the
   whole library and it is not obviously worth it -- multiplication and
   division would halve their word counts, but every partial product would
   need 128-bit accumulation, and `% BASE` on a `UInt128` is the thing that
   was slow everywhere else today. Worth measuring on a prototype before
   believing either way.
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
