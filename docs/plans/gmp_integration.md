# GMP Integration Plan for Decimo

> **Date**: 2026-04-02  
> **Target**: decimo >=0.9.0  
> **Mojo Version**: >=0.26.2  
> **GMP Version**: 6.3.0 (tested on macOS ARM64, Apple Silicon)
>
> 子曰工欲善其事必先利其器  
> The mechanic, who wishes to do his work well, must first sharpen his tools -- Confucius

## 1. Executive Summary

### Verdict: FEASIBLE ✓

GMP integration into Decimo is technically feasible — I've proven it with a working prototype. A C wrapper (`gmp_wrapper.c`) bridges Mojo's FFI layer to GMP, and all core arithmetic operations pass.

### Key Findings

| Aspect                   | Status      | Notes                                                                           |
| ------------------------ | ----------- | ------------------------------------------------------------------------------- |
| Mojo → C FFI             | ✓ Works     | Via `external_call` with link-time binding                                      |
| GMP arithmetic ops       | ✓ All work  | Add, sub, mul, div, mod, pow, sqrt, gcd, bitwise                                |
| Build pipeline           | ✓ Works     | `mojo build` with `-Xlinker` flags                                              |
| Runtime detection        | ! Partial   | Build-time detection feasible; true runtime dlopen not available in Mojo 0.26.2 |
| BigInt ↔ GMP conversion  | ✓ Efficient | Both use base-2^32, near-trivial O(n) conversion                                |
| BigUInt/BigDecimal ↔ GMP | ! Costly    | Requires base-10^9 → binary conversion (O(n²) naïve, O(n·log²n) D&C)            |
| `mojo run` (JIT)         | ✗ Broken    | `-Xlinker` flags ignored in JIT mode; only `mojo build` works                   |
| Cross-platform           | ! Varies    | macOS/Linux straightforward; Windows needs MPIR or MinGW GMP                    |

### Recommendation

Two-type architecture:

1. **BigFloat** — a new first-class MPFR-backed binary float type (like mpmath's `mpf`
   but faster). Requires MPFR. Every operation is a single MPFR call. This is the fast
   path for scientific computing at high precision.
2. **BigDecimal** — keeps its native base-10⁹ implementation. Gains an optional
   `gmp=True` parameter for one-off acceleration of expensive operations (sqrt, exp, ln,
   etc.) without changing types. No MPFR dependency.
3. **BigInt** — GMP backend deferred to Phase 3. Cheap O(n) word conversion, 7–18×
   speedup measured.

BigFloat and BigDecimal coexist because they solve different problems: BigFloat is fast
binary arithmetic (like mpmath); BigDecimal is exact decimal arithmetic (like Python
`decimal`). Both in one library, user picks the right tool.

## 2. Technical Feasibility Assessment

### 2.1 What Was Tested

A complete prototype was built in `temp/gmp/`:

1. **C wrapper** (`gmp_wrapper.c`): Handle-based API wrapping GMP's `mpz_t` operations
2. **Shared library** (`libgmp_wrapper.dylib`): Compiled, linked against GMP
3. **Mojo FFI test** (`test_gmp_ffi.mojo`): 18 tests covering all operation categories
4. **Mojo benchmark** (`bench_gmp_vs_decimo.mojo`): Performance comparison across digit sizes

### 2.2 Prototype Results

| Test Category              | Result                                |
| -------------------------- | ------------------------------------- |
| Initialization & cleanup   | ✓ Pass                                |
| String import/export       | ✓ Pass                                |
| Addition, subtraction      | ✓ Pass                                |
| Multiplication             | ✓ Pass                                |
| Floor/truncate division    | ✓ Pass                                |
| Modulo                     | ✓ Pass                                |
| Power, modular power       | ✓ Pass                                |
| Square root                | ✓ Pass                                |
| GCD                        | ✓ Pass                                |
| Negation, absolute value   | ✓ Pass                                |
| Comparison, sign           | ✓ Pass                                |
| Bitwise AND, OR, XOR       | ✓ Pass                                |
| Left/right shift           | ✓ Pass                                |
| Availability/version check | ✓ Pass                                |
| UInt32 word import/export  | ! Partial (parameter alignment issue) |

### 2.3 Why C Wrapper Is Required

Direct FFI to GMP doesn't work in Mojo 0.26.2 because:

1. **No `DLHandle`**: Mojo 0.26.2 does not expose `DLHandle` for runtime dynamic library loading. Only `external_call` (compile-time/link-time binding) is available.
2. **`mpz_t` is a struct**: GMP's `mpz_t` is `__mpz_struct[1]` (a 1-element array used as a pass-by-reference trick). Mojo cannot directly represent or pass this.
3. **Pointer origin tracking**: `UnsafePointer` in Mojo 0.26.2 has strict origin tracking that prevents constructing pointers from raw integer addresses in non-`fn` contexts.
4. **GMP macros**: Many GMP operations (e.g., `mpz_init`, `mpz_clear`) are preprocessor macros, not true function symbols.

The C wrapper solves all of this by exposing a flat, handle-based C API where Mojo
passes and receives only primitive types (`Int32`, `Int`).

## 3. Mojo FFI Capabilities and Constraints

### 3.1 Available FFI Mechanism

```mojo
from std.ffi import external_call

# Example: calling a C function
var result = external_call["gmpw_add", NoneType, Int32, Int32, Int32](a, b, c)
```

- `external_call` resolves symbols at **link time** (not runtime)
- Function signature must be known at compile time
- Supports: `Int`, `Int32`, `UInt32`, `Float64`, `NoneType`, pointer-as-`Int`
- Does **not** support: variadic args, struct-by-value, function pointers

### 3.2 Constraints Discovered

| Constraint                       | Impact                                            | Workaround                                              |
| -------------------------------- | ------------------------------------------------- | ------------------------------------------------------- |
| No `DLHandle` (runtime dlopen)   | Cannot conditionally load GMP at runtime          | Compile-time feature flag or separate build targets     |
| `-Xlinker` ignored in `mojo run` | JIT mode cannot link external libs                | Must use `mojo build` + execute binary                  |
| `UnsafePointer` origin tracking  | Cannot construct pointers from addresses in `def` | Pass pointers as `Int` type                             |
| No struct-by-value in FFI        | Cannot pass/return C structs                      | Handle-based API (C wrapper manages structs internally) |
| `UnsafePointer.alloc()` removed  | Cannot allocate raw memory directly               | Use `List[T](length=n, fill=v)` + `.unsafe_ptr()`       |
| Same-pointer aliasing forbidden  | Cannot pass same buffer twice to `external_call`  | Use separate buffer variables                           |

### 3.3 Future Mojo Improvements That Would Help

- **`DLHandle` support**: Would enable true runtime detection and conditional loading
- **Stable `UnsafePointer` API**: Would simplify pointer handling
- **Global variables**: Would allow module-level GMP backend state
- **Conditional compilation (`@static_if`)**: Would enable clean feature toggling

## 4. Architecture Analysis

### 4.1 Current Decimo Architecture

```txt
Decimo Types                Internal Representation
─────────────               ───────────────────────
BigInt (BInt)        →      List[UInt32] in base-2^32 + Bool sign
BigUInt              →      List[UInt32] in base-10^9 (unsigned)
BigDecimal (Decimal) →      BigUInt coefficient + Int scale + Bool sign
Dec128               →      3×UInt32 coefficient + UInt32 flags (fixed 128-bit)
```

### 4.2 GMP Architecture

```txt
GMP Types                   Internal Representation
─────────────               ───────────────────────
mpz_t                →      mp_limb_t* (base-2^64 on ARM64) + int size + int alloc
mpq_t                →      mpz_t numerator + mpz_t denominator
mpf_t                →      Binary floating-point with configurable precision
```

### 4.3 Type Mapping

| Decimo Type          | GMP Equivalent                  | Conversion Cost                                       | Integration Priority |
| -------------------- | ------------------------------- | ----------------------------------------------------- | -------------------- |
| **BigFloat** *(new)* | `mpfr_t`                        | **None** — direct MPFR handle                         | **Phase 1** (HIGH)   |
| **BigInt**           | `mpz_t`                         | **Low** — same binary base (2^32 → 2^64 word packing) | **Phase 3** (MEDIUM) |
| **BigUInt**          | `mpz_t` (unsigned subset)       | **High** — base-10^9 → binary conversion              | Skip                 |
| **BigDecimal**       | via BigFloat (`gmp=True` sugar) | **High** — string conversion, but single round-trip   | **Phase 2** (HIGH)   |
| **Dec128**           | Not applicable                  | N/A — fixed precision, already fast                   | Skip                 |

### 4.4 Where GMP Helps

GMP's advantages over my native implementation:

1. **Highly optimized assembly**: GMP includes hand-tuned ARM64 assembly for core operations
2. **Mature algorithm suite**: Decades of optimization (Schönhage-Strassen for huge multiplications, sub-quadratic GCD, etc.)
3. **Large-number regime**: GMP's algorithmic cutoffs are well-tuned for every platform
4. **Additional algorithms**: FFT-based multiplication, extended GCD, primality testing, etc.

Where GMP does **not** help:

1. **Small numbers** (<50 digits): FFI overhead dominates
2. **Dec128**: Fixed 128-bit operations are already optimal with native code
3. **Base-10 operations**: GMP works in binary; base-10 output requires conversion
4. **Decimal arithmetic**: GMP has no native decimal type; scale management would remain in Mojo

### 4.5 MPFR Memory Layout & Data Flow

How data flows from Mojo `BigFloat` → C wrapper → MPFR library.

#### 4.5.1 MPFR's `mpfr_t` Internal Structure (32 bytes on ARM64/x86_64)

```txt
mpfr_t (typedef: __mpfr_struct[1])
┌─────────────────────────────────────────────────────────────────┐
│ offset  field        type           meaning                     │
├─────────────────────────────────────────────────────────────────┤
│  0      _mpfr_prec   mpfr_prec_t    precision in bits (≥2)      │
│         (8 bytes)     (long)                                    │
├─────────────────────────────────────────────────────────────────┤
│  8      _mpfr_sign   mpfr_sign_t    +1 or −1                    │
│         (4 bytes)     (int)                                     │
├─────────────────────────────────────────────────────────────────┤
│ 12      (padding)    4 bytes        align _mpfr_exp to 8-byte   │
│                                     boundary (long requires it) │
├─────────────────────────────────────────────────────────────────┤
│ 16      _mpfr_exp    mpfr_exp_t     binary exponent             │
│         (8 bytes)     (long)         (value = man × 2^exp)      │
├─────────────────────────────────────────────────────────────────┤
│ 24      _mpfr_d      mp_limb_t*     → heap-allocated limb array │
│         (8 bytes)     (uint64_t*)    (mantissa bits, MSB first) │
└─────────────────────────────────────────────────────────────────┘
         Total: 32 bytes (struct) + heap limbs
```

**Limb Array Detail**

The `_mpfr_d` pointer points to a heap-allocated array of 64-bit "limbs":

```txt
_mpfr_d ────────┐
                ▼
               ┌────────────┬────────────┬────────┬────────────┐
               │  limb[0]   │  limb[1]   │  ...   │  limb[n-1] │
               │ (64 bits)  │ (64 bits)  │        │ (64 bits)  │
               └────────────┴────────────┴────────┴────────────┘
                MSB of mantissa ───────────────────────► LSB
                n = ceil(precision / 64)
                e.g. 200-bit precision → 4 limbs → 32 bytes of mantissa
```

**Value Representation**

```txt
value = sign × mantissa × 2^(exponent − precision)

Example: π at 200-bit precision
  sign  = +1
  prec  = 200
  exp   = 2           (so π ≈ mantissa × 2^(2−200))
  limbs = [0xC90FDAA2..., 0x2168C234..., 0xC4C6628B..., 0x80DC1CD1...]
```

#### 4.5.2 C Wrapper Handle Pool (`gmp_wrapper.c`)

