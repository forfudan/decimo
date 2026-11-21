<!--
The `mdbook:` comments in this file split it into the pages of the online
book (decimo.mojo-lang.com, built by the decimo-docs repository). A page runs
from its `page` comment to the next one; `skip` leaves a part out of the book.
GitHub does not show these comments. A new section that should be a page of
its own needs a `page` comment above its heading.

`[forthcoming]` comments mark text about changes after the latest release.
Reword or remove those notes when the release is made.
-->
<!-- mdbook: page file="introduction.md" title="Introduction" -->
# Decimo — User Manual <!-- omit from toc -->

Decimo is an arbitrary-precision arithmetic library for
[Mojo](https://www.modular.com/mojo), written in pure Mojo. Its numbers grow
as needed: an integer never overflows, and a decimal keeps as many digits as
you ask for.

```mojo
from decimo.prelude import *


def main() raises:
    print(BInt(2) ** 100)                    # 1267650600228229401496703205376
    print(Decimal("0.1") + Decimal("0.2"))   # 0.3, not 0.30000000000000004
    print(Decimal(2).sqrt(precision=50))     # sqrt(2) to 50 digits
```

## Which type to use <!-- omit from toc -->

| Type         | Short name           | Use it for                                                                | Covered in                           |
| ------------ | -------------------- | ------------------------------------------------------------------------- | ------------------------------------ |
| `BigInt`     | `BInt`               | Integers of any size, like Python's `int`                                 | [Part I](#part-i--bigint-bint)       |
| `Decimal`    | `BigDecimal`, `BDec` | Decimals of any precision, like Python's `decimal.Decimal`                | [Part II](#part-ii--decimal-bdec)    |
| `BigFloat`   | `BFlt`               | Binary floats of any precision, correctly rounded, like MPFR              | [Part III](#part-iii--bigfloat-bflt) |
| `Rational`   | `Frac`               | Exact fractions, like Python's `fractions.Fraction`                       | [Part IV](#part-iv--rational-frac)   |
| `Decimal128` | `Dec128`             | A fixed 128-bit decimal: up to 29 digits, 0 to 28 of them after the point | [Part V](#part-v--decimal128-dec128) |
| `BigUInt`    | `BUInt`              | Non-negative integers in base 10^18; it holds the digits of a `Decimal`   | —                                    |

Every type except `Rational` and `BigUInt` comes with the prelude. All examples
in this manual assume it at the top of the file:

```mojo
from decimo.prelude import *
```

Start with [Installation](#installation) and the [Quick Start](#quick-start).
The source is on [GitHub](https://github.com/forfudan/decimo), and the
[changelog](changelog.md) lists what changed in each release.

<!-- mdbook: skip -->

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Part I — BigInt (`BInt`)](#part-i--bigint-bint)
  - [Overview (BigInt)](#overview-bigint)
  - [Construction (BigInt)](#construction-bigint)
  - [Operators (BigInt)](#operators-bigint)
  - [Division (BigInt)](#division-bigint)
  - [Math and Number Theory (BigInt)](#math-and-number-theory-bigint)
  - [Conversion and Queries (BigInt)](#conversion-and-queries-bigint)
- [Part II — Decimal (`BDec`)](#part-ii--decimal-bdec)
  - [Overview (Decimal)](#overview-decimal)
  - [How Precision Works (Decimal)](#how-precision-works-decimal)
  - [Construction (Decimal)](#construction-decimal)
  - [Arithmetic (Decimal)](#arithmetic-decimal)
  - [Division (Decimal)](#division-decimal)
  - [Comparison (Decimal)](#comparison-decimal)
  - [Rounding and Formatting (Decimal)](#rounding-and-formatting-decimal)
  - [Roots and Powers (Decimal)](#roots-and-powers-decimal)
  - [Exponential and Logarithmic (Decimal)](#exponential-and-logarithmic-decimal)
  - [Trigonometric Functions (Decimal)](#trigonometric-functions-decimal)
  - [Functions Near Zero (Decimal)](#functions-near-zero-decimal)
  - [Constants (Decimal)](#constants-decimal)
  - [Conversion and Output (Decimal)](#conversion-and-output-decimal)
  - [Query Methods (Decimal)](#query-methods-decimal)
  - [Python Interoperability (Decimal)](#python-interoperability-decimal)
- [Part III — BigFloat (`BFlt`)](#part-iii--bigfloat-bflt)
  - [Overview (BigFloat)](#overview-bigfloat)
  - [Construction (BigFloat)](#construction-bigfloat)
  - [How Rounding Works (BigFloat)](#how-rounding-works-bigfloat)
  - [Mathematical Functions (BigFloat)](#mathematical-functions-bigfloat)
  - [Other Bases and Exact Results (BigFloat)](#other-bases-and-exact-results-bigfloat)
  - [`hypot` and `arctan2` (BigFloat)](#hypot-and-arctan2-bigfloat)
  - [Roots (BigFloat)](#roots-bigfloat)
  - [Power (BigFloat)](#power-bigfloat)
  - [Functions Near Zero (BigFloat)](#functions-near-zero-bigfloat)
  - [Special Values (BigFloat)](#special-values-bigfloat)
  - [IEEE 754 Functions (BigFloat)](#ieee-754-functions-bigfloat)
  - [Decimal Conversion (BigFloat)](#decimal-conversion-bigfloat)
  - [BigFloat, Decimal, or MPF](#bigfloat-decimal-or-mpf)
- [Part IV — Rational (`Frac`)](#part-iv--rational-frac)
  - [Construction (Rational)](#construction-rational)
  - [Arithmetic (Rational)](#arithmetic-rational)
  - [Rounding (Rational)](#rounding-rational)
  - [Closest Fraction (Rational)](#closest-fraction-rational)
  - [Conversions (Rational)](#conversions-rational)
- [Part V — Decimal128 (`Dec128`)](#part-v--decimal128-dec128)
  - [Construction (Decimal128)](#construction-decimal128)
  - [Arithmetic and Rounding (Decimal128)](#arithmetic-and-rounding-decimal128)
  - [Mathematical Functions (Decimal128)](#mathematical-functions-decimal128)
  - [Conversion and Queries (Decimal128)](#conversion-and-queries-decimal128)
- [Tools](#tools)
  - [Chinese Numerals](#chinese-numerals)
  - [Expression Engine](#expression-engine)
- [Appendices](#appendices)
  - [Appendix A — Import Paths](#appendix-a--import-paths)
  - [Appendix B — Traits Implemented](#appendix-b--traits-implemented)
  - [Appendix C — Complete API Tables](#appendix-c--complete-api-tables)

<!-- mdbook: end skip -->

<!-- mdbook: page file="installation.md" -->
## Installation

Decimo is a [pixi](https://pixi.sh) package in the
[modular-community](https://repo.prefix.dev/modular-community) channel. It
needs Mojo 1.2.

To start a new project with Decimo:

```bash
pixi init my-project \
    -c https://conda.modular.com/max \
    -c https://repo.prefix.dev/modular-community \
    -c conda-forge
cd my-project
pixi add mojo decimo
```

For an existing project, add the modular-community channel to the `channels`
list in `pixi.toml`:

```toml
channels = ["https://conda.modular.com/max", "https://repo.prefix.dev/modular-community", "conda-forge"]
```

Then run `pixi add decimo`, or add the dependency by hand and run
`pixi install`:

```toml
decimo = ">=0.16.0, <0.17.0"
```

To check that it works, save this as `hello.mojo`:

```mojo
from decimo.prelude import *


def main() raises:
    print(BInt(2) ** 100)
```

and run it:

```bash
pixi run mojo run hello.mojo
# 1267650600228229401496703205376
```

<!-- mdbook: page file="quick-start.md" -->
## Quick Start

Each block below goes inside `def main() raises:`, after
`from decimo.prelude import *`.

**Integers** never overflow. `BInt` works like Python's `int`:

```mojo
var a = BInt("12345678901234567890")
print(a * 42)             # 518518513851851851380
print(BInt(2) ** 100)     # 1267650600228229401496703205376
```

**Decimals** are exact where a binary float is not. Operators round to 28
significant digits, as Python's `decimal` does. Methods take a precision:

```mojo
print(Decimal("0.1") + Decimal("0.2"))   # 0.3
print(Decimal(1) / Decimal(3))           # 0.3333333333333333333333333333
print(Decimal(2).sqrt(precision=50))     # 50 significant digits
print(Decimal.pi(precision=30))          # 3.14159265358979323846264338328
```

**Binary floats** have any precision you choose, in bits. A tenth is not exact
in binary, at any precision:

```mojo
print(BigFloat.from_string("0.1", 100))        # 0.10000000000000000000000000000002
print(BigFloat.from_string("2", 200).sqrt())   # 200 bits of the square root of 2
```

**Fractions** are exact. `Rational` is not in the prelude, so add
`from decimo import Rational` at the top of the file:

```mojo
print(Rational(1, 3) + Rational(1, 6))   # 1/2
```

Next, read the part for the type you need: [BigInt](#part-i--bigint-bint),
[Decimal](#part-ii--decimal-bdec), [BigFloat](#part-iii--bigfloat-bflt),
[Rational](#part-iv--rational-frac) or [Decimal128](#part-v--decimal128-dec128).

<!-- mdbook: page file="bigint/index.md" -->
## Part I — BigInt (`BInt`)

### Overview (BigInt)

`BigInt` (alias `BInt`) is an arbitrary-precision signed integer
type — the Mojo-native equivalent of Python's `int`. It supports
unlimited-precision integer arithmetic, bitwise operations, and number-theoretic
functions.

| Property          | Value                        |
| ----------------- | ---------------------------- |
| Full name         | `BigInt`                     |
| Alias             | `BInt`                       |
| Internal base     | 2^64 (binary representation) |
| Word type         | `UInt64` (little-endian)     |
| Python equivalent | `int`                        |

<!-- mdbook: page file="bigint/construction.md" -->
### Construction (BigInt)

A `BInt` can be built from an `Int`, an integer literal of any size, a
`String`, or any integral SIMD value.

#### From zero <!-- omit from toc -->

```mojo
var x = BInt()          # 0
```

#### From `Int` <!-- omit from toc -->

```mojo
var x = BInt(42)
var y = BInt(-100)
var z: BInt = 42        # Implicit conversion from Int
```

The constructor is marked `@implicit`, so Mojo can automatically convert `Int`
to `BInt` where expected.

#### From an integer literal of any size <!-- omit from toc -->

*To be in v0.17.0.* <!-- [forthcoming] -->

```mojo
var a: BInt = 12345678901234567890123456789012345678901234567890
var b: BInt = -340282366920938463463374607431768211457
var c = BInt(2**200)
var d = a + 99999999999999999999999  # works wherever a BInt is expected
```

A literal wider than `Int` can be written directly, with no string. Its words
are worked out at compile time, so nothing is parsed at run time and nothing
can fail. `BUInt` accepts literals the same way; a negative literal is a
compile-time error there.

#### From `String` <!-- omit from toc -->

```mojo
var a = BInt("12345678901234567890")  # Basic decimal string
var b = BInt("-98765")                 # Negative number
var c = BInt("1_000_000")             # Underscores as separators
var d = BInt("1,234,567")             # Commas as separators
var e = BInt("1.23e5")                # Scientific notation (= 123000)
var f = BInt("1991_10,18")            # Mixed separators (= 19911018)
```

> [!NOTE]
> The string must represent an integer. `BInt("1.5")` raises an error. Scientific notation like `"1.23e5"` is accepted only if the result is an integer.

#### From `Scalar` (any integral SIMD type) <!-- omit from toc -->

```mojo
var x = BInt(UInt32(42))
var y = BInt(Int64(-5))
var z: BInt = UInt32(99)     # Implicit conversion
```

Accepts any integral scalar type (`Int8` through `Int256`, `UInt8` through
`UInt256`, etc.).

#### Summary of constructors <!-- omit from toc -->

| Constructor                        | Description                            |
| ---------------------------------- | -------------------------------------- |
| `BInt()`                           | Zero                                   |
| `BInt(value: IntLiteral)`          | From a literal of any size (implicit)  |
| `BInt(value: String)`              | From decimal string (raises)           |
| `BInt(value: Scalar)`              | From any integral scalar (implicit)    |
| `BInt.from_integral_scalar(value)` | From any integral scalar type          |
| `BInt.from_string(value)`          | Explicit factory from string (raises)  |
| `BInt.from_biguint(value, sign)`   | From a base-10^18 magnitude and a sign |

#### Unsafe constructors <!-- omit from toc -->

These constructors skip validation for performance-sensitive code. The caller
must ensure the data is valid.

| Constructor                            | Description                               |
| -------------------------------------- | ----------------------------------------- |
| `BInt(uninitialized_capacity=n)`       | Empty words list with reserved capacity   |
| `BInt(raw_words=Magnitude, sign=Bool)` | From raw words, no leading-zero stripping |

`Magnitude` is `BInt`'s word storage, exported from `decimo`. Its words are
`UInt64` and its base is 2^64; before v0.14.0 this was a `List[UInt32]` in
base 2^32, so a literal is now `[UInt64(1)]`, and an existing `List` goes in
as `BInt(raw_words=Magnitude(words^), sign=False)`.

<!-- mdbook: page file="bigint/operators.md" -->
### Operators (BigInt)

The operators of `BInt`: arithmetic, comparison, bitwise and shift.
[Division](#division-bigint) has its own page.

#### Arithmetic

##### Binary operators <!-- omit from toc -->

| Expression        | Description                       | Raises?            |
| ----------------- | --------------------------------- | ------------------ |
| `a + b`           | Addition                          | No                 |
| `a - b`           | Subtraction                       | No                 |
| `a * b`           | Multiplication                    | No                 |
| `a / b`           | Truncating division (toward zero) | Yes (zero div)     |
| `a // b`          | Floor division (rounds toward −∞) | Yes (zero div)     |
| `a % b`           | Floor modulo (Python semantics)   | Yes (zero div)     |
| `a.__divmod__(b)` | Floor quotient and remainder      | Yes (zero div)     |
| `a ** b`          | Exponentiation                    | Yes (negative exp) |

##### Unary operators <!-- omit from toc -->

| Expression | Description                               |
| ---------- | ----------------------------------------- |
| `-a`       | Negation                                  |
| `+a`       | Unary plus (returns copy)                 |
| `abs(a)`   | Absolute value                            |
| `if a:`    | Nonzero test (`Bool(a)` is not supported) |
| `~a`       | Bitwise NOT (two's complement)            |

##### In-place operators <!-- omit from toc -->

`+=`, `-=`, `*=`, `//=`, `%=`, `<<=`, `>>=` are all supported and perform true
in-place mutation to reduce memory allocation.

```mojo
var a = BInt("12345678901234567890")
var b = BInt(12345)
print(a + b)   # 12345678901234580235
print(a - b)   # 12345678901234555545
print(a * b)   # 152407406035740740602050
print(a // b)  # 1000054994024671
print(a % b)   # 4395
print(BInt(2) ** 10)  # 1024
```

#### Comparison

All six comparison operators (`==`, `!=`, `>`, `>=`, `<`, `<=`) are supported.
Each accepts both `BInt` and `Int` as the right operand.

```mojo
var a = BInt("12345678901234567890")
print(a > 1000)        # True
print(a == BInt("12345678901234567890"))  # True
print(a != 0)          # True
```

Additional methods:

```mojo
a.compare(b)              # Returns Int8: 1, 0, or -1
a.compare_magnitudes(b)   # Compares |a| vs |b|
```

#### Bitwise

All bitwise operations follow **Python's two's complement semantics** for
negative numbers.

| Operator | Description                   |
| -------- | ----------------------------- |
| `a & b`  | Bitwise AND                   |
| `a \| b` | Bitwise OR                    |
| `a ^ b`  | Bitwise XOR                   |
| `~a`     | Bitwise NOT: `~x == -(x + 1)` |

Each accepts both `BInt` and `Int` as the right operand. In-place variants
(`&=`, `|=`, `^=`) are also available.

```mojo
var a = BInt(0b1100)
var b = BInt(0b1010)
print(a & b)   # 8   (0b1000)
print(a | b)   # 14  (0b1110)
print(a ^ b)   # 6   (0b0110)
print(~a)      # -13

# Negative numbers use two's complement:
print(BInt(-1) & BInt(255))  # 255
```

Single bits can be read and changed by index, counting from 0 at the lowest
bit. The changing methods return a new value:

```mojo
var x = BInt(10)            # 0b1010
print(x.test_bit(1))        # True
print(x.set_bit(0))         # 11  (0b1011)
print(x.clear_bit(1))       # 8   (0b1000)
print(x.flip_bit(3))        # 2   (0b0010)
print(BInt(40).trailing_zeros())  # 3: 40 = 0b101000
```

#### Shift

Shifting a `BInt` moves its bits. The result never overflows, because a
`BInt` grows as needed.

| Operator | Description                          |
| -------- | ------------------------------------ |
| `a << n` | Left shift (multiply by `2**n`)      |
| `a >> n` | Right shift (floor divide by `2**n`) |

```mojo
var x = BInt(1)
print(x << 100)         # 1267650600228229401496703205376 (= 2^100)
print(BInt(1024) >> 5)  # 32
```

<!-- mdbook: page file="bigint/division.md" -->
### Division (BigInt)

BigInt supports two division conventions:

| Name              | Operator / Method                               | Quotient    | Python equivalent |
| ----------------- | ----------------------------------------------- | ----------- | ----------------- |
| Floor division    | `//`, `%`, `.__divmod__()`                      | Toward −∞   | `//`, `%`         |
| Truncate division | `/`, `.truncate_divide()`, `.truncate_modulo()` | Toward zero | C/Java `/`, `%`   |

`/` on a `BInt` is integer division, not a promotion to a decimal type. It
follows Mojo's own `Int`, where `Int(7) / Int(-2)` is `-3`: the quotient stays
in the type and rounds toward zero. It is therefore a different operator from
`//`, not a synonym, and the two disagree exactly when the operands have
opposite signs.

The difference matters for negative operands:

```mojo
var a = BInt(7)
var b = BInt(-2)

# Floor division (Python semantics)
print(a // b)                    # -4
print(a % b)                     # -1

# Truncate division (C/Java semantics)
print(a / b)                     # -3
print(a.truncate_divide(b))      # -3
print(a.truncate_modulo(b))      #  1
```

Named methods exist for the floor forms too, and for rounding the quotient up:

```mojo
print(BInt(-7).floor_modulo(BInt(2)))   # 1, same as %
print(BInt(7).ceil_divide(BInt(2)))     # 4
print(BInt(-7).ceil_divide(BInt(2)))    # -3
```

<!-- mdbook: page file="bigint/math.md" -->
### Math and Number Theory (BigInt)

Powers, roots and number theory for `BInt`.

#### Mathematical Functions

##### Exponentiation <!-- omit from toc -->

```mojo
print(BInt(2).power(100))    # 2^100
print(BInt(2) ** 100)         # Same via ** operator
```

Both `power(exponent: Int)` and `power(exponent: BigInt)` are supported. The
exponent must be non-negative.

##### Integer square root <!-- omit from toc -->

```mojo
var x = BInt("100000000000000000000")
print(x.sqrt())    # 10000000000 (largest y such that y² ≤ x)
print(x.isqrt())   # Same as sqrt()
```

Raises if the value is negative. Three related methods:

```mojo
var r = BInt(30).sqrt_rem()          # (5, 5): 30 = 5*5 + 5
print(BInt(49).is_perfect_square())  # True
var p = BInt(1024).perfect_power()   # (2, 10): 1024 = 2**10
```

`perfect_power()` returns the largest exponent it can, and `(x, 1)` when there
is none above one.

##### Combinatorics <!-- omit from toc -->

```mojo
print(BInt(20).factorial())         # 2432902008176640000
print(BInt(9).double_factorial())   # 945 = 9*7*5*3*1
print(BInt(10).binomial(3))         # 120 ways to choose 3 of 10
print(BInt(10).permutation(3))      # 720 ordered choices of 3 of 10
print(BInt(100).fibonacci())        # 354224848179261915075
print(BInt(10).lucas())             # 123
```

#### Number Theory

`gcd`, `lcm`, `extended_gcd`, `mod_pow`, `mod_inverse`, `jacobi`, `legendre`,
`kronecker` and `sqrt_mod` are both methods and free functions. The rest of
this section is free functions only. Import them from `decimo`:

```mojo
from decimo import gcd, lcm, extended_gcd, mod_pow, mod_inverse
```

##### GCD — Greatest Common Divisor <!-- omit from toc -->

```mojo
var a = BInt(48)
var b = BInt(18)
print(a.gcd(b))      # 6
print(gcd(a, b))      # 6 (free function)
```

##### LCM — Least Common Multiple <!-- omit from toc -->

```mojo
print(BInt(12).lcm(BInt(18)))    # 36
print(lcm(BInt(12), BInt(18)))   # 36
```

##### Extended GCD <!-- omit from toc -->

Returns `(g, x, y)` such that `a*x + b*y = g`:

```mojo
var result = BInt(35).extended_gcd(BInt(15))
# result = (5, 1, -2)   — since 35×1 + 15×(−2) = 5
```

##### Modular Exponentiation <!-- omit from toc -->

Computes `base**exp % m` without computing the full power:

```mojo
print(BInt(2).mod_pow(BInt(100), BInt(1000000007)))
print(mod_pow(BInt(2), BInt(100), BInt(1000000007)))  # free function
```

##### Modular Inverse <!-- omit from toc -->

Finds `x` such that `a * x % m == 1`:

```mojo
print(BInt(3).mod_inverse(BInt(7)))      # 5 (since 3×5 = 15 ≡ 1 mod 7)
print(mod_inverse(BInt(3), BInt(7)))      # 5
```

##### Modular square roots and symbols <!-- omit from toc -->

```mojo
from decimo import jacobi, kronecker, legendre, sqrt_mod

var s = sqrt_mod(BInt(2), BInt(7))   # Optional: 3, since 3*3 = 9 = 2 mod 7
print(s.value())                     # 3
print(legendre(BInt(2), BInt(7)))    # 1: 2 is a square modulo the prime 7
print(jacobi(BInt(2), BInt(15)))     # 1
print(kronecker(BInt(2), BInt(15)))  # 1
```

`sqrt_mod` returns nothing when there is no square root. `sqrt_mod` and
`legendre` need a prime modulus; this is not checked.

##### Chinese remainder theorem <!-- omit from toc -->

`crt(residues, moduli)` finds `x` that leaves the same remainder as
`residues[i]` when divided by `moduli[i]`, for every `i`. It returns `(x, m)`, where `m` is the least common multiple of the moduli,
or nothing when there is no solution. The moduli need not be coprime.

```mojo
from decimo import crt

var residues: List[BInt] = [BInt(2), BInt(3)]
var moduli: List[BInt] = [BInt(3), BInt(5)]
var c = crt(residues, moduli)
print(c.value()[0], c.value()[1])    # 8 15
```

##### Primes <!-- omit from toc -->

```mojo
from decimo import is_prime, next_prime, prev_prime, primes_below

print(is_prime(BInt(2) ** 127 - 1))  # True
print(next_prime(BInt(100)))         # 101
print(prev_prime(BInt(100)))         # 97
print(primes_below(30))              # [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]
```

##### Factorization and divisors <!-- omit from toc -->

```mojo
from decimo import factor, divisors, divisor_count, divisor_sum
from decimo import euler_phi, moebius, multiplicative_order

var f = factor(BInt(360))
print(f)                                      # 2^3 * 3^2 * 5
print(f.primes[0], f.powers[0])               # 2 3
print(divisors(BInt(12)))                     # [1, 2, 3, 4, 6, 12]
print(divisor_count(BInt(360)))               # 24
print(divisor_sum(BInt(12)))                  # 28
print(euler_phi(BInt(36)))                    # 12
print(moebius(BInt(30)))                      # -1
print(multiplicative_order(BInt(2), BInt(7))) # 3: 2**3 = 8 = 1 mod 7
```

`factor` returns a `Factorization`: the lists `primes` and `powers`, and a
`cofactor` it could not split. Factoring is hard for very large numbers, so
each of these functions takes an optional `budget`, the work it may spend.
When the budget runs out, `factor` returns what it found: `f.is_complete()` is
`False` and the `cofactor` holds the unfactored part. The other functions
raise `ValueError` instead.

<!-- mdbook: page file="bigint/conversion.md" -->
### Conversion and Queries (BigInt)

Turning a `BInt` into text and other types, asking about its value, and
the ready-made constants.

#### Conversion and Output

##### String conversions <!-- omit from toc -->

| Method                             | Example output      |
| ---------------------------------- | ------------------- |
| `String(x)`                        | `"12345"`           |
| `repr(x)`                          | `'BigInt("12345")'` |
| `x.to_string_with_separators("_")` | `"1_234_567"`       |
| `x.to_string_with_separators(",")` | `"1,234,567"`       |
| `x.to_hex_string()`                | `"0x1a2b3c"`        |
| `x.to_binary_string()`             | `"0b110101"`        |
| `x.to_string(line_width=20)`       | Multi-line output   |
| `x.to_chinese()`                   | `"十五"`            |

##### Numeric conversions <!-- omit from toc -->

| Method           | Description                                       |
| ---------------- | ------------------------------------------------- |
| `Int(x)`         | Convert to `Int` (raises if exceeds 64-bit range) |
| `Float64(x)`     | Convert to `Float64` (may lose precision)         |
| `x.to_biguint()` | Convert the magnitude to `BigUInt` (base-10^18)   |

```mojo
var x = BInt("123456789012345678901234567890")
print(x.to_string_with_separators())  # 123_456_789_012_345_678_901_234_567_890
print(x.to_hex_string())              # 0x...
```

`to_chinese()` writes the number in Chinese numerals; see
[Chinese Numerals](#chinese-numerals) for the reading rules and the available
styles.

```mojo
print(BInt(15).to_chinese())          # 十五
print(BInt("123456789").to_chinese()) # 一亿二千三百四十五万六千七百八十九
```

#### Query Methods

These methods answer questions about a `BInt` without changing it.

| Method                 | Return | Description                           |
| ---------------------- | ------ | ------------------------------------- |
| `x.is_zero()`          | `Bool` | `True` if value is 0                  |
| `x.is_negative()`      | `Bool` | `True` if value < 0                   |
| `x.is_positive()`      | `Bool` | `True` if value > 0                   |
| `x.is_one()`           | `Bool` | `True` if value is 1                  |
| `x.bit_length()`       | `Int`  | Number of bits in the magnitude       |
| `x.bit_count()`        | `Int`  | Population count (number of set bits) |
| `x.number_of_words()`  | `Int`  | Number of `UInt64` words              |
| `x.number_of_digits()` | `Int`  | Number of decimal digits              |

```mojo
var x = BInt(13)
print(x.bit_length())       # 4  (13 = 0b1101)
print(x.bit_count())        # 3  (three 1-bits)
print(x.number_of_digits()) # 2
print(x.is_positive())      # True
```

#### Constants and Factory Methods

Shortcuts for the `BInt` values you need most often.

| Method / Constant      | Value                                                     |
| ---------------------- | --------------------------------------------------------- |
| `BInt.zero()`          | 0                                                         |
| `BInt.one()`           | 1                                                         |
| `BInt.negative_one()`  | −1                                                        |
| `BigInt.ZERO`          | 0 (comptime; use `materialize[BigInt.ZERO]()` at runtime) |
| `BigInt.ONE`           | 1 (comptime; use `materialize[BigInt.ONE]()` at runtime)  |
| `BigInt.BITS_PER_WORD` | 64                                                        |

<!-- mdbook: page file="decimal/index.md" -->
## Part II — Decimal (`BDec`)

### Overview (Decimal)

`Decimal` is an arbitrary-precision decimal type — the Mojo-native equivalent of
Python's `decimal.Decimal`. It can represent numbers with unlimited digits and
decimal places, making it suitable for financial modeling, scientific computing,
and applications where floating-point errors are unacceptable.

| Property          | Value                                     |
| ----------------- | ----------------------------------------- |
| Name              | `Decimal`                                 |
| Aliases           | `BigDecimal`, `BDec`                      |
| Internal base     | Base-10^18 (each word stores ≤ 18 digits) |
| Default precision | 28 significant digits                     |
| Python equivalent | `decimal.Decimal`                         |

`Decimal`, `BigDecimal`, and `BDec` are all the same type. We recommend
`Decimal` for consistency with Python's `decimal.Decimal`.

<!-- mdbook: page file="decimal/precision.md" -->
### How Precision Works (Decimal)

A `Decimal` holds any number of digits, but most operations round their
result. This page says when they round and to how many digits.

- The default precision is **28** significant digits, matching Python's
  `decimal` module.
- **Operators** `+` `-` `*` `+=` `-=` `*=` (and reflected `__radd__` /
  `__rsub__` / `__rmul__`) round their result HALF_EVEN to the default precision
  (28 significant digits), matching Python `decimal.Decimal` default-context
  arithmetic.
- **Methods** `.add(other)` / `.subtract(other)` / `.multiply(other)` (and the
  in-place variants `.add_inplace(other)` / `.subtract_inplace(other)` /
  `.multiply_inplace(other)`) take an optional `precision: Int = 0` argument.
  The default `precision=0` returns the **exact, unrounded** result; passing
  `precision > 0` rounds HALF_EVEN to that many significant digits.
- **Division** and **mathematical functions** (`sqrt`, `ln`, `exp`, etc.) accept
  an optional `precision` parameter specifying the number of
  **significant digits** in the result.

```mojo
var a = Decimal("999999999999999999999999999999")  # 30 nines
var b = Decimal("1")

# Operators round to 28 digits (matches Python decimal default context)
print(a + b)             # 1.000000000000000000000000000E+30

# Methods at precision=0 (default) are exact
print(a.add(b))          # 1000000000000000000000000000000

# Methods accept an explicit precision
print(a.add(b, 50))      # 1000000000000000000000000000000 (exact, fits)
print(a.multiply(a, 40)) # 40-significant-digit rounded product
```

```mojo
var x = Decimal("2")
print(x.sqrt())                # 28 significant digits (default)
print(x.sqrt(precision=100))   # 100 significant digits
print(x.sqrt(precision=1000))  # 1000 significant digits
```

> [!NOTE]
> The default precision of 28 will be configurable globally in a
> future version when Mojo supports global variables.

<!-- mdbook: page file="decimal/construction.md" -->
### Construction (Decimal)

Decimal can be constructed from various types of input using the `Decimal()`
constructor or factory methods. Among these, the most common way is from a
**string representation** of the decimal number, which is the most accurate way
to create a Decimal without any precision loss.

#### From `String` (Decimal) <!-- omit from toc -->

It is highly recommended to construct `Decimal` from a string. Please consider
using this method whenever possible.

```mojo
var a = Decimal("123456789.123456789")  # Basic decimal string
var b = Decimal("1.23E+10")             # Scientific notation
var c = Decimal("-0.000001")            # Negative
var d = Decimal("1_000_000.50")         # Separator support
```

#### From zero (Decimal) <!-- omit from toc -->

```mojo
var x = Decimal("0")  # Explicitly from string
var y = Decimal()    # Default constructor creates zero, same as Decimal("0")
```

#### From `Int` or an integer literal (Decimal) <!-- omit from toc -->

```mojo
var x = Decimal(42)     # From Int
var y: Decimal = 100    # From an integer literal
var z: Decimal = 123456789012345678901234567890  # Wider than Int, still exact
var w = Decimal(2**200)  # Worked out exactly at compile time
```

*To be in v0.17.0:* <!-- [forthcoming] --> an integer literal of any size is exact, as `decimal.Decimal(int)` is in
Python. A run-time `Int` is 64 bits, so `Decimal(n << 100)` for an `Int` `n`
has already lost its high bits before `Decimal` sees it.

#### From integral scalars <!-- omit from toc -->

```mojo
var x = Decimal(Int64(123456789))
var y = Decimal(UInt128(99999999999999))
```

Works with all integral SIMD types.
**Floating-point scalars are rejected at compile time** — use
`from_float_scalar()` instead.

#### From `BigInt` (Decimal) <!-- omit from toc -->

A `BigInt` converts exactly, and implicitly, so it can be passed wherever a
`Decimal` is expected:

```mojo
var d: Decimal = BInt(2) ** 100
print(d)   # 1267650600228229401496703205376
```

#### From floating-point — `from_float_scalar()` <!-- omit from toc -->

`from_float_scalar()` reads the bits of the float and returns the value the
float actually holds, not the literal that was written to produce it:
`from_float_scalar(0.1)` is
0.1000000000000000055511151231257827021181583404541015625, which is what
`decimal.Decimal(0.1)` gives as well.

Note that not all decimal numbers can be represented exactly as binary
floating-point. You may lose precision without awareness.

To make the conversion from float to `Decimal` more explicit so that you are
aware of the potential precision issues, the `Decimal()` constructor does not
accept floating-point numbers directly. Instead, to create a `Decimal` from a
float, you must use the `from_float_scalar()` factory method. It accepts any
floating-point width — `Float16`, `BFloat16`, `Float32`, `Float64` and the
8-bit formats — since every one of them widens to `Float64` exactly.

Consider never using `Decimal.from_float_scalar()` in performance-sensitive
code, but use string construction instead.

```mojo
var x = Decimal.from_float_scalar(3.14159)
var y = Decimal.from_float_scalar(Float32(2.71828))
```

`from_float()` is the former name and still works, forwarding unchanged. It is
deprecated in favour of `from_float_scalar()`, which lines up with
`from_integral_scalar()`.

#### From Python — `from_python_decimal()` <!-- omit from toc -->

You can always safely construct a `Decimal` from a Python `decimal.Decimal`
using the `from_python_decimal()` method without worrying about precision loss.

```mojo
from std.python import Python

var decimal = Python.import_module("decimal")
var py_dec = decimal.Decimal("123.456")

var a = Decimal.from_python_decimal(py_dec)
var b = Decimal(py=py_dec)  # Alternative keyword-only syntax
```

#### Summary of Decimal constructors <!-- omit from toc -->

| Constructor                           | Description                         |
| ------------------------------------- | ----------------------------------- |
| `Decimal()`                           | Zero                                |
| `Decimal(value: IntLiteral)`          | From a literal of any size          |
| `Decimal(value: BigInt)`              | From `BigInt`, exact (implicit)     |
| `Decimal(value: String)`              | From string (raises)                |
| `Decimal(value: Scalar)`              | From any integral scalar (implicit) |
| `Decimal(py=py_obj)`                  | From Python `Decimal` (raises)      |
| `Decimal.from_integral_scalar(value)` | From any integral scalar type       |
| `Decimal.from_float_scalar(value)`    | From any float scalar (raises)      |
| `Decimal.from_float(value)`           | Deprecated alias of the above       |
| `Decimal.from_string(value)`          | Explicit factory from string        |
| `Decimal.from_python_decimal(py_obj)` | From Python `Decimal` (raises)      |

#### Unsafe Decimal constructors <!-- omit from toc -->

These constructors skip validation for performance-sensitive code. The caller
must ensure the data is valid.

| Constructor                                               | Description                                  |
| --------------------------------------------------------- | -------------------------------------------- |
| `Decimal(coefficient: BigUInt, scale: Int, sign: Bool)`   | From raw components                          |
| `Decimal.from_raw_components(words, scale=0, sign=False)` | From raw `List[BigUInt.Word]` words (unsafe) |
| `Decimal.from_raw_components(word, scale=0, sign=False)`  | From a single `BigUInt.Word` (unsafe)        |

<!-- mdbook: page file="decimal/arithmetic.md" -->
### Arithmetic (Decimal)

The operators `+`, `-` and `*` round their result HALF_EVEN to 28 significant
digits, as Python's `decimal` default context does. Use `.add()`, `.subtract()`
and `.multiply()` for the exact, unrounded result; see
[How Precision Works](#how-precision-works-decimal).

| Expression        | Description                           | Result               |
| ----------------- | ------------------------------------- | -------------------- |
| `a + b`           | Addition                              | Rounded to 28 digits |
| `a - b`           | Subtraction                           | Rounded to 28 digits |
| `a * b`           | Multiplication                        | Rounded to 28 digits |
| `a / b`           | True division (default precision=28)  | Rounded to precision |
| `a // b`          | Truncated division (toward zero)      | Integer part         |
| `a % b`           | Truncated modulo                      | —                    |
| `a ** b`          | Exponentiation (default precision=28) | Rounded to precision |
| `a.__divmod__(b)` | Returns `(a // b, a % b)`             | —                    |

Built-in integral types are **implicitly converted** when used in arithmetic:

```mojo
var c = Decimal("3.14") + 1        # Int → Decimal
var d = Decimal("100") * UInt(8)   # UInt → Decimal
```

In-place operators (`+=`, `-=`, `*=`) perform true in-place mutation for reduced
allocation.

```mojo
var a = Decimal("123456789.123456789")
var b = Decimal("1234.56789")
print(a + b)   # 123458023.691346789
print(a - b)   # 123455554.555566789
print(a * b)   # 152415787654.32099750190521
```

#### Result exponents (`Decimal` and `Dec128`)

decimo follows the **preferred-exponent** rules from IEEE 754-2008 §3.3
and the IBM General Decimal Arithmetic specification §4.1. Concretely:

- For `add`/`subtract`, the result exponent is `min(exp(a), exp(b))`.
- For `multiply`, the result exponent is `exp(a) + exp(b)` — even when the
  numerical value is zero. So `Decimal("123.45") * Decimal("0")` prints as
  `"0.00"`, not `"0"`, because both operands' scales are preserved in the
  product's scale (`-2 + 0 = -2`).
- For `divide`, the **ideal** exponent is `exp(a) - exp(b)`. The result
  exponent is the ideal one when the quotient is exact at that scale
  (`Decimal("10.5") / Decimal("2.5")` prints as `"4.2"`, not `"4.20"`), and
  otherwise the smallest exponent that still represents the exact value
  (`Decimal("123.45") / Decimal("-2")` prints as `"-61.725"`).
- The sign of zero is preserved (`Decimal("-0.00")` round-trips to
  `"-0.00"`).

This matches Python's `decimal.Decimal`, `System.Decimal` (.NET BCL,
both C# and VB.NET), and the GDA reference. It differs from
`rust_decimal`, which always pads multiplication-by-zero to the maximum
scale of the operands and pads exact divide quotients with trailing
zeros to the operand-scale difference. If you need rust_decimal-style
output, call `.quantize(...)` or `.normalize()` explicitly.

<!-- mdbook: page file="decimal/division.md" -->
### Division (Decimal)

Division is the primary operation where precision matters. Decimo provides
several variants:

#### `true_divide()` — recommended for decimal division <!-- omit from toc -->

```mojo
var a = Decimal("1")
var b = Decimal("3")
print(a.true_divide(b))                # 0.3333333333333333333333333333 (28 digits)
print(a.true_divide(b, precision=50))  # 50 significant digits
print(a.true_divide(b, precision=200)) # 200 significant digits
```

#### Operator `/` — true division with default precision <!-- omit from toc -->

```mojo
var result = a / b  # Same as a.true_divide(b, precision=28)
```

#### Operator `//` — truncated (integer) division <!-- omit from toc -->

```mojo
print(Decimal("7") // Decimal("4"))    # 1
print(Decimal("-7") // Decimal("4"))   # -1  (toward zero)
```

<!-- mdbook: page file="decimal/comparison.md" -->
### Comparison (Decimal)

All six comparison operators are supported:

```mojo
var a = Decimal("123.456")
var b = Decimal("123.4560")  # Same value, different scale
print(a == b)  # True (comparison by value)
print(a > 100) # True (Int implicitly converted)
```

Additional methods:

```mojo
a.compare(b)           # Returns Int8: 1, 0, or -1
a.compare_absolute(b)  # Compares |a| vs |b|
a.max(b)               # Returns the larger value
a.min(b)               # Returns the smaller value
```

<!-- mdbook: page file="decimal/rounding.md" -->
### Rounding and Formatting (Decimal)

#### `round()` — round to decimal places <!-- omit from toc -->

```mojo
var x = Decimal("123.456")
print(x.round(2))                       # 123.46 (ROUND_HALF_EVEN)
print(x.round(1))                       # 123.5
print(x.round(0))                       # 123
print(x.round(-1))                      # 1.2E+2
print(x.round(2, ROUND_DOWN))           # 123.45
print(x.round(2, ROUND_UP))            # 123.46
```

Also works with `round()` builtin:

```mojo
print(round(Decimal("123.456"), 2))  # 123.46
```

#### `quantize()` — match scale of another decimal <!-- omit from toc -->

Adjusts the scale (number of decimal places) to match the scale of `exp`. The
actual value of `exp` is ignored — only its scale matters.

```mojo
var x = Decimal("1.2345")
print(x.quantize(Decimal("0.01")))   # 1.23 (2 decimal places)
print(x.quantize(Decimal("0.1")))    # 1.2  (1 decimal place)
print(x.quantize(Decimal("1")))      # 1    (0 decimal places)

# Currency formatting:
var price = Decimal("19.999")
print(price.quantize(Decimal("0.01")))  # 20.00
```

#### `normalize()` — remove trailing zeros <!-- omit from toc -->

```mojo
print(Decimal("1.2345000").normalize())  # 1.2345
```

#### `__ceil__`, `__floor__`, `__trunc__` <!-- omit from toc -->

```mojo
print(Decimal("1.1").__ceil__())    # 2
print(Decimal("1.9").__floor__())   # 1
print(Decimal("-1.9").__trunc__())  # -1
```

#### RoundingMode

Every type in decimo that rounds uses the same seven modes. Each mode has two
spellings that are the same value: the constant `ROUND_DOWN` and the member
`RoundingMode.ROUND_DOWN`. Both are in the prelude.

| Constant          | Description                             |
| ----------------- | --------------------------------------- |
| `ROUND_DOWN`      | Truncate toward zero                    |
| `ROUND_UP`        | Round away from zero                    |
| `ROUND_HALF_UP`   | Round half away from zero (traditional) |
| `ROUND_HALF_DOWN` | Round half toward zero                  |
| `ROUND_HALF_EVEN` | Banker's rounding (default)             |
| `ROUND_CEILING`   | Round toward +∞                         |
| `ROUND_FLOOR`     | Round toward −∞                         |

```mojo
var x = Decimal("2.5")
print(x.round(0, ROUND_HALF_UP))    # 3
print(x.round(0, ROUND_HALF_EVEN))  # 2  (banker's rounding)
print(x.round(0, ROUND_DOWN))       # 2
print(x.round(0, ROUND_UP))         # 3
print(x.round(0, ROUND_CEILING))    # 3
print(x.round(0, ROUND_FLOOR))      # 2
```

<!-- mdbook: page file="decimal/roots-and-powers.md" -->
### Roots and Powers (Decimal)

All mathematical functions accept an optional `precision` parameter
(default=28).

#### Square root <!-- omit from toc -->

```mojo
print(Decimal("2").sqrt())               # 1.414213562373095048801688724
print(Decimal("2").sqrt(precision=100))  # 100 significant digits
```

#### Cube root <!-- omit from toc -->

```mojo
print(Decimal("27").cbrt())  # 3.000000000000000000000000000
print(Decimal("2").cbrt(precision=50))
```

#### Nth root <!-- omit from toc -->

```mojo
print(Decimal("256").root(Decimal("8")))    # 2
print(Decimal("100").root(Decimal("3")))    # 4.641588833612778892...
```

#### Power / exponentiation <!-- omit from toc -->

```mojo
print(Decimal("2").power(exponent=Decimal("10")))                 # 1024
print(Decimal("2").power(exponent=Decimal("0.5"), precision=50))  # sqrt(2) to 50 digits
print(Decimal("2") ** 10)                                         # 1024
```

#### Factorial <!-- omit from toc -->

The factorial of a whole `Decimal` is exact by default. With a precision, it
is rounded, which keeps large factorials fast:

```mojo
print(Decimal(30).factorial())                # 265252859812191058636308480000000
print(Decimal(1000).factorial(precision=20))  # 4.0238726007709377354E+2567
```

<!-- mdbook: page file="decimal/exp-and-log.md" -->
### Exponential and Logarithmic (Decimal)

#### Exponential (e^x) <!-- omit from toc -->

```mojo
print(Decimal("1").exp())                # e ≈ 2.718281828459045235360287471
print(Decimal("10").exp(precision=50))   # e^10 to 50 digits
```

#### Near zero: `expm1` and `log1p` <!-- omit from toc -->

For a tiny `x`, `exp(x) - 1` and `ln(1 + x)` lose their digits to
cancellation. `expm1` and `log1p` keep them:

```mojo
var tiny = Decimal("1E-20")
print(tiny.exp(precision=30) - 1)    # 1.000000000E-20: most digits are lost
print(tiny.expm1(precision=30))      # 1.00000000000000000000500000000E-20
print(tiny.log1p(precision=30))      # 9.99999999999999999995000000000E-21
```

#### Natural logarithm <!-- omit from toc -->

```mojo
print(Decimal("10").ln(precision=50))    # ln(10) to 50 digits
```

For repeated calls, a `MathCache` can be used to avoid recomputing cached
constants:

```mojo
from decimo.bigdecimal.exponential import MathCache

var cache = MathCache()
var x1 = Decimal("2")
var x2 = Decimal("2.5")
var r1 = x1.ln(100, cache)
var r2 = x2.ln(100, cache)  # Reuses cached ln(2) and ln(1.25)
```

#### Logarithm with arbitrary base <!-- omit from toc -->

```mojo
print(Decimal("100").log(base=Decimal("10")))  # 2
print(Decimal("8").log(base=2))                # 3.000000000000000000000000000
```

`log`, `power`, `arctan2` and `hypot` take the other value by keyword: `x.log(base=b)`, `x.power(exponent=e)`, `y.arctan2(other=x)` and `x.hypot(other=y)`. An `Int` converts to a `Decimal`, so a positional `x.log(100)` would read as base 100 while `x.ln(100)` means 100 digits; the keyword keeps the two apart. *To be in v0.17.0:* <!-- [forthcoming] --> the positional form still works, with a deprecation warning, and goes in v0.18.0.

#### Base-10 logarithm <!-- omit from toc -->

```mojo
print(Decimal("1000").log10())  # 3 (exact for powers of 10)
print(Decimal("2").log10(precision=50))
```

<!-- mdbook: page file="decimal/trigonometric.md" -->
### Trigonometric Functions (Decimal)

All trigonometric functions take inputs in **radians** and accept an optional
`precision` parameter.

#### Basic functions <!-- omit from toc -->

```mojo
print(Decimal("0.5").sin(precision=50))
print(Decimal("0.5").cos(precision=50))
print(Decimal("0.5").tan(precision=50))
```

#### Reciprocal functions <!-- omit from toc -->

```mojo
print(Decimal("1").cot(precision=50))   # cos/sin
print(Decimal("1").csc(precision=50))   # 1/sin
print(Decimal("1").sec(precision=50))   # 1/cos
```

#### Inverse functions <!-- omit from toc -->

```mojo
print(Decimal("1").arctan(precision=50))  # π/4 to 50 digits
print(Decimal("0.5").arcsin(precision=30))  # 0.523598775598298873077107230547
print(Decimal("0.5").arccos(precision=30))  # 1.04719755119659774615421446109
```

#### Two-argument functions <!-- omit from toc -->

`y.arctan2(other=x)` is the angle of the point `(x, y)`, and `x.hypot(other=y)`
is its distance from the origin. Pass the other value by keyword.

```mojo
print(Decimal("1").arctan2(other=Decimal("1"), precision=30))  # π/4
print(Decimal("3").hypot(other=Decimal("4")))                  # 5
```

#### Hyperbolic functions <!-- omit from toc -->

```mojo
print(Decimal("1").sinh(precision=30))     # 1.17520119364380145688238185060
print(Decimal("1").cosh(precision=30))     # 1.54308063481524377847790562076
print(Decimal("1").tanh(precision=30))     # 0.761594155955764888119458282605
print(Decimal("1").arcsinh(precision=30))  # 0.881373587019543025232609324980
print(Decimal("2").arccosh(precision=30))  # 1.31695789692481670862504634731
print(Decimal("0.5").arctanh(precision=30))  # 0.549306144334054845697622618461
```

<!-- mdbook: page file="decimal/near-zero.md" -->
### Functions Near Zero (Decimal)

Each trigonometric function of `Decimal` comes to a simple value as its
argument goes to nought: the sine to the argument itself, the cosine to one, the cosecant to
one over the argument. Every one of those is a value the destination holds
exactly, and that is awkward for a function that decides its rounding rather
than assuming it. Deciding means evaluating wider than asked until every
value the error allows rounds the same way, and an answer that lands on a
value the destination holds has values on both sides of it that round
differently, however wide the evaluation goes.

The three nearest modes do not notice, since the answer is that value either
way. The four directed modes do, because they have to say which side of it
the truth lies on.

```mojo
from decimo import Decimal, RoundingMode

var tiny = Decimal("1E-500")
print(tiny.sin(precision=20, rounding_mode=RoundingMode.ROUND_DOWN))
# 9.9999999999999999999E-501 -- the sine is below its argument
print(tiny.tan(precision=20, rounding_mode=RoundingMode.ROUND_DOWN))
# 1.0000000000000000000E-500 -- the tangent is above it
print(tiny.cos(precision=20, rounding_mode=RoundingMode.ROUND_DOWN))
# 0.99999999999999999999 -- the cosine is below one
```

So such an argument is answered from the sign of the function's own first
correction term, which is all the rounding needs: `sin(x) = x - x^3/6` is
below `x` and `tan(x) = x + x^3/3` is above it, and neither correction can be
computed at `1E-500` by any width a loop would reach.

A small argument is not the only place this happens. Wherever a function's
value is a whole number, an argument a hair away from that point has an
answer a hair away from a value the destination holds, and the same thing
goes wrong. `log10(1000)` is three exactly; `log10` of a thousand plus
`1E-500` is three plus a correction five hundred digits down.

```mojo
from decimo import Decimal, RoundingMode

var beside = Decimal("1000").add(Decimal("1E-500"))
print(beside.log10(precision=20, rounding_mode=RoundingMode.ROUND_UP))
# 3.0000000000000000001 -- above three, because the argument is above a thousand
print(beside.log10(precision=20, rounding_mode=RoundingMode.ROUND_DOWN))
# 3.0000000000000000000 -- and the same value truncated is three
```

`BigFloat` has the same answers for `ln` beside one, `log2` and `log10`
beside a power of their base, and `exp2` and `exp10` beside a whole
argument.

<!-- mdbook: page file="decimal/constants.md" -->
### Constants (Decimal)

#### π (pi) <!-- omit from toc -->

Computed using the **Chudnovsky algorithm** with binary splitting:

```mojo
print(Decimal.pi(precision=100))    # 100 digits of π
print(Decimal.pi(precision=1000))   # 1000 digits of π
```

#### e (Euler's number) <!-- omit from toc -->

Computed as `exp(1)`:

```mojo
print(Decimal.e(precision=100))     # 100 digits of e
print(Decimal.e(precision=1000))    # 1000 digits of e
```

<!-- mdbook: page file="decimal/conversion.md" -->
### Conversion and Output (Decimal)

#### String output <!-- omit from toc -->

The `to_string()` method provides flexible formatting:

```mojo
var x = Decimal("123456789.123456789")
print(x)                                          # 123456789.123456789
print(x.to_string(scientific=True))               # 1.23456789123456789E+8
print(x.to_string(engineering=True, force_exponent=True))  # 123.456789123456789E+6
print(x.to_string(delimiter="_"))                 # 123_456_789.123_456_789
print(x.to_string(line_width=20))                 # Multi-line output
print(x.to_string(force_plain=True))              # Suppress auto-scientific notation
```

Default output follows CPython's `Decimal.__str__()` rules: plain notation when
feasible, scientific notation when there would be more than 6 leading zeros
or the exponent is positive.

`Dec128` does not switch: it is bounded to 29 digits and a scale of 0 to 28,
so plain notation is never longer than 30 characters, and it always prints
plain (the .NET `System.Decimal` rule). The two types therefore print the
same value differently below `1E-6` and at a positive exponent:

```mojo
print(Decimal("1E-7"))                  # 1E-7
print(Dec128("1E-7"))                   # 0.0000001
print(Decimal("1E+28"))                 # 1E+28
print(Dec128("1E+28"))                  # 10000000000000000000000000000
print(Decimal("1E-6"), Dec128("1E-6"))  # 0.000001 0.000001
```

To get the other form: `Decimal.to_string(force_plain=True)` and
`Dec128.to_string(scientific=True)`.

Convenience aliases:

```mojo
x.to_scientific_string()               # to_string(scientific=True)
x.to_eng_string()                      # to_string(engineering=True)
x.to_string_with_separators("_")       # to_string(delimiter="_")
```

`to_chinese()` writes the number in Chinese numerals; see
[Chinese Numerals](#chinese-numerals) for the reading rules and the available
styles.

```mojo
print(Decimal("1050.07").to_chinese())  # 一千零五十点零七
```

#### `repr()` <!-- omit from toc -->

```mojo
print(repr(Decimal("123.45")))  # BigDecimal("123.45")
```

#### Decimal numeric conversions <!-- omit from toc -->

```mojo
var n = Int(Decimal("123.99").truncate())  # 123; Int() alone raises on a fraction
var f = Float64(Decimal("3.14"))   # 3.14 (may lose precision)
```

<!-- mdbook: page file="decimal/query.md" -->
### Query Methods (Decimal)

| Method                 | Return | Description                               |
| ---------------------- | ------ | ----------------------------------------- |
| `x.is_zero()`          | `Bool` | `True` if value is zero                   |
| `x.is_one()`           | `Bool` | `True` if value is exactly 1              |
| `x.is_integer()`       | `Bool` | `True` if no fractional part              |
| `x.is_negative()`      | `Bool` | `True` if negative                        |
| `x.is_positive()`      | `Bool` | `True` if strictly positive               |
| `x.is_odd()`           | `Bool` | `True` if odd integer                     |
| `x.number_of_digits()` | `Int`  | Total digits in coefficient               |
| `x.adjusted()`         | `Int`  | Adjusted exponent (≈ floor(log10(\|x\|))) |
| `x.same_quantum(y)`    | `Bool` | `True` if both have same scale            |

#### `as_tuple()` — Python-compatible decomposition <!-- omit from toc -->

```mojo
var parts = Decimal("7.25").as_tuple()
# parts[0] = False (sign), parts[1] = [7, 2, 5] (digits), parts[2] = -2 (exponent)
# sign=False, digits=[7, 2, 5], exp=-2
```

#### Other methods <!-- omit from toc -->

```mojo
x.copy_abs()             # Copy with positive sign
x.copy_negate()          # Copy with inverted sign
x.copy_sign(other)       # Copy of x with sign of other
x.fma(a, b)              # Fused multiply-add: x*a+b (exact)
x.scaleb(n)              # Multiply by 10^n (O(1), adjusts scale only)
```

<!-- mdbook: page file="decimal/python.md" -->
### Python Interoperability (Decimal)

#### From Python <!-- omit from toc -->

A Python `decimal.Decimal` converts without loss; see
[From Python](#from-python--from_python_decimal) on the Construction page.

#### Matching Python's API <!-- omit from toc -->

Many methods mirror Python's `decimal.Decimal` API:

| Python `Decimal` method | Decimo equivalent       |
| ----------------------- | ----------------------- |
| `d.quantize(exp)`       | `x.quantize(exp)`       |
| `d.normalize()`         | `x.normalize()`         |
| `d.as_tuple()`          | `x.as_tuple()`          |
| `d.copy_abs()`          | `x.copy_abs()`          |
| `d.copy_negate()`       | `x.copy_negate()`       |
| `d.copy_sign(other)`    | `x.copy_sign(other)`    |
| `d.fma(a, b)`           | `x.fma(a, b)`           |
| `d.adjusted()`          | `x.adjusted()`          |
| `d.same_quantum(other)` | `x.same_quantum(other)` |

<!-- mdbook: page file="bigfloat/index.md" -->
## Part III — BigFloat (`BFlt`)

### Overview (BigFloat)

`BigFloat` is an arbitrary-precision binary floating-point type, written in
Mojo with nothing to install. Where `Decimal` keeps digits and a scale,
`BigFloat` keeps a significand and a power of two, which is what makes it the
right type for scientific work: a square root, an exponential or a sine has
no exact decimal answer, so the question is not whether it rounds but whether
it rounds correctly. Every function here does.

| Property       | Value                                                |
| -------------- | ---------------------------------------------------- |
| Name           | `BigFloat`                                           |
| Alias          | `BFlt`                                               |
| Value          | `(-1)^sign * significand * 2^exponent`               |
| Significand    | A `BigInt`, exactly `precision` bits when non-zero   |
| Exponent       | An `Int`, so from `Int.MIN` to `Int.MAX`             |
| Precision      | A field on the value, in bits, chosen per call       |
| Special values | `NaN`, `+Infinity`, `-Infinity`, `+0` and `-0`       |
| Rounding       | All seven [rounding modes](#roundingmode), correctly |
| Dependencies   | None                                                 |

The precision is a field on the value rather than a global context. Two values
of different precisions can be added, and the destination's precision is an
argument to the operation, not a setting somewhere else:

```mojo
from decimo import BigFloat
from decimo.bigfloat.arithmetics import add

var a = BigFloat.from_string("0.1", 53)      # 53 bits
var b = BigFloat.from_string("0.1", 200)     # 200 bits
print(a == b)                                 # False: b holds more of a tenth
print(add(a, b, 300).precision)               # 300: the caller says
print((a + b).precision)                      # 200: an operator takes the wider
```

<!-- mdbook: page file="bigfloat/construction.md" -->
### Construction (BigFloat)

*To be in v0.17.0:* <!-- [forthcoming] --> the constructors `BigFloat(...)` from text, an `Int`, a `Float64`, a
literal or a `BigInt`, `from_bigint_exactly()`, and operators that take a
literal. v0.16.0 has the named forms `from_string()`, `from_int()`,
`from_float64()` and `from_bigint()`.

```mojo
from decimo import BigDecimal, BigFloat

var from_text = BigFloat("3.14159")                    # rounds, 53 bits
var wider = BigFloat("3.14159", 120)                   # rounds, 120 bits
var from_int = BigFloat(42)                            # exact
var from_double = BigFloat(0.1)                        # exact: a double is one
var from_decimal = BigFloat.from_bigdecimal(BigDecimal("0.1"), 53)

var zero = BigFloat.zero(53, False)                    # a signed zero
var infinity = BigFloat.infinity(53, True)             # -Infinity
var nan = BigFloat.nan(53)
```

With a precision, and optionally a rounding mode, each constructor is a `from_` function under another name: `BigFloat(text, p, mode)` is `from_string`, `BigFloat(n, p, mode)` is `from_int`, `BigFloat(x, p, mode)` is `from_float64`. Without a precision, text and a `Float64` get 53 bits. An `Int` gets 53 bits, or its own number of significant bits when that is more, so unlike `from_int(n)` it never rounds:

```mojo
print(BigFloat(2).precision)                    # 53
print(BigFloat((1 << 60) + 1).precision)        # 61
print(BigFloat(1 << 62).precision)              # 53
```

An integer literal wider than `Int` and a `BigInt` are exact too, by the same rule: `var x: BigFloat = 123456789012345678901234567890` has 96 bits. With a precision, `BigFloat(2**100 + 1, 10)` rounds the whole literal, and `BigFloat(n, p, mode)` for a `BigInt` is `from_bigint`. The exact conversion has its own name, `from_bigint_exactly(n)`; `from_bigint(n)` rounds to 53 bits.

The `Int` and the `Float64` constructors are implicit, so a literal can stand on either side of an operator, and in-place operators work too. Each operator rounds half to even at the wider of the two precisions, as described in the [overview](#part-iii--bigfloat-bflt). A literal has at least 53 bits, so it lifts a narrower float to 53 bits: with a 24-bit `x`, `x * 2` has 53. Mojo has no reflected comparisons, so in a comparison the literal goes on the right: `x < 2` works and `2 > x` does not compile.

A `Float64` literal is the double it stands for, not the decimal: `x * 0.1` multiplies by the double nearest a tenth. For the decimal, write `x * BigFloat("0.1", p)`, or `x / 10`.

```mojo
var x = BigFloat(1.5)
print(1 + x)                                    # 2.5
print(3 / x)                                    # 2
print(x == 1.5)                                 # True
x += 1
x *= 2
print(x)                                        # 5
```

`from_float64` is exact in both directions where there is room for it: a
`Float64` is a binary float of 53 bits, so at 53 bits or more nothing is lost
either way and every double round-trips bit for bit. Two things qualify that.
Asking for fewer bits rounds, like any other conversion — `from_float64(0.1,
24)` is not `0.1`. And a NaN does not survive: this type keeps one canonical
NaN, so a sign or a payload goes in and does not come out.

`from_string` and `from_bigdecimal` round, because almost no decimal is a
binary float, and they round correctly in whichever mode is asked for.

<!-- mdbook: page file="bigfloat/rounding.md" -->
### How Rounding Works (BigFloat)

Every function takes a precision and a rounding mode, and returns the float of
that precision nearest the true value, with the mode settling which side when
the true value sits between two. That is a stronger promise than "accurate to
the last bit or so", and the difference shows in the directed modes:

```mojo
from decimo.bigfloat import sqrt
from decimo import RoundingMode

var two = BigFloat.from_int(2, 53)
print(sqrt(two, 53, RoundingMode.ROUND_DOWN))      # toward zero
print(sqrt(two, 53, RoundingMode.ROUND_UP))        # away from zero
print(sqrt(two, 53, RoundingMode.ROUND_HALF_EVEN)) # the default
```

For a transcendental function the true value cannot be computed, only
approached, so the answer is decided rather than assumed: the function is
evaluated wider than asked, and the rounding is only returned when every value
the error allows rounds the same way. If they do not, the width grows and it is
tried again. This is Ziv's method, and it is why the last bit can be trusted.

<!-- mdbook: page file="bigfloat/math.md" -->
### Mathematical Functions (BigFloat)

| Function                                | Where                           |
| --------------------------------------- | ------------------------------- |
| `add`, `subtract`, `multiply`, `divide` | `decimo.bigfloat.arithmetics`   |
| `sqrt`, `exp`, `ln`                     | `decimo.bigfloat.exponential`   |
| `root`, `cbrt`                          | `decimo.bigfloat.exponential`   |
| `hypot`                                 | `decimo.bigfloat.exponential`   |
| `exp2`, `exp10`, `log2`, `log10`, `log` | `decimo.bigfloat.exponential`   |
| `expm1`, `log1p`                        | `decimo.bigfloat.exponential`   |
| `power`                                 | `decimo.bigfloat.power`         |
| `sin`, `cos`, `tan`                     | `decimo.bigfloat.trigonometric` |
| `cot`, `csc`, `sec`                     | `decimo.bigfloat.trigonometric` |
| `arcsin`, `arccos`, `arctan`            | `decimo.bigfloat.trigonometric` |
| `arctan2`                               | `decimo.bigfloat.trigonometric` |
| `sinh`, `cosh`, `tanh`                  | `decimo.bigfloat.hyperbolic`    |
| `arcsinh`, `arccosh`, `arctanh`         | `decimo.bigfloat.hyperbolic`    |
| `pi`, `ln2`, `ln10`, `e`                | `decimo.bigfloat.constants`     |
| `fma`, `remainder`, `fmod`              | `decimo.bigfloat.ieee`          |

Each takes its arguments, a precision in bits and an optional rounding mode
(half to even by default), and returns the float of that precision nearest
the true value. `log` takes the base as its second argument, before the
precision.

`cot` and `csc` have a pole at zero and return an infinity of the zero's
sign, the way a float does; `Decimal` raises there instead, having no
infinity to return.

```mojo
from decimo.bigfloat.constants import pi
from decimo.bigfloat import exp, ln
from decimo.bigfloat.trigonometric import sin

print(pi(200).to_bigdecimal_rounded(60))
print(exp(BigFloat.from_int(1), 120))
print(ln(BigFloat.from_int(2), 120))
print(sin(BigFloat.from_string("1e10", 60), 53))
```

That last one is worth a word. Reducing an argument of `10^10` by `pi/2` has
to cancel its leading bits against pi, so the number of bits of pi needed is
counted from the argument rather than fixed — `sin(2^300)` fetches three
hundred bits of pi before the first bit of its answer is right. An argument
whose leading bit sits beyond what a precision may be is refused rather than
answered badly.

*To be in v0.17.0:* <!-- [forthcoming] --> each function except the constants and the four arithmetic ones is also a method. `fma`, `remainder` and `fmod` always take a precision, as they do as functions. The rest come in two forms. Without a precision it keeps this value's own precision and rounds half to even. With a precision, and optionally a rounding mode, it behaves like the free function asked for those:

```mojo
var x = BigFloat.from_int(2, 53)
print(x.sin())                         # 53 bits, half to even
print(x.sin(200))                      # 200 bits, half to even
print(x.sin(200, RoundingMode.ROUND_UP))
print(BigFloat.from_int(8, 53).log2())        # 3
print(BigFloat.from_int(27, 53).log(base=BigFloat.from_int(3, 53)))  # 3
print(BigFloat.from_int(27, 53).log(200, base=3).precision)  # 200
```

*To be in v0.17.0:* <!-- [forthcoming] --> the four methods of two values, `log`, `power`, `hypot` and `arctan2`, take the other value by keyword: `x.log(base=b)`, `x.power(exponent=e)`, `x.hypot(other=y)` and `y.arctan2(other=x)`. That keeps one rule for every method: a positional `Int` is a precision. Without a precision they keep the wider of the two precisions. The positional form, `x.log(b)`, still works in v0.17.0 with a deprecation warning, and goes in v0.18.0.

<!-- mdbook: page file="bigfloat/bases.md" -->
### Other Bases and Exact Results (BigFloat)

`log2`, `log10`, `log`, `exp2` and `exp10` have something the natural
exponential and logarithm do not: arguments whose answers a float holds
exactly. `log2(8)` is three, and three is a float.

That matters because a correctly rounded transcendental function works by
deciding its rounding rather than assuming it — evaluating wider than asked
until every value the error allows rounds the same way. An answer sitting
exactly on a representable value can never be decided that way, however wide
the evaluation goes, because there are values on both sides of it that round
differently. So those arguments are recognized first, from the integer
significand, and answered exactly:

```mojo
from decimo.bigfloat import exp2, log, log10, log2

print(log2(BigFloat.power_of_two(-70), 53))        # exactly -70
print(log10(BigFloat.from_int(1000), 53))          # exactly 3
print(log(BigFloat.from_int(27), BigFloat.from_int(3), 53))   # exactly 3
print(log(BigFloat.from_int(3), BigFloat.from_int(9), 53))    # exactly 0.5
print(exp2(BigFloat.from_int(10), 53))             # exactly 1024
```

Which arguments those are has an exact answer in each case, and each is worth
knowing:

- `log2(x)` is exact exactly when `x` is a power of two, which is every
  argument whose significand is a single bit, at any exponent.
- `log10(x)` is exact exactly when `x` is `10^k` for a `k` at nought or above.
  A negative power of ten is not a binary float at all — a fifth is not a
  dyadic rational — so `log10` of the float nearest a thousandth is
  irrational and a hair away from `-3`, and it is answered by the series.
- `log(x, base)` is exact whenever the answer is exactly representable, which
  includes `log(3, 9) = 0.5` and not only the whole answers. An answer that is
  exact but not representable, like `log(9, 27) = 2/3`, goes through the
  series and comes back correctly rounded like any other.
- `exp2(x)` is exact exactly when `x` is a whole number, and `exp10(x)` when
  `x` is a whole number at nought or above and `10^x` still fits the precision
  asked for. Past that `10^x` is not representable, so the series settles on
  it.
- `expm1` and `log1p` are exact only at zero, where both are zero with the
  sign of the argument, and `expm1(-Infinity)` which is exactly minus one.

<!-- mdbook: page file="bigfloat/hypot-arctan2.md" -->
### `hypot` and `arctan2` (BigFloat)

`hypot(x, y, precision, mode)` is the length of the point and
`arctan2(y, x, precision, mode)` is its angle, with `x.hypot(other=y)` and
`y.arctan2(other=x)` over them. Together they turn a pair of coordinates into polar
form.

`hypot` forms `x*x + y*y` exactly, in integers, and never as two roundings
that could each be wrong. Both squares are integers — a significand is one —
so the sum over their common exponent is an integer too, and the integer
square root of it brackets the answer with its remainder as the sticky bit.
So `hypot(3, 4)` is `5`, in every mode, which a pair of rounded squares and a
rounded root could not promise.

A leg far below the other contributes nothing but a sticky bit, and the
answer is then the larger leg moved by a hair — not the larger leg itself,
which is the mistake that would make `hypot(x, tiny)` wrong in the directed
modes.

`arctan2` is where signed zeros earn their keep. `arctan2(0, -1)` is `pi` and
`arctan2(-0, -1)` is `-pi`: the two zeros lie on opposite shores of the cut
along the negative axis, and the sign is the only thing that says which one a
point on the cut came from. The argument order is the one every other
language uses — the second coordinate first, because the function inverts a
tangent and a tangent is a rise over a run.

```mojo
from decimo.bigfloat import arctan2, hypot
from decimo import BigFloat

def main() raises:
    var x = BigFloat.from_int(3, 53)
    var y = BigFloat.from_int(4, 53)
    print(hypot(x, y, 53))            # 5
    print(arctan2(y, x, 53))          # 0.92729521800161219
```

<!-- mdbook: page file="bigfloat/roots.md" -->
### Roots (BigFloat)

`root(x, degree, precision, mode)` and `cbrt(x, precision, mode)`, also
`x.root(n)` and `x.cbrt()`, take any positive degree.

They need no series and no deciding loop, because a root is algebraic. The
integer `degree`-th root of a scaled significand brackets the true root
between two consecutive integers, and whether it landed on the lower one
exactly is the sticky bit; one rounding then finishes the job in each of the
seven modes. So an exact root comes out exact — `root(8, 3)` is `2` in every
mode, including the directed ones, where a function that evaluated and then
rounded would have to pick a side and both sides would be wrong.

Dividing the exponent is the whole of the scaling. `x` is
`s * 2^(q * degree + r)` with `r` below the degree, so the factor of `2^r`
moves into the significand and the root sits at `2^q`. The product is never
formed again, which is what keeps a value near the bottom of the exponent
range from leaving it.

A negative value has a real root only at an odd degree, and gives a NaN at an
even one, the way `sqrt` does. A nought keeps its sign at an odd degree and
loses it at an even one. A degree of nought or less is refused rather than
answered.

<!-- mdbook: page file="bigfloat/power.md" -->
### Power (BigFloat)

`power(x, y, precision, mode)`, also `x.power(exponent=y)` and `x ** y`, raises one
value to another. It ends in `exp(y ln x)`, and almost nothing about it is
that line.

The reason is the same one [the other bases](#other-bases-and-exact-results-bigfloat) have, only more so. A power sits
on an exactly representable answer constantly: `2 ** 10` is `1024`, which
every directed mode has to return and no bracket around it can prove. What
is less obvious is that a *fractional* exponent does it too — `4 ** 0.5` is
exactly `2`, and `16 ** 0.25` is as well — so recognizing the whole
exponents is not enough.

Three kinds of exact answer are found before any series runs.

A whole exponent is a power of the significand. `x` is `s * 2^e`, so `x^n` is
`s^n * 2^(en)`, and `s^n` is an integer however large; it is formed while it
is short enough to be worth forming, and one rounding finishes it. A
negative whole exponent is one correctly rounded division of exact operands.

A base that is a power of two answers any exponent leaving a whole result:
`2^m` to the `a / 2^b` is `2^(ma / 2^b)`, exact exactly when `2^b` divides
`m`.

Anything else with a fractional exponent — and every binary float is `a / 2^b`
for some `a` and `b` — is `b` square roots followed by a whole power. A
square root is exact only when the significand is a perfect square, and each
exact root halves the bits, so the question answers itself within a few steps
or not at all.

What reaches the series is therefore known to be irrational, where the loop
settles.

```mojo
from decimo.bigfloat import power
from decimo import BigFloat
from decimo import RoundingMode

def main() raises:
    var two = BigFloat.from_int(2, 53)
    print(two ** BigFloat.from_int(10, 53))      # 1024, in every mode
    print(BigFloat.from_int(4, 53) ** BigFloat.from_string("0.5", 53))  # 2
    print(power(two, BigFloat.from_string("0.5", 53), 53,
                RoundingMode.ROUND_DOWN))        # 1.4142135623730949
```

The special values follow IEEE 754's `pow`, which answers two cases before it
looks at anything else: a nought exponent gives one for every base, a NaN
included, and a base of one gives one for every exponent, a NaN included.
A negative base with a fractional exponent gives a NaN, there being no real
answer. There is no overflow to an infinity for finite arguments — this
type's exponent is as wide as an `Int`, and an answer asking for more is
refused rather than answered with an infinity it did not earn.

<!-- mdbook: page file="bigfloat/near-zero.md" -->
### Functions Near Zero (BigFloat)

`expm1` is `exp(x) - 1` and `log1p` is `ln(1 + x)`, and both exist because the
expressions they are named after throw their answers away for a small
argument. `exp(2^-100)` rounds to one, so the difference is nought where the
answer is `2^-100`; `1 + 2^-100` rounds to one, so the logarithm is nought
too. These two compute the difference and the logarithm directly:

```mojo
from decimo.bigfloat import expm1, log1p

var tiny = BigFloat.power_of_two(-100000)
print(expm1(tiny, 53).internal_representation())   # 2^-100000, not nought
print(log1p(tiny, 53).internal_representation())   # and a hair under it
```

They are also what the hyperbolic functions are built on, which is why
`sinh(2^-100000)` is `2^-100000` rather than zero.

<!-- mdbook: page file="bigfloat/special-values.md" -->
### Special Values (BigFloat)

The special values follow IEEE 754 rather than `Decimal`'s rules, because this
is a float:

```mojo
from decimo.bigfloat import ln, sqrt
from decimo.bigfloat.trigonometric import arctan, sin

print(sqrt(BigFloat.from_int(-4), 53).is_nan())      # True, not an error
print(ln(BigFloat.zero(), 53))                        # -Infinity
print(sin(BigFloat.infinity(), 53).is_nan())          # True: it settles nowhere
print(arctan(BigFloat.infinity(), 53))                # pi/2: this one settles
```

Three methods tell the kinds apart: `x.is_nan()`, `x.is_infinite()` and
`x.is_finite()`. A NaN is neither infinite nor finite.

A NaN is unordered, so every comparison with it is False except `!=`, and that
holds for a NaN against itself. The two zeros compare equal. Sorting therefore
needs an order that covers them, and `compare_total(x, y)` is it (import it
from `decimo.bigfloat.comparison`): it runs from
`-Infinity` up to the NaN and separates values that are numerically equal by
their precision.

There is no overflow to an infinity for a finite argument. The exponent is as
wide as an `Int`, so an operation that asks for more — `exp` of anything from
about `6.4e18` up — raises rather than returning an infinity it did not earn.

<!-- mdbook: page file="bigfloat/ieee754.md" -->
### IEEE 754 Functions (BigFloat)

Beyond the arithmetic and the functions, IEEE 754 asks a format for a set of
small operations that numerical code reaches for constantly. They are in
`decimo.bigfloat.ieee`, which is where they are imported from, and each one is
also a method on the value:

| Function                             | What it gives                               |
| ------------------------------------ | ------------------------------------------- |
| `next_plus(x, p)`                    | The smallest value above `x` at `p` bits    |
| `next_minus(x, p)`                   | The largest value below it                  |
| `next_toward(x, y, p)`               | One step from `x` in the direction of `y`   |
| `logb(x)`                            | `floor(log2(abs(x)))`, as a `BigInt`        |
| `scaleb(x, n)`                       | `x * 2^n`, exactly                          |
| `copy_sign(x, y)`                    | `x` with the sign of `y`                    |
| `copy_abs(x)`, `copy_negate(x)`      | The sign dropped, the sign flipped          |
| `number_class(x)`                    | `+Normal`, `-Zero`, `NaN`, and so on        |
| `is_integer(x)`                      | Whether `x` is a whole number               |
| `truncate(x)`, `floor(x)`, `ceil(x)` | The three named roundings to a whole number |
| `round_to_integer(x, mode)`          | The same in any of the seven modes          |
| `fma(x, y, z, p, mode)`              | `x * y + z` with a single rounding          |
| `remainder(x, y, p)`                 | `x - y*n`, `n` the nearest integer          |
| `fmod(x, y, p)`                      | `x - y*n`, `n` the quotient truncated       |

```mojo
from decimo import BigFloat
from decimo.bigfloat import fma, next_plus, remainder

var one = BigFloat.from_float64(1.0)
print(next_plus(one, 53))                     # 1 + 2^-52
print(one.next_minus(53))                     # 1 - 2^-53, half a step away
print(String(BigFloat.from_float64(12.0).logb()))   # 3
print(one.scaleb(10))                          # 1024, nothing computed
print(BigFloat.from_string("-0.5", 53).ceil()) # -0, the sign surviving
print(remainder(BigFloat.from_float64(5.0), BigFloat.from_float64(3.0), 53))
# -1: six is nearer to five than three is. `fmod` of the same pair is 2.
```

`fma` is the one with substance. `x * y + z` written out rounds the product
before the addition sees it, and a product that nearly cancels with `z` loses
exactly the bits the answer is made of. Here the product is formed exactly —
it is an integer times a power of two, so there is nothing to round — and only
the sum is rounded:

```mojo
var above = next_plus(one, 53)             # 1 + 2^-52
var product = above * above                 # rounded: 1 + 2^-51
print(product + (-product))                 # 0: the two-step answer
print(fma(above, above, -product, 53))      # 2^-104: what the rounding dropped
```

Two of these differ from a double, and both follow from the type rather than
from a choice. `number_class` never answers `+Subnormal` or `-Subnormal`: a
significand here always holds its full precision, so every finite non-zero
value is normal. And `next_plus` and `next_minus` step through an exponent
range as wide as an `Int`, so the ends they reach are not a double's —
`next_plus(BigFloat.zero(), 53)` is `2^(Int.MIN + 52)` where a double answers
`2^-1074`. Within that range the two agree bit for bit, which is how these are
tested.

`logb` returns a `BigInt` rather than an `Int` because the position of the
leading bit is `exponent + precision - 1`, and that sum can be outside an
`Int` while the value itself is an ordinary one. It has no answer for a zero,
an infinity or a NaN, where the standard's answers are infinities and a NaN,
and raises instead.

<!-- mdbook: page file="bigfloat/decimal-conversion.md" -->
### Decimal Conversion (BigFloat)

Every binary float is exactly a decimal, because `2^-k` is `5^k / 10^k`, so
the conversion out loses nothing and only the number of digits is a choice:

```mojo
var tenth = BigFloat.from_float64(0.1)
print(tenth.to_bigdecimal())            # all 55 digits of the double
print(tenth.to_bigdecimal_rounded(17))  # 0.10000000000000001
print(tenth)                            # as many digits as 53 bits are worth
print(tenth.internal_representation())  # the significand, exponent, precision
```

A digit count costs what the digits cost. The digits asked for are taken by
scaling the value by a power of ten, so a deep exponent is no longer a reason
to wait: a value whose exact expansion runs to 301,031 digits still gives
twenty of them at once, and the smallest and largest values a `BigFloat` can
hold print like any other.

```mojo
var deep = BigFloat.power_of_two(-1000000)
print(deep.to_string(20))               # 1.0100340591980302247E-301030
```

`to_bigdecimal()` is the one to ask when every digit is wanted, and it is the
only one whose cost follows the exponent, because the answer does.

Coming in costs what the precision is, in the same way and for the same
reason. A decimal exponent of nine or eighteen figures is a decimal nobody
could write out, and it parses at once:

```mojo
var deep = BigFloat.from_string("1.5e-1000000", 53)
print(deep.to_string(17))                   # 1.5000000000000000E-1000000
print(BigFloat.from_string("7e1000000000", 53).to_string(17))
# 6.9999999999999999E+1000000000
```

The second one is seven to a billion powers of ten, which has no exact
rendering in 53 bits — the digits shown are the float's own.

Going the other way rounds. `to_float64()` is exact for a normal double but
rounds a second time when the answer is subnormal, since a subnormal has fewer
bits than 53: converting from a wider precision avoids it.

<!-- mdbook: page file="bigfloat/choosing.md" -->
### BigFloat, Decimal, or MPF

Use `Decimal` when the arithmetic has to be decimal — money, anything whose
digits are the point, anything that has to agree with Python's
`decimal.Decimal`. Use `BigFloat` for scientific computation at a chosen
precision, where binary is the natural base and the question is whether the
last bit is right.

`MPF`, the MPFR-backed float that used to carry the name `BigFloat`, is still
in the source at `decimo.mpf.mpf.MPF`. It is not exported and carries no
promise of a stable interface, and using it means installing MPFR and linking
a C wrapper. It is kept as a second implementation to test the traits against,
as the baseline the Mojo one is measured against, and for anyone who was
relying on it.

<!-- mdbook: page file="rational/index.md" -->
## Part IV — Rational (`Frac`)

An exact fraction of two arbitrary-precision integers. Nothing is ever
rounded: a third is a third, and a third times three is one.

`Rational` is not in the prelude, which carries the four types most programs
reach for. Import it by name, as itself or under the short name `Frac`:

```mojo
from decimo import Frac, Rational
```

The value is always in lowest terms with a positive denominator, so two equal
values have the same two parts and `==` is a comparison of integers rather
than of fractions. The two parts are the fields `numerator` and `denominator`:

```mojo
var r = Rational(6, -8)
print(r.numerator, r.denominator)   # -3 4
```

<!-- mdbook: page file="rational/construction.md" -->
### Construction (Rational)

```mojo
from decimo import Rational

print(Rational(3, 4))                      # 3/4
print(Rational(BigInt(6), BigInt(8)))      # 3/4, reduced on the way in
print(Rational("22/7"))                    # 22/7
print(Rational("0.25"))                    # 1/4, a decimal literal
print(Rational.from_float_scalar(0.1))     # 3602879701896397/36028797018963968
```

The float constructor is exact and that is the point of it: a double holding
"0.1" is not a tenth, and this is the fraction it really holds. Use
`Rational("0.1")` for the tenth.

<!-- mdbook: page file="rational/arithmetic.md" -->
### Arithmetic (Rational)

The four operations, the comparisons and the in-place forms are all exact.
Multiplication and division reduce across the two fractions before
multiplying, so the intermediates stay near the size of the answer rather
than growing to the product of the denominators.

```mojo
from decimo import Rational

print(Rational(1, 2) + Rational(1, 3))     # 5/6
print(Rational(1, 2) / Rational(1, 3))     # 3/2
print(Rational(1, 3) < Rational(1, 2))     # True

var x = Rational(1, 2)
x += Rational(1, 3)                        # 5/6
x **= 3                                    # 125/216
```

A power takes a whole exponent, which may be negative:

```mojo
print(Rational(3, 2) ** 7)                 # 2187/128
print(Rational(3, 2) ** -2)                # 4/9
```

A fractional exponent is not accepted. Python's `Fraction` answers one with a
float, which throws away the exactness the type exists for; ask `BigFloat`
for that answer instead, where the precision is yours to choose.

<!-- mdbook: page file="rational/rounding.md" -->
### Rounding (Rational)

The four roundings all return a `Rational` with a denominator of one, and the
standard library's functions take this type:

```mojo
from decimo import Rational

from std.math import ceil, floor, trunc

var half_down = Rational(-7, 2)
print(floor(half_down))                    # -4
print(ceil(half_down))                     # -3
print(trunc(half_down))                    # -3, toward zero
print(round(half_down))                    # -4
print(round(Rational(5, 2)))               # 2, halves go to the even side
print(round(Rational(1, 8), 2))            # 3/25, which is 0.12
```

`round(x, n)` takes a negative `n` to round above the decimal point, as
Python's does: `round(Rational(1350), -2)` is 1400.

<!-- mdbook: page file="rational/closest-fraction.md" -->
### Closest Fraction (Rational)

`limit_denominator` answers the closest fraction whose denominator is at most
the limit, which is how a long exact value becomes a short readable one:

```mojo
from decimo import Rational

var pi_ish = Rational(BigInt(31415926535), BigInt(10000000000))
print(pi_ish.limit_denominator(BigInt(10)))     # 22/7
print(pi_ish.limit_denominator(BigInt(1000)))   # 355/113
```

It walks the continued fraction of the value, so the work is proportional to
the length of that walk and not to the size of the denominator it starts
from. Where two fractions are equally close it returns the same one Python's
`Fraction` does, which is not always the one with the smaller denominator.

<!-- mdbook: page file="rational/conversions.md" -->
### Conversions (Rational)

```mojo
from decimo import Rational

print(Rational(1, 3).to_float())           # 0.3333333333333333
print(Rational(1, 3).to_bigdecimal(20))    # 0.33333333333333333333
print(Rational(-7, 2).to_integer())        # -3, truncated toward zero
print(Rational(-7, 2).reciprocal())        # -2/7
```

`to_bigdecimal` takes the digits to keep, because a third has no decimal
expansion that ends. Everything else here is exact.

<!-- mdbook: page file="decimal128/index.md" -->
## Part V — Decimal128 (`Dec128`)

A decimal of fixed size, like `System.Decimal` in C# and .NET. It fits in 128
bits and holds up to 29 digits, with 0 to 28 of them after the point. It never
uses the heap, so it is fast and cheap to copy.

| Property        | Value                                                    |
| --------------- | -------------------------------------------------------- |
| Name            | `Decimal128`                                             |
| Alias           | `Dec128`                                                 |
| Value           | `(-1)^sign * coefficient * 10^(-scale)`                  |
| Coefficient     | 96 bits, from 0 to `2^96 - 1`                            |
| Scale           | 0 to 28 (`Dec128.MAX_SCALE`)                             |
| Digits          | Up to 29 (`Dec128.MAX_NUM_DIGITS`)                       |
| Largest value   | `Dec128.MAX()`, which is `79228162514264337593543950335` |
| Smallest step   | `1E-28`                                                  |
| Special values  | None: no NaN and no infinity, but `-0` is kept           |
| Rounding        | Half to even, the only mode for arithmetic and functions |
| Memory          | 16 bytes, no heap                                        |
| .NET equivalent | `System.Decimal`                                         |

The scale is the number of digits after the point, and a value keeps it:
`Dec128("1.50")` prints as `1.50` and is equal to `Dec128("1.5")`.

```mojo
var price = Dec128("19.99")
print(price * Dec128(3))                # 59.97
print(Dec128.MAX())                     # 79228162514264337593543950335
print(Dec128.MIN())                     # -79228162514264337593543950335
```

#### Decimal128 or Decimal <!-- omit from toc -->

Both are decimal types, so `0.1 + 0.2` is `0.3` in both. The difference is
size.

|                        | `Decimal128`                    | `Decimal`                     |
| ---------------------- | ------------------------------- | ----------------------------- |
| Digits                 | Up to 29                        | Any number                    |
| Digits after the point | 0 to 28                         | Any number                    |
| A result too large     | Raises `OverflowError`          | Grows                         |
| A result below `1E-28` | Rounds to zero                  | Kept                          |
| Arithmetic rounds to   | 29 digits, at most 28 after `.` | 28 significant digits         |
| Precision              | Fixed                           | Can be chosen                 |
| Functions              | Roots, powers, exp, log, trig   | Also inverse trig, hyperbolic |
| Memory                 | 16 bytes, no heap               | Grows on the heap             |

Choose `Dec128` for money, prices, rates and quantities that fit in 29 digits,
when speed and a fixed size matter. It also matches .NET `System.Decimal`, and
it reads and writes the IEEE 754 decimal128 bytes that BSON stores.

Choose `Decimal` when a value can have more than 29 digits, when you need a
precision of your choice, a function that `Dec128` lacks, or results that
match Python's `decimal` digit for digit.

```mojo
print(Dec128(100) / Dec128(3))          # 33.333333333333333333333333333
print(Decimal(100) / Decimal(3))        # 33.33333333333333333333333333
```

`Dec128` fills its 29 digits; `Decimal` rounds to 28 significant digits.

`Dec128` is in the prelude. Its traits are listed in
[Appendix B](#appendix-b--traits-implemented).

<!-- mdbook: page file="decimal128/construction.md" -->
### Construction (Decimal128)

A `Dec128` can be built from an `Int`, an integer literal, a `String`, a float,
any integer scalar, or its raw parts.

| Constructor                                    | Example                                      | Result                 |
| ---------------------------------------------- | -------------------------------------------- | ---------------------- |
| `Dec128()`                                     | `Dec128()`                                   | `0`                    |
| `Dec128(n)`                                    | `Dec128(-42)`                                | `-42`                  |
| `Dec128(n, scale)`                             | `Dec128(12345, 2)`                           | `123.45`               |
| `Dec128(s)`, `Dec128.from_string(s)`           | `Dec128("1.50")`                             | `1.50`                 |
| `Dec128(f)`                                    | `Dec128(2.5)`                                | `2.5`                  |
| `Dec128.from_int(n, scale)`                    | `Dec128.from_int(-5, 3)`                     | `-0.005`               |
| `Dec128.from_integral_scalar(v)`               | `Dec128.from_integral_scalar(UInt64.MAX)`    | `18446744073709551615` |
| `Dec128.from_float_scalar(v)`                  | `Dec128.from_float_scalar(Float32(0.5))`     | `0.5`                  |
| `Dec128.from_uint128(c, scale, sign)`          | `Dec128.from_uint128(314, 2)`                | `3.14`                 |
| `Dec128.from_components(l, m, h, scale, sign)` | `Dec128.from_components(150, 0, 0, 2, True)` | `-1.50`                |
| `Dec128.from_words(l, m, h, flags)`            | `Dec128.from_words(150, 0, 0, 0x80020000)`   | `-1.50`                |
| `Dec128.from_decimal(d)`                       | `Dec128.from_decimal(Decimal("2.5"))`        | `2.5`                  |
| `Dec128.from_ieee754(bits)`                    | See [IEEE 754](#ieee-754-decimal128-bytes)   |                        |

The constants are static methods: `Dec128.ZERO()`, `ONE()`, `MAX()`, `MIN()`,
`PI()` and `E()`. `zero()` and `one()` are the same values for generic code.

#### From `Int` <!-- omit from toc -->

```mojo
var a = Dec128(42)
var b = Dec128(12345, 2)                # 123.45: the second number is the scale
var c = Dec128("1.23") + 1              # 2.23: an Int converts implicitly
```

The scale must be from 0 to 28. `Dec128(1, 29)` raises.

The constructors wrap any error in a `ConversionError`; its cause names the
problem, such as an `OverflowError`.

An integer scalar other than `Int`, such as `Int64` or `UInt128`, goes through
`from_integral_scalar()`. It raises `OverflowError` above `Dec128.MAX()`,
which only 128-bit and 256-bit scalars can reach. *To be in v0.17.0:* <!-- [forthcoming] -->
`Dec128(Int64(-5))` does the same.

#### From an integer literal <!-- omit from toc -->

```mojo
var a: Dec128 = 123
var b: Dec128 = -79228162514264337593543950335   # Dec128.MIN()
```

*To be in v0.17.0:* <!-- [forthcoming] --> a literal wider than `Int` works
directly, up to `Dec128.MAX()` (v0.16.0 silently gets it wrong). A literal
beyond that is a compile-time error, which suggests `BigDecimal` instead:

```text
var c: Dec128 = 79228162514264337593543950336
# error: the literal is beyond what a Decimal128 can hold; use a BigDecimal instead
```

#### From `String` <!-- omit from toc -->

```mojo
print(Dec128("123.4500"))               # 123.4500, the scale is kept
print(Dec128("-1.5E-3"))                # -0.0015
print(Dec128("1.5e3"))                  # 1500
print(Dec128("1_000_000.50"))           # 1000000.50
print(Dec128("0.12345678901234567890123456789"))  # 0.1234567890123456789012345679
print(Dec128("1E-30"))                  # 0.0000000000000000000000000000
```

The text may have digits, one `.`, a sign in front, and an exponent after `e`
or `E`. Spaces, `,` and `_` are ignored.

- More than 28 digits after the point are rounded, half to even.
- A value below `1E-28` rounds to zero; it does not raise.
- An integer part beyond `Dec128.MAX()` raises `OverflowError`.
- An empty string, or one with no digits such as `"."`, raises `ValueError`.

#### From a float <!-- omit from toc -->

```mojo
print(Dec128(2.5))                                  # 2.5
print(Dec128(0.1))                                  # 0.1
print(Dec128.from_float_scalar(Float32(0.1)))       # 0.100000001490116119384765625
```

This conversion is not exact. The float `0.1` really holds
`0.1000000000000000055511151231...`, but `Dec128(0.1)` gives `0.1`: the digits
after the point are worked out in floating point, and they stop where that
runs out. Do not trust more than 15 digits. (`Decimal.from_float_scalar()` is
exact.) For an exact value, write a string.

Infinity, NaN and a float of `2^96` or more raise an error.

#### From raw parts <!-- omit from toc -->

A `Dec128` is four `UInt32` words. `low`, `mid` and `high` hold the 96-bit
coefficient, low word first. `flags` holds the scale in bits 16 to 23 and the
sign in bit 31; the other bits must be zero.

```mojo
var x = Dec128.from_words(150, 0, 0, 0x80020000)
print(x)                                # -1.50
print(x.low, x.mid, x.high, hex(x.flags))   # 150 0 0 0x80020000
print(Dec128.from_components(0, 0, 1, 0, False))  # 18446744073709551616, 2^64
```

`from_words()` checks the flags and raises `ValueError` on a bad bit or a scale
above 28. `from_components()` takes the scale and the sign as separate
arguments. The four-word constructor `Dec128(low, mid, high, flags)` checks
nothing in a release build; use `from_words()` for data from outside.

<!-- mdbook: page file="decimal128/arithmetic.md" -->
### Arithmetic and Rounding (Decimal128)

| Operation                           | Result                               |
| ----------------------------------- | ------------------------------------ |
| `x + y`, `x - y`, `x * y`           | Sum, difference, product             |
| `x / y`                             | Quotient                             |
| `x // y`                            | Quotient truncated toward zero       |
| `x % y`                             | Remainder, with the sign of `x`      |
| `x.__divmod__(y)`                   | `(x // y, x % y)` in one call        |
| `x ** n`, `x.power(n)`              | Power; `n` is an `Int` or a `Dec128` |
| `-x`, `+x`, `abs(x)`                | Negation, copy, absolute value       |
| `+=`, `-=`, `*=`, `/=`, `//=`, `%=` | In-place forms                       |
| `==`, `!=`, `<`, `<=`, `>`, `>=`    | Compare by value: `1.0 == 1.00`      |
| `x.max(y)`, `x.min(y)`              | The larger or the smaller            |
| `x.clamp(lower, upper)`             | `x` limited to `[lower, upper]`      |
| `x.fma(y, z)`                       | `x * y + z`, rounded once            |

```mojo
var a = Dec128("123456789.123456789")
var b = Dec128("1234.56789")
print(a + b)                            # 123458023.691346789
print(a * b)                            # 152415787654.32099750190521
print(Dec128(7) // Dec128(2), Dec128(-7) // Dec128(2))   # 3 -3
print(Dec128(7) % Dec128(2), Dec128(-7) % Dec128(2))     # 1 -1
print(Dec128("1.0") == Dec128("1.00"))  # True
```

`//` and `%` work as in Python's `decimal`, not as for Python's `int`. The
builtin `divmod()` does not take a `Dec128`; call `x.__divmod__(y)`.

#### How results round <!-- omit from toc -->

The scale of a result follows the same rules as `Decimal`; see
[Result exponents](#result-exponents-decimal-and-dec128). When the exact
result does not fit, digits after the point are dropped until it has at most
29 digits and at most 28 after the point. The rest is rounded half to even.
Operators have no other rounding mode.

```mojo
print(Dec128(2) / Dec128(3))            # 0.6666666666666666666666666667
print(Dec128(100) / Dec128(3))          # 33.333333333333333333333333333
print(Dec128("1E-28") / Dec128(2))      # 0.0000000000000000000000000000
```

The last result is half of `1E-28`, which rounds to the even side, zero. A
result below the smallest step becomes zero without an error.

`fma` rounds once where `x * y + z` rounds twice, so it can keep one more
digit:

```mojo
var pi = Dec128("3.141592653589793238462643383")
print(pi.fma(pi, Dec128("-9.8")))       # 0.0696044010893586188344909981
print(pi * pi + Dec128("-9.8"))         # 0.069604401089358618834490998
```

#### Overflow <!-- omit from toc -->

There is no infinity. When the integer part of a result does not fit, the
operation raises `OverflowError`:

```mojo
try:
    print(Dec128.MAX() + Dec128(1))
except e:
    print("OverflowError")              # this branch runs
print(Dec128.MAX() + Dec128("0.4"))     # 79228162514264337593543950335
```

The second sum is exact as `...335.4`, which rounds back to `Dec128.MAX()`.

#### Rounding <!-- omit from toc -->

`round(ndigits, rounding_mode)` rounds to `ndigits` places after the point,
half to even by default. A negative `ndigits` rounds to the left of the point.
It takes all seven modes of [RoundingMode](#roundingmode).

```mojo
var x = Dec128("123.456")
print(x.round(2))                       # 123.46
print(x.round(-1))                      # 120
print(x.round(2, ROUND_DOWN))           # 123.45
print(x.round(5))                       # 123.45600
print(round(x, 2))                      # 123.46
print(round(Dec128("2.5")))             # 2, halves go to the even side
```

A `round()` that would need more than 29 digits raises `OverflowError`. The
builtin `round(x, n)` does not raise: it returns `x` unchanged instead.

`quantize(exp)` rounds to the scale of `exp`; the value of `exp` does not
matter. `normalize()` removes trailing zeros.

```mojo
print(Dec128("19.999").quantize(Dec128("0.01")))   # 20.00
print(Dec128("1.2345").quantize(Dec128("0.01"), ROUND_UP))   # 1.24
print(Dec128("1.2345000").normalize())  # 1.2345
```

The integer part, the fraction and the sign are methods too:

```mojo
var y = Dec128("-3.75")
print(y.trunc(), y.floor(), y.ceil())   # -3 -4 -3
print(y.fract())                        # -0.75
print(y.signum())                       # -1
```

The standard library's `floor()`, `ceil()` and `trunc()` do not take a
`Dec128`; use these methods.

<!-- mdbook: page file="decimal128/math.md" -->
### Mathematical Functions (Decimal128)

The functions are methods. Each one works with extra digits inside and rounds
once at the end, half to even. When the extra digits cannot decide the last
digit, it runs again with more. There is no precision argument: the result
always has up to 29 digits and up to 28 after the point.

| Method                      | Computes                   | Raises when                                         |
| --------------------------- | -------------------------- | --------------------------------------------------- |
| `x.sqrt()`                  | Square root                | `x < 0`                                             |
| `x.cbrt()`                  | Cube root                  | —                                                   |
| `x.root(n)`                 | `n`-th root                | `n <= 0`, or `n` is even and `x < 0`                |
| `x.power(e)`, `x ** e`      | `x` to the power `e`       | `x < 0` and `e` has a fraction, `x = 0` and `e < 0` |
| `x.exp()`                   | `e` to the power `x`       | `x` above about 66.54                               |
| `x.ln()`                    | Natural logarithm          | `x <= 0`                                            |
| `x.log10()`                 | Base-10 logarithm          | `x <= 0`                                            |
| `x.log(base)`               | Logarithm in `base`        | `x <= 0`, `base <= 0` or `base = 1`                 |
| `x.sin()`, `x.cos()`        | Sine, cosine (radians)     | —                                                   |
| `x.tan()`, `x.sec()`        | Tangent, secant            | Very near `pi/2 + k * pi`, if the result is too big |
| `x.cot()`, `x.csc()`        | Cotangent, cosecant        | `x = 0`, or very near `k * pi`                      |
| `Dec128.PI()`, `Dec128.E()` | `pi` and `e`, 28 places    | —                                                   |
| `factorial(n)`              | `n!`, for `n` from 0 to 27 | `n < 0` or `n > 27`                                 |

Any function also raises `OverflowError` when its result is above
`Dec128.MAX()`.

`factorial` is a function, not a method. Import it with
`from decimo.decimal128.special import factorial`.

```mojo
print(Dec128(2).sqrt())                 # 1.4142135623730950488016887242
print(Dec128(-8).cbrt())                # -2
print(Dec128(2).root(5))                # 1.1486983549970350067986269468
print(Dec128(2) ** 10)                  # 1024
print(Dec128(2) ** Dec128("0.5"))       # 1.4142135623730950488016887242
print(Dec128(1).exp())                  # 2.7182818284590452353602874714
print(Dec128(10).ln())                  # 2.3025850929940456840179914547
print(Dec128(8).log(Dec128(2)))         # 3
print(Dec128(1).sin())                  # 0.8414709848078965066525023216
print(Dec128("1E20").sin())             # -0.6452512852657808442058117113
```

A large angle is reduced with enough digits of `pi`, so `sin(1E20)` is right
to the last digit.

#### What it lacks <!-- omit from toc -->

`Dec128` has no inverse trigonometric functions (`arcsin`, `arccos`, `arctan`,
`arctan2`), no hyperbolic functions or their inverses, and no `expm1`,
`log1p` or `hypot`. `Decimal` has all of them. Convert, compute, and convert
back:

```mojo
var x = Dec128("0.5")
var y = Dec128.from_decimal(Decimal(String(x)).arctan(precision=40))
print(y)                                # 0.4636476090008061162142562315
```

<!-- mdbook: page file="decimal128/conversion.md" -->
### Conversion and Queries (Decimal128)

#### To a string <!-- omit from toc -->

`Dec128` always prints in plain notation, never as `1E-7`. See
[Conversion and Output (Decimal)](#conversion-and-output-decimal) for how
this differs from `Decimal`.

```mojo
var x = Dec128("12345.678")
print(x)                                # 12345.678
print(x.to_string(scientific=True))     # 1.2345678E+4
print(x.to_string(engineering=True))    # 12.345678E+3
print(x.to_string(delimiter="_"))       # 12_345.678
print(repr(Dec128("1.50")))             # Decimal128("1.50")
```

`to_scientific_string()`, `to_eng_string()` and
`to_string_with_separators("_")` are short forms of the three calls above.

#### To numbers <!-- omit from toc -->

```mojo
var x = Dec128("-123.99")
print(Int(x))                           # -123, toward zero
print(x.to_int64())                     # -123
print(x.to_int128())                    # -123
print(x.to_uint128())                   # 123, the integer part of abs(x)
print(Float64(x))                       # -123.99
print(Dec128.MAX().to_int128())         # 79228162514264337593543950335
```

`Int(x)`, `to_int()` and `to_int64()` drop the fraction and raise when the
result does not fit in 64 bits. This is unlike `Decimal`, where `Int()` raises
on a fraction. `to_int128()` and `to_uint128()` never raise, since every
`Dec128` fits. `Float64(x)` never raises, but it may lose digits.

#### To and from `Decimal` <!-- omit from toc -->

```mojo
var d = Decimal(String(Dec128("1.50")))
print(d)                                # 1.50
var e = Dec128.from_decimal(Decimal("3.14159265358979323846264338327950288"))
print(e)                                # 3.1415926535897932384626433833
```

`from_decimal()` rounds half to even to 29 digits, at most 28 after the point. It raises
`OverflowError` when the integer part does not fit.

#### Raw parts <!-- omit from toc -->

```mojo
var x = Dec128("-1.50")
print(x.coefficient(), x.scale(), x.is_negative())   # 150 2 True
print(x.repr_words())                   # Decimal128(0x96, 0x0, 0x0, 0x80020000)
var y = Dec128.from_words(x.low, x.mid, x.high, x.flags)
print(y)                                # -1.50
```

`as_tuple()` gives `(is_negative, coefficient, scale)` in one call, and
`repr_components()` prints the five parts that `from_components()` takes.

#### IEEE 754 decimal128 bytes <!-- omit from toc -->

`to_ieee754()` writes the value in the IEEE 754 decimal128 interchange format,
binary integer decimal encoding (what BSON and Intel's library use). The
sixteen bytes come back as one `UInt128`. `from_ieee754()` reads them back.
Trailing zeros are kept, so `1.0` and `1` give different bytes.

```mojo
from decimo.ieee754 import decimal128_to_bytes

var bits = Dec128("1.0").to_ieee754()
print(hex(bits))                        # 0x303e000000000000000000000000000a
print(Dec128.from_ieee754(bits))        # 1.0
var bytes = decimal128_to_bytes(bits)   # little-endian by default, as in BSON
print(bytes[0])                         # 10
```

The format holds 34 digits and a far wider exponent, so `from_ieee754()` can
round, ties to even. It raises `OverflowError` for a value above
`Dec128.MAX()` and `ValueError` for an infinity or a NaN. A value below
`1E-28` rounds to zero. `decimal128_from_bytes()` turns sixteen bytes back
into the `UInt128`.

#### Queries <!-- omit from toc -->

| Method                           | Return    | Description                                 |
| -------------------------------- | --------- | ------------------------------------------- |
| `is_zero()`                      | `Bool`    | Zero, of any sign and scale                 |
| `is_negative()`                  | `Bool`    | The sign bit is set, also for `-0`          |
| `is_positive()`                  | `Bool`    | Greater than zero                           |
| `is_integer()`                   | `Bool`    | No fraction: `2.00` is an integer           |
| `is_one()`                       | `Bool`    | Equal to 1, at any scale                    |
| `is_odd()`                       | `Bool`    | The integer part is odd                     |
| `scale()`                        | `Int`     | Digits after the point                      |
| `coefficient()`                  | `UInt128` | The digits as an integer: 150 for `1.50`    |
| `number_of_significant_digits()` | `Int`     | Digits in the coefficient                   |
| `number_of_trailing_zeros()`     | `Int`     | Trailing zeros in the coefficient           |
| `adjusted()`                     | `Int`     | Exponent of the first digit: 2 for `123.45` |
| `same_quantum(y)`                | `Bool`    | Same scale as `y`                           |

```mojo
var x = Dec128("123.4500")
print(x.scale(), x.coefficient())       # 4 1234500
print(x.number_of_significant_digits(), x.number_of_trailing_zeros())  # 7 2
print(x.adjusted(), x.is_integer())     # 2 False
print(Dec128("2.00").is_integer(), Dec128("1.000").is_one())   # True True
```

<!-- mdbook: part title="Tools" -->
<!-- mdbook: skip -->

## Tools

<!-- mdbook: end skip -->

<!-- mdbook: page file="tools/chinese-numerals.md" -->
### Chinese Numerals

Both `BInt` and `Decimal` can write themselves in Chinese numerals with
`to_chinese()`:

```mojo
print(BInt(15).to_chinese())                    # 十五
print(Decimal("1050.07").to_chinese())          # 一千零五十点零七
print(Decimal("-100000001").to_chinese())       # 负一亿零一
```

The conversion works on the decimal *string* of the number rather than on a
particular numeric type, so it is not limited by any integer width. The
string-level entry point is available directly if you need it:

```mojo
from decimo.numerals import decimal_string_to_chinese

print(decimal_string_to_chinese("1050.07"))     # 一千零五十点零七
```

#### Reading rules <!-- omit from toc -->

The integer part is split into sections of eight digits, counted from the
decimal point. Within a section the digits take the 十/百/千 units, and the
upper four take 万. Sections are joined by 亿, which **multiplies everything
read before it** rather than labelling one section:

```mojo
print(BInt("1234567890123").to_chinese())
# 一万二千三百四十五亿六千七百八十九万零一百二十三  (12345亿 + 6789万 + 123)
```

Because 亿 is a multiplier, each further 亿 raises the magnitude by another
10^8 — 亿亿 is 10^16, 亿亿亿 is 10^24 — so arbitrarily large integers are
readable without the rarely-agreed-upon 兆/京/垓 units:

```mojo
print(BInt("10000000000000000").to_chinese())   # 一亿亿
print(BInt("10000000000000005").to_chinese())   # 一亿亿零五
```

Runs of zeros collapse into a single 零, and a leading 一十 is shortened to 十
(`BInt(15)` is 十五, not 一十五). The fractional part is read digit by digit
after 点, zeros included, so the written precision survives the conversion:

```mojo
print(Decimal("1.50").to_chinese())             # 一点五零 (not 一点五)
print(Decimal("2.000").to_chinese())            # 二点零零零
```

#### Styles <!-- omit from toc -->

The character tables are supplied by `ChineseNumeralStyle`, which ships with
four presets:

| Preset                    | Digits | Units  | 10^4 / 10^8 | Point | Example for `1050` |
| ------------------------- | ------ | ------ | ----------- | ----- | ------------------ |
| `simplified()` (default)  | 一二三 | 十百千 | 万 / 亿     | 点    | `一千零五十`       |
| `simplified_financial()`  | 壹贰叁 | 拾佰仟 | 万 / 亿     | 点    | `壹仟零伍拾`       |
| `traditional()`           | 一二三 | 十百千 | 萬 / 億     | 點    | `一千零五十`       |
| `traditional_financial()` | 壹貳參 | 拾佰仟 | 萬 / 億     | 點    | `壹仟零伍拾`       |

```mojo
from decimo import ChineseNumeralStyle

print(Decimal("1050.07").to_chinese(ChineseNumeralStyle.simplified_financial()))
# 壹仟零伍拾点零柒
print(Decimal("1050.07").to_chinese(ChineseNumeralStyle.traditional()))
# 一千零五十點零七
```

The financial (大写) styles keep the leading 一十 rather than shortening it,
since dropping a digit on a cheque would make the amount easier to tamper
with. A custom style can be built from the same constructor if you need a
table the presets do not cover.

#### Digit budget <!-- omit from toc -->

A reading is always written out in full, so its cost is set by the *written*
length of the number, not by how compactly the value was given —
`Decimal("1E+1000000000")` is a few characters of input and a billion digits
of output. Conversions therefore take a `max_digits` budget, defaulting to
`MAX_CHINESE_NUMERAL_DIGITS` (10 000), and raise a `ValueError` past it. The
check happens before the digits are expanded, so an absurd magnitude costs
nothing:

```mojo
_ = Decimal("1E+1000000000").to_chinese()          # raises ValueError
_ = BInt("1" + String("0") * 20000).to_chinese()   # raises ValueError

# Raise or lift the cap when a very long reading really is what you want:
print(Decimal("1E+20000").to_chinese(max_digits=0))
```

<!-- mdbook: page file="tools/expression-engine.md" -->
### Expression Engine

`eval()` takes an arithmetic expression as a string and works it out with
`Decimal` arithmetic. It is the same engine that drives the `decimo` CLI
calculator:

```mojo
from decimo import eval

print(eval("100 + e * pi"))
# 108.53973422267356706546355086954657449503488853577
print(eval("sqrt(2) + 1/3", precision=30))
# 1.74754689570642838213502205754
```

The result is rounded to `precision` significant digits, 50 by default, with
`rounding_mode` (see [RoundingMode](#roundingmode)), half-even by default:

```mojo
print(eval("1/3", precision=20))
# 0.33333333333333333333
print(eval("1/3", precision=5, rounding_mode=ROUND_CEILING))
# 0.33334
```

#### What you can write <!-- omit from toc -->

The operators are `+`, `-`, `*`, `/`, `^` (power), a unary minus or plus,
and parentheses. A unary minus binds looser than `^`, as in Python: `-2^2` is
`-4`. The constants are `pi` and `e`. The functions are `sqrt`, `cbrt`,
`root(x, n)`, `ln`, `log(x, base)`, `log10`, `exp`, `sin`, `cos`, `tan`, `cot`,
`csc`, and `abs`.

Names are case-sensitive: `pi` is the constant, `PI` is an unknown identifier.
(The CLI lower-cases each line before it reaches the engine, which is why `PI`
works there but not here.) Line breaks count as whitespace, so an expression
can span several lines:

```mojo
print(eval("""
    100 + 2 * 3
"""))                                           # 106
```

#### Variables <!-- omit from toc -->

Pass a `Dict` and the expression can refer to your own values. Any identifier
that is not a built-in constant or function is looked up there:

```mojo
from std.collections import Dict

var vars = Dict[String, Decimal]()
vars["x"] = Decimal.from_string("10")
vars["y"] = Decimal.from_string("3")
print(eval("x^2 + y", variables=vars))          # 103
```

#### Errors <!-- omit from toc -->

A syntax error, an unknown name, a division by zero, or a domain error raises,
and the message says where in the expression it went wrong:

```mojo
try:
    _ = eval("1 / 0")
except e:
    print(e)      # Error at position 2: division by zero
```

#### The individual stages <!-- omit from toc -->

`eval()` tokenizes, parses to reverse Polish notation, and evaluates. The three
stages are exported as well, in case you want to look at the tokens or the RPN
form:

```mojo
from decimo.expression import tokenize, parse_to_rpn, evaluate_rpn

var rpn = parse_to_rpn(tokenize("1 + 2 * 3"))
print(evaluate_rpn(rpn^, precision=50))         # 7
```

`evaluate()` is an alias of `eval()`.

<!-- mdbook: part title="Appendices" -->
<!-- mdbook: skip -->

## Appendices

<!-- mdbook: end skip -->

<!-- mdbook: page file="appendix/import-paths.md" -->
### Appendix A — Import Paths

```mojo
# Recommended: import everything commonly needed
from decimo.prelude import *
# Brings in: BigInt, BInt, Decimal, BigDecimal, BDec, Decimal128, Dec128,
#   BigFloat, BFlt, RoundingMode, ROUND_DOWN, ROUND_HALF_UP,
#   ROUND_HALF_DOWN, ROUND_HALF_EVEN, ROUND_UP, ROUND_CEILING, ROUND_FLOOR

# Or import specific types
from decimo import BInt, BigInt
from decimo import Decimal  # also available as BigDecimal or BDec
from decimo import BigFloat, BFlt
from decimo import RoundingMode

# The exact fraction is exported but not in the prelude, which carries the
# four types most programs reach for.
from decimo import Rational

# The MPFR-backed float is in the source but not exported, and carries no
# promise of a stable interface. It also needs its C wrapper linked; see
# `src/decimo/mpf/__init__.mojo`.
from decimo.mpf.mpf import MPF

# Number-theory free functions
from decimo import gcd, lcm, extended_gcd, mod_pow, mod_inverse

# The binary float's own functions live in their modules; the top
# level exports the type and not its functions
from decimo.bigfloat import exp, exp2, exp10, expm1, ln, ln10, log
from decimo.bigfloat import log1p, log2, log10, sqrt
from decimo.bigfloat import power
from decimo.bigfloat import cbrt, root
from decimo.bigfloat import arctan2, hypot
from decimo.bigfloat import ceil, floor, number_class, truncate
from decimo.bigfloat import fma, logb, next_plus, remainder, scaleb
from decimo.bigfloat.trigonometric import cos, sin, tan

# Chinese numerals: the style presets are re-exported at the top level, the
# string-level engine lives in the `decimo.numerals` sub-package
from decimo import ChineseNumeralStyle
from decimo.numerals import (
    decimal_string_to_chinese,
    MAX_CHINESE_NUMERAL_DIGITS,
)

# Expression engine: `eval` at the top level, the individual stages in the
# `decimo.expression` sub-package
from decimo import eval
from decimo.expression import tokenize, parse_to_rpn, evaluate_rpn
```

<!-- mdbook: page file="appendix/traits.md" -->
### Appendix B — Traits Implemented

All of these come from the Mojo standard library except **`Numeric`**, **`Parsable`** and **`Rootable`**, which Decimo defines in `decimo.traits`. `BigInt`, `BigDecimal`, `BigFloat` and `Decimal128` conform to all three, and `Rational` to `Numeric` and `Parsable`. Mojo checks conformance nominally, which is why the traits live in Decimo rather than in the consumer.

`Numeric` gathers `zero()`, `one()`, `-x`, `+`, `-`, `*` and `/`, so a generic routine — a matrix or polynomial library, say — can be written once against `T: Numeric` and run over any of them.

`Parsable` requires the static `from_string(value)`, so the same generic
routine can also fill itself from text. The two are separate because the
capabilities are: the MPFR-backed `MPF`, which is in the source but outside
the public interface, parses but is `Movable` without being `Copyable`, so it
can never be `Numeric`. Ask for `T: Numeric & Parsable` to get both.

`Rootable` requires `sqrt()`, the one operation a Cholesky or QR factorisation needs beyond arithmetic. It is separate for the same reason, and here the evidence is sharper: `BigUInt` has a square root but is unsigned, so it has no `__neg__` and can never be `Numeric` either. Its supertraits are `Deinitable` and `Movable` and no more — `Copyable` is pointedly absent, so that `MPF` can conform. `MPF` and `BigUInt` therefore conform to `Rootable` as well, six types in all. Ask for `T: Numeric & Rootable` in a routine that needs both. What the root means stays the implementing type's business: on an integral type it truncates, so `BigInt("10").sqrt()` is `3`, exactly as `/` truncates there. So does what a negative value does — the four exact types raise, while `BigFloat` and `MPF` return a NaN, as they do for every other function outside their domain.

`Hashable` gives `hash(x)`, and with it a key in a `Dict`. `BigUInt`,
`BigInt`, `BigDecimal`, `BigFloat`, `Rational` and `Decimal128` all conform.
The rule a hash has to keep is that equal values hash alike, and each of
these types holds values that are equal without being written the same way,
so each has something to see through. A decimal drops the trailing zeros it
was written with, which is why `1.0` and `1.00` reach the same entry. A
binary float shifts its significand down to an odd number, which is why a
half at fifty-three bits and a half at five hundred reach the same entry. A
zero is one key whatever sign it carries. The converse is not promised: two
different numbers may land on the same sixty-four bits, as they may under
any hash, and the dictionary settles that with `==`.

Every one of these types also answers `String(x)` and `repr(x)`. Neither
needs a trait of its own here: `String(x)` and `print(x)` come from
`Writable`, and `repr(x)` from the type's own `__repr__`. Mojo 1.2 has no
`Stringable` or `Representable` to ask for, so generic code that wants to
print its argument asks for `Writable`.

#### BigInt <!-- omit from toc -->

| Trait              | What it enables                       |
| ------------------ | ------------------------------------- |
| `Absable`          | `abs(x)`                              |
| `Comparable`       | `<`, `<=`, `>`, `>=`, `==`, `!=`      |
| `Copyable`         | Value-semantic copy                   |
| `Movable`          | Move semantics                        |
| `FloatableRaising` | `Float64(x)`                          |
| `Hashable`         | `hash(x)`, a key in a dictionary      |
| `IntableRaising`   | `Int(x)`                              |
| `Numeric`          | Generic code over Decimo numbers      |
| `Parsable`         | `T.from_string(text)` in generic code |
| `Rootable`         | `x.sqrt()` in generic code            |
| `Writable`         | `print(x)`, `String(x)`               |

#### BigDecimal <!-- omit from toc -->

| Trait              | What it enables                       |
| ------------------ | ------------------------------------- |
| `Absable`          | `abs(x)`                              |
| `Comparable`       | `<`, `<=`, `>`, `>=`, `==`, `!=`      |
| `Copyable`         | Value-semantic copy                   |
| `Movable`          | Move semantics                        |
| `FloatableRaising` | `Float64(x)`                          |
| `Hashable`         | `hash(x)`, a key in a dictionary      |
| `IntableRaising`   | `Int(x)`                              |
| `Numeric`          | Generic code over Decimo numbers      |
| `Parsable`         | `T.from_string(text)` in generic code |
| `Rootable`         | `x.sqrt()` in generic code            |
| `Roundable`        | `round(x)`, `round(x, ndigits)`       |
| `Writable`         | `print(x)`, `String(x)`               |

#### Decimal128 <!-- omit from toc -->

| Trait                     | What it enables                       |
| ------------------------- | ------------------------------------- |
| `Absable`                 | `abs(x)`                              |
| `Boolable`                | `Bool(x)`, `if x`                     |
| `Comparable`              | `<`, `<=`, `>`, `>=`, `==`, `!=`      |
| `Floatable`               | `Float64(x)`, which cannot overflow   |
| `Hashable`                | `hash(x)`, a key in a dictionary      |
| `IntableRaising`          | `Int(x)`                              |
| `Numeric`                 | Generic code over Decimo numbers      |
| `Parsable`                | `T.from_string(text)` in generic code |
| `Rootable`                | `x.sqrt()` in generic code            |
| `Roundable`               | `round(x)`, `round(x, ndigits)`       |
| `TrivialRegisterPassable` | Passed in registers, copied bitwise   |
| `Writable`                | `print(x)`, `String(x)`               |

#### BigFloat <!-- omit from toc -->

| Trait        | What it enables                       |
| ------------ | ------------------------------------- |
| `Absable`    | `abs(x)`                              |
| `Comparable` | `<`, `<=`, `>`, `>=`, `==`, `!=`      |
| `Copyable`   | Value-semantic copy                   |
| `Hashable`   | `hash(x)`, a key in a dictionary      |
| `Movable`    | Move semantics                        |
| `Numeric`    | Generic code over Decimo numbers      |
| `Parsable`   | `T.from_string(text)` in generic code |
| `Rootable`   | `x.sqrt()` in generic code            |
| `Writable`   | `print(x)`, `String(x)`               |

`Parsable` asks for a `from_string(text)` of one argument, and a binary float
has to be told how many bits to keep, so there are two: the one the trait
needs, which lands at the default precision of fifty-three bits, and
`from_string(text, precision, rounding_mode)` for everything else. Generic
code bounded on `T: Parsable` therefore gets a float at a double's precision,
which is the only precision it could have asked for without saying so.

`Comparable` is conformed to with the one reservation IEEE 754 asks for: a
NaN is unordered, so `<`, `<=`, `>`, `>=` and `==` are all False for it and
`!=` is True, which breaks the law that exactly one of less, equal and
greater holds. `compare_total(x, y)`, a function in `decimo.bigfloat.comparison`,
is there for code that needs a total order.

`Numeric` asks for `zero()` and `one()` without arguments, so those two give values of fifty-three bits; `zero(precision, sign)` and `one(precision)` give any other. The operators keep the wider of the two precisions and round half to even, so generic code works at the precision of the values it is handed.

#### Rational <!-- omit from toc -->

| Trait                   | What it enables                       |
| ----------------------- | ------------------------------------- |
| `Absable`               | `abs(x)`                              |
| `Ceilable`, `Floorable` | `ceil(x)`, `floor(x)`                 |
| `Comparable`            | `<`, `<=`, `>`, `>=`, `==`, `!=`      |
| `Copyable`              | Value-semantic copy                   |
| `FloatableRaising`      | `Float64(x)`                          |
| `Hashable`              | `hash(x)`, a key in a dictionary      |
| `IntableRaising`        | `Int(x)`                              |
| `Movable`               | Move semantics                        |
| `Numeric`               | Generic code over Decimo numbers      |
| `Parsable`              | `T.from_string(text)` in generic code |
| `Roundable`             | `round(x)`, `round(x, ndigits)`       |
| `Truncable`             | `trunc(x)`                            |
| `Writable`              | `print(x)`, `String(x)`               |

<!-- mdbook: page file="appendix/api-tables.md" -->
### Appendix C — Complete API Tables

One table per type of the operators and methods. Free functions and longer
explanations are on the pages linked from each table.

#### BigFloat <!-- omit from toc -->

The free functions and their modules are listed in
[Mathematical Functions (BigFloat)](#mathematical-functions-bigfloat) and
[IEEE 754 Functions (BigFloat)](#ieee-754-functions-bigfloat).

| Operator / Method                           | Description                                  |
| ------------------------------------------- | -------------------------------------------- |
| `a + b`, `a - b`                            | At the wider precision, half to even         |
| `a * b`, `a / b`, `a ** b`                  | The same                                     |
| `BigFloat(text)`, `BigFloat(x)`             | At fifty-three bits; a `Float64` is exact    |
| `BigFloat(n)`                               | Exact, at fifty-three bits or more           |
| `BigFloat(v, p, mode)`                      | At `p` bits, in `mode`                       |
| `1 + a`, `2 * a`, `2 ** a`, and the rest    | The literal converts, then as `a + b`        |
| `a += b`, `a -= b`, `a *= b`, `a /= b`      | As `a + b` and the rest                      |
| `a **= b`                                   | As `a ** b`                                  |
| `-a`, `abs(a)`                              | Exact                                        |
| `a == b`, `a < b`, and the rest             | False for a NaN, both zeros equal            |
| `a.sqrt()`                                  | At `a`'s own precision, half to even         |
| `a.fma(b, c, p)`                            | `a * b + c`, the product formed exactly      |
| `a.remainder(b, p)`, `a.fmod(b, p)`         | The two remainders                           |
| `a.next_plus(p)`, `a.next_minus(p)`         | The neighbours                               |
| `a.logb()`, `a.scaleb(n)`                   | The exponent, read and written               |
| `a.truncate()`, `a.floor()`, `a.ceil()`     | Rounded to a whole number                    |
| `a.round_to_integer(mode)`                  | The same in any mode                         |
| `a.number_class()`, `a.is_integer()`        | What kind of value it is                     |
| `a.exp()`, `a.ln()`                         | The same                                     |
| `a.exp2()`, `a.exp10()`                     | The same; a whole exponent is exact          |
| `a.log2()`, `a.log10()`                     | The same; a whole power of the base is exact |
| `a.log(base=b)`                             | At the wider precision, half to even         |
| `a.expm1()`, `a.log1p()`                    | The same; these keep a small argument        |
| `a.sin()`, `a.cos()`, `a.tan()`             | At `a`'s own precision, half to even         |
| `a.cot()`, `a.csc()`, `a.sec()`             | The same                                     |
| `a.arcsin()`, `a.arccos()`, `a.arctan()`    | The same                                     |
| `a.sinh()`, `a.cosh()`, `a.tanh()`          | The same                                     |
| `a.arcsinh()`, `a.arccosh()`, `a.arctanh()` | The same                                     |
| `a.exp(p)`, `a.exp(p, mode)`                | `sqrt`, and `exp` to `arctanh`, at `p` bits  |
| `BigFloat.zero()`, `BigFloat.one()`         | At fifty-three bits                          |
| `a.to_bigdecimal()`                         | The exact decimal expansion                  |
| `a.to_bigdecimal_rounded(n)`                | `n` significant digits                       |
| `a.to_float64()`                            | The nearest double                           |
| `a.internal_representation()`               | The significand, exponent and precision      |

#### BigInt <!-- omit from toc -->

Free functions: see [Number Theory](#number-theory).

| Operator / Method                                 | Accepts              | Raises? | Description                  |
| ------------------------------------------------- | -------------------- | ------- | ---------------------------- |
| `a + b`                                           | `BInt`, `Int`        | No      | Addition                     |
| `a - b`                                           | `BInt`, `Int`        | No      | Subtraction                  |
| `a * b`                                           | `BInt`, `Int`        | No      | Multiplication               |
| `a / b`                                           | `BInt`, `Int`        | Yes     | Truncating division          |
| `a // b`                                          | `BInt`, `Int`        | Yes     | Floor division               |
| `a % b`                                           | `BInt`, `Int`        | Yes     | Floor modulo                 |
| `a ** b`                                          | `BInt`, `Int`        | Yes     | Power                        |
| `a << n`                                          | `Int`                | No      | Left shift                   |
| `a >> n`                                          | `Int`                | No      | Right shift                  |
| `a & b`                                           | `BInt`, `Int`        | No      | Bitwise AND                  |
| `a \| b`                                          | `BInt`, `Int`        | No      | Bitwise OR                   |
| `a ^ b`                                           | `BInt`, `Int`        | No      | Bitwise XOR                  |
| `~a`                                              | —                    | No      | Bitwise NOT                  |
| `-a`                                              | —                    | No      | Negation                     |
| `abs(a)`                                          | —                    | No      | Absolute value               |
| `a.sqrt()`                                        | —                    | Yes     | Integer square root          |
| `a.gcd(b)`                                        | `BInt`               | Yes     | GCD                          |
| `a.lcm(b)`                                        | `BInt`               | Yes     | LCM                          |
| `a.extended_gcd(b)`                               | `BInt`               | Yes     | Extended GCD                 |
| `a.mod_pow(e, m)`                                 | `BInt`/`Int`, `BInt` | Yes     | Modular exponentiation       |
| `a.mod_inverse(m)`                                | `BInt`               | Yes     | Modular inverse              |
| `a.__divmod__(b)`                                 | `BInt`               | Yes     | Floor quotient and remainder |
| `a.truncate_divide(b)`, `a.truncate_modulo(b)`    | `BInt`               | Yes     | Division toward zero         |
| `a.floor_modulo(b)`                               | `BInt`               | Yes     | Same as `%`                  |
| `a.ceil_divide(b)`                                | `BInt`               | Yes     | Quotient rounded up          |
| `a.sqrt_rem()`                                    | —                    | Yes     | Root and remainder           |
| `a.is_perfect_square()`                           | —                    | Yes     | Whether a square             |
| `a.perfect_power()`                               | —                    | Yes     | `(base, exponent)`           |
| `a.factorial()`, `a.double_factorial()`           | —                    | Yes     | `n!`, `n!!`                  |
| `a.binomial(k)`, `a.permutation(k)`               | `Int`                | Yes     | Choices of `k`               |
| `a.fibonacci()`, `a.lucas()`                      | —                    | Yes     | The `n`th number             |
| `a.test_bit(i)`                                   | `Int`                | Yes     | Whether bit `i` is set       |
| `a.set_bit(i)`, `a.clear_bit(i)`, `a.flip_bit(i)` | `Int`                | Yes     | A copy with bit `i` changed  |
| `a.bit_count()`                                   | —                    | No      | Number of set bits           |
| `a.trailing_zeros()`                              | —                    | No      | Zero bits at the low end     |

#### Decimal <!-- omit from toc -->

The precision is in significant digits, 28 by default. Most functions also
take a `rounding_mode`, half to even by default.

| Function                        | Signature                           | Description                    |
| ------------------------------- | ----------------------------------- | ------------------------------ |
| `sqrt`, `cbrt`                  | `x.sqrt(precision=28)`              | Square and cube root           |
| `root`                          | `x.root(n, precision)`              | `n`th root                     |
| `power`                         | `x.power(exponent=e, precision=28)` | Power                          |
| `exp`, `expm1`                  | `x.exp(precision=28)`               | `e**x`, and `e**x - 1`         |
| `ln`, `log1p`                   | `x.ln(precision=28)`                | Natural log, and `ln(1 + x)`   |
| `log`                           | `x.log(base=b, precision=28)`       | Logarithm in any base          |
| `log10`                         | `x.log10(precision=28)`             | Base-10 logarithm              |
| `sin`, `cos`, `tan`             | `x.sin(precision=28)`               | In radians                     |
| `cot`, `csc`, `sec`             | `x.cot(precision=28)`               | In radians                     |
| `arcsin`, `arccos`, `arctan`    | `x.arcsin(precision=28)`            | In radians                     |
| `arctan2`                       | `y.arctan2(other=x, precision=28)`  | Angle of the point `(x, y)`    |
| `hypot`                         | `x.hypot(other=y, precision=28)`    | `sqrt(x*x + y*y)`              |
| `sinh`, `cosh`, `tanh`          | `x.sinh(precision=28)`              | Hyperbolic functions           |
| `arcsinh`, `arccosh`, `arctanh` | `x.arcsinh(precision=28)`           | Their inverses                 |
| `factorial`                     | `x.factorial(precision=0)`          | Exact unless a precision given |
| `pi`, `e`                       | `Decimal.pi(precision)`             | The constants                  |

#### Rational <!-- omit from toc -->

| Operator / Method                  | Description                                   |
| ---------------------------------- | --------------------------------------------- |
| `a + b`, `a - b`, `a * b`, `a / b` | Exact, and the in-place forms                 |
| `a ** n`                           | Exact, for an `Int` or `BigInt` exponent      |
| `-a`, `abs(a)`                     | Exact                                         |
| `a == b`, `a < b`, and the rest    | Exact comparison                              |
| `floor(a)`, `ceil(a)`, `trunc(a)`  | Rounded to a whole number                     |
| `round(a)`, `round(a, n)`          | Half to even, to a whole number or `n` places |
| `a.numerator`, `a.denominator`     | The two parts, in lowest terms                |
| `a.reciprocal()`                   | `1 / a`                                       |
| `a.limit_denominator(n)`           | The closest fraction with denominator `<= n`  |
| `a.is_integer()`, `a.is_zero()`    | What kind of value it is                      |
| `a.sign()`                         | `-1`, `0` or `1`                              |
| `a.to_integer()`, `a.to_int()`     | Truncated toward zero                         |
| `a.to_float()`                     | The nearest double                            |
| `a.to_bigdecimal(precision)`       | A `Decimal`, rounded once                     |
