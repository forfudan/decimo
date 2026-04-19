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

| Feature            | Python `Fraction`          | Java `BigFraction`           | Rust `Ratio<T>`        | Boost `rational<I>`   | Proposed `Rational`        |
| ------------------ | -------------------------- | ---------------------------- | ---------------------- | --------------------- | -------------------------- |
| Underlying integer | Python `int` (arbitrary)   | Java `BigInteger`            | Generic `T: Integer`   | Template `I`          | `BigInt`                   |
| Immutable          | ✓                          | ✓                            | ✓ (by convention)      | ✓ (mostly)            | Mutable (Mojo convention)  |
| Auto-normalizes    | ✓ (always lowest terms)    | ✓                            | ✓ (`new()` normalizes) | ✓ (always)            | ✓ (always lowest terms)    |
| Denominator sign   | Always positive            | Always positive              | Always positive        | Always positive       | Always positive            |
| Zero denominator   | Raises `ZeroDivisionError` | Raises `ArithmeticException` | Panics                 | Throws `bad_rational` | Raises `ZeroDivisionError` |
| NaN / Infinity     | ✗                          | ✗                            | ✗                      | ✗                     | ✗                          |

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

| Constant    | Python | Java                    | Rust            | Boost | Proposed               |
| ----------- | ------ | ----------------------- | --------------- | ----- | ---------------------- |
| zero()      | —      | `BigFraction.ZERO`      | `Ratio::zero()` | —     | `Rational.zero()`      |
| one()       | —      | `BigFraction.ONE`       | `Ratio::one()`  | —     | `Rational.one()`       |
| two()       | —      | `BigFraction.TWO`       | —               | —     | `Rational.two()`       |
| minus_one() | —      | `BigFraction.MINUS_ONE` | —               | —     | `Rational.minus_one()` |
| one_half()  | —      | `BigFraction.ONE_HALF`  | —               | —     | `Rational.one_half()`  |
| one_third() | —      | `BigFraction.ONE_THIRD` | —               | —     | `Rational.one_third()` |

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

| Decision                        | Choice                      | Rationale                                                                         |
| ------------------------------- | --------------------------- | --------------------------------------------------------------------------------- |
| Underlying integer              | `BigInt`                    | Has GCD, is faster, is the primary integer type                                   |
| Mutability                      | Mutable struct              | Mojo convention; in-place ops avoid allocation                                    |
| Auto-normalization              | Always                      | All four reference libraries do this; prevents unbounded growth                   |
| Zero denominator                | Raise `ZeroDivisionError`   | Consistent with implementation; no NaN/Infinity (matches all reference libraries) |
| Sign convention                 | Denominator always positive | Universal convention across all reference libraries                               |
| String format                   | `"3/7"` (no spaces)         | Matches Python and Rust; parseable round-trip                                     |
| `__truediv__` vs `__floordiv__` | Both                        | `/` returns `Rational`; `//` returns `BigInt` (floor division)                    |

## 7. Complexity Notes

