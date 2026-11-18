"""
Test BigFloat construction from integer literals of any size and from a
`BigInt`. A literal wider than `Int` used to be cut to 64 bits on the way in,
which gave a wrong value with no error.
"""

from std import testing

from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


def test_literal_is_exact() raises:
    """A wide literal keeps every significant bit, as an `Int` does."""
    var a: BigFloat = 123456789012345678901234567890
    testing.assert_equal(String(a), "123456789012345678901234567890")
    # 97 bits, the last of them zero.
    testing.assert_equal(a.precision, 96)
    var b: BigFloat = -(2**200 + 1)
    testing.assert_equal(b.precision, 201)
    testing.assert_equal(
        String(b),
        "-1606938044258990275541962092341162602522202993782792835301377",
    )


def test_literal_keeps_the_default_precision() raises:
    """A literal with few significant bits gets the default 53."""
    testing.assert_equal(BigFloat(3).precision, 53)
    testing.assert_equal(BigFloat(1 << 200).precision, 53)
    testing.assert_equal(BigFloat(0).precision, 53)


def test_literal_at_a_precision() raises:
    """A literal and a precision round the literal, not its low 64 bits."""
    var a = BigFloat(2**100 + 1, 10)
    testing.assert_true(a == BigFloat(2) ** 100)
    var b = BigFloat(-(2**100 + 1), 10, RoundingMode.ROUND_UP)
    testing.assert_true(b == -(BigFloat(2) ** 100) * BigFloat("1.001953125"))


def test_literal_does_not_shadow_int() raises:
    """An `Int` value still uses its own constructor."""
    var n: Int = 12
    var a: BigFloat = n
    testing.assert_equal(String(a), "12")


def test_from_bigint_exactly() raises:
    """`from_bigint_exactly()` keeps every bit; `from_bigint()` rounds."""
    var n = BigInt(3).power(100)  # 159 bits
    var x = BigFloat.from_bigint_exactly(n)
    testing.assert_equal(x.precision, 159)
    testing.assert_equal(String(x), String(n))
    testing.assert_equal(BigFloat.from_bigint(n).precision, 53)
    testing.assert_equal(BigFloat.from_bigint_exactly(BigInt(0)).precision, 53)
    testing.assert_equal(
        BigFloat.from_bigint_exactly(-BigInt(1) << 300).precision, 53
    )


def test_bigint_constructors() raises:
    """`BigFloat(n)` is exact for a `BigInt`; with a precision it rounds."""
    var n = BigInt(2).power(100) + BigInt(1)
    var a = BigFloat(n)
    testing.assert_equal(a.precision, 101)
    testing.assert_equal(String(a), String(n))
    var b = BigFloat(n, 10)
    testing.assert_true(b == BigFloat(2) ** 100)
    var c: BigFloat = n  # implicit
    testing.assert_true(c == a)


def test_every_integer_reaches_the_right_constructor() raises:
    """An `Int`, a literal and a `BigInt` each convert without ambiguity."""
    var n: Int = 5
    var big = BigInt(2).power(100) + BigInt(1)
    var x = BigFloat(1.5)
    testing.assert_equal(String(BigFloat(n)), "5")
    testing.assert_equal(String(BigFloat(5)), "5")
    testing.assert_equal(String(x + 5), "6.5")
    testing.assert_equal(String(x + n), "6.5")
    testing.assert_equal(String(BigFloat(0) + big), String(big))
    testing.assert_equal(
        String(BigFloat.from_bigint_exactly(2**100 + 1)), String(big)
    )
    testing.assert_equal(String(BigFloat.from_bigint_exactly(n)), "5")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
