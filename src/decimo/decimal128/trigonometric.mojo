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
#
# Trigonometric functions for Decimal128
#
# ===----------------------------------------------------------------------=== #

"""Implements sine, cosine and tangent for `Decimal128`.

The work is in the argument reduction, not the series. `Decimal128` reaches
`7.9E+28`, so `x` can be twenty billion billion billion quarter-turns from
zero, and what the series needs is where `x` sits inside its own quarter
turn. Subtracting `k * (pi/2)` with a 28-digit quarter turn answers a
different question than the caller asked: by `x = 1E+20` there is nothing
left of the answer.

So the quarter turn is kept in four exact pieces of 38 digits, 152 digits in
all. `k` has at most 29 digits, so each `k * piece` is 67 digits and exact at
`Extended`, and the subtractions give back the digits the reduction is meant
to expose rather than the ones it cancelled. What survives is measured rather
than assumed, and the rounding is decided the same way `exp` and `ln` decide
theirs.
"""

from std.builtin.globals import global_constant

from decimo.decimal128.decimal128 import Decimal128
import decimo.decimal128.utility as decimal128_utility
from decimo.decimal128.wide import Wide, Extended, WideValue
from decimo.decimal128.wide import (
    fixed_from_wide,
    wide_from_fixed,
    fixed_multiply,
    fixed_divide_by_int,
    FIXED_ONE,
)
from decimo.errors import ValueError, OverflowError, ZeroDivisionError


# ===----------------------------------------------------------------------=== #
# The quarter turn, in pieces
#
# `pi/2 = PART_0 + PART_1 + PART_2 + PART_3` to within `4E-152`, each part 38
# digits and so exact at either width. Multiplied by a `k` of 29 digits the
# neglected tail is `2E-123`, which is far below the last digit of any answer
# this type can hold, even one whose reduction cancelled thirty digits.
# ===----------------------------------------------------------------------=== #

comptime _HALF_PI_PART_MANTISSA: Array[UInt256, 4] = [
    15707963267948966192313216916397514420,  # pi/2 part 0
    98584699687552910487472296153908203143,  # pi/2 part 1
    10449931401741267105853399107404325664,  # pi/2 part 2
    11533235469223047752911158626797040642,  # pi/2 part 3
]


comptime _HALF_PI_PART_EXPONENT: Array[Int, 4] = [
    -37,  # pi/2 part 0
    -75,  # pi/2 part 1
    -113,  # pi/2 part 2
    -151,  # pi/2 part 3
]


def half_pi_part_at[WIDTH: Int](index: Int) raises -> WideValue[WIDTH]:
    """Returns one piece of the quarter turn.

    Parameters:
        WIDTH: The width to return it at.

    Args:
        index: Which piece, from 0 to 3, each 38 digits below the last.

    Returns:
        The piece, exactly.

    Raises:
        Error: Propagated from the construction.
    """
    ref mantissas = global_constant[_HALF_PI_PART_MANTISSA]()
    ref exponents = global_constant[_HALF_PI_PART_EXPONENT]()
    return WideValue[WIDTH](mantissas[index], exponents[index], False)


def two_over_pi_at[WIDTH: Int]() raises -> WideValue[WIDTH]:
    """Returns `2/pi`, the number of quarter turns in one radian.

    Parameters:
        WIDTH: The width to return it at.

    Returns:
        The constant.

    Raises:
        Error: Propagated from the construction.
    """
    comptime if WIDTH <= 38:
        return WideValue[WIDTH](
            UInt256(63661977236758134307553505349005744814), -38, False
        )
    else:
        return WideValue[WIDTH](
            UInt256(
                636619772367581343075535053490057448137838582961825794990669376235587190537
            ),
            -75,
            False,
        )


# ===----------------------------------------------------------------------=== #
# What the series and the reduction are trusted within
# ===----------------------------------------------------------------------=== #

