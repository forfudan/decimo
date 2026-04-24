# Decimal128 Enhancement Plan

> **Date**: 2026-04-08 (created), last consolidated 2026-04-23
> **Target**: decimo >=0.9.0
> **Mojo Version**: >=0.26.2
>
> 子曰：工欲善其事，必先利其器。

This document tracks the Decimal128 audit started on 2026-04-08 and the
performance work that followed. It is the single source of truth for the
arithmetic / parse / format hot-path optimisation effort.

---

## 1. Cross-Language Snapshot

Scope: 128-bit (or near-128-bit) **fixed-precision** decimal types.
Out of scope: arbitrary-precision (`BigDecimal`, Python `Decimal`),
IEEE 754 decimal128 (floating point with NaN/Inf).

| Library               | Layout                               | Max coef  | Digits | NaN/Inf |
| --------------------- | ------------------------------------ | --------- | ------ | ------- |
| **decimo Decimal128** | 96-bit coef (3×UInt32 LE) + 32 flags | 2^96 − 1  | 29\*   | No      |
| C# `System.Decimal`   | identical to decimo                  | 2^96 − 1  | 29\*   | No      |
| Rust `rust_decimal`   | identical to decimo                  | 2^96 − 1  | 29\*   | No      |
| Apache Arrow Dec128   | 128-bit two's-comp signed            | 10^p − 1  | ≤ 38   | No      |
| Go `govalues/decimal` | 64-bit coef                          | 10^19 − 1 | 19     | No      |

\* 29 digits but the leading digit can only be 0–7 (since
`10^29 − 1 > 2^96 − 1`); §6 lists this as an architectural concern.

Arithmetic coverage (decimo vs others): we are the most complete —
the only library with `root`, `log10`, `log` (arbitrary base) and
`factorial`. Missing only `min`/`max`/`clamp` and `normalize()` (§5).

---

## 2. Change History — Done

Dated by report file under `benches/decimal128/reports/`. Every row
corresponds to one landed PR / one bench snapshot. Rows are *append-only*.

### 2.1 Correctness

