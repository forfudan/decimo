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

from std.bit import bit_width

from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import test_bit, trailing_zeros
from decimo.errors import OverflowError, ValueError
from decimo.rounding_mode import RoundingMode


comptime MAX_PRECISION: Int = Int.MAX // 4
"""The widest precision this layer accepts.

Every operation adds guard bits before it rounds -- two for an addition, a
few more for a division, twice the width for a square root -- and a precision
near `Int.MAX` makes those additions wrap, which turns a value too large to
allocate into a loop that cannot finish. A quarter of `Int.MAX` leaves room
for all of them.

The bound is arithmetic and not a judgement about memory: a significand this
wide is `2^58` bytes, so nothing reaches it. It is here so that an absurd
precision is refused in one line rather than discovered as a hang.
"""


def checked_precision(precision: Int, function: String) raises -> Int:
    """Returns `precision`, or refuses it.

    Args:
        precision: The number of bits asked for.
        function: The caller, for the message.

    Returns:
        The precision, unchanged.

    Raises:
        ValueError: If it is not positive, or above `MAX_PRECISION`.
    """
    if precision <= 0:
        raise ValueError(
            message="A precision must be at least one bit.",
            function=function,
        )
    if precision > MAX_PRECISION:
        raise ValueError(
            message=(
                "A precision must leave room for the guard bits an operation"
                " adds, so it cannot be above a quarter of Int.MAX."
            ),
            function=function,
        )
    return precision


def _lowered(exponent: Int, by: Int) raises -> Int:
    """`exponent - by` for a non-negative `by`, refusing to wrap.

    Args:
        exponent: The exponent to lower.
        by: How far to lower it, never negative.

    Returns:
        The lowered exponent.

    Raises:
        OverflowError: If the result is below `Int.MIN`.

    Notes:

    Widening a significand to the precision asked for lowers the exponent by
    the same amount, and a value already at the bottom of the range has
    nowhere to go. Wrapping round would answer with the largest exponent
    there is, so the answer is a refusal instead.
    """
    if exponent < Int.MIN + by:
        raise OverflowError(
            message=(
                "Normalizing to this precision needs an exponent below what"
                " an Int holds."
            ),
            function="round_to_precision()",
        )
    return exponent - by


def _raised(exponent: Int, by: Int) raises -> Int:
    """`exponent + by` for a non-negative `by`, refusing to wrap.

    Args:
        exponent: The exponent to raise.
        by: How far to raise it, never negative.

    Returns:
        The raised exponent.

    Raises:
        OverflowError: If the result is above `Int.MAX`.

    Notes:

    Dropping bits raises the exponent by the number dropped, and an
    increment that carries past the top raises it once more. Two values at
    the top of the range sum to one whose exponent is a step above it, and a
    step above the top is a refusal rather than the bottom.
    """
    if exponent > Int.MAX - by:
        raise OverflowError(
            message=(
                "Normalizing to this precision needs an exponent above what"
                " an Int holds."
            ),
            function="round_to_precision()",
        )
    return exponent + by


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
            Only meaningful when the magnitude has more bits than `precision`,
            since the flag says where the discarded part sits relative to the
            bits being dropped and nothing else; passing it without those
            guard bits is refused.

    Returns:
        A normalized `(magnitude, exponent)`: the magnitude holds exactly
        `precision` bits, with its top bit set, or is zero.

    Raises:
        ValueError: If `precision` is not positive, if `magnitude` is
            negative, or if `inexact_below` is set while the magnitude has no
            bits to drop.
        OverflowError: If normalizing to `precision` needs an exponent
            outside `Int`. Widening lowers the exponent and dropping bits
            raises it, so a value at either end of the range can be asked
            for one a step beyond it.
        Error: Propagated from the arithmetic.

    Notes:

    A significand with fewer bits than asked for is shifted up rather than
    left short, so that "exactly `precision` bits" holds for every finite
    non-zero value and nothing downstream has to ask how many bits are really
    there. The shift is exact; only the other direction rounds.

    A caller with something still to discard must hand over the bits to drop
    along with it. `inexact_below` says only that the remainder is non-zero,
    which places it below the lowest dropped bit; without a dropped bit there
    is nothing to place it under, and the flag cannot say whether the value is
    a hair above the significand or most of the way to the next one. A
    conversion from decimal has those bits by construction: it computes a
    couple more than it keeps and then rounds here.

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
    _ = checked_precision(precision, "round_to_precision()")
    if magnitude.sign:
        raise ValueError(
            message="A significand cannot be negative.",
            function="round_to_precision()",
        )

    var bits = magnitude.bit_length()
    if inexact_below and bits <= precision:
        raise ValueError(
            message=(
                "A discarded remainder needs the bits it was discarded below:"
                " supply a magnitude wider than the precision."
            ),
            function="round_to_precision()",
        )

    if magnitude.is_zero():
        return (BigInt.zero(), 0)

    if bits <= precision:
        # Exact: shift into the normalized form and move the exponent to
        # match. `inexact_below` cannot reach the kept bits here, but it still
        # decides whether the value is on a boundary for a later rounding, so
        # a caller that cares passes it down rather than relying on this.
        var shift = precision - bits
        return (magnitude << shift, _lowered(exponent, shift))

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
            return (kept^, _raised(exponent, dropped + 1))

    return (kept^, _raised(exponent, dropped))


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


