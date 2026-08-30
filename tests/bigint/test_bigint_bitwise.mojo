"""
Test BigInt bitwise operations: __and__, __or__, __xor__, __invert__,
and augmented assignment (&=, |=, ^=). All tests compare against Python's
arbitrary-precision integer bitwise semantics.
"""

from std import testing

from decimo.bigint.bigint import BigInt


# ===----------------------------------------------------------------------=== #
# Test: __invert__ (bitwise NOT)
# ===----------------------------------------------------------------------=== #


def test_invert_zero() raises:
    """Tests ~0 = -1."""
    testing.assert_equal(String(~BigInt(0)), "-1")


def test_invert_positive() raises:
    """Tests ~x = -(x+1) for positive x."""
    testing.assert_equal(String(~BigInt(1)), "-2")
    testing.assert_equal(String(~BigInt(2)), "-3")
    testing.assert_equal(String(~BigInt(42)), "-43")
    testing.assert_equal(String(~BigInt(255)), "-256")
    testing.assert_equal(String(~BigInt(1000000)), "-1000001")


def test_invert_negative() raises:
    """Tests ~(-x) = x - 1 for negative x."""
    testing.assert_equal(String(~BigInt(-1)), "0")
    testing.assert_equal(String(~BigInt(-2)), "1")
    testing.assert_equal(String(~BigInt(-3)), "2")
    testing.assert_equal(String(~BigInt(-42)), "41")
    testing.assert_equal(String(~BigInt(-256)), "255")
    testing.assert_equal(String(~BigInt(-1000001)), "1000000")


def test_invert_double() raises:
    """Tests ~~x = x (involution)."""
    testing.assert_equal(String(~(~BigInt(0))), "0")
    testing.assert_equal(String(~(~BigInt(42))), "42")
    testing.assert_equal(String(~(~BigInt(-42))), "-42")
    testing.assert_equal(
        String(~(~BigInt("123456789012345678901234567890"))),
        "123456789012345678901234567890",
    )


def test_invert_large() raises:
    """Tests ~x for large multi-word values."""
    # ~(2^32) = -(2^32 + 1)
    testing.assert_equal(String(~BigInt("4294967296")), "-4294967297")
    # ~(2^64) = -(2^64 + 1)
    testing.assert_equal(
        String(~BigInt("18446744073709551616")), "-18446744073709551617"
    )
    # ~(-(2^64)) = 2^64 - 1
    testing.assert_equal(
        String(~BigInt("-18446744073709551616")), "18446744073709551615"
    )


# ===----------------------------------------------------------------------=== #
# Test: __and__ (bitwise AND)
# ===----------------------------------------------------------------------=== #


def test_and_both_positive() raises:
    """Tests Positive & Positive → Positive."""
    # 0xFF & 0x0F = 0x0F = 15
    testing.assert_equal(String(BigInt(255) & BigInt(15)), "15")
    # 0b1010 & 0b1100 = 0b1000 = 8
    testing.assert_equal(String(BigInt(10) & BigInt(12)), "8")
    # x & 0 = 0
    testing.assert_equal(String(BigInt(12345) & BigInt(0)), "0")
    # x & x = x
    testing.assert_equal(String(BigInt(42) & BigInt(42)), "42")


def test_and_positive_negative() raises:
    """Tests Positive & Negative → Positive (Python semantics).
    In Python: 5 & -3 = 5.
    5    = ...00000101
    -3   = ...11111101  (two's complement)
    AND  = ...00000101  = 5.
    """
    testing.assert_equal(String(BigInt(5) & BigInt(-3)), "5")

    # 255 & -1 = 255 (since -1 = all bits set)
    testing.assert_equal(String(BigInt(255) & BigInt(-1)), "255")

    # 12 & -8 = 8
    # 12   = ...00001100
    # -8   = ...11111000
    # AND  = ...00001000 = 8
    testing.assert_equal(String(BigInt(12) & BigInt(-8)), "8")


def test_and_both_negative() raises:
    """Tests Negative & Negative → Negative (Python semantics).
    In Python: -5 & -3 = -7.
    -5   = ...11111011
    -3   = ...11111101
    AND  = ...11111001 = -7.
    """
    testing.assert_equal(String(BigInt(-5) & BigInt(-3)), "-7")

    # -1 & -1 = -1
    testing.assert_equal(String(BigInt(-1) & BigInt(-1)), "-1")

    # -256 & -16 = -256
    # -256 = ...100000000 → TC = ...1_00000000
    # -16  = ...11110000 → TC = ...1_11110000
    # AND  = ...1_00000000 = -256
    testing.assert_equal(String(BigInt(-256) & BigInt(-16)), "-256")


