# Decimal128 Enhancement Plan

> **Date**: 2026-04-08
> **Target**: decimo >=0.9.0
> **Mojo Version**: >=0.26.2
>
> 子曰工欲善其事必先利其器
> The mechanic, who wishes to do his work well, must first sharpen his tools -- Confucius

I did a thorough audit of `src/decimo/decimal128/` and compared it against other 128-bit fixed-precision decimal libraries - C# [`System.Decimal`](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Decimal.DecCalc.cs), Rust [`rust_decimal`](https://github.com/paupino/rust-decimal), Apache Arrow [`Decimal128`](https://github.com/apache/arrow/blob/main/cpp/src/arrow/util/basic_decimal.h), and Go [`govalues/decimal`](https://github.com/govalues/decimal). This document records everything I found: correctness bugs, performance bottlenecks, and improvement opportunities.

Scope: only 128-bit (or near-128-bit) fixed-precision, non-floating-point decimal types. Arbitrary-precision decimals (Python `decimal.Decimal`, Java `BigDecimal`) are out of scope - they are covered by `BigDecimal`. IEEE 754 decimal128 is also out of scope - it is a floating-point format with discontinuous representation, not comparable to our fixed-point design.

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

\* 29 digits, but the leading digit can only be 0–7 (since 10^29 − 1 > 2^96 − 1). This is pretty dirty and difficult to handle. I think the current implementation is not the most optimized. Need to check and refine.

Decimo, C#, and Rust share the same layout - a proven design. Arrow and govalues use a fundamentally different approach with decimal-bounded coefficients (10^p − 1 instead of 2^N − 1), which gives them cleaner digit semantics at the cost of unused bit range.

### 1.2 Special Values

| Feature       | Decimo             | C#         | Rust | Arrow | Go govalues |
| ------------- | ------------------ | ---------- | ---- | ----- | ----------- |
| +Infinity     | ✗ (removed - §3.1) | ✗ (throws) | ✗    | ✗     | ✗           |
| −Infinity     | ✗ (removed)        | ✗          | ✗    | ✗     | ✗           |
| NaN           | ✗ (removed - §3.1) | ✗          | ✗    | ✗     | ✗           |
| Negative zero | ✗                  | ✗          | ✗    | ✗     | ✗           |
| Subnormals    | ✗                  | ✗          | ✗    | ✗     | ✗           |

None of the comparable 128-bit fixed-precision libraries support NaN or Infinity. We removed our broken NaN/Infinity support (§3.1) to match the established paradigm - all four comparable libraries simply raise errors for undefined operations.

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

Our arithmetic coverage is the most complete among all five libraries - we are the only one with `root`, `log10`, `log`, and `factorial`. Matching Rust on `exp` and `ln`. The gap is `min`/`max` which every other library provides and we do not.

## 2. The Coefficient Bound Problem

This is probably the biggest architectural concern I found. It affects performance, code complexity, and user-facing semantics.

### 2.1 The Problem

Our max coefficient is 2^96 − 1 = 79,228,162,514,264,337,593,543,950,335. This is a 29-digit number, but the leading digit can only be 0–7. The number 80,000,000,000,000,000,000,000,000,000 (which has only 2 significant digits) is out of range. Meanwhile, all 28-digit numbers fit.

This creates a messy boundary: after every arithmetic operation that might produce a wide result (multiplication, addition with carry, etc.), I need to check whether the coefficient exceeds 2^96 − 1 and, if so, round it down. The rounding itself is non-trivial because the boundary is not at a clean decimal digit - I cannot just drop the last digit. The `fit_to_max_coefficient` + `round_coefficient` pair in `utility.mojo` handles this (replacing the old `truncate_to_max` / `round_to_keep_first_n_digits`).

### 2.2 How Other Libraries Handle This

#### C# System.Decimal - [`ScaleResult()`](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Decimal.DecCalc.cs) (binary bound, same as us)

.NET's approach is heavily optimized. The core function `ScaleResult()` in `Decimal.DecCalc.cs`:

1. Estimates how many decimal digits to remove using `LeadingZeroCount` and the constant `log10(2) ≈ 77/256`.
2. Divides the wide result (stored in a `Buf24`, up to 192 bits) by powers of 10, using `DivByConst()` specialized per constant (10^1 through 10^9) for maximum speed - on 64-bit targets, these use compiler-generated multiply-by-reciprocal.
3. Applies banker's rounding with a sticky bit for lost precision.
4. If rounding causes a carry that pushes above 96 bits again, scales down by 10 one more time.

Additional C# tricks:

- `SearchScale()` - binary search using precomputed `OVFL_MAX_N_HI` constants to find the largest safe scale-up factor.
- `PowerOvflValues[]` - table of largest 96-bit values that won't overflow when multiplied by 10^1 through 10^8.
- `Unscale()` - efficiently removes trailing zeros using binary search: try 10^8, 10^4, 10^2, 10^1, with quick-reject bit checks (e.g., `(low & 0xF) == 0` before trying 10^4).
- `OverflowUnscale()` - when quotient overflows by exactly 1 bit, feeds the carry back in and divides by 10, avoiding a full rescale.

The bottom line: .NET has hundreds of lines of intricate, heavily-optimized code just for this boundary handling. Every multiply that exceeds 96 bits pays for multi-word division.

#### Rust rust_decimal - [Port of .NET](https://github.com/paupino/rust-decimal/blob/master/src/ops/common.rs) (binary bound, same as us)

`rust_decimal` is essentially a Rust port of .NET's `DecCalc`. The `Buf24::rescale()` in `ops/common.rs` is the equivalent of `ScaleResult()`. Same `log10(2) × 256 = 77` trick, same `OVERFLOW_MAX_N_HI` constants, same `POWER_OVERFLOW_VALUES` table.

One difference: `rust_decimal` returns `CalculationResult::Overflow` instead of throwing, letting the caller handle it.

#### Apache Arrow Decimal128 - [256-bit promotion](https://github.com/apache/arrow/blob/main/cpp/src/gandiva/precompiled/decimal_ops.cc) (decimal bound)

Arrow sidesteps the problem entirely by capping at 10^38 − 1 instead of 2^128 − 1. The overflow check is just `abs(value) < 10^precision` - a single comparison against a precomputed constant.

For multiplication that might overflow 128 bits, Arrow promotes to `int256_t` (Boost or compiler `__int128`-based), multiplies, scales down by `10^delta_scale` in one clean division, then converts back. This replaces .NET's iterative divide-and-round loop with a single wide multiplication + one division.

The `FitsInPrecision(precision)` check is trivially a comparison against a table entry. No multi-step rescaling needed for the check itself.

#### Go govalues/decimal - [Two-tier fast path](https://github.com/govalues/decimal/blob/main/decimal.go) (decimal bound)

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

Mojo now has native `UInt128` and `UInt256` types (via `Scalar[DType.uint128]` and `Scalar[DType.uint256]`). The codebase already uses them - `coefficient()` bitcasts the three UInt32 words to UInt128, and `multiply()` uses UInt256 for intermediate products. But there are more opportunities:

