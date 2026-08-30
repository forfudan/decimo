"""
Test BigInt string formatting: to_string_with_separators,
to_string with line_width, number_of_digits, __repr__, and the hex and
binary renderings.
"""

from std import testing

from decimo.bigint.bigint import BigInt


# ===----------------------------------------------------------------------=== #
# Test: to_string_with_separators
# ===----------------------------------------------------------------------=== #


def test_to_string_with_separators() raises:
    """Test to_string_with_separators."""
    testing.assert_equal(BigInt(0).to_string_with_separators(), "0")
    testing.assert_equal(BigInt(1).to_string_with_separators(), "1")
    testing.assert_equal(BigInt(100).to_string_with_separators(), "100")
    testing.assert_equal(BigInt(1000).to_string_with_separators(), "1_000")
    testing.assert_equal(
        BigInt(1000000).to_string_with_separators(), "1_000_000"
    )
    testing.assert_equal(
        BigInt(-1234567).to_string_with_separators(), "-1_234_567"
    )

    # Custom separator
    testing.assert_equal(
        BigInt(1234567890).to_string_with_separators(","), "1,234,567,890"
    )


# ===----------------------------------------------------------------------=== #
# Test: to_string with line_width
# ===----------------------------------------------------------------------=== #


def test_to_string_line_width() raises:
    """Test to_string with line_width parameter."""
    # Default: no wrapping
    var val = BigInt("12345678901234567890")
    testing.assert_equal(val.to_string(), "12345678901234567890")

    # line_width=10: "1234567890\n1234567890"
    var wrapped = val.to_string(line_width=10)
    testing.assert_equal(wrapped, "1234567890\n1234567890")

    # line_width=5: "12345\n67890\n12345\n67890"
    var wrapped5 = val.to_string(line_width=5)
    testing.assert_equal(wrapped5, "12345\n67890\n12345\n67890")

    # Short string: no wrapping needed
    testing.assert_equal(BigInt(42).to_string(line_width=10), "42")


# ===----------------------------------------------------------------------=== #
# Test: number_of_digits
# ===----------------------------------------------------------------------=== #


def test_number_of_digits() raises:
    """Test number_of_digits method."""
    testing.assert_equal(BigInt(0).number_of_digits(), 1)
    testing.assert_equal(BigInt(1).number_of_digits(), 1)
    testing.assert_equal(BigInt(9).number_of_digits(), 1)
    testing.assert_equal(BigInt(10).number_of_digits(), 2)
    testing.assert_equal(BigInt(99).number_of_digits(), 2)
    testing.assert_equal(BigInt(100).number_of_digits(), 3)
    testing.assert_equal(BigInt(999).number_of_digits(), 3)
    testing.assert_equal(BigInt(1000).number_of_digits(), 4)

    # Negative numbers: digits count of magnitude
    testing.assert_equal(BigInt(-1).number_of_digits(), 1)
    testing.assert_equal(BigInt(-999).number_of_digits(), 3)

    # Large number
    testing.assert_equal(BigInt("12345678901234567890").number_of_digits(), 20)


# ===----------------------------------------------------------------------=== #
# Test: __repr__
# ===----------------------------------------------------------------------=== #


def test_repr() raises:
    """Test __repr__ (Writable trait)."""
    testing.assert_equal(repr(BigInt(42)), 'BigInt("42")')
    testing.assert_equal(repr(BigInt(-7)), 'BigInt("-7")')
    testing.assert_equal(repr(BigInt(0)), 'BigInt("0")')


def test_to_hex_string() raises:
    """Hex matches CPython's `hex()`, either side of the word boundary.

    Values whose lower words do not fill the full width are the ones that
    matter: the padding used to be eight hex digits, which is a 32-bit word's
    worth, so `2^64` rendered as `0x100000000` -- the hex for `2^32`.
    """
    testing.assert_equal(BigInt("0").to_hex_string(), "0x0")
    testing.assert_equal(BigInt("1").to_hex_string(), "0x1")
    testing.assert_equal(BigInt("-1").to_hex_string(), "-0x1")
    testing.assert_equal(BigInt("255").to_hex_string(), "0xff")
    testing.assert_equal(BigInt("4294967295").to_hex_string(), "0xffffffff")
    testing.assert_equal(BigInt("4294967296").to_hex_string(), "0x100000000")

    # One word, full width.
    testing.assert_equal(
        BigInt("18446744073709551615").to_hex_string(), "0xffffffffffffffff"
    )
    # Two words with an empty low word -- the case that was wrong.
    testing.assert_equal(
        BigInt("18446744073709551616").to_hex_string(), "0x10000000000000000"
    )
    testing.assert_equal(
        BigInt("18446744073709551617").to_hex_string(), "0x10000000000000001"
    )
    testing.assert_equal(
        BigInt("36893488147419103232").to_hex_string(), "0x20000000000000000"
    )
    testing.assert_equal(
        BigInt("-18446744073709551616").to_hex_string(),
        "-0x10000000000000000",
    )
    # Two full words.
    testing.assert_equal(
        BigInt("340282366920938463463374607431768211455").to_hex_string(),
        "0xffffffffffffffffffffffffffffffff",
    )


def test_to_binary_string() raises:
    """Binary matches CPython's `bin()` at the same boundaries.

    This one was written against `BITS_PER_WORD` rather than a literal and so
    survived the move to 64-bit words. It is pinned here anyway, because the
    hex version next to it did not.
    """
    testing.assert_equal(BigInt("0").to_binary_string(), "0b0")
    testing.assert_equal(BigInt("1").to_binary_string(), "0b1")
    testing.assert_equal(BigInt("-1").to_binary_string(), "-0b1")
    testing.assert_equal(BigInt("255").to_binary_string(), "0b11111111")
    testing.assert_equal(
        BigInt("4294967296").to_binary_string(),
        "0b1" + "0" * 32,
    )
    testing.assert_equal(
        BigInt("18446744073709551615").to_binary_string(), "0b" + "1" * 64
    )
    testing.assert_equal(
        BigInt("18446744073709551616").to_binary_string(), "0b1" + "0" * 64
    )
    testing.assert_equal(
        BigInt("-18446744073709551616").to_binary_string(), "-0b1" + "0" * 64
    )
    testing.assert_equal(
        BigInt("340282366920938463463374607431768211455").to_binary_string(),
        "0b" + "1" * 128,
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
