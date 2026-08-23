"""
Test BigInt conversion: to_int, from_integral_scalar, from_string with
various formats (commas, underscores, spaces, scientific notation, decimal
point), and D&C from_string for large numbers.
"""

from std import testing
from decimo.bigint.bigint import BigInt
from decimo.bigint10.bigint10 import BigInt10
from decimo.biguint.biguint import BigUInt


# ===----------------------------------------------------------------------=== #
# Test: to_int / __int__
# ===----------------------------------------------------------------------=== #


def test_to_int_small_positive() raises:
    """Test to_int with small positive numbers."""
    testing.assert_equal(Int(BigInt(0)), 0)
    testing.assert_equal(Int(BigInt(1)), 1)
    testing.assert_equal(Int(BigInt(42)), 42)
    testing.assert_equal(Int(BigInt(1000000)), 1000000)


def test_to_int_small_negative() raises:
    """Test to_int with small negative numbers."""
    testing.assert_equal(Int(BigInt(-1)), -1)
    testing.assert_equal(Int(BigInt(-42)), -42)
    testing.assert_equal(Int(BigInt(-1000000)), -1000000)


def test_to_int_large_values() raises:
    """Test to_int with values near Int.MAX and Int.MIN."""
    # Int.MAX = 9_223_372_036_854_775_807
    var max_val = BigInt("9223372036854775807")
    testing.assert_equal(Int(max_val), 9223372036854775807)

    # Int.MIN = -9_223_372_036_854_775_808
    var min_val = BigInt("-9223372036854775808")
    testing.assert_equal(Int(min_val), Int.MIN)


def test_to_int_overflow() raises:
    """Test to_int raises on overflow."""
    var too_large = BigInt("9223372036854775808")  # Int.MAX + 1
    var raised = False
    try:
        _ = Int(too_large)
    except:
        raised = True
    testing.assert_true(raised, "to_int should raise for Int.MAX + 1")

    var too_small = BigInt("-9223372036854775809")  # Int.MIN - 1
    raised = False
    try:
        _ = Int(too_small)
    except:
        raised = True
    testing.assert_true(raised, "to_int should raise for Int.MIN - 1")

    var huge = BigInt("99999999999999999999999999999999999")
    raised = False
    try:
        _ = Int(huge)
    except:
        raised = True
    testing.assert_true(raised, "to_int should raise for very large number")


# ===----------------------------------------------------------------------=== #
# Test: from_int edge cases (Int.MIN, Int.MAX)
# ===----------------------------------------------------------------------=== #


def test_from_int_edge_cases() raises:
    """Test from_int with Int.MIN, Int.MAX, and other edge values."""
    # Int.MAX via from_int path
    var max_val = BigInt(Int.MAX)
    testing.assert_equal(String(max_val), "9223372036854775807")
    testing.assert_equal(Int(max_val), Int.MAX)

    # Int.MIN via from_int path — the critical edge case
    var min_val = BigInt(Int.MIN)
    testing.assert_equal(String(min_val), "-9223372036854775808")
    testing.assert_equal(Int(min_val), Int.MIN)

    # -1 via from_int
    var neg_one = BigInt(-1)
    testing.assert_equal(String(neg_one), "-1")

    # 0 via from_int
    var zero = BigInt(Int(0))
    testing.assert_equal(String(zero), "0")


# ===----------------------------------------------------------------------=== #
# Test: from_integral_scalar / Scalar constructor
# ===----------------------------------------------------------------------=== #


