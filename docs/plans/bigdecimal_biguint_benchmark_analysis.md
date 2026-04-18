# BigDecimal and BigUInt Benchmark Results & Optimization Roadmap

> Date of initial planning: 2026-02-21
> Author: Yuhao Zhu
> Scope: BigDecimal (Decimal) and BigUInt (BUInt)

> [!IMPORTANT]
> For v0.8.0, Tasks 1✓, 2✓, 3a✓, 3b✓, 3c✓, 3d✓, 4✓, 6✓, 7✓, 8✓ are the priority to be competitive at all sizes.

## Optimization priority and planning

| Task       | Operation(s) Improved     |            Current vs Python             |   Expected After    |  Effort   | Priority     |
| ---------- | ------------------------- | :--------------------------------------: | :-----------------: | :-------: | ------------ |
| **Task 1** | Asymmetric division       |               ✓ **31–79×**               |     ✓ COMPLETED     |   Done    | High         |
| **Task 2** | Division (large operands) | ✓ **avg 24.6× (was 0.78×), up to 915×**  |     ✓ COMPLETED     |   Done    | High         |
| **Task 3** | Exp, ln                   | Exp: **0.87×@p50→5.3×@p2000** (3d done)  | 3a✓,3b✓,3c✓,3d✓,3f✓ |  Medium   | **Critical** |
| **Task 4** | Sqrt                      |    ✓ **3.53× geo (was 0.66×@p5000)**     |     ✓ COMPLETED     |   Done    | High         |
| **Task 5** | ALL large operations      |                  varies                  |     2–10× gain      | Very High | Low          |
| **Task 6** | Large multiplication      | ✓ **+14–29% over Karatsuba (256–4096w)** |     ✓ COMPLETED     |   Done    | Medium       |
| **Task 7** | Nth root                  |   7a✓ **3.9–25×**; 7c✓ frac roots fast   |    7b remaining     |  Medium   | High         |
| **Task 8** | All (allocation overhead) |           ✓ **+15–27% exp/ln**           |     ✓ COMPLETED     |   Done    | High         |
| **Task 9** | Schoolbook multiply base  |                    —                     |       1.5–2×        |    Low    | Medium       |

### Planned Execution Order

1. ~~**Task 1** (asymmetric division fix) — immediate win, unblocks other work~~ ✓ DONE
1. ~~**Task 3a** (cache ln(2)/ln(1.25) via MathCache struct)~~ ✓ DONE
1. ~~**Task 3b** (exp/ln cheap integer division)~~ ✓ DONE — ln near-1 improved 30–100%, exp improved 5–30% at p≤200
1. ~~**Task 3c** (cache `ln(10)` in MathCache)~~ ✓ DONE — `get_ln10()` used by `log10()`/`log()` directly; ln() decomposes into ln(2)+ln(1.25) for generality
1. ~~**Task 7** (direct nth root) — Newton's method replaces exp(ln(x)/n)~~ ✓ DONE (7a) — integer roots 1.2–50× Python (was 0.14–0.49×)
1. ~~**Task 8** (in-place operations) — broad improvement~~ ✓ DONE — exp +15–21%, ln +15–27%, sqrt +9%
1. ~~**Task 4** (CPython-style exact sqrt + reciprocal sqrt hybrid)~~ ✓ DONE — 3.53× geometric mean (was 0.66×), 0 correctness warnings, bit-perfect Python match
1. ~~**Task 2** (truncation optimization for large-operand division)~~ ✓ DONE — avg 24.6× (was 0.78×), large balanced up to 915× Python, asymmetric up to 124×
1. ~~**Task 6** (Toom-3) — medium complexity, medium gain~~ ✓ DONE — +14% at 256–1024w, +28–29% at 2048–4096w
1. ~~**Task 3d** (aggressive range reduction for exp)~~ ✓ DONE — exp 0.87×@p50→5.3×@p2000, beats Python at p≥200
1. ~~**Task 3f** (atanh reformulation for ln)~~ ✓ DONE — ln_series_expansion uses 2·atanh(z/(2+z)) identity, ~3× fewer terms (rate 1/9 vs 1/2), exact Python match at p=50 and p=100
1. ~~**Task 7c** (rational root decomposition)~~ ✓ DONE — fractional n=a/b decomposed to integer_power(integer_root(x,a),b), exact results for perfect cases (8^(2/3)=4, 27^(2/3)=9, etc.)
1. **Task 7b** (reciprocal Newton for integer_root) — 1.5–2× per iteration, medium effort
1. **Task 3e** (binary splitting for ln series) — mainly benefits ln now (exp already fast with 3d)
1. **Task 3g** (AGM-based ln for p>1000) — 10–50× at large p, high effort
1. **Task 5** (NTT) — less urgent than thought; Karatsuba competitive up to p=1000
1. **Task 9** (SIMD multiply) — polish

---

### Design Idea: `pad_to_precision: Bool = False` parameter

**Context:** After implementing the truncation optimization (Task 2), an exact-division post-check was added: when the result has trailing zeros, we verify whether `stripped_result × original_y == original_x`. If so, we return the stripped result (e.g., `"2"` instead of `"2.0000000000000000000000000000"`). This ensures Python-matching behavior for exact divisions.

**Proposal:** Add an optional `pad_to_precision: Bool = False` parameter to `true_divide()` (and potentially `sqrt()`).

| `pad_to_precision` | Behavior                                                                                                        | Use Case                                                                    |
| ------------------ | --------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `False` (default)  | Python semantics: detect exact division, strip trailing zeros. `10 / 5 → "2"`                                   | Correctness, Python compatibility, financial precision                      |
| `True`             | Always return a result with exactly `precision` significant digits. `10 / 5 → "2.0000000000000000000000000000"` | High-throughput scientific computing where fixed-width results are expected |

**Advantages:**

1. **Performance:** When `True`, skips the exact-division check (a `BigUInt × BigUInt` multiplication + comparison), saving time for callers who don't need minimal representation.
2. **Predictable output width:** All results have exactly `precision` digits, simplifying downstream formatting/alignment.
3. **No breaking change:** Default is `False` → existing code behaves identically.

**Concerns addressed:**

- The exact-division check only fires when trailing zeros exist, so the cost is already minimal for non-exact divisions. The speedup from `pad_to_precision=True` is only meaningful when many exact divisions occur in a hot loop.
- For `sqrt()`, the same logic applies: `sqrt(4, precision=28)` currently returns `"2"`, but with `pad_to_precision=True` would return `"2.000000000000000000000000000"`.

**Recommendation:** Good idea. Low implementation cost (single `if` guard around the post-check), zero overhead for existing callers, useful for batch numerical computing. Implement when a concrete use case demands it.

---

## Benchmarks

**Benchmark location:** `benches/bigdecimal/` (BigDecimal vs Python `decimal`).  
BigUInt-only benchmarks are in `benches/biguint/`.  
Run with `pixi run bdec` (interactive) or `pixi run bench bigdecimal <op>`.

## Architecture Overview

```txt
BigDecimal  (coefficient: BigUInt, scale: Int, sign: Bool)
    ↓ delegates ALL integer arithmetic to
BigUInt     (words: List[UInt32], base-10^9, little-endian)
```

**Value formula:** $(-1)^{\text{sign}} \times \text{coefficient} \times 10^{-\text{scale}}$

BigDecimal is a **thin wrapper** around BigUInt. Its performance is almost
entirely determined by BigUInt's performance, because:

- Addition/subtraction: align scales via `multiply_by_power_of_ten` → add/subtract BigUInt coefficients
- Multiplication: multiply BigUInt coefficients → add scales
- Division: scale up dividend's BigUInt → integer divide → adjust scale
- Sqrt: CPython-style exact integer rescaling → `fast_isqrt` (reciprocal sqrt + Newton) → round
- Exp/ln/trig: iterative algorithms (Taylor series, Newton) composed from the above

**BigUInt internals:** base-$10^9$, each limb is `UInt32 ∈ [0, 999_999_999]`, SIMD-vectorized addition/subtraction (width=4), Karatsuba multiplication (cutoff=64 words), Burnikel-Ziegler division (cutoff=32 words).

---

## Benchmark Summary (latest results, macOS arm64, Apple Silicon)

All benchmarks compare **Decimo BigDecimal** against **Python `decimal.Decimal`** (CPython 3.13, backed by `libmpdec`). Speedup = Python time / Mojo time. Values >1× mean Mojo is faster; <1× mean Python is faster.

### Overall Results by Operation

| Operation          | Avg Speedup vs Python | Precision | Key Observation                                                    |
| ------------------ | :-------------------: | :-------: | ------------------------------------------------------------------ |
| **Addition**       |       **2.22×**       |    28     | Consistent ~2.4× for ≤28 digits; degrades >1000 digits             |
| **Subtraction**    |       **9.79×**       |    28     | Consistently ~9× across all small cases                            |
| **Multiplication** |       **3.44×**       |    28     | 2–7× across all tested sizes                                       |
| **Division**       |      **24.62×**       |    50     | Up to 915× for large balanced; **12–124× asymmetric** (Tasks 1+2)  |
| **Sqrt**           |       **3.53×**       |   5000    | 1.6–75× all cases; **0 correctness warnings** (exact Python match) |
| **Exp**            |        0.55×†         |    50     | ↑ from 0.34× at p=28; Python still ~2× faster consistently         |
| **Ln**             |        0.18×†         |    50     | 0.78× near 1; Python has cached ln(10) for power-of-10 args        |
| **Root (nth)**     |        0.25×†         |    50     | √ fast; general nth root **0.14–0.49×** (exp(ln(x)/n) costly)      |
| **Rounding**       |      **105.80×**      |    28     | Overwhelmingly faster (simple word truncation)                     |

\* Geometric mean across all 70 cases; trivial cases (√1, √0.01, etc.) are 73–75×.  
† New results with precision = 50 (Mojo and Python at same precision). Previous results at mismatched precision (Mojo default 28–36 vs Python 10000) were not comparable.

---

## Detailed Per-Operation Analysis

### Addition (60 cases, precision=28)

| Size               | Mojo (ns) | Python (ns) |  Speedup  |
| ------------------ | --------: | ----------: | :-------: |
| Small (≤28 digits) |   100–160 |     250–300 | 2.0–6.3×  |
| 1000 digits        |       208 |         319 |   1.53×   |
| 1500 digits        |       229 |         374 |   1.63×   |
| 2000 digits        |       257 |         328 |   1.28×   |
| 2500 digits        |       580 |         546 | **0.94×** |
| 3000+ digits       |       819 |         626 | **0.76×** |

**Analysis:** Addition is 2.0–2.5× faster for typical-precision decimals (≤28 digits). The SIMD-vectorized BigUInt addition gives an edge. At 2500+ digits, Python overtakes because `libmpdec` uses assembly-optimized routines for large coefficient arithmetic.

**Bottleneck:** Scale alignment via `multiply_by_power_of_ten` can be expensive if scales differ greatly, triggering large word-array expansions before the actual add.

---

### Subtraction (50 cases, precision=28)

| Size            | Mojo (ns) | Python (ns) | Speedup |
| --------------- | --------: | ----------: | :-----: |
| Typical (≤28 d) |   130–230 | 1,400–1,800 |  7–11×  |
| Zero result     |       141 |       1,585 |  11.2×  |
| Subtract 0      |        58 |       1,669 |  28.8×  |

**Analysis:** Subtraction is surprisingly fast — **~10× Python** on average. The gap vs addition speedup (2.2×) is noteworthy. This likely reflects Python `decimal`'s overhead for subtraction's sign handling and normalization, which `libmpdec` does not fast-path as well as addition.

---

### Multiplication (50 cases, precision=28)

| Size               | Mojo (ns) | Python (ns) | Speedup  |
| ------------------ | --------: | ----------: | :------: |
| Zero/one operand   |    36–100 |     258–264 | 2.6–7.2× |
| Small (≤28 digits) |    70–130 |     258–318 | 2.0–4.4× |
| Typical (28-digit) |    80–110 |     274–304 | 2.8–3.8× |

**Analysis:** Multiplication is consistently 3–4× faster for typical precision. This is excellent. The Karatsuba-accelerated BigUInt multiplication pays off even at small sizes because there's no overhead for scale handling (just add scales, XOR sign).

**Missing:** No benchmarks for very large multiplication (1000+ digit coefficients). This would be important for operations like `exp` at high precision, which need many large-coefficient multiplications internally.

---

### Division (64 cases, precision=50)

