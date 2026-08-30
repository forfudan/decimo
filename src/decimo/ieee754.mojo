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
# The IEEE 754 decimal128 interchange format
#
# ===----------------------------------------------------------------------=== #

"""Reads and writes the IEEE 754 decimal128 interchange format.

This is a codec and nothing else: sixteen bytes in, a sign, a coefficient and
an exponent out, and back. It does not bring IEEE arithmetic with it, and it
knows nothing about `Decimal128` or `BigDecimal` -- both hand it the three
numbers they already hold.

The format is a sign, a 34-digit coefficient and an exponent from -6176 to
6111, written in the binary integer decimal encoding: the coefficient is one
plain binary integer rather than the packed declets of the other encoding.
That is what MongoDB's BSON `decimal128` and Intel's library use. IBM's
hardware and `decNumber` use densely packed decimal, which this module does
not read; it is a different arrangement of the same numbers, not a different
set of them.

A `Decimal128` always fits: 29 digits and a scale of at most 28 sit well
inside 34 digits and the exponent range. Coming the other way needs rounding,
and can be out of range entirely, so the conversion is allowed to fail.
"""

from std.builtin.simd import SIMD

from decimo.errors import OverflowError, ValueError


comptime DECIMAL128_PRECISION = 34
"""Digits a decimal128 coefficient holds."""


comptime DECIMAL128_BIAS = 6176
"""What is added to the exponent before it is written."""


comptime DECIMAL128_MAX_BIASED_EXPONENT = 12287
"""The largest exponent field, which is 14 bits less one value."""


comptime DECIMAL128_MAX_EXPONENT = 6111
"""The largest exponent, which is `DECIMAL128_MAX_BIASED_EXPONENT - BIAS`."""


comptime DECIMAL128_MIN_EXPONENT = -6176
"""The smallest exponent, which is `-BIAS`."""


comptime DECIMAL128_MAX_COEFFICIENT = UInt128(10) ** 34 - UInt128(1)
"""The largest coefficient, `10^34 - 1`.

It is below `2^113`, which is why an encoder never needs the second of the
two coefficient layouts: every canonical coefficient fits in the 113 bits the
first one gives it.

The second layout begins the coefficient with an implied `100`, so the
smallest value it can express is `2^113`, which is `1.038E+34` -- larger than
any coefficient decimal128 allows. Every value written that way is therefore
non-canonical, and the standard says a non-canonical coefficient reads as
zero. A decoder still has to recognise the layout to answer zero rather than
nonsense; the wider formats, where the same layout is ordinary, are not this
module's concern.
"""


comptime _COEFFICIENT_MASK = (UInt128(1) << 113) - UInt128(1)
comptime _LARGE_COEFFICIENT_MASK = (UInt128(1) << 111) - UInt128(1)
comptime _LARGE_COEFFICIENT_PREFIX = UInt128(1) << 113
comptime _EXPONENT_MASK = UInt128(0x3FFF)


def encode_decimal128(
    sign: Bool, coefficient: UInt128, exponent: Int
) raises -> UInt128:
    """Writes a number as a decimal128.

    Args:
        sign: True when the number is negative.
        coefficient: The digits, at most `10^34 - 1`.
        exponent: The power of ten they are multiplied by, from -6176 to
            6111.

    Returns:
        The sixteen bytes, as one integer.

    Raises:
        ValueError: If the coefficient has more than 34 digits or the
            exponent is outside what the format holds.

    Notes:
        Nothing is rounded here. The caller says which member of the cohort
        it wants written -- `1E+1` and `10` are different sixteen bytes and
        the same number -- and this writes that one.
    """
    if coefficient > DECIMAL128_MAX_COEFFICIENT:
        raise ValueError(
            message=(
                "The coefficient has more than 34 digits, which decimal128"
                " does not hold."
            ),
            function="encode_decimal128()",
        )
    if exponent < DECIMAL128_MIN_EXPONENT or exponent > DECIMAL128_MAX_EXPONENT:
        raise ValueError(
            message=(
                "The exponent is outside the range decimal128 holds, which is"
                " -6176 to 6111."
            ),
            function="encode_decimal128()",
        )

    var biased = UInt128(exponent + DECIMAL128_BIAS)
    var bits = (biased << 113) | coefficient
    if sign:
        bits |= UInt128(1) << 127
    return bits