comptime SERIES_SLACK = 500
"""Units in the last place a sine or cosine series is trusted within.

Twenty-five terms at 38 digits, each truncated at the fixed point's own last
digit, with the divisions between them.
"""


comptime REDUCTION_SLACK = 100
"""Units in the last place the reduction is trusted within, before
cancellation.

The first subtraction is exact -- `k * PART_0` has 67 digits and `Extended`
holds 75 -- so what is left is what the later pieces lose against a remainder
that has already shrunk, plus the tail beyond the fourth piece.
"""


comptime QUOTIENT_SLACK = 20
"""Units added for the division that turns a sine and a cosine into a
tangent."""


# ===----------------------------------------------------------------------=== #
# The reduction
# ===----------------------------------------------------------------------=== #


def reduce(x: Decimal128) raises -> Tuple[Extended, Int, UInt256]:
    """Writes `x` as `k * (pi/2) + r` and returns what is left.

    Args:
        x: The angle in radians.

    Returns:
        The remainder `r`, with `|r| <= pi/4`; the quadrant `k mod 4`, always
        from 0 to 3; and the units in the last place of `r`'s mantissa that
        the reduction is trusted within.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:
        `k` is the nearest whole number of quarter turns, and it need not be
        the exactly nearest one: any `k` gives a true identity, since the
        quadrant that selects the series is the same `k` that was subtracted.
        What matters is that `r` comes back with digits in it.

        The reduction runs at `Extended` whatever the caller wants, because
        at 38 digits an argument of `1E+20` has nothing left after the
        subtraction. How much is left here is measured: the widest remainder
        along the way, against the one that came out.
    """
    var wide_x = Extended.from_decimal(x)
    if x.is_zero():
        return (Extended(), 0, UInt256(REDUCTION_SLACK))

    var turns = wide_x * two_over_pi_at[75]()
    var k = turns.rounded_to_integer()
    if k.is_zero():
        # Already inside the first quarter turn, exactly as given.
        return (wide_x^, 0, UInt256(REDUCTION_SLACK))

    var quadrant = k.integer_remainder(4)
    if k.sign:
        quadrant = (4 - quadrant) % 4

    var remainder = wide_x.copy()
    var largest = remainder.exponent
    for index in range(4):
        remainder = remainder - k * half_pi_part_at[75](index)
        if remainder.is_zero():
            break
        if remainder.exponent > largest:
            largest = remainder.exponent

    var slack = UInt256(REDUCTION_SLACK)
    if not remainder.is_zero():
        var spread = largest - remainder.exponent
        if spread > 0:
            if spread > 70:
                slack = UInt256.MAX
            else:
                slack *= decimal128_utility.power_of_10[DType.uint256](spread)
    return (remainder^, quadrant, slack)


# ===----------------------------------------------------------------------=== #
# The series
# ===----------------------------------------------------------------------=== #


def sine_series_at[WIDTH: Int](r: WideValue[WIDTH]) raises -> WideValue[WIDTH]:
    """Returns `sin(r)` for `|r| <= pi/4`, at the given width.

    Parameters:
        WIDTH: The width to compute at.

    Args:
        r: The angle, whose magnitude must be at most a quarter turn.

    Returns:
        Its sine.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:
        `r - r^3/3! + r^5/5! - ...`, which at `|r| <= 0.79` crosses 38 digits
        in about twenty terms. Fixed point sums them for the price of an
        addition, but holds a fixed number of decimal places rather than of
        digits, so a tiny `r` -- which is what a reduction that cancelled
        thirty digits leaves -- would come back with a tenth of the digits it
        needs. There the series is two terms and is taken in the floating
        form.
    """
    if r.is_zero():
        return WideValue[WIDTH]()

    comptime if WIDTH == 38:
        if r.exponent >= -41:
            var r_fixed = fixed_from_wide(r.to_width[38]())
            var minus_r_squared = -fixed_multiply(r_fixed, r_fixed)
            var term = r_fixed
            var total = r_fixed
            for index in range(1, 200):
                term = fixed_multiply(term, minus_r_squared)
                term = fixed_divide_by_int(term, 2 * index * (2 * index + 1))
                if term == Int256(0):
                    break
                total += term
            return wide_from_fixed(total).to_width[WIDTH]()
        return _sine_series_floating[WIDTH](r)
    else:
        return _sine_series_floating[WIDTH](r)