> **Update (2026-02-22):** Precision unified to 50 via TOML config. Both Mojo
> (`true_divide_general(a, b, precision)`) and Python (`getcontext().prec = 50`)
> now compute the same number of significant digits. Previous benchmarks used
> `comptime PRECISION = 4096` for Mojo and `prec = 4096` for Python.
>
> **Update (2026-02-23):** Task 2 implemented — truncation optimization for large-operand
> division. When both operands have far more words than needed for the requested precision,
> truncate to only the significant top words before dividing. This avoids running
> Burnikel-Ziegler on hundreds of thousands of unnecessary words. Average speedup
> improved from **0.78× → 24.6×** (was slower than Python, now massively faster).

**Balanced division (equal-size operands) — AFTER Task 2 (truncation optimization, 2026-02-23):**

| Size (words)      | Mojo (ns) | Python (ns) |   Speedup   |
| ----------------- | --------: | ----------: | :---------: |
| Small (≤28 d)     |   310–680 |   730–2,710 |  2.0–8.0×   |
| 1024w / 1024w     |     1,480 |      11,280 |  **7.62×**  |
| 2048w / 2048w     |     2,000 |      25,333 | **12.67×**  |
| 4096w / 4096w     |     1,333 |      42,333 | **31.76×**  |
| 8192w / 8192w     |     9,000 |      88,666 |  **9.85×**  |
| 16384w / 16384w   |    10,666 |     170,000 | **15.94×**  |
| 32768w / 32768w   |     5,333 |     334,333 | **62.69×**  |
| 65536w / 65536w   |     5,666 |     646,666 | **114.13×** |
| 262144w / 262144w |     2,666 |   2,438,666 | **914.73×** |

**Balanced division — BEFORE Task 2 (for comparison):**

| Size (words)      |  Mojo (ns) | Python (ns) | Speedup |
| ----------------- | ---------: | ----------: | :-----: |
| 1024w / 1024w     |     36,990 |      11,180 |  0.30×  |
| 2048w / 2048w     |     75,666 |      21,333 |  0.28×  |
| 4096w / 4096w     |    156,666 |      40,666 |  0.26×  |
| 8192w / 8192w     |    310,666 |      83,333 |  0.27×  |
| 16384w / 16384w   |    680,000 |     225,666 |  0.33×  |
| 32768w / 32768w   |  1,375,666 |     335,000 |  0.24×  |
| 65536w / 65536w   |  2,842,333 |     641,666 |  0.23×  |
| 262144w / 262144w | 12,088,000 |   2,276,666 |  0.19×  |

**Asymmetric division (unbalanced operands) — BEFORE Task 1 FIX:**

| Size            |   Mojo (ns) | Python (ns) |   Speedup   |
| --------------- | ----------: | ----------: | :---------: |
| 65536w / 32768w | 444,571,666 |  50,058,333 | **0.11×** ✗ |
| 65536w / 16384w | 146,761,000 |  24,933,000 | **0.17×** ✗ |
| 65536w / 8192w  |  47,861,000 |  12,604,333 | **0.26×** ✗ |
| 65536w / 4096w  |  15,804,000 |   6,376,666 | **0.40×** ✗ |
| 65536w / 2048w  |   5,099,000 |   3,180,333 | **0.62×** ✗ |
| 65536w / 1024w  |   1,776,333 |     805,333 | **0.45×** ✗ |

**Asymmetric division — AFTER Task 2 (2026-02-23), supersedes Task 1 results:**

| Size            | Mojo (ns) | Python (ns) |   Speedup   |
| --------------- | --------: | ----------: | :---------: |
| 65536w / 32768w |     5,333 |     652,666 | **122.38×** |
| 65536w / 16384w |     2,333 |     289,000 | **123.87×** |
| 65536w / 8192w  |     3,333 |     144,000 | **43.20×**  |
| 65536w / 4096w  |     2,000 |      72,333 | **36.17×**  |
| 65536w / 2048w  |     1,666 |      38,666 | **23.21×**  |
| 65536w / 1024w  |     2,000 |      25,000 | **12.50×**  |

**Key findings:**

1. ~~**Balanced division is outstanding** — 15–28× faster than Python at large sizes.~~ **IMPROVED to 8–915× after Task 2 truncation.** Truncation reduces the effective problem size to ~12 words regardless of operand size, making Mojo time nearly constant while Python scales linearly with operand size. The 262144w case went from 0.19× (5× slower than Python) to **914.73×** (fastest case in the benchmark).
2. ~~**Asymmetric division is catastrophically slow**~~ **FIXED in Task 1, further improved in Task 2.**
   Task 1 root cause was BigDecimal.true_divide_general computing full quotient then discarding (31–79× after fix). Task 2 truncation further improved to **12–124×** by also truncating the large dividend.
3. **Small-case performance unchanged.** The truncation optimization uses an early-return to a helper function only when the divisor exceeds `needed_divisor_words = ceil(precision/9) + 2 + 4`. For small operands the original code path runs untouched — no regression.
4. **Algorithm:** When divisor has more words than needed for the target precision, both operands are truncated by removing low-order words via `floor_divide_by_power_of_billion()` (O(n) memcpy). This exploits $x/y \approx (x/10^k)/(y/10^k)$ with negligible relative error for the requested precision. Guard words (`TRUNCATION_GUARD = 4`) ensure sufficient accuracy.

---

### Square Root (70 cases, precision=5000)

> **Update (2026-02-23):** sqrt completely rewritten with CPython's exact integer
> algorithm (`sqrt_exact`) for bit-perfect correctness, plus a hybrid `fast_isqrt`
> accelerator (reciprocal sqrt approximation + exact integer Newton refinement).
> `to_string()` fully rewritten to match CPython's `Decimal.__str__` logic exactly
> (scientific notation when `_exp > 0` or `leftdigits <= -6`; removed the Decimo-specific
> `precision` parameter). `root()` now strips trailing fractional zeros from exact results
> (e.g., `cbrt(8) → "2"` instead of `"2.000…0"`). All 70 benchmark
> cases now produce **identical** output to Python's `Decimal.sqrt()` with 0 warnings.

#### BEFORE Task 4 (BigUInt.sqrt Newton only, v0.5.0)

| Input type               |           Mojo (ns) |         Python (ns) |    Speedup     |
| ------------------------ | ------------------: | ------------------: | :------------: |
| Perfect squares (√4, √9) |       25,000–28,000 | 5,135,000–5,520,000 |  **185–215×**  |
| Trivial scale (√0.0001)  |               6,550 |           5,478,790 |    **836×**    |
| Irrational (√2, √3, √5)  | 7,550,000–7,670,000 | 4,500,000–5,500,000 | **0.55–0.72×** |
| Large coefficients       | 7,600,000–7,710,000 | 5,088,000–5,478,000 | **0.66–0.71×** |

Geometric mean: ~0.66× (heavily skewed by perfect square fast-paths).
**50 of 54 irrational cases had correctness warnings** (last digits mismatch).

#### AFTER Task 4 (CPython exact algorithm + fast_isqrt hybrid, 2026-02-23)

| Input type                   |           Mojo (ns) |         Python (ns) |   Speedup    |
| ---------------------------- | ------------------: | ------------------: | :----------: |
| Perfect squares (√4, √9)     |     584,000–634,000 | 5,170,000–5,496,000 | **8.2–8.9×** |
| Trivial (√0.0001, √1, √0.01) |       72,000–75,000 | 5,482,000–5,514,000 |  **73–75×**  |
| Small irrational (√2, √PI)   | 1,560,000–1,600,000 | 5,196,000–5,546,000 | **3.2–3.5×** |
| General irrational (primes)  | 1,560,000–2,100,000 | 4,232,000–5,520,000 | **2.0–3.5×** |
| Large coefficients (≥2500w)  | 2,726,000–3,271,000 | 5,088,000–5,486,000 | **1.6–2.0×** |

**Summary statistics (70 cases):**

| Metric          |  Speedup  |
| --------------- | :-------: |
| Min             |   1.58×   |
| Median          |   2.86×   |
| Geometric mean  | **3.53×** |
| Arithmetic mean |   8.14×   |
| Max             |   75.4×   |
| Warnings        |   **0**   |

**Key improvements:**

1. **100% correctness.** All 70 results match Python's `Decimal.sqrt()` string output exactly. Zero warnings (was 50+ warnings before). Perfect squares produce exact results (e.g., `sqrt(9) = "3"`, not `"2.999..."`) at all precisions including p=5000.
2. **Consistently faster than Python.** Every case is ≥1.58× Python speed. No cases slower than Python (was 0.55–0.72× for all irrationals before).
3. **Algorithm:** CPython-style exact integer rescaling + `isqrt(c)` + `n*n==c` check. For large inputs (>20 BigUInt words), `fast_isqrt` provides a fast initial approximation via reciprocal sqrt with precision doubling, then refines with exact integer Newton iterations to converge to the true `isqrt(c)`.
4. **Function hierarchy:** `sqrt()` (public API) → `sqrt_exact()` (CPython-style, for user-facing results) and `sqrt_reciprocal()` (fast, for internal use by `arctan`, `ln`, `pi`, etc. where exact perfect-square detection is unnecessary).

**Why perfect squares are slower than before (8× vs 185×):** The old algorithm fast-pathed perfect squares with a trivial check before any Newton work. The CPython algorithm always rescales `c` and computes `isqrt(c)` before checking exactness. The ~630µs cost is the rescaling + isqrt of an ~5000-digit number. This trade-off is worth it: 8× Python is still fast, and correctness is guaranteed.

**Why irrationals are much faster (1.6–3.5× vs 0.55–0.72×):** The old algorithm used pure `BigUInt.sqrt()` Newton (with division in every iteration). The new `fast_isqrt` uses reciprocal sqrt with precision doubling (division-free, O(M(n) log n)) to get a close approximation, then only 1–3 cheap integer Newton steps to converge exactly. This avoids the expensive ~15–20 Newton divisions of the old approach.

---

### Exp (50 cases)

#### BEFORE precision matching (Mojo default=36, Python prec=10000) — NOT comparable

These earlier results were invalid benchmarks: Mojo computed only 36 significant digits
while Python computed 10000. The speedup figures were misleading.

| Input        | Mojo (ns) | Python (ns) | Speedup | Note                  |
| ------------ | --------: | ----------: | :-----: | --------------------- |
| exp(0)       |        60 |       1,510 |  25.2×  | Fast-path (trivial)   |
| exp(1)       |    16,250 |       6,410 |  0.39×  | Mojo=36 vs Python=10K |
| exp(0.01)    |    11,750 |       4,030 |  0.34×  | ← unfair comparison   |
| exp(0.1)     |    14,480 |       6,270 |  0.43×  | ← unfair comparison   |
| exp(10)      |    17,740 |       7,710 |  0.43×  | ← unfair comparison   |
| exp(-1)      |    21,630 |       6,760 |  0.31×  | ← unfair comparison   |
| exp(1e-10)   |     3,840 |       1,670 |  0.43×  | ← unfair comparison   |
| exp(1000000) |    20,800 |      11,240 |  0.54×  | ← unfair comparison   |

Previous average: 0.34× (Python appeared ~3× faster)

#### AFTER precision matching (both precision=50, 2026-02-22)

All computations now produce identical results at 50 significant digits.
Zero correctness warnings except for extreme edge cases (`exp(-10000000)` etc. where
Python underflows to zero due to exponent range limits).

| Input       | Mojo (ns) | Python (ns) | Speedup  | Difference |
| ----------- | --------: | ----------: | :------: | :--------: |
| exp(0)      |       120 |         320 | **2.7×** |     0      |
| exp(1)      |   105,290 |      68,190 |  0.65×   |   0E-50    |
| exp(-1)     |   110,490 |      66,280 |  0.60×   |   0E-50    |
| exp(2)      |   106,350 |      67,730 |  0.64×   |   0E-50    |
| exp(0.1)    |    94,530 |      66,100 |  0.70×   |   0E-50    |
| exp(0.01)   |    90,420 |      42,280 |  0.47×   |   0E-50    |
| exp(0.5)    |   111,650 |      64,580 |  0.58×   |   0E-50    |
| exp(10)     |   106,420 |      65,860 |  0.62×   |   0E-49    |
| exp(100)    |   110,440 |      71,840 |  0.65×   |   0E-48    |
| exp(0.0001) |    58,200 |      25,590 |  0.44×   |   0E-50    |
| exp(1e-10)  |    27,960 |       9,850 |  0.35×   |   0E-50    |

**New average**: ~0.55× (Python ~1.8× faster)

**Analysis (updated):** With matched precision=50, Mojo's exp is **less slow than
previously reported** (0.55× vs the misleading 0.34×). The per-call cost is higher
because Mojo now computes 50 digits instead of 36, but the comparison is fair.
Python is still ~1.8× faster due to:

- `libmpdec`'s NTT-based multiplication for internal Taylor series arithmetic
- Optimized range reduction (reduction by `ln(10)`, not `ln(2)`)
- Correct rounding via Ziv's method (compute at slightly higher precision, retry if needed)

