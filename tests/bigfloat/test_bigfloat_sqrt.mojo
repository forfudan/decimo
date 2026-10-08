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
Tests the square root of `BigFloat`.

Two kinds of check. The first is a table: fifteen roots at several precisions
in all seven modes, with the expectations from a short Python program that
brackets the root with `math.isqrt` and applies each mode to the bracket.

The second does not take anyone's word for what correct rounding is, and
works it out from the definition instead. Take the root rounded toward zero;
square it and square the value one step above it, both exactly, and the
original value has to sit between. Then the mode decides by where the value
sits relative to the midpoint of those two, which is settled by squaring the
midpoint. Squaring is monotonic, so comparing squares compares roots, and
every comparison here is exact. Nothing in it repeats the way the root is
computed.
"""

from std import testing
from std.testing import assert_equal, assert_false, assert_true

from decimo.bigfloat.arithmetics import multiply
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.exponential import sqrt
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


def _modes() -> List[RoundingMode]:
    """All seven of them.

    Returns:
        The modes, in the order the rounding primitive documents them.
    """
    return [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]


def _next_up(value: BigFloat) raises -> BigFloat:
    """The float one step above a positive finite `value`.

    Args:
        value: A positive finite value.

    Returns:
        The next value at the same precision. Adding one to the significand
        can carry past the top, and the normalization takes care of that
        exactly, since the carry leaves a power of two.

    Raises:
        Error: Propagated from the construction.
    """
    return BigFloat.from_rounded_parts(
        value.significand + BigInt.one(),
        value.exponent,
        value.precision,
        False,
    )


def _midpoint(value: BigFloat) raises -> BigFloat:
    """The value halfway between a positive finite `value` and the next up.

    Args:
        value: A positive finite value.

    Returns:
        The midpoint, held in one bit more than `value` so that it is exact.

    Raises:
        Error: Propagated from the construction.
    """
    return BigFloat(
        significand=(value.significand << 1) + BigInt.one(),
        exponent=value.exponent - 1,
        precision=value.precision + 1,
        sign=False,
    )


def test_the_root_is_the_one_exact_integers_give() raises:
    """Fifteen roots in all seven modes, against integer bracketing.

    Two, three and five at the precisions where their roots are interesting;
    the exact squares, where no mode may move the answer; and odd exponents,
    which have to be made even before the exponent can be halved.
    """
    var modes = _modes()
    var values = [
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("5"),
        String("5"),
        String("5"),
        String("5"),
        String("5"),
        String("5"),
        String("5"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("9"),
        String("9"),
        String("9"),
        String("9"),
        String("9"),
        String("9"),
        String("9"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("10"),
        String("10"),
        String("10"),
        String("10"),
        String("10"),
        String("10"),
        String("10"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
    ]
    var exponents = [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        101,
        101,
        101,
        101,
        101,
        101,
        101,
        -101,
        -101,
        -101,
        -101,
        -101,
        -101,
        -101,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        -3,
        -3,
        -3,
        -3,
        -3,
        -3,
        -3,
    ]
    var precisions = [
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        24,
        24,
        24,
        24,
        24,
        24,
        24,
        113,
        113,
        113,
        113,
        113,
        113,
        113,
    ]
    var picks = [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
    ]
    var roots = [
        String("6369051672525772"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525772"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("2"),
        String("3"),
        String("3"),
        String("2"),
        String("3"),
        String("3"),
        String("3"),
        String("7800463371553962"),
        String("7800463371553963"),
        String("7800463371553963"),
        String("7800463371553962"),
        String("7800463371553962"),
        String("7800463371553962"),
        String("7800463371553962"),
        String("5035177455121575"),
        String("5035177455121576"),
        String("5035177455121576"),
        String("5035177455121575"),
        String("5035177455121576"),
        String("5035177455121576"),
        String("5035177455121576"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("6755399441055744"),
        String("6755399441055744"),
        String("6755399441055744"),
        String("6755399441055744"),
        String("6755399441055744"),
        String("6755399441055744"),
        String("6755399441055744"),
        String("6369051672525772"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525772"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525772"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525772"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525772"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525772"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525772"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525772"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("6369051672525773"),
        String("13263553"),
        String("13263554"),
        String("13263554"),
        String("13263553"),
        String("13263554"),
        String("13263554"),
        String("13263554"),
        String("9713897947529984179792293095507162"),
        String("9713897947529984179792293095507163"),
        String("9713897947529984179792293095507163"),
        String("9713897947529984179792293095507162"),
        String("9713897947529984179792293095507162"),
        String("9713897947529984179792293095507162"),
        String("9713897947529984179792293095507162"),
    ]
    var root_exponents = [
        -52,
        -52,
        -52,
        -52,
        -52,
        -52,
        -52,
        0,
        1,
        1,
        0,
        0,
        0,
        0,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -52,
        -52,
        -52,
        -52,
        -52,
        -52,
        -52,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -52,
        -52,
        -52,
        -52,
        -52,
        -52,
        -52,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -53,
        -53,
        -53,
        -53,
        -53,
        -53,
        -53,
        -52,
        -52,
        -52,
        -52,
        -52,
        -52,
        -52,
        -2,
        -2,
        -2,
        -2,
        -2,
        -2,
        -2,
        -103,
        -103,
        -103,
        -103,
        -103,
        -103,
        -103,
        -22,
        -22,
        -22,
        -22,
        -22,
        -22,
        -22,
        -113,
        -113,
        -113,
        -113,
        -113,
        -113,
        -113,
    ]
    for i in range(len(values)):
        var x = BigFloat(
            significand=BigInt(values[i]),
            exponent=exponents[i],
            precision=BigInt(values[i]).bit_length(),
            sign=False,
        )
        assert_equal(
            sqrt(x, precisions[i], modes[picks[i]]).internal_representation(),
            roots[i]
            + "p"
            + String(root_exponents[i])
            + "@"
            + String(precisions[i]),
            String("the root of ")
            + values[i]
            + " times two to the "
            + String(exponents[i])
            + " at "
            + String(precisions[i])
            + " bits, "
            + String(modes[picks[i]]),
        )


def test_correct_rounding_from_its_definition() raises:
    """The answer bracketed by exact squares, for every mode.

    For each value: the root toward zero squares to no more than the value,
    and one step above it squares to more. If the first square is the value
    then the root is exact and no mode may move it. Otherwise the three half
    modes are settled by squaring the midpoint, and the directed four by
    their direction.
    """
    var significands = [
        String("2"),
        String("3"),
        String("5"),
        String("7"),
        String("10"),
        String("12345678901234567890"),
        String("99999999999999999999999999"),
        String("18446744073709551617"),
    ]
    var exponents = [0, -1, 1, -7, 64, -64, 101, -101]
    for s in range(len(significands)):
        for e in range(len(exponents)):
            var x = BigFloat(
                significand=BigInt(significands[s]),
                exponent=exponents[e],
                precision=BigInt(significands[s]).bit_length(),
                sign=False,
            )
            for precision in [1, 2, 24, 53]:
                var down = sqrt(x, precision, RoundingMode.ROUND_DOWN)
                var up = _next_up(down)
                var wide = 2 * precision + 8
                var square = multiply(down, down, wide)
                var next_square = multiply(up, up, wide)
                var at = (
                    String(" for ")
                    + significands[s]
                    + "p"
                    + String(exponents[e])
                    + " at "
                    + String(precision)
                    + " bits"
                )
                assert_true(square <= x, "the root toward zero is below" + at)
                assert_true(
                    next_square > x, "and one step above it is above" + at
                )

                if square == x:
                    for mode in _modes():
                        assert_equal(
                            sqrt(x, precision, mode).internal_representation(),
                            down.internal_representation(),
                            "an exact root does not move" + at,
                        )
                    continue

                var middle = multiply(_midpoint(down), _midpoint(down), wide)
                for mode in _modes():
                    var answer = sqrt(x, precision, mode)
                    var took_the_step = (
                        answer.internal_representation()
                        == up.internal_representation()
                    )
                    var expected = False
                    if (
                        mode == RoundingMode.ROUND_UP
                        or mode == RoundingMode.ROUND_CEILING
                    ):
                        expected = True
                    elif mode == RoundingMode.ROUND_HALF_UP:
                        expected = x >= middle
                    elif mode == RoundingMode.ROUND_HALF_DOWN:
                        expected = x > middle
                    elif mode == RoundingMode.ROUND_HALF_EVEN:
                        expected = x > middle or (
                            x == middle
                            and not (down.significand % BigInt(2)).is_zero()
                        )
                    assert_equal(
                        took_the_step,
                        expected,
                        String("the step ") + String(mode) + at,
                    )
                    assert_true(
                        answer.internal_representation()
                        == down.internal_representation()
                        or took_the_step,
                        "every mode lands on one of the two" + at,
                    )


def test_a_root_that_is_a_tie_exists_and_is_decided() raises:
    """A value whose root sits exactly halfway between two floats.

    Squaring the midpoint of two floats gives such a value, and it is the
    only case where the three half modes have to disagree. Here the lower
    float is even, so half to even keeps it and half up steps away.
    """
    var lower = BigFloat(
        significand=BigInt(4),
        exponent=0,
        precision=3,
        sign=False,
    )
    var middle = _midpoint(lower)
    var tie = multiply(middle, middle, 16)
    assert_equal(
        sqrt(tie, 3, RoundingMode.ROUND_HALF_EVEN).internal_representation(),
        lower.internal_representation(),
        "half to even keeps the even significand",
    )
    assert_equal(
        sqrt(tie, 3, RoundingMode.ROUND_HALF_DOWN).internal_representation(),
        lower.internal_representation(),
        "half down keeps it too",
    )
    assert_equal(
        sqrt(tie, 3, RoundingMode.ROUND_HALF_UP).internal_representation(),
        _next_up(lower).internal_representation(),
        "half up takes the step",
    )


def test_a_perfect_square_comes_back_whole() raises:
    """Where the root is a float, it is the float and not a rounding of one."""
    # Each of these is a 53-bit float whose root is one too, which is what
    # "perfect square" has to mean here: `1e100` is not one of them, since
    # ten to the hundredth needs 167 bits and is already a rounding at 53.
    for text in ["1", "4", "16", "0.25", "1024", "2.25", "6.25", "1e8"]:
        var x = BigFloat.from_string(text, 53)
        var root = sqrt(x, 53)
        # The square is held in more bits than the value was, so this
        # compares the numbers and not the shapes they are held in.
        assert_true(
            multiply(root, root, 106) == x,
            String("the root of ") + text + " squares back exactly",
        )

    # And the root of a square of a wide value needs the width to be exact.
    var wide = BigFloat.from_string("1.4142135623730950488016887242", 100)
    var square = multiply(wide, wide, 200)
    assert_equal(
        sqrt(square, 100).internal_representation(),
        wide.internal_representation(),
        "a hundred bits squared and rooted comes back",
    )


def test_the_special_values_follow_ieee() raises:
    """A negative value has no root among the reals, so it has a NaN."""
    assert_true(sqrt(BigFloat.nan(), 53).is_nan(), "a NaN stays one")
    assert_true(
        sqrt(BigFloat.from_int(-4), 53).is_nan(), "a negative value has none"
    )
    assert_true(
        sqrt(-BigFloat.infinity(), 53).is_nan(),
        "nor has a negative infinity",
    )
    assert_true(
        sqrt(BigFloat.infinity(), 53).is_infinite(),
        "a positive infinity is its own root",
    )
    assert_false(
        sqrt(BigFloat.infinity(), 53).sign,
        "and the root is positive",
    )

    # The zeros. A root has nothing to take from a zero, so the sign stays,
    # which is what IEEE 754 asks for and the one case where a negative
    # value does not give a NaN.
    assert_true(sqrt(BigFloat.zero(53, False), 53).is_zero(), "zero is zero")
    assert_false(sqrt(BigFloat.zero(53, False), 53).sign, "positive stays")
    assert_true(
        sqrt(BigFloat.zero(53, True), 53).is_zero(), "and so is minus zero"
    )
    assert_true(
        sqrt(BigFloat.zero(53, True), 53).sign,
        "which keeps its sign",
    )


def test_the_method_is_the_rootable_one() raises:
    """`sqrt()` on the value takes its own precision and rounds half to even."""
    var x = BigFloat.from_string("2", 120)
    assert_equal(
        x.sqrt().internal_representation(),
        sqrt(x, 120, RoundingMode.ROUND_HALF_EVEN).internal_representation(),
        "the method is the function at the value's own precision",
    )
    assert_equal(x.sqrt().precision, 120, "and keeps that precision")
    assert_true(
        BigFloat.from_int(-1).sqrt().is_nan(),
        "a negative value gives a NaN rather than raising",
    )


def test_a_precision_must_be_positive() raises:
    for precision in [0, -1]:
        var raised = False
        try:
            _ = sqrt(BigFloat.from_int(2), precision)
        except:
            raised = True
        assert_true(raised, "a root of no bits was accepted")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
