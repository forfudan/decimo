# Internal Notes

## Goals

Two targets to steer by, both about being competitive with the established
libraries rather than beating them everywhere. Measured on Apple M4 Pro,
20260825.

**1. `pi(10^6)` within 1.2x of mpmath+GMP** — 314 ms, against 796 ms today
(3.0x). Two steps get there and neither needs a new algorithm: Newton
reciprocal division (T-D6) is worth about 115 ms, and the rest has to come
from a cheaper NTT butterfly — precomputed twiddles and radix-4, together
about 2.5x. Detail in the sections on the NTT and on GMP's ratios below.

**2. Beat CPython's `decimal` on small numbers** — this is what a
`decimal.Decimal` drop-in is judged on, and today we are at parity on
subtract, multiply and `from_string`, and 1.8-2.1x behind on add, round and
divide. It is almost entirely memory management, not arithmetic: a small add
does about 5 ns of real work and spends 36 ns allocating the result. Giving
`BigUInt` inline storage for one or two words would remove the allocation
and should put small operations clearly ahead of libmpdec. See "Small
operations are allocation, not arithmetic".

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
- **The split stopped being the whole cost, then became the largest single
  piece again.** When the `P`/`Q`/`T` shape landed, the split was 66 ms of the
  289 ms of a `pi(100000)`, the rest being base conversion, the final division
  and `sqrt(10005)`. Those three have since been cut hard enough that the split
  is back on top at roughly 45% - see the stage table below. Further work on
  the series itself is now the thing with the most left to win, and it means
  faster multiplication rather than a better recurrence.

### Where the rest of `pi()` goes

Measured per stage, in milliseconds:

| Stage                     | 5 000 digits | 10 000 | 50 000 |
| ------------------------- | ------------ | ------ | ------ |
| binary splitting          | 0.54         | 1.58   | 21.1   |
| `5^s` and the scaling mul | 0.09         | 0.26   | 3.5    |
| final division, binary    | 0.17         | 0.49   | 6.2    |
| base 2^32 -> 10^9, x1     | 0.19         | 0.62   | 7.1    |
| `sqrt(10005)`             | 0.18         | 0.57   | 7.4    |
| final multiplies, round   | 0.10         | 0.30   | 3.8    |

Two stages of that table used to be one line reading `base 2^32 -> 10^9, x2`,
and it cost 0.43 / 1.33 / 23.9. The final step of the evaluation built a
`BigDecimal` out of each of `q` and `t` and divided those, so both operands
crossed from binary to decimal. Base conversion is the one cost a binary bignum
library never pays at all, so the fix is to stay in binary as long as possible:
scale `q` by `10^s` there, take a single integer division, and convert only the
quotient. That trades one whole conversion for a multiplication, and the
multiplication is the cheaper of the two. `10^s` is spelled `5^s << s`, which
takes the power over the smaller base and leaves the factor of `2^s` to a word
shift.

A third of what remains is the binary splitting, and most of what was shaved
off that was not arithmetic at all. `P(k)`, `Q(k)` and `T(k)` fit in a
`UInt128` for every `k` below four million, so a leaf can pack its words
directly instead of composing itself out of about ten small `BigInt` operands;
there are `precision / 14` leaves, and at 1 000 digits that allocation traffic
was half of the whole split. The root of the split also stopped computing
`left.p * right.p`, which is a full-width multiplication the final formula
never reads.

`sqrt(10005)` used to head this table - 1.61 ms, 4.59 ms and 36.8 ms, ahead of
the split itself - because `pi()` called the public `sqrt()`, which is
`sqrt_exact()`. That function reproduces CPython's `Decimal.sqrt()` bit for bit
by computing an exact integer square root and then testing whether the input is
a perfect square; both cost full-size divisions, and neither means anything for
a fixed non-square constant used as an intermediate. `pi()` now calls
`sqrt_via_reciprocal_iteration()`, whose Newton iteration is division-free.

