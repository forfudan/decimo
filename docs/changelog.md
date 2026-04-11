# Decimo changelog

This is a list of changes for the Decimo package (formerly DeciMojo).

## Unreleased - under development

### ⭐️ New in v0.10.0

**CLI Calculator:**

1. Add **pipe/stdin mode**: read expressions from standard input, one per line, when no positional argument is given and stdin is piped (e.g. `echo "1+2" | decimo`, `printf "pi\nsqrt(2)" | decimo -P 100`). Blank lines and comment lines (starting with `#`) are automatically skipped.
1. Add **file mode**: use `--file` / `-F` flag to evaluate expressions from a file, one per line (e.g. `decimo -F expressions.dm -P 50`). Comments (`#`), inline comments, and blank lines are skipped. All CLI flags (precision, formatting, rounding) apply to every expression.
1. Add **shell completion** documentation for Bash, Zsh, and Fish (`decimo --completions bash|zsh|fish`).
1. Add **CLI performance benchmarks** (`benches/cli/bench_cli.sh`) comparing correctness and timing against `bc` and `python3` across 47 comparisons — all results match to 15 significant digits; `decimo` is 3–4× faster than `python3 -c`.

### 🦋 Changed in v0.10.0

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

fn main() raises:
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

fn main() raises:
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