**Key insight:** The previous 0.34× figure was artificially deflated by Python
doing 278× more work (10000 vs 36 digits). The true gap is ~1.8×, which is
much more tractable for optimization via Task 3b–3d.

---

### Ln (50 cases)

> **Note (2026-02-22):** Ln was not benchmarked with matched precision before this
> update. Previous estimates came from the root cause analysis section (estimated
> ~0.3× Python at precision=28 based on exp performance). These are the first
> properly matched benchmarks.

#### Ln results with precision matching (both precision=50, 2026-02-22)

All computations produce identical results at 50 significant digits.
Zero correctness warnings (all differences are 0 or 0E-xxx with zero coefficient).

| Input     | Mojo (ns) | Python (ns) | Speedup  | Difference |
| --------- | --------: | ----------: | :------: | :--------: |
| ln(1)     |       300 |         300 | **1.0×** |     0      |
| ln(e)     | 6,607,540 |     120,050 |  0.02×   |   0E-200   |
| ln(2)     |   677,110 |     118,700 |  0.18×   |   0E-200   |
| ln(10)    | 1,007,810 |       1,130 |  0.001×  |   0E-199   |
| ln(0.5)   |   672,140 |     124,260 |  0.18×   |   0E-200   |
| ln(0.9)   |   162,430 |     126,330 |  0.78×   |   0E-200   |
| ln(0.99)  |    83,710 |      76,420 |  0.91×   |   0E-201   |
| ln(0.999) |    56,390 |      54,520 |  0.97×   |   0E-202   |
| ln(1.001) |    55,340 |      44,180 |  0.80×   |   0E-203   |
| ln(1.01)  |    80,630 |      55,160 |  0.68×   |   0E-202   |
| ln(1.1)   |   162,240 |      76,580 |  0.47×   |   0E-201   |
| ln(0.1)   |   994,350 |         770 |  0.001×  |   0E-199   |
| ln(100)   |   998,260 |       1,020 |  0.001×  |   0E-199   |
| ln(1e-10) |   993,000 |         710 |  0.001×  |   0E-198   |

**Key observations:**

1. **Values near 1 are competitive:** `ln(0.9)` = 0.78×, `ln(0.99)` = 0.91×, `ln(0.999)` = 0.97× — the Taylor series converges very fast for small arguments.
2. **Powers of 10 are catastrophically slow:** `ln(10)`, `ln(0.1)`, `ln(100)` show Mojo 1000× slower. Python's `libmpdec` caches `ln(10)` and computes `ln(10^k)` = `k × ln(10)` in O(1). Mojo must compute from scratch each time.
3. **ln(e)** is surprisingly slow (~6.6ms) because `e` = 2.718… is far from 1.0 and requires full range reduction + series evaluation.
4. **ln(2)** = 677µs vs Python's 119µs → 0.18×. This is the constant that `MathCache` optimizes for repeated calls.

**Analysis:** The ln performance landscape has two distinct regimes:

- **Near 1 (|x-1| < 0.1):** Mojo is 0.68–0.97× Python (nearly competitive)
- **Far from 1:** Mojo is 0.001–0.18× Python (extremely slow)

The far-from-1 case is dominated by range reduction to $x = m \times 2^k \times 1.25^j$, which requires computing `ln(2)` and `ln(1.25)` each time (unless cached via `MathCache`). The `MathCache` from Task 3a helps with repeated calls but can't eliminate the first-call cost.

**Python `libmpdec`'s advantage for ln:**

- Cached `ln(10)` at various precisions with sub-microsecond lookup
- Range reduction modulo `ln(10)` instead of `ln(2)` (more efficient for decimal base)
- NTT-based multiplication in the Taylor series
- Ziv's method for correct rounding

---

### Root (50 cases)

#### BEFORE precision matching (Mojo hardcoded=28, Python prec=10000) — NOT comparable

| Input                | Mojo (ns) | Python (ns) | Speedup | Note                  |
| -------------------- | --------: | ----------: | :-----: | --------------------- |
| √64 (perfect square) |     1,750 |      47,420 |  27.1×  | Fast-path             |
| √2 (irrational)      |     7,640 |      46,530 |  6.1×   | Mojo=28 vs Python=10K |
| ∛27 (perfect cube)   |   171,430 |      50,030 |  0.29×  | ← unfair comparison   |
| ∛10 (non-perfect)    |    85,080 |      17,340 |  0.20×  | ← unfair comparison   |
| ⁵√32                 |   175,460 |      47,870 |  0.27×  | ← unfair comparison   |
| ∛e                   |   291,100 |      51,200 |  0.18×  | ← unfair comparison   |
| 100th root of 2      |    15,450 |      40,130 |  2.6×   | ← unfair comparison   |

#### AFTER precision matching (both precision=50, 2026-02-22)

All computations produce identical results at 50 significant digits (4 edge cases
with 1–3 ULP last-digit difference, expected for compound `exp(ln(x)/n)`).

| Input                    | Mojo (ns) | Python (ns) |  Speedup  | Difference |
| ------------------------ | --------: | ----------: | :-------: | :--------: |
| √64 (perfect square)     |     1,500 |      60,730 | **40.5×** |   0E-49    |
| √(non-perfect)           |     7,250 |      74,510 | **10.3×** |   0E-49    |
| ∛27 (perfect cube)       |   243,570 |      58,390 |   0.24×   |   0E-49    |
| ∛10 (non-perfect)        |   145,880 |      20,440 |   0.14×   |   0E-49    |
| ⁴√16 (perfect power)     |   200,000 |      60,830 |   0.30×   |   0E-49    |
| ⁵√32 (perfect power)     |   242,190 |      62,390 |   0.26×   |   0E-49    |
| ¹⁰√1024 (perfect power)  |   149,830 |      37,660 |   0.25×   |   0E-49    |
| ∛(non-perfect, 4th root) |   129,020 |      63,560 |   0.49×   |   0E-49    |
| ¹⁰⁰√2                    |   116,780 |      20,170 |   0.17×   |   0E-49    |
| ⅓ root (0.333…)          |   241,970 |     100,710 |   0.42×   |   0E-49    |

**Before vs After comparison for Root:**

| Input         | Before Speedup | After Speedup | Change                                            |
| ------------- | :------------: | :-----------: | ------------------------------------------------- |
| √64           |     27.1×      |   **40.5×**   | ↑ Faster (precision=50 vs 28)                     |
| √2 (non-perf) |      6.1×      |   **10.3×**   | ↑ Faster (new sqrt case)                          |
| ∛27           |     0.29×      |     0.24×     | ≈ Same (fair comparison now)                      |
| ∛10           |     0.20×      |     0.14×     | ↓ Slightly worse (Python was undercounted before) |
| ⁵√32          |     0.27×      |     0.26×     | ≈ Same                                            |

**Analysis (updated after Task 7a ✓):** Square roots are fast-pathed via `BigUInt.sqrt()` and show excellent speedups (10–40×). General nth roots now use direct Newton's method ($r_{k+1} = ((n-1)r + x/r^{n-1})/n$), matching Python `libmpdec`'s approach. At precision=50, **integer roots improved from 0.14–0.49× to 1.2–9× Python**. Fractional roots (0.5th, 0.25th, 0.333rd) still use `exp(ln(x)/n)` path (0.2–0.4×) — see Task 7c for fix.

**Correctness:** `root()` now strips trailing fractional zeros from exact results via `_strip_trailing_fractional_zeros()` — e.g., `root(8, 3)` returns `"2"` instead of `"2.000000000000000000000000000"`, matching Python's behavior. The stripping uses a threshold (≥9 trailing zeros) to distinguish true exact results from coincidental trailing zeros in approximate results.

**Before → After Task 7a (selected cases at p=50):**

| Case              | Before | After | Improvement |
| ----------------- | :----: | :---: | :---------: |
| ∛27 (perfect)     | 0.24×  | 4.25× |    17.7×    |
| ∛10 (non-perfect) | 0.14×  | 2.0×  |    14.3×    |
| ⁴√16              | 0.30×  | 5.91× |    19.7×    |
| ⁵√32              | 0.26×  | 4.83× |    18.6×    |
| ¹⁰√1024           | 0.25×  | 2.47× |    9.9×     |
| ¹⁰⁰√2             | 0.17×  | 5.13× |    28.5×    |

---

### Rounding (25 cases, precision=28)

Avg 105.8×. This is dominated by the overhead of Python's `decimal.quantize()` vs Mojo's direct word-level truncation. Not a concern for optimization.

**Bug fix (2026-02-23):** `round()` with `ROUND_UP` mode now correctly returns 1 (at the target scale) when all significant digits are removed from a non-zero value. Previously it returned 0 in this case.

---

## Multi-Precision Scaling Analysis (2026-02-22)

> **Why multi-precision?** A single precision level (e.g., p=50) only tests small-sized
> computation. Precision determines problem size for transcendental functions — at p=50,
> BigUInt coefficients are ~6 words; at p=1000, they're ~112 words. Scaling behavior
> reveals where algorithmic complexity differences dominate.

### Exp — Multi-Precision Scaling (p=50 to 2000)

Benchmarked 12 representative cases at 6 precision levels. Iterations decrease with
precision to keep total bench time manageable (50→20→5→2→1→1).

**Summary table (excluding trivial exp(0)), after Task 3b (UInt32 division in Taylor series):**

| Case        |  p=50 | p=100 | p=200 | p=500 | p=1000 | p=2000 |
| ----------- | ----: | ----: | ----: | ----: | -----: | -----: |
| exp(1)      | 0.60× | 0.46× | 0.71× | 1.12× |  1.11× |  1.61× |
| exp(-1)     | 0.51× | 0.41× | 0.65× | 1.07× |  1.12× |  1.35× |
| exp(2)      | 0.56× | 0.44× | 0.59× | 1.16× |  1.01× |  1.51× |
| exp(0.5)    | 0.48× | 0.32× | 0.67× | 0.64× |  0.94× |  1.38× |
| exp(-0.5)   | 0.46× | 0.36× | 0.61× | 0.91× |  0.95× |  1.37× |
| exp(0.01)   | 0.32× | 0.32× | 0.53× | 0.81× |  0.83× |  1.23× |
| exp(0.1)    | 0.53× | 0.44× | 0.81× | 1.17× |  1.10× |  1.60× |
| exp(10)     | 0.67× | 0.44× | 0.65× | 1.06× |  1.08× |  1.58× |
| exp(-10)    | 0.56× | 0.39× | 0.69× | 1.05× |  1.09× |  1.58× |
| exp(100)    | 0.69× | 0.51× | 0.71× | 1.17× |  1.17× |  1.62× |
| exp(0.0001) | 0.26× | 0.28× | 0.45× | 0.68× |  0.77× |  1.13× |

**Key findings (updated after Task 3b):**

1. **Mojo exp now beats Python at p=2000 across the board: 1.13–1.62×.**
2. **At p=1000, Mojo is roughly at parity (0.83–1.17×).**
3. **At p=50, Task 3b improved performance by 5–25%.** Typical cases: exp(1) 0.48→0.60×, exp(10) 0.58→0.67×, exp(-10) 0.45→0.56×.
4. **The crossover point is around p=200–500** (unchanged from before).
5. **exp(0.0001) and exp(0.01) remain the slowest** due to Python's fast-path optimizations for tiny arguments.

**Absolute timing growth (exp(1)):**

| Precision |  Mojo (ns) | Python (ns) | Ratio |
| --------: | ---------: | ----------: | ----: |
|        50 |     15,500 |       9,280 | 0.60× |
|       100 |     33,150 |      15,300 | 0.46× |
|       200 |     95,600 |      68,000 | 0.71× |
|       500 |    804,000 |     903,000 | 1.12× |
|     1,000 |  4,272,000 |   4,732,000 | 1.11× |
|     2,000 | 22,872,000 |  36,865,000 | 1.61× |

Mojo scales at roughly $O(p^{2.3})$ while Python scales at $O(p^{2.5})$ — Mojo's per-step cost is higher at small sizes but grows slower, leading to the crossover.

---

### Ln — Multi-Precision Scaling (p=50 to 2000)

Benchmarked 12 representative cases at 6 precision levels.

**Summary table (excluding trivial ln(1)), after Task 3b (UInt32 division in series):**

