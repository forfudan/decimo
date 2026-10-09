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


"""The circular functions of a binary float.

Everything here turns on one reduction. The series for a sine or a cosine
only converges while its argument is small, so the argument is first written
as `k * (pi/2) + r` with `|r|` at most `pi/4`, and which of the four
quadrants `k` lands in says whether the answer is the sine or the cosine of
`r`, and with which sign.

That reduction is the whole difficulty, and the reason is that pi is
irrational. Subtracting `k * (pi/2)` from a large argument cancels the
leading bits, so as many bits of pi are needed as the argument has, plus the
bits the answer wants. An argument of `2^1000` needs a thousand bits of pi
before the first bit of the answer is right, and this asks for them: the
count is derived from the argument's own leading bit rather than fixed, and
`k` is a `BigInt` because it can be far larger than an `Int`.

The cosine's series computes `cos(r) - 1` for the same reason the
exponential's computes `exp(x) - 1`: a leading one would swamp a small
argument, while adding it back through the addition turns what would vanish
into the sticky bit it is.
"""

from std.bit import bit_width

import decimo.bigfloat.arithmetics as bigfloat_arithmetics
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.comparison import compare_absolute
from decimo.bigfloat.constants import pi
from decimo.bigfloat.exponential import round_by_deciding_at
from decimo.bigfloat.rounding import (
    MAX_PRECISION,
    checked_precision,
    round_to_precision,
)
from decimo.bigint.bigint import BigInt
from decimo.errors import OverflowError
from decimo.rounding_mode import RoundingMode


comptime _SINE_SLACK = 4
"""Units in the last place the sine's and cosine's kernels may be off by.

The reduction, the series and the one addition that puts the leading one back
each cost a unit or two of the working width, and the working width carries
`bit_width(terms) + 8` bits beyond what the kernel returns.
"""

comptime _TANGENT_SLACK = 8
"""Units in the last place the tangent's kernel may be off by.

It is a sine over a cosine, so both of their bounds compound and the division
rounds once more.
"""


def _truncated_to_bigint(value: BigFloat) raises -> BigInt:
    """The integer part of a finite value, toward zero.

    Args:
        value: The value.

    Returns:
        The integer part, which can be far larger than an `Int`.

    Raises:
        Error: Propagated from the arithmetic.
    """
    if value.is_zero() or value.exponent + value.precision <= 0:
        return BigInt.zero()
    var magnitude = value.significand.copy()
    if value.exponent >= 0:
        magnitude = magnitude << value.exponent
    else:
        magnitude = magnitude >> -value.exponent
    if value.sign:
        magnitude = -magnitude
    return magnitude^


def _leading_bit_position(x: BigFloat) raises -> BigInt:
    """Where the top bit of a finite non-zero value sits.

    Args:
        x: The value.

    Returns:
        `exponent + precision - 1`, as a `BigInt` because that sum can leave
        an `Int` while the value itself is ordinary.

    Raises:
        Error: Propagated from the arithmetic.
    """
    return BigInt(x.exponent) + BigInt(x.precision) - BigInt.one()


def _reduction_width(x: BigFloat, width: Int) raises -> Int:
    """How many bits of pi the reduction of `x` needs.

    Args:
        x: The argument.
        width: The bits wanted in the answer.

    Returns:
        The width to ask pi for.

    Raises:
        OverflowError: If that is more than a precision may be.
        Error: Propagated from the arithmetic.

    Notes:

    Subtracting `k * (pi/2)` cancels the leading bits of `x`, so the answer's
    first bit needs as many bits of pi as `x` has above the binary point,
    plus the width wanted and room for the series. An argument whose leading
    bit sits beyond what a precision may be would need more bits of pi than
    this layer accepts, and that is said rather than attempted.
    """
    var leading = _leading_bit_position(x)
    var above = 0
    if leading > BigInt.zero():
        if leading > BigInt(MAX_PRECISION):
            raise OverflowError(
                message=(
                    "Reducing an argument this large needs more bits of pi"
                    " than a precision may be."
                ),
                function="_reduction_width()",
            )
        above = leading.to_int()
    var total = width + above + Int(bit_width(UInt(width))) + 16
    if total > MAX_PRECISION:
        raise OverflowError(
            message=(
                "Reducing an argument this large needs more bits of pi than a"
                " precision may be."
            ),
            function="_reduction_width()",
        )
    return total


