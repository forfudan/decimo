# Decimo changelog

This is a list of changes for the Decimo package (formerly DeciMojo).

## 20260514 (v0.10.0)

Decimo v0.10.0 updates the codebase to **Mojo v1.0.0b1** and marks the **"polish and parity"** phase. This release introduces four major additions.

First, the **`Decimal128`** API reaches feature parity with `BigDecimal` and Python's `decimal.Decimal` / IEEE 754: `fma()`, `__divmod__()`, `from_decimal(BigDecimal)`, `cbrt()`, `normalize()`, `__hash__()`, `same_quantum()`, `max` / `min` / `clamp`, `trunc` / `floor` / `ceil` / `fract` / `signum` / `unpack`, `__bool__` / `__pos__`, and a unified `to_string` family with `scientific` / `engineering` / `delimiter` keywords. The `nan` / `inf` values are removed — `Decimal128` is now a strict finite type — and the arithmetic and string hot paths are heavily optimised.

Second, **`BigDecimal`** operator semantics are aligned with Python's `decimal.Decimal`: `+`, `-`, `*` now round HALF_EVEN to the default precision (`PRECISION = 28`) instead of returning unrounded results. New explicit-precision methods `add(other, precision=0)` / `subtract(...)` / `multiply(...)` (and `*_inplace` variants) let callers choose between exact and rounded arithmetic. Internal `pi_machin` / `exp` / `ln` / trig sites switch to the exact `*_inplace` path, and the **CLI calculator's RPN evaluator** now honors `--precision` end to end.

