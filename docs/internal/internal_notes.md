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

The base cases are the remaining structural inefficiency. Each leaf `k` rebuilds
`(6k)!/(3k)!`, `(k!)^3` and `C^k` from scratch, which is O(k) big-integer
multiplications per leaf and O(n^2) overall. The textbook `P`/`Q`/`T` binary
splitting recurrence makes the leaf O(1) and lets those factors telescope
through the combines instead. At 640 terms the leaves alone cost 0.89 s of the
total, so this is not yet the bottleneck, but it is where the next big win is.

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
