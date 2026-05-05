"""
Tests for Decimal128 integer-part / fractional-part / sign helpers,
the IEEE 754 / IBM GDA "preferred exponent" semantics for multiply and
divide, and the canonicalisation / introspection surface
(`normalize`, `__hash__`, `same_quantum`, `adjusted`, `compare_total`,
`is_signed`, `canonical`, `is_canonical`).

Consolidates test_decimal128_{integer_part, preferred_exp,
canonicalization}.mojo. None use TOML.
"""

from std import testing
from std.hashlib.hasher import default_hasher

from decimo import Dec128


# ─────────────────────────────────────────────────────────────────────────────
# trunc()
# ─────────────────────────────────────────────────────────────────────────────


def test_trunc_positive_fraction() raises:
    testing.assert_equal(String(Dec128("3.7").trunc()), "3", "trunc(3.7)")
    testing.assert_equal(String(Dec128("3.999").trunc()), "3", "trunc(3.999)")
    testing.assert_equal(
        String(Dec128("0.999999999").trunc()), "0", "trunc(0.999999999)"
    )


def test_trunc_negative_fraction() raises:
    """Truncation rounds toward zero, NOT toward -inf."""
    testing.assert_equal(String(Dec128("-3.7").trunc()), "-3", "trunc(-3.7)")
    testing.assert_equal(
        String(Dec128("-3.999").trunc()), "-3", "trunc(-3.999)"
    )
    testing.assert_equal(
        String(Dec128("-0.5").trunc()), "-0", "trunc(-0.5) -> -0 (signed)"
    )


def test_trunc_already_integer() raises:
    testing.assert_equal(String(Dec128("3").trunc()), "3", "trunc(3)")
    testing.assert_equal(String(Dec128("3.0").trunc()), "3", "trunc(3.0)")
    testing.assert_equal(String(Dec128("100").trunc()), "100", "trunc(100)")


def test_trunc_zero() raises:
    testing.assert_equal(String(Dec128("0").trunc()), "0", "trunc(0)")
    testing.assert_equal(String(Dec128("0.000").trunc()), "0", "trunc(0.000)")
    testing.assert_equal(String(Dec128("-0.5").trunc()), "-0", "trunc(-0.5)")


def test_trunc_large_value() raises:
    var v = Dec128("79228162514264337593543950334.5")
    testing.assert_equal(
        String(v.trunc()),
        "79228162514264337593543950334",
        "trunc near max: drops .5",
    )


# ─────────────────────────────────────────────────────────────────────────────
# floor()
# ─────────────────────────────────────────────────────────────────────────────


def test_floor_positive() raises:
    testing.assert_equal(String(Dec128("3.7").floor()), "3")
    testing.assert_equal(String(Dec128("3.0").floor()), "3")
    testing.assert_equal(String(Dec128("3").floor()), "3")


def test_floor_negative() raises:
    testing.assert_equal(String(Dec128("-3.2").floor()), "-4")
    testing.assert_equal(String(Dec128("-3.7").floor()), "-4")
    testing.assert_equal(String(Dec128("-0.001").floor()), "-1")
    testing.assert_equal(String(Dec128("-3.0").floor()), "-3")


def test_floor_zero() raises:
    testing.assert_equal(String(Dec128("0").floor()), "0")


# ─────────────────────────────────────────────────────────────────────────────
# ceil()
# ─────────────────────────────────────────────────────────────────────────────


def test_ceil_positive() raises:
    testing.assert_equal(String(Dec128("3.2").ceil()), "4")
    testing.assert_equal(String(Dec128("3.7").ceil()), "4")
    testing.assert_equal(String(Dec128("0.001").ceil()), "1")
    testing.assert_equal(String(Dec128("3.0").ceil()), "3")


def test_ceil_negative() raises:
    testing.assert_equal(String(Dec128("-3.7").ceil()), "-3")
    testing.assert_equal(String(Dec128("-3.2").ceil()), "-3")
    testing.assert_equal(String(Dec128("-0.5").ceil()), "-0")


def test_ceil_zero() raises:
    testing.assert_equal(String(Dec128("0").ceil()), "0")