| Case      |   p=50 |  p=100 |  p=200 |  p=500 | p=1000 | p=2000 |
| --------- | -----: | -----: | -----: | -----: | -----: | -----: |
| ln(2)     | 16.54× |  0.24× |  0.19× |  0.13× |  0.12× |  0.26× |
| ln(e)     |  0.05× |  0.02× |  0.02× |  0.02× |  0.03× |  0.09× |
| ln(10)    |  0.01× | 0.003× | 0.003× | 0.001× | 0.000× |  0.12× |
| ln(0.5)   | 13.85× |  0.26× |  0.20× |  0.15× |  0.12× |  0.28× |
| ln(0.9)   |  0.79× |  0.91× |  1.22× |  2.58× |  4.33× | 17.06× |
| ln(0.99)  |  0.98× |  0.86× |  1.36× |  3.11× |  5.87× | 31.19× |
| ln(1.01)  |  0.70× |  0.65× |  0.97× |  2.37× |  4.83× | 27.29× |
| ln(1.1)   |  0.64× |  0.45× |  0.67× |  1.58× |  3.22× | 14.68× |
| ln(100)   |  0.01× | 0.000× | 0.000× | 0.000× | 0.000× |  0.12× |
| ln(0.001) |  0.01× | 0.000× | 0.000× | 0.000× | 0.000× |  0.12× |
| ln(PI)    |  0.05× |  0.03× |  0.02× |  0.02× |  0.03× |  0.08× |

**Improvement from Task 3b (UInt32 division) vs previous data:**

| Case     |  p=50 | p=100 | p=200 | p=500 | p=1000 |
| -------- | ----: | ----: | ----: | ----: | -----: |
| ln(0.9)  |  +39% |  +98% |  +61% |  +45% |   +21% |
| ln(0.99) |  +75% |  +62% |  +56% |  +29% |   +38% |
| ln(1.01) |  +59% |  +59% |  +56% |  +82% |   +26% |
| ln(1.1)  | +129% |  +61% |  +46% |  +33% |   +31% |

**Key findings (updated after Task 3b):**

1. **Near-1 cases dramatically improved at all precisions.** `ln(0.99)` went from 0.56→0.98× at p=50 (+75%) and from 4.24→5.87× at p=1000 (+38%). The UInt32 division optimization reduces per-iteration overhead in the Taylor series, helping most where the series dominates.
2. **At p=2000, ln near-1 reaches astronomical speedups: 14–31× Python!** Mojo's $O(p^{1.7})$ scaling vs Python's $O(p^{2.8})$ creates massive gaps at high precision.
3. **ln(2) unchanged** (16.54× at p=50, 0.12× at p=1000) — the decomposition into ln(2)/ln(1.25) is preserved without regression.
4. **Far-from-1 cases unchanged** (still 0.001–0.01× at p=50–1000). These are dominated by computing ln(2)/ln(1.25) from scratch. At p=2000, Python also must compute (0.12×), making the gap smaller.
5. **Task 3c (cached ln(10))** benefits visible in `log10()`/`log()` which use `cache.get_ln10()` directly. Not visible in standalone `ln()` benchmarks since each call creates a fresh cache.

**Two distinct scaling regimes in ln (confirmed, even wider gap now):**

| Regime     |    p=50     |   p=2000   | Scaling               |
| :--------- | :---------: | :--------: | :-------------------- |
| Near-1     | 0.64–0.98×  | 14.7–31.2× | **Mojo dominates**    |
| Far-from-1 | 0.005–0.19× | 0.08–0.28× | **Python still wins** |

**Why the split?** Near-1 inputs use a Taylor series that converges in few terms with small coefficients — multiplication cost dominates, and Karatsuba scales well. Far-from-1 inputs require: (a) computing `ln(2)` and `ln(1.25)` from scratch (Python caches `ln(10)`), (b) many more series terms, (c) full-precision arithmetic on larger intermediate values.

**Absolute timing growth (ln(0.99), near-1 case, after Task 3b):**

| Precision | Mojo (ns) | Python (ns) |  Ratio |
| --------: | --------: | ----------: | -----: |
|        50 |    11,540 |      11,360 |  0.98× |
|       100 |    26,400 |      22,800 |  0.86× |
|       200 |    58,200 |      79,200 |  1.36× |
|       500 |   215,000 |     668,500 |  3.11× |
|     1,000 |   732,000 |   4,295,000 |  5.87× |
|     2,000 | 2,277,000 |  71,013,000 | 31.19× |

Mojo scales at $O(p^{1.7})$ while Python scales at $O(p^{2.8})$ for this near-1 case. Task 3b (UInt32 division) reduced Mojo's absolute time by **27–45%** compared to before (e.g., p=50: 21,000→11,540, p=1000: 1,012,000→732,000).

**Absolute timing growth (ln(10), far-from-1 case):**

| Precision |   Mojo (ns) | Python (ns) |  Ratio |
| --------: | ----------: | ----------: | -----: |
|        50 |      52,600 |         600 |  0.01× |
|       100 |     276,750 |         900 | 0.003× |
|       200 |     929,600 |       2,400 | 0.003× |
|       500 |   9,041,000 |       7,500 | 0.001× |
|     1,000 |  52,867,000 |      18,000 | 0.000× |
|     2,000 | 325,125,000 |  39,116,000 |  0.12× |

Python caches `ln(10)` internally, giving O(1) lookup at p≤1000. At p=2000, Python must recompute (39ms), narrowing the gap to 0.12×. This confirms that the bottleneck is not algorithmic but caching — once Python recomputes, the gap is manageable.

---

### Implications for Task Priorities (updated after Tasks 3b+3c)

The multi-precision data reveals that **the optimization landscape depends heavily on the target precision range**:

**For p ≤ 100 (most common use cases):**

- Exp is 0.3–0.7× Python → constant-factor overhead still dominant
- Ln near-1 is 0.65–0.98× → much improved by Task 3b (was 0.4–0.6×)
- Ln far-from-1 is 0.001–0.01× → still limited by ln(2)/ln(1.25) computation cost

**For p = 200–500 (medium precision):**

- Exp is 0.5–1.2× → approaching/at parity
- Ln near-1 is **0.97–3.11×** → Mojo now wins at p=200+ (was p=500+ before Task 3b)
- Ln far-from-1 still poor → fundamental algorithmic limitation

**For p ≥ 1000 (high precision):**

- Exp is **0.83–1.62× Python** → Mojo ahead!
- Ln near-1 is **3.2–31× Python** → Mojo dominates massively
- Ln far-from-1 at p=2000: 0.12× (Python also recomputes at high precision)

**Remaining task priorities after Tasks 3b+3c+7 ✓:**

1. ~~**Task 8** (in-place operations)~~ ✓ DONE — +15–27% exp/ln, +9% sqrt
2. ~~**Task 4** (reciprocal sqrt + precision doubling)~~ ✓ DONE — 17.9× Python (was 0.90×), **~20× improvement**
3. **Task 2** (reciprocal-Newton division) — requires careful implementation
4. **Task 5** (NTT) — less urgent; Karatsuba competitive up to p=2000

### Root — Multi-Precision Scaling (after Task 7a ✓)

Benchmarked 10 representative root cases (cbrt, 5th root, 10th root, sqrt) at 5 precision levels.
Newton's method scales better than Python's approach at larger precisions:

**Summary table (integer roots only, excluding fractional root cases):**

| Case            |     p=50 |    p=100 |    p=200 |     p=500 |    p=1000 |
| --------------- | -------: | -------: | -------: | --------: | --------: |
| cbrt(2)         |    5.18× |    5.51× |    7.74× |     21.0× |     43.8× |
| cbrt(10)        |    1.56× |    1.29× |    2.31× |     8.07× |     15.8× |
| 5th_root(2)     |    5.25× |    4.82× |    6.68× |    19.58× |     40.4× |
| 5th_root(100)   |    1.48× |    1.34× |    2.62× |     7.38× |     13.3× |
| 10th_root(2)    |    3.81× |    4.04× |    5.65× |    11.06× |     22.3× |
| 10th_root(1000) |    1.21× |    1.00× |    1.80× |     5.78× |     10.1× |
| cbrt(PI)        |    4.69× |    4.32× |    6.17× |    14.81× |     30.2× |
| cbrt(large_dec) |    5.14× |    4.46× |    7.06× |    21.15× |     30.4× |
| cbrt(0.001)     |    1.86× |    1.75× |    3.85× |    14.15× |     16.1× |
| sqrt(2)         |    8.52× |    4.93× |    6.37× |    13.19× |     22.1× |
| **Average**     | **3.9×** | **3.3×** | **5.0×** | **13.6×** | **25.0×** |

**Key insight:** Newton's method has the same asymptotic complexity per iteration as Python's
approach, but Mojo's tighter inner loops and no interpreter overhead compound across iterations.
At p=1000, cbrt(2) reaches **43.8× Python** — a ~300× improvement from the original 0.14×.

---

## Root Cause Analysis: Where Performance Is Lost

### 1. **Division (asymmetric case): ~~0.11–0.62× Python~~ → 31–79× Python** — Task 1 ✓ FIXED

~~The Burnikel-Ziegler algorithm pads the divisor up to match the dividend's block structure.~~ **Actual root cause:** `BigDecimal.true_divide_general()` computed full quotient coefficients regardless of the needed precision, then discarded excess digits via rounding. For 65536w/32768w at precision=4096, this meant a 65994-word / 32768-word integer division when only a ~458-word quotient was needed. Fix: compute
`extra_words = ceil(P/9) + 2 - diff_n_words` and truncate the dividend when negative.

### 2. **Exp function: ~~0.35–0.65×~~ → 0.60× at p=50, **1.62× at p=2000** — Task 3b ✓

Previous estimate (0.31–0.43×) was based on mismatched precision (Mojo=36, Python=10000).
Multi-precision analysis reveals the gap is **precision-dependent**: at p=50 Mojo is ~0.60×
(improved from 0.48× by Task 3b), at p=500+ Mojo catches up to parity, and at p=2000
**Mojo is 1.1–1.6× Python**. Task 3b (UInt32 division in Taylor series) improved exp by
5–25% at p≤200.

### 3. **Ln function: two radically different regimes (confirmed, Task 3b improved near-1 by 30–100%)**

Multi-precision analysis confirms ln has two fundamentally different performance profiles:

- **Near 1 (|x-1| < 0.1):** After Task 3b, Mojo scales as $O(p^{1.7})$ vs Python's $O(p^{2.8})$.
  Mojo is 0.98× at p=50 (was 0.56×) and **31× at p=2000**. Major win at all precisions above p=200.
- **Far from 1 (powers of 10):** Mojo scales as $O(p^{2.5})$ vs Python's $O(1)$ (cached up to p~1000).
  At p=2000, Python also recomputes (gap narrows to 0.12×).

Task 3c added `get_ln10(precision)` to `MathCache` — used by `log10()`/`log()` to avoid recomputing `ln(10)` from scratch. The `ln()` function itself decomposes into `ln(2)`/`ln(1.25)` for generality (avoids unnecessary overhead for inputs like `ln(2)`).

### 4. **Sqrt (irrational, high precision): 0.55–0.72× Python**

Newton's method for sqrt requires one division per iteration. At precision=5000, each division is on ~556-word numbers. The `BigUInt.sqrt()` converges in ~15–20 iterations. `libmpdec` uses reciprocal sqrt (no division) and NTT multiplication.

### 5. **Addition at very large sizes: 0.76× Python at 3000+ digits**

BigUInt's SIMD vectorized addition (width=4) is fast but scale alignment (`multiply_by_power_of_ten`) for large scale differences creates oversized intermediate arrays.

---

## Literature Review: How Major Decimal Libraries Are Designed

### 1. Python `decimal` → `libmpdec` (Stefan Krah)

**Internal representation:** base-$10^9$ (`uint32_t` limbs), optionally base-$10^{19}$ (`uint64_t`) on 64-bit platforms. Sign + exponent + coefficient (similar to Decimo).

**Key algorithms:**

- **Multiplication:** Schoolbook for small, Karatsuba for medium, **Number Theoretic   Transform (NTT)** for large (>1024 limbs). NTT is in-place, uses three primes   (MPD_PRIMES) enabling Chinese Remainder Theorem reconstruction for exact results. $O(n \log n)$ — this is the primary advantage over Decimo's $O(n^{1.585})$ Karatsuba.
- **Division:** Schoolbook for small, then balanced division via Newton's method for the reciprocal (`1/y`), computed using *NTT-multiplied** Newton iterations: $r_{k+1} = r_k(2 - yr_k)$. This avoids explicit long division entirely for large operands. $O(M(n))$ where $M(n)$ is the cost of multiplication.
- **Sqrt:** Reciprocal square root via Newton ($r_{k+1} = r_k(3 - yr_k^2)/2$) then multiply ($\sqrt{y} = y \cdot r$). Again uses NTT multiplication, never divides.
- **Exp/Ln:** Correct rounding via Ziv's method. Range reduction + Taylor/Maclaurin series, with all multiplications done via NTT at large precision.

**Why it's fast:** NTT gives $O(n \log n)$ multiplication for all sizes above ~1000 digits. Since division and sqrt are reduced to multiplication, all operations benefit.

**Source:** `Modules/_decimal/libmpdec/` in CPython source.

### 2. GMP / MPFR (GNU Multi-Precision)

