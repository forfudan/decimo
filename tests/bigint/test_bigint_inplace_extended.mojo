"""
Test BigInt extended in-place operations: //=, %=, <<=, >>=, &=, |=, ^=.

These tests verify that each in-place operator produces results identical
to the corresponding non-in-place operator.
"""

from std import testing

from decimo.bigint.bigint import BigInt


# ===----------------------------------------------------------------------=== #
# Test: __ilshift__ (<<=)
# ===----------------------------------------------------------------------=== #


def test_ilshift_zero_shift() raises:
    """Left shift by 0 is no-op."""
    var x = BigInt(42)
    x <<= 0
    testing.assert_equal(String(x), "42")


def test_ilshift_zero_value() raises:
    """Left shift of 0 is 0."""
    var x = BigInt(0)
    x <<= 10
    testing.assert_equal(String(x), "0")


def test_ilshift_basic() raises:
    """Basic left shift: 1 << 1 = 2."""
    var x = BigInt(1)
    x <<= 1
    testing.assert_equal(String(x), "2")


def test_ilshift_byte() raises:
    """Left shift by 8: 1 << 8 = 256."""
    var x = BigInt(1)
    x <<= 8
    testing.assert_equal(String(x), "256")


def test_ilshift_word_boundary() raises:
    """Left shift by 32: crosses word boundary."""
    var x = BigInt(1)
    x <<= 32
    testing.assert_equal(String(x), "4294967296")


def test_ilshift_multi_word() raises:
    """Left shift by 64: two full words."""
    var x = BigInt(1)
    x <<= 64
    testing.assert_equal(String(x), "18446744073709551616")


def test_ilshift_partial() raises:
    """Left shift by non-word-aligned amount."""
    var x = BigInt(5)
    x <<= 3
    testing.assert_equal(String(x), "40")


def test_ilshift_negative() raises:
    """Left shift of negative number."""
    var x = BigInt(-3)
    x <<= 4
    testing.assert_equal(String(x), "-48")


def test_ilshift_large() raises:
    """Left shift of large multi-word number."""
    var x = BigInt("123456789012345678901234567890")
    x <<= 1
    testing.assert_equal(String(x), "246913578024691357802469135780")


def test_ilshift_matches_lshift() raises:
    """Inplace left shift produces same result as non-inplace."""

    def _check(val: String, shift: Int) raises:
        var expected = String(BigInt(val) << shift)
        var x = BigInt(val)
        x <<= shift
        testing.assert_equal(String(x), expected)

    _check("0", 5)
    _check("1", 0)
    _check("1", 1)
    _check("1", 31)
    _check("1", 32)
    _check("1", 33)
    _check("1", 64)
    _check("255", 24)
    _check("-1", 10)
    _check("-42", 32)
    _check("123456789012345678901234567890", 17)


# ===----------------------------------------------------------------------=== #
# Test: __irshift__ (>>=)
# ===----------------------------------------------------------------------=== #


def test_irshift_zero_shift() raises:
    """Right shift by 0 is no-op."""
    var x = BigInt(42)
    x >>= 0
    testing.assert_equal(String(x), "42")


def test_irshift_zero_value() raises:
    """Right shift of 0 is 0."""
    var x = BigInt(0)
    x >>= 10
    testing.assert_equal(String(x), "0")


def test_irshift_basic() raises:
    """Basic right shift: 4 >> 1 = 2."""
    var x = BigInt(4)
    x >>= 1
    testing.assert_equal(String(x), "2")


def test_irshift_truncate() raises:
    """Right shift truncates: 5 >> 1 = 2."""
    var x = BigInt(5)
    x >>= 1
    testing.assert_equal(String(x), "2")


def test_irshift_word_boundary() raises:
    """Right shift by 32: drops full word."""
    var x = BigInt("4294967296")  # 2^32
    x >>= 32
    testing.assert_equal(String(x), "1")


def test_irshift_to_zero() raises:
    """Right shift beyond all bits → 0."""
    var x = BigInt(255)
    x >>= 100
    testing.assert_equal(String(x), "0")


def test_irshift_negative_floor() raises:
    """Negative right shift rounds toward -inf: -1 >> 1 = -1."""
    var x = BigInt(-1)
    x >>= 1
    testing.assert_equal(String(x), "-1")

    var y = BigInt(-3)
    y >>= 1
    testing.assert_equal(String(y), "-2")


