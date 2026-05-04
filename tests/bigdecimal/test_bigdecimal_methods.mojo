# Consider incorporating some of the tests to other test files in future
"""
Tests for BigDecimal utility methods added in v0.8.x:
  - is_positive()
  - __rtruediv__()
  - to_scientific_string() / to_eng_string()
  - number_of_digits()
  - as_tuple()
  - copy_abs() / copy_negate() / copy_sign()
  - adjusted()
  - same_quantum()
  - scaleb()
  - fma()
  - to_string_with_separators()
"""

from std import testing
from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.biguint.biguint import BigUInt


# ===----------------------------------------------------------------------=== #
# is_positive()
# ===----------------------------------------------------------------------=== #


def test_is_positive_positive_values() raises:
    """Positive values return True."""
    testing.assert_true(BigDecimal("1").is_positive())
    testing.assert_true(BigDecimal("0.001").is_positive())
    testing.assert_true(BigDecimal("999999999999999999").is_positive())
    testing.assert_true(BigDecimal("1E+50").is_positive())


def test_is_positive_negative_values() raises:
    """Negative values return False."""
    testing.assert_false(BigDecimal("-1").is_positive())
    testing.assert_false(BigDecimal("-0.001").is_positive())
    testing.assert_false(BigDecimal("-1E+50").is_positive())


def test_is_positive_zero() raises:
    """Zero is not positive."""
    testing.assert_false(BigDecimal("0").is_positive())
    testing.assert_false(BigDecimal("0.000").is_positive())


def test_is_positive_matches_bigint_semantics() raises:
    """Strictly positive (zero excluded), matching BigInt semantics."""
    var pos = BigDecimal("1")
    var neg = BigDecimal("-1")
    var zero = BigDecimal("0")
    testing.assert_true(pos.is_positive())
    testing.assert_false(neg.is_positive())
    testing.assert_false(zero.is_positive())
    # Consistency: is_positive and is_negative are mutually exclusive, and
    # both false for zero.
    testing.assert_false(pos.is_negative())
    testing.assert_true(neg.is_negative())
    testing.assert_false(zero.is_negative())


# ===----------------------------------------------------------------------=== #
# __rtruediv__()
# ===----------------------------------------------------------------------=== #


def test_rtruediv_basic() raises:
    """Int / BigDecimal dispatches via __rtruediv__."""
    # 1 / 2  -> 0.5
    var result = BigDecimal("1") / BigDecimal("2")
    # Now test __rtruediv__ path: BigDecimal("2").__rtruediv__(BigDecimal("1"))
    var lhs = BigDecimal("1")
    var rhs = BigDecimal("2")
    var r = rhs.__rtruediv__(lhs)
    testing.assert_equal(String(r), String(result), "1 / 2 via __rtruediv__")
    # Also test language-level dispatch: 1 / x
    var x = BigDecimal("2")
    var dispatched = BigDecimal(1) / x
    testing.assert_equal(String(dispatched), String(result), "1 / x dispatch")


def test_rtruediv_integer_numerator() raises:
    """Verify 1 / x == x.__rtruediv__(1)."""
    var x = BigDecimal("4")
    var expected = BigDecimal("1") / x
    var got = x.__rtruediv__(BigDecimal("1"))
    testing.assert_equal(String(got), String(expected))


def test_rtruediv_negative() raises:
    """-1 / 2 == BigDecimal('2').__rtruediv__(BigDecimal('-1'))."""
    var x = BigDecimal("2")
    var got = x.__rtruediv__(BigDecimal("-1"))
    var expected = BigDecimal("-1") / BigDecimal("2")
    testing.assert_equal(String(got), String(expected))


def test_rtruediv_symmetry() raises:
    """Verify a / b == b.__rtruediv__(a) for various pairs."""
    var as_: List[String] = ["10", "1", "100", "-5"]
    var bs: List[String] = ["3", "7", "6", "2"]
    for i in range(len(as_)):
        var a = BigDecimal(as_[i])
        var b = BigDecimal(bs[i])
        var direct = a / b
        var reflected = b.__rtruediv__(a)
        testing.assert_equal(
            String(direct),
            String(reflected),
            "a/b == b.__rtruediv__(a) for a=" + as_[i] + ", b=" + bs[i],
        )


# ===----------------------------------------------------------------------=== #
# to_scientific_string()
# ===----------------------------------------------------------------------=== #