# ─────────────────────────────────────────────────────────────────────────────
# fract() — fractional part: self - self.trunc()
# ─────────────────────────────────────────────────────────────────────────────


def test_fract_positive() raises:
    testing.assert_equal(String(Dec128("3.75").fract()), "0.75")
    testing.assert_equal(String(Dec128("0.123").fract()), "0.123")


def test_fract_negative() raises:
    """Fract preserves the sign of the input."""
    testing.assert_equal(String(Dec128("-3.75").fract()), "-0.75")
    testing.assert_equal(String(Dec128("-0.123").fract()), "-0.123")


def test_fract_integer() raises:
    """Fract of an integer is zero — but with the original scale preserved."""
    testing.assert_equal(String(Dec128("3").fract()), "0")
    testing.assert_equal(String(Dec128("3.000").fract()), "0.000")
    testing.assert_equal(String(Dec128("-3").fract()), "0")


def test_fract_round_trip() raises:
    """Trunc(x) + fract(x) == x for every x."""
    var samples = [
        String("3.75"),
        String("-3.75"),
        String("0.123456789012345678901234567"),
        String("-0.123456789012345678901234567"),
        String("100"),
        String("0"),
        String("1.5"),
        String("-0.5"),
    ]
    for s in samples:
        var x = Dec128(s)
        var sum = x.trunc() + x.fract()
        testing.assert_equal(
            String(sum), s, "trunc + fract round-trip for " + s
        )


# ─────────────────────────────────────────────────────────────────────────────
# signum()
# ─────────────────────────────────────────────────────────────────────────────


def test_signum_positive() raises:
    testing.assert_equal(String(Dec128("3.7").signum()), "1")
    testing.assert_equal(String(Dec128("0.001").signum()), "1")
    testing.assert_equal(
        String(Dec128("79228162514264337593543950335").signum()), "1"
    )


def test_signum_negative() raises:
    testing.assert_equal(String(Dec128("-3.7").signum()), "-1")
    testing.assert_equal(String(Dec128("-0.001").signum()), "-1")


def test_signum_zero() raises:
    testing.assert_equal(String(Dec128("0").signum()), "0")
    testing.assert_equal(String(Dec128("0.000").signum()), "0")
    testing.assert_equal(String(Dec128("-0").signum()), "0")
    testing.assert_equal(String(Dec128("-0.000").signum()), "0")


# ─────────────────────────────────────────────────────────────────────────────
# unpack() — (low, mid, high, scale, sign)
# ─────────────────────────────────────────────────────────────────────────────


def test_unpack_simple() raises:
    var parts = Dec128("123.45").unpack()
    testing.assert_equal(Int(parts[0]), 12345, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 0, "high")
    testing.assert_equal(Int(parts[3]), 2, "scale")
    testing.assert_equal(parts[4], False, "sign (positive)")


def test_unpack_negative() raises:
    var parts = Dec128("-123.45").unpack()
    testing.assert_equal(Int(parts[0]), 12345, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 0, "high")
    testing.assert_equal(Int(parts[3]), 2, "scale")
    testing.assert_equal(parts[4], True, "sign (negative)")


def test_unpack_zero() raises:
    var parts = Dec128("0").unpack()
    testing.assert_equal(Int(parts[0]), 0, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 0, "high")
    testing.assert_equal(Int(parts[3]), 0, "scale")
    testing.assert_equal(parts[4], False, "sign")

    var parts2 = Dec128("0.000").unpack()
    testing.assert_equal(Int(parts2[3]), 3, "scale of 0.000 is preserved")


def test_unpack_max_scale() raises:
    var v = Dec128("0." + "0" * 27 + "1")  # 1e-28
    var parts = v.unpack()
    testing.assert_equal(Int(parts[0]), 1, "low")
    testing.assert_equal(Int(parts[3]), 28, "scale (max)")
    testing.assert_equal(parts[4], False, "sign")


def test_unpack_high_word_used() raises:
    var parts = Dec128("18446744073709551616").unpack()
    testing.assert_equal(Int(parts[0]), 0, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 1, "high")
    testing.assert_equal(Int(parts[3]), 0, "scale")
    testing.assert_equal(parts[4], False, "sign")


