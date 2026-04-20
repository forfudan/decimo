# Decimal128 Enhancement Plan

> **Date**: 2026-04-08
> **Target**: decimo >=0.9.0
> **Mojo Version**: >=0.26.2
>
> 子曰工欲善其事必先利其器
> The mechanic, who wishes to do his work well, must first sharpen his tools -- Confucius

I did a thorough audit of `src/decimo/decimal128/` and compared it against other 128-bit fixed-precision decimal libraries — C# [`System.Decimal`](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Decimal.DecCalc.cs), Rust [`rust_decimal`](https://github.com/paupino/rust-decimal), Apache Arrow [`Decimal128`](https://github.com/apache/arrow/blob/main/cpp/src/arrow/util/basic_decimal.h), and Go [`govalues/decimal`](https://github.com/govalues/decimal). This document records everything I found: correctness bugs, performance bottlenecks, and improvement opportunities.

Scope: only 128-bit (or near-128-bit) fixed-precision, non-floating-point decimal types. Arbitrary-precision decimals (Python `decimal.Decimal`, Java `BigDecimal`) are out of scope — they are covered by `BigDecimal`. IEEE 754 decimal128 is also out of scope — it is a floating-point format with discontinuous representation, not comparable to our fixed-point design.

## 1. Cross-Language Comparison

### 1.1 Storage & Layout

| Feature                | Decimo Decimal128    | C# System.Decimal    | Rust rust_decimal    | Arrow Decimal128           | Go govalues/decimal             |
| ---------------------- | -------------------- | -------------------- | -------------------- | -------------------------- | ------------------------------- |
| Total bits             | 128                  | 128                  | 128                  | 128                        | ~128 (bool+uint64+int, may pad) |
| Coefficient storage    | 96-bit (3×UInt32 LE) | 96-bit (3×UInt32 LE) | 96-bit (3×UInt32 LE) | 128-bit signed two's compl | 64-bit unsigned                 |
| Max coefficient        | 2^96 − 1             | 2^96 − 1             | 2^96 − 1             | 10^38 − 1                  | 10^19 − 1                       |
| Bound type             | Binary               | Binary               | Binary               | Decimal                    | Decimal                         |
| Max significant digits | 29*                  | 29*                  | 29*                  | 38                         | 19                              |
| Scale range            | 0–28                 | 0–28                 | 0–28                 | User-defined               | 0–19                            |
| Sign storage           | Bit 31 of flags      | Bit 31 of flags      | Bit 31 of flags      | Two's complement           | Bool field                      |
| Endianness             | Little-endian        | Little-endian        | Little-endian        | Platform-native            | N/A                             |

\* 29 digits, but the leading digit can only be 0–7 (since 10^29 − 1 > 2^96 − 1). This is pretty dirty and difficult to handle. I think the current implmention is not the most optimized. Need to check and refine.

Decimo, C#, and Rust share the same layout — a proven design. Arrow and govalues use a fundamentally different approach with decimal-bounded coefficients (10^p − 1 instead of 2^N − 1), which gives them cleaner digit semantics at the cost of unused bit range.

### 1.2 Special Values

| Feature       | Decimo             | C#         | Rust | Arrow | Go govalues |
| ------------- | ------------------ | ---------- | ---- | ----- | ----------- |
| +Infinity     | ✗ (removed — §3.1) | ✗ (throws) | ✗    | ✗     | ✗           |
| −Infinity     | ✗ (removed)        | ✗          | ✗    | ✗     | ✗           |
| NaN           | ✗ (removed — §3.1) | ✗          | ✗    | ✗     | ✗           |
| Negative zero | ✗                  | ✗          | ✗    | ✗     | ✗           |
| Subnormals    | ✗                  | ✗          | ✗    | ✗     | ✗           |

None of the comparable 128-bit fixed-precision libraries support NaN or Infinity. We removed our broken NaN/Infinity support (§3.1) to match the established paradigm — all four comparable libraries simply raise errors for undefined operations.

### 1.3 Rounding Modes