def test_to_scientific_string_basic() raises:
    """Basic scientific notation examples."""
    testing.assert_equal(
        BigDecimal("123456.789").to_scientific_string(), "1.23456789E+5"
    )
    testing.assert_equal(
        BigDecimal("0.00123").to_scientific_string(), "1.23E-3"
    )
    testing.assert_equal(BigDecimal("1").to_scientific_string(), "1E0")
    testing.assert_equal(BigDecimal("10").to_scientific_string(), "1E+1")


def test_to_scientific_string_trailing_zeros_stripped() raises:
    """Trailing zeros are stripped in scientific notation."""
    # "1.23000" stored as coefficient=123000, scale=5
    var v = BigDecimal("1.23000")
    var s = v.to_scientific_string()
    # Should not end with trailing zeros
    testing.assert_equal(s, "1.23E0")


def test_to_scientific_string_negative() raises:
    """Negative numbers keep the minus sign."""
    testing.assert_equal(
        BigDecimal("-0.00123").to_scientific_string(), "-1.23E-3"
    )


def test_to_scientific_string_zero() raises:
    """Zero renders correctly."""
    testing.assert_equal(BigDecimal("0").to_scientific_string(), "0E0")


# ===----------------------------------------------------------------------=== #
# to_eng_string()
# ===----------------------------------------------------------------------=== #


def test_to_eng_string_basic() raises:
    """Engineering notation: exponent is a multiple of 3."""
    testing.assert_equal(
        BigDecimal("123456.789").to_eng_string(), "123.456789E+3"
    )
    testing.assert_equal(BigDecimal("0.00123").to_eng_string(), "1.23E-3")
    testing.assert_equal(BigDecimal("1000000").to_eng_string(), "1E+6")


def test_to_eng_string_trailing_zeros_stripped() raises:
    """Trailing zeros are stripped in engineering notation."""
    var v = BigDecimal("1230.00")
    var s = v.to_eng_string()
    # Should not have trailing zeros in mantissa
    testing.assert_false(
        s.startswith("1230.00"), "trailing zeros should be stripped: " + s
    )


def test_to_eng_string_negative() raises:
    """Negative numbers keep the minus sign."""
    var s = BigDecimal("-123456").to_eng_string()
    testing.assert_true(s.startswith("-"), "negative sign preserved: " + s)


def test_to_eng_string_is_alias() raises:
    """Verify to_eng_string() returns the same as to_string(engineering=True).
    """
    var values: List[String] = ["123456.789", "0.00123", "-9.99E+10", "0"]
    for i in range(len(values)):
        var d = BigDecimal(values[i])
        testing.assert_equal(
            d.to_eng_string(),
            d.to_string(engineering=True),
            "to_eng_string() == to_string(engineering=True) for " + values[i],
        )


def test_to_scientific_string_is_alias() raises:
    """Verify to_scientific_string() returns the same as to_string(scientific=True).
    """
    var values: List[String] = ["123456.789", "0.00123", "-9.99E+10", "0"]
    for i in range(len(values)):
        var d = BigDecimal(values[i])
        testing.assert_equal(
            d.to_scientific_string(),
            d.to_string(scientific=True),
            "to_scientific_string() == to_string(scientific=True) for "
            + values[i],
        )


def test_to_string_force_plain_negative_scale() raises:
    """`force_plain=True` must materialise trailing zeros for values with
    `scale < 0` (i.e. internally an exponent rather than coefficient
    digits). Regression test for the bug where `BigDecimal("1e40")`
    stringified as `"1"` instead of `"1" + 40*"0"`, silently producing a
    wrong value when `from_string()` re-parsed it (e.g. through
    `Decimal128.from_decimal()`)."""
    testing.assert_equal(
        BigDecimal("1e40").to_string(force_plain=True),
        "10000000000000000000000000000000000000000",
    )
    testing.assert_equal(
        BigDecimal("12e3").to_string(force_plain=True), "12000"
    )
    testing.assert_equal(
        BigDecimal("-7e5").to_string(force_plain=True), "-700000"
    )
    # Single digit / single trailing zero edge case.
    testing.assert_equal(BigDecimal("5e1").to_string(force_plain=True), "50")
    # scale == 0 path stays unaffected.
    testing.assert_equal(
        BigDecimal("12345").to_string(force_plain=True), "12345"
    )
    # scale > 0 path stays unaffected.
    testing.assert_equal(BigDecimal("1.23").to_string(force_plain=True), "1.23")
    # Round-trip: `from_string(to_string(force_plain=True))` must equal
    # the original value (this is what `Decimal128.from_decimal()` relies
    # on for overflow detection).
    var huge = BigDecimal("1e40")
    var round_trip = BigDecimal(huge.to_string(force_plain=True))
    testing.assert_true(huge == round_trip)


