"""
Test BigDecimal construction from integer literals of any size. A literal
wider than `Int` used to be cut to 64 bits on the way in, which gave a wrong
value with no error.
"""

from std import testing

from decimo.bigdecimal.bigdecimal import BigDecimal


def _takes_bigdecimal(x: BigDecimal) -> BigDecimal:
    return x.copy()


def test_literal_matches_string() raises:
    """Wide literals equal the same digits given as a string."""
    var a: BigDecimal = 123456789012345678901234567890
    testing.assert_equal(String(a), "123456789012345678901234567890")
    var b: BigDecimal = -340282366920938463463374607431768211457
    testing.assert_equal(String(b), "-340282366920938463463374607431768211457")
    testing.assert_equal(a.scale, 0)


def test_literal_small_values() raises:
    """Literals that fit in `Int` give the same value as before."""
    testing.assert_equal(String(BigDecimal(0)), "0")
    testing.assert_equal(String(BigDecimal(-5)), "-5")
    testing.assert_equal(
        String(BigDecimal(-9223372036854775808)), "-9223372036854775808"
    )
    testing.assert_equal(
        String(BigDecimal(18446744073709551616)), "18446744073709551616"
    )


def test_literal_comptime_expressions() raises:
    """A literal expression is evaluated exactly before conversion."""
    testing.assert_equal(String(BigDecimal(1 << 70)), "1180591620717411303424")
    testing.assert_equal(
        String(BigDecimal(-(1 << 70))), "-1180591620717411303424"
    )
    testing.assert_equal(BigDecimal(10**50), BigDecimal("1E+50"))


def test_literal_implicit_conversion() raises:
    """Wide literals convert implicitly into arguments and operands."""
    testing.assert_equal(
        _takes_bigdecimal(100000000000000000000),
        BigDecimal("100000000000000000000"),
    )
    var x = BigDecimal("0.5")
    testing.assert_equal(
        String(x + 10000000000000000000), "10000000000000000000.5"
    )


def test_literal_does_not_shadow_int() raises:
    """An `Int` value still uses its own constructor."""
    var n: Int = -42
    var a: BigDecimal = n
    testing.assert_equal(String(a), "-42")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
