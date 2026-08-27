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

| Program                       |   decimo |  decimal |                  |
| ----------------------------- | -------: | -------: | ---------------- |
| compound interest, 150 years  | 13.0 µs  | 14.5 µs  | **1.12× faster** |
| sqrt by Newton, 1000 digits   | 233.8 µs | 232.1 µs | about the same   |
| e from its series, 500 digits | 199.1 µs | 170.3 µs | 1.17× slower     |
| pi by Machin, 500 digits      | 719.2 µs | 554.3 µs | 1.30× slower     |
| parse and print, 1000 digits  | 3.34 µs  | 2.71 µs  | 1.23× slower     |
| arithmetic at 1000 digits     | 3.67 µs  | 5.83 µs  | **1.59× faster** |

Operation by operation, in nanoseconds. At 9 digits:

| | decimo | decimal | |
| --- | ---: | ---: | --- |
| `a + b` | 36.8 | 34.7 | 1.06× slower |
| `a - b` | 41.4 | 35.5 | 1.17× slower |
| `a * b` | 36.3 | 33.4 | 1.09× slower |
| `a / b` | 71.0 | 57.1 | 1.24× slower |

and at the default precision of 28:

| | decimo | decimal | |
| --- | ---: | ---: | --- |
| `a + b`    |  45.8 |  42.7 | 1.07× slower |
| `a * b`    |  52.8 |  47.3 | 1.12× slower |
| `a / b`    | 138.8 | 100.3 | 1.38× slower |
| `a < b`    |  21.9 |  18.8 | 1.16× slower |
| `a + 2`    |  57.2 |  65.6 | **1.15× faster** |
| `quantize` |  42.6 |  61.8 | **1.45× faster** |

So: within about 10% on addition and multiplication, ahead on
`Decimal + int` and `quantize`, and behind on division by roughly a third.

**decimo is faster once the numbers are large, and close on small ones.**
Two things are structural. CPython's `decimal` keeps a 28-digit coefficient
inside the object and never calls the allocator for it. And it works in base
10^19 where decimo works in base 10^9, so decimo handles twice as many words
for the same value -- which is most of what is left in division.

The Mojo library underneath is further ahead, because it does not pay for the
Python call. Measured against libmpdec directly, decimo is faster at **every**
operation at 1000 digits, and at 9 digits it is 3.4× faster at addition, 3.5×
at multiplication and 4× at rounding. See
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
