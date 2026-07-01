# mojo4py: Exposing decimo to Python via Mojo Bindings

> Initial date of planning: 2026-03-02
>
> I use "mojo4py" as the name of this document - it refers to a package *written in Mojo* that is callable *from Python*. The inverse ("py4mojo") would be calling Python from Mojo, which decimo already does in some places.
>
> This name is pretty concise and descriptive. I will use the same "mojo4py" for Mojo Miji when discussing the Mojo-Python inter-operability.

---

## 1. Summary

Modular has introduced a beta mechanism that allows Mojo code to be exposed as a standard CPython extension module (`.so` / `.dylib`). This means a Python user can write `import decimo` and get access to Mojo-native `Decimal128`, `BigDecimal`, `BigInt`, and `BigUint` types at near-native speed, without rewriting anything in Python.

**Feasibility verdict: Possible but non-trivial.** The main (no surprise) blocker is that decimo is a *packaged* Mojo library (`.mojoc`), not a single `.mojo` file. The Mojo importer hook (the easy dev-time path) does not support custom import paths for non-stdlib Mojo packages. The `.so` build path (the distribution path) works fine. This means the developer workflow is slightly more manual, but distribution is fully viable.

---

## 2. How the Mechanism Works (State of the Art)

### 2.1 The Two Paths

| Path                   | How                                                                                                               | When to Use                                   |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| **Source import hook** | `import mojo.importer` in Python, then `import mojo_module` (auto-compiles `.mojo` → `.so` into `__mojocache__/`) | Dev prototyping with single-file modules only |
| **Pre-built `.so`**    | `mojo build mojo_module.mojo --emit shared-lib -o mojo_module.so`                                                 | Production, packages with dependencies, CI/CD |

For decimo, **only the pre-built `.so` path is viable** because the binding code will `import decimo` (the `.mojoc`), and the importer hook cannot resolve that path.

### 2.2 The Binding Pattern

Every exposed module needs a `PyInit_<module_name>()` entry point:

```mojo
from python import PythonObject
from python.bindings import PythonModuleBuilder
from os import abort

@export
def PyInit_decimo() -> PythonObject:
    try:
        var m = PythonModuleBuilder("decimo")
        m.def_function[some_fn]("some_fn", docstring="...")
        _ = m.add_type[BigDecimal]("BigDecimal")
              .def_py_init[BigDecimal.py_init]()
              .def_method[BigDecimal.py_add]("__add__")
              # ...etc
        return m.finalize()
    except e:
        abort(String("error creating decimo Python module: ", e))
```

### 2.3 Type Binding Requirements

For a Mojo struct to be bindable:

| Feature                       | Required Trait                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------- |
| Bind the type at all          | `Representable`                                                                 |
| Custom `__init__` from Python | `Movable` + `def_py_init`                                                       |
| Default (no-arg) `__init__`   | `Defaultable + Movable` + `def_init_defaultable`                                |
| Methods                       | `@staticmethod` with `py_self: PythonObject` or `self_ptr: UnsafePointer[Self]` |
| Static methods                | `@staticmethod` with normal `PythonObject` args                                 |
| Return Mojo value to Python   | `PythonObject(alloc=value^)` (type must be registered first)                    |
| Accept Mojo value from Python | `py_obj.downcast_value_ptr[T]()`                                                |

### 2.4 Known Limitations (as of MAX 26.1)

These are hard constraints today, expected to improve over time:

1. **Max 6 `PythonObject` arguments** per bound function (use `def_py_function` workaround for variadic).
2. **No keyword-only arguments** (`def foo(*, x: Int)` is unsupported).
3. **No native `*args`/`**kwargs`** syntax — must use `OwnedKwargsDict[PythonObject]` and `def_py_function` respectively.
4. **No computed properties** (getter/setter via `@property`).
5. **Non-stdlib Mojo package deps** are not resolvable by the importer hook — must build manually.
6. **Many stdlib types** do not yet implement `ConvertibleFromPython`, requiring manual conversion boilerplate.
7. **Methods must use non-standard self** (`py_self: PythonObject` or `UnsafePointer[Self]`) instead of normal `self`.
8. This is **Beta** — API will change. Do not stabilize the Python API until Modular marks this stable.

---

## 3. Impact Analysis for decimo Types

### 3.1 `BigDecimal` ★ Primary target

