# Decimo changelog

This is a list of changes for the Decimo package (formerly DeciMojo).

## 20260901 (v0.14.0)

Decimo v0.14.0 is a **Python and correctness** release, on top of a base change
in both integer types.

The Python package becomes a real drop-in for the standard library's `decimal`:
wheels for macOS and Linux, a full `Context`, every rounding mode but
`ROUND_05UP`, the whole method surface, and `Decimal128` beside `Decimal`.

Every transcendental now *decides* its rounding rather than assuming it — it
takes the interval its own error bound allows and checks that the whole of it
rounds to one answer — and the trigonometric functions size their argument
reduction to the argument instead of to a flat ninety-nine digits, which they
were silently wrong past.

`BigUInt` moves from base 10^9 to base 10^18 and `BigInt` from base 2^32 to
base 2^64, both gain a number-theoretic transform, and small values now live
inside the struct. Multiplication, division, addition and text conversion are
each 2-3x faster, `BigDecimal.pi()` four orders of magnitude, and `BigInt` is
ahead of CPython's `int` on every large operation. It is measured against GMP
now, which is the comparison it should be held to. Seventeen bugs are fixed,
two of them present in released versions.

The measurements are in [docs/benchmarks.md](benchmarks.md); the reasoning
behind them is in [docs/internal/internal_notes.md](internal/internal_notes.md).

### ⭐️ New in v0.14.0

**The Python package**:

1. **Wheels for macOS and Linux**, CPython 3.13 and 3.14 — macOS arm64
   (macOS 11 and later) and Linux x86_64 and arm64 (glibc 2.35 and later).
   The Mojo runtime libraries travel inside the wheel, so nothing else is
   needed. `pixi run -e py313 release` (or `py314`) builds one;
   `release_python.yaml` builds the set and uploads through PyPI trusted
   publishing. A tag publishes a release, a commit on `main` publishes
   `<version>.devYYYYMMDDHHMMSS`, and a tag that disagrees with `pixi.toml`
   stops the run. The library is compiled and tested on Linux now too — a
   wheel for a platform nothing had ever run on is not one anyone should
   install.

1. **Every rounding mode.** `getcontext().rounding` accepts all seven but
   `ROUND_05UP`, and arithmetic, `quantize`, `round(x, n)` and
   `to_integral_value` follow it exactly, checked against `decimal` digit for
   digit. `Context` is a value until installed, as in `decimal`;
   `localcontext()` takes keyword overrides; `BasicContext` and
   `ExtendedContext` exist. On the Mojo side `add`, `subtract`, `multiply`,
   `true_divide` and the in-place forms take a `rounding_mode`.

1. **The rest of `decimal`'s surface.** Keyword arguments where `decimal`
   takes them (`quantize(exp, rounding=...)` and the rest);
   `Decimal((sign, digits, exponent))`, which closes the `as_tuple()` round
   trip; `pow(x, y, modulus)` by modular exponentiation; the sixty `Context`
   methods that compute without disturbing the current context; and
   `remainder_near`, `next_plus`, `next_minus`, `next_toward`, `shift`,
   `rotate`, the four `logical_` methods, `logb`, `compare_total`,
   `compare_total_mag`, `compare_signal`, `max_mag`, `min_mag`,
   `number_class`, `to_integral_exact`, `is_normal`, `is_subnormal`,
   `is_qnan`, `is_snan` and `from_number` — all checked against `decimal`.
   The arithmetic lives in Mojo, in the new `decimo.bigdecimal.spec`; the four
   answers that need an `Emin` are finished in the Python layer, since
   decimo's exponents are unbounded.

1. **`decimo.pi()` and `decimo.e()`**, to the context precision or to the
   digits asked for: `decimo.pi(1000)`. `decimal` has neither.

1. **`sqrt`, `exp`, `ln` and `log10` are always half to even**, which is what
   `decimal` does with them; `**` still follows the context mode, also as
   `decimal` does. All four additionally take decimo's own `rounding=`, which
   `decimal` has no equivalent of, and are correctly rounded under whichever
   mode applies.

1. **Every operation applies the context, as in `decimal`.** `abs()`, `max`,
   `min`, `normalize`, `scaleb`, `fma` and the remainder from `%` and `divmod`
   were returning an exact value where `decimal` returns a rounded one. `fma`
   is also exact now where it went through `*` and `+`, which round at each
   step; `x ** n` and `exp` no longer come back one digit wide when the
   rounding carries.

1. **`Decimal128` in Python**, as `decimo.Decimal128` (`Dec128` for short):
   96 bits of coefficient and a scale from 0 to 28, in sixteen bytes that own
   nothing. It does arithmetic, compares, hashes, rounds, copies, pickles and
   formats like `Decimal`, takes an `int`, a `float` or a `str` on either side
   of an operator, and carries the methods and the mathematics — `quantize`,
   `as_tuple`, `fma`, `sqrt`, `exp`, `ln`, `log10`, all six trigonometric
   functions, the IEEE 754 bytes. Its hash agrees with `int`, `float`,
   `decimal.Decimal` and `Decimal`, so the four are interchangeable as
   dictionary keys, and a mixed expression settles in the wider type:
   `Decimal128 + Decimal` is a `Decimal`, either way round.

   Its results never allocate. Nanoseconds against `Decimal` and
   `decimal.Decimal`: addition 46 / 67 / 73, multiplication 57 / 92 / 85,
   division 114 / 225 / 133, construction from text 116 / 160 / 136, `str`
   118 / 437 / 67. A worked invoice — three lines quantized to cents, with
   tax — is 633 / 713 / 705. `str` is the one that is slower.

1. **Four conversions no longer go through a string.** `hash()` is a `tp_hash`
   slot reducing the coefficient over its own words (493 ns to 33),
   `Decimal(x)` copies the struct when `x` is already one (348 to 89), `int()`
   uses `PyLong_FromSsize_t` for anything that fits a machine word (295 to
   77), and `float()` no longer imports `builtins` on every call (342 to 179).

**`Decimal128`**:

1. **The IEEE 754 decimal128 interchange format.** `decimo.ieee754` encodes and
   decodes the sixteen bytes in the binary integer decimal layout — what
   MongoDB's BSON `decimal128` and Intel's library store — with
   `Decimal128.to_ieee754()`, `from_ieee754()`,
   `BigDecimal.to_ieee754_decimal128()` and `from_ieee754_decimal128()` on top.

   It is a codec and brings no IEEE arithmetic with it. Trailing zeros are part
   of the encoding and are kept, so `1.0` and `1` are one number and two
   patterns. Every `Decimal128` fits the format and every decimal128 fits a
   `BigDecimal` exactly; coming the other way into a `Decimal128` rounds to
   nearest and refuses what is too large, and an infinity or a NaN is refused
   by name. Densely packed decimal is not read here.

1. **Trigonometry.** `sin`, `cos`, `tan`, `cot`, `sec` and `csc`, as functions
   and as methods, correctly rounded across the whole range the type holds.
   The work is the argument reduction: `Decimal128` reaches `7.9E+28`, so
   subtracting `k * (pi/2)` with the 28-digit quarter turn the type itself
   holds answers a different question than the caller asked — at `1E+20` only
   8 digits of the remainder are right, and at `1.2E+27` only one. The quarter
   turn is kept here in four exact pieces of 38 digits, and what the
   subtractions leave is measured rather than assumed. 881 checks against a
   reference built on CPython's `decimal` at 140 digits: none wrong.

**Rounding that is decided rather than assumed**:

1. **`exp`, `ln`, `log10`, `**`, `sin`, `cos` and `tan`** computed a fixed
   number of digits beyond what was asked and rounded once, which is right
   whenever the discarded tail happens to miss a boundary and silently wrong
   when it does not — for the default half to even as much as for a
   directional mode, since a tie is just another boundary. They now take the
   interval their own error bound allows and check that the whole of it rounds
   to one answer, widening and asking again when a boundary falls inside. Each
   states its bound instead of carrying its own guess. `sqrt` needs no loop: a
   root is algebraic, so `isqrt` of the scaled coefficient, nudged off `0` and
   `5`, is already correctly rounded under every mode.

   About 12% on `exp` at 28 digits and 1% on the trigonometric functions; a
   second attempt is needed on about eight calls in a thousand. Checked over
   seventeen thousand cases against `decimal` at forty digits beyond the
   precision, and twenty-one thousand for `sqrt` against exact rational
   arithmetic.

1. **`arctan`, `cot`, `csc` and `sec` decide theirs too.** They were the last
   ones adding nine guard digits and rounding once. An argument built to catch
   that — a value whose 29th digit is a 5, put through the inverse function
   — had `arctan` come back one unit low and `log10` one unit high. Both are
   correct now, and the arguments are pinned as tests.

1. **The trigonometric reduction budget is measured, not guessed.** An argument
   close to a multiple of `pi/2` loses digits to the subtraction there, by as
   much as it is close, and no constant can cover that: `sin` of pi taken to
   250 digits is `1.456...E-250`, and the library returned `3.904...E-127` — a
   number with no digit of the answer in it. `budget_for()` now measures the
   distance to the nearest multiple, at a narrow width first since almost no
   argument is near one, and widens when the measurement comes back at its own
   noise floor. The measurement is the reduction the function was going to do
   anyway, so an argument nowhere near a multiple pays nothing: `sin(1.5)` is
   18.7 us, where a separate probe made it 20.1.

**Integers**:

1. **`BigInt` keeps small values inside the struct.** `WordList`, written for
   `BigUInt`, gains an inline-capacity parameter and moves to
   `decimo.wordlist`; `BigInt` uses it under the name `Magnitude`, at seven
   words after the move to base 2^64 — the sum of two hundred-digit values.
   Addition at a hundred digits goes from 40.3 ns to 11.2 ns and division from
   406 ns to 296 ns. Above a thousand digits nothing moves.

1. **`BigInt` is measured against GMP.** `docs/benchmarks.md` times GMP in C
   alongside libmpdec, which is the comparison a big-integer library should be
   held to; CPython's `int` can only be reached through the interpreter and
   loses on call overhead before the arithmetic starts. GMP wins most rows.
   The exception is small values, where an `mpz_t` still goes to the heap and
   decimo no longer does: at ten digits decimo is 2.45x faster at addition and
   1.94x at multiplication. What is left is written down in
   `docs/internal/todo.md`.

1. **`BigInt.sqrt()` gains Zimmermann's recursion.** Above 64 words it uses the
   Karatsuba square root of INRIA RR-3805 instead of CPython's
   precision-doubling: the division at the last step is half the width, and the
   remainder falls out of the recursion. At 10 000 digits 50.0 us against
   87.8, and at 100 000 digits 1297 us against 2417. Below the crossover the
   older path still wins and stays, as the recursion's base case.

1. **`BigUInt` multiplication gains a number-theoretic transform.** Toom-3 was
   the largest algorithm available to it, so `BigDecimal` multiplication was
   stuck at O(n^1.465) while libmpdec switches to a transform.
   `decimo.biguint.ntt` supplies that tier, reusing the field arithmetic in
   `decimo.bigint.ntt` — only the packing differs, since a decimal magnitude
   can only be cut at a power of ten. At 100 000 decimal digits multiplication
   goes from 4.53 ms to 2.58 ms, and division follows, 16.53 ms to 13.74 ms.