Against mpmath 1.4.1 on its pure-Python backend, best of N for both sides on
the same machine, comparing against its `to_str` timing since decimo returns
decimal digits and mpmath's `pi_fixed` does not:

| digits  | decimo   | mpmath   |
| ------- | -------- | -------- |
| 100     | 0.011 ms | 0.008 ms |
| 500     | 0.039    | 0.043    |
| 1 000   | 0.110    | 0.116    |
| 5 000   | 1.19     | 1.67     |
| 10 000  | 3.55     | 5.11     |
| 50 000  | 47.9     | 61.5     |
| 100 000 | 148      | 189      |

Note that "pure-Python mpmath" still multiplies and divides in C: what the
backend switch turns off is gmpy2, not CPython's own Karatsuba `int`. Only the
orchestration is Python.

Below about 500 digits decimo is still behind, and the profile there is flat -
no single stage dominates, it is fixed overhead spread across a dozen small
allocations. That is the remaining piece worth looking at, along with the
`to_biguint()` in the table above, which is still two thirds the cost of the
division it feeds.

### Toom-3 helps the multiply much more than it helps `pi()`

Toom-3 on `BigInt` is 1.15x Karatsuba at 400 words, 1.26x at 5 000 and 1.51x at
22 000, but on its own `pi(100000)` only went 152 -> 142 ms. The tree shape
explains it: doubling the term count multiplies the split's cost by 3.06, so the
top level is only 35% of the total and each level below adds 65% of the one
above. Toom-3 reaches the top three or four levels; the rest is Karatsuba as
before.

So a faster multiply only pays across a *wide* size range. Toom-4 would move
the same few levels again; only an FFT changes the exponent everywhere.

Where the time goes, after the rest of the 2026-08-24 work took it to 78 ms:

| Stage                                  | ms   | Base |
| -------------------------------------- | ---- | ---- |
| binary splitting, below the root       | 24.5 | 2^32 |
| base 2^32 -> 10^9                      | 12.5 | both |
| `sqrt_via_reciprocal_iteration(10005)` | 11.1 | 10^9 |
| root join, 3 full-width multiplies     | 9.7  | 2^32 |
| final division                         | 9.6  | 2^32 |
| final multiplies and round             | 6.0  | 10^9 |
| `5^s` and the scaling multiply         | 4.9  | 2^32 |

17 ms still runs in base 10^9, where the same multiply costs more than it does
in base 2^32 (6.0 ms against 3.4 at 100 000 digits). Neither stage has to be
decimal. See `plans/bigdecimal_enhancement.md` T-PI4.

**Update (T-PI4, done).** The square root and the final multiplies moved to
`BigInt`; only the one conversion still runs in base 10^9. What made it work
was writing `π = 426880 * √10005 * (q/t)` as `426880 * 10005 / √10005 * (q/t)`

- as a *reciprocal* root it needs no division, and `426880 * 10005` is still
one word. 58.2 → 50.2 ms.

### The exact `sqrt()` spends 87% of its time after Newton has finished

`sqrt(10005, 50000)` takes 18.3 ms;
`sqrt_via_reciprocal_iteration(10005, 50000)` takes 2.36 ms and agrees to every
digit checked. The difference is `sqrt_exact()`'s exact-integer tail: rescale
`c`, one `c.floor_divide(n)` refinement step, and the `n * n == c`
perfect-square test. Instrumenting the refinement loop shows it runs **once**,
so this is not a convergence problem - it is one full-width division plus one
full-width square, both in base 10^9.

That is why rearranging `isqrt_via_reciprocal_seed()`'s Newton step around the
residual, which was worth 1.6x in `sqrt_via_reciprocal_iteration()`, is worth
only 6% here. The exactness guarantee costs a divide and a square at full width,
and the fix is to stop paying for them in base 10^9 (T-Sq2, same argument as
T-PI4).

### Where `pi()` stands against mpmath and MPFR, and what the exponent says