def test_from_integral_scalar() raises:
    """Test construction from Scalar types."""
    # UInt8
    var u8 = BigInt(UInt8(255))
    testing.assert_equal(String(u8), "255")

    # Int8
    var i8 = BigInt(Int8(-128))
    testing.assert_equal(String(i8), "-128")

    # UInt16
    var u16 = BigInt(UInt16(65535))
    testing.assert_equal(String(u16), "65535")

    # Int16
    var i16 = BigInt(Int16(-32768))
    testing.assert_equal(String(i16), "-32768")

    # UInt32
    var u32 = BigInt(UInt32(4294967295))
    testing.assert_equal(String(u32), "4294967295")

    # Int32
    var i32 = BigInt(Int32(-2147483648))
    testing.assert_equal(String(i32), "-2147483648")

    # UInt64
    var u64 = BigInt(UInt64(18446744073709551615))
    testing.assert_equal(String(u64), "18446744073709551615")

    # Int64
    var i64 = BigInt(Int64(-9223372036854775808))
    testing.assert_equal(String(i64), "-9223372036854775808")

    # UInt128
    var u128_small = BigInt(UInt128(12345))
    testing.assert_equal(String(u128_small), "12345")

    var u128_large = BigInt(UInt128(80554649779790687400))
    testing.assert_equal(String(u128_large), "80554649779790687400")

    # UInt128.MAX = 340282366920938463463374607431768211455
    var u128_max = BigInt(UInt128.MAX)
    testing.assert_equal(
        String(u128_max), "340282366920938463463374607431768211455"
    )

    # Int128
    var i128_pos = BigInt(Int128(80554649779790687400))
    testing.assert_equal(String(i128_pos), "80554649779790687400")

    var i128_neg = BigInt(Int128(-80554649779790687400))
    testing.assert_equal(String(i128_neg), "-80554649779790687400")

    # Int128.MIN = -170141183460469231731687303715884105728
    var i128_min = BigInt(Int128.MIN)
    testing.assert_equal(
        String(i128_min), "-170141183460469231731687303715884105728"
    )

    # Int128.MAX = 170141183460469231731687303715884105727
    var i128_max = BigInt(Int128.MAX)
    testing.assert_equal(
        String(i128_max), "170141183460469231731687303715884105727"
    )

    # UInt256
    var u256_small = BigInt(UInt256(12345))
    testing.assert_equal(String(u256_small), "12345")

    var u256_large = BigInt(UInt256(80554649779790687400))
    testing.assert_equal(String(u256_large), "80554649779790687400")

    # UInt256 value larger than UInt64.MAX
    var u256_big = BigInt(UInt256(8055464977979068740023761289648172697))
    testing.assert_equal(
        String(u256_big), "8055464977979068740023761289648172697"
    )

    # Int256
    var i256_pos = BigInt(Int256(8055464977979068740023761289648172697))
    testing.assert_equal(
        String(i256_pos), "8055464977979068740023761289648172697"
    )

    var i256_neg = BigInt(Int256(-8055464977979068740023761289648172697))
    testing.assert_equal(
        String(i256_neg), "-8055464977979068740023761289648172697"
    )

    # Int256.MIN
    var i256_min = BigInt(Int256.MIN)
    testing.assert_equal(
        String(i256_min),
        "-57896044618658097711785492504343953926634992332820282019728792003956564819968",
    )

    # Int256.MAX
    var i256_max = BigInt(Int256.MAX)
    testing.assert_equal(
        String(i256_max),
        "57896044618658097711785492504343953926634992332820282019728792003956564819967",
    )

    # Platform-sized UInt
    var u_plat = BigInt(UInt(18446744073709551615))
    testing.assert_equal(String(u_plat), "18446744073709551615")

    # Platform-sized Int
    var i_plat_pos = BigInt(Scalar[DType.int](1234567890))
    testing.assert_equal(String(i_plat_pos), "1234567890")

    var i_plat_neg = BigInt(Scalar[DType.int](-1234567890))
    testing.assert_equal(String(i_plat_neg), "-1234567890")

    # Zero for various types
    testing.assert_equal(String(BigInt(UInt8(0))), "0")
    testing.assert_equal(String(BigInt(Int32(0))), "0")
    testing.assert_equal(String(BigInt(UInt64(0))), "0")
    testing.assert_equal(String(BigInt(Int128(0))), "0")
    testing.assert_equal(String(BigInt(UInt256(0))), "0")
    testing.assert_equal(String(BigInt(Int256(0))), "0")


# ===----------------------------------------------------------------------=== #
# Test: D&C from_string for large numbers
# ===----------------------------------------------------------------------=== #


def test_from_string_large_dc() raises:
    """Test from_string round-trip for large numbers (500–2000 digits).
    These sizes exercise the simple O(n²) path. The D&C path is only
    entered at >10000 digits and is tested in test_from_string_dc_path.
    """

    # Case 1: 500-digit number
    # Construct via arithmetic: 10^499 + 42
    var a1 = BigInt(10).power(499) + BigInt(42)
    var s1 = String(a1)
    var b1 = BigInt(s1)
    testing.assert_true(
        a1 == b1,
        msg="[D&C from_string] round-trip 500-digit number",
    )

    # Case 2: 1000-digit number
    var a2 = BigInt(7) * BigInt(10).power(999) + BigInt(123456789)
    var s2 = String(a2)
    var b2 = BigInt(s2)
    testing.assert_true(
        a2 == b2,
        msg="[D&C from_string] round-trip 1000-digit number",
    )

    # Case 3: 2000-digit negative number
    var a3 = -(BigInt(3) * BigInt(10).power(1999) + BigInt(987654321))
    var s3 = String(a3)
    var b3 = BigInt(s3)
    testing.assert_true(
        a3 == b3,
        msg="[D&C from_string] round-trip 2000-digit negative number",
    )

    # Case 4: Cross-check with BigInt10 path (independent reference)
    var a4 = BigInt(10).power(599) + BigInt(10).power(300) + BigInt(7)
    testing.assert_equal(
        lhs=String(a4),
        rhs=String(BigInt10.from_bigint(a4)),
        msg="[D&C from_string] D&C to_string matches BigInt10 for 600-digit",
    )