def test_and_large_values() raises:
    """AND with multi-word values."""
    # (2^64 - 1) & (2^32 - 1) = 2^32 - 1
    var all_64 = BigInt("18446744073709551615")
    var all_32 = BigInt("4294967295")
    testing.assert_equal(String(all_64 & all_32), "4294967295")

    # Large & 0 = 0
    testing.assert_equal(
        String(BigInt("123456789012345678901234567890") & BigInt(0)), "0"
    )


def test_and_with_int() raises:
    """AND with Int overload."""
    testing.assert_equal(String(BigInt(255) & 15), "15")
    testing.assert_equal(String(BigInt(-5) & -3), "-7")


# ===----------------------------------------------------------------------=== #
# Test: __or__ (bitwise OR)
# ===----------------------------------------------------------------------=== #


def test_or_both_positive() raises:
    """Tests Positive | Positive → Positive."""
    # 0b1010 | 0b1100 = 0b1110 = 14
    testing.assert_equal(String(BigInt(10) | BigInt(12)), "14")
    # x | 0 = x
    testing.assert_equal(String(BigInt(42) | BigInt(0)), "42")
    # 0 | x = x
    testing.assert_equal(String(BigInt(0) | BigInt(42)), "42")
    # x | x = x
    testing.assert_equal(String(BigInt(42) | BigInt(42)), "42")


def test_or_positive_negative() raises:
    """Tests Positive | Negative → Negative (Python semantics).
    In Python: 5 | -3 = -3.
    5    = ...00000101
    -3   = ...11111101
    OR   = ...11111101  = -3.
    """
    testing.assert_equal(String(BigInt(5) | BigInt(-3)), "-3")

    # x | -1 = -1 (all bits set)
    testing.assert_equal(String(BigInt(255) | BigInt(-1)), "-1")

    # 12 | -8 = -4
    # 12   = ...00001100
    # -8   = ...11111000
    # OR   = ...11111100 = -4
    testing.assert_equal(String(BigInt(12) | BigInt(-8)), "-4")


def test_or_both_negative() raises:
    """Tests Negative | Negative → Negative (Python semantics).
    In Python: -5 | -3 = -1.
    -5   = ...11111011
    -3   = ...11111101
    OR   = ...11111111 = -1.
    """
    testing.assert_equal(String(BigInt(-5) | BigInt(-3)), "-1")

    # -256 | -16 = -16
    testing.assert_equal(String(BigInt(-256) | BigInt(-16)), "-16")


def test_or_large_values() raises:
    """OR with multi-word values."""
    # (2^32) | 1 = 2^32 + 1
    testing.assert_equal(String(BigInt("4294967296") | BigInt(1)), "4294967297")


def test_or_with_int() raises:
    """OR with Int overload."""
    testing.assert_equal(String(BigInt(10) | 12), "14")
    testing.assert_equal(String(BigInt(5) | -3), "-3")


# ===----------------------------------------------------------------------=== #
# Test: __xor__ (bitwise XOR)
# ===----------------------------------------------------------------------=== #


def test_xor_both_positive() raises:
    """Positive ^ Positive → Positive."""
    # 0b1010 ^ 0b1100 = 0b0110 = 6
    testing.assert_equal(String(BigInt(10) ^ BigInt(12)), "6")
    # x ^ 0 = x
    testing.assert_equal(String(BigInt(42) ^ BigInt(0)), "42")
    # x ^ x = 0
    testing.assert_equal(String(BigInt(42) ^ BigInt(42)), "0")
    # 0xFF ^ 0x0F = 0xF0 = 240
    testing.assert_equal(String(BigInt(255) ^ BigInt(15)), "240")


def test_xor_positive_negative() raises:
    """Tests Positive ^ Negative → Negative (Python semantics).
    In Python: 5 ^ -3 = -8.
    5    = ...00000101
    -3   = ...11111101
    XOR  = ...11111000 = -8.
    """
    testing.assert_equal(String(BigInt(5) ^ BigInt(-3)), "-8")

    # x ^ -1 = ~x (XOR with all-ones inverts)
    testing.assert_equal(String(BigInt(255) ^ BigInt(-1)), "-256")
    testing.assert_equal(String(BigInt(0) ^ BigInt(-1)), "-1")

    # 12 ^ -8 = -4
    # 12   = ...00001100
    # -8   = ...11111000
    # XOR  = ...11110100 = -12
    testing.assert_equal(String(BigInt(12) ^ BigInt(-8)), "-12")


