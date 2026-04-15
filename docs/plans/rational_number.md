# Rational Number Plan

> Date of initial planning: 2025-07-15
> Author: Yuhao Zhu
> Scope: A first-class exact rational number type `Rational`
> Target: decimo v0.10.0+
>
> 子曰工欲善其事必先利其器
> The mechanic, who wishes to do his work well, must first sharpen his tools -- Confucius

## 1. Motivation

A rational number type can represent any value p/q (where p, q are integers and q ≠ 0) without any loss of precision. Unlike `BigDecimal`, which loses precision when representing numbers like 1/3, a `Rational` type preserves exactness through all arithmetic operations. This makes it ideal for:

- **Lossless intermediate computation**: algorithms like binary splitting (already used in `pi_chudnovsky_binary_split`) accumulate exact rational sums before a single final conversion to `BigDecimal`, avoiding compounding rounding error.
- **Exact linear algebra and combinatorics**: Gaussian elimination, binomial coefficients, and probability calculations benefit from exact fractions.
- **Conversion hub**: a `Rational` can be losslessly converted to/from integers and can be converted to `BigDecimal` or `Float64` at any desired precision.

A simple internal `Rational` struct already exists in `src/decimo/bigdecimal/constants.mojo` (using `BigInt10` for p and q), but it is a private helper with no normalization, no arithmetic, and no trait conformance. This plan proposes a full public type.

## 2. Design Decision: BigInt as the Underlying Integer Type

