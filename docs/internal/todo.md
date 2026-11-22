# TODO

Decided work only, one item each with the reason. Measurements and settled questions are in `notes.md`; designs for larger work are in `plans/`; finished plans are in `archived/`. Updated at each release.

Last updated 2026-11-22.

## Performance

- **`BigInt` subtraction: break the borrow chain.** `_subtract_words()` still runs one chain. Splitting `_add_words()` into four segments made addition 1.5x faster above 125 words, and subtraction has the same shape.
- **`BigInt.power()`: a dedicated `square()`.** Squaring needs about half the word products of a general multiply.
- **`BigInt`: measure `CUTOFF_KARATSUBA`.** It is 64 words (~1200 digits); GMP switches near 500 digits. Our Comba base case is fast, so measure rather than assume.
- **Large multiplication.** At 10^6 digits we are 3.8x GMP, and division and `sqrt` inherit it. Lazy reduction in the NTT (~1.15x) is the cheap idea left; Schönhage-Strassen is the one that would close the gap.
- **Audit 128-bit and 256-bit divisions by a runtime value** in `decimal128/`, `rational/` and `bigint/exponential.mojo`. Each one is a software helper costing 20-40 ns. A constant divisor is fine.
- **`true_divide` keeps 90 digits to answer 28.** With a long divisor the `+2` guard words keep five base-10^18 words. Argue any cut against the tie-detection fallback.

## Python package

- **The extension runs the same Mojo code ~2.8x slower** than a plain shared library. Send a minimal repro upstream before tuning more here.
- **`Decimal(x)` where `x` is already a `Decimal`** costs 71 ns against `decimal`'s 35. The widest single gap in the package.
- **`.pyi` stub for `Decimal128`.** Only `Decimal` has one.
- **Register `Decimal` with `numbers.Number`**, so it joins Python's numeric tower.
- **Bind `BigInt`.** Only the decimal types are exposed.

## API

- **`BigDecimal.exponent()` and `significand()`**, so the public fields can change without breaking callers.
- **`signum()` and `clamp()` on `BigDecimal` and `BigInt`.** `Decimal128` has both.
- **`to_integral_value()`, `to_integral_exact()` and `as_integer_ratio()` on Mojo `BigDecimal`.** Only the Python layer has them.
- **`is_integer()` and `as_integer_ratio()` on `BigInt`.** Same reason.
- **`is_close(other, rel_tol, abs_tol)`.** No `decimal` counterpart, so the signature needs a decision first.
- **`BigDecimal.from_fraction(numerator, denominator, precision)`**, the conversion from `Rational`.
- **Arithmetic with `Int` without an implicit conversion**, on the arbitrary-precision types.
- **Rounding mode as an enum**, once Mojo has enums.

## Functions

The order and the reasons are in `plans/math_functions.md`.

- **`BigComplex`** over two `BigDecimal`s. Gamma and zeta matter mostly off the real line, so it comes first.
- **Special functions:** `gamma`, `lgamma`, `erf`, `erfc`, `beta`, `digamma`, `zeta`.
- **Numerics:** `findroot`, tanh-sinh quadrature.

## Rational

- **`//` and `%`.** Python's `Fraction` has both.
- **`continued_fraction()` and `mediant()`.**
- **Arithmetic with `BigInt` and `Int` directly.**
- **Benchmarks.** There are none yet.

## CLI and limo

- **Unit tests for limo's `LineEditor`:** buffer edits, cursor moves, history.
- **limo: history saved to a file, UTF-8 input and wide-character width.**