def _sine_series_floating[
    WIDTH: Int
](r: WideValue[WIDTH]) raises -> WideValue[WIDTH]:
    """Returns `sin(r)` in the floating form, which keeps its digits wherever
    the value sits.

    Parameters:
        WIDTH: The width to compute at.

    Args:
        r: The angle, whose magnitude must be at most a quarter turn.

    Returns:
        Its sine.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var minus_r_squared = -(r * r)
    var term = r.copy()
    var total = r.copy()
    for index in range(1, 400):
        term = (term * minus_r_squared).divide_by_int(
            2 * index * (2 * index + 1)
        )
        if term.is_zero():
            break
        var next_total = total + term
        if next_total.compare_absolute(total) == 0:
            break
        total = next_total^
    return total^


def cosine_series_at[
    WIDTH: Int
](r: WideValue[WIDTH]) raises -> WideValue[WIDTH]:
    """Returns `cos(r)` for `|r| <= pi/4`, at the given width.

    Parameters:
        WIDTH: The width to compute at.

    Args:
        r: The angle, whose magnitude must be at most a quarter turn.

    Returns:
        Its cosine.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:
        `1 - r^2/2! + r^4/4! - ...`. The answer is about one whatever `r` is,
        so the fixed point's last decimal place is the answer's last digit
        and a tiny `r` costs nothing here.
    """
    if r.is_zero():
        return WideValue[WIDTH].from_int(1)

    comptime if WIDTH == 38:
        var r_fixed = fixed_from_wide(r.to_width[38]())
        var minus_r_squared = -fixed_multiply(r_fixed, r_fixed)
        var term = FIXED_ONE
        var total = FIXED_ONE
        for index in range(1, 200):
            term = fixed_multiply(term, minus_r_squared)
            term = fixed_divide_by_int(term, (2 * index - 1) * (2 * index))
            if term == Int256(0):
                break
            total += term
        return wide_from_fixed(total).to_width[WIDTH]()
    else:
        var minus_r_squared = -(r * r)
        var term = WideValue[WIDTH].from_int(1)
        var total = WideValue[WIDTH].from_int(1)
        for index in range(1, 400):
            term = (term * minus_r_squared).divide_by_int(
                (2 * index - 1) * (2 * index)
            )
            if term.is_zero():
                break
            var next_total = total + term
            if next_total.compare_absolute(total) == 0:
                break
            total = next_total^
        return total^


# ===----------------------------------------------------------------------=== #
# The functions
# ===----------------------------------------------------------------------=== #


def sin(x: Decimal128) raises -> Decimal128:
    """Calculates the sine of an angle in radians.

    Args:
        x: The angle in radians.

    Returns:
        Its sine, correctly rounded.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:
        The argument is reduced to a quarter turn, the quadrant picks the
        sine or the cosine series, and the answer is rounded once. Where the
        digits below it do not say which way it rounds, the series runs again
        at `Extended`.
    """
    if x.is_zero():
        return Decimal128.ZERO()
    return _circular(x, is_sine=True)


def cos(x: Decimal128) raises -> Decimal128:
    """Calculates the cosine of an angle in radians.

    Args:
        x: The angle in radians.

    Returns:
        Its cosine, correctly rounded.

    Raises:
        Error: Propagated from the arithmetic.
    """
    if x.is_zero():
        return Decimal128.ONE()
    return _circular(x, is_sine=False)


def _circular(x: Decimal128, is_sine: Bool) raises -> Decimal128:
    """Returns the sine or the cosine, whichever was asked for.

    Args:
        x: The angle in radians.
        is_sine: True for the sine, False for the cosine.

    Returns:
        The value, correctly rounded.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var reduced = reduce(x)
    var narrow = _circular_at[38](reduced, is_sine)
    var decided = narrow[0].to_decimal_decided(narrow[1])
    if decided:
        return decided.value()

    var wide = _circular_at[75](reduced, is_sine)
    var settled = wide[0].to_decimal_decided(wide[1])
    if settled:
        return settled.value()
    return wide[0].to_decimal()