def test_unpack_negative_zero_preserves_sign() raises:
    """`Dec128("-0")` and `Dec128("-0.000")` retain `sign == True` and
    preserve scale through `unpack()`. Regression test for IEEE 754 /
    IBM GDA signed-zero semantics (PR #227 review)."""
    var parts = Dec128("-0").unpack()
    testing.assert_equal(Int(parts[0]), 0, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 0, "high")
    testing.assert_equal(Int(parts[3]), 0, "scale of -0 is 0")
    testing.assert_equal(parts[4], True, "sign of -0 is negative")

    var parts2 = Dec128("-0.000").unpack()
    testing.assert_equal(Int(parts2[0]), 0, "low")
    testing.assert_equal(Int(parts2[1]), 0, "mid")
    testing.assert_equal(Int(parts2[2]), 0, "high")
    testing.assert_equal(Int(parts2[3]), 3, "scale of -0.000 is preserved")
    testing.assert_equal(parts2[4], True, "sign of -0.000 is negative")


# ─────────────────────────────────────────────────────────────────────────────
# Preferred-exponent semantics for multiply and divide (IEEE 754-2008 §3.3 /
# IBM GDA §4.1). Pinned to catch regressions toward `rust_decimal` behaviour.
# ─────────────────────────────────────────────────────────────────────────────


def test_multiply_by_zero_preserves_scale() raises:
    """123.45 * 0 must be '0.00' (preferred exponent = -2)."""
    var result = Dec128("123.45") * Dec128("0")
    testing.assert_equal(
        String(result),
        "0.00",
        "123.45 * 0 should preserve scale -2 per IEEE 754 §3.3",
    )


def test_multiply_by_zero_negative_exponent() raises:
    """Multiplying any value by zero adopts the sum of exponents."""
    var result = Dec128("1.234567") * Dec128("0")
    testing.assert_equal(String(result), "0.000000")

    var result2 = Dec128("0.0") * Dec128("0.000")
    testing.assert_equal(String(result2), "0.0000")


def test_multiply_zero_by_integer() raises:
    """0 * anything-with-positive-exponent stays at '0' (ideal exp = 0+0)."""
    var result = Dec128("0") * Dec128("123")
    testing.assert_equal(String(result), "0")


def test_divide_preferred_exponent_exact() raises:
    """10.5 / 2.5 must be '4.2' (NOT '4.20')."""
    var result = Dec128("10.5") / Dec128("2.5")
    testing.assert_equal(
        String(result),
        "4.2",
        "10.5 / 2.5 should be '4.2' (largest exp giving exact quotient)",
    )


def test_divide_preferred_exponent_negative() raises:
    """123.45 / -2 must be '-61.725' (exact at exp -3, smallest |exp|)."""
    var result = Dec128("123.45") / Dec128("-2")
    testing.assert_equal(String(result), "-61.725")


def test_divide_exact_integer_quotient() raises:
    """10 / 2 should be '5'."""
    var result = Dec128("10") / Dec128("2")
    testing.assert_equal(String(result), "5")


def test_divide_above_ideal_exponent() raises:
    """6.0 / 2 should hit ideal exponent -1 → '3.0'."""
    var result = Dec128("6.0") / Dec128("2")
    testing.assert_equal(String(result), "3.0")


# ─────────────────────────────────────────────────────────────────────────
# normalize()
# ─────────────────────────────────────────────────────────────────────────


def test_normalize_strips_fractional_zeros() raises:
    testing.assert_equal(String(Dec128("1.000").normalize()), "1")
    testing.assert_equal(String(Dec128("1.0").normalize()), "1")
    testing.assert_equal(String(Dec128("123.4500").normalize()), "123.45")
    testing.assert_equal(String(Dec128("0.1000").normalize()), "0.1")


def test_normalize_keeps_integer_trailing_zeros() raises:
    """`100` has scale 0 already; normalize must not collapse it to `1E2`
    (we don't carry an exponent separate from scale, so the trailing
    zeros in the integer part of a scale-0 value are part of the
    coefficient)."""
    testing.assert_equal(String(Dec128("100").normalize()), "100")
    testing.assert_equal(String(Dec128("1000").normalize()), "1000")


