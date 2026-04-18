# Decimo API Roadmap

> Date of initial planning: 2026-02-23  
> Author: Yuhao Zhu
> Scope: BigDecimal (Decimal), BigInt (BInt)

## Summary

The functional core of Decimo is solid after a series of optimizations and improvements. Now I am back to think about the API surface and usability. My main goal is to provide Pythonistas a familiar and intuitive experience when using Decimo types, while incorporating some new and modern features that leverage the strengths of the Mojo programming language (note that it is a static language).

The main areas for further improvement are:

1. **API consistency across types** — naming, method availability, field access
2. **Python compatibility gaps** — missing dunders and named methods that Python users expect  
3. **Modern ergonomics** — method-based API already started, needs completion
4. **Missing RoundingMode variants** — 4 of 8 Python modes absent

Note that `Decimal128` is not among the priority at this stage because it is a fixed-width type and is not a big number. For the release of v0.8 or v0.9, I should focus only on `BigDecimal` and `BigInt` because they have direct Python counterparties. For `BigUInt`, the priority is lower because it is not directly exposed to users.

## Part I: Cross-Type Consistency Issues

These inconsistencies will confuse users who use both types in the same codebase.

### 1.1 Naming: Free Function Inconsistencies

| Concept  | BigDecimal                                                                                                                                              | BigInt                                                      | Status                                                                                            |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Equality | ~~`equals()` / `not_equals()`~~ → `equal()` / `not_equal()`                                                                                             | `equal()` / `not_equal()`                                   | ✓ **DONE** — old aliases removed                                                                  |
| Ordering | ~~`less_than()` / `greater_than()` / `less_than_or_equal()` / `greater_than_or_equal()`~~ → `less()` / `greater()` / `less_equal()` / `greater_equal()` | `less()` / `greater()` / `less_equal()` / `greater_equal()` | ✓ **DONE** — old aliases removed                                                                  |
| Division | `true_divide()`                                                                                                                                         | N/A                                                         | `true_divide` is aligned with `__truediv__` dunder. Maybe add an alias `divide()` for convenience |

### 1.2 Field Access vs Method Access

BigDecimal exposes internal state via direct field access (`self.scale`, `self.coefficient`, `self.sign`). Consider adding accessor methods for a cleaner public API:

| What        | Current (BigDecimal)            | Recommendation                                                          |
| ----------- | ------------------------------- | ----------------------------------------------------------------------- |
| Scale       | Direct field `self.scale`       | Consider adding `exponent(self) -> Int` method                          |
| Coefficient | Direct field `self.coefficient` | Consider adding `significand(self) -> BigUInt` method (or `mantissa()`) |
| Sign        | Direct field `self.sign` (Bool) | `is_negative()` already exists — use it as the canonical way            |

### 1.3 BigDecimal — Missing Methods to Add

Methods that BigDecimal should have but currently lacks:

| Method                           | Status       | Action                                                                                                    |
| -------------------------------- | ------------ | --------------------------------------------------------------------------------------------------------- |
| `as_tuple()`                     | ✓ **DONE**   | Implemented — returns `(sign: Bool, digits: List[UInt8], exponent: Int)` matching Python's `DecimalTuple` |
| `copy()`                         | ✓ **DONE**   | Implemented — used internally by `__pos__`, `__round__`, etc.                                             |
| `number_of_significant_digits()` | ~~REMOVED~~  | Removed — identical to `number_of_digits()`; not a Python API                                             |
| `is_positive()`                  | ✓ **DONE**   | Implemented                                                                                               |
| `to_scientific_string()`         | ✓ **DONE**   | Added — convenience alias for `to_string(scientific=True)`                                                |
| `__divmod__()`                   | ✓ **DONE**   | Implemented                                                                                               |
| `Int` overloads for operators    | **RESOLVED** | Mojo's `@implicit` handles this — `BigDecimal("1.5") + 1` already works                                   |
| `__ifloordiv__` / `__imod__`     | ✓ **DONE**   | Implemented                                                                                               |
| `__rtruediv__`                   | ✓ **DONE**   | Implemented                                                                                               |
| Debug repr returning String      | Prints only  | **Improve** — `print_internal_representation()` should also have a variant that returns String            |

