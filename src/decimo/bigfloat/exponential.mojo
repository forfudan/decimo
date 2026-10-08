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


"""The square root of a binary float.

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
