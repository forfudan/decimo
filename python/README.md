# decimo

**A drop-in replacement for Python's `decimal`, written in
[Mojo](https://www.modular.com/mojo).**

[![PyPI](https://img.shields.io/pypi/v/decimo)](https://pypi.org/project/decimo/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](https://github.com/forfudan/decimo/blob/main/LICENSE)

> ⚠️ **Development release.** The API is settled enough to use, but the
> version numbers are timestamps. Wheels: Linux x86_64 and macOS arm64
> (14 and later), CPython 3.13 and 3.14.

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
  `ROUND_FLOOR`, exact under every operation
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
- **`ROUND_05UP`.** Nothing implements it; setting it raises
  `NotImplementedError`.
- **`sqrt`, `exp`, `ln`, `log10` and `**` under a rounding mode other than
  `ROUND_HALF_EVEN`** are computed nine digits wider and rounded once more.
  The last digit can differ from `decimal` when the true value lies within
  `10^-9` relative of a rounding boundary. Arithmetic, `quantize` and
  `round()` are exact under every mode.
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

Wheels are built for Linux x86_64 and macOS arm64 (macOS 14 and later), for
CPython 3.13 and 3.14. On anything else, build from source with
[pixi](https://pixi.sh):

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