def test_irshift_negative_large() raises:
    """Negative number shifted beyond all bits → -1."""
    var x = BigInt(-42)
    x >>= 100
    testing.assert_equal(String(x), "-1")


def test_irshift_large() raises:
    """Right shift of large multi-word number."""
    var x = BigInt("123456789012345678901234567890")
    x >>= 1
    testing.assert_equal(String(x), "61728394506172839450617283945")


def test_irshift_matches_rshift() raises:
    """Inplace right shift produces same result as non-inplace."""

    def _check(val: String, shift: Int) raises:
        var expected = String(BigInt(val) >> shift)
        var x = BigInt(val)
        x >>= shift
        testing.assert_equal(String(x), expected)

    _check("0", 5)
    _check("1", 0)
    _check("1", 1)
    _check("256", 8)
    _check("4294967296", 32)
    _check("255", 100)
    _check("-1", 1)
    _check("-3", 1)
    _check("-42", 100)
    _check("-1024", 5)
    _check("123456789012345678901234567890", 17)


# ===----------------------------------------------------------------------=== #
# Test: __ifloordiv__ (//=)
# ===----------------------------------------------------------------------=== #


def test_ifloordiv_basic() raises:
    """Basic floor division: 10 // 3 = 3."""
    var x = BigInt(10)
    x //= BigInt(3)
    testing.assert_equal(String(x), "3")


def test_ifloordiv_exact() raises:
    """Exact division: 12 // 4 = 3."""
    var x = BigInt(12)
    x //= BigInt(4)
    testing.assert_equal(String(x), "3")


def test_ifloordiv_by_one() raises:
    """Division by 1 is no-op."""
    var x = BigInt(42)
    x //= BigInt(1)
    testing.assert_equal(String(x), "42")


def test_ifloordiv_negative_dividend() raises:
    """Floor division with negative dividend: -10 // 3 = -4."""
    var x = BigInt(-10)
    x //= BigInt(3)
    testing.assert_equal(String(x), "-4")


def test_ifloordiv_negative_divisor() raises:
    """Floor division with negative divisor: 10 // -3 = -4."""
    var x = BigInt(10)
    x //= BigInt(-3)
    testing.assert_equal(String(x), "-4")


def test_ifloordiv_both_negative() raises:
    """Floor division both negative: -10 // -3 = 3."""
    var x = BigInt(-10)
    x //= BigInt(-3)
    testing.assert_equal(String(x), "3")


def test_ifloordiv_zero_dividend() raises:
    """Zero divided by anything: 0 // x = 0."""
    var x = BigInt(0)
    x //= BigInt(42)
    testing.assert_equal(String(x), "0")


