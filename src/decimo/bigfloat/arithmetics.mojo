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


"""The four arithmetic operations on binary floats.

The sum of two floats is usually not a float, so the answer is the correctly
rounded one: the exact sum is decided to the destination's precision in a
single rounding, in each of the seven modes.

What makes this more than an aligned integer addition is that the alignment
can be wider than any machine will hold. Two values whose exponents are far
apart have an exact sum with a long run of zeros in the middle, and those
zeros are not worth storing: below the destination's last bit the smaller
operand can only say whether something is there, which is one bit of
information. So the two are added exactly while their leading bits are close
enough for the bits to matter, and otherwise the smaller one becomes the
larger one's sticky bit. The cut is drawn where the two agree, so it changes
no answer.

Cancellation is the same question from the other side. Two values whose
leading bits are two or more apart cannot cancel more than a single bit, so
the near case is the only one where the result can be far smaller than both
operands, and there the sum is taken over as many bits as the operands
themselves carry, which is the work a subtraction genuinely needs.

Every exponent here is handled by subtraction and never by addition. An
exponent sits anywhere in `Int`, so `exponent + precision` can overflow where
the difference of two exponents does not, and the one comparison that could
overflow is written to answer without doing so. Making room for guard bits
lowers an exponent, and that cannot leave the range either: the case that
does it is only reached when the exponent is already above the bottom by more
than the room it needs, which the code asserts and says why.

Multiplying and dividing are the two that can genuinely leave the range,
since they add and subtract whole exponents rather than adjusting one, and
there they refuse the answer rather than wrapping round to the other end of
it. That is the one place this type's unbounded exponent meets a bound, and
the bound is an `Int`.
"""

from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.comparison import compare_absolute
from decimo.bigfloat.rounding import round_to_precision
from decimo.bigint.bigint import BigInt
from decimo.errors import ValueError
from decimo.rounding_mode import RoundingMode


def _difference_at_most(left: Int, right: Int, bound: Int) -> Bool:
    """Whether `left - right` is at most `bound`, without overflowing.

    Args:
        left: The first operand.
        right: The second operand.
        bound: What the difference is compared against.

    Returns:
        True if `left - right <= bound` as mathematics, whether or not that
        difference fits in an `Int`.

    Notes:

    A difference too wide to hold has already answered the question: above
    `Int.MAX` it is above any bound, and below `Int.MIN` it is below any. The
    two guards are written as additions that cannot overflow, since the value
    added to `Int.MAX` is negative in both.
    """
    if left >= right:
        if right < 0 and left > Int.MAX + right:
            return False
        return left - right <= bound
    if left < 0 and right > Int.MAX + left:
        return True
    return left - right <= bound


def _exponent_sum(left: Int, right: Int) raises -> Int:
    """`left + right`, refusing the answer rather than wrapping it.

    Args:
        left: The first exponent.
        right: The second one.

    Returns:
        The sum.

    Raises:
        ValueError: If the sum is outside `Int`.

    Notes:

    The exponent is held in an `Int`, so the values this type reaches are the
    ones whose exponent an `Int` holds. A product of two values near the top
    of that range has an exponent above it, and saying so is better than
    wrapping round to the bottom and answering with a tiny number.
    """
    if right > 0 and left > Int.MAX - right:
        raise ValueError(
            message="The exponent of the product is above what an Int holds.",
            function="_exponent_sum()",
        )
    if right < 0 and left < Int.MIN - right:
        raise ValueError(
            message="The exponent of the product is below what an Int holds.",
            function="_exponent_sum()",
        )
    return left + right


def _exponent_difference(left: Int, right: Int) raises -> Int:
    """`left - right`, refusing the answer rather than wrapping it.

    Args:
        left: The exponent subtracted from.
        right: What is taken away.

    Returns:
        The difference.

    Raises:
        ValueError: If the difference is outside `Int`.
    """
    if right < 0 and left > Int.MAX + right:
        raise ValueError(
            message="The exponent of the quotient is above what an Int holds.",
            function="_exponent_difference()",
        )
    if right > 0 and left < Int.MIN + right:
        raise ValueError(
            message="The exponent of the quotient is below what an Int holds.",
            function="_exponent_difference()",
        )
    return left - right


def _fitted(
    magnitude: BigInt,
    exponent: Int,
    precision: Int,
    negative: Bool,
    rounding_mode: RoundingMode,
    inexact_below: Bool = False,
) raises -> BigFloat:
    """Rounds a magnitude and exponent into a float.

    Args:
        magnitude: The significand, which must not be negative.
        exponent: The power of two it is scaled by.
        precision: How many bits the result keeps.
        negative: The sign of the result.
        rounding_mode: Which way to round.
        inexact_below: Whether something non-zero sits below the magnitude.

    Returns:
        The value, normalized to `precision` bits.

    Raises:
        Error: Propagated from the rounding.
    """
    var fitted = round_to_precision(
        magnitude,
        exponent,
        precision,
        negative,
        rounding_mode,
        inexact_below,
    )
    return BigFloat(
        significand=fitted[0],
        exponent=fitted[1],
        precision=precision,
        sign=negative,
    )


