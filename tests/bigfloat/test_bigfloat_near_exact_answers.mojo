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
Tests answers that sit a known distance from a float or a midpoint.

Each case here is one the review of v0.16.0 found answered wrongly or
refused. Three were rounded the wrong way, because a gate that moves a value
by a hair measured against the destination precision rather than the bits
the value carries. Four more raised, because the deciding loop stopped at a
fixed 1536 bits, or the argument reduction at eight steps, where the answer
needs more. Two had an exact answer that no path formed.

The expected values come from mpmath at 9000 bits, as a 53-bit significand
and an exponent, in five modes.
"""

from std import testing
from std.testing import assert_true

from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.constants import ln2, pi
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


def _modes() -> List[RoundingMode]:
    """The modes each case is checked in, in the order of expected values.

    Returns:
        Down, up, half-even, floor and ceiling.
    """
    return [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_HALF_EVEN,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_CEILING,
    ]


def _dyadic(significand: BigInt, exponent: Int) raises -> BigFloat:
    """`significand * 2^exponent`, with exactly the bits it needs.

    Args:
        significand: The significand, positive.
        exponent: The power of two.

    Returns:
        The value, exact.
    """
    return BigFloat(
        significand=significand,
        exponent=exponent,
        precision=significand.bit_length(),
        sign=False,
    )


def _two_to(power: Int) -> BigInt:
    """`2^power` as an integer.

    Args:
        power: The power, not negative.

    Returns:
        The integer.
    """
    return BigInt(1) << power


def _check(
    name: String,
    got: List[BigFloat],
    expected: List[Tuple[String, Int]],
    precision: Int,
) raises:
    """Compares one answer per mode against mpmath's.

    Args:
        name: What is being checked, for the message.
        got: The answers, one per entry of `_modes()`.
        expected: The significand, signed, and the exponent, one per mode.
        precision: The bits of the expected significands.
    """
    var modes = _modes()
    for i in range(len(modes)):
        var text = expected[i][0]
        var negative = text.startswith("-")
        var digits = String(text[byte=1:]) if negative else text
        var want = BigFloat(
            significand=BigInt(digits),
            exponent=expected[i][1],
            precision=precision,
            sign=negative,
        )
        assert_true(
            got[i] == want,
            name
            + " in "
            + String(modes[i])
            + ": got "
            + got[i].to_string(40)
            + ", want "
            + want.to_string(40),
        )


def test_hypot_with_a_wide_larger_leg() raises:
    """A 200-bit leg against one sixty places below it.

    The sum is past the midpoint `1 + 2^-53`, which a hair on the larger leg
    could not reach when the hair was a guard unit of its 200 bits.
    """
    var larger = _dyadic(_two_to(199) + _two_to(146) - BigInt(1), -199)
    var smaller = _dyadic(BigInt(1), -60)
    var got = List[BigFloat]()
    for mode in _modes():
        got.append(larger.hypot(53, mode, other=smaller))
    _check(
        "hypot(1 + 2^-53 - 2^-199, 2^-60)",
        got,
        [
            ("4503599627370496", -52),
            ("4503599627370497", -52),
            ("4503599627370497", -52),
            ("4503599627370496", -52),
            ("4503599627370497", -52),
        ],
        53,
    )


def test_exp10_beside_a_power_that_needs_more_bits() raises:
    """`10^8` has 19 bits of `5^8`, more than the 13 asked for."""
    var x = _dyadic(BigInt(8) * _two_to(21) - BigInt(3), -21)
    var got = List[BigFloat]()
    for mode in _modes():
        got.append(x.exp10(13, mode))
    _check(
        "exp10(8 - 3 * 2^-21)",
        got,
        [
            ("6103", 14),
            ("6104", 14),
            ("6103", 14),
            ("6103", 14),
            ("6104", 14),
        ],
        13,
    )


def test_arctan2_with_a_tiny_inexact_ratio() raises:
    """A ratio that rounds to `2^-100` before the hair is added.

    The angle is above `2^-100`, so rounding down keeps it there.
    """
    var y = _dyadic(BigInt(3) * _two_to(68) + BigInt(1), -168)
    var x = BigFloat(3)
    var got = List[BigFloat]()
    for mode in _modes():
        got.append(y.arctan2(53, mode, other=x))
    _check(
        "arctan2(3 * 2^-100 + 2^-168, 3)",
        got,
        [
            ("4503599627370496", -152),
            ("4503599627370497", -152),
            ("4503599627370496", -152),
            ("4503599627370496", -152),
            ("4503599627370497", -152),
        ],
        53,
    )


def test_a_precise_pi_reduced_at_low_precision() raises:
    """`pi` to 800 bits, whose sine is its own rounding error."""
    var x = pi(800)
    var sines = List[BigFloat]()
    var cosines = List[BigFloat]()
    for mode in _modes():
        sines.append(x.sin(53, mode))
        cosines.append(x.cos(53, mode))
    _check(
        "sin(pi(800))",
        sines,
        [
            ("8746374372936217", -852),
            ("8746374372936218", -852),
            ("8746374372936218", -852),
            ("8746374372936217", -852),
            ("8746374372936218", -852),
        ],
        53,
    )
    _check(
        "cos(pi(800))",
        cosines,
        [
            ("-9007199254740991", -53),
            ("-4503599627370496", -52),
            ("-4503599627370496", -52),
            ("-4503599627370496", -52),
            ("-9007199254740991", -53),
        ],
        53,
    )


def test_wide_arguments_past_the_old_limit() raises:
    """Answers more than 1536 bits from a float, which the loop now reaches."""
    var small = _dyadic(_two_to(3000) + BigInt(1), -4000)
    var near_one = _dyadic(_two_to(2000) + BigInt(1), -2000)
    var below_one = _dyadic(_two_to(1601) - BigInt(1), -1601)
    var beside_eight = _dyadic(_two_to(1703) + BigInt(1), -1700)
    var wide_ln2 = ln2(3000)
    var sines = List[BigFloat]()
    var cubes = List[BigFloat]()
    var angles = List[BigFloat]()
    var logs = List[BigFloat]()
    var twos = List[BigFloat]()
    for mode in _modes():
        sines.append(small.sin(53, mode))
        cubes.append(near_one.power(53, mode, exponent=BigFloat(3)))
        angles.append(below_one.arccos(53, mode))
        logs.append(beside_eight.log(53, mode, base=BigFloat(2)))
        twos.append(wide_ln2.exp(53, mode))
    _check(
        "sin(2^-1000 + 2^-4000)",
        sines,
        [
            ("9007199254740991", -1053),
            ("4503599627370496", -1052),
            ("4503599627370496", -1052),
            ("9007199254740991", -1053),
            ("4503599627370496", -1052),
        ],
        53,
    )
    _check(
        "power(1 + 2^-2000, 3)",
        cubes,
        [
            ("4503599627370496", -52),
            ("4503599627370497", -52),
            ("4503599627370496", -52),
            ("4503599627370496", -52),
            ("4503599627370497", -52),
        ],
        53,
    )
    _check(
        "arccos(1 - 2^-1601)",
        angles,
        [
            ("4503599627370496", -852),
            ("4503599627370497", -852),
            ("4503599627370496", -852),
            ("4503599627370496", -852),
            ("4503599627370497", -852),
        ],
        53,
    )
    _check(
        "log(8 + 2^-1700, base=2)",
        logs,
        [
            ("6755399441055744", -51),
            ("6755399441055745", -51),
            ("6755399441055744", -51),
            ("6755399441055744", -51),
            ("6755399441055745", -51),
        ],
        53,
    )
    _check(
        "exp(ln2(3000))",
        twos,
        [
            ("9007199254740991", -52),
            ("4503599627370496", -51),
            ("4503599627370496", -51),
            ("9007199254740991", -52),
            ("4503599627370496", -51),
        ],
        53,
    )


def test_an_exact_root_of_a_large_degree() raises:
    """`3^100` to the hundredth is three, at a precision below the degree."""
    var x = BigFloat.from_bigint(BigInt(3).power(100), 159)
    for mode in _modes():
        assert_true(x.root(100, 53, mode) == BigFloat(3), String(mode))
    var odd_degree = BigFloat.from_bigint(BigInt(-3).power(101), 161)
    for mode in _modes():
        assert_true(
            odd_degree.root(101, 53, mode) == BigFloat(-3), String(mode)
        )


def test_minus_one_to_a_huge_whole_power() raises:
    """Past `2^62` the exponent does not fit the integer path."""
    var even = BigFloat.from_bigint(_two_to(62), 53)
    var odd = BigFloat.from_bigint(_two_to(62) + BigInt(1), 64)
    for mode in _modes():
        assert_true(
            BigFloat(-1).power(53, mode, exponent=even) == BigFloat(1),
            String(mode),
        )
        assert_true(
            BigFloat(-1).power(53, mode, exponent=odd) == BigFloat(-1),
            String(mode),
        )


def test_a_whole_power_near_the_top_of_an_int() raises:
    """`9 ** 2^61` wrapped the exact-path gate and was refused.

    It is `81 ** 2^60` as well, which takes the other path, and the two have
    to agree.
    """
    var nine = BigFloat(9) ** BigFloat.from_bigint(_two_to(61), 53)
    var eighty_one = BigFloat(81) ** BigFloat.from_bigint(_two_to(60), 53)
    assert_true(nine == eighty_one, nine.to_string(20))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
