"""
Test that `BigInt`, `BigDecimal` and `Decimal128` are usable *through* the
`Numeric` trait, not merely declared to conform to it.

The helpers below are written once, against the trait alone. They can only
compile if every required operation is present with the declared signature, and
they can only produce the right answer if the conforming type's own method is
the one that runs. Each concrete test then checks the result with the operators
the concrete type has and the trait does not, `==` foremost.

`_sum` additionally stores the element type in a `List` and returns an owned
value, which is the case the `Movable` supertrait exists to serve.
"""

from std import testing

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigint.bigint import BigInt
from decimo.decimal128.decimal128 import Decimal128
from decimo.traits import Numeric


def _sum[T: Numeric](values: List[T]) raises -> T:
    """Adds a list of values, starting from the additive identity."""
    var acc = T.zero()
    for value in values:
        acc = acc + value
    return acc^


def _horner[T: Numeric](c2: T, c1: T, c0: T, x: T) raises -> T:
    """Evaluates `c2*x^2 + c1*x + c0` using only `+` and `*`."""
    var acc = c2 * x + c1
    acc = acc * x + c0
    return acc^


def _negated_difference[T: Numeric](a: T, b: T) raises -> T:
    """Returns `-(a - b)`, exercising subtraction and negation together."""
    return -(a - b)


def _ratio_plus_one[T: Numeric](a: T, b: T) raises -> T:
    """Returns `a / b + 1`, exercising division and the multiplicative identity.
    """
    return a / b + T.one()


def test_bigint_through_numeric() raises:
    """`BigInt` used through the trait."""
    testing.assert_equal(BigInt.zero(), BigInt(0), "BigInt.zero()")
    testing.assert_equal(BigInt.one(), BigInt(1), "BigInt.one()")

    var values: List[BigInt] = [BigInt(1), BigInt(2), BigInt(3), BigInt(4)]
    testing.assert_equal(_sum(values), BigInt(10), "sum of 1..4")

    testing.assert_equal(
        _horner(BigInt(2), BigInt(3), BigInt(4), BigInt(5)),
        BigInt(69),
        "2*5^2 + 3*5 + 4",
    )
    testing.assert_equal(
        _negated_difference(BigInt(3), BigInt(10)),
        BigInt(7),
        "-(3 - 10)",
    )
    # Division truncates toward zero on an integer type: -7/2 is -3, not -4.
    testing.assert_equal(
        _ratio_plus_one(BigInt(-7), BigInt(2)),
        BigInt(-2),
        "-7 / 2 + 1",
    )


def test_bigdecimal_through_numeric() raises:
    """`BigDecimal` used through the trait."""
    testing.assert_equal(
        BigDecimal.zero(), BigDecimal("0"), "BigDecimal.zero()"
    )
    testing.assert_equal(BigDecimal.one(), BigDecimal("1"), "BigDecimal.one()")

    var values: List[BigDecimal] = [
        BigDecimal("0.1"),
        BigDecimal("0.2"),
        BigDecimal("0.3"),
    ]
    testing.assert_equal(_sum(values), BigDecimal("0.6"), "0.1 + 0.2 + 0.3")

    testing.assert_equal(
        _horner(
            BigDecimal("2"), BigDecimal("3"), BigDecimal("4"), BigDecimal("5")
        ),
        BigDecimal("69"),
        "2*5^2 + 3*5 + 4",
    )
    testing.assert_equal(
        _negated_difference(BigDecimal("3"), BigDecimal("10")),
        BigDecimal("7"),
        "-(3 - 10)",
    )
    # Division is exact here, so no rounding mode is in play: -7/2 is -3.5.
    testing.assert_equal(
        _ratio_plus_one(BigDecimal("-7"), BigDecimal("2")),
        BigDecimal("-2.5"),
        "-7 / 2 + 1",
    )


def test_decimal128_through_numeric() raises:
    """`Decimal128` used through the trait."""
    testing.assert_equal(
        Decimal128.zero(), Decimal128("0"), "Decimal128.zero()"
    )
    testing.assert_equal(Decimal128.one(), Decimal128("1"), "Decimal128.one()")

    var values: List[Decimal128] = [
        Decimal128("0.1"),
        Decimal128("0.2"),
        Decimal128("0.3"),
    ]
    testing.assert_equal(_sum(values), Decimal128("0.6"), "0.1 + 0.2 + 0.3")

    testing.assert_equal(
        _horner(
            Decimal128("2"), Decimal128("3"), Decimal128("4"), Decimal128("5")
        ),
        Decimal128("69"),
        "2*5^2 + 3*5 + 4",
    )
    testing.assert_equal(
        _negated_difference(Decimal128("3"), Decimal128("10")),
        Decimal128("7"),
        "-(3 - 10)",
    )
    testing.assert_equal(
        _ratio_plus_one(Decimal128("-7"), Decimal128("2")),
        Decimal128("-2.5"),
        "-7 / 2 + 1",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