Measured 20260825 on Apple M4 Pro, after the NTT landed. Every engine was
verified to produce the same digits first: at 1 000 000 digits decimo agrees
with MPFR on all of them, and where a shorter run appears to disagree in its
last digit it is decimo rounding half-even against a truncated reference.
mpmath and MPFR both cache pi internally, so each measurement ran in a cold
process.

Compute pi and produce the decimal digits — the fair column, because decimo's
pi is decimal-native while the other two are binary and pay conversion only on
demand:

| digits    | decimo   | mpmath (py) | mpmath+GMP | MPFR     |
| --------- | -------- | ----------- | ---------- | -------- |
| 100       | 7.0 us   | 28.0 us     | 37.9 us    | 37.5 us  |
| 1 000     | 63 us    | 153 us      | 99 us      | 63.8 us  |
| 10 000    | 1.25 ms  | 5.71 ms     | 0.85 ms    | 0.65 ms  |
| 100 000   | 33.0 ms  | 182 ms      | 15.1 ms    | 23.7 ms  |
| 1 000 000 | 797 ms   | 8.49 s      | 262 ms     | 410 ms   |

Empirical exponent `t ~ digits^k`, per decade:

| engine      | 100->1k | 1k->10k | 10k->100k | 100k->1M |
| ----------- | ------- | ------- | --------- | -------- |
| decimo      | 0.95    | 1.30    | 1.42      | **1.38** |
| mpmath (py) | 0.74    | 1.57    | 1.50      | 1.67     |
| mpmath+GMP  | 0.42    | 0.93    | 1.25      | 1.24     |
| MPFR        | 0.23    | 1.01    | 1.56      | 1.24     |

The exponent is the whole story of the widening ratio: 1.47x behind mpmath+GMP
at 10 000 digits becomes 3.04x at 10^6 purely by compounding 1.38 against 1.24.
decimo is still at 1.38 rather than the ~1.1 a fully-FFT pipeline would show
because 39% of `pi(10^6)` is division and base conversion, which run at
Toom-3's 1.465 — Burnikel-Ziegler reaches multiplication only through operands
half the size and smaller, where the transform has not opened up. The binary
splitting stage itself measures 1.38, not ~1.05, for the same reason: only the
top few levels of its tree are above the transform's crossover.

decimo wins outright at 100 and 1 000 digits, including against MPFR. That is
real and not a warm-up artifact — decimo was timed in-process, best-of-N.

### Small operations are allocation, not arithmetic

Measured on one-word operands:

| | ns |
| --- | --- |
| `+=` in place, no allocation | 5 |
| one `List[UInt32]` alloc + free | 36 |
| `a + b` out of place | 43 |
| libmpdec small add, for reference | 32 |

The arithmetic is already fast; a small `BigDecimal` operation is one or two
malloc/free pairs with a little work attached. That is the whole gap against
libmpdec, which keeps small coefficients inline and never calls malloc for
them.

One instance of this was a plain bug and is fixed: `BigDecimal.__init__`
took its coefficient *borrowed* and then copied it, so the 27 call sites
already written as `coefficient=coef^` were all paying a full extra
allocation for a move they had asked for. Making the parameter owned took
`a + b` from 73 ns to 43 ns, multiply from 2.3x libmpdec to 1.2x, and
subtract to parity.

What is left is the allocation itself, and only inline storage removes it.

### MPFR computes pi by AGM, mpmath by Chudnovsky

Why MPFR is the *slower* of the two GMP-backed engines, which is otherwise
surprising. At 10^6 digits a single `gmpy2.agm()` costs 341 ms and
`mpfr_const_pi` costs 371 ms: `mpfr_const_pi` is one Brent-Salamin AGM plus
change. The AGM needs a full-precision square root per iteration and about
`log2(bits)` iterations — 22 sqrt at 12.5 ms is already 275 ms of the 371.
mpmath instead runs Chudnovsky with binary splitting over GMP integers, the
same algorithm we use, and lands at 262 ms. Both are `O(M(n) log n)` and both
measure an exponent of 1.24; the difference is entirely the constant, which is
why every pi record uses Chudnovsky and not AGM.