# ===----------------------------------------------------------------------=== #
# number_of_digits()
# ===----------------------------------------------------------------------=== #


def test_number_of_digits_basic() raises:
    """Counts all coefficient digits."""
    testing.assert_equal(BigDecimal("123.456").number_of_digits(), 6)
    testing.assert_equal(BigDecimal("0.00123").number_of_digits(), 3)
    # Trailing zeros in fractional part are stored in the coefficient
    testing.assert_equal(BigDecimal("100.00").number_of_digits(), 5)
    testing.assert_equal(BigDecimal("100").number_of_digits(), 3)
    testing.assert_equal(BigDecimal("1.0000").number_of_digits(), 5)


def test_number_of_digits_zero() raises:
    """Zero has one digit."""
    testing.assert_equal(BigDecimal("0").number_of_digits(), 1)
    testing.assert_equal(BigDecimal("0.0").number_of_digits(), 1)


def test_number_of_digits_after_normalize() raises:
    """After normalize(), trailing zeros are stripped, reducing digit count."""
    # "1.0000" normalizes to "1" (coefficient = 1, scale = 0)
    var one_with_zeros = BigDecimal("1.0000")
    testing.assert_equal(one_with_zeros.number_of_digits(), 5)
    var normalized = one_with_zeros.normalize()
    testing.assert_equal(normalized.number_of_digits(), 1)


def test_number_of_digits_zero_normalize() raises:
    """Normalizing zero keeps 1 digit."""
    var z = BigDecimal("0")
    testing.assert_equal(z.number_of_digits(), 1)
    var zn = z.normalize()
    testing.assert_equal(zn.number_of_digits(), 1)


def test_number_of_digits_large_integer() raises:
    """Large integers keep all digits in the coefficient."""
    var big = BigDecimal("100")
    testing.assert_equal(big.number_of_digits(), 3)
    # normalize() removes trailing zeros: coefficient becomes 1, scale=-2
    var big_norm = big.normalize()
    testing.assert_equal(big_norm.number_of_digits(), 1)


# ===----------------------------------------------------------------------=== #
# as_tuple()
# ===----------------------------------------------------------------------=== #


def test_as_tuple_positive_decimal() raises:
    """7.25 → (False, [7,2,5], -2)."""
    var t = BigDecimal("7.25").as_tuple()
    testing.assert_false(t[0], "sign should be False for positive")
    testing.assert_equal(len(t[1]), 3, "digits length")
    testing.assert_equal(Int(t[1][0]), 7)
    testing.assert_equal(Int(t[1][1]), 2)
    testing.assert_equal(Int(t[1][2]), 5)
    testing.assert_equal(t[2], -2, "exponent")


def test_as_tuple_negative_decimal() raises:
    """-0.001 → (True, [1], -3)."""
    var t = BigDecimal("-0.001").as_tuple()
    testing.assert_true(t[0], "sign should be True for negative")
    testing.assert_equal(len(t[1]), 1)
    testing.assert_equal(Int(t[1][0]), 1)
    testing.assert_equal(t[2], -3, "exponent")


def test_as_tuple_integer() raises:
    """12345 → (False, [1,2,3,4,5], 0)."""
    var t = BigDecimal("12345").as_tuple()
    testing.assert_false(t[0])
    testing.assert_equal(len(t[1]), 5)
    testing.assert_equal(Int(t[1][0]), 1)
    testing.assert_equal(Int(t[1][4]), 5)
    testing.assert_equal(t[2], 0)


def test_as_tuple_scientific_positive_exp() raises:
    """1E+5 → (False, [1], 5)."""
    var t = BigDecimal("1E+5").as_tuple()
    testing.assert_false(t[0])
    testing.assert_equal(len(t[1]), 1)
    testing.assert_equal(Int(t[1][0]), 1)
    testing.assert_equal(t[2], 5)


def test_as_tuple_zero() raises:
    """0 → (False, [0], 0)."""
    var t = BigDecimal("0").as_tuple()
    testing.assert_false(t[0], "zero is not negative")
    testing.assert_equal(len(t[1]), 1)
    testing.assert_equal(Int(t[1][0]), 0)
    testing.assert_equal(t[2], 0)


