# Internal Notes

## Inconsistencies between libraries

- For power functionality: `BigDecimal.power()`, Python's decimal, WolframAlpha
  give the same result, but `mpmath` gives a different result. Examples:
  - `0.123456789 ** 1000`
  - `1234523894766789 ** 1098.1209848`
- For sin functionality: `BigDecimal.sin()` and WolframAlpha give the same
  results, but `mpmath` gives a different result. This occurs mainly for
  pi-related values. Examples:
  - `sin(3.1415926535897932384626433833)`, precision 50:
    - Decimo:       -2.0497115802830600624894179025055407692183593713791E-29
    - WolframAlpha: -2.0497115802830600624894179025055407692183593713791 x 10-29
    - mpmath:       -2.049711580283060062489453928920860542175349360102e-29
  - `sin(6.2831853071795864769252867666)`, precision 50:
    - Decimo:       4.0994231605661201249788358050110815384367187427582E-29
    - WolframAlpha: 4.0994231605661201249788358050110815384367187427582 x 10-29
    - mpmath:       4.0994231605661201249789078578417210843506987202039e-29

## Time complexity for pi() implementations

- #94. Implementing pi() with Machin's formula. Time taken for precision 2048:
  33.580649 seconds.
- #95. Implementing pi() with Chudnovsky algorithm (binary splitting). Time
  taken for precision 2048: 1.771954 seconds.
- #97. Implementing Karatsuba multiplication for BigUInt. Time taken for
  precision 2048: 0.60656999994535 seconds.
- #105. Implementing Burnikel-Ziegler division for BigUInt. Time taken for
  precision 2048: 0.5454419999732636 seconds.

The entries above were each measured on the machine of the day, so they are a
record of direction rather than a comparable series. The three below were all
re-measured together (Apple silicon, best of three runs, `pi(2048)`), so the
ratios between them are meaningful:

| Stage                                              | `pi(2048)` | vs. previous |
| -------------------------------------------------- | ---------- | ------------ |
| `2e81976` - Chudnovsky over `BigInt10` (base 10^9) | 0.2539 s   | -            |
| `51e5896` - Chudnovsky over `BigInt` (base 2^32)   | 0.1408 s   | 1.80x        |
| common powers of two divided out in `combine()`    | 0.0974 s   | 1.45x        |
| `P`/`Q`/`T` binary splitting recurrence            | 0.0007 s   | 139x         |

Notes on the last two, both in `bigdecimal/constants.mojo`:

- Moving binary splitting from `BigInt10` to `BigInt` was a 5x *regression*
  before it was a win. `BigInt` arithmetic is the faster of the two (at 20 000
  digits: multiply 798 vs. 690 us, divide 2285 vs. 3049 us), but the split
  hands back two operands of tens of thousands of digits that then have to
  cross from base 2^32 to base 10^9. Profiling `pi(1000)`: split 15.9 ms, the
  two base conversions 44.5 ms, the division that consumes them 0.082 ms. Two
  fixes: `BigInt.to_biguint()` reuses the divide-and-conquer conversion that
  `to_string()` already had (above 128 words), and both operands are shifted
  right by a common bit count before the conversion, which leaves their ratio
  intact but converts only the digits the quotient actually needs.
- Dividing the common powers of two out of `p` and `q` at each combine is two
  shifts, no gcd. `q` is dense in factors of two - it is built from `(k!)^3`
  and `262537412640768000^k`, and 262537412640768000 alone contributes 2^18 per
  term - so this reclaims a large constant factor for almost nothing.

Measured over the whole split (not just `pi`), at 640 terms (~9 000 digits):

| Reduction at each combine         | Time   | Final `p` size  |
| --------------------------------- | ------ | --------------- |
| none                              | 15.2 s | 16 232 668 bits |
| common powers of two (two shifts) | 10.0 s | 11 958 706 bits |
| full gcd                          | 14.8 s | 36 921 bits     |