- In `round_coefficient` and `fit_to_max_coefficient`, the divmod operations on UInt128/UInt256 exploit the fact that Mojo compiles to LLVM IR, where UInt128 division on 64-bit targets translates to one `___udivti3` library call. LLVM canonicalizes `a % b` to `sub(a, mul(udiv(a, b), b))` and CSE-deduplicates the shared `udiv` against the explicit `a // b`, so writing `// + %` already lowers to a single divmod (see plan §4.7 for the asm-level verification). Manual `value - truncated * divisor` rewrites do not help and on UInt64 are 2× slower.
- The `number_of_bits` loop (§4.1) could be replaced by casting UInt128 to two UInt64s and using `count_leading_zeros` on the high word - this gives O(1) bit width instead of a 128-iteration loop (~96 in practice for Decimal128 coefficients).
- Arrow's approach of promoting to 256-bit for multiply is directly applicable since we already have UInt256. Instead of the current 3×UInt32 partial-product approach in some code paths, we could do: `UInt256(x_coef) * UInt256(y_coef)`, then scale/truncate the result. This is simpler and likely just as fast since LLVM will optimize the wide multiply.

In short: we already depend on UInt128/UInt256 for the core paths. The opportunity is to use them more consistently and eliminate the remaining manual multi-word arithmetic.

### 2.6 Proposed: Steal Bits from Flags Word to Eliminate the Bound Mismatch

The current 96-bit binary coefficient + 32-bit flags layout (mirroring `System.Decimal`) leaves **24 bits unused** in the flags word (only sign bit + 5-bit scale field are populated; bits 0–15 and 24–30 are unused). The "29 digits but leading 0–7" boundary problem in §2.1 is purely an artifact of holding the coefficient at 96 bits when the flags word has space to spare.

**Proposal:** widen the coefficient field by stealing N unused bits from flags, eliminating the dual binary+decimal boundary check entirely.

| Coefficient bits | Max coefficient |    Full digits | Bits stolen from flags | Wins                                                             |
| ---------------- | --------------- | -------------: | ---------------------: | ---------------------------------------------------------------- |
| 96 (today)       | 2^96 − 1        |       29 (0–7) |                      0 | Status quo; messy boundary                                       |
| 97               | 2^97 − 1        |       30 (0–1) |                      1 | Marginal; still messy                                            |
| **100**          | **10^30 − 1**   | **30 (clean)** |                      4 | **Eliminates §2 boundary; +1 digit precision over .NET/Rust**    |
| **107**          | **10^32 − 1**   | **32 (clean)** |                     11 | **Real competitive edge: +3 digits over .NET/Rust, still clean** |
| 110              | 2^110 − 1       |       33 (0–1) |                     14 | Diminishing returns                                              |

**Recommended target: 107-bit coefficient → 10^32 − 1 (32 full digits, clean decimal bound).**

Trade-offs:

| Aspect                                      | Impact                                                                                                                                                                                                   |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Eliminates §2 architectural concern         | ✓ — `fit_to_max_coefficient` becomes a single `digits ≤ 32` check; no more "binary bound + leading-digit check" combo.                                                                                   |
| Beats .NET/Rust on precision                | ✓ — 32 full digits vs their 28-full-plus-0-to-7 ≈ 28.9 digits. A real, user-visible competitive advantage.                                                                                               |
| Hot-path arithmetic perf                    | Zero impact — coefficient is already a `UInt128` internally (per §4.9.1 probe (2): `coefficient()` is `@always_inline` bitcast, ~0 ns).                                                                  |
| `fit_to_max_coefficient` perf               | **Faster** — drops one of the two boundary checks. Called after every multiply / add-with-carry, so this compounds.                                                                                      |
| `number_of_digits` semantics                | Cleaner — full 32-digit range, no leading-digit special case in tests.                                                                                                                                   |
| Cache footprint / `TrivialRegisterPassable` | Unchanged — still 128 bits, still register-passable.                                                                                                                                                     |
| Loses .NET binary-layout interop            | **Not material for decimo.** No C ABI exports; .NET `Decimal` itself isn't stable C-ABI-exposed; real interop happens via string / Arrow / Protobuf round-trip, none of which depend on internal layout. |
| `from_words(low, mid, high, flags)` API     | Breaking change — `flags` layout shifts. Migration is mechanical but is a public-API break; bump to a major version.                                                                                     |
| Scale field width                           | Could stay 5 bits (max 31) or widen to 6 bits (max 63) if we want symmetric scale range. Recommend keep at 5 bits (scale 0–31) to match precision.                                                       |
| Phase 4 `normalize()` (§5.4)                | Easier — no leading-digit edge case to worry about.                                                                                                                                                      |
| Test fixtures                               | TOML test cases are decimal-string-based and unaffected. Only `from_words` callers (none in production code; only `tests/test_*_from_words.mojo`) need updates.                                          |

**Action items if accepted:**

1. Define new flag-word layout: bits 0–106 = coefficient (across the existing 96-bit field + 11 stolen bits), bit 31 of flags = sign, bits 24–28 = scale (0–31), other bits reserved.
2. Update `Decimal128.coefficient()`, `from_words()`, `from_uint128()`, scale getter/setter — all `@always_inline` bitcast paths.
3. Replace `fit_to_max_coefficient`'s binary-bound check + leading-digit fix-up with a single decimal-digit-count check against 32.
4. Drop the "29 digits but leading 0–7" wart from §1.1 and §2.1 documentation.
5. Update `MAX_VALUE` constant and any tests asserting it.
6. Re-run cross-language bench (§4.9.3) to confirm no perf regression on `add` / `mul` / `div`. **Expected: small speedup** on overflow-prone paths because `fit_to_max_coefficient` is simpler.
7. Add a migration note to changelog (breaking: `from_words` flag layout, max coefficient widened).

**Recommended priority: P5 (long-term nice-to-have).** This is a *polish* item, not a *competitive* item. Realistic landscape: decimo's audience is Mojo users (rust_decimal is pure Rust with no Mojo bindings; FFI-bridging it is impractical), and 28-digit precision already covers >99% of financial/accounting workloads. 32-digit precision is a clean architectural win that eliminates the §2 boundary wart and would simplify code, but it neither attracts new users nor closes any real gap. Defer until the perf workstream (§4.9) is fully landed and we have spare cycles for an architecturally clean breaking-change release. Until then, keep §2.6 as a documented design proposal, not a roadmap commitment.

## 3. Correctness Bugs

### 3.1 NaN/Infinity Implementation Was Broken (Removed) — Done

File: `decimal128.mojo`. The NaN/Infinity support had multiple compounding bugs (mask mismatch, `is_zero()` returning True, no arithmetic propagation). Since no comparable 128-bit fixed-precision library supports NaN or Infinity (§1.2), we removed the support entirely. Operations that would produce undefined results now raise errors, matching C#, Rust, Arrow, and govalues. Removed: `NAN()`, `NEGATIVE_NAN()`, `INFINITY()`, `NEGATIVE_INFINITY()`, `NAN_MASK`, `INFINITY_MASK`, `is_nan()`, `is_infinity()` and their callers.

### 3.2 `from_words` Uses `testing.assert_true` in Production Code — Done