def test_as_tuple_reconstruct() raises:
    """Round-trip: reconstruct BigDecimal from (sign, digits, exponent)."""
    var values: List[String] = ["123.456", "-0.001", "12345", "0"]
    for vi in range(len(values)):
        var d = BigDecimal(values[vi])
        var t = d.as_tuple()
        # Rebuild coefficient string from digit list
        var coef_str = String()
        for i in range(len(t[1])):
            coef_str += String(Int(t[1][i]))
        # exponent = -scale  =>  scale = -exponent
        var reconstructed = BigDecimal(
            BigUInt(coef_str), scale=-t[2], sign=t[0]
        )
        testing.assert_equal(
            String(reconstructed),
            String(d),
            "round-trip for " + values[vi],
        )


# ===----------------------------------------------------------------------=== #
# copy_abs() / copy_negate() / copy_sign()
# ===----------------------------------------------------------------------=== #


def test_copy_abs_positive() raises:
    """Positive value unchanged."""
    var x = BigDecimal("3.14")
    testing.assert_equal(String(x.copy_abs()), "3.14")


def test_copy_abs_negative() raises:
    """Negative value becomes positive."""
    var x = BigDecimal("-3.14")
    testing.assert_equal(String(x.copy_abs()), "3.14")


def test_copy_abs_zero() raises:
    """Zero stays zero."""
    testing.assert_equal(String(BigDecimal("0").copy_abs()), "0")


def test_copy_abs_matches_abs() raises:
    """Verify copy_abs() == abs(x)."""
    var x = BigDecimal("-42.5")
    testing.assert_equal(String(x.copy_abs()), String(x.__abs__()))


def test_copy_negate_positive() raises:
    """Positive becomes negative."""
    testing.assert_equal(String(BigDecimal("3.14").copy_negate()), "-3.14")


def test_copy_negate_negative() raises:
    """Negative becomes positive."""
    testing.assert_equal(String(BigDecimal("-3.14").copy_negate()), "3.14")


def test_copy_negate_zero() raises:
    """Negating zero."""
    var z = BigDecimal("0").copy_negate()
    # Zero negated — coefficient is still 0
    testing.assert_true(z.is_zero())


def test_copy_negate_matches_neg() raises:
    """Verify copy_negate() == -x."""
    var x = BigDecimal("42.5")
    testing.assert_equal(String(x.copy_negate()), String(x.__neg__()))


def test_copy_sign_positive_to_negative() raises:
    """Copy sign of negative onto positive value."""
    var x = BigDecimal("3.14")
    var y = BigDecimal("-1")
    testing.assert_equal(String(x.copy_sign(y)), "-3.14")


def test_copy_sign_negative_to_positive() raises:
    """Copy sign of positive onto negative value."""
    var x = BigDecimal("-3.14")
    var y = BigDecimal("1")
    testing.assert_equal(String(x.copy_sign(y)), "3.14")


def test_copy_sign_same_sign() raises:
    """Same sign leaves value unchanged."""
    var x = BigDecimal("3.14")
    var y = BigDecimal("99")
    testing.assert_equal(String(x.copy_sign(y)), "3.14")


def test_copy_sign_zero_source() raises:
    """Zero takes sign of other."""
    var x = BigDecimal("0")
    var y = BigDecimal("-5")
    var result = x.copy_sign(y)
    # Sign bit set but coefficient is 0
    testing.assert_true(result.sign)
    testing.assert_true(result.is_zero())


# ===----------------------------------------------------------------------=== #
# adjusted()
# ===----------------------------------------------------------------------=== #


def test_adjusted_basic() raises:
    """Basic adjusted exponent values."""
    testing.assert_equal(BigDecimal("123.45").adjusted(), 2)
    testing.assert_equal(BigDecimal("0.00123").adjusted(), -3)
    testing.assert_equal(BigDecimal("100").adjusted(), 2)
    testing.assert_equal(BigDecimal("1").adjusted(), 0)
    testing.assert_equal(BigDecimal("10").adjusted(), 1)


def test_adjusted_zero() raises:
    """Zero has adjusted exponent 0 regardless of scale."""
    testing.assert_equal(BigDecimal("0").adjusted(), 0)
    testing.assert_equal(BigDecimal("0.00").adjusted(), 0)
    testing.assert_equal(BigDecimal("0.000000").adjusted(), 0)
    testing.assert_equal(BigDecimal("0E+10").adjusted(), 0)


def test_adjusted_scientific() raises:
    """Scientific notation inputs."""
    testing.assert_equal(BigDecimal("1E+5").adjusted(), 5)
    testing.assert_equal(BigDecimal("1E-5").adjusted(), -5)
    testing.assert_equal(BigDecimal("1.23E+10").adjusted(), 10)


