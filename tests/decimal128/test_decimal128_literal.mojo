"""
Test Decimal128 construction from integer literals. A literal wider than
`Int` used to be cut to 64 bits on the way in, which gave a wrong value with
no error. A literal beyond the largest coefficient is now a compile-time
error, which a test cannot show.
"""

from std import testing

from decimo import Decimal128


def test_literal_largest_coefficient() raises:
    """The largest and smallest values are written directly."""
    var a: Decimal128 = 79228162514264337593543950335
    testing.assert_equal(String(a), "79228162514264337593543950335")
    var b: Decimal128 = -79228162514264337593543950335
    testing.assert_equal(String(b), "-79228162514264337593543950335")


def test_literal_word_boundaries() raises:
    """Literals on each side of 2^32, 2^64 and 2^95 have the right words."""
    var a: Decimal128 = 4294967296  # 2^32
    testing.assert_equal(a.low, 0)
    testing.assert_equal(a.mid, 1)
    testing.assert_equal(a.high, 0)
    var b: Decimal128 = 18446744073709551616  # 2^64
    testing.assert_equal(b.mid, 0)
    testing.assert_equal(b.high, 1)
    var c: Decimal128 = 2**95 + 1
    testing.assert_equal(c.low, 1)
    testing.assert_equal(c.mid, 0)
    testing.assert_equal(c.high, 0x8000_0000)
    testing.assert_equal(String(c), "39614081257132168796771975169")


def test_literal_small_values() raises:
    """Literals that fit in `Int` give the same value as before."""
    testing.assert_equal(String(Decimal128(0)), "0")
    testing.assert_equal(String(Decimal128(-7)), "-7")
    testing.assert_equal(Decimal128(123), Decimal128.from_int(123))
    testing.assert_equal(
        String(Decimal128(-9223372036854775808)), "-9223372036854775808"
    )


def test_literal_does_not_shadow_int() raises:
    """An `Int` value still uses its own constructor."""
    var n: Int = -42
    var a: Decimal128 = n
    testing.assert_equal(String(a), "-42")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