def _reduced(x: BigFloat, width: Int) raises -> Tuple[BigFloat, Int]:
    """Writes `x` as `k * (pi/2) + r` and returns `r` with `k mod 4`.

    Args:
        x: The argument, finite.
        width: The bits wanted in the answer.

    Returns:
        The remainder, whose magnitude is at most `pi/4` and a little, and
        which quadrant `k` lands in, from zero to three.

    Raises:
        OverflowError: If the reduction needs more bits of pi than a
            precision may be.
        Error: Propagated from the arithmetic.
    """
    var scale = _reduction_width(x, width)
    var half_pi = bigfloat_arithmetics.multiply(
        pi(scale), _power_of_two(-1), scale
    )
    var quotient = bigfloat_arithmetics.divide(
        x, half_pi, scale, RoundingMode.ROUND_DOWN
    )
    var multiple = _truncated_to_bigint(quotient)
    var remainder = x.copy()
    if not multiple.is_zero():
        remainder = bigfloat_arithmetics.subtract(
            x,
            bigfloat_arithmetics.multiply(
                BigFloat.from_bigint(multiple, scale), half_pi, scale
            ),
            scale,
        )
    # The quadrant is `k` modulo four, taken toward negative infinity so that
    # a negative `k` lands in the same four cases as a positive one.
    var quadrant = (multiple % BigInt(4)).to_int()
    if quadrant < 0:
        quadrant += 4
    return (remainder^, quadrant)


def _power_of_two(exponent: Int) raises -> BigFloat:
    """`2^exponent` held in a single bit.

    Args:
        exponent: The power.

    Returns:
        The value, which multiplying by is exact at any precision.

    Raises:
        Error: Propagated from the construction.
    """
    return BigFloat(
        significand=BigInt.one(), exponent=exponent, precision=1, sign=False
    )


def _sine_series(x: BigFloat, width: Int) raises -> BigFloat:
    """`sin(x)` for a small `x`, as a sum of its terms.

    Args:
        x: The argument, whose magnitude should be at most `pi/4`.
        width: The bits to work in.

    Returns:
        The sum.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The series is `x - x^3/3! + x^5/5! - ...`, each term the one before it
    times `-x^2` over the two integers that follow. There is no leading
    constant to swamp a small argument, so the sum needs no help from the
    addition the way the cosine's does.
    """
    if x.is_zero():
        return BigFloat.zero(width, x.sign)
    var square = bigfloat_arithmetics.multiply(x, x, width)
    var term = BigFloat.from_rounded_parts(
        x.significand, x.exponent, width, x.sign
    )
    var total = term.copy()
    var index = 2
    while True:
        term = bigfloat_arithmetics.divide(
            bigfloat_arithmetics.multiply(term, square, width),
            BigFloat.from_int(index * (index + 1), width),
            width,
        )
        term = -term
        if term.is_zero():
            return total^
        if (
            compare_absolute(
                term,
                bigfloat_arithmetics.multiply(
                    total, _power_of_two(-width - 2), width
                ),
            )
            < 0
        ):
            return total^
        total = bigfloat_arithmetics.add(total, term, width)
        index += 2


def _cosine_minus_one_series(x: BigFloat, width: Int) raises -> BigFloat:
    """`cos(x) - 1` for a small `x`, as a sum of its terms.

    Args:
        x: The argument, whose magnitude should be at most `pi/4`.
        width: The bits to work in.

    Returns:
        The sum, which is negative for every argument but zero.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The series is `-x^2/2! + x^4/4! - ...`. The leading one is left for the
    caller to add, because adding it here would swamp a small argument: a
    term below the last place would vanish, while the addition turns it into
    the sticky bit it is.
    """
    if x.is_zero():
        return BigFloat.zero(width, False)
    var square = bigfloat_arithmetics.multiply(x, x, width)
    var term = bigfloat_arithmetics.divide(
        square, BigFloat.from_int(2, width), width
    )
    term = -term
    var total = term.copy()
    var index = 3
    while True:
        term = bigfloat_arithmetics.divide(
            bigfloat_arithmetics.multiply(term, square, width),
            BigFloat.from_int(index * (index + 1), width),
            width,
        )
        term = -term
        if term.is_zero():
            return total^
        if (
            compare_absolute(
                term,
                bigfloat_arithmetics.multiply(
                    total, _power_of_two(-width - 2), width
                ),
            )
            < 0
        ):
            return total^
        total = bigfloat_arithmetics.add(total, term, width)
        index += 2


