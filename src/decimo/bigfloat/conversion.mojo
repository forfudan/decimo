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


"""Between a binary float and decimal.

One direction is exact and the other is not, which is the whole asymmetry of
the pair. Every binary float has an exact decimal expansion -- `2^-n` is
`5^n / 10^n` -- so going out loses nothing and only the number of digits is a
choice. Coming in, almost no decimal is a binary float, so the conversion
rounds, and rounding correctly means computing more bits than are kept and
handing the rest to `round_to_precision()` as the remainder it is.
"""

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigfloat.rounding import round_to_precision
from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import trailing_zeros
from decimo.biguint.biguint import BigUInt
from decimo.errors import ValueError
from decimo.rounding_mode import RoundingMode


def from_decimal_parts(
    magnitude: BigInt,
    decimal_exponent: Int,
    precision: Int,
    negative: Bool,
    rounding_mode: RoundingMode,
) raises -> Tuple[BigInt, Int]:
    """Rounds `magnitude * 10^decimal_exponent` to a binary significand.

    Args:
        magnitude: The decimal digits as an integer, never negative.
        decimal_exponent: The power of ten they are scaled by.
        precision: How many bits to keep.
        negative: The sign, which the directed rounding modes read.
        rounding_mode: Which way to round.

    Returns:
        A normalized `(significand, binary_exponent)` pair, as
        `round_to_precision()` returns.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    A non-negative power of ten is exact: the product is an integer and the
    only rounding is the one that fits it to the precision.

    A negative power is a division, and this is where the care goes. The
    quotient is taken with enough bits below the precision for the rounding
    to have something to read, and the division's own remainder says whether
    anything is left under them. That remainder is the sticky bit: without it
    a quotient that stops just short of a half is indistinguishable from one
    that sits exactly on it, and half the modes would answer differently.

    The shift is chosen rather than guessed, and then checked: `10^k` is below
    `2^(4k)`, so `4k` bits recover what the division consumes, and the
    precision plus two more give the rounding its room. If the quotient still
    comes back too narrow -- a magnitude far smaller than the power of ten can
    do that -- the shift grows and the division is taken again, which is the
    one loop here and runs at most twice in practice.
    """
    if precision <= 0:
        raise ValueError(
            message="A precision must be at least one bit.",
            function="from_decimal_parts()",
        )
    if magnitude.is_zero():
        return (BigInt.zero(), 0)

    if decimal_exponent >= 0:
        var exact = magnitude * BigInt.from_biguint(
            BigUInt.power_of_10(decimal_exponent)
        )
        return round_to_precision(exact, 0, precision, negative, rounding_mode)

    var power = BigInt.from_biguint(BigUInt.power_of_10(-decimal_exponent))
    var shift = 4 * (-decimal_exponent) + precision + 2
    while True:
        var scaled = magnitude << shift
        var quotient = scaled.truncate_divide(power)
        if quotient.bit_length() > precision:
            var remainder = scaled - quotient * power
            return round_to_precision(
                quotient,
                -shift,
                precision,
                negative,
                rounding_mode,
                not remainder.is_zero(),
            )
        shift += precision + 64


def to_exact_bigdecimal(
    significand: BigInt, binary_exponent: Int, negative: Bool
) raises -> BigDecimal:
    """Returns `significand * 2^binary_exponent` as an exact decimal.

    Args:
        significand: The significand, never negative.
        binary_exponent: The power of two it is scaled by.
        negative: Whether the value is negative.

    Returns:
        The same value, exactly, as a `BigDecimal`.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Nothing is lost going this way, and nothing has to be chosen either.
    A negative power of two is a power of five over a power of ten:

        m * 2^-k = m * 5^k / 10^k

    so the coefficient is `m * 5^k` and the scale is `k`. The digits can run
    long -- the smallest double needs 1074 decimal places -- but they are all
    real.

    The scale that comes out is the smallest one that holds the value. A
    significand normalized to the precision carries factors of two, and each
    one pairs with a five to make a ten that the scale would otherwise count
    twice: the smallest double is held as `2^52 * 2^-1126`, which would give
    a scale of 1126 and fifty-two trailing zeros. The factors of two are
    exactly the significand's trailing zero bits, so one division removes
    them all rather than fifty-two.
    """
    if significand.is_zero():
        return BigDecimal(BigUInt.zero(), 0, negative)

    if binary_exponent >= 0:
        var integral = (significand << binary_exponent).to_biguint()
        return BigDecimal(integral^, 0, negative)

    var scale = -binary_exponent
    var twos = trailing_zeros(significand)
    var shared = twos if twos < scale else scale
    var magnitude = (significand >> shared).to_biguint()
    var five_power = BigUInt(5).power(scale - shared)
    var coefficient = magnitude * five_power
    return BigDecimal(coefficient^, scale - shared, negative)