def _cancelled_zero(
    precision: Int, rounding_mode: RoundingMode
) raises -> BigFloat:
    """The zero that two values cancelling exactly leave.

    Args:
        precision: The precision the result carries.
        rounding_mode: The mode, which decides the sign.

    Returns:
        A positive zero, except toward negative infinity where a sum that
        vanished is approached from above and the answer is `-0`. This is the
        rule IEEE 754 gives for a sum that cancels, and the same one that
        makes `x - x` keep the sign of the direction it was rounded in.

    Raises:
        Error: Propagated from the construction.
    """
    return BigFloat.zero(precision, rounding_mode == RoundingMode.ROUND_FLOOR)


def _combine(
    big: BigFloat,
    small: BigFloat,
    subtracting: Bool,
    precision: Int,
    rounding_mode: RoundingMode,
) raises -> BigFloat:
    """Adds two finite non-zero values, the larger magnitude first.

    Args:
        big: The operand of larger or equal magnitude.
        small: The other one.
        subtracting: Whether the signs differ, so that the small magnitude
            comes off the big one rather than onto it.
        precision: How many bits the result keeps.
        rounding_mode: Which way to round.

    Returns:
        The correctly rounded sum, whose sign is `big`'s unless the two
        cancelled exactly.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The width worked in is `precision + 2` bits, or `big`'s own precision when
    that is wider, since there is no sense in narrowing an operand before
    rounding it. `small` is below the last bit of `big` at that width exactly
    when

        small.exponent - big.exponent <= big.precision - small.precision
                                          - width

    which is the far case: what `small` contributes is then a sticky bit, and
    for a subtraction one unit off the last bit as well, because a positive
    amount taken from a multiple of that unit lands between it and the one
    below.
    """
    var width = precision + 2
    if big.precision > width:
        width = big.precision
    var stretch = width - big.precision

    if _difference_at_most(
        small.exponent,
        big.exponent,
        big.precision - small.precision - width,
    ):
        var widened = big.significand << stretch
        if subtracting:
            widened = widened - BigInt.one()
        # Lowering the exponent by `stretch` cannot leave the range. The
        # condition just tested rearranges to
        #
        #     big.exponent >= small.exponent + small.precision + stretch
        #
        # and `small.exponent` is at least `Int.MIN` with a precision of at
        # least one bit, so `big.exponent` is above `Int.MIN + stretch`.
        debug_assert(
            big.exponent > Int.MIN + stretch,
            "the far case lowered an exponent below Int.MIN",
        )
        return _fitted(
            widened,
            big.exponent - stretch,
            precision,
            big.sign,
            rounding_mode,
            True,
        )

    # The near case. Both operands are brought down to the lower of the two
    # exponents, where the sum is exact: the shift is bounded by the operands'
    # own precisions, because the far case took every pair whose exponents are
    # further apart than that.
    var exponent = (
        big.exponent if big.exponent < small.exponent else small.exponent
    )
    var aligned_big = big.significand << (big.exponent - exponent)
    var aligned_small = small.significand << (small.exponent - exponent)

    if not subtracting:
        return _fitted(
            aligned_big + aligned_small,
            exponent,
            precision,
            big.sign,
            rounding_mode,
        )

    var total = aligned_big - aligned_small
    if total.is_zero():
        return _cancelled_zero(precision, rounding_mode)
    return _fitted(total, exponent, precision, big.sign, rounding_mode)