File: `decimal128.mojo`, lines ~344, 351. The function used `testing.assert_true` to validate arguments, which panics with a test-failure message rather than raising a recoverable error. Replaced with `raise Error(...)` for both scale and coefficient validation.

### 3.3 Division Hardcodes Rounding Behavior — Open (Low)

`arithmetics.mojo` `divide()` always uses banker's rounding (HALF_EVEN). Same as C#/Rust/Arrow/govalues for the `/` operator. If we ever want configurable rounding, add a `divide(x, y, rounding_mode)` overload. Low priority.

## 4. Performance Bottlenecks

### 4.1 `number_of_bits()` Used a Loop — Done

File: `utility.mojo`. The original implementation was an O(n)-bit while-loop over the input — up to 128 iterations on a generic `UInt128`. C#'s [`ScaleResult`](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Decimal.DecCalc.cs) uses `LeadingZeroCount`, which is a single hardware instruction.

Fix: delegate to `std.bit.bit_width`, which lowers to LLVM's `count_leading_zeros` intrinsic (single-instruction for ≤64-bit, two CLZs for 128-bit). Now O(1) in bit width regardless of input. See §2.5 for the broader use of UInt128/UInt256 as an acceleration bridge.

### 4.2 `power_of_10` Not Using Precomputed Constants Efficiently — Done

File: `utility.mojo`. The function had hardcoded return values for n=0–32, but for n=33 onward it fell back to `ValueType(10) ** n` which computes via loop.

Fix: extended hardcoded constants up to n=58 (max needed for UInt256 products of two 29-digit numbers). The cache layer remains for values beyond the hardcoded range, but in practice n ≤ 58 covers all Decimal128 arithmetic paths.

### 4.3 `round_to_keep_first_n_digits` Lacked .NET-style Optimisations — Done

File: `utility.mojo`. Two real inefficiencies vs .NET's [`ScaleResult`](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Decimal.DecCalc.cs):

1. **Expensive half-comparison** — the cutoff `5 * power_of_10(n − 1)` required an extra power-of-10 lookup and a wide multiply. .NET instead compares `2 * remainder` against `divisor` (a single left-shift).
2. **Redundant `number_of_digits` call** — always recomputed even when the caller already knew it.

A third candidate ("replace `value % divisor` with `value - truncated * divisor`") was tried but the microbenchmark in §4.7 plus ARM64 asm inspection showed LLVM canonicalizes `urem` to `sub(a, mul(udiv, b))` and CSE-deduplicates the shared `udiv`, so `// + %` and `// + (a - q*b)` lower to identical code.

Fix: introduced `round_coefficient(value, ndigits_to_remove, sign, rounding_mode)` with the half-comparison shortcut and explicit `ndigits_to_remove`. All 10 production callers migrated; old function deprecated. Also: hoisted `UInt256(x2_coef)` out of the long-division UInt256 loop (the only real win from the §4.7 investigation).

### 4.4 `ln()` Range Reduction Uses Loops

File: `exponential.mojo`, lines 727–746

The `ln()` function reduces input to [0.5, 2.0) in two while-loop stages:

```mojo
# Step 1: divide-by-10 until 0.1 <= m < 10
while m >= decimo.decimal128.constants.M10():
    m = m / decimo.decimal128.constants.M10()
    q += 1

# Step 2: divide-by-2 until 0.5 <= m < 2
while m >= decimo.decimal128.constants.M2():
    m = m / decimo.decimal128.constants.M2()
    p += 1
```

For `ln(1e28)`, Step 1 runs ~28 times (one division per decimal digit) and Step 2 runs ~3–4 more times. Each iteration is a full Decimal128 division - the most expensive primitive in the package.

Fix: use the identity `ln(a × 10^q) = ln(a) + q × ln(10)` and read `q` directly from the input scale + a digit count, replacing Step 1 with a constant-time scale adjustment. Step 2 can be reduced by computing `bit_width(coefficient) − target_width` and dividing by the appropriate `power_of_2` in a single shot. Expected: ~30 divisions → 1 scale-fix + 1 division.

This is now the highest-value remaining performance lever - `ln()` and `log10()` are the slowest non-divide primitives.

### 4.5 Series Computations Cap at 500 Iterations

File: `exponential.mojo`

Both `exp_series` and `ln_series` loop up to 500 with convergence check `term.is_zero()`. In practice they converge in 30–60 iterations. The issue: `is_zero()` triggers only when the term underflows to exactly zero, which may require a few extra iterations beyond when the term is already too small to affect the result.

Fix: break early if the term is smaller than 10^(−29) - it cannot change the result at our precision.

### 4.6 `from_string` optimization

`from_string` processes digits one at a time. File: `decimal128.mojo`, line 543.

```mojo
coef = coef * 10 + digit
```

Each iteration does a UInt128 multiply-by-10 and add.

**Empirical baseline** (`temp/bench_from_string.mojo`, M-series Apple Silicon, 50_000 iters per sample, best of 3):

| Input                                      | Release (`-D ASSERT=none`) | Debug (`-D ASSERT=all --debug-level=full`) |
| ------------------------------------------ | -------------------------- | ------------------------------------------ |
| `1234567890123456789012345678` (28 digits) | 56 ns/call                 | 70 ns/call                                 |
| `12345.67890123456789012345`               | 53 ns/call                 | 66 ns/call                                 |
| `0.0000000000000000000000001234`           | 54 ns/call                 | 71 ns/call                                 |
| `-9999999999999999999999999999`            | 61 ns/call                 | 76 ns/call                                 |
| `1.23456789e15`                            | 28 ns/call                 | 35 ns/call                                 |

At ~50–70 ns/call for full-precision strings the absolute cost is already low. The digit-batching trick (group up to 9 digits into a UInt64 then one `coef * 10^k + batch` per chunk) is a clean 5–7× reduction on the inner loop and would bring us closer to rust_decimal's `FromStr` (~20–30 ns/call). Worth doing, but rank below §4.4 since `ln()`/`log10()` dominate end-to-end runtime in any real workload.

A second, mostly-orthogonal cleanup: `Decimal128.from_string()` reimplements parsing logic that `str.parse_numeric_string()` (used by `BigDecimal.from_string()`) already covers. Switching to the shared scanner would shrink the surface area at no perf cost. Defer until after the digit-batching change so the perf delta is measurable.

### 4.7 Division Loop: Separate `//` and `%` Operations (Investigated, No Change)

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

Why: inspecting `mojo build --emit=asm -O3` output on aarch64 (Apple Silicon) shows that for **both** patterns the compiler emits exactly one division - a single `___udivti3` library call for UInt128 (or one `udiv` instruction for UInt64) - followed by an inline `mul + sub` for the remainder. The mechanism is LLVM's `DivRemPairs` / instruction-combining pass: `urem(a, b)` is canonicalized to `sub(a, mul(udiv(a, b), b))`, and the shared `udiv` is then CSE-deduplicated against the explicit `a // b`. So writing `a % b` does **not** issue a second division; the manual `a - q * b` rewrite gives the compiler nothing extra and is strictly more source code to maintain.

Reproduction recipe: write each pattern as an `@export fn` taking runtime (non-constant) inputs, build with `pixi run mojo build --emit=asm -O3 <file>.mojo -o <file>.s`, then `grep` the output for the function symbols and count `bl ___udivti3` / `udiv` instructions per body - both should appear exactly once.

