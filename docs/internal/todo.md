# TODO

The one ranked list of what to do next. Everything else points here: the
enhancement plans in `docs/plans/` carry the detail and the reasoning, and
`internal_notes.md` carries the measurements, but neither keeps its own
ranking. There were four such lists in August 2026 and they had already
drifted apart, so there is now one.

Last reviewed 2026-08-30 (seventh pass).

## `BigInt` against GMP (20260827)

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
3. **Break the carry chain in add and subtract.** **Addition done 20260902;
   `_subtract_words()` still runs one borrow chain.** `_add_words()` cuts the
   array into four segments
   that add with no carry in, interleaved in one loop so the core can
   actually overlap them, and stitches the segment carries afterwards. The
   stitch is cheap because a carry only travels while it meets words of all
   ones. Four loops rather than one interleaved loop would not have worked:
   the reorder window does not span a segment.

   `BigInt` addition, ns per word, four chains against one:

   | words | one chain | four | |
   | ----: | --------: | ---: | --- |
   |    26 |     1.142 | 1.115 | below the cutoff, same path |
   |    37 |     0.927 | 0.828 | 1.12x |
   |    63 |     0.696 | 0.601 | 1.16x |
   |   125 |     0.664 | 0.443 | 1.50x |
   |   260 |     0.578 | 0.362 | 1.60x |
   |  5 191 |    0.499 | 0.319 | 1.56x |

   That is 1.75 cycles a word down to about 1.05, which is where GMP's
   `ADCS` chain runs. `_ADD_SEGMENT_MIN` is 32 words; under it the setup and
   the stitch cost more than the shorter chain buys.

   **Subtraction is the same shape and has not been done.**
   `_subtract_words()` carries the borrow the same way and should take the
   same treatment; the stitch is a borrow that travels while it meets words
   of zero rather than of all ones.

   **The gain does not reach multiplication or division.** Measured with the
   path on and off and the package rebuilt between: multiply and divide move
   by at most 3% at every size, which is noise. Additions are simply a small
   share of what those spend, and at a million digits multiplication is the
   transform, which does no bignum addition at all. Worth knowing before
   anyone prices the next carry-chain idea by what the recursion might
   inherit.

   Checked over 1 196 adversarial cases -- `2^(64k) - 1` for every `k` from
   1 to 299, where the carry has to ripple across every possible segment
   boundary and out of the top -- plus the full suite.
4. **Multiplication thresholds.** `CUTOFF_KARATSUBA` is 64 words, which is
   1233 decimal digits; GMP switches around 500. Our Comba is good enough that
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

Ordered by value. The Python package is where the library is still behind
CPython's `decimal`, and the first item is why: the extension build runs the
same code at about 2.8x. The Mojo library itself is ahead of libmpdec on
every operation but division and parsing, where it is 1.16x and 1.23x.

1. **The extension build runs the same Mojo code at about 2.8x (20260902).**
   Not a `divide` problem or a `parse` problem, and not interop per call.
   The same source, the same loop, no Python inside it, parsing ten-byte
   decimals:

   | where                                | ns   |
   | ------------------------------------ | ---- |
   | `mojo run`                           | 21.4 |
   | `mojo build`, executable             | 25.0 |
   | plain `.so`, called through `ctypes` | 20.6 |
   | `_decimo.so`, the Python extension   | 58.5 |

   Both `.so` files are loaded into a CPython process, so the host and its
   allocator are the same in the two bottom rows. A plain shared library is
   as fast as an executable, so this is not shared-library codegen either.

   **It lands on memory, not on instructions.** A loop of integer arithmetic
   that never touches the heap is 1.365 ns in the plain library and 1.749 in
   the extension -- 1.28x. The parse, which allocates, is 2.84x. The
   extension is 1.48 MB against the plain library's 108 KB for the same
   parse code, which points at code layout and instruction cache rather than
   at the arithmetic.

   Ruled out: optimization level (`mojo build` defaults to `-O3`); the
   `decimo.mojoc` boundary (`-I src` against the sources gives 44.07 against
   43.75, so no cross-module inlining is lost); the per-call binding (~8 ns
   between the in-library loop and one `Decimal("...")`); reading the
   `_Global`; the `PythonObject` subscript in the constructor
   (`PyObject_Length` plus `PyTuple_GetItem` measured neutral); the
   `try`/`except` around the parse (~3 ns); the block pool (keeping the
   parsed values rather than dropping them costs 2.3 ns); and a wrong
   constructor overload (`__init__` takes a `StringSlice`, and there is no
   `String` overload to fall into).

   Next: a minimal repro for upstream -- one `.so` built plain and one built
   as an extension from the same file. 2.8x across everything the package
   does dwarfs what the individual operations have left, so it is worth
   asking before spending more here.