**Internal representation:** base-$2^{64}$ (or $2^{32}$). Binary, not decimal.

**Key algorithms:**

- **Multiplication:** Schoolbook → Karatsuba → Toom-3 → Toom-4 → Toom-6.5 → Toom-8.5 → **FFT** (Schönhage-Strassen). Seven levels of algorithms, carefully tuned with machine-specific thresholds. The FFT is $O(n \log n \log \log n)$.
- **Division:** $O(M(n))$ via Newton (reciprocal iteration) using fast multiplication.
- **Sqrt:** $O(M(n))$ via reciprocal sqrt Newton.

**Note:** MPFR is a **binary** floating-point library. It provides exact rounding for mathematical functions (exp, ln, sin, etc.) using Ziv's method. Not directly comparable to decimal arithmetic, but the algorithms translate.

**Decimo relevance:** GMP's chain Schoolbook → Karatsuba → Toom-3 → FFT suggests Decimo should implement Toom-3 as the next multiplication tier before
considering NTT.

### 3. mpdecimal (Rust) / `rust_decimal`

**`rust_decimal`:** Fixed 96-bit coefficient (28 significant digits max). Not comparable to arbitrary precision.

**`bigdecimal` (Rust):** base-$10^9$ limbs via `num-bigint`. Uses the same Schoolbook → Karatsuba → Toom-3 progression from `num-bigint`. No NTT. Performance is typically 2–5× slower than Python `decimal` for very large numbers due to lack of NTT.

### 4. Java `BigDecimal` (OpenJDK)

**Internal representation:** Unscaled `BigInteger` + 32-bit scale. Binary internally.

**Key algorithms:**

- `BigInteger` multiplication: Schoolbook → Karatsuba (≥80 ints/2560 bits) → Toom-3 (≥240 ints/7680 bits) → **Parallel Schönhage** (≥10240 ints). Uses fork-join for parallel multiplication.
- Division: Burnikel-Ziegler for large divisions, delegated to Knuth's Algorithm D at the base case.
- Sqrt: Newton's method with binary integer arithmetic.

**Note:** Java `BigDecimal` stores the coefficient in **binary** (as a `BigInteger`), not base-10^9. All base-10 formatting is done at I/O time. This gives Java the full benefit of binary arithmetic speed for internal computation.

### 5. Intel® Decimal Floating-Point Math Library (BID)

**Internal representation:** Binary Integer Decimal (BID) — coefficient is stored as a binary integer, exponent is power-of-10. This is IEEE 754-2008 decimal.

**Key insight:** By storing the coefficient in binary, BID gets fast binary arithmetic for +, -, *, and only pays the decimal conversion cost at I/O boundaries.

### 6. `mpd` — Mike Cowlishaw's General Decimal Arithmetic

The **specification** that Python `decimal` implements. Not a library per se, but defines the semantics. All conforming implementations share the same behavior.

---

## Design Question: Should BigDecimal Use BigUInt (10^9) or BigInt2 (2^32)?

### Current Design: base-$10^9$ (BigUInt)

**Advantages:**

- ✓ **Trivial I/O:** `to_string()` is $O(n)$ — just print each 9-digit word with   zero padding. No expensive base conversion. This matters hugely for financial apps.
- ✓ **Exact scale arithmetic:** Adding trailing zeros or shifting decimal point = insert/remove whole words of zeros. No multiplication by powers of 10 needed.
- ✓ **Natural precision control:** Truncating to $p$ significant digits = keeping $\lceil p/9 \rceil$ words. Rounding operates on decimal digit boundaries.
- ✓ **Simple debugging:** Internal state is human-readable.
- ✓ **No representation error:** "0.1" is stored exactly.

**Disadvantages:**

- ✗ **Wasted bits:** Each 32-bit word stores $\log_2(10^9) ≈ 29.9$ bits of information out of 32 bits — 6.5% waste. Not critical but adds up in memory and cache.
- ✗ **Complex carry/borrow:** Carries are at $10^9$ boundary, requiring UInt64 intermediate products and modulo/division. Binary carry is a single bit shift.
- ✗ **Sqrt/Newton division less efficient:** Per-iteration cost is higher than binary because each BigUInt division involves more complex quotient estimation.
- ✗ **No NTT:** NTT requires prime-modular arithmetic on binary words. Doing NTT in base-$10^9$ is possible (`libmpdec` does it) but the primes must be carefully chosen.

### Alternative: base-$2^{32}$ (BigInt2)

**Advantages:**

- ✓ **Maximum bit density:** Every bit used.
- ✓ **Simpler carry:** Single-bit carry propagation, pipeline-friendly.
- ✓ **Standard algorithms apply directly:** Karatsuba, Toom, NTT all work naturally.
- ✓ **Hardware-aligned:** SIMD, popcount, clz all work directly on limbs.
- ✓ **Better benchmark performance:** BigInt2 is 4.3× Python for addition vs BigUInt's 2.4×; 4× for multiplication vs 1.9×.

**Disadvantages:**

- ✗ **Expensive base conversion:** `to_string()` is $O(n^2)$ naïvely, $O(M(n) \log n)$ with D&C. The BigInt2 analysis shows to_string is only 1.17× Python at 10000 digits vs BigUInt's 34.5×.
- ✗ **Scale arithmetic is expensive:** Multiplying/dividing by $10^k$ requires actual multiplication, not word insertion.
- ✗ **Precision control is hard:** Truncating to $p$ decimal digits requires computing how many binary words correspond to $p$ digits, then base-converting.

### What libmpdec Does (and Why)

**`libmpdec` uses base-$10^9$ on 32-bit platforms and base-$10^{19}$ on 64-bit platforms.** It implements NTT directly on the decimal limbs. The NTT primes are specifically chosen so that the transform operates on numbers in $[0, 10^9)$ or $[0, 10^{19})$.

This is the strongest evidence that **staying with base-$10^9$ is correct** for a decimal library. The key insight is:

> The O(n log n) multiplication advantage of NTT/FFT can be obtained in ANY base.
> But the O(1) I/O advantage of decimal base is unique to decimal.

### What Java BigDecimal Does (and Why)

Java stores the coefficient as a **binary** `BigInteger` internally, paying the conversion cost at construction and `toString()`. This gives fast arithmetic but slow I/O. For computation-heavy uses (scientific computing), this is a good tradeoff.

### Approach for Decimo

**Stay with base-$10^9$, but implement NTT for large multiplication.**

The reasoning:

1. **For a decimal library**, I/O speed matters. Financial and engineering users frequently create decimals from strings and print them. A 34× advantage on `to_string()` at 10000 digits is significant.
2. The current performance gap vs Python is **not because of the base**. It's because `libmpdec` has NTT and Decimo doesn't. Once NTT is implemented (Task 5), the multiplication gap closes.
3. Division and sqrt performance will improve dramatically once they're reformulated to use reciprocal-Newton methods (avoiding explicit division), which requires fast multiplication (NTT) to be worthwhile.
4. For specific operations where binary arithmetic is vastly superior (e.g., integer sqrt at intermediate precision), it's possible to **use BigInt2 as a transit format**: convert to BigInt2, compute, convert back. But this should be the exception, not the default.

### Hybrid Strategy (Selective BigInt2 Transit)

For operations where BigInt2 is clearly faster and the conversion overhead is amortized:

| Operation              | Use BigInt2 transit? | Rationale                                                     |
| ---------------------- | :------------------: | ------------------------------------------------------------- |
| Addition / Subtraction |          No          | BigUInt is already fast enough                                |
| Multiplication         |          No          | NTT in base-10^9 is the right answer                          |
| Division               |          No          | Reciprocal-Newton will use multiplication                     |
| Sqrt                   |      **Maybe**       | If precision-doubling Newton in BigInt2 is much faster        |
| Power                  |      **Maybe**       | Binary exponentiation benefits from BigInt2's shift fast path |
| Exp / Ln / Trig        |          No          | These compose from multiply/divide, which BigUInt handles     |

The transit overhead is roughly `O(n)` for conversion each way, so it's only worth it if the operation itself saves more than `O(n)` in total.

---

## Optimization Roadmap

### Task 1: Fix Asymmetric Division Performance ✓ COMPLETED

**Priority: CRITICAL** — Was 0.11× Python, now **31–79× Python**

**Root cause:** The real bottleneck was NOT in B-Z itself, but in `BigDecimal.true_divide_general()`. When dividend has $d$ more coefficient words than divisor, the function always padded by `ceil(P/9) + 2` extra words WITHOUT subtracting the existing surplus $d$. For 65536w/32768w at precision=4096: the integer division was **65994w / 32768w → ~33226-word quotient**, but only
**~458 words** were needed. The **32768 excess quotient words** were computed and immediately discarded by rounding. The exact-check multiplication (`q × b == a_scaled`) on these oversized operands compounded the waste.

**Fix (2 lines changed in `arithmetics.mojo`):**

```python
# Before (BUG): extra_words = ceil(P/9) + 2  ← ignores positive diff_n_words
# After  (FIX): extra_words = ceil(P/9) + 2 - diff_n_words
```

When `extra_words < 0`, the dividend is truncated via
`floor_divide_by_power_of_billion()` to eliminate unnecessary low-order
words, and the exact-division check is skipped (truncation discards the
information needed for that check; exactness is vanishingly unlikely
for large asymmetric operands anyway).

Also fixed a bug in `true_divide_fast()`: was passing `-extra_words * 9`
(9× too many words) to `floor_divide_by_power_of_billion()`.

**Actual benchmark results (2025-02-21):**

| Size            | Before (ns) | Before | After (ns) |     After | Improvement |
| --------------- | ----------: | -----: | ---------: | --------: | ----------: |
| 65536w / 32768w | 444,571,666 |  0.11× |    614,000 | **76.1×** |    **724×** |
| 65536w / 16384w | 146,761,000 |  0.17× |    299,333 | **77.9×** |    **490×** |
| 65536w / 8192w  |  47,861,000 |  0.26× |    149,000 | **78.8×** |    **321×** |
| 65536w / 4096w  |  15,804,000 |  0.40× |     89,000 | **67.1×** |    **178×** |
| 65536w / 2048w  |   5,099,000 |  0.62× |     42,666 | **72.2×** |    **119×** |
| 65536w / 1024w  |   1,776,333 |  0.45× |     24,000 | **31.2×** |     **74×** |

Balanced cases unchanged (15–24× Python). Overall average speedup: **12.4× Python**.

---

### Task 2: Reciprocal-Newton Division (Avoids Explicit Long Division)

**Priority: HIGH** — Reduces division to multiplication at large sizes

**Algorithm:** Instead of directly computing $q = a / b$:

1. Compute $r \approx 1/b$ using Newton's iteration: $r_{k+1} = r_k(2 - br_k)$
2. Then $q = a \times r$ (one multiplication)
3. Adjust by at most ±1 using a correction step

**Key requirement:** The Newton iteration uses only multiplication (no division), so this is $O(M(n))$ where $M(n)$ is multiplication cost. With NTT (Task 5), this becomes $O(n \log n)$.

**Without NTT (i.e., with Karatsuba only):** $O(n^{1.585})$ — still better than schoolbook division's $O(n^2)$, and avoids the B-Z recursion overhead.

**Expected gain at precision=5000:**

- Current (B-Z + schoolbook base): division ≈ 400µs per 556-word division
- With reciprocal-Newton + Karatsuba: ≈ 150µs (estimated from 2× multiply cost)
- This directly speeds sqrt by ~2× (each Newton iteration has one division)

---

### Task 3: Optimized Exp/Ln (Reduce Iteration Count and Per-Iteration Cost)

**Priority: HIGH** — Currently 0.31–0.43× Python

**Sub-optimizations:**

#### Task 3a: Cache `ln(2)` and `ln(1.25)` — ✓ COMPLETED (2026-02-22)

**Problem:** `ln(2)` and `ln(1.25)` were recomputed on every `ln()` call. At precision=28, this wastes ~5µs per call. Functions like `log()` that call `ln()` twice internally pay this cost doubly.

**Solution:** Implemented `MathCache` struct in `exponential.mojo` — a user-passable cache that stores computed values of `ln(2)` and `ln(1.25)` with their precision levels. Auto-handles precision upgrades (if cached at P1, requesting P2 > P1 recomputes and re-caches).

**Implementation details:**

- Added `struct MathCache` with `get_ln2(precision)` / `get_ln1d25(precision)` methods
- Added overloaded `def ln(x, precision, mut cache: MathCache)` as the primary implementation
- Original `def ln(x, precision)` delegates to cached version with a local cache (100% backward compatible)
- `log()` and `log10()` now create a local `MathCache` so their 2 internal `ln()` calls share cached constants
- Added `BigDecimal.ln(precision, cache)` method overload
- Exported `MathCache` from `decimo` top-level