- Arbitrary precision decimal — the most compelling type to expose to Python, directly competing with (and outperforming) Python's `decimal.Decimal`.
- Key operations to expose: `__init__`, `__add__`, `__sub__`, `__mul__`, `__truediv__`, `__mod__`, `__pow__`, `__neg__`, `__abs__`, `__repr__`, `__str__`, `__eq__`, `__lt__`, `__le__`, `__gt__`, `__ge__`, `sqrt`, `exp`, `ln`, `log10`, `round`.
- Constructors from Python `int`, `float`, `str` need manual dispatch in `py_init`.
- Requires `RoundingMode` to also be bound (see Section 3.4).
- **Complexity: Medium-High.** ~25-35 method bindings.

### 3.2 `Decimal128`

- Already `Stringable`, `Representable`, likely `Movable` — binding traits are probably satisfied.
- Fixed-precision (IEEE 754 decimal128) — useful as a faster, lower-memory alternative to `BigDecimal` when the precision fits.
- Exposes a nearly identical API surface to `BigDecimal`, so can share the same Python-side `.pyi` stub pattern.
- **Complexity: Medium.** Type is self-contained; ~20-30 method bindings.

### 3.3 `BigInt` / `BigUint`

- Heavy use of parameterized types internally; the public API surface is simpler.
- Python's `int` is arbitrary precision, so these directly compete with Python's native type — positioning matters.
- **Complexity: Medium.**

### 3.4 Shared Infrastructure

- `RoundingMode` enum-like struct needs to be either exposed as a Python class or mapped to Python string constants.
- Error types: Mojo `raises` becomes Python `Exception` automatically via the binding layer.
- `PythonObject` conversions: `String(py_obj)`, `Int(py=py_obj)` are supported for stdlib types.

---

## 4. File Structure

The binding code lives in a top-level `python/` directory at the project root, parallel to `src/`, `tests/`, `benches/`, and `docs/`. This keeps the Python distribution separate from the Mojo library source.

```txt
python/
├── pyproject.toml            ← PyPI package config (hatchling, src layout)
├── README.md                 ← PyPI landing page
├── decimo_module.mojo        ← Mojo binding source (builds to src/decimo/_decimo.so)
├── src/
│   └── decimo/
│       ├── __init__.py       ← Python wrapper: Decimal class + BigDecimal alias
│       ├── _decimo.pyi       ← Type stub for Pylance/mypy
│       ├── _decimo.so        ← compiled extension (gitignored)
│       └── py.typed          ← PEP 561 marker
└── tests/
    └── test_decimo.py        ← Python tests
```

The core Mojo library (`src/decimo/`) is not modified — all binding logic lives in `python/decimo_module.mojo` as free functions.

The `src` layout (PEP 517) is used so that `pip install -e python/` installs cleanly and the package is importable as `from decimo import Decimal` without any path manipulation.

### 4.1 Two-Layer Architecture

Due to CPython slot limitations (see Phase 0 findings in Section 8), a two-layer pattern is used:

1. **Mojo layer** (`decimo_module.mojo` → `_decimo.so`): Exposes `BigDecimal` with non-dunder method names (`add`, `sub`, `mul`, `to_string`, etc.).
2. **Python layer** (`decimo.py`): A thin `Decimal` wrapper class that delegates Python dunders (`__add__`, `__str__`, etc.) to the Mojo methods.

This keeps the core `BigDecimal` struct unmodified and provides full Pythonic behavior (operators, `str()`, `repr()`, comparisons).

### 4.2 The `Decimal` Alias

The `Decimal` alias is set in `src/decimo/__init__.py` as the primary class name, with `BigDecimal = Decimal` for users who prefer the full name:

```python
# python/src/decimo/__init__.py
from ._decimo import BigDecimal as _BigDecimal

class Decimal:
    __slots__ = ("_inner",)
    def __init__(self, value="0"):
        self._inner = _BigDecimal(str(value))
    def __add__(self, other):
        ...
    # etc.

BigDecimal = Decimal   # alias
```

Python users import like:

```python
from decimo import Decimal          # preferred
from decimo import BigDecimal       # also works, same class
```

---

## 5. Build System Integration (pixi.toml)

Tasks in `pixi.toml`:

```toml
# python bindings (mojo4py)
bpy     = "clear && pixi run buildpy"
buildpy = "pixi run mojo build python/decimo_module.mojo --emit shared-lib -I src -o python/src/decimo/_decimo.so"
testpy  = "pixi run buildpy && pixi run python python/tests/test_decimo.py"
tpy     = "clear && pixi run testpy"
wheel   = "cd python && pixi run python -m build --wheel"
```