Note: the `// + %` pattern *is* the canonical way to access divmod in Mojo - there is no separate `divmod` primitive in `std`, and one is not needed.

**Action taken:** kept the `// + %` form unchanged. The only related change was hoisting `UInt256(x2_coef)` out of the UInt256 loop into a single `x2_coef256` local, so the `UInt256(...)` lift no longer runs every iteration.

The `round_coefficient` rewrite (§4.3) used to use the same `value - truncated * divisor` form on the same assumption; it has now been switched back to the natural `// + %` for consistency.

### 4.8 Decimal128 Unit Test Suite Is Surprisingly Slow

Empirical observation: running the Decimal128 suite via `pixi run test decimal128` takes several minutes - anecdotally slower than the heap-based BigDecimal suite. Wall-clock breakdown of representative files (M-series macOS, ASSERT=all + `--debug-level=full`, the flags used by `tests/test.sh`):

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
   Every TOML test row constructs `Dec128(test_case.a)` + `Dec128(test_case.b)`. Each call walks the input byte-by-byte, doing one UInt128 multiply-add per character (see §4.6). For 53 arithmetic test cases × 2 operands × ~10 chars = ~1000 multiply-adds before any *actual* arithmetic happens. Fixing §4.6 (digit batching) would directly speed up the test suite.

7. **Misleading internal timer.**
   The `PASS [ NN.NNN ]` value emitted by Mojo's test runner does not match `/usr/bin/time` wall-clock - it appears to include compilation/instrumentation cost rather than pure execution time. This makes `test_decimal128_arithmetics` look pathologically slow (35 s reported) when the actual run is ~7 s. Worth keeping in mind when prioritising - the test code itself isn't as bad as the runner suggests; the test *infrastructure* (flags + per-file JIT) is.

Combined fix priority for Phase 3: (1) split the inner-loop dev workflow from the CI flags, (2) consolidate/cached TOML parsing, (3) attack `from_string` (§4.6) since it has independent value beyond tests.

### 4.9 Per-Operation Arithmetic Overhead vs Other Libraries (Top Priority)

Direct head-to-head benchmark (`temp/bench_decimo.mojo` vs `temp/rust_compare/`, both built `--release` / `-D ASSERT=none`, 200_000 iters per op, best of 5, M-series Apple Silicon):

| Operation                             | rust_decimal | decimo.Decimal128 | decimo / rust |
| ------------------------------------- | ------------ | ----------------- | ------------- |
| `add` (two mid-scale operands)        | **22 ns**    | 624 ns            | **28×**       |
| `mul` (two mid-scale operands)        | **25 ns**    | 754 ns            | **30×**       |
| `div` (mid-scale dividend / divisor)  | **33 ns**    | 809 ns            | **25×**       |
| `to_string` (mid-scale 25-char value) | **69 ns**    | 515 ns            | 7.5×          |
| `cmp` (two close values)              | **2 ns**     | 13 ns             | 6×            |

> Let's keep this table with the original numbers for comparison. After each optimization step, we add a new table below with the updated numbers. We also have a brief table whose columns are historical decimo/rust ratios, so we can track the improvement over time.

This is far worse than the “~2× gap” the plan previously assumed. The from_string gap (§4.6) is small (~2–3×); the arithmetic gap is the real story and overshadows every other perf item in the plan.

**Hypothesised causes** (must be confirmed with profiling before attacking):

1. ~~**`coefficient()` reconstructs UInt128 from 3×UInt32 on every call.** `add`/`subtract`/`multiply`/`compare` all start with at least two `coefficient()` calls. Rust stores the coefficient as a single 96-bit field that bitcasts directly. We should add an `@always_inline` direct-load fast path~~or store the coefficient as `UInt128` natively (with the flags packed elsewhere)~~. Bitcast the 4 UInt32 words to a single UInt128 and mask off the sign/scale bits in one shot, then use that UInt128 directly in the operators instead of working on the three UInt32s and reconstructing UInt128 repeatedly. I think this is the single biggest low-hanging fruit on the hot path.~~
2. **`raises` overhead on every operator.** `__add__`, `__mul__`, `__truediv__` are all `raises` even when overflow is impossible. Rust’s `+`/`*`/`/` are infallible (panicking) by default and `checked_*` is opt-in. Each `raises` call adds an error-pointer setup + branch. Consider an `@always_inline` non-raising fast path that asserts in debug builds and panics on overflow (matching Rust default). For example, `add_promised` (think about other names recently) that assumes no overflow and is `@always_inline`, then `add` that calls `add_promised` and checks for overflow in debug but not in release.
3. **Scale alignment uses `power_of_10(diff)` lookups + a wide multiply** even when scales already match. Add a `if scale_a == scale_b` short-circuit at the top of `add`.
4. **Multiply always promotes to UInt256** even when `coef_a * coef_b` provably fits in UInt128 (which is most cases for 14-digit-ish inputs). Add a UInt128 fast path with overflow check.
5. **Divide uses a long-division digit loop in Mojo**; rust_decimal uses a UInt128 hardware divide for the common case. Adopt the same fast path.
6. **`to_string` likely allocates a `String` builder per call.** rust_decimal uses a stack `[u8; 32]` buffer. We can do the same with `InlineArray[UInt8, 64]` and a single `String(bytes)` at the end.

**Empirical Decomposition** (`temp/bench_decompose.mojo`) [§4.9.1]

Each row isolates one suspected cost (1_000_000 iters/op, best of 5, same machine/build flags):

| Probe                                       | ns/op    | Notes                                                              |
| ------------------------------------------- | -------- | ------------------------------------------------------------------ |
| (1) raw `UInt128 + UInt128`                 | **~0**   | Loop fully constant-folded by LLVM                                 |
| (2) 2× `Decimal128.coefficient()`           | **~0**   | `@always_inline` bitcast - already optimal at this site            |
| (3) 2× `Decimal128.is_integer()`            | **~250** | Each call is `coefficient % power_of_10[scale]` - full UInt128 mod |
| (4) `Decimal128.from_uint128(value, 20, 0)` | **~1.6** | Basically free                                                     |
| (5) `add()` same scale (20,20)              | **~691** | = 2 × `add` calls per iter ⇒ **~345 ns per add**                   |
| (6) `add()` different scale (20,10)         | **~647** | UInt256 promotion path (~324 ns/call)                              |
| (7) `add()` integers (scale 0,0)            | **9**    | **Faster than rust_decimal's 22 ns** - fast path is excellent      |
| (8) `mul()` integers (scale 0,0)            | **8**    | **Faster than rust_decimal's 25 ns**                               |
| (9) `mul()` fractional (12,12)              | **~802** | UInt256 promotion + scale rebalance                                |

#### 4.9.2 Marginal-Value Ranking (Validated Against Decomposition)

Mapped against the hypotheses above, ranked by **measured ns saved per fractional add()**:

