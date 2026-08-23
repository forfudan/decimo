# Advanced Math Functions: Optimization Notes

> Date: 2026-02-23 Author: Yuhao Zhu Scope: BigDecimal trigonometric functions
> (sin, cos, tan, arctan, etc.) and pi computation Status: Reference notes for
> future work. Not on current roadmap — current priority is replacing `int` and
> `decimal`.

## Background

Benchmarks against `mpmath` (Python, backed by GMP/MPIR) show Decimo's trig and
pi functions are significantly slower — ranging from ~200× slower (sin at low
precision) to ~500,000× slower (pi at 10,000 digits). This is expected given
Decimo's pure-Mojo base-10^9 arithmetic vs. GMP's highly optimized base-2^64
assembly core. The accuracy is excellent (full precision digits match
WolframAlpha); this document is purely about performance.

## Identified Optimization Opportunities

### 1. Pi Caching (High Impact, Low Effort)

**Current behavior:** Every call to `sin()`, `cos()`, `tan()` recomputes π from
scratch via Chudnovsky binary splitting. `tan()` is worst — it calls `sin()` and
`cos()` independently, each of which computes π, so a single `tan()` call
computes π 3–4 times.

**What can be done:** Once Mojo supports module-level mutable globals, enable
the cache so that `pi(precision)` returns the precomputed value instead of
recomputing when precision is low. For higher precision, a runtime cache can
store the highest-precision π computed so far and reuse it for subsequent calls
at equal or lower precision.

### 2. Excessive Buffer Digits in Trigonometric Functions (High Impact, Low Effort)

**Current behavior:** `sin()`, `cos()`, and `tan_cot()` all use
`BUFFER_DIGITS = 99`. This means a request for 50-digit precision actually
computes at 149 digits — nearly 3× the requested work. The buffer exists to
ensure accurate range reduction near π-related values - I want to be
conservative at this stage.

**What can be done:** Profile to determine how many buffer digits are actually
needed for correctness. A value of 15–30 is likely sufficient for most cases. An
adaptive approach is also possible: use a smaller buffer normally and only
increase it when the input is detected to be close to a multiple of π/2.

### 3. cos() Implementation (Medium Impact, Low Effort)

**Current behavior:** `cos(x, precision)` computes `sin(π/2 - x, precision)`.
This means every `cos()` call: (a) computes π from scratch, (b) delegates to
`sin()` which computes π again for its own range reduction. So `cos()` computes
π at least twice. Meanwhile, `cos_taylor_series()` already exists and works
correctly — `sin()` itself uses it internally for inputs in the (π/4, π/2)
range.

