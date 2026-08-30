"""
Test BigInt power and shift operations: __pow__, __lshift__, __rshift__,
augmented assignment (<<=, >>=), and power-of-2 vs shift cross-checks.
"""

from std import testing

from decimo.bigint.bigint import BigInt


# ===----------------------------------------------------------------------=== #
# Test: __pow__ / power
# ===----------------------------------------------------------------------=== #


def test_power_basic() raises:
    """Test basic exponentiation."""
    # 2^10 = 1024
    testing.assert_equal(String(BigInt(2) ** 10), "1024")

    # 3^5 = 243
    testing.assert_equal(String(BigInt(3) ** 5), "243")

    # 10^0 = 1
    testing.assert_equal(String(BigInt(10) ** 0), "1")

    # 0^0 = 1 (convention)
    testing.assert_equal(String(BigInt(0) ** 0), "1")

    # 7^1 = 7
    testing.assert_equal(String(BigInt(7) ** 1), "7")

    # 1^1000 = 1
    testing.assert_equal(String(BigInt(1) ** 1000), "1")

    # 0^5 = 0
    testing.assert_equal(String(BigInt(0) ** 5), "0")


def test_power_negative_base() raises:
    """Test exponentiation with negative base."""
    # (-2)^3 = -8
    testing.assert_equal(String(BigInt(-2) ** 3), "-8")

    # (-2)^4 = 16
    testing.assert_equal(String(BigInt(-2) ** 4), "16")

    # (-1)^0 = 1
    testing.assert_equal(String(BigInt(-1) ** 0), "1")

    # (-1)^1 = -1
    testing.assert_equal(String(BigInt(-1) ** 1), "-1")

    # (-1)^100 = 1
    testing.assert_equal(String(BigInt(-1) ** 100), "1")

    # (-1)^99 = -1
    testing.assert_equal(String(BigInt(-1) ** 99), "-1")


def test_power_large() raises:
    """Test exponentiation with large results."""
    # 2^64 = 18446744073709551616
    testing.assert_equal(String(BigInt(2) ** 64), "18446744073709551616")

    # 2^100 = 1267650600228229401496703205376
    testing.assert_equal(
        String(BigInt(2) ** 100),
        "1267650600228229401496703205376",
    )

    # 10^20 = 100000000000000000000
    testing.assert_equal(String(BigInt(10) ** 20), "100000000000000000000")


def test_power_bigint_exponent() raises:
    """Test exponentiation with BigInt exponent."""
    var base = BigInt(2)
    var exp = BigInt(10)
    testing.assert_equal(String(base**exp), "1024")


def test_power_negative_exponent_raises() raises:
    """Test that negative exponent raises an error."""
    var raised = False
    try:
        _ = BigInt(2) ** -1
    except:
        raised = True
    testing.assert_true(raised, "Negative exponent should raise")


# ===----------------------------------------------------------------------=== #
# Test: __lshift__ / __rshift__
# ===----------------------------------------------------------------------=== #


def test_left_shift_basic() raises:
    """Test basic left shift operations."""
    # 1 << 0 == 1
    testing.assert_equal(String(BigInt(1) << 0), "1")

    # 1 << 1 == 2
    testing.assert_equal(String(BigInt(1) << 1), "2")

    # 1 << 32 == 4294967296 == 2^32
    testing.assert_equal(String(BigInt(1) << 32), "4294967296")

    # 1 << 64 == 2^64
    testing.assert_equal(String(BigInt(1) << 64), "18446744073709551616")

    # 5 << 3 == 40
    testing.assert_equal(String(BigInt(5) << 3), "40")

    # 0 << 100 == 0
    testing.assert_equal(String(BigInt(0) << 100), "0")


def test_left_shift_negative() raises:
    """Test left shift with negative numbers."""
    # -1 << 1 == -2
    testing.assert_equal(String(BigInt(-1) << 1), "-2")

    # -5 << 3 == -40
    testing.assert_equal(String(BigInt(-5) << 3), "-40")


def test_right_shift_basic() raises:
    """Test basic right shift operations."""
    # 1 >> 0 == 1
    testing.assert_equal(String(BigInt(1) >> 0), "1")

    # 1 >> 1 == 0
    testing.assert_equal(String(BigInt(1) >> 1), "0")

    # 8 >> 3 == 1
    testing.assert_equal(String(BigInt(8) >> 3), "1")

    # 255 >> 4 == 15
    testing.assert_equal(String(BigInt(255) >> 4), "15")

    # 0 >> 100 == 0
    testing.assert_equal(String(BigInt(0) >> 100), "0")


def test_right_shift_large() raises:
    """Test right shift with large values."""
    # 2^64 >> 32 = 2^32 = 4294967296
    var val = BigInt(1) << 64
    testing.assert_equal(String(val >> 32), "4294967296")

    # 2^64 >> 64 = 1
    testing.assert_equal(String(val >> 64), "1")

    # 2^64 >> 65 = 0
    testing.assert_equal(String(val >> 65), "0")


def test_right_shift_negative() raises:
    """Test right shift with negative numbers (Python-compatible arithmetic)."""
    # -1 >> 1 == -1 (Python behavior: floor toward -inf)
    testing.assert_equal(String(BigInt(-1) >> 1), "-1")

    # -8 >> 3 == -1
    testing.assert_equal(String(BigInt(-8) >> 3), "-1")

    # -7 >> 1 == -4 (Python: -7 // 2 = -4)
    testing.assert_equal(String(BigInt(-7) >> 1), "-4")

    # -100 >> 3 == -13 (Python: -100 // 8 = -13)
    testing.assert_equal(String(BigInt(-100) >> 3), "-13")

    # -1 >> 100 == -1 (any rshift of -1 is still -1)
    testing.assert_equal(String(BigInt(-1) >> 100), "-1")


def test_shift_augmented_assignment() raises:
    """Test <<= and >>= augmented assignment operators."""
    var x = BigInt(1)
    x <<= 10
    testing.assert_equal(String(x), "1024")

    x >>= 5
    testing.assert_equal(String(x), "32")


def test_shift_roundtrip() raises:
    """Test that left shift then right shift recovers original value."""
    var original = BigInt("123456789012345678901234567890")
    var shifted = original << 100
    var recovered = shifted >> 100
    testing.assert_equal(String(recovered), String(original))


# ===----------------------------------------------------------------------=== #
# Test: power of 2 cross-checks with shifts
# ===----------------------------------------------------------------------=== #


def test_power_of_2_vs_shift() raises:
    """Verify that 2**n equals 1 << n for various n."""
    testing.assert_equal(String(BigInt(2) ** 0), String(BigInt(1) << 0))
    testing.assert_equal(String(BigInt(2) ** 1), String(BigInt(1) << 1))
    testing.assert_equal(String(BigInt(2) ** 31), String(BigInt(1) << 31))
    testing.assert_equal(String(BigInt(2) ** 32), String(BigInt(1) << 32))
    testing.assert_equal(String(BigInt(2) ** 63), String(BigInt(1) << 63))
    testing.assert_equal(String(BigInt(2) ** 64), String(BigInt(1) << 64))
    testing.assert_equal(String(BigInt(2) ** 100), String(BigInt(1) << 100))
    testing.assert_equal(String(BigInt(2) ** 128), String(BigInt(1) << 128))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
