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

## Should you use it?

Honestly: **only if your numbers are large.** Here is the same benchmark file
run against both libraries — `python/benchmarks/compare.py` in the repository,
which imports one or the other and runs identical code.

| Program                     |    decimo |   decimal |              |
| --------------------------- | --------: | --------: | ------------ |
| add/sub/mul/div, 28 digits  |    347 ns |     73 ns | 4.8× slower  |
| add/sub/mul/div, 200 digits |    593 ns |    385 ns | 1.5× slower  |
| add/sub/mul/div, 1000 digits|   4.75 µs |   5.85 µs | **1.2× faster** |
| compound interest, 150 years|  54.96 µs |  13.83 µs | 4.0× slower  |
| e from its series, 500 digits| 364.7 µs |  171.2 µs | 2.1× slower  |
| sqrt by Newton, 1000 digits |  266.8 µs |  237.6 µs | 1.1× slower  |
| parse and print, 1000 digits|   3.03 µs |   2.91 µs | about equal  |

CPython's `decimal` is a mature C library with a fast path for small values,
and at the default precision of 28 digits it is hard to beat from an extension
module. decimo's per-call overhead is about 110 ns, which is most of the cost
of a small operation and almost none of the cost of a large one. That overhead
is the thing being worked on next.

The Mojo library underneath is a different story — measured against libmpdec
directly, without either interpreter in the way, decimo is faster at every
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