def test_xor_both_negative() raises:
    """Tests Negative ^ Negative → Positive (Python semantics).
    In Python: -5 ^ -3 = 6.
    -5   = ...11111011
    -3   = ...11111101
    XOR  = ...00000110 = 6.
    """
    testing.assert_equal(String(BigInt(-5) ^ BigInt(-3)), "6")

    # -1 ^ -1 = 0
    testing.assert_equal(String(BigInt(-1) ^ BigInt(-1)), "0")

    # -256 ^ -16 = 240
    testing.assert_equal(String(BigInt(-256) ^ BigInt(-16)), "240")


def test_xor_large_values() raises:
    """XOR with multi-word values."""
    # (2^32) ^ 1 = 2^32 + 1
    testing.assert_equal(String(BigInt("4294967296") ^ BigInt(1)), "4294967297")

    # x ^ x = 0 for large numbers
    var big = BigInt("123456789012345678901234567890")
    testing.assert_equal(String(big ^ big.copy()), "0")


def test_xor_with_int() raises:
    """XOR with Int overload."""
    testing.assert_equal(String(BigInt(10) ^ 12), "6")
    testing.assert_equal(String(BigInt(5) ^ -3), "-8")


# ===----------------------------------------------------------------------=== #
# Test: augmented assignment operators (&=, |=, ^=)
# ===----------------------------------------------------------------------=== #


def test_augmented_and() raises:
    """Test &= operator."""
    var x = BigInt(255)
    x &= BigInt(15)
    testing.assert_equal(String(x), "15")


def test_augmented_or() raises:
    """Test |= operator."""
    var x = BigInt(10)
    x |= BigInt(12)
    testing.assert_equal(String(x), "14")


def test_augmented_xor() raises:
    """Test ^= operator."""
    var x = BigInt(10)
    x ^= BigInt(12)
    testing.assert_equal(String(x), "6")


# ===----------------------------------------------------------------------=== #
# Test: identities and cross-checks
# ===----------------------------------------------------------------------=== #


def test_demorgan_laws() raises:
    """De Morgan's laws: ~(a & b) = ~a | ~b, ~(a | b) = ~a & ~b."""
    var a = BigInt(42)
    var b = BigInt(99)

    # ~(a & b) = ~a | ~b
    testing.assert_equal(
        String(~(a & b)),
        String((~a) | (~b)),
    )

    # ~(a | b) = ~a & ~b
    testing.assert_equal(
        String(~(a | b)),
        String((~a) & (~b)),
    )

    # With negative values
    var c = BigInt(-17)
    var d = BigInt(53)
    testing.assert_equal(
        String(~(c & d)),
        String((~c) | (~d)),
    )
    testing.assert_equal(
        String(~(c | d)),
        String((~c) & (~d)),
    )


def test_xor_self_cancels() raises:
    """Tests a ^ a = 0 for various values."""
    testing.assert_equal(String(BigInt(0) ^ BigInt(0)), "0")
    testing.assert_equal(String(BigInt(42) ^ BigInt(42)), "0")
    testing.assert_equal(String(BigInt(-42) ^ BigInt(-42)), "0")
    var big = BigInt("999999999999999999999999999")
    testing.assert_equal(String(big ^ big.copy()), "0")


def test_and_with_minus_one() raises:
    """Tests a & -1 = a (AND with all-ones is identity)."""
    testing.assert_equal(String(BigInt(0) & BigInt(-1)), "0")
    testing.assert_equal(String(BigInt(42) & BigInt(-1)), "42")
    testing.assert_equal(String(BigInt(-42) & BigInt(-1)), "-42")
    testing.assert_equal(
        String(BigInt("12345678901234567890") & BigInt(-1)),
        "12345678901234567890",
    )


def test_or_with_zero() raises:
    """Tests a | 0 = a (OR with zero is identity)."""
    testing.assert_equal(String(BigInt(0) | BigInt(0)), "0")
    testing.assert_equal(String(BigInt(42) | BigInt(0)), "42")
    testing.assert_equal(String(BigInt(-42) | BigInt(0)), "-42")


