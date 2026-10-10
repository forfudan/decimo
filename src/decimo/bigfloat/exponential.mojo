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


"""The square root, the exponentials, the logarithms, and the loop that
decides a rounding.

A square root is algebraic, so unlike the transcendental functions it needs
no loop that computes more digits until the answer settles: the integer
square root of a scaled significand is exact, and what it leaves behind says
whether the root was. That remainder is the sticky bit, and one rounding
finishes the job in each of the seven modes.

Halving an exponent is the whole of the scaling. An odd exponent cannot be
halved, so the significand takes a factor of two and the exponent gives one
up, which changes no value and leaves an exponent that can be. The root then
sits at half that exponent, less the bits the significand was scaled up by to
make room for the precision asked for.

`exp` and `ln` are the two the series are written for. The other bases --
`exp2`, `exp10`, `log2`, `log10` and `log` -- are those two with the logarithm
of the base multiplied in or divided out, and `expm1` and `log1p` are the two
that compute a difference from one directly rather than forming it, so that a
small argument keeps its bits. None of that is the hard part.

The hard part is that the other bases have arguments whose answers a float
holds exactly, where `exp` and `ln` have none: `log2(8)` is three. Ziv's loop
cannot settle on such an answer, however far it widens, so each of those
arguments is recognized first and answered from integer arithmetic. Which
arguments those are has an exact answer in every case, and each function's
docstring states it.
"""

from std.bit import bit_width

import decimo.bigfloat.arithmetics as bigfloat_arithmetics
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.comparison import compare_absolute
from decimo.bigfloat.constants import ln10, ln2
from decimo.bigfloat.rounding import (
    MAX_PRECISION,
    _lowered,
    _raised,
    checked_precision,
    fixed_point_scale,
    from_fixed_point,
    guard_bits,
    leading_bit_position,
    rounded_beside,
    to_fixed_point,
    working_width,
)
from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import test_bit, trailing_zeros
from decimo.bigint.exponential import root as bigint_root, sqrt_rem
from decimo.errors import OverflowError, ValueError
from decimo.rounding_mode import RoundingMode