# ===----------------------------------------------------------------------=== #
# Values beside a value
# ===----------------------------------------------------------------------=== #
#
# Several functions have an argument so small that their answer is the
# argument moved a hair to one side -- the sine toward zero, the tangent
# away from it -- and the move cannot be computed, only placed. These are
# what place it, and they are here rather than in one of the function
# modules because three of them need the same ones.


def working_width(width: Int) -> Int:
    """How many bits a kernel evaluates in to return `width` good ones.

    Args:
        width: The bits the kernel returns.

    Returns:
        The width plus a margin: a dozen bits, and one more for every
        doubling of the width.

    Notes:

    Every kernel in this layer widens by the same amount, and the amount has
    to grow with the width because the number of roundings does. A series of
    `n` terms, a reduction that squares `log(n)` times, a quotient of two
    logarithms -- each costs a few units of the last place of the width it
    works in, and `bit_width(width)` bits covers a count of them that grows
    with the width while the dozen covers the handful that does not.

    The constants widen by a little less, because their series are summed in
    integers and not in rounded floats; `constants._series_scale()` says so
    where it differs.
    """
    return width + Int(bit_width(UInt(width))) + 12


def fixed_point_scale(x: BigFloat, width: Int) -> Int:
    """The power of two to scale a series on `x` by, for `width` good bits.

    Args:
        x: The argument the series runs on, finite and not nought.
        width: The bits the sum has to be good to.

    Returns:
        A `scale` such that `|x| * 2^scale` has `width` bits and a dozen more.

    Notes:

    A series summed in fixed-point integers is quicker than the same series
    summed in correctly rounded floats by an order of magnitude, because a
    term costs one shift and one division by a small integer rather than a
    multiply, a divide and an addition that each allocate and round. The
    constants have always been summed this way; this is what lets the
    functions be.

    What a fixed point cannot do is hold a value of unknown size: a scale
    fixed in advance would leave a tiny `x` with nothing but leading noughts.
    So the scale is taken from `x` itself, measured down from its leading bit,
    and the sum is as good relative to its own first term whether that term is
    near one or near nothing.
    """
    # The leading bit sits at `exponent + precision - 1`.
    return working_width(width) - x.exponent - x.precision


def square_fixed_point_scale(x: BigFloat, width: Int) -> Int:
    """The same, for a series whose first term is of the order of `x^2`.

    Args:
        x: The argument the series runs on, finite and not nought.
        width: The bits the sum has to be good to.

    Returns:
        A `scale` such that `x^2 * 2^scale` has `width` bits and a dozen more.

    Notes:

    The cosine's series starts at `x^2/2`, not at `x`, so its fixed point has
    to be measured down from there. Measured down from `x` instead, a small
    argument would leave the sum good only in its own leading bits, and what
    this series is for is exactly the tiny amount by which the cosine falls
    short of one.
    """
    # `x^2` lies in `[2^2L, 2^(2L+2))` for a leading bit at `L`, so this is
    # within a bit of its leading bit, and a bit is what the margin is for.
    return working_width(width) - 2 * (x.exponent + x.precision - 1)


def to_fixed_point(x: BigFloat, scale: Int) -> BigInt:
    """The magnitude of `x` as an integer scaled by `2^scale`, truncated.

    Args:
        x: A finite value.
        scale: The power of two to scale by, from `fixed_point_scale()`.

    Returns:
        `|x| * 2^scale`, rounded toward zero, which is exact at the scale that
        function returns.
    """
    var shift = scale + x.exponent
    if shift >= 0:
        return x.significand << shift
    return x.significand >> -shift


def square_to_fixed_point(x: BigFloat, scale: Int) -> BigInt:
    """`x^2` as an integer scaled by `2^scale`, truncated.

    Args:
        x: A finite value.
        scale: The power of two to scale by.

    Returns:
        `x^2 * 2^scale`, rounded toward zero. The square of the significand is
        formed exactly, so this loses only what the scale itself cannot hold,
        rather than the unit of the last place a rounded multiply would.
    """
    var shift = scale + 2 * x.exponent
    var square = x.significand * x.significand
    if shift >= 0:
        return square << shift
    return square >> -shift