### 1.4 Missing Parity: BigInt vs BigDecimal

| Method                        | BigInt   | BigDecimal  | Action                                                              |
| ----------------------------- | -------- | ----------- | ------------------------------------------------------------------- |
| `is_positive()`               | ✓ Has it | ✓ Done      | —                                                                   |
| `__bool__()`                  | ✓ Done   | ✓ Done      | —                                                                   |
| `to_string_with_separators()` | Has it   | **MISSING** | Nice to have on BigDecimal too (can use `to_string(delimiter=...)`) |
| `number_of_digits()`          | Has it   | ✓ Done      | —                                                                   |

---

## Part II: BigDecimal (Decimal) — Python Compatibility

These are the gaps vs Python's `decimal.Decimal`, prioritized by user impact.

### 2.1 HIGH Priority — Dunders That Pythonistas Expect

| Method                                     | What It Does                                     | Notes                                                     |
| ------------------------------------------ | ------------------------------------------------ | --------------------------------------------------------- |
| **`__bool__(self) -> Bool`**               | `if x:` — True if nonzero                        | ✓ **DONE**                                                |
| **`__pos__(self) -> Self`**                | `+x` — unary plus                                | ✓ **DONE**                                                |
| **`__divmod__(self, other) -> Tuple`**     | `divmod(a, b)`                                   | ✓ **DONE**                                                |
| **`__ceil__` / `__floor__` / `__trunc__`** | `math.ceil(x)`, `math.floor(x)`, `math.trunc(x)` | ✓ **DONE**                                                |
| **`__rtruediv__(self, other) -> Self`**    | `1 / x` where x is BigDecimal                    | ✓ **DONE**                                                |
| **`__hash__(self) -> UInt`**               | Hashable                                         | **MISSING**. Can wait for Mojo's Hashable trait maturity. |

### 2.2 MEDIUM Priority — Named Methods for Python Migration