| Date     | Item                                                                               |
| -------- | ---------------------------------------------------------------------------------- |
| earlier  | NaN/Infinity removed (matches all 4 reference libraries)                           |
| earlier  | `from_words` now raises on invalid input (was `testing.assert_true` in production) |
| 20260423 | `power_of_10_unsafe[uint128]` OOB defence (3 layers; PR #221/#224)                 |
| 20260423 | `multiply` single-step rounding fix (re-round `prod_orig`, not the rounded value)  |

### 2.2 Performance utility

| Date     | Item                                                                                     |
| -------- | ---------------------------------------------------------------------------------------- |
| earlier  | `number_of_bits` → `bit_width` (LLVM `clz` intrinsic)                                    |
| earlier  | `power_of_10` precomputed up to n=58                                                     |
| earlier  | `round_coefficient` with .NET `2*remainder vs divisor` shortcut + `skip_digit_check`     |
| 20260422 | **`debug_assert(..., "msg {}".format(n))` audit** — `.format()` is *not* lazy under      |
|          | `-D ASSERT=none`; eager `String.format` allocates inside hot loops. All sites swept.     |
| 20260422 | `power_of_10[uint128/uint256]` → balanced bisect if/else tree (depth ~5/6)               |
| 20260422 | **Granlund-Möller reciprocal divider** for UInt256 / 10^k (k ∈ [1,29]). 250→6 ns/call.   |
|          | **Critical:** magic constant must use **ceiling** division. Floor failed 17/2000 at k=1. |
| 20260422 | `udiv_u256_by_u64` schoolbook over u64 limbs (~12 ns vs 236 ns native UInt256/UInt256)   |
| 20260422 | `power_of_10_unsafe` swept across 22 hot sites (was `UInt(128 or 256)(10) ** k`)         |

### 2.3 Performance — arithmetic ops

Each row landed one hypothesis (H#x) — see §3 for the validated marginal
value before the fact and §2.4 / §2.5 for end-to-end snapshots.

| Date     | Item                                                                                 |
| -------- | ------------------------------------------------------------------------------------ |
| 20260421 | H#3.1(a) Hoist `same scale` branch above `is_integer()` in `add()`. add 106→5 ns     |
| 20260421 | H#3.1(b) `is_integer()` cheap pre-check `(low & ((1<<scale)-1)) != 0` (still useful  |
|          | for `multiply()` and external callers; removed from `add()` in step (c))             |
| 20260421 | H#3.1(c) Remove `is_integer` branch from `add()` entirely — was net loss even when   |
|          | triggered (dispatch ~250 ns, fall-through ~110 ns). add `Both integer` 121→6 ns      |
| 20260422 | H#4.1 Remove `is_integer` branch from `multiply()` (same logic). 548-759→5-6 ns      |
| 20260422 | `fit_to_max_coefficient` instantiates `round_coefficient[skip_digit_check=True]`     |
| 20260422 | H#11 Hot-path-first single-function `add`/`sub`. Same-scale branch first, zero-with- |
|          | diff-scale routed into the cold tail. add 5→4 ns (dm/rs 2.1→1.3)                     |
| 20260422 | H#3 `subtract()` diff-scale arm fully inlined (no `add(x1, negative(x2))` detour);   |
|          | `@always_inline` on `multiply()`. sub `diff scale` 12→10 ns                          |
| 20260422 | H#5 `divide()` two-phase: probe loop (≤2 iters) + `udiv_u256_by_u64` bulk finish +   |
|          | bisect-style trailing-zero trim. divide max **287→56 ns**                            |
| 20260422 | H#14 `power_of_10_unsafe` sweep + `from_uint128` `@always_inline` with `raises`      |
|          | extracted into `@no_inline` helpers. add dm/rs 1.2→0.8; divide dm/rs 2.2→1.0         |

### 2.4 Performance — comparison / format / parse (this PR)

| Date     | Item                                                                                 |
| -------- | ------------------------------------------------------------------------------------ |
| 20260423 | **`compare_absolute` rewrite.** Same-scale → direct UInt128 compare. Different scale |
|          | → scale-up smaller side and compare (UInt128 if scale_diff ≤ 9, else UInt256).       |
|          | Eliminates 2 `number_of_digits` + 4 `power_of_10_unsafe` + 2 wide div + 2 wide mod   |
|          | per call. Worst case 13.6 → 3.8 ns.                                                  |
| 20260423 | **`to_str` / `write_to` rewrite.** `write_to` now contains all formatting; `to_str`  |
|          | is a thin wrapper. Digits extracted into a 32-byte `InlineArray` right-aligned via   |
|          | 9-digit chunks (UInt128 // 10^9 outer + UInt32 // 10 inner). One `StringSlice` write |
|          | per logical span. Median 0.4× rust, worst case ~1.1× rust.                           |
| 20260423 | **`multiply` single-pass rounding.** When `prod > MAX_AS_UINT128` *or*               |
|          | `combined_scale > MAX_SCALE`, compute `drop = max(drop_for_fit, drop_for_scale)` in  |
|          | one shot and call `round_coefficient` once. Replaces the old two-pass                |
|          | `fit_to_max_coefficient` + re-round pattern. Saves ~5 ns + one wide divide. Applied  |
|          | to both `combined_num_bits ≤ 128` and `≤ 192` branches. **`High precision multiply`  |
|          | 19 → 13 ns.**                                                                        |
| 20260423 | **`from_string` parser.** (a) Drop the separate non-ASCII pre-scan loop (folded into |
|          | the `else` arm). (b) Reorder the per-byte switch so the digit branch (48–57) comes   |
|          | first. (c) Merge the separate '0' and '1–9' branches into one. **Long integer        |
|          | 41 → 22 ns; Long fractional 71 → 46 ns; Maximum coefficient 64 → 36 ns.**            |
| 20260423 | **`str.parse_numeric_string` lessons backport (H#18).** Extracted the `.format()`-   |
|          | bearing invalid-character raise into a `@no_inline` helper (Lesson #4) and added the |
|          | non-ASCII byte diagnostic from `Decimal128.from_string` (raw byte hex + original     |
|          | input — `chr()` of a UTF-8 lead/continuation byte is garbled). No behaviour change   |
|          | for valid inputs; cleaner error messages for invalid ones; smaller hot-loop body for |
|          | the BigInt/BigUInt/BigDecimal callers. **Consolidation rejected — see H#18.**        |
| 20260423 | **Decimal128.from_string invalid-char raise extraction (Lesson #4 sweep).** The two  |
|          | `String.format(...)` raises in the `else` arm of `from_string`'s per-byte switch     |
|          | were inline. Moved into a `@no_inline _raise_from_string_invalid_char` static helper |
|          | alongside the existing `_raise_from_uint128_*` helpers. Kept local to Decimal128 to  |
|          | preserve `function="Decimal128.from_string()"` attribution without paying a string-  |
|          | parameter overhead.                                                                  |
| 20260423 | **BigDecimal `from_string` test coverage.** Added `bigdecimal_from_string.toml` (47  |
|          | cases across 8 sections: integers, decimals, negatives, zeros, scientific, format    |
|          | variants, separators/slow-path, boundary) + a TOML-driven runner and a dedicated     |
|          | `test_bigdecimal_from_string_invalid_inputs` covering every reject arm.              |
| 20260423 | **`BigDecimal.from_python_decimal` signed/scaled-zero fix.** The zero short-circuit  |
|          | hardcoded `sign=False, scale=0`, dropping both pieces of significant information per |
|          | IEEE 754-2008 / IBM GDA. Now propagates `sign` and `-exponent` from Python's         |
|          | `as_tuple()`, so `Decimal("-0")` round-trips to `"-0"` and `Decimal("-0.00")` to     |
|          | `"-0.00"`, matching `BigDecimal.from_string` and Python's own behaviour.             |
| 20260423 | **`Decimal128` integer-part / sign API parity** (P2 of §5.2 closed). Added six       |
|          | methods to bring Decimal128 to parity with `rust_decimal::Decimal` and               |
|          | `System.Decimal`: `trunc()` (round toward zero), `floor()` (round toward -∞),        |
|          | `ceil()` (round toward +∞), `fract()` (= `self - self.trunc()`, sign- and            |
|          | scale-preserving), `signum()` (returns Decimal128 ±1/0), and `unpack()` (returns     |
|          | `(low, mid, high, scale, sign)` tuple matching `Decimal.GetBits` / Rust              |
|          | `UnpackedDecimal`). All `@always_inline`, dispatching to `rounding.round` with       |
|          | the appropriate `RoundingMode`. 23 new tests in                                      |
|          | `tests/decimal128/test_decimal128_integer_part.mojo` cover signed-zero               |
|          | preservation, fract round-trip identity (`trunc(x)+fract(x)≡x`), boundary            |
|          | values, and the high-word path of `unpack`.                                          |
| 20260423 | **IEEE 754 preferred-exponent regression tests** (§6.0 closed). Added                |
|          | `tests/decimal128/test_decimal128_preferred_exp.mojo` (7 cases) pinning the          |
|          | three disputed cases vs rust_decimal: `123.45 × 0 → "0.00"`, `10.5 / 2.5 → "4.2"`,   |
|          | `123.45 / -2 → "-61.725"`, plus zero-with-various-scales and ideal-exponent          |
|          | rules per IEEE 754-2008 §3.3 / IBM GDA §4.1.                                         |

### 2.5 Performance tracking — absolute decimo median ns/iter

Lower = faster. Numbers come from `benches/decimal128/run_all.sh`
(best-of-5, `-D ASSERT=none`). Append-only.

| Date     |  add |  sub |  mul |  div |  cmp | from_str | to_str | note                                               |
| -------- | ---: | ---: | ---: | ---: | ---: | -------: | -----: | -------------------------------------------------- |
| 20260421 |  106 |  123 |    4 |    8 |    0 |    24.25 | 128.30 | Before any optimisations (cmp inaccurate)          |
| 20260421 |    5 |    6 |    4 |    8 | 2.10 |    24.15 | 127.00 | After H#3.1 add reorder                            |
| 20260421 |    5 |  6.5 |    6 |    9 | 2.10 |    21.80 | 129.60 | After H#3.1 is_integer removed from add            |
| 20260422 |    5 |    7 |    5 |    8 | 2.10 |    23.10 | 124.30 | After H#4.1 is_integer removed from mul            |
| 20260422 |    5 |    6 |    5 |    8 | 2.10 |    22.65 | 136.00 | After Granlund-Möller UInt256 / 10^k               |
| 20260422 |    4 |    4 |    5 |    9 | 2.10 |    25.20 | 119.20 | After H#3 sub diff-scale inlined + mul ais         |
| 20260422 |    4 |    4 |    4 |    8 | 2.10 |    26.00 |  82.70 | After H#5 divide two-phase                         |
| 20260422 |    3 |    3 |    4 |    6 | 2.00 |    23.30 | 122.40 | After H#14 power_of_10_unsafe sweep + from_uint128 |
| 20260423 |  3.5 |    2 |  3.5 |    5 |  3.2 |    14.05 |  16.60 | After §2.4 (compare/write_to/multiply/from_string) |

### 2.6 Performance tracking — worst-case (max across cases) ns/iter

| Date     |  add |  sub |  mul |  div |  cmp | from_str | to_str | note                                           |
| -------- | ---: | ---: | ---: | ---: | ---: | -------: | -----: | ---------------------------------------------- |
| 20260421 |  121 |  121 |  500 |  359 | 18.1 |   177.60 | 586.70 | After H#3.1 add reorder                        |
| 20260422 |   17 |   16 |  262 |  307 | 19.8 |    68.40 | 577.90 | After debug_assert .format sweep + bisect tree |
| 20260422 |   14 |   15 |   22 |  257 | 17.4 |    65.30 | 554.50 | After Granlund-Möller                          |
| 20260422 |   13 |   14 |   25 |   45 | 18.0 |    67.60 | 583.70 | After H#14                                     |
| 20260423 |    5 |    4 |   23 |   54 |  4.2 |    46.20 |  83.30 | After §2.4                                     |

### 2.7 Performance tracking — decimo / rust ratio (>1 = decimo slower)

| Date     |   add |   sub |  mul |  div |  cmp | from_str | to_str |
| -------- | ----: | ----: | ---: | ---: | ---: | -------: | -----: |
| 20260421 | 21.2x | 61.5x | 1.6x | 1.4x | 0.0x |     2.6x |   3.6x |
| 20260422 |  0.8x |  1.3x | 1.7x | 1.0x | 0.8x |     1.4x |   3.4x |
| 20260423 |  1.2x |  0.8x | 1.5x | 0.9x | 1.2x |     1.4x |   0.4x |

The 20260423 row reflects the post-§2.4 cross-op overview from
`dec128_report_20260423_145648.md`. **All medians ≤ 1.5× rust.** The
worst-case "≤ 1.5×" target is met for `add`, `sub`, `cmp`, `to_str`. It
is missed on the long tail of `multiply` (worst 2.0×, e.g. `High precision`
13 vs 6.46 ns), `divide` (worst 3.9×, `Repeating decimal` 47 vs 12.12 ns),
and `from_string` (worst 2.1×, `Long integer` 24.7 vs 11.5 ns). Closing
those last gaps requires deeper algorithmic work (see §5.4).

---

## 3. Hypothesis Ledger

Marginal-value ranking from the original §4.9 decomposition, kept for
context. All P1/P2 items have landed; P3 items are tracked in §5.

| H#  | Hypothesis                                                 | Outcome                                                                                               |
| --- | ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| 1   | `coefficient()` reconstructs UInt128 each call             | DISPROVEN — already `@always_inline` bitcast (~0 ns)                                                  |
| 2   | `def raises` calling-convention overhead                   | DONE — kept `def raises`, hot-path-first ordering captured the win (H#11)                             |
| 3   | UInt256 promotion in `add` when scales differ              | DONE — `subtract` diff-scale fully inlined                                                            |
| 3.1 | `is_integer()` ×2 wastes UInt128 mod                       | DONE — three-step landing 21→2.1 ns                                                                   |
| 4   | UInt256 promotion in `mul` when product fits UInt128       | DEPRIORITISED — bench cases all have `combined_num_bits ≥ 186`, mandatory UInt256                     |
| 4.1 | `is_integer` branch in `multiply()`                        | DONE — removed; 548→5 ns on `Both integer`                                                            |
| 5   | divide long-division loop                                  | DONE — two-phase probe + UInt256/u64 schoolbook                                                       |
| 6   | `to_string` per-call allocation                            | DONE (this PR) — `write_to` writes digits via 32-byte `InlineArray` + single `StringSlice`            |
| 7   | bitcast 4×UInt32 → single UInt128 in `coefficient()`       | DISPROVEN                                                                                             |
| 8   | `from_uint128()` raises overhead                           | DISPROVEN initially, but H#14 found it once `from_uint128` is `@always_inline`                        |
| 9   | Power-of-10 LUT vs if/elif tree                            | LANDED bisect tree; LUT regressed when `debug_assert .format` was eager                               |
| 10  | Granlund-Möller reciprocal for `UInt256 / 10^k`            | DONE — 250→6 ns                                                                                       |
| 11  | Hot-path-first single-function `add` / `sub`               | DONE — add 5→4 ns                                                                                     |
| 12  | `subtract` diff-scale: inline vs `add(x1, negative(x2))`   | DONE — saves ~3 ns / op                                                                               |
| 13  | divide two-phase: probe + bulk finish                      | DONE — divide max 287→56 ns                                                                           |
| 14  | `power_of_10_unsafe` sweep + `from_uint128` always-inline  | DONE — divide median 8→6 ns; raises extracted to `@no_inline` helpers                                 |
| 15  | `compare_absolute` rewrite                                 | DONE (this PR) — worst case 13.6→3.8 ns                                                               |
| 16  | `multiply` single-pass rounding (saves second wide divide) | DONE (this PR) — High-precision 19→13 ns                                                              |
| 17  | `from_string` per-byte switch reorder + branch merge       | DONE (this PR) — Long integer 41→22 ns                                                                |
| 18  | `Decimal128.from_string` call `str.parse_numeric_string`   | DISPROVEN — Output-shape mismatch: `parse_numeric_string` returns `List[UInt8]` digit bytes           |
|     |                                                            | (right for arbitrary-precision `BigInt`/`BigUInt`/`BigDecimal`), `Decimal128.from_string` accumulates |
|     |                                                            | straight into `UInt128` in-loop. Routing Decimal128 through the shared parser would add               |
|     |                                                            | (a) one heap allocation per call and (b) a second loop to fold the digit bytes into `UInt128`         |
|     |                                                            | — directly fighting the §5.1 P2 follow-up (digit batching → ~14 ns target).                           |
|     |                                                            | Cross-checked: the two parsers already converged on the same per-byte switch ordering,                |
|     |                                                            | the same separator-handling, and the same EBNF in §17. **Lessons backported instead** (see §2.4):     |
|     |                                                            | non-ASCII byte diagnostic + `@no_inline` raise helpers folded into `str.parse_numeric_string`.        |

---

## 4. Lessons Learnt (the reusable bits)

1. **`debug_assert` does NOT lazy-evaluate its message argument** under
   `-D ASSERT=none`. `String.format` allocates and runs inside the hot
   loop anyway. Use plain string literals only. Filed as a Mojo-team
   reproducer: `/tmp/repro_debug_assert_format.mojo`.

2. **`urem` lowers to `sub(a, mul(udiv, b))` and CSE-deduplicates with
   the explicit `// + %`.** Writing `q = a // b; r = a - q*b` gives
   the compiler nothing extra and adds source noise. Confirmed at the
   ARM64 asm level. Use the natural `// + %` form.

3. **Branches that test a non-trivial predicate to skip a moderately-
   priced fall-through are often anti-optimisations.** Always measure
   the dispatch cost separately from the body cost. The `is_integer`
   branches in `add()` and `multiply()` were both net losses *even when
   triggered*.

4. **For raises functions on the hot path, extract each `raise ... .format(...)`
   into a `@no_inline` helper.** Lets `@always_inline` actually fire.
   `from_uint128` benefited the most.

5. **Granlund-Möller needs ceiling division** for the magic constant
   `mp = ⌈2^(N+ℓ)/d⌉ − 2^N`. Floor failed 17/2000 random tests at k=1.

6. **When LLVM lowers wide-integer division to a software loop and the
   divisor is one of a small fixed set of compile-time constants, a
   reciprocal table is the right answer** — but verify against the
   native divide on a randomised sweep across the entire k range.

7. **The count of branches before the fast arm matters more than the
   body of the fast arm.** A 6-arm linear scan makes even the cheapest
   arm pay for the predicates of every prior arm. Hot path first; rare
   cases routed to the cold tail of the same function.

8. **Helper-function decomposition costs ~1 ns over a well-ordered
   monolith.** Reserve helpers for genuinely shared code paths, not
   for rhetorical "decomposition".

9. **`from_string`-style state-machine parsers benefit hugely from
   reordering the per-byte switch so the digit branch comes first.**
   Two-pass scans (e.g. a separate pre-pass for non-ASCII) should be
   folded into the main loop's `else` arm.

10. **For `to_string`, build the digit buffer right-aligned in a fixed
    `InlineArray` and emit via a single `StringSlice`.** Avoid per-byte
    `writer.write` calls and avoid an intermediate `String` builder.

11. **For multi-pass rounding, compute the total drop count in one shot
    when both constraints are independent (e.g. coefficient-fits and
    scale-fits in `multiply`).** The boundary case (round-up carries
    past `MAX_COEF`) is handled by a single `if rounded > MAX: drop +=
    1; round again` — and the re-round must use the **original** value,
    not the already-rounded one (subtle bug introduced and fixed in this
    PR for the UInt256 branch).

---

## 5. Open Items / Future Improvements

### 5.1 Worst-case ratios still > 1.5× rust

These are the residual gaps after this PR. Each requires algorithmic
work, not micro-optimisation.

| Op       | Worst case                      | decimo |  rust | dm/rs | Likely root cause                                                                                            |
| -------- | ------------------------------- | -----: | ----: | ----: | ------------------------------------------------------------------------------------------------------------ |
| multiply | High precision multiplication   |   13.0 |  6.50 |  2.0× | UInt128 path: 17×17-digit prod, mandatory `round_coefficient` work                                           |
| multiply | Multiplication by zero          |    4.0 |  1.38 |  2.9× | Per-call dispatch overhead (raises + special-case tree)                                                      |
| multiply | Negative numbers                |    4.0 |  1.08 |  3.7× | Same                                                                                                         |
| multiply | e * e^0.5                       |   23.0 | 27.79 |  0.8× | UInt256 path; *faster* than rust                                                                             |
| divide   | Division with repeating decimal |   47.0 | 12.12 |  3.9× | Rust uses a `div_internal` magic-multiply trick; decimo's two-phase loop still pays 28 digits' worth of bulk |
| divide   | High precision division         |   48.0 | 19.21 |  2.5× | Same                                                                                                         |
| divide   | Large coprime quotient          |   43.0 | 16.88 |  2.5× | Same                                                                                                         |
| from_str | Long integer part (20 digits)   |   24.7 | 11.52 |  2.1× | UInt128 multiply-by-10 per digit; could batch into u64 chunks                                                |
| from_str | Long fractional (28 digits)     |   46.2 | 27.12 |  1.7× | Same                                                                                                         |
| from_str | Zero value                      |    4.3 |  1.79 |  2.4× | Per-call dispatch; rust has a 2-byte fast path                                                               |

**Possible follow-ups** (none committed):

- *divide* (highest impact): adopt rust_decimal's reciprocal-multiplication
  approach. Pre-compute reciprocals of common divisors or use a single
  hardware `__udivti3` + correction, instead of the per-digit loop.
- *from_string*: digit batching — accumulate up to 19 digits in a `UInt64`,
  then `coef = coef * 10^k + batch` once per chunk. ~5–7× reduction on the
  inner-loop multiplies. Targeted estimate: 24 → ~14 ns on `Long integer`.
- *multiply per-call dispatch*: collapse the 6-way special-case tree into
  3 branches (zero short-circuit, integer fast path, general). Risk:
  regressions on the cases the dispatch was added for.

### 5.2 API gaps vs `rust_decimal`

Landed 2026-04-23: `trunc`, `floor`, `ceil`, `fract`, `signum`, `unpack`
(see §2.4). Still tracked:

- `min` / `max` / `clamp`
- `normalize()` (strip trailing zeros)
- `__hash__` (depends on `normalize`)

### 5.3 `ln()` / `log10()` range reduction

`ln()` reduces input to `[0.5, 2.0)` via two while-loops; for `ln(1e28)`
that's ~30 full Decimal128 divisions. Use `ln(a × 10^q) = ln(a) + q × ln(10)`
to read `q` directly from the input scale. Bit-width can collapse the second
loop similarly. Expected: ~30 divs → 1 scale-fix + 1 div.

Before working on this, we should first create benchmarking tests for `ln()`,
`ln10()`, `exp()`, etc against other implementations to verify the current 
behavior and track improvements.

### 5.4 Test-suite latency

Two factors dominate. `-D ASSERT=all --debug-level=full` is 5–7× slower
than release; per-file JIT adds ~0.5–1 s of fixed cost × 17 files.

No need to change anything. Safety is over speed.

### 5.5 Architectural: 96-bit coefficient → 32-digit decimal-bounded

The `2^96 − 1` upper bound has a non-clean decimal boundary (29 digits
but leading digit only 0–7). A future major release could repurpose 5
unused bits in the flags word to extend the coefficient to `10^32 − 1`,
unifying the digit semantics.

Pros: cleaner API (32 digits, no weird leading-digit constraint), less mental
burden on users to judge when they're hitting the coefficient limit,
no complex rounding logic to handle the 29-digit edge case, wider range.

Cons: completely different API shape (four raw words instead of three + flags),
imcompatible with .NET and rust_decimal, more complex implementation (101-bit
coefficient arithmetic instead of 96-bit).

It is a long-term proposal; not on the active roadmap.

See git history (pre-2026-04-23) for the full analysis.

---

## 6. Result-Equivalence vs `rust_decimal` / .NET (3 vs 1 verdict)

The cross-language harness flags trailing-zero / scale-string differences
in `multiply` and `divide`. On every disputed case **decimo, C# and
VB.NET `System.Decimal` agree** against `rust_decimal`:

| op       | inputs        | decimo / .NET | rust_decimal | Verdict                                                                                           |
| -------- | ------------- | ------------- | ------------ | ------------------------------------------------------------------------------------------------- |
| multiply | `123.45 × 0`  | `0.00`        | `0`          | **decimo + .NET correct.** `exp(0×X) = exp(a)+exp(b) = -2`, so `0` at exp `-2` is `0.00`.         |
| divide   | `10.5 / 2.5`  | `4.2`         | `4.20`       | Ideal exponent for divide = `exp(a)−exp(b) = 0`; `4.2` (exact at exp `-1`) preferred over `4.20`. |
| divide   | `123.45 / -2` | `-61.725`     | `-61.7250`   | Exact result needs exp `-3`; ideal exp `-2` would require fractional coef.                        |

decimo follows IEEE 754-2008 §3.3 (preferred exponent) and the IBM
General Decimal Arithmetic spec §4.1, matching .NET BCL. `rust_decimal`
is the lone outlier among the four references surveyed. **No
remediation needed on the decimo side.**

Regression coverage: `tests/decimal128/test_decimal128_preferred_exp.mojo`
pins all three cases plus zero-with-various-scales and ideal-exponent
rules (landed 2026-04-23). User-manual note added the same day under
Part II → "A note on result exponents (`Decimal` and `Dec128`)".

---

## 7. Priority Summary

Open items, in priority order:

| #   | Issue                                             | Effort  | Priority |
| --- | ------------------------------------------------- | ------- | -------- |
| 5.1 | divide repeating-decimal long tail (47 → ≤ 19 ns) | Large   | P1       |
| 5.1 | from_string digit batching                        | Medium  | P2       |
| 5.3 | `ln()` range reduction loops                      | Medium  | P2       |
| 5.2 | `min`/`max`/`clamp`                               | Trivial | P3       |
| 5.2 | `normalize()`                                     | Small   | P3       |
| 5.2 | `__hash__` (depends on `normalize()`)             | Small   | P3       |
| 5.5 | Steal flag bits → 32-digit coefficient            | Large   | P4       |