Rational arithmetic can cause **coefficient explosion**: numerators and denominators grow with each operation unless kept in lowest terms. Auto-normalization (dividing by GCD after each operation) is critical. The cost of GCD is O(n²) for n-digit numbers (using binary Stein's algorithm on `BigInt`), which is acceptable since the alternative — deferring normalization — leads to exponentially growing intermediates.

For applications that chain many operations, consider:

- Using `BigDecimal` with a fixed precision instead, if exact representation is not needed.
- Providing a `reduce()` method that is a no-op (since we always normalize), but documents the intent for users coming from other libraries.

## 8. Literature Research: Internal Representation Best Practices

> Date of research: 2025-07-16
> Sources: Python `fractions.py`, Rust `num-rational`, Boost `rational`, GMP `mpq_t`

### 8.1 Sign Representation: Separate `sign` Field vs. Signed Numerator

**Research question:** Should a Rational struct use a separate `sign: Bool` field (like BigInt does), or embed the sign in the numerator (signed numerator + always-positive denominator)?

**Findings — all four major libraries use the same convention:**

| Library                  | Fields                                           | Sign Convention                                                                                           | Separate Sign Field? |
| ------------------------ | ------------------------------------------------ | --------------------------------------------------------------------------------------------------------- | -------------------- |
| **Python `Fraction`**    | `_numerator`, `_denominator` (Python `int`)      | Numerator carries sign; denominator always positive                                                       | No                   |
| **Rust `num::Ratio<T>`** | `numer: T`, `denom: T` (generic signed integer)  | Numerator carries sign; denominator always positive after `reduce()`                                      | No                   |
| **Boost `rational<I>`**  | Two fields of type `I` (signed integer template) | "Stored in fully normalized form: GCD=1, denominator always positive"                                     | No                   |
| **GMP `mpq_t`**          | `mpz_t` numerator, `mpz_t` denominator           | "Canonical form means no common factors and denominator is positive. Zero has unique representation 0/1." | No                   |

**Key details from source code:**

- **Rust `num-rational`** (lines 51–56 of `lib.rs`):

  ```rust
  pub struct Ratio<T> {
      numer: T,
      denom: T,
  }
  ```

  The `reduce()` method (line 164–168) enforces positive denominator:

  ```rust
  // keep denom positive!
  if self.denom < T::zero() {
      replace_with(&mut self.numer, |x| T::zero() - x);
      replace_with(&mut self.denom, |x| T::zero() - x);
  }
  ```

- **Python `fractions.py`**: The `__new__` constructor normalizes sign via:

  ```python
  if denominator < 0:
      numerator = -numerator
      denominator = -denominator
  ```

- **Boost `rational<I>`**: Documentation states: "Internally, rational numbers are always stored in normalized form — the numerator and denominator have no common factors, and the denominator is always positive."

- **GMP `mpq_t`**: Documentation states: "A rational number is stored as a pair of `mpz_t` integers, canonical form means denominator and numerator have no common factors, and denominator is positive."

**Conclusion:** The universal convention is **no separate sign field**. The sign is encoded in the signed numerator, and the denominator is always positive. This is the correct choice for our `Rational` struct.

**Why not a separate sign field?**

1. **Redundancy**: Since `BigInt` already has a `sign: Bool` field internally, a separate `sign` on `Rational` would be redundant. The numerator's `BigInt.sign` already carries the sign.
2. **Consistency invariant**: A separate sign field creates a three-way consistency problem (rational sign, numerator sign, denominator sign). With the convention "sign in numerator, denom positive", there's only one invariant to maintain.
3. **Simplicity of arithmetic**: All four libraries implement negation as `Ratio(-numer, denom)` — just negate the numerator. With a separate sign field, every operation would need to reconcile the sign.
4. **Industry consensus**: 40+ years of implementations (GMP since 1991, Python since 2.6, Rust, Boost, Java) all converged on the same design.

### 8.2 Underlying Integer Type: BigInt vs. BigInt10

**Research question:** Should numerator and denominator use `BigInt` (base 2^32 binary) or `BigInt10` (base 10^9 decimal)?

| Criterion         | BigInt (base 2^32)                         | BigInt10 (base 10^9)     |
| ----------------- | ------------------------------------------ | ------------------------ |
| GCD support       | Binary Stein's algorithm (fast)            | Not implemented          |
| LCM support       | Yes                                        | No                       |
| Extended GCD      | Yes                                        | No                       |
| Arithmetic speed  | 4.3× faster add, 4.0× faster mul vs Python | Slower                   |
| Bitwise ops       | Full support                               | No                       |
| Project direction | Primary type, aliased as `BInt`, `Integer` | Legacy, being phased out |

All four reference libraries use a binary representation for the underlying integer:

- **Python**: Python `int` (binary internally, CPython uses 30-bit digits)
- **Rust**: Generic over `T: Integer`, but `BigRational = Ratio<BigInt>` uses binary `BigInt`
- **Boost**: Template `I`, typically `int` or `long` (binary)
- **GMP**: `mpz_t` (binary limbs)

**Conclusion:** `BigInt` is the correct choice. GCD is essential for normalization, and `BigInt10` lacks it. Additionally, `BigInt` is faster and is the project's primary integer type going forward.

### 8.3 Normalization Strategy

All four libraries auto-normalize after every operation:

| Library           | When                                         | How                                                        |
| ----------------- | -------------------------------------------- | ---------------------------------------------------------- |
| Python `Fraction` | In constructor                               | `g = math.gcd(numer, denom); numer //= g; denom //= g`     |
| Rust `Ratio`      | In `new()`, after each op via `Ratio::new()` | `g = numer.gcd(&denom); numer /= g; denom /= g` + sign fix |
| Boost `rational`  | After every assignment/op                    | `normalize()` — GCD + sign fix                             |
| GMP `mpq_t`       | `mpq_canonicalize()` — user must call        | GCD + sign fix                                             |

Notably, Rust's `Ratio` also provides `new_raw()` which skips normalization for performance-critical paths where the caller guarantees the inputs are already normalized.

**Recommendation:** Always auto-normalize (matching Python, Rust `new()`, Boost). Optionally provide a `_raw()` internal constructor that skips normalization for internal use where normalization is already guaranteed.

### 8.4 Comparison Strategy (Avoiding Overflow)

Rust `num-rational`'s comparison is noteworthy — it avoids cross-multiplication overflow by using a recursive algorithm based on floor division:

```txt
cmp(a/b, c/d):
  if b == d: compare numerators directly
  if a == c: compare denominators inversely
  else: compute floor_div and remainders, recurse on reciprocals
```

This is important for fixed-size integers but less critical for `BigInt` (which doesn't overflow). However, cross-multiplication (`a*d` vs `b*c`) can create unnecessarily large intermediates. Consider the Rust approach for efficiency.

### 8.5 Arithmetic Optimization (GCD Before Multiplication)

Rust `num-rational` uses a cross-GCD optimization for multiplication and division to avoid coefficient explosion:

```txt
a/b * c/d:
  gcd_ad = gcd(a, d)
  gcd_bc = gcd(b, c)
  result = (a/gcd_ad * c/gcd_bc) / (d/gcd_ad * b/gcd_bc)
```

This reduces intermediate sizes significantly. All four libraries use similar pre-reduction strategies. Our implementation should adopt this pattern.

### 8.6 Summary of Validated Design Decisions

| Decision                                | Our Implementation | Industry Consensus                  | Status        |
| --------------------------------------- | ------------------ | ----------------------------------- | ------------- |
| No separate sign field                  | ✓                  | ✓ (all 4 libraries)                 | **Validated** |
| Sign in numerator, denom positive       | ✓                  | ✓ (all 4 libraries)                 | **Validated** |
| BigInt as underlying type               | ✓                  | ✓ (binary representation universal) | **Validated** |
| Auto-normalization                      | ✓                  | ✓ (all except GMP which is manual)  | **Validated** |
| `_raw()` constructor (no normalization) | ✓                  | ✓ (Rust `new_raw()`)                | **Validated** |
| Zero = 0/1                              | ✓                  | ✓ (all 4 libraries)                 | **Validated** |

## 9. Future Extensions (Out of Scope)

- **Gaussian rationals**: `Rational` + `Rational * i` for exact complex arithmetic.
- **p-adic rationals**: For number-theoretic applications.
- **Rational matrix**: Dense matrix of `Rational` for exact linear algebra.
- **Symbolic expression tree**: Using `Rational` as leaf nodes in a CAS.