| Method                              | What It Does                                             | Notes                                                                                                    |
| ----------------------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `as_tuple()`                        | Returns `(sign, digits, exponent)`                       | ✓ **DONE** — returns `(sign: Bool, digits: List[UInt8], exponent: Int)` matching Python's `DecimalTuple` |
| `adjusted()`                        | Returns adjusted exponent (= exponent + len(digits) - 1) | ✓ **DONE** — renamed from former `exponent()` method.                                                    |
| `copy_abs()`                        | Returns `abs(self)`                                      | ✓ **DONE** — alias for `__abs__()`.                                                                      |
| `copy_negate()`                     | Returns `-self`                                          | ✓ **DONE** — alias for `__neg__()`.                                                                      |
| `copy_sign(other)`                  | Returns self with the sign of other                      | ✓ **DONE**.                                                                                              |
| `same_quantum(other)`               | True if both have same exponent/scale                    | ✓ **DONE**.                                                                                              |
| `normalize()`                       | Already exists                                           | ✓                                                                                                        |
| `to_eng_string()`                   | Engineering notation (exponent multiple of 3)            | ✓ **DONE** — alias for `to_string(engineering=True)`                                                     |
| `to_integral_value(rounding)`       | Round to integer, keep as Decimal                        | `round(ndigits=0)` is close but not identical (doesn't strip trailing zeros).                            |
| `max_mag(other)` / `min_mag(other)` | Max/min by absolute value                                | `compare_absolute` exists; this is a convenience.                                                        |
| `remainder_near(other)`             | IEEE 754 remainder                                       | Different from `%` (truncated).                                                                          |
| `logb()`                            | Returns adjusted exponent as Decimal                     | Different from `adjusted()` (returns Decimal, not Int).                                                  |
| `fma(a, b)`                         | `self * a + b` without intermediate rounding             | Important for numerical algorithms.                                                                      |
| `scaleb(n)`                         | Multiply by 10^n efficiently                             | Useful for scale manipulation.                                                                           |

### 2.3 LOW Priority — Completeness

| Method                                           | Notes                                                           |
| ------------------------------------------------ | --------------------------------------------------------------- |
| `is_finite()`                                    | Always True for BigDecimal (no Inf/NaN). Add for compatibility. |
| `is_signed()`                                    | Similar to `is_negative()` but returns True for -0.             |
| `canonical()` / `is_canonical()`                 | Always canonical. Trivial.                                      |
| `conjugate()`                                    | Returns self. Trivial.                                          |
| `number_class()`                                 | Returns classification string.                                  |
| `radix()`                                        | Returns 10. Trivial.                                            |
| `next_minus()` / `next_plus()` / `next_toward()` | Complex, rarely needed.                                         |
| `rotate()` / `shift()`                           | Coefficient digit rotation/shifting. Rarely needed.             |
| `logical_and/or/xor/invert`                      | Operates on coefficient digits. Rarely needed.                  |

---

## Part III: BigInt (BInt) — Python Compatibility

### 3.1 HIGH Priority

| Method                                     | What It Does                 | Notes                                                                                                                                               |
| ------------------------------------------ | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`__bool__(self) -> Bool`**               | `if n:` — True if nonzero    | ✓ **DONE**                                                                                                                                          |
| **`__pos__(self) -> Self`**                | `+n` — returns self          | ✓ **DONE**                                                                                                                                          |
| **`__ceil__` / `__floor__` / `__trunc__`** | All return self for integers | ✓ **DONE**                                                                                                                                          |
| **`bit_count(self) -> Int`**               | Popcount (number of 1-bits)  | **MISSING**. Python 3.10+. Useful.                                                                                                                  |
| **`__float__(self) -> Float64`**           | Float conversion             | **MISSING**. Python's `float(n)`. Useful for interop.                                                                                               |
| **`__pow__(self, exp, mod)`**              | 3-arg pow                    | Python's `pow(base, exp, mod)`. `mod_pow` exists but not via the dunder. **Mojo may not support 3-arg **pow** yet — keep `mod_pow` as workaround.** |

### 3.2 MEDIUM Priority

| Method                                 | What It Does                    | Notes                             |
| -------------------------------------- | ------------------------------- | --------------------------------- |
| `to_bytes(length, byteorder, signed)`  | Serialization                   | Useful for crypto / network code. |
| `from_bytes(bytes, byteorder, signed)` | Deserialization                 | Counterpart of above.             |
| `__index__(self) -> Int`               | Allows `list[big_int]` indexing | Maps to `__int__`. Useful.        |

### 3.3 LOW Priority

| Method               | Notes                                 |
| -------------------- | ------------------------------------- |
| `as_integer_ratio()` | Returns `(self, BigInt(1))`. Trivial. |
| `is_integer()`       | Always True. Trivial.                 |
| `conjugate()`        | Returns self. Trivial.                |

---

## Part IV: RoundingMode

### Current: 6 modes

| Mode              | Python Name       | Status |
| ----------------- | ----------------- | ------ |
| `ROUND_DOWN`      | `ROUND_DOWN`      | ✓ Done |
| `ROUND_UP`        | `ROUND_UP`        | ✓ Done |
| `ROUND_HALF_UP`   | `ROUND_HALF_UP`   | ✓ Done |
| `ROUND_HALF_EVEN` | `ROUND_HALF_EVEN` | ✓ Done |
| `ROUND_CEILING`   | `ROUND_CEILING`   | ✓ Done |
| `ROUND_FLOOR`     | `ROUND_FLOOR`     | ✓ Done |

### Missing: 2 modes

| Mode              | Python Name       | Description            | Priority              |
| ----------------- | ----------------- | ---------------------- | --------------------- |
| `ROUND_HALF_DOWN` | `ROUND_HALF_DOWN` | Round ties toward zero | ✓ Implemented         |
| `ROUND_05UP`      | `ROUND_05UP`      | Special IEEE rounding  | **LOW** — rarely used |

---

## Part V: Ergonomic Improvements (Static Language Features)

These go beyond Python compatibility — they make the API feel native to a static language.

### 5.1 Method-Based API (Already Started — Complete It)

BigDecimal already has method-based math: `x.sqrt()`, `x.exp()`, `x.ln()`, `x.sin()` etc.

**Gaps to fill:**

- BigDecimal: ensure all free functions have method counterparts (e.g., `truncate_modulo` is free def only)

### 5.2 Fluent / Chainable API

Currently methods return new values (immutable style), which is good. But some things to consider:

```mojo
# This already works:
var result = x.sqrt().round(2)

# Make sure these patterns all work:
var result = a.add(b).multiply(c)  # ← NOT currently possible, no add() instance method for BigDecimal
```

Consider adding `add()`, `sub()`, `mul()`, `div()` as instance method aliases for chaining:

```mojo
# Python-like (already works):
var result = a + b * c

# Chainable with precision control (new):
var result = a.mul(b).add(c).round(10)  
```

### 5.3 `with_scale(n)` / `with_precision(n)` Builders

```mojo
# Instead of:
var x = BigDecimal("3.14159")
var y = x.round(2, ROUND_HALF_EVEN)

# Also allow:
var y = x.with_scale(2)                    # set scale to 2 decimal places
var y = x.with_precision(6)                # keep 6 significant digits
```

### 5.4 Operator Overloads with `Int` (BigDecimal)

Mojo's `@implicit` decorator on `BigDecimal.__init__(out self, value: Int)` handles this automatically. `BigDecimal("1.5") + 1` already works — the `Int` is implicitly converted to `BigDecimal` before the operator is called. No explicit `Int` overloads needed.

Thus, we can clean the `Int` operator overloads from the API, since they are redundant with the implicit conversion.

### 5.5 Named Constructors for Common Patterns

```mojo
# Already have:
var x = BigDecimal("3.14")
var x = BigDecimal(42)

# Consider adding:
var x = BigDecimal.from_components(sign=False, coefficient=314, scale=2)  # ← exists for raw words, but not clean components
var x = BigDecimal.from_fraction(1, 3, precision=20)  # 0.33333...
```

### 5.6 Iterator / Digit Access

```mojo
# Useful for financial formatting:
var d = x.digits()    # Returns iterator over decimal digits
var d = x.digit(i)    # Returns i-th decimal digit
```

### 5.7 Clamp / Restrict

```mojo
# Very useful, std lib pattern:
var y = x.clamp(lower, upper)   # clamp between bounds
```

### 5.8 Approximate Equality

```mojo
# Useful for testing and numerical code:
x.is_close(y, tolerance=BigDecimal("0.001"))
x.is_close(y, rel_tol=BigDecimal("1e-9"))
```

## Part VI: Remaining Tasks (Re-ranked)

> Updated after audit on 2026-02-27. Items already completed are removed.
> Last updated: 2026-02-27 (Tier 1 completed).

### ✓ Tier 1: Completed

1. ✓ **Naming cleanup** — removed old aliases `equals`/`not_equals`/`less_than`/`greater_than`/`less_than_or_equal`/`greater_than_or_equal` from BigDecimal `comparison.mojo`
2. ✓ **`__rtruediv__()`** on BigDecimal — `1 / some_decimal` now works
3. ✓ **`is_positive()`** on BigDecimal
4. ✓ **`number_of_digits()`** on BigDecimal (`number_of_significant_digits()` removed — identical behavior, not a Python API)
5. ✓ **`to_scientific_string()`** and **`to_eng_string()`** on BigDecimal

### Tier 2: Important (Remaining)

1. ✓ **`as_tuple()`** on BigDecimal — returns `(sign: Bool, digits: List[UInt8], exponent: Int)` matching Python's `DecimalTuple`
2. ✓ **`copy_abs()` / `copy_negate()` / `copy_sign(other)`** on BigDecimal
3. ✓ **`adjusted()`** on BigDecimal — renamed from `exponent()` to match Python's `Decimal.adjusted()`
4. ✓ **`same_quantum(other)`** on BigDecimal
5. ✓ **`ROUND_HALF_DOWN`** rounding mode
6. ✓ **`scaleb(n)`** on BigDecimal — adjusts scale by `n` (O(1), no coefficient change)
7. ✓ **`bit_count()`** on BigInt — popcount (Kernighan's algorithm over UInt32 words)
8. ✓ **`__float__()`** on BigInt — `float(n)` via `Float64(String(self))`; `FloatableRaising` trait added
9. ✓ **`fma(a, b)`** on BigDecimal — `self * a + b` (exact, no intermediate rounding)
10. ✓ **`to_string_with_separators()`** on BigDecimal — alias for `to_string(delimiter=...)`

### Tier 3: Nice-to-Have (Remaining)

1. `signum()` returning -1/0/1 on BigDecimal and BigInt
2. `clamp(lower, upper)` on BigDecimal and BigInt
3. `is_close(other, tolerance)` on BigDecimal
4. `from_fraction(num, den, precision)` on BigDecimal
5. `to_bytes()` / `from_bytes()` on BigInt
6. `to_integral_value()` / `remainder_near()` on BigDecimal
7. Method aliases for chaining (`add()`, `sub()`, `mul()`, `div()`) on BigDecimal
8. `__hash__()` when Mojo's Hashable trait matures

### Tier 4: Completeness (Low urgency)

1. `is_finite()` / `is_canonical()` / `conjugate()` / `radix()` on BigDecimal
2. `next_minus()` / `next_plus()` / `next_toward()` on BigDecimal
3. `number_class()` on BigDecimal
4. `rotate()` / `shift()` on BigDecimal
5. `logical_and/or/xor/invert` on BigDecimal
6. `ROUND_05UP` rounding mode
7. `is_integer()` / `as_integer_ratio()` / `conjugate()` on BigInt

---

## Appendix: Quick Reference — Python `decimal.Decimal` Full API

For tracking against the above:

```txt
# Python decimal.Decimal methods (3.12)
# ✓ = implemented, △ = partial/alias only, ✗ = missing

✓ __abs__          ✓ __add__          ✓ __bool__         ✓ __ceil__
✗ __complex__      ✓ __eq__           ✓ __float__        ✓ __floor__
✓ __floordiv__     ✓ __ge__           ✓ __gt__           ✗ __hash__
✓ __int__          ✓ __le__           ✓ __lt__           ✓ __mod__
✓ __mul__          ✓ __ne__           ✓ __neg__          ✓ __pos__
✓ __pow__          ✓ __radd__         ✓ __repr__         ✓ __rfloordiv__
✓ __rmod__         ✓ __rmul__         ✓ __round__        ✓ __rpow__
✓ __rsub__         ✓ __rtruediv__     ✓ __str__          ✓ __sub__
✓ __truediv__      ✓ __trunc__
✓ adjusted         ✗ as_integer_ratio ✓ as_tuple         ✗ canonical
✓ compare          ✗ conjugate        ✓ copy_abs         ✓ copy_negate
✓ copy_sign        ✓ exp              ✗ fma              ✗ is_canonical
✗ is_finite        ✓ is_integer       ✗ is_nan           ✗ is_normal
✗ is_signed        ✗ is_snan          ✗ is_subnormal     ✗ is_qnan
✓ ln               ✓ log10            ✗ logb             ✗ logical_and
✗ logical_invert   ✗ logical_or       ✗ logical_xor      ✓ max
✗ max_mag          ✓ min              ✗ min_mag          ✗ next_minus
✗ next_plus        ✗ next_toward      ✓ normalize        ✗ number_class
✓ quantize         ✗ radix            ✗ remainder_near   ✗ rotate
✓ same_quantum     ✗ scaleb           ✗ shift            ✓ sqrt
✓ to_eng_string    ✗ to_integral_exact ✗ to_integral_value
```
