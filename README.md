# Decimo (formerly DeciMojo) <!-- omit from toc -->

An arbitrary-precision integer and decimal library for
[Mojo](https://www.modular.com/mojo), also with a 128-bit fixed-point decimal
type, inspired by Python's `int` and `Decimal`. Install it with
`pixi add decimo`.

Comes with an interactive arbitrary-precision calculator (REPL + one-shot mode)
powered by [ArgMojo](https://github.com/forfudan/argmojo). Install it with
`brew install forfudan/tap/decimo`.

The same library is packaged for Python as a near drop-in for the standard
library's `decimal`, and a superset of it: the whole of its method surface,
plus `pi()`, `e()` and a 128-bit decimal type. Install it with
`pip install decimo`.

[![Version](https://img.shields.io/badge/version-v0.14.0-blue)](https://github.com/forfudan/decimo/releases/tag/v0.14.0)
[![Mojo](https://img.shields.io/badge/mojo-1.0.0-orange)](https://docs.modular.com/mojo/manual/)
[![CI](https://img.shields.io/github/actions/workflow/status/forfudan/decimo/run_tests.yaml?branch=main&label=tests)](https://github.com/forfudan/decimo/actions/workflows/run_tests.yaml)
[![License](https://img.shields.io/github/license/forfudan/decimo)](https://github.com/forfudan/decimo/blob/main/LICENSE)

[![pixi](https://img.shields.io/badge/pixi%20add-decimo-purple)](https://prefix.dev/channels/modular-community/packages/decimo)
[![PyPI](https://img.shields.io/badge/pip%20install-decimo-blue)](https://pypi.org/project/decimo/)
[![Homebrew](https://img.shields.io/badge/brew%20install-forfudan%2Ftap%2Fdecimo-orange)](https://github.com/forfudan/homebrew-tap)

| Type         | Alias             | Information                              | Layout       |
| ------------ | ----------------- | ---------------------------------------- | ------------ |
| `BigInt`     | `BInt`            | Equivalent to Python's `int`             | Base-2^64    |
| `BigDecimal` | `BDec`, `Decimal` | Equivalent to Python's `decimal.Decimal` | Base-10^18   |
| `Decimal128` | `Dec128`          | 128-bit fixed-precision decimal type     | 32-bit words |
| `BigFloat`   | `Float`           | Arbitrary-precision floating-point type  | MPFR/GMP     |

<!--
[![Stars](https://img.shields.io/github/stars/forfudan/decimo?style=flat)](https://github.com/forfudan/decimo/stargazers)
[![Issues](https://img.shields.io/github/issues/forfudan/decimo)](https://github.com/forfudan/decimo/issues)
![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)
[![Last Commit](https://img.shields.io/github/last-commit/forfudan/decimo?color=red)](https://github.com/forfudan/decimo/commits/main)
-->

<!--
[![中文](https://img.shields.io/badge/中文-介紹-red)](https://github.com/forfudan/decimo/blob/main/docs/readme_zht.md)
[![Changelog](https://img.shields.io/badge/change-log-yellow)](https://github.com/forfudan/decimo/blob/main/docs/changelog.md)
[![Repository on GitHub](https://img.shields.io/badge/repo-GitHub-black)](https://github.com/forfudan/decimo)
[![Discord](https://img.shields.io/badge/discord-join-darkblue)](https://discord.gg/3rGH87uZTk)
-->

## Overview

### Decimo library

![Decimo library](https://raw.githubusercontent.com/forfudan/forfudan-github-data/main/decimo/library.webp)  
*Base-ten arithmetic, integers with no width limit, and an expression evaluator*

Decimo provides an arbitrary-precision integer and decimal library for Mojo. It
delivers exact calculations for financial modeling, scientific computing, and
applications where floating-point approximation errors are unacceptable. Beyond
basic arithmetic, the library includes advanced mathematical functions with
guaranteed precision.

For Pythonistas, `decimo.BigInt` to Mojo is like `int` to Python, and
`decimo.BigDecimal` to Mojo is like `decimal.Decimal` to Python.
`decimo.Decimal128` to Mojo is like `System.Decimal` to C# or `rust_decimal` to
Rust.

The core types are[^auxiliary]:

- An arbitrary-precision signed integer type `BigInt`[^bigint] (alias `BInt`),
  which is a Mojo-native equivalent of Python's `int`.
- An arbitrary-precision decimal implementation (`BigDecimal`) (alias `Decimal`)
  allowing for calculations with unlimited digits and decimal
  places[^arbitrary], which is a Mojo-native equivalent of Python's
  `decimal.Decimal`.
- A 128-bit fixed-point decimal implementation (`Decimal128`) (alias `Dec128`)
  supporting up to 29 significant digits with a maximum of 28 decimal
  places[^fixed], which is a Mojo-native equivalent of C#'s `System.Decimal` or
  Rust's `rust_decimal`.
- An arbitrary-precision floating-point implementation (`BigFloat`) backed by
  the GNU MPFR library, supporting computations with configurable precision and
  a wide exponent range. Unlike `BigDecimal`, which uses base-10 arithmetic,
  `BigFloat` uses binary floating-point internally. This type is optional and
  requires MPFR/GMP to be installed on the user's system.
<!-- - An arbitrary-precision exact rational number type (`Rational`) represented as a reduced fraction of two `BigInt`s (numerator and denominator). It supports exact arithmetic and comparisons without any loss of precision, making it ideal for applications that require precise fractional calculations. -->

Decimo is fast: at a million digits `pi()` is nearly twelve times quicker than
pure-Python mpmath, `BigInt` multiplication is fifteen times quicker than
CPython's `int`,
and small `BigDecimal` operations are close to libmpdec, the C library behind
Python's `decimal`. The measured numbers, with the commit they were taken on,
are in [docs/benchmarks.md](docs/benchmarks.md); `pixi run benchdoc` regenerates
them.

**Decimo** combines "**Deci**mal" and "**Mo**jo" - reflecting its purpose and
implementation language. "Decimo" is also a Latin word meaning "tenth" and is
the root of the word "decimal".

### CLI calculator

`decimo` is a command-line calculator built on the Decimo library and powered by
[ArgMojo](https://github.com/forfudan/argmojo). Run it with no arguments for an
interactive REPL, or pass an expression / file / piped stdin for one-shot
evaluation. The binary is self-contained — no Mojo or Pixi needed on the user's
machine. See the [user manual](./docs/user_manual_cli.md) for the full
reference, and the [Quick start](#cli-quick-start) below for a taste.

![Decimo CLI calculator](https://raw.githubusercontent.com/forfudan/forfudan-github-data/main/decimo/cli.webp)  
*Ask for as many significant digits as you like*

### Python package

![Decimo for Python](https://raw.githubusercontent.com/forfudan/forfudan-github-data/main/decimo/python.webp)  
*Everything `decimal` has, and things it does not*

The Mojo library is also compiled into a Python extension and published on PyPI,
where it stands in for the standard library's `decimal`. Change one import and
a `decimal` program keeps working:

```python
# from decimal import Decimal, getcontext
from decimo import Decimal, getcontext

getcontext().prec = 50
print(Decimal(1) / Decimal(7))
# 0.14285714285714285714285714285714285714285714285714
```

The two agree digit for digit. The test suite checks every operation against
the standard library rather than against a table of expected strings, so
"agrees with `decimal`" is measured rather than claimed.

Nothing is missing: every method `decimal.Decimal` has, `decimo.Decimal` has
too. And it goes further. `pi()` and `e()` are there, which `decimal` has
neither of. `sqrt`, `exp`, `ln` and `log10` take a `rounding=` argument, where
`decimal` ignores the context mode for those and always rounds half to even.
`Decimal128` brings trigonometry, `cbrt`, `root` and the IEEE 754 interchange
bytes with it. And it is faster once the numbers are large — 2.9x at a
thousand digits — 20-25% behind on small ones, where what is left is the cost
of the Python call rather than the arithmetic.

Where it is not a drop-in it refuses rather than answers differently: no NaN
or infinity, no `ROUND_05UP`, no signals or traps, and one context per process
rather than per thread. See [python/README.md](./python/README.md) for the
full list with the reasoning, and the
[Python quick start](#python-quick-start) below for a taste.

### TOML parser

This repository includes a built-in [TOML parser](./docs/readme_toml.md)
(`decimo.toml`), a lightweight pure-Mojo implementation supporting TOML v1.0. It
parses configuration files and test data, supporting basic types, arrays, and
nested tables. While created for Decimo's testing framework, it offers
general-purpose structured data parsing with a clean, simple API.

## Installation

### Install Decimo library for Mojo projects

Decimo is available in the modular-community
`https://repo.prefix.dev/modular-community` package repository. To access this
repository, add it to your `channels` list in your `pixi.toml` file:

```toml
channels = ["https://conda.modular.com/max", "https://repo.prefix.dev/modular-community", "conda-forge"]
```

Then, you can install Decimo using any of these methods:

1. From the `pixi` CLI, run the command ```pixi add decimo```. This fetches the
   latest version and makes it immediately available for import.

1. In the `mojoproject.toml` file of your project, add the following dependency:

    ```toml
    decimo = ">=0.14.0, <0.15.0"
    ```

    Then run `pixi install` to download and install the package.

1. For the latest development version in the `main` branch, clone
   [this GitHub repository](https://github.com/forfudan/decimo) and build the
   package locally using the command `pixi run package`.

---

<details>
<summary><b>Package versions and Mojo compatibility</b></summary>

The following table summarizes the package versions and their corresponding Mojo
versions:

| library    | version | Mojo version    | package manager |
| ---------- | ------- | --------------- | --------------- |
| `decimojo` | v0.1.0  | ==25.1          | magic           |
| `decimojo` | v0.2.0  | ==25.2          | magic           |
| `decimojo` | v0.3.0  | ==25.2          | magic           |
| `decimojo` | v0.3.1  | >=25.2, <25.4   | pixi            |
| `decimojo` | v0.4.x  | ==25.4          | pixi            |
| `decimojo` | v0.5.0  | ==25.5          | pixi            |
| `decimojo` | v0.6.0  | ==0.25.7        | pixi            |
| `decimojo` | v0.7.0  | ==0.26.1        | pixi            |
| `decimo`   | v0.8.0  | ==0.26.1        | pixi            |
| `decimo`   | v0.9.0  | ==0.26.2        | pixi            |
| `decimo`   | v0.10.0 | ==1.0.0b1       | pixi            |
| `decimo`   | v0.11.0 | ==1.0.0b2       | pixi            |
| `decimo`   | v0.12.0 | >=1.0.0, <1.1.0 | pixi            |
| `decimo`   | v0.13.0 | >=1.0.0, <1.1.0 | pixi            |
| `decimo`   | v0.14.0 | >=1.0.0, <1.1.0 | pixi            |

</details>

---

### Install CLI calculator

The `decimo` CLI is distributed via the
[`forfudan/tap`](https://github.com/forfudan/homebrew-tap) Homebrew tap.
Pre-built binaries are available for **macOS arm64** (Apple Silicon) and
**Linux x86_64**, and ship with the Mojo runtime libraries bundled — you do not
need Mojo or Pixi installed.

```bash
brew install forfudan/tap/decimo
decimo --version
```

Or tap once and use the bare formula name:

```bash
brew tap forfudan/tap
brew install decimo
```

To upgrade to a later release:

```bash
brew update && brew upgrade decimo
```

### Install the Python package

```bash
pip install decimo
```

Wheels are built for macOS arm64 (macOS 11 and later) and for Linux on x86_64
and arm64 (glibc 2.35 and later), for CPython 3.13 and 3.14. Nothing else is
needed — the Mojo runtime libraries travel inside the wheel. On any other
platform, build from source with [pixi](https://pixi.sh):

```bash
git clone https://github.com/forfudan/decimo && cd decimo
pixi run -e py314 release        # or py313; the wheel lands in python/dist/
pip install python/dist/*.whl
```

## Quick start

### Library quick start

You can start using Decimo by importing the `decimo` module. An easy way to do
this is to import everything from the `prelude` module, which provides the most
commonly used types.

```mojo
from decimo.prelude import *
```

This will import the following types or aliases into your namespace:

- `BigInt` (and its alias `BInt`): An arbitrary-precision signed
  integer type, equivalent to Python's `int`.
- `BigDecimal` (and its aliases `BDec`, `Decimal`): An arbitrary-precision
  decimal type, equivalent to Python's `decimal.Decimal`.
- `Decimal128` (and its alias `Dec128`): A 128-bit fixed-precision decimal type.
- `RoundingMode`: An enumeration for rounding modes.
- `ROUND_DOWN`, `ROUND_HALF_UP`, `ROUND_HALF_EVEN`, `ROUND_UP`,
  `ROUND_CEILING`, `ROUND_FLOOR`: Constants for common rounding modes.

---

<details>
<summary><b>BigDecimal — arbitrary precision, and how to set it</b></summary>

Here are some examples showcasing the arbitrary-precision feature of the
`BigDecimal` (`Decimal`) type. For some mathematical operations, the default
precision (number of significant digits) is set to `28`. You can change the
precision by passing the `precision` argument to the function. This default
precision will be configurable globally in future when Mojo supports global
variables.

```mojo
from decimo.prelude import *


def main() raises:
    var a = BigDecimal("123456789.123456789") 
    var b = Decimal("1234.56789")  # Alias of BigDecimal

    # === Basic Arithmetic === #
    print(a + b)  # 123458023.691346789
    print(a - b)  # 123455554.555566789
    print(a * b)  # 152415787654.32099750190521
    print(a.true_divide(b + 1))  # 99919.06565608207008357913866

    # === Exponential Functions === #
    print(a.sqrt(precision=80))
    # 11111.111066111110969430554981749302328338130654689094538188579359566416821203641
    print(a.cbrt(precision=80))
    # 497.93385938415242742001134219007635925452951248903093962731782327785111102410518
    print(a.root(b, precision=80))
    # 1.0152058862996527138602610522640944903320735973237537866713119992581006582644107
    print(a.power(b, precision=80))
    # 3.3463611024190802340238135400789468682196324482030786573104956727660098625641520E+9989
    print(a.exp(precision=80))
    # 1.8612755889649587035842377856492201091251654136588338983610243887893287518637652E+53616602
    print(a.log(b, precision=80))
    # 2.6173300266565482999078843564152939771708486260101032293924082259819624360226238
    print(a.ln(precision=80))
    # 18.631401767168018032693933348296537542797015174553735308351756611901741276655161

    # === Trigonometric Functions === #
    print(a.sin(precision=200))
    # 0.99985093087193092464780008002600992896256609588456
    #   91036188395766389946401881352599352354527727927177
    #   79589259132243649550891532070326452232864052771477
    #   31418817041042336608522984511928095747763538486886
    print(b.cos(precision=1000))
    # -0.9969577603867772005841841569997528013669868536239849713029893885930748434064450375775817720425329394
    #    9756020177557431933434791661179643984869397089102223199519409695771607230176923201147218218258755323
    #    7563476302904118661729889931783126826250691820526961290122532541861737355873869924820906724540889765
    #    5940445990824482174517106016800118438405307801022739336016834311018727787337447844118359555063575166
    #    5092352912854884589824773945355279792977596081915868398143592738704592059567683083454055626123436523
    #    6998108941189617922049864138929932713499431655377552668020889456390832876383147018828166124313166286
    #    6004871998201597316078894718748251490628361253685772937806895692619597915005978762245497623003811386
    #    0913693867838452088431084666963414694032898497700907783878500297536425463212578556546527017688874265
    #    0785862902484462361413598747384083001036443681873292719322642381945064144026145428927304407689433744
    #    5821277763016669042385158254006302666602333649775547203560187716156055524418512492782302125286330865

    # === Internal representation of the number === #
    (
        Decimal(
            "3.141592653589793238462643383279502884197169399375105820974944"
        ).power(2, precision=60)
    ).print_internal_representation()
    # Internal Representation Details of BigDecimal
    # ----------------------------------------------
    # number:         9.8696044010893586188344909998
    #                 761511353136994072407906264133
    #                 5
    # coefficient:    986960440108935861883449099987
    #                 615113531369940724079062641335
    # negative:       False
    # scale:          59
    # word 0:         940724079062641335
    # word 1:         99987615113531369
    # word 2:         440108935861883449
    # word 3:         986960
    # ----------------------------------------------
```

</details>

---

<details>
<summary><b>BigInt — arbitrary-precision signed integers</b></summary>

A quick tour of the main methods of the `BigInt` (`BInt`) type.

```mojo
from decimo.prelude import *


def main() raises:
    # === Construction ===
    var a = BigInt("12345678901234567890")  # From string
    var b = BigInt(12345)  # From integer
    var c = BInt("1991_10,18")  # From string with separators and spaces
    print(a, b, c)

    # === Basic Arithmetic ===
    print(a + b)  # Addition: 12345678901234580235
    print(a - b)  # Subtraction: 12345678901234555545
    print(a * b)  # Multiplication: 152407406035740740602050

    # === Division Operations ===
    print(a // b)  # Floor division: 1000054994024671
    print(a.truncate_divide(b))  # Truncate division: 1000054994024671
    print(a % b)  # Modulo: 4395

    # === Power Operation ===
    print(BigInt(2).power(10))  # Power: 1024
    print(BigInt(2) ** 10)  # Power (using ** operator): 1024

    # === Comparison ===
    print(a > b)  # Greater than: True
    print(a == BigInt("12345678901234567890"))  # Equality: True
    print(a.is_zero())  # Check for zero: False

    # === Type Conversions ===
    print(String(a))  # To string: "12345678901234567890"

    # === Sign Handling ===
    print(-a)  # Negation: -12345678901234567890
    print(
        abs(BigInt("-12345678901234567890"))
    )  # Absolute value: 12345678901234567890
    print(a.is_negative())  # Check if negative: False

    # === Extremely large numbers ===
    # 3600 digits // 1800 digits
    print(BigInt("123456789" * 400) // BigInt("987654321" * 200))

    # === Greatest common divisor ===
    print(a.gcd(b))  # Greatest common divisor: 15
    print(a.gcd(c))  # Greatest common divisor: 6
```

</details>

---

<details>
<summary><b>Decimal128 — a fixed 128-bit decimal</b></summary>

A quick tour of the main methods of the `Decimal128` (`Dec128`) type.

```mojo
from decimo.prelude import *


def main() raises:
    # === Construction ===
    # Decimal128 and Dec128 are aliases
    var a = Decimal128("123.45")  # From string
    var b = Decimal128(123)  # From integer
    var c = Dec128(123, 2)  # Integer with scale (1.23)
    var d = Dec128.from_float_scalar(3.14159)  # From floating-point

    # === Basic Arithmetic ===
    print(a + b)  # Addition: 246.45
    print(a - b)  # Subtraction: 0.45
    print(a * b)  # Multiplication: 15184.35
    print(a / b)  # Division: 1.0036585365853658536585365854

    # === Rounding & Precision ===
    print(a.round(1))  # Round to 1 decimal place, half to even: 123.4
    print(a.quantize(Dec128("0.01")))  # Format to 2 decimal places: 123.45
    print(a.round(0, RoundingMode.ROUND_DOWN))  # Round down to integer: 123

    # === Comparison ===
    print(a > b)  # Greater than: True
    print(a == Dec128("123.45"))  # Equality: True
    print(a.is_zero())  # Check for zero: False
    print(Dec128("0").is_zero())  # Check for zero: True

    # === Type Conversions ===
    print(Float64(a))  # To float: 123.45
    print(a.to_int())  # To integer: 123
    print(a.to_string())  # To string: "123.45"
    print(a.coefficient())  # Get coefficient: 12345
    print(a.scale())  # Get scale: 2

    # === Mathematical Functions ===
    print(Dec128("2").sqrt())  # Square root: 1.4142135623730950488016887242
    print(Dec128("100").root(3))  # Cube root: 4.641588833612778892410076351
    print(Dec128("2.71828").ln())  # Natural log: 0.9999993273472820031578910056
    print(Dec128("10").log10())  # Base-10 log: 1
    print(
        Dec128("16").log(Dec128("2"))
    )  # Log base 2: 3.9999999999999999999999999999
    print(Dec128("10").exp())  # e^10: 22026.465794806716516957900645
    print(Dec128("2").power(10))  # Power: 1024

    # === Sign Handling ===
    print(-a)  # Negation: -123.45
    print(abs(Dec128("-123.45")))  # Absolute value: 123.45
    print(Dec128("123.45").is_negative())  # Check if negative: False

    # === Special Values ===
    print(Dec128.PI())  # π constant: 3.1415926535897932384626433833
    print(Dec128.E())  # e constant: 2.7182818284590452353602874714
    print(Dec128.ONE())  # Value 1: 1
    print(Dec128.ZERO())  # Value 0: 0
    print(Dec128.MAX())  # Maximum value: 79228162514264337593543950335

    # === Convenience Methods ===
    print(Dec128("123.400").is_integer())  # Check if integer: False
    print(a.number_of_significant_digits())  # Count significant digits: 5
    print(
        Dec128("12.34").to_scientific_string()
    )  # Scientific notation: 1.234E+1
```

</details>

---

### CLI quick start

For an interactive session, just type `decimo`:

![Decimo REPL](https://raw.githubusercontent.com/forfudan/forfudan-github-data/main/decimo/repl.webp)  
*A real session: `ans`, the `:` settings system, and inline settings*

```sh
$ decimo
Decimo — an arbitrary-precision calculator 🔥
Type ? for help, : for settings, :q to quit.
Precision: 50. Rounding: ROUND_HALF_EVEN.
decimo> 2 ^ 10
1024
decimo> ans / 4
256
decimo> 1/7
0.14285714285714285714285714285714285714285714285714
decimo> :100
Current settings:
  Precision     : 100
  Scientific    : off
  Engineering   : off
  Pad           : off
  Delimiter     : (none)
  Rounding mode : ROUND_HALF_EVEN
decimo> pi
3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117068
decimo> sqrt(e) / ln(10) + sin(-1.23) :200 e he delimiter _
-226.458_251_870_114_348_807_514_569_584_297_293_353_150_959_525_480_515_507_901_779_719_167_225_208_528_825_475_488_261_072_148_336_432_171_617_635_953_314_758_797_226_777_458_915_435_649_950_836_584_843_137_886_028_274_720_793_979_517_570_004_978_334_405_953_342_64E-3
decimo> :q
```

The REPL keeps the last result in `ans`, lets you define variables
(`name = expr`), and exposes settings via `:`-prefixed commands (e.g. `:100` for
precision, `:s` for scientific, `:d` for ROUND_DOWN). Input is case-insensitive.
Quit with `:q`, `exit`, or Ctrl-D.

As an innovative feature, Decimo supports multiple settings in a single line.
They can either be global (persist across calculations) or local (apply only to
the current expression). In the example above, `:200 e he delimiter _` means
"evaluate the expression with precision 200 (`200`), scientific notation with
engineering exponent (`e`), round half to even (`he`), and use `_` as the digit
delimiter in the output (`delimiter _`)". The settings apply only to the current
expression and do not affect subsequent calculations.

For one-shot evaluation, pass an expression on the command line, pipe it via
stdin, or read from a file:

```bash
$ decimo "sqrt(2)" -P 30
1.41421356237309504880168872421

$ echo "1/3" | decimo -P 50
0.33333333333333333333333333333333333333333333333333

$ decimo -F expressions.dm -P 80
```

Useful flags: `-P N` (precision), `-R MODE` (rounding), `-S` / `-E` (scientific
/ engineering), `--pad`, `--delimiter`, `--completions {bash,zsh,fish}`. Run
`decimo --help` for the full list.

### Python quick start

Everything a `decimal` program normally touches is there, under the same names:

```python
from decimo import Decimal, Decimal128, getcontext, localcontext, ROUND_FLOOR

getcontext().prec = 28

# The operators, the context, and the methods, as in `decimal`.
Decimal("0.1") + Decimal("0.2")          # 0.3, exactly
Decimal(1) / Decimal(7)                  # to the context precision
Decimal("2.675").quantize(Decimal("0.01"))
divmod(Decimal(17), Decimal(5))          # (3, 2)

# A context you can compute in, without touching the global one.
with localcontext(prec=50):
    print(Decimal(2).sqrt())

# Three things `decimal` does not have.
import decimo
decimo.pi(1000)                          # Chudnovsky with binary splitting
decimo.e(50)
Decimal(2).sqrt(rounding=ROUND_FLOOR)    # and exp, ln, log10, correctly rounded

# The fixed-width type for money: 16 bytes that own nothing.
price = Decimal128("19.99")
(price * 3).quantize(Decimal128("0.01"))  # 59.97
```

A mixed expression settles in the wider type — `Decimal128 + Decimal` is a
`Decimal`, either way round — and the hashes of `Decimal`, `Decimal128`,
`int`, `float` and `decimal.Decimal` all agree, so the five are
interchangeable as dictionary keys.

What decimo refuses rather than answering differently: NaN and infinity,
`ROUND_05UP`, signals and traps, and one context per process rather than per
thread. The full list, with the reasoning, is in
[python/README.md](./python/README.md).

## Objective

Financial calculations and data analysis require precise decimal arithmetic that
floating-point numbers cannot reliably provide. As someone working in finance
and credit risk model validation, I needed a dependable correctly-rounded,
fixed-precision numeric type when migrating my personal projects from Python to
Mojo.

Since Mojo currently lacks a native Decimal type in its standard library, I
decided to create my own implementation to fill that gap.

This project draws inspiration from several established decimal implementations
and documentation, e.g.,
[Python built-in `Decimal` type](https://docs.python.org/3/library/decimal.html),
[Rust `rust_decimal` crate](https://docs.rs/rust_decimal/latest/rust_decimal/index.html),
[Microsoft's `Decimal` implementation](https://learn.microsoft.com/en-us/dotnet/api/system.decimal.getbits?view=net-9.0&redirectedfrom=MSDN#System_Decimal_GetBits_System_Decimal_),
[General Decimal Arithmetic Specification](https://speleotrove.com/decimal/decarith.html),
etc. Many thanks to these predecessors for their contributions and their
commitment to open knowledge sharing.

## Status

Rome wasn't built in a day. Decimo is currently under active development. It has
successfully progressed through the **"make it work"** phase and the
**"make it right"**, and is now well into the **"make it fast"** phase.

The `BigInt` type is fully implemented and optimized. It is measured against
GMP, timed in C, rather than against CPython's `int`, which is reached through
the interpreter and so loses on call overhead before the arithmetic starts.

Bug reports and feature requests are welcome! If you encounter issues, please
[file them here](https://github.com/forfudan/decimo/issues).

## Project structure

<details>
<summary><b>The source tree</b></summary>

```text
decimo/
├── src/                          # All source code
│   ├── decimo/                   # Core library (mojo pre-compiled package)
│   │   ├── bigdecimal/           #   Arbitrary-precision decimal (Decimal)
│   │   ├── bigint/               #   Arbitrary-precision signed integer (BigInt)
│   │   ├── bigint10/             #   Base-10 signed integer (BigInt10)
│   │   ├── biguint/              #   Base-10 unsigned integer (BigUInt)
│   │   ├── bigfloat/             #   Arbitrary-precision binary float (MPFR)
│   │   ├── rational/             #   Exact rational number (Rational)
│   │   ├── decimal128/           #   128-bit fixed-precision decimal (Dec128)
│   │   ├── expression/           #   Expression engine behind `decimo.eval()`
│   │   │   ├── tokenizer.mojo    #     Lexer: expression → tokens
│   │   │   ├── parser.mojo       #     Shunting-yard: infix → RPN
│   │   │   └── evaluator.mojo    #     RPN evaluator using Decimal
│   │   ├── numerals/             #   Numeral systems (e.g. Chinese numerals)
│   │   ├── toml/                 #   TOML parser (decimo.toml)
│   │   └── ...                   #   Shared utilities (str, errors, rounding)
│   └── cli/                      # CLI calculator application
│       ├── main.mojo             #   Entry point (ArgMojo CLI)
│       ├── limo/                 #   Line editor used by the REPL
│       └── calculator/           #   Presentation layer (display, io, repl, settings)
├── python/                       # The library packaged for Python (PyPI: decimo)
│   ├── decimo_module.mojo        #   The Python extension, written in Mojo
│   ├── src/decimo/               #   The `decimo` Python package around it
│   └── tests/                    #   Checked against the standard library's `decimal`
├── tests/                        # Unit tests (one subfolder per module)
│   ├── bigdecimal/
│   ├── bigint/
│   ├── biguint/
│   ├── decimal128/
│   ├── expression/               #   Expression engine tests
│   ├── numerals/                 #   Numeral system tests
│   ├── cli/                      #   CLI calculator tests
│   └── toml/
├── benches/                      # Benchmarks (one subfolder per module)
├── docs/                         # Documentation and design notes
└── pixi.toml                     # Project configuration and tasks
```

`src/decimo/` is a Mojo package — it is compiled with `mojo precompile` and can
be imported by external projects. The expression engine (`decimo.expression`),
the numeral systems (`decimo.numerals`), and the TOML parser (`decimo.toml`) are
included as subpackages. `src/cli/` is an application that consumes the `decimo`
package and compiles to a standalone binary via `mojo build`. `python/` compiles
the same package into a CPython extension and wraps it in a Python package, and
is what `pip install decimo` fetches.

</details>

## Tests and benches

After cloning the repo onto your local disk, you can:

- Use `pixi run test` to run all tests, or `pixi run test <suite>` for one suite
  (`pixi run test --list` shows them).
- Use `pixi run testcli` to run CLI calculator tests.
- Use `pixi run testpy` to build the Python extension and run its tests against
  the standard library's `decimal`.
- Use `pixi run bench` to run benchmarks.
- Use `pixi run benchdoc` to regenerate [docs/benchmarks.md](docs/benchmarks.md)
  against libmpdec, GMP, CPython and MPFR. Needs `mpdecimal` and `gmp`
  installed for the C comparisons; the reference libraries for the `pi()` table
  live in the optional
  `benchdoc` environment (`pixi install -e benchdoc`).
- Use `pixi run buildcli` to compile the CLI calculator to a `./decimo` binary.
- Use `pixi run organize_imports` to group, sort and de-duplicate the imports
  in every `.mojo` file: four blocks separated by a blank line — the Mojo
  standard library, third-party packages, `decimo` itself, and modules reached
  through `-I`. `--check` is what the pre-commit hook runs. A file whose import
  block holds a comment is left alone and named as skipped;
  `scripts/organize_mojo_imports.py`'s docstring says why, and why
  `--remove-unused` is opt-in.
- Use `pixi run check_import_fixed_point` after changing the organizer or the
  Mojo version: it asserts that the organizer and `mojo format` do not undo
  each other's work.

## Citation

If you find Decimo useful, consider listing it in your citations.

```tex
@software{Zhu.2026,
    author       = {Zhu, Yuhao},
    year         = {2026},
    title        = {Decimo: An arbitrary-precision integer and decimal library for Mojo},
    url          = {https://github.com/forfudan/decimo},
    version      = {0.14.0},
    note         = {Computer Software}
}
```

## License

This repository and its contributions are licensed under the Apache License
v2.0.

The `BigFloat` type optionally uses the
[GNU MPFR Library](https://www.mpfr.org/) (LGPLv3+) and
[GMP](https://gmplib.org/) (LGPLv3+ or GPLv2+) at runtime. Decimo does not
include or distribute any MPFR/GMP source code or binaries — they are loaded via
`dlopen` only if the user has independently installed them. All other Decimo
types work without any external dependencies. See the [NOTICE](./NOTICE) file
for details.

[^fixed]: The `Dec128` type can represent values with up to 29 significant
    digits and a maximum of 28 digits after the decimal point. When a
    value exceeds the maximum representable value (`2^96 - 1`), Decimo
    either raises an error or rounds the value to fit within these
    constraints. For example, the significant digits of
    `8.8888888888888888888888888888` (29 eights total with 28 after the
    decimal point) exceeds the maximum representable value (`2^96 - 1`)
    and is automatically rounded to `8.888888888888888888888888889` (28
    eights total with 27 after the decimal point). Decimo's `Dec128` type
    is similar to `System.Decimal` (C#/.NET), `rust_decimal` in Rust,
    `DECIMAL/NUMERIC` in SQL Server, etc.
[^bigint]: The `BigInt` implementation uses a base-2^64 representation with a
    little-endian format, where the least significant word is stored at
    index 0. Each word is a `UInt64`, allowing for efficient storage and
    arithmetic operations on large integers. This design choice optimizes
    performance for binary computations while still supporting arbitrary
    precision.
[^auxiliary]: The auxiliary types include a base-10 arbitrary-precision signed
    integer type (`BigInt10`) and a base-10 arbitrary-precision
    unsigned integer type (`BigUInt`) supporting unlimited
    digits[^bigint10]. `BigUInt` is used as the internal
    representation for `BigInt10` and `Decimal`.
[^bigint10]: The BigInt10 implementation uses a base-10 representation for users
    (maintaining decimal semantics), while internally using an
    optimized base-10^18 storage system for efficient calculations. This
    approach balances human-readable decimal operations with
    high-performance computing. It provides both floor division (round
    toward negative infinity) and truncate division (round toward zero)
    semantics, enabling precise handling of division operations with
    correct mathematical behavior regardless of operand signs.
[^arbitrary]: Built on the `BigUInt` implementation, Decimal
    supports arbitrary precision for both the integer and fractional
    parts, similar to `decimal` and `mpmath` in Python,
    `java.math.BigDecimal` in Java, etc.