- `pixi run buildpy` — compiles the Mojo binding directly into the installable package at `python/src/decimo/_decimo.so`. No need to pre-package `decimo.mojoc`; the `-I src` flag resolves `import decimo` to `src/decimo/`.
- `pixi run testpy` — builds then runs the Python test suite.
- `pixi run wheel` — produces a pure-Python placeholder wheel in `python/dist/` (no `.so` included); suitable for PyPI name reservation.

---

## 6. Testing Strategy

### 6.1 Test Layout

```txt
python/
└── tests/
    └── test_decimo.py         ← Phase 0 tests (will be split per type later)
```

Tests live inside `python/tests/` — co-located with the binding code and `.so` file. This separation avoids mixing Python tests with the Mojo-native tests in `tests/`.

### 6.2 Test Approach

**Unit tests (pytest):**

```python
# tests/python/test_bigdecimal.py
import pytest
from decimo import Decimal, BigDecimal

def test_addition():
    a = Decimal("1.5")
    b = Decimal("2.3")
    assert str(a + b) == "3.8"

def test_division_by_zero():
    with pytest.raises(Exception):
        Decimal("1") / Decimal("0")

def test_high_precision():
    a = Decimal("1") / Decimal("3")   # 1/3 to full precision
    assert str(a).startswith("0.333333")
```

**Alias tests:**

```python
# tests/python/test_aliases.py
from decimo import Decimal, BigDecimal

def test_decimal_is_bigdecimal():
    assert Decimal is BigDecimal

def test_isinstance_works_both_ways():
    d = Decimal("1.5")
    assert isinstance(d, Decimal)
    assert isinstance(d, BigDecimal)  # same type object
```

**Parity tests:** For each operation already tested in the Mojo test suite (e.g., `tests/bigdecimal/`), write a corresponding Python test with the same inputs/outputs. This double-checks that the binding layer doesn't silently change behavior.

**Type and interop tests:** Verify that Python `int`, `float`, `str` arguments are accepted and correctly converted:

```python
d = Decimal(42)        # from Python int
d = Decimal(3.14)      # from Python float
d = Decimal("1.23e5")  # from Python str
```

**Exception propagation tests:** Verify that Mojo `raises` correctly surfaces as Python exceptions with meaningful messages.

**Benchmark parity:** After the Python-callable layer is working, run a comparison of `decimo.Decimal` vs Python's `decimal.Decimal` to validate the performance proposition.

### 6.3 CI Integration

Add to CI pipeline:

```bash
pixi run pytest
```

---

## 7. Distribution (Publishing)

### 7.1 Distribution Formats

| Format                  | How                                         | Audience                 |
| ----------------------- | ------------------------------------------- | ------------------------ |
| **conda package**       | pixi/conda-forge, ships `.so` per platform  | Mojo/MAX ecosystem users |
| **PyPI wheel**          | `python -m build`, platform-specific wheels | General Python users     |
| **Source distribution** | Requires Mojo toolchain to build            | Advanced / contributors  |

For PyPI, build platform-specific wheels. Since decimo currently targets `osx-arm64` and `linux-64`, this matches standard wheel tags: `cp313-cp313-macosx_11_0_arm64` and `cp313-cp313-linux_x86_64`.

### 7.2 PyPI Wheel Build Process

Use `scikit-build-core` or `meson-python` to integrate `mojo build` as the build backend step, or write a custom `build.py` script:

```txt
python/
├── pyproject.toml
├── build.py              ← custom build step: invokes `mojo build --emit shared-lib`
├── MANIFEST.in
└── decimo/
    ├── __init__.py
    ├── *.so              ← built artifacts
    └── *.pyi             ← stubs
```

Example `pyproject.toml`:

```toml
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.backends.legacy:build"

[project]
name = "decimo"
version = "0.8.0"
description = "Arbitrary-precision decimal and integer types for Python, powered by Mojo"
requires-python = ">=3.13"
license = {text = "Apache-2.0"}

[tool.setuptools.package-data]
decimo = ["*.so", "*.pyi", "py.typed"]
```

### 7.3 GitHub Actions CI/CD Sketch