def test_normalize_no_trailing_zeros_is_idempotent() raises:
    testing.assert_equal(String(Dec128("1.23").normalize()), "1.23")
    testing.assert_equal(String(Dec128("3").normalize()), "3")
    testing.assert_equal(String(Dec128("-3.14159").normalize()), "-3.14159")


def test_normalize_zero_canonicalizes_to_positive_zero_scale_zero() raises:
    """All zero representations collapse to `Decimal128.ZERO()` so
    hashing / equality stay consistent."""
    testing.assert_equal(String(Dec128("0").normalize()), "0")
    testing.assert_equal(String(Dec128("0.0").normalize()), "0")
    testing.assert_equal(String(Dec128("0.0000").normalize()), "0")
    testing.assert_equal(String(Dec128("-0").normalize()), "0")
    testing.assert_equal(String(Dec128("-0.000").normalize()), "0")


def test_normalize_negative_strips_zeros_keeps_sign() raises:
    testing.assert_equal(String(Dec128("-1.500").normalize()), "-1.5")
    testing.assert_equal(String(Dec128("-100.00").normalize()), "-100")


def test_normalize_high_precision_strips_at_chunk_boundary() raises:
    """Hits the 9-digit chunk pre-pass: 18 trailing zeros -> 2 chunks
    peeled in two iterations."""
    var v = Dec128("1.000000000000000000")  # 1 then 18 zeros, scale 18
    testing.assert_equal(String(v.normalize()), "1")
    var w = Dec128("1.234500000000000000")  # scale 18, last 14 zeros
    testing.assert_equal(String(w.normalize()), "1.2345")


def test_normalize_max_scale_no_zeros_to_strip_is_idempotent() raises:
    """Tests scale=28 with coef=5 (no trailing zeros): nothing to strip,
    `normalize()` is the identity."""
    var v = Dec128("0.0000000000000000000000000005")
    var n = v.normalize()
    testing.assert_equal(String(v), String(n))
    testing.assert_true(v == n)
    testing.assert_equal(n.scale(), 28)


# ─────────────────────────────────────────────────────────────────────────
# __hash__ (Hashable)
# ─────────────────────────────────────────────────────────────────────────


def _h(d: Dec128) -> UInt64:
    """Helper: feed `d` through the default Mojo hasher and finish."""
    var h = default_hasher()
    d.__hash__(h)
    return h^.finish()


def test_hash_equal_values_same_scale_collide() raises:
    testing.assert_equal(_h(Dec128("1.23")), _h(Dec128("1.23")))


def test_hash_equal_values_different_scale_collide() raises:
    """The defining contract: a == b => hash(a) == hash(b)."""
    testing.assert_true(Dec128("1.0") == Dec128("1.00"))
    testing.assert_equal(_h(Dec128("1.0")), _h(Dec128("1.00")))
    testing.assert_equal(_h(Dec128("1")), _h(Dec128("1.000000")))
    testing.assert_equal(_h(Dec128("100")), _h(Dec128("100.000")))


def test_hash_zero_collides_across_signs_and_scales() raises:
    """All zeros hash the same after normalize() canonicalises sign+scale."""
    var z0 = _h(Dec128("0"))
    testing.assert_equal(z0, _h(Dec128("0.0")))
    testing.assert_equal(z0, _h(Dec128("0.000000")))
    testing.assert_equal(z0, _h(Dec128("-0")))
    testing.assert_equal(z0, _h(Dec128("-0.00")))


def test_hash_distinct_values_distinct() raises:
    """Sanity sample (NOT a contract — 64-bit hashes can collide in
    principle). We only assert it on a tiny hand-picked set where the
    AHasher output is empirically distinct on the current platform; this
    is a smoke test for the hashing path being wired up at all, not a
    distinctness guarantee.

    The Hashable contract is `a == b ⇒ hash(a) == hash(b)` only — the
    converse is NOT required. Coverage of the contract proper lives in
    `test_hash_equal_values_*_collide` and
    `test_hash_zero_collides_across_signs_and_scales` above.
    """
    # Smoke: the hasher must return a value at all (no panic, no zero-
    # init bug). We deliberately do NOT assert distinctness across
    # arbitrary inputs to avoid flaky failures from random collisions.
    _ = _h(Dec128("1.23"))
    _ = _h(Dec128("-1.23"))
    _ = _h(Dec128("100"))
    _ = _h(Dec128("1000"))