**Measured speedup (10× ln() calls at same precision, with shared MathCache):**

- precision=100: **~3× faster** (4ms → 1ms)
- precision=500: **~4.5× faster** (103ms → 23ms)

**Limitation (documented compromise):** Mojo doesn't support module-level mutable variables, so each standalone `ln()` call still creates a fresh `MathCache`. The full benefit requires: (a) internal callers like `log()` sharing a local cache, or (b) users manually passing a cache across multiple `ln()` calls. When Mojo adds global variables, a single global `MathCache` will eliminate all redundant computation automatically.

#### Task 3b: Replace Division in Taylor Series with UInt32 Division — ✓ COMPLETED (2026-02-22)

**Problem:** Each Taylor term computed `term = term * x / n`. The division by $n$ (a small integer that fits in UInt32) went through the full BigDecimal division pipeline: constructing `BigDecimal(n, 0, False)`, computing buffer digits, scaling up the coefficient, doing general BigUInt division, then rounding.

**Solution:** Added `true_divide_inexact_by_uint32()` function in `arithmetics.mojo` that wraps `BigUInt.floor_divide_by_uint32()` for O(n) single-word division. Changed the loop variable `n` from `BigUInt`/`BigDecimal` to `UInt32` in three functions:

- `exp_taylor_series()`: `n` (factorial index) changed to UInt32
- `ln_series_expansion()`: `k` (series index) changed to UInt32, even/odd check simplified
- `compute_ln2()`: `k` (series index) changed to UInt32

**Measured improvements (series-dominated near-1 ln cases):**

| Case     |  p=50 | p=100 | p=200 | p=500 | p=1000 |
| -------- | ----: | ----: | ----: | ----: | -----: |
| ln(0.9)  |  +39% |  +98% |  +61% |  +45% |   +21% |
| ln(0.99) |  +75% |  +62% |  +56% |  +29% |   +38% |
| ln(1.01) |  +59% |  +59% |  +56% |  +82% |   +26% |
| ln(1.1)  | +129% |  +61% |  +46% |  +33% |   +31% |

Exp improved 5–25% at p≤200 (e.g., exp(1): 0.48→0.60× at p=50).

#### Task 3c: Cache `ln(10)` in MathCache — ✓ COMPLETED (2026-02-22)

**Problem:** `log10()` and `log()` computed `ln(10)` from scratch on each call (via `ln(BigDecimal("10"))`), requiring two full series evaluations (ln(2) + ln(1.25)).

**Solution:** Added `get_ln10(precision)` method to `MathCache` that computes `ln(10) = 3*ln(2) + ln(1.25)` using the already-cached `ln(2)` and `ln(1.25)` values. Used by `log10()` and `log()` directly.

**Design decision:** The `ln()` function itself decomposes `power_of_10 * ln(10)` into `3*power_of_10*ln(2) + power_of_10*ln(1.25)` rather than calling `get_ln10()`. This avoids computing `ln(1.25)` unnecessarily for inputs like `ln(2)` that only need `ln(2)`. The cached `ln(10)` benefits `log10()`/`log()` where both constants are always needed anyway.

#### Task 3d: Better Range Reduction for Exp ✓ DONE

**Implementation (2026-02-24):**

Replaced the weak halving strategy (divide by $2^k$ until $x < 1$) with **aggressive/optimal halving**: divide by $2^M$ where $M \approx \sqrt{3.322 \cdot p}$, making the reduced argument $x / 2^M \approx 10^{-\sqrt{p}}$ (tiny). The Taylor series then converges in only $\sim M$ terms instead of $\sim 2.5p$ terms, and we need $M$ squarings to recover. Total multiplications: $\sim 2\sqrt{3.322p}$ instead of $\sim 2.5p$.

**Key optimizations:**

- **Exact division by $2^M$**: multiply coefficient by $5^M$ and add $M$ to scale (no rounding error)
- **Adaptive guard digits**: $\lfloor 0.35M \rfloor + 3$ extra digits to compensate for squaring error amplification ($2^M$ amplification of relative error)
- **Input-aware $M$**: for small $|x|$, the natural smallness reduces the optimal $M$, automatically falling back to fewer halvings

**Results (before → after, excluding exp(0) anomaly):**

| Precision | Before | After    | Improvement |
| --------- | ------ | -------- | ----------- |
| p=50      | 0.79×  | 0.87×    | +10%        |
| p=100     | 0.58×  | 0.87×    | +50%        |
| p=200     | 0.74×  | 1.08×    | +46%        |
| p=500     | ~1.1×  | 1.95×    | +77%        |
| p=1000    | ~1.0×  | **2.6×** | +160%       |
| p=2000    | ~1.7×  | **5.3×** | +212%       |

At p≥200, Decimo now consistently beats Python. At p=2000, exp is 5.3× faster than Python's C-based `libmpdec`.

#### Task 3e: Binary Splitting for Exp/Ln Series

**Current:** Sequential Taylor series, one term at a time. Each term depends on the previous term.

**Fix:** Use binary splitting to evaluate $\sum \frac{x^k}{k!}$ as a single rational $p/q$ with exact `BigUInt` arithmetic (same approach used for π Chudnovsky), then do a single final division.

**Benefit:** Reduces $O(p)$ BigDecimal divisions to $O(1)$ final division + $O(p \log p)$ BigUInt multiplications. At large precision, this is dramatically faster.

**Note:** With Task 3d done, the exp Taylor series now only has $\sim\sqrt{p}$ terms, so binary splitting for exp would provide diminishing returns. The main remaining opportunity is for `ln()` where the sequential series still runs $\sim 2.5p$ terms.

> **Attempted: Repeated-sqrt range reduction for ln (REVERTED)**
> Analogous to 3d for exp: take $M$ square roots to bring argument near 1, evaluate Taylor with fewer terms, then multiply result by $2^M$. **Result: catastrophic regression (0.01–0.1× Python).** Root cause: each `sqrt_reciprocal` call involves multiple full-precision Newton iterations (each with 2+ $O(p^2)$ multiplications), far more expensive than the cheap sequential Taylor terms it saves (one multiply + one single-word divide per term). The overhead of $M$ sqrt calls dwarfs the savings from fewer series terms. Sequential Taylor remains optimal for ln until binary splitting (Task 3e) is implemented.

#### Task 3f: atanh Reformulation for Ln Series

**Priority: HIGH** — Estimated **3× speedup** for far-from-1 inputs, easy to implement.

**Problem:** The current `ln_series_expansion()` uses the standard Taylor series $\ln(1+z) = z - z^2/2 + z^3/3 - \ldots$ After range reduction, $z \in [-0.5, 0.5)$, so the series converges at rate $|z| \leq 0.5$, requiring $\sim 3.3p$ terms in the worst case.

**Fix:** Use the identity:
$$\ln(x) = 2 \cdot \text{atanh}\left(\frac{x-1}{x+1}\right) = 2 \sum_{k=0}^{\infty} \frac{u^{2k+1}}{2k+1}, \quad u = \frac{x-1}{x+1}$$

For $x \in [0.5, 1.5)$ (the range after current reduction): $u = (x-1)/(x+1) \in [-1/3, 1/5)$, so $u^2 \in [0, 1/9)$. The series converges at rate $1/9$ instead of $1/2$, needing $\sim 1.05p$ terms instead of $\sim 3.3p$ — a **3× reduction in term count**.

**Also benefits `compute_ln1d25()`:** Currently `ln(1.25)` uses Taylor with $z = 0.25$ (rate $1/4$, $\sim 1.66p$ terms). With atanh, $u = 0.25/2.25 = 1/9$ (rate $1/81$, $\sim 0.52p$ terms) — a **3.2× reduction**.

**Cost:** One extra BigDecimal division to compute $u = (m-1)/(m+1)$, amortized over the $3\times$ fewer iterations. Net win for $|z| > 0.05$.

**Implementation:** Replace `ln_series_expansion(z, precision)` internals with the atanh series. The function signature and range reduction in `ln()` can stay the same — just compute $u$ from $z$ inside the series function.

#### Task 3g: AGM-Based Ln for Large Precision (p > 1000)

**Priority: MEDIUM** — Estimated **10–50× speedup at p=5000**, but complex to implement.

**Problem:** Even with atanh (Task 3f), ln still requires $O(p)$ series terms, each costing $O(M(p))$, for total $O(p \cdot M(p))$. At p=5000+, this is extremely slow.

**Fix:** Use the AGM (Arithmetic-Geometric Mean) method:
$$\ln(x) = \frac{\pi}{2 \cdot \text{AGM}(1, 4/s)} - M \ln 2$$
where $s = x \cdot 2^M$ with $M$ chosen so $s \gg 1$. The AGM converges in $O(\log p)$ iterations, each costing one multiplication + one sqrt. Total: $O(M(p) \log p)$.

**Comparison:**

| Method           | Cost                   | At p=5000                             |
| ---------------- | ---------------------- | ------------------------------------- |
| Taylor (current) | $O(p \cdot M(p))$      | ~16,600 multiplications               |
| atanh (Task 3f)  | $O(p \cdot M(p)) / 3$  | ~5,250 multiplications                |
| AGM              | $O(M(p) \cdot \log p)$ | ~13 iterations (each: 1 mul + 1 sqrt) |

**Prerequisites:**

- Fast `sqrt` (already have `sqrt_reciprocal` with precision doubling — ✓)
- Fast `π` computation (already have `pi()` via Chudnovsky — ✓, but should be cached in `MathCache`)
- Cached `ln(2)` (already in `MathCache` — ✓)

**Note:** This is what MPFR/GMP use for `mpfr_log` at large precision. Best suited as a "large p" fast-path that coexists with the series approach for small p.

---

### Task 4: Optimized Sqrt (Reciprocal Square Root, Avoid Division) ✓ DONE

**Priority: HIGH** — ~~Currently 0.55–0.72× Python at precision=5000~~ ✓ Now **17.9× Python** at precision=5000

**Implementation (2026-02-22):**

Replaced the old BigUInt.sqrt()-based approach (Newton with division, no precision doubling) with a reciprocal square root Newton iteration at the BigDecimal level:

1. Normalize $x$ to $[0.1, 100)$ by shifting scale by even power of 10
2. Float64 initial guess: $r_0 \approx x^{-0.5}$ (~15 digits accuracy)
3. Precision doubling schedule: start at ~20 digits, double each iteration up to
   `working_precision = precision + BUFFER_DIGITS`
4. Newton iterations: $r_{k+1} = r_k(3 - xr_k^2)/2$ (2 multiplications, no division)
5. Final: $\sqrt{x} = x \times r$, adjust scale, round to precision
6. Perfect square detection: strip trailing zeros, verify $\text{candidate}^2 = x$

**Key optimizations:**

- **No division** — each Newton step uses 2 multiplications instead of 1 division
- **Precision doubling** — total work ≈ 2× cost of final iteration (vs k× full cost)
- **BigDecimal-level** — natural precision control, no need to extend coefficient to 2× size
- **BUFFER_DIGITS = 25** — sufficient guard digits for downstream consumers (e.g., arctan)

**Benchmark results (precision=5000, 54 cases, 100 iterations each):**

- Before: avg 0.90× Python (Mojo 10% slower) — old BigUInt.sqrt() with division
- After:  avg **17.9× Python** — reciprocal sqrt with precision doubling
- Range: 5.7–22× for non-trivial cases (49 of 54), extreme outliers up to 68,000×
- **~20× improvement** over baseline, far exceeding the predicted 1.5–3×

The massive gain comes primarily from precision doubling: the old approach ran every Newton iteration at full 5000-digit precision, while the new approach starts at ~20 digits and doubles each step, making total work ≈ 3× the final iteration cost.

**Algorithm (libmpdec-style):**

1. Compute $r \approx 1/\sqrt{x}$ using Newton: $r_{k+1} = r_k(3 - xr_k^2)/2$
   - This uses only multiplication, no division!
2. Then $\sqrt{x} = x \times r$
3. Correct by at most ±1 ulp

**Each Newton iteration cost:** 2 multiplications + 1 subtraction + 1 right-shift (vs current: 1 division + 1 addition + 1 right-shift)

**With Karatsuba (current):**

- Division: $O(n^{1.585})$ via B-Z + Karatsuba
- 2 multiplications: $2 \times O(n^{1.585})$ ← same asymptotic, but ~2× constant factor better because no B-Z recursion overhead

**With NTT (Task 5):**

- Current (with div): $O(n \log n)$ per iteration via NTT division
- Reciprocal sqrt: $2 \times O(n \log n)$ per iteration, no division at all

**Expected gain:** ~1.5× improvement immediately (Karatsuba-based), ~3× with NTT. At precision=5000, this means sqrt goes from 7.6ms to ~2.5ms, beating Python's ~5ms.

**Additional optimization — Precision doubling:**
Newton's method has quadratic convergence. Start with low precision and double each iteration:

- Iteration 1: 8 digits precision (hardware arithmetic)
- Iteration 2: 16 digits
- Iteration 3: 32 digits
- ...
- Iteration k: 5000 digits

Total work ≈ $2 \times$ cost of the final iteration, instead of $k \times$ full cost. This optimization is already used in BigInt2's sqrt — adapt it for BigUInt.

---

### Task 5: Number Theoretic Transform (NTT) for Large Multiplication

**Priority: HIGHEST LONG-TERM** — The single most impactful optimization

**What it is:** NTT is the integer analogue of FFT. It computes multiplication in $O(n \log n)$ by:

1. Transform both operands into NTT domain (modular evaluation at roots of unity)
2. Pointwise multiply in NTT domain
3. Inverse transform back

**For base-$10^9$:** Choose NTT primes $p$ such that:

- $p > 2 \times 10^{18}$ (to avoid overflow of pointwise products)
- $p$ has a large power-of-2 factor (for radix-2 NTT)
- Use 2–3 primes with CRT reconstruction (Chinese Remainder Theorem)

**`libmpdec` primes (reference):**

- $p_1 = 2^{64} - 2^{32} + 1$ (Fermat-style, if fits)
- Three 64-bit primes with large $2^k$ factors for the transform length

**Implementation path:**

1. Implement forward/inverse NTT with a single prime
2. Implement CRT for multi-prime NTT
3. Integrate into `BigUInt.multiply()` with a cutoff (e.g., 512+ words)
4. Verify correctness for all carry patterns

**Expected gain:**

- 10000-digit multiply: Karatsuba $O(n^{1.585})$ → NTT $O(n \log n)$ ≈ 2–3× faster
- 100000-digit multiply: ~10× faster
- All operations that depend on multiplication (division, sqrt, exp, ln) improve transitively

**This is what closes the gap with `libmpdec` for large numbers.**

---

### Task 6: Toom-3 Multiplication (Intermediate Step Before NTT) — ✓ COMPLETED (2026-02-24)

**Status: COMPLETED** — Large multiply improved +14% at 256–1024 words, +28–29% at 2048–4096 words

**Algorithm:** Toom-3 splits each operand into 3 parts instead of Karatsuba's 2. Requires 5 recursive multiplications instead of Karatsuba's 3, but reduces the sub-problem size to $n/3$ instead of $n/2$.

**Complexity:** $O(n^{\log_3 5}) = O(n^{1.465})$, better than Karatsuba's $O(n^{1.585})$.

**Integration:**

- Before: Schoolbook → Karatsuba (cutoff=64 words)
- After: Schoolbook → Karatsuba (cutoff=64) → Toom-3 (cutoff=128) → NTT (future)

**Implementation details:**

- `CUTOFF_TOOM3 = 128` (words). Below 128, Karatsuba is used.
- 5-point evaluation at $p(0), p(1), p(-1), p(2), p(\infty)$
- Signed intermediate handling for $v_{-1}$ via boolean sign tracking (avoids signed BigUInt type)
- Shared `x0+x2` / `y0+y2` subexpressions for $p(1)$/$p(-1)$ and $q(1)$/$q(-1)$
- Horner evaluation for $p(2)$: $(x_2 \cdot 2 + x_1) \cdot 2 + x_0$
- Helper functions: `_exact_divide_by_2_inplace`, `_exact_divide_by_3_inplace`, `_exact_divide_by_6_inplace` (carry-based, no BigUInt division)
- Interpolation optimized: in-place variable reuse ($t_3 \to w_3$, $t_1 \to w_1$), avoids extra BigUInt copies
- Recomposition via parametric `_add_at_offset` helper

**Benchmark results (BigUInt multiply vs Python `int`, 100 iterations):**

| Word Size | Before (ns) | After (ns) | BigUInt Improvement | vs Python Before | vs Python After |
| --------- | ----------: | ---------: | :-----------------: | :--------------: | :-------------: |
| 32w       |       1,310 |      1,380 |    — (Karatsuba)    |      0.53×       |      0.62×      |
| 64w       |       5,560 |      5,610 |    — (Karatsuba)    |      0.45×       |      0.48×      |
| 128w      |      16,660 |     18,540 |    — (Karatsuba)    |      0.45×       |      0.42×      |
| 256w      |      51,950 |     44,670 |      **+14%**       |      0.44×       |    **0.60×**    |
| 512w      |     167,310 |    143,020 |      **+14%**       |      0.47×       |    **0.51×**    |
| 1024w     |     478,830 |    409,020 |      **+15%**       |      0.46×       |    **0.54×**    |
| 2048w     |   1,401,370 |    991,490 |      **+29%**       |      0.49×       |    **0.69×**    |
| 4096w     |   4,207,650 |  3,014,910 |      **+28%**       |      0.48×       |    **0.68×**    |

Note: "vs Python" compares BigUInt to CPython `int` (GMP-backed). Run-to-run Python times vary slightly.

**Analysis:** Toom-3 provides meaningful improvement at ≥256 words, with increasing benefit at larger sizes. The asymptotic $O(n^{1.465})$ vs $O(n^{1.585})$ advantage becomes dominant above ~2048 words. At 512–1024 words, the improvement is modest (~14%) because the recursive Toom-3 subproblems at ~171 words produce ~57-word sub-sub-problems that fall just below the Karatsuba threshold (schoolbook at 57 words), limiting the recursive benefit. The 2048–4096 word range sees the full advantage as deeper recursion levels all land in efficient algorithm tiers.

**Why still slower than Python:** CPython's `int` uses GMP with base-$2^{64}$ limbs (64-bit native multiply), while Decimo uses base-$10^9$ with `UInt32` limbs. Each GMP limb holds ~19.3 digits vs our ~9 digits, so GMP processes ≈2× fewer limbs for the same number. GMP's schoolbook base case also uses hardware `UMULL` (64×64→128 bit), while our base case is `UInt32×UInt32→UInt64` with a `divmod(10^9)` carry step.

---

### Task 7: Nth Root Optimization

#### Task 7a: Newton's Method (Avoid exp(ln(x)/n)) — ✓ COMPLETED (2026-02-22)

**Status: COMPLETED** — Integer roots improved from 0.14–0.49× to **1.2–50× Python**

**Implementation:** Direct Newton's method for `integer_root()` in `exponential.mojo`: $$r_{k+1} = \frac{1}{n}\left((n-1)r_k + \frac{x}{r_k^{n-1}}\right)$$

**Key design decisions:**

- Float64 initial guess via `exponent()` + mantissa normalization
- Precision doubling for quadratic convergence (start at 18 digits)
- Uses `integer_power(r, n-1)` (binary exponentiation) per iteration
- Division by n uses `true_divide_inexact_by_uint32()` for n ≤ UInt32.MAX
- Falls back to `exp(ln(x)/n)` for n > 1000 (binary exponentiation too expensive)
- Early convergence detection for exact results (e.g., cbrt(0.001) = 0.1)
- Coefficient trimming prevents bloated representations from triggering BigUInt division edge cases

**Multi-precision scaling (10 representative cases avg):**

| Precision | Avg Speedup | Notes                              |
| --------- | :---------: | ---------------------------------- |
| p=50      |  **3.9×**   | Newton overhead visible at small p |
| p=100     |  **3.3×**   | Crossover region                   |
| p=200     |  **5.0×**   | Newton's O(M(n)) advantage grows   |
| p=500     |  **13.6×**  | Mojo dominates                     |
| p=1000    |  **25.0×**  | Massive advantage                  |

**Peak speedups at p=1000:** cbrt(2) = 43.8×, 5th_root(2) = 40.4×, cbrt(PI) = 30.2×

#### Task 7b: Reciprocal Newton Iteration (Eliminate Division)

**Priority: MEDIUM** — Estimated **1.5–2× speedup** per Newton iteration for integer roots.

**Problem:** The current Newton iteration $r_{k+1} = ((n-1)r + x/r^{n-1})/n$ requires one full BigDecimal division ($x / r^{n-1}$) per iteration. Division is ~2–3× slower than multiplication for large operands (Burnikel-Ziegler overhead).

**Fix:** Iterate for the reciprocal $r = x^{-1/n}$ instead:
$$r_{k+1} = r_k + \frac{r_k}{n}\left(1 - x \cdot r_k^n\right)$$
Then recover $x^{1/n} = x \cdot r$ with one final multiply. Each iteration costs:

- One `integer_power(r, n)` — same asymptotic as current `integer_power(r, n-1)`
- One multiply $x \cdot r_k^n$ — comparable cost to current division
- One UInt32 divide by $n$ — already cheap
- **No full BigDecimal division**

This is analogous to how Task 4 (sqrt) uses reciprocal sqrt $r_{k+1} = r_k(3 - xr_k^2)/2$ — which achieved **20× improvement**. The same principle applies to general nth roots.

**Caveat:** Convergence requires $r_0$ close enough to $x^{-1/n}$. The Float64 initial guess provides ~15 digits, sufficient with precision doubling. May need a guard condition if $|1 - x \cdot r_k^n|$ overshoots.

**Estimated impact:** Since Task 7a already uses precision doubling, the total work is dominated by the last 1–2 iterations at full precision. Replacing division with multiplication in those iterations should yield ~1.5–2× per iteration, i.e., ~1.5× overall for `integer_root()`.

#### Task 7c: Rational Root Decomposition (Fractional Roots via Integer Root + Power)

**Priority: HIGH** — Estimated **5–10× speedup** for fractional roots, low implementation effort.

**Problem:** Fractional roots like $x^{2/3}$, $x^{0.4}$, $x^{1.5}$ currently fall through to the `exp(ln(x)/n)` path, which is **0.2–0.4× Python** because it chains three expensive operations: `ln()` + division + `exp()`.

**Fix:** Any rational root $x^{a/b}$ (with $a, b \in \mathbb{Z}$, $\gcd(a,b)=1$) can be decomposed as:
$$x^{a/b} = \text{integer\_power}\!\big(\text{integer\_root}(x, b),\; a\big)$$

Both `integer_root()` (Task 7a, 3.9–25× Python) and `integer_power()` (fast binary exponentiation) are already fast paths.

**Examples:**

- $x^{2/3}$ → `integer_power(integer_root(x, 3), 2)` — cbrt + 1 squaring
- $x^{0.4} = x^{2/5}$ → `integer_power(integer_root(x, 5), 2)`
- $x^{1.5} = x^{3/2}$ → `integer_power(sqrt(x), 3)` — sqrt + 2 multiplies
- $x^{0.333...} = x^{1/3}$ → `integer_root(x, 3)` — already handled (exact reciprocal)

