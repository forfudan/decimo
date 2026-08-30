# ===----------------------------------------------------------------------=== #
# Test BigInt basic functionality
# ===----------------------------------------------------------------------=== #

from std import testing
from decimo.bigint.bigint import BigInt


def test_default_constructor() raises:
    """Test that default constructor creates zero."""
    var x = BigInt()
    assert_true(x.is_zero(), "Default constructor should be zero")
    assert_true(not x.is_negative(), "Zero should not be negative")
    assert_true(not x.is_positive(), "Zero should not be positive")
    assert_true(String(x) == "0", "Zero should stringify to '0'")


def test_from_int() raises:
    """Test construction from Int."""
    var zero = BigInt(0)
    assert_true(zero.is_zero(), "BigInt(0) should be zero")
    assert_true(String(zero) == "0", "BigInt(0) should be '0'")

    var one = BigInt(1)
    assert_true(one.is_one(), "BigInt(1) should be one")
    assert_true(String(one) == "1", "BigInt(1): " + String(one))

    var neg_one = BigInt(-1)
    assert_true(neg_one.is_negative(), "-1 should be negative")
    assert_true(String(neg_one) == "-1", "BigInt(-1): " + String(neg_one))

    var large = BigInt(1_000_000_000)
    assert_true(
        String(large) == "1000000000",
        "BigInt(1000000000): " + String(large),
    )

    var large_neg = BigInt(-9_876_543_210)
    assert_true(
        String(large_neg) == "-9876543210",
        "BigInt(-9876543210): " + String(large_neg),
    )

    # A value past the old 32-bit word boundary; one word now
    var two_words = BigInt(0xFFFF_FFFF + 1)  # 2^32 = 4294967296
    assert_true(
        String(two_words) == "4294967296",
        "BigInt(2^32): " + String(two_words),
    )


def test_from_string() raises:
    """Test construction from String."""
    var zero = BigInt("0")
    assert_true(zero.is_zero(), "from_string('0') should be zero")

    var one = BigInt("1")
    assert_true(String(one) == "1", "from_string('1'): " + String(one))

    var neg = BigInt("-42")
    assert_true(String(neg) == "-42", "from_string('-42'): " + String(neg))

    var large = BigInt("123456789012345678901234567890")
    assert_true(
        String(large) == "123456789012345678901234567890",
        "from_string large: " + String(large),
    )

    var neg_large = BigInt("-999999999999999999999999999999")
    assert_true(
        String(neg_large) == "-999999999999999999999999999999",
        "from_string neg_large: " + String(neg_large),
    )

    # Leading zeros
    var leading = BigInt("00042")
    assert_true(
        String(leading) == "42", "from_string('00042'): " + String(leading)
    )

    # Plus sign
    var plus = BigInt("+100")
    assert_true(String(plus) == "100", "from_string('+100'): " + String(plus))


def test_negation_and_abs() raises:
    """Test __neg__ and __abs__."""
    var pos = BigInt(42)
    var neg = -pos
    assert_true(String(neg) == "-42", "neg(42): " + String(neg))

    var abs_neg = abs(neg)
    assert_true(String(abs_neg) == "42", "abs(-42): " + String(abs_neg))

    var zero = BigInt(0)
    var neg_zero = -zero
    assert_true(neg_zero.is_zero(), "neg(0) should be zero")
    assert_true(not neg_zero.sign, "neg(0) sign should be False")


def test_hex_and_binary_string() raises:
    """Test to_hex_string and to_binary_string."""
    var zero = BigInt(0)
    assert_true(
        zero.to_hex_string() == "0x0", "hex(0): " + zero.to_hex_string()
    )
    assert_true(
        zero.to_binary_string() == "0b0",
        "bin(0): " + zero.to_binary_string(),
    )

    var val = BigInt(255)
    assert_true(
        val.to_hex_string() == "0xff",
        "hex(255): " + val.to_hex_string(),
    )
    assert_true(
        val.to_binary_string() == "0b11111111",
        "bin(255): " + val.to_binary_string(),
    )

    var neg = BigInt(-16)
    assert_true(
        neg.to_hex_string() == "-0x10",
        "hex(-16): " + neg.to_hex_string(),
    )


def test_bit_length() raises:
    """Test bit_length."""
    var zero = BigInt(0)
    assert_true(zero.bit_length() == 0, "bit_length(0)")

    var one = BigInt(1)
    assert_true(one.bit_length() == 1, "bit_length(1)")

    var two = BigInt(2)
    assert_true(two.bit_length() == 2, "bit_length(2)")

    var val_255 = BigInt(255)
    assert_true(val_255.bit_length() == 8, "bit_length(255)")

    var val_256 = BigInt(256)
    assert_true(val_256.bit_length() == 9, "bit_length(256)")


def test_copy() raises:
    """Test copy method."""
    var original = BigInt("12345678901234567890")
    var copied = original.copy()
    assert_true(
        String(copied) == String(original), "copy should equal original"
    )
    # Verify it's a deep copy by modifying the original
    original.words[0] = 0
    assert_true(
        String(copied) != String(original),
        "copy should be independent of original",
    )


def test_normalize() raises:
    """Test _normalize strips leading zeros and normalizes -0."""
    var x = BigInt(raw_words=[UInt64(42), UInt64(0), UInt64(0)], sign=False)
    x._normalize()
    assert_true(len(x.words) == 1, "normalize should strip leading zeros")
    assert_true(x.words[0] == 42, "normalize should preserve value")

    # Test -0 normalization
    var neg_zero = BigInt(raw_words=[UInt64(0)], sign=True)
    neg_zero._normalize()
    assert_true(not neg_zero.sign, "-0 should normalize to +0")


def test_print_internal() raises:
    """Smoke test for print_internal_representation."""
    var x = BigInt("1234567890123456789")
    x.print_internal_representation()


def assert_true(cond: Bool, msg: String) raises:
    if not cond:
        raise Error("FAIL: " + msg)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