Third, the **CLI calculator** is now distributed as a self-contained binary. A new `release_cli` workflow builds tarballs for **macOS arm64** and **Linux x86_64** (Mojo runtime bundled, `rpath` patched) and publishes them via the [`forfudan/tap`](https://github.com/forfudan/homebrew-tap) Homebrew tap — `brew install forfudan/tap/decimo` and Mojo / Pixi are no longer required on the user's machine. The CLI itself gains a Mojo-native line editor **`limo`** (REPL editing, history, cursor movement); pipe / stdin and file modes (`-F`); shell-completion docs for Bash / Zsh / Fish; REPL info commands (`:`, `?`, `$`, `:q`, `:info`); the `ans` variable; user-defined variables; a `:100` precision shortcut; and case-insensitive input.

Fourth, the codebase gains two new core types and a reworked error system. **`BigFloat`** is an arbitrary-precision binary floating-point type backed by **GMP / MPFR** through a thin C wrapper (`src/decimo/gmp/gmp_wrapper.c`, `src/decimo/bigfloat/mpfr_wrapper.mojo`); every operation is a single MPFR call against a pooled `mpfr_t` handle, precision is in decimal digits with 64 guard bits added internally, and the type is the right choice when MPFR-quality transcendentals or a wider exponent range than `BigDecimal` are wanted. MPFR/GMP must be present at runtime (PR #190, #191). **`Rational`** is a new exact rational number type, stored as a reduced fraction of two `Integer`s (PR #214). The **error system** replaces the catch-all `DecimoError` with concrete types such as `RuntimeError`, makes `message` and `function` mandatory, and renders coloured errors with auto-inferred shortened-relative file/line info (PR #195, #196, #198, #200); `raises:` docstring sections are audited (PR #199) and every public symbol now carries a docstring (PR #194).

### ⭐️ New in v0.10.0

**New core types:**

1. New **`BigFloat`** type (alias `BFlt`, `Float`) — arbitrary-precision **binary floating-point** wrapping a single MPFR handle via a C wrapper. Each arithmetic and transcendental operation is a single MPFR call against a pooled `mpfr_t` handle. Precision is specified in decimal digits and converted to bits internally; 64 guard bits are added so the requested decimal digits are correct. Provides `+ - * /`, `sqrt`, `cbrt`, `root`, `pow`, `exp`, `ln`, `log`, `log10`, full trig and hyperbolic suite, comparison and rounding, plus conversion to / from `BigDecimal`. RAII destructor frees the MPFR handle. Optional — requires MPFR/GMP to be installed at runtime; the C wrapper is built via `pixi run buildgmp` (PR #190, #191).
1. New **`Rational`** type — arbitrary-precision exact rational number, stored as a reduced fraction of two `Integer`s. Supports exact arithmetic and comparisons without precision loss (PR #214).

**Decimal128 — feature parity with Python `decimal.Decimal`:**

1. **`fma(other, third)`** — fused multiply-add with a single rounding (IEEE 754-2008 §5.4.1, matches Python `Decimal.fma`). Falls back to the two-step path only when the aligned working coefficient exceeds the 58-digit fast-path cap. Bit-identical to the `BigDecimal` oracle on all 12 cross-language bench cases (PR #241).
1. **`__divmod__(other)`** — single-call `(self // other, self % other)`, amortising the divide pipeline. Supports both `Decimal128` and `Int` right-hand sides; `Int → Dec128` is now `@implicit` (PR #242).
1. **`from_decimal(BigDecimal)`** — quantises a high-precision `BigDecimal` onto the Decimal128 grid (banker's rounding to 28 fractional digits, raises `OverflowError` on integral overflow). Acts as the cross-language bench oracle bridge (PR #239).
1. **`normalize()`**, **`__hash__()`**, **`same_quantum(other)`** — strip trailing zeros, hash for use as dict key / set element, IEEE 754 scale comparison (PR #238).
1. **`max`, `min`, `clamp`** instance methods (PR #230).
1. **`trunc`, `floor`, `ceil`, `fract`, `signum`, `unpack`** — round towards zero / −∞ / +∞, extract fractional part / sign, unpack into coefficient/sign/scale words (PR #227).
1. **`cbrt()`** — convenience cube root, well-defined for negative values via `root()`'s odd-root path.
1. **`__bool__`** and **`__pos__`** (so `if d:`, `Bool(d)`, `+d` all work); `Decimal128` now conforms to `Boolable`.
1. **`is_positive()`**, **`is_odd()`**, **`number_of_trailing_zeros()`** — small introspection helpers, mirroring `BigDecimal`.
1. **`to_scientific_string()`**, **`to_eng_string()`**, **`to_string_with_separators(separator="_")`** — convenience aliases matching the equivalent `BigDecimal` API.
1. **`fit_to_max_coefficient()`** and **`round_coefficient()`** — utility helpers shared by `from_string()` and the arithmetic paths (PR #216).

**CLI calculator & `limo` line editor:**

1. New **`limo`** package — a small Mojo-native line editor used by the REPL for line editing and history navigation (PR #212).
1. Interactive **REPL**: `decimo` with no arguments launches a coloured `decimo>` prompt with per-line error recovery, comment/blank-line skipping, and graceful exit via `exit` / `quit` / Ctrl-D (PR #205).
1. **REPL info commands**: `:` shows current settings, `?` shows help, `$` / `:v` / `:vars` lists variables, `:q` / `:quit` / `:exit` exits (PR #210, #211).
1. **REPL `:info` / `:about` section** — print version, author, license, and project links from inside the REPL (PR #213).
1. **REPL configuration system** — settings commands (`:p`, `:scientific`, etc.) now print the full settings block after every change so the effect is immediately visible; multiple flags can be set on a single line (PR #208).
1. **Variable assignment** in REPL (`x = 1+2`) plus the `ans` variable holding the last result (PR #206).
1. **Pipe / stdin mode**: read expressions from piped stdin, one per line (e.g. `echo "1+2" | decimo`). Comments and blank lines are skipped (PR #203).
1. **File mode** (`--file` / `-F`): evaluate expressions from a file, one per line, sharing all CLI flags (PR #203).
1. **Negative numbers and negative expressions** as positional CLI arguments (PR #201, #202).
1. **Argument parsing polish** — range / value-name / argument-group validation, custom usage line, all short option names upper-cased (PR #201, #203).
1. **Shell completion** documentation for Bash, Zsh, and Fish (`decimo --completions bash|zsh|fish`) (PR #204).
1. **Standalone-precision shortcut** in settings: `:100` is equivalent to `:p 100` (PR #211).
1. Case-insensitive REPL input (`PI`, `Sqrt(2)`, `SIN(1)` all work) (PR #210).

**Error handling:**

1. New **`RuntimeError`** type and other concrete error types replacing the catch-all `DecimoError`; `message` and `function` fields are now mandatory on the base error type (PR #196, #198).
1. Coloured error messages with auto-inferred file name and line number (PR #195); shortened relative paths in error messages to preserve user privacy at compilation (PR #200).
1. Fixed `raises:` sections in docstrings across the codebase to advertise the correct error types (PR #199).

**Distribution:**

1. New **`release_cli`** workflow building self-contained `decimo` CLI tarballs for **macOS arm64** and **Linux x86_64**; published via the `forfudan/tap` Homebrew tap (`brew install forfudan/tap/decimo`).
1. Bundled third-party licenses are now documented in `NOTICE` and shipped in the source tarball (PR #231).

### 🦋 Changed in v0.10.0

**Mojo 1.0.0b1 migration** (PR #243):

1. Retarget the entire codebase to **Mojo v1.0.0b1**: new `def` / `fn` keyword conventions, `String` API changes (e.g. UTF-8 byte iteration), and updated stdlib import paths.
1. Migrate the Decimal128 `power_of_10_unsafe` rodata tables from `StringLiteral` packed bytes to **`comptime InlineArray`**, sidestepping a Mojo 1.0.0b1 regression that mangles `StringLiteral` UTF-8 bytes. Type bridging via zero-cost `rebind[Scalar[dtype]]`.
1. Use **`argmojo` 0.6.0** as a conda dependency instead of fetching from git (`pixi.toml`); CLI build no longer needs an extra fetch step.
1. Test runner (`tests/test.sh`, `tests/test_cli.sh`) auto-builds `tests/decimo.mojopkg` on demand, working around Mojo 1.0.0b1's inability to resolve qualified `decimo.X.Y.foo` references in source-imported builds.

**BigDecimal — operator semantics aligned with Python `decimal.Decimal`:**

1. `+` / `-` / `*` (and reflected / augmented variants) now round **HALF_EVEN to `PRECISION = 28`** by default instead of returning an exact unrounded result. Use the new explicit-precision methods when exact intermediate arithmetic matters.
1. New **exact methods** `add(other, precision=0)`, `subtract(other, precision=0)`, `multiply(other, precision=0)` — `precision=0` (default) returns the exact result, `precision > 0` rounds HALF_EVEN to that many digits (PR #233, #235).
1. New **in-place exact methods** `add_inplace`, `subtract_inplace`, `multiply_inplace` with the same `precision` parameter, for tight loops.
1. **Internal call sites migrated**: `pi_machin`, Newton iterations, Taylor series, and trig range reduction now use the exact `*_inplace` methods, so high-precision π / `ln` / `exp` / trig results are no longer silently capped at 28 digits.
1. **CLI calculator** RPN evaluator now drives `+` / `-` / `*` through `.add(b, working_precision)` etc. so the user-requested `--precision` is honored end to end (previously results were silently capped at 28).
1. Improved numeric string parsing for `BigDecimal` plus extra test sets and a few bug fixes (PR #226).

**Decimal128 — performance:**

1. Hot-path `UInt(128|256)(10) ** k` calls swept to **`power_of_10_unsafe`** rodata indexed loads (~4–12 ns → ~0.8 ns) (PR #224).
1. `from_uint128()` marked `@always_inline` with cold `raise ValueError` blocks split into `@no_inline` helpers; brings `add` to **0.9× `rust_decimal`**, `subtract` to **0.9–1.3× `rust_decimal`**, `divide` to **1.0× `rust_decimal`** on median bench (PR #224).
1. **`exp()` / `ln()` / `log10()`**: rewrite Taylor and range-reduction loops; worst-case ratio drops to **≤ 1.0× `rust_decimal`** across all 42 bench cases (was up to 1.7×). Adds new `cases/{ln,log10,exp}.toml` harnesses (PR #229).
1. **`exp()` 2-tier sub-unit chunker** — 17 precomputed per-tenth and per-hundredth constants halve Taylor iterations on inputs like `exp(π)` (1350 → 770 ns) and improve accuracy 3 ulp → 1 ulp; `exp(0.1)` collapses to a single constant lookup (~25 ns) (PR #229).
1. **`divide()`** — drop redundant rounding-digit padding (PR #237) and switch the inner loop to a school-book long-division layout that avoids slow `UInt256 // UInt256` fallbacks (PR #223).
1. **`add()` / `subtract()`** — reorder branches so the sign-and-scale-aligned hot path runs first; cold cases moved to the tail (PR #220, #222).
1. **`multiply()`** — remove `is_integer()` and `format()` from the hot path; **fix latent rounding bugs** when intermediate scale exceeds 28 (PR #221).
1. Tighter inner loops in `comparison`, `from_string()`, `to_string()` etc. (PR #225); `number_of_bits()` switches to `std.bit.bit_width` and is `@always_inline` (PR #218).

**Decimal128 — API removals and consolidations:**

1. **Removed `nan` and `inf`** values: `Decimal128` is now a strict finite type. `from_words()` updated accordingly (PR #215).
1. **Consolidated `to_string_scientific()` into `to_string()`**: `to_string()` now takes `scientific: Bool = False`, `engineering: Bool = False`, `delimiter: String = ""`, mirroring `BigDecimal.to_string`. Adds engineering notation as a new code path (`Decimal128("0.5").to_string(engineering=True) == "500E-3"`).
1. **Removed `Decimal128.copy()` / `clone()`**: trivial and unused. `Decimal128` is `TrivialRegisterPassable`, so `var b = a` is the idiomatic copy.
1. **Removed `Decimal128.print_internal_representation()`**: one-line wrapper, unused. Use `print(x.internal_representation())` directly.

**BigInt:**

1. Rewrite type conversion from all integral scalar types (`Int`, `UInt`, `IntLiteral`, `Scalar[DType.intN]`, `Scalar[DType.uintN]`) so that every integral scalar can be converted to `BigInt` / `BigUInt` correctly, including the corner case of `Int.MIN` and signed-to-unsigned narrowing (PR #189).

### 🐛 Fixed in v0.10.0

1. **`BigDecimal.to_string(force_plain=True)` dropping trailing zeros for `scale < 0`**: `BigDecimal("1e40").to_string(force_plain=True)` previously returned `"1"` instead of the full 41-digit integer, silently producing a wrong value when re-parsed (e.g. via `Decimal128.from_decimal()`).
1. **`Decimal128.multiply()`**: latent rounding bugs affecting products whose intermediate scale exceeded 28 (PR #221).

### 📚 Docs, tests, and benchmarks in v0.10.0

1. Ensure all functions, fields, and constants have docstrings; eliminates `mojo doc` warnings (PR #194).
1. Reorganise the `docs/` folder and update user-facing manuals (PR #207).
1. Add planning documents `docs/plans/gmp_integration.md` (kicks off the GMP/MPFR integration that lands as `BigFloat`) and `docs/plans/decimal128_enhancement.md` (roadmap for Decimal128 parity work in this release) (PR #190, #193).
1. Refactor the GitHub Actions unit-test workflow to use caching for faster CI (PR #234).
1. Consolidate the Decimal128 test suites into fewer files (`test_decimal128_arithmetics.mojo`, `test_decimal128_creation.mojo`, etc.) for faster compilation (PR #228).
1. Refactor cross-language benchmark harness to include **Rust (`rust_decimal`)**, **C# (`System.Decimal`)**, and **VB.NET** (PR #219); `BigDecimal` acts as the high-precision oracle for `ln` / `log10` / `exp` (PR #229).
1. Add **CLI performance benchmarks** comparing correctness and timing against `bc` and `python3` across 47 cases — all results match to 15 significant digits; `decimo` is **3–4× faster than `python3 -c`** (PR #204).
1. Refactor BigDecimal benchmark suites (PR #232); add edge-case tests for `compare_absolute()` (PR #217); refactor test files to a CLI argument style (PR #209).
1. Document bundled third-party libraries in `NOTICE` and ship their licenses in the source tarball (PR #231).

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
