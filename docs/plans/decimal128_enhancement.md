# Decimal128 Enhancement Plan

> **Date**: 2026-04-08 (created), last consolidated 2026-04-23
> **Target**: decimo >=0.9.0
> **Mojo Version**: >=0.26.2
<!-- > **Status**: Fully executed as of 2026-05-04 -->
>
> 子曰：工欲善其事，必先利其器。
> Confucius said: If a craftsman wants to do good work, he must first sharpen his tools.

This document tracks the Decimal128 audit started on 2026-04-08 and the
performance work that followed. It is the single source of truth for the
arithmetic / parse / format hot-path optimisation effort.

<!-- This plan has been fully executed as of 2026-05-04 (PR #239). -->

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
`factorial`. As of 2026-05-03 the API is at parity with `rust_decimal`,
`System.Decimal`, and Python `Decimal` for the introspection / canonical
surface (`normalize`, `same_quantum`, `adjusted`, `compare_total`,
`is_signed`, `canonical`, `is_canonical`) — see §2.4 (20260503).

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

### 2.4 Performance — comparison / format / parse

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
| 20260427 | **`Decimal128.min` / `max` / `clamp`** (P3 of §5.2). Added free functions in         |
|          | `comparison.mojo` and `@always_inline` methods on `Decimal128`. `max(a,b)` /         |
|          | `min(a,b)` return the first argument on tie (preserving its scale, matching          |
|          | rust_decimal `Ord::max` / `min`). `clamp(x, lower, upper)` raises if                 |
|          | `lower > upper`. 8 new tests in `test_decimal128_comparison.mojo` cover              |
|          | positives/negatives, tie-preserves-scale, signed zeros, in-range / below /           |
|          | above / boundary clamps, and invalid-bounds raise.                                   |
| 20260502 | **`divide` long-division refactor (P1 of §5.1).** Three independent changes in the   |
|          | UInt128 sub-case: (a) dropped the `+1` rounding-digit padding from `max_steps`, so   |
|          | the long division produces exactly the final coefficient and the post-divide         |
|          | `round_coefficient` overflow fix-up is no longer triggered for results that fit      |
|          | `MAX_AS_UINT128`; (b) replaced the `UInt256` `combined = quot * 10^k + quot_added`   |
|          | fold with a `UInt128` multiply (post-bulk total digits ≤ 29 → < 2^97 fits UInt128);  |
|          | (c) replaced the OLD "+1 padding then `round_coefficient` (banker's) with override   |
|          | `if digit == 5 and rem != 0: quot += 1`" pattern with a direct three-branch          |
|          | banker's test on the residual rem (`2*rem > x2`/`==`/`<`), eliminating the wide      |
|          | divide that `round_coefficient` performed at the boundary. Behaviour preserved:      |
|          | banker's (round-half-to-even) at exact half; round-up at "5 with non-zero tail"      |
|          | (mathematically > half, not a banker's tie). Added `test_divide_bankers_rounding_at` |
|          | `_boundary` (5 cases) pinning all four arms (even-keeps, odd-bumps, 5+tail,          |
|          | below-half) cross-checked against Python `decimal` ROUND_HALF_EVEN. Bench best-of-3  |
|          | UInt128 path: `Repeating decimal` 47 → 36 ns, `High precision division` 47–61 →      |
|          | 33–39 ns, `Large coprime quotient` 42–54 → 29–35 ns. UInt256 sub-case unchanged.     |
|          | Negative results explored same day (none landed): (i) chunked-9 UInt128/UInt128      |
|          | divide replacing the bulk UInt256 path regressed +10–15 ns because aarch64           |
|          | UInt128/UInt128 falls back to libgcc `__udivti3` (~30 ns) vs the existing            |
|          | `udiv_u256_by_u64`'s 4× hardware-favored u128/u64 divides; (ii) manually splitting   |
|          | the probe-loop `// + %` into one divide + multiply-subtract regressed +4–5 ns        |
|          | because LLVM already CSE-deduplicates `// + %` to a single `__udivmodti4`            |
|          | (verified by bench, matches the existing UInt256-loop comment); (iii) full           |
|          | rust_decimal `partial_divide_64`-style port is the only remaining algorithmic        |
|          | win but requires Granlund-Möller shift-normalize that Mojo cannot express            |
|          | without inline asm or LLVM intrinsics, deferred to §7 P2.                            |
| 20260503 | **`from_string` digit batching — DISPROVEN.** Implemented the §5.1 follow-up         |
|          | (BATCH_CAP=19, accumulate up to 19 digits in a `UInt64`, fold once per chunk via     |
|          | `coef = coef * 10^k + batch`). Best-of-3 bench: `Long integer (20 digits)`           |
|          | 24.7 → 28.5 ns (+15%); `Long fractional (28 digits)` 46.2 → 52.3 ns (+13%). Both     |
|          | regressed. Root cause: LLVM already lowers `coef * 10` for `UInt128` to a tight      |
|          | shift-add (`(c << 3) + (c << 1)`), so the per-digit multiply is essentially free;    |
|          | the batching adds a per-iteration `batch_size` branch + a wide `power_of_10_unsafe`  |
|          | lookup + a flush-time `UInt128 × UInt128` (lowered to `__multi3`) that exceed the    |
|          | savings. A literal-`10^19` constant variant (skip the lookup) measured the same.     |
|          | **Reverted; removed from §7 priority list.** Lesson #12 added.                       |
| 20260503 | **`Decimal128` canonicalisation / introspection API parity** (§5.2 closed). Added    |
|          | seven methods to bring Decimal128 to parity with `rust_decimal::Decimal`,            |
|          | `System.Decimal`, and Python `Decimal` for the canonicalisation surface:             |
|          | `normalize()` (strip trailing zeros; collapses every zero representation to          |
|          | `Decimal128.ZERO()` so the hash/eq contract holds), `__hash__` (Hashable             |
|          | conformance — hashes the *normalised* `(sign, coef, scale)` triple so                |
|          | `1.0 == 1.00 == True ⇒ hash(1.0) == hash(1.00)`), `same_quantum()` (compare scale    |
|          | only, IBM GDA §5.5.10), `adjusted()` (= `n_digits - 1 - scale`, IBM GDA              |
|          | §5.5.2), `compare_total()` (IBM GDA §5.5.13 total ordering — for positives lower     |
|          | scale precedes higher; for negatives higher scale precedes lower so the global       |
|          | sequence stays monotonic across the sign change), `is_signed()` (alias of            |
|          | `is_negative()` for Python-API compatibility), `canonical()` / `is_canonical()`      |
|          | (identity / always-True — Decimal128 has no non-canonical encoding). `normalize()`   |
|          | uses a 9-digit chunk pre-pass via `power_of_10_unsafe[uint128](9)` then a 1-digit    |
|          | tail loop; both rely on LLVM's CSE of `// + %` to one `__udivmodti4` (Lesson #2).    |
|          | All `@always_inline` except `normalize` and `__hash__`. `compare_total` lives in     |
|          | `comparison.mojo` as a free function (alongside `compare`, `min`, `max`, `clamp`);   |
|          | the `Decimal128.compare_total` method is an `@always_inline` thin wrapper. The       |
|          | dual-zero branch is handled *before* delegating to `compare()` because `compare()`   |
|          | collapses every zero (`{-0,+0} × scale`) into a single equivalence class, which      |
|          | would break the strict-total-order contract; the free function orders by sign first  |
|          | (`-0 < +0`) then by scale (rule 3). 30 new tests appended to                         |
|          | `tests/decimal128/test_decimal128_methods.mojo` cover the hash/eq contract           |
|          | (incl. signed-zero and  scaled-zero collapse), the chunk-boundary strip path,        |
|          | signed-zero ordering under `compare_total`, the cross-sign monotonicity of scaled    |
|          | zeros, and adjusted / signed / canonical edges.                                      |
| 20260503 | **`exp()` 2-tier sub-unit chunk constants — §5.3 follow-up landed.** Added 17 new    |
|          | precomputed `e^k` constants: per-tenth `E0D1`…`E0D9` (skipping `E0D5` which already  |
|          | existed) and per-hundredth `E0D01`…`E0D09`. All at 28 fractional digits, generated   |
|          | via Python `decimal` Taylor at `prec=50`; the script's `E0D5` output reproduces      |
|          | the existing `E0D5` constant byte-for-byte (validates the encoding pipeline).        |
|          | Rewrote the `x_int < 1` arm of `exp()` as a 2-tier chunker: tier 1 peels off         |
|          | `d1 = Int(x*10) ∈ [0, 9]` and applies `E0D{d1}`; if `d1 == 0` (i.e. `x < 0.1`) we    |
|          | drop into tier 2 which peels off `d2 = Int(x*100) ∈ [0, 9]` and applies              |
|          | `E0D0{d2}`. The final residual lands in `[0, 0.01)` (instead of the old              |
|          | `[0, 0.25)`), so Taylor converges in ~5 terms instead of ~17. `d == 0` at any tier   |
|          | short-circuits the chunk multiply. **The 2-tier design improves both speed *and*     |
|          | accuracy** (precision was the explicit goal for tier 2): every saved Taylor          |
|          | multiply also avoids ~0.5 ulp of truncation, so the speed gain translates directly   |
|          | to ulp gain. Numbers (decimo, median ns/iter; ulps off BigDecimal reference):        |
|          | - `exp(π)`:    1350 → **770 ns** (1.75×); 3 ulp → **1 ulp**.                         |
|          | - `exp(typical)` (= e^1.234…): 960 → **725 ns** (1.32×); 4 ulp → **2 ulp**.          |
|          | - `exp(0.1)`, `exp(0.5)`, `exp(2)`, `exp(5)`, `exp(10)`, `exp(66)`: unchanged at     |
|          | 25 / 25 / 15 / 10 / 15 / 70 ns and 0 ulp.                                            |
|          | - `exp(50)`: 80 ns / 2 ulp (integer-only path; no fractional chunking applies —      |
|          | a smaller follow-up could precompute `E33`…`E66` to land it at 0 ulp).               |
|          |                                                                                      |
|          | All 9 decimal128 test files green under `-D ASSERT=all --debug-level=full`           |
|          | (182 tests). `M0D5` / `M0D25` / `E0D25` kept (still imported elsewhere or            |
|          | symmetric with the new layer). Reading `d1`/`d2` directly from the coefficient       |
|          | (skipping the two `Decimal128 × N` multiplies in the chunkers) is a possible         |
|          | micro-follow-up that would shave a few more ns but was left as future work.          |

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
| 6   | `to_string` per-call allocation                            | DONE — `write_to` writes digits via 32-byte `InlineArray` + single `StringSlice`                      |
| 7   | bitcast 4×UInt32 → single UInt128 in `coefficient()`       | DISPROVEN                                                                                             |
| 8   | `from_uint128()` raises overhead                           | DISPROVEN initially, but H#14 found it once `from_uint128` is `@always_inline`                        |
| 9   | Power-of-10 LUT vs if/elif tree                            | LANDED bisect tree; LUT regressed when `debug_assert .format` was eager                               |
| 10  | Granlund-Möller reciprocal for `UInt256 / 10^k`            | DONE — 250→6 ns                                                                                       |
| 11  | Hot-path-first single-function `add` / `sub`               | DONE — add 5→4 ns                                                                                     |
| 12  | `subtract` diff-scale: inline vs `add(x1, negative(x2))`   | DONE — saves ~3 ns / op                                                                               |
| 13  | divide two-phase: probe + bulk finish                      | DONE — divide max 287→56 ns                                                                           |
| 14  | `power_of_10_unsafe` sweep + `from_uint128` always-inline  | DONE — divide median 8→6 ns; raises extracted to `@no_inline` helpers                                 |
| 15  | `compare_absolute` rewrite                                 | DONE — worst case 13.6→3.8 ns                                                                         |
| 16  | `multiply` single-pass rounding (saves second wide divide) | DONE — High-precision 19→13 ns                                                                        |
| 17  | `from_string` per-byte switch reorder + branch merge       | DONE — Long integer 41→22 ns                                                                          |
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

12. **Don't batch into a `UInt64` accumulator on the assumption that a
    `UInt128 * 10` per-digit multiply is expensive.** LLVM lowers
    `UInt128 * 10` to a shift-add (`(c << 3) + (c << 1)`); the batch's
    flush-time `UInt128 × UInt64` (lowered to `__multi3`) plus the
    per-iteration `batch_size` branch and the wide `power_of_10_unsafe`
    table lookup *exceed* the saving. Confirmed 2026-05-03 on the
    `from_string` parser: `Long integer` regressed 24.7 → 28.5 ns. Always
    measure batching against the natural per-element loop on the target
    architecture before adopting.

---

## 5. Open Items / Future Improvements

### 5.1 Worst-case ratios still > 1.5× rust

These are the residual gaps. Each requires algorithmic work, not 
micro-optimisation.

| Op          | Worst case                    | decimo |  rust | dm/rs | Likely root cause                                                       |
| ----------- | ----------------------------- | -----: | ----: | ----: | ----------------------------------------------------------------------- |
| multiply    | High precision mul            |   13.0 |  6.50 |  2.0× | UInt128 path: 17×17-digit prod, mandatory `round_coefficient` work      |
| multiply    | Multiplication by zero        |    4.0 |  1.38 |  2.9× | Per-call dispatch overhead (raises + special-case tree)                 |
| multiply    | Negative numbers              |    4.0 |  1.08 |  3.7× | Same                                                                    |
| multiply    | e * e^0.5                     |   23.0 | 27.79 |  0.8× | UInt256 path; *faster* than rust                                        |
| divide      | Div with repeating decimal    |   36.0 | 12.04 |  3.0× | One bulk wide-divide + post-divide overhead. After 20260502             |
|             |                               |        |       |       | refactor (§2.4); rust_decimal still uses a `div_internal` magic-        |
|             |                               |        |       |       | multiply trick. Closing the rest needs reciprocal multiplication.       |
| divide      | High precision division       |   37.0 | 18.67 |  2.0× | Same                                                                    |
| divide      | Large coprime quotient        |   30.0 | 16.67 |  1.8× | Same                                                                    |
| from_string | Long integer part (20 digits) |   24.7 | 11.52 |  2.1× | UInt128 multiply-by-10 per digit. Batching disproven 2026-05-03 (§2.4). |
| from_string | Long fractional (28 digits)   |   46.2 | 27.12 |  1.7× | Same                                                                    |
| from_string | Zero value                    |    4.3 |  1.79 |  2.4× | Per-call dispatch; rust has a 2-byte fast path                          |

**Possible follow-ups** (none committed):

- *divide* — REJECTED 2026-05-02. Adopting rust_decimal's
  reciprocal-multiplication / `partial_divide_64` approach was
  investigated and rejected: the win in rust comes from inlined
  shift-normalize Granlund-Möller code that LLVM emits for u128/u64,
  which Mojo cannot express in pure source (the `UInt128/UInt128`
  operator lowers through libgcc `__udivti3` regardless). All explored
  pure-Mojo variants (chunked-9, manual divmod split) regressed; see
  the 2026-05-02 §2.4 entry for measurements. Revisit only if Mojo
  gains inline-asm or a dedicated `divrem_2by1` intrinsic.
- *from_string*: digit batching — REJECTED 2026-05-03. Implemented
  with `BATCH_CAP = 19` (accumulate up to 19 digits in a `UInt64`, fold
  once per chunk via `coef = coef * 10^k + batch`); both the variable-k
  and literal-`10^19` variants regressed `Long integer` 24.7 → 28.5 ns
  (+15%) and `Long fractional` 46.2 → 52.3 ns (+13%). LLVM lowers
  `UInt128 * 10` to a shift-add already, so per-digit multiplies are
  essentially free; the batching adds a per-iteration branch + a wide
  `power_of_10_unsafe` lookup + a flush-time `__multi3` that exceed the
  saving. See the 2026-05-03 §2.4 entry. Revisit only if Mojo gains a
  cheaper-than-`__multi3` `mul_u128_by_u64` intrinsic.
- *multiply per-call dispatch*: collapse the 6-way special-case tree into
  3 branches (zero short-circuit, integer fast path, general). Risk:
  regressions on the cases the dispatch was added for.

### 5.2 API gaps vs `rust_decimal` / Python `Decimal` — DONE (2026-05-03)

Landed 2026-04-23: `trunc`, `floor`, `ceil`, `fract`, `signum`, `unpack`
(see §2.4). Landed 2026-04-27: `min`, `max`, `clamp`. Landed 2026-05-03:
`normalize`, `__hash__` (Hashable conformance), `same_quantum`,
`adjusted`, `compare_total`, `is_signed`, `canonical`, `is_canonical`
— see the 2026-05-03 §2.4 entry. The Decimal128 API surface is now at
parity with `rust_decimal::Decimal`, `System.Decimal`, and the
introspection / canonicalisation half of Python `Decimal`.

### 5.3 `ln()` / `log10()` / `exp()` range reduction — DONE (2026-04-25)

**Status:** complete. All `ln`/`log10`/`exp` worst-case ratios are now
**≤ 1.0× vs `rust_decimal`** across the full bench corpus.

Changes landed:

1. `ln()` (`exponential.mojo`): replaced the two while-loops that scaled
   `x` into `[0.5, 2.0)` with a direct scale-based extraction
   `q = num_digits(coef) - 1 - x_scale`, so `ln(x) = ln(coef × 10^-q) +
   q·ln(10)`. Gated on `x ∉ [0.1, 10)` to preserve 1-ulp accuracy for
   the direct-bucket cases (otherwise `ln(0.5)` would chain through
   `q·ln(10)` and lose 1 ulp).
2. `exp_series()`: replaced per-iteration `term * x / Decimal128(i)`
   (one full `Decimal128` divide per term) with
   `x_power *= x; term = x_power * factorial_reciprocal(i)` (two
   multiplies). Drops `exp(0.1)` from 1050 → 295 ns, ~3.6× faster.
3. `log10()`: replaced the per-digit `% 10 / //= 10` integer-power-of-10
   probe loop with O(1) `number_of_digits` + `power_of_10_unsafe`
   equality check. Drops `log10(1e28)` from 100 → 10 ns.

**Cross-language ratios (mojo / rust, worst case shown):**

| op      | worst case              | mojo (ns) | rust (ns) | ratio |
| ------- | ----------------------- | --------: | --------: | ----: |
| `ln`    | `ln(0.95)` close-to-1   |       945 |       989 | 0.96× |
| `log10` | `log10(0.99999999)`     |       255 |       375 | 0.68× |
| `exp`   | `exp(π)` high precision |      1225 |      1533 | 0.80× |

Bench cases live in `benches/decimal128/cases/{ln,log10,exp}.toml`
(12–16 cases each); `run_all.sh` now includes these ops by default so
they appear in the aggregated markdown report.

**Follow-up — DONE (2026-05-03), 2-tier extension:** the `exp(π)` cost
was dominated by ~17 Taylor iterations on a 28-digit-scale remainder, so
we landed a **2-tier sub-unit chunker**. Added 17 precomputed constants
— per-tenth `E0D1`…`E0D9` (skipping `E0D5` which already existed) and
per-hundredth `E0D01`…`E0D09` — and rewrote the `x_int < 1` arm to peel
off `d1 = Int(x*10)` then, when `d1 == 0`, `d2 = Int(x*100)`. The final
residual lives in `[0, 0.01)` (Taylor converges in ~5 terms instead of
~17). The 2-tier design improves **both speed and accuracy**: each saved
Taylor multiply also avoids ~0.5 ulp of truncation, so the speed gain
translates directly to ulp gain. `exp(π)` 1350 → 770 ns (1.75×) and
3 ulp → 1 ulp off the BigDecimal reference; `exp(typical)` 960 → 725 ns
(1.32×) and 4 ulp → 2 ulp. `exp(0.1)`, `exp(0.5)`, `exp(2)`, etc. were
already at 0 ulp / constant-lookup speed and are unchanged. See
§2.4 (20260503) for the full table and a possible "read-`d1`/`d2`
directly from coef" micro-follow-up.

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
incompatible with .NET and rust_decimal, more complex implementation (107-bit
coefficient arithmetic instead of 96-bit).

107 comes from log(10^32, 2).

It is a long-term proposal; not on the active roadmap.

### 5.6 Per-op `RoundingMode` parameter on `Decimal128` arithmetic — REJECTED

**Considered 2026-05-02.** Cross-language survey of fixed-precision
decimal `/`: C# `System.Decimal`, `rust_decimal`, Apache Arrow Decimal128,
Go `govalues/decimal`, Python `decimal` — *none* take a per-op rounding
mode; all use implicit banker's. Only arbitrary-precision types (Java /
decimo `BigDecimal`) take one. **Verdict: REJECTED** to match the
fixed-precision convention. Decimo already exposes
`Decimal128.round(scale, RoundingMode)` for follow-up adjustment, and
`BigDecimal` for callers needing per-op control.

### 5.7 API additions

On 2026-05-04, I added the trivial API methods
(`__bool__`, `__pos__`, `is_positive`, `is_odd`,
`number_of_trailing_zeros`, `to_string_with_separators`,
`to_scientific_string` / `to_eng_string` aliases) and consolidated
`to_string_scientific()` into `to_string(scientific=, engineering=)`.
On 2026-05-05, I implemented `fma(other, third)` (single-rounding
fused multiply-add); the three items below are still pending.

1. **`fma(a, b)` — fused multiply-add.** Implemented 2026-05-05.
   `Decimal128.fma(other, third)` computes `self * other + third` with
   a single final rounding. The intermediate product is kept exact in
   `UInt256`; the addend is aligned by scale (falling back to the
   two-step `multiply(self, other) + third` path when the aligned
   working coefficient would exceed the implementation's 58-digit
   working cap — the size of the `power_of_10_unsafe[uint256]` rodata
   table, which is the fast power-of-10 path used here, not a UInt256
   limit), then a signed magnitude combine and a single
   `round_coefficient` pass mirror `multiply()`'s late stage.
   Bit-identical to the high-precision `BigDecimal` oracle (work=40,
   using the exact `multiply(precision=0)` / `add(precision=0)`
   methods) on all 12 cross-language bench cases. Bench harness lands
   at `benches/decimal128/cases/fma.toml`.
2. **`__divmod__(other)` / `__rdivmod__(other)`.** Return
   `(quotient, remainder)` in a single call. Today callers must do two
   separate divisions (`a // b` and `a % b`), each going through the
   full division pipeline. A combined entry point would amortise the
   cost. `BigDecimal` exposes both dunders.
3. **`cbrt()` — cube root.** Convenience wrapper for `root(3)`.
   Trivial, but useful.
4. **Trigonometric functions** — `sin`, `cos`, `tan`, `cot`, `csc`,
   `sec`, `arctan`, etc. Not commonly found in fixed-point decimal types,
   but can be a unique selling point for decimo. The problem is that the
   cumulative rounding errors in the Taylor series can be larger as we do not
   have buffer digits to carry the intermediate precision. Need to make 
   notes that the ULPs can be larger than 1 for some inputs. For users needing
   more precision, they can use `BigDecimal`.

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

## 7. Tasks and future improvements

Open items, in priority order:

| #   | Item                         | Section | Notes                                           |
| --- | ---------------------------- | ------- | ----------------------------------------------- |
| 1   | `__divmod__` / `__rdivmod__` | §5.7.2  | Amortise the divide pipeline across `//` + `%`. |
| 2   | `cbrt()`                     | §5.7.3  | Trivial wrapper over `root(3)`.                 |

Future improvements (may not be necessary or urgent):

| #   | Item                          | Section | Notes                                          |
| --- | ----------------------------- | ------- | ---------------------------------------------- |
| 1   | Trigonometric functions       | §5.7.4  | Quite unique to a 128-bit decimal library.     |
|     | (`sin`, `cos`, `tan`, `cot`,  |         | But why not use `BigDecimal`?                  |
|     | `csc`, `sec`, `arctan`, etc)  |         |                                                |
| 2   | 96-bit → 32-digit coefficient | §5.5    | Cleaner API, wider range, always 32 sig digit. |
|     | low, mid, high, top (11 bits) |         | Incompatible with other implementations.       |
|     |                               |         | Cannot be bit-casted to others.                |
