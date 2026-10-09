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


"""The square root of a binary float, and the loop that decides a rounding.

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

from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.rounding import checked_precision
from decimo.bigint.bigint import BigInt
from decimo.bigint.exponential import sqrt_rem
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
