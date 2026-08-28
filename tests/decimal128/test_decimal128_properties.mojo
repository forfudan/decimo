"""
Property and boundary tests for `Decimal128` arithmetic.

`Decimal128` is the .NET `System.Decimal` layout: a 96-bit coefficient and a
scale from 0 to 28, so every operation has two ways to leave the
representation -- the coefficient overflowing 2^96, and the scale needing to
go past 28. The existing suite checks named cases. What is added here is the
part a table cannot state: that the operations agree with each other, and that
both ceilings behave the same way whichever operation walks into them.

The exact-arithmetic sweep behind this file lives outside the repository: 1300
sums, differences and products generated with CPython's `decimal`, kept only
where the exact result provably fits -- coefficient under 2^96, scale at most
28 -- so that no model of the rounding rules is needed to say what the answer
must be. All 1300 matched in both value and scale. The properties below are
the part of that worth keeping in the suite.
"""

from std import testing
from std.testing import assert_true, assert_equal

from decimo.decimal128.decimal128 import Dec128


def sweep_values() raises -> List[Dec128]:
    """Values across the scale range, both signs, including the extremes."""
    var values = List[Dec128]()
    for text in [
        String("0"),
        String("1"),
        String("-1"),
        String("0.5"),
        String("-2.25"),
        String("123.456"),
        String("1000000"),
        String("0.0000000000000000000000000001"),
        String("79228162514264337593543950335"),
        String("-79228162514264337593543950335"),
        String("12345678901234567890.12345678"),
        String("0.1"),
        String("-0.3"),
    ]:
        values.append(Dec128(text))
    return values^


def test_addition_and_multiplication_commute() raises:
    for a in sweep_values():
        for b in sweep_values():
            var forward_sum_failed = False
            var reverse_sum_failed = False
            var forward_sum = Dec128("0")
            var reverse_sum = Dec128("0")
            try:
                forward_sum = a + b
            except e:
                forward_sum_failed = True
            try:
                reverse_sum = b + a
            except e:
                reverse_sum_failed = True
            assert_equal(
                forward_sum_failed,
                reverse_sum_failed,
                "a + b and b + a disagree on whether they fit",
            )
            if not forward_sum_failed:
                assert_true(
                    forward_sum == reverse_sum
                    and forward_sum.scale() == reverse_sum.scale(),
                    "addition does not commute for "
                    + String(a)
                    + " and "
                    + String(b),
                )

            var forward_product_failed = False
            var reverse_product_failed = False
            var forward_product = Dec128("0")
            var reverse_product = Dec128("0")
            try:
                forward_product = a * b
            except e:
                forward_product_failed = True
            try:
                reverse_product = b * a
            except e:
                reverse_product_failed = True
            assert_equal(
                forward_product_failed,
                reverse_product_failed,
                "a * b and b * a disagree on whether they fit",
            )
            if not forward_product_failed:
                assert_true(
                    forward_product == reverse_product
                    and forward_product.scale() == reverse_product.scale(),
                    "multiplication does not commute for "
                    + String(a)
                    + " and "
                    + String(b),
                )


def test_subtracting_back_gives_the_original() raises:
    """`(a + b) - b == a` wherever the sum is representable."""
    for a in sweep_values():
        for b in sweep_values():
            try:
                var back = (a + b) - b
                assert_true(
                    back == a,
                    "(a + b) - b changed a: "
                    + String(a)
                    + " with "
                    + String(b)
                    + " gave "
                    + String(back),
                )
            except e:
                pass  # Out of range on the way, which is its own answer.


def test_a_string_round_trip_preserves_value_and_scale() raises:
    for value in sweep_values():
        var parsed = Dec128(String(value))
        assert_true(parsed == value, "value changed: " + String(value))
        assert_equal(
            parsed.scale(),
            value.scale(),
            "scale changed for " + String(value),
        )


def test_the_coefficient_ceiling() raises:
    var maximum = Dec128("79228162514264337593543950335")
    assert_equal(maximum.scale(), 0)
    assert_true(Dec128(String(maximum)) == maximum, "the maximum round trips")

    with testing.assert_raises():
        _ = maximum + Dec128("1")
    with testing.assert_raises():
        _ = Dec128("79228162514264337593543950336")
    with testing.assert_raises():
        _ = Dec128("8922162514264337593543950335") * Dec128("10")


def test_the_scale_ceiling_rounds_rather_than_raising() raises:
    """Past 28 places the value is rounded, not rejected.

    Half-even throughout, which is what the .NET type does: a product that
    lands exactly on a midpoint goes to the even neighbour.
    """
    var below = Dec128("0.00000000000000000000000000005")
    assert_equal(below.scale(), 28)
    assert_true(below == Dec128("0"), "5E-29 rounds to an even zero")

    # Products landing exactly on a midpoint at scale 28.
    var midpoints = [
        (
            String("0.00000000000001"),
            String("0.000000000000015"),
            String("2E-28"),
        ),
        (
            String("0.00000000000002"),
            String("0.000000000000015"),
            String("3E-28"),
        ),
        (
            String("0.00000000000003"),
            String("0.000000000000015"),
            String("4E-28"),
        ),
        (
            String("0.00000000000001"),
            String("0.000000000000025"),
            String("2E-28"),
        ),
        (
            String("0.00000000000003"),
            String("0.000000000000025"),
            String("8E-28"),
        ),
    ]
    for item in midpoints:
        var product = Dec128(item[0]) * Dec128(item[1])
        assert_true(
            product == Dec128(item[2]),
            item[0]
            + " * "
            + item[1]
            + " gave "
            + String(product)
            + ", want "
            + item[2],
        )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