### GMP's own division and base-conversion ratios, as a target

Measured at 104 200 words (10^6 digits), against a same-size multiply:

| operation           | GMP      | ratio to mul | decimo ratio |
| ------------------- | -------- | ------------ | ------------ |
| mul n x n           | 5.83 ms  | 1.00         | 1.00         |
| divmod 2n / n       | 15.69 ms | 2.69         | 4.90         |
| base 2^k -> decimal | 33.71 ms | 5.78         | 8.50         |

Two things to take from this. GMP's division is 2.69x a multiply *with* all of
its Newton-reciprocal machinery, so 2.7x is the realistic floor for T-D6 — not
the ~2.1x the textbook operation count suggests. And our raw multiply is
24.0 ms against GMP's 5.83, a 4.1x gap that is pure constant factor: same
algorithm class, thirty years of tuning apart.

### GMP is on FFT from ~32 000 digits, and that is most of the gap

Superseded in part by the table above — the 6.1x multiply gap it describes is
now 4.1x, and the FFT half of it is closed. Kept for the measurement method.


`mpz_mul` normalised to Toom-3's exponent, `t / n^1.465` with `n` in 64-bit
limbs, is flat until it suddenly isn't:

| digits  | limbs | mul    | t/n^1.465 |
| ------- | ----- | ------ | --------- |
| 20 000  | 1 039 | 147 us | 5.58      |
| 30 000  | 1 558 | 263    | 5.53      |
| 40 000  | 2 077 | 220    | 3.03      |
| 100 000 | 5 191 | 412    | 1.49      |
| 180 000 | 9 343 | 742    | 1.13      |

40 000 digits is faster in *absolute* terms than 30 000, so Schonhage-Strassen
takes over between them, at roughly 1 600-2 000 limbs.

Extrapolating the flat part to 100 000 digits gives ~1 550 us for a GMP that
had stayed on Toom. It actually takes 412, so FFT is worth 3.7x there; our
2 500 us against that 1 550 is 1.6x, and that 1.6x is base case, glue and
assembly.

Of the 6.1x multiply gap at 100 000 digits, then, 3.7x is algorithm and 1.6x
is code. NTT is not a >=10^6-digit concern - it is the largest single lever at
the sizes we already benchmark, and it makes Toom-4 (which by the tree-shape
argument above would be worth a couple of percent on `pi`) not worth doing.

### Burnikel-Ziegler padding has to survive every halving

Found while making the above change, and worth recording separately because it
had nothing to do with `pi()`: `BigInt` division was losing its asymptotics on
about half of all operand sizes.

`_bz_two_by_one_slices()` bails out to schoolbook Knuth D when the block size
`n` is odd. That is correct - Knuth D gives the right answer at any size - so
nothing failed; it just meant the recursion could stop one step in. `n` was
rounded up only to even, and evenness does not survive halving. A 20 762-word
divisor is even, its half is 10 381, and the very first recursive step
therefore ran a 10 381-word schoolbook division. Measured on 100 000-digit
operands: 81 ms, against 26 ms for the same operands one power of two smaller,
where the halving happened to stay even further down.

The fix is to pad to `n = j * 2^k`, with `2^k` the smallest power of two that
brings `j` down to the cutoff. Halving then stays even until it reaches `j`,
which is small enough that Knuth D is the right answer. That took the same
division to 18 ms.

`BigUInt` had the opposite version of the same problem. It padded to
`2^k * cutoff`, which always halves cleanly but rounds a 5 556-word divisor up
to 8 192 - both operands carry nearly 50% dead words through every level.
Deriving `j` from the divisor instead pads it to 5 632, and division is 20%
faster from 10 000 digits up.

