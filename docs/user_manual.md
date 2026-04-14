# Decimo — User Manual <!-- omit from toc -->

> Comprehensive guide to using the Decimo arbitrary-precision arithmetic library in Mojo.

All code examples below assume that you have imported the prelude at the top of
your Mojo file:

```mojo
from decimo.prelude import *
```

- [Part I — BigInt (`BInt`)](#part-i--bigint-bint)
  - [Overview](#overview)
  - [Construction](#construction)
    - [From zero](#from-zero)
    - [From `Int`](#from-int)
    - [From `String`](#from-string)
    - [From `Scalar` (any integral SIMD type)](#from-scalar-any-integral-simd-type)
    - [Summary of constructors](#summary-of-constructors)
  - [Arithmetic Operations](#arithmetic-operations)
    - [Binary operators](#binary-operators)
    - [Unary operators](#unary-operators)
    - [In-place operators](#in-place-operators)
  - [Division Semantics](#division-semantics)
  - [Comparison](#comparison)
  - [Bitwise Operations](#bitwise-operations)
  - [Shift Operations](#shift-operations)
  - [Mathematical Functions](#mathematical-functions)
    - [Exponentiation](#exponentiation)
    - [Integer square root](#integer-square-root)
  - [Number Theory](#number-theory)
    - [GCD — Greatest Common Divisor](#gcd--greatest-common-divisor)
    - [LCM — Least Common Multiple](#lcm--least-common-multiple)
    - [Extended GCD](#extended-gcd)
    - [Modular Exponentiation](#modular-exponentiation)
    - [Modular Inverse](#modular-inverse)
  - [Conversion and Output](#conversion-and-output)
    - [String conversions](#string-conversions)
    - [Numeric conversions](#numeric-conversions)
  - [Query Methods](#query-methods)
  - [Constants and Factory Methods](#constants-and-factory-methods)
- [Part II — Decimal](#part-ii--decimal)
  - [Overview](#overview-1)
  - [How Precision Works](#how-precision-works)
  - [Construction](#construction-1)
    - [From zero](#from-zero-1)
    - [From `Int`](#from-int-1)
    - [From `String`](#from-string-1)
    - [From integral scalars](#from-integral-scalars)
    - [From floating-point — `from_float()`](#from-floating-point--from_float)
    - [From Python — `from_python_decimal()`](#from-python--from_python_decimal)
    - [Summary of constructors](#summary-of-constructors-1)
  - [Arithmetic Operations](#arithmetic-operations-1)
  - [Division Methods](#division-methods)
    - [`true_divide()` — recommended for decimal division](#true_divide--recommended-for-decimal-division)
    - [Operator `/` — true division with default precision](#operator---true-division-with-default-precision)
    - [Operator `//` — truncated (integer) division](#operator---truncated-integer-division)
  - [Comparison](#comparison-1)
  - [Rounding and Formatting](#rounding-and-formatting)
    - [`round()` — round to decimal places](#round--round-to-decimal-places)
    - [`quantize()` — match scale of another decimal](#quantize--match-scale-of-another-decimal)
    - [`normalize()` — remove trailing zeros](#normalize--remove-trailing-zeros)
    - [`__ceil__`, `__floor__`, `__trunc__`](#__ceil__-__floor__-__trunc__)
  - [RoundingMode](#roundingmode)
  - [Mathematical Functions — Roots and Powers](#mathematical-functions--roots-and-powers)
    - [Square root](#square-root)
    - [Cube root](#cube-root)
    - [Nth root](#nth-root)
    - [Power / exponentiation](#power--exponentiation)
  - [Mathematical Functions — Exponential and Logarithmic](#mathematical-functions--exponential-and-logarithmic)
    - [Exponential (e^x)](#exponential-ex)
    - [Natural logarithm](#natural-logarithm)
    - [Logarithm with arbitrary base](#logarithm-with-arbitrary-base)
    - [Base-10 logarithm](#base-10-logarithm)
  - [Mathematical Functions — Trigonometric](#mathematical-functions--trigonometric)
    - [Basic functions](#basic-functions)
    - [Reciprocal functions](#reciprocal-functions)
    - [Inverse functions](#inverse-functions)
  - [Mathematical Constants](#mathematical-constants)
    - [π (pi)](#π-pi)
    - [e (Euler's number)](#e-eulers-number)
  - [Conversion and Output](#conversion-and-output-1)
    - [String output](#string-output)
    - [`repr()`](#repr)
    - [Numeric conversions](#numeric-conversions-1)
  - [Query Methods](#query-methods-1)
    - [`as_tuple()` — Python-compatible decomposition](#as_tuple--python-compatible-decomposition)
    - [Other methods](#other-methods)
  - [Python Interoperability](#python-interoperability)
    - [From Python](#from-python)
    - [Matching Python's API](#matching-pythons-api)
  - [Appendix A — Import Paths](#appendix-a--import-paths)
  - [Appendix B — Traits Implemented](#appendix-b--traits-implemented)
    - [BigInt](#bigint)
    - [Decimal](#decimal)
  - [Appendix C — Complete API Tables](#appendix-c--complete-api-tables)
    - [BigInt — All Operators](#bigint--all-operators)
    - [Decimal — Mathematical Functions](#decimal--mathematical-functions)

## Installation

Decimo is available in the [modular-community](https://repo.prefix.dev/modular-community) package repository. Add it to your `channels` list in `pixi.toml`:

```toml
channels = ["https://conda.modular.com/max", "https://repo.prefix.dev/modular-community", "conda-forge"]
```

Then install:

```bash
pixi add decimo
```

Or add it manually to `pixi.toml`:

```toml
decimo = "==0.9.0"
```

Then run `pixi install`.

## Quick Start

```mojo
from decimo.prelude import *


fn main() raises:
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

# Part I — BigInt (`BInt`)

## Overview

`BigInt` (alias `BInt`) is an arbitrary-precision signed integer type — the Mojo-native equivalent of Python's `int`. It supports unlimited-precision integer arithmetic, bitwise operations, and number-theoretic functions.

| Property          | Value                        |
| ----------------- | ---------------------------- |
| Full name         | `BigInt`                     |
| Short alias       | `BInt`                       |
| Internal base     | 2^32 (binary representation) |
| Word type         | `UInt32` (little-endian)     |
| Python equivalent | `int`                        |

## Construction

### From zero

```mojo
var x = BInt()          # 0
```

### From `Int`

```mojo
var x = BInt(42)
var y = BInt(-100)
var z: BInt = 42        # Implicit conversion from Int
```

The constructor is marked `@implicit`, so Mojo can automatically convert `Int` to `BInt` where expected.

### From `String`

```mojo
var a = BInt("12345678901234567890")  # Basic decimal string
var b = BInt("-98765")                 # Negative number
var c = BInt("1_000_000")             # Underscores as separators
var d = BInt("1,234,567")             # Commas as separators
var e = BInt("1.23e5")                # Scientific notation (= 123000)
var f = BInt("1991_10,18")            # Mixed separators (= 19911018)
```

> **Note:** The string must represent an integer. `BInt("1.5")` raises an error. Scientific notation like `"1.23e5"` is accepted only if the result is an integer.

### From `Scalar` (any integral SIMD type)

```mojo
var x = BInt(UInt32(42))
var y = BInt(Int64(-5))
var z: BInt = UInt32(99)     # Implicit conversion
```

Accepts any integral scalar type (`Int8` through `Int256`, `UInt8` through `UInt256`, etc.).

### Summary of constructors

| Constructor                 | Description                           |
| --------------------------- | ------------------------------------- |
| `BInt()`                    | Zero                                  |
| `BInt(value: Int)`          | From `Int` (implicit)                 |
| `BInt(value: String)`       | From decimal string (raises)          |
| `BInt(value: Scalar)`       | From integral scalar (implicit)       |
| `BInt.from_uint64(value)`   | From `UInt64`                         |
| `BInt.from_uint128(value)`  | From `UInt128`                        |
| `BInt.from_string(value)`   | Explicit factory from string (raises) |
| `BInt.from_bigint10(value)` | Convert from `BigInt10`               |

## Arithmetic Operations

### Binary operators

| Expression    | Description                       | Raises?            |
| ------------- | --------------------------------- | ------------------ |
| `a + b`       | Addition                          | No                 |
| `a - b`       | Subtraction                       | No                 |
| `a * b`       | Multiplication                    | No                 |
| `a // b`      | Floor division (rounds toward −∞) | Yes (zero div)     |
| `a % b`       | Floor modulo (Python semantics)   | Yes (zero div)     |
| `divmod(a,b)` | Floor quotient and remainder      | Yes (zero div)     |
| `a ** b`      | Exponentiation                    | Yes (negative exp) |

### Unary operators

| Expression | Description                    |
| ---------- | ------------------------------ |
| `-a`       | Negation                       |
| `+a`       | Unary plus (returns copy)      |
| `abs(a)`   | Absolute value                 |
| `bool(a)`  | `True` if nonzero              |
| `~a`       | Bitwise NOT (two's complement) |

### In-place operators

`+=`, `-=`, `*=`, `//=`, `%=`, `<<=`, `>>=` are all supported and perform true in-place mutation to reduce memory allocation.

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

## Division Semantics

BigInt supports two division conventions:

| Name              | Operator / Method                          | Quotient    | Python equivalent |
| ----------------- | ------------------------------------------ | ----------- | ----------------- |
| Floor division    | `//`, `%`, `divmod()`                      | Toward −∞   | `//`, `%`         |
| Truncate division | `.truncate_divide()`, `.truncate_modulo()` | Toward zero | C/Java `/`, `%`   |

The difference matters for negative operands:

```mojo
var a = BInt(7)
var b = BInt(-2)

# Floor division (Python semantics)
print(a // b)                    # -4
print(a % b)                     # -1

# Truncate division (C/Java semantics)
print(a.truncate_divide(b))      # -3
print(a.truncate_modulo(b))      #  1
```

## Comparison

All six comparison operators (`==`, `!=`, `>`, `>=`, `<`, `<=`) are supported. Each accepts both `BInt` and `Int` as the right operand.

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

## Bitwise Operations

All bitwise operations follow **Python's two's complement semantics** for negative numbers.

| Operator | Description                  |
| -------- | ---------------------------- |
| `a & b`  | Bitwise AND                  |
| `a \| b` | Bitwise OR                   |
| `a ^ b`  | Bitwise XOR                  |
| `~a`     | Bitwise NOT: $~x = -(x + 1)$ |

Each accepts both `BInt` and `Int` as the right operand. In-place variants (`&=`, `|=`, `^=`) are also available.

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

## Shift Operations

| Operator | Description                         |
| -------- | ----------------------------------- |
| `a << n` | Left shift (multiply by $2^n$)      |
| `a >> n` | Right shift (floor divide by $2^n$) |

```mojo
var x = BInt(1)
print(x << 100)         # 1267650600228229401496703205376 (= 2^100)
print(BInt(1024) >> 5)  # 32
```

## Mathematical Functions

### Exponentiation

```mojo
print(BInt(2).power(100))    # 2^100
print(BInt(2) ** 100)         # Same via ** operator
```

Both `power(exponent: Int)` and `power(exponent: BigInt)` are supported. The exponent must be non-negative.

### Integer square root

```mojo
var x = BInt("100000000000000000000")
print(x.sqrt())    # 10000000000 (largest y such that y² ≤ x)
print(x.isqrt())   # Same as sqrt()
```

Raises if the value is negative.

## Number Theory

All number-theory operations are available as both **instance methods** and **free functions**:

```mojo
from decimo import BInt, gcd, lcm, extended_gcd, mod_pow, mod_inverse
```

### GCD — Greatest Common Divisor

```mojo
var a = BInt(48)
var b = BInt(18)
print(a.gcd(b))      # 6
print(gcd(a, b))      # 6 (free function)
```

### LCM — Least Common Multiple

```mojo
print(BInt(12).lcm(BInt(18)))    # 36
print(lcm(BInt(12), BInt(18)))   # 36
```

### Extended GCD

Returns `(g, x, y)` such that `a*x + b*y = g`:

```mojo
var result = BInt(35).extended_gcd(BInt(15))
# result = (5, 1, -2)   — since 35×1 + 15×(−2) = 5
```

### Modular Exponentiation

Computes $(base^{exp}) \mod m$ efficiently without computing the full power:

```mojo
print(BInt(2).mod_pow(BInt(100), BInt(1000000007)))
print(mod_pow(BInt(2), BInt(100), BInt(1000000007)))  # free function
```

### Modular Inverse

Finds $x$ such that $(a \cdot x) \equiv 1 \pmod{m}$:

```mojo
print(BInt(3).mod_inverse(BInt(7)))      # 5 (since 3×5 = 15 ≡ 1 mod 7)
print(mod_inverse(BInt(3), BInt(7)))      # 5
```

## Conversion and Output

### String conversions

| Method                             | Example output      |
| ---------------------------------- | ------------------- |
| `str(x)` / `String(x)`             | `"12345"`           |
| `repr(x)`                          | `'BigInt("12345")'` |
| `x.to_string_with_separators("_")` | `"1_234_567"`       |
| `x.to_string_with_separators(",")` | `"1,234,567"`       |
| `x.to_hex_string()`                | `"0x1A2B3C"`        |
| `x.to_binary_string()`             | `"0b110101"`        |
| `x.to_string(line_width=20)`       | Multi-line output   |

### Numeric conversions

| Method            | Description                                       |
| ----------------- | ------------------------------------------------- |
| `int(x)`          | Convert to `Int` (raises if exceeds 64-bit range) |
| `float(x)`        | Convert to `Float64` (may lose precision)         |
| `x.to_bigint10()` | Convert to `BigInt10` (base-10^9)                 |

```mojo
var x = BInt("123456789012345678901234567890")
print(x.to_string_with_separators())  # 123_456_789_012_345_678_901_234_567_890
print(x.to_hex_string())              # 0x...
```

## Query Methods

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

## Constants and Factory Methods

| Method / Constant      | Value |
| ---------------------- | ----- |
| `BInt.zero()`          | 0     |
| `BInt.one()`           | 1     |
| `BInt.negative_one()`  | −1    |
| `BigInt.ZERO`          | 0     |
| `BigInt.ONE`           | 1     |
| `BigInt.BITS_PER_WORD` | 32    |

# Part II — Decimal

## Overview

`Decimal` is an arbitrary-precision decimal type — the Mojo-native equivalent of Python's `decimal.Decimal`. It can represent numbers with unlimited digits and decimal places, making it suitable for financial modeling, scientific computing, and applications where floating-point errors are unacceptable.

| Property          | Value                                   |
| ----------------- | --------------------------------------- |
| Name              | `Decimal`                               |
| Aliases           | `BigDecimal`, `BDec`                    |
| Internal base     | Base-10^9 (each word stores ≤ 9 digits) |
| Default precision | 28 significant digits                   |
| Python equivalent | `decimal.Decimal`                       |

`Decimal`, `BigDecimal`, and `BDec` are all the same type. We recommend `Decimal` for consistency with Python's `decimal.Decimal`.

## How Precision Works

- **Addition, subtraction, multiplication** are always **exact** — no precision loss.
- **Division** and **mathematical functions** (`sqrt`, `ln`, `exp`, etc.) accept an optional `precision` parameter specifying the number of **significant digits** in the result.
- The default precision is **28** significant digits, matching Python's `decimal` module.

```mojo
var x = Decimal("2")
print(x.sqrt())                # 28 significant digits (default)
print(x.sqrt(precision=100))   # 100 significant digits
print(x.sqrt(precision=1000))  # 1000 significant digits
```

> **Note:** The default precision of 28 will be configurable globally in a future version when Mojo supports global variables.

## Construction

### From zero

```mojo
var x = Decimal()  # 0
```

### From `Int`

```mojo
var x = Decimal(42)
var y: Decimal = 100     # Implicit conversion
```

### From `String`

```mojo
var a = Decimal("123456789.123456789")  # Plain notation
var b = Decimal("1.23E+10")             # Scientific notation
var c = Decimal("-0.000001")            # Negative
var d = Decimal("1_000_000.50")         # Separator support
```

### From integral scalars

```mojo
var x = Decimal(Int64(123456789))
var y = Decimal(UInt128(99999999999999))
```

Works with all integral SIMD types. **Floating-point scalars are rejected at compile time** — use `from_float()` instead.

### From floating-point — `from_float()`

```mojo
var x = Decimal.from_float(3.14159)
var y = Decimal.from_float(Float64(2.71828))
```

> **Why no implicit Float64 constructor?** Implicit conversion from float would silently introduce floating-point artifacts (e.g., `0.1` → `0.1000000000000000055...`). The `from_float()` method makes this explicit.

### From Python — `from_python_decimal()`

```mojo
from python import Python

var decimal = Python.import_module("decimal")
var py_dec = decimal.Decimal("123.456")

var a = Decimal.from_python_decimal(py_dec)
var b = Decimal(py=py_dec)  # Alternative keyword syntax
```

### Summary of constructors

| Constructor                           | Description                     |
| ------------------------------------- | ------------------------------- |
| `Decimal()`                           | Zero                            |
| `Decimal(value: Int)`                 | From `Int` (implicit)           |
| `Decimal(value: String)`              | From string (raises)            |
| `Decimal(value: Scalar)`              | From integral scalar (implicit) |
| `Decimal.from_float(value)`           | From floating-point (raises)    |
| `Decimal.from_python_decimal(py_obj)` | From Python `Decimal` (raises)  |
| `Decimal(coefficient, scale, sign)`   | From raw components             |

## Arithmetic Operations

Addition, subtraction, and multiplication are always **exact** (no precision loss).

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

In-place operators (`+=`, `-=`, `*=`) perform true in-place mutation for reduced allocation.

```mojo
var a = Decimal("123456789.123456789")
var b = Decimal("1234.56789")
print(a + b)   # 123458023.691346789
print(a - b)   # 123455554.555566789
print(a * b)   # 152415787654.32099750190521
```

## Division Methods

Division is the primary operation where precision matters. Decimo provides several variants:

### `true_divide()` — recommended for decimal division

```mojo
var a = Decimal("1")
var b = Decimal("3")
print(a.true_divide(b))                # 0.3333333333333333333333333333 (28 digits)
print(a.true_divide(b, precision=50))  # 50 significant digits
print(a.true_divide(b, precision=200)) # 200 significant digits
```

### Operator `/` — true division with default precision

```mojo
var result = a / b  # Same as a.true_divide(b, precision=28)
```

### Operator `//` — truncated (integer) division

```mojo
print(Decimal("7") // Decimal("4"))    # 1
print(Decimal("-7") // Decimal("4"))   # -1  (toward zero)
```

## Comparison

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

## Rounding and Formatting

### `round()` — round to decimal places

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

### `quantize()` — match scale of another decimal

Adjusts the scale (number of decimal places) to match the scale of `exp`. The actual value of `exp` is ignored — only its scale matters.

```mojo
var x = Decimal("1.2345")
print(x.quantize(Decimal("0.01")))   # 1.23 (2 decimal places)
print(x.quantize(Decimal("0.1")))    # 1.2  (1 decimal place)
print(x.quantize(Decimal("1")))      # 1    (0 decimal places)

# Currency formatting:
var price = Decimal("19.999")
print(price.quantize(Decimal("0.01")))  # 20.00
```

### `normalize()` — remove trailing zeros

```mojo
print(Decimal("1.2345000").normalize())  # 1.2345
```

### `__ceil__`, `__floor__`, `__trunc__`

```mojo
from math import ceil, floor, trunc
print(ceil(Decimal("1.1")))    # 2
print(floor(Decimal("1.9")))   # 1
print(trunc(Decimal("-1.9")))  # -1
```

## RoundingMode

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

## Mathematical Functions — Roots and Powers

All mathematical functions accept an optional `precision` parameter (default=28).

### Square root

```mojo
print(Decimal("2").sqrt())               # 1.414213562373095048801688724
print(Decimal("2").sqrt(precision=100))  # 100 significant digits
```

### Cube root

```mojo
print(Decimal("27").cbrt())  # 3
print(Decimal("2").cbrt(precision=50))
```

### Nth root

```mojo
print(Decimal("256").root(Decimal("8")))    # 2
print(Decimal("100").root(Decimal("3")))    # 4.641588833612778892...
```

### Power / exponentiation

```mojo
print(Decimal("2").power(Decimal("10")))                 # 1024
print(Decimal("2").power(Decimal("0.5"), precision=50))  # sqrt(2) to 50 digits
print(Decimal("2") ** 10)                                # 1024
```

## Mathematical Functions — Exponential and Logarithmic

### Exponential (e^x)

```mojo
print(Decimal("1").exp())                # e ≈ 2.718281828459045235360287471
print(Decimal("10").exp(precision=50))   # e^10 to 50 digits
```

### Natural logarithm

```mojo
print(Decimal("10").ln(precision=50))    # ln(10) to 50 digits
```

For repeated calls, a `MathCache` can be used to avoid recomputing cached constants:

```mojo
from decimo.bigdecimal.exponential import MathCache

var cache = MathCache()
var r1 = x1.ln(100, cache)
var r2 = x2.ln(100, cache)  # Reuses cached ln(2) and ln(1.25)
```

### Logarithm with arbitrary base

```mojo
print(Decimal("100").log(Decimal("10")))  # 2
print(Decimal("8").log(Decimal("2")))     # 3
```

### Base-10 logarithm

```mojo
print(Decimal("1000").log10())  # 3 (exact for powers of 10)
print(Decimal("2").log10(precision=50))
```

## Mathematical Functions — Trigonometric

All trigonometric functions take inputs in **radians** and accept an optional `precision` parameter.

### Basic functions

```mojo
print(Decimal("0.5").sin(precision=50))
print(Decimal("0.5").cos(precision=50))
print(Decimal("0.5").tan(precision=50))
```

### Reciprocal functions

```mojo
print(Decimal("1").cot(precision=50))   # cos/sin
print(Decimal("1").csc(precision=50))   # 1/sin
print(Decimal("1").sec(precision=50))   # 1/cos
```

### Inverse functions

```mojo
print(Decimal("1").arctan(precision=50))  # π/4 to 50 digits
```

## Mathematical Constants

### π (pi)

Computed using the **Chudnovsky algorithm** with binary splitting:

```mojo
print(Decimal.pi(precision=100))    # 100 digits of π
print(Decimal.pi(precision=1000))   # 1000 digits of π
```

### e (Euler's number)

Computed as `exp(1)`:

```mojo
print(Decimal.e(precision=100))     # 100 digits of e
print(Decimal.e(precision=1000))    # 1000 digits of e
```

## Conversion and Output

### String output

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

Default output follows CPython's `Decimal.__str__()` rules: plain notation when feasible, scientific notation when there would be more than 6 leading zeros.

Convenience aliases:

```mojo
x.to_scientific_string()               # to_string(scientific=True)
x.to_eng_string()                      # to_string(engineering=True)
x.to_string_with_separators("_")       # to_string(delimiter="_")
```

### `repr()`

```mojo
print(repr(Decimal("123.45")))  # Decimal("123.45")
```

### Numeric conversions

```mojo
var n = Int(Decimal("123.99"))     # 123 (truncates)
var f = Float64(Decimal("3.14"))   # 3.14 (may lose precision)
```

## Query Methods

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

### `as_tuple()` — Python-compatible decomposition

```mojo
var sign, digits, exp = Decimal("7.25").as_tuple()
# sign=False, digits=[7, 2, 5], exp=-2
```

### Other methods

```mojo
x.copy_abs()             # Copy with positive sign
x.copy_negate()          # Copy with inverted sign
x.copy_sign(other)       # Copy of x with sign of other
x.fma(a, b)              # Fused multiply-add: x*a+b (exact)
x.scaleb(n)              # Multiply by 10^n (O(1), adjusts scale only)
```

## Python Interoperability

### From Python

```mojo
from python import Python

var decimal = Python.import_module("decimal")
var py_val = decimal.Decimal("3.14159265358979323846")

var d = BigDecimal.from_python_decimal(py_val)
# Or:
var d = BigDecimal(py=py_val)
```

### Matching Python's API

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

## Appendix A — Import Paths

```mojo
# Recommended: import everything commonly needed
from decimo.prelude import *
# Brings in: BInt, Decimal, Dec128, RoundingMode,
#   ROUND_DOWN, ROUND_HALF_UP, ROUND_HALF_EVEN, ROUND_UP, ROUND_CEILING, ROUND_FLOOR

# Or import specific types
from decimo import BInt, BigInt
from decimo import Decimal  # also available as BigDecimal or BDec
from decimo import RoundingMode

# Number-theory free functions
from decimo import gcd, lcm, extended_gcd, mod_pow, mod_inverse
```

## Appendix B — Traits Implemented

### BigInt

| Trait              | What it enables                  |
| ------------------ | -------------------------------- |
| `Absable`          | `abs(x)`                         |
| `Comparable`       | `<`, `<=`, `>`, `>=`, `==`, `!=` |
| `Copyable`         | Value-semantic copy              |
| `Movable`          | Move semantics                   |
| `FloatableRaising` | `Float64(x)`                     |
| `IntableRaising`   | `Int(x)`                         |
| `Representable`    | `repr(x)`                        |
| `Stringable`       | `String(x)`, `str(x)`            |
| `Writable`         | `print(x)`, writer protocol      |

### Decimal

| Trait              | What it enables                  |
| ------------------ | -------------------------------- |
| `Absable`          | `abs(x)`                         |
| `Comparable`       | `<`, `<=`, `>`, `>=`, `==`, `!=` |
| `Copyable`         | Value-semantic copy              |
| `Movable`          | Move semantics                   |
| `FloatableRaising` | `Float64(x)`                     |
| `IntableRaising`   | `Int(x)`                         |
| `Representable`    | `repr(x)`                        |
| `Roundable`        | `round(x)`, `round(x, ndigits)`  |
| `Stringable`       | `String(x)`, `str(x)`            |
| `Writable`         | `print(x)`, writer protocol      |

## Appendix C — Complete API Tables

### BigInt — All Operators

| Operator / Method   | Accepts              | Raises? | Description            |
| ------------------- | -------------------- | ------- | ---------------------- |
| `a + b`             | `BInt`, `Int`        | No      | Addition               |
| `a - b`             | `BInt`, `Int`        | No      | Subtraction            |
| `a * b`             | `BInt`, `Int`        | No      | Multiplication         |
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

### Decimal — Mathematical Functions

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
