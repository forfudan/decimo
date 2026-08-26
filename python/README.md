# decimo

**A drop-in replacement for Python's `decimal`, written in
[Mojo](https://www.modular.com/mojo).**

[![PyPI](https://img.shields.io/pypi/v/decimo)](https://pypi.org/project/decimo/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](https://github.com/forfudan/decimo/blob/main/LICENSE)

> ⚠️ **Development release.** The API is settled enough to use, but the
> version numbers are timestamps and the wheels are macOS arm64 only for now.

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

| Program                       |   decimo |  decimal |                 |
| ----------------------------- | -------: | -------: | --------------- |
| compound interest, 150 years  | 16.8 µs  | 14.5 µs  | 1.16× slower    |
| e from its series, 500 digits | 199.5 µs | 177.3 µs | 1.13× slower    |
| sqrt by Newton, 1000 digits   | 234.7 µs | 232.3 µs | about the same  |
| pi by Machin, 500 digits      | 722.0 µs | 547.1 µs | 1.32× slower    |
| parse and print, 1000 digits  | 3.21 µs  | 2.75 µs  | 1.17× slower    |
| arithmetic at 1000 digits     | 3.96 µs  | 5.85 µs  | **1.48× faster** |

Operation by operation at the default precision of 28 digits, in nanoseconds:

| | decimo | decimal | |
| --- | ---: | ---: | --- |
| `a + b`    |  53.7 | 41.7 | 1.29× slower |
| `a * b`    |  59.7 | 48.8 | 1.22× slower |
| `a / b`    | 143.1 | 101.0 | 1.42× slower |
| `a < b`    |  22.6 | 18.1 | 1.25× slower |
| `a + 2`    |  63.4 | 63.4 | the same |
| `quantize` |  47.3 | 60.6 | **1.28× faster** |

The short version: **decimo is faster on large numbers and a little slower on
small ones.** CPython's `decimal` is a mature C library that keeps a 28-digit
coefficient inside the object and never calls the allocator for it; decimo
works in base 10^9 where libmpdec uses base 10^19, so it handles twice as many
words for the same value. Neither of those goes away, and neither matters once
the numbers are big enough for the arithmetic to dominate the call.

The Mojo library underneath is further ahead -- measured against libmpdec
directly, without either interpreter in the way, it is faster at every
operation at 1000 digits and 3.2× faster at multiplication. See
[the benchmarks](https://github.com/forfudan/decimo/blob/main/docs/benchmarks.md).

## What works

Everything a `decimal` program normally touches:

- all the operators, including `//`, `%`, `divmod()` and `**`
- `getcontext().prec`, `setcontext()` and `localcontext()`
- `int()`, `float()`, `round()`, `math.floor/ceil/trunc`, `hash()`, `format()`
- `quantize`, `normalize`, `as_tuple`, `as_integer_ratio`, `compare`, `fma`,
  `sqrt`, `exp`, `ln`, `log10`, `scaleb`, `adjusted`, `copy_abs`,
  `copy_negate`, `copy_sign`, `same_quantum`, `to_eng_string`, `max`, `min`
- the same coercion rules: `int` converts in arithmetic, `float` does not, and
  both convert in a comparison
- `copy`, `deepcopy` and `pickle`
- `ZeroDivisionError` where you expect it, and hashes that agree with `int`,
  `float` and `decimal.Decimal`

## What does not

decimo refuses these rather than answering differently:

- **NaN and infinity.** decimo has no non-finite values. `is_nan()` and
  `is_infinite()` are always `False`.
- **Rounding modes other than `ROUND_HALF_EVEN`.** Setting
  `getcontext().rounding` to anything else raises `NotImplementedError`.
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

Wheels are built for macOS arm64. On anything else, build from source with
[pixi](https://pixi.sh):

```bash
git clone https://github.com/forfudan/decimo && cd decimo
pixi run buildpy
pip install -e python/
```

## Links

- **GitHub**: <https://github.com/forfudan/decimo>
- **Benchmarks**:
  <https://github.com/forfudan/decimo/blob/main/docs/benchmarks.md>
- **Changelog**:
  <https://github.com/forfudan/decimo/blob/main/docs/changelog.md>
- **Mojo library docs**:
  <https://github.com/forfudan/decimo/blob/main/docs/api.md>
