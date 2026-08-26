# TODO

The one ranked list of what to do next. Everything else points here: the
enhancement plans in `docs/plans/` carry the detail and the reasoning, and
`internal_notes.md` carries the measurements, but neither keeps its own
ranking. There were four such lists in August 2026 and they had already
drifted apart, so there is now one.

Last reviewed 2026-08-27.

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

1. **Python binding overhead.** Now the top item by a wide margin, and it has
   a number to beat. `decimo.Decimal` is a drop-in replacement for `decimal`
   as of 20260827, so the two can be timed on the same source file
   (`python/benchmarks/compare.py`), and CPython's `decimal` wins everything
   below about 500 digits:

   |                       | decimo  | decimal |                  |
   | --------------------- | ------- | ------- | ---------------- |
   | `a + b`, 9 digits     | 141 ns  | 33 ns   | 4.3x slower      |
   | `a / b`, 9 digits     | 241 ns  | 56 ns   | 4.3x slower      |
   | four ops, 1000 digits | 4.75 us | 5.85 us | **1.23x faster** |

   The arithmetic is not the problem: at 9 digits the Mojo addition is 47 ns
   and libmpdec's is comparable. The problem is that a call costs ~110 ns
   before any arithmetic happens -- roughly 25 ns to enter and leave Mojo,
   ~22 ns to reach the operand, 14 ns to read the context precision, and
   28 ns to allocate the result. CPython's `_decimal` does the whole
   operation in 33 ns because the value lives inside the PyObject and small
   coefficients need no second allocation.

   So the fix is item 6 below plus a way to embed the value in the PyObject
   rather than allocating it separately. That second half needs something
   from the Mojo bindings that does not exist today.
   See `docs/plans/mojo4py.md`.

2. **`divide`.** Newton reciprocal division, which is also worth ~115 ms of
   `pi(10^6)`. See `bigint_enhancement.md` T-D4 and
   `bigdecimal_enhancement.md` T-D3. The free part was done 20260826:
   division hands back the remainder it already computed, so
   `true_divide_general()` reads exactness off it instead of building a
   product, and `%` no longer recomputes it.
3. **The last 12 ns of `subtract` at 1000 digits.** Diagnosed (20260826) and
   no longer a loop problem: the add and subtract kernels time the same. Two
   things are left. `subtract` is `raises` where `add` is not, so every caller
   pays the error path on the hot path. And `BigDecimal.subtract` compares the
   two coefficients to pick the larger, then calls a `BigUInt.subtract` that
   compares them again in order to decide whether to raise -- a non-raising
   `subtract_no_check()` that trusts an ordering the caller has already
   established would drop both.
4. **`subtract_inplace()`** builds a negated copy of its right operand to flip
   a sign: `x -= y` is 5.2x slower than libmpdec in place, where `x += y` is
   1.3x *faster*. See `bigdecimal_enhancement.md` H#21.
5. **A cheaper NTT butterfly** — precomputed (Shoup) twiddles and radix-4.
   Needed for goal 1: `pi(10^6)` at 1.2x of mpmath+GMP wants roughly 2.5x here
   on top of item 2.
6. **Inline storage (SBO)** for one or two words in `BigUInt`, worth about
   33 ns of a 44 ns operation. Half of item 1's remaining gap.
7. **`from_string`** at ~95 ns, roughly three allocations, never investigated.
8. **A cheaper read of the context precision.** `std.ffi._Global` costs 14 ns
   per call, because `KGEN_CompilerRT_GetOrCreateGlobal` hashes the name every
   time. `get_or_create_indexed_ptr()` skips the hash but wants one of a small
   set of reserved indices, and squatting on one in a published package would
   collide with whatever the stdlib puts there next. Left alone deliberately.
9. ~~**`floor_divide()` 2n-by-n scaling** in `BigUInt`~~ — answered, see the
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
