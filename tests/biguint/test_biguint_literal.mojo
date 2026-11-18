"""
Test BigUInt construction from integer literals of any size: the base-10^18
words worked out at compile time must match what the string constructor
builds, around every word boundary.
"""

from std import testing

from decimo.biguint.biguint import BigUInt


def _takes_biguint(x: BigUInt) -> BigUInt:
    return x.copy()


def test_literal_zero() raises:
    """Zero gets its one word."""
    var z: BigUInt = 0
    testing.assert_equal(len(z.words), 1)
    testing.assert_equal(z.words[0], 0)
    testing.assert_equal(String(z), "0")


def test_literal_word_boundaries() raises:
    """Literals on each side of 10^18 and 10^36 have the right words."""
    var a: BigUInt = 999999999999999999  # 10^18 - 1
    testing.assert_equal(len(a.words), 1)
    testing.assert_equal(a.words[0], 999999999999999999)

    var b: BigUInt = 1000000000000000000  # 10^18
    testing.assert_equal(len(b.words), 2)
    testing.assert_equal(b.words[0], 0)
    testing.assert_equal(b.words[1], 1)

    var c: BigUInt = 1000000000000000000000000000000000001  # 10^36 + 1
    testing.assert_equal(len(c.words), 3)
    testing.assert_equal(c.words[0], 1)
    testing.assert_equal(c.words[1], 0)
    testing.assert_equal(c.words[2], 1)


def test_literal_matches_string() raises:
    """Wide literals equal the same digits given as a string."""
    var a: BigUInt = 12345678901234567890123456789012345678901234567890
    testing.assert_equal(
        a, BigUInt("12345678901234567890123456789012345678901234567890")
    )
    var m: BigUInt = 18446744073709551616  # 2^64
    testing.assert_equal(String(m), "18446744073709551616")


def test_literal_comptime_expressions() raises:
    """A literal expression is evaluated exactly before conversion."""
    testing.assert_equal(BigUInt(10**100), BigUInt("1" + "0" * 100))
    testing.assert_equal(BigUInt(2**200), BigUInt(2).power(200))


def test_literal_implicit_conversion() raises:
    """Wide literals convert implicitly into arguments and operands."""
    testing.assert_equal(
        _takes_biguint(100000000000000000000000000000),
        BigUInt("100000000000000000000000000000"),
    )
    var x: BigUInt = 5
    testing.assert_equal(
        x + 99999999999999999999999, BigUInt("100000000000000000000004")
    )


def test_literal_does_not_shadow_int_or_scalar() raises:
    """`Int` and `Scalar` values still use their own constructors."""
    var n: Int = 42
    var a: BigUInt = n
    testing.assert_equal(String(a), "42")
    var neg: Int = -1
    with testing.assert_raises():
        var _b: BigUInt = neg


def test_literal_split_in_halves() raises:
    """Long literals, with zero words inside and none, have the right words."""
    var a: BigUInt = 10**90 + 1  # six words, four zeros between
    testing.assert_equal(len(a.words), 6)
    testing.assert_equal(a.words[0], 1)
    for i in range(1, 5):
        testing.assert_equal(a.words[i], 0)
    testing.assert_equal(a.words[5], 1)
    var b: BigUInt = 3**2000
    testing.assert_equal(b, BigUInt(3).power(2000))
    var c: BigUInt = 10**1152 - 1  # exactly 64 words, all 10^18 - 1
    testing.assert_equal(len(c.words), 64)
    testing.assert_equal(c.words[63], 999999999999999999)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