def _sin_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`sin(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_SINE_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The quadrant decides which series answers. In the first and third the
    sine of the remainder is the sine of the argument, up to sign; in the
    second and fourth it is the cosine of the remainder, which is where the
    leading one has to be put back.
    """
    if x.is_nan() or x.is_infinite():
        return BigFloat.nan(width)
    if x.is_zero():
        return BigFloat.zero(width, x.sign)

    var scale = width + Int(bit_width(UInt(width))) + 12
    var parts = _reduced(x, width)
    var remainder = BigFloat.from_rounded_parts(
        parts[0].significand, parts[0].exponent, scale, parts[0].sign
    )
    var quadrant = parts[1]

    var answer = _sine_series(remainder, scale)
    if quadrant == 1 or quadrant == 3:
        answer = bigfloat_arithmetics.add(
            BigFloat.from_int(1, scale),
            _cosine_minus_one_series(remainder, scale),
            scale,
        )
    if quadrant >= 2:
        answer = -answer
    return BigFloat.from_rounded_parts(
        answer.significand, answer.exponent, width, answer.sign
    )


def _cos_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`cos(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_SINE_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The cosine is the sine a quadrant along, so this is the same work with
    the cases rotated: the first and third quadrants want the cosine of the
    remainder and the second and fourth its sine.
    """
    if x.is_nan() or x.is_infinite():
        return BigFloat.nan(width)
    if x.is_zero():
        return BigFloat.from_int(1, width)

    var scale = width + Int(bit_width(UInt(width))) + 12
    var parts = _reduced(x, width)
    var remainder = BigFloat.from_rounded_parts(
        parts[0].significand, parts[0].exponent, scale, parts[0].sign
    )
    var quadrant = parts[1]

    var answer = bigfloat_arithmetics.add(
        BigFloat.from_int(1, scale),
        _cosine_minus_one_series(remainder, scale),
        scale,
    )
    if quadrant == 1 or quadrant == 3:
        answer = _sine_series(remainder, scale)
        answer = -answer
    if quadrant == 2 or quadrant == 3:
        answer = -answer
    return BigFloat.from_rounded_parts(
        answer.significand, answer.exponent, width, answer.sign
    )


def _tan_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`tan(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_TANGENT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    A sine over a cosine, both at the working width. Near a pole the answer
    is enormous but its relative accuracy is not in doubt: the remainder is
    at most `pi/4` from a multiple of `pi/2`, so whichever of the two series
    is small is small because its own argument is, and a series knows a small
    argument exactly. There is no pole to land on, since every one of them is
    an irrational multiple of a half and no binary float is one.
    """
    if x.is_nan() or x.is_infinite():
        return BigFloat.nan(width)
    if x.is_zero():
        return BigFloat.zero(width, x.sign)

    var scale = width + Int(bit_width(UInt(width))) + 16
    var parts = _reduced(x, width)
    var remainder = BigFloat.from_rounded_parts(
        parts[0].significand, parts[0].exponent, scale, parts[0].sign
    )
    var quadrant = parts[1]

    var sine = _sine_series(remainder, scale)
    var cosine = bigfloat_arithmetics.add(
        BigFloat.from_int(1, scale),
        _cosine_minus_one_series(remainder, scale),
        scale,
    )
    # In an odd quadrant the two swap places, and the sign goes with them.
    var answer = bigfloat_arithmetics.divide(sine, cosine, scale)
    if quadrant == 1 or quadrant == 3:
        answer = bigfloat_arithmetics.divide(cosine, sine, scale)
        answer = -answer
    return BigFloat.from_rounded_parts(
        answer.significand, answer.exponent, width, answer.sign
    )


def sin(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The sine of a value, correctly rounded.

    Args:
        x: The argument, in radians.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `sin(x)`.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If reducing the argument would need more bits of pi
            than a precision may be.
        Error: Propagated from the arithmetic.

    Notes:

    An infinity has no sine, since the value does not settle anywhere, so the
    answer there is a NaN. The sine of a zero is that zero, sign and all.

    An argument below the last place of the answer does not reach the series:
    `sin(x)` is `x` less a cubic term there, and that is a subtraction the
    addition already rounds correctly. Answering it directly also keeps the
    deciding loop from widening after a bit it cannot reach.
    """
    _ = checked_precision(precision, "sin()")
    if (
        x.is_finite()
        and not x.is_zero()
        and compare_absolute(x, _power_of_two(-(precision + 4) // 2)) < 0
    ):
        # `sin(x) = x - x^3/6 + ...`, so the answer is `x` moved toward zero
        # by something positive and far below its last place. Returning `x`
        # rounded would be wrong for the directed modes: where `x` is itself
        # representable, toward zero has to give the value below it. So the
        # move is made rather than assumed, with a subtrahend that is below
        # half the last place and above nothing -- which is all the rounding
        # needs to know, since every value in that interval rounds alike.
        return bigfloat_arithmetics.subtract(
            x,
            bigfloat_arithmetics.multiply(
                x, _power_of_two(-(precision + 8)), 8
            ),
            precision,
            rounding_mode,
        )
    return round_by_deciding_at[_sin_kernel, _SINE_SLACK](
        x, precision, rounding_mode
    )


def cos(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The cosine of a value, correctly rounded.

    Args:
        x: The argument, in radians.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `cos(x)`.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If reducing the argument would need more bits of pi
            than a precision may be.
        Error: Propagated from the arithmetic.

    Notes:

    An infinity has no cosine and gives a NaN. The cosine of a zero is one,
    of either sign of zero.

    An argument small enough that `cos(x)` is one to within a rounding is
    answered by `1 - x^2/2` through the subtraction, which gets the directed
    modes right: toward zero the answer is the value below one, not one.
    """
    _ = checked_precision(precision, "cos()")
    if (
        x.is_finite()
        and not x.is_zero()
        and compare_absolute(x, _power_of_two(-(precision + 8) // 2)) < 0
    ):
        var square = bigfloat_arithmetics.multiply(x, x, precision + 8)
        var half_square = bigfloat_arithmetics.multiply(
            square, _power_of_two(-1), precision + 8
        )
        return bigfloat_arithmetics.subtract(
            BigFloat.from_int(1, precision),
            half_square,
            precision,
            rounding_mode,
        )
    return round_by_deciding_at[_cos_kernel, _SINE_SLACK](
        x, precision, rounding_mode
    )


def tan(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The tangent of a value, correctly rounded.

    Args:
        x: The argument, in radians.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `tan(x)`.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If reducing the argument would need more bits of pi
            than a precision may be.
        Error: Propagated from the arithmetic.

    Notes:

    An infinity gives a NaN. No argument is a pole, because every pole is an
    irrational multiple of a half and no binary float is one, so the answer
    is always a number -- however large.

    A small argument goes the other way from the sine's: `tan(x)` is
    `x + x^3/3`, away from zero rather than toward it. That the two differ in
    direction is the whole reason neither can simply return `x`.
    """
    _ = checked_precision(precision, "tan()")
    if (
        x.is_finite()
        and not x.is_zero()
        and compare_absolute(x, _power_of_two(-(precision + 4) // 2)) < 0
    ):
        return bigfloat_arithmetics.add(
            x,
            bigfloat_arithmetics.multiply(
                x, _power_of_two(-(precision + 8)), 8
            ),
            precision,
            rounding_mode,
        )
    return round_by_deciding_at[_tan_kernel, _TANGENT_SLACK](
        x, precision, rounding_mode
    )
