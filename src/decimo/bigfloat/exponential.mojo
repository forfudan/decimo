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


"""The square root, the exponential, the logarithm, and the loop that decides
a rounding.

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
"""

from std.bit import bit_width

import decimo.bigfloat.arithmetics as bigfloat_arithmetics
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.comparison import compare_absolute
from decimo.bigfloat.constants import ln2
from decimo.bigfloat.rounding import checked_precision
from decimo.bigint.bigint import BigInt
from decimo.bigint.exponential import sqrt_rem
from decimo.errors import OverflowError
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
"""Units in the last place `_exp_kernel` may be off by.

Every step of the series is one correctly rounded multiply and one correctly
rounded divide, so a term is off by a couple of units of the working width,
and the working width carries `bit_width(terms) + 8` bits beyond what the
kernel returns.
"""

comptime _LN_SLACK = 2
"""Units in the last place `_ln_kernel` may be off by, for the same reasons."""

comptime _EXPONENT_LIMIT_BITS = 62
"""Where an argument to `exp` stops having a representable answer.

`exp(x)` is `2^(x / ln 2)`, so an argument at `2^62` asks for an exponent of
about `2^62 / 0.693`, which is still inside an `Int`, and anything larger is
not. The limit is on the argument rather than on the answer because it can be
tested before any work is done.
"""


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


def _truncated_to_int(value: BigFloat) raises -> Int:
    """The integer part of a finite value, toward zero.

    Args:
        value: The value, whose magnitude must be below `2^63`.

    Returns:
        The integer part, signed.

    Raises:
        OverflowError: If the integer part does not fit in an `Int`.
        Error: Propagated from the arithmetic.
    """
    if value.is_zero():
        return 0
    var magnitude = value.significand.copy()
    if value.exponent >= 0:
        magnitude = magnitude << value.exponent
    else:
        magnitude = magnitude >> -value.exponent
    if magnitude.bit_length() > 62:
        raise OverflowError(
            message="The integer part of this value does not fit in an Int.",
            function="_truncated_to_int()",
        )
    var result = magnitude.to_int()
    return -result if value.sign else result


def _expm1_series(x: BigFloat, width: Int) raises -> BigFloat:
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

    Every step is a correctly rounded multiply and divide, so a term is off by
    at most a unit of the last place and the sum by at most one per term,
    which the caller's working width is chosen to absorb.
    """
    if x.is_zero():
        return BigFloat.zero(width, x.sign)
    var term = BigFloat.from_rounded_parts(
        x.significand, x.exponent, width, x.sign
    )
    var total = term.copy()
    var index = 2
    while True:
        term = bigfloat_arithmetics.divide(
            bigfloat_arithmetics.multiply(term, x, width),
            BigFloat.from_int(index, width),
            width,
        )
        if term.is_zero():
            return total^
        # A term below the last place of the sum cannot move it, and every
        # term after it is smaller again.
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
        index += 1


def _atanh_series(x: BigFloat, width: Int) raises -> BigFloat:
    """`atanh(x)` for `|x| < 1/2`, as a sum of its terms.

    Args:
        x: The argument.
        width: The bits to work in.

    Returns:
        The sum, within a couple of units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The series is `x + x^3/3 + x^5/5 + ...`. The running power of `x^2` is
    kept apart from the division by the odd number, as in the constants, so
    that the two errors do not compound.
    """
    if x.is_zero():
        return BigFloat.zero(width, x.sign)
    var square = bigfloat_arithmetics.multiply(x, x, width)
    var power = BigFloat.from_rounded_parts(
        x.significand, x.exponent, width, x.sign
    )
    var total = power.copy()
    var index = 3
    while True:
        power = bigfloat_arithmetics.multiply(power, square, width)
        if power.is_zero():
            return total^
        var term = bigfloat_arithmetics.divide(
            power, BigFloat.from_int(index, width), width
        )
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


def _exp_kernel(x: BigFloat, width: Int) raises -> BigFloat:
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

    if compare_absolute(x, _power_of_two(_EXPONENT_LIMIT_BITS)) >= 0:
        raise OverflowError(
            message=(
                "The exponent of exp() of this argument would not fit in an"
                " Int."
            ),
            function="exp()",
        )

    # `k` only has to be an integer near `x / ln 2`; being one out costs a
    # term of the series and nothing else, so a narrow logarithm will do.
    var k = _truncated_to_int(
        bigfloat_arithmetics.divide(x, ln2(64), 64, RoundingMode.ROUND_DOWN)
    )
    var scale = (
        width + Int(bit_width(UInt(width))) + Int(bit_width(UInt(abs(k)))) + 12
    )
    var logarithm = ln2(scale)
    var reduced = x.copy()
    if k != 0:
        reduced = bigfloat_arithmetics.subtract(
            x,
            bigfloat_arithmetics.multiply(
                BigFloat.from_int(k, scale), logarithm, scale
            ),
            scale,
        )

    var series = _expm1_series(reduced, scale)
    var total = bigfloat_arithmetics.add(
        BigFloat.from_int(1, scale), series, scale
    )
    if k != 0:
        total = bigfloat_arithmetics.multiply(total, _power_of_two(k), scale)
    return BigFloat.from_rounded_parts(
        total.significand, total.exponent, width, total.sign
    )


def _ln_kernel(x: BigFloat, width: Int) raises -> BigFloat:
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

    var scale = width + Int(bit_width(UInt(width))) + 12
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

    var one = BigFloat.from_int(1, scale)
    var ratio = bigfloat_arithmetics.divide(
        bigfloat_arithmetics.subtract(mantissa, one, scale),
        bigfloat_arithmetics.add(mantissa, one, scale),
        scale,
    )
    var total = bigfloat_arithmetics.multiply(
        _atanh_series(ratio, scale), _power_of_two(1), scale
    )
    if not whole_binades.is_zero():
        total = bigfloat_arithmetics.add(
            bigfloat_arithmetics.multiply(
                BigFloat.from_bigint(whole_binades, scale), ln2(scale), scale
            ),
            total,
            scale,
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
            which an argument at `2^62` already asks for.
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
    if (
        x.is_finite()
        and not x.is_zero()
        and compare_absolute(x, _power_of_two(-(precision + 4))) < 0
    ):
        return bigfloat_arithmetics.add(
            BigFloat.from_int(1, precision), x, precision, rounding_mode
        )

    return round_by_deciding_at[_exp_kernel, _EXP_SLACK](
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
    return round_by_deciding_at[_ln_kernel, _LN_SLACK](
        x, precision, rounding_mode
    )