The full gcd is not the disaster its cost per step suggests: it collapses the
operands by a factor of ~440, so it is already break-even at 9 000 digits and
wins outright beyond that. It is not used because the shifts get most of the
benefit for a fraction of the cost, and because `BigInt`'s gcd is binary
(Stein's), which is quadratic; a subquadratic gcd would change this trade-off.

### The `P`/`Q`/`T` recurrence

The base cases used to be the remaining structural inefficiency: each leaf `k`
rebuilt `(6k)!/(3k)!`, `(k!)^3` and `C^k` from scratch, O(k) big-integer
multiplications per leaf and O(n^2) overall. That has been replaced with the
textbook `P`/`Q`/`T` recurrence, in which the leaf is O(1) and those factors
telescope through the combines.

The leaf cost was the visible half of the problem and the smaller half. The
larger half was what the old shape did to the operands. Carrying each term as
an evaluated fraction means `combine()` multiplies the two denominators, so the
denominator at the root is the *product* of all `n` term denominators - about
O(n^2 log n) bits. With `P`/`Q`/`T` the same root denominator is
`((n-1)!)^3 (C^3/24)^(n-1)`, the denominator of a *single* term, about
O(n log n) bits. That is where the two-to-three orders of magnitude come from,
and why the win grows with precision:

| `pi(n)`   | Fraction leaves | `P`/`Q`/`T` | Speedup |
| --------- | --------------- | ----------- | ------- |
| 1 000     | 10.46 ms        | 0.25 ms     | 43x     |
| 2 048     | 86.01 ms        | 0.69 ms     | 125x    |
| 5 000     | 1.464 s         | 3.30 ms     | 443x    |
| 10 000    | 13.658 s        | 8.81 ms     | 1 551x  |
| 20 000    | -               | 27.92 ms    | -       |
| 50 000    | -               | 96.89 ms    | -       |
| 100 000   | -               | 288.84 ms   | -       |

Two consequences worth recording:

- **The common-powers-of-two trick is gone, and it is not a loss.** The triple
  is homogeneous of degree one in each child, so dividing all three fields of a
  subrange by a common factor does propagate correctly. But `P` is a product of
  `(6k-5)(2k-1)(6k-1)`, all three of which are odd, so `P` is always odd and
  the common factor is always one. There is nothing left to strip. The
  reduction the old code did was reclaiming bloat the old shape created.
- **The split is no longer where the time goes.** At `pi(100000)`, the split is
  66 ms of the 289 ms total; the rest is the base-2^32 to base-10^9 conversion,
  the final division, and `sqrt(10005)`. Further work on the series itself has
  little left to win.

### Where the rest of `pi()` goes

Measured per stage, in milliseconds, after the `sqrt` change below:

| Stage                   | 5 000 digits | 10 000 | 50 000 |
| ----------------------- | ------------ | ------ | ------ |
| binary splitting        | 0.70         | 1.88   | 22.5   |
| base 2^32 -> 10^9, x2    | 0.43         | 1.33   | 23.9   |
| final division          | 0.58         | 1.27   | 12.4   |
| `sqrt(10005)`           | 0.19         | 0.56   | 6.6    |
| final multiplies, round | 0.10         | 0.30   | 3.8    |

`sqrt(10005)` used to head this table - 1.61 ms, 4.59 ms and 36.8 ms, ahead of
the split itself - because `pi()` called the public `sqrt()`, which is
`sqrt_exact()`. That function reproduces CPython's `Decimal.sqrt()` bit for bit
by computing an exact integer square root and then testing whether the input is
a perfect square; both cost full-size divisions, and neither means anything for
a fixed non-square constant used as an intermediate. `pi()` now calls
`sqrt_reciprocal()`, whose Newton iteration is division-free.

What remains is mostly a tax that a binary library does not pay. mpmath's
`pi_fixed` stays in binary from end to end and converts once, when the value is
printed; decimo converts both operands of the final division into base 10^9
before dividing. Against mpmath 1.4.1 on the pure-Python backend, comparing
against its `to_str` timing since decimo returns decimal digits, the ratio is
now 1.5x at 1 000 digits and 1.2x from 5 000 up, against 2.1x before. Closing
the rest means converting once rather than twice - computing `q * 10^p // t` in
`BigInt` and converting only the quotient - and giving `to_biguint()` a
divide-and-conquer that splits on powers of `10^9` rather than powers of `10`,
so the halves land on word boundaries and no decimal string is built at all.

### A Newton schedule reaches `seed * 2^n`, and nothing caps it

Two bugs in `sqrt_reciprocal()` and `fast_isqrt()`, caught while measuring the
above, both of which returned the full requested digit count with a wrong tail
and raised nothing.

The iteration `r <- r * (3 - x * r^2) / 2` doubles the correct digits. It does
*not* get pulled up to whatever precision the arithmetic inside it runs at, so
`n` iterations return `seed * 2^n` digits and no more. Both functions built
their schedule by halving from the target down to 20, which credits the seed
with 20 digits; and both seeded with `x ** -0.5`, which goes through `exp`/`log`
and is accurate to about ten digits for some inputs while being exact for
others. Instrumented, `sqrt_reciprocal(1234.5678, 1500)`:

| iteration precision | 34 | 58 | 106 | 201 | 392 | 773 | 1535 |
| ------------------- | -- | -- | --- | --- | --- | --- | ---- |
| correct digits      | 19 | 38 | 78  | 156 | 312 | 624 | 1248 |

Clean doubling from a ten-digit seed, never once reaching the precision the
iteration was nominally running at. The schedule now halves down to
`_F64_SEED_DIGITS`, and the seed is `1 / sqrt(x)`, which is correctly rounded.

The reason this survived so long is that both dials have to be wrong *and* the
schedule has to land badly. `sqrt_reciprocal(10005, 1000)` and
`(10005, 2000)` were correct in full; `(10005, 1500)` was correct in full but
`(1234.5678, 1500)` was not, because `1.0005 ** -0.5` happens to be exact and
`12.345678 ** -0.5` is not. Any spot check picks a survivor. The test sweeps
inputs against precisions for that reason.

### Could the public `Rational` carry the split?

Asked and measured, because it would be one type fewer. The answer is no, but
not for the reason the old `_UnreducedFraction` docstring gave.

The natural `Rational` formulation carries two fractions per node - the partial
sum `S` and the running term ratio `R` - and combines them as
`S = S_left + R_left * S_right`, `R = R_left * R_right`. That is a faithful
translation, and it agrees with the `P`/`Q`/`T` result exactly at every size
tested, which is a useful independent check on the implementation. It is also
much slower, and falls further behind as the range grows:

| Terms | `P`/`Q`/`T` | Two `Rational`s | Root denominator, reduced |
| ----- | ----------- | --------------- | ------------------------- |
| 80    | 0.17 ms     | 2.60 ms         | 84% of unreduced          |
| 160   | 0.28 ms     | 8.77 ms         | 81%                       |
| 320   | 0.58 ms     | 31.24 ms        | 78%                       |
| 640   | 1.60 ms     | 119.72 ms       | 75%                       |
| 1 280 | 4.65 ms     | 481.02 ms       | 72%                       |

The reason is in the last column. `Rational`'s invariant forces a gcd at every
node, and here it buys almost nothing: the operands are only about a quarter
smaller after full reduction, because the `P`/`Q`/`T` products are already
close to coprime by construction. Paying a gcd per node to shave 25% off the
operands is a bad trade at any size, and it gets worse, not better, as the
numbers grow. `Rational` is the right type for exact fractions; it is the wrong
type for a splitting tree whose whole point is that the fractions never need to
be in lowest terms.

## `Rational` addition and unbalanced `gcd`

Two changes that came out of the question above, and that stand on their own.

`Rational.__add__` used to form `(a.n*b.d + b.n*a.d) / (a.d*b.d)` and then
normalize, which pays a gcd over two full-width operands to throw away a
denominator it just built. `__mul__` and `__truediv__` already cross-cancelled;
addition now does the equivalent, via Algorithm A of Knuth 4.5.1: gcd the two
denominators first, and both branches return a fraction already in lowest
terms.

That change on its own was *slower*, which is the interesting part. Knuth's
form replaces one gcd of two big operands with `gcd(big denominator, small
denominator)` - and Stein's binary algorithm is close to its worst case on
exactly that shape. It makes about one bit of progress per iteration and every
iteration costs a subtraction over the larger operand, so gcd(18 000-bit,
20-bit) spends 18 000 full-width subtractions to reach what a single remainder
reaches at once. Euclidean steps have the opposite profile: worth their
division cost only while they shrink the operand by a large factor.

So `gcd()` now takes Euclidean steps while the bit-length gap exceeds two
words, and hands over to Stein as soon as it does not:

| `gcd(a, b)`             | Stein only | Euclid-balanced |
| ----------------------- | ---------- | --------------- |
| 1 795 bits, 20 bits     | 0.049 ms   | 0.002 ms        |
| 5 981 bits, 20 bits     | 0.534 ms   | 0.002 ms        |
| 17 940 bits, 20 bits    | 4.850 ms   | 0.003 ms        |
| 5 980 bits, 5 980 bits  | 0.805 ms   | 0.818 ms        |

The balanced row is the control: the loop never fires there, and the difference
is noise. With that in place the `Rational` change pays - summing `1/k^2` to
1 200 terms goes from 123 ms to 3.1 ms, a 39x improvement.

One trap worth recording, caught in review of PR #270. `bit_length()` returns a
signed `Int`, so for `gcd(small, big)` the gap is simply negative, the
balancing loop never runs, and the call drops straight back into the quadratic
binary loop. Both argument orders still return the right answer, so no
correctness test can see it:

| `gcd(a, b)`            | forward  | reversed, unordered | reversed, ordered |
| ---------------------- | -------- | ------------------- | ----------------- |
| 1 329 bits, 41 bits    | 0.000 ms | 0.014 ms            | 0.000 ms          |
| 5 980 bits, 7 bits     | 0.001 ms | 0.268 ms            | 0.001 ms          |
| 17 939 bits, 7 bits    | 0.002 ms | 2.367 ms            | 0.003 ms          |

`gcd()` therefore orders its operands by magnitude before measuring the gap.
Each Euclidean step preserves that order on its own - the new pair is
`(v, u mod v)`, and a remainder is smaller than what it was taken modulo - so
one comparison at the top is enough.

The balanced case is still Stein's, which is quadratic. A subquadratic gcd
(Lehmer, or half-gcd) would be the next step, and would also change the
full-gcd-per-combine trade-off recorded above.

## Test suite timing

### The harness prints milliseconds, not seconds

`std.testing.TestSuite` renders every duration through `_format_nsec`, which
divides nanoseconds by 1 000 000 and prints `NNN.NNN` with no unit. So

```
    PASS [ 118.116 ] test_biguint_truncate_divide_huge_random_numbers_against_python
```

is 118 **milliseconds**, not 118 seconds. Calibrated against a spin loop:

| Spin  | Reported  |
| ----- | --------- |
| 0.1 s |   100.003 |
| 0.5 s |   500.000 |
| 1.0 s |  1000.000 |

Worth remembering before optimising anything on the strength of those numbers.
The slowest-looking test in the repo takes about a tenth of a second.

### Where the wall clock actually goes

Warm compile cache, this machine, `bash tests/test.sh decimo` (50 files):

| Quantity                                   | Time   |
| ------------------------------------------ | ------ |
| Sum of all test bodies (harness durations) | 0.78 s |
| Wall clock, sequential                     | 67.4 s |

About 99% of the run is fixed per-file cost: one `mojo run` process each, with
process start, compile-cache validation, `decimo.mojoc` load and libpython
init. A bare `mojo run` on a two-line hello-world is already 0.27 s; a decimo
test file that asserts nothing measurable still costs ~0.6 s.

Nothing inside the tests is worth optimising at this ratio. The lever is to
stop paying that cost 50 times in series. The files are independent, so
`tests/test.sh` takes `DECIMO_TEST_JOBS` (default 1) and runs that many
concurrently, buffering each file's output and replaying it whole, in the
original order, so the transcript is unchanged:

| `DECIMO_TEST_JOBS` | `test.sh decimo` | `test.sh all` |
| ------------------ | ---------------- | ------------- |
| 1 (default)        | 67.4 s           | 68.4 s        |
| 4                  | 21.4 s           |               |
| 8                  | 13.3 s           | 15.2 s        |
| 14 (= `hw.ncpu`)   | 10.6 s           |               |

Same 1005 passing tests either way, and the normalised transcripts are
identical. Note that these numbers all assume a warm cache: the first run after
`src/decimo` changes recompiles every test file and takes ~320 s sequentially.

### Building long decimal literals in tests

Several cross-check tests build a long decimal literal out of random 18-digit
groups. A review flagged the `result += String(...)` loop as quadratic. It is
not: `String._iadd` grows through `_realloc_mutable`, which allocates
`max(requested, capacity * 2)`, so appending is amortised O(1).

Measured, best of 20, including the `random_ui64` draws (which dominate):

| Groups    | `+=`      | `+=` after reserving | `List` + `join` |
| --------- | --------- | -------------------- | --------------- |
| 789       | 0.044 ms  | 0.047 ms             | 0.041 ms        |
| 12 345    | 0.699 ms  | 0.743 ms             | 0.649 ms        |
| 123 450   | 7.052 ms  | 7.496 ms             | 6.644 ms        |
| 1 234 500 | 71.450 ms | 75.658 ms            | 67.633 ms       |

Linear across three orders of magnitude, and the three forms are within 10% of
each other. Reserving up front is *slower* than the naive loop here, because it
touches the full 18-bytes-per-group upper bound while the doubling strategy
never allocates more than twice what is used. The tests use
`decimo.tests.random_decimal_string()` (the `join` form) for the marginal win
and, mainly, so the intent lives in one place.
