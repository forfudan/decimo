# ===----------------------------------------------------------------------=== #
# Copyright 2025-2026 Yuhao Zhu
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===----------------------------------------------------------------------=== #


"""
Tests the answers the deciding loop cannot reach.

A correctly rounded function decides its rounding by bracketing the true
value and asking whether both ends round the same way. Two kinds of answer
defeat that. One is a value sitting exactly on a rounding boundary, which in
a directed mode has neighbours on both sides -- `exp(0)` is exactly one, and
every directed mode refused it. The other is a value the kernel cannot get
near enough to in the widenings the loop allows: `arctan2(1, 2^-4006)` and
`power(2, 2^-4000)` were refused for that reason.

Both kinds have to be answered before the loop, from what is known about the
argument. That is what this file pins, and it pins it in **all seven modes**,
because the half modes settle on an exactly representable value by themselves
and so cannot see the defect at all.
"""

from std import testing
from std.testing import assert_equal

from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.exponential import exp
from decimo.bigfloat.hyperbolic import cosh
from decimo.bigfloat.power import power
from decimo.bigfloat.trigonometric import arctan, arctan2, cos
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


def _modes() -> List[RoundingMode]:
    """The seven modes."""
    return [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]


def test_the_three_functions_that_are_one_at_nought() raises:
    """`exp(0)`, `cos(0)` and `cosh(0)` are exactly one, in every mode.

    All three used to raise in the four directed modes. Both signs of nought
    and three precisions, including the one-bit case where a significand is a
    single bit.
    """
    var modes = _modes()
    for index in range(7):
        for negative in range(2):
            for precision in [1, 2, 53]:
                var zero = BigFloat.zero(precision, negative == 1)
                assert_equal(
                    String(exp(zero, precision, modes[index])),
                    "1",
                    String("exp of a nought in mode ") + String(index),
                )
                assert_equal(
                    String(cos(zero, precision, modes[index])),
                    "1",
                    String("cos of a nought in mode ") + String(index),
                )
                assert_equal(
                    String(cosh(zero, precision, modes[index])),
                    "1",
                    String("cosh of a nought in mode ") + String(index),
                )


def test_an_angle_whose_ratio_is_tiny() raises:
    """`arctan2(y, 1)` is `arctan(y)`, which is the reference.

    The two are the same number and do not share a path: the one-argument
    function has had the small-argument guard all along, and the
    two-argument one wrote its own loop without it. Below about `2^-1600` at
    53 bits the loop cannot reach the answer however far it widens, and the
    directed modes refused.
    """
    var modes = _modes()
    for exponent in [200, 600, 4006, 100000]:
        for index in range(7):
            for negative in range(2):
                var y = BigFloat.power_of_two(-exponent)
                if negative == 1:
                    y = -y
                assert_equal(
                    arctan2(
                        y, BigFloat.from_int(1, 53), 53, modes[index]
                    ).internal_representation(),
                    arctan(y, 53, modes[index]).internal_representation(),
                    String("the angle at two to the minus ")
                    + String(exponent)
                    + " in mode "
                    + String(index),
                )


def test_a_power_whose_exponent_is_tiny() raises:
    """`x ** y` for a tiny `y` is one, moved by a hair the right way.

    Which way is the whole content of the answer: above one when `y ln x` is
    positive and below it when negative, which is what the two signs decide
    between them. The half modes give one either way, so they cannot tell
    whether the direction was found; the directed modes can.
    """
    var modes = _modes()
    var tiny = BigFloat.power_of_two(-4000)
    var one = BigFloat.from_int(1, 53)
    var above = BigFloat.from_int(2, 53)
    var below = BigFloat.from_string("0.5", 53)
    # toward zero is the value under one, away from it the value over
    var under = BigFloat.from_rounded_parts(
        BigInt("9007199254740991"), -53, 53, False
    )
    var over = BigFloat.from_rounded_parts(
        BigInt("4503599627370497"), -52, 53, False
    )
    for index in range(7):
        var mode = modes[index]
        var downward = (
            index == 0 or index == 3
        )  # toward zero, or toward negative infinity
        var upward = index == 1 or index == 2  # away from zero, or ceiling
        # two to a tiny power is just above one
        var got = power(above, tiny, 53, mode)
        if upward:
            assert_equal(
                got.internal_representation(),
                over.internal_representation(),
                String("two to a tiny power, upward, mode ") + String(index),
            )
        else:
            assert_equal(
                got.internal_representation(),
                one.internal_representation(),
                String("two to a tiny power, mode ") + String(index),
            )
        # a half to a tiny power is just below one
        var low = power(below, tiny, 53, mode)
        if downward:
            assert_equal(
                low.internal_representation(),
                under.internal_representation(),
                String("a half to a tiny power, downward, mode ")
                + String(index),
            )
        else:
            assert_equal(
                low.internal_representation(),
                one.internal_representation(),
                String("a half to a tiny power, mode ") + String(index),
            )
        # and a negative tiny exponent flips the side
        var flipped = power(above, -tiny, 53, mode)
        assert_equal(
            flipped.internal_representation(),
            low.internal_representation(),
            String("a negative tiny exponent is the reciprocal's side, mode ")
            + String(index),
        )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
