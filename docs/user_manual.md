# Decimo — User Manual <!-- omit from toc -->

> Comprehensive guide to using the Decimo arbitrary-precision arithmetic library
> in Mojo.

All code examples below assume that you have imported the prelude at the top of
your Mojo file:

```mojo
from decimo.prelude import *
```

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Part I — BigInt (`BInt`)](#part-i--bigint-bint)
  - [Overview](#overview)
  - [Construction](#construction)
  - [Arithmetic Operations](#arithmetic-operations)
  - [Division Semantics](#division-semantics)
  - [Comparison](#comparison)
  - [Bitwise Operations](#bitwise-operations)
  - [Shift Operations](#shift-operations)
  - [Mathematical Functions](#mathematical-functions)
  - [Number Theory](#number-theory)
  - [Conversion and Output](#conversion-and-output)
  - [Query Methods](#query-methods)
  - [Constants and Factory Methods](#constants-and-factory-methods)
- [Part II — Decimal](#part-ii--decimal)
  - [Overview — Decimal](#overview--decimal)
  - [How Precision Works](#how-precision-works)
  - [Construction — Decimal](#construction--decimal)
  - [Decimal Arithmetic](#decimal-arithmetic)
  - [Division Methods](#division-methods)
  - [Decimal Comparison](#decimal-comparison)
  - [Rounding and Formatting](#rounding-and-formatting)
  - [RoundingMode](#roundingmode)
  - [Mathematical Functions — Roots and Powers](#mathematical-functions--roots-and-powers)
  - [Mathematical Functions — Exponential and Logarithmic](#mathematical-functions--exponential-and-logarithmic)
  - [Mathematical Functions — Trigonometric](#mathematical-functions--trigonometric)
  - [Mathematical Constants](#mathematical-constants)
  - [Decimal Conversion and Output](#decimal-conversion-and-output)
  - [Decimal Query Methods](#decimal-query-methods)
  - [Python Interoperability](#python-interoperability)
  - [A note on result exponents (`Decimal` and `Dec128`)](#a-note-on-result-exponents-decimal-and-dec128)
  - [Chinese Numerals](#chinese-numerals)
  - [Expression Engine](#expression-engine)
  - [Appendix A — Import Paths](#appendix-a--import-paths)
  - [Appendix B — Traits Implemented](#appendix-b--traits-implemented)
  - [Appendix C — Complete API Tables](#appendix-c--complete-api-tables)

## Installation

Decimo is available in the
[modular-community](https://repo.prefix.dev/modular-community) package
repository. Add it to your `channels` list in `pixi.toml`:

```toml
channels = ["https://conda.modular.com/max", "https://repo.prefix.dev/modular-community", "conda-forge"]
```

Then install:

```bash
pixi add decimo
```

Or add it manually to `pixi.toml`:

```toml
decimo = "==0.13.0"
```

Then run `pixi install`.

## Quick Start

```mojo
from decimo.prelude import *


def main() raises:
    # Arbitrary-precision integer
    var a = BInt("12345678901234567890")
    var b = BInt(42)
    print(a * b)          # 518518513851851851180
    print(BInt(2) ** 256)  # 2^256, all 78 digits

    # Arbitrary-precision decimal
    var x = Decimal("123456789.123456789")
    var y = Decimal("1234.56789")
    print(x + y)                          # 123458023.691346789 (exact)
    print(x.true_divide(y, precision=50)) # 50 significant digits
    print(x.sqrt(precision=100))          # 100 significant digits
    print(Decimal.pi(precision=1000))     # 1000 digits of π
```

## Part I — BigInt (`BInt`)

### Overview

`BigInt` (aliases `BInt`, `Integer`) is an arbitrary-precision signed integer
type — the Mojo-native equivalent of Python's `int`. It supports
unlimited-precision integer arithmetic, bitwise operations, and number-theoretic
functions.

| Property          | Value                        |
| ----------------- | ---------------------------- |
| Full name         | `BigInt`                     |
| Aliases           | `BInt`, `Integer`            |
| Internal base     | 2^32 (binary representation) |
| Word type         | `UInt32` (little-endian)     |
| Python equivalent | `int`                        |

### Construction

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

#### From `String` <!-- omit from toc -->

```mojo
var a = BInt("12345678901234567890")  # Basic decimal string
var b = BInt("-98765")                 # Negative number
var c = BInt("1_000_000")             # Underscores as separators
var d = BInt("1,234,567")             # Commas as separators
var e = BInt("1.23e5")                # Scientific notation (= 123000)
var f = BInt("1991_10,18")            # Mixed separators (= 19911018)
```

> **Note:** The string must represent an integer. `BInt("1.5")` raises an error.
> Scientific notation like `"1.23e5"` is accepted only if the result is an
> integer.

#### From `Scalar` (any integral SIMD type) <!-- omit from toc -->

```mojo
var x = BInt(UInt32(42))
var y = BInt(Int64(-5))
var z: BInt = UInt32(99)     # Implicit conversion
```

Accepts any integral scalar type (`Int8` through `Int256`, `UInt8` through
`UInt256`, etc.).

#### Summary of constructors <!-- omit from toc -->

| Constructor                        | Description                           |
| ---------------------------------- | ------------------------------------- |
| `BInt()`                           | Zero                                  |
| `BInt(value: String)`              | From decimal string (raises)          |
| `BInt(value: Scalar)`              | From any integral scalar (implicit)   |
| `BInt.from_integral_scalar(value)` | From any integral scalar type         |
| `BInt.from_string(value)`          | Explicit factory from string (raises) |
| `BInt.from_biguint(value, sign)`   | From a base-10^9 magnitude and a sign |

#### Unsafe constructors <!-- omit from toc -->

These constructors skip validation for performance-sensitive code. The caller
must ensure the data is valid.

| Constructor                               | Description                               |
| ----------------------------------------- | ----------------------------------------- |
| `BInt(uninitialized_capacity=n)`          | Empty words list with reserved capacity   |
| `BInt(raw_words=List[UInt32], sign=Bool)` | From raw words, no leading-zero stripping |

### Arithmetic Operations

#### Binary operators <!-- omit from toc -->

| Expression    | Description                       | Raises?            |
| ------------- | --------------------------------- | ------------------ |
| `a + b`       | Addition                          | No                 |
| `a - b`       | Subtraction                       | No                 |
| `a * b`       | Multiplication                    | No                 |
| `a / b`       | Truncating division (toward zero) | Yes (zero div)     |
| `a // b`      | Floor division (rounds toward −∞) | Yes (zero div)     |
| `a % b`       | Floor modulo (Python semantics)   | Yes (zero div)     |
| `divmod(a,b)` | Floor quotient and remainder      | Yes (zero div)     |
| `a ** b`      | Exponentiation                    | Yes (negative exp) |

#### Unary operators <!-- omit from toc -->

| Expression | Description                    |
| ---------- | ------------------------------ |
| `-a`       | Negation                       |
| `+a`       | Unary plus (returns copy)      |
| `abs(a)`   | Absolute value                 |
| `bool(a)`  | `True` if nonzero              |
| `~a`       | Bitwise NOT (two's complement) |

#### In-place operators <!-- omit from toc -->

`+=`, `-=`, `*=`, `//=`, `%=`, `<<=`, `>>=` are all supported and perform true
in-place mutation to reduce memory allocation.

```mojo
var a = BInt("12345678901234567890")
var b = BInt(12345)
print(a + b)   # 12345678901234580235
print(a - b)   # 12345678901234555545
print(a * b)   # 152415787814108380241050
print(a // b)  # 999650944609516
print(a % b)   # 9615
print(BInt(2) ** 10)  # 1024
```

### Division Semantics

BigInt supports two division conventions:

| Name              | Operator / Method                               | Quotient    | Python equivalent |
| ----------------- | ----------------------------------------------- | ----------- | ----------------- |
| Floor division    | `//`, `%`, `divmod()`                           | Toward −∞   | `//`, `%`         |
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

### Comparison

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

### Bitwise Operations

All bitwise operations follow **Python's two's complement semantics** for
negative numbers.

| Operator | Description                  |
| -------- | ---------------------------- |
| `a & b`  | Bitwise AND                  |
| `a \| b` | Bitwise OR                   |
| `a ^ b`  | Bitwise XOR                  |
| `~a`     | Bitwise NOT: $~x = -(x + 1)$ |

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

### Shift Operations

| Operator | Description                         |
| -------- | ----------------------------------- |
| `a << n` | Left shift (multiply by $2^n$)      |
| `a >> n` | Right shift (floor divide by $2^n$) |

```mojo
var x = BInt(1)
print(x << 100)         # 1267650600228229401496703205376 (= 2^100)
print(BInt(1024) >> 5)  # 32
```

### Mathematical Functions

#### Exponentiation <!-- omit from toc -->

```mojo
print(BInt(2).power(100))    # 2^100
print(BInt(2) ** 100)         # Same via ** operator
```

Both `power(exponent: Int)` and `power(exponent: BigInt)` are supported. The
exponent must be non-negative.

#### Integer square root <!-- omit from toc -->

```mojo
var x = BInt("100000000000000000000")
print(x.sqrt())    # 10000000000 (largest y such that y² ≤ x)
print(x.isqrt())   # Same as sqrt()
```

Raises if the value is negative.

### Number Theory

All number-theory operations are available as both **instance methods** and
**free functions**:

```mojo
from decimo import BInt, gcd, lcm, extended_gcd, mod_pow, mod_inverse
```

#### GCD — Greatest Common Divisor <!-- omit from toc -->

```mojo
var a = BInt(48)
var b = BInt(18)
print(a.gcd(b))      # 6
print(gcd(a, b))      # 6 (free function)
```

#### LCM — Least Common Multiple <!-- omit from toc -->

```mojo
print(BInt(12).lcm(BInt(18)))    # 36
print(lcm(BInt(12), BInt(18)))   # 36
```

#### Extended GCD <!-- omit from toc -->

Returns `(g, x, y)` such that `a*x + b*y = g`:

```mojo
var result = BInt(35).extended_gcd(BInt(15))
# result = (5, 1, -2)   — since 35×1 + 15×(−2) = 5
```

#### Modular Exponentiation <!-- omit from toc -->

Computes $(base^{exp}) \mod m$ efficiently without computing the full power:

```mojo
print(BInt(2).mod_pow(BInt(100), BInt(1000000007)))
print(mod_pow(BInt(2), BInt(100), BInt(1000000007)))  # free function
```

#### Modular Inverse <!-- omit from toc -->

Finds $x$ such that $(a \cdot x) \equiv 1 \pmod{m}$:

```mojo
print(BInt(3).mod_inverse(BInt(7)))      # 5 (since 3×5 = 15 ≡ 1 mod 7)
print(mod_inverse(BInt(3), BInt(7)))      # 5
```

### Conversion and Output

#### String conversions <!-- omit from toc -->

| Method                             | Example output      |
| ---------------------------------- | ------------------- |
| `str(x)` / `String(x)`             | `"12345"`           |
| `repr(x)`                          | `'BigInt("12345")'` |
| `x.to_string_with_separators("_")` | `"1_234_567"`       |
| `x.to_string_with_separators(",")` | `"1,234,567"`       |
| `x.to_hex_string()`                | `"0x1A2B3C"`        |
| `x.to_binary_string()`             | `"0b110101"`        |
| `x.to_string(line_width=20)`       | Multi-line output   |
| `x.to_chinese()`                   | `"十五"`            |

#### Numeric conversions <!-- omit from toc -->

| Method            | Description                                       |
| ----------------- | ------------------------------------------------- |
| `int(x)`          | Convert to `Int` (raises if exceeds 64-bit range) |
| `float(x)`        | Convert to `Float64` (may lose precision)         |
| `x.to_biguint()`  | Convert the magnitude to `BigUInt` (base-10^9)    |

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

### Query Methods

| Method                 | Return | Description                           |
| ---------------------- | ------ | ------------------------------------- |
| `x.is_zero()`          | `Bool` | `True` if value is 0                  |
| `x.is_negative()`      | `Bool` | `True` if value < 0                   |
| `x.is_positive()`      | `Bool` | `True` if value > 0                   |
| `x.is_one()`           | `Bool` | `True` if value is 1                  |
| `x.bit_length()`       | `Int`  | Number of bits in the magnitude       |
| `x.bit_count()`        | `Int`  | Population count (number of set bits) |
| `x.number_of_words()`  | `Int`  | Number of `UInt32` words              |
| `x.number_of_digits()` | `Int`  | Number of decimal digits              |

```mojo
var x = BInt(13)
print(x.bit_length())       # 4  (13 = 0b1101)
print(x.bit_count())        # 3  (three 1-bits)
print(x.number_of_digits()) # 2
print(x.is_positive())      # True
```

### Constants and Factory Methods

| Method / Constant      | Value |
| ---------------------- | ----- |
| `BInt.zero()`          | 0     |
| `BInt.one()`           | 1     |
| `BInt.negative_one()`  | −1    |
| `BigInt.ZERO`          | 0     |
| `BigInt.ONE`           | 1     |
| `BigInt.BITS_PER_WORD` | 32    |

## Part II — Decimal

### Overview — Decimal

`Decimal` is an arbitrary-precision decimal type — the Mojo-native equivalent of
Python's `decimal.Decimal`. It can represent numbers with unlimited digits and
decimal places, making it suitable for financial modeling, scientific computing,
and applications where floating-point errors are unacceptable.

| Property          | Value                                   |
| ----------------- | --------------------------------------- |
| Name              | `Decimal`                               |
| Aliases           | `BigDecimal`, `BDec`                    |
| Internal base     | Base-10^9 (each word stores ≤ 9 digits) |
| Default precision | 28 significant digits                   |
| Python equivalent | `decimal.Decimal`                       |

`Decimal`, `BigDecimal`, and `BDec` are all the same type. We recommend
`Decimal` for consistency with Python's `decimal.Decimal`.

### How Precision Works

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

> **Note:** The default precision of 28 will be configurable globally in a
> future version when Mojo supports global variables.

### Construction — Decimal

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

#### From `Int` (Decimal) <!-- omit from toc -->

Although you can construct a `Decimal` from an `Int` directly, it is still risky
if the `Int` is so large that it exceeds the maximum value of `Int` (which is
2^63-1).

```mojo
# These work
var x = Decimal(42)     # From Int
var y: Decimal = 100    # Implicit conversion (IntLiteral -> Int -> Decimal)

# This is dangerous!
var z: Decimal = 9223372036854775808  # 2^63, exceeds Int range!
print(z)  # Prints -9223372036854775808, overflowed!
```

#### From integral scalars <!-- omit from toc -->

```mojo
var x = Decimal(Int64(123456789))
var y = Decimal(UInt128(99999999999999))
```

Works with all integral SIMD types.
**Floating-point scalars are rejected at compile time** — use `from_float()`
instead.

#### From floating-point — `from_float()` <!-- omit from toc -->

When constructing a `Decimal` from a floating-point number, the number is first
converted to its string representation and then parsed as a `Decimal`.

Note that not all decimal numbers can be represented exactly as binary
floating-point. You may lose precision without awareness.

To make the conversion from float to `Decimal` more explicit so that you are
aware of the potential precision issues, the `Decimal()` constructor does not
accept floating-point numbers directly. Instead, to create a `Decimal` from a
float, you must use the `from_float()` factory method.

Consider never using `Decimal.from_float()` in performance-sensitive code, but
use string construction instead.

```mojo
var x = Decimal.from_float(3.14159)
var y = Decimal.from_float(Float64(2.71828))
```

#### From Python — `from_python_decimal()` <!-- omit from toc -->

You can always safely construct a `Decimal` from a Python `decimal.Decimal`
using the `from_python_decimal()` method without worrying about precision loss.

```mojo
from python import Python

var decimal = Python.import_module("decimal")
var py_dec = decimal.Decimal("123.456")

var a = Decimal.from_python_decimal(py_dec)
var b = Decimal(py=py_dec)  # Alternative keyword-only syntax
```

#### Summary of Decimal constructors <!-- omit from toc -->

| Constructor                           | Description                     |
| ------------------------------------- | ------------------------------- |
| `Decimal()`                           | Zero                            |
| `Decimal(value: String)`              | From string (raises)            |
| `Decimal(value: Scalar)`              | From any integral scalar (impl) |
| `Decimal(py=py_obj)`                  | From Python `Decimal` (raises)  |
| `Decimal.from_integral_scalar(value)` | From any integral scalar type   |
| `Decimal.from_float(value)`           | From floating-point (raises)    |
| `Decimal.from_string(value)`          | Explicit factory from string    |
| `Decimal.from_python_decimal(py_obj)` | From Python `Decimal` (raises)  |

#### Unsafe Decimal constructors <!-- omit from toc -->

These constructors skip validation for performance-sensitive code. The caller
must ensure the data is valid.

| Constructor                                               | Description                            |
| --------------------------------------------------------- | -------------------------------------- |
| `Decimal(coefficient: BigUInt, scale: Int, sign: Bool)`   | From raw components                    |
| `Decimal.from_raw_components(words, scale=0, sign=False)` | From raw `List[UInt32]` words (unsafe) |
| `Decimal.from_raw_components(word, scale=0, sign=False)`  | From a single `UInt32` word (unsafe)   |

### Decimal Arithmetic

Addition, subtraction, and multiplication are always **exact** (no precision
loss).

| Expression    | Description                           | Exact?               |
| ------------- | ------------------------------------- | -------------------- |
| `a + b`       | Addition                              | ✓ Always exact       |
| `a - b`       | Subtraction                           | ✓ Always exact       |
| `a * b`       | Multiplication                        | ✓ Always exact       |
| `a / b`       | True division (default precision=28)  | Rounded to precision |
| `a // b`      | Truncated division (toward zero)      | ✓ Integer part       |
| `a % b`       | Truncated modulo                      | —                    |
| `a ** b`      | Exponentiation (default precision=28) | Rounded to precision |
| `divmod(a,b)` | Returns `(a // b, a % b)`             | —                    |

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

### Division Methods

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

### Decimal Comparison

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

### Rounding and Formatting

#### `round()` — round to decimal places <!-- omit from toc -->

```mojo
var x = Decimal("123.456")
print(x.round(2))                       # 123.46 (ROUND_HALF_EVEN)
print(x.round(1))                       # 123.5
print(x.round(0))                       # 123
print(x.round(-1))                      # 12E+1
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
from math import ceil, floor, trunc
print(ceil(Decimal("1.1")))    # 2
print(floor(Decimal("1.9")))   # 1
print(trunc(Decimal("-1.9")))  # -1
```

### RoundingMode

Seven rounding modes are available:

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

### Mathematical Functions — Roots and Powers

All mathematical functions accept an optional `precision` parameter
(default=28).

#### Square root <!-- omit from toc -->

```mojo
print(Decimal("2").sqrt())               # 1.414213562373095048801688724
print(Decimal("2").sqrt(precision=100))  # 100 significant digits
```

#### Cube root <!-- omit from toc -->

```mojo
print(Decimal("27").cbrt())  # 3
print(Decimal("2").cbrt(precision=50))
```

#### Nth root <!-- omit from toc -->

```mojo
print(Decimal("256").root(Decimal("8")))    # 2
print(Decimal("100").root(Decimal("3")))    # 4.641588833612778892...
```

#### Power / exponentiation <!-- omit from toc -->

```mojo
print(Decimal("2").power(Decimal("10")))                 # 1024
print(Decimal("2").power(Decimal("0.5"), precision=50))  # sqrt(2) to 50 digits
print(Decimal("2") ** 10)                                # 1024
```

### Mathematical Functions — Exponential and Logarithmic

#### Exponential (e^x) <!-- omit from toc -->

```mojo
print(Decimal("1").exp())                # e ≈ 2.718281828459045235360287471
print(Decimal("10").exp(precision=50))   # e^10 to 50 digits
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
var r1 = x1.ln(100, cache)
var r2 = x2.ln(100, cache)  # Reuses cached ln(2) and ln(1.25)
```

#### Logarithm with arbitrary base <!-- omit from toc -->

```mojo
print(Decimal("100").log(Decimal("10")))  # 2
print(Decimal("8").log(Decimal("2")))     # 3
```

#### Base-10 logarithm <!-- omit from toc -->

```mojo
print(Decimal("1000").log10())  # 3 (exact for powers of 10)
print(Decimal("2").log10(precision=50))
```

### Mathematical Functions — Trigonometric

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
```

### Mathematical Constants

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

### Decimal Conversion and Output

#### String output <!-- omit from toc -->

The `to_string()` method provides flexible formatting:

```mojo
var x = Decimal("123456789.123456789")
print(x)                                          # 123456789.123456789
print(x.to_string(scientific=True))               # 1.23456789123456789E+8
print(x.to_string(engineering=True))              # 123.456789123456789E+6
print(x.to_string(delimiter="_"))                 # 123_456_789.123_456_789
print(x.to_string(line_width=20))                 # Multi-line output
print(x.to_string(force_plain=True))              # Suppress auto-scientific notation
```

Default output follows CPython's `Decimal.__str__()` rules: plain notation when
feasible, scientific notation when there would be more than 6 leading zeros.

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
var n = Int(Decimal("123.99"))     # 123 (truncates)
var f = Float64(Decimal("3.14"))   # 3.14 (may lose precision)
```

### Decimal Query Methods

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
var sign, digits, exp = Decimal("7.25").as_tuple()
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

### Python Interoperability

#### From Python <!-- omit from toc -->

```mojo
from python import Python

var decimal = Python.import_module("decimal")
var py_val = decimal.Decimal("3.14159265358979323846")

var d = Decimal.from_python_decimal(py_val)
# Or:
var d = Decimal(py=py_val)
```

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

### A note on result exponents (`Decimal` and `Dec128`)

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
`rounding_mode`, half-even by default:

```mojo
print(eval("1/3", precision=20))
# 0.33333333333333333333
print(eval("1/3", precision=5, rounding_mode=ROUND_CEILING))
# 0.33334
```

#### What you can write <!-- omit from toc -->

The operators are `+`, `-`, `*`, `/`, `^` (power), a unary minus, and
parentheses. The constants are `pi` and `e`. The functions are `sqrt`, `cbrt`,
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

### Appendix A — Import Paths

```mojo
# Recommended: import everything commonly needed
from decimo.prelude import *
# Brings in: BigInt, BInt, Integer, Decimal, BigDecimal, BDec, Dec128,
#   RoundingMode, ROUND_DOWN, ROUND_HALF_UP, ROUND_HALF_EVEN,
#   ROUND_UP, ROUND_CEILING, ROUND_FLOOR

# Or import specific types
from decimo import BInt, BigInt, Integer
from decimo import Decimal  # also available as BigDecimal or BDec
from decimo import RoundingMode

# Number-theory free functions
from decimo import gcd, lcm, extended_gcd, mod_pow, mod_inverse

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

### Appendix B — Traits Implemented

All of these come from the Mojo standard library except **`Numeric`**,
**`Parsable`** and **`Rootable`**, which Decimo defines in `decimo.traits`.
`BigInt`, `BigDecimal` and `Decimal128` conform to all three. Mojo checks
conformance nominally, which is why the traits live in Decimo rather than in
the consumer.

`Numeric` gathers `zero()`, `one()`, `-x`, `+`, `-`, `*` and `/`, so a generic
routine — a matrix or polynomial library, say — can be written once against
`T: Numeric` and run over any of the three.

`Parsable` requires the static `from_string(value)`, so the same generic
routine can also fill itself from text. The two are separate because the
capabilities are: `BigFloat` parses but is `Movable` without being `Copyable`,
so it can never be `Numeric`. Ask for `T: Numeric & Parsable` to get both.

`Rootable` requires `sqrt()`, the one operation a Cholesky or QR factorisation
needs beyond arithmetic. It is separate for the same reason, and here the
evidence is sharper: `BigUInt` has a square root but is unsigned, so it has no
`__neg__` and can never be `Numeric` either. Its supertraits are `Deinitable`
and `Movable` and no more — `Copyable` is pointedly absent, so that `BigFloat`
can conform.
`BigFloat` and `BigUInt` therefore conform to `Rootable` as well, five types
in all. Ask for `T: Numeric & Rootable` in a routine that needs both. What the
root means stays the implementing type's business: on an integral type it
truncates, so `BigInt("10").sqrt()` is `3`, exactly as `/` truncates there. So
does what a negative value does — the four exact types raise, and `BigFloat`
returns `nan`, as it does for every other function outside its domain.

#### BigInt <!-- omit from toc -->

| Trait              | What it enables                       |
| ------------------ | ------------------------------------- |
| `Absable`          | `abs(x)`                              |
| `Comparable`       | `<`, `<=`, `>`, `>=`, `==`, `!=`      |
| `Copyable`         | Value-semantic copy                   |
| `Movable`          | Move semantics                        |
| `FloatableRaising` | `Float64(x)`                          |
| `IntableRaising`   | `Int(x)`                              |
| `Numeric`          | Generic code over Decimo numbers      |
| `Parsable`         | `T.from_string(text)` in generic code |
| `Rootable`         | `x.sqrt()` in generic code            |
| `Representable`    | `repr(x)`                             |
| `Stringable`       | `String(x)`, `str(x)`                 |
| `Writable`         | `print(x)`, writer protocol           |

#### Decimal <!-- omit from toc -->

| Trait              | What it enables                       |
| ------------------ | ------------------------------------- |
| `Absable`          | `abs(x)`                              |
| `Comparable`       | `<`, `<=`, `>`, `>=`, `==`, `!=`      |
| `Copyable`         | Value-semantic copy                   |
| `Movable`          | Move semantics                        |
| `FloatableRaising` | `Float64(x)`                          |
| `IntableRaising`   | `Int(x)`                              |
| `Numeric`          | Generic code over Decimo numbers      |
| `Parsable`         | `T.from_string(text)` in generic code |
| `Rootable`         | `x.sqrt()` in generic code            |
| `Representable`    | `repr(x)`                             |
| `Roundable`        | `round(x)`, `round(x, ndigits)`       |
| `Stringable`       | `String(x)`, `str(x)`                 |
| `Writable`         | `print(x)`, writer protocol           |

### Appendix C — Complete API Tables

#### BigInt — All Operators <!-- omit from toc -->

| Operator / Method   | Accepts              | Raises? | Description            |
| ------------------- | -------------------- | ------- | ---------------------- |
| `a + b`             | `BInt`, `Int`        | No      | Addition               |
| `a - b`             | `BInt`, `Int`        | No      | Subtraction            |
| `a * b`             | `BInt`, `Int`        | No      | Multiplication         |
| `a / b`             | `BInt`, `Int`        | Yes     | Truncating division    |
| `a // b`            | `BInt`, `Int`        | Yes     | Floor division         |
| `a % b`             | `BInt`, `Int`        | Yes     | Floor modulo           |
| `a ** b`            | `BInt`, `Int`        | Yes     | Power                  |
| `a << n`            | `Int`                | No      | Left shift             |
| `a >> n`            | `Int`                | No      | Right shift            |
| `a & b`             | `BInt`, `Int`        | No      | Bitwise AND            |
| `a \| b`            | `BInt`, `Int`        | No      | Bitwise OR             |
| `a ^ b`             | `BInt`, `Int`        | No      | Bitwise XOR            |
| `~a`                | —                    | No      | Bitwise NOT            |
| `-a`                | —                    | No      | Negation               |
| `abs(a)`            | —                    | No      | Absolute value         |
| `a.sqrt()`          | —                    | Yes     | Integer square root    |
| `a.gcd(b)`          | `BInt`               | No      | GCD                    |
| `a.lcm(b)`          | `BInt`               | Yes     | LCM                    |
| `a.extended_gcd(b)` | `BInt`               | Yes     | Extended GCD           |
| `a.mod_pow(e, m)`   | `BInt`/`Int`, `BInt` | Yes     | Modular exponentiation |
| `a.mod_inverse(m)`  | `BInt`               | Yes     | Modular inverse        |

#### Decimal — Mathematical Functions <!-- omit from toc -->

| Function | Signature                    | Default | Description          |
| -------- | ---------------------------- | ------- | -------------------- |
| `sqrt`   | `x.sqrt(precision=28)`       | 28      | Square root          |
| `cbrt`   | `x.cbrt(precision=28)`       | 28      | Cube root            |
| `root`   | `x.root(n, precision=28)`    | 28      | Nth root             |
| `power`  | `x.power(exp, precision=28)` | 28      | Exponentiation       |
| `exp`    | `x.exp(precision=28)`        | 28      | e^x                  |
| `ln`     | `x.ln(precision=28)`         | 28      | Natural logarithm    |
| `log`    | `x.log(base, precision=28)`  | 28      | Logarithm (any base) |
| `log10`  | `x.log10(precision=28)`      | 28      | Base-10 logarithm    |
| `sin`    | `x.sin(precision=28)`        | 28      | Sine (radians)       |
| `cos`    | `x.cos(precision=28)`        | 28      | Cosine (radians)     |
| `tan`    | `x.tan(precision=28)`        | 28      | Tangent (radians)    |
| `cot`    | `x.cot(precision=28)`        | 28      | Cotangent (radians)  |
| `csc`    | `x.csc(precision=28)`        | 28      | Cosecant (radians)   |
| `sec`    | `x.sec(precision=28)`        | 28      | Secant (radians)     |
| `arctan` | `x.arctan(precision=28)`     | 28      | Arctangent (radians) |
| `pi`     | `Decimal.pi(precision)`      | —       | Compute π            |
| `e`      | `Decimal.e(precision)`       | —       | Compute e            |