def _circular_at[
    WIDTH: Int
](reduced: Tuple[Extended, Int, UInt256], is_sine: Bool) raises -> Tuple[
    WideValue[WIDTH], UInt256
]:
    """Returns the sine or cosine of a reduced angle, with how far it may be
    off.

    Parameters:
        WIDTH: The width to run the series at.

    Args:
        reduced: The remainder, the quadrant, and what the reduction is
            trusted within.
        is_sine: True for the sine, False for the cosine.

    Returns:
        The value, and the units in the last place of its mantissa that the
        computation is trusted within.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:
        The quadrant decides which series answers and with what sign:

            quadrant  0        1        2        3
            sin       sin(r)   cos(r)  -sin(r)  -cos(r)
            cos       cos(r)  -sin(r)  -cos(r)   sin(r)

        What the reduction is trusted within is stated in units of `r`'s last
        digit at 75; at 38 the last digit is 37 places coarser, and near zero
        the sine passes that straight through while the cosine flattens it
        away.
    """
    var r = reduced[0].to_width[WIDTH]()
    var quadrant = reduced[1]

    var use_sine = is_sine
    if quadrant == 1 or quadrant == 3:
        use_sine = not use_sine

    var value: WideValue[WIDTH]
    if use_sine:
        value = sine_series_at[WIDTH](r)
    else:
        value = cosine_series_at[WIDTH](r)

    var negative: Bool
    if is_sine:
        negative = quadrant == 2 or quadrant == 3
    else:
        negative = quadrant == 1 or quadrant == 2
    if negative:
        value = -value

    # `sin(r)` is `r` near zero, so an error in `r` is an error of the same
    # size in the answer; `cos(r)` is `1 - r^2/2`, where it is squared away.
    var carried = reduced[2]
    comptime if WIDTH < 75:
        var narrowing = decimal128_utility.power_of_10[DType.uint256](
            75 - WIDTH
        )
        carried = carried // narrowing + UInt256(1)
    if not use_sine:
        carried = UInt256(1)
    return (value^, carried + UInt256(SERIES_SLACK))


def tan(x: Decimal128) raises -> Decimal128:
    """Calculates the tangent of an angle in radians.

    Args:
        x: The angle in radians.

    Returns:
        Its tangent, correctly rounded.

    Raises:
        OverflowError: If the angle is so close to a pole that the tangent
            leaves what `Decimal128` holds.
        Error: Propagated from the arithmetic.

    Notes:
        `sin(r) / cos(r)` at the working width, one rounding at the end. The
        quadrant only decides the sign, since the tangent repeats every half
        turn.
    """
    if x.is_zero():
        return Decimal128.ZERO()

    var reduced = reduce(x)
    var narrow = _tangent_at[38](reduced)
    var decided = narrow[0].to_decimal_decided(narrow[1])
    if decided:
        return decided.value()

    var wide = _tangent_at[75](reduced)
    var settled = wide[0].to_decimal_decided(wide[1])
    if settled:
        return settled.value()
    return wide[0].to_decimal()