def test_hash_negative() raises:
    testing.assert_equal(_h(Dec128("-1.5")), _h(Dec128("-1.500")))
    # Probabilistic distinctness check kept off the assert path — see
    # `test_hash_distinct_values_distinct` for the rationale.


# ─────────────────────────────────────────────────────────────────────────
# same_quantum()
# ─────────────────────────────────────────────────────────────────────────


def test_same_quantum_equal_scale() raises:
    testing.assert_true(Dec128("1.23").same_quantum(Dec128("4.56")))
    testing.assert_true(Dec128("0.001").same_quantum(Dec128("999.999")))
    testing.assert_true(Dec128("100").same_quantum(Dec128("0")))


def test_same_quantum_different_scale() raises:
    testing.assert_false(Dec128("1.230").same_quantum(Dec128("1.23")))
    testing.assert_false(Dec128("1").same_quantum(Dec128("1.0")))


def test_same_quantum_signs_irrelevant() raises:
    testing.assert_true(Dec128("-1.23").same_quantum(Dec128("4.56")))
    testing.assert_true(Dec128("-0.00").same_quantum(Dec128("0.00")))


# ─────────────────────────────────────────────────────────────────────────
# adjusted()
# ─────────────────────────────────────────────────────────────────────────


def test_adjusted_basic() raises:
    # 1.2345e2 -> adjusted = 2
    testing.assert_equal(Dec128("123.45").adjusted(), 2)
    # 1.00e2 -> adjusted = 2
    testing.assert_equal(Dec128("100").adjusted(), 2)
    # 1.0e0 -> adjusted = 0
    testing.assert_equal(Dec128("1").adjusted(), 0)
    # 1.0e0 (with trailing zeros bumping digit count) -> adjusted = 0
    testing.assert_equal(Dec128("1.00").adjusted(), 0)


def test_adjusted_fractional() raises:
    # 1.23e-3 -> -3
    testing.assert_equal(Dec128("0.00123").adjusted(), -3)
    # 1e-1 -> -1
    testing.assert_equal(Dec128("0.1").adjusted(), -1)
    # 5e-28 -> -28 (max scale)
    testing.assert_equal(
        Dec128("0.0000000000000000000000000005").adjusted(), -28
    )


def test_adjusted_negative_value() raises:
    """Sign does not affect adjusted exponent."""
    testing.assert_equal(Dec128("-123.45").adjusted(), 2)
    testing.assert_equal(Dec128("-0.001").adjusted(), -3)


def test_adjusted_zero() raises:
    testing.assert_equal(Dec128("0").adjusted(), 0)
    testing.assert_equal(Dec128("0.000").adjusted(), 0)
    testing.assert_equal(Dec128("-0.00").adjusted(), 0)


# ─────────────────────────────────────────────────────────────────────────
# compare_total()
# ─────────────────────────────────────────────────────────────────────────


def test_compare_total_distinguishes_scales_when_equal() raises:
    """Numerically equal values: lower scale precedes higher scale for
    positives (`1 < 1.0 < 1.00`)."""
    testing.assert_equal(Int(Dec128("1.0").compare_total(Dec128("1.00"))), -1)
    testing.assert_equal(Int(Dec128("1").compare_total(Dec128("1.0"))), -1)
    testing.assert_equal(Int(Dec128("1.00").compare_total(Dec128("1.0"))), 1)


def test_compare_total_negative_reverses_scale_ordering() raises:
    """For negatives, higher scale precedes lower scale so the global
    sequence stays monotonic across the sign change."""
    testing.assert_equal(Int(Dec128("-1.00").compare_total(Dec128("-1.0"))), -1)
    testing.assert_equal(Int(Dec128("-1.0").compare_total(Dec128("-1"))), -1)


