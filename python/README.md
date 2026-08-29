# decimo

**A drop-in replacement for Python's `decimal`, written in
[Mojo](https://www.modular.com/mojo).**

[![PyPI](https://img.shields.io/pypi/v/decimo)](https://pypi.org/project/decimo/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](https://github.com/forfudan/decimo/blob/main/LICENSE)

> ⚠️ **Development release.** The API is settled enough to use, but the
> versions carry a timestamp: `0.14.0.devYYYYMMDDHHMMSS`, where `0.14.0` is
> the version of the Mojo library the wheel packages. Wheels: macOS arm64
> (11 and later), CPython 3.13 and 3.14. Everywhere else, build from source.

Change one import and your program keeps working:

```python
# from decimal import Decimal, getcontext
from decimo import Decimal, getcontext

getcontext().prec = 50
print(Decimal(1) / Decimal(7))
# 0.14285714285714285714285714285714285714285714285714
```

The two libraries agree digit for digit. The test suite checks every
operation against the standard library rather than against a table of
expected strings, so "agrees with `decimal`" is a property that is measured,
not a claim.

## How fast is it?

The same benchmark file run against both libraries -- `python/benchmarks/compare.py`
in the repository, which imports one or the other and runs identical code.
Best of five, on an Apple M-series laptop:

| Program                         |    decimo |   decimal |                  |
| ------------------------------- | --------: | --------: | ---------------- |
| add/sub/mul/div, 28 digits      |   90.6 ns |   73.0 ns | 1.24× slower     |
| add/sub/mul/div, 200 digits     |  331.8 ns |  409.0 ns | **1.23× faster** |
| add/sub/mul/div, 1000 digits    |   2.02 µs |   5.89 µs | **2.91× faster** |
| compound interest, 150 years    |  12.71 µs |  13.08 µs | about the same   |
| e from its series, 500 digits   | 197.92 µs | 162.75 µs | 1.22× slower     |
| sqrt by Newton, 1000 digits     | 143.29 µs | 232.29 µs | **1.62× faster** |
| pi by Machin, 500 digits        | 620.12 µs | 520.17 µs | 1.19× slower     |
| parse and print, 1000 digits    |   3.28 µs |   2.60 µs | 1.26× slower     |

**decimo is faster once the numbers are large, and 20-25% behind on small
ones.** The small-number gap is not the arithmetic: measured against
libmpdec directly, without an interpreter in the way, decimo is 2-4× faster
at 9 digits and faster at every operation at 1000 digits. What is left is the
cost of the Python call itself -- building the result object and converting
the operands -- which CPython's `decimal` has had thirty years to shave. See
[the benchmarks](https://github.com/forfudan/decimo/blob/main/docs/benchmarks.md).

## What works

Everything a `decimal` program normally touches:

- all the operators, including `//`, `%`, `divmod()` and `**`
- `getcontext().prec` and `getcontext().rounding`, `setcontext()`,
  `localcontext()` (with keyword overrides), `Context` objects
- all the rounding modes: `ROUND_HALF_EVEN`, `ROUND_HALF_UP`,
  `ROUND_HALF_DOWN`, `ROUND_DOWN`, `ROUND_UP`, `ROUND_CEILING`,
  `ROUND_FLOOR`, exact for arithmetic, `quantize`, `round()` and
  `to_integral_value()`
- `int()`, `float()`, `round()`, `math.floor/ceil/trunc`, `hash()`, `format()`
- `Context` you can compute with: `ctx.divide(x, y)`, `ctx.sqrt(x)`,
  `ctx.quantize(x, y)` and the rest, none of them touching the current
  context
- keyword arguments where `decimal` takes them: `quantize(exp,
  rounding=ROUND_HALF_UP)`, `to_integral_value(rounding=...)`,
  `sqrt(context=...)`
- `Decimal((sign, digits, exponent))`, so `as_tuple()` round-trips
- `pow(x, y, modulus)`, by modular exponentiation
- `quantize`, `normalize`, `as_tuple`, `as_integer_ratio`, `compare`, `fma`,
  `sqrt`, `exp`, `ln`, `log10`, `scaleb`, `adjusted`, `copy_abs`,
  `copy_negate`, `copy_sign`, `same_quantum`, `to_eng_string`, `max`, `min`
- the rest of the specification's surface: `remainder_near`, `next_plus`,
  `next_minus`, `next_toward`, `shift`, `rotate`, `logical_and`,
  `logical_or`, `logical_xor`, `logical_invert`, `logb`, `compare_total`,
  `compare_total_mag`, `compare_signal`, `max_mag`, `min_mag`,
  `number_class`, `to_integral_exact`, `is_normal`, `is_subnormal`,
  `from_number`
- the same coercion rules: `int` converts in arithmetic, `float` does not, and
  both convert in a comparison
- `copy`, `deepcopy` and `pickle`
- `ZeroDivisionError` where you expect it, and hashes that agree with `int`,
  `float` and `decimal.Decimal`

### Three things `decimal` does not have

```python
decimo.pi(1000)   # 1000 digits of pi, by Chudnovsky with binary splitting
decimo.e(50)      # 50 digits of e
Decimal(2).sqrt(rounding=ROUND_FLOOR)   # and exp, ln, log10 too
```

`pi()` and `e()` use the context precision when given no argument; `decimal`
has neither, and its documentation gives a recipe to write your own.

`rounding=` on `sqrt`, `exp`, `ln` and `log10` is decimo's own: `decimal`
ignores the context mode for these and always rounds half to even. And the
answer under any mode is **decided rather than approximated**. The library
computes wider than you asked, takes the interval its own error bound allows,
and checks that the whole of it rounds to one answer; if a boundary falls
inside, it widens and looks again. The same check now guards the default half
to even, where before the last digit was assumed rather than known -- so
`ROUND_FLOOR` really does stay under the true value, and a tie really is a
tie.

### A second type for money

`Decimal` is arbitrary precision and is what a program reaching for
`decimal.Decimal` wants. `Decimal128` is the other one: 96 bits of
coefficient and a scale from 0 to 28, in sixteen bytes that own nothing --
the layout .NET's `System.Decimal` and Rust's `rust_decimal` use.

```python
from decimo import Decimal128        # Dec128 is the same type

price = Decimal128("19.99")
line = (price * 3).quantize(Decimal128("0.01"))     # 59.97
Decimal128(2).sqrt()                                # and exp, ln, log10, sin, cos, tan
Decimal128("1").to_ieee754()                        # the IEEE 754 interchange bytes
```

It arithmetics, compares, hashes and rounds like `Decimal`, mixes with `int`,
`float` and `str` on either side of an operator, and converts both ways
(`Decimal128(x).to_decimal()`, `Decimal(x)`). Its results never allocate, so
it is quicker where the values are money and the shape of them is known:

| | `Decimal128` | `Decimal` | `decimal` |
| --- | ---: | ---: | ---: |
| `a + b` | **46 ns** | 67 | 73 |
| `a * b` | **57 ns** | 92 | 85 |
| `a / b` | **114 ns** | 225 | 133 |
| from text | **116 ns** | 160 | 136 |
| `str(x)` | 118 ns | 437 | **67** |
| an invoice | **633 ns** | 713 | 705 |

`str` is the one that is slower.

A mixed expression settles in the wider type: `Decimal128(x) + Decimal(y)` is
a `Decimal`, either way round, because widening loses nothing.

What it does not do: it stops at `7.9E+28` and 28 decimal places and raises
rather than rounding into a context, it has no `Context` of its own beyond
the rounding mode, and its scale is never negative -- `Decimal128("1.23E+5")`
is `123000`, where `decimal` keeps a coefficient of 123 with an exponent of 3
and can print it as `123E+3`. `Decimal128(0.1)` is `0.1` rather than the whole
binary expansion, since 55 digits do not fit 28; what is promised is that
`float(Decimal128(x)) == x`.

## What does not

decimo refuses these rather than answering differently:

- **NaN and infinity.** decimo has no non-finite values. `is_nan()` and
  `is_infinite()` are always `False`.
- **`ROUND_05UP`.** Nothing implements it; setting it raises
  `NotImplementedError`.
- **`sqrt`, `exp`, `ln` and `log10` ignore the context rounding**, as they do
  in `decimal`, and round half to even unless you pass `rounding=`. `**`
  follows the context, also as in `decimal`. All of them are correctly
  rounded whichever mode applies, as are arithmetic, `quantize` and
  `round()`.
- **`//`, `%`, `divmod()` and `remainder_near` with a long quotient.**
  `decimal` raises `InvalidOperation` when the integer quotient has more
  digits than the precision; decimo answers. The remainder is rounded to the
  context, as in `decimal`.
- **`Emin` only reaches four methods.** Exponents are unbounded, so `Emin`
  changes nothing except what `next_plus(0)`, `next_minus(0)`,
  `is_subnormal()` and `number_class()` say, where `decimal`'s answers need
  a smallest exponent.
- **Signals and traps.** `Context.flags` and `Context.traps` exist and stay
  empty. `Inexact`, `Rounded` and the rest are importable but never raised.
- **`Emin` / `Emax`.** Exponents are unbounded, so nothing ever underflows to
  zero or overflows to infinity. A loop that waits for a term to become
  exactly zero will not stop; wait for the sum to stop changing instead.
- **One context per process, not per thread.**

`DivisionByZero` and `InvalidOperation` are aliases for `ZeroDivisionError`
and `ValueError`, which is what decimo actually raises, so `except` clauses
written against `decimal` still catch.

## Installing

```bash
pip install decimo
```

Wheels are built for macOS arm64 (macOS 11 and later), for CPython 3.13 and
3.14. On anything else -- Linux included, until its build is verified --
build from source with [pixi](https://pixi.sh):

```bash
git clone https://github.com/forfudan/decimo && cd decimo
pixi run -e py314 release        # or py313; the wheel lands in python/dist/
pip install python/dist/*.whl
```

## Links

- **GitHub**: <https://github.com/forfudan/decimo>
- **Benchmarks**:
  <https://github.com/forfudan/decimo/blob/main/docs/benchmarks.md>
- **Changelog**:
  <https://github.com/forfudan/decimo/blob/main/docs/changelog.md>
- **Mojo library docs**:
  <https://github.com/forfudan/decimo/blob/main/docs/api.md>
