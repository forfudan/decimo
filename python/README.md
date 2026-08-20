# decimo

**Arbitrary-precision decimal and integer arithmetic for Python, powered by
Mojo.**

[![PyPI](https://img.shields.io/pypi/v/decimo)](https://pypi.org/project/decimo/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](https://github.com/forfudan/decimo/blob/main/LICENSE)

> ⚠️ **Pre-Alpha / Placeholder release.**  
> The Python bindings are under active development. A proper installable wheel
> is coming soon.  
> Full Mojo library is already available — see the
> [main repository](https://github.com/forfudan/decimo).

---

## What is decimo?

`decimo` is an arbitrary-precision decimal and integer library, originally
written in [Mojo](https://www.modular.com/mojo).  
This package exposes `decimo`'s `Decimal` type to Python via a Mojo-built
CPython extension module (`_decimo.so`), with a thin Python wrapper providing
full Pythonic operator support.

```python
from decimo import Decimal

a = Decimal("1.234567890123456789012345678901234567890")
b = Decimal("9.876543210987654321098765432109876543210")

print(a + b)  # 11.111111101111111110111111111111111111100
print(a * b)  # 12.193263111263526900...
print(a / b)  # 0.12499999...
```

## Status

| Feature                                   | Status        |
| ----------------------------------------- | ------------- |
| `Decimal` arithmetic (`+`, `-`, `*`, `/`) | ✓ Working     |
| Comparison operators                      | ✓ Working     |
| Unary `-`, `abs()`, `bool()`              | ✓ Working     |
| Pre-built wheels on PyPI                  | ? Coming soon |
| `BigInt` / `Decimal128` Python bindings   | ? Planned     |

## Building from source

The extension requires [Mojo](https://docs.modular.com/mojo/manual/get-started/)
and [pixi](https://pixi.sh):

```bash
git clone https://github.com/forfudan/decimo
cd decimo
pixi run buildpy
# .so is built at python/src/decimo/_decimo.so
```

Then install in editable mode:

```bash
pip install -e python/
```

## Links

- **GitHub**: <https://github.com/forfudan/decimo>
- **Changelog**:
  <https://github.com/forfudan/decimo/blob/main/docs/changelog.md>
- **Mojo library docs**:
  <https://github.com/forfudan/decimo/blob/main/docs/api.md>