# ===----------------------------------------------------------------------=== #
# Test: from_string D&C path (>10000 digits)
# ===----------------------------------------------------------------------=== #


def test_from_string_dc_path() raises:
    """Test that from_string exercises the D&C conversion path by parsing
    a string with >10000 digits (_DC_FROM_STR_ENTRY_THRESHOLD).
    """

    # Build "1" followed by 10500 zeros → 10^10500 (a 10501-digit number)
    var s = String("1") + String("0") * 10500
    var a = BigInt(s)
    # Verify via to_string round-trip
    testing.assert_equal(
        String(a), s, msg="[D&C from_string] 10501-digit round-trip"
    )

    # Cross-check with BigInt10 (independent reference implementation)
    var b = BigInt10(s).to_bigint()
    testing.assert_true(
        a == b,
        msg="[D&C from_string] 10501-digit D&C matches BigInt10 path",
    )

    # Test a non-trivial large number: 7 followed by 10490 zeros then 123456789
    # Build the decimal string directly to avoid expensive power() + to_string
    var s2 = String("7") + String("0") * 10490 + String("123456789")
    var a2 = BigInt(s2)
    # Cross-check against an independent BigInt10-based reference
    var b2 = BigInt10(s2).to_bigint()
    testing.assert_true(
        a2 == b2,
        msg="[D&C from_string] 10500-digit non-trivial round-trip",
    )


# ===----------------------------------------------------------------------=== #
# Test: from_string with various string formats (via parse_numeric_string)
# ===----------------------------------------------------------------------=== #


def test_from_string_with_commas() raises:
    """Test from_string handles commas as thousand separators."""
    testing.assert_equal(String(BigInt("1,234,567")), "1234567")
    testing.assert_equal(String(BigInt("-1,000,000")), "-1000000")
    testing.assert_equal(
        String(BigInt("123,456,789,012,345")), "123456789012345"
    )


def test_from_string_with_underscores() raises:
    """Test from_string handles underscores as digit separators."""
    testing.assert_equal(String(BigInt("1_000_000")), "1000000")
    testing.assert_equal(String(BigInt("-99_999")), "-99999")
    testing.assert_equal(String(BigInt("1_2_3_4_5")), "12345")


def test_from_string_with_spaces() raises:
    """Test from_string handles spaces in the string."""
    testing.assert_equal(String(BigInt(" 42 ")), "42")
    testing.assert_equal(String(BigInt("1 000 000")), "1000000")
    testing.assert_equal(String(BigInt("- 123")), "-123")


def test_from_string_with_scientific_notation() raises:
    """Test from_string handles scientific/exponential notation."""
    # 1.23e5 = 123000
    testing.assert_equal(String(BigInt("1.23e5")), "123000")
    # 5e10 = 50000000000
    testing.assert_equal(String(BigInt("5e10")), "50000000000")
    # -2.5E4 = -25000
    testing.assert_equal(String(BigInt("-2.5E4")), "-25000")
    # 1e0 = 1
    testing.assert_equal(String(BigInt("1e0")), "1")
    # 100e2 = 10000
    testing.assert_equal(String(BigInt("100e2")), "10000")


def test_from_string_with_decimal_point_integer() raises:
    """Test from_string with decimal point where fractional part is zero."""
    testing.assert_equal(String(BigInt("123.0")), "123")
    testing.assert_equal(String(BigInt("100.00")), "100")
    testing.assert_equal(String(BigInt("-42.000")), "-42")


def test_from_string_non_integer_raises() raises:
    """Test from_string raises error for non-integer values."""
    var raised = False
    try:
        _ = BigInt("123.456")
    except:
        raised = True
    testing.assert_true(raised, msg="Should raise for non-integer '123.456'")

    # 1.5e2 = 150, which is an integer, so parsing should not raise.
    raised = False
    try:
        _ = BigInt("1.5e2")
    except:
        raised = True
    testing.assert_false(raised, msg="1.5e2 = 150 should not raise")

    raised = False
    try:
        _ = BigInt("1.23e1")  # 12.3, not integer
    except:
        raised = True
    testing.assert_true(raised, msg="Should raise for non-integer '1.23e1'")