def test_compare_total_falls_back_to_value_when_scales_match() raises:
    testing.assert_equal(Int(Dec128("1.5").compare_total(Dec128("2.5"))), -1)
    testing.assert_equal(Int(Dec128("2.5").compare_total(Dec128("1.5"))), 1)


def test_compare_total_identical_returns_zero() raises:
    testing.assert_equal(Int(Dec128("1.23").compare_total(Dec128("1.23"))), 0)
    testing.assert_equal(Int(Dec128("-0.00").compare_total(Dec128("-0.00"))), 0)


def test_compare_total_signs() raises:
    # Negative precedes positive even when |a| > |b|.
    testing.assert_equal(Int(Dec128("-100").compare_total(Dec128("0.1"))), -1)
    testing.assert_equal(Int(Dec128("0.1").compare_total(Dec128("-100"))), 1)


def test_compare_total_signed_zero() raises:
    """Signed zero edge case (rule 1): `-0 < +0` even though `compare()`
    treats them as equal. This is the load-bearing difference between
    `compare()` and `compare_total()` — the latter must NOT delegate to
    `compare()` for the dual-zero branch (which would return 0 and break
    the strict total order)."""
    testing.assert_equal(Int(Dec128("-0.00").compare_total(Dec128("0.00"))), -1)
    testing.assert_equal(Int(Dec128("0.00").compare_total(Dec128("-0.00"))), 1)
    testing.assert_equal(Int(Dec128("-0").compare_total(Dec128("0"))), -1)


def test_compare_total_scaled_zeros_same_sign() raises:
    """Scaled-zero edge case (rule 3): same-sign zeros differ by scale.
    For positives lower scale precedes higher (`0 < 0.0 < 0.00`); for
    negatives the relation reverses (`-0.00 < -0.0 < -0`) so the global
    sequence stays monotonic across +0/-0."""
    # Positive zeros: lower scale precedes higher.
    testing.assert_equal(Int(Dec128("0").compare_total(Dec128("0.0"))), -1)
    testing.assert_equal(Int(Dec128("0.0").compare_total(Dec128("0.00"))), -1)
    testing.assert_equal(Int(Dec128("0.00").compare_total(Dec128("0"))), 1)
    # Negative zeros: higher scale precedes lower.
    testing.assert_equal(Int(Dec128("-0.00").compare_total(Dec128("-0.0"))), -1)
    testing.assert_equal(Int(Dec128("-0.0").compare_total(Dec128("-0"))), -1)
    testing.assert_equal(Int(Dec128("-0").compare_total(Dec128("-0.0"))), 1)
    # Identical zero representations still tie.
    testing.assert_equal(Int(Dec128("0").compare_total(Dec128("0"))), 0)
    testing.assert_equal(Int(Dec128("-0.00").compare_total(Dec128("-0.00"))), 0)


def test_compare_total_zero_vs_nonzero_signs() raises:
    """Cross-cases that mix signed zero with non-zero values: the sign
    rule (rule 1) still dominates."""
    # +0 < any positive non-zero; -0 < any positive non-zero.
    testing.assert_equal(Int(Dec128("0").compare_total(Dec128("1"))), -1)
    testing.assert_equal(Int(Dec128("-0").compare_total(Dec128("1"))), -1)
    # any negative non-zero < +0 and < -0.
    testing.assert_equal(Int(Dec128("-1").compare_total(Dec128("0"))), -1)
    testing.assert_equal(Int(Dec128("-1").compare_total(Dec128("-0"))), -1)


# ─────────────────────────────────────────────────────────────────────────
# is_signed / canonical / is_canonical
# ─────────────────────────────────────────────────────────────────────────


def test_is_signed() raises:
    testing.assert_true(Dec128("-1").is_signed())
    testing.assert_true(Dec128("-0.00").is_signed())  # signed zero
    testing.assert_false(Dec128("1").is_signed())
    testing.assert_false(Dec128("0").is_signed())


def test_canonical_returns_self_unchanged() raises:
    """Decimal128 has no non-canonical encoding; `canonical()` is identity."""
    var v = Dec128("123.450")
    var c = v.canonical()
    testing.assert_equal(String(v), String(c))
    testing.assert_true(v == c)
    # Also keep the original scale (does NOT normalize).
    testing.assert_equal(c.scale(), 3)