| Rank | Hypothesis (H#x.y from §4.9.1)               | Evidence              | Marginal value | Verdict / next action                                                 |
| ---- | -------------------------------------------- | --------------------- | -------------- | --------------------------------------------------------------------- |
| 1    | H#3.1 `is_integer()` × 2 wastes UInt128 mod  | (3)=250ns, ¬(7)       | ~125 ns / add  | ✓ **DONE 20260421** — three-step landing; see notes below             |
| 2    | H#2 `def raises` operators not inlined       | (5)−(3)−rest ≈ 80 ns  | 40-80 ns / add | **Likely.** Add `@always_inline fn add_promised`; `__add__` calls it  |
| 3    | H#4 UInt256 promotion in `mul` when fits 128 | (9)=802ns, prod<2^96  | ~200 ns / mul  | **Confirmed.** `__umulh` high-half check; promote only on overflow    |
| 4    | H#3 UInt256 promotion in `add` (diff scale)  | (6)≈(5)               | ~30-50 ns      | Marginal; after #1–#3                                                 |
| 5    | H#5 divide long-division loop                | div=809ns total       | TBD ~200-400ns | Probe divide-only decomposition first                                 |
| 6    | H#6 `to_string` per-call allocation          | 515 ns vs rust 69     | ~300 ns / call | **Confirmed.** Stack `InlineArray[UInt8,64]` + single `String` build  |
| 7    | H#1 `coefficient()` reconstruction           | (2)≈0 ns              | ~0 ns ✗        | **Disproven** for `add`/`mul` hot path; native UInt128 field separate |
| 8    | `from_uint128()` raises/check overhead       | (4)=1.6 ns            | ~0 ns ✗        | **Disproven.** Don't touch                                            |
| 9    | H#4.1 `is_integer()` branch in `multiply()`  | By analogy with #1(c) | TBD ~?? ns/mul | **Investigate** — add `Both int, diff scale` cases to `multiply.toml` |

**Notes for #1 (three-step landing):**

- **(a) Hoist the same-scale branch above the `is_integer` branch in `add()`** (`arithmetics.mojo`, commit `ee1c0db`). Correctness preserved (`coefficient + coefficient < MAX_AS_UINT128`, `x1.scale == x2.scale`); `subtract()` benefits transitively via `x1 + (-x2)`. Add median 106 → 5 ns/iter (~21×); sub median 123 → 6 ns/iter (~20×). Report: `dec128_report_20260421_203452.md`.
- **(b) Cheap pre-check in `is_integer()`** (`decimal128.mojo`, commit `63c0445`). Test `(self.low & ((1 << scale) - 1)) != 0` fast-rejects on divisibility-by-`2^scale` before the full UInt128 `% 10^scale` (max scale 28 fits in the low UInt32). Initially measured against `add()` (`Mixed magnitudes` 121 → 14 ns), but step (c) below later removed all `is_integer()` calls from `add()`. The pre-check is still useful for **`multiply()`** (which still has an `is_integer` branch) and for any external caller of the public `is_integer()` API, so it stays. Report: `dec128_report_20260421_205835.md`.
- **(c) Remove the `is_integer` branch from `add()` entirely** (`arithmetics.mojo`, uncommitted). Branch dispatch costs ~250 ns even with the (b) pre-check, while the UInt256 fall-through costs only ~110 ns — the branch was a net loss even when triggered. Three new `Both integer, different scale` cases added to `add.toml` and `subtract.toml`. Those cases drop 121-136 → 6-14 ns (~10-20×); the existing `Different scales` case drops 109 → 7 ns (~15×) because `is_integer()` is no longer dispatched on the no-integer path either. Report: `dec128_report_20260421_211510.md`.

**Action plan (Phase 3, supersedes prior §4.9 priority - re-ordered by validated marginal value):**

1. **Cheap `is_integer` pre-check or restructure** (P1, ~125 ns/add saved). Either short-circuit `is_integer` on a low-bit-chunk test before the full UInt128 mod, **or** simply move the `same scale` branch above the `is_integer` branch in `add()` - the same-scale UInt128 path already correctly handles two integers with positive scale.
2. **Non-raising `add_promised` / `mul_promised` fast path** (P1, ~40-80 ns/op saved). `@always_inline fn` covering the same-scale-fits-in-UInt128 case; have `def add` call it and only enter the slow path on detected overflow.
3. **UInt128-only `multiply` fast path** (P1, ~200 ns/mul saved). Use `__umulh`-style intrinsic; if high-64 of the 128×128→256 product is zero, the result fits and we skip UInt256 entirely.
4. **`to_string` inline buffer** (P2, ~300 ns/call saved). Replace per-call `String` builder with a 64-byte stack buffer, single final `String(StringSlice(buf))`.
5. **Probe `divide`** (P2). Add probes (10)-(11) to `bench_decompose.mojo` to isolate the long-division-loop cost before refactoring.
6. **Same-scale early return in `add()`** (P3, ~30 ns/add when applicable). Add `if x1_scale == x2_scale: return _add_same_scale(...)` near the top - covered for free if action #1 restructures.
7. Re-run both benchmarks after each change. Targets: add ≤ 80 ns, mul ≤ 100 ns, div ≤ 200 ns, to_string ≤ 150 ns.

This is now the **single highest-value perf workstream** in the plan - ahead of §4.4 (`ln()`) and §4.6 (`from_string`). The good news the decomposition reveals: integer fast paths are already faster than rust_decimal, so the architecture works; we just need to apply the same care to the fractional path.

#### 4.9.3 Historical Performance Tracking (Cross-Library Median ns/iter)

Median ns/iter across all TOML test cases per op, from `benches/decimal128/`. Lower is better. `dm/rs` = decimo / rust_decimal ratio (>1 means decimo is slower). After each optimization landing, append a new row — do **not** edit prior rows. The first table tracks absolute decimo timings; the second tracks competitive ratios.

**Absolute decimo median ns/iter (lower = faster):**

| date     | report                             |  add |  sub |  mul |  div |  cmp | from_str | to_str |
| -------- | ---------------------------------- | ---: | ---: | ---: | ---: | ---: | -------: | -----: |
| 20260421 | `dec128_report_20260421_112354.md` |  106 |  123 |    4 |    8 |    0 |    24.25 | 128.30 |
| 20260421 | `dec128_report_20260421_203452.md` |    5 |    6 |    4 |    8 | 2.10 |    24.15 | 127.00 |
| 20260421 | `dec128_report_20260421_205835.md` |    5 |    6 |    5 |    8 | 2.10 |    22.45 | 126.60 |
| 20260421 | `dec128_report_20260421_211510.md` |    5 |  6.5 |    6 |    9 | 2.10 |    21.80 | 129.60 |

**Decimo / competitor ratio (>1 = decimo slower; <1 = decimo faster):**

| date     | op       | dm/rust | dm/csharp | dm/vbnet | notes                                                                 |
| -------- | -------- | ------: | --------: | -------: | --------------------------------------------------------------------- |
| 20260421 | add      |   21.2x |     43.1x |    59.2x | Before any optimizations                                              |
| 20260421 | sub      |   61.5x |     59.0x |    68.7x | Before any optimizations                                              |
| 20260421 | mul      |    1.6x |      2.9x |     4.4x | Before any optimizations                                              |
| 20260421 | div      |    1.4x |      0.5x |     1.5x | Before any optimizations                                              |
| 20260421 | cmp      |    0.0x |      0.0x |     0.0x | Before any optimizations                                              |
| 20260421 | from_str |    2.6x |      0.7x |     0.7x | Before any optimizations                                              |
| 20260421 | to_str   |    3.6x |      4.2x |     4.3x | Before any optimizations                                              |
| 20260421 | add      |    2.2x |      2.0x |     2.7x | After H#3.1 `add()` reorder                                           |
| 20260421 | sub      |    2.1x |      3.1x |     3.1x | After H#3.1 `add()` reorder                                           |
| 20260421 | mul      |    1.8x |      2.6x |     3.6x | After H#3.1 `add()` reorder                                           |
| 20260421 | div      |    1.4x |      0.6x |     1.4x | After H#3.1 `add()` reorder                                           |
| 20260421 | cmp      |    0.8x |      1.4x |     1.1x | After H#3.1 `add()` reorder                                           |
| 20260421 | from_str |    2.4x |      0.7x |     0.7x | After H#3.1 `add()` reorder                                           |
| 20260421 | to_str   |    3.5x |      4.3x |     4.1x | After H#3.1 `add()` reorder                                           |
| 20260421 | add      |    2.2x |      2.0x |     2.8x | After H#3.1 `is_integer()` pre-check                                  |
| 20260421 | sub      |    2.9x |      2.8x |     2.7x | After H#3.1 `is_integer()` pre-check                                  |
| 20260421 | mul      |    1.9x |      3.0x |     4.6x | After H#3.1 `is_integer()` pre-check                                  |
| 20260421 | div      |    1.5x |      0.6x |     1.3x | After H#3.1 `is_integer()` pre-check                                  |
| 20260421 | cmp      |    0.8x |      1.4x |     1.1x | After H#3.1 `is_integer()` pre-check                                  |
| 20260421 | from_str |    2.4x |      0.6x |     0.6x | After H#3.1 `is_integer()` pre-check                                  |
| 20260421 | to_str   |    3.5x |      4.4x |     4.3x | After H#3.1 `is_integer()` pre-check                                  |
| 20260421 | add      |    1.5x |      2.2x |     1.9x | After H#3.1 `is_integer` branch removed from `add()`                  |
| 20260421 | sub      |    3.3x |      3.6x |     2.9x | After H#3.1 `is_integer` branch removed from `add()`                  |
| 20260421 | mul      |    3.0x |      5.6x |     5.6x | After H#3.1 `is_integer` branch removed (untouched code; bench noise) |
| 20260421 | div      |    1.8x |      0.6x |     1.6x | After H#3.1 `is_integer` branch removed (untouched code)              |
| 20260421 | cmp      |    0.8x |      1.4x |     1.2x | After H#3.1 `is_integer` branch removed (untouched code)              |
| 20260421 | from_str |    2.1x |      0.6x |     0.6x | After H#3.1 `is_integer` branch removed (untouched code)              |
| 20260421 | to_str   |    3.9x |      4.4x |     4.6x | After H#3.1 `is_integer` branch removed (untouched code)              |

Observations from the 20260421 baseline:

- `add`/`sub` are the worst gaps — fractional-scale paths dominate (consistent with §4.9.1 decomposition).
- `mul` is already within 2–3× — the integer fast path lands cleanly; gap is only on UInt256-promoting cases.
- `div` already beats C# (`dm/cs = 0.5x`) — our long-division Mojo loop is competitive with .NET.
- `cmp` is essentially free for decimo (rounds to 0 ns/iter) — already faster than all three.
- `to_str` gap is purely allocator-driven (per-call `String` builder) — §4.9.2 action #4 directly targets this.

Observations from the `203452` run (after H#3.1 `add()` reorder — `same-scale` branch hoisted above `is_integer()` to avoid two UInt128 modulus operations on the common path; `subtract()` benefits transitively because it shares the `add()` core):

- **`add` median: 106 → 5 ns/iter (~21× faster)**, decimo ratio vs rust collapses from 21.2× to 2.2× — now within striking distance of native implementations on the same-scale path.
- **`sub` median: 123 → 6 ns/iter (~20× faster)**, ratio vs rust 61.5× → 2.1× (largest single relative improvement in the table).
- **`cmp` reported as 2.10 ns/iter** instead of the previous 0.0 — the prior 0.0 was a measurement artefact (constant folding); the optimiser-barrier work in `_bench_one` now produces honest numbers, and decimo is still competitive (`dm/rs = 0.8x`).
- `mul`, `div`, `from_str`, `to_str` are unchanged because no code change touched their hot paths; the next priorities are §4.9.2 actions #2 (non-raising fast path) and #3 (UInt128-only `multiply`).
- The remaining add/sub gap is dominated by **different-scale cases** (`Different scales`: 115 ns; `Mixed magnitudes`: 121 ns) — these still take the UInt256 path and are §4.9.2 action #6 (a separate same-scale-is-cheaper-than-different optimisation).

Observations from the `205835` run (after the `is_integer()` cheap pre-check landed in `decimal128.mojo` — a `(self.low & ((1 << scale) - 1)) != 0` test fast-rejects on divisibility-by-`2^scale` before falling back to the full UInt128 `% 10^scale` modulus):

- **`add` `Mixed magnitudes`: 121 → 14 ns (~8.6× faster)** — this is the case where one operand (`0.000000001`) has `low=1, scale=9, mask=0x1FF`, and the bottom-bit AND fast-rejects without any modulus. The `is_integer()` short-circuit (`x1 and x2`) then skips the second operand entirely, saving the full ~125 ns mod that previously dominated this case.
- **Median timings unchanged at the table level** (add=5, sub=6) because the median is already pinned by the same-scale fast path landed in the previous run; the win is concentrated in the long tail of cases that still reach `is_integer()`.
- **`Different scales` (109 ns) and the `subtract` different-scale case (111 ns)** are roughly flat vs the previous run — these cases reach the UInt256 promotion regardless of `is_integer()`, so the remaining ~110 ns is now genuinely the UInt256 promotion cost (§4.9.2 action #6 territory).
- `from_str` improved 24.15 → 22.45 ns (~7%) and `to_str` 127.00 → 126.60 ns; these are noise-level fluctuations as no code path was touched.
- Result equivalence preserved: add 11/11, sub 11/11, no new mismatches.

Observations from the `211510` run (after the third sub-step — the `elif x1.is_integer() and x2.is_integer():` branch was removed entirely from `arithmetics.mojo` `add()`, with the previously-tracked benches augmented by three new "Both integer, different scale" cases (small / medium / wide gap) added to both `add.toml` and `subtract.toml`):

- **The `is_integer` branch was a NET LOSS even when triggered.** The branch dispatch alone called `is_integer()` twice (~250 ns, even with the cheap pre-check) and then performed extra UInt128 arithmetic + power-of-10 multiply, while the UInt256 fall-through path costs only ~110 ns end-to-end. Removing the branch is therefore a strict win — both for the cases it used to catch *and* for the cases that fell through it.
- **New `Both integer, different scale` cases (the cases the branch was supposedly designed to optimise):** add `(small) 123 → 7 ns (~17×)`, `(medium) 121 → 6 ns (~20×)`, `(wide gap) 136 → 14 ns (~10×)`; sub `(small) 118 → 7 ns (~17×)`, `(medium) 132 → 10 ns (~13×)`, `(wide gap) 149 → 15 ns (~10×)`.
- **Existing `Different scales` case (neither operand integer): add 109 → 7 ns (~15×)**, sub `111 → 7 ns (~16×)`. Even cases that should not have benefited from the branch removal speed up — because the `is_integer()` fast-reject pre-check, while cheap, was still being executed twice on every add of differently-scaled operands.
- **Mixed magnitudes** stays at 14 ns (the pre-check still wins for it, and it always took the UInt256 path after the branch failed). Same-scale fast path (~5 ns) is untouched.
- **Result equivalence preserved**: add 14/14, sub 14/14, no new mismatches across all four languages.
- **Take-away:** branches that test a non-trivial predicate to skip a moderately-priced fall-through are often anti-optimisations; always measure the dispatch cost separately from the body cost.

## 5. Improvement Opportunities

### 5.1 `Stringable` / `Writable` / `__hash__`

`Decimal128` already conforms to `Writable` (modern replacement for `Stringable`); `String(d)` and `print(d)` work today.

Missing: **`__hash__`** — C# and Rust both hash their decimal types. Approach: hash the normalized form (strip trailing zeros, then hash coefficient + scale + sign). Depends on §5.4 (`normalize()`).

### 5.2 Better `from_float` Accuracy

Verified via direct read of `decimal128.mojo` line 829–920: `from_float` already does IEEE 754 bit extraction (`UnsafePointer(to=abs_value).bitcast[UInt64]()`, mask out exponent, derive `decimal_exp` from `binary_exp * log10(2)`). It does **not** route through string conversion.

What remains: the post-extraction loop fine-tunes `coefficient` digit-by-digit; this could be tightened with a Grisu-style table lookup. Lower priority - most users converting from `Float64` accept the documented 15–16 significant digit cap.

For reference: Rust [`rust_decimal::Decimal::from_f64`](https://docs.rs/rust_decimal/latest/rust_decimal/struct.Decimal.html#method.from_f64) uses the same IEEE 754 extraction approach.

### 5.3 `min()` / `max()` / `clamp()`

All four comparable libraries provide `min`/`max`. Easy to implement.

### 5.4 Canonicalization / `normalize()`

Strip trailing zeros: `1.200` (coef=1200, scale=3) → `1.2` (coef=12, scale=1). Useful for hashing (§5.1) and reducing coefficient size for faster subsequent arithmetic. Rust [`rust_decimal`](https://docs.rs/rust_decimal/latest/rust_decimal/struct.Decimal.html#method.normalize) has `normalize()`.

### 5.5 Wider Testing for Edge Cases

Some test cases worth adding:

| Test Case                                | Expected Behavior           |
| ---------------------------------------- | --------------------------- |
| `from_words` with scale > 28             | Error (not assertion panic) |
| `from_words` with coefficient > 2^96 − 1 | Error (not assertion panic) |
| `is_one()` with 1.0, 1.00, 1.000         | True                        |
| Max coefficient after multiply           | Correct rounding            |
| 29-digit numbers near 2^96 − 1 boundary  | Correct truncate/round      |

### 5.6 Rust `rust_decimal` Parity Gaps (Competitive Surface)

A scan of the public `decimal128` API against `rust_decimal::Decimal` surfaces the following missing surface area. The goal is API competitiveness for users porting code from Rust; perf-wise we are already in the same order of magnitude (see §4.6 from_string benchmarks vs Rust's ~25 ns).

| Rust API                            | Mojo equivalent                       | Status / suggested action                                |
| ----------------------------------- | ------------------------------------- | -------------------------------------------------------- |
| `Decimal::trunc()`                  | (none - `__round__` rounds half-even) | Add `trunc()` (toward zero)                              |
| `Decimal::floor()` / `ceil()`       | (none)                                | Add free functions in `arithmetics.mojo`                 |
| `Decimal::fract()`                  | (none)                                | Add `fract()` (= `x - x.trunc()`)                        |
| `Decimal::signum()`                 | (none - only `is_negative()`)         | Add `signum() -> Decimal128` returning {−1, 0, 1}        |
| `Decimal::mantissa()` + `scale()`   | `coefficient()` + `scale()`           | Already present                                          |
| `Decimal::unpack()`                 | (none - three-word `from_words`)      | Add `unpack() -> (UInt128, UInt32, Bool)` for round-trip |
| `Decimal::set_scale(u32)`           | `quantize()` is close                 | Document quantize as the equivalent                      |
| `checked_add` / `checked_mul` / …   | All ops `raises`                      | Mojo idiom is already raise-based; document mapping      |
| `Hash` impl                         | (none)                                | See §5.1                                                 |
| `min` / `max`                       | (none)                                | See §5.4                                                 |
| `normalize()`                       | (none)                                | See §5.5                                                 |
| `from_str_exact()`                  | `from_string` (always exact)          | Already present                                          |
| `Serialize` / `Deserialize` (serde) | (none - string round-trip only)       | Out of scope until Mojo gets a serde-equivalent          |

**Action items grouped:**

- *Trivial* (1–2 lines each): `trunc`, `floor`, `ceil`, `fract`, `signum`, `unpack`. Implement together as a single PR.
- *Already covered*: `mantissa`/`scale`, `checked_*` (via `raises`), `from_str_exact`.
- *Tracked elsewhere*: `Hash` (§5.1), `min`/`max`/`clamp` (§5.3), `normalize` (§5.4).
- *Out of scope today*: serde - wait for the Mojo ecosystem.

No behavioural changes are needed to be "competitive" with rust_decimal on perf for **string parsing** - the asm-level investigation in §4.7 plus the from_string benchmark in §4.6 confirm we are within ~2–3× there. **Arithmetic is a different story**: the head-to-head numbers in §4.9 show large remaining gaps on `add`/`sub`, which is the dominant remaining workstream. The Rust-parity API surface (this section) is independent of that perf work.

### 5.7 Result-Equivalence vs `rust_decimal`, C# `System.Decimal`, and VB.NET `System.Decimal` (Empirical, IEEE 754-2008 Compliance)

The cross-language harness in `benches/decimal128/` runs the *same* TOML cases through **decimo**, **`rust_decimal` (Rust)**, **`System.Decimal` (.NET / C#)**, and **`System.Decimal` (.NET / VB.NET)** and flags result-string mismatches. As of `dec128_report_20260421_*.md` (11/11/13/11/30/16/9 cases per op), the **only divergences are trailing-zero / scale differences in `multiply` and `divide`**, all of which `rust_decimal` gets wrong relative to the IEEE 754-2008 / IBM General Decimal Arithmetic "preferred (ideal) exponent" rule — and on every disputed case, **C# and VB.NET `System.Decimal` agree with decimo, not with `rust_decimal`** (3 implementations to 1):

| op       | inputs        | decimo    | C# `System.Decimal` | VB.NET `System.Decimal` | rust_decimal | spec verdict                                                                                                                                                                          |
| -------- | ------------- | --------- | ------------------- | ----------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| multiply | `123.45 × 0`  | `0.00`    | `0.00`              | `0.00`                  | `0`          | **decimo + .NET correct.** `exp(0×X) = exp(a) + exp(b) = -2 + 0 = -2`, so coefficient `0` at exponent `-2` is `0.00`. rust strips the scale.                                          |
| divide   | `10.5 / 2.5`  | `4.2`     | `4.2`               | `4.2`                   | `4.20`       | **decimo + .NET correct.** Ideal exponent for divide = `exp(a) − exp(b) = -1 − (-1) = 0`; result `4.2` (exact at exp `-1`) is preferred over `4.20` (exp `-2`). rust pads spuriously. |
| divide   | `123.45 / -2` | `-61.725` | `-61.725`           | `-61.725`               | `-61.7250`   | **decimo + .NET correct.** Exact result needs exp `-3` (`-61725 × 10⁻³`); ideal exp `-2` would require fractional coefficient. rust adds an unjustified trailing zero.                |

**Conclusion:** decimo's scale handling matches IEEE 754-2008 §3.3 (preferred exponent rules), the IBM General Decimal Arithmetic Specification §4.1, **and** the de-facto reference implementation in .NET BCL (`System.Decimal`, also a 128-bit fixed-precision decimal — same type, two language frontends). `rust_decimal` is the lone outlier among the four canonical implementations surveyed. **No remediation is needed on the decimo side.**

**Action items elsewhere:**

- Add a regression test asserting these exact strings for the three cases above in `tests/test_arithmetic.mojo` (or wherever the multiply/divide suite lives), so we catch any future regression toward "rust-style" trailing zeros.
- Add a one-paragraph note in `docs/user_manual.md` (Decimal128 chapter) calling out that scale follows IEEE 754-2008 / IBM Decimal Arithmetic preferred-exponent rules (matching .NET `System.Decimal`), since this differs visibly from `rust_decimal` and may surprise users porting code.

## 6. Priority Summary

Open items (in priority order):

| #   | Issue                                                     | Severity      | Effort  | Priority |
| --- | --------------------------------------------------------- | ------------- | ------- | -------- |
| 4.9 | Arithmetic gap vs rust_decimal (add/sub dominant)         | Critical      | Large   | P1       |
| 2.6 | Steal flag bits to extend coefficient to 10^32-1 (32 dig) | Architectural | Medium  | P2       |
| 4.2 | `ln()` range reduction loops                              | High          | Medium  | P2       |
| 5.6 | Rust parity (trunc/floor/ceil/fract/signum/unpack)        | Enhancement   | Small   | P2       |
| 5.7 | Regression tests pinning IEEE 754 preferred-exp scale     | Enhancement   | Trivial | P2       |
| 5.3 | `min/max/clamp`                                           | Enhancement   | Trivial | P3       |
| 5.4 | `normalize()`                                             | Enhancement   | Small   | P3       |
| 5.1 | `__hash__` (depends on §5.4)                              | Enhancement   | Small   | P3       |
| 4.4 | `from_string` digit batching + shared scanner             | Medium        | Medium  | P3       |
| 4.6 | Test suite slow (flags + per-file JIT)                    | Medium        | Medium  | P3       |
| 5.5 | Edge case tests                                           | Enhancement   | Medium  | P3       |
| 4.3 | Series convergence tolerance                              | Low           | Small   | P4       |
| 3.3 | Division rounding mode (configurable)                     | Low           | Medium  | P4       |
| 5.2 | Better `from_float` (Grisu-style)                         | Enhancement   | Medium  | P4       |

Done items (kept for tracking, not actionable):

| #   | Issue                                            | Severity | Effort | Status            |
| --- | ------------------------------------------------ | -------- | ------ | ----------------- |
| 3.1 | NaN/Inf removed                                  | Critical | Small  | Done              |
| 3.2 | `from_words` uses `testing.assert_true`          | Medium   | Small  | Done              |
| 4.1 | `number_of_bits` loop                            | Medium   | Small  | Done              |
| 4.2 | `power_of_10` not fully precomputed              | High     | Small  | Done              |
| 4.3 | `round_to_keep_first_n_digits` lacks .NET tricks | High     | Medium | Done              |
| 4.5 | Separate `//` and `%` in division loop           | Medium   | Small  | Verified-NoChange |

## 7. Execution Order

**Phase 1 (correctness)** — Done. NaN/Inf removed; `from_words` raises on invalid input.

**Phase 2 (coefficient-bound perf)** — Done. `power_of_10` extended to n=58; `round_coefficient` with .NET tricks; `number_of_bits` via `bit_width` intrinsic.

**Phase 3 (general perf)** — close the rust_decimal gap. This is the actual competitive workstream.

1. **Close the arithmetic gap (§4.9)** — highest priority. Restructure `add()` to short-circuit before `is_integer`; non-raising `add_promised`/`mul_promised` fast paths; UInt128-only `multiply` fast path; inline `to_string` buffer. Re-bench after each change and append a new row to the §4.9.3 tracking table.
2. **Improve `ln()` range reduction (§4.4)** — 30 divisions → 1 via scale-read + bit-width single-shot.
3. **`from_string` digit batching (§4.6)** — ~55 ns/call → target ~25 ns.
4. **Test-suite latency (§4.8)** — split dev/CI flag profiles, hoist `parse_file`, consolidate per-file JIT.

**Phase 4 (enhancements / Rust parity)**:

1. `trunc` / `floor` / `ceil` / `fract` / `signum` / `unpack` (§5.6) — single small PR.
2. Regression tests pinning IEEE 754-2008 preferred-exp behaviour for the three §5.7 cases + user-manual note.
3. `min/max/clamp` (§5.3).
4. `normalize()` (§5.4).
5. `__hash__` (§5.1) — depends on `normalize()` for stable hashes.
6. Tighten `from_float` accuracy with Grisu-style table (§5.2).

**Phase 5 (long-term, deferred)**:

1. **Steal flag bits to widen coefficient to 10^32−1 (§2.6)** — architectural cleanup, not a competitive driver. Defer until perf parity (§4.9) is solid and there is appetite for a breaking-change major release. Documented as a design proposal; not on the active roadmap.

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
number - the upper bound is a power-of-2 boundary, not 10^29 − 1.

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

Not truly 128-bit - the struct is **160 bits (20 bytes)**. Layout:

- `exponent: Int8` (−128 to +127)
- `lengthFlagsAndReserved: UInt8` (4-bit length, 1-bit isNegative, 1-bit isCompact, 2-bit reserved)
- `reserved: UInt16`
- `mantissa: (UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16)` - 8×UInt16 = 128 bits

The 128-bit mantissa can theoretically hold values up to 2^128 − 1, but the `_length` field (4 bits, max 15) indicates how many of the 8 UInt16 slots are used, and Apple documents the max as 38 significant decimal digits (i.e., effectively capped at 10^38 − 1).

Unlike C# and Rust, Swift Decimal **supports NaN** (`isNaN` property). It does NOT support Infinity in practice - the `isInfinite` property exists (inherited from `FloatingPoint` protocol) but Apple's implementation does not produce or handle Infinity values meaningfully.

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

- Natural fit for hardware - the coefficient is just a native (multi-word) integer
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