def from_fixed_point(
    total: BigInt, scale: Int, width: Int, negative: Bool
) raises -> BigFloat:
    """A fixed-point integer as a float of `width` bits.

    Args:
        total: The magnitude, scaled by `2^scale`, never negative.
        scale: The power of two it was scaled by.
        width: The bits the answer keeps.
        negative: The sign to give it.

    Returns:
        The value, normalized and rounded half to even.

    Raises:
        Error: Propagated from the rounding.
    """
    if total.is_zero():
        return BigFloat.zero(width, negative)
    return BigFloat.from_rounded_parts(total, -scale, width, negative)


def leading_bit_position(x: BigFloat) raises -> BigInt:
    """Where the top bit of a finite non-zero value sits.

    Args:
        x: The value.

    Returns:
        `exponent + precision - 1`, as a `BigInt` because that sum can leave
        an `Int` while the value itself is ordinary.

    Raises:
        Error: Propagated from the arithmetic.
    """
    return BigInt(x.exponent) + BigInt(x.precision) - BigInt.one()


def cubic_term_is_below_a_guard_unit(x: BigFloat, guard: Int) raises -> Bool:
    """Whether `x^3` is small enough for a guard unit to stand in for it.

    Args:
        x: The argument, finite and not zero.
        guard: How many guard bits the rounding will be given.

    Returns:
        True when the cubic correction is below one guard unit of `x`, which
        is what makes moving `x` by a guard unit land on the same side of
        every rounding boundary as the true value does.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The test is on the leading bits, in a `BigInt` because those positions
    can be far outside an `Int`. With `L` the leading bit's position,
    `|x^3/3|` is below `2^(3L+2)` and a guard unit is `2^(L - p + 1 - g)`
    for a significand of `p` bits, so the condition is

        2L < -p - g - 1

    which is a real restriction and not a formality: at one bit of
    destination and `x = 3065/32768`, the cubic term is nine times `x`'s own
    last place, and the earlier gate -- `|x|` below `2^-((precision+4)/2)` --
    let it through. The tangent then answered `1/16` where the truth is above
    the midpoint and the answer is `1/8`.
    """
    var leading = leading_bit_position(x)
    return (leading + leading) < BigInt(-(x.precision + guard + 1))


def guard_bits(x: BigFloat, precision: Int) -> Int:
    """How many bits to widen `x` by before rounding it to `precision`.

    Args:
        x: The value.
        precision: The bits the answer keeps.

    Returns:
        At least two, and enough that the widened significand has more bits
        than the answer keeps, which is what the rounding needs to read a
        discarded remainder.
    """
    var guard = 2
    if precision + 2 - x.precision > guard:
        guard = precision + 2 - x.precision
    return guard


def rounded_beside(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode,
    toward_zero: Bool,
) raises -> BigFloat:
    """Rounds the value a hair to one side of `x`, by one guard unit.

    Args:
        x: The value the answer sits beside, finite and not zero.
        precision: The bits the answer keeps.
        rounding_mode: Which way to round.
        toward_zero: Whether the answer is below `x` in magnitude or above.

    Returns:
        `x` moved by less than a quarter of its own last place, rounded.

    Raises:
        OverflowError: If `x` sits so low in the exponent range that there is
            no room for the guard bits.
        Error: Propagated from the rounding.

    Notes:

    This is for an argument whose correction term is real but far too small
    to compute: `sin(x)` is `x - x^3/6` and the tangent is `x + x^3/3`, and
    at `x = 2^-100000` neither correction has an exponent an `Int` can hold.
    What the rounding needs is not the correction's size but its side, and
    one guard unit stands in for it exactly.

    Exactly, because a guard unit is at most a quarter of `x`'s own last
    place, while the distance from `x` to any rounding boundary it does not
    sit on is at least a whole one: so moving by a guard unit cannot cross a
    boundary that the true correction does not. And where `x` sits on a
    boundary -- a tie, or a value the destination holds exactly -- moving off
    it is the whole point, since the truth is not on it.

    An earlier version moved by `x * 2^-(precision+8)` instead, which is
    larger than the correction for a small `x` rather than smaller. At one
    bit of precision and `x = 3077/32768`, just above the midpoint `3/32`,
    that crossed the midpoint and answered `1/16` where the sine is above it
    and the answer is `1/8`.
    """
    var guard = guard_bits(x, precision)
    if x.exponent < Int.MIN + guard:
        raise OverflowError(
            message=(
                "This argument sits too low in the exponent range to leave"
                " room for the bits its rounding needs."
            ),
            function="rounded_beside()",
        )
    var magnitude = x.significand << guard
    if toward_zero:
        magnitude = magnitude - BigInt.one()
    return BigFloat.from_rounded_parts(
        magnitude,
        x.exponent - guard,
        precision,
        x.sign,
        rounding_mode,
        True,
    )