def _tangent_at[
    WIDTH: Int
](reduced: Tuple[Extended, Int, UInt256]) raises -> Tuple[
    WideValue[WIDTH], UInt256
]:
    """Returns the tangent of a reduced angle, with how far it may be off.

    Parameters:
        WIDTH: The width to run the series at.

    Args:
        reduced: The remainder, the quadrant, and what the reduction is
            trusted within.

    Returns:
        The value, and the units in the last place of its mantissa that the
        computation is trusted within.

    Raises:
        OverflowError: If the cosine is small enough that the quotient leaves
            `Decimal128`.
        Error: Propagated from the arithmetic.
    """
    var r = reduced[0].to_width[WIDTH]()
    var sine = sine_series_at[WIDTH](r)
    var cosine = cosine_series_at[WIDTH](r)

    var carried = reduced[2]
    comptime if WIDTH < 75:
        var narrowing = decimal128_utility.power_of_10[DType.uint256](
            75 - WIDTH
        )
        carried = carried // narrowing + UInt256(1)

    var quadrant = reduced[1]
    var value: WideValue[WIDTH]
    if quadrant == 1 or quadrant == 3:
        # A quarter turn on turns the tangent into minus its reciprocal.
        if sine.is_zero():
            raise OverflowError(
                message=(
                    "The tangent is too large for Decimal128 at this angle."
                ),
                function="tan()",
            )
        value = -(cosine / sine)
    else:
        if cosine.is_zero():
            raise OverflowError(
                message=(
                    "The tangent is too large for Decimal128 at this angle."
                ),
                function="tan()",
            )
        value = sine / cosine

    return (
        value^,
        (carried + UInt256(SERIES_SLACK)) * UInt256(QUOTIENT_SLACK),
    )


def cot(x: Decimal128) raises -> Decimal128:
    """Calculates the cotangent of an angle in radians.

    Args:
        x: The angle in radians.

    Returns:
        Its cotangent, correctly rounded.

    Raises:
        ZeroDivisionError: If the angle is a whole number of half turns,
            where the cotangent has no value.
        OverflowError: If the angle is so close to one that the cotangent
            leaves what `Decimal128` holds.
        Error: Propagated from the arithmetic.
    """
    if x.is_zero():
        raise ZeroDivisionError(
            message="The cotangent of zero has no value.",
            function="cot()",
        )
    return _ratio(x, wants_cotangent=True)


def sec(x: Decimal128) raises -> Decimal128:
    """Calculates the secant of an angle in radians.

    Args:
        x: The angle in radians.

    Returns:
        Its secant, correctly rounded.

    Raises:
        OverflowError: If the angle is close enough to a quarter turn that
            the secant leaves what `Decimal128` holds.
        Error: Propagated from the arithmetic.
    """
    if x.is_zero():
        return Decimal128.ONE()
    return _inverse_circular(x, is_sine=False)


def csc(x: Decimal128) raises -> Decimal128:
    """Calculates the cosecant of an angle in radians.

    Args:
        x: The angle in radians.

    Returns:
        Its cosecant, correctly rounded.

    Raises:
        ZeroDivisionError: If the angle is zero, where the cosecant has no
            value.
        OverflowError: If the angle is close enough to a half turn that the
            cosecant leaves what `Decimal128` holds.
        Error: Propagated from the arithmetic.
    """
    if x.is_zero():
        raise ZeroDivisionError(
            message="The cosecant of zero has no value.",
            function="csc()",
        )
    return _inverse_circular(x, is_sine=True)


def _ratio(x: Decimal128, wants_cotangent: Bool) raises -> Decimal128:
    """Returns the tangent or the cotangent.

    Args:
        x: The angle in radians.
        wants_cotangent: True for the cotangent.

    Returns:
        The value, correctly rounded.

    Raises:
        OverflowError: If the value leaves what `Decimal128` holds.
        Error: Propagated from the arithmetic.
    """
    var reduced = reduce(x)
    var narrow = _ratio_at[38](reduced, wants_cotangent)
    var decided = narrow[0].to_decimal_decided(narrow[1])
    if decided:
        return decided.value()

    var wide = _ratio_at[75](reduced, wants_cotangent)
    var settled = wide[0].to_decimal_decided(wide[1])
    if settled:
        return settled.value()
    return wide[0].to_decimal()