def test_from_string_plus_sign() raises:
    """Tests from_string handles explicit positive sign."""
    testing.assert_equal(String(BigInt("+42")), "42")
    testing.assert_equal(String(BigInt("+0")), "0")
    testing.assert_equal(String(BigInt("+1,000")), "1000")


# ===----------------------------------------------------------------------=== #
# Test: __float__
# ===----------------------------------------------------------------------=== #


def test_float_small() raises:
    """Tests __float__ with small integers."""
    testing.assert_equal(Float64(BigInt(0)), 0.0)
    testing.assert_equal(Float64(BigInt(1)), 1.0)
    testing.assert_equal(Float64(BigInt(42)), 42.0)
    testing.assert_equal(Float64(BigInt(-7)), -7.0)


def test_float_large() raises:
    """Tests __float__ with a large-ish integer."""
    testing.assert_equal(Float64(BigInt(1000000)), 1000000.0)


# ===----------------------------------------------------------------------=== #
# Test: to_biguint / from_biguint
# ===----------------------------------------------------------------------=== #


def test_biguint_round_trip() raises:
    """A BigInt survives the trip through base-10^9 and back."""
    for value in [
        String("0"),
        String("1"),
        String("-1"),
        String("999999999"),
        String("1000000000"),
        String("-123456789012345678901234567890"),
    ]:
        var n = BigInt(value)
        var back = BigInt.from_biguint(n.to_biguint(), n.is_negative())
        testing.assert_equal(String(back), String(n))


def test_to_biguint_drops_the_sign() raises:
    """`to_biguint` hands back the magnitude, not the value."""
    testing.assert_equal(String(BigInt("-42").to_biguint()), "42")
    testing.assert_equal(String(BigInt("42").to_biguint()), "42")
    # Zero is unsigned whatever sign is asked for.
    testing.assert_equal(String(BigInt.from_biguint(BigUInt(), True)), "0")


def test_to_biguint_large_takes_the_dc_path() raises:
    """Above the D&C threshold the fast path must agree with the slow one.

    2000 digits is well past `_DC_TO_STR_ENTRY_THRESHOLD` (128 words, about
    1230 digits), so this exercises the divide-and-conquer conversion; the
    decimal string is the independent reference.
    """
    var digits = String("1234567890") * 200
    var n = BigInt(digits)
    testing.assert_equal(String(n.to_biguint()), digits)
    testing.assert_equal(String(BigInt("-" + digits).to_biguint()), digits)


def _digit_run(count: Int) -> String:
    """Builds a `count`-digit decimal string with no leading zero."""
    var out = String("1")
    var x = 7
    for j in range(count - 1):
        x = (x * 7 + j) % 10
        out += String(x)
    return out^


def test_to_biguint_sweeps_the_dc_split_points() raises:
    """`to_biguint()` must agree with the decimal string at every size.

    The divide-and-conquer conversion splits on powers of `10^9` so that each
    half lands on a base-10^9 word boundary and its words can be written
    straight into the output buffer. That makes the split points, not the
    magnitudes, the interesting cases: the sizes below bracket the entry
    threshold (128 binary words, about 1 230 digits) and the points where a
    subproblem exactly fills its slot in the buffer or falls one word short.
    Each value is also tested shifted up by `10^37`, because a high half whose
    low words are zero has to leave the zeros already sitting in its slot
    alone instead of writing over the word boundary.
    """
    var sizes = [
        1,
        9,
        10,
        18,
        19,
        1229,
        1230,
        1231,
        1232,
        2303,
        2304,
        2305,
        4607,
        4608,
        4609,
        5000,
    ]

    for i in range(len(sizes)):
        var digits = _digit_run(sizes[i])
        var n = BigInt(digits)
        testing.assert_equal(
            String(n.to_biguint()),
            digits,
            String("to_biguint() disagrees at ") + String(sizes[i]) + " digits",
        )

        var padded = n * BigInt(10) ** 37
        testing.assert_equal(
            String(padded.to_biguint()),
            String(padded),
            String("to_biguint() disagrees at ")
            + String(sizes[i])
            + " digits with a trailing zero run",
        )


def test_bigint10_bridge() raises:
    """The legacy BigInt10 bridge round-trips through BigInt."""
    for value in [
        String("0"),
        String("-1"),
        String("123456789012345678901234567890"),
        String("-987654321098765432109876543210"),
    ]:
        var b10 = BigInt10(value)
        testing.assert_equal(String(b10.to_bigint()), value)
        testing.assert_equal(String(BigInt10.from_bigint(BigInt(value))), value)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
