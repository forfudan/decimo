# TODO

The one ranked list of what to do next. Everything else points here: the
enhancement plans in `docs/plans/` carry the detail and the reasoning, and
`internal_notes.md` carries the measurements, but neither keeps its own
ranking. There were four such lists in August 2026 and they had already
drifted apart, so there is now one.

Last reviewed 2026-08-27 (second pass, evening).

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

## Goal, round two: mostly met (20260827)

Be no more than 1.2x of CPython's `decimal` from Python at 28 digits, now
that `BigUInt` keeps small values inline. Measured with
`python/benchmarks/compare.py`, which runs the same source file under both:

| operation  | decimo | decimal |                  |
| ---------- | ------ | ------- | ---------------- |
| `a + b`    | 53.7   | 41.7    | 1.29x            |
| `a * b`    | 59.7   | 48.8    | 1.22x            |
| `a / b`    | 143.1  | 101.0   | 1.42x            |
| `a < b`    | 22.6   | 18.1    | 1.25x            |
| `a + 2`    | 63.4   | 63.4    | the same         |
| `quantize` | 47.3   | 60.6    | **1.28x faster** |

Whole programs: compound interest 1.16x, e from its series 1.13x, sqrt by
Newton at parity, pi by Machin 1.32x, and 1000-digit arithmetic 1.48x faster.
The day started at 4.8x on the four operators and 4.1x on compound interest.

Division is the one left outside the bar, and it is item 1 below.

## Now

Ordered by value, judged against the two goals in `internal_notes.md`.

1. **`divide` from Python, at 1.42x of CPython's `decimal`.** The only
   operator still outside 1.3x. 143 ns against 101, of which 112 is Mojo and
   ~33 is the call. Inside the Mojo half: 4.6 ns padding, 15.7 normalizing,
   63 in Knuth D, ~15 rounding and construction, and about 13 of dispatch --
   `floor_divide_modulo` re-runs every check that `floor_divide_modulo_schoolbook`
   then runs again. Knuth D is 12.7 ns per quotient word for a four-word
   divisor, which is close to what the arithmetic costs; the dispatch and the
   normalization are the parts with slack left.
2. **Newton reciprocal division**, worth ~115 ms of `pi(10^6)`. See
   `bigint_enhancement.md` T-D4 and `bigdecimal_enhancement.md` T-D3.
3. **`subtract_inplace()`** builds a negated copy of its right operand to flip
   a sign: `x -= y` is 5.2x slower than libmpdec in place, where `x += y` is
   1.3x *faster*. See `bigdecimal_enhancement.md` H#21.
4. **A cheaper NTT butterfly** -- precomputed (Shoup) twiddles and radix-4.
   Needed for goal 1: `pi(10^6)` at 1.2x of mpmath+GMP wants roughly 2.5x here
   on top of item 2.
5. **`from_string`** at ~95 ns, roughly three allocations, never investigated.
   `parse and print` is the one whole-program benchmark still at 1.17x.
6. **Audit the remaining `UInt128` and `UInt256` uses.** Two of the three big
   wins today were removing one. The rule that came out of it: 128-bit as an
   *accumulator* is fine, because a 64x64 multiply is one instruction; 128-bit
   or 256-bit as the *left side of a divide* is a call to a software helper
   and costs 20-40 ns. `grep -n "UInt128\|UInt256" src/decimo/**/*.mojo` and
   look at every `//` and `%`. Known remaining: `decimal128/`, `rational/`,
   `bigint/exponential.mojo`.
7. **The last of the Python call overhead**, about 33 ns on every operation.
   ~20 of that is CPython's own dispatch, which `decimal` pays too. What is
   left is the result `PyObject` allocation, roughly 9 ns, which CPython's
   `_decimal` avoids with a freelist. Installing our own `tp_dealloc` slot
   would let us do the same.
8. **`round` at 100 000 digits and above, 15-20% slower than it was.**
   `benchdoc` at ca2ab3c against the run at 06bafb7: 4.75 -> 5.40 us at
   100 000 digits, 47.0 -> 57.5 us at 10^6. Everything else at those sizes
   held or improved, so this looks like the inline array making a large value
   more expensive to move rather than anything about rounding. Not chased yet.
9. **`add` reads 46.5 ns at 9 digits where `subtract` reads 13.4**, in the
   same `benchdoc` run, from kernels that time the same in isolation. `add`
   is the first measurement the harness takes, so this is probably a cold
   start being charged to it -- which would mean the harness has been
   flattering `subtract` and libmpdec's `parse` for a while. Worth one look
   at `benches/doc/generate.py` before believing either number.
10. ~~**`floor_divide()` 2n-by-n scaling** in `BigUInt`~~ -- answered, see the
    note below.

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