def _ratio_at[
    WIDTH: Int
](
    reduced: Tuple[Extended, Int, UInt256], wants_cotangent: Bool
) raises -> Tuple[WideValue[WIDTH], UInt256]:
    """Returns the tangent or cotangent of a reduced angle, with how far it
    may be off.

    Parameters:
        WIDTH: The width to run the series at.

    Args:
        reduced: The remainder, the quadrant, and what the reduction is
            trusted within.
        wants_cotangent: True for the cotangent.

    Returns:
        The value, and the units in the last place of its mantissa that the
        computation is trusted within.

    Raises:
        OverflowError: If the divisor is zero, which means the value has no
            place on the line.
        Error: Propagated from the arithmetic.
    """
    var r = reduced[0].to_width[WIDTH]()
    var sine = sine_series_at[WIDTH](r)
    var cosine = cosine_series_at[WIDTH](r)

    var carried = reduced[2]
    comptime if WIDTH < 75:
        carried = carried // decimal128_utility.power_of_10[DType.uint256](
            75 - WIDTH
        ) + UInt256(1)

    # A quarter turn on exchanges the two and flips the sign, which turns a
    # tangent into a cotangent and back.
    var quadrant = reduced[1]
    var upper = sine.copy()
    var lower = cosine.copy()
    var negative = False
    if wants_cotangent:
        upper = cosine.copy()
        lower = sine.copy()
    if quadrant == 1 or quadrant == 3:
        var swap = upper.copy()
        upper = lower^
        lower = swap^
        negative = True

    if lower.is_zero():
        raise OverflowError(
            message="The value is too large for Decimal128 at this angle.",
            function="tan()",
        )
    var value = upper / lower
    if negative:
        value = -value

    return (
        value^,
        (carried + UInt256(SERIES_SLACK)) * UInt256(QUOTIENT_SLACK),
    )


def _inverse_circular(x: Decimal128, is_sine: Bool) raises -> Decimal128:
    """Returns the cosecant or the secant.

    Args:
        x: The angle in radians.
        is_sine: True for the cosecant, which is one over the sine.

    Returns:
        The value, correctly rounded.

    Raises:
        OverflowError: If the value leaves what `Decimal128` holds.
        Error: Propagated from the arithmetic.
    """
    var reduced = reduce(x)
    var narrow = _inverse_circular_at[38](reduced, is_sine)
    var decided = narrow[0].to_decimal_decided(narrow[1])
    if decided:
        return decided.value()

    var wide = _inverse_circular_at[75](reduced, is_sine)
    var settled = wide[0].to_decimal_decided(wide[1])
    if settled:
        return settled.value()
    return wide[0].to_decimal()


def _inverse_circular_at[
    WIDTH: Int
](reduced: Tuple[Extended, Int, UInt256], is_sine: Bool) raises -> Tuple[
    WideValue[WIDTH], UInt256
]:
    """Returns one over the sine or the cosine of a reduced angle, with how
    far it may be off.

    Parameters:
        WIDTH: The width to run the series at.

    Args:
        reduced: The remainder, the quadrant, and what the reduction is
            trusted within.
        is_sine: True for the cosecant.

    Returns:
        The value, and the units in the last place of its mantissa that the
        computation is trusted within.

    Raises:
        OverflowError: If the sine or cosine is zero at this angle.
        Error: Propagated from the arithmetic.
    """
    var circular = _circular_at[WIDTH](reduced, is_sine)
    if circular[0].is_zero():
        raise OverflowError(
            message="The value is too large for Decimal128 at this angle.",
            function="csc()",
        )
    var value = WideValue[WIDTH].from_int(1) / circular[0]
    return (value^, circular[1] * UInt256(QUOTIENT_SLACK))