def sqrt(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The square root of a value, correctly rounded.

    Args:
        x: The value to take the root of.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest the exact square root.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    A negative value has no square root among the reals, and the answer is a
    NaN rather than a refusal. That is what IEEE 754 asks for and what `MPF`
    does, and this type carries a NaN for exactly this kind of question.
    `-0` is the exception: its root is `-0`, since the sign survives a root
    that has nothing to take.

    The scaling is a shift of twice the bits wanted, because a root halves
    them: shifting the significand up by `2k` shifts the root up by `k`. The
    shift is chosen so the root comes out a couple of bits past the precision
    and then checked, since a narrow significand can leave it short.
    """
    _ = checked_precision(precision, "sqrt()")

    if x.is_nan():
        return BigFloat.nan(precision)
    if x.sign:
        if x.is_zero():
            return BigFloat.zero(precision, True)
        return BigFloat.nan(precision)
    if x.is_zero():
        return BigFloat.zero(precision, False)
    if x.is_infinite():
        return BigFloat.infinity(precision, False)

    # An even exponent is what can be halved. Taking a factor of two out of
    # the exponent and into the significand is exact and changes no value,
    # and an odd exponent is above `Int.MIN`, which is even, so the step down
    # stays in range.
    var magnitude = x.significand.copy()
    var exponent = x.exponent
    if exponent & 1 != 0:
        magnitude = magnitude << 1
        exponent -= 1
    var half = exponent >> 1

    # The root of a `b`-bit value has about `b / 2` bits, so this aims a
    # couple past the precision.
    var scale = precision + 2 - (magnitude.bit_length() + 1) // 2
    if scale < 0:
        scale = 0
    while True:
        var parts = sqrt_rem(magnitude << (2 * scale))
        if parts[0].bit_length() > precision:
            # `half - scale` cannot leave the range: halving an exponent puts
            # it within `Int.MAX / 2` of zero, and `scale` is a precision.
            debug_assert(
                half - scale < half + 1,
                "halving an exponent did not keep it in range",
            )
            return BigFloat.from_rounded_parts(
                parts[0],
                half - scale,
                precision,
                False,
                rounding_mode,
                not parts[1].is_zero(),
            )
        scale += precision + 32


comptime _ROOT_SLACK = 6
"""Units in the last place the logarithm's route to a root may be off by.

The logarithm, the division by the degree and the exponential each cost a
unit or two of the working width.
"""


def _root_by_logarithm(
    x: BigFloat, degree: Int, precision: Int, rounding_mode: RoundingMode
) raises -> BigFloat:
    """The `degree`-th root of a value, through the logarithm.

    Args:
        x: The value, finite and not nought. A negative one needs an odd
            degree, which the caller has checked.
        degree: Which root to take, positive.
        precision: The bits the answer keeps.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest the root.

    Raises:
        OverflowError: If the answer's exponent would not fit an `Int`.
        Error: If the rounding cannot be decided, or propagated from the
            arithmetic.

    Notes:

    The exponent is split off first, and that is what makes this work at all.
    `x` is `s * 2^(q * degree + r)` with `r` below the degree, so the root is
    the root of `s * 2^r` times `2^q`, and the second factor is exact. Handed
    the whole value instead, the logarithm of something near the top of the
    exponent range divided by a modest degree would still be enormous and the
    exponential would refuse it -- while the answer is an ordinary number.

    Nothing is lengthened. The split only moves an exponent, so unlike the
    integer root this route costs the same whatever the degree is, which is
    why the caller sends the large degrees here.
    """
    var remainder = x.exponent % degree
    var quotient = x.exponent // degree
    var inner = BigFloat(
        significand=x.significand,
        exponent=remainder,
        precision=x.precision,
        sign=False,
    )

    var width = precision + _ZIV_START
    for _ in range(_ZIV_LIMIT):
        var work = working_width(width)
        var scaled = bigfloat_arithmetics.divide(
            ln_at_width(inner, work), BigFloat.from_int(degree, work), work
        )
        var value = exp_at_width(scaled, work)
        var wide = BigFloat.from_rounded_parts(
            value.significand, value.exponent, width, x.sign
        )
        var settled = _settled(
            wide, width, _ROOT_SLACK, precision, rounding_mode
        )
        if settled:
            var found = settled.take()
            # The exponent that was split off goes back on, which is exact and
            # is the one place an answer outside the range can show up.
            var exponent = _raised(
                found.exponent, quotient
            ) if quotient >= 0 else _lowered(found.exponent, -quotient)
            return BigFloat(
                significand=found.significand,
                exponent=exponent,
                precision=found.precision,
                sign=found.sign,
            )
        width += width - precision
    raise Error(
        "the rounding of this root could not be decided; the logarithm is"
        " further from the true value than its stated bound allows"
    )


def root(
    x: BigFloat,
    degree: Int,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The `degree`-th root of a value, correctly rounded.

    Args:
        x: The value to take the root of.
        degree: Which root to take. Must be positive.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `x ** (1 / degree)`.

    Raises:
        ValueError: If `precision` is not positive, or `degree` is not.
        OverflowError: If the working value would be longer than a precision
            may be, which takes a degree in the billions.
        Error: Propagated from the arithmetic.

    Notes:

    A root is algebraic, so unlike the transcendental functions it needs no
    loop that computes more digits until the answer settles. The integer
    `degree`-th root of a scaled significand brackets the true root between
    two consecutive integers, and whether it landed on the lower one exactly
    is the sticky bit. One rounding then finishes the job in each of the
    seven modes -- and an exact root comes out exact, which is what makes
    `root(8, 3)` two rather than a value near it.

    Dividing the exponent is the whole of the scaling. `x` is
    `s * 2^(q * degree + r)` with `r` below the degree, so the factor of
    `2^r` moves into the significand and the root sits at `2^q`, less the
    bits the significand was scaled up by to make room for the precision
    asked for. The exponent is never multiplied back out, which is what keeps
    a value near the bottom of the range from leaving it.

    A negative value has a real root only at an odd degree, and gets a NaN at
    an even one, which is what `sqrt` does for the same reason.
    """
    _ = checked_precision(precision, "root()")
    if degree <= 0:
        raise ValueError(
            message="The degree of a root must be positive.",
            function="root()",
        )
    if degree == 1:
        if not x.is_finite() or x.is_zero():
            return x.copy()
        return BigFloat.from_rounded_parts(
            x.significand, x.exponent, precision, x.sign, rounding_mode
        )
    if degree == 2:
        return sqrt(x, precision, rounding_mode)

    var odd = degree % 2 != 0
    if x.is_nan():
        return BigFloat.nan(precision)
    if x.is_zero():
        # The root of a nought is a nought, and keeps its sign at an odd
        # degree because an odd power of a negative nought is one.
        return BigFloat.zero(precision, x.sign and odd)
    if x.is_infinite():
        if x.sign and not odd:
            return BigFloat.nan(precision)
        return BigFloat.infinity(precision, x.sign)
    if x.sign and not odd:
        return BigFloat.nan(precision)

    # The integer root is the right method only while the degree is small.
    # It needs the value lengthened to about `degree` times the precision, so
    # a large degree asks for a number nothing can hold -- and it buys
    # nothing there either: an exact root above one needs a significand of at
    # least `degree` bits, so no significand of this precision has one. The
    # exception is a power of two, whose root is a power of two and takes no
    # work at all.
    if degree > precision + 2:
        var zeros = trailing_zeros(x.significand)
        if (x.significand >> zeros).is_one():
            var position = BigInt(x.exponent) + BigInt(zeros)
            var step = BigInt(degree)
            if (position % step).is_zero():
                return BigFloat.from_rounded_parts(
                    BigInt.one(),
                    (position // step).to_int(),
                    precision,
                    x.sign,
                    rounding_mode,
                )
        return _root_by_logarithm(x, degree, precision, rounding_mode)

    # `exponent` is `quotient * degree + remainder` with the remainder below
    # the degree, and neither product is ever formed.
    var remainder = x.exponent % degree
    var quotient = x.exponent // degree
    var magnitude = x.significand << remainder

    # The root of a `b`-bit value has about `b / degree` bits, so this aims a
    # couple of bits past the precision.
    var scale = precision + 2 - (magnitude.bit_length() + degree - 1) // degree
    if scale < 0:
        scale = 0
    while True:
        if scale > MAX_PRECISION // degree:
            raise OverflowError(
                message=(
                    "Taking this root needs a longer value than a precision"
                    " may be."
                ),
                function="root()",
            )
        var scaled = magnitude << (degree * scale)
        var candidate = bigint_root(scaled, degree)
        if candidate.bit_length() > precision:
            debug_assert(
                quotient - scale < quotient + 1,
                "dividing an exponent did not keep it in range",
            )
            return BigFloat.from_rounded_parts(
                candidate,
                quotient - scale,
                precision,
                x.sign,
                rounding_mode,
                candidate**degree != scaled,
            )
        scale += precision + 32


def hypot(
    x: BigFloat,
    y: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The hypotenuse of two legs, correctly rounded.

    Args:
        x: One leg.
        y: The other leg.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `sqrt(x*x + y*y)`.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If the answer's exponent would not fit an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    `x*x + y*y` is formed exactly, in integers, and never as two roundings
    that could each be wrong. Both squares are integers -- a significand is
    one -- so the sum over their common exponent is an integer too, and the
    integer square root of it brackets the answer between two consecutive
    values with its remainder as the sticky bit. One rounding then finishes
    the job in each of the seven modes, as it does for `sqrt`, and an answer
    that is exact comes out exact: `hypot(3, 4)` is five, which a pair of
    rounded squares and a rounded root could not promise.

    Scaling is done around the smaller exponent rather than by squaring
    either of them. A square's exponent is twice the value's and need not fit
    an `Int` at all, while the hypotenuse's is within a bit of the larger
    leg's, so the work is done relative to the common exponent and that
    exponent is added back at the end, where the only overflow that can
    happen is one the answer really has.

    A leg far below the other contributes nothing but a sticky bit. The
    answer is then the larger leg moved by a hair, which is what
    `rounded_beside()` is for: once the ratio's square is below the last
    place, no width would ever show where the sum sits, and the gap in
    leading bits says when that is.

    The special values follow IEEE 754's `hypot`, which answers an infinity
    before it looks at the other leg: `hypot(inf, NaN)` is an infinity,
    because no value of the second leg could make the first one finite.
    """
    _ = checked_precision(precision, "hypot()")

    if x.is_infinite() or y.is_infinite():
        return BigFloat.infinity(precision, False)
    if x.is_nan() or y.is_nan():
        return BigFloat.nan(precision)
    if x.is_zero() and y.is_zero():
        return BigFloat.zero(precision, False)
    if x.is_zero():
        return BigFloat.from_rounded_parts(
            y.significand, y.exponent, precision, False, rounding_mode
        )
    if y.is_zero():
        return BigFloat.from_rounded_parts(
            x.significand, x.exponent, precision, False, rounding_mode
        )

    # The larger leg decides the answer's size, and the smaller one may not
    # reach it at all.
    var larger = x.copy()
    var smaller = y.copy()
    if compare_absolute(x, y) < 0:
        larger = y.copy()
        smaller = x.copy()

    var gap = leading_bit_position(larger) - leading_bit_position(smaller)
    if gap > BigInt(precision + 4):
        # `larger * sqrt(1 + ratio^2)` with `ratio^2` below the last place:
        # above the larger leg, and by less than a guard unit of it.
        return rounded_beside(
            BigFloat(
                significand=larger.significand,
                exponent=larger.exponent,
                precision=larger.precision,
                sign=False,
            ),
            precision,
            rounding_mode,
            False,
        )

    # Both squares over the lower of the two exponents, which is exact.
    var base = larger.exponent
    if smaller.exponent < base:
        base = smaller.exponent
    var left = larger.significand << (larger.exponent - base)
    var right = smaller.significand << (smaller.exponent - base)
    var total = left * left + right * right

    # The root of a `b`-bit value has about `b / 2` bits, so this aims a
    # couple past the precision, exactly as `sqrt` does.
    var scale = precision + 2 - (total.bit_length() + 1) // 2
    if scale < 0:
        scale = 0
    while True:
        var parts = sqrt_rem(total << (2 * scale))
        if parts[0].bit_length() > precision:
            var relative = BigFloat.from_rounded_parts(
                parts[0],
                -scale,
                precision,
                False,
                rounding_mode,
                not parts[1].is_zero(),
            )
            if relative.is_zero():
                return relative^
            # The common exponent goes back on, which is exact, and is the
            # one place an answer outside the range can show up.
            var exponent = _raised(
                relative.exponent, base
            ) if base >= 0 else _lowered(relative.exponent, -base)
            return BigFloat(
                significand=relative.significand,
                exponent=exponent,
                precision=relative.precision,
                sign=False,
            )
        scale += precision + 32


def cbrt(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The cube root of a value, correctly rounded.

    Args:
        x: The value to take the root of.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest the cube root of `x`.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from `root()`.

    Notes:

    A cube root takes a negative value, unlike a square root, because an odd
    power keeps its sign: the cube root of `-8` is `-2`.
    """
    return root(x, 3, precision, rounding_mode)


# ===----------------------------------------------------------------------=== #
# Deciding a rounding
# ===----------------------------------------------------------------------=== #
#
# A square root is exact and needs none of this. A transcendental value is
# not: it can only be computed to some width with some error, and rounding
# what comes back is a guess unless the error is accounted for. The way out is
# Ziv's: compute wider than asked, ask whether every value the error allows
# rounds the same way, and widen again if they do not.


comptime _ZIV_START = 12
"""Bits asked for beyond the caller's precision on the first attempt.

With a kernel good to two units in the last place of the width it is given,
the interval to check spans four of them, so the check fails only when a
rounding boundary lies within `4 * 2^-start` of the answer -- about one call
in a thousand here. Twelve bits of extra work is nothing next to a retry, and
a retry is what fewer bits would buy more often.
"""

comptime _ZIV_LIMIT = 8
"""How many times the width may grow before giving up.

The loop always ends long before this. It is here so that a kernel whose
error is larger than it claims ends in an error rather than in a hang.
"""


def _settled(
    wide: BigFloat,
    width: Int,
    slack: Int,
    precision: Int,
    rounding_mode: RoundingMode,
) raises -> Optional[BigFloat]:
    """The answer, if every value the kernel's error allows rounds to it.

    Args:
        wide: What the kernel returned, of `width` bits.
        width: The number of bits it was asked for.
        slack: Units in the last place of `width` the kernel may be off by.
        precision: The number of bits wanted.
        rounding_mode: How to round.

    Returns:
        The rounded value when both ends of `wide +/- slack` round to it, and
        nothing when the interval straddles a boundary, where the answer is
        not yet decided.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The two ends are magnitudes, and rounding is monotonic in the magnitude
    for a fixed sign, so agreeing at the ends means agreeing throughout. They
    are built in one bit more than `width` because adding the slack can carry
    and taking it away can borrow, and neither is to be rounded here.
    """
    var reach = BigInt(slack)
    var low = BigFloat.from_rounded_parts(
        wide.significand - reach, wide.exponent, width + 1, wide.sign
    )
    var high = BigFloat.from_rounded_parts(
        wide.significand + reach, wide.exponent, width + 1, wide.sign
    )
    var low_rounded = BigFloat.from_rounded_parts(
        low.significand, low.exponent, precision, low.sign, rounding_mode
    )
    var high_rounded = BigFloat.from_rounded_parts(
        high.significand, high.exponent, precision, high.sign, rounding_mode
    )
    if (
        low_rounded.significand == high_rounded.significand
        and low_rounded.exponent == high_rounded.exponent
    ):
        return low_rounded^
    return None


def round_by_deciding[
    kernel: def(Int) thin raises -> BigFloat, slack: Int
](precision: Int, rounding_mode: RoundingMode) raises -> BigFloat:
    """`kernel`'s value rounded to `precision` bits, decided and not assumed.

    Parameters:
        kernel: What to evaluate. It takes a width in bits and returns a
            value of that many bits, within `slack` units of the last place
            of the true one.
        slack: The bound the kernel keeps to.

    Args:
        precision: The number of bits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: If the kernel raises, or if the width grows `_ZIV_LIMIT` times
            without the rounding settling, which would mean the kernel is
            further off than `slack` allows.
    """
    _ = checked_precision(precision, "round_by_deciding()")
    var width = precision + _ZIV_START
    for _ in range(_ZIV_LIMIT):
        var settled = _settled(
            kernel(width), width, slack, precision, rounding_mode
        )
        if settled:
            return settled.take()
        width += width - precision
    raise Error(
        "the rounding of this value could not be decided; the kernel is"
        " further from the true value than its stated bound allows"
    )


# ===----------------------------------------------------------------------=== #
# The exponential and the logarithm
# ===----------------------------------------------------------------------=== #


comptime _EXP_SLACK = 2
"""Units in the last place `exp_at_width` may be off by.

Every step of the series is one correctly rounded multiply and one correctly
rounded divide, so a term is off by a couple of units of the working width,
and the working width carries `bit_width(terms) + 8` bits beyond what the
kernel returns.
"""

comptime _LN_SLACK = 2
"""Units in the last place `ln_at_width` may be off by, for the same reasons."""


def _truncated_to_int(value: BigFloat, function: String) raises -> Int:
    """The integer part of a finite value, toward zero.

    Args:
        value: The value.
        function: The caller, for the message if it does not fit.

    Returns:
        The integer part, signed.

    Raises:
        OverflowError: If the integer part does not fit in an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    The sign goes on before the conversion rather than after, so that the
    bound checked is the signed one: `Int.MIN` is a magnitude of `2^63` and
    fits, while `2^63` positive does not. `BigInt.to_int()` draws that line
    exactly, so there is no second check here to draw it less well -- an
    earlier version compared bit lengths and refused every 63-bit magnitude,
    which rejected answers that were perfectly representable.

    The leading bit's position is looked at before the shift, though, and not
    to draw the line: it is to keep the shift from being attempted at all.
    Widening a significand by an exponent near the top of the range asks for
    an integer of some exabits, and that does not fail by raising -- the
    allocator returns nothing and the process stops, where no caller can
    catch it. A value whose leading bit is past the first hundred bits has no
    integer part that fits, so it is refused without being formed.
    """
    if value.is_zero():
        return 0
    if leading_bit_position(value) > BigInt(128):
        raise OverflowError(
            message=(
                "The integer part of this value does not fit in an Int, so"
                " the answer's exponent would not either."
            ),
            function=function,
        )
    var magnitude = value.significand.copy()
    if value.exponent >= 0:
        magnitude = magnitude << value.exponent
    else:
        magnitude = magnitude >> -value.exponent
    if value.sign:
        magnitude = -magnitude
    try:
        return magnitude.to_int()
    except:
        raise OverflowError(
            message=(
                "The integer part of this value does not fit in an Int, so"
                " the answer's exponent would not either."
            ),
            function=function,
        )


def expm1_series_at_width(x: BigFloat, width: Int) raises -> BigFloat:
    """`exp(x) - 1` for a small `x`, as a sum of its terms.

    Args:
        x: The argument, whose magnitude should be below one for the series
            to be worth using.
        width: The bits to work in.

    Returns:
        The sum, within a couple of units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The series is `x + x^2/2! + x^3/3! + ...`, each term the one before it
    times `x` over the next integer. It is `exp(x) - 1` and not `exp(x)`
    because the leading one would swamp a small `x`: added here, a term below
    the width's last place would vanish, while `add()` on the way out turns
    it into the sticky bit it is.

    The sum is taken in fixed-point integers, a dozen bits below the last
    place the caller asked for. Each step truncates twice, by a unit of that
    scale each time, and there are fewer steps than there are bits in the
    scale, so what the whole sum loses stays well under the last place.

    Terms are kept as magnitudes and the sign is applied as they are added,
    which for a negative `x` alternates: `x^n` is negative exactly when `n`
    is odd. Keeping them positive keeps every division a truncation toward
    nought, so the error has one direction per term rather than two.
    """
    if x.is_zero():
        return BigFloat.zero(width, x.sign)
    var scale = fixed_point_scale(x, width)
    var total = _expm1_in_fixed_point(to_fixed_point(x, scale), x.sign, scale)
    return from_fixed_point(abs(total), scale, width, total.sign)


def _expm1_in_fixed_point(
    magnitude: BigInt, negative: Bool, scale: Int
) raises -> BigInt:
    """`exp(x) - 1` for `x = (-1)^negative * magnitude * 2^-scale`.

    Args:
        magnitude: The argument's magnitude, scaled by `2^scale`.
        negative: The argument's sign.
        scale: The power of two the argument is scaled by.

    Returns:
        The sum, scaled by the same power of two, signed, and within as many
        units of the true value as the series took terms.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var total = BigInt.zero()
    var term = magnitude.copy()
    var index = 1
    while True:
        if negative and index % 2 == 1:
            total -= term
        else:
            total += term
        term = ((term * magnitude) >> scale).truncate_divide(BigInt(index + 1))
        if term.is_zero():
            return total^
        index += 1


def _halvings(scale: Int) -> Int:
    """How many times to halve an argument before summing its series.

    Args:
        scale: The bits the sum is taken to. Must not be negative.

    Returns:
        The integer square root of `scale`, which is where the two costs
        balance.

    Notes:

    Halving the argument `m` times costs `m` squarings on the way back, and
    buys a factor of `2^m` in every term, so the series needs about `scale/m`
    of them instead of `scale`. The two together are smallest at
    `m = sqrt(scale)`, which turns a cost linear in the precision into one
    that goes as its square root.

    The root is taken in `Int` by Newton's method rather than through
    `sqrt_rem()`, because every call makes this choice and a `BigInt` root of
    a number that fits a machine word costs more than the whole exponential
    does at 53 bits.
    """
    if scale < 2:
        return 0
    # `2^ceil(b/2)` is at or above the root of any value of `b` bits, which
    # is what Newton's method needs to descend to the floor of it.
    var root = 1 << ((Int(bit_width(UInt(scale))) + 1) // 2)
    while True:
        var lowered = (root + scale // root) // 2
        if lowered >= root:
            return root
        root = lowered


def _exponential_of_small(x: BigFloat, width: Int) raises -> BigFloat:
    """`exp(x) - 1` for an `x` below one, by halving, summing and squaring.

    Args:
        x: The argument, finite, not nought, and below one in magnitude.
        width: The bits the answer keeps.

    Returns:
        `exp(x) - 1`, within a couple of units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `exp(x)` is `exp(x / 2^m)` squared `m` times, and the halving is exact in
    a binary float. The series on the halved argument converges `m` bits a
    term quicker, and `m` squarings put the answer back.

    The squaring is done on `exp(y) - 1` rather than on `exp(y)`, by
    `u -> 2u + u^2`, for the same reason the series computes a difference
    from one: a `u` of `2^-m` added to one would lose its last `m` bits
    before the first squaring ever happened. Each squaring doubles the
    relative error, so `m` of them cost `m` bits, and the fixed point carries
    them.
    """
    var halvings = _halvings(width)
    var scale = fixed_point_scale(x, width + halvings + 2)
    var total = _expm1_in_fixed_point(
        to_fixed_point(x, scale) >> halvings, x.sign, scale
    )
    for _ in range(halvings):
        total = (total << 1) + ((total * total) >> scale)
    return from_fixed_point(abs(total), scale, width, total.sign)


def atanh_at_width(x: BigFloat, width: Int) raises -> BigFloat:
    """`atanh(x)` for `|x| < 1/2`, as a sum of its terms.

    Args:
        x: The argument.
        width: The bits to work in.

    Returns:
        The sum, within a couple of units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The series is `x + x^3/3 + x^5/5 + ...`, summed in fixed-point integers
    at a scale taken from `x`. The running power of `x^2` is kept apart from
    the division by the odd number, as in the constants, so that the two
    errors do not compound.

    Every term has the sign of `x`, odd powers being what they are, so the
    magnitudes add and the sign goes on at the end.
    """
    if x.is_zero():
        return BigFloat.zero(width, x.sign)
    var scale = fixed_point_scale(x, width)
    var magnitude = to_fixed_point(x, scale)
    var square = (magnitude * magnitude) >> scale

    var total = magnitude.copy()
    var power = magnitude.copy()
    var index = 3
    while True:
        power = (power * square) >> scale
        var term = power.truncate_divide(BigInt(index))
        if term.is_zero():
            return from_fixed_point(total, scale, width, x.sign)
        total += term
        index += 2


def round_by_deciding_at[
    kernel: def(BigFloat, Int) thin raises -> BigFloat, slack: Int
](x: BigFloat, precision: Int, rounding_mode: RoundingMode) raises -> BigFloat:
    """`kernel(x)` rounded to `precision` bits, decided and not assumed.

    Parameters:
        kernel: What to evaluate. It takes an argument and a width in bits,
            and returns a value of that width within `slack` units of the
            last place of the true one.
        slack: The bound the kernel keeps to.

    Args:
        x: The argument.
        precision: The number of bits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: If the kernel raises, or if the width grows `_ZIV_LIMIT` times
            without the rounding settling.
    """
    _ = checked_precision(precision, "round_by_deciding_at()")
    var width = precision + _ZIV_START
    for _ in range(_ZIV_LIMIT):
        var wide = kernel(x, width)
        if not wide.is_finite() or wide.is_zero():
            # An infinity, a NaN or an exact zero is the answer whatever the
            # width, and has no last place to put the slack under. It still
            # has to come back at the precision asked for and not at the
            # width it was computed in.
            if wide.is_nan():
                return BigFloat.nan(precision)
            if wide.is_infinite():
                return BigFloat.infinity(precision, wide.sign)
            return BigFloat.zero(precision, wide.sign)
        var settled = _settled(wide, width, slack, precision, rounding_mode)
        if settled:
            return settled.take()
        width += width - precision
    raise Error(
        "the rounding of this value could not be decided; the kernel is"
        " further from the true value than its stated bound allows"
    )


def round_by_deciding_at_two[
    kernel: def(BigFloat, BigFloat, Int) thin raises -> BigFloat, slack: Int
](
    x: BigFloat,
    y: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode,
) raises -> BigFloat:
    """`kernel(x, y)` rounded to `precision` bits, decided and not assumed.

    Parameters:
        kernel: What to evaluate. It takes two arguments and a width in bits,
            and returns a value of that width within `slack` units of the
            last place of the true one.
        slack: The bound the kernel keeps to.

    Args:
        x: The first argument.
        y: The second argument.
        precision: The number of bits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: If the kernel raises, or if the width grows `_ZIV_LIMIT` times
            without the rounding settling.

    Notes:

    The same loop as `round_by_deciding_at()` with one more argument. The two
    were once written out at every call site, on the grounds that a Mojo
    parameter is a function rather than a closure and so cannot carry a
    second argument -- which is true and beside the point, since the second
    argument can simply be one the kernel takes.

    What still cannot come here is a kernel of a different shape: the power
    passes a whole degree as an `Int`, or a sign alongside the two values,
    and decides the sign of an exact zero for itself rather than taking the
    kernel's.
    """
    _ = checked_precision(precision, "round_by_deciding_at_two()")
    var width = precision + _ZIV_START
    for _ in range(_ZIV_LIMIT):
        var wide = kernel(x, y, width)
        if not wide.is_finite() or wide.is_zero():
            # An infinity, a NaN or an exact zero is the answer whatever the
            # width, and has no last place to put the slack under.
            if wide.is_nan():
                return BigFloat.nan(precision)
            if wide.is_infinite():
                return BigFloat.infinity(precision, wide.sign)
            return BigFloat.zero(precision, wide.sign)
        var settled = _settled(wide, width, slack, precision, rounding_mode)
        if settled:
            return settled.take()
        width += width - precision
    raise Error(
        "the rounding of this value could not be decided; the kernel is"
        " further from the true value than its stated bound allows"
    )


def exp_at_width(x: BigFloat, width: Int) raises -> BigFloat:
    """`exp(x)` to `width` bits.

    Args:
        x: The exponent.
        width: The bits wanted.

    Returns:
        The value, within `_EXP_SLACK` units of the last place.

    Raises:
        OverflowError: If the answer's exponent would not fit in an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    The argument is reduced by the logarithm of two: `x` is `k ln 2 + r` with
    `|r|` below `ln 2`, so `exp(x)` is `2^k exp(r)`, and multiplying by a
    power of two is exact. The series then runs on a value below one, where
    it converges, and the integer `k` carries the size.

    Taking `k` out costs precision: `k ln 2` is about as large as `x` and the
    difference is about one, so the subtraction loses as many bits as `k` has.
    The working width carries those bits back, which is why it depends on `k`
    and not only on the width asked for.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_infinite():
        if x.sign:
            return BigFloat.zero(width, False)
        return BigFloat.infinity(width, False)
    if x.is_zero():
        return BigFloat.from_int(1, width)

    # `k` only has to be an integer near `x / ln 2`; being one out costs a
    # term of the series and nothing else, so a narrow logarithm will do.
    #
    # Where the answer stops being representable is also decided here, and
    # exactly: `exp(x)` is `2^k` times something near one, so an answer has
    # an exponent if and only if `k` has an `Int`. There is no separate bound
    # on the argument, because any bound stated in powers of two is either
    # stricter than that or looser.
    var k = _truncated_to_int(
        bigfloat_arithmetics.divide(x, ln2(64), 64, RoundingMode.ROUND_DOWN),
        "exp()",
    )
    var scale = (
        width + Int(bit_width(UInt(width))) + Int(bit_width(UInt(abs(k)))) + 12
    )
    var reduced = x.copy()
    if k != 0:
        # The logarithm of two is asked for only here. An argument already
        # below it needs no reduction, and computing a constant it will not
        # use costs more than everything else this function does.
        reduced = bigfloat_arithmetics.subtract(
            x,
            bigfloat_arithmetics.multiply(
                BigFloat.from_int(k, scale), ln2(scale), scale
            ),
            scale,
        )

    var total = BigFloat.from_int(1, scale)
    if not reduced.is_zero():
        # The series is summed on an argument halved `sqrt(scale)` times and
        # squared back, which is what makes the cost grow as the square root
        # of the precision rather than with it. The squarings cost a bit
        # each, and that is the width they are given.
        var series = _exponential_of_small(reduced, scale)
        total = bigfloat_arithmetics.add(total, series, scale)
    if k != 0:
        total = bigfloat_arithmetics.multiply(
            total, BigFloat.power_of_two(k), scale
        )
    return BigFloat.from_rounded_parts(
        total.significand, total.exponent, width, total.sign
    )


def _agreement_with_one(value: BigFloat, limit: Int) raises -> Int:
    """How many bits a value between a half and two shares with one.

    Args:
        value: The value, finite, positive, and in `[1/2, 2)`.
        limit: How far to count. The answer is never above this.

    Returns:
        The number of bits the value agrees with one in, counted no further
        than `limit`.

    Raises:
        Error: Propagated from reading a bit of the significand.

    Notes:

    Above one the leading bit is followed by noughts for as long as the value
    agrees with one, and below one by ones, so the count is a run of bits in
    the significand and the first bit that breaks the run ends it. Below one
    it can come out one short, which only ever asks for one root more than
    the balance wanted and is covered by the working width.

    Nothing is allocated and no float arithmetic happens. That matters because
    the answer is wanted on every call, including the calls that go on to take
    no roots at all, where forming `significand - 2^-exponent` as a `BigInt`
    cost a sixth of the whole logarithm at a thousand bits.
    """
    var top = value.precision - 1
    var continues = value.exponent < -top
    for offset in range(1, limit + 1):
        if top - offset < 0:
            # Nothing left below the leading bit. Above one that makes the
            # value exactly one; below one it makes it `1 - 2^-precision`.
            if continues:
                return value.precision
            return limit
        if test_bit(value.significand, top - offset) != continues:
            return offset
    return limit


def _root_reductions(scale: Int, value: BigFloat) raises -> Tuple[Int, Int]:
    """How many square roots to take before summing the logarithm's series.

    Args:
        scale: The bits the sum is taken to.
        value: The argument the series will run on, in `[1/2, 2)`.

    Returns:
        The number of roots worth taking, and how many bits the argument
        already shares with one. Both are nought when no root is worth it.

    Raises:
        Error: Propagated from measuring the argument.

    Notes:

    `ln(m)` is `2^k ln(m^(1/2^k))`, and each root halves the distance from
    one. A root costs three to five multiplies, while the series gains
    `2(d + 1)` bits a term for an argument `d` bits from one, so `k` roots cut
    the terms from `scale/2d` to `scale/2(d + k)`. The two costs balance near
    `k = sqrt(scale)/3`, and a `d` already past that leaves nothing to buy.

    Below a few hundred bits the series is short enough that the roots cost
    more than the terms they save, so none are taken -- and the argument is
    not measured either, which at 53 bits is itself worth a few per cent.
    """
    var wanted = _halvings(scale) // 3
    if wanted < 4:
        return (0, 0)
    var agreement = _agreement_with_one(value, wanted)
    if agreement >= wanted:
        return (0, 0)
    return (wanted - agreement, agreement)


def ln_at_width(x: BigFloat, width: Int) raises -> BigFloat:
    """`ln(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_LN_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    A binary float is already `m * 2^e` with `m` between one and two, so the
    logarithm is `e ln 2 + ln m` and the series only ever sees `m`. The
    series itself is the inverse hyperbolic tangent, `ln m = 2 atanh((m-1) /
    (m+1))`, whose argument is at most a third there.

    For `x` between a half and two the two parts would cancel -- `e` is nought
    or minus one and the answer is near nought -- so the split is skipped and
    the series runs on `x` itself, where its argument is still at most a
    third. Beyond that binade `|e ln 2|` is at least 1.38 while `|ln m|` is at
    most 0.7, so the sum loses at most a bit.

    A third of `m` gains the series only three bits a term, which at a
    thousand bits is three hundred terms, so `m` is first brought closer to
    one by square roots: `ln(m)` is `2^k ln(m^(1/2^k))`, and the scaling back
    is a power of two and therefore exact. The series then gains `2k` bits a
    term instead of three.

    What the roots cost is bits, not just time. A root is correctly rounded
    and so lands within a unit of the last place of a value near one, while
    the series is handed `root - 1`, which is `2^-(d+k)` for an argument `d`
    bits from one. That subtraction is exact -- both sides lie between a half
    and two -- but it leaves `d + k` fewer bits than the root has, so the
    working width carries them. The count is bounded by the choice of `k`:
    a `d` already past what the roots would buy leaves `k` at nought.

    The leading bit's position is formed as a `BigInt`, because
    `exponent + precision` can leave an `Int` while the logarithm of such a
    value is an ordinary number.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.sign:
        if x.is_zero():
            return BigFloat.infinity(width, True)
        return BigFloat.nan(width)
    if x.is_zero():
        return BigFloat.infinity(width, True)
    if x.is_infinite():
        return BigFloat.infinity(width, False)

    var scale = working_width(width)
    # The position of the top bit, which is `exponent + precision - 1`.
    var leading = BigInt(x.exponent) + BigInt(x.precision) - BigInt.one()

    var mantissa = x.copy()
    var whole_binades = BigInt.zero()
    if leading > BigInt.zero() or leading < BigInt(-1):
        mantissa = BigFloat(
            significand=x.significand,
            exponent=-(x.precision - 1),
            precision=x.precision,
            sign=False,
        )
        whole_binades = leading.copy()

    var choice = _root_reductions(scale, mantissa)
    var reductions = choice[0]
    var work = scale
    if reductions > 0:
        # The subtraction below loses the bits the root shares with one,
        # which is what the argument already shared plus one per root -- the
        # `k` the balance asked for, and a bit for a count that came out
        # short. The width does not otherwise depend on which of the two the
        # bits came from.
        var lost = choice[0] + choice[1]
        work = scale + lost + Int(bit_width(UInt(lost))) + 4

    var root = mantissa.copy()
    for _ in range(reductions):
        root = sqrt(root, work)

    var one = BigFloat.from_int(1, work)
    var ratio = bigfloat_arithmetics.divide(
        bigfloat_arithmetics.subtract(root, one, work),
        bigfloat_arithmetics.add(root, one, work),
        work,
    )
    var total = bigfloat_arithmetics.multiply(
        atanh_at_width(ratio, work),
        BigFloat.power_of_two(reductions + 1),
        work,
    )
    if not whole_binades.is_zero():
        total = bigfloat_arithmetics.add(
            bigfloat_arithmetics.multiply(
                BigFloat.from_bigint(whole_binades, work), ln2(work), work
            ),
            total,
            work,
        )
    return BigFloat.from_rounded_parts(
        total.significand, total.exponent, width, total.sign
    )


def exp(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """`e` to the power of a value, correctly rounded.

    Args:
        x: The exponent.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `exp(x)`.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If the answer's exponent would not fit in an `Int`,
            which happens exactly when `x / ln 2` does not.
        Error: Propagated from the arithmetic.

    Notes:

    `exp` of an infinity is an infinity or a zero, and of a NaN a NaN. There
    is no overflow to an infinity for a finite argument: this type's exponent
    is as wide as an `Int`, so an argument that asks for more is refused
    rather than answered with an infinity it did not earn.
    """
    _ = checked_precision(precision, "exp()")

    # An argument far below the last place of the answer has an answer the
    # series cannot reach: `exp(x)` is `1 + x + x^2/2 + ...`, and once `|x|`
    # is below `2^-(precision+4)` the quadratic term is nowhere near a
    # rounding boundary, so `1 + x` rounds exactly as `exp(x)` does. The
    # addition already knows how to do that, sticky bit and all.
    #
    # This is not only a shortcut. The loop widens geometrically, so an
    # argument like `2^-100000` would need more widenings than the limit
    # allows before the kernel could tell which side of one the answer is on,
    # and the call would be refused rather than answered.
    # A nought argument is the one place the answer is exactly one, which is
    # the one answer the loop below can never settle on: a value that sits
    # exactly on a boundary has rounding neighbours on both sides, so the
    # directed modes widened to the limit and refused `exp(0)`.
    if x.is_zero():
        return BigFloat.from_int(1, precision)
    if (
        x.is_finite()
        and compare_absolute(x, BigFloat.power_of_two(-(precision + 4))) < 0
    ):
        return bigfloat_arithmetics.add(
            BigFloat.from_int(1, precision), x, precision, rounding_mode
        )

    return round_by_deciding_at[exp_at_width, _EXP_SLACK](
        x, precision, rounding_mode
    )


def ln(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The natural logarithm of a value, correctly rounded.

    Args:
        x: The argument.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `ln(x)`.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    A negative argument gives a NaN, as the square root of one does, and zero
    gives a negative infinity, which is the value the logarithm approaches
    there. `ln(1)` is a positive zero.
    """
    _ = checked_precision(precision, "ln()")
    return round_by_deciding_at[ln_at_width, _LN_SLACK](
        x, precision, rounding_mode
    )


# ===----------------------------------------------------------------------=== #
# The other bases, and the two functions that hold their accuracy near zero
# ===----------------------------------------------------------------------=== #
#
# `log2`, `log10` and `log` are `ln` divided by the logarithm of the base, and
# `exp2` and `exp10` are `exp` of the argument times it. Neither identity is
# the hard part. The hard part is that these functions, unlike `ln` and `exp`,
# have arguments whose answers are exactly representable -- `log2(8)` is three
# -- and `round_by_deciding_at()` can never settle on such an answer. It asks
# whether every value the kernel's error allows rounds the same way, and an
# answer sitting exactly on a representable value has values on either side of
# it that do not, however far the width grows. So it widens to `_ZIV_LIMIT`
# and raises.
#
# Every one of those arguments is therefore recognized first and answered from
# integer arithmetic rather than from a series. Which arguments those are is a
# question with an exact answer in each case, and each function's docstring
# states it.


comptime _OTHER_BASE_SLACK = 2
"""Units in the last place the kernels below may be off at their own width.

Each is a handful of correctly rounded steps -- one or two logarithms or one
exponential, and a multiply or a divide -- carried at `working_width()`
and rounded once on the way out. Those steps contribute a few units of the
working width, which `bit_width(width) + 12` bits beyond the answer leaves far
below its last place, so what is left is the one rounding, worth half a unit.
"""


def _at_width(value: BigFloat, width: Int) raises -> BigFloat:
    """Rounds a value computed at a working width into the width to return.

    Args:
        value: What the identity came to.
        width: The bits to keep.

    Returns:
        The value at `width` bits, sign and all.

    Raises:
        Error: Propagated from the rounding.
    """
    if not value.is_finite():
        if value.is_nan():
            return BigFloat.nan(width)
        return BigFloat.infinity(width, value.sign)
    if value.is_zero():
        return BigFloat.zero(width, value.sign)
    return BigFloat.from_rounded_parts(
        value.significand, value.exponent, width, value.sign
    )


def _odd_part(x: BigFloat) raises -> Tuple[BigInt, BigInt]:
    """A finite non-zero magnitude as an odd integer times a power of two.

    Args:
        x: The value, finite and not nought. Its sign is not read.

    Returns:
        A pair `(m, e)` with `|x| = m * 2^e` and `m` odd.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    This is the form every exactness question below is decided in, because it
    is canonical: a positive dyadic rational is an odd integer times a power
    of two in exactly one way. The significand a `BigFloat` carries is not
    canonical -- `3 * 2^-1` and `6 * 2^-2` are the same number held at two
    precisions -- so a test written on the significand as it stands would
    answer differently for two values that are equal.

    The exponent comes back as a `BigInt` because `exponent + precision` can
    leave an `Int` while the value itself is ordinary, which is the reason
    `leading_bit_position()` returns one too.
    """
    var shift = trailing_zeros(x.significand)
    return (x.significand >> shift, BigInt(x.exponent) + BigInt(shift))


def _is_even(value: BigInt) -> Bool:
    """Whether an integer is even.

    Args:
        value: The integer.

    Returns:
        True for an even value, and for nought, which is even.

    Notes:

    `trailing_zeros()` answers `-1` for nought and the index of the lowest
    set bit otherwise, so only an odd value answers nought. The sign does not
    enter, since negating a value does not move its lowest set bit.
    """
    return trailing_zeros(value) != 0


def _exact_power_exponent(
    magnitude: BigInt, base: BigInt
) raises -> Optional[Int]:
    """The `k` above nought with `base^k == magnitude`, where there is one.

    Args:
        magnitude: The value to write as a power, odd and above one.
        base: The base, odd and above one.

    Returns:
        The exponent, or nothing when the value is no power of the base.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `base^k` grows with `k`, so this is a binary search, and the bit lengths
    bound where to search. A `k`-th power of a `b`-bit value has between
    `k(b-1) + 1` and `kb` bits, so matching `magnitude`'s `a` bits puts `k`
    between `a/b` and `(a-1)/(b-1)`. Without those bounds the search would
    open by raising the base to half of `magnitude`'s bit length, which for a
    large base is a number with far more bits than either of them.
    """
    var size = magnitude.bit_length()
    var base_size = base.bit_length()
    var low = size // base_size
    if low < 1:
        low = 1
    var high = (size - 1) // (base_size - 1)
    while low <= high:
        var middle = low + (high - low) // 2
        var order = base.power(middle).compare(magnitude)
        if order == 0:
            return middle
        if order < 0:
            low = middle + 1
        else:
            high = middle - 1
    return None


def _exact_integer_log(
    magnitude: BigInt,
    power: BigInt,
    base_magnitude: BigInt,
    base_power: BigInt,
) raises -> Optional[BigInt]:
    """The whole `k` with `m * 2^e == (n * 2^f)^k`, where there is one.

    Args:
        magnitude: `m`, the argument's odd part.
        power: `e`, the power of two the argument carries.
        base_magnitude: `n`, the base's odd part.
        base_power: `f`, the power of two the base carries.

    Returns:
        The exponent, or nothing when the argument is no whole power of the
        base.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Both sides are in the canonical form, so the one equation splits into two
    with no roots and no logarithms in them: `m = n^k` on the odd parts and
    `e = f k` on the powers of two. Which of the two decides `k` depends on
    which part of the base is trivial.

    With `f` not nought the second equation gives `k` outright, as `e / f`
    where that division comes out exact, and the first is then one power to
    form and one comparison. With `f` nought the base is an odd integer, `e`
    has to be nought as well, and `k` comes from the search above.

    A base that is a power of two -- `n` equal to one -- makes the first
    equation `m = 1`, so an argument with any odd part at all is no power of
    it. That is not an approximation of the answer but all of it: `m^q = 1`
    forces `m = 1`, so such an argument has no rational logarithm in that
    base either.
    """
    if magnitude.is_one() and power.is_zero():
        # The argument is one, whose logarithm is nought in every base.
        return BigInt.zero()
    if base_magnitude.is_one():
        # The base is a power of two, and not one, so `f` is not nought.
        if not magnitude.is_one():
            return None
        var quotient = power.truncate_divide(base_power)
        if quotient * base_power != power:
            return None
        return quotient^
    if magnitude.is_one():
        # A power of two in a base that is not one. Only `k = 0` could leave
        # an odd part of one, and that case was taken above.
        return None
    if not base_power.is_zero():
        var quotient = power.truncate_divide(base_power)
        if quotient * base_power != power:
            return None
        if quotient < BigInt.one():
            return None
        # `n^k` holds at least `k + 1` bits, so a `k` past `m`'s bit length
        # cannot be the one, and that bound is what makes it an `Int`.
        if quotient > BigInt(magnitude.bit_length()):
            return None
        if base_magnitude.power(quotient.to_int()) != magnitude:
            return None
        return quotient^
    if not power.is_zero():
        return None
    var found = _exact_power_exponent(magnitude, base_magnitude)
    if not found:
        return None
    return BigInt(found.take())


def _halved_base(
    base_magnitude: BigInt, base_power: BigInt
) raises -> Tuple[BigInt, BigInt, Int]:
    """A base reduced by every exact square root it has.

    Args:
        base_magnitude: `n`, the base's odd part.
        base_power: `f`, the power of two the base carries.

    Returns:
        The odd part and the power of two of `base^(1/2^r)`, and the `r` that
        got there: the largest one for which that root is still a dyadic
        rational.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    This is what turns the whole-number search above into a complete test for
    an exactly representable answer. `log_b(x)` is `log_{b'}(x) / 2` for `b'`
    the square root of `b`, so one halving of the base turns an answer of
    `k/2` into a whole `k`, and `r` of them turn `k/2^r` into one.

    A base is the square of a dyadic rational exactly when `f` is even and
    `n` is a perfect square, since the power of two in a square is even and
    the odd part of a square is itself a square. Both tests are integer ones:
    a parity, and one integer square root with its remainder. There are at
    most as many halvings as `f` has trailing zeros, so the loop runs a few
    times and never long.
    """
    var odd = base_magnitude.copy()
    var power = base_power.copy()
    var taken = 0
    while _is_even(power):
        if odd.is_one():
            if power.is_zero():
                # The base is one, which `log()` refuses before this. Stopping
                # here rather than halving nought for ever is the guard.
                break
            power = power.truncate_divide(BigInt(2))
        else:
            var parts = sqrt_rem(odd)
            if not parts[1].is_zero():
                break
            odd = parts[0].copy()
            power = power.truncate_divide(BigInt(2))
        taken += 1
    return (odd^, power^, taken)


def _integer_argument(x: BigFloat) raises -> Optional[Int]:
    """The value of `x` where it is a whole number an `Int` holds.

    Args:
        x: The value, finite.

    Returns:
        The integer, or nothing when `x` has a fractional part or is too
        large for an `Int`.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    An `Int` is the right bound and not a convenience. `exp2` of a whole `k`
    is `2^k`, whose exponent is `k` less the bits of its significand, so a
    `k` outside an `Int` has no answer in this type at all. Returning nothing
    there sends the argument to the kernel, which refuses it with the message
    the exponential already has for an answer whose exponent will not fit.

    The exponent is tested before it is added to, because a value sitting
    near the top of the exponent range would make the sum wrap.
    """
    if x.is_zero():
        return 0
    if x.exponent > 63:
        return None
    var shift = trailing_zeros(x.significand)
    if x.exponent + shift < 0:
        return None
    var whole = x.significand >> shift
    if whole.bit_length() + x.exponent + shift > 62:
        return None
    var value = (whole << (x.exponent + shift)).to_int()
    return -value if x.sign else value


def log2_at_width(x: BigFloat, width: Int) raises -> BigFloat:
    """`log2(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_OTHER_BASE_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `ln(x) / ln 2`, at a working width, rounded once. Dividing by a constant
    costs no accuracy beyond its own rounding: the quotient's relative error
    is the sum of the two relative errors, and `ln_at_width` keeps a relative
    accuracy for every argument, including one near enough to one that the
    answer is tiny.

    The special values need no code of their own. `ln_at_width` answers a
    NaN for a NaN and for a negative, a negative infinity for either zero,
    and a positive infinity for an infinity, and dividing any of those four
    by a positive constant leaves it as it was.

    This never answers a whole number for an argument that has one, because
    it is never asked to: `log2()` takes those itself.
    """
    var work = working_width(width)
    return _at_width(
        bigfloat_arithmetics.divide(ln_at_width(x, work), ln2(work), work),
        width,
    )


def log10_at_width(x: BigFloat, width: Int) raises -> BigFloat:
    """`log10(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_OTHER_BASE_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `ln(x) / ln 10`, which is why `ln10()` exists beside `ln2()`. The same
    accounting as `log2_at_width` applies, and so does the same account of
    the special values.
    """
    var work = working_width(width)
    return _at_width(
        bigfloat_arithmetics.divide(ln_at_width(x, work), ln10(work), work),
        width,
    )


def log_at_width(x: BigFloat, base: BigFloat, width: Int) raises -> BigFloat:
    """`log(x) / log(base)` to `width` bits.

    Args:
        x: The argument, which must not be a NaN or negative.
        base: The base, which must be finite, positive, and not one.
        width: The bits wanted.

    Returns:
        The value, within `_OTHER_BASE_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Two logarithms and a division. The base's logarithm is as accurate
    relative to itself as the argument's is to its own, so the quotient keeps
    that accuracy even for a base so near one that its logarithm is tiny --
    which is the case a fixed working width above the answer's would get
    wrong.

    A zero or an infinity for `x` never arrives, `log()` answering those
    itself, and the division would answer them correctly if one did: `ln(0)`
    is a negative infinity, and dividing that by the negative logarithm of a
    base below one turns it positive, which is what `log(0)` in such a base
    is.
    """
    var work = working_width(width)
    return _at_width(
        bigfloat_arithmetics.divide(
            ln_at_width(x, work), ln_at_width(base, work), work
        ),
        width,
    )


def exp2_at_width(x: BigFloat, width: Int) raises -> BigFloat:
    """`2^x` to `width` bits.

    Args:
        x: The exponent.
        width: The bits wanted.

    Returns:
        The value, within `_OTHER_BASE_SLACK` units of the last place.

    Raises:
        OverflowError: If the answer's exponent would not fit in an `Int`,
            which happens exactly when the whole part of `x` does not.
        Error: Propagated from the arithmetic.

    Notes:

    `exp(x ln 2)`, and the width the product is formed at is the whole of the
    care. An error in an exponent is a relative error in the answer, so a
    product good to a relative `2^-w` leaves the answer good to a relative
    `|x| ln 2 * 2^-w` -- the larger the argument, the more bits the product
    has to carry. The leading bit of `x` says how many, and that is what
    `reach` adds.

    Past a leading bit of 64 the answer has no exponent an `Int` could hold,
    so the extra bits stop there and `exp_at_width` refuses the argument. It
    refuses exactly the right ones: it forms `k` as the whole part of
    `x ln 2 / ln 2`, which is the whole part of `x`.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_infinite():
        if x.sign:
            return BigFloat.zero(width, False)
        return BigFloat.infinity(width, False)
    if x.is_zero():
        return BigFloat.from_int(1, width)

    var leading = leading_bit_position(x)
    var reach = 0
    if leading > BigInt(64):
        reach = 64
    elif leading > BigInt.zero():
        reach = leading.to_int()
    var work = working_width(width) + reach
    return _at_width(
        exp_at_width(bigfloat_arithmetics.multiply(x, ln2(work), work), work),
        width,
    )


def exp10_at_width(x: BigFloat, width: Int) raises -> BigFloat:
    """`10^x` to `width` bits.

    Args:
        x: The exponent.
        width: The bits wanted.

    Returns:
        The value, within `_OTHER_BASE_SLACK` units of the last place.

    Raises:
        OverflowError: If the answer's exponent would not fit in an `Int`,
            which happens exactly when `x log2(10)` does not.
        Error: Propagated from the arithmetic.

    Notes:

    `exp(x ln 10)`, by the same accounting as `exp2_at_width`, with two more
    bits of reach because the logarithm of ten is above two rather than
    below one.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_infinite():
        if x.sign:
            return BigFloat.zero(width, False)
        return BigFloat.infinity(width, False)
    if x.is_zero():
        return BigFloat.from_int(1, width)

    var leading = leading_bit_position(x)
    var reach = 2
    if leading > BigInt(64):
        reach = 66
    elif leading > BigInt.zero():
        reach = leading.to_int() + 2
    var work = working_width(width) + reach
    return _at_width(
        exp_at_width(bigfloat_arithmetics.multiply(x, ln10(work), work), work),
        width,
    )


def expm1_at_width(x: BigFloat, width: Int) raises -> BigFloat:
    """`exp(x) - 1` to `width` bits, without the cancellation the name avoids.

    Args:
        x: The argument, finite and not nought.
        width: The bits to work in.

    Returns:
        The value, within a handful of units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Below a half in magnitude the series is the whole of it, which is why
    `expm1_series_at_width` exists: the difference from one is what a small
    argument has bits for, and the exponential itself has thrown them away by
    the time it is formed. Above a half there is nothing left to cancel --
    `exp(x) - 1` is then at least 0.64 while `exp(x)` is at most about 1.65
    times that -- so taking the one away costs less than two units.

    Both the rounded `expm1()` and the hyperbolic functions evaluate this,
    which is why it is here and not in either of them.
    """
    if compare_absolute(x, BigFloat.power_of_two(-1)) <= 0:
        return expm1_series_at_width(x, width)
    return bigfloat_arithmetics.subtract(
        exp_at_width(x, width), BigFloat.from_int(1, width), width
    )


def log1p_at_width(x: BigFloat, width: Int) raises -> BigFloat:
    """`ln(1 + x)` to `width` bits, without the cancellation the name avoids.

    Args:
        x: The argument, finite, not nought and above minus one.
        width: The bits to work in.

    Returns:
        The value, within a handful of units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `1 + x` is `(1 + z)/(1 - z)` with `z = x/(x + 2)`, so `ln(1 + x)` is
    `2 atanh(z)`, and that rearrangement is exact. For a small `x` the
    quotient is `x/2` to within its own square, so the series sees every bit
    of it, where forming `1 + x` first would have thrown them away. Above a
    half the logarithm is far enough from zero to be taken as it reads.

    Both the rounded `log1p()` and the inverse hyperbolic functions evaluate
    this, which is why it is here and not in either of them.
    """
    if compare_absolute(x, BigFloat.power_of_two(-1)) <= 0:
        var ratio = bigfloat_arithmetics.divide(
            x,
            bigfloat_arithmetics.add(x, BigFloat.from_int(2, width), width),
            width,
        )
        return bigfloat_arithmetics.multiply(
            atanh_at_width(ratio, width), BigFloat.power_of_two(1), width
        )
    return ln_at_width(
        bigfloat_arithmetics.add(BigFloat.from_int(1, width), x, width), width
    )


def _expm1_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`exp(x) - 1` to `width` bits, without the cancellation.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_OTHER_BASE_SLACK` units of the last place.

    Raises:
        OverflowError: If the answer's exponent would not fit in an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    The value itself is `expm1_at_width`, which the hyperbolic functions
    evaluate too. What this adds is the special values and the one rounding
    into `width`.

    `exp(-infinity) - 1` is exactly minus one, which `expm1()` answers
    itself: a value a kernel returns exactly cannot be settled on.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_infinite():
        if x.sign:
            return BigFloat.from_int(-1, width)
        return BigFloat.infinity(width, False)
    if x.is_zero():
        return BigFloat.zero(width, x.sign)

    return _at_width(expm1_at_width(x, working_width(width)), width)


def _log1p_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`ln(1 + x)` to `width` bits, without the cancellation.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_OTHER_BASE_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `1 + x` is `(1 + z)/(1 - z)` for `z = x/(x + 2)`, so `ln(1 + x)` is
    `2 atanh(z)`, and that rearrangement is exact. For a small `x` the
    quotient is `x/2` to within its own square, so the series sees every bit
    of `x`, where forming `1 + x` first would have thrown all but the leading
    ones away. Above a half in magnitude the logarithm is far enough from
    nought to be taken as it reads, and `1 + x` is formed there -- exactly,
    as it happens, whenever it cancels, since a difference of two values
    within a factor of two of each other is exact.

    The value itself is `log1p_at_width`, which the inverse hyperbolic
    functions evaluate too. What this adds is the special values, the edge of
    the domain, and the one rounding into `width`.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_infinite():
        if x.sign:
            return BigFloat.nan(width)
        return BigFloat.infinity(width, False)
    if x.is_zero():
        return BigFloat.zero(width, x.sign)

    if x.sign:
        # At minus one the logarithm falls off the end, and below it there is
        # no real answer. Asked above, where the identity holds, this costs a
        # comparison against a one-bit value.
        var order = compare_absolute(x, BigFloat.from_int(1, 1))
        if order == 0:
            return BigFloat.infinity(width, True)
        if order > 0:
            return BigFloat.nan(width)

    return _at_width(log1p_at_width(x, working_width(width)), width)


def _square_term_is_below_a_guard_unit(x: BigFloat, guard: Int) raises -> Bool:
    """Whether `x^2` is small enough for a guard unit to stand in for it.

    Args:
        x: The argument, finite and not nought.
        guard: How many guard bits the rounding will be given.

    Returns:
        True when the quadratic correction is below one guard unit of `x`,
        which is what makes moving `x` by a guard unit land on the same side
        of every rounding boundary as the true value does.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `expm1(x)` is `x + x^2/2 + ...` and `log1p(x)` is `x - x^2/2 + ...`, so
    for both of them the correction to `x` is quadratic, where the sine's and
    the tangent's is cubic. With `L` the leading bit's position, `|x^2/2|` is
    below `2^(2L+1)` and a guard unit is `2^(L - p + 1 - g)` for a
    significand of `p` bits, so the condition is

        L <= -(p + g)

    and the test is one bit stricter than that, which costs nothing: an
    argument just the other side of the line is one the loop that decides a
    rounding settles, since the correction it has to see is then about
    `2^-g` of a unit in the last place rather than nothing at all.

    The comparison is in a `BigInt` because `L` can be far outside an `Int`,
    which is the whole reason this gate exists.
    """
    return leading_bit_position(x) < BigInt(-(x.precision + guard))


def _expm1_saturation_magnitude(width: Int) raises -> BigFloat:
    """The `|x|` past which `e^-|x|` cannot reach the last place of `width`.

    Args:
        width: The bits in question.

    Returns:
        A bound on `|x|`. Below minus it, `expm1(x)` is within half a unit of
        minus one.

    Raises:
        Error: Propagated from the construction.

    Notes:

    `expm1(x)` falls short of minus one by `e^x`, which for a negative `x` is
    `e^-|x|`, and that is below `2^-(width+1)` -- half the distance from
    minus one to the float beside it -- once `|x| > (width + 1) ln 2`. So the
    bound is `(width + 4) ln 2`, from above.

    It is computed in integers against `6932/10000`, which is above
    `ln 2 = 0.6931471805...`, for the reason `tanh`'s bound gives: a constant
    a hair below the true one is not conservative, and no fixed cushion
    rescues it, because the shortfall grows with the width. The division
    comes before the multiplication so that the product cannot leave an `Int`
    at the widest precision this layer takes.
    """
    var whole = (width + 4) // 10000
    var rest = (width + 4) % 10000
    var bound = whole * 6932 + (rest * 6932) // 10000 + 1
    return BigFloat.from_int(bound, Int(bit_width(UInt(bound))) + 1)


def _saturated_expm1(
    precision: Int, rounding_mode: RoundingMode
) raises -> BigFloat:
    """`expm1` of an argument below `-_expm1_saturation_magnitude(precision)`.

    Args:
        precision: The bits wanted.
        rounding_mode: How to round.

    Returns:
        The correctly rounded value, which is minus one only in the modes
        that round that way.

    Raises:
        Error: Propagated from the construction.

    Notes:

    `expm1` never reaches minus one: it falls short by `e^x`, and past the
    bound that shortfall is below half the distance from minus one to the
    float beside it. So the true value sits strictly between minus one and
    that neighbour, nearer to minus one, and which of the two is the answer
    is the mode's to say. This is `tanh`'s saturation with the sign fixed
    negative, and the modes fall out the same way:

    - the three nearest modes take minus one, the shortfall being under half
      a unit;
    - `UP` rounds away from zero, so it takes minus one as well;
    - `FLOOR` takes the lower of the two, which is minus one;
    - `CEILING` takes the higher, which is the neighbour;
    - `DOWN` rounds toward zero, so it takes the neighbour too.
    """
    var takes_one: Bool
    if (
        rounding_mode == RoundingMode.ROUND_HALF_EVEN
        or rounding_mode == RoundingMode.ROUND_HALF_UP
        or rounding_mode == RoundingMode.ROUND_HALF_DOWN
        or rounding_mode == RoundingMode.ROUND_UP
        or rounding_mode == RoundingMode.ROUND_FLOOR
    ):
        takes_one = True
    else:
        takes_one = False

    if takes_one:
        return BigFloat(
            significand=BigInt.one() << (precision - 1),
            exponent=-(precision - 1),
            precision=precision,
            sign=True,
        )
    # The float of largest magnitude below one: `(2^p - 1) * 2^-p`, which
    # holds exactly `p` bits with its top bit set.
    return BigFloat(
        significand=(BigInt.one() << precision) - BigInt.one(),
        exponent=-precision,
        precision=precision,
        sign=True,
    )


def _exact_log2(
    x: BigFloat, precision: Int, rounding_mode: RoundingMode
) raises -> Optional[BigFloat]:
    """`log2(x)` where it is exact, and nothing where it is not.

    Args:
        x: The argument, finite, positive and not nought.
        precision: The bits the answer keeps.
        rounding_mode: How to round, which matters only for a `k` with more
            bits than the precision holds.

    Returns:
        The answer for a power of two, and nothing otherwise.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var parts = _odd_part(x)
    if not parts[0].is_one():
        return None
    return BigFloat.from_bigint(parts[1], precision, rounding_mode)


def _exact_log10(
    x: BigFloat, precision: Int, rounding_mode: RoundingMode
) raises -> Optional[BigFloat]:
    """`log10(x)` where it is exact, and nothing where it is not.

    Args:
        x: The argument, finite, positive and not nought.
        precision: The bits the answer keeps.
        rounding_mode: How to round, which matters only for a `k` with more
            bits than the precision holds.

    Returns:
        The answer for `10^k` with `k` at nought or above, and nothing
        otherwise.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    With `|x| = m * 2^e` and `m` odd, `x` is `10^k` exactly when `m = 5^k`
    and `e = k`, since `10^k` is `5^k * 2^k` and the odd part of a value is
    unique. So `e` is the only candidate there is, and the test is to form
    `5^e` and compare.

    `5^e` holds more than `2e` bits, so an `e` past half of `m`'s bit length
    cannot be the one. That bound is checked before the power is formed, both
    to keep the work small and to make `e` an `Int`.
    """
    var parts = _odd_part(x)
    if parts[0].is_one():
        # A power of two. Only `10^0` is one, and that is the value one.
        if parts[1].is_zero():
            return BigFloat.zero(precision, False)
        return None
    if parts[1] < BigInt.one():
        return None
    if parts[1] > BigInt(parts[0].bit_length()):
        return None
    var power = parts[1].to_int()
    if 2 * power + 1 > parts[0].bit_length():
        return None
    if BigInt(5).power(power) != parts[0]:
        return None
    return BigFloat.from_bigint(parts[1], precision, rounding_mode)


def _exact_log(
    x: BigFloat,
    base: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode,
) raises -> Optional[BigFloat]:
    """`log(x, base)` where it is exactly representable, and nothing where not.

    Args:
        x: The argument, finite, positive and not nought.
        base: The base, finite, positive, not nought and not one.
        precision: The bits the answer keeps.
        rounding_mode: How to round, which matters only for an answer with
            more bits than the precision holds.

    Returns:
        The answer where it is a dyadic rational, and nothing otherwise.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The base is reduced by every exact square root it has, `r` of them, and
    then the answer is `k / 2^r` for the whole `k` that makes
    `x = base^(1/2^r)` to the `k`. Both steps are integer arithmetic on the
    canonical forms. `log()`'s notes carry the argument that this finds every
    exactly representable answer and no others.
    """
    var left = _odd_part(x)
    var right = _odd_part(base)
    var reduced = _halved_base(right[0], right[1])
    var found = _exact_integer_log(left[0], left[1], reduced[0], reduced[1])
    if not found:
        return None
    var whole = found.take()
    if whole.is_zero():
        return BigFloat.zero(precision, False)
    return BigFloat.from_rounded_parts(
        abs(whole), -reduced[2], precision, whole.sign, rounding_mode
    )


def _log_rounded(
    x: BigFloat,
    base: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode,
) raises -> BigFloat:
    """`log_at_width(x, base)` rounded, decided and not assumed.

    Args:
        x: The argument, finite, positive and not nought.
        base: The base, finite, positive, not nought and not one.
        precision: The number of bits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: If the width grows `_ZIV_LIMIT` times without the rounding
            settling, or from the arithmetic.

    Notes:

    The kernel cannot come back non-finite here: both arguments are finite
    and positive, so the quotient of two logarithms is an ordinary number. It
    can come back as an exact zero, for an argument of one -- except that
    `log()` takes that case before this is called, as it takes every other
    answer a width could not settle on.
    """
    return round_by_deciding_at_two[log_at_width, _OTHER_BASE_SLACK](
        x, base, precision, rounding_mode
    )


def log2(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The base-two logarithm of a value, correctly rounded.

    Args:
        x: The argument.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `log2(x)`.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    A negative argument gives a NaN and either zero a negative infinity, as
    they do for `ln`.

    `log2` of a power of two is a whole number, and that is the only argument
    whose answer is rational at all. The reason is short: `log2(x) = p/q`
    means `x^q = 2^p`, and writing `|x|` as `m * 2^e` with `m` odd makes that
    `m^q * 2^(eq) = 2^p`, which forces `m = 1`. So an answer that is not a
    whole number is irrational, and an answer that is a whole number comes
    from an `m` of one and is `e`.

    Those arguments are answered from the integer significand, before any
    series runs. They have to be: the true value of `log2(8)` is exactly
    three, and the loop that decides a rounding can never settle on a value
    a float holds exactly, because the interval it checks straddles it
    whatever the width. It would widen to its limit and then refuse.

    The test is on the odd part of the significand and not on float
    arithmetic, so it is exact for every exponent: `log2(2^-70)` is `-70` and
    `log2(2^(2^62))` is `2^62`. An answer with more bits than the precision
    holds is rounded in the mode asked for, like any other conversion from an
    integer.
    """
    _ = checked_precision(precision, "log2()")

    if x.is_finite() and not x.is_zero() and not x.sign:
        var exact = _exact_log2(x, precision, rounding_mode)
        if exact:
            return exact.take()

    return round_by_deciding_at[log2_at_width, _OTHER_BASE_SLACK](
        x, precision, rounding_mode
    )


def log10(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The base-ten logarithm of a value, correctly rounded.

    Args:
        x: The argument.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `log10(x)`.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    A negative argument gives a NaN and either zero a negative infinity, as
    they do for `ln`.

    `log10` is exact for `10^k`, and only for `10^k`, and only for a `k` at
    nought or above. Each half of that is worth a line.

    It is exact only at a whole power: `log10(x) = p/q` means
    `x^q = 10^p`, and with `|x| = m * 2^e` and `m` odd that is
    `m^q * 2^(eq) = 5^p * 2^p`. Matching the odd parts gives `m^q = 5^p`, so
    `m` is `5^(p/q)` and that is an integer only when `q` divides `p`. So the
    answer is either a whole number or irrational.

    And only a non-negative `k` is an argument at all. `10^-k` is `1/(2^k
    5^k)`, which is no binary float for `k` above nought -- a fifth is not a
    dyadic rational -- so the negative powers of ten simply cannot be handed
    to this function. `log10(0.001)` is `log10` of the float nearest a
    thousandth, which is not a power of ten and whose logarithm is
    irrational and a hair away from `-3`. It is answered by the series, and
    correctly.

    The test for `10^k` is exact integer arithmetic. `|x| = m * 2^e` is
    `10^k` exactly when `e = k` and `m = 5^e`, so there is one candidate
    exponent and one power to form, and it is only formed when `m` has the
    bits to hold it.
    """
    _ = checked_precision(precision, "log10()")

    if x.is_finite() and not x.is_zero() and not x.sign:
        var exact = _exact_log10(x, precision, rounding_mode)
        if exact:
            return exact.take()

    return round_by_deciding_at[log10_at_width, _OTHER_BASE_SLACK](
        x, precision, rounding_mode
    )


def log(
    x: BigFloat,
    base: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The logarithm of a value in an arbitrary base, correctly rounded.

    Args:
        x: The argument.
        base: The base, which must be finite, positive and not one.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `log(x) / log(base)`.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    A base that is not a base gives a NaN rather than a refusal, which is the
    answer this type gives to every question that has none: a negative base,
    either zero, an infinity, and one, whose logarithm is nought and which
    therefore names no base at all. A negative `x` gives a NaN too.

    A zero or an infinity for `x` gives an infinity whose sign depends on the
    base: `log(0)` runs to a negative infinity in a base above one and to a
    positive one in a base below it, the logarithm being a falling function
    there.

    What is detected exactly, and why that is all of it:

    Every exactly representable answer is found. An answer is exactly
    representable when it is a dyadic rational, `p/2^j`, and the test finds
    every one of those. The base is reduced by its exact square roots as far
    as it goes, `r` of them, and then the whole `k` with `x = base^(1/2^r)`
    to the `k` is searched for; the answer is `k / 2^r`.

    That this is complete takes three steps. Write `|x| = m * 2^e` and
    `base = n * 2^f` with `m` and `n` odd. First, `log_base(x) = p/q` means
    `m^q = n^p` and `eq = fp`. Second, writing `m = g^s` and `n = g^u` with
    `g` the primitive base both share -- which they must, a value's primitive
    base being unique -- the answer is `s/u`, so `q` divides `u`, and from
    `eq = fp` it divides `f` as well. Third, a representable answer has `q`
    equal to `2^j`, so `2^j` divides both `u` and `f`, and the number of
    exact square roots the base has is exactly the smaller of the twos in
    those two -- so `j` is at most `r` and `k = p * 2^(r-j)` is the whole
    number the search finds.

    What is not detected is an answer that is exact but not representable.
    `log(9, 27)` is exactly two thirds, which no binary float holds, so it is
    computed by the series and correctly rounded like any irrational answer.
    Nothing is lost by that: the loop settles on it, because the value it is
    settling on is not one a float sits exactly on.

    The cost of the test is a few integer square roots of the base's odd part
    and one integer power, on every call, whether or not the answer turns out
    to be exact. That is paid because the alternative is not a slower answer
    but no answer: without it, `log(27, 3)` would widen to the limit and
    raise.
    """
    _ = checked_precision(precision, "log()")

    if x.is_nan() or base.is_nan():
        return BigFloat.nan(precision)
    if base.sign or base.is_zero() or base.is_infinite():
        return BigFloat.nan(precision)
    var base_order = compare_absolute(base, BigFloat.from_int(1, 1))
    if base_order == 0:
        return BigFloat.nan(precision)
    if x.sign and not x.is_zero():
        return BigFloat.nan(precision)

    if x.is_zero() or x.is_infinite():
        # `ln(0)` is a negative infinity and `ln(infinity)` a positive one,
        # and dividing by a logarithm that is itself negative -- which is
        # what a base below one has -- turns it round.
        return BigFloat.infinity(precision, x.is_zero() == (base_order > 0))

    var exact = _exact_log(x, base, precision, rounding_mode)
    if exact:
        return exact.take()

    return _log_rounded(x, base, precision, rounding_mode)


def exp2(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """Two to the power of a value, correctly rounded.

    Args:
        x: The exponent.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `2^x`.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If the answer's exponent would not fit in an `Int`,
            which happens exactly when the whole part of `x` does not.
        Error: Propagated from the arithmetic.

    Notes:

    `exp2` of an infinity is an infinity or a zero, and of a NaN a NaN, as
    `exp`'s is.

    A whole argument is answered exactly, and no other argument has an exact
    answer: `2^(p/q)` is a binary float only when `q` divides `p`, since
    otherwise it is an irrational number. So the whole arguments are the ones
    the loop that decides a rounding could not settle, and they are taken
    first, from a single bit with the exponent to match.

    An argument below the last place of the answer is answered too, for the
    reason `exp` gives: `2^x` is `1 + x ln 2 + ...`, and once `|x|` is below
    `2^-(precision+6)` the quadratic term is nowhere near a rounding
    boundary and neither is the factor of `ln 2`. `1 + x` and `2^x` then both
    lie strictly between one and the next float on the same side of it, so
    they round the same way in every mode, and the addition is what knows how
    to do that. Without this an argument like `2^-100000` would widen to the
    limit and raise, since no width the loop reaches can tell `2^x` from one.
    """
    _ = checked_precision(precision, "exp2()")

    if x.is_finite():
        var whole = _integer_argument(x)
        if whole:
            # `2^k` to the precision asked for: one bit, and the rounding
            # pads it out. The exponent is what can fail here, and the
            # rounding is where that is checked.
            return BigFloat.from_rounded_parts(
                BigInt.one(), whole.take(), precision, False
            )
        if (
            not x.is_zero()
            and compare_absolute(x, BigFloat.power_of_two(-(precision + 6))) < 0
        ):
            return bigfloat_arithmetics.add(
                BigFloat.from_int(1, precision), x, precision, rounding_mode
            )

    return round_by_deciding_at[exp2_at_width, _OTHER_BASE_SLACK](
        x, precision, rounding_mode
    )


def exp10(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """Ten to the power of a value, correctly rounded.

    Args:
        x: The exponent.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `10^x`.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If the answer's exponent would not fit in an `Int`,
            which happens exactly when `x log2(10)` does not.
        Error: Propagated from the arithmetic.

    Notes:

    `exp10` of an infinity is an infinity or a zero, and of a NaN a NaN.

    A whole argument at nought or above is answered exactly, by forming
    `10^k` as an integer and rounding it once. Those are the only arguments
    with an exactly representable answer. A negative whole `k` gives
    `1/(2^k 5^k)`, which is no binary float, and a fractional argument gives
    an irrational number; both go to the series, which settles on them
    because the value it is settling on is not one a float sits exactly on.

    The exact path is taken only while `k` is at most the precision asked
    for, which is not a compromise but the same boundary stated twice:
    `10^k` is exactly representable at `p` bits only while `5^k` fits in `p`
    bits, and `5^k` holds more than `2k` of them, so a `k` above `p` has an
    answer that is not representable and that the loop can therefore settle.
    Keeping the cut there also keeps the integer from being formed at a size
    nobody asked for -- `10^(10^18)` is a perfectly good float and a
    hopeless integer.

    An argument below `2^-(precision+6)` is answered as `1 + x`, by the
    account `exp2` gives: the factor of `ln 10` is below four, so `x ln 10`
    is still far inside the first rounding boundary either side of one.
    """
    _ = checked_precision(precision, "exp10()")

    if x.is_finite():
        var whole = _integer_argument(x)
        if whole:
            var power = whole.take()
            if power >= 0 and power <= precision:
                return BigFloat.from_bigint(
                    BigInt(10).power(power), precision, rounding_mode
                )
        if (
            not x.is_zero()
            and compare_absolute(x, BigFloat.power_of_two(-(precision + 6))) < 0
        ):
            return bigfloat_arithmetics.add(
                BigFloat.from_int(1, precision), x, precision, rounding_mode
            )

    return round_by_deciding_at[exp10_at_width, _OTHER_BASE_SLACK](
        x, precision, rounding_mode
    )


def expm1(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """`exp(x) - 1`, correctly rounded, without the cancellation.

    Args:
        x: The argument.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `exp(x) - 1`.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If the answer's exponent would not fit in an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    This is the function to use when the argument is small. `exp(x) - 1`
    computed as written loses every bit of a small `x`: `exp(2^-100)` rounds
    to one, so the difference comes out as nought where the answer is
    `2^-100`. Here the difference is what is computed, by the series
    `expm1_series_at_width` sums, and `expm1(2^-100000)` is `2^-100000`
    nought.

    `exp(x) - 1` is exact only at nought, where it is nought with the sign of
    the argument, and at a negative infinity, where it is exactly minus one.
    Both are answered directly: a value a kernel returns exactly is a value
    the loop that decides a rounding cannot settle on. Any other exact answer
    would need `exp(x)` to be `1 + d` for a dyadic `d`, which makes `x` the
    logarithm of a rational and so irrational.

    Two ranges of argument are answered without the kernel as well, and for
    the same reason in both cases -- the kernel's answer there is a value it
    cannot see past, so no width would settle it.

    Near nought the answer is `x + x^2/2`, which is `x` moved by less than it
    takes to compute: at `2^-100000` the quadratic term has no exponent an
    `Int` could hold. The rounding needs only the side, and one guard unit
    stands in for it -- away from zero, since `x^2/2` is positive whichever
    sign `x` has.

    Far below nought the answer is just inside minus one: `expm1(x)` falls
    short of it by `e^x`, and past `_expm1_saturation_magnitude()` that
    shortfall is less than half the distance from minus one to its
    neighbour. Which of the two the answer is belongs to the mode, and
    `_saturated_expm1()` says which takes which.
    """
    _ = checked_precision(precision, "expm1()")

    if x.is_nan():
        return BigFloat.nan(precision)
    if x.is_infinite():
        if x.sign:
            return BigFloat.from_int(-1, precision)
        return BigFloat.infinity(precision, False)
    if x.is_zero():
        return BigFloat.zero(precision, x.sign)

    if _square_term_is_below_a_guard_unit(x, guard_bits(x, precision)):
        return rounded_beside(x, precision, rounding_mode, x.sign)

    if (
        x.sign
        and compare_absolute(x, _expm1_saturation_magnitude(precision)) > 0
    ):
        return _saturated_expm1(precision, rounding_mode)

    return round_by_deciding_at[_expm1_kernel, _OTHER_BASE_SLACK](
        x, precision, rounding_mode
    )


def log1p(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """`ln(1 + x)`, correctly rounded, without the cancellation.

    Args:
        x: The argument.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `ln(1 + x)`.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    This is the function to use when the argument is small. `ln(1 + x)`
    computed as written rounds its argument to one before the logarithm sees
    it, so it answers nought for every `x` below the last place; here `1 + x`
    is never formed for a small argument, the series running on `x/(x + 2)`
    instead, and `log1p(2^-100000)` is `2^-100000`.

    An argument of minus one gives a negative infinity, one below minus one a
    NaN, and a negative infinity a NaN, since `1 + x` is then negative. A
    positive infinity gives a positive infinity.

    `ln(1 + x)` is exact only at nought, where it is nought with the sign of
    the argument: any other exact answer would make `1 + x` the exponential
    of a rational and so irrational. That case is answered directly, as a
    value the loop could not settle on.

    Near nought the answer is `x - x^2/2`, which is `x` moved by less than it
    takes to compute, so it is answered by moving `x` one guard unit toward
    zero -- toward, because the quadratic term here is subtracted, where
    `expm1`'s is added.
    """
    _ = checked_precision(precision, "log1p()")

    if x.is_nan():
        return BigFloat.nan(precision)
    if x.is_infinite():
        if x.sign:
            return BigFloat.nan(precision)
        return BigFloat.infinity(precision, False)
    if x.is_zero():
        return BigFloat.zero(precision, x.sign)

    if x.sign:
        var order = compare_absolute(x, BigFloat.from_int(1, 1))
        if order == 0:
            return BigFloat.infinity(precision, True)
        if order > 0:
            return BigFloat.nan(precision)

    if _square_term_is_below_a_guard_unit(x, guard_bits(x, precision)):
        return rounded_beside(x, precision, rounding_mode, not x.sign)

    return round_by_deciding_at[_log1p_kernel, _OTHER_BASE_SLACK](
        x, precision, rounding_mode
    )