```yaml
# .github/workflows/python-wheel.yml
jobs:
  build-wheels:
    strategy:
      matrix:
        os: [macos-14, ubuntu-24.04]   # arm64 mac, x86_64 linux
    steps:
      - uses: actions/checkout@v4
      - name: Install pixi
        run: curl -fsSL https://pixi.sh/install.sh | sh
      - name: Install dependencies
        run: pixi install
      - name: Build .so files
        run: pixi run py_build
      - name: Build wheel
        run: cd python && pip wheel . -w dist/
      - uses: actions/upload-artifact@v4
        with:
          path: python/dist/*.whl
  publish:
    needs: build-wheels
    steps:
      - uses: pypa/gh-action-pypi-publish@v1
```

---

## 8. Roadmap

### Phase 0 — Proof of Concept ✅ DONE (2026-03-02)

- [x] Write binding for `BigDecimal.__init__(str)` and `BigDecimal.__str__`.
- [x] Manually build the `.so` with `mojo build --emit shared-lib -I src`.
- [x] Import from Python, confirm round-trip: `str(Decimal("1.23")) == "1.23"`.
- [x] Identify trait gaps (`Representable`, `Movable`, etc. — all satisfied).
- [x] Arithmetic: `+`, `-`, `*`, `/` work. Comparison: `==`, `<`, `<=`, `>`, `>=`, `!=` work.
- [x] `Decimal` alias (`Decimal is BigDecimal` → `True` in Python).
- [x] Large arbitrary-precision numbers work (38+ digit numbers).
- [x] Cross-validated all operations against Python stdlib `decimal.Decimal`.
- [x] Type stubs (`_decimo.pyi`) and `py.typed` PEP 561 marker.
- [x] `pyproject.toml` + `src` layout for PyPI; placeholder wheel built and uploaded to PyPI.
- [x] CI: `test-python` job in GitHub Actions parallel CI.
- [x] Python code formatter: `ruff` integrated into `pixi run format` and pre-commit.

**Phase 0 findings & architecture decisions:**

1. **Two-layer architecture is required.** `PythonTypeBuilder.def_method("__str__")` creates a dict entry but does NOT set the CPython `tp_str` type slot. Similarly, `def_method("__add__")` does NOT set `nb_add`. This means `str(d)` and `d + e` don't work — only `d.__str__()` and `d.__add__(e)` do. This is a CPython limitation for heap types created via C API: dunder methods must be registered as type slots, not just dict entries.

2. **Solution: Mojo `.so` exposes non-dunder methods** (`to_string`, `add`, `sub`, `mul`, `neg`, `abs_`, `eq`, `lt`, `le`), and a **thin Python wrapper class** (`decimo.py`) delegates Python dunders to them. Overhead is negligible — one Python method call per operation, with all heavy math done in Mojo.

3. **File layout for Phase 0:**

   ```txt
   python/
   ├── pyproject.toml            ← PyPI package config (hatchling, src layout)
   ├── README.md                 ← PyPI landing page
   ├── decimo_module.mojo        ← Mojo binding (builds to src/decimo/_decimo.so)
   ├── src/
   │   └── decimo/
   │       ├── __init__.py       ← Python wrapper: Decimal class + BigDecimal alias
   │       ├── _decimo.pyi       ← Type stub for Pylance/mypy
   │       ├── _decimo.so        ← compiled extension (gitignored)
   │       └── py.typed          ← PEP 561 marker
   └── tests/
       └── test_decimo.py        ← test script
   ```

4. **Build command:** `pixi run buildpy` (= `mojo build python/decimo_module.mojo --emit shared-lib -I src -o python/src/decimo/_decimo.so`)

5. **`def_py_init` signature:** `fn(out self: T, args: PythonObject, kwargs: PythonObject) raises` — works as a free function, does not need to be a `@staticmethod` on the struct itself. This means **zero modifications to the core BigDecimal struct** are needed for the binding.

6. **`String(py_obj)` conversion:** `String(args[0])` works for Python `str` objects. For Python `int`/`float`, the caller must pass `str(value)` before calling the Mojo constructor — the Python wrapper handles this.

### Phase 1 — BigDecimal Full Binding