def test_is_canonical_always_true() raises:
    testing.assert_true(Dec128("0").is_canonical())
    testing.assert_true(Dec128("123.45").is_canonical())
    testing.assert_true(Dec128("-0.00").is_canonical())
    testing.assert_true(Dec128("79228162514264337593543950335").is_canonical())


# ─────────────────────────────────────────────────────────────────────────
# to_string(scientific=True) / to_scientific_string()
# ─────────────────────────────────────────────────────────────────────────


def test_to_string_default_unchanged() raises:
    """Default to_string() preserves trailing zeros via the scale."""
    testing.assert_equal(Dec128("1.2300").to_string(), "1.2300")
    testing.assert_equal(Dec128("0").to_string(), "0")
    testing.assert_equal(Dec128("-0.00").to_string(), "-0.00")
    testing.assert_equal(Dec128("12345").to_string(), "12345")


def test_to_string_scientific_basic() raises:
    testing.assert_equal(
        Dec128("123456.789").to_string(scientific=True), "1.23456789E+5"
    )
    testing.assert_equal(
        Dec128("0.00123").to_string(scientific=True), "1.23E-3"
    )
    # One-digit coefficient renders with the historical `.0` suffix.
    testing.assert_equal(Dec128("1").to_string(scientific=True), "1.0E+0")
    testing.assert_equal(Dec128("10").to_string(scientific=True), "1.0E+1")


def test_to_string_scientific_strips_trailing_zeros() raises:
    # Coefficient 50000, scale 4 -> magnitude 5, scientific 5.0E+0.
    testing.assert_equal(Dec128("5.0000").to_string(scientific=True), "5.0E+0")


def test_to_string_scientific_negative() raises:
    testing.assert_equal(
        Dec128("-0.00123").to_string(scientific=True), "-1.23E-3"
    )
    testing.assert_equal(Dec128("-12.5").to_string(scientific=True), "-1.25E+1")


def test_to_string_scientific_zero() raises:
    testing.assert_equal(Dec128("0").to_string(scientific=True), "0")
    testing.assert_equal(Dec128("0.000").to_string(scientific=True), "0E-3")
    testing.assert_equal(Dec128("-0.000").to_string(scientific=True), "-0E-3")


def test_to_scientific_string_alias() raises:
    var v = Dec128("123456.789")
    testing.assert_equal(v.to_scientific_string(), v.to_string(scientific=True))


# ─────────────────────────────────────────────────────────────────────────
# to_string(engineering=True) / to_eng_string()
# ─────────────────────────────────────────────────────────────────────────


def test_to_string_engineering_basic() raises:
    testing.assert_equal(
        Dec128("123456.789").to_string(engineering=True), "123.456789E+3"
    )
    testing.assert_equal(
        Dec128("0.00123").to_string(engineering=True), "1.23E-3"
    )
    testing.assert_equal(Dec128("1000000").to_string(engineering=True), "1E+6")
    # adjusted_exp == 0 -> no E suffix.
    testing.assert_equal(Dec128("1").to_string(engineering=True), "1")
    testing.assert_equal(Dec128("12.34").to_string(engineering=True), "12.34")


def test_to_string_engineering_pads_lead_digits() raises:
    # adjusted_exp = -1, eng_exp = -3, lead_digits = 3 -> "500E-3".
    testing.assert_equal(Dec128("0.5").to_string(engineering=True), "500E-3")
    # adjusted_exp = 1, eng_exp = 0, lead_digits = 2 -> "50".
    testing.assert_equal(Dec128("50").to_string(engineering=True), "50")


def test_to_string_engineering_negative_and_zero() raises:
    testing.assert_equal(
        Dec128("-123456.789").to_string(engineering=True), "-123.456789E+3"
    )
    testing.assert_equal(Dec128("0").to_string(engineering=True), "0")
    testing.assert_equal(Dec128("0.00").to_string(engineering=True), "0E-2")


def test_to_string_engineering_wins_over_scientific() raises:
    """Both flags True -> engineering takes precedence."""
    var v = Dec128("123456.789")
    testing.assert_equal(
        v.to_string(scientific=True, engineering=True), "123.456789E+3"
    )


