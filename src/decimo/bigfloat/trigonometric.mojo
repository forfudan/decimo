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
from decimo.bigfloat.exponential import (
    round_by_deciding,
    round_by_deciding_at,
    round_by_deciding_at_two,
    sqrt,
)
from decimo.bigfloat.rounding import (
    MAX_PRECISION,
    checked_precision,
    cubic_term_is_below_a_guard_unit,
    fixed_point_scale,
    from_fixed_point,
    guard_bits,
    leading_bit_position,
    round_to_precision,
    rounded_beside,
    square_fixed_point_scale,
    square_to_fixed_point,
    to_fixed_point,
    working_width,
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

comptime _INVERSE_SLACK = 8
"""Units in the last place the inverse functions' kernels may be off by.

Each halving of the argument costs a square root and a division, the series
costs a unit a term, and the identities that reach the inverse sine and
cosine add a root and a division of their own.
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
    var leading = leading_bit_position(x)
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


def _nearest_to_bigint(value: BigFloat, width: Int) raises -> BigInt:
    """The integer nearest a finite value.

    Args:
        value: The value.
        width: A precision wide enough to hold its integer part and a bit
            more, so that adding a half is exact.

    Returns:
        The nearest integer, ties going away from zero.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var half = BigFloat.power_of_two(-1)
    if value.sign:
        half = -half
    return _truncated_to_bigint(bigfloat_arithmetics.add(value, half, width))


def _reduced(x: BigFloat, width: Int) raises -> Tuple[BigFloat, Int]:
    """Writes `x` as `k * (pi/2) + r` and returns `r` with `k mod 4`.

    Args:
        x: The argument, finite and not zero.
        width: The bits wanted in the answer.

    Returns:
        The remainder, whose magnitude is at most `pi/4`, and which quadrant
        `k` lands in, from zero to three.

    Raises:
        OverflowError: If the reduction needs more bits of pi than a
            precision may be, or cannot resolve the remainder in eight tries.
        Error: Propagated from the arithmetic.

    Notes:

    `k` is the nearest multiple and not the one toward zero. Toward zero
    leaves `r` anywhere in `[0, pi/2)`, and a remainder near `pi/2` is where
    the cosine's series is worst: `cos(r)` is then near nought, so putting
    the leading one back cancels it away and the kernel's error bound stops
    holding. The nearest multiple leaves `|r| <= pi/4`, where `cos(r)` is at
    least `0.707` and nothing cancels.

    The remainder is then checked rather than trusted. Pi is irrational and
    the pi used here is rounded, so subtracting `k * (pi/2)` cancels the
    argument's leading bits against a value that is itself only approximate:
    the error in `r` is about `|x| * 2^-scale`, and `r` has to stand well
    above that to mean anything. An argument that happens to agree with the
    rounded `pi/2` to the working width -- `pi(88)/2` itself, say -- leaves a
    remainder of exactly nought, which would make the cosine nought and the
    tangent an infinity, though no binary float is a pole. So when `r` is too
    small for its own error the scale grows and the reduction runs again.
    """
    var leading = leading_bit_position(x)
    var scale = _reduction_width(x, width)
    for _ in range(8):
        var half_pi = bigfloat_arithmetics.multiply(
            pi(scale), BigFloat.power_of_two(-1), scale
        )
        var quotient = bigfloat_arithmetics.divide(x, half_pi, scale)
        var multiple = _nearest_to_bigint(quotient, scale + 4)
        var remainder = x.copy()
        if not multiple.is_zero():
            remainder = bigfloat_arithmetics.subtract(
                x,
                bigfloat_arithmetics.multiply(
                    BigFloat.from_bigint(multiple, scale), half_pi, scale
                ),
                scale,
            )
        # The error in the remainder is about `|x| * 2^-scale`, so its
        # leading bit has to sit at least `width` places above that.
        var floor_position = leading - BigInt(scale) + BigInt(width) + BigInt(8)
        if not remainder.is_zero():
            if leading_bit_position(remainder) >= floor_position:
                var quadrant = (multiple % BigInt(4)).to_int()
                if quadrant < 0:
                    quadrant += 4
                return (remainder^, quadrant)
        scale = _widened_reduction(scale, width)
    raise OverflowError(
        message=(
            "The reduction of this argument could not be resolved: its"
            " remainder cancels against pi further than eight widenings"
            " reach."
        ),
        function="_reduced()",
    )


def _widened_reduction(scale: Int, width: Int) raises -> Int:
    """The next scale to try when a remainder cancelled too far.

    Args:
        scale: The scale that was not enough.
        width: The bits wanted in the answer.

    Returns:
        A wider scale.

    Raises:
        OverflowError: If that is more than a precision may be.
    """
    if scale > MAX_PRECISION - width - 16:
        raise OverflowError(
            message=(
                "Resolving this reduction needs more bits of pi than a"
                " precision may be."
            ),
            function="_reduced()",
        )
    return scale + width + 16


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

    It is summed in fixed-point integers, whose scale is taken from `x` --
    the first term -- so that a term costs a shift and a division by a small
    integer rather than a rounded multiply, divide and add. The magnitudes
    stay positive and the alternation is applied as they are added, which
    leaves every division a truncation toward nought. The sum itself is
    positive for every argument the caller sends, `pi/4` being well short of
    where the sine turns.
    """
    if x.is_zero():
        return BigFloat.zero(width, x.sign)
    var scale = fixed_point_scale(x, width)
    var magnitude = to_fixed_point(x, scale)
    var square = (magnitude * magnitude) >> scale

    var total = magnitude.copy()
    var term = magnitude.copy()
    var index = 2
    var subtract = True
    while True:
        term = ((term * square) >> scale).truncate_divide(
            BigInt(index * (index + 1))
        )
        if term.is_zero():
            return from_fixed_point(total, scale, width, x.sign)
        if subtract:
            total -= term
        else:
            total += term
        subtract = not subtract
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

    It is summed in fixed-point integers, like the sine's, but at the scale of
    `x^2` rather than of `x`, because `x^2/2` is the first term here. The sum
    is negative for every argument but nought, the first term outweighing all
    that follow it.
    """
    if x.is_zero():
        return BigFloat.zero(width, False)
    var scale = square_fixed_point_scale(x, width)
    var square = square_to_fixed_point(x, scale)

    var total = BigInt.zero()
    var term = square >> 1
    var index = 3
    var subtract = True
    while True:
        if subtract:
            total -= term
        else:
            total += term
        subtract = not subtract
        term = ((term * square) >> scale).truncate_divide(
            BigInt(index * (index + 1))
        )
        if term.is_zero():
            return from_fixed_point(abs(total), scale, width, total.sign)
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

    var scale = working_width(width)
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

    var scale = working_width(width)
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
        and cubic_term_is_below_a_guard_unit(x, guard_bits(x, precision))
    ):
        # `sin(x) = x - x^3/6 + ...`, so the answer is `x` moved toward zero.
        return rounded_beside(x, precision, rounding_mode, True)
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
    # The cosine of a nought is exactly one, which is the one answer the loop
    # below can never settle on, so it is answered here.
    if x.is_zero():
        return BigFloat.from_int(1, precision)
    if (
        x.is_finite()
        and compare_absolute(x, BigFloat.power_of_two(-(precision + 8) // 2))
        < 0
    ):
        var square = bigfloat_arithmetics.multiply(x, x, precision + 8)
        var half_square = bigfloat_arithmetics.multiply(
            square, BigFloat.power_of_two(-1), precision + 8
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
        and cubic_term_is_below_a_guard_unit(x, guard_bits(x, precision))
    ):
        # `tan(x) = x + x^3/3 + ...`, away from zero.
        return rounded_beside(x, precision, rounding_mode, False)
    return round_by_deciding_at[_tan_kernel, _TANGENT_SLACK](
        x, precision, rounding_mode
    )


# ===----------------------------------------------------------------------=== #
# The inverse functions
# ===----------------------------------------------------------------------=== #


def _arctangent_series(x: BigFloat, width: Int) raises -> BigFloat:
    """`arctan(x)` for a small `x`, as a sum of its terms.

    Args:
        x: The argument, whose magnitude should be well below one.
        width: The bits to work in.

    Returns:
        The sum.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The series is `x - x^3/3 + x^5/5 - ...`, which gains `2 log2(1/|x|)` bits
    a term. That is why the caller halves the argument first: at `|x|` near
    one the series gains nothing at all.

    It is summed in fixed-point integers at the scale of `x`, and the running
    power of `x^2` is kept apart from the division by the odd number so that
    the two truncations do not compound. The sum is positive for a positive
    argument, the arctangent keeping the sign of what it is given.
    """
    if x.is_zero():
        return BigFloat.zero(width, x.sign)
    var scale = fixed_point_scale(x, width)
    var magnitude = to_fixed_point(x, scale)
    var square = (magnitude * magnitude) >> scale

    var total = magnitude.copy()
    var power = magnitude.copy()
    var index = 3
    var subtract = True
    while True:
        power = (power * square) >> scale
        var term = power.truncate_divide(BigInt(index))
        if term.is_zero():
            return from_fixed_point(total, scale, width, x.sign)
        if subtract:
            total -= term
        else:
            total += term
        subtract = not subtract
        index += 2


def _arctangent_of_small(x: BigFloat, width: Int) raises -> BigFloat:
    """`arctan(x)` for `|x| <= 1`, by halving the argument and then summing.

    Args:
        x: The argument, with magnitude at most one.
        width: The bits to work in.

    Returns:
        The value.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The identity is `arctan(x) = 2 arctan(x / (1 + sqrt(1 + x^2)))`, which
    roughly halves the argument each time it is applied. The series gains
    `2 log2(1/|x|)` bits a term, so halving until `|x|` is below `1/width`
    leaves about `width / (2 log2 width)` terms to sum -- fifty of them at a
    thousand bits, against a series that would never finish at `|x| = 1`.

    Doubling the answer back does not lose anything: the answer is
    `2^m` times a value `2^m` smaller, so the relative error is carried
    through unchanged.
    """
    var one = BigFloat.from_int(1, width)
    var target = BigFloat.power_of_two(-Int(bit_width(UInt(width))) - 1)
    var reduced = BigFloat.from_rounded_parts(
        x.significand, x.exponent, width, x.sign
    )
    var halvings = 0
    while not reduced.is_zero() and compare_absolute(reduced, target) >= 0:
        var root = sqrt(
            bigfloat_arithmetics.add(
                one,
                bigfloat_arithmetics.multiply(reduced, reduced, width),
                width,
            ),
            width,
        )
        reduced = bigfloat_arithmetics.divide(
            reduced, bigfloat_arithmetics.add(one, root, width), width
        )
        halvings += 1
    var total = _arctangent_series(reduced, width)
    if halvings > 0:
        total = bigfloat_arithmetics.multiply(
            total, BigFloat.power_of_two(halvings), width
        )
    return total^


def _arctan_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`arctan(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_INVERSE_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    An argument above one is turned over: `arctan(x)` is `pi/2 - arctan(1/x)`
    for a positive `x`, and the mirror for a negative one. That leaves the
    halving identity an argument it can shrink, and costs no cancellation,
    since `arctan(1/x)` is below `pi/4` and `pi/2` is above it.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_zero():
        return BigFloat.zero(width, x.sign)

    var scale = width + Int(bit_width(UInt(width))) + 16

    # Pi is built only where it is used. Below one the series is the whole
    # answer and pi never appears, and asking for it there would make every
    # ordinary call pay for the constant -- at high precision that is most of
    # the work.
    if x.is_finite() and compare_absolute(x, BigFloat.from_int(1, 1)) <= 0:
        var series = _arctangent_of_small(x, scale)
        return BigFloat.from_rounded_parts(
            series.significand, series.exponent, width, series.sign
        )

    var half_pi = bigfloat_arithmetics.multiply(
        pi(scale), BigFloat.power_of_two(-1), scale
    )
    if x.is_infinite() or leading_bit_position(x) >= BigInt(width + 2):
        # An infinity settles at a right angle, and so does an argument so
        # large that the correction `1/x` falls below half a unit in the last
        # place of the answer. Taking that branch rather than forming `1/x`
        # is not only a saving: at the top of the exponent range the
        # reciprocal has no exponent, and an argument whose inverse tangent
        # is an ordinary number would be refused. Nothing can widen its way
        # out of this branch either, since `width` cannot reach the leading
        # bit of such an argument.
        var answer = half_pi.copy()
        if x.sign:
            answer = -answer
        return BigFloat.from_rounded_parts(
            answer.significand, answer.exponent, width, answer.sign
        )

    var reciprocal = bigfloat_arithmetics.divide(
        BigFloat.from_int(1, scale), x, scale
    )
    var total = bigfloat_arithmetics.subtract(
        half_pi, _arctangent_of_small(abs(reciprocal), scale), scale
    )
    if x.sign:
        total = -total
    return BigFloat.from_rounded_parts(
        total.significand, total.exponent, width, total.sign
    )


def arctan(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The inverse tangent of a value, correctly rounded.

    Args:
        x: The argument.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `arctan(x)`, between `-pi/2`
        and `pi/2`.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    An infinity has an answer here, unlike in the forward functions: the
    inverse tangent settles at `pi/2`, so that is what it gives.

    A small argument is `x - x^3/3`, toward zero, so it is answered by moving
    `x` that way rather than by returning it -- and only where the cubic term
    is small enough for a guard unit to stand in for it, which is the same
    condition the sine's shortcut keeps to.
    """
    _ = checked_precision(precision, "arctan()")
    if (
        x.is_finite()
        and not x.is_zero()
        and cubic_term_is_below_a_guard_unit(x, guard_bits(x, precision))
    ):
        return rounded_beside(x, precision, rounding_mode, True)
    return round_by_deciding_at[_arctan_kernel, _INVERSE_SLACK](
        x, precision, rounding_mode
    )


comptime _TURN_SLACK = 4
"""Units in the last place the three-eighths turn's kernel may be off by.

Pi is correctly rounded and three times a significand is exact, so what is
left is the one rounding to the width asked for.
"""

comptime _ARCTAN2_SLACK = 8
"""Units in the last place the two-argument arctangent's kernel may be off by.

The division, the one-argument arctangent and the addition of pi each cost a
unit or two of the working width.
"""


def _arctangent_of_ratio(
    y: BigFloat, x: BigFloat, work: Int
) raises -> BigFloat:
    """`arctan(y / x)` to `work` bits, for two finite non-zero coordinates.

    Args:
        y: The second coordinate.
        x: The first coordinate.
        work: The bits wanted.

    Returns:
        The value, within a unit or two of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The quotient is formed only where it exists. Two coordinates at opposite
    ends of the exponent range have a ratio that no exponent can hold, and
    yet the angle between them is an ordinary number -- a right angle, or a
    half turn, to far more bits than anyone asks for. So the two ends of the
    range are answered from the identity instead of from the division.

    A ratio whose leading bit sits above the working width makes the angle a
    right angle: the correction to it is `1/ratio`, below an eighth of the
    last place here. That is the one-argument arctangent's own shortcut, and
    this is it taken before the division rather than after.

    The other end only works in the left half plane, where `pi` is about to
    be added and is the whole answer. There a ratio that small leaves the
    angle a half turn, so the arctangent can come back as a nought and let
    the addition carry the value. In the right half plane the ratio is the
    answer and nothing can stand in for it, which is why the caller turns
    that case away before reaching here.
    """
    var negative = y.sign != x.sign
    var gap = leading_bit_position(y) - leading_bit_position(x)

    if gap >= BigInt(work + 3):
        var half_turn = pi(work)
        return BigFloat(
            significand=half_turn.significand,
            exponent=half_turn.exponent - 1,
            precision=work,
            sign=negative,
        )

    if x.sign and gap <= BigInt(-(work + 3)):
        return BigFloat.zero(work, negative)

    return _arctan_kernel(bigfloat_arithmetics.divide(y, x, work), work)


def _arctan2_at_width(y: BigFloat, x: BigFloat, width: Int) raises -> BigFloat:
    """The angle of the point `(x, y)` to `width` bits.

    Args:
        y: The second coordinate.
        x: The first coordinate, which must not be nought.
        width: The bits wanted.

    Returns:
        The angle, within `_ARCTAN2_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `arctan(y / x)` gives the angle in the right half plane and is a half
    turn out in the left one, where pi is added or subtracted according to
    the sign of `y` so that the answer lands in `(-pi, pi]`.

    Nothing cancels. The answer is near nought only in the right half plane,
    where no pi is added at all, and in the left half plane `arctan(y / x)`
    and pi are both about a right angle, so their sum keeps every bit it had.
    """
    var work = working_width(width)
    var angle = _arctangent_of_ratio(y, x, work)
    if x.sign:
        var half_turn = pi(work)
        if y.sign:
            angle = bigfloat_arithmetics.subtract(angle, half_turn, work)
        else:
            angle = bigfloat_arithmetics.add(angle, half_turn, work)
    return BigFloat.from_rounded_parts(
        angle.significand, angle.exponent, width, angle.sign
    )


def arctan2(
    y: BigFloat,
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The angle of the point `(x, y)`, correctly rounded.

    Args:
        y: The second coordinate.
        x: The first coordinate.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The angle in `(-pi, pi]` whose tangent is `y / x`, taking the
        quadrant from the signs of both.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If the angle lies so near the positive horizontal axis
            that its own exponent would not fit an `Int`. Every other angle,
            including the ones whose coordinates have no quotient, is
            answered.
        Error: If the rounding cannot be decided, or propagated from the
            arithmetic.

    Notes:

    The argument order is the one every other language uses: the second
    coordinate first, because the function is the inverse of a tangent and a
    tangent is a rise over a run.

    This is where signed zeros earn their keep. `arctan2(0, -1)` is pi and
    `arctan2(-0, -1)` is minus pi: the two zeros are on opposite shores of
    the cut along the negative axis, and the sign is the only thing that says
    which. The same goes for the axis itself -- `arctan2(1, 0)` and
    `arctan2(1, -0)` are both a right angle, because the point is on the
    positive vertical axis either way.

    The special values follow IEEE 754's `atan2`, including the four
    diagonals between the infinities, which are the odd multiples of a
    quarter turn.
    """
    _ = checked_precision(precision, "arctan2()")

    if x.is_nan() or y.is_nan():
        return BigFloat.nan(precision)

    if x.is_infinite():
        if y.is_infinite():
            # The diagonals: an eighth of a turn into the right half plane,
            # three eighths into the left.
            if x.sign:
                return _three_eighth_turn(precision, y.sign, rounding_mode)
            return _turn(precision, 2, y.sign, rounding_mode)
        # A finite second coordinate against an infinite first: the angle is
        # a nought or a half turn, by the sign of the first.
        if x.sign:
            return _turn(precision, 0, y.sign, rounding_mode)
        return BigFloat.zero(precision, y.sign)

    if y.is_infinite():
        return _turn(precision, 1, y.sign, rounding_mode)

    if y.is_zero():
        # On the horizontal axis. The sign of the first coordinate says which
        # side of the origin, and the sign of the nought which shore of the
        # cut.
        if x.sign:
            return _turn(precision, 0, y.sign, rounding_mode)
        return BigFloat.zero(precision, y.sign)

    if x.is_zero():
        return _turn(precision, 1, y.sign, rounding_mode)

    # In the right half plane a ratio whose cube cannot reach the last place
    # leaves the angle equal to the ratio, less a hair. The loop below cannot
    # answer that: once the series terminates on its first term the kernel
    # returns the ratio exactly, and an exactly representable value has
    # rounding neighbours on both sides, so the directed modes widened to the
    # limit and refused. The one-argument arctangent guards this already;
    # this is the same guard, asked of the ratio without forming it, because
    # a ratio that small can be below what an exponent holds.
    if not x.sign:
        var gap = leading_bit_position(y) - leading_bit_position(x)
        if (gap + gap) < BigInt(-(precision + 10)):
            # Here the angle is the ratio, and a ratio can be smaller than
            # any exponent holds -- in which case so is the angle, and there
            # is no value to return. The division says so, in words about a
            # quotient the caller never asked for, so the answer is named
            # here instead.
            var ratio: BigFloat
            try:
                ratio = bigfloat_arithmetics.divide(y, x, precision + 8)
            except:
                raise OverflowError(
                    message=(
                        "The angle of this point is too near the horizontal"
                        " axis for its exponent to fit in an Int."
                    ),
                    function="arctan2()",
                )
            return rounded_beside(ratio, precision, rounding_mode, True)

    return round_by_deciding_at_two[_arctan2_at_width, _ARCTAN2_SLACK](
        y, x, precision, rounding_mode
    )


def _magnitude_mode(
    rounding_mode: RoundingMode, negative: Bool
) -> RoundingMode:
    """The mode as it applies to a magnitude, once the sign is known.

    Args:
        rounding_mode: The mode asked for.
        negative: Whether the answer is below nought.

    Returns:
        The mode that rounds `|answer|` the way `rounding_mode` rounds the
        answer.

    Notes:

    Five of the seven modes do not care about the sign. The two that point at
    an end of the line do: toward positive infinity is away from nought for a
    positive value and toward it for a negative one, and the other way about
    for toward negative infinity. The constant below is asked for a
    magnitude, so the sign has to be folded in before it is.
    """
    if rounding_mode == RoundingMode.ROUND_CEILING:
        return RoundingMode.ROUND_DOWN if negative else RoundingMode.ROUND_UP
    if rounding_mode == RoundingMode.ROUND_FLOOR:
        return RoundingMode.ROUND_UP if negative else RoundingMode.ROUND_DOWN
    return rounding_mode


def _turn(
    precision: Int, halvings: Int, negative: Bool, rounding_mode: RoundingMode
) raises -> BigFloat:
    """Pi over a power of two, correctly rounded, with the sign asked for.

    Args:
        precision: The bits the answer keeps.
        halvings: How many times to halve pi. Nought gives a half turn, one a
            quarter turn, two an eighth.
        negative: Whether to give the angle below the axis.
        rounding_mode: Which way to round.

    Returns:
        `pi / 2^halvings` to `precision` bits.

    Raises:
        Error: Propagated from the constant.

    Notes:

    Pi is asked for at the precision wanted and not at a wider one, because
    rounding a wider value again is a double rounding, and a double rounding
    is not a rounding. It goes wrong whenever the bits between the two widths
    sit on the half-way pattern, which for pi happens at about two precisions
    in three: with eight guard bits, `arctan2(1, 0)` at 189 bits came back a
    unit below the correctly rounded right angle.

    Halving is what makes one rounding enough. Dividing by a power of two is
    exact and rounding to a count of significant bits does not care about the
    scale, so rounding pi and then halving gives what rounding the half
    would. No other divisor has that property, which is why the three-eighth
    turn below cannot be had this way.
    """
    var turn = pi(precision, _magnitude_mode(rounding_mode, negative))
    return BigFloat(
        significand=turn.significand,
        exponent=turn.exponent - halvings,
        precision=precision,
        sign=negative,
    )


def _three_eighth_turn_at_width(width: Int) raises -> BigFloat:
    """Three quarters of pi to `width` bits.

    Args:
        width: The bits wanted.

    Returns:
        The value, within `_TURN_SLACK` units of the last place.

    Raises:
        Error: Propagated from the constant.

    Notes:

    Three quarters of a turn is the one diagonal that is not pi over a power
    of two, so it cannot be had by moving an exponent and has to be decided
    like any other irrational value. Three times a significand is exact, so
    the only error is the constant's own and the one rounding here.
    """
    var work = width + Int(bit_width(UInt(width))) + 8
    var turn = pi(work)
    return BigFloat.from_rounded_parts(
        turn.significand * BigInt(3), turn.exponent - 2, width, False
    )


def _three_eighth_turn(
    precision: Int, negative: Bool, rounding_mode: RoundingMode
) raises -> BigFloat:
    """Three quarters of pi, correctly rounded, with the sign asked for.

    Args:
        precision: The bits the answer keeps.
        negative: Whether to give the angle below the axis.
        rounding_mode: Which way to round.

    Returns:
        `3 pi / 4` to `precision` bits.

    Raises:
        Error: Propagated from the constant, or if the rounding cannot be
            decided.
    """
    var magnitude = round_by_deciding[_three_eighth_turn_at_width, _TURN_SLACK](
        precision, _magnitude_mode(rounding_mode, negative)
    )
    return BigFloat(
        significand=magnitude.significand,
        exponent=magnitude.exponent,
        precision=precision,
        sign=negative,
    )


def _arcsin_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`arcsin(x)` to `width` bits.

    Args:
        x: The argument, whose magnitude must be at most one.
        width: The bits wanted.

    Returns:
        The value, within `_INVERSE_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The identity is `arcsin(x) = arctan(x / sqrt(1 - x^2))`, and the only
    care it needs is where `1 - x^2` cancels. For `|x|` near one it cancels
    almost entirely -- at `|x| = 1 - 2^-d` the difference is about `2^(1-d)`
    -- so the working width carries those `d` bits, counted from how far the
    argument is from one rather than guessed at. The quotient is then
    enormous, which is the one case `arctan`'s own reduction is built for.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_infinite():
        return BigFloat.nan(width)
    if x.is_zero():
        return BigFloat.zero(width, x.sign)

    var one = BigFloat.from_int(1, width + 8)
    var magnitude = abs(x)
    var order = compare_absolute(x, one)
    if order > 0:
        return BigFloat.nan(width)

    var scale = width + Int(bit_width(UInt(width))) + 16
    if order == 0:
        var right_angle = bigfloat_arithmetics.multiply(
            pi(scale), BigFloat.power_of_two(-1), scale
        )
        if x.sign:
            right_angle = -right_angle
        return BigFloat.from_rounded_parts(
            right_angle.significand,
            right_angle.exponent,
            width,
            right_angle.sign,
        )

    # How many bits `1 - x^2` will cancel, from the distance to one.
    var gap = bigfloat_arithmetics.subtract(
        BigFloat.from_int(1, width + 8), magnitude, width + 8
    )
    if not gap.is_zero():
        var position = leading_bit_position(gap)
        if position < BigInt.zero():
            var lost = -position
            if lost > BigInt(MAX_PRECISION - scale):
                raise OverflowError(
                    message=(
                        "This argument is so close to one that the identity"
                        " would need more bits than a precision may be."
                    ),
                    function="arcsin()",
                )
            scale += lost.to_int()

    var wide_one = BigFloat.from_int(1, scale)
    var square = bigfloat_arithmetics.multiply(x, x, scale)
    var root = sqrt(
        bigfloat_arithmetics.subtract(wide_one, square, scale), scale
    )
    var quotient = bigfloat_arithmetics.divide(x, root, scale)
    var total = _arctan_kernel(quotient, scale)
    return BigFloat.from_rounded_parts(
        total.significand, total.exponent, width, total.sign
    )


def _arccos_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`arccos(x)` to `width` bits.

    Args:
        x: The argument, whose magnitude must be at most one.
        width: The bits wanted.

    Returns:
        The value, within `_INVERSE_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Below a half the answer is `pi/2 - arcsin(x)`, where the two parts are
    the same size and nothing is lost. Above it that subtraction cancels --
    the answer runs to nought as the argument runs to one -- so the half
    angle is used instead: `arccos(x) = 2 arcsin(sqrt((1-x)/2))`, whose
    argument runs to nought with the answer and cancels nowhere.
    """
    if x.is_nan() or x.is_infinite():
        return BigFloat.nan(width)
    var one = BigFloat.from_int(1, width + 8)
    if compare_absolute(x, one) > 0:
        return BigFloat.nan(width)

    var scale = width + Int(bit_width(UInt(width))) + 16
    var half = BigFloat.power_of_two(-1)
    if compare_absolute(x, half) <= 0 or x.sign:
        var right_angle = bigfloat_arithmetics.multiply(
            pi(scale), BigFloat.power_of_two(-1), scale
        )
        var total = bigfloat_arithmetics.subtract(
            right_angle, _arcsin_kernel(x, scale), scale
        )
        return BigFloat.from_rounded_parts(
            total.significand, total.exponent, width, total.sign
        )

    # A positive argument above a half: the half angle avoids the
    # cancellation that `pi/2 - arcsin(x)` would suffer.
    var gap = bigfloat_arithmetics.subtract(
        BigFloat.from_int(1, scale), x, scale
    )
    if gap.is_zero():
        return BigFloat.zero(width, False)
    var root = sqrt(
        bigfloat_arithmetics.multiply(gap, BigFloat.power_of_two(-1), scale),
        scale,
    )
    var total = bigfloat_arithmetics.multiply(
        _arcsin_kernel(root, scale), BigFloat.power_of_two(1), scale
    )
    return BigFloat.from_rounded_parts(
        total.significand, total.exponent, width, total.sign
    )


def arcsin(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The inverse sine of a value, correctly rounded.

    Args:
        x: The argument, whose magnitude must be at most one.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `arcsin(x)`, between `-pi/2`
        and `pi/2`. An argument outside `[-1, 1]` gives a NaN, as it has no
        inverse sine among the reals.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    A small argument is `x + x^3/6`, away from zero, which is the other way
    from the inverse tangent's.
    """
    _ = checked_precision(precision, "arcsin()")
    if (
        x.is_finite()
        and not x.is_zero()
        and cubic_term_is_below_a_guard_unit(x, guard_bits(x, precision))
    ):
        return rounded_beside(x, precision, rounding_mode, False)
    return round_by_deciding_at[_arcsin_kernel, _INVERSE_SLACK](
        x, precision, rounding_mode
    )


def arccos(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The inverse cosine of a value, correctly rounded.

    Args:
        x: The argument, whose magnitude must be at most one.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `arccos(x)`, between nought and
        `pi`. An argument outside `[-1, 1]` gives a NaN.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    `arccos(1)` is a positive zero, which is the one value of this function
    that is exact.
    """
    _ = checked_precision(precision, "arccos()")
    return round_by_deciding_at[_arccos_kernel, _INVERSE_SLACK](
        x, precision, rounding_mode
    )