The C wrapper pre-allocates a flat array of 4096 "slots", each 64 bytes
(over-allocated from MPFR's 32-byte struct for ABI safety).

```txt
handle_pool[4096][64]                        handle_in_use[4096]
┌──────────────────────────────────────────┐ ┌───────────────────┐
│ slot[0]  (64 bytes, 16-byte aligned)     │ │ [0] = 1 (in use)  │
│ ┌──────┬──────┬──────┬──────┬──────────┐ │ │                   │
│ │ prec │ sign │ exp  │ *d ──┼──→ heap  │ │ │                   │
│ │  8B  │  4B  │  8B  │  8B  │ (unused) │ │ │                   │
│ └──────┴──────┴──────┴──────┴──────────┘ │ │                   │
├──────────────────────────────────────────┤ ├───────────────────┤
│ slot[1]  (64 bytes)                      │ │ [1] = 1 (in use)  │
│ ┌──────┬──────┬──────┬──────┬──────────┐ │ │                   │
│ │ prec │ sign │ exp  │ *d ──┼──→ heap  │ │ │                   │
│ └──────┴──────┴──────┴──────┴──────────┘ │ │                   │
├──────────────────────────────────────────┤ ├───────────────────┤
│ slot[2]  (64 bytes)                      │ │ [2] = 0 (free)    │
│ ┌──────────────────────────────────────┐ │ │                   │
│ │ (uninitialized / cleared)            │ │ │                   │
│ └──────────────────────────────────────┘ │ │                   │
├──────────────────────────────────────────┤ ├───────────────────┤
│                   ...                    │ │       ...         │
├──────────────────────────────────────────┤ ├───────────────────┤
│ slot[4095]                               │ │ [4095] = 0 (free) │
└──────────────────────────────────────────┘ └───────────────────┘

Memory:          _Alignas(16) char[4096][64]      int[4096]
                 = 256 KB (static, pre-allocated)
```

#### 4.5.3 End-to-End Data Flows

**Construction: `BigFloat("3.14", precision=100)`**

```txt
Mojo (bigfloat.mojo)          C wrapper (gmp_wrapper.c)         MPFR library
─────────────────────          ─────────────────────────         ────────────

① _dps_to_bits(100)
   = 100 × 4 + 64
   = 464 bits

② mpfrw_init(464) ─────────→  ③ Find free slot (say i=0)
   via external_call              handle_in_use[0] = 1
                                  p_init2(&slot[0], 464)  ──→ ④ mpfr_init2:
                                                                 slot[0].prec = 464
                                                                 slot[0].sign = +1
                                                                 slot[0].exp  = 0
                                                                 slot[0].*d   = malloc(8 limbs)
                               ← return handle = 0

⑤ mpfrw_set_str(0,            ⑥ Copy "3.14" to buf\0
   "3.14", 4) ─────────────→     p_set_str(&slot[0],     ──→ ⑦ mpfr_set_str:
   via external_call              buf, 10, RNDN)                 parse "3.14"
                                                                 set mantissa limbs
                                                                 set exponent = 2
                               ← return 0 (success)

self.handle = 0
self.precision = 100
```

**Arithmetic: `a + b`  (both are BigFloat)**

```txt
Mojo                           C wrapper                        MPFR
────                           ─────────                        ────

① mpfrw_init(464) ──────────→ alloc slot[2]
   result handle = 2           handle_in_use[2] = 1           → mpfr_init2

② mpfrw_add(2, 0, 1) ──────→ ③ CHECK_HANDLES_3(2, 0, 1)
   via external_call              p_add(&slot[2],             → ④ mpfr_add:
                                        &slot[0],                r.limbs = a.limbs + b.limbs
                                        &slot[1],                r.exp adjusted
                                        RNDN)                    rounding applied
                               ← (void)

⑤ return BigFloat(
     _handle=2,
     _precision=max(a,b))
```

**String Export: `bf.to_string(30)`**

```txt
Mojo                           C wrapper                         MPFR
────                           ─────────                         ────

① mpfrw_get_str(0, 30) ────→  ② buf = malloc(94)
   returns Int (raw address)      p_snprintf(buf, 94,        → ③ mpfr_snprintf:
                                    "%.*Rg", 30,                   format mantissa limbs
                                    &slot[0])                      as decimal string
                                                                   "3.14..."
                               ← return buf (raw address)

④ _read_c_string(addr)
   strlen(addr) → length
   memcpy into List[Byte]
   → String

⑤ mpfrw_free_str(addr) ────→  ⑥ free(buf)
```

**Destruction: `__del__`**

```txt
Mojo                           C wrapper                        MPFR
────                           ─────────                        ────

① mpfrw_clear(0) ──────────→  ② p_clear(&slot[0])          → ③ mpfr_clear:
   via external_call              handle_in_use[0] = 0            free(slot[0].*d)
                                                                  (limb array freed)
                               slot[0] bytes now stale
                               but slot is reusable
```

#### 4.5.4 BigFloat ↔ BigDecimal Conversion

The two directions use different strategies:

**BigFloat → BigDecimal** (`to_bigdecimal`): Uses `mpfr_get_str` to export raw
decimal digits and a base-10 exponent directly, then constructs the BigDecimal
via a single `memcpy` — no intermediate `String` or full `parse_numeric_string`.

**BigDecimal → BigFloat**: Uses `BigDecimal.to_string()` → `mpfr_set_str` (the
standard string round-trip, since BigDecimal already stores base-10 digits).

```txt
┌─────────────┐  mpfr_get_str (raw digits + exp)   ┌──────────────┐
│  BigFloat   │ ─────────────────────────────────→ │ BigDecimal   │
│  (MPFR      │  direct construction (memcpy)      │ (coefficient │
│   binary)   │                                    │  + scale     │
│             │ ←───────────────────────────────── │  + sign)     │
│             │  .to_string() → mpfr_set_str       │              │
└─────────────┘                                    └──────────────┘
```

Why asymmetric? The `to_bigdecimal` path avoids the overhead of formatting a
full decimal string and then re-parsing it. `mpfr_get_str` returns exactly the
significant digits needed, and the exponent is a separate integer, so BigDecimal
can be assembled directly. The reverse direction still goes through a string
because `mpfr_set_str` handles all the base-2 conversion internally.

#### 4.5.5 Library Loading: dlopen Chain

```txt
                      mpfrw_available()
                            │
                            ▼
               ┌─── mpfrw_load() ────┐
               │ mpfr_load_attempted │
               │     == 0 ?          │
               └────────┬────────────┘
                        │ yes
                        ▼
              ┌── check DECIMO_NOGMP ──┐
              │ env var set?           │
              └────────┬───────────────┘
                       │ no
                       ▼
           ┌── dlopen("libmpfr.dylib") ───────────────────────┐
           │   try paths in order:                            │
           │   1. libmpfr.dylib (rpath)                       │
           │   2. /opt/homebrew/lib/libmpfr.dylib (macOS ARM) │
           │   3. /usr/local/lib/libmpfr.dylib (macOS x86)    │
           │   4. libmpfr.so (Linux rpath)                    │
           │   5. /usr/lib/.../libmpfr.so (Debian)            │
           └────────────────┬─────────────────────────────────┘
                            │ success
                            ▼
           ┌── dlsym for each function pointer ──┐
           │ p_init2    = dlsym("mpfr_init2")    │
           │ p_clear    = dlsym("mpfr_clear")    │
           │ p_set_str  = dlsym("mpfr_set_str")  │
           │ p_add      = dlsym("mpfr_add")      │
           │ p_sqrt     = dlsym("mpfr_sqrt")     │
           │ p_snprintf = dlsym("mpfr_snprintf") │
           │ ... (21 function pointers total)    │
           └─────────────────────────────────────┘
                            │
                            ▼
           ┌── verify critical pointers ──┐
           │ if any of init2, clear,      │
           │ set_str, get_str, add, sub,  │
           │ mul, div, neg, abs, cmp      │
           │ is NULL → fail, dlclose      │
           └──────────────┬───────────────┘
                          │ all OK
                          ▼
                   return 1 (available)
```

The result is cached: `mpfr_load_attempted = 1`. Subsequent calls skip all
of the above and return immediately.

## 5. Performance Comparison: GMP vs Decimo

All benchmarks run side-by-side in a single binary (`bench_gmp_vs_decimo.mojo`), compiled
with `mojo build -O3` (release mode, assertions off). Each data point is the **median of
7 runs**. Platform: Apple M2, macOS, GMP 6.3.0, Mojo 0.26.2.

### 5.1 BigInt (base-2³²) vs GMP `mpz`

These compare Decimo's `BigInt` (Karatsuba multiply, Burnikel-Ziegler divide) against
GMP's `mpz_*` functions. Both operate in binary representation; no base conversion needed.

#### Multiplication (n-digit × n-digit)

| Digits | GMP      | Decimo    | Decimo / GMP |
| ------ | -------- | --------- | ------------ |
| 50     | 12 ns    | 106 ns    | 8.8×         |
| 100    | 21 ns    | 156 ns    | 7.4×         |
| 500    | 223 ns   | 2.20 µs   | 9.9×         |
| 1,000  | 733 ns   | 7.45 µs   | 10.2×        |
| 5,000  | 10.40 µs | 127.44 µs | 12.3×        |
| 10,000 | 24.45 µs | 380.81 µs | 15.6×        |

GMP is **8–16× faster** for multiplication, with the gap widening at larger sizes due to
GMP's hand-tuned assembly (Karatsuba / Toom-3 / FFT) versus Decimo's pure-Mojo Karatsuba.

#### Addition (n-digit + n-digit)

| Digits | GMP    | Decimo  | Decimo / GMP |
| ------ | ------ | ------- | ------------ |
| 50     | 5 ns   | 51 ns   | 10.2×        |
| 100    | 5 ns   | 56 ns   | 11.2×        |
| 500    | 8 ns   | 111 ns  | 13.9×        |
| 1,000  | 12 ns  | 181 ns  | 15.1×        |
| 5,000  | 69 ns  | 667 ns  | 9.7×         |
| 10,000 | 150 ns | 1.24 µs | 8.2×         |

GMP is **8–15× faster** for addition. GMP uses assembly-optimized `mpn_add_n`; Decimo
uses SIMD vectorization but cannot match hand-written assembly.

#### Floor Division (n-digit / (n/2)-digit)

| Digits | GMP      | Decimo    | Decimo / GMP |
| ------ | -------- | --------- | ------------ |
| 100    | 44 ns    | 510 ns    | 11.6×        |
| 500    | 218 ns   | 1.76 µs   | 8.1×         |
| 1,000  | 593 ns   | 5.47 µs   | 9.2×         |
| 5,000  | 7.16 µs  | 81.73 µs  | 11.4×        |
| 10,000 | 22.62 µs | 254.62 µs | 11.3×        |

GMP is **8–12× faster** for division. Both use sub-quadratic algorithms (Burnikel-Ziegler),
but GMP's multiply subroutine is faster, and its lower-level code is more optimized.

#### Integer Square Root

| Digits | GMP      | Decimo    | Decimo / GMP |
| ------ | -------- | --------- | ------------ |
| 50     | 44 ns    | 205 ns    | 4.7×         |
| 100    | 81 ns    | 709 ns    | 8.8×         |
| 500    | 273 ns   | 3.55 µs   | 13.0×        |
| 1,000  | 569 ns   | 8.41 µs   | 14.8×        |
| 5,000  | 5.90 µs  | 104.67 µs | 17.7×        |
| 10,000 | 17.52 µs | 322.26 µs | 18.4×        |

GMP is **5–18× faster** for sqrt. Both use Newton's method, but GMP's inner multiply/divide
is much faster, and the gap accumulates over Newton iterations.

#### GCD

| Digits | GMP     | Decimo  | Decimo / GMP |
| ------ | ------- | ------- | ------------ |
| 50     | 53 ns   | 216 ns  | 4.1×         |
| 100    | 45 ns   | 247 ns  | 5.5×         |
| 500    | 93 ns   | 543 ns  | 5.8×         |
| 1,000  | 142 ns  | 955 ns  | 6.7×         |
| 5,000  | 646 ns  | 4.21 µs | 6.5×         |
| 10,000 | 1.95 µs | 8.02 µs | 4.1×         |

GMP is **4–7× faster** for GCD. GMP uses a sub-quadratic half-GCD algorithm (Lehmer/​Schönhage);
Decimo currently uses the Euclidean algorithm. This is the smallest gap of all operations.

### 5.2 BigDecimal (base-10⁹) vs GMP Integer Equivalents

GMP has no native decimal type. To compare fairly, I benchmark GMP performing the
**equivalent integer computation** that a GMP-backed BigDecimal would perform:

- **Multiply**: GMP integer multiply on same-digit-count coefficients
- **Sqrt(2) at precision P**: GMP `isqrt(2 × 10^(2P))` vs Decimo `BigDecimal.sqrt(precision=P)`
- **Division (1/3) at precision P**: GMP `(1 × 10^P) / 3` vs Decimo `BigDecimal.true_divide(…, precision=P)`

These ratios represent the **best-case speedup** from a GMP backend, before
accounting for the base-10⁹ ↔ binary conversion overhead.

#### BigDecimal Multiplication (n sig-digits × n sig-digits)

| Digits | GMP (int mul) | Decimo (BigDecimal) | Decimo / GMP |
| ------ | ------------- | ------------------- | ------------ |
| 28     | 9 ns          | 137 ns              | 15.2×        |
| 100    | 21 ns         | 327 ns              | 15.6×        |
| 500    | 226 ns        | 7.92 µs             | 35.1×        |
| 1,000  | 725 ns        | 25.75 µs            | 35.5×        |
| 5,000  | 10.72 µs      | 309.71 µs           | 28.9×        |
| 10,000 | 24.63 µs      | 923.19 µs           | 37.5×        |

BigDecimal multiply is **15–38× slower** than GMP integer multiply. This large gap comes
from two factors: (1) BigDecimal uses base-10⁹ `BigUInt` internally (not the faster base-2³²
`BigInt`), and (2) GMP's assembly is faster than either Decimo representation.

#### BigDecimal Sqrt(2) at Various Precisions

| Precision | GMP (isqrt) | Decimo (BigDecimal.sqrt) | Decimo / GMP |
| --------- | ----------- | ------------------------ | ------------ |
| 28        | 32 ns       | 3.48 µs                  | 109×         |
| 100       | 112 ns      | 9.58 µs                  | 86×          |
| 500       | 430 ns      | 93.41 µs                 | 217×         |
| 1,000     | 1.05 µs     | 258.40 µs                | 246×         |
| 2,000     | 2.75 µs     | 869.55 µs                | 316×         |
| 5,000     | 11.10 µs    | 3.92 ms                  | 353×         |

BigDecimal sqrt is **86–353× slower** than GMP's integer sqrt equivalent. This extreme gap
reflects the compounding cost of Newton iteration: every iteration requires multiple
BigDecimal multiplies and divides, each of which is individually 15–35× slower than GMP.

#### BigDecimal Division (1/3) at Various Precisions

| Precision | GMP (int div) | Decimo (BigDecimal.true_divide) | Decimo / GMP |
| --------- | ------------- | ------------------------------- | ------------ |
| 28        | 10 ns         | 426 ns                          | 42.6×        |
| 100       | 18 ns         | 496 ns                          | 27.6×        |
| 500       | 70 ns         | 830 ns                          | 11.9×        |
| 1,000     | 150 ns        | 1.30 µs                         | 8.7×         |
| 2,000     | 300 ns        | 2.30 µs                         | 7.7×         |
| 5,000     | 800 ns        | 4.80 µs                         | 6.0×         |

BigDecimal division is **6–43× slower**. The ratio decreases at higher precision because
Decimo's division cost is dominated by the final long-division step (linear), while at
low precision the constant overhead of BigDecimal setup is proportionally larger.

### 5.3 Summary of Speedup Ratios

| Operation           | Small (≤100d) | Medium (~1,000d) | Large (≥5,000d) | Key Driver                              |
| ------------------- | ------------- | ---------------- | --------------- | --------------------------------------- |
| BigInt Multiply     | 7–9×          | 10×              | 12–16×          | GMP asm multiply (Karatsuba/Toom/FFT)   |
| BigInt Add          | 10–11×        | 15×              | 8–10×           | GMP asm `mpn_add_n`                     |
| BigInt Floor Divide | 12×           | 9×               | 11×             | GMP asm multiply in Burnikel-Ziegler    |
| BigInt Sqrt         | 5–9×          | 15×              | 18×             | Multiply gap compounds in Newton iters  |
| BigInt GCD          | 4–6×          | 7×               | 4–7×            | GMP sub-quadratic half-GCD              |
| BigDecimal Multiply | 15–16×        | 36×              | 29–38×          | base-10⁹ overhead + GMP asm             |
| BigDecimal Sqrt     | 86–109×       | 246×             | 316–353×        | Newton iteration compounds the gap      |
| BigDecimal Divide   | 28–43×        | 9×               | 6–8×            | Gap narrows as division dominates setup |

### 5.4 FFI Overhead Consideration

The C wrapper call path has fixed overhead:

1. `external_call` dispatch: ~1–2 ns
2. Handle array lookup: ~1–2 ns
3. Total fixed overhead: **~3–5 ns per call**

In practice:

- At **10 digits**: overhead is 30–100% of operation time → **GMP not beneficial**
- At **100 digits**: overhead is 5–10% → **GMP moderately beneficial**
- At **1,000+ digits**: overhead is <0.5% → **GMP clearly beneficial**

**Recommended crossover threshold**: Use GMP backend for numbers with **≥64 words** (~600
digits for BigInt). Below this, Decimo's native implementation avoids FFI overhead.

### 5.5 Mojo String FFI Safety Issue

During benchmarking, I hit a Mojo compiler issue where the optimizer may drop a
`String` parameter's backing buffer before the `external_call` using its `unsafe_ptr()`
completes. Under heavy allocation pressure, the freed buffer gets reused immediately,
causing GMP's `mpz_set_str` to read corrupted data.

**Workaround**: I added a length-aware C function `gmpw_set_str_n(handle, ptr, len)` that
copies exactly `len` bytes into a null-terminated buffer before calling GMP, making the
FFI call safe regardless of the caller's buffer lifetime. Any production integration must
use the length-based variant (`gmpw_set_str_n`) or ensure String buffers remain live
through explicit variable binding.

## 6. Operation Coverage Mapping

### 6.1 BigInt Operations → GMP Functions

| Decimo BigInt Operation  | GMP Function (via wrapper)          | Status         |
| ------------------------ | ----------------------------------- | -------------- |
| `__add__`                | `mpz_add` → `gmpw_add`              | ✓ Tested       |
| `__sub__`                | `mpz_sub` → `gmpw_sub`              | ✓ Tested       |
| `__mul__`                | `mpz_mul` → `gmpw_mul`              | ✓ Tested       |
| `__floordiv__`           | `mpz_fdiv_q` → `gmpw_fdiv_q`        | ✓ Tested       |
| `__truediv__`            | `mpz_tdiv_q` → `gmpw_tdiv_q`        | ✓ Tested       |
| `__mod__`                | `mpz_mod` → `gmpw_mod`              | ✓ Tested       |
| `__pow__`                | `mpz_pow_ui` → `gmpw_pow_ui`        | ✓ Tested       |
| `mod_pow`                | `mpz_powm` → `gmpw_powm`            | ✓ Tested       |
| `sqrt` / `isqrt`         | `mpz_sqrt` → `gmpw_sqrt`            | ✓ Tested       |
| `gcd`                    | `mpz_gcd` → `gmpw_gcd`              | ✓ Tested       |
| `__neg__`                | `mpz_neg` → `gmpw_neg`              | ✓ Tested       |
| `__abs__`                | `mpz_abs` → `gmpw_abs`              | ✓ Tested       |
| `__eq__`, `__lt__`, etc. | `mpz_cmp` → `gmpw_cmp`              | ✓ Tested       |
| `__and__`                | `mpz_and` → `gmpw_and`              | ✓ Tested       |
| `__or__`                 | `mpz_ior` → `gmpw_or`               | ✓ Tested       |
| `__xor__`                | `mpz_xor` → `gmpw_xor`              | ✓ Tested       |
| `__lshift__`             | `mpz_mul_2exp` → `gmpw_lshift`      | ✓ Tested       |
| `__rshift__`             | `mpz_fdiv_q_2exp` → `gmpw_rshift`   | ✓ Tested       |
| `lcm`                    | `mpz_lcm`                           | Wrapper needed |
| `extended_gcd`           | `mpz_gcdext`                        | Wrapper needed |
| `mod_inverse`            | `mpz_invert`                        | Wrapper needed |
| `from_string`            | `mpz_set_str` → `gmpw_set_str`      | ✓ Tested       |
| `__str__`                | `mpz_get_str` → `gmpw_get_str_buf`  | ✓ Tested       |
| Word import              | `mpz_import` → `gmpw_import_u32_le` | ! Partial      |
| Word export              | `mpz_export` → `gmpw_export_u32_le` | ! Partial      |

### 6.2 BigDecimal Operations → GMP Coverage

BigDecimal operations would use GMP indirectly by converting the coefficient (BigUInt) to/from GMP:

| Operation   | GMP Applicability | Notes                                                                  |
| ----------- | ----------------- | ---------------------------------------------------------------------- |
| Add/Sub     | ! Low value       | Scale alignment dominates; coefficient add is cheap                    |
| Multiply    | ✓ High value      | Large coefficient multiplication benefits from GMP                     |
| Divide      | ✓ High value      | Newton iteration on large coefficients benefits                        |
| Sqrt        | ✓ High value      | Large-precision sqrt benefits from GMP's optimized Newton              |
| Exp/Ln/Trig | ! Mixed           | Series evaluation is Mojo-managed; inner multiplications could use GMP |
| Round       | ✗ No value        | Pure digit manipulation, no heavy arithmetic                           |

### 6.3 Operations NOT in GMP

These must remain native Mojo:

- Decimal rounding (all modes)
- Scale/exponent management
- Base-10 digit manipulation
- Trigonometric series evaluation logic
- TOML parsing
- CLI calculator evaluation
- Dec128 operations (fixed-precision)

## 7. Data Conversion Between Decimo and GMP

### 7.1 BigInt ↔ GMP (Efficient)

BigInt uses base-2^32 `List[UInt32]` in little-endian order — basically the same thing as GMP's `mpz_t` but with 32-bit limbs instead of 64-bit.

**Conversion approach**:

```txt
BigInt.words: [w0, w1, w2, w3, ...]  (UInt32, little-endian)
GMP limbs:   [w0|w1, w2|w3, ...]     (UInt64, little-endian)
```

Using `mpz_import`:

```c
// Import BigInt words into GMP
mpz_import(z, word_count, -1, sizeof(uint32_t), 0, 0, words_ptr);
// -1 = least significant word first (little-endian word order)
// sizeof(uint32_t) = 4 bytes per word
// 0 = native byte order within word
// 0 = no nail bits
```

Using `mpz_export`:

```c
// Export GMP value to BigInt words
size_t count;
mpz_export(words_ptr, &count, -1, sizeof(uint32_t), 0, 0, z);
```

**Cost**: O(n) memory copy — essentially free compared to the arithmetic operations.

**Sign handling**: BigInt stores sign as separate `Bool`; GMP stores sign in `_mp_size` (negative = negative). Trivial to map.

**Implementation in C wrapper** (already prototyped):

```c
void gmpw_import_u32_le(int handle, const uint32_t* words, int count);
int  gmpw_export_u32_le(int handle, uint32_t* out_buf, int max_count);
```

### 7.2 BigUInt ↔ GMP (Expensive)

BigUInt uses base-10^9 — a completely different number base from GMP's binary format.

**Conversion options**:

| Method             | Complexity | Description                                                    |
| ------------------ | ---------- | -------------------------------------------------------------- |
| String round-trip  | O(n²)      | `BigUInt → String → mpz_set_str` — simple but slow             |
| Horner's method    | O(n²)      | Evaluate polynomial: `((w[n-1] × 10^9 + w[n-2]) × 10^9 + ...)` |
| Divide-and-conquer | O(n·log²n) | Split at midpoint, convert halves, combine with shift+add      |

**Recommended approach**:

- For <1000 words: Horner's method (simpler, O(n²) acceptable)
- For ≥1000 words: Divide-and-conquer using GMP's own multiply for combining

**Break-even analysis**: Assuming base conversion costs ~O(n²) for n words:

- At 100 words (~900 digits): conversion ~10 µs, GMP multiply saves ~4 µs → **NOT worth it**
- At 1000 words (~9000 digits): conversion ~1 ms, GMP multiply saves ~150 µs → **NOT worth it for single operation**
- **Conclusion**: BigUInt→GMP conversion is only justified when amortized across many operations (e.g., performing multiple root/exp iterations on the same number).

### 7.3 Recommended Strategy

```txt
                    ┌──────────────────────────────────────┐
 BigInt operations  │  Direct word import/export (O(n))    │ → Phase 1
                    │  Cheap, always beneficial > 64 words │
                    └──────────────────────────────────────┘

                    ┌──────────────────────────────────────┐
 BigDecimal ops     │  Convert once, compute many times    │ → Phase 2
 (iterative: sqrt,  │  Cache GMP representation during     │
  exp, ln, etc.)    │  multi-step computations             │
                    └──────────────────────────────────────┘

                    ┌──────────────────────────────────────┐
 BigDecimal ops     │  Skip GMP — conversion cost          │ → Phase 3 (or skip)
 (single-shot:      │  exceeds arithmetic savings          │
  add, sub, round)  │                                      │
                    └──────────────────────────────────────┘
```

## 8. GMP Detection and Fallback Strategy

### 8.1 Detection Approaches

Since Mojo 0.26.2 doesn't have `DLHandle` for runtime library probing, detection has to be **build-time** or **semi-static**:

#### Option A: Compile-Time Feature Flag (Recommended for Now)

```toml
# pixi.toml
[feature.gmp]
tasks.package-gmp = "mojo build -DGMP_ENABLED -Xlinker -lgmp_wrapper ..."
```

```mojo
# In Decimo source (when Mojo supports comptime parameters)
@parameter
if GMP_ENABLED:
    alias _engine = GMPEngine
else:
    alias _engine = NativeEngine
```

**Pros**: Zero overhead, no runtime branching  
**Cons**: Requires separate builds for GMP and non-GMP versions

#### Option B: Probe Function at Module Load

```mojo
# Use the C wrapper's availability check
def _check_gmp_available() -> Bool:
    """Call gmpw_available() which returns 1 if GMP is linked."""
    try:
        var result = external_call["gmpw_available", Int32]()
        return result == 1
    except:
        return False

# Cache at first use (workaround for no global variables)
struct _GMPState:
    var checked: Bool
    var available: Bool
```

**Pros**: Single binary works with or without GMP  
**Cons**: Requires the wrapper to be linked (even if GMP is absent)

#### Option C: Two-Library Approach

Build two versions of the wrapper:

1. `libgmp_wrapper.dylib` — full GMP wrapper (requires GMP)
2. `libgmp_stub.dylib` — stub that returns "unavailable" for all functions

Link against whichever is present. The stub library lets Decimo compile and run without GMP.

**Pros**: Clean separation, single Mojo codebase  
**Cons**: Requires distributing two library variants

### 8.2 Recommended Detection Strategy

**Phase 1 (immediate)**: Use **Option A** — compile-time feature flag. Build two package variants:

- `decimo.mojoc` — native only (default)
- `decimo_gmp.mojoc` — with GMP backend

**Phase 2 (when Mojo matures)**: Migrate to **Option B** with `DLHandle` when available, enabling true runtime detection.

### 8.3 Fallback Behavior

```txt
User calls BigInt.multiply(a, b):
  1. Check engine preference (from parameter or default)
  2. If engine == GMP and gmp_available:
     a. Check size threshold (≥64 words?)
     b. If yes: convert words → GMP, compute, convert back
     c. If no: use native Mojo implementation
  3. If engine == Native or !gmp_available:
     → Use native Mojo implementation (current code)
```

## 9. Type Design: BigFloat and BigDecimal

Decimo gets two arbitrary-precision types with different backends and semantics.

### 9.1 Two Types, Two Number Systems

|                    | **BigDecimal**                   | **BigFloat**                                       |
| ------------------ | -------------------------------- | -------------------------------------------------- |
| Internal base      | 10⁹ (decimal)                    | binary (MPFR `mpfr_t`)                             |
| Python analogue    | `decimal.Decimal`                | `mpmath.mpf`                                       |
| `sqrt(0.01)`       | `0.1` (exact)                    | `0.1000...0` (padded)                              |
| Dependency         | None                             | MPFR required                                      |
| Speed at high prec | Native Mojo                      | 10–400× faster (MPFR)                              |
| Precision unit     | Decimal digits                   | Bits (user specifies digits, converted internally) |
| Rounding           | Decimal-exact where possible     | Correctly rounded per IEEE binary semantics        |
| Primary use case   | Finance, human-friendly decimals | Scientific computing, transcendentals              |

They coexist in the same library. User picks the right tool for the job.

### 9.2 Why Two Types Instead of a Backend Swap

`mpmath` pulls off a transparent backend swap (`MPZ = gmpy.mpz or int`) because:

- Python is dynamically typed — the swap is invisible at runtime
- `mpmath` already uses binary representation internally — swapping `int` for `mpz_t`
  doesn't change semantics

I can't do this in Decimo because:

1. **Mojo is statically typed** — users must choose their type at compile time.
2. **BigDecimal uses base-10⁹** — swapping BigUInt for `mpz_t` would change decimal
   semantics (e.g., `sqrt(0.01)` behavior).
3. **They solve different problems** — BigDecimal is for exact decimal arithmetic;
   BigFloat is for fast scientific computation.

Python itself acknowledges this split: `decimal.Decimal` and `mpmath.mpf` are separate
packages. I'm combining both under one import.

### 9.3 BigFloat: MPFR-Backed Binary Float

```mojo
struct BigFloat:
    """Arbitrary-precision binary floating-point, backed by MPFR.

    Like mpmath's mpf but faster — every operation is a single MPFR call.
    Requires MPFR to be installed. If MPFR is unavailable, construction raises.
    """
    var handle: Int32  # MPFR handle (via C wrapper handle pool)
```

**BigFloat requires MPFR. No fallback.**

I considered a pure-Mojo BigInt-based fallback (like mpmath's pure-Python mode), but:

- mpmath's fallback arithmetic is ~30K lines of Python for the math functions alone
  (Taylor series, argument reduction, binary splitting, etc.)
- Reimplementing all that in Mojo defeats the purpose — BigFloat's value proposition
  IS speed via MPFR
- If MPFR isn't installed, users have BigDecimal — it already does sqrt, exp, ln, sin,
  cos, tan, pi, all in pure Mojo. Just slower at high precision.
- A half-working BigFloat (add/sub/mul work but sqrt/exp/ln don't) would be confusing

So: BigFloat without MPFR is like numpy without its C core. Users without MPFR use
BigDecimal. This is an honest, clean boundary.

### 9.4 Why MPFR, Not `mpz_t` with Manual Scale

GMP has three numeric types:

| Type     | What it stores                                      | Mojo analogue | Use for BigFloat?                                                  |
| -------- | --------------------------------------------------- | ------------- | ------------------------------------------------------------------ |
| `mpz_t`  | Arbitrary-precision **integer**                     | BigInt        | ✗ Poor — must manually track scale, sign, implement all algorithms |
| `mpf_t`  | Arbitrary-precision **binary float** (GMP built-in) | —             | △ Works but legacy, no correct rounding                            |
| `mpfr_t` | Arbitrary-precision **binary float** (MPFR library) | **BigFloat**  | **✓ Best** — correctly rounded, built-in exp/ln/sin/cos/π          |

With `mpz_t`, I'd have to:

- Store `(sign, mantissa: mpz_t, exponent: Int)` and manage scale manually
- Scale up numerators by 10^N before integer division
- Implement Newton iterations for sqrt, Taylor series for exp/ln/trig — **myself**
- Handle scale alignment for addition/subtraction
- That's basically reimplementing mpmath in Mojo (~30K lines)

With **MPFR**, all of this is handled internally:

- Division: `mpfr_div(r, a, b, MPFR_RNDN)` — one call
- Sqrt: `mpfr_sqrt(r, a, MPFR_RNDN)` — one call
- Exp/Ln: `mpfr_exp`, `mpfr_log` — one call each, correctly rounded
- Sin/Cos/Tan: `mpfr_sin`, `mpfr_cos`, `mpfr_tan` — one call each
- π: `mpfr_const_pi(r, MPFR_RNDN)` — one call, arbitrary precision

MPFR sits on top of GMP and is the industry standard for arbitrary-precision
floating-point. Easy to get: `brew install mpfr` (macOS), `apt install libmpfr-dev`
(Linux).

### 9.5 BigFloat API

```mojo
# Construction
var x = BigFloat("3.14159", precision=1000)   # from string
var y = BigFloat(bd, precision=1000)           # from BigDecimal
var z = BigFloat.pi(precision=5000)            # constant

# Arithmetic (returns BigFloat)
var r = x + y
var r = x * y
var r = x / y

# Transcendentals (single MPFR call each)
var r = x.sqrt()
var r = x.exp()
var r = x.ln()
var r = x.sin()
var r = x.cos()
var r = x.tan()
var r = x.root(n)
var r = x.power(y)

# Conversion back to BigDecimal
var bd = r.to_bigdecimal(precision=1000)

# Chained computation (stays in MPFR the whole time)
var result = (
    BigFloat("23", P).sqrt()
    .multiply(BigFloat("2.1", P).exp())
    .divide(BigFloat.pi(P))
    .to_bigdecimal(P)
)
# Cost: 2 string→MPFR conversions in, 5 MPFR calls, 1 MPFR→string out
# No intermediate decimal conversions
```

Precision is specified in decimal digits but converted to bits internally:
`bits = ceil(digits × 3.322) + guard_bits`. Guard bits (64 extra) ensure the
requested decimal digits are all correct after binary→decimal conversion.

### 9.6 BigDecimal `gmp=True` Convenience

BigDecimal keeps an optional `gmp=True` parameter for **one-off acceleration**
without changing types. Internally it does `BigDecimal → BigFloat → compute → BigDecimal`:

```mojo
# Single-call sugar (user stays in BigDecimal world)
var r = sqrt(x, precision=5000, gmp=True)
var r = exp(x, precision=5000, gmp=True)
var r = pi(precision=10000, gmp=True)

# Equivalent to:
var r = BigFloat(x, 5010).sqrt().to_bigdecimal(5000)
```

Only **iterative compute-heavy** operations get the `gmp` parameter:

| Function                        | Gets `gmp`? | Reason                                  |
| ------------------------------- | ----------- | --------------------------------------- |
| `sqrt`, `root`                  | ✓ Yes       | Newton iteration → single MPFR call     |
| `exp`, `ln`                     | ✓ Yes       | Taylor/atanh series → single MPFR call  |
| `sin`, `cos`, `tan`             | ✓ Yes       | Taylor series → single MPFR call        |
| `pi`                            | ✓ Yes       | Chudnovsky → `mpfr_const_pi`            |
| `true_divide`                   | ✓ Yes       | Long division at high precision         |
| `__add__`, `__sub__`, `__mul__` | ✗ No        | Too cheap — FFI overhead not worth it   |
| `round`, `__floordiv__`         | ✗ No        | Digit manipulation, no heavy arithmetic |

**When to use `gmp=True` vs BigFloat directly:**

- Single operation on BigDecimal inputs? → `gmp=True` (one liner, stays in BigDecimal)
- Chain of operations? → Use BigFloat directly (avoids repeated conversion)

### 9.7 Behavioral Differences: Binary vs. Decimal

MPFR is a **binary** float internally. What this means:

1. **Last 1–2 decimal digits may differ** between `gmp=True` and `gmp=False`. The
   numerical value agrees to the requested precision, but the least significant digits
   can differ due to binary↔decimal rounding.

2. **Guard digits handle this** — I compute with `precision + 10` extra digits, then
   truncate. Standard practice (Python's `decimal` module does the same).

3. **MPFR guarantees correct rounding** — every operation is correctly rounded to the
   working binary precision. Actually *stronger* than Decimo's native implementation
   which may accumulate rounding errors across Newton iterations.

4. **Semantic difference with BigFloat** — `BigFloat("0.01").sqrt()` returns
   `0.1000000...0` (binary representation of 0.1). `BigDecimal("0.01").sqrt()` returns
   exactly `0.1`. For scientific computing this doesn't matter. For financial/display
   work, use BigDecimal.

### 9.8 When to Use Which

| Scenario                                 | Use                      | Why                                               |
| ---------------------------------------- | ------------------------ | ------------------------------------------------- |
| Financial calculations                   | BigDecimal               | Exact decimal representation, no binary surprises |
| Display-friendly output                  | BigDecimal               | `0.1` stays `0.1`, not `0.10000...00001`          |
| Fast transcendentals (exp, ln, sin, cos) | BigFloat                 | Single MPFR call, 10–353× faster                  |
| Scientific computing                     | BigFloat                 | MPFR's correctly-rounded arithmetic               |
| Chained high-precision computation       | BigFloat                 | Stays in MPFR, no intermediate conversions        |
| One-off speedup without changing types   | `gmp=True` on BigDecimal | Drop-in acceleration, backward compatible         |
| No MPFR installed                        | BigDecimal               | Works everywhere, pure Mojo                       |
| Quick calculation under ~100 digits      | BigDecimal               | FFI overhead not worth it at low precision        |

### 9.9 Future: Lazy Evaluation for BigDecimal

The `gmp=True` per-call approach has a weakness: chained operations convert back and
forth between BigDecimal and MPFR at every step. A future `lazy()` API fixes this:

```mojo
# Future API
var result = (
    BigDecimal("23").lazy()
    .sqrt(5000)
    .multiply(BigDecimal("2.1").lazy().exp(5000))
    .divide(BigDecimal.pi(5000))
    .collect()       # executes the whole chain
)
```

How it would work:

1. `.lazy()` returns a `LazyDecimal` that **records operations** instead of evaluating
2. `.collect()` analyzes the expression tree and picks the best execution strategy
3. If MPFR available: convert leaf inputs to MPFR **once**, execute entire DAG in MPFR,
   convert root output back **once** — zero intermediate conversions
4. If MPFR unavailable (or `.collect(gmp=False)`): execute natively in BigDecimal

This is the same pattern as:

- **Polars** — lazy DataFrames, `.collect()` triggers execution
- **Spark** — query planning, transformations are lazy until action
- **C++ Eigen** — expression templates, deferred evaluation until assignment
- **TensorFlow 1.x** — computation graphs, `session.run()` triggers execution

The key insight: users write BigDecimal code (familiar API), the engine figures out the
fastest execution path. This goes beyond the roadmap below but is architecturally clean
because BigFloat and the MPFR wrapper already provide the fast backend.

### 9.10 CLI Integration

With BigFloat as a first-class type, the CLI can offer:

```bash
decimo "sqrt(2)" -p 1000                     # default: BigDecimal
decimo "sqrt(2)" -p 1000 --mode float         # use BigFloat (requires MPFR)
decimo "sqrt(2)" -p 1000 --gmp                # BigDecimal with gmp=True
```

`--mode float` tells the evaluator to parse all literals as BigFloat and evaluate the
entire expression in MPFR. `--gmp` keeps BigDecimal but enables `gmp=True` on each
operation (current plan, deferred to Phase 4).

### 9.11 Future: Global Variable or Context

When Mojo gets global variables, a module-level default can supplement the per-call
parameter:

```mojo
# Future (when Mojo supports global variables)
BigDecimal.set_default_engine("gmp")
var result = sqrt(x, 1000)            # automatically uses GMP
```

The `gmp` parameter stays as an explicit override for fine-grained control.

## 10. Build System Integration

### 10.1 C Wrapper Compilation

The C wrapper gets compiled as a shared library, shipped alongside the Mojo package.

**Build script** (`build_gmp_wrapper.sh`):

```bash
#!/bin/bash
# Detect GMP installation
GMP_PREFIX=$(brew --prefix gmp 2>/dev/null || echo "/usr/local")

if [ ! -f "$GMP_PREFIX/include/gmp.h" ]; then
    echo "GMP not found. Building without GMP support."
    exit 0
fi

# Compile wrapper
cc -shared -O2 -o libgmp_wrapper.dylib gmp_wrapper.c \
   -I"$GMP_PREFIX/include" -L"$GMP_PREFIX/lib" -lgmp

# Fix install name (macOS)
if [[ "$(uname)" == "Darwin" ]]; then
    install_name_tool -id @rpath/libgmp_wrapper.dylib libgmp_wrapper.dylib
fi
```

### 10.2 pixi.toml Integration

```toml
[tasks]
build-gmp-wrapper = """
    bash src/decimo/gmp/build_gmp_wrapper.sh
"""

package-with-gmp = { depends-on = ["build-gmp-wrapper"] }
package-with-gmp.cmd = """
    mojo precompile src/decimo -o decimo.mojoc && \
    cp src/decimo/gmp/libgmp_wrapper.dylib .
"""
```

### 10.3 Mojo Build Flags

For building executables that use Decimo with GMP:

```bash
# macOS (Homebrew)
mojo build \
  -Xlinker -L./path/to/wrapper -Xlinker -lgmp_wrapper \
  -Xlinker -L/opt/homebrew/lib -Xlinker -lgmp \
  -Xlinker -rpath -Xlinker ./path/to/wrapper \
  -Xlinker -rpath -Xlinker /opt/homebrew/lib \
  -o myprogram myprogram.mojo

# Linux (system GMP)
mojo build \
  -Xlinker -L./path/to/wrapper -Xlinker -lgmp_wrapper \
  -Xlinker -lgmp \
  -Xlinker -rpath -Xlinker ./path/to/wrapper \
  -o myprogram myprogram.mojo
```

### 10.4 Runtime Detection: Single Binary Without Link-Time Dependencies

**Goal**: One compiled binary that works whether or not MPFR/GMP is on the
machine. If `gmp=True` is requested and MPFR is found, use it. If not, raise
a helpful error. If nobody calls `gmp=True`, zero cost.

**Verified**: `dlopen` works from Mojo 0.26.2 via `external_call["dlopen", ...]`.
I tested it — GMP loaded at runtime without any `-Xlinker` flags at compile time.

**Architecture**: The C wrapper does lazy loading internally using `dlopen`/`dlsym`,
so it compiles and links **without** needing MPFR/GMP headers or libraries present:

```c
// gmp_wrapper.c — always compilable, no link-time dependency on libmpfr
#include <dlfcn.h>

static void *mpfr_lib = NULL;
static int   mpfr_loaded = 0;

// Function pointer types
typedef int  (*mpfr_init2_t)(void*, long);
typedef void (*mpfr_clear_t)(void*);
typedef int  (*mpfr_set_str_t)(void*, const char*, int, int);
// ... one typedef per MPFR function used

static mpfr_init2_t   p_mpfr_init2   = NULL;
static mpfr_clear_t   p_mpfr_clear   = NULL;
static mpfr_set_str_t p_mpfr_set_str = NULL;
// ... etc.

int mpfrw_load(void) {
    if (mpfr_loaded) return mpfr_lib != NULL;
    mpfr_loaded = 1;

    // Try common library paths
    const char *paths[] = {
        "libmpfr.dylib",                           // macOS rpath
        "/opt/homebrew/lib/libmpfr.dylib",         // macOS ARM64
        "/usr/local/lib/libmpfr.dylib",            // macOS x86_64
        "libmpfr.so",                              // Linux rpath
        "/usr/lib/x86_64-linux-gnu/libmpfr.so",    // Debian/Ubuntu
        "/usr/lib/libmpfr.so",                     // Generic Linux
        NULL
    };

    for (int i = 0; paths[i]; i++) {
        mpfr_lib = dlopen(paths[i], RTLD_LAZY);
        if (mpfr_lib) break;
    }
    if (!mpfr_lib) return 0;

    // Resolve all needed symbols
    p_mpfr_init2   = dlsym(mpfr_lib, "mpfr_init2");
    p_mpfr_clear   = dlsym(mpfr_lib, "mpfr_clear");
    p_mpfr_set_str = dlsym(mpfr_lib, "mpfr_set_str");
    // ... resolve all function pointers

    return (p_mpfr_init2 && p_mpfr_clear && p_mpfr_set_str /* && ... */);
}

int mpfrw_available(void) {
    return mpfrw_load();
}
```

**On the Mojo side**, the wrapper is the only native dependency:

```mojo
def sqrt(x: BigDecimal, precision: Int, gmp: Bool = False) raises -> BigDecimal:
    if not gmp:
        return _sqrt_native(x, precision)

    # Check MPFR availability at runtime
    var available = external_call["mpfrw_available", c_int]()
    if available == 0:
        raise Error(
            "gmp=True requires MPFR. Install: brew install mpfr (macOS) "
            "or apt install libmpfr-dev (Linux)"
        )
    return _sqrt_mpfr(x, precision)
```

**Build simplification**: With lazy loading, the build command for users becomes:

```bash
# Only need to link the small wrapper — no -lmpfr or -lgmp needed
mojo build -Xlinker -L./path/to/wrapper -Xlinker -ldecimo_gmp_wrapper \
           -Xlinker -rpath -Xlinker ./path/to/wrapper \
           -o myprogram myprogram.mojo
```

The wrapper is a tiny C file (~200 lines) that compiles on any system
with just a C compiler — no GMP/MPFR headers needed. MPFR only gets loaded at
runtime when `gmp=True` is actually called.

**Summary of approach by timeline**:

| Timeline              | Detection Method             | Binary Requirements                              |
| --------------------- | ---------------------------- | ------------------------------------------------ |
| **Now** (Mojo 0.26.2) | C wrapper + `dlopen`/`dlsym` | Link wrapper only; MPFR loaded lazily at runtime |
| **Future** (DLHandle) | Mojo-native `DLHandle`       | Pure Mojo detection, no C wrapper needed         |

### 10.5 End-User Build & Run Guide (BigFloat)

BigFloat requires linking the C wrapper at build time and having MPFR available at
runtime. The steps differ from pure-Mojo types (BigDecimal, BigInt, etc.) which work
with a bare `mojo run`.

#### Prerequisites

```bash
# macOS
brew install mpfr

# Linux (Debian/Ubuntu)
sudo apt install libmpfr-dev
```

#### Step 1: Build the C wrapper

```bash
# From the decimo source directory
bash src/decimo/gmp/build_gmp_wrapper.sh
# Produces: src/decimo/gmp/libdecimo_gmp_wrapper.dylib  (macOS)
#       or: src/decimo/gmp/libdecimo_gmp_wrapper.so      (Linux)
```

The wrapper compiles with any C compiler — no MPFR headers needed at compile time
(it uses `dlopen`/`dlsym` internally).

#### Step 2: Build your Mojo binary

`mojo run` cannot link external libraries (`-Xlinker` flags are silently ignored in
JIT mode). You must use `mojo build`:

```bash
# macOS
mojo build -I src \
    -Xlinker -L./src/decimo/gmp -Xlinker -ldecimo_gmp_wrapper \
    -o myprogram myprogram.mojo

# Linux (same command)
mojo build -I src \
    -Xlinker -L./src/decimo/gmp -Xlinker -ldecimo_gmp_wrapper \
    -o myprogram myprogram.mojo
```

#### Step 3: Run with library path

The OS needs to find the `.dylib`/`.so` at runtime:

```bash
# macOS
DYLD_LIBRARY_PATH=./src/decimo/gmp ./myprogram

# Linux
LD_LIBRARY_PATH=./src/decimo/gmp ./myprogram
```

#### All-in-one example

```bash
bash src/decimo/gmp/build_gmp_wrapper.sh \
&& pixi run mojo build -I src \
    -Xlinker -L./src/decimo/gmp -Xlinker -ldecimo_gmp_wrapper \
    -o /tmp/myprogram myprogram.mojo \
&& DYLD_LIBRARY_PATH=./src/decimo/gmp /tmp/myprogram
```

#### Comparison with pure-Mojo types

| Type         | Build command                                   | Extra dependencies | Library path needed? |
| ------------ | ----------------------------------------------- | ------------------ | -------------------- |
| BigDecimal   | `mojo run -I src myprogram.mojo`                | None               | No                   |
| BigInt       | `mojo run -I src myprogram.mojo`                | None               | No                   |
| Dec128       | `mojo run -I src myprogram.mojo`                | None               | No                   |
| **BigFloat** | `mojo build -I src -Xlinker ... myprogram.mojo` | MPFR + C wrapper   | **Yes**              |

When Mojo gains native `DLHandle` support, the C wrapper can be eliminated and BigFloat
will work with `mojo run` like the other types.

## 11. Cross-Platform Considerations

### 11.1 Platform Matrix

| Platform         | GMP Availability  | Wrapper Format | Install Method           | Notes                       |
| ---------------- | ----------------- | -------------- | ------------------------ | --------------------------- |
| **macOS ARM64**  | ✓ Homebrew        | `.dylib`       | `brew install gmp`       | **Tested ✓**                |
| **macOS x86_64** | ✓ Homebrew        | `.dylib`       | `brew install gmp`       | Should work (untested)      |
| **Linux x86_64** | ✓ System packages | `.so`          | `apt install libgmp-dev` | Expected to work            |
| **Linux ARM64**  | ✓ System packages | `.so`          | `apt install libgmp-dev` | Expected to work            |
| **Windows**      | ! Complex         | `.dll`         | MSYS2/vcpkg/MPIR         | Requires MinGW or MPIR fork |

### 11.2 GMP Detection by Platform

```bash
# macOS
GMP_PREFIX=$(brew --prefix gmp 2>/dev/null)
# → /opt/homebrew/Cellar/gmp/6.3.0

# Linux (Debian/Ubuntu)
dpkg -l libgmp-dev 2>/dev/null | grep -q '^ii'
# Headers: /usr/include/gmp.h
# Library: /usr/lib/x86_64-linux-gnu/libgmp.so

# Linux (generic)
pkg-config --exists gmp && pkg-config --cflags --libs gmp
```

### 11.3 Platform-Specific Considerations

**macOS**:

- Homebrew puts GMP in `/opt/homebrew/` (ARM64) or `/usr/local/` (x86_64)
- Must set `@rpath` for `.dylib` loading
- SIP may restrict library search paths

**Linux**:

- System GMP is typically in standard paths (`/usr/lib/`, `/usr/include/`)
- No rpath issues with standard paths
- May need `-lgmp` at end of link flags for some linkers

**Windows** (future):

- GMP does not natively support MSVC
- Options: MPIR (Windows-friendly GMP fork), MinGW-compiled GMP, or Cygwin
- Different shared library format (`.dll` + import lib)
- Mojo on Windows is still early — defer this concern

## 12. Risk Analysis

### 12.1 Technical Risks

| Risk                                    | Likelihood | Impact | Mitigation                                                 |
| --------------------------------------- | ---------- | ------ | ---------------------------------------------------------- |
| Mojo FFI API changes in future versions | HIGH       | MEDIUM | Isolate FFI calls in single module; version-gate if needed |
| GMP version incompatibility             | LOW        | LOW    | Target GMP ≥6.0 (stable ABI); C wrapper abstracts details  |
| Handle exhaustion (4096 limit)          | LOW        | MEDIUM | Add handle recycling; expand pool; document limit          |
| Memory leaks from uncleared handles     | MEDIUM     | MEDIUM | Add `__del__` integration; RAII pattern in Mojo wrapper    |
| Base conversion overhead for BigDecimal | HIGH       | MEDIUM | Only use GMP for iterative operations; cache conversions   |
| Build complexity increase               | MEDIUM     | MEDIUM | Provide clear build scripts; make GMP optional             |

### 12.2 Ecosystem Risks

| Risk                            | Likelihood | Impact | Mitigation                                                |
| ------------------------------- | ---------- | ------ | --------------------------------------------------------- |
| Users don't have GMP installed  | HIGH       | LOW    | GMP is optional; native Mojo is always available          |
| Package distribution complexity | MEDIUM     | MEDIUM | Document build steps; consider bundling prebuilt wrappers |
| Mojo package system changes     | MEDIUM     | MEDIUM | Keep wrapper as separate build artifact                   |

### 12.3 Performance Risks

| Risk                                     | Description                          | Mitigation                                       |
| ---------------------------------------- | ------------------------------------ | ------------------------------------------------ |
| FFI overhead dominates for small numbers | Measured: ~3–5 ns overhead per call  | Size threshold (≥64 words) before using GMP      |
| String-based conversion bottleneck       | O(n²) for string round-trip          | Use binary word import/export instead            |
| Unnecessary conversions                  | Converting back and forth repeatedly | Cache GMP handles during multi-step computations |
| GMP slower for specific operations       | Possible edge cases                  | Benchmark-driven thresholds per operation type   |

## 13. Lessons from Other Libraries

Before diving into the roadmap, I looked at how major open-source libraries integrate GMP/MPFR to see what I can learn from them.

### 13.1 mpmath (Python) — Backend Abstraction

mpmath is *the* arbitrary-precision math library for Python (~1M+ monthly downloads).

**How mpmath does it**:

- **Backend swap**: `backend.py` defines `MPZ` (integer type) and `BACKEND` (string).
  At startup it tries `import gmpy2`, then `import gmp`, falling back to Python `int`.
  All mantissa arithmetic goes through `MPZ` — a single point of substitution.
- **Environment override**: `MPMATH_NOGMPY` env var disables GMP entirely,
  useful for debugging and pure-Python deployment.
- **gmpy acceleration hooks**: When gmpy is available, mpmath replaces its
  `_normalize` and `from_man_exp` hot-path functions with optimized C versions
  from gmpy (`gmpy._mpmath_normalize`, `gmpy._mpmath_create`), and also
  `mpf_mul_int` is swapped to a gmpy-accelerated version. This gives 2–5×
  speedup on core arithmetic with zero API change.
- **Internal representation**: Binary floating-point tuples `(sign, man, exp, bc)`.
  All precision is in **bits**, converted to/from decimal digits via
  `dps_to_prec(n) = max(1, int(round((n+1)*3.3219...)))` and
  `prec_to_dps(n) = max(1, int(round(n/3.3219...))-1)`.
- **Guard bits**: Extra precision is added internally. Individual functions use
  `extraprec` (add N bits) or `workprec` (set to N bits). The `autoprec` decorator
  doubles precision until results converge — a "guess-and-verify" paradigm.

**Takeaway**: The single-variable backend swap (`MPZ = gmpy.mpz`) is clean.
My C wrapper approach is analogous but at a lower level. I should make sure
that all GMP-dependent code stays isolated in a single module.

### 13.2 gmpy2 (Python ↔ MPFR) — Context-Based Precision

gmpy2 is the standard Python binding for GMP + MPFR + MPC.

**How gmpy2 does it**:

- **Context object**: `gmpy2.context()` controls precision, rounding mode, exception
  traps, and exponent range. `get_context()` returns the active context;
  `local_context()` provides temporary overrides (similar to Python's `decimal.localcontext()`).
- **5 rounding modes**: RoundToNearest, RoundToZero, RoundUp, RoundDown, RoundAwayZero.
  These map directly to MPFR's rounding modes.
- **Thread safety**: MPFR data (flags, emin/emax, default precision) uses
  thread-local storage when built with `--enable-thread-safe`.
- **Exception model**: Flags for overflow, underflow, inexact, invalid, divzero,
  erange. Each has a corresponding `trap_*` bool — if True, raises a Python
  exception; if False, sets the flag silently and returns a special value (NaN, ±Inf).
- **Precision tracking**: Each `mpfr` value carries its own precision. When combining
  values of different precisions, the context precision governs the result.
- **Implicit conversion**: `mpz → mpfr` is automatic. `float → mpfr` preserves
  all 53 bits. `str → mpfr` uses full specified precision.

**Takeaway**: My `gmp: Bool = False` parameter approach is simpler but
sufficient. If I later want a richer API, a context object could control precision,
rounding mode, and GMP-enable globally. For now, per-call `gmp=True` is fine.

### 13.3 Arb/FLINT — Ball Arithmetic & Guard Bits

Arb (now merged into FLINT) implements rigorous arbitrary-precision ball arithmetic.

**How Arb works**:

- **Ball semantics**: Each number is `[midpoint ± radius]`. Operations propagate
  error bounds automatically. The user doesn't manually track rounding errors.
- **Binary ↔ decimal conversion**: Arb explicitly warns that this conversion is
  lossy. `arb_set_str("2.3", prec)` correctly creates a ball containing 23/10,
  unlike a naive `double` assignment. `arb_printn()` only prints digits that are
  guaranteed correct.
- **Guess-and-verify paradigm**: Start with modest precision, check if the result
  is accurate enough, double precision and retry if not. This is the recommended
  approach for complex computations.
- **Guard bits heuristic**: For accuracy of p bits, use working precision O(1)+p.
  The O(1) term depends on the expression. "Adding a few guard bits" (10–20 for
  basic operations) is usually enough.
- **Polynomial time guarantee**: Arb caps internal work parameters by polynomial
  functions of `prec` to prevent runaway computation. E.g., `arb_sin(huge_x)` returns
  `[±1]` instead of attempting expensive argument reduction.
- **Handle lifecycle**: GMP-style `arb_init(x)` / `arb_clear(x)`. Output parameters
  come first, then inputs, then precision.

**Takeaway**: The guard bits pattern confirms my approach of using
`prec + 10` in MPFR calls. I should also add a precision cap for safety.
The polynomial time guarantee is worth stealing for my iterative operations.

### 13.4 python-flint — Direct FLINT/Arb Bindings

python-flint wraps FLINT (which includes Arb) for Python.

**How python-flint works**:

- **Type hierarchy**: Separate types for each number ring: `fmpz` (integers),
  `fmpq` (rationals), `arb` (real balls), `acb` (complex balls), plus polynomial
  and matrix variants.
- **Global context**: Precision is set globally (`ctx.prec = 333` for ~100 decimal
  digits). All operations use the current context precision.

### 13.5 Consistency Check: My Plan vs. Best Practices

| Best Practice (from survey)                | Status in My Plan   | Notes                                                             |
| ------------------------------------------ | ------------------- | ----------------------------------------------------------------- |
| Graceful fallback (GMP optional)           | ✓ Designed          | BigDecimal works without MPFR; BigFloat requires it               |
| First-class user-facing type               | ✓ BigFloat          | Like mpmath's `mpf` — user constructs and chains operations       |
| Convenience sugar on existing type         | ✓ `gmp=True`        | BigDecimal ops accept `gmp=True` for one-off acceleration         |
| Isolated backend module                    | ✓ `bigfloat.mojo`   | All MPFR calls in one file                                        |
| Guard bits in MPFR calls                   | ✓ `prec + 10`       | Confirmed adequate by Arb docs                                    |
| Decimal ↔ binary via string (not raw bits) | ✓ Planned           | `mpfr_set_str` / `mpfr_get_str`, base 10                          |
| Environment variable to disable GMP        | ✗ **Not yet**       | **TODO**: `DECIMO_NOGMP` env check (like mpmath `MPMATH_NOGMPY`)  |
| Handle pool with lifecycle management      | ✓ Planned           | C wrapper handle pool                                             |
| Rounding mode control                      | △ Partial           | RNDN only. Consider exposing rounding mode later                  |
| Precision cap for safety                   | ✗ **Not yet**       | **TODO**: Cap internal MPFR precision to prevent OOM              |
| Conversion overhead awareness              | ✓ Documented        | String round-trip mitigated by BigFloat chaining + lazy future    |
| Thread safety considerations               | ✗ **Not yet**       | **TODO**: MPFR handle pool is not thread-safe; document this      |
| Benchmark-driven thresholds                | ✓ Planned (Phase 1) | Find break-even precision for each operation                      |
| Lazy evaluation for chained ops            | △ Future            | `BigDecimal.lazy()...collect()` — deferred, architecturally clean |

**Gaps I found** (incorporated into the roadmap below):

1. **`DECIMO_NOGMP` environment variable** (Phase 1) — lets users disable GMP at
   runtime, like mpmath's `MPMATH_NOGMPY`.
2. **Precision cap** (Phase 1) — prevent MPFR from allocating unbounded memory
   for extreme precision values.
3. **Thread safety docs** (Phase 4) — the C handle pool is not thread-safe;
   need to document this.

## 14. Implementation Roadmap

> BigFloat first (Phase 1), then BigDecimal `gmp=True` sugar (Phase 2), then BigInt
> backend (Phase 3 or never). MPFR has built-in sqrt, exp, ln, sin, cos, tan, π with correct
> rounding — so BigFloat operations are single MPFR calls, and BigDecimal sugar is
> just BigFloat under the hood.

### Phase 0: Prerequisites

- [x] **0.1 Install MPFR**
  `brew install mpfr` (macOS). Verify: `/opt/homebrew/lib/libmpfr.dylib` exists,
  `#include <mpfr.h>` compiles. MPFR depends on GMP (already installed).

### Phase 1: Foundation — MPFR C Wrapper & BigFloat

**Goal**: Get the MPFR-based C wrapper working, build the `BigFloat` struct as a
first-class user-facing type, and prove the pipeline with `sqrt`.

- [x] **1.1 Extend C wrapper with `mpfr_t` handle pool**
  Add to `gmp_wrapper.c`:
  (a) `static mpfr_t f_handles[MAX_HANDLES]` pool,
  (b) `mpfrw_init(prec_bits) → handle`,
  (c) `mpfrw_clear(h)`,
  (d) `mpfrw_set_str(h, str, len)` (length-safe, base-10),
  (e) `mpfrw_get_str(h, digits) → char*`,
  (f) `mpfrw_available()`.
  Keep existing `mpz_t` wrappers intact for BigInt.
  **Add precision cap**: reject `prec_bits > MAX_PREC` (e.g. 1M bits ≈ 300K digits)
  to prevent OOM, inspired by Arb's polynomial time guarantee.
  *Done: MAX_HANDLES=4096, MAX_PREC_BITS=1048576.*
- [x] **1.2 Add MPFR arithmetic wrappers** (Small, deps: 1.1)
  One-line C wrappers: `mpfrw_add(r,a,b)`, `mpfrw_sub(r,a,b)`, `mpfrw_mul(r,a,b)`,
  `mpfrw_div(r,a,b)`, `mpfrw_sqrt(r,a)`, `mpfrw_neg(r,a)`, `mpfrw_abs(r,a)`,
  `mpfrw_cmp(a,b)`. All use `MPFR_RNDN` (round-to-nearest). Each is 1 line.
- [x] **1.3 Add MPFR transcendental wrappers** (Small, deps: 1.1)
  `mpfrw_exp(r,a)`, `mpfrw_log(r,a)`, `mpfrw_sin(r,a)`, `mpfrw_cos(r,a)`,
  `mpfrw_tan(r,a)`, `mpfrw_const_pi(r)`, `mpfrw_pow(r,a,b)`, `mpfrw_rootn_ui(r,a,n)`.
  Each is 1 line.
- [x] **1.4 Implement lazy `dlopen` loading** (Medium, deps: 1.2, 1.3)
  Wrap all MPFR calls behind function pointers resolved via `dlopen`/`dlsym` at
  first use (see Section 10.4). This makes the wrapper compilable without MPFR
  headers. Add `mpfrw_available() → 0/1`.
  **Add `DECIMO_NOGMP` check**: if set, `mpfrw_available()` returns 0 without
  attempting `dlopen` (inspired by mpmath's `MPMATH_NOGMPY`).
  *Done: 8 library search paths (macOS + Linux), DECIMO_NOGMP implemented.*
- [x] **1.5 Compile wrapper, run smoke test** (Small, deps: 1.4)
  Build `libdecimo_gmp_wrapper.dylib` linking against `-lmpfr -lgmp`. Write minimal
  Mojo test: `mpfrw_init(200) → set_str("3.14") → mpfrw_sqrt → get_str → print`.
  Verify output.
  *Done: wrapper compiles without -lmpfr (dlopen). 14 smoke tests pass.*
- [x] **1.6 Create `src/decimo/bigfloat/bigfloat.mojo`** (Medium, deps: 1.5)
  Implement `BigFloat` struct (single `handle: Int32` field). Constructor from
  string via `mpfrw_set_str`. Constructor from BigDecimal via `str(bd) → mpfrw_set_str`.
  `to_bigdecimal(precision) → mpfrw_get_str → BigDecimal(s)`. Destructor calls
  `mpfrw_clear`. Use guard bits: init MPFR with `dps_to_prec(precision) + 20` bits.
  *Done: ~320 lines. Also constructors from Int. Aliases: BFlt, Float.*
- [x] **1.7 BigFloat arithmetic and transcendentals** (Medium, deps: 1.6)
  Wire all MPFR wrappers into BigFloat methods: `sqrt()`, `exp()`, `ln()`, `sin()`,
  `cos()`, `tan()`, `root(n)`, `power(y)`, `+`, `-`, `*`, `/`, `pi()`.
  Each is a thin wrapper around the corresponding `mpfrw_*` call.
  *Done: all listed + `__neg__`, `__abs__`, comparisons (`__eq__`, `__ne__`, `__lt__`, `__le__`, `__gt__`, `__ge__`).*
- [x] **1.8 BigFloat ↔ BigDecimal conversion** (Small, deps: 1.6)
  `BigFloat(bd: BigDecimal, precision)` and `bf.to_bigdecimal(precision)`.
  Both go through string representation (`mpfr_set_str` / `mpfr_get_str`).
- [ ] **1.9 Test BigFloat correctness** (Medium, deps: 1.7)
  For each operation × x ∈ {2, 3, 0.5, 100, 10⁻⁸, 10¹⁰⁰⁰} × P ∈ {28, 100, 500,
  1000, 5000}: verify BigFloat results match BigDecimal results to P digits.
  Edge cases: 0, negative, very large/small.
- [ ] **1.10 Benchmark BigFloat** (Small, deps: 1.9)
  Measure wall time for BigFloat vs BigDecimal across operations and precisions.
  Find break-even precision where BigFloat wins. Expected: above ~50–100 digits.
- [x] **1.11 Update build system** (Small, deps: 1.1)
  `pixi.toml` tasks: `build-gmp-wrapper` (compiles C wrapper + links MPFR).
  `build_gmp_wrapper.sh` for macOS + Linux.
  *Done: pixi tasks (buildgmp, testfloat, tf), test_bigfloat.sh, CI job in run_tests.yaml.*

**Deliverable**: `BigFloat("2", 5000).sqrt()` works. Users can construct BigFloat,
chain operations, and convert back to BigDecimal.

### Phase 2: BigDecimal `gmp=True` Convenience Sugar

**Goal**: Wire `gmp=True` into BigDecimal compute-heavy operations. Internally each
uses BigFloat (Phase 1), so this is just plumbing.

- [ ] **2.1 Wire `sqrt(x, P, gmp=True)`** (Small, deps: Phase 1)
  If `gmp=True`: `BigFloat(x, P+10).sqrt().to_bigdecimal(P)`. Three lines.
- [ ] **2.2 Wire `true_divide(x, y, P, gmp=True)`** (Small, deps: Phase 1)
  `BigFloat(x, P+10) / BigFloat(y, P+10) → to_bigdecimal(P)`.
- [ ] **2.3 Wire `root`, `exp`, `ln`, `sin`, `cos`, `tan`** (Small, deps: Phase 1)
  Each is a one-liner delegating to BigFloat. Single MPFR call per operation.
- [ ] **2.4 Wire `pi(P, gmp=True)`** (Small, deps: Phase 1)
  `BigFloat.pi(P+10).to_bigdecimal(P)`. No Chudnovsky needed.
- [ ] **2.5 Instance method wrappers** (Small, deps: 2.4)
  Update `self.sqrt()`, `self.exp()`, etc. to accept `gmp: Bool = False`.
- [ ] **2.6 Comprehensive test suite** (Large, deps: 2.5)
  For each function × {gmp=True, gmp=False}: verify agreement to requested
  precision. Edge cases: 0, negative, very large/small.
- [ ] **2.7 Benchmark gmp=True vs gmp=False** (Medium, deps: 2.6)
  Table: operation × precision (28, 100, 500, 1000, 5000) × gmp. Include
  conversion overhead.

**Deliverable**: All iterative BigDecimal functions support `gmp=True`. Existing
BigDecimal API unchanged for `gmp=False`.

**Checkpoint test**: `pi(precision=10000, gmp=True)` matches known π digits and runs
significantly faster than `pi(precision=10000)`.

### Phase 3: BigInt GMP Backend (Deferred, maybe never)

**Goal**: GMP backend for BigInt (base-2³²) using `mpz_t`. Deferred — integer
ops are less user-facing.

- [ ] **3.1 Word import/export in C wrapper** (Small, deps: Phase 1)
  Complete `gmpw_import_u32_le` / `gmpw_export_u32_le`. Test round-trip.
- [ ] **3.2 Create `src/decimo/bigint/gmp_backend.mojo`** (Medium, deps: 3.1)
  GMPBigInt struct. Convert BigInt ↔ GMP via O(n) word import/export.
- [ ] **3.3 Add `gmp: Bool = False` to BigInt ops** (Medium, deps: 3.2)
  On `multiply`, `floor_divide`, `sqrt`, `gcd`, `power` free functions.
- [ ] **3.4 Tests and benchmarks** (Medium, deps: 3.3)
  Verify correctness. Confirm 7–18× speedup.

### Phase 4: Polish, Distribution & Future

- [x] **4.1 Cross-platform wrapper compilation (Linux)** (Small, deps: Phase 1)
  *Done: build_gmp_wrapper.sh handles Linux (.so, -fPIC, -ldl). CI verified on ubuntu-22.04.*
- [ ] **4.2 Pre-built wrapper binaries (macOS ARM64, Linux x86)** (Medium, deps: 4.1)
- [ ] **4.3 CLI `--mode float` and `--gmp` flags** (Medium, deps: Phase 2)
  `--mode float` evaluates in BigFloat; `--gmp` enables `gmp=True` on BigDecimal ops.
- [ ] **4.4 Documentation: user guide for BigFloat and GMP integration** (Small, deps: Phase 2)
- [ ] **4.5 Pure-Mojo runtime detection (when DLHandle available)** (Medium, deps: Mojo improvement)
- [ ] **4.6 GMP rational numbers (`mpq_t`) for exact division** (Medium, future)
- [ ] **4.7 Document thread safety** (Small, deps: Phase 1)
  The C handle pool is not thread-safe; MPFR requires `--enable-thread-safe` for
  concurrent use. Document this limitation.
- [ ] **4.8 Lazy evaluation: `BigDecimal.lazy()...collect()`** (Large, future)
  Record a DAG of operations, execute entire chain in MPFR with zero intermediate
  conversions. See Section 9.9 for design. Architecturally clean because BigFloat
  and the MPFR wrapper (Phase 1) already provide the backend.

### Estimated Effort Summary

- **Phase 1: MPFR wrapper + BigFloat** — 11 steps, Medium complexity (most work is C wrapper + BigFloat struct). **HIGH** priority.
- **Phase 2: BigDecimal gmp=True sugar** — 7 steps, **Low** complexity (each op delegates to BigFloat). **HIGH** priority.
- **Phase 3: BigInt backend** — 4 steps, Medium complexity. Deferred.
- **Phase 4: Polish + lazy eval** — 8 steps, **1/8 done** (4.1 Linux build). Low priority.

## 15. Appendix: Prototype Results

### 15.1 Files Created

| File                                | Purpose                   | Status                                 |
| ----------------------------------- | ------------------------- | -------------------------------------- |
| `temp/gmp/gmp_wrapper.c`            | C wrapper library source  | ✓ Complete                             |
| `temp/gmp/libgmp_wrapper.dylib`     | Compiled shared library   | ✓ Built                                |
| `temp/gmp/test_gmp_ffi.mojo`        | FFI test suite (18 tests) | ✓ 14/18 pass (4 wrong expected values) |
| `temp/gmp/bench_gmp_vs_decimo.mojo` | GMP benchmark suite       | ✓ Complete                             |
| `temp/gmp/build_and_test.sh`        | Build and test automation | ✓ Complete                             |

### 15.2 C Wrapper API Summary

```c
// Lifecycle
int  gmpw_init(void);                              // → handle
void gmpw_clear(int handle);

// String I/O
int  gmpw_set_str(int handle, const char* str, int base);
int  gmpw_get_str_buf(int handle, char* buf, int bufsize, int base);

// Arithmetic
void gmpw_add(int r, int a, int b);
void gmpw_sub(int r, int a, int b);
void gmpw_mul(int r, int a, int b);
void gmpw_fdiv_q(int r, int a, int b);             // Floor division
void gmpw_tdiv_q(int r, int a, int b);             // Truncate division
void gmpw_mod(int r, int a, int b);
void gmpw_pow_ui(int r, int base, unsigned long exp);
void gmpw_powm(int r, int base, int exp, int mod); // Modular exponentiation
void gmpw_sqrt(int r, int a);
void gmpw_gcd(int r, int a, int b);
void gmpw_neg(int r, int a);
void gmpw_abs(int r, int a);

// Comparison
int  gmpw_cmp(int a, int b);
int  gmpw_sign(int handle);
int  gmpw_sizeinbase10(int handle);

// Bitwise
void gmpw_and(int r, int a, int b);
void gmpw_or(int r, int a, int b);
void gmpw_xor(int r, int a, int b);
void gmpw_lshift(int r, int a, unsigned long bits);
void gmpw_rshift(int r, int a, unsigned long bits);

// Binary word I/O
void gmpw_import_u32_le(int handle, const uint32_t* words, int count);
int  gmpw_export_u32_le(int handle, uint32_t* out, int max_words);
int  gmpw_export_u32_count(int handle);

// Meta
int         gmpw_available(void);
const char* gmpw_version(void);
```

### 15.3 Sample Mojo FFI Calls

```mojo
from std.ffi import external_call, c_int

# ⚠️ SAFE pattern: pass length explicitly to avoid use-after-free (see Section 16.1)
def gmp_set_str(h: c_int, s: String):
    var slen = c_int(len(s))
    var ptr = Int(s.unsafe_ptr())
    _ = external_call["gmpw_set_str_n", c_int, c_int, Int, c_int](h, ptr, slen)

# ❌ UNSAFE pattern: DO NOT USE — String may be freed before external_call executes
# def gmp_set_str(h: c_int, s: String):
#     _ = external_call["gmpw_set_str", c_int, c_int, Int](h, Int(s.unsafe_ptr()))

def gmp_init() -> c_int:
    return external_call["gmpw_init", c_int]()

def gmp_clear(h: c_int):
    external_call["gmpw_clear", NoneType, c_int](h)

def gmp_add(r: c_int, a: c_int, b: c_int):
    external_call["gmpw_add", NoneType, c_int, c_int, c_int](r, a, b)
```

### 15.4 Benchmark Data Table

**GMP absolute timings** (per operation, macOS ARM64, Apple M-series):

| Digits  | Multiply | Add    | Divide | Sqrt   | GCD    |
| ------- | -------- | ------ | ------ | ------ | ------ |
| 10      | 5 ns     | 7 ns   | —      | 8 ns   | 8 ns   |
| 100     | 23 ns    | 8 ns   | 67 ns  | 114 ns | 50 ns  |
| 1,000   | 1 µs     | 20 ns  | 818 ns | 722 ns | 169 ns |
| 10,000  | 50 µs    | 226 ns | 30 µs  | 21 µs  | 2 µs   |
| 100,000 | 939 µs   | 2 µs   | 740 µs | 642 µs | 324 µs |

## 16. Lessons Learned from Prototype Development

This section documents gotchas from the GMP prototype build-test cycle
and how I fixed them. **Read this before starting implementation** — every item
cost me real debugging time and will bite again if not handled.

### 16.1 CRITICAL: Mojo String Use-After-Free in FFI

**Symptom**: GMP's `mpz_set_str()` silently fails (returns -1), leaving the mpz as 0. Subsequent operations on zero values trigger `__gmp_overflow_in_mpz` in division
or crash with corrupt data.

**Root cause**: When you write:

```mojo
def gmp_set_str(h: c_int, s: String):
    _ = external_call["gmpw_set_str", c_int, c_int, Int](h, Int(s.unsafe_ptr()))
```

Mojo's optimizer may drop the `String` parameter `s` (freeing its buffer) before
`external_call` reads the pointer. Under heavy allocation pressure (millions of
BigInt/BigDecimal ops), the freed buffer gets reused immediately,
overwriting the null terminator. GMP reads past the string into adjacent
memory, hits non-digit bytes, returns -1.

**How I found it**: The crash only showed up in the full benchmark binary after
millions of prior allocations — never in small test files. Adding `fprintf(stderr)`
logging to the C wrapper revealed:

- `strlen()` on the pointer showed 109 instead of expected 100
- `mpz_set_str` returned -1 (failure), not 0 (success)
- The extra bytes were from adjacent String buffers reusing freed memory

**Fix**: Pass the string length explicitly and copy in C:

```c
// In gmp_wrapper.c
int gmpw_set_str_n(int h, const char *str, int len) {
    char *buf = (char *)malloc(len + 1);
    memcpy(buf, str, len);
    buf[len] = '\0';
    int rc = mpz_set_str(handles[h], buf, 10);
    free(buf);
    return rc;
}
```

```mojo
# In Mojo
def gmp_set_str(h: c_int, s: String):
    var slen = c_int(len(s))    # Extract length BEFORE ptr
    var ptr = Int(s.unsafe_ptr())
    _ = external_call["gmpw_set_str_n", c_int, c_int, Int, c_int](h, ptr, slen)
```

**Rule**: **Always use `gmpw_set_str_n` with explicit length for any String → C FFI
call.** Don't rely on null-termination of Mojo `String.unsafe_ptr()` in `external_call`.

**Broader implication**: This affects ALL FFI calls passing Mojo `String` pointers.
Every such call must either:

1. Use the length-aware C variant (recommended), or
2. Store the String in a local variable AND ensure no other allocation occurs between
   `unsafe_ptr()` extraction and the `external_call` (fragile, not recommended)

### 16.2 `mojo run` Does Not Support `-Xlinker` Flags

**Symptom**: `mojo run file.mojo -Xlinker -lgmp_wrapper` ignores the linker flags,
causing "undefined symbol" errors at runtime.

**Cause**: The JIT (`mojo run`) does not process `-Xlinker` flags. Only `mojo build`
(AOT compilation) supports them.

**Fix**: Always use `mojo build` → run the executable. Never use `mojo run` for
GMP-linked code.

```bash
# ✓ Correct
pixi run mojo build -Xlinker -L... -Xlinker -lgmp_wrapper -o program program.mojo
./program

# ✗ Wrong — linker flags silently ignored
pixi run mojo run -Xlinker -L... program.mojo
```

### 16.3 Mojo 0.26.2 Syntax Differences

Several Mojo syntax changes from earlier versions caused compile errors:

| Feature            | Old Syntax                         | Mojo 0.26.2 Syntax                             |
| ------------------ | ---------------------------------- | ---------------------------------------------- |
| Compile-time const | `alias X = 7`                      | `comptime X = 7`                               |
| String slicing     | `s[:10]`                           | `s[byte=:10]`                                  |
| UInt → Float64     | `Float64(some_uint)`               | `Float64(Int(some_uint))`                      |
| UnsafePointer      | `UnsafePointer[Byte](address=ptr)` | `UnsafePointer[Byte](unsafe_from_address=ptr)` |

### 16.4 GMP `__gmp_overflow_in_mpz` Means Bad Input, Not Overflow

Despite the name, `__gmp_overflow_in_mpz` usually means the `mpz_t` struct has
corrupted metadata (alloc=0, size=0, or bad limb pointer), NOT that a result was too large. If you see this:

1. **First check**: Did `mpz_set_str` fail? (Return value -1 means the string was invalid.)
2. **Second check**: Was the handle cleared and reused?
3. **Third check**: Was the handle ever initialized?

In my case it was always (1) — the string pointer was dangling.

### 16.5 Handle Pool Sizing

The C wrapper uses a static array of `MAX_HANDLES = 4096`. For Phase 1 (sqrt),
each Newton iteration typically uses 3–5 temporary handles, so 4096 is plenty. But for
Phase 2 (complex expression trees), monitor handle usage. Consider:

- Adding `gmpw_handles_in_use()` diagnostic function
- Expanding to dynamic allocation if 4096 is insufficient
- Ensuring every code path calls `gmpw_clear()` (RAII via `BigFloat.__del__`)

### 16.6 Build Command Template

The full build command for any GMP-linked Mojo file on macOS:

```bash
pixi run mojo build \
  -Xlinker -L/path/to/temp/gmp -Xlinker -lgmp_wrapper \
  -Xlinker -L/opt/homebrew/lib -Xlinker -lgmp \
  -Xlinker -rpath -Xlinker /path/to/temp/gmp \
  -Xlinker -rpath -Xlinker /opt/homebrew/lib \
  -I src \
  -o output_binary input_file.mojo
```

Key points:

- `-I src` is needed for `from decimo.xxx import ...` to resolve
- Both `-L` (link-time) and `-rpath` (run-time) paths needed for each library
- Build must be run from the project root directory for module resolution
- The binary must be run from the directory containing `libgmp_wrapper.dylib`
  (or use absolute rpath)

### 16.7 Debugging Tip: Add `fprintf(stderr)` to C Wrapper

When debugging FFI issues, temporarily add `fprintf(stderr)` logging to the C wrapper
functions. This is invaluable because Mojo's error reporting for FFI issues is limited.
The C wrapper can inspect raw pointer values, string contents, and GMP internal state
(`handles[h]->_mp_alloc`, `_mp_size`, `_mp_d`) that are invisible from the Mojo side.

Always remove debug logging before benchmarking — `fprintf` has measurable overhead.

## Summary

GMP/MPFR integration is **proven and worth doing** for Decimo. Two-type architecture:

1. **BigFloat** — new first-class MPFR-backed binary float type. Like mpmath's `mpf`
   but faster. Every operation (sqrt, exp, ln, sin, cos, tan, π, divide) is a **single
   MPFR call**. Struct is one field (`handle: Int32`). Requires MPFR — no fallback,
   no apologies. Users without MPFR use BigDecimal.
2. **BigDecimal `gmp=True`** — convenience sugar for one-off acceleration. Internally
   delegates to BigFloat. Backward-compatible: defaults to `gmp=False`, existing code
   unchanged. Guard digits handle binary↔decimal rounding.
3. **Two types, two use cases** — BigFloat for fast scientific computing (binary
   semantics). BigDecimal for exact decimal arithmetic (finance, human-friendly output).
   Both in one library.
4. **Single binary, runtime detection** — C wrapper uses `dlopen`/`dlsym` to load
   MPFR lazily (verified on Mojo 0.26.2). If MPFR isn't installed, BigDecimal works
   fine without it; BigFloat raises a clear error.
5. **BigInt** deferred to Phase 3 (`mpz_t` with word import/export, ~10× speedup).
6. **Future: lazy evaluation** — `BigDecimal.lazy()...collect()` records an operation
   DAG and executes the whole chain in MPFR with zero intermediate conversions.
   Deferred to Phase 4, but architecturally clean because BigFloat provides the backend.