- [ ] Expose `RoundingMode` as Python constants or a Python enum.
- [ ] Expose all arithmetic operators: `__add__`, `__sub__`, `__mul__`, `__truediv__`, `__mod__`, `__pow__`, `__neg__`, `__abs__`.
- [ ] Expose comparison: `__eq__`, `__ne__`, `__lt__`, `__le__`, `__gt__`, `__ge__`.
- [ ] Expose constructors from `int`, `float`, `str`.
- [ ] Expose transcendentals: `sqrt`, `exp`, `ln`, `log10`.
- [ ] Expose `round(d, ndigits)` via `__round__`.
- [ ] Write Python test suite for `BigDecimal` (parity with `tests/bigdecimal/`).
- [ ] Add `pixi run py_build_bigdecimal` task.
- [ ] Write `.pyi` stub for `BigDecimal`.
- [ ] Set `Decimal = BigDecimal` alias in `python/decimo/__init__.py`.
- [ ] Add `test_aliases.py` to verify `Decimal is BigDecimal`.

### Phase 2 — Decimal128 Binding

- [ ] Expose `Decimal128`: same API surface as `BigDecimal` but fixed precision.
- [ ] Write `.pyi` stub for `Decimal128` (can largely mirror `bigdecimal.pyi`).
- [ ] Python tests with parity checks against `tests/decimal128/`.

### Phase 3 — BigInt / BigUint Binding

- [ ] Expose `BigInt`: arithmetic, comparison, `__int__`, `__str__`, `__hash__` (if feasible).
- [ ] Expose `BigUint` similarly.
- [ ] Handle `Int` ↔ `PythonObject` conversion for large Python integers (requires manual conversion logic since Python `int` is arbitrary precision).
- [ ] Python tests with parity checks.

### Phase 4 — Packaging + Distribution

- [x] Create `python/` directory with `pyproject.toml` (hatchling, src layout) and `src/decimo/__init__.py`.
- [x] Write `.pyi` stubs for `BigDecimal` (`_decimo.pyi`).
- [x] Add `py.typed` marker (PEP 561).
- [x] PyPI name reserved — placeholder wheel (`0.1.0.dev0`) published to PyPI.
- [ ] Test `pip install` of the built wheel locally (blocked until pre-built `.so` in wheel).
- [ ] Set up GitHub Actions for wheel builds (macOS arm64, Linux x86_64).
- [ ] Publish platform-specific wheels with bundled `.so`.

### Phase 5 — Ergonomics + Stabilization

- [ ] Add `__hash__` for use in dicts/sets.
- [ ] Add `__copy__` / `__deepcopy__`.
- [ ] Add `__reduce__` / `__reduce_ex__` for pickling.
- [ ] Handle `math.floor`, `math.ceil`, `math.trunc` via `__floor__`, `__ceil__`, `__trunc__`.
- [ ] Add `numbers.Number` ABC registration (soft-codes into Python's numeric tower).
- [ ] Implement `__format__` for f-string formatting.
- [ ] Benchmark against `decimal.Decimal` and publish results.
- [ ] Wait for Modular to stabilize the bindings API before final API freeze.

---

## 9. Open Questions & Risks

| Risk                                    | Severity | Notes                                                                                                                 |
| --------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------- |
| Beta API changes                        | High     | Modular explicitly warns the bindings API will change. Pin to a specific MAX version until stable.                    |
| Mojo package deps in importer hook      | Medium   | Fully worked around via the manual `--emit shared-lib` build. No blocker.                                             |
| Python `int` → Mojo `BigInt` conversion | Medium   | Python's `int` is arbitrary-size. Need custom `ConvertibleFromPython` implementation or `def_py_function` workaround. |
| 6-argument limit                        | Low      | Most arithmetic ops take ≤2 args. Might be hit by some `BigDecimal` rounding APIs.                                    |
| No property support                     | Low      | Use getter methods (`get_precision()`) as a workaround until properties land.                                         |
| Platform support                        | Medium   | Currently only `osx-arm64` and `linux-64`. Windows is not yet a Mojo target.                                          |
| ABI compatibility                       | Medium   | The `.so` is linked against a specific MAX/Python version. Wheels must be version-specific.                           |

---

## 10. Quick-Start

Build and test with two commands:

```bash
pixi run buildpy    # Compiles python/decimo_module.mojo → python/src/decimo/_decimo.so
pixi run testpy     # Builds, then runs python/tests/test_decimo.py
```

From Python:

```python
from decimo import Decimal

a = Decimal("1.5")
b = Decimal("2.3")
print(a + b)        # 3.8
print(repr(a))      # Decimal("1.5")
assert Decimal("1") < Decimal("2")  # True
```