def test_ifloordiv_large() raises:
    """Floor division with large values."""
    var x = BigInt("123456789012345678901234567890")
    x //= BigInt("987654321")
    testing.assert_equal(
        String(x),
        String(BigInt("123456789012345678901234567890") // BigInt("987654321")),
    )


def test_ifloordiv_matches_floordiv() raises:
    """Inplace floor division produces same result as non-inplace."""

    def _check(a: String, b: String) raises:
        var expected = String(BigInt(a) // BigInt(b))
        var x = BigInt(a)
        x //= BigInt(b)
        testing.assert_equal(String(x), expected)

    _check("10", "3")
    _check("12", "4")
    _check("-10", "3")
    _check("10", "-3")
    _check("-10", "-3")
    _check("0", "1")
    _check("999999999999999999", "1000000000")
    _check("-999999999999999999", "1000000000")


# ===----------------------------------------------------------------------=== #
# Test: __imod__ (%=)
# ===----------------------------------------------------------------------=== #


def test_imod_basic() raises:
    """Basic modulo: 10 % 3 = 1."""
    var x = BigInt(10)
    x %= BigInt(3)
    testing.assert_equal(String(x), "1")


def test_imod_exact() raises:
    """Exact division: 12 % 4 = 0."""
    var x = BigInt(12)
    x %= BigInt(4)
    testing.assert_equal(String(x), "0")


def test_imod_negative_dividend() raises:
    """Floor modulo with negative dividend: -10 % 3 = 2."""
    var x = BigInt(-10)
    x %= BigInt(3)
    testing.assert_equal(String(x), "2")


def test_imod_negative_divisor() raises:
    """Floor modulo with negative divisor: 10 % -3 = -2."""
    var x = BigInt(10)
    x %= BigInt(-3)
    testing.assert_equal(String(x), "-2")


def test_imod_both_negative() raises:
    """Floor modulo both negative: -10 % -3 = -1."""
    var x = BigInt(-10)
    x %= BigInt(-3)
    testing.assert_equal(String(x), "-1")


def test_imod_large() raises:
    """Modulo with large values."""
    var x = BigInt("123456789012345678901234567890")
    x %= BigInt("987654321")
    testing.assert_equal(
        String(x),
        String(BigInt("123456789012345678901234567890") % BigInt("987654321")),
    )


def test_imod_matches_mod() raises:
    """Inplace modulo produces same result as non-inplace."""

    def _check(a: String, b: String) raises:
        var expected = String(BigInt(a) % BigInt(b))
        var x = BigInt(a)
        x %= BigInt(b)
        testing.assert_equal(String(x), expected)

    _check("10", "3")
    _check("12", "4")
    _check("-10", "3")
    _check("10", "-3")
    _check("-10", "-3")
    _check("1", "1")
    _check("999999999999999999", "1000000000")
    _check("-999999999999999999", "1000000000")


# ===----------------------------------------------------------------------=== #
# Test: __iand__ (&=)
# ===----------------------------------------------------------------------=== #


def test_iand_basic() raises:
    """Basic AND: 0b1111 & 0b1010 = 0b1010."""
    var x = BigInt(15)
    x &= BigInt(10)
    testing.assert_equal(String(x), "10")


def test_iand_zero() raises:
    """AND with zero: x & 0 = 0."""
    var x = BigInt(42)
    x &= BigInt(0)
    testing.assert_equal(String(x), "0")


def test_iand_all_ones() raises:
    """AND with all-ones mask: x & 0xFF = x & 255."""
    var x = BigInt(300)
    x &= BigInt(255)
    testing.assert_equal(String(x), "44")


def test_iand_negative() raises:
    """AND with negative (two's complement semantics)."""
    var x = BigInt(-1)
    x &= BigInt(255)
    testing.assert_equal(String(x), "255")


def test_iand_both_negative() raises:
    """AND of two negatives."""
    var x = BigInt(-3)
    x &= BigInt(-5)
    testing.assert_equal(String(x), String(BigInt(-3) & BigInt(-5)))


def test_iand_large() raises:
    """AND of large multi-word values."""
    var x = BigInt("123456789012345678901234567890")
    var y = BigInt("987654321098765432109876543210")
    var expected = String(BigInt("123456789012345678901234567890") & y)
    x &= y
    testing.assert_equal(String(x), expected)


def test_iand_matches_and() raises:
    """Inplace AND produces same result as non-inplace."""

    def _check(a: String, b: String) raises:
        var expected = String(BigInt(a) & BigInt(b))
        var x = BigInt(a)
        x &= BigInt(b)
        testing.assert_equal(String(x), expected)

    _check("15", "10")
    _check("42", "0")
    _check("0", "42")
    _check("-1", "255")
    _check("-3", "-5")
    _check("123456789", "987654321")
    _check("-123456789", "987654321")
    _check("-123456789", "-987654321")


# ===----------------------------------------------------------------------=== #
# Test: __ior__ (|=)
# ===----------------------------------------------------------------------=== #


def test_ior_basic() raises:
    """Basic OR: 0b1010 | 0b0101 = 0b1111."""
    var x = BigInt(10)
    x |= BigInt(5)
    testing.assert_equal(String(x), "15")


def test_ior_zero() raises:
    """OR with zero: x | 0 = x."""
    var x = BigInt(42)
    x |= BigInt(0)
    testing.assert_equal(String(x), "42")


def test_ior_self() raises:
    """OR with self: x | x = x."""
    var x = BigInt(42)
    x |= BigInt(42)
    testing.assert_equal(String(x), "42")


def test_ior_negative() raises:
    """OR with negative (two's complement semantics)."""
    var x = BigInt(0)
    x |= BigInt(-1)
    testing.assert_equal(String(x), "-1")


def test_ior_large() raises:
    """OR of large multi-word values."""
    var x = BigInt("123456789012345678901234567890")
    var y = BigInt("987654321098765432109876543210")
    var expected = String(BigInt("123456789012345678901234567890") | y)
    x |= y
    testing.assert_equal(String(x), expected)


def test_ior_matches_or() raises:
    """Inplace OR produces same result as non-inplace."""

    def _check(a: String, b: String) raises:
        var expected = String(BigInt(a) | BigInt(b))
        var x = BigInt(a)
        x |= BigInt(b)
        testing.assert_equal(String(x), expected)

    _check("10", "5")
    _check("42", "0")
    _check("0", "42")
    _check("0", "-1")
    _check("-1", "0")
    _check("-3", "-5")
    _check("123456789", "987654321")
    _check("-123456789", "987654321")


# ===----------------------------------------------------------------------=== #
# Test: __ixor__ (^=)
# ===----------------------------------------------------------------------=== #


def test_ixor_basic() raises:
    """Basic XOR: 0b1111 ^ 0b1010 = 0b0101."""
    var x = BigInt(15)
    x ^= BigInt(10)
    testing.assert_equal(String(x), "5")


def test_ixor_zero() raises:
    """XOR with zero: x ^ 0 = x."""
    var x = BigInt(42)
    x ^= BigInt(0)
    testing.assert_equal(String(x), "42")


def test_ixor_self_cancel() raises:
    """XOR with self cancels: x ^ x = 0."""
    var x = BigInt(42)
    x ^= BigInt(42)
    testing.assert_equal(String(x), "0")


def test_ixor_negative() raises:
    """XOR with negative (two's complement semantics)."""
    var x = BigInt(0)
    x ^= BigInt(-1)
    testing.assert_equal(String(x), "-1")


def test_ixor_large() raises:
    """XOR of large multi-word values."""
    var x = BigInt("123456789012345678901234567890")
    var y = BigInt("987654321098765432109876543210")
    var expected = String(BigInt("123456789012345678901234567890") ^ y)
    x ^= y
    testing.assert_equal(String(x), expected)


def test_ixor_matches_xor() raises:
    """Inplace XOR produces same result as non-inplace."""

    def _check(a: String, b: String) raises:
        var expected = String(BigInt(a) ^ BigInt(b))
        var x = BigInt(a)
        x ^= BigInt(b)
        testing.assert_equal(String(x), expected)

    _check("15", "10")
    _check("42", "0")
    _check("42", "42")
    _check("0", "-1")
    _check("-1", "0")
    _check("-3", "-5")
    _check("123456789", "987654321")
    _check("-123456789", "987654321")
    _check("-123456789", "-987654321")


# ===----------------------------------------------------------------------=== #
# Test: chained extended in-place operations
# ===----------------------------------------------------------------------=== #


def test_chained_shift() raises:
    """Chained shift operations: (1 << 10) >> 5 = 32."""
    var x = BigInt(1)
    x <<= 10
    x >>= 5
    testing.assert_equal(String(x), "32")


def test_chained_divmod() raises:
    """Chained div/mod: verify divmod identity x = (x // y) * y + (x % y)."""
    var original = BigInt(12345)
    var divisor = BigInt(67)

    var q = BigInt(12345)
    q //= BigInt(67)

    var r = BigInt(12345)
    r %= BigInt(67)

    # q * divisor + r should equal original
    var reconstructed = q * divisor + r
    testing.assert_equal(String(reconstructed), String(original))


def test_chained_bitwise() raises:
    """Chained bitwise: (0xFF | 0x100) & 0x1FF ^ 0x0FF = 0x100."""
    var x = BigInt(0xFF)
    x |= BigInt(0x100)  # 0x1FF
    x &= BigInt(0x1FF)  # 0x1FF (no change)
    x ^= BigInt(0x0FF)  # 0x100
    testing.assert_equal(String(x), "256")


def test_mixed_all_inplace() raises:
    """Mix all in-place operations together."""
    var x = BigInt(100)
    x += BigInt(28)  # 128
    x <<= 3  # 1024
    x -= BigInt(24)  # 1000
    x *= BigInt(5)  # 5000
    x //= BigInt(3)  # 1666
    x %= BigInt(100)  # 66
    x |= BigInt(1)  # 67 (set bit 0)
    x &= BigInt(0xFF)  # 67 (mask to byte)
    x ^= BigInt(3)  # 64 (67 ^ 3 = 64)
    x >>= 2  # 16
    testing.assert_equal(String(x), "16")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