def add(
    x1: BigFloat,
    x2: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The sum of two values, correctly rounded.

    Args:
        x1: The first operand.
        x2: The second operand.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest the exact sum, with the mode
        settling which side when the sum sits between two.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    The special values follow IEEE 754. A NaN anywhere gives a NaN. Two
    infinities of the same sign give that infinity and of opposite signs a
    NaN, since their difference is no value at all. An infinity and a finite
    value give the infinity.

    A zero added to a value gives that value, rounded to `precision`, which
    is not always the value itself: the destination can be narrower than the
    operand. Two zeros of the same sign keep it, and of opposite signs give
    what an exact cancellation gives.
    """
    if x1.is_nan() or x2.is_nan():
        return BigFloat.nan(precision)

    if x1.is_infinite() or x2.is_infinite():
        if x1.is_infinite() and x2.is_infinite():
            if x1.sign != x2.sign:
                return BigFloat.nan(precision)
            return BigFloat.infinity(precision, x1.sign)
        if x1.is_infinite():
            return BigFloat.infinity(precision, x1.sign)
        return BigFloat.infinity(precision, x2.sign)

    if x1.is_zero() and x2.is_zero():
        if x1.sign == x2.sign:
            return BigFloat.zero(precision, x1.sign)
        return _cancelled_zero(precision, rounding_mode)
    if x1.is_zero():
        return _fitted(
            x2.significand, x2.exponent, precision, x2.sign, rounding_mode
        )
    if x2.is_zero():
        return _fitted(
            x1.significand, x1.exponent, precision, x1.sign, rounding_mode
        )

    var subtracting = x1.sign != x2.sign
    if compare_absolute(x1, x2) >= 0:
        return _combine(x1, x2, subtracting, precision, rounding_mode)
    return _combine(x2, x1, subtracting, precision, rounding_mode)


def subtract(
    x1: BigFloat,
    x2: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The difference of two values, correctly rounded.

    Args:
        x1: The value subtracted from.
        x2: The value taken away.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `x1 - x2`.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    This is `x1 + (-x2)` and nothing else: negating is exact, and the rounding
    of a sum depends on its value and sign alone, so the two cannot differ.
    That also carries the special cases across -- `inf - inf` is a NaN, and
    `0 - 0` is the positive zero that a cancellation leaves -- without
    restating any of them.
    """
    return add(x1, -x2, precision, rounding_mode)


def multiply(
    x1: BigFloat,
    x2: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The product of two values, correctly rounded.

    Args:
        x1: The first operand.
        x2: The second operand.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest the exact product.

    Raises:
        ValueError: If `precision` is not positive, or the product's exponent
            is outside `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    This is the easy one of the four. The product of two significands is an
    integer, so it is computed exactly and rounded once, and the exponents
    simply add. Nothing has to decide how much of an operand matters, which
    is what makes addition hard.

    The special values follow IEEE 754. An infinity times a zero is a NaN,
    since the two pull the product in opposite directions and neither wins.
    Everything else keeps the sign the two operands give it, including the
    zeros: `-0` times a positive value is `-0`.
    """
    var negative = x1.sign != x2.sign

    if x1.is_nan() or x2.is_nan():
        return BigFloat.nan(precision)

    if x1.is_infinite() or x2.is_infinite():
        if x1.is_zero() or x2.is_zero():
            return BigFloat.nan(precision)
        return BigFloat.infinity(precision, negative)

    if x1.is_zero() or x2.is_zero():
        return BigFloat.zero(precision, negative)

    return _fitted(
        x1.significand * x2.significand,
        _exponent_sum(x1.exponent, x2.exponent),
        precision,
        negative,
        rounding_mode,
    )


def divide(
    x1: BigFloat,
    x2: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The quotient of two values, correctly rounded.

    Args:
        x1: The value divided.
        x2: The value divided by.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `x1 / x2`.

    Raises:
        ValueError: If `precision` is not positive, or the quotient's
            exponent is outside `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    A quotient is almost never exact, so the division is taken with more bits
    than are kept and the division's own remainder is the sticky bit. That is
    the same shape the conversion from decimal has, and for the same reason:
    a quotient that stops just short of a half cannot be told from one that
    sits exactly on it without knowing whether anything is left below.

    The shift is chosen so that the quotient has a few bits past the
    precision and then checked, because a numerator much smaller than the
    denominator can leave it short. If it does, the shift grows and the
    division is taken again.

    Dividing by zero gives an infinity rather than raising, which is what a
    float does: IEEE 754 calls it an exception and flags it, and this type
    has no flags to raise, so the value it specifies is the whole of the
    answer. Zero over zero and an infinity over an infinity are NaNs, having
    no value either way, and a finite value over an infinity is a signed zero.
    """
    var negative = x1.sign != x2.sign

    if x1.is_nan() or x2.is_nan():
        return BigFloat.nan(precision)

    if x1.is_infinite():
        if x2.is_infinite():
            return BigFloat.nan(precision)
        return BigFloat.infinity(precision, negative)
    if x2.is_infinite():
        return BigFloat.zero(precision, negative)

    if x2.is_zero():
        if x1.is_zero():
            return BigFloat.nan(precision)
        return BigFloat.infinity(precision, negative)
    if x1.is_zero():
        return BigFloat.zero(precision, negative)

    # The quotient of the significands has about `p1 - p2 + shift` bits, so
    # this aims a few past the precision; the loop covers the rest.
    var shift = precision + 3 + x2.precision - x1.precision
    if shift < 0:
        shift = 0
    while True:
        var scaled = x1.significand << shift
        var quotient = scaled.truncate_divide(x2.significand)
        if quotient.bit_length() > precision:
            var remainder = scaled - quotient * x2.significand
            return _fitted(
                quotient,
                _exponent_difference(
                    _exponent_difference(x1.exponent, x2.exponent), shift
                ),
                precision,
                negative,
                rounding_mode,
                not remainder.is_zero(),
            )
        shift += precision + 64