| Mode                 | Decimo | C#                       | Rust        | Arrow           | Go govalues    |
| -------------------- | ------ | ------------------------ | ----------- | --------------- | -------------- |
| HALF_EVEN (banker's) | ✓      | ✓ (default)              | ✓ (default) | ✓ (default)     | ✓ (default)    |
| HALF_UP              | ✓      | ✓ (`AwayFromZero`)       | ✓           | ✓ (`HALF_UP`)   | ✓ (`HalfUp`)   |
| HALF_DOWN            | ✓      | ✗                        | ✓           | ✓ (`HALF_DOWN`) | ✓ (`HalfDown`) |
| UP (away from zero)  | ✓      | ✓ (`AwayFromZero`)       | ✓           | ✓ (`UP`)        | ✓ (`Up`)       |
| DOWN (truncate)      | ✓      | ✓ (`ToZero`)             | ✓           | ✓ (`DOWN`)      | ✓ (`Down`)     |
| CEILING              | ✓      | ✓ (`ToPositiveInfinity`) | ✓           | ✓ (`CEILING`)   | ✓ (`Ceiling`)  |
| FLOOR                | ✓      | ✓ (`ToNegativeInfinity`) | ✓           | ✓ (`FLOOR`)     | ✓ (`Floor`)    |

All five libraries (including us) support these 7 rounding modes. We are on par.

### 1.4 Arithmetic Coverage

| Operation            | Decimo          | C#               | Rust       | Arrow     | Go govalues  |
| -------------------- | --------------- | ---------------- | ---------- | --------- | ------------ |
| add                  | ✓               | ✓                | ✓          | ✓         | ✓            |
| subtract             | ✓ (via add)     | ✓                | ✓          | ✓         | ✓            |
| multiply             | ✓               | ✓                | ✓          | ✓         | ✓            |
| divide               | ✓               | ✓                | ✓          | ✓         | ✓ (`Quo`)    |
| truncate_divide      | ✓               | ✓ (`Truncate`)   | ✓          | ✗         | ✓ (`QuoRem`) |
| modulo               | ✓               | ✓ (`%`)          | ✓          | ✗         | ✓ (`Rem`)    |
| power (int exponent) | ✓               | ✗ (use Math.Pow) | ✓ (`powi`) | ✗         | ✓ (`PowInt`) |
| sqrt                 | ✓               | ✗                | ✓          | ✗         | ✓            |
| root (nth)           | ✓               | ✗                | ✗          | ✗         | ✗            |
| exp                  | ✓               | ✗                | ✓          | ✗         | ✗            |
| ln                   | ✓               | ✗                | ✓          | ✗         | ✗            |
| log10                | ✓               | ✗                | ✗          | ✗         | ✗            |
| log (arbitrary base) | ✓               | ✗                | ✗          | ✗         | ✗            |
| abs                  | ✓               | ✓                | ✓          | ✓         | ✓            |
| negate               | ✓               | ✓                | ✓          | ✓         | ✓            |
| round                | ✓               | ✓                | ✓          | ✓         | ✓            |
| quantize             | ✓               | ✗                | ✗          | via round | ✗            |
| factorial            | ✓ (0–27 lookup) | ✗                | ✗          | ✗         | ✗            |
| min / max            | ✗               | ✓                | ✓          | ✓         | ✓            |
| normalize            | ✗               | ✗                | ✓          | ✗         | ✗            |

Our arithmetic coverage is the most complete among all five libraries — we are the only one with `root`, `log10`, `log`, and `factorial`. Matching Rust on `exp` and `ln`. The gap is `min`/`max` which every other library provides and we do not.

## 2. The Coefficient Bound Problem

This is probably the biggest architectural concern I found. It affects performance, code complexity, and user-facing semantics.

### 2.1 The Problem

Our max coefficient is 2^96 − 1 = 79,228,162,514,264,337,593,543,950,335. This is a 29-digit number, but the leading digit can only be 0–7. The number 80,000,000,000,000,000,000,000,000,000 (which has only 2 significant digits) is out of range. Meanwhile, all 28-digit numbers fit.

This creates a messy boundary: after every arithmetic operation that might produce a wide result (multiplication, addition with carry, etc.), I need to check whether the coefficient exceeds 2^96 − 1 and, if so, round it down. The rounding itself is non-trivial because the boundary is not at a clean decimal digit — I cannot just drop the last digit. The `fit_to_max_coefficient` + `round_coefficient` pair in `utility.mojo` handles this (replacing the old `truncate_to_max` / `round_to_keep_first_n_digits`).

### 2.2 How Other Libraries Handle This

#### C# System.Decimal — [`ScaleResult()`](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Decimal.DecCalc.cs) (binary bound, same as us)

.NET's approach is heavily optimized. The core function `ScaleResult()` in `Decimal.DecCalc.cs`:

1. Estimates how many decimal digits to remove using `LeadingZeroCount` and the constant `log10(2) ≈ 77/256`.
2. Divides the wide result (stored in a `Buf24`, up to 192 bits) by powers of 10, using `DivByConst()` specialized per constant (10^1 through 10^9) for maximum speed — on 64-bit targets, these use compiler-generated multiply-by-reciprocal.
3. Applies banker's rounding with a sticky bit for lost precision.
4. If rounding causes a carry that pushes above 96 bits again, scales down by 10 one more time.

Additional C# tricks:

- `SearchScale()` — binary search using precomputed `OVFL_MAX_N_HI` constants to find the largest safe scale-up factor.
- `PowerOvflValues[]` — table of largest 96-bit values that won't overflow when multiplied by 10^1 through 10^8.
- `Unscale()` — efficiently removes trailing zeros using binary search: try 10^8, 10^4, 10^2, 10^1, with quick-reject bit checks (e.g., `(low & 0xF) == 0` before trying 10^4).
- `OverflowUnscale()` — when quotient overflows by exactly 1 bit, feeds the carry back in and divides by 10, avoiding a full rescale.

The bottom line: .NET has hundreds of lines of intricate, heavily-optimized code just for this boundary handling. Every multiply that exceeds 96 bits pays for multi-word division.

#### Rust rust_decimal — [Port of .NET](https://github.com/paupino/rust-decimal/blob/master/src/ops/common.rs) (binary bound, same as us)

`rust_decimal` is essentially a Rust port of .NET's `DecCalc`. The `Buf24::rescale()` in `ops/common.rs` is the equivalent of `ScaleResult()`. Same `log10(2) × 256 = 77` trick, same `OVERFLOW_MAX_N_HI` constants, same `POWER_OVERFLOW_VALUES` table.

One difference: `rust_decimal` returns `CalculationResult::Overflow` instead of throwing, letting the caller handle it.

#### Apache Arrow Decimal128 — [256-bit promotion](https://github.com/apache/arrow/blob/main/cpp/src/gandiva/precompiled/decimal_ops.cc) (decimal bound)

Arrow sidesteps the problem entirely by capping at 10^38 − 1 instead of 2^128 − 1. The overflow check is just `abs(value) < 10^precision` — a single comparison against a precomputed constant.

For multiplication that might overflow 128 bits, Arrow promotes to `int256_t` (Boost or compiler `__int128`-based), multiplies, scales down by `10^delta_scale` in one clean division, then converts back. This replaces .NET's iterative divide-and-round loop with a single wide multiplication + one division.

The `FitsInPrecision(precision)` check is trivially a comparison against a table entry. No multi-step rescaling needed for the check itself.

#### Go govalues/decimal — [Two-tier fast path](https://github.com/govalues/decimal/blob/main/decimal.go) (decimal bound)

`govalues/decimal` uses the most elegant approach. Max coefficient = 10^19 − 1 (fits in `uint64`).

1. Fast path: try the operation using native 64-bit arithmetic. If overflow detected (e.g., `z/y != x || z > maxFint`), fall through.
2. Slow path: redo with `big.Int` (arbitrary precision), compute exact result, then round to 19 digits using `rshHalfEven` (right-shift in decimal = divide by 10^N, round half-to-even).

Since the bound IS a power of 10, the rounding is clean: just count digits, divide by 10^excess, round. No awkward non-decimal boundary to deal with.

### 2.3 Comparison

| Strategy            | Used by           | Bound check cost      | Overflow rounding cost                  | Code complexity |
| ------------------- | ----------------- | --------------------- | --------------------------------------- | --------------- |
| Binary (2^96 − 1)   | C#, Rust, Decimo  | Cheap (bit compare)   | Expensive (multi-word ÷10^N, iterative) | High            |
| Decimal (10^38 − 1) | Arrow, SQL Server | Cheap (one compare)   | Cheap (one wide ÷10^N)                  | Low             |
| Decimal (10^19 − 1) | govalues/decimal  | Trivial (one compare) | Trivial (big.Int fallback + round)      | Very low        |

### 2.4 Implications for Decimo

Since we follow the C#/Rust paradigm (binary bound, 2^96 − 1), the coefficient-fitting complexity is inherent. What we have done so far:

1. (Done) Adopted three .NET `ScaleResult` optimisations in the new `round_coefficient()` function: single-division remainder, `2×remainder` vs `divisor` half-comparison, and caller-supplied digit-removal count. The old `truncate_to_max` and `round_to_keep_first_n_digits` are replaced by `fit_to_max_coefficient` + `round_coefficient`. Possible future work: CLZ-based digit estimation (`LeadingZeroCount × 77/256`), precomputed `POWER_OVERFLOW_VALUES` table for safe scale-up, and `Unscale()` trailing-zero removal with quick-reject bit checks.

2. Consider decimal bound for a future Decimal256. If I ever widen to full 128-bit coefficient, using 10^38 − 1 as the max (matching Arrow and SQL Server) would eliminate this problem entirely and give us interoperability with Arrow wire format and SQL `decimal(38)`.

3. Document the "29 digits but not 29 nines" behavior clearly. Users should know that "29 digits of precision" really means "28 full digits plus a leading digit 0–7".

### 2.5 Using UInt128/UInt256 as Acceleration Bridge

Mojo now has native `UInt128` and `UInt256` types (via `Scalar[DType.uint128]` and `Scalar[DType.uint256]`). The codebase already uses them — `coefficient()` bitcasts the three UInt32 words to UInt128, and `multiply()` uses UInt256 for intermediate products. But there are more opportunities:

- In `round_coefficient` and `fit_to_max_coefficient`, the divmod operations on UInt128/UInt256 exploit the fact that Mojo compiles to LLVM IR, where UInt128 division on 64-bit targets translates to two hardware `div` instructions (high and low halves). LLVM also fuses the `q = a // b; r = a % b` pattern on identical operands into a single `__udivmodti4` library call (see plan §4.8 for the empirical measurement), so writing `// + %` is already optimal — manual `value - truncated * divisor` rewrites do not help.
- The `number_of_bits` loop (§4.1) could be replaced by casting UInt128 to two UInt64s and using `count_leading_zeros` on the high word — this gives O(1) bit width instead of a 96-iteration loop.
- Arrow's approach of promoting to 256-bit for multiply is directly applicable since we already have UInt256. Instead of the current 3×UInt32 partial-product approach in some code paths, we could do: `UInt256(x_coef) * UInt256(y_coef)`, then scale/truncate the result. This is simpler and likely just as fast since LLVM will optimize the wide multiply.

In short: we already depend on UInt128/UInt256 for the core paths. The opportunity is to use them more consistently and eliminate the remaining manual multi-word arithmetic.

## 3. Correctness Bugs

### 3.1 NaN/Infinity Implementation Was Broken (Removed)

File: `decimal128.mojo`

The NaN/Infinity support had multiple compounding bugs (mask mismatch, `is_zero()` returning True,
no arithmetic propagation). Since no comparable 128-bit fixed-precision library supports NaN or
Infinity (§1.2), we removed NaN/Infinity support entirely. Operations that would produce
undefined results now raise errors, matching C#, Rust, Arrow, and govalues.

Status: **Done** (removed `NAN()`, `NEGATIVE_NAN()`, `INFINITY()`, `NEGATIVE_INFINITY()`,
`NAN_MASK`, `INFINITY_MASK`, `is_nan()`, `is_infinity()` and their callers).

### 3.2 `from_words` Uses `testing.assert_true` in Production Code (Fixed)

File: `decimal128.mojo`, lines ~344, 351

The function used `testing.assert_true` to validate arguments, which panics with a test failure
message rather than raising a recoverable error.

Status: **Done** — replaced with `raise Error(...)` for both scale and coefficient validation.

### 3.3 Division Hardcodes Rounding Behavior

File: `arithmetics.mojo`, inside `divide()`

The long division loop always uses banker's rounding (HALF_EVEN). The function does not accept a rounding mode parameter.

This matches C# and Rust behavior — both hardcode banker's rounding for the `/` operator. Arrow and govalues also default to HALF_EVEN for division. So this is consistent with all comparable libraries and not really a bug.

If I ever want configurable rounding in division, I would add a `divide(x, y, rounding_mode)` overload. Low priority.

### 3.4 `is_one()` Might Be Incomplete

File: used in `exponential.mojo` (e.g., `log()` calls `x.is_one()`)

I should verify `is_one()` handles all representations of 1: `1` (coef=1, scale=0), `1.0` (coef=10, scale=1), `1.00` (coef=100, scale=2), etc. If it only checks `coefficient == 1 and scale == 0`, it misses the other forms.

## 4. Performance Bottlenecks

### 4.1 `number_of_bits()` Used a Loop (Fixed)

File: `utility.mojo`

The original implementation:

```mojo
def number_of_bits(n: UInt128) -> Int:
    var count = 0
    var x = n
    while x > 0:
        count += 1
        x >>= 1
    return count
```

O(n) in bit count — up to 96 iterations for a UInt128. C#'s [`ScaleResult`](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Decimal.DecCalc.cs) uses `LeadingZeroCount`, which is a single hardware instruction on modern CPUs.

Fix (done): delegate to `std.bit.bit_width`, which lowers to LLVM's `count_leading_zeros` intrinsic (single-instruction for ≤ 64-bit operands and two CLZs for 128-bit operands). The function is now O(1) in bit width regardless of input. See §2.5 for the broader use of UInt128/UInt256 as an acceleration bridge.

### 4.2 `power_of_10` Is Not Using Precomputed Constants Efficiently

File: `utility.mojo`

The function had hardcoded return values for n=0 through n=32, but for n=33 through n=56+ it fell back to `ValueType(10) ** n` which computes via loop.

Fix (done): extended the hardcoded constants up to n=58 (the maximum needed for UInt256 products of two 29-digit numbers). The cache layer remains for values beyond the hardcoded range, but in practice n ≤ 58 covers all Decimal128 arithmetic paths.

### 4.3 `round_to_keep_first_n_digits` Lacked .NET-style Optimisations

File: `utility.mojo`

The old `round_to_keep_first_n_digits` had two real inefficiencies compared to
.NET's [`ScaleResult`](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Decimal.DecCalc.cs):

1. **Expensive half-comparison** — the cutoff `5 * power_of_10(n − 1)` required an extra power-of-10 lookup and a wide multiply. .NET instead compares `2 * remainder` against `divisor`, which is a single left-shift.
2. **Redundant `number_of_digits` call** — the function always recomputed the digit count even though most callers already knew it.

A third candidate ("two wide divisions: replace `value % divisor` with `value - truncated * divisor`") was also tried, but the microbenchmark in §4.8 — plus a direct read of the generated ARM64 assembly — showed it does not help. LLVM canonicalizes `urem` to `sub(a, mul(udiv, b))` and CSE-deduplicates the shared `udiv`, so `// + %` and `// + (a - q*b)` lower to identical code (one `___udivti3` call + inline mul/sub). The current `round_coefficient` therefore uses the natural `// + %` form.

Fix (done): introduced `round_coefficient(value, ndigits_to_remove, sign, rounding_mode)` which applies the half-comparison shortcut and takes `ndigits_to_remove` directly so callers that already know the digit count skip the redundant computation. All production call sites migrated; the old function is kept but deprecated.

### 4.4 `ln()` Range Reduction Uses Loops

File: `exponential.mojo`

The `ln()` function reduces input to [0.5, 2.0) by repeatedly dividing by 10, then by 2:

```mojo
while x_reduced > Decimal128(2, 0, 0, 0):
    x_reduced = decimo.decimal128.arithmetics.divide(x_reduced, Decimal128(2, 0, 0, 0))
    halving_count += 1
```

For `ln(1e28)`, this loop runs ~93 times (since 10^28 ≈ 2^93), each doing a full Decimal128 division.

Fix: use the identity `ln(a × 10^n) = ln(a) + n × ln(10)` to strip the scale in one step. Then only the coefficient (which is in [1, 2^96)) needs halving, which could be reduced by computing the bit width and dividing by the appropriate power of 2 in one shot.

### 4.5 `subtract()` Creates a Temporary

File: `arithmetics.mojo`

```mojo
def subtract(x1: Decimal128, x2: Decimal128) raises -> Decimal128:
    return add(x1, negative(x2))
```

Creates a temporary just to flip the sign bit. Probably minor — Decimal128 is 16 bytes and should be in registers. Low priority unless profiling shows otherwise.

### 4.6 Series Computations Cap at 500 Iterations

File: `exponential.mojo`

Both `exp_series` and `ln_series` loop up to 500 with convergence check `term.is_zero()`. In practice they converge in 30–60 iterations. The issue: `is_zero()` triggers only when the term underflows to exactly zero, which may require a few extra iterations beyond when the term is already too small to affect the result.

Fix: break early if the term is smaller than 10^(−29) — it cannot change the result at our precision.

### 4.7 `from_string` optimization

`from_string` processes Digits One at a Time

File: `decimal128.mojo`

```mojo
coef = coef * 10 + digit
```

Each iteration does a UInt128 multiply-by-10 and add.

Fix: batch up to 9 digits into a UInt64, then multiply `coef` by the appropriate power of 10 and add the batch. Reduces 128-bit multiplications from ~29 to ~4 for a max-length number.

---

`Decimal128.from_string()` has its own parsing code, which seems to be highly overlapping with `str.parse_numeric_string()` that is currently used for `BigDecimal.from_string()`.

Consider using `str.parse_numeric_string()` for `Decimal128.from_string()`.

### 4.8 Division Loop: Separate `//` and `%` Operations (Investigated, No Change)

File: `arithmetics.mojo`

The long-division digit-extraction loop in `divide()` executes:

```mojo
digit = rem // x2_coef
rem = rem % x2_coef
```

It looks like two separate 128-bit (or 256-bit) divisions on the same operands, so the natural "optimization" is the trick used in `round_coefficient` (§4.3): replace the second division with `rem - digit * x2_coef`.

**Empirical microbenchmark** (`temp/bench_divmod.mojo`, M-series Apple Silicon, `--debug-level=line-tables -D ASSERT=none`, 200_000 iters per call, best of 3):

| Type    | `q = a // b; r = a % b` | `q = a // b; r = a - q*b` | Winner                    |
| ------- | ----------------------- | ------------------------- | ------------------------- |
| UInt64  | **0.105 ms**            | 0.207 ms                  | `// + %` is **2× faster** |
| UInt128 | 0.547 ms                | 0.519 ms                  | tied (within noise)       |
| UInt256 | **0.660 ms**            | 0.690 ms                  | `// + %` is ~5% faster    |

Why: inspecting `mojo build --emit=asm -O3` output on aarch64 (Apple Silicon) shows that for **both** patterns the compiler emits exactly one division — a single `___udivti3` library call for UInt128 (or one `udiv` instruction for UInt64) — followed by an inline `mul + sub` for the remainder. The mechanism is LLVM's `DivRemPairs` / instruction-combining pass: `urem(a, b)` is canonicalized to `sub(a, mul(udiv(a, b), b))`, and the shared `udiv` is then CSE-deduplicated against the explicit `a // b`. So writing `a % b` does **not** issue a second division; the manual `a - q * b` rewrite gives the compiler nothing extra and is strictly more source code to maintain. (Reference asm: `temp/divmod_isolation.s`, generated from `temp/divmod_isolation.mojo`.)

Note: the `// + %` pattern *is* the canonical way to access divmod in Mojo — there is no separate `divmod` primitive in `std`, and one is not needed.

**Action taken:** kept the `// + %` form unchanged. The only related change was hoisting `UInt256(x2_coef)` out of the UInt256 loop into a single `x2_coef256` local, so the `UInt256(...)` lift no longer runs every iteration.

The `round_coefficient` rewrite (§4.3) used to use the same `value - truncated * divisor` form on the same assumption; it has now been switched back to the natural `// + %` for consistency.

### 4.9 Decimal128 Unit Test Suite Is Surprisingly Slow

Empirical observation: running the Decimal128 suite via `pixi run test decimal128` takes several minutes — anecdotally slower than the heap-based BigDecimal suite. Wall-clock breakdown of representative files (M-series macOS, ASSERT=all + `--debug-level=full`, the flags used by `tests/test.sh`):

| Test file                          | Real (s) | Reported per-test (s) | Cases |
| ---------------------------------- | -------- | --------------------- | ----- |
| `test_decimal128_arithmetics.mojo` | ~7       | 35.9 (test runner)    | 53    |
| `test_decimal128_quantize.mojo`    | ~5       | 30.9 (test runner)    | ~6    |
| `test_decimal128_from_string.mojo` | ~3       | 1.6                   | many  |
| `test_decimal128_comparison.mojo`  | <1       | 0.018                 | 10    |
| `test_decimal128_utility.mojo`     | <1       | 0.04                  | 8     |

For comparison, `test_bigdecimal_arithmetics.mojo` runs in ~12 s real / 94 s reported under the same flags. So the per-test reported numbers from the mojo test runner are **inflated** vs. true wall-clock (likely include JIT/instrumentation overhead under `--debug-level=full`).

Investigated bottlenecks (in priority order):

1. **`-D ASSERT=all --debug-level=full` is 5–7× slower than release.**
   Re-running `test_decimal128_arithmetics.mojo` with `-D ASSERT=none` and no debug flags drops wall-clock from 7.32 s to **1.06 s**. Most of the perceived slowness comes from these flags, which (a) emit full debug info, (b) compile every `debug_assert(...)` into a real branch (and `power_of_10` has many of them), and (c) prevent inlining of the UInt128/UInt256 operations that are everywhere on the hot path. UInt128/UInt256 are software-emulated on aarch64, so missed inlining is especially costly.
   *Recommendation:* keep `-D ASSERT=all --debug-level=full` for CI, but add a fast inner-loop variant (`pixi run testfast` → `-D ASSERT=none` and `--debug-level=line-tables-only`) for development.

2. **Per-file JIT compilation dominates short tests.**
   `tests/test.sh` invokes `mojo run -I src ... <file>` once per test file. Each invocation re-parses the entire `decimo` package and JIT-compiles the test binary (≈ 0.5–1 s of fixed cost per file). With 17 Decimal128 files, that is 10–15 s of pure compile overhead before any test code runs.
   *Recommendation:* either (a) build the test binaries with `mojo build` once and reuse them, or (b) consolidate small files into fewer test binaries. The `mojo test` discovery flow (single binary per package) would also fix this.

3. **TOML parser walks the file char-by-char, allocating heavily.**
   `parse_file` (`src/decimo/toml/parser.mojo:1033`) reads the entire file into a `String`, then `TOMLParser` scans it character-by-character. `expand_value` (`src/decimo/tests.mojo:213`) does additional `String += ch` concatenations inside `{C,N}` pattern expansion, each of which is an O(n) allocation. For TOML files in the hundreds of lines this is a measurable but secondary cost.
   *Recommendation:* use a `StringBuilder`/byte buffer in `expand_value` instead of `+=` on `String`. Lower priority than (1) and (2).

4. **TOML re-parsing within a file (lower priority once 1+2 are addressed).**
   Inside `test_decimal128_from_string.mojo`, the suite is reasonably structured (one `parse_file` call shared via `_run_unary_section`), but other files (e.g. `test_decimal128_arithmetics.mojo`) call `parse_file` once at the top of each test function. With 5 test functions in arithmetics, that's 5 disk reads + 5 parses of the same TOML file per process.
   *Recommendation:* hoist `parse_file(file_path)` into a module-level cache, or pass the parsed `TOMLDocument` into a helper that runs all sections.

5. **`Python.import_module("decimal")` per test function.**
   `test_decimal128_arithmetics` imports `decimal` once in its body, but several other files (and the failure-path `pydecimal.Decimal(...)` calls) repeatedly cross the FFI boundary. Each Python interop call has ~µs overhead and triggers GIL acquisition. Only relevant on failure paths today; impact is small.
   *Recommendation:* keep Python comparisons strictly to failure-debug output; don't add them to hot loops.

6. **`Dec128(string)` (i.e. `from_string`) is the inner-loop allocator.**
   Every TOML test row constructs `Dec128(test_case.a)` + `Dec128(test_case.b)`. Each call walks the input byte-by-byte, doing one UInt128 multiply-add per character (see §4.7). For 53 arithmetic test cases × 2 operands × ~10 chars = ~1000 multiply-adds before any *actual* arithmetic happens. Fixing §4.7 (digit batching) would directly speed up the test suite.

7. **Misleading internal timer.**
   The `PASS [ NN.NNN ]` value emitted by Mojo's test runner does not match `/usr/bin/time` wall-clock — it appears to include compilation/instrumentation cost rather than pure execution time. This makes `test_decimal128_arithmetics` look pathologically slow (35 s reported) when the actual run is ~7 s. Worth keeping in mind when prioritising — the test code itself isn't as bad as the runner suggests; the test *infrastructure* (flags + per-file JIT) is.

Combined fix priority for Phase 3: (1) split the inner-loop dev workflow from the CI flags, (2) consolidate/cached TOML parsing, (3) attack `from_string` (§4.7) since it has independent value beyond tests.

## 5. Improvement Opportunities

### 5.1 Add `__hash__` Support

C# and Rust both support hashing their decimal types. I should implement `__hash__` so Decimal128 can be used as a dictionary key or in sets.

Approach: hash the normalized form (strip trailing zeros, then hash coefficient + scale + sign).

### 5.2 Add `Stringable` / `Representable` Protocol Conformance

Check that we conform to Mojo's `Stringable` and `Representable` traits for `str()` and `repr()`.

### 5.3 Better `from_float` Accuracy

The current `from_float` (Float64) path likely goes through string conversion. Maybe consider exact float decomposition (extracting mantissa and exponent from IEEE 754 double bits).

For reference: Rust [`rust_decimal`](https://github.com/paupino/rust-decimal) uses exact mantissa/exponent extraction from f64 bits.

### 5.4 `min()` / `max()` / `clamp()`

All four comparable libraries provide `min`/`max`. Easy to implement.

### 5.5 Canonicalization / `normalize()`

Strip trailing zeros: `1.200` (coef=1200, scale=3) → `1.2` (coef=12, scale=1). Useful for hashing (§5.1) and reducing coefficient size for faster subsequent arithmetic. Rust [`rust_decimal`](https://docs.rs/rust_decimal/latest/rust_decimal/struct.Decimal.html#method.normalize) has `normalize()`.

### 5.6 Wider Testing for Edge Cases

Some test cases worth adding:

| Test Case                                | Expected Behavior           |
| ---------------------------------------- | --------------------------- |
| `from_words` with scale > 28             | Error (not assertion panic) |
| `from_words` with coefficient > 2^96 − 1 | Error (not assertion panic) |
| `is_one()` with 1.0, 1.00, 1.000         | True                        |
| Max coefficient after multiply           | Correct rounding            |
| 29-digit numbers near 2^96 − 1 boundary  | Correct truncate/round      |

## 6. Priority Summary

| #   | Issue                                            | Severity    | Effort  | Priority | Status |
| --- | ------------------------------------------------ | ----------- | ------- | -------- | ------ |
| 3.1 | NaN/Inf removed                                  | Critical    | Small   | P0       | Done   |
| 3.2 | `from_words` uses `testing.assert_true`          | Medium      | Small   | P1       | Done   |
| 4.2 | `power_of_10` not fully precomputed              | High        | Small   | P1       | Done   |
| 4.3 | `round_to_keep_first_n_digits` lacks .NET tricks | High        | Medium  | P1       | Done   |
| 4.1 | `number_of_bits` loop                            | Medium      | Small   | P2       | Done   |
| 4.8 | Separate `//` and `%` in division loop           | Medium      | Small   | P2       | N/A    |
| 4.7 | `from_string` optimization                       | Medium      | Medium  | P2       | -      |
| 4.4 | `ln()` range reduction loops                     | Medium      | Medium  | P2       | -      |
| 4.9 | Test suite slow (flags + per-file JIT)           | Medium      | Medium  | P2       | -      |
| 5.4 | `min/max/clamp`                                  | Enhancement | Trivial | P3       | -      |
| 5.5 | `normalize()`                                    | Enhancement | Small   | P3       | -      |
| 5.1 | `__hash__`                                       | Enhancement | Small   | P3       | -      |
| 5.6 | Edge case tests                                  | Enhancement | Medium  | P3       | -      |
| 4.5 | `subtract` temporary                             | Low         | Trivial | P4       | -      |
| 4.6 | Series convergence tolerance                     | Low         | Small   | P4       | -      |
| 3.3 | Division rounding mode (configurable)            | Low         | Medium  | P4       | -      |
| 5.3 | Better `from_float`                              | Enhancement | Medium  | P4       | -      |
| 5.2 | `Stringable` conformance                         | Enhancement | Trivial | P4       | -      |

## 7. Execution Order

Phase 1 — correctness: **(Done)**

1. ~~Decide: remove NaN/Infinity or fix them (§3.1).~~ **Done** — removed NaN/Infinity entirely.
2. ~~Fix `from_words` to use `raise Error` instead of `testing.assert_true` (§3.2).~~ **Done.**
3. Add edge case tests (§5.6). (Partially done — `test_round_coefficient` added 19 cases.)

Phase 2 — performance (coefficient bound): **(Mostly done)**

1. ~~Extend `power_of_10` hardcoded constants up to n=58 (§4.2).~~ **Done.**
2. ~~Add .NET-style tricks to rounding: new `round_coefficient` with single-division remainder, cheap half-comparison, and caller-supplied removal count (§4.3).~~ **Done** — all 10 production callers migrated.
3. ~~Replace `number_of_bits` with hardware CLZ via UInt64 split (§4.1).~~ **Done** — now delegates to `std.bit.bit_width` (LLVM `count_leading_zeros`).

Phase 3 — performance (general):

1. Optimize `from_string` digit batching (§4.7).
2. ~~Use single divmod in division loop (§4.8).~~ **Investigated, no change** — microbenchmark showed LLVM already fuses `// + %` into a single divmod; the mul+sub rewrite does not help (and hurts UInt64 by 2×). Only kept the `UInt256(x2_coef)` hoist out of the loop.
3. Improve `ln()` range reduction (§4.4).
4. Address test-suite latency (§4.9): split dev/CI flag profiles, hoist `parse_file` calls, consolidate per-file JIT runs.

Phase 4 — enhancements:

1. Add `min/max/clamp` (§5.4).
2. Add `normalize()` (§5.5).
3. Add `__hash__` (§5.1).
4. Better `from_float` (§5.3).

## Appendix A. Survey of 128-Bit Fixed-Precision Decimal Types

> **Scope:** 128-bit (or near-128-bit) fixed-precision, non-floating-point decimal types across
> programming languages and libraries. This explicitly **excludes** arbitrary-precision decimals
> (Python `decimal.Decimal`, Java `BigDecimal`, Go `shopspring/decimal`, Go `cockroachdb/apd`) and
> IEEE 754 decimal128 (which is a floating-point format with 34-digit significand, exponent range
> −6176 to +6111, and NaN/Infinity/subnormals).

### A.1 Detailed Comparison Table

| Name                 | Language / Platform           | Total Bits                      | Coefficient Storage                              | Max Coefficient                                      | Max Sig. Digits | Scale Range                | NaN / ±Inf |
| -------------------- | ----------------------------- | ------------------------------- | ------------------------------------------------ | ---------------------------------------------------- | --------------- | -------------------------- | ---------- |
| **System.Decimal**   | C# / .NET CLR                 | 128                             | 96-bit unsigned (3×Int32: lo, mid, hi)           | 2^96 − 1 = 79,228,162,514,264,337,593,543,950,335    | 29              | 0–28                       | No         |
| **rust_decimal**     | Rust (crate)                  | 128                             | 96-bit unsigned (3×u32: lo, mid, hi)             | 2^96 − 1 (same as C#)                                | 29              | 0–28                       | No         |
| **VB.NET Decimal**   | VB.NET / .NET CLR             | 128                             | Identical to C# (same CLR type `System.Decimal`) | 2^96 − 1                                             | 29              | 0–28                       | No         |
| **Arrow Decimal128** | Apache Arrow (cross-language) | 128                             | 128-bit two's complement signed integer          | 10^p − 1 (bounded by declared precision p, max p=38) | 38              | User-defined (any integer) | No         |
| **govalues/decimal** | Go (module)                   | 128 (1 bool + 1 uint64 + 1 int) | 64-bit unsigned integer (uint64 coefficient)     | 10^19 − 1 = 9,999,999,999,999,999,999                | 19              | 0–19                       | No         |

Other non-128-bit types for reference:

| Name                          | Language / Platform    | Total Bits     | Coefficient Storage                    | Max Coefficient                                                                   | Max Sig. Digits   | Scale Range            | NaN / ±Inf |
| ----------------------------- | ---------------------- | -------------- | -------------------------------------- | --------------------------------------------------------------------------------- | ----------------- | ---------------------- | ---------- |
| **Swift Decimal** (NSDecimal) | Swift / Foundation     | 160 (20 bytes) | 128-bit mantissa (8×UInt16)            | Up to 38 decimal digits; mantissa is 128 bits but capped at 10^38 − 1 in practice | 38                | Exponent: −128 to +127 | NaN only   |
| **SQL Server decimal(38)**    | T-SQL / SQL Server     | 136 (17 bytes) | 128-bit unsigned integer (4×Int32)     | 10^38 − 1 = 99,999,999,999,999,999,999,999,999,999,999,999,999                    | 38                | 0 to p (max 38)        | No         |
| **Delphi Currency**           | Delphi / Object Pascal | 64             | 64-bit signed integer (scaled by 10^4) | 2^63 − 1 = 922,337,203,685,477.5807                                               | 19 (4 fractional) | Fixed at 4             | No         |

### A.2 Notes on Each Type

#### C# System.Decimal (and VB.NET, F#)

The .NET CLR `System.Decimal` is the reference design that Decimo Decimal128, Rust `rust_decimal`,
and several others copy. Its 128-bit layout packs a 96-bit unsigned coefficient into three 32-bit
words (`lo`, `mid`, `hi`), with a 32-bit flags word encoding: sign in bit 31, scale in bits 16–20
(value 0–28), and bits 0–15 & 21–30 reserved (must be zero).

Constructor: `Decimal(Int32 lo, Int32 mid, Int32 hi, Boolean isNegative, Byte scale)`.

Max value: ±79,228,162,514,264,337,593,543,950,335 (= 2^96 − 1). This is **not** a round decimal
number — the upper bound is a power-of-2 boundary, not 10^29 − 1.

No NaN, no Infinity. `INumberBase<Decimal>.IsNaN()` always returns `false`.

#### Rust rust_decimal

Mirrors the C# layout exactly: `lo: u32, mid: u32, hi: u32` for the 96-bit coefficient, flags word
with sign + scale. `MAX = 79_228_162_514_264_337_593_543_950_335`. Serializes to 16 bytes
(4 bytes flags + 12 bytes coefficient). The `from_parts(lo, mid, hi, negative, scale)` constructor
matches C# directly.

No NaN, no Infinity. The `MathematicalOps` trait adds `sqrt()`, `exp()`, `ln()`, `pow()`, etc.

#### Apache Arrow Decimal128

Fundamentally different from the C#/Rust design. Arrow Decimal128 stores the value as a **128-bit
two's complement signed integer**, not a 96-bit unsigned coefficient. The value represents
`integer_value / 10^scale`, where `precision` (1–38) and `scale` are declared in the schema.

The max representable coefficient for `decimal128(38, 0)` is 10^38 − 1 (= 38 nines), which is
much smaller than 2^127 − 1 ≈ 1.7 × 10^38. Arrow deliberately caps at 10^precision − 1 rather
than using the full bit range, to ensure consistent decimal digit semantics.

Schema definition (Apache Arrow `Schema.fbs`):

```txt
table Decimal { precision: int; scale: int; bitWidth: int = 128; }
```

No NaN, no Infinity. Each column has a single fixed precision and scale.

#### Swift Foundation Decimal (NSDecimal)

Not truly 128-bit — the struct is **160 bits (20 bytes)**. Layout:

- `exponent: Int8` (−128 to +127)
- `lengthFlagsAndReserved: UInt8` (4-bit length, 1-bit isNegative, 1-bit isCompact, 2-bit reserved)
- `reserved: UInt16`
- `mantissa: (UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16)` — 8×UInt16 = 128 bits

The 128-bit mantissa can theoretically hold values up to 2^128 − 1, but the `_length` field (4 bits, max 15) indicates how many of the 8 UInt16 slots are used, and Apple documents the max as 38 significant decimal digits (i.e., effectively capped at 10^38 − 1).

Unlike C# and Rust, Swift Decimal **supports NaN** (`isNaN` property). It does NOT support Infinity in practice — the `isInfinite` property exists (inherited from `FloatingPoint` protocol) but Apple's implementation does not produce or handle Infinity values meaningfully.

#### SQL Server decimal / numeric

SQL Server `decimal(p, s)` with max precision 38. Storage size varies by precision:

| Precision | Storage Bytes |
| --------- | ------------- |
| 1–9       | 5             |
| 10–19     | 9             |
| 20–28     | 13            |
| 29–38     | 17            |

At precision 29–38, the storage is 17 bytes: 1 byte for sign + 16 bytes (128 bits) for the
unsigned integer coefficient. The max value is 10^38 − 1 (38 nines). This is a decimal-bounded
maximum, not a binary one. Valid values range from `-(10^p - 1)` to `+(10^p - 1)`.

No NaN, no Infinity. `decimal` and `numeric` are synonyms; both are fixed precision and scale.

#### Go govalues/decimal

A high-performance, zero-allocation decimal designed for financial systems. Internally uses a `uint64` coefficient (max 10^19 − 1 = 9,999,999,999,999,999,999) with 19-digit precision and scale 0–19. The struct fits in 128 bits total (bool sign + uint64 coefficient + int scale, though Go struct layout may pad slightly).

No NaN, no Infinity, no negative zero, no subnormals. Immutable, panic-free (returns errors). Uses half-to-even rounding by default. Falls back to `big.Int` for intermediate calculations to maintain correctness, but final results are always rounded to 19 digits.

#### Delphi Currency

Only 64 bits, included for completeness. A 64-bit signed integer scaled by 10^4 (i.e., always exactly 4 decimal places). Max value: 922,337,203,685,477.5807. Not truly 128-bit, but it is a notable example of a fixed-point decimal type in the wild.

### A.3 Eliminated Candidates

The following were investigated but **excluded** because they are arbitrary-precision (not fixed-precision within 128 bits):

| Name                   | Language   | Reason for Exclusion                                                                                                           |
| ---------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------ |
| **shopspring/decimal** | Go         | Arbitrary precision; uses `math/big.Int` internally. No fixed bit width.                                                       |
| **cockroachdb/apd**    | Go         | Arbitrary precision; `Decimal.Coeff` is a `BigInt` (wrapper around `big.Int`). Implements the General Decimal Arithmetic spec. |
| **PostgreSQL numeric** | PostgreSQL | Variable-length arbitrary precision. Stored as variable-length array of base-10000 digits. No 128-bit limit.                   |
| **GCC __int128**       | C/C++      | A 128-bit integer, not a decimal type. Could be used to build a decimal library but is not one itself.                         |

### A.4 Critical Analysis: Coefficient Upper Bound Approaches

There are **two fundamentally different approaches** to bounding the coefficient in fixed-precision decimal types:

#### Approach 1: Binary Bound (2^N − 1)

**Used by:** C# System.Decimal, Rust rust_decimal, Decimo Decimal128

The coefficient is an N-bit unsigned integer, and the maximum value is the full binary range 2^N − 1. For 96-bit coefficients:

- Max = 2^96 − 1 = **79,228,162,514,264,337,593,543,950,335**
- This is a 29-digit number, but the leading digit can only be 0–7 (since 10^29 − 1 > 2^96 − 1)
- Consequence: The first significant digit is constrained. You get 29 digits only when the leading
  digit is ≤ 7. You get the full 0–9 range only for 28-digit numbers.

**Pros:**

- Natural fit for hardware — the coefficient is just a native (multi-word) integer
- Simple bounds check: just compare against 2^96 − 1
- Slightly larger range than 10^28 − 1 (about 7.9× more values in the 29th digit range)

**Cons:**

- The "truncate-to-max" problem: when an operation produces a coefficient > 2^96 − 1, you must either raise an error or round. The boundary is not at a clean decimal digit boundary, which makes rounding semantics awkward. E.g., 80,000,000,000,000,000,000,000,000,000 (8×10^28) is out of range, even though it only needs 2 significant digits.
- Non-uniform digit range: the 29th digit has range 0–7, not 0–9. This is confusing for users.

#### Approach 2: Decimal Bound (10^p − 1)

**Used by:** Apache Arrow Decimal128, SQL Server decimal(38), Swift Decimal, govalues/decimal

The coefficient is bounded by 10^p − 1, where p is the declared precision. Even if the underlying storage has more bits available, values above 10^p − 1 are not representable.

For Arrow/SQL precision 38:

- Max = 10^38 − 1 = **99,999,999,999,999,999,999,999,999,999,999,999,999** (38 nines)
- Fits in 128 bits (10^38 − 1 < 2^127 − 1), with ~90 bits of the 128 used
- Every digit position has the full 0–9 range

For govalues/decimal precision 19:

- Max = 10^19 − 1 = **9,999,999,999,999,999,999** (19 nines)
- Fits in a single uint64 (10^19 − 1 < 2^64 − 1), with ~63 bits of the 64 used

**Pros:**

- Clean decimal semantics: every digit position has the full 0–9 range
- No "truncate-to-max" confusion at non-decimal boundaries
- Precision is exactly p significant decimal digits, no asterisks
- Easier to reason about for financial applications

**Cons:**

- Wastes some of the available bit range (Arrow uses ~126.5 of 128 bits; govalues uses ~63.1 of 64)
- Bounds checking requires a comparison against a decimal constant, not a simple overflow check

#### Implications for Decimo

Decimo follows the C#/Rust approach (binary bound, 2^96 − 1). This means:

1. **The coefficient-fitting logic IS a concern:** When multiplying two 29-digit numbers, the intermediate product can have up to 58 digits. If the result after scale adjustment still exceeds 2^96 − 1, we must handle it. The current behavior should be documented: do we raise an error, or do we round to fit?

2. **The non-uniform 29th digit** should be documented. Users may expect that "29 digits of precision" means they can represent any 29-digit number, but `99,999,999,999,999,999,999,999,999,999` (29 nines) = ~10^29 is > 2^96 and therefore out of range. The actual guarantee is "28 full digits plus a leading digit 0–7".

3. **If we ever consider a Decimal256 or widen to full 128-bit coefficient:** We should evaluate whether to switch to the decimal-bounded approach (10^38 − 1 with 128-bit storage, matching Arrow/SQL) vs. staying with binary bound (2^128 − 1, giving ~38.5 digits with non-uniform leading digit). The Arrow/SQL approach would give us exact compatibility with SQL Server `decimal(38)` and Arrow `Decimal128` wire format, which is a significant interoperability advantage.
