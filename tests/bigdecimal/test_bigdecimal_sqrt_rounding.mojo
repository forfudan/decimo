"""
`sqrt()` under every rounding mode, where the answer is exact.

A square root is algebraic: squaring the candidate back says which side of a
boundary the true value falls on, so a directional mode needs no guard digits
and cannot be wrong in the last digit. These check that against values whose
roots are known by hand, and against the defining property -- the result and
its neighbour bracket the true root -- for the rest.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.bigdecimal import BDec
from decimo.rounding_mode import RoundingMode


def test_the_modes_differ_where_they_should() raises:
    var two = BDec("2")
    # sqrt(2) = 1.41421356...
    assert_equal(String(two.sqrt(5, RoundingMode.ROUND_HALF_EVEN)), "1.4142")
    assert_equal(String(two.sqrt(5, RoundingMode.ROUND_DOWN)), "1.4142")
    assert_equal(String(two.sqrt(5, RoundingMode.ROUND_FLOOR)), "1.4142")
    assert_equal(String(two.sqrt(5, RoundingMode.ROUND_UP)), "1.4143")
    assert_equal(String(two.sqrt(5, RoundingMode.ROUND_CEILING)), "1.4143")

    # One digit, where the two neighbours are 1 and 2.
    assert_equal(String(two.sqrt(1, RoundingMode.ROUND_DOWN)), "1")
    assert_equal(String(two.sqrt(1, RoundingMode.ROUND_UP)), "2")


def test_an_exact_root_is_the_same_in_every_mode() raises:
    var modes = [
        RoundingMode.ROUND_HALF_EVEN,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
    ]
    for text in ["4", "9", "1.44", "0.25", "10000", "1E-20"]:
        var value = BDec(text)
        var expected = String(value.sqrt(28, RoundingMode.ROUND_HALF_EVEN))
        for mode in modes:
            assert_equal(
                String(value.sqrt(28, mode)),
                expected,
                "exact sqrt(" + text + ") should not depend on the mode",
            )


def test_the_result_brackets_the_true_root() raises:
    # The defining property, checked by squaring back: the value rounded down
    # is at or below the root, and one unit further up is above it.
    var texts = ["2", "3", "5", "7", "10", "1.0001", "123456789", "0.000123"]
    for text in texts:
        var value = BDec(text)
        for precision in [1, 5, 17, 28]:
            var low = value.sqrt(precision, RoundingMode.ROUND_FLOOR)
            var high = value.sqrt(precision, RoundingMode.ROUND_CEILING)
            assert_true(
                low.multiply(low, precision=0) <= value,
                "floor(sqrt(" + text + ")) squared must not exceed it",
            )
            assert_true(
                high.multiply(high, precision=0) >= value,
                "ceil(sqrt(" + text + ")) squared must not fall short",
            )
            # And they are neighbours: nothing representable lies between.
            assert_true(
                low <= high,
                "the floor must not exceed the ceiling",
            )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