**What can be done:** Implement `cos()` with its own range reduction (analogous
to `sin()`'s range reduction) that directly calls `cos_taylor_series()` for the
base case. This avoids the double π computation entirely.

### 4. Chudnovsky Binary Splitting: Factorial/Power Recomputation — DONE

**Was:** Each leaf node in `chudnovsky_split()` called `compute_m_k_rational(k)`,
which computed `(6k)! / (3k)!` and `(k!)^3` from scratch using loops, and
`X(k) = (-262537412640768000)^k` by multiplying in a loop `k` times. Factorial
products were rebuilt from 1 for every single term.

**Now:** `chudnovsky_split()` uses the standard 3-variable `P`/`Q`/`T`
recurrence — the formulation used by y-cruncher, GMP's `mpfr_const_pi`, and
mpmath — where each level combines its children's partial products and no
per-leaf factorial computation happens at all:

- `P(a,b) = P(a,m) * P(m,b)`
- `Q(a,b) = Q(a,m) * Q(m,b)`
- `T(a,b) = T(a,m) * Q(m,b) + P(a,m) * T(m,b)`

`pi(2048)` went from 86.0 ms to 0.69 ms and `pi(10000)` from 13.66 s to 8.81 ms.
The leaf cost was the smaller half of the win; the larger half was that an
evaluated-fraction leaf makes the root denominator the product of all `n` term
denominators rather than the size of one.

Later work on the stages around the split - an intermediate-grade `sqrt`,
scaling and dividing in binary so only the quotient is converted to base 10^9,
and machine-arithmetic leaves - took those two to 0.30 ms and 3.55 ms, which is
ahead of mpmath's pure-Python backend. See `docs/internal/internal_notes.md`
for the per-stage measurements and for what is left.

### 5. tan() Redundant Range Reduction (Medium Impact, Low Effort)

**Current behavior:** `tan_cot()` performs its own modular reduction to
`(-π/2, π/2)`, then calls `sin()` and `cos()` independently. Each of `sin()` and
`cos()` performs their own range reduction again (computing π again).

**What can be done:** After `tan_cot()` reduces `x` to `(-π/2, π/2)`, pass the
reduced value directly to Taylor series evaluation rather than going through the
full `sin()`/`cos()` entry points. This skips redundant range reduction and π
computation. Alternatively, compute `tan()` via its own Taylor series or
continued fraction expansion.

### 6. Argument Reduction via Multiplication Instead of Division (Low Impact, Low Effort)

**Current behavior:** Range reduction computes `π/2` and `π/4` via
`pi.true_divide(2, ...)` and `pi.true_divide(4, ...)`.

**What can be done:** Multiplication by `0.5` or `0.25` (or a right-shift by 1–2
in the coefficient) is cheaper than arbitrary-precision division. This is a
minor optimization but essentially free to implement.

### 7. Toom-3 and NTT/FFT Multiplication (High Impact, High Effort)

**Current behavior:** Multiplication uses Karatsuba with a crossover at 64 words
(~576 digits). Karatsuba is O(n^1.585), which is competitive up to ~1000 digits
but falls behind for larger operands.

**What can be done.** Two natural next steps for large multiplication are:

- **Toom-3:** O(n^1.465), a natural next step above Karatsuba. Adds one more
  level of divide-and-conquer.
- **NTT/FFT:** O(n log n), transformative for large multiplications (thousands
  of digits). This would benefit pi, exp, ln, and all functions that chain many
  large multiplications.

**Note:** NTT/FFT is a long-term consideration with no concrete timeline.

### 8. Base Representation

**Current:** Decimo uses base 10^9 with UInt32 words. GMP uses base 2^64 with
native 64-bit words, which is inherently more efficient for binary hardware
(full use of 64-bit multiply/divide, double the digits per word).

**Decision:** Changing to base 2^64 would fundamentally alter the library
architecture (input/output conversion, all arithmetic routines, decimal scaling
logic). **This is not planned** — Decimo is a decimal arithmetic library and the
base-10^9 representation aligns with its purpose.

### 9. GMP Backend Option (Long-Term Consideration)

For users who need high-performance transcendental functions and are willing to
accept a native dependency, a future option is to provide a GMP-backed
implementation of sin, cos, pi, etc. at the lower level (similar to how mpmath
delegates to GMP). Decimo would also continue to provide pure-Mojo fallbacks for
environments where GMP is not available or where a dependency-free build is
preferred.

This would be a separate module or compile-time feature flag, not a replacement
for the existing pure-Mojo code.

## Summary Table

| #   | Area                                    | Impact | Effort | Notes                                                        |
| --- | --------------------------------------- | ------ | ------ | ------------------------------------------------------------ |
| 1   | Pi caching                              | High   | Low    | Blocked on Mojo global variable support; code already exists |
| 2   | Reduce BUFFER_DIGITS                    | High   | Low    | Profile to find safe minimum; likely 15–30                   |
| 3   | Direct cos() range reduction            | Medium | Low    | cos_taylor_series() already exists                           |
| 4   | Chudnovsky P/Q/B recursion              | High   | Medium | Standard formulation, well-documented                        |
| 5   | tan() skip redundant reduction          | Medium | Low    | Pass reduced input directly to Taylor                        |
| 6   | Multiply instead of divide for π/2, π/4 | Low    | Low    | Trivial change                                               |
| 7   | Toom-3 / NTT multiplication             | High   | High   | Long-term, no timeline                                       |
| 8   | Base 2^64                               | —      | —      | Not planned; would break architecture                        |
| 9   | Optional GMP backend                    | High   | High   | Long-term consideration                                      |
