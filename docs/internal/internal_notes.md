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

| Stage | `pi(2048)` | vs. previous |
| --- | --- | --- |
| `2e81976` - Chudnovsky over `BigInt10` (base 10^9) | 0.2539 s | - |
| `51e5896` - Chudnovsky over `BigInt` (base 2^32) | 0.1408 s | 1.80x |
| common powers of two divided out in `combine()` | 0.0974 s | 1.45x |

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

| Reduction at each combine | Time | Final `p` size |
| --- | --- | --- |
| none | 15.2 s | 16 232 668 bits |
| common powers of two (two shifts) | 10.0 s | 11 958 706 bits |
| full gcd | 14.8 s | 36 921 bits |

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