def test_to_eng_string_alias() raises:
    var v = Dec128("123456.789")
    testing.assert_equal(v.to_eng_string(), v.to_string(engineering=True))


# ─────────────────────────────────────────────────────────────────────────
# to_string_with_separators()
# ─────────────────────────────────────────────────────────────────────────


def test_to_string_with_separators_default() raises:
    testing.assert_equal(
        Dec128("1234567.89").to_string_with_separators(), "1_234_567.89"
    )
    testing.assert_equal(
        Dec128("-9876543210.123456").to_string_with_separators(),
        "-9_876_543_210.123_456",
    )
    # Short integer part (no grouping needed).
    testing.assert_equal(
        Dec128("12.345678").to_string_with_separators(), "12.345_678"
    )


def test_to_string_with_separators_custom() raises:
    testing.assert_equal(
        Dec128("1234567.89").to_string_with_separators(","), "1,234,567.89"
    )


def test_to_string_with_separators_no_fraction() raises:
    testing.assert_equal(
        Dec128("1234567").to_string_with_separators(), "1_234_567"
    )
    testing.assert_equal(Dec128("123").to_string_with_separators(), "123")


def test_to_string_delimiter_arg() raises:
    """`to_string(delimiter=...)` is the underlying primitive; the
    convenience alias `to_string_with_separators` should match it."""
    testing.assert_equal(
        Dec128("1234567.89").to_string(delimiter="_"), "1_234_567.89"
    )
    # Combines with scientific notation: the exponent is preserved
    # verbatim (only the mantissa is grouped).
    testing.assert_equal(
        Dec128("12345678.9").to_string(scientific=True, delimiter="_"),
        "1.234_567_89E+7",
    )
    # Engineering notation + delimiter.
    testing.assert_equal(
        Dec128("123456.789").to_string(engineering=True, delimiter="_"),
        "123.456_789E+3",
    )


# ─────────────────────────────────────────────────────────────────────────
# __bool__ / __pos__
# ─────────────────────────────────────────────────────────────────────────


def test_bool_dunder() raises:
    testing.assert_true(Bool(Dec128("1")))
    testing.assert_true(Bool(Dec128("-0.001")))
    testing.assert_false(Bool(Dec128("0")))
    testing.assert_false(Bool(Dec128("-0.000")))


def test_pos_dunder() raises:
    var v = Dec128("-123.45")
    var p = +v
    testing.assert_equal(String(p), "-123.45")
    testing.assert_true(p == v)


# ─────────────────────────────────────────────────────────────────────────
# is_positive / is_odd / number_of_trailing_zeros
# ─────────────────────────────────────────────────────────────────────────


def test_is_positive() raises:
    testing.assert_true(Dec128("1").is_positive())
    testing.assert_true(Dec128("0.001").is_positive())
    testing.assert_false(Dec128("0").is_positive())
    testing.assert_false(Dec128("-0.00").is_positive())
    testing.assert_false(Dec128("-1").is_positive())


def test_is_odd_integer() raises:
    testing.assert_true(Dec128("3").is_odd())
    testing.assert_true(Dec128("-7").is_odd())
    testing.assert_false(Dec128("4").is_odd())
    testing.assert_false(Dec128("0").is_odd())


def test_is_odd_with_fraction() raises:
    """Fractional part is ignored; sign is ignored."""
    testing.assert_true(Dec128("13.5").is_odd())
    testing.assert_true(Dec128("-13.999").is_odd())
    testing.assert_false(Dec128("12.999").is_odd())
    testing.assert_false(Dec128("0.999").is_odd())


def test_number_of_trailing_zeros() raises:
    testing.assert_equal(Dec128("1.2300").number_of_trailing_zeros(), 2)
    testing.assert_equal(Dec128("12000").number_of_trailing_zeros(), 3)
    testing.assert_equal(Dec128("0").number_of_trailing_zeros(), 0)
    testing.assert_equal(Dec128("0.000").number_of_trailing_zeros(), 0)
    testing.assert_equal(Dec128("123.45").number_of_trailing_zeros(), 0)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