Two lessons. First, a performance bug that hides behind a correct fallback path
produces no test failure and no exception; the only symptom is a timing curve
with a step in it, which is why the division benchmark now sweeps sizes rather
than checking one. Second, the padding rule and the recursion's base case are
one decision, not two - the base case's condition (`n` odd) is what determines
what the padding has to guarantee, and they were written far enough apart in
the file to be changed independently.

### Two size points are not a size sweep

`floor_divide_by_uint128()` dropped the quotient of its leading partial group
for over a year: a three-word divisor lost a factor of 10^9 when the dividend
had `4k + 3` words, and crashed outright when the dividend *was* the leading
group. `BigUInt("23334504672441144935") // BigUInt("1854056525350022197")`
faulted.

Both randomized division cross-checks against Python used fixed sizes —
2 214 digits over 810, and 200 000 over 14 000. `random_decimal_string(n)`
counts 18-digit chunks, not digits, so both are far above
`CUTOFF_BURNIKEL_ZIEGLER` and both take the B-Z path. The whole
`len(y.words) <= 4` branch had no randomized cross-check at all.

The dispatch has four branches and the three-or-four-word one behaves
differently for each residue of the dividend length mod 4. Two samples cannot
cross that. `test_biguint_divide_across_the_dispatch_boundaries_against_python`
now walks divisor 1-40 digits against dividend up to 90.

### Passing one pointer as both source and destination

The exclusivity checker rejects `kernel(p, p, ...)` when the destination
parameter requires `Origin[mut=True]`: `list.unsafe_ptr()` carries
`origin_of(list.words)`, and two arguments tied to the same origin, one of them
mutable, is an aliasing error even when the aliasing is the whole point of an
in-place loop. `list._data` yields the same address without the origin, so
`kernel(x._data, x._data, ...)` compiles. Used by every in-place add/sub kernel
in both types.

Reading a `UInt32` array two words at a time needs
`ptr.unsafe_bitcast[UInt64]().unsafe_load[alignment=4](i)`. Without the
explicit alignment the load claims 8-byte alignment, which a slice starting at
an odd word offset does not have — and the Karatsuba and Toom-3 helpers pass
exactly those.

### `_data` is not a substitute for `unsafe_ptr()` on an appended list

`list._data` reads the wrong address for a list built with `append()`: the
element at index 0 comes back as zero while every later index reads correctly.
It cost an afternoon in the NTT twiddle table, where the first entry of the
root-of-unity table is `w^0 = 1` and silently became `0`. `unsafe_ptr()` is
right in every case; `_data` is only for the one situation described above,
where an origin would trip the exclusivity checker, and those lists are all
built with `resize(unsafe_uninit_length=...)`.

### Where the NTT actually wins, and where it does not

Per-stage timings for `pi(1000000)`, in milliseconds, before and after the
transform landed:

| Stage                     | before | after |
| ------------------------- | ------ | ----- |
| binary splitting          | 627    | 436   |
| base 2^32 -> 10^9         | 206    | 204   |
| final division, binary    | 145    | 135   |
| `sqrt(10005)`             | 62     | 44    |
| final multiplies          | 56     | 25    |
| scaling multiply          | 52     | 12    |
| `5^s`                     | 26     | 15    |

Every stage that is a multiplication moved. The two that did not are the two
that are divisions, and the reason is worth recording: Burnikel-Ziegler is
built out of multiplications, but of operands half the size and smaller, where
the transform's advantage has not opened up yet, and its own constant did not
change. Division measured 2.64x a same-size multiplication before the
transform and 4.9x after — the denominator got cheaper and the numerator did
not. That inverts the earlier assessment of reciprocal-Newton division: it was
worth about 4% of `pi` when division was 2.64x a multiply, and it is worth
about 20% now.

### A missing `return` in `subtract_inplace()`

Found while checking a Copilot review comment on PR #271 (which was itself
right: the B-Z block guard tested `len(a.words)` where `t` counts blocks of
`normalized_a`).