def decode_decimal128(bits: UInt128) raises -> Tuple[Bool, UInt128, Int]:
    """Reads a decimal128 as a sign, a coefficient and an exponent.

    Args:
        bits: The sixteen bytes, as one integer.

    Returns:
        Whether the number is negative, its digits, and the power of ten they
        are multiplied by.

    Raises:
        ValueError: If the bytes hold an infinity or a NaN, which neither
            `Decimal128` nor `BigDecimal` has anywhere to put. Ask
            `decimal128_is_infinity` or `decimal128_is_nan` first when the
            source may contain them.

    Notes:
        A coefficient too large to be one -- which the second layout can
        write and no canonical value uses -- reads as zero, as the standard
        says it must.
    """
    if decimal128_is_infinity(bits):
        raise ValueError(
            message="The value is an infinity, which decimo does not hold.",
            function="decode_decimal128()",
        )
    if decimal128_is_nan(bits):
        raise ValueError(
            message="The value is a NaN, which decimo does not hold.",
            function="decode_decimal128()",
        )

    var sign = (bits >> 127) & UInt128(1) == UInt128(1)
    var biased: UInt128
    var coefficient: UInt128
    if (bits >> 125) & UInt128(3) == UInt128(3):
        # The second layout: the exponent sits two bits lower and the
        # coefficient begins with an implied `100`.
        biased = (bits >> 111) & _EXPONENT_MASK
        coefficient = _LARGE_COEFFICIENT_PREFIX | (
            bits & _LARGE_COEFFICIENT_MASK
        )
    else:
        biased = (bits >> 113) & _EXPONENT_MASK
        coefficient = bits & _COEFFICIENT_MASK

    if coefficient > DECIMAL128_MAX_COEFFICIENT:
        coefficient = UInt128(0)

    return (sign, coefficient, Int(biased) - DECIMAL128_BIAS)


def decimal128_is_infinity(bits: UInt128) -> Bool:
    """Returns whether the bytes hold an infinity.

    Args:
        bits: The sixteen bytes, as one integer.

    Returns:
        True for either infinity.
    """
    return (bits >> 122) & UInt128(0x1F) == UInt128(0x1E)


def decimal128_is_nan(bits: UInt128) -> Bool:
    """Returns whether the bytes hold a NaN.

    Args:
        bits: The sixteen bytes, as one integer.

    Returns:
        True for a NaN of either kind.
    """
    return (bits >> 122) & UInt128(0x1F) == UInt128(0x1F)


def decimal128_is_signaling_nan(bits: UInt128) -> Bool:
    """Returns whether the bytes hold a signalling NaN.

    Args:
        bits: The sixteen bytes, as one integer.

    Returns:
        True for a signalling NaN.
    """
    return decimal128_is_nan(bits) and (bits >> 121) & UInt128(1) == UInt128(1)


def decimal128_is_finite(bits: UInt128) -> Bool:
    """Returns whether the bytes hold a number.

    Args:
        bits: The sixteen bytes, as one integer.

    Returns:
        True unless the value is an infinity or a NaN.
    """
    return (bits >> 122) & UInt128(0x1E) != UInt128(0x1E)


def decimal128_infinity(sign: Bool = False) -> UInt128:
    """Returns the bytes for an infinity.

    Args:
        sign: True for negative infinity.

    Returns:
        The sixteen bytes, as one integer.
    """
    var bits = UInt128(0x1E) << 122
    if sign:
        bits |= UInt128(1) << 127
    return bits


def decimal128_quiet_nan(sign: Bool = False) -> UInt128:
    """Returns the bytes for a quiet NaN.

    Args:
        sign: True for the sign bit set, which a NaN may carry.

    Returns:
        The sixteen bytes, as one integer.
    """
    var bits = UInt128(0x1F) << 122
    if sign:
        bits |= UInt128(1) << 127
    return bits


def decimal128_to_bytes[
    little_endian: Bool = True
](bits: UInt128) -> InlineArray[UInt8, 16]:
    """Returns a decimal128 as sixteen bytes.

    Parameters:
        little_endian: The byte order. BSON and Intel's library store these
            little-endian, which is the default.

    Args:
        bits: The value, as one integer.

    Returns:
        The bytes.
    """
    var result = InlineArray[UInt8, 16](uninitialized=True)
    for index in range(16):
        var byte = UInt8((bits >> UInt128(8 * index)) & UInt128(0xFF))
        result[index if little_endian else 15 - index] = byte
    return result^


def decimal128_from_bytes[
    little_endian: Bool = True
](bytes: InlineArray[UInt8, 16]) -> UInt128:
    """Returns sixteen bytes as a decimal128.

    Parameters:
        little_endian: The byte order the bytes are in.

    Args:
        bytes: The bytes.

    Returns:
        The value, as one integer.
    """
    var bits = UInt128(0)
    for index in range(16):
        var byte = bytes[index if little_endian else 15 - index]
        bits |= UInt128(byte) << UInt128(8 * index)
    return bits