**Conversions** (PR #269):

1. **`Rational` conversions.** Constructors from an integral scalar, a `String`
   and a `BigDecimal`; the factories `from_string()`, `from_integral_scalar()`,
   `from_float_scalar()` and `from_bigdecimal()`; and the outbound `__int__()`,
   `__float__()`, `to_int()`, `to_integer()`, `to_float()` and
   `to_bigdecimal()`.

1. **`from_integral_scalar()` and `from_float_scalar()`** on `BigInt`,
   `BigDecimal`, `Decimal128` and `Rational` — one pair of names across the
   library, constrained with `where` clauses rather than `comptime assert`, so
   the wrong scalar kind is an overload mismatch and not an assertion. Plus
   `BigInt.from_biguint()` / `to_biguint()` and `BigInt10.from_bigint()` /
   `to_bigint()`.

### 🦋 Changed in v0.14.0

**Allocation, and the small operations it dominates**:

1. **Heap blocks are reused instead of freed.** `alloc` and `dealloc` together
   cost about 36 nanoseconds whatever the size, so every value too long to sit
   inside the struct paid the same toll — a six-word addition spent more than
   half its time there. A released block now goes on a small stack sorted by
   size, and the next request of that size takes it back.

   A six-word addition is 22.0 ns against 43.8, a 200-word copy 28.5 against
   54.3, a 200-by-20 division 1.98 us against 3.17, and a 60-digit
   `BigDecimal` division 177 ns against 262. A large multiplication does
   enough work to hide its own allocation, so 200-by-200 moves by 3 percent.
   Values that fit inside the struct never reach the pool. The pool is
   process-wide, holds at most eight blocks per size (about 500 KB in all),
   and is shared under an atomic flag, so two threads never see one block.

1. **Small operations are about twice as fast.** At these sizes the library
   spends ~4 ns on arithmetic and ~33 ns per allocation, so an operation's
   speed is very nearly its allocation count — and several were allocating for
   nothing: `add()` and `subtract()` scaled both coefficients when only one
   ever needs it, a buffer was sized exactly and then grown, `multiply()`'s
   single-word paths copied the other operand before growing the copy, and
   three `debug_assert` calls built their message with `+ String(n)`, which
   allocates even with assertions compiled out (modular/modular#6439).
   Add 1.90x, subtract 1.82x, multiply 2.06x, round 2.45x, divide 1.73x.

1. **`BigDecimal` construction no longer copies its coefficient.** The
   component constructor took `coefficient` borrowed and then copied it, so
   every one of the 27 call sites already written as `coefficient=coef^` paid
   a full heap allocation for a move it had explicitly asked for. `a + b` on
   short operands goes from 73 ns to 43 ns; against libmpdec, multiply goes
   from 2.3x to 1.2x and add from 2.5x to 1.9x.

**Multiplication, division and roots**:

1. **Multiplication is 2-3x faster.** Toom-3 comes to `BigInt`, which had
   stopped at Karatsuba while `BigUInt` has had it since v0.10.0. The
   schoolbook base case is rewritten to product scanning — it walks the result
   one word at a time and sums each column in `UInt128` accumulators, so the
   column stays in registers — and then packed into base-2^64 limbs, which
   quarters the word pairs. Both crossovers were re-swept afterwards, worth
   another 20% on their own. At 100 000 decimal digits a `BigInt` product goes
   from 7.7 ms to 2.3 ms and a `BigUInt` product from 11.8 to 6.0.

1. **`BigInt` multiplication gains a number-theoretic transform.** Above
   Toom-3 the product is evaluated as a cyclic convolution modulo the
   Goldilocks prime `2^64 - 2^32 + 1`, which brings the exponent down from
   `n^1.465` to `n log n`. One prime, so there is no CRT step. Two choices
   carried most of the speedup: the chunk width is left free rather than fixed
   at 16 bits, since the transform length has to be a power of two and the
   rounding up is pure waste; and the dispatch compares fitted cost models
   rather than a word count, because the transform's cost steps at powers of
   two while Toom-3's climbs smoothly. At a million digits multiplication goes
   from 54.7 ms to 24.0 ms.

1. **Addition and subtraction are 2-3x faster**, and the recursive algorithms,
   which are add-heavy at every level, inherit most of it. `BigInt`'s
   little-endian words are already base-2^64 limbs in pairs, so one 64-bit add
   does the work of two 32-bit ones (0.71 to 0.25 ns/word). A base-10^9
   `BigUInt` word carries by comparison against `BASE`, which put the carry on
   the loop-carried chain; both answers are now computed off that chain and
   the incoming carry only selects between them, in one pass rather than two
   (1.75 to 0.83 ns/word at 100 000 words). Exact division by three, which
   Toom-3 calls once per node, is split so its one division is off the chain
   too. `subtract_simd()` and `add_slices_simd()` are renamed
   `subtract_carry_select()` and `add_slices_carry_select()`, since neither is
   vectorized any more, and `normalize_borrows()` is gone.

1. **Division is 1.2x to 2x faster.** Knuth D was spending six of its own
   multiplications on work a multiplication does in one — at 500 digits, 2.50
   us against 0.42 for the 52x52 schoolbook multiply underneath it, for the
   same number of word products. Its multiply-subtract now runs two words at a
   time, and it no longer allocates a fifth word list for its remainder: the
   working dividend *is* the remainder by then. Against GMP, floor divide goes
   from 4.98x slower at 1000 digits to 2.87x, and at ten digits it reaches
   parity.

1. **`BigUInt` schoolbook division is 1.3-2x faster.** Each quotient word used
   to build `q * y` as a fresh `BigUInt`, shift it, compare it against the
   whole remainder and subtract it — four passes over the full dividend plus
   an allocation, per word. It is now a single fused multiply-subtract over
   the `n + 1` word window the quotient word touches. 2.0x at 100 digits, 1.5x
   at 300, 1.3x at 1 000.

1. **Burnikel-Ziegler starts where it begins to pay, and pads to `j * 2^k`
   words.** The cutoff was a 24-word divisor and the recursion does not earn
   its keep until about 48. Separately, the recursion falls back to schoolbook
   as soon as it meets an odd block, so the padding has to keep the block size
   even the whole way down; `BigInt` rounded up only to even, so a
   20 762-word divisor landed on schoolbook at the first recursive step and
   the algorithm lost its asymptotics — a 100 000-digit division took 81 ms
   where the same operands one power of two smaller took 26, and now takes 18.
   `BigUInt` was correct but carried up to 50% dead words through every level.
   `BigDecimal.true_divide()` at 20 000 digits goes from 4.49 ms to 3.83 ms.

1. **`sqrt_via_reciprocal_iteration()` is 1.6x faster at high precision.** The
   Newton step was the textbook `r * (3 - x * r^2) / 2`, whose second multiply
   is half-width by full-width. Written around the residual instead —
   `r + r * (1 - x * r^2) / 2`, algebraically the same — the correction is
   around `10^(-p/2)`, which a `BigDecimal` keeps in the scale rather than in
   the coefficient, so the multiply is half-width by half-width. At 100 000
   digits, 6.6 ms against 10.4.

**`pi()`, and the constants**:

1. **`BigDecimal.pi()` is four orders of magnitude faster.** Five changes, and
   they compound. The Chudnovsky binary splitting uses the `P`/`Q`/`T`
   recurrence, so each leaf is O(1); the leaves are built in machine
   arithmetic, since `P(k)`, `Q(k)` and `T(k)` all fit a `UInt128` below four
   million; the term count is sized to the precision rather than to a flat
   margin; the square root of 10005 is no longer taken exactly, which means
   nothing for a fixed non-square constant used as an intermediate; and the
   pipeline stays binary to the end, so the irrational factor enters as a
   *reciprocal* square root, which Newton reaches without a division.

   | digits  | before  | after   |
   | ------- | ------- | ------- |
   | 1 000   | --      | 71 us   |
   | 10 000  | 13.7 s  | 1.59 ms |
   | 100 000 | --      | 50.2 ms |

   100 000 digits was out of practical reach before. Digits are unchanged:
   exact against MPFR at every precision from 1 to 100 000. Everything that
   range-reduces against pi inherits the gain. With the transform and the
   faster addition and the block pool on top, `pi(1000000)` is 700 ms,
   ahead of pure-Python mpmath from 500 digits up.

1. **`ln` picks its series by how small the argument is, not how long it is.**
   The choice between the Taylor series and the atanh identity read the number
   of digits in `z = x - 1` and compared it to a tenth of the working
   precision. That is the wrong quantity: what decides the term count is `z`'s
   magnitude. `ln(2.3456789)` has eight digits but leaves `z = 0.34`, so it
   took the Taylor path at every precision above 71 and paid twice over. At
   100 digits, 17.4 us against 41.6 — 2.3 times faster than libmpdec, where it
   had been 1.83 times slower, the one row in the benchmarks where the
   logarithm lost.

**Text**:

1. **Reading a `BigUInt` from text is up to seven times faster.** The parser
   normalized every string first, writing a `List[UInt8]` of one digit per byte
   and reading it back into words. A string that is nothing but digits, which
   is nearly all of them, now goes straight into the words: one digit 10.7 ns
   against 78.5, nine 20.6 against 91.2, twenty-eight 46.8 against 118.4.

1. **A plain decimal string is parsed straight into the words.** The same for
   `BigDecimal` — a sign, some digits, at most one point: 59 ns to 10, 64 to
   19, and forty digits 114 to 74. Anything with an exponent or a separator
   still takes the general parser. `from_string` and the `Parsable` trait take
   a `StringSlice` now, so a substring or a foreign buffer costs no
   allocation, which is what lets the Python binding read CPython's own
   string: `Decimal("1.5")` 182 ns to 104, and a forty-digit literal 367 to
   163, which is where `decimal` is.

1. **Writing a `BigDecimal` out is two to four times cheaper.** The text was
   three allocations and two copies for what is one row of digits. The digits
   now go from the coefficient's words straight into one buffer — on the stack
   when the value is short enough — and `BigUInt` emits two digits per
   division against a table of pairs, halving the divisions.

   | Digits | `to_string()` before | after | `String(x)` before | after | `decimal` |
   | -----: | -------------------: | ----: | -----------------: | ----: | --------: |
   |      9 |                   21 |    15 |                 84 |    20 |        68 |
   |     28 |                  159 |    66 |                350 |    77 |        84 |
   |    100 |                  181 |   110 |                209 |   131 |       131 |
   |  1,000 |                  716 |   376 |                997 |   475 |       805 |

   From Python, `str(Decimal(...))` went from 423 ns to 108 against
   `decimal`'s 63.

1. **`String(BigInt)` is 1.3x to 1.9x faster above about 600 digits.** The
   divide-and-conquer conversion had its two thresholds derived rather than
   measured, and the derivation was wrong: what D&C buys is the balanced
   split, not large enough internal divisions, and that pays long before any
   division inside it reaches Burnikel-Ziegler. Measured, the entry threshold
   belongs at 64 words and the base case at 48. At 1233 digits, 18.80 us
   against 36.37.

1. **`BigInt.to_biguint()` no longer detours through a decimal string.** The
   divide-and-conquer conversion splits on powers of `10^18` instead of powers
   of `10`, so each half lands on a word boundary and its words go straight
   into the result.

**`Decimal128` internals**:

1. **Division is one wide division rather than a walk.** The quotient was built
   a digit at a time and could run out of digits before reaching the position
   the rounding needed: 1 in 300 random pairs was wrong in the last place. The
   numerator is now raised until the integer quotient is about thirty digits,
   divided once, and rounded from the remainder. That needed a 256-by-128
   divider — `udiv_u256_by_u128`, Knuth D over 64-bit limbs, 22 ns against the
   261 of the software shift-subtract loop it replaces. Division is 70 ns
   against 226, and correct on all 300 pairs.

1. **`Wide` is written once and used at two widths.** `WideValue[DIGITS]`
   carries the mantissa the series run on; `Wide` is 38 digits of it and
   `Extended` 75. The constants exist at both widths, and a test narrows each
   wide one to check it gives the narrow one exactly. The reciprocal divider
   `udiv_u256_by_pow10_gm` reaches `10^48` now, since normalizing a 76-digit
   product needs it, and the second width no longer falls back to software
   division: one 75-digit multiplication goes from 370 ns to 20, which takes
   the argument reduction from 3298 ns to 226.

1. **An exact integer power is known to be exact, and trailing zeros come off
   in one step.** A base of `d` digits raised to the `n`-th has at most `d * n`
   digits, so below the working width nothing is rounded and the answer needs
   no second look: `1.05^12` is one pass again rather than three. The zeros at
   the end were stripped one at a time, each a software divide of about 185 ns;
   halving finds them in five steps and one division.

**Other**:

1. **`Rational.__add__` and `__sub__` cancel before they multiply**, using
   Algorithm A of Knuth 4.5.1, so the result is in lowest terms without a
   second gcd over two full-width operands. Summing `1/k^2` to 1 200 terms
   goes from 123 ms to 3.1 ms. This pays because **`gcd()` now balances its
   operands** before entering Stein's binary loop, which makes about one bit of
   progress per full-width subtraction and so is quadratic when one operand
   dwarfs the other: `gcd(17 940-bit, 20-bit)` drops from 4.85 ms to 0.003 ms.

1. **`BigInt10` is no longer used by any other module.** Bridging goes through
   `BigUInt`, and `BigInt10` keeps its own conversions for code that still
   wants them (PR #269).

1. **`List._data` is no longer used anywhere.** All 63 sites moved to
   `unsafe_ptr()`, which returns the same address with an origin attached, so
   the library no longer depends on a private field of the standard library.
   No performance change. Restoring origins exposed twelve deliberate in-place
   aliases, which now say so through `alias_as_immutable_source()`.

1. **`tests/test.sh` runs in parallel by default.** `DECIMO_TEST_JOBS` defaults
   to the machine's logical CPU count, which takes `test.sh all` from ~68 s to
   ~13 s on 14 cores. CI stays at 1, since each suite is already its own job
   there. Test helpers that built large decimal strings by repeated appending
   now pre-size the `String`, and `decimo.tests` gains
   `random_decimal_string()`.

1. **The out-of-range message for `power_of_10_unsafe[uint256]` says 0..77.**
   It still said 0..58 after the table was extended.

### 🩹 Fixed in v0.14.0

1. **`sin`, `cos` and `tan` were wrong for a large argument, silently.** The
   reduction `x mod 2*pi` cancels everything above the remainder, so an
   argument of `10^k` spends `k` digits of pi before the remainder starts. The
   budget was a flat ninety-nine digits: right up to `10^99`, half wrong by
   `10^105`, and at `10^150` `sin` returned `-0.89395145461803107` where the
   true value is `-0.95074387683304597` — nothing correct in it, and nothing
   to say so. `reduction_digits()` now sizes the budget to the argument, and
   `cot`, `csc` and `sec` inherit it. Pinned against an independent
   computation up to `10^300`.

1. **`BigInt.sqrt()` never returned for values at the top of a word.** The
   one- and two-word paths refined a `math.sqrt` estimate with
   `while (guess + 1) * (guess + 1) <= value`. Near the top of the range that
   square overflows and wraps to something small, the test reads true forever,
   and the walk does not stop. `sqrt(2^32 - 1)` hung, as did 131 071 other
   single-word values and about 2^33 two-word ones. Both paths now go through
   `isqrt_uint64()`, which clamps the estimate first. **Present since v0.13.0,
   so released versions are affected.**

   That helper also stopped asking `math.sqrt` for an integer root — Mojo
   resolves that to a software integer square root, 21.3 ns against 0.45 — and
   four more places in `biguint.exponential` were asking the same way. Small
   `BigUInt.sqrt()` goes from 10.8 ns to 2.2 at one word.

1. **`BigUInt` division crashed, or silently lost a factor of 10^9, for
   three-word dividends.** `floor_divide()` routes a divisor of three or four
   words to `floor_divide_by_uint128()`, which consumes the dividend four words
   at a time; when the word count is not a multiple of four the leading group
   is short, and its quotient was discarded. A seven-word dividend over a
   three-word divisor came back a factor of 10^9 too small, and a three-word
   one produced a `BigUInt` with no words at all, which faults the next
   operation that reads `words[len(words) - 1]`. A sweep of dividend lengths
   one to nine against divisor lengths one to five had 80 wrong results in
   1 824. **Present since PR #111 (2025-07-23), so released versions are
   affected.**

1. **`BigUInt` in-place subtraction returned garbage when the two operands were
   equal**, and with it long division for a whole class of dividends.
   `subtract_inplace()` handled `x == y` by shortening `x` to a single zero
   word — and then fell through into the general path, which subtracted over
   `len(y.words)` words of a value now one word long, reading and writing past
   the end. `x -= x` returned `877910460` for one 18-word operand. The reach
   went past `-=`: Burnikel-Ziegler's base case computes its remainder as
   `a_slice -= q * b_slice`, and a block that divides exactly makes those two
   equal, so `//` and `%` returned wrong quotients whenever the recursion met
   such a block — 676 wrong results in a 5 148-case sweep, and none now. The
   fix is a `return`. `BigInt`, `BigDecimal` and `gcd()` have their own
   subtraction and were never affected.

1. **Toom-3 wrote one word past the end of its result buffer for lopsided
   operands.** A three-way split sizes its limbs by the longer operand, so a
   short second operand can have empty high limbs while `4 * m` — where the
   `w4` coefficient is recomposed — runs past the end of the result. With 513
   and 129 words, `4 * m` is 684 against a 642-word buffer. `w4` is zero in
   exactly those cases, so it wrote a zero out of bounds and no value
   comparison could see it. `BigUInt`'s Toom-3 was never affected. Found by
   Copilot on PR #273. `_add_at_offset_inplace()` now states the precondition
   and asserts it, so the suite catches any recurrence.

1. **`sqrt_via_reciprocal_iteration()` returned fewer correct digits than asked
   for**, from two causes: the iteration schedule halved down to 20, crediting
   the seed with more digits than it carries, and the seed itself was
   `x ** -0.5`, accurate for some inputs to only about ten digits. Together
   these left `sqrt_via_reciprocal_iteration(1234.5678, 1500)` correct to 1248
   of 1500 digits, with the full digit count returned and nothing raised.
   `isqrt_via_reciprocal_seed()` shared both and was hiding them behind
   full-size corrective divisions, so `sqrt_exact()` is about 30% faster now.

1. **`Decimal128`'s `exp`, `ln`, `log10` and `sqrt` were wrong in the last
   digits.** All four summed their series in `Decimal128` arithmetic, which
   rounds to 28 digits after every term, so the answer inherited every one of
   those roundings. Against CPython's `decimal` at 70 digits, `ln` was out on
   108 of 200 random arguments, `log10` on 126, `sqrt` on 75, and `exp` by up
   to four units in the last place. The series now run in a fixed-width
   accumulator carrying ten digits more than `Decimal128` holds, and the
   answer is rounded once: 0 wrong in the same 720 checks. `sqrt` no longer
   refines a floating estimate at all — it scales the coefficient, takes an
   integer square root, and says whether the root was exact. `Decimal128`
   still imports nothing from `BigDecimal`; the accumulator is 38 digits in a
   `UInt256`, inside `decimal128` itself.

1. **`Decimal128`'s powers and roots were wrong in the last digits.** `x^y`
   went through `exp(y * ln(x))` with the logarithm and the product each
   rounded to 28 digits on the way, and an absolute error in `y * ln(x)` is a
   relative error in the answer: 51 of 60 random arguments were wrong, by up
   to 40 units in the last place, and `1.0001^10000` by 84. The integer path
   was wrong on 22 of 40 and `root` on a quarter of the arguments tried. All
   three now compute at 38 digits and round once, and run again at 75 when the
   digits below the answer do not settle it. 540 checks against `decimal`:
   none wrong. A power or root that comes out whole stays whole.

1. **`Decimal128`'s logarithms and exponentials decide their rounding.** When
   the value sits on a boundary within the computation's own error, the whole
   thing runs again at 75 digits, which has forty-six digits below the answer
   instead of nine. Two arguments found by searching three million:
   `ln(6215888314.385201)` continues `...0245000017266`, seventeen hundred
   units past a boundary the first width can only place to within two
   thousand, and `log10(5120760.203168846)` continues `...1444999949`. The
   wider pass runs on about one call in a quarter million and costs 55 us when
   it does, against 0.8 for the ordinary path. It used to abort rather than
   answer, because shifting a 75-digit mantissa asks for powers of ten up to
   `10^74` and the reciprocal divider's table stopped at `10^48`.

1. **`ln` of a value close to one lost most of its digits.** The reduction
   wrote `x` as `m * 2^p * 10^q` and added `p * ln(2) + q * ln(10)` back at the
   end. For `x` just under one those three terms are each about two while
   their sum is `1E-14`, so fourteen of the digits carried went into
   cancelling them out. Arguments already in `[0.5, 2)` now go straight to the
   series.

1. **A computed value whose dropped digits were all zeros claimed to be exact.**
   `to_decimal_decided` refused to round when the digits below the answer sat
   near a boundary, but treated a remainder of exactly zero as settled however
   much room the computation had asked for. Zero *is* the boundary: with room
   to be wrong the true value may sit either side of the multiple, and the
   claim decides whether the trailing zeros are dropped.
   `cos(0.0000000001)` printed `0.999999999999999999995`, saying the value
   terminates there, where it continues `...41666` at the 41st digit.

1. **A value too large for `Decimal128` came back with a scale of four
   billion.** When more digits had to be dropped than there were places after
   the point, the scale went negative and wrapped. Nothing reached it before:
   `exp` refuses its argument above 66.54 and a logarithm is small. `tan` of
   an angle a hair past a pole reaches it, and now raises `OverflowError`.

1. **A value below the smallest scale returned zero instead of rounding.**
   `ln(1.0000000000000000000000000001)` is `9.99...E-29`, whose every digit
   sits below the `1E-28` that `Decimal128` stops at. Rounding them says
   `1E-28`; the conversion returned zero whenever the digits being dropped
   were all of them.

1. **The digit count stopped at 58 and returned 59 for anything larger.**
   `number_of_digits` covered the 58-digit product of two `Decimal128`
   coefficients and answered wrongly, rather than refusing, above that. It now
   covers both types to the top, and is about sixty times faster: the old
   binary search compared against `10 ** k`, which is not folded for 128- and
   256-bit scalars and so was built at run time by repeated multiplication —
   330 ns against 5.

1. **Burnikel-Ziegler's "add one more block" guard tested the wrong length.**
   It compared `len(a.words)` against `t * n` while `t` counts blocks of the
   *normalized* dividend, which the normalization has usually lengthened, so
   the guard fired more or less at random. It now tests the normalized length,
   as `BigInt`'s copy of the algorithm always has.

1. **The in-place single-word divisions left a `BigUInt` with no words at all**
   when the quotient was zero, and `floor_divide_by_word_inplace()` read its
   loop bound from the already-shortened list, skipping a word whenever the
   leading word was smaller than the divisor. Neither is called anywhere in the
   library today; the out-of-place versions that `//` uses were correct.

1. **`BigUInt.is_two()` could not return `True` for any value.** It asked for a
   two-word value and then for the second word to be zero, which the
   no-leading-zero invariant forbids; `words[0]` was never compared against 2
   at all. It has no callers in the library, which is why nothing caught it
   (issue #312).

### 🗑️ Deprecated in v0.14.0

1. **`BigDecimal.from_float()` and `Decimal128.from_float()`** are deprecated in
   favour of `from_float_scalar()`, the name that lines up with
   `from_integral_scalar()`. They forward unchanged (PR #269).

### 💥 Breaking in v0.14.0

1. **`BigUInt`'s words are `UInt64`, and its base is 10^18.** It held nine
   decimal digits in a `UInt32` and now holds eighteen in a `UInt64` — the
   same digits per byte, half the words. `BigUInt.words`, `Coefficient` and
   `BigUInt(raw_words=...)` all follow, so `raw_words=` takes a `List[UInt64]`
   and a list literal becomes `[UInt64(1)]`. Write `BigUInt.Word` for the type
   of a coefficient word and `BigUInt.DIGITS_PER_WORD` for how many digits it
   holds, rather than a literal `UInt32` or `9`. Values, strings and every
   arithmetic result are unchanged; only the representation is. Add 1.06x to
   1.54x, multiply up to 2.91x, divide up to 2.16x.

1. **`BigInt`'s words are `UInt64`, and its base is 2^64.** `BigInt.words`,
   `Magnitude` and `BInt(raw_words=..., sign=...)` all follow. Code that reads
   or builds the magnitude directly has to change: a list literal becomes
   `[UInt64(1)]`, shifting by 32 becomes shifting by 64, masking with
   `0xFFFF_FFFF` becomes masking with `0xFFFF_FFFF_FFFF_FFFF` or dropping the
   mask, and a word count derived as `(bits + 31) // 32` becomes
   `(bits + 63) // 64`. Values, strings and every arithmetic result are
   unchanged; only the representation is. It held its words in base 2^32 while
   doing all its arithmetic in 64-bit registers, so schoolbook multiplication
   and Knuth D both made twice the passes they needed to: floor divide 1.99x
   at ten digits and 1.86x at a thousand, sqrt 1.76x and 1.41x.

1. **`BInt(raw_words=..., sign=...)` takes a `Magnitude`, not a
   `List[UInt32]`.** That is the inline word storage `BigInt` moved to, and the
   constructor moves into it rather than copying. A list literal still works
   unchanged; an existing `List` goes in as
   `BInt(raw_words=Magnitude(words^), sign=False)`. `Magnitude` is exported
   from `decimo`.

1. **The `Integer` alias for `BigInt` is removed.** `BInt` remains, and matches
   `BDec` and `Dec128` in shape. `Integer` named a general concept rather than
   one concrete type, and collided with the ordinary English word used
   throughout the documentation. Replace `Integer` with `BInt` or `BigInt`.

1. **`gcd()` and `BigInt.gcd()` are now `raises`.** They take a remainder on
   unbalanced operands, and `BigInt` division raises. Callers already inside a
   `raises` function need no change.

1. **`product_range()` caps the number of factors, not the size of the
   bounds.** Its old bound, `high <= 2^32 - 1`, was there because each factor is
   cast to a word; every non-negative `Int` fits a word now. The cap is
   `FACTORIAL_MAX_INPUT`, the same one `factorial()` and `permutation()`
   already answer to.

1. **`BigInt.from_bigint10()` and `BigInt.to_bigint10()` are removed.** Use
   `BigInt10.from_bigint()` and `BigInt10.to_bigint()` (PR #269).

## 20260822 (v0.13.0)

Decimo v0.13.0 is a **traits** release. `Numeric`, `Parsable` and `Rootable`
let code be written once and run over `BigInt`, `BigUInt`, `BigDecimal`,
`Decimal128` and `BigFloat` alike — a matrix library asking for
`T: Numeric & Rootable` is the motivating case. `BigInt` gains `/`. The errors
module is reworked so that the error kinds are functions returning a plain
`Error`, which is a breaking change for code that spells a typed raise such as
`raises ValueError` in its own signatures.

### ⭐️ New in v0.13.0

**Traits (`decimo.traits`)**:

1. **`Numeric`** — `zero()`, `one()`, `-x`, `+`, `-`, `*` and `/`, conformed to
   by `BigInt`, `BigDecimal` and `Decimal128`. Enough for the whole of dense
   linear algebra. Every operation is declared `raises`, the widest signature,
   so a non-raising implementation conforms unchanged (PR #265).
1. **`Parsable`** — the static `from_string()`, and the counterpart of
   `Writable`: it lets a container be filled from a literal without knowing
   which number type it holds. Same three types (PR #266).
1. **`Rootable`** — `sqrt()`, conformed to by five types, `BigUInt` and
   `BigFloat` included. It is separate from `Numeric` because those two can
   never be `Numeric`: `BigUInt` is unsigned and so has no `__neg__`, and
   `BigFloat` is `Movable` without being `Copyable`. What the root means stays
   the implementing type's business — on an integral type it truncates, so
   `BigInt("10").sqrt()` is `3`, and a negative value raises on the four exact
   types but yields `nan` on `BigFloat` (PR #268).

**Other additions**:

1. **`BigInt.__truediv__`** — `/` on integers is closed and truncates toward
   zero, matching Mojo's own `Int`: `BInt(-7) / BInt(2)` is `-3` where
   `BInt(-7) // BInt(2)` is `-4`. The two operators differ exactly when the
   operands have opposite signs (PR #265).
1. **`BigDecimal.zero()` / `one()`** and **`Decimal128.zero()` / `one()`**, the
   `Numeric` spelling of the identities. `Decimal128.ZERO()` and `ONE()` stay
   as they are (PR #265).
1. **`PRECISION`** (28, the same default as Python's `decimal`) is exported
   from the top level, so a caller can name the default it is getting (PR
   #268).

### 🦋 Changed in v0.13.0

**Errors** (PR #267):

1. **The error kinds are now functions**, not aliases for a parametrised
   payload type: `ValueError`, `OverflowError` and the rest return a plain
   **`Error`**, so an enclosing function needs nothing beyond a bare `raises`.
   Raise sites are unchanged, but a signature can no longer be spelled
   `raises ValueError` — a typed raise is invariant in Mojo v1.0.0, which cuts
   such a function off from `std.testing` and from any ordinary helper.
   `BaseError` is now the payload only.
1. A new comptime toggle **`_USE_COLOUR`** blanks every ANSI escape, for when
   the tracebacks go to a log file rather than a terminal. Chained tracebacks
   gain a blank line after the separator, and a frame now names the function it
   was raised in.

**Signatures** (PR #268):

1. **`BigDecimal.sqrt()`** splits its defaulted `precision` into the overloads
   `sqrt(self)` and `sqrt(self, precision)`, since in Mojo a default argument
   does not satisfy a trait signature. Existing calls are unaffected.
1. **`root()` converges on one spelling**, `root(self, n: Int)`, which
   `BigDecimal`, `Decimal128` and `BigFloat` now all accept. `BigDecimal` keeps
   its `BigDecimal`-degree overloads for non-integral roots and `BigFloat` its
   `UInt32` one. Every existing call keeps working. `root` is deliberately not
   part of `Rootable`: `BigInt` and `BigUInt` have no nth root to offer.

**Documentation and tooling:**

1. Markdown across the repository is **reformatted** — long lines rewrapped and
   list formatting made uniform — and **`argmojo`** is an active Pixi
   dependency again, pinned to `>=0.8.0,<0.9.0` now that modular-community
   ships it (PR #264).
1. The user manual's **Appendix B** documents the three traits and which types
   conform; the `BigInt` division section covers the new `/` (PR #265, #266,
   #268).
1. The test suite **`numeric` is renamed to `traits`**, with `numeric` and
   `num` kept as aliases and the tests moved to `tests/traits/` (PR #266,
   #267).
1. **`tests/test.sh` bug fix**: the retry loop read `$?` after an `if`, which
   is the `if` statement's own status — zero — so a suite that failed to
   compile was reported as passing. It now uses `&&` (PR #268).

## 20260812 (v0.12.0)

Decimo v0.12.0 retargets the codebase to **Mojo v1.0.0**, promotes the CLI's
expression evaluator to a first-class part of the library (`decimo.eval()`), and
adds Chinese numeral output for `BigInt` and `BigDecimal`. The `from_int()` and
`from_uint()` factory methods are removed, which is a breaking change for code
that calls them directly.

### ⭐️ New in v0.12.0

**Expression engine (`decimo.expression`)** (PR #259):

1. The tokenizer, shunting-yard parser, and RPN evaluator that used to live
   inside the CLI now sit in the core library under `decimo/expression/`. A
   string can be evaluated in one call with
   **`decimo.eval(expr, precision=50, variables=..., rounding_mode=...)`**, e.g.
   `decimo.eval("100 + e * pi")`. The individual stages are still available via
   `from decimo.expression import tokenize, parse_to_rpn, evaluate_rpn`, and
   `decimo.evaluate` is kept as an alias of `eval`.
1. `eval()` takes an optional **`variables`** map, so an expression can refer to
   named values supplied by the caller, e.g. `eval("x^2 + y", variables=vars)`.
1. The tokenizer treats `\n` and `\r` as whitespace, so multi-line (e.g.
   triple-quoted) expressions are accepted.
1. The CLI re-uses this shared engine instead of its own copy. Its presentation
   layer (`display`, `io`, `repl`, `settings`, `engine`) stays in the CLI, and
   the engine tests move from `tests/cli/` to `tests/expression/`.

**Chinese numerals (`decimo.numerals`)** (PR #262):

1. New sub-package **`decimo.numerals`** hosts conversions to non-Latin numeral
   systems. Each module renders a decimal *string* rather than a particular
   numeric type, so the conversions are shared by every Decimo type and are not
   limited by any integer width.
1. New **`decimal_string_to_chinese()`**, plus the **`BigInt.to_chinese()`** and
   **`BigDecimal.to_chinese()`** methods, write a number in Chinese numerals —
   `BigDecimal("1050.07").to_chinese()` gives `一千零五十点零七`. The integer
   part is split into sections of eight digits, read with the 十/百/千/万 units
   and joined by 亿, which multiplies everything read before it: `1234567890123`
   gives `一万二千三百四十五亿六千七百八十九万零一百二十三`, and each further 亿
   raises the magnitude by another 10^8 (亿亿 is 10^16). Integers of any length
   are therefore supported without relying on the rarely-agreed-upon 兆/京/垓
   units. Runs of zeros collapse into a single 零, a leading 一十 is shortened
   to 十, and the fractional part is read digit by digit after 点 so the written
   precision is preserved (`1.50` gives `一点五零`).
1. A reading is always written out in full, so its cost follows the *written*
   length of the number rather than the length of the input —
   `BigDecimal("1E+1000000000")` is a few characters that would expand into a
   billion digits. All three conversions therefore take a **`max_digits`**
   budget, defaulting to **`MAX_CHINESE_NUMERAL_DIGITS`** (10 000), and raise a
   `ValueError` past it. The budget is checked before the digits are expanded,
   so an absurd magnitude is rejected at no cost; pass `max_digits=0` to lift
   the cap.
1. The rendering is table-driven through the new **`ChineseNumeralStyle`**
   struct, which ships with the `simplified()`, `simplified_financial()` (大写:
   壹贰叁 / 拾佰仟), `traditional()` (繁體: 萬億點負), and
   `traditional_financial()` presets; custom tables can be supplied as well.

### 🦋 Changed in v0.12.0

**Mojo v1.0.0 migration** (PR #260):

1. Retarget the codebase to **Mojo v1.0.0** and bump the Pixi dependency to
   `mojo >=1.0.0,<1.1.0`.
1. **`from_int()` and `from_uint()` are removed** from `BigInt`, `BigUInt`,
   `BigInt10`, and `BigDecimal`, along with their separate `Int` / `UInt`
   constructors: `Int` is now an integral scalar, so the generic
   `from_integral_scalar()` path covers it (and `BigUInt` gains one). `BInt(42)`
   and `Decimal(42)` are unaffected; direct calls to `from_int()` /
   `from_uint()` must switch to `from_integral_scalar()`.
1. The power-of-10 lookup tables are emitted once into static storage with
   `global_constant` instead of being rebuilt at every call site (the
   alternatives, `materialize` and a `comptime for`, cost either stack traffic
   or code size). Fixed-size tables and temporaries switch from `List` to
   `Array` / `InlineArray`, and slice operations in `BigInt` take `ImmSpan`
   instead of copying.
1. `Decimal128` bitcasting moves from `UnsafePointer` to
   `Pointer(to=).unsafe_bitcast()`.
1. **Build tasks**: `pixi run argmojo` (new `src/cli/ensure_argmojo.sh`)
   resolves ArgMojo from the conda package when it is available and otherwise
   clones and precompiles the pinned upstream v0.8.0 commit into `temp/`, so
   `pixi run buildcli` works while modular-community catches up.
   `pixi run clean` no longer fails on a fresh checkout, and `pixi run doc`
   resolves `limo` from source.

**Errors** (PR #261):

1. The base error type `DecimoError` is renamed to **`BaseError`**, which reads
   better now that every concrete type (`ValueError`, `OverflowError`, …) is
   derived from it. `DecimoError` remains as a derived alias, so existing code
   keeps working.

**Documentation and CI:**

1. The user manual gains an **Expression Engine** section covering `eval()`, the
   supported syntax, variables, and the individual stages. The README's
   project-structure tree is brought up to date, and `docs/readme_unreleased.md`
   — a duplicate of the README — is removed.
1. CI gains a **`test-expression`** job, since those tests no longer run as part
   of the CLI suite.

## 20260701 (v0.11.0)

Decimo v0.11.0 retargets the codebase to **Mojo v1.0.0b2**, adds the
`factorial()` and `permutation()` functions to `BigInt` and `BigDecimal`, and
includes a series of performance improvements for `BigDecimal` and `BigUInt`
arithmetic. It also renames the `BigDecimal` `round_to_precision` APIs to
`*_inplace`, which is a breaking change for code that calls them directly.

### ⭐️ New in v0.11.0

**Number-theoretic functions:**

1. **`factorial()`** for `BigInt` and `BigDecimal` — a standalone function in
   the new `special` modules and an instance method on both types.
   `BigDecimal.factorial(precision=0)` returns the exact value by default and a
   rounded value when a positive `precision` is given. The exact path uses
   balanced binary splitting (`product_range`) with in-place single-word
   multiplication at the recursion leaves, which is much faster than a naive
   running product for large arguments (PR #254, #255, #256).
1. **`permutation()`** — the number of `k`-permutations of `n`,
   `P(n, k) = n! / (n − k)!`, likewise provided as a `special`-module function
   and as a method on `BigInt` / `BigDecimal` (with optional rounding for
   `BigDecimal`). For `BigInt`, `n` is restricted to a single word (PR #255).

### 🦋 Changed in v0.11.0

**Mojo v1.0.0b2 migration** (PR #257):

1. Retarget the codebase to **Mojo v1.0.0b2**, and bump the Pixi dependencies to
   `mojo >=1.0.0b2` and `argmojo 0.7.0`.
1. Switch packaging from the deprecated `mojo package` / `.mojopkg` to
   `mojo precompile` / `.mojoc` across the Pixi tasks, CI workflows, and helper
   scripts.
1. Update the `Decimal128` string formatter to the
   `StringSlice(unsafe_from_utf8=Span(...))` constructor, replacing the
   deprecated `StringSlice(ptr=, length=)` form.

**BigDecimal — rounding API rename:**

1. The free function `round_to_precision` and the matching `BigDecimal` method
   are renamed to **`round_to_precision_inplace`**, which makes their mutating
   semantics explicit, and now run through an allocation-free in-place path. The
   out-of-place, Python-compatible `BigDecimal.round(ndigits=...)` is unchanged.
   Code that calls the renamed APIs must update its import and call sites (PR
   #245).

**Performance:**

1. **`BigDecimal` addition / subtraction** — a same-scale fast path avoids the
   scale-alignment work when both operands share a scale (and, for `add`, a
   sign) (PR #247).
1. **`BigDecimal` multiplication** — compute the exact coefficient product in a
   single pass and round only afterwards when a precision is requested, removing
   a recursive call and a duplicated zero fast-path (PR #248).
1. **`BigDecimal` division and string conversion** — fewer allocations in
   `divide`, `from_string` parsing, and `to_string` rendering, through in-place
   batching and an exact-size output buffer (PR #249).
1. **`BigUInt` multiplication** — a deferred-carry (product-scanning) schoolbook
   path is selected once the operand size crosses a threshold; the Toom-3 cutoff
   is retuned and the "school" helpers are renamed to "schoolbook" (PR #250).
1. **Logarithm constants** — `compute_ln2` and `compute_ln1d25` fold their
   series factor into a single `UInt32` division per term, and
   `BigUInt.floor_divide_by_word` hoists its buffer pointers out of the inner
   loop (PR #251).

**Code quality and tooling:**

1. **`BigInt.from_integral_scalar()`** is simplified into one generic
   word-peeling loop over any integral scalar type, backed by a new
   `unsigned_counterpart` type helper (PR #253).
1. The **`BigInt` benchmarks** are refactored into a cross-language harness that
   compares `decimo.BigInt` against Python `int` and Rust `num-bigint`, with a
   Markdown report aggregator (PR #252).
1. **Documentation** — added `Raises:` sections across the public API, replaced
   banner-style header comments with module docstrings, and introduced local
   import aliases in place of fully-qualified references (PR #245, #246).

## 20260514 (v0.10.0)

Decimo v0.10.0 updates the codebase to **Mojo v1.0.0b1** and marks the
**"polish and parity"** phase. This release introduces four major additions.

First, the **`Decimal128`** API reaches feature parity with `BigDecimal` and
Python's `decimal.Decimal` / IEEE 754: `fma()`, `__divmod__()`,
`from_decimal(BigDecimal)`, `cbrt()`, `normalize()`, `__hash__()`,
`same_quantum()`, `max` / `min` / `clamp`, `trunc` / `floor` / `ceil` / `fract`
/ `signum` / `unpack`, `__bool__` / `__pos__`, and a unified `to_string` family
with `scientific` / `engineering` / `delimiter` keywords. The `nan` / `inf`
values are removed — `Decimal128` is now a strict finite type — and the
arithmetic and string hot paths are optimised.

Second, **`BigDecimal`** operator semantics are aligned with Python's
`decimal.Decimal`: `+`, `-`, `*` now round HALF_EVEN to the default precision
(`PRECISION = 28`) instead of returning unrounded results. New
explicit-precision methods `add(other, precision=0)` / `subtract(...)` /
`multiply(...)` (and `*_inplace` variants) let callers choose between exact and
rounded arithmetic. Internal `pi_machin` / `exp` / `ln` / trig sites switch to
the exact `*_inplace` path, and the **CLI calculator's RPN evaluator** now
honors `--precision` end to end.

Third, the **CLI calculator** is now distributed as a self-contained binary. A
new `release_cli` workflow builds tarballs for **macOS arm64** and
**Linux x86_64** (Mojo runtime bundled, `rpath` patched) and publishes them via
the [`forfudan/tap`](https://github.com/forfudan/homebrew-tap) Homebrew tap —
`brew install forfudan/tap/decimo` and Mojo / Pixi are no longer required on the
user's machine. The CLI itself gains a Mojo-native line editor **`limo`** (REPL
editing, history, cursor movement); pipe / stdin and file modes (`-F`);
shell-completion docs for Bash / Zsh / Fish; REPL info commands (`:`, `?`, `$`,
`:q`, `:info`); the `ans` variable; user-defined variables; a `:100` precision
shortcut; and case-insensitive input.

Fourth, the codebase gains two new core types and a reworked error system.
**`BigFloat`** is an arbitrary-precision binary floating-point type backed by
**GMP / MPFR** through a thin C wrapper (`src/decimo/gmp/gmp_wrapper.c`,
`src/decimo/bigfloat/mpfr_wrapper.mojo`); every operation is a single MPFR call
against a pooled `mpfr_t` handle, precision is in decimal digits with 64 guard
bits added internally, and the type is the right choice when MPFR-quality
transcendentals or a wider exponent range than `BigDecimal` are wanted. MPFR/GMP
must be present at runtime (PR #190, #191). **`Rational`** is a new exact
rational number type, stored as a reduced fraction of two `Integer`s (PR #214).
The **error system** replaces the catch-all `DecimoError` with concrete types
such as `RuntimeError`, makes `message` and `function` mandatory, and renders
coloured errors with auto-inferred shortened-relative file/line info (PR #195,
#196, #198, #200); `raises:` docstring sections are audited (PR #199) and every
public symbol now carries a docstring (PR #194).

### ⭐️ New in v0.10.0

**New core types:**

1. New **`BigFloat`** type (alias `BFlt`, `Float`) — arbitrary-precision
   **binary floating-point** wrapping a single MPFR handle via a C wrapper. Each
   arithmetic and transcendental operation is a single MPFR call against a
   pooled `mpfr_t` handle. Precision is specified in decimal digits and
   converted to bits internally; 64 guard bits are added so the requested
   decimal digits are correct. Provides `+ - * /`, `sqrt`, `cbrt`, `root`,
   `pow`, `exp`, `ln`, `log`, `log10`, full trig and hyperbolic suite,
   comparison and rounding, plus conversion to / from `BigDecimal`. RAII
   destructor frees the MPFR handle. Optional — requires MPFR/GMP to be
   installed at runtime; the C wrapper is built via `pixi run buildgmp` (PR
   #190, #191).
1. New **`Rational`** type — arbitrary-precision exact rational number, stored
   as a reduced fraction of two `Integer`s. Supports exact arithmetic and
   comparisons without precision loss (PR #214).

**Decimal128 — feature parity with Python `decimal.Decimal`:**

1. **`fma(other, third)`** — fused multiply-add with a single rounding (IEEE
   754-2008 §5.4.1, matches Python `Decimal.fma`). Falls back to the two-step
   path only when the aligned working coefficient exceeds the 58-digit fast-path
   cap. Bit-identical to the `BigDecimal` oracle on all 12 cross-language bench
   cases (PR #241).
1. **`__divmod__(other)`** — single-call `(self // other, self % other)`,
   amortising the divide pipeline. Supports both `Decimal128` and `Int`
   right-hand sides; `Int → Dec128` is now `@implicit` (PR #242).
1. **`from_decimal(BigDecimal)`** — quantises a high-precision `BigDecimal` onto
   the Decimal128 grid (banker's rounding to 28 fractional digits, raises
   `OverflowError` on integral overflow). Acts as the cross-language bench
   oracle bridge (PR #239).
1. **`normalize()`**, **`__hash__()`**, **`same_quantum(other)`** — strip
   trailing zeros, hash for use as dict key / set element, IEEE 754 scale
   comparison (PR #238).
1. **`max`, `min`, `clamp`** instance methods (PR #230).
1. **`trunc`, `floor`, `ceil`, `fract`, `signum`, `unpack`** — round towards
   zero / −∞ / +∞, extract fractional part / sign, unpack into
   coefficient/sign/scale words (PR #227).
1. **`cbrt()`** — convenience cube root, well-defined for negative values via
   `root()`'s odd-root path.
1. **`__bool__`** and **`__pos__`** (so `if d:`, `Bool(d)`, `+d` all work);
   `Decimal128` now conforms to `Boolable`.
1. **`is_positive()`**, **`is_odd()`**, **`number_of_trailing_zeros()`** — small
   introspection helpers, mirroring `BigDecimal`.
1. **`to_scientific_string()`**, **`to_eng_string()`**,
   **`to_string_with_separators(separator="_")`** — convenience aliases matching
   the equivalent `BigDecimal` API.
1. **`fit_to_max_coefficient()`** and **`round_coefficient()`** — utility
   helpers shared by `from_string()` and the arithmetic paths (PR #216).

**CLI calculator & `limo` line editor:**

1. New **`limo`** package — a small Mojo-native line editor used by the REPL for
   line editing and history navigation (PR #212).
1. Interactive **REPL**: `decimo` with no arguments launches a coloured
   `decimo>` prompt with per-line error recovery, comment/blank-line skipping,
   and graceful exit via `exit` / `quit` / Ctrl-D (PR #205).
1. **REPL info commands**: `:` shows current settings, `?` shows help, `$` /
   `:v` / `:vars` lists variables, `:q` / `:quit` / `:exit` exits (PR #210,
   #211).
1. **REPL `:info` / `:about` section** — print version, author, license, and
   project links from inside the REPL (PR #213).
1. **REPL configuration system** — settings commands (`:p`, `:scientific`, etc.)
   now print the full settings block after every change so the effect is
   immediately visible; multiple flags can be set on a single line (PR #208).
1. **Variable assignment** in REPL (`x = 1+2`) plus the `ans` variable holding
   the last result (PR #206).
1. **Pipe / stdin mode**: read expressions from piped stdin, one per line (e.g.
   `echo "1+2" | decimo`). Comments and blank lines are skipped (PR #203).
1. **File mode** (`--file` / `-F`): evaluate expressions from a file, one per
   line, sharing all CLI flags (PR #203).
1. **Negative numbers and negative expressions** as positional CLI arguments (PR
   #201, #202).
1. **Argument parsing polish** — range / value-name / argument-group validation,
   custom usage line, all short option names upper-cased (PR #201, #203).
1. **Shell completion** documentation for Bash, Zsh, and Fish
   (`decimo --completions bash|zsh|fish`) (PR #204).
1. **Standalone-precision shortcut** in settings: `:100` is equivalent to
   `:p 100` (PR #211).
1. Case-insensitive REPL input (`PI`, `Sqrt(2)`, `SIN(1)` all work) (PR #210).

**Error handling:**

1. New **`RuntimeError`** type and other concrete error types replacing the
   catch-all `DecimoError`; `message` and `function` fields are now mandatory on
   the base error type (PR #196, #198).
1. Coloured error messages with auto-inferred file name and line number (PR
   #195); shortened relative paths in error messages to preserve user privacy at
   compilation (PR #200).
1. Fixed `raises:` sections in docstrings across the codebase to advertise the
   correct error types (PR #199).

**Distribution:**

1. New **`release_cli`** workflow building self-contained `decimo` CLI tarballs
   for **macOS arm64** and **Linux x86_64**; published via the `forfudan/tap`
   Homebrew tap (`brew install forfudan/tap/decimo`).
1. Bundled third-party licenses are now documented in `NOTICE` and shipped in
   the source tarball (PR #231).

### 🦋 Changed in v0.10.0

**Mojo 1.0.0b1 migration** (PR #243):

1. Retarget the entire codebase to **Mojo v1.0.0b1**: new `def` / `fn` keyword
   conventions, `String` API changes (e.g. UTF-8 byte iteration), and updated
   stdlib import paths.
1. Migrate the Decimal128 `power_of_10_unsafe` rodata tables from
   `StringLiteral` packed bytes to **`comptime InlineArray`**, sidestepping a
   Mojo 1.0.0b1 regression that mangles `StringLiteral` UTF-8 bytes. Type
   bridging via zero-cost `rebind[Scalar[dtype]]`.
1. Use **`argmojo` 0.6.0** as a conda dependency instead of fetching from git
   (`pixi.toml`); CLI build no longer needs an extra fetch step.
1. Test runner (`tests/test.sh`, `tests/test_cli.sh`) auto-builds
   `tests/decimo.mojopkg` on demand, working around Mojo 1.0.0b1's inability to
   resolve qualified `decimo.X.Y.foo` references in source-imported builds.

**BigDecimal — operator semantics aligned with Python `decimal.Decimal`:**

1. `+` / `-` / `*` (and reflected / augmented variants) now round
   **HALF_EVEN to `PRECISION = 28`** by default instead of returning an exact
   unrounded result. Use the new explicit-precision methods when exact
   intermediate arithmetic matters.
1. New **exact methods** `add(other, precision=0)`,
   `subtract(other, precision=0)`, `multiply(other, precision=0)` —
   `precision=0` (default) returns the exact result, `precision > 0` rounds
   HALF_EVEN to that many digits (PR #233, #235).
1. New **in-place exact methods** `add_inplace`, `subtract_inplace`,
   `multiply_inplace` with the same `precision` parameter, for tight loops.
1. **Internal call sites migrated**: `pi_machin`, Newton iterations, Taylor
   series, and trig range reduction now use the exact `*_inplace` methods, so
   high-precision π / `ln` / `exp` / trig results are no longer silently capped
   at 28 digits.
1. **CLI calculator** RPN evaluator now drives `+` / `-` / `*` through
   `.add(b, working_precision)` etc. so the user-requested `--precision` is
   honored end to end (previously results were silently capped at 28).
1. Improved numeric string parsing for `BigDecimal` plus extra test sets and a
   few bug fixes (PR #226).

**Decimal128 — performance:**

1. Hot-path `UInt(128|256)(10) ** k` calls swept to **`power_of_10_unsafe`**
   rodata indexed loads (~4–12 ns → ~0.8 ns) (PR #224).
1. `from_uint128()` marked `@always_inline` with cold `raise ValueError` blocks
   split into `@no_inline` helpers; brings `add` to **0.9× `rust_decimal`**,
   `subtract` to **0.9–1.3× `rust_decimal`**, `divide` to
   **1.0× `rust_decimal`** on median bench (PR #224).
1. **`exp()` / `ln()` / `log10()`**: rewrite Taylor and range-reduction loops;
   worst-case ratio drops to **≤ 1.0× `rust_decimal`** across all 42 bench cases
   (was up to 1.7×). Adds new `cases/{ln,log10,exp}.toml` harnesses (PR #229).
1. **`exp()` 2-tier sub-unit chunker** — 17 precomputed per-tenth and
   per-hundredth constants halve Taylor iterations on inputs like `exp(π)` (1350
   → 770 ns) and improve accuracy 3 ulp → 1 ulp; `exp(0.1)` collapses to a
   single constant lookup (~25 ns) (PR #229).
1. **`divide()`** — drop redundant rounding-digit padding (PR #237) and switch
   the inner loop to a school-book long-division layout that avoids slow
   `UInt256 // UInt256` fallbacks (PR #223).
1. **`add()` / `subtract()`** — reorder branches so the sign-and-scale-aligned
   hot path runs first; cold cases moved to the tail (PR #220, #222).
1. **`multiply()`** — remove `is_integer()` and `format()` from the hot path;
   **fix latent rounding bugs** when intermediate scale exceeds 28 (PR #221).
1. Tighter inner loops in `comparison`, `from_string()`, `to_string()` etc. (PR
   #225); `number_of_bits()` switches to `std.bit.bit_width` and is
   `@always_inline` (PR #218).

**Decimal128 — API removals and consolidations:**

1. **Removed `nan` and `inf`** values: `Decimal128` is now a strict finite type.
   `from_words()` updated accordingly (PR #215).
1. **Consolidated `to_string_scientific()` into `to_string()`**: `to_string()`
   now takes `scientific: Bool = False`, `engineering: Bool = False`,
   `delimiter: String = ""`, mirroring `BigDecimal.to_string`. Adds engineering
   notation as a new code path
   (`Decimal128("0.5").to_string(engineering=True) == "500E-3"`).
1. **Removed `Decimal128.copy()` / `clone()`**: trivial and unused. `Decimal128`
   is `TrivialRegisterPassable`, so `var b = a` is the idiomatic copy.
1. **Removed `Decimal128.print_internal_representation()`**: one-line wrapper,
   unused. Use `print(x.internal_representation())` directly.

**BigInt:**

1. Rewrite type conversion from all integral scalar types (`Int`, `UInt`,
   `IntLiteral`, `Scalar[DType.intN]`, `Scalar[DType.uintN]`) so that every
   integral scalar can be converted to `BigInt` / `BigUInt` correctly, including
   the corner case of `Int.MIN` and signed-to-unsigned narrowing (PR #189).

### 🐛 Fixed in v0.10.0

1. **`BigDecimal.to_string(force_plain=True)` dropping trailing zeros for
   `scale < 0`**: `BigDecimal("1e40").to_string(force_plain=True)` previously
   returned `"1"` instead of the full 41-digit integer, silently producing a
   wrong value when re-parsed (e.g. via `Decimal128.from_decimal()`).
1. **`Decimal128.multiply()`**: latent rounding bugs affecting products whose
   intermediate scale exceeded 28 (PR #221).

### 📚 Docs, tests, and benchmarks in v0.10.0

1. Ensure all functions, fields, and constants have docstrings; eliminates
   `mojo doc` warnings (PR #194).
1. Reorganise the `docs/` folder and update user-facing manuals (PR #207).
1. Add planning documents `docs/plans/gmp_integration.md` (kicks off the
   GMP/MPFR integration that lands as `BigFloat`) and
   `docs/plans/decimal128_enhancement.md` (roadmap for Decimal128 parity work in
   this release) (PR #190, #193).
1. Refactor the GitHub Actions unit-test workflow to use caching for faster CI
   (PR #234).
1. Consolidate the Decimal128 test suites into fewer files
   (`test_decimal128_arithmetics.mojo`, `test_decimal128_creation.mojo`, etc.)
   for faster compilation (PR #228).
1. Refactor cross-language benchmark harness to include
   **Rust (`rust_decimal`)**, **C# (`System.Decimal`)**, and **VB.NET** (PR
   #219); `BigDecimal` acts as the high-precision oracle for `ln` / `log10` /
   `exp` (PR #229).
1. Add **CLI performance benchmarks** comparing correctness and timing against
   `bc` and `python3` across 47 cases — all results match to 15 significant
   digits; `decimo` is **3–4× faster than `python3 -c`** (PR #204).
1. Refactor BigDecimal benchmark suites (PR #232); add edge-case tests for
   `compare_absolute()` (PR #217); refactor test files to a CLI argument style
   (PR #209).
1. Document bundled third-party libraries in `NOTICE` and ship their licenses in
   the source tarball (PR #231).

## 20260323 (v0.9.0)

Decimo v0.9.0 updates the codebase to **Mojo v0.26.2** and marks the
**"make it useful"** phase. This release introduces three major additions:

First, a full-featured **CLI arbitrary-precision calculator** (`decimo`),
powered by Decimo's `BigDecimal`. It includes a complete tokenizer, a
shunting-yard parser, and an RPN evaluator with working-precision guard digits,
supporting built-in mathematical functions (`sqrt`, `cbrt`, `root`, `ln`, `log`,
`log10`, `exp`, trigonometric functions, `abs`), constants (`pi`, `e`), and
configurable output formatting (scientific/engineering notation, digit
delimiters, rounding modes, and precision control).

Second, the `BigDecimal` API is significantly expanded with methods aligned to
Python's `decimal.Decimal` and the IEEE 754 specification, including
`as_tuple()`, `adjusted()`, `same_quantum()`, `scaleb()`, `fma()`, `copy_abs()`,
`copy_negate()`, `copy_sign()`, `bit_count()`, `__float__()`, engineering
notation, and digit-group delimiters for `to_string()`. The `ROUND_HALF_DOWN`
rounding mode is added, bringing the total to seven.

Third, Decimo gains **Python bindings** via Mojo's `PythonModuleBuilder`,
exposing `BigDecimal` as a native Python extension module (`_decimo.so`) with a
Pythonic `Decimal` wrapper for interoperability with Python code.

### ⭐️ New in v0.9.0

**CLI Calculator:**

1. Implement an arbitrary-precision CLI calculator with tokenizer, shunting-yard
   parser, and RPN evaluator, supporting arithmetic expressions with parentheses
   and operator precedence (PR #170).
1. Add built-in functions (`sqrt`, `cbrt`, `root`, `ln`, `log`, `log10`, `exp`,
   `sin`, `cos`, `tan`, `cot`, `csc`, `abs`), constants (`pi`, `e`), and
   configurable output formatting (scientific/engineering notation, digit
   delimiter, padding, rounding mode) (PR #171).
1. Improve CLI error handling with token location tracing and ANSI-coloured
   diagnostic output (PR #178).
1. Use working precision (user precision + guard digits) for intermediate
   calculations to improve result accuracy (PR #182).

**BigDecimal:**

1. Add **engineering notation** (`to_eng_string()`) and
   **digit-group delimiters** (`to_string_with_separators()`) to `to_string()`,
   with optional line-width wrapping (PR #172).
1. Add utility methods: `is_integer()`, `is_signed()`, `number_class()`,
   `logb()`, `normalize()`, `radix()` (PR #173).
1. Implement `as_tuple()` returning `(sign, digits, exponent)`, matching
   Python's `Decimal.as_tuple()` (PR #174).
1. Implement `adjusted()`, `copy_abs()`, `copy_negate()`, and `copy_sign()`
   aligned with Python's `decimal` API (PR #176).
1. Implement `same_quantum()` and add the `ROUND_HALF_DOWN` rounding mode,
   bringing the total to seven (PR #177).
1. Implement `scaleb()`, `fma()`, `bit_count()`, and `__float__()` (implements
   `FloatableRaising`) (PR #183).

**Python Bindings:**

1. Implement Python bindings via Mojo's `PythonModuleBuilder`, exposing
   `BigDecimal` as a native extension module `_decimo.so` with arithmetic,
   comparison, and string operations (PR #179).
1. Restructure `python/` to a `src` layout with `pyproject.toml` for PyPI
   packaging (PR #180).

### 🦋 Changed in v0.9.0

1. Update the codebase to **Mojo v0.26.2**, adopting `byte=` slicing syntax,
   `out` parameter convention for constructors, and updated
   `String`/`StringSlice` APIs (PR #185).
1. Merge `TOMLMojo` into Decimo as the sub-package `decimo.toml`, removing
   standalone packaging (PR #181).
1. Rename `exponent()` to `adjusted()` for `BigDecimal` to align with Python's
   `decimal` module naming (PR #176).
1. Change default precision of `BigDecimal` to **28** significant digits,
   matching Python's `decimal` module default.
1. Remove deprecated free-function comparison aliases and legacy method names
   from `BigDecimal` (PR #173).
1. Align `print_internal_representation()` output style across `BigInt`,
   `BigUInt`, `BigDecimal`, and `Decimal128` with dynamic column alignment (PR
   #169).

### 📚 Documentation and testing in v0.9.0

- Add user manuals for the Decimo library and the CLI calculator
  (PR #184).
- Add info badges to the README file.

## 20260225 (v0.8.0)

> **Library renamed from `decimojo` to `decimo`.** The package name, import
> path, and all public references have been updated. GitHub repository will be
> renamed to `forfudan/decimo` (GitHub auto-redirects the old URL).

Decimo v0.8.0 marks the **"make it fast"** phase. There are two major
improvements in this release:

First, it introduces a completely new `BigInt` (`BInt`) type using a
**base-2^32 internal representation**. This replaces the previous base-10^9
implementation (now available as `BigInt10`) with a little-endian format using
`UInt32` words, improving the performance of all integer
operations. The new `BigInt` implements the
**Karatsuba multiplication algorithm** and the
**Burnikel-Ziegler division algorithm** for sub-quadratic performance on large
integers, and includes **divide-and-conquer base conversion** for fast string
I/O. It also adds **bitwise operations**, **GCD and modular arithmetic**, and an
optimized **integer square root**. Benchmarks show that the new `BigInt`
outperforms Python's built-in `int` type in most cases, with up to 11× speedup
for power operations and 5× for shift operations.

Second, it optimizes the mathematical operations for `BigDecimal`, bringing
significant performance and accuracy improvements. The `sqrt()` function is
re-implemented using the **reciprocal square root method** combined with
Newton's method for faster convergence. The `ln()` function now supports an
**atanh-based approach** with mathematical constant caching via `MathCache`. The
`exp()` function benefits from **aggressive range reduction** for much faster
convergence. The `root()` function gains **rational root decomposition** and a
direct Newton method. The `to_string()` method is aligned with CPython's
`decimal` module formatting rules for scientific notation and trailing zeros.
The `BigUInt` layer also gains the **Toom-Cook 3-way multiplication algorithm**.
Benchmarks indicate that `BigDecimal` operations beat Python's `decimal` module
in speed, especially for high-precision calculations (e.g., division up to 915×
faster, sqrt 3.5× faster on average).

### ⭐️ New in v0.8.0

**BigInt (base-2^32):**

1. Implement the `BigInt` (`BInt`) type using a base-2^32 internal
   representation with little-endian `UInt32` words. This is a completely new
   implementation optimized for binary computations while supporting arbitrary
   precision (PR #133, #134, #135, #141).
1. Implement the **Karatsuba multiplication algorithm** for `BigInt`, reducing
   time complexity from $O(n^2)$ to $O(n^{\log_2 3})$ for large integers (PR
   #142).
1. Implement the **slice-based Burnikel-Ziegler division algorithm** for
   `BigInt`, providing sub-quadratic division performance for the base-2^32
   representation (PR #144).
1. Implement **divide-and-conquer base conversion** for `BigInt.to_string()`,
   significantly improving string conversion speed for large integers (PR #145).
1. Implement **bitwise operations** (`__and__`, `__or__`, `__xor__`,
   `__lshift__`, `__rshift__`, `__invert__`) and true in-place bitwise
   operations for `BigInt` (PR #150, #151).
1. Implement `gcd()`, `extended_gcd()`, `mod_inverse()`, and `mod_pow()` for
   `BigInt`, providing number-theoretic functions (PR #152, #153).
1. Implement an optimized `sqrt()` for `BigInt` using Newton's method with a
   good initial approximation, delivering 1.39× average speedup over Python (PR
   #155).

**BigDecimal:**

1. Implement the `quantize()` function for `BigDecimal` to format decimal
   numbers to a specified number of decimal places, similar to Python's
   `Decimal.quantize()` (PR #126).
1. Implement true in-place arithmetic functions (`__iadd__`, `__isub__`,
   `__imul__`) for `BigDecimal` to reduce memory allocations during repeated
   operations (PR #162).
1. Implement methods to initialize `BigInt` and `BigDecimal` from Python
   objects, enabling interoperability with Python's `int` and
   `decimal.Decimal` (PR #129).

**Core:**

1. Add `ROUND_CEILING` and `ROUND_FLOOR` rounding modes to `RoundingMode`,
   bringing the total to six modes (PR #164).

**TOMLMojo:**

1. Implement all core **TOML v1.0 specification** features for `TOMLMojo`,
   including inline tables, arrays of tables, dotted keys, multiline strings,
   and all value types (PR #140).

### 🦋 Changed in v0.8.0

**BigInt:**

1. Rename the previous base-10^9 `BigInt` to `BigInt10`. The alias `BInt` now
   refers to the new base-2^32 `BigInt` type (PR #143, #154).
1. Optimize `from_string()` for `BigInt` with an improved string parser and
   divide-and-conquer approach for fast base conversion (PR #146, #147, #148).
1. Optimize `to_string()` for `BigInt` with divide-and-conquer base conversion,
   achieving 6× average speedup over Python (PR #149).

**BigDecimal:**

1. Re-implement `sqrt()` for `BigDecimal` using the
   **reciprocal square root method** combined with Newton's method, delivering
   faster convergence and better accuracy for high-precision calculations (PR
   #163).
1. Optimize `ln()` and `exp()` for `BigDecimal` with mathematical constant
   caching via `MathCache` and improved handling of one-word dividends (PR
   #160).
1. Apply **aggressive range reduction** for `exp()` to achieve faster
   convergence at high precision (PR #167).
1. Implement direct Newton method for general `root()` calculation, replacing
   the previous iterative approach (PR #161).
1. Add **rational root decomposition** to `root()` and an
   **atanh-based approach** to `ln()` for improved accuracy and convergence (PR
   #168).
1. Optimize `true_divide_general()` to correctly account for existing word
   surplus in the dividend (PR #158).
1. Optimize division with truncation and align `to_string()` output with
   CPython's `decimal` module formatting for scientific notation and trailing
   zeros (PR #165).

**BigUInt:**

1. Implement the **Toom-Cook 3-way multiplication algorithm** for `BigUInt`,
   improving performance for large number multiplications (PR #166).
1. Unify and refine initialization methods for `BigUInt` with consistent
   constructors and improved validation (PR #127, #128, #131).

**Core:**

1. Improve naming consistency between types, ensuring uniform method names
   across `BigInt`, `BigDecimal`, and `Decimal128` (PR #164).
1. Make `RoundingMode` type implicitly copyable for easier usage in function
   signatures (PR #125).

### 🛠️ Fixed in v0.8.0

- Fix string formatting for `BigDecimal` to match Python's `decimal` module
  formatting rules, including correct scientific notation thresholds and
  trailing zero handling (PR #163, #165).

### 📚 Documentation and testing in v0.8.0

- Refactor the testing files for `Decimal128` (PR #132).
- Refactor the benchmarking system to use TOML-based input files with
  configurable precision (PR #139, #159).
- Update document links for the repository organization move to `forfudan` (PR
  #130).
- Update documents and add the planning files for BigInt and BigDecimal
  optimization roadmaps (PR #157).

## 20260212 (v0.7.0)

DeciMojo v0.7.0 updates the codebase to Mojo v0.26.1.

- Replaces all `alias` declarations with `comptime` in all files. `alias` is
  deprecated.
- Updates list and constant construction syntax throughout the codebase, e.g.,
  replaced `List[UInt32](...)` with `[UInt32(...), ...]`, used `[word]` instead
  of `List[UInt32](word)`, etc. The old syntax is deprecated.
- Updates list slicing syntax to use the new syntax. Now `lst[1:]` returns a
  `Span` instead of a `List`, so it needs to be converted to a list using the
  constructor `List(...)`.
- Updates some methods of the `String` type and the indexing and slicing syntax
  for `String` objects to match the latest Mojo syntax. The old syntax is
  deprecated.
- Fixes the closure capture when using `vectorize`. The new syntax requires
  something like `unified {read x, mut y}` to capture variables `x` and `y` in
  the closure. The old syntax is deprecated.

## 20251216 (v0.6.0)

DeciMojo v0.6.0 updates the codebase to Mojo v0.25.7, adopting the new
`TestSuite` type for improved test organization. All tests have been refactored
to use the native Mojo testing framework instead of the deprecated `pixi test`
command.

## 20250806 (v0.5.0)

DeciMojo v0.5.0 introduces significant enhancements to the `BigDecimal` and
`BigUInt` types, including new mathematical functions and performance
optimizations. The release adds **trigonometric functions** for `BigDecimal`,
implements the **Chudnovsky algorithm** for computing π, and implements the
**Karatsuba multiplication algorithm** and
**Burnikel-Ziegler division algorithm** for `BigUInt`. In-place operations,
slice operations, and SIMD operations are now supported for `BigUInt`
arithmetic. The `Decimal` type is renamed to `Decimal128` to reflect its 128-bit
fixed precision. The release also includes improved error handling, optimized
type conversions, refactored testing suites, and documentation updates.

DeciMojo v0.5.0 is compatible with Mojo v25.5.

### ⭐️ New in v0.5.0

1. Introduce trigonometric functions for `BigDecimal`: `sin()`, `cos()`,
   `tan()`, `cot()`, `csc()`, `sec()`. These functions compute the corresponding
   trigonometric values of a given angle in radians with arbitrary precision
   (#96, #99).
1. Introduce the function `pi()` for `BigDecimal` to compute the value of π (pi)
   with arbitrary precision with the Chudnovsky algorithm with binary splitting
   (#95).
1. Implement the `sqrt()` function for `BigUInt` to compute the square root of a
   `BigUInt` number as a `BigUInt` object (#107).
1. Introduce a `DeciMojoError` type and various aliases to handle errors in
   DeciMojo. This enables a more consistent error handling mechanism across the
   library and allows users to track errors more easily (#114).

### 🦋 Changed in v0.5.0

Changes in **BigUInt**:

1. Refine the `BigUInt` multiplication with the **Karatsuba algorithm**. The
   time complexity of multiplication is reduced from $O(n^2)$ to
   $O(n^{\log_2 3})$ for large integers, which improves performance
   for big numbers. Doubling the size of the numbers will only increase the time
   taken by a factor of about 3, instead of 4 as in the previous implementation
   (#97).
1. Refine the `BigUInt` division with the
   **Burnikel-Ziegler fast recursive division algorithm**. The time complexity
   of division is also reduced from $O(n^2)$ to $O(n^{\log_2 3})$ for large
   integers (#103).
1. Refine the fall-back **schoolbook division** of `BigUInt` to improve
   performance. The fallback division is used when the divisor is small enough
   (#98, #100).
1. Implement auxiliary functions for arithmetic operations of `BigUInt` to
   handle **special cases** more efficiently, e.g., when the second operand is
   one-word long or is a `UInt32` value (#98, #104, #111).
1. Implement in-place subtraction for `BigUInt`. The `__isub__` method of
   `BigUInt` will now conduct in-place subtraction. `x -= y` will not lead to
   memory allocation, but will modify the original `BigUInt` object `x` directly
   (#98).
1. Use SIMD for `BigUInt` addition and subtraction operations. This allows the
   addition and subtraction of two `BigUInt` objects to be performed in
   parallel, significantly improving performance for large numbers (#101, #102).
1. Implement functions for all arithmetic operations on slices of `BigUInt`
   objects. This allows you to perform arithmetic operations on slices of
   `BigUInt` objects without having to convert them to `BigUInt` first, leading
   to less memory allocation and improved performance (#105).
1. Add `to_uint64()` and `to_uint128()` methods to `BigUInt` for fast type
   conversion (#91).

Changes in **BigDecimal**:

1. Re-implement the `sqrt()` function for `BigDecimal` to use the new
   `BigUInt.sqrt()` method for better performance and accuracy. The new
   implementation adjusts the scale and coefficient directly, which is more
   efficient than the previous method. Introduce a new `sqrt_decimal_approach()`
   function to preserve the old implementation for reference (#108).
1. Refine or re-implement the basic arithmetic operations, *e.g.,*, addition,
   subtraction, multiplication, division, etc, for `BigDecimal` and simplify the
   logic. The new implementation is more efficient and easier to understand,
   leading to better performance (#109, #110).
1. Add a default precision 36 for `BigDecimal` methods (#112).

Other changes:

1. Update the codebase to Mojo v25.5 (#113).
1. Remove unnecessary `raises` keywords for all functions (#92).
1. Rename the `Decimal` type to `Decimal128` to reflect its fixed precision of
   128 bits. It has a new alias `Dec128` (#112).
1. `Decimal` is now an alias for `BigDecimal` (#112).

### 🛠️ Fixed in v0.5.0

- Fix a bug for `BigUInt` comparison: When there are leading zero words, the
  comparison returns incorrect results (#97).
- Fix the `is_zero()`, `is_one()`, and `is_two()` methods for `BigUInt` to
  correctly handle the case when there are leading zero words (#97).

### 📚 Documentation and testing in v0.5.0

- Refactor the test files for `BigDecimal` (PR #93).
- Refactor the test files for `BigInt` (PR #106).

## 20250701 (v0.4.1)

Version 0.4.1 of DeciMojo introduces implicit type conversion between built-in
integral types and arbitrary-precision types.

### ⭐️ New in v0.4.1

Now DeciMojo supports implicit type conversion between built-in integral types
(`Int`, `UInt`, `Int8`, `UInt8`, `Int16`, `UInt16`, `Int32`, `UInt32`, `Int64`,
`UInt64`, `Int128`,`UInt128`, `Int256`, and `UInt256`) and the
arbitrary-precision types (`BigUInt`, `BigInt`, and `BigDecimal`). This allows
you to use these built-in types directly in arithmetic operations with `BigInt`
and `BigUInt` without explicit conversion. The merged type will always be the
most compatible one (PR #89, PR #90).

For example, you can now do the following:

```mojo
from decimojo.prelude import *

def main() raises:
    var a = BInt(Int256(-1234567890))
    var b = BigUInt(31415926)
    var c = BDec("3.14159265358979323")

    print("a =", a)
    print("b =", b)
    print("c =", c)

    print(a * b)  # Merged to BInt
    print(a + c)  # Merged to BDec
    print(b + c)  # Merged to BDec
    print(a * Int(-128))  # Merged to BInt
    print(b * UInt(8))  # Merged to BUInt
    print(c * Int256(987654321123456789))  # Merged to BDec

    var lst = [a, b, c, UInt8(255), Int64(22222), UInt256(1234567890)]
    # The list is of the type `List[BigDecimal]`
    for i in lst:
        print(i, end=", ")
```

Running the code gives the following results:

```console
a = -1234567890
b = 31415926
c = 3.14159265358979323
-38785093474216140
-1234567886.85840734641020677
31415929.14159265358979323
158024689920
251327408
3102807559527666386.46423202534973847
-1234567890, 31415926, 3.14159265358979323, 255, 22222, 1234567890,
```

### 🦋 Changed in v0.4.1

Optimize the case when you increase the value of a `BigInt` object in-place by
1, *i.e.*, `i += 1`. This allows you to iterate faster (PR #89). For example, we
can compute the time taken to iterate from `0` to `1_000_000` using `BigInt` and
compare it with the built-in `Int` type:

```mojo
from decimojo.prelude import *

def main() raises:
    i = BigInt(0)
    end = BigInt(1_000_000)
    while i < end:
        print(i)
        i += 1
```

| scenario        | Time taken |
| --------------- | ---------- |
| v0.4.0 `BigInt` | 1.102s     |
| v0.4.1 `BigInt` | 0.912s     |
| Built-in `Int`  | 0.893s     |

### 🛠️ Fixed in v0.4.1

Fix a bug in `BigDecimal` where it cannot create a correct value from a integral
scalar, e.g., `BDec(UInt16(0))` returns an uninitialized `BigDecimal` object (PR
#89).

### 📚 Documentation and testing in v0.4.1

Update the `tests` module and refactor the test files for `BigUInt` (PR #88).

## 20250625 (v0.4.0)

DeciMojo v0.4.0 updates the codebase to Mojo v25.4.

## 20250606 (v0.3.1)

DeciMojo v0.3.1 updates the codebase to Mojo v25.3 and replaces the `magic`
package manager with `pixi`.

## 20250415 (v0.3.0)

DeciMojo v0.3.0 introduces the arbitrary-precision `BigDecimal` type with
arithmetic operations, comparisons, and mathematical functions
(`sqrt`, `root`, `log`, `exp`, `power`). A new `tomlmojo` package supports test
refactoring. Improvements include refined `BigUInt` constructors, enhanced
`scale_up_by_power_of_10()` functionality, and a critical multiplication bug
fix.

### ⭐️ New in v0.3.0

- Implement the `BigDecimal` type with unlimited precision arithmetic.
  - Implement basic arithmetic operations for `BigDecimal`: addition,
    subtraction, multiplication, division, and modulo.
  - Implement comparison operations for `BigDecimal`: less than, greater than,
    equal to, and not equal to.
  - Implement string representation and parsing for `BigDecimal`.
  - Implement mathematical operations for `BigDecimal`: `sqrt`, `nroot`, `log`,
    `exp`, and `power` functions.
  - Implement rounding functions.
- Implement a simple TOML parser as package `tomlmojo` to refactor tests (PR
  #63).

### 🦋 Changed in v0.3.0

- Refine the constructors of `BigUInt` (PR #64).
- Improve the method `BigUInt.scale_up_by_power_of_10()` (PR #72).

### 🛠️ Fixed in v0.3.0

- Fix a bug in `BigUInt` multiplication where the calculation of carry is
  mistakenly skipped if a word of x2 is zero (PR #70).

## 20250401 (v0.2.0)

Version 0.2.0 marks a significant expansion of DeciMojo with the introduction of
`BigInt` and `BigUInt` types, providing unlimited precision integer arithmetic
to complement the existing fixed-precision `Decimal` type. Core arithmetic
functions for the `Decimal` type have been completely rewritten using Mojo
25.2's `UInt128`, delivering substantial performance improvements. This release
also extends mathematical capabilities with advanced operations including
logarithms, exponentials, square roots, and n-th roots for the `Decimal` type.
The codebase has been reorganized into a more modular structure, enhancing
maintainability and extensibility. With comprehensive test coverage, improved
documentation in multiple languages, and optimized memory management, v0.2.0
represents a major advancement in both functionality and performance for
numerical computing in Mojo.

### ⭐️ New in v0.2.0

- Add `BigInt` and `BigUInt` with unlimited-precision integer arithmetic.
- Implement full arithmetic operations for `BigInt` and `BigUInt`: addition,
  subtraction, multiplication, division, modulo and power operations.
- Support both floor division (round toward negative infinity) and truncate
  division (round toward zero) semantics for mathematical correctness.
- Add complete comparison operations for `BigInt` with proper handling of
  negative values.
- Implement efficient string representation and parsing for `BigInt` and
  `BigUInt`.
- Add advanced mathematical operations for `Decimal`: square root and n-th root.
- Add logarithm functions for `Decimal`: natural logarithm, base-10 logarithm,
  and logarithm with arbitrary base.
- Add exponential function and power function with arbitrary exponents for
  `Decimal`.

### 🦋 Changed in v0.2.0

- Completely re-write the core arithmetic functions for `Decimal` type using
  `UInt128` introduced in Mojo 25.2. This significantly improves the performance
  of `Decimal` operations.
- Improve memory management system to reduce allocations during calculations.
- Reorganize codebase with modular structure (decimal, arithmetics, comparison,
  exponential).
- Enhance `Decimal` comparison operators for better handling of edge cases.
- Update internal representation of `Decimal` for better precision handling.

### ❌ Removed in v0.2.0

- Remove deprecated legacy string formatting methods.
- Remove redundant conversion functions that were replaced with a more unified
  API.

### 🛠️ Fixed in v0.2.0

- Fix edge cases in division operations with zero and one.
- Correct sign handling in mixed-sign operations for `Decimal`.
- Fix precision loss in repeated addition/subtraction operations.
- Correct rounding behavior in edge cases for financial calculations.
- Address inconsistencies between operator methods and named functions.

### 📚 Documentation and testing in v0.2.0

- Add a test suite for `BigInt` and `BigUInt` with over 200 test cases.
- Create detailed API documentation for both `Decimal` and `BigInt`.
- Add performance comparison benchmarks between DeciMojo and Python's
  decimal/int implementation.
- Update multi-language documentation to include all new functionality (English
  and Chinese).
- Include clear explanations of division semantics and other potentially
  confusing numerical concepts.