2. **`Decimal(x)` where `x` is already a `Decimal`: 71.1 ns against 35.0
   (20260902).** The widest single gap left in the Python package, and the
   one place where CPython's constructor is *faster* than its own no-argument
   one. Ours costs 18.1 ns over `Decimal()`; theirs costs less than nothing.
   Not taken apart yet.

   For scale, the rest of the constructor, decimo against `decimal`:
   `Decimal()` 53.0 against 74.4 and `Decimal(0)` 59.4 against 84.4 -- both
   ahead -- while `Decimal("1.99999999")` is 124.5 against 107.6. The
   marginal cost per digit is already even (14.1 ns against 15.2 from `"0"`
   to nine digits); it is the fixed cost of the string path that is behind,
   and item 1 is most of it.

3. **`true_divide` keeps 90 digits to answer 28 (20260902).** At 100-digit
   operands and a precision of 28, division from Python is 2.15x `decimal`
   where 28 digits is 1.05x. The truncation path does fire -- 6 divisor words
   against a `needed_divisor_words` of 5 -- but `ceildiv(p, 18) + 2 + G` with
   `G = 1` still keeps five base-10^18 words, which is 90 digits. The error
   bound in the comment above `TRUNCATION_GUARD` justifies the `+2`, and `G`
   has already come down from 4, so anything further has to be argued against
   the tie-detection fallback rather than guessed.

4. ~~**Newton reciprocal division.**~~ **Dropped 20260902: our division is
   already cheaper than the replacement.** The case for it was that division
   cost 4.9 same-size multiplications, measured just after the transform
   landed. Base 2^64, base 10^18, the Knuth D work and the block pool have
   all landed since, and a 2n-by-n division now costs:

   | digits    | multiply | divide  | div/mul |
   | --------- | -------- | ------- | ------- |
   | 1 000     | 1.06 us  | 1.80 us | 1.70    |
   | 10 000    | 46.6 us  | 76.7 us | 1.64    |
   | 100 000   | 1.23 ms  | 3.12 ms | 2.53    |
   | 1 000 000 | 25.0 ms  | 81.3 ms | 3.25    |

   A Barrett divide is a Newton reciprocal, about 3 M(n) with precision
   doubling, plus two multiplications for the quotient and remainder: 4 to 5
   M(n) for a one-shot division, and only amortised to ~2 M(n) when the same
   divisor is reused, which the binary splitting in `pi()` never does. At
   3.25 M(n) we are already under that, and under GMP's own 2.6 ratio at the
   small end.

   This is what the `BigInt` against GMP section above already concluded from
   the other direction -- "neither needs a new division algorithm" -- and
   `internal_notes.md`'s "worth about 20% now" is the stale half of the
   record. The lever for division is item 6: it is built out of
   multiplications and inherits whatever they gain.
5. ~~**`subtract_inplace()`** builds a negated copy of its right operand.~~
   **Done 20260902.** It built a whole `BigDecimal` with a copied coefficient
   just to flip one sign bit, and the copy costs an allocation as soon as the
   coefficient outgrows the inline words. The sign is an argument now:
   `add_inplace_signed()` carries the body and both `add_inplace()` and
   `subtract_inplace()` delegate to it.

   | digits | `x += y` | `x -= y` before | after | ratio to add |
   | -----: | -------: | --------------: | ----: | -----------: |
   |      9 |  4.45 ns |         5.85 ns | 4.40  |         0.99 |
   |     28 |  5.68    |         6.82    | 5.73  |         1.01 |
   |    100 |  8.16    |        27.03    | 8.18  |         1.00 |
   |  1 000 | 27.45    |        46.65    | 27.45 |         1.00 |

   Subtraction costs what addition costs now, which is what it should: they
   do the same arithmetic. The hundred-digit row is 3.3x because that is
   where the coefficient stops fitting inline -- six base-10^18 words -- so
   the copy was reaching the allocator. Checked against the out-of-place
   `subtract()` and `add()` over 196 pairs covering both signs, zero, unequal
   scales and both magnitude orders.
6. ~~**Radix-4 for the NTT.**~~ **Dropped 20260902: the multiply it was
   meant to remove is not expensive.** The case rested on two legs. The first
   was already weak in our own notes -- the butterfly is not memory-bound
   (2^15 costs 1.29 ns and 2^19 costs 1.40, a 9% spread over 16x the working
   set), so halving the passes buys little. The second was that radix-4 turns
   a quarter of the twiddle multiplies into a shift, because `2^96 = -1` for
   this prime makes the fourth root of unity `2^48`.

   The arithmetic checks out -- `2^96 mod P = P - 1`, `(2^48)^2 = -1`,
   `(2^48)^4 = 1` -- and a shift-based `x * 2^48 mod P` written from
   `2^64 = 2^32 - 1` and `2^96 = -1` agrees with `mod_mul` on every value
   tried. It is just not faster:

   | | latency (serial) | throughput (4 chains) |
   | ----------------- | ------- | ------- |
   | `mod_mul(x, w4)`  | 2.18 ns | 0.703 ns |
   | shift-based `w4`  | 2.61 ns | 0.749 ns |

   Both ways round it loses. `mul` and `umulh` are pipelined and the shift
   path has more dependent operations, so replacing a general modular
   multiply with the "cheap" one makes the butterfly slower, not faster.
   Radix-4 would therefore remove no multiplies at all, leaving only the
   pass-count saving that leg one already priced at a few percent.

   The deeper reason to stop: `mod_mul` is 0.70 ns of throughput, about two
   cycles. A 64-bit modular multiply has nothing left in it. **Shoup
   twiddles are separately impossible here** -- `2P` does not fit a `UInt64`
   for a prime this close to `2^64`, and overflows on a measured 25% of
   values.

   What is left for the transform is lazy reduction (~1.15x) and, to actually
   close the gap to GMP, Schonhage-Strassen, which multiplies by a root of
   unity with a bit shift because its modulus is chosen so that this is free.
   Ours is not.