# ===----------------------------------------------------------------------=== #
# same_quantum()
# ===----------------------------------------------------------------------=== #


def test_same_quantum_same_scale() raises:
    """Same scale returns True."""
    testing.assert_true(BigDecimal("1.23").same_quantum(BigDecimal("4.56")))
    testing.assert_true(BigDecimal("100").same_quantum(BigDecimal("1")))
    testing.assert_true(BigDecimal("0").same_quantum(BigDecimal("5")))


def test_same_quantum_different_scale() raises:
    """Different scale returns False."""
    testing.assert_false(BigDecimal("1.2").same_quantum(BigDecimal("4.56")))
    testing.assert_false(BigDecimal("1").same_quantum(BigDecimal("1.0")))
    testing.assert_false(BigDecimal("0").same_quantum(BigDecimal("0.00")))


def test_same_quantum_negative() raises:
    """Sign does not affect quantum comparison."""
    testing.assert_true(BigDecimal("1.23").same_quantum(BigDecimal("-4.56")))
    testing.assert_true(BigDecimal("-1.23").same_quantum(BigDecimal("4.56")))


def test_same_quantum_zero_variants() raises:
    """Zeros with different scales have different quanta."""
    testing.assert_true(BigDecimal("0").same_quantum(BigDecimal("0")))
    testing.assert_true(BigDecimal("0.00").same_quantum(BigDecimal("0.00")))
    testing.assert_false(BigDecimal("0").same_quantum(BigDecimal("0.0")))


# ===----------------------------------------------------------------------=== #
# scaleb()
# ===----------------------------------------------------------------------=== #


def test_scaleb_positive() raises:
    """Tests scaleb with positive n multiplies value by 10^n."""
    testing.assert_equal(String(BigDecimal("1.23").scaleb(2)), "123")
    testing.assert_equal(String(BigDecimal("5").scaleb(3)), "5E+3")


def test_scaleb_negative() raises:
    """Tests scaleb with negative n divides value by 10^|n|."""
    testing.assert_equal(String(BigDecimal("1.23").scaleb(-2)), "0.0123")
    testing.assert_equal(String(BigDecimal("100").scaleb(-1)), "10.0")


def test_scaleb_zero() raises:
    """Tests scaleb(0) returns the same value."""
    testing.assert_equal(String(BigDecimal("42.5").scaleb(0)), "42.5")


def test_scaleb_on_zero() raises:
    """Tests scaleb on zero adjusts scale but value stays zero."""
    var result = BigDecimal("0").scaleb(5)
    testing.assert_true(result.is_zero())


# ===----------------------------------------------------------------------=== #
# fma()
# ===----------------------------------------------------------------------=== #


def test_fma_basic() raises:
    """Tests fma(a, b) = self * a + b."""
    var result = BigDecimal("2").fma(BigDecimal("3"), BigDecimal("4"))
    testing.assert_equal(String(result), "10")


def test_fma_decimal() raises:
    """Tests fma with fractional values."""
    var result = BigDecimal("1.5").fma(BigDecimal("2"), BigDecimal("0.1"))
    testing.assert_equal(String(result), "3.1")


def test_fma_negative() raises:
    """Tests fma with negative values."""
    var result = BigDecimal("-3").fma(BigDecimal("4"), BigDecimal("15"))
    testing.assert_equal(String(result), "3")


def test_fma_zero_multiplier() raises:
    """Tests fma with zero multiplier: 0 * a + b = b."""
    var result = BigDecimal("0").fma(BigDecimal("999"), BigDecimal("42"))
    testing.assert_equal(String(result), "42")


# ===----------------------------------------------------------------------=== #
# to_string_with_separators()
# ===----------------------------------------------------------------------=== #


def test_to_string_with_separators_default() raises:
    """Tests to_string_with_separators with default separator."""
    testing.assert_equal(
        BigDecimal("1234567").to_string_with_separators(), "1_234_567"
    )


def test_to_string_with_separators_comma() raises:
    """Tests to_string_with_separators with custom comma separator."""
    testing.assert_equal(
        BigDecimal("1234567.89").to_string_with_separators(","),
        "1,234,567.89",
    )


def test_to_string_with_separators_small() raises:
    """Tests to_string_with_separators with numbers having fewer than 4 digits.
    """
    testing.assert_equal(BigDecimal("123").to_string_with_separators(), "123")


def test_to_string_with_separators_negative() raises:
    """Tests to_string_with_separators with negative numbers."""
    testing.assert_equal(
        BigDecimal("-1234567").to_string_with_separators(), "-1_234_567"
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
