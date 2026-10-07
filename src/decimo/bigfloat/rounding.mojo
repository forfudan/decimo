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


"""Rounding a binary significand to a precision in bits.

Every arithmetic operation on a `BigFloat` ends here: it computes an exact
result, or an exact result plus the knowledge that something was discarded
below it, and this decides the last bit. The seven rounding modes are
decimo's own, the same ones the decimal types take.

The contract both ways is `(magnitude, exponent)` with the value being
`magnitude * 2^exponent`, and a magnitude that comes back holding exactly
`precision` bits unless it is zero.
"""

from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import test_bit, trailing_zeros
from decimo.errors import ValueError
from decimo.rounding_mode import RoundingMode


def round_to_precision(
    magnitude: BigInt,
    exponent: Int,
    precision: Int,
    negative: Bool,
    rounding_mode: RoundingMode,
    inexact_below: Bool = False,
) raises -> Tuple[BigInt, Int]:
    """Rounds `magnitude * 2^exponent` to `precision` significant bits.

    Args:
        magnitude: The significand, which must not be negative.
        exponent: The power of two the significand is scaled by.
        precision: How many bits the result keeps. Must be positive.
        negative: The sign of the value, which the directed modes need and
            the magnitude does not carry.
        rounding_mode: Which way to round.
        inexact_below: Whether something non-zero was already discarded below
            `magnitude`, as a conversion from decimal discards a remainder.
            It only ever makes the result rounder, never the other way.

    Returns:
        A normalized `(magnitude, exponent)`: the magnitude holds exactly
        `precision` bits, with its top bit set, or is zero.

    Raises:
        ValueError: If `precision` is not positive or `magnitude` is negative.
        Error: Propagated from the arithmetic.

    Notes:

    A significand with fewer bits than asked for is shifted up rather than
    left short, so that "exactly `precision` bits" holds for every finite
    non-zero value and nothing downstream has to ask how many bits are really
    there. The shift is exact; only the other direction rounds.

    Rounding reads two things about what is dropped: the leading dropped bit,
    and whether anything below that is set. The seven modes are then what
    they say they are, with the directed three reading the sign:

    - `DOWN` keeps the truncation, `UP` takes the next value up whenever
      anything was dropped at all.
    - `CEILING` rounds up for a positive value and truncates a negative one;
      `FLOOR` is its mirror.
    - `HALF_UP` goes up from a half, `HALF_DOWN` goes down from it, and
      `HALF_EVEN` goes up from a half only when the bit it would leave is
      odd.

    An increment can carry past the top -- `0b111` becoming `0b1000` -- and
    that is the one case where the exponent moves on the way out.
    """
    if precision <= 0:
        raise ValueError(
            message="A precision must be at least one bit.",
            function="round_to_precision()",
        )
    if magnitude.sign:
        raise ValueError(
            message="A significand cannot be negative.",
            function="round_to_precision()",
        )

    if magnitude.is_zero():
        if inexact_below:
            # Everything the value had sat below what was kept, so it is the
            # smallest step away from zero in the direction the mode allows.
            if _rounds_away_from_zero(rounding_mode, negative, True, True):
                return (BigInt.one() << (precision - 1), exponent)
        return (BigInt.zero(), 0)

    var bits = magnitude.bit_length()

    if bits <= precision:
        # Exact: shift into the normalized form and move the exponent to
        # match. `inexact_below` cannot reach the kept bits here, but it still
        # decides whether the value is on a boundary for a later rounding, so
        # a caller that cares passes it down rather than relying on this.
        var shift = precision - bits
        return (magnitude << shift, exponent - shift)

    var dropped = bits - precision
    var kept = magnitude >> dropped
    var leading_dropped = test_bit(magnitude, dropped - 1)
    var rest_below = inexact_below
    if not rest_below and dropped >= 2:
        # Anything set below the leading dropped bit makes the remainder more
        # than a half. The lowest set bit says it in one comparison.
        var lowest = trailing_zeros(magnitude)
        rest_below = lowest < dropped - 1

    if _rounds_away_from_zero(
        rounding_mode, negative, leading_dropped, rest_below, test_bit(kept, 0)
    ):
        kept = kept + BigInt.one()
        if kept.bit_length() > precision:
            # `0b111 + 1` is `0b1000`: one bit wider, and exactly a power of
            # two, so the shift is exact and the exponent takes the carry.
            kept = kept >> 1
            return (kept^, exponent + dropped + 1)

    return (kept^, exponent + dropped)


def _rounds_away_from_zero(
    rounding_mode: RoundingMode,
    negative: Bool,
    leading_dropped: Bool,
    rest_below: Bool,
    lowest_kept: Bool = False,
) raises -> Bool:
    """Decides whether what was dropped rounds the kept part up.

    Args:
        rounding_mode: Which way to round.
        negative: The sign of the value.
        leading_dropped: The most significant dropped bit, which is the half.
        rest_below: Whether anything below that bit is set.
        lowest_kept: The last bit that survives, which only `HALF_EVEN` reads.

    Returns:
        Whether to add one to the kept significand.

    Raises:
        Error: Never, but the signature matches its callers.
    """
    var any_dropped = leading_dropped or rest_below
    if not any_dropped:
        return False

    if rounding_mode == RoundingMode.ROUND_DOWN:
        return False
    if rounding_mode == RoundingMode.ROUND_UP:
        return True
    if rounding_mode == RoundingMode.ROUND_CEILING:
        return not negative
    if rounding_mode == RoundingMode.ROUND_FLOOR:
        return negative
    if rounding_mode == RoundingMode.ROUND_HALF_UP:
        return leading_dropped
    if rounding_mode == RoundingMode.ROUND_HALF_DOWN:
        return leading_dropped and rest_below
    # ROUND_HALF_EVEN
    return leading_dropped and (rest_below or lowest_kept)