7. **Audit the remaining `UInt128` and `UInt256` uses.** Three of the day's
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
8. ~~**Base 10^18 for `BigUInt`.**~~ **Done 20260828 (#288).** A 28-digit
   value is two words where it used to be four, the same as libmpdec.
   Measured on the same operands, base 10^9 over base 10^18: add 1.06x to
   1.54x, multiply up to 2.91x, divide up to 2.16x. The traps the type
   checker could not see are recorded in `docs/plans/bigint_enhancement.md`
   under T-W1.
9. ~~**`floor_divide()` 2n-by-n scaling** in `BigUInt`~~ -- answered below.

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

- [ ] Finish `BigDecimal`'s `decimal` method surface. Issue #175 tracked this
      and is closed; what its list still showed as missing has mostly landed,
      much of it in v0.14.0's `bigdecimal/spec.mojo`. What is left, sorted by
      whether it is work:

      *Real work.* `__hash__` -- the Python binding has a `tp_hash` slot but
      the Mojo type has none, so `BigDecimal` cannot be a dictionary key in
      Mojo. `as_integer_ratio`. `to_integral_value` and `to_integral_exact`:
      `rounding.mojo` has `quantize`, `round` and `round_to_precision_inplace`
      and nothing that rounds to an integer under the context.

      *One line each*, because decimo has no NaN or infinity and one canonical
      form: `canonical`, `is_canonical`, `is_finite` (always true), `is_nan`,
      `is_snan`, `is_qnan` (always false), `radix` (always 10).

      *Blocked on a decision.* `is_normal` and `is_subnormal` need a smallest
      exponent, and decimo's exponents are unbounded. The Python layer answers
      them with an `Emin` it keeps itself; Mojo would need the same or an
      argument.

      *Not applicable.* `__complex__` and `conjugate` -- Mojo has no complex
      type.

      Renamed rather than missing, in case the old names are wanted as
      aliases: `max_mag` is `max_absolute`, `min_mag` is `min_absolute`,
      `is_signed` is `is_negative`.

- [ ] Expose the trigonometric functions on `decimo.Decimal` in Python. The
      Mojo `BigDecimal` has `sin`, `cos`, `tan`, `cot`, `csc`, `sec` and
      `arctan`, each with the `_rounded` variant that v0.14.0 added, and the
      Python `Decimal128` exposes its own set -- but `decimo.Decimal` has
      none of them, which is backwards: the arbitrary-precision type is the
      one a caller would reach for. `sqrt`, `exp`, `ln` and `log10` already
      go through `def_py_c_method` to take `rounding=`, so this is six
      wrappers on that pattern plus their registrations. Found while writing
      the v0.14.0 README; nothing tracked it before.

- [ ] Implement a complex number class `BigComplex` that uses `Decimal` for the
      real and imaginary parts. This will allow users to perform high-precision
      complex number arithmetic.

- [ ] Implement different methods for adding decimo types with `Int` types so
      that an implicit conversion is not required.

## Investigations

- [ ] (20260902) conda-forge, once Mojo is on it. `mojo`, `max`, `modular` and
      `mojo-compiler` are all 404 on conda-forge; Mojo ships only from
      Modular's own channel. A conda-forge package may depend only on
      conda-forge, so their CI cannot build the extension, and repackaging the
      wheel is not something they take for a compiled extension. Not a
      difficulty, a wall.

      Answered for now: **do not**. The Mojo library is already a conda
      package -- `modular-community` is a conda channel -- and `pip install
      decimo` works inside a conda environment, since the wheel carries its
      own Mojo runtime. A private channel on anaconda.org would add a release
      step that nothing discovers, and every extra channel is another place
      that quietly falls behind: Homebrew sat four months and three releases
      out of date. Revisit if Mojo reaches conda-forge, where the feedstock
      bot would carry the maintenance.

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

- [x] (20260828) **Cache the Mojo compilation cache in CI. Done.**
      `run_tests.yaml` restores `.mojo_cache` after `setup-pixi`, keyed per
      job. The notes below are the measurements that decided the shape.
      Mojo keeps a
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
