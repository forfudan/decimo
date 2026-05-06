# Decimo changelog

This is a list of changes for the Decimo package (formerly DeciMojo).

## Unreleased - under development

### ⭐️ New in v0.10.0

**Decimal128:**

1. Add **`normalize()`** to strip non-significant trailing zeros from the coefficient (matches Python `decimal.Decimal.normalize()`), **`__hash__()`** so `Decimal128` can be used as a dict key or set element, **`same_quantum(other)`** for IEEE 754-style scale comparison, plus other small additions (PR #238).
1. Add **`from_decimal(BigDecimal)`** static constructor that quantises a high-precision `BigDecimal` onto the Decimal128 grid by rendering with `to_string(force_plain=True)` and re-parsing via `from_string()` (banker's rounding to 28 fractional digits, raises `OverflowError` when the integral part overflows the 96-bit coefficient). Primarily used by the cross-language bench harness as an oracle bridge from `BigDecimal` reference values into the Decimal128 grid (PR #239).
1. Add **`max`, `min`, `clamp`** instance methods (PR #230).
1. Add **`trunc`, `floor`, `ceil`, `fract`, `signum`, `unpack`** instance methods to round towards zero / −∞ / +∞, extract the fractional part and sign, and unpack into the underlying coefficient/sign/scale words (PR #227).
1. Add **`fit_to_max_coefficient()`** and **`round_coefficient()`** utility helpers; `from_string()` and the arithmetic paths now share these instead of inline scratch logic (PR #216).
1. Add **`__bool__`** (so `if d:` and `Bool(d)` work) and **`__pos__`** (so `+d` is a copy), matching Python `decimal.Decimal` and `BigDecimal`. `Decimal128` now also conforms to the `Boolable` trait.
1. Add **`is_positive()`** (strictly positive, i.e. nonzero and not negative) and **`is_odd()`** (true when the integer part's units digit is odd, regardless of sign or fractional part), matching the existing `is_negative()` / `is_zero()` / `is_one()` introspection surface.
1. Add **`number_of_trailing_zeros()`**, mirroring `BigDecimal.number_of_trailing_zeros()`. Returns the count of trailing zero digits in the coefficient (e.g. `Decimal128("1.2300").number_of_trailing_zeros() == 2`).
1. Add **`to_scientific_string()`** and **`to_eng_string()`** convenience aliases for `to_string(scientific=True)` / `to_string(engineering=True)`, matching the equivalent `BigDecimal` API.
1. Add **`to_string_with_separators(separator="_")`** which renders the plain-notation string with digit-group separators inserted every 3 digits in both the integer and fractional parts, matching `BigDecimal.to_string_with_separators`. Implemented as a thin alias for `to_string(delimiter=separator)` (the `delimiter` argument was added to `to_string` in this release; see the Changed section).
1. Add **`fma(other, third)`** — fused multiply-add `self * other + third` with a single rounding at the end. Computes the exact `UInt256` product, aligns scales for the addend, performs a signed magnitude combine, and rounds once via the same `round_coefficient` path as `multiply()` (with banker's-rounding carry recheck). When the aligned working coefficient would exceed the implementation's 58-digit working cap (the size of the `power_of_10_unsafe[uint256]` rodata table — not a UInt256 limit, which is ~77 digits — used to keep scaling and rounding in the fast path), it falls back to the two-step `multiply(self, other) + third` path. Matches Python `decimal.Decimal.fma` and IEEE 754-2008 §5.4.1 semantics. Bit-identical to the high-precision `BigDecimal` oracle (work=40, exact `multiply(precision=0)`/`add(precision=0)`) on all 12 cross-language bench cases. Bench cases include four "group-2" demonstrators (`pi·pi − 9.8`, `e·pi − 8.539`, `(1+ε)(1−ε) − 1`, near-cancellation typical) where fma reclaims one full extra digit of precision over the naive `(a*b) + c` path that has to round the intermediate product first.
1. Add **`__divmod__(other)`** — returns `(self // other, self % other)` in a single call, mirroring Python's `divmod()` and `BigDecimal.__divmod__()`. Amortises the divide pipeline: the truncated quotient is computed once via `truncate_divide()` and reused to derive the remainder as `self - q * other`, avoiding the second full `divide()` pass that the naive `(a // b, a % b)` two-step would perform. Both `Decimal128` and `Int` right-hand sides are supported.
1. Add **`cbrt()`** — convenience cube-root method, equivalent to `self.root(3)`. Matches the `BigDecimal` API. Unlike `sqrt()`, `cbrt()` is well-defined for negative values (delegates to `root()`'s odd-root handling, e.g. `Dec128("-8").cbrt()` returns `-2`).

**CLI Calculator:**

1. Add **pipe/stdin mode**: read expressions from standard input, one per line, when no positional argument is given and stdin is piped (e.g. `echo "1+2" | decimo`, `printf "pi\nsqrt(2)" | decimo -P 100`). Blank lines and comment lines (starting with `#`) are automatically skipped.
1. Add **file mode**: use `--file` / `-F` flag to evaluate expressions from a file, one per line (e.g. `decimo -F expressions.dm -P 50`). Comments (`#`), inline comments, and blank lines are skipped. All CLI flags (precision, formatting, rounding) apply to every expression.
1. Add **shell completion** documentation for Bash, Zsh, and Fish (`decimo --completions bash|zsh|fish`).
1. Add **CLI performance benchmarks** (`benches/cli/bench_cli.sh`) comparing correctness and timing against `bc` and `python3` across 47 comparisons — all results match to 15 significant digits; `decimo` is 3–4× faster than `python3 -c`.
1. Add **interactive REPL**: launch with `decimo` (no arguments, TTY attached). Features coloured `decimo>` prompt on stderr, per-line error recovery with caret diagnostics, comment/blank-line skipping, and graceful exit via `exit`, `quit`, or Ctrl-D. All CLI flags (`-P`, `--scientific`, etc.) apply to the REPL session.
1. Add **REPL info commands**: `:` shows current settings, `?` shows help, `$` / `:v` / `:vars` lists all defined variables, `:q` / `:quit` / `:exit` exits the session.
1. Add **case-insensitive input** in the REPL: all input is lowercased before processing, so `PI`, `Sqrt(2)`, `SIN(1)` all work.
1. Streamline the **REPL welcome banner** to a compact one-liner with a hint to `?`, `:`, and `:q`.
1. Add **standalone integer precision shortcut** in settings: `:100` is equivalent to `:p 100`. Any all-digit token in a settings command is treated as the precision value.
1. Print **full settings block** after every settings change (`:...` commands) instead of a one-line summary, so the effect is immediately visible.

### 🦋 Changed in v0.10.0

**Decimal128:**

1. Sweep all hot-path `UInt(128|256)(10) ** k` calls (in `arithmetics`, `comparison`, `rounding`, `decimal128`) to `power_of_10_unsafe`, replacing runtime exponentiation (~4–12 ns) with a single rodata indexed load (~0.8 ns) (PR #224).
1. Mark `Decimal128.from_uint128()` as `@always_inline` and split its two cold `raise ValueError` blocks into separate `@no_inline` helpers (`_raise_from_uint128_value_too_large`, `_raise_from_uint128_scale_too_large`), so the inline body stays small (two checks + bitcast + flag-or) without dragging `String.format` into every caller. Brings `add` to **0.9× rust**, `subtract` to **0.9–1.3× rust**, and `divide` to **1.0× rust** on the median bench (PR #224).
1. Mark `number_of_bits()` as `@always_inline` to remove the call frame on `multiply()`'s critical path; underlying implementation switches to `std.bit.bit_width` (PR #218).
1. **`exp()` / `ln()` / `log10()` range reduction:** rewrite Taylor and range-reduction loops so that worst-case ratios drop to **≤ 1.0× rust_decimal** across all 42 bench cases (previously up to 1.7×). `exp_series()` now uses precomputed factorial reciprocals (two multiplies per term instead of one multiply + one divide), `ln()` reads the decade exponent `q` directly from the input scale instead of looping divisions/multiplications by 10, and `log10()`'s integer-power-of-10 fast path uses `number_of_digits` (O(1)) instead of a per-digit `% 10 / //= 10` loop. Adds new bench harnesses `cases/{ln,log10,exp}.toml` and wires `ln`/`log10`/`exp` into `run_all.sh` and the Rust harness (via the `maths` feature) (PR #229).
1. **`exp()` 2-tier sub-unit chunker:** add 17 precomputed sub-unit constants — per-tenth `E0D1`…`E0D9` and per-hundredth `E0D01`…`E0D09` — and rewrite the `x_int < 1` arm to peel off the first decimal digit, then (when that digit is zero) the second decimal digit, before falling back to `exp_series()` on a residual in `[0, 0.01)`. Halves Taylor iterations on inputs like `exp(π)` (1350 → 770 ns) and improves accuracy from 3 ulp → 1 ulp off the `BigDecimal` reference; `exp(0.1)` collapses to a single constant lookup at 25 ns.
1. Improve **`divide()`** by dropping a redundant rounding-digit padding step; trims the hot path without changing semantics or rounding (PR #237).
1. Update **comparison functions, `from_string()`, `to_string()`, etc.** to improve performance: tighter inner loops on the codepoint iterator, cheaper sign/scale extraction, and shared scratch buffers (PR #225).
1. Optimize **`divide()`** to use a school-book long-division layout that avoids the slow `UInt256 // UInt256` fallback for typical operands (PR #223).
1. Reorder branches in **`add()` and `subtract()`** so the sign-and-scale-aligned hot path is hit first; cold cases (sign mismatch, scale-only mismatch) move to the tail (PR #220, #222).
1. Improve the performance of **`multiply()`**: remove the `is_integer()` and `format()` calls from the hot path, optimize `power_of_10()`, and **fix latent rounding bugs** that affected products whose intermediate scale exceeded 28 (PR #221).
1. Add edge-case tests for **`compare_absolute()`** (PR #217).
1. **Remove `nan` and `inf` values:** `Decimal128` is now a strict finite type. `from_words()` updated accordingly and `power_of_10()` further improved (PR #215).
1. **Consolidate `to_string_scientific()` into `to_string()`:** `Decimal128.to_string()` now takes three optional arguments — `scientific: Bool = False`, `engineering: Bool = False`, and `delimiter: String = ""` — mirroring `BigDecimal.to_string`. The previous standalone `to_string_scientific()` has been removed (no callers in the repo); use `to_string(scientific=True)` or the new `to_scientific_string()` alias instead. Also adds engineering notation as a new code path (exponent always a multiple of 3, e.g. `Decimal128("0.5").to_string(engineering=True) == "500E-3"`); when both `scientific` and `engineering` are True, engineering wins. Passing `delimiter="_"` (or any other separator string) inserts digit-group separators every 3 digits in the mantissa while preserving the optional `E±N` exponent suffix verbatim.
1. **Remove `Decimal128.copy()` and `Decimal128.clone()`:** both were trivial returns of `Self(self.low, self.mid, self.high, self.flags)` and unused anywhere in the repo. `Decimal128` is a `TrivialRegisterPassable` value type, so `var b = a` is the idiomatic copy.
1. **Remove `Decimal128.print_internal_representation()`:** the method was a one-line wrapper around `print(self.internal_representation())` and is unused in the repo. Use `print(x.internal_representation())` directly instead. The structured-string method `internal_representation()` is unchanged.

**BigDecimal:**

1. **Operator semantics aligned with Python `decimal.Decimal`:** the `+` / `-` / `*` operators (and their reflected and augmented variants `__radd__` / `__rsub__` / `__rmul__` / `__iadd__` / `__isub__` / `__imul__`) now round HALF_EVEN to the default precision (`PRECISION = 28` significant digits), instead of returning an exact unrounded result. This matches Python `decimal.Decimal` default-context behavior.
1. **New exact methods with explicit precision:** `BigDecimal.add(other, precision=0)`, `subtract(other, precision=0)`, and `multiply(other, precision=0)` give callers an explicit choice — `precision=0` (default) returns the exact unrounded result, `precision > 0` rounds HALF_EVEN to that many significant digits. Use these methods (instead of operators) whenever exact intermediate arithmetic matters.
1. **New in-place exact methods:** `BigDecimal.add_inplace(other, precision=0)`, `subtract_inplace(other, precision=0)`, and `multiply_inplace(other, precision=0)`, mirroring the precision-aware non-inplace methods. Use these in tight loops to replace `+= / -= / *=` when exact intermediate arithmetic matters. The free functions `arithmetics.add_inplace` / `subtract_inplace` / `multiply_inplace` also gain the same `precision` parameter.
1. **Internal call sites migrated:** `pi_machin` (`constants.mojo`), Newton iterations and Taylor series in `exponential.mojo`, and range-reduction loops in `trigonometric.mojo` now use the exact `*_inplace` methods so high-precision π / `ln` / `exp` / trig results are no longer silently capped at 28 digits.
1. **CLI calculator:** the RPN evaluator (`src/cli/calculator/evaluator.mojo`) now drives `+` / `-` / `*` through `.add(b, working_precision)` / `.subtract(...)` / `.multiply(...)` so the user-requested `--precision` is honored end to end (previously results were silently capped at PRECISION = 28).
1. **Fix `to_string(force_plain=True)` dropping trailing zeros for `scale < 0`:** `BigDecimal("1e40").to_string(force_plain=True)` previously returned `"1"` instead of the full 41-digit integer, silently producing a wrong value when re-parsed (e.g. via `Decimal128.from_decimal()`). The plain-notation `leftdigits >= num_digits` branch now materialises the `leftdigits − num_digits` trailing zeros that `force_plain=True` requires when `scale < 0`.

### 🧪 Tests and benchmarks in v0.10.0

**Decimal128:**

1. Consolidate the Dec128 test suites into fewer files (`test_decimal128_arithmetics.mojo`, `test_decimal128_creation.mojo`, etc.) for faster compilation and easier navigation (PR #228).
1. Refactor the cross-language benchmark harness to include comparisons against **Rust (`rust_decimal`)**, **C# (`System.Decimal`)**, and **VB.NET** (PR #219); `BigDecimal` acts as the high-precision oracle for `ln` / `log10` / `exp` (PR #229).

## 20260323 (v0.9.0)

Decimo v0.9.0 updates the codebase to **Mojo v0.26.2** and marks the **"make it useful"** phase. This release introduces three major additions:

First, a full-featured **CLI arbitrary-precision calculator** (`decimo`), powered by Decimo's `BigDecimal`. It includes a complete tokenizer, a shunting-yard parser, and an RPN evaluator with working-precision guard digits, supporting built-in mathematical functions (`sqrt`, `cbrt`, `root`, `ln`, `log`, `log10`, `exp`, trigonometric functions, `abs`), constants (`pi`, `e`), and configurable output formatting (scientific/engineering notation, digit delimiters, rounding modes, and precision control).

Second, the `BigDecimal` API is significantly expanded with methods aligned to Python's `decimal.Decimal` and the IEEE 754 specification, including `as_tuple()`, `adjusted()`, `same_quantum()`, `scaleb()`, `fma()`, `copy_abs()`, `copy_negate()`, `copy_sign()`, `bit_count()`, `__float__()`, engineering notation, and digit-group delimiters for `to_string()`. The `ROUND_HALF_DOWN` rounding mode is added, bringing the total to seven.

Third, Decimo gains **Python bindings** via Mojo's `PythonModuleBuilder`, exposing `BigDecimal` as a native Python extension module (`_decimo.so`) with a Pythonic `Decimal` wrapper for seamless interoperability.

### ⭐️ New in v0.9.0

**CLI Calculator:**

1. Implement an arbitrary-precision CLI calculator with tokenizer, shunting-yard parser, and RPN evaluator, supporting arithmetic expressions with parentheses and operator precedence (PR #170).
1. Add built-in functions (`sqrt`, `cbrt`, `root`, `ln`, `log`, `log10`, `exp`, `sin`, `cos`, `tan`, `cot`, `csc`, `abs`), constants (`pi`, `e`), and configurable output formatting (scientific/engineering notation, digit delimiter, padding, rounding mode) (PR #171).
1. Improve CLI error handling with token location tracing and ANSI-coloured diagnostic output (PR #178).
1. Use working precision (user precision + guard digits) for intermediate calculations to improve result accuracy (PR #182).

**BigDecimal:**

1. Add **engineering notation** (`to_eng_string()`) and **digit-group delimiters** (`to_string_with_separators()`) to `to_string()`, with optional line-width wrapping (PR #172).
1. Add utility methods: `is_integer()`, `is_signed()`, `number_class()`, `logb()`, `normalize()`, `radix()` (PR #173).
1. Implement `as_tuple()` returning `(sign, digits, exponent)`, matching Python's `Decimal.as_tuple()` (PR #174).
1. Implement `adjusted()`, `copy_abs()`, `copy_negate()`, and `copy_sign()` aligned with Python's `decimal` API (PR #176).
1. Implement `same_quantum()` and add the `ROUND_HALF_DOWN` rounding mode, bringing the total to seven (PR #177).
1. Implement `scaleb()`, `fma()`, `bit_count()`, and `__float__()` (implements `FloatableRaising`) (PR #183).

**Python Bindings:**

1. Implement Python bindings via Mojo's `PythonModuleBuilder`, exposing `BigDecimal` as a native extension module `_decimo.so` with arithmetic, comparison, and string operations (PR #179).
1. Restructure `python/` to a `src` layout with `pyproject.toml` for PyPI packaging (PR #180).

### 🦋 Changed in v0.9.0

1. Update the codebase to **Mojo v0.26.2**, adopting `byte=` slicing syntax, `out` parameter convention for constructors, and updated `String`/`StringSlice` APIs (PR #185).
1. Merge `TOMLMojo` into Decimo as the sub-package `decimo.toml`, removing standalone packaging (PR #181).
1. Rename `exponent()` to `adjusted()` for `BigDecimal` to align with Python's `decimal` module naming (PR #176).
1. Change default precision of `BigDecimal` to **28** significant digits, matching Python's `decimal` module default.
1. Remove deprecated free-function comparison aliases and legacy method names from `BigDecimal` (PR #173).
1. Align `print_internal_representation()` output style across `BigInt`, `BigUInt`, `BigDecimal`, and `Decimal128` with dynamic column alignment (PR #169).

### 📚 Documentation and testing in v0.9.0

- Add comprehensive user manuals for the Decimo library and the CLI calculator (PR #184).
- Add info badges to the README file.

## 20260225 (v0.8.0)

> **Library renamed from `decimojo` to `decimo`.** The package name, import path, and all public references have been updated. GitHub repository will be renamed to `forfudan/decimo` (GitHub auto-redirects the old URL).

Decimo v0.8.0 is a profound milestone in the development of Decimo, marking the **"make it fast"** phase. There are two major improvements in this release:

First, it introduces a completely new `BigInt` (`BInt`) type using a **base-2^32 internal representation**. This replaces the previous base-10^9 implementation (now available as `BigInt10`) with a little-endian format using `UInt32` words, dramatically improving the performance of all integer operations. The new `BigInt` implements the **Karatsuba multiplication algorithm** and the **Burnikel-Ziegler division algorithm** for sub-quadratic performance on large integers, and includes **divide-and-conquer base conversion** for fast string I/O. It also adds **bitwise operations**, **GCD and modular arithmetic**, and an optimized **integer square root**. Benchmarks show that the new `BigInt` outperforms Python's built-in `int` type in most cases, with up to 11× speedup for power operations and 5× for shift operations.

Second, it optimizes the mathematical operations for `BigDecimal`, bringing significant performance and accuracy improvements. The `sqrt()` function is re-implemented using the **reciprocal square root method** combined with Newton's method for faster convergence. The `ln()` function now supports an **atanh-based approach** with mathematical constant caching via `MathCache`. The `exp()` function benefits from **aggressive range reduction** for much faster convergence. The `root()` function gains **rational root decomposition** and a direct Newton method. The `to_string()` method is aligned with CPython's `decimal` module formatting rules for scientific notation and trailing zeros. The `BigUInt` layer also gains the **Toom-Cook 3-way multiplication algorithm**. Benchmarks indicate that `BigDecimal` operations beat Python's `decimal` module in speed, especially for high-precision calculations (e.g., division up to 915× faster, sqrt 3.5× faster on average).

### ⭐️ New in v0.8.0

**BigInt (base-2^32):**

1. Implement the `BigInt` (`BInt`) type using a base-2^32 internal representation with little-endian `UInt32` words. This is a completely new implementation optimized for binary computations while supporting arbitrary precision (PR #133, #134, #135, #141).
1. Implement the **Karatsuba multiplication algorithm** for `BigInt`, reducing time complexity from $O(n^2)$ to $O(n^{\log_2 3})$ for large integers (PR #142).
1. Implement the **slice-based Burnikel-Ziegler division algorithm** for `BigInt`, providing sub-quadratic division performance for the base-2^32 representation (PR #144).
1. Implement **divide-and-conquer base conversion** for `BigInt.to_string()`, significantly improving string conversion speed for large integers (PR #145).
1. Implement **bitwise operations** (`__and__`, `__or__`, `__xor__`, `__lshift__`, `__rshift__`, `__invert__`) and true in-place bitwise operations for `BigInt` (PR #150, #151).
1. Implement `gcd()`, `extended_gcd()`, `mod_inverse()`, and `mod_pow()` for `BigInt`, providing number-theoretic functions (PR #152, #153).
1. Implement an optimized `sqrt()` for `BigInt` using Newton's method with a good initial approximation, delivering 1.39× average speedup over Python (PR #155).

**BigDecimal:**

1. Implement the `quantize()` function for `BigDecimal` to format decimal numbers to a specified number of decimal places, similar to Python's `Decimal.quantize()` (PR #126).
1. Implement true in-place arithmetic functions (`__iadd__`, `__isub__`, `__imul__`) for `BigDecimal` to reduce memory allocations during repeated operations (PR #162).
1. Implement methods to initialize `BigInt` and `BigDecimal` from Python objects, enabling seamless interoperability with Python's `int` and `decimal.Decimal` (PR #129).

**Core:**

1. Add `ROUND_CEILING` and `ROUND_FLOOR` rounding modes to `RoundingMode`, bringing the total to six modes (PR #164).

**TOMLMojo:**

1. Implement all core **TOML v1.0 specification** features for `TOMLMojo`, including inline tables, arrays of tables, dotted keys, multiline strings, and all value types (PR #140).

### 🦋 Changed in v0.8.0

**BigInt:**

1. Rename the previous base-10^9 `BigInt` to `BigInt10`. The alias `BInt` now refers to the new base-2^32 `BigInt` type (PR #143, #154).
1. Optimize `from_string()` for `BigInt` with an improved string parser and divide-and-conquer approach for fast base conversion (PR #146, #147, #148).
1. Optimize `to_string()` for `BigInt` with divide-and-conquer base conversion, achieving 6× average speedup over Python (PR #149).

**BigDecimal:**

1. Re-implement `sqrt()` for `BigDecimal` using the **reciprocal square root method** combined with Newton's method, delivering faster convergence and better accuracy for high-precision calculations (PR #163).
1. Optimize `ln()` and `exp()` for `BigDecimal` with mathematical constant caching via `MathCache` and improved handling of one-word dividends (PR #160).
1. Apply **aggressive range reduction** for `exp()` to achieve faster convergence at high precision (PR #167).
1. Implement direct Newton method for general `root()` calculation, replacing the previous iterative approach (PR #161).
1. Add **rational root decomposition** to `root()` and an **atanh-based approach** to `ln()` for improved accuracy and convergence (PR #168).
1. Optimize `true_divide_general()` to correctly account for existing word surplus in the dividend (PR #158).
1. Optimize division with truncation and align `to_string()` output with CPython's `decimal` module formatting for scientific notation and trailing zeros (PR #165).

**BigUInt:**

1. Implement the **Toom-Cook 3-way multiplication algorithm** for `BigUInt`, improving performance for large number multiplications (PR #166).
1. Unify and refine initialization methods for `BigUInt` with consistent constructors and improved validation (PR #127, #128, #131).

**Core:**

1. Improve naming consistency between types, ensuring uniform method names across `BigInt`, `BigDecimal`, and `Decimal128` (PR #164).
1. Make `RoundingMode` type implicitly copyable for easier usage in function signatures (PR #125).

### 🛠️ Fixed in v0.8.0

- Fix string formatting for `BigDecimal` to match Python's `decimal` module formatting rules, including correct scientific notation thresholds and trailing zero handling (PR #163, #165).

### 📚 Documentation and testing in v0.8.0

- Refactor the testing files for `Decimal128` (PR #132).
- Refactor the benchmarking system to use TOML-based input files with configurable precision (PR #139, #159).
- Update document links for the repository organization move to `forfudan` (PR #130).
- Update documents and add the planning files for BigInt and BigDecimal optimization roadmaps (PR #157).

## 20260212 (v0.7.0)

DeciMojo v0.7.0 updates the codebase to Mojo v0.26.1.

- Replaces all `alias` declarations with `comptime` in all files. `alias` is deprecated.
- Updates list and constant construction syntax throughout the codebase, e.g., replaced `List[UInt32](...)` with `[UInt32(...), ...]`, used `[word]` instead of `List[UInt32](word)`, etc. The old syntax is deprecated.
- Updates list slicing syntax to use the new syntax. Now `lst[1:]` returns a `Span` instead of a `List`, so it needs to be converted to a list using the constructor `List(...)`.
- Updates some methods of the `String` type and the indexing and slicing syntax for `String` objects to match the latest Mojo syntax. The old syntax is deprecated.
- Fixes the closure capture when using `vectorize`. The new syntax requires something like `unified {read x, mut y}` to capture variables `x` and `y` in the closure. The old syntax is deprecated.

## 20251216 (v0.6.0)

DeciMojo v0.6.0 updates the codebase to Mojo v0.25.7, adopting the new `TestSuite` type for improved test organization. All tests have been refactored to use the native Mojo testing framework instead of the deprecated `pixi test` command.

## 20250806 (v0.5.0)

DeciMojo v0.5.0 introduces significant enhancements to the `BigDecimal` and `BigUInt` types, including new mathematical functions and performance optimizations. The release adds **trigonometric functions** for `BigDecimal`, implements the **Chudnovsky algorithm** for computing π, and implements the **Karatsuba multiplication algorithm** and **Burnikel-Ziegler division algorithm** for `BigUInt`. In-place operations, slice operations, and SIMD operations are now supported for `BigUInt` arithmetic. The `Decimal` type is renamed to `Decimal128` to reflect its 128-bit fixed precision. The release also includes improved error handling, optimized type conversions, refactored testing suites, and documentation updates.

DeciMojo v0.5.0 is compatible with Mojo v25.5.

### ⭐️ New in v0.5.0

1. Introduce trigonometric functions for `BigDecimal`: `sin()`, `cos()`, `tan()`, `cot()`, `csc()`, `sec()`. These functions compute the corresponding trigonometric values of a given angle in radians with arbitrary precision (#96, #99).
1. Introduce the function `pi()` for `BigDecimal` to compute the value of π (pi) with arbitrary precision with the Chudnovsky algorithm with binary splitting (#95).
1. Implement the `sqrt()` function for `BigUInt` to compute the square root of a `BigUInt` number as a `BigUInt` object (#107).
1. Introduce a `DeciMojoError` type and various aliases to handle errors in DeciMojo. This enables a more consistent error handling mechanism across the library and allows users to track errors more easily (#114).

### 🦋 Changed in v0.5.0

Changes in **BigUInt**:

1. Refine the `BigUInt` multiplication with the **Karatsuba algorithm**. The time complexity of multiplication is reduced from $O(n^2)$ to $O(n^{ln(3/2)})$ for large integers, which significantly improves performance for big numbers. Doubling the size of the numbers will only increase the time taken by a factor of about 3, instead of 4 as in the previous implementation (#97).
1. Refine the `BigUInt` division with the **Burnikel-Ziegler fast recursive division algorithm**. The time complexity of division is also reduced from $O(n^2)$ to $O(n^{ln(3/2)})$ for large integers (#103).
1. Refine the fall-back **schoolbook division** of `BigUInt` to improve performance. The fallback division is used when the divisor is small enough (#98, #100).
1. Implement auxiliary functions for arithmetic operations of `BigUInt` to handle **special cases** more efficiently, e.g., when the second operand is one-word long or is a `UInt32` value (#98, #104, #111).
1. Implement in-place subtraction for `BigUInt`. The `__isub__` method of `BigUInt` will now conduct in-place subtraction. `x -= y` will not lead to memory allocation, but will modify the original `BigUInt` object `x` directly (#98).
1. Use SIMD for `BigUInt` addition and subtraction operations. This allows the addition and subtraction of two `BigUInt` objects to be performed in parallel, significantly improving performance for large numbers (#101, #102).
1. Implement functions for all arithmetic operations on slices of `BigUInt` objects. This allows you to perform arithmetic operations on slices of `BigUInt` objects without having to convert them to `BigUInt` first, leading to less memory allocation and improved performance (#105).
1. Add `to_uint64()` and `to_uint128()` methods to `BigUInt` to for fast type conversion (#91).

Changes in **BigDecimal**:

1. Re-implemente the `sqrt()` function for `BigDecimal` to use the new `BigUInt.sqrt()` method for better performance and accuracy. The new implementation adjusts the scale and coefficient directly, which is more efficient than the previous method. Introduce a new `sqrt_decimal_approach()` function to preserve the old implementation for reference (#108).
1. Refine or re-implement the basic arithmetic operations, *e.g.,*, addition, subtraction, multiplication, division, etc, for `BigDecimal` and simplify the logic. The new implementation is more efficient and easier to understand, leading to better performance (#109, #110).
1. Add a default precision 36 for `BigDecimal` methods (#112).

Other changes:

1. Update the codebase to Mojo v25.5 (#113).
1. Remove unnecessary `raises` keywords for all functions (#92).
1. Rename the `Decimal` type to `Decimal128` to reflect its fixed precision of 128 bits. It has a new alias `Dec128` (#112).
1. `Decimal` is now an alias for `BigDecimal` (#112).

### 🛠️ Fixed in v0.5.0

- Fix a bug for `BigUInt` comparison: When there are leading zero words, the comparison returns incorrect results (#97).
- Fix the `is_zero()`, `is_one()`, and `is_two()` methods for `BigUInt` to correctly handle the case when there are leading zero words (#97).

### 📚 Documentation and testing in v0.5.0

- Refactor the test files for `BigDecimal` (PR #93).
- Refactor the test files for `BigInt` (PR #106).

## 20250701 (v0.4.1)

Version 0.4.1 of DeciMojo introduces implicit type conversion between built-in integral types and arbitrary-precision types.

### ⭐️ New in v0.4.1

Now DeciMojo supports implicit type conversion between built-in integeral types (`Int`, `UInt`, `Int8`, `UInt8`, `Int16`, `UInt16`, `Int32`, `UInt32`, `Int64`, `UInt64`, `Int128`,`UInt128`, `Int256`, and `UInt256`) and the arbitrary-precision types (`BigUInt`, `BigInt`, and `BigDecimal`). This allows you to use these built-in types directly in arithmetic operations with `BigInt` and `BigUInt` without explicit conversion. The merged type will always be the most compatible one (PR #89, PR #90).

For example, you can now do the following:

```mojo
from decimojo.prelude import *

def main() raises:
    var a = BInt(Int256(-1234567890))
    var b = BigUInt(31415926)
    var c = BDec("3.14159265358979323")

    print("a =", a)
    print("b =", b)
    print("c =", c)

    print(a * b)  # Merged to BInt
    print(a + c)  # Merged to BDec
    print(b + c)  # Merged to BDec
    print(a * Int(-128))  # Merged to BInt
    print(b * UInt(8))  # Merged to BUInt
    print(c * Int256(987654321123456789))  # Merged to BDec

    var lst = [a, b, c, UInt8(255), Int64(22222), UInt256(1234567890)]
    # The list is of the type `List[BigDecimal]`
    for i in lst:
        print(i, end=", ")
```

Running the code will give your the following results:

```console
a = -1234567890
b = 31415926
c = 3.14159265358979323
-38785093474216140
-1234567886.85840734641020677
31415929.14159265358979323
158024689920
251327408
3102807559527666386.46423202534973847
-1234567890, 31415926, 3.14159265358979323, 255, 22222, 1234567890,
```

### 🦋 Changed in v0.4.1

Optimize the case when you increase the value of a `BigInt` object in-place by 1, *i.e.*, `i += 1`. This allows you to iterate faster (PR #89). For example, we can compute the time taken to iterate from `0` to `1_000_000` using `BigInt` and compare it with the built-in `Int` type:

```mojo
from decimojo.prelude import *

def main() raises:
    i = BigInt(0)
    end = BigInt(1_000_000)
    while i < end:
        print(i)
        i += 1
```

| scenario        | Time taken |
| --------------- | ---------- |
| v0.4.0 `BigInt` | 1.102s     |
| v0.4.1 `BigInt` | 0.912s     |
| Built-in `Int`  | 0.893s     |

### 🛠️ Fixed in v0.4.1

Fix a bug in `BigDecimal` where it cannot create a correct value from a integral scalar, e.g., `BDec(UInt16(0))` returns an unitialized `BigDecimal` object (PR #89).

### 📚 Documentation and testing in v0.4.1

Update the `tests` module and refactor the test files for `BigUInt` (PR #88).

## 20250625 (v0.4.0)

DeciMojo v0.4.0 updates the codebase to Mojo v25.4. This release enables you to use DeciMojo with the latest Mojo features.

## 20250606 (v0.3.1)

DeciMojo v0.3.1 updates the codebase to Mojo v25.3 and replaces the `magic` package manager with `pixi`. This release enables you to use DeciMojo with the latest Mojo features and the new package manager.

## 20250415 (v0.3.0)

DeciMojo v0.3.0 introduces the arbitrary-precision `BigDecimal` type with comprehensive arithmetic operations, comparisons, and mathematical functions (`sqrt`, `root`, `log`, `exp`, `power`). A new `tomlmojo` package supports test refactoring. Improvements include refined `BigUInt` constructors, enhanced `scale_up_by_power_of_10()` functionality, and a critical multiplication bug fix.

### ⭐️ New in v0.3.0

- Implement the `BigDecimal` type with unlimited precision arithmetic.
  - Implement basic arithmetic operations for `BigDecimal`: addition, subtraction, multiplication, division, and modulo.
  - Implement comparison operations for `BigDecimal`: less than, greater than, equal to, and not equal to.
  - Implement string representation and parsing for `BigDecimal`.
  - Implement mathematical operations for `BigDecimal`: `sqrt`, `nroot`, `log`, `exp`, and `power` functions.
  - Iimplement rounding functions.
- Implement a simple TOML parser as package `tomlmojo` to refactor tests (PR #63).

### 🦋 Changed in v0.3.0

- Refine the constructors of `BigUInt` (PR #64).
- Improve the method `BigUInt.scale_up_by_power_of_10()` (PR #72).

### 🛠️ Fixed in v0.3.0

- Fix a bug in `BigUInt` multiplication where the calcualtion of carry is mistakenly skipped if a word of x2 is zero (PR #70).

## 20250401 (v0.2.0)

Version 0.2.0 marks a significant expansion of DeciMojo with the introduction of `BigInt` and `BigUInt` types, providing unlimited precision integer arithmetic to complement the existing fixed-precision `Decimal` type. Core arithmetic functions for the `Decimal` type have been completely rewritten using Mojo 25.2's `UInt128`, delivering substantial performance improvements. This release also extends mathematical capabilities with advanced operations including logarithms, exponentials, square roots, and n-th roots for the `Decimal` type. The codebase has been reorganized into a more modular structure, enhancing maintainability and extensibility. With comprehensive test coverage, improved documentation in multiple languages, and optimized memory management, v0.2.0 represents a major advancement in both functionality and performance for numerical computing in Mojo.

### ⭐️ New in v0.2.0

- Add comprehensive `BigInt` and `BigUInt` implementation with unlimited precision integer arithmetic.
- Implement full arithmetic operations for `BigInt` and `BigUInt`: addition, subtraction, multiplication, division, modulo and power operations.
- Support both floor division (round toward negative infinity) and truncate division (round toward zero) semantics for mathematical correctness.
- Add complete comparison operations for `BigInt` with proper handling of negative values.
- Implement efficient string representation and parsing for `BigInt` and `BigUInt`.
- Add advanced mathematical operations for `Decimal`: square root and n-th root.
- Add logarithm functions for `Decimal`: natural logarithm, base-10 logarithm, and logarithm with arbitrary base.
- Add exponential function and power function with arbitrary exponents for `Decimal`.

### 🦋 Changed in v0.2.0

- Completely re-write the core arithmetic functions for `Decimal` type using `UInt128` introduced in Mojo 25.2. This significantly improves the performance of `Decimal` operations.
- Improve memory management system to reduce allocations during calculations.
- Reorganize codebase with modular structure (decimal, arithmetics, comparison, exponential).
- Enhance `Decimal` comparison operators for better handling of edge cases.
- Update internal representation of `Decimal` for better precision handling.

### ❌ Removed in v0.2.0

- Remove deprecated legacy string formatting methods.
- Remove redundant conversion functions that were replaced with a more unified API.

### 🛠️ Fixed in v0.2.0

- Fix edge cases in division operations with zero and one.
- Correct sign handling in mixed-sign operations for both `Decimal`.
- Fix precision loss in repeated addition/subtraction operations.
- Correct rounding behavior in edge cases for financial calculations.
- Address inconsistencies between operator methods and named functions.

### 📚 Documentation and testing in v0.2.0

- Add comprehensive test suite for `BigInt` and `BigUInt` with over 200 test cases covering all operations and edge cases.
- Create detailed API documentation for both `Decimal` and `BigInt`.
- Add performance comparison benchmarks between DeciMojo and Python's decimal/int implementation.
- Update multi-language documentation to include all new functionality (English and Chinese).
- Include clear explanations of division semantics and other potentially confusing numerical concepts.
