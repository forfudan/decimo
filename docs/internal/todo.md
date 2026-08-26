# TODO

The one ranked list of what to do next. Everything else points here: the
enhancement plans in `docs/plans/` carry the detail and the reasoning, and
`internal_notes.md` carries the measurements, but neither keeps its own
ranking. There were four such lists in August 2026 and they had already
drifted apart, so there is now one.

Last reviewed 2026-08-26.

## The goal for this round: met (20260826)

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

The next goal, if there is one, is to make divide *win* rather than tie: 30%
of a 1000-digit division is recursion bookkeeping rather than arithmetic. See
`internal_notes.md`.

## Now

Ordered by value, judged against the two goals in `internal_notes.md`.

1. **Python binding overhead.** Half done (20260826): `decimo.Decimal` is now
   the Mojo type itself rather than a Python class wrapping one, and the type
   check on `self` is gone. `a + b` went 215 ns to 107 ns, `a * b` 215 to 114.
   The wrapper class, not the operator slots, was where the time was — see
   `internal_notes.md`. What is left is the 28 ns result allocation, which
   needs the bindings to embed the value in the PyObject instead of allocating
   it separately; that is not something this side can do today.
   See `docs/plans/mojo4py.md`.
2. **`divide`.** The free part is done (20260826): division hands back the
   remainder it already computed, so `true_divide_general()` reads exactness
   off it instead of building a product, and `%` no longer recomputes it.
   Divide is 1.23-1.32x faster from 10^4 digits up and no longer loses at any
   size we measure. What is left is Newton reciprocal division, which is also
   worth ~115 ms of `pi(10^6)`. See `bigint_enhancement.md` T-D4 and
   `bigdecimal_enhancement.md` T-D3.
3. **The last 12 ns of `subtract` at 1000 digits.** Diagnosed (20260826) and
   no longer a loop problem: the add and subtract kernels time the same. Two
   things are left. `subtract` is `raises` where `add` is not, so every caller
   pays the error path on the hot path. And `BigDecimal.subtract` compares the
   two coefficients to pick the larger, then calls a `BigUInt.subtract` that
   compares them again in order to decide whether to raise — a non-raising
   `subtract_no_check()` that trusts an ordering the caller has already
   established would drop both.
4. **`subtract_inplace()`** builds a negated copy of its right operand to flip
   a sign: `x -= y` is 5.2x slower than libmpdec in place, where `x += y` is
   1.3x *faster*. See `bigdecimal_enhancement.md` H#21.
5. **A cheaper NTT butterfly** — precomputed (Shoup) twiddles and radix-4.
   Needed for goal 1: `pi(10^6)` at 1.2x of mpmath+GMP wants roughly 2.5x here
   on top of item 2.
6. **Inline storage (SBO)** for one or two words in `BigUInt`, worth about
   33 ns of a 44 ns operation. Deliberately after items 1 and 2: there is no
   point removing a 33 ns allocation underneath a 110 ns wrapper.
7. **`from_string`** at ~95 ns, roughly three allocations, never investigated.
8. ~~**`floor_divide()` 2n-by-n scaling** in `BigUInt`~~ — answered, see the
   note below.

## Blocked on the language

Nothing to do here until Mojo grows the feature.

- [ ] When Mojo supports **global variables**, implement a type `Context` and a
      global variable `context` for the `Decimal` class to store the precision
      of the decimal number and other configurations. This will allow users to
      set the precision globally, rather than having to set it for each function
      of the `Decimal` class.

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