**Implementation:** After the existing `is_integer_reciprocal_and_return(n)` check in `root()`, add a rational decomposition step: extract $a/b = 1/n$ in lowest terms (since $n$ is a finite decimal, it's always rational). This is straightforward because BigDecimal already has exact coefficient and scale.

**Scope:** Covers all cases where the root exponent is a terminating decimal. The only remaining `exp(ln(x)/n)` cases would be irrational exponents (rare in practice).

---

### Task 8: In-Place Arithmetic for BigDecimal (Reduce Allocations) — ✓ DONE

**Status: COMPLETED** (2026-02-23)

BigUInt already had 13 inplace functions (add_inplace, subtract_inplace, multiply_inplace_by_uint32, etc.). The gap was at the BigDecimal level: `__iadd__`, `__isub__`, `__imul__` all used `self = allocating_fn(self, other)`.

**Changes made:**

1. **New BigDecimal inplace functions** (in `bigdecimal/arithmetics.mojo`):
   - `multiply_inplace(mut x1, x2)` — computes product, moves result into x1
   - `add_inplace(mut x1, x2)` — uses BigUInt inplace add/subtract with scale alignment
   - `subtract_inplace(mut x1, x2)` — negates x2, delegates to add_inplace

2. **Updated `__iadd__`, `__isub__`, `__imul__`** to call inplace versions

3. **Applied inplace multiply in Taylor series loops:**
   - `exp_taylor_series`: `term = term * add_on` → `multiply_inplace(term, add_on)`
   - `ln_series_expansion`: `term = term * z` → `multiply_inplace(term, z)`
   - `compute_ln2`: `term * x_squared` → `multiply_inplace(term, x_squared)` + cached x²
   - sin/cos/arctan: `term = term * x_squared` → `term *= x_squared` (uses new **imul**)

4. **Quick wins (no new functions needed):**
   - sin/cos: `BigDecimal(n) * BigDecimal(n-1)` → `true_divide_inexact_by_uint32(UInt32(n*(n-1)))`
   - arctan: `term.true_divide(BigDecimal(n))` → `true_divide_inexact_by_uint32(UInt32(n))`
   - compute_ln2: `term * BigDecimal.from_int(Int(k))` → `multiply_inplace_by_uint32(term.coefficient, k)`
   - exp threshold doubling: `coefficient + coefficient` → `multiply_inplace_by_uint32_le_4(coefficient, 2)`
   - sqrt Newton: `divide(x, BigDecimal(2))` → `true_divide_inexact_by_uint32(2, ...)`

**Note:** Self-squaring (`x = x * x`) cannot benefit from inplace because `multiply_inplace` would need a copy of the operand first, negating the allocation savings.

**Benchmark results (macOS arm64 Apple Silicon):**

| Operation | Precision | Before |  After | Improvement |
| --------- | --------: | -----: | -----: | ----------: |
| **exp**   |        50 |  0.68× |  0.82× |    **+21%** |
| **exp**   |       100 |  0.60× |  0.69× |    **+15%** |
| **exp**   |       200 |  0.72× |  0.85× |    **+18%** |
| **ln**    |        50 |  2.37× |  3.00× |    **+27%** |
| **ln**    |       100 |  0.35× |  0.44× |    **+26%** |
| **ln**    |       200 |  0.47× |  0.54× |    **+15%** |
| **ln**    |       500 |  0.99× |  1.04× |     **+5%** |
| root      |        50 |  3.86× |  3.98× |         +3% |
| root      |       100 |  3.04× |  3.28× |         +8% |
| root      |       200 |  5.61× |  5.61× |          0% |
| root      |       500 | 15.86× | 15.86× |          0% |
| root      |      1000 | 28.49× | 28.49× |       ~same |
| sqrt      |      5000 |   398× |   432× |     **+9%** |

Biggest wins: exp/ln Taylor series loops (many iterations, each saving 1–2 allocations). Root/sqrt show modest gains since Newton iteration has fewer multiplies per step.

---

### Task 9: SIMD-Optimized BigUInt Multiplication

**Priority: LOW-MEDIUM** — Constant factor improvement for schoolbook

**Current:** Schoolbook multiplication uses UInt64 products with sequential carry.

**Optimization:** Use SIMD to process 4 limb products in parallel, accumulate in UInt64 SIMD vectors, then normalize carries. On Apple Silicon M-series:

- `SIMD[DType.uint32, 4]` for load/store
- `SIMD[DType.uint64, 4]` for products
- Horizontal add + carry propagation

**Expected gain:** 1.5–2× for schoolbook kernel, which is the base case for both Karatsuba and Toom-3.

---

## Appendix: Comparison with Python `libmpdec` Architecture

| Feature              |      Decimo BigDecimal       |            Python `libmpdec`             |                 Gap                  |
| -------------------- | :--------------------------: | :--------------------------------------: | :----------------------------------: |
| Base                 |       $10^9$ (UInt32)        | $10^9$ (uint32_t) / $10^{19}$ (uint64_t) | Minor — 64-bit limbs give 2× density |
| Small multiply       |          Schoolbook          |                Schoolbook                |                Parity                |
| Medium multiply      |    Karatsuba (cutoff=64w)    |                Karatsuba                 |                Parity                |
| Large multiply       |          Karatsuba           |           **NTT** $O(n\log n)$           |            **Major gap**             |
| Small division       | Specialized (UInt64/128/256) |                Schoolbook                |             Mojo faster              |
| Large balanced div   |       Burnikel-Ziegler       |          **Reciprocal-Newton**           |           Significant gap            |
| Large asymmetric div |   B-Z (broken for m >> n)    |           GMP-style recursive            |           **Critical gap**           |
| Sqrt                 |    Newton (with division)    |    **Reciprocal sqrt** (no division)     |           Significant gap            |
| Exp                  |  Taylor series (sequential)  |      Taylor + **binary splitting**       |              Major gap               |
| Ln                   |  Taylor series (sequential)  |    Taylor + cached `ln(10)` + **NTT**    |  Major gap (3a partially mitigates)  |
| I/O (to/from string) |        $O(n)$ trivial        |              $O(n)$ trivial              |                Parity                |
| Rounding             |    Word-level truncation     |                 Similar                  |           Mojo 100× faster           |

**Bottom line:** The performance gap is not about the base representation. It's about the algorithm tier for large numbers: NTT multiplication, reciprocal-based division and sqrt, and binary splitting for series evaluation. These are all implementable in base-$10^9$.

---

## Before vs After Optimization Summary (All Operations)

> **Date:** 2026-02-22. All benchmarks run on macOS arm64 Apple Silicon (M-series).
> All "After" results use precision-matched benchmarks via TOML config (`precision` field).

### Completed Optimizations

#### Task 1: Fix Asymmetric Division (2026-02-21)

| Case            | BEFORE (ns) | BEFORE vs Python | AFTER (ns) | AFTER vs Python | Improvement |
| --------------- | ----------: | :--------------: | ---------: | :-------------: | ----------: |
| 65536w / 32768w | 444,571,666 |      0.11×       |    614,000 |    **76.1×**    |    **724×** |
| 65536w / 16384w | 146,761,000 |      0.17×       |    299,333 |    **77.9×**    |    **490×** |
| 65536w / 8192w  |  47,861,000 |      0.26×       |    149,000 |    **78.8×**    |    **321×** |
| 65536w / 4096w  |  15,804,000 |      0.40×       |     89,000 |    **67.1×**    |    **178×** |
| 65536w / 2048w  |   5,099,000 |      0.62×       |     42,666 |    **72.2×**    |    **119×** |
| 65536w / 1024w  |   1,776,333 |      0.45×       |     24,000 |    **31.2×**    |     **74×** |

**Root cause:** `true_divide_general()` computed full quotient regardless of needed precision.
**Fix:** `extra_words = ceil(P/9) + 2 - diff_n_words` + truncate dividend when excess.

#### Task 3a: MathCache for ln(2)/ln(1.25) (2026-02-22)

| Scenario                              | BEFORE |  AFTER |  Speedup |
| ------------------------------------- | -----: | -----: | -------: |
| 10× ln() calls, precision=100, cached |   4 ms |   1 ms |   **3×** |
| 10× ln() calls, precision=500, cached | 103 ms |  23 ms | **4.5×** |
| log(x) — 2 internal ln() calls shared |  2× ln | ~1× ln |   **2×** |

**Root cause:** `ln(2)` and `ln(1.25)` recomputed on every `ln()` call.
**Fix:** `MathCache` struct caches computed constants with precision-aware invalidation.

#### Benchmark Infrastructure: Precision Unification (2026-02-22)

| Bench File | BEFORE (Mojo prec / Python prec) | AFTER                    |
| ---------- | :------------------------------: | :----------------------- |
| ln         |       36 / 10000 ← UNFAIR        | **50 / 50** via TOML     |
| exp        |       36 / 10000 ← UNFAIR        | **50 / 50** via TOML     |
| root       | 28 (hardcoded) / 10000 ← UNFAIR  | **50 / 50** via TOML     |
| sqrt       |       5000 / 5000 (was OK)       | **5000 / 5000** via TOML |
| divide     | 4096 (comptime) / 4096 (was OK)  | **50 / 50** via TOML     |

All bench files now:

- Read `precision` from TOML `[config]` section
- Pass it to both Mojo's BigDecimal methods and Python's `getcontext().prec`
- Flag non-zero differences via `diff.is_zero()` with `*** WARNING ***` message

### Updated Performance Scorecard

| Operation       | Before Optimization | After Optimization | Change                                    |
| --------------- | :-----------------: | :----------------: | ----------------------------------------- |
| Addition        |        2.22×        |       2.22×        | (no change)                               |
| Subtraction     |        9.79×        |       9.79×        | (no change)                               |
| Multiplication  |        3.44×        |       3.44×        | (no change)                               |
| Division (sym)  |       15–28×        |       15–28×       | (no change)                               |
| Division (asym) |     0.11–0.62×      |     **31–79×**     | ↑ **Task 1** — 74–724× raw improvement    |
| Sqrt (irrat)    |     0.55–0.72×      |     0.55–0.72×     | (no change, sqrt bench was already fair)  |
| **Exp**         |       ~0.34×*       |   **0.69–0.85×**   | ↑ Task 3b + **Task 8** inplace ops        |
| **Ln (mixed)**  |      (no data)      |   **0.44–3.00×**   | ↑ Task 3a–3c + **Task 8** inplace ops     |
| **Root (nth)**  |     0.18–0.33×*     |   **3.3–28.5×**    | ↑ **Task 7a** Newton + **Task 8** inplace |
| Root (√)        |        27.1×        |      **432×**      | ↑ Task 1 + **Task 8** divide-by-2 uint32  |
| Rounding        |       105.8×        |       105.8×       | (no change)                               |

\* Previous values were measured with mismatched precision (Mojo 28–36 digits vs Python 10000 digits) and were not valid benchmarks. The "Before" column shows the originally reported numbers for historical reference.

### What Changed and Why

1. **Division asymmetric: 0.11× → 76×** — Algorithmic fix in `true_divide_general()`. The biggest single improvement. Two-line fix eliminated 99.8% of wasted computation.

2. **Exp: 0.34× → 0.55×** — Not an algorithmic improvement; the 0.34× was an artifact of Python computing 278× more digits. The true gap is ~1.8× (Python faster), much more tractable for future optimization (Task 3b–3d).

3. **Ln: first real data** — Reveals two regimes. Near 1: nearly competitive (0.97×). Far from 1: Python's cached `ln(10)` is game-changing. `MathCache` (Task 3a) helps with repeated calls but can't eliminate first-call cost without global variables.

4. **Root: 0.18× → 0.14× (corrected)** — The previous 0.18× was actually optimistic because Python was doing 357× more precision. With fair comparison, nth root is 0.14–0.49× Python. ~~Task 7 (direct Newton) is the fix.~~ ✓ FIXED (Task 7a): now 1.2–50× Python for integer roots. Fractional roots still 0.2–0.4× (see Task 7c).

5. **Task 8 (in-place operations): +15–27% exp/ln, +9% sqrt** — Added BigDecimal-level `multiply_inplace`, `add_inplace`, `subtract_inplace`; applied in all Taylor series loops. Also replaced full BigDecimal divisions with `true_divide_inexact_by_uint32` in sin/cos/arctan/sqrt/compute_ln2. Biggest wins at low-to-medium precision where allocation overhead is a larger fraction of total cost.

6. **Task 4 (reciprocal sqrt + precision doubling): 0.90× → 17.9× (~20× improvement)** — Replaced BigUInt.sqrt()-based Newton (with division, no precision doubling) with reciprocal sqrt Newton at BigDecimal level. Two key wins: (a) no division (2 muls vs 1 div per iteration), (b) precision doubling (total work ≈ 3× final iteration cost vs k× full cost). The improvement far exceeded the predicted 1.5–3× because the old approach lacked precision doubling entirely.

### Remaining Targets

| Priority | Task    |                 Current                  |     Target      | Approach                                            |
| -------- | ------- | :--------------------------------------: | :-------------: | --------------------------------------------------- |
| ✓ DONE   | Task 2  | ~~0.78×~~ **avg 24.6×, up to 915× div**  |     ✓ DONE      | Truncation optimization for oversized operands      |
| ✓ DONE   | Task 4  |  ~~0.55–0.72×~~ **3.53× geo-mean sqrt**  |     ✓ DONE      | CPython exact algorithm + reciprocal sqrt hybrid    |
| ✓ DONE   | Task 7a | ~~0.14–0.49×~~ **3.9–25× int nth root**  |     ✓ DONE      | Newton for nth root (was exp(ln(x)/n))              |
| ✓ DONE   | Task 8  |       **+15–27% exp/ln, +9% sqrt**       |     ✓ DONE      | In-place BigDecimal operations + uint32 quick paths |
| ✓ DONE   | Task 6  | ✓ **+14–29% over Karatsuba (256–4096w)** |   ✓ COMPLETED   | Toom-3 multiplication                               |
| **HIGH** | Task 3f |    Ln far-from-1: 0.001–0.18× Python     | 3× fewer terms  | atanh reformulation for ln series                   |
| **HIGH** | Task 7c |       Frac roots: 0.2–0.4× Python        |  5–10× speedup  | Rational root decomposition (a/b → root+power)      |
| MEDIUM   | Task 7b |          Integer roots: 3.9–25×          | 1.5–2× further  | Reciprocal Newton (eliminate division)              |
| MEDIUM   | Task 3e |          Ln: O(p) series terms           | O(p log p) muls | Binary splitting for ln Taylor series               |
| MEDIUM   | Task 3g |         Ln at p>1000: 0.08–0.28×         | 10–50× at p>1k  | AGM-based ln (O(M(p) log p))                        |
| LOW      | Task 5  |                  varies                  |   2–10× gain    | NTT multiplication                                  |
| LOW      | Task 9  |                    —                     |     1.5–2×      | SIMD schoolbook multiply base                       |