```mojo
if comparison_result == 0:
    x.words.resize(unsafe_uninit_length=1)
    x.words[0] = UInt32(0)   # Result is zero
elif comparison_result < 0:
    raise OverflowError(...)
# ... and then falls straight through into the general subtraction
```

With no `return`, the equal case sets `x` to one zero word and then subtracts
`y` from it: the vectorized loop runs over `len(y.words)` words, reads and
writes past the end of `x`, and `normalize_borrows()` tidies the garbage into
something that looks like a number. `x -= x` returned `877910460` for one
18-word operand.

It reached past `-=`. B-Z's schoolbook base case computes `a_slice -= q *
b_slice`, and a block that divides exactly makes those equal, so `//` and `%`
returned wrong quotients: 676 wrong in 5 148 over a sweep of
`b * (10^9)^k + j * (b - 1)`.

Two lessons. Test every in-place op against its out-of-place twin over a grid
of widths, *including equal operands* - that differential is now
`test_biguint_inplace_arithmetics_match_out_of_place`. And random dividends
never land on the recursion's internal block boundaries, so structured
adversarial inputs are the only thing that finds this class of bug.

### A Newton schedule reaches `seed * 2^n`, and nothing caps it

Two bugs in `sqrt_via_reciprocal_iteration()` and `isqrt_via_reciprocal_seed()`,
caught while measuring the above, both of which returned the full requested
digit count with a wrong tail and raised nothing.

The iteration `r <- r * (3 - x * r^2) / 2` doubles the correct digits. It does
*not* get pulled up to whatever precision the arithmetic inside it runs at, so
`n` iterations return `seed * 2^n` digits and no more. Both functions built
their schedule by halving from the target down to 20, which credits the seed
with 20 digits; and both seeded with `x ** -0.5`, which goes through `exp`/`log`
and is accurate to about ten digits for some inputs while being exact for
others. Instrumented, `sqrt_via_reciprocal_iteration(1234.5678, 1500)`:

| iteration precision | 34 | 58 | 106 | 201 | 392 | 773 | 1535 |
| ------------------- | -- | -- | --- | --- | --- | --- | ---- |
| correct digits      | 19 | 38 | 78  | 156 | 312 | 624 | 1248 |

Clean doubling from a ten-digit seed, never once reaching the precision the
iteration was nominally running at. The schedule now halves down to
`_F64_SEED_DIGITS`, and the seed is `1 / sqrt(x)`, which is correctly rounded.

The reason this survived so long is that both dials have to be wrong *and* the
schedule has to land badly. `sqrt_via_reciprocal_iteration(10005, 1000)` and
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
`tests/test.sh` runs `DECIMO_TEST_JOBS` of them concurrently, buffering each
file's output and replaying it whole, in the original order, so the transcript
is unchanged:

| `DECIMO_TEST_JOBS` | `test.sh decimo` | `test.sh all` |
| ------------------ | ---------------- | ------------- |
| 1                  | 67.4 s           | 68.4 s        |
| 4                  | 21.4 s           |               |
| 8                  | 13.3 s           | 15.2 s        |
| 14 (= `hw.ncpu`)   | 10.6 s           | 13.1 s        |

Same 1062 passing tests either way, and the normalised transcripts are
identical. Note that these numbers all assume a warm cache: the first run after
`src/decimo` changes recompiles every test file and takes ~320 s sequentially.

The default is the machine's logical CPU count, from `nproc` or from
`sysctl -n hw.logicalcpu` on macOS, falling back to 1 if neither is available.
A five-fold saving on every local run is worth more than an incrementally
arriving transcript, and the replayed output is byte-identical to the
sequential one anyway - it just all arrives at the end of the suite.

CI keeps the sequential default, keyed off the `CI` environment variable that
GitHub Actions and every other provider set. There, each suite is already its
own job on a runner with few cores to share, and when the only evidence of a
crash is a log file, a transcript that stops at the offending line is worth
more than one that has to be read backwards.

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