| Criterion               | BigInt (base 2^32)                             | BigInt10 (base 10^9)     | BigUInt (base 10^9, unsigned) |
| ----------------------- | ---------------------------------------------- | ------------------------ | ----------------------------- |
| GCD / LCM support       | ✓ (binary Stein's algorithm)                   | ✗                        | ✗                             |
| Extended GCD            | ✓                                              | ✗                        | ✗                             |
| Bitwise operations      | ✓                                              | ✗                        | ✗                             |
| Signed                  | ✓                                              | ✓                        | ✗                             |
| Performance vs Python   | Add 4.30×, Mul 3.98×, Power 11.17×             | Slower                   | N/A                           |
| Forward-looking status  | Primary integer type (alias `BInt`, `Integer`) | Legacy, being phased out | Internal for `BigDecimal`     |
| Arithmetic completeness | +, -, *, //, %, **, mod_exp, mod_inv, sqrt     | +, -, *, //, %           | +, -, * (internal)            |

**Recommendation**: Use `BigInt` for both numerator and denominator.

- GCD is **essential** for keeping fractions in lowest terms. `BigInt` already has a fast binary GCD (Stein's algorithm) plus extended GCD and LCM.
- `BigInt` is significantly faster for the heavy multiplication and division operations that dominate rational arithmetic.
- `BigInt` is the recommended forward-looking integer type in decimo; using it aligns with the project's direction.
- The existing `Rational` in `constants.mojo` should be migrated from `BigInt10` to `BigInt` once the new type is ready.

## 3. Cross-Library Comparison

### 3.1 Core Design

| Feature            | Python `Fraction`          | Java `BigFraction`           | Rust `Ratio<T>`        | Boost `rational<I>`   | Proposed `Rational`       |
| ------------------ | -------------------------- | ---------------------------- | ---------------------- | --------------------- | ------------------------- |
| Underlying integer | Python `int` (arbitrary)   | Java `BigInteger`            | Generic `T: Integer`   | Template `I`          | `BigInt`                  |
| Immutable          | ✓                          | ✓                            | ✓ (by convention)      | ✓ (mostly)            | Mutable (Mojo convention) |
| Auto-normalizes    | ✓ (always lowest terms)    | ✓                            | ✓ (`new()` normalizes) | ✓ (always)            | ✓ (always lowest terms)   |
| Denominator sign   | Always positive            | Always positive              | Always positive        | Always positive       | Always positive           |
| Zero denominator   | Raises `ZeroDivisionError` | Raises `ArithmeticException` | Panics                 | Throws `bad_rational` | Raises `ValueError`       |
| NaN / Infinity     | ✗                          | ✗                            | ✗                      | ✗                     | ✗                         |

### 3.2 Construction

| Constructor         | Python                     | Java                      | Rust                     | Boost                 | Proposed                   |
| ------------------- | -------------------------- | ------------------------- | ------------------------ | --------------------- | -------------------------- |
| From two integers   | `Fraction(3, 7)`           | `BigFraction(3, 7)`       | `Ratio::new(3, 7)`       | `rational<int>(3, 7)` | `Rational(3, 7)`           |
| From single integer | `Fraction(5)`              | `BigFraction(5)`          | `Ratio::from_integer(5)` | `rational<int>(5)`    | `Rational(5)`              |
| From string `"3/7"` | `Fraction("3/7")`          | ✗                         | ✗ (via parse)            | `cin >> r`            | `Rational("3/7")`          |
| From decimal string | `Fraction("1.5")`          | ✗                         | ✗                        | ✗                     | `Rational("1.5")`          |
| From float          | `Fraction.from_float(1.5)` | `BigFraction(1.5)`        | ✗                        | ✗                     | `Rational.from_float(1.5)` |
| From BigDecimal     | —                          | `BigFraction(bigDecimal)` | —                        | —                     | `Rational(big_decimal)`    |

### 3.3 Arithmetic Operations

| Operation             | Python         | Java                           | Rust                 | Boost       | Proposed                              |
| --------------------- | -------------- | ------------------------------ | -------------------- | ----------- | ------------------------------------- |
| `+`, `-`, `*`, `/`    | ✓              | `add/subtract/multiply/divide` | ✓ (ops)              | ✓ (ops)     | ✓ (ops + dunder methods)              |
| `//` (floor div)      | ✗              | ✗                              | ✗                    | ✗           | ✓                                     |
| `%` (modulo)          | ✗              | ✗                              | `rem()`              | ✗           | ✓                                     |
| `**` (power)          | `**` (int exp) | `pow(int)`                     | `pow(i32)`           | ✗           | `**` (int exp)                        |
| Negate                | `-x`           | `negate()`                     | `-x`                 | `-x`        | `-x`                                  |
| Reciprocal            | `1/x`          | `reciprocal()`                 | `recip()`            | ✗           | `reciprocal()`                        |
| Absolute value        | `abs(x)`       | `abs()`                        | `abs()`              | `abs(x)`    | `abs(x)` / `__abs__()`                |
| Increment / Decrement | ✗              | ✗                              | ✗                    | `++` / `--` | ✗ (not idiomatic Mojo)                |
| Checked arithmetic    | ✗              | ✗                              | `CheckedAdd/Mul/...` | ✗           | Not planned (BigInt doesn't overflow) |

### 3.4 Conversion & Rounding

| Feature               | Python                   | Java                         | Rust           | Boost                   | Proposed                       |
| --------------------- | ------------------------ | ---------------------------- | -------------- | ----------------------- | ------------------------------ |
| To float              | `float(x)`               | `doubleValue()`              | —              | `rational_cast<double>` | `Float64(x)` / `to_float()`    |
| To integer (truncate) | `int(x)` / `trunc(x)`    | `intValue()`                 | `to_integer()` | `rational_cast<int>`    | `Int(x)` / `to_integer()`      |
| To BigDecimal         | —                        | `bigDecimalValue(scale, rm)` | —              | —                       | `to_bigdecimal(precision, rm)` |
| `floor()`             | `math.floor(x)`          | —                            | `floor()`      | —                       | `floor()`                      |
| `ceil()`              | `math.ceil(x)`           | —                            | `ceil()`       | —                       | `ceil()`                       |
| `round()`             | `round(x, n)`            | —                            | `round()`      | —                       | `round(ndigits)`               |
| `trunc()`             | `math.trunc(x)`          | —                            | `trunc()`      | —                       | `trunc()`                      |
| `fract()`             | —                        | —                            | `fract()`      | —                       | `fract()`                      |
| Limit denominator     | `limit_denominator(max)` | —                            | —              | —                       | `limit_denominator(max)`       |

### 3.5 Query & Comparison

| Feature                           | Python                | Java                                  | Rust                              | Boost                           | Proposed                          |
| --------------------------------- | --------------------- | ------------------------------------- | --------------------------------- | ------------------------------- | --------------------------------- |
| `numerator` / `denominator`       | Properties            | `getNumerator()` / `getDenominator()` | `numer()` / `denom()`             | `numerator()` / `denominator()` | Fields (direct access)            |
| `is_integer()`                    | `is_integer()` method | —                                     | `is_integer()`                    | —                               | `is_integer()`                    |
| `is_zero()`                       | —                     | —                                     | `is_zero()`                       | —                               | `is_zero()`                       |
| `is_positive()` / `is_negative()` | —                     | —                                     | `is_positive()` / `is_negative()` | —                               | `is_positive()` / `is_negative()` |
| Sign / signum                     | —                     | `signum()`                            | `signum()`                        | —                               | `sign()`                          |
| `==`, `!=`, `<`, `>`, `<=`, `>=`  | ✓                     | `compareTo()`                         | ✓ (Ord)                           | ✓ (ops)                         | ✓ (ops)                           |
| Hash                              | `hash(x)`             | `hashCode()`                          | `Hash`                            | —                               | `__hash__()`                      |

### 3.6 String & Display

| Feature            | Python             | Java      | Rust    | Boost   | Proposed           |
| ------------------ | ------------------ | --------- | ------- | ------- | ------------------ |
| Display format     | `"3/7"`            | `"3 / 7"` | `"3/7"` | `"3/7"` | `"3/7"`            |
| `repr()`           | `"Fraction(3, 7)"` | —         | —       | —       | `"Rational(3, 7)"` |
| Float-style format | `format(x, ".6f")` | —         | —       | —       | Future             |

### 3.7 Predefined Constants

| Constant  | Python | Java                    | Rust            | Boost | Proposed            |
| --------- | ------ | ----------------------- | --------------- | ----- | ------------------- |
| ZERO      | —      | `BigFraction.ZERO`      | `Ratio::zero()` | —     | `Rational.ZERO`     |
| ONE       | —      | `BigFraction.ONE`       | `Ratio::one()`  | —     | `Rational.ONE`      |
| TWO       | —      | `BigFraction.TWO`       | —               | —     | —                   |
| MINUS_ONE | —      | `BigFraction.MINUS_ONE` | —               | —     | —                   |
| ONE_HALF  | —      | `BigFraction.ONE_HALF`  | —               | —     | `Rational.ONE_HALF` |
| ONE_THIRD | —      | `BigFraction.ONE_THIRD` | —               | —     | —                   |

### 3.8 Notable Methods Worth Adopting

1. **`limit_denominator(max_denominator)`** (Python): Uses the continued-fraction algorithm to find the closest rational with denominator ≤ max. Very useful for approximation (e.g., finding 355/113 ≈ π). No other library has this.
2. **`to_bigdecimal(precision, rounding_mode)`** (Java-inspired): Convert to `BigDecimal` at a given scale with explicit rounding. Essential for decimo's ecosystem.
3. **`floor()` / `ceil()` / `round()` / `trunc()` / `fract()`** (Rust): Complete set of rounding-to-integer operations. `fract()` returns the fractional part as a `Rational`.
4. **`from_decimal_string("1.5")`** (Python): Parse `"1.5"` → `Rational(3, 2)`. Very user-friendly.
5. **`mediant(other)`**: Compute the mediant (a+c)/(b+d) of two fractions. Useful in Stern-Brocot tree and Farey sequence applications.
6. **`continued_fraction()`**: Return the continued-fraction representation `[a0; a1, a2, ...]` as a list of `BigInt`. Useful for number theory.

## 4. Proposed API Design

### 4.1 Struct Layout

```mojo
struct Rational(
    Absable,
    Comparable,
    ComparableCollectionElement,
    Copyable,
    EqualityComparable,
    ExplicitlyCopyable,
    Formattable,
    Hashable,
    Movable,
    RepresentableCollectionElement,
    Sized,
    Stringable,
    Writable,
):
    """An arbitrary-precision exact rational number p/q.

    The fraction is always stored in lowest terms with a positive denominator.
    """

    var numerator: BigInt
    """The numerator of the rational number."""
    var denominator: BigInt
    """The denominator of the rational number. Always positive."""
```

### 4.2 Normalization Invariant

All constructors and arithmetic operations maintain the invariant:

1. `gcd(abs(numerator), denominator) == 1` (lowest terms)
2. `denominator > 0` (sign is carried by numerator)
3. If the value is zero, the representation is `0/1`

A private `_normalize()` method computes `g = gcd(abs(numerator), denominator)` and divides both by `g`, then ensures the denominator is positive.

### 4.3 Method Categories

#### Construction

- `__init__(numerator: BigInt, denominator: BigInt)` — auto-normalizes
- `__init__(numerator: BigInt)` — integer as rational (denominator = 1)
- `__init__(value: Int)` — convenience for integer literals
- `__init__(value: String)` — parse `"3/7"`, `"1.5"`, `"-42"`, `"7e-3"`
- `from_float(value: Float64) -> Rational` — exact float-to-rational
- `from_bigdecimal(value: BigDecimal) -> Rational` — exact conversion

#### Arithmetic (return new Rational — consider `__iadd__` etc. for in-place)

- `__add__`, `__sub__`, `__mul__`, `__truediv__`
- `__floordiv__`, `__mod__`
- `__pow__(exp: Int)` — integer exponentiation
- `__neg__`, `__abs__`
- `reciprocal() -> Rational`

#### Comparison

- `__eq__`, `__ne__`, `__lt__`, `__le__`, `__gt__`, `__ge__`
- `__hash__`

#### Conversion

- `to_float() -> Float64`
- `to_integer() -> BigInt` (truncates toward zero)
- `to_bigdecimal(precision: Int, rounding_mode: RoundingMode) -> BigDecimal`
- `__int__() -> Int` (small values)
- `__float__() -> Float64`

#### Rounding (return BigInt or Rational)

- `floor() -> BigInt` — largest integer ≤ self
- `ceil() -> BigInt` — smallest integer ≥ self
- `trunc() -> BigInt` — truncate toward zero
- `round(ndigits: Int = 0) -> Rational` — round to n decimal places
- `fract() -> Rational` — fractional part (self - trunc(self))

#### Query

- `is_integer() -> Bool`
- `is_zero() -> Bool`
- `is_positive() -> Bool`
- `is_negative() -> Bool`
- `sign() -> Int` — returns -1, 0, or 1

#### Approximation & Number Theory

- `limit_denominator(max_denominator: BigInt) -> Rational`
- `continued_fraction() -> List[BigInt]`
- `mediant(other: Rational) -> Rational`

#### String

- `__str__() -> String` — `"3/7"`
- `__repr__() -> String` — `"Rational(3, 7)"`
- `write_to(writer)` — Writable conformance

#### Constants (comptime aliases or static methods)

- `ZERO = Rational(0, 1)`
- `ONE = Rational(1, 1)`
- `ONE_HALF = Rational(1, 2)`

## 5. Implementation Roadmap

### Phase 1: Core Type (Foundation)

- [ ] Create `src/decimo/rational/` module directory
- [ ] Implement `Rational` struct with `BigInt` numerator/denominator
- [ ] `_normalize()` using `BigInt.gcd()`
- [ ] Constructors: from two BigInts, from single BigInt, from Int
- [ ] Basic arithmetic: `+`, `-`, `*`, `/`
- [ ] Comparison operators: `==`, `!=`, `<`, `<=`, `>`, `>=`
- [ ] `__str__`, `__repr__`, `write_to`
- [ ] `__neg__`, `__abs__`
- [ ] Trait conformances: Stringable, Writable, Comparable, EqualityComparable, Hashable, Copyable, Movable
- [ ] Unit tests for all of the above

### Phase 2: Conversions & Rounding

- [ ] String parsing: `"3/7"`, `"1.5"`, `"-42"`, `"7e-3"`
- [ ] `from_float(Float64)`
- [ ] `from_bigdecimal(BigDecimal)`
- [ ] `to_float()`, `to_integer()`, `to_bigdecimal(precision, rounding_mode)`
- [ ] `floor()`, `ceil()`, `trunc()`, `round()`, `fract()`
- [ ] `__floordiv__`, `__mod__`
- [ ] `__pow__(Int)`
- [ ] `reciprocal()`
- [ ] In-place operators: `__iadd__`, `__isub__`, `__imul__`, `__itruediv__`
- [ ] Unit tests

### Phase 3: Advanced Features

- [ ] `limit_denominator(max)` — continued-fraction best-approximation algorithm
- [ ] `continued_fraction() -> List[BigInt]`
- [ ] `mediant(other)`
- [ ] `is_integer()`, `is_zero()`, `is_positive()`, `is_negative()`, `sign()`
- [ ] Predefined constants: `ZERO`, `ONE`, `ONE_HALF`
- [ ] Mixed-type arithmetic: `Rational + BigInt`, `Rational + Int`, etc.
- [ ] Unit tests

### Phase 4: Integration

- [ ] Migrate `constants.mojo`'s internal `Rational` (BigInt10-based) to the new type
- [ ] Add `Rational` to `decimo/prelude.mojo` exports
- [ ] Add type alias: `Frac` or `Fraction`
- [ ] Add examples in `examples/examples_on_rational.mojo`
- [ ] CLI calculator support for rational expressions
- [ ] Documentation in user manual
- [ ] Benchmark suite in `benches/rational/`

## 6. Key Design Decisions

| Decision                        | Choice                      | Rationale                                                                                |
| ------------------------------- | --------------------------- | ---------------------------------------------------------------------------------------- |
| Underlying integer              | `BigInt`                    | Has GCD, is faster, is the primary integer type                                          |
| Mutability                      | Mutable struct              | Mojo convention; in-place ops avoid allocation                                           |
| Auto-normalization              | Always                      | All four reference libraries do this; prevents unbounded growth                          |
| Zero denominator                | Raise `ValueError`          | Consistent with decimo error handling; no NaN/Infinity (matches all reference libraries) |
| Sign convention                 | Denominator always positive | Universal convention across all reference libraries                                      |
| String format                   | `"3/7"` (no spaces)         | Matches Python and Rust; parseable round-trip                                            |
| `__truediv__` vs `__floordiv__` | Both                        | `/` returns `Rational`; `//` returns `BigInt` (floor division)                           |

## 7. Complexity Notes

Rational arithmetic can cause **coefficient explosion**: numerators and denominators grow with each operation unless kept in lowest terms. Auto-normalization (dividing by GCD after each operation) is critical. The cost of GCD is O(n²) for n-digit numbers (using binary Stein's algorithm on `BigInt`), which is acceptable since the alternative — deferring normalization — leads to exponentially growing intermediates.

For applications that chain many operations, consider:

- Using `BigDecimal` with a fixed precision instead, if exact representation is not needed.
- Providing a `reduce()` method that is a no-op (since we always normalize), but documents the intent for users coming from other libraries.

## 8. Future Extensions (Out of Scope)

- **Gaussian rationals**: `Rational` + `Rational * i` for exact complex arithmetic.
- **p-adic rationals**: For number-theoretic applications.
- **Rational matrix**: Dense matrix of `Rational` for exact linear algebra.
- **Symbolic expression tree**: Using `Rational` as leaf nodes in a CAS.