def test_xor_with_zero() raises:
    """Tests a ^ 0 = a (XOR with zero is identity)."""
    testing.assert_equal(String(BigInt(42) ^ BigInt(0)), "42")
    testing.assert_equal(String(BigInt(-42) ^ BigInt(0)), "-42")


def test_commutativity() raises:
    """Tests a op b = b op a for all binary bitwise ops."""
    var a = BigInt(123)
    var b = BigInt(-456)

    testing.assert_equal(String(a & b), String(b & a))
    testing.assert_equal(String(a | b), String(b | a))
    testing.assert_equal(String(a ^ b), String(b ^ a))


def test_python_cross_check() raises:
    """Cross-check specific values against Python results.
    Computed in Python 3.13:
        123 & -456 = 56
        123 | -456 = -389
        123 ^ -456 = -445
        -100 & -200 = -232
        -100 | -200 = -68
        -100 ^ -200 = 164.
    """
    testing.assert_equal(String(BigInt(123) & BigInt(-456)), "56")
    testing.assert_equal(String(BigInt(123) | BigInt(-456)), "-389")
    testing.assert_equal(String(BigInt(123) ^ BigInt(-456)), "-445")
    testing.assert_equal(String(BigInt(-100) & BigInt(-200)), "-232")
    testing.assert_equal(String(BigInt(-100) | BigInt(-200)), "-68")
    testing.assert_equal(String(BigInt(-100) ^ BigInt(-200)), "164")


def test_word_boundary_values() raises:
    """Test values at word boundaries (32-bit, 64-bit)."""
    # 2^32 - 1 = 0xFFFFFFFF (single word, all bits set)
    var w32 = BigInt("4294967295")
    # 2^32 = 0x1_00000000 (two words)
    var w32p1 = BigInt("4294967296")

    # (2^32 - 1) & (2^32) = 0
    testing.assert_equal(String(w32 & w32p1), "0")

    # (2^32 - 1) | (2^32) = 2^33 - 1 = 8589934591
    testing.assert_equal(String(w32 | w32p1), "8589934591")

    # (2^32 - 1) ^ (2^32) = 2^33 - 1 = 8589934591
    testing.assert_equal(String(w32 ^ w32p1), "8589934591")

    # 2^64 - 1 (two full words)
    var w64 = BigInt("18446744073709551615")
    # (2^64 - 1) & (2^32 - 1) = 2^32 - 1
    testing.assert_equal(String(w64 & w32), "4294967295")

    # ~(2^32 - 1) = -(2^32) = -4294967296
    testing.assert_equal(String(~w32), "-4294967296")

    # ~(2^64 - 1) = -(2^64) = -18446744073709551616
    testing.assert_equal(String(~w64), "-18446744073709551616")


# ===----------------------------------------------------------------------=== #
# Test: bit_count() — population count
# ===----------------------------------------------------------------------=== #


def test_bit_count_zero() raises:
    """Tests bit_count(0) = 0."""
    testing.assert_equal(BigInt(0).bit_count(), 0)


def test_bit_count_one() raises:
    """Tests bit_count(1) = 1."""
    testing.assert_equal(BigInt(1).bit_count(), 1)


def test_bit_count_powers_of_two() raises:
    """Powers of 2 have exactly 1 bit set."""
    testing.assert_equal(BigInt(2).bit_count(), 1)
    testing.assert_equal(BigInt(4).bit_count(), 1)
    testing.assert_equal(BigInt(1024).bit_count(), 1)


def test_bit_count_small() raises:
    """Small values: 7 = 0b111 (3 bits), 13 = 0b1101 (3 bits)."""
    testing.assert_equal(BigInt(7).bit_count(), 3)
    testing.assert_equal(BigInt(13).bit_count(), 3)
    testing.assert_equal(BigInt(15).bit_count(), 4)
    testing.assert_equal(BigInt(255).bit_count(), 8)


def test_bit_count_negative() raises:
    """Tests bit_count on negative values counts bits in the magnitude."""
    testing.assert_equal(BigInt(-7).bit_count(), 3)
    testing.assert_equal(BigInt(-1).bit_count(), 1)


def test_bit_count_large() raises:
    """2^32 - 1 = 0xFFFFFFFF has 32 bits set."""
    var n = BigInt(1) << 32
    n = n - BigInt(1)  # 2^32 - 1
    testing.assert_equal(n.bit_count(), 32)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
