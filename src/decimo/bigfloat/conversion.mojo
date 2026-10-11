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

from std.bit import bit_width

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigfloat.rounding import (
    checked_precision,
    round_to_precision,
    rounds_away_from_zero,
)
from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import test_bit, trailing_zeros
from decimo.biguint.biguint import BigUInt
from decimo.errors import OverflowError, ValueError
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

    Two ways there, chosen on what the power of ten would cost.
    `_from_decimal_exactly()` builds it whole, which is the quickest way
    while it is small -- and `10^1000` is small. `_from_decimal_by_scaling()`
    truncates it to a working width instead, which is the only way when the
    exponent has nineteen figures to play with. Both round once, from the
    exact value, so the choice shows in the time and nowhere else.
    """
    _ = checked_precision(precision, "from_decimal_parts()")
    if magnitude.is_zero():
        return (BigInt.zero(), 0)

    if decimal_exponent != 0 and not _power_is_worth_building(
        decimal_exponent, precision, 0
    ):
        return _from_decimal_by_scaling(
            magnitude, decimal_exponent, precision, negative, rounding_mode
        )
    return _from_decimal_exactly(
        magnitude, decimal_exponent, precision, negative, rounding_mode
    )


def _from_decimal_exactly(
    magnitude: BigInt,
    decimal_exponent: Int,
    precision: Int,
    negative: Bool,
    rounding_mode: RoundingMode,
) raises -> Tuple[BigInt, Int]:
    """Rounds `magnitude * 10^decimal_exponent` through the whole power.

    Args:
        magnitude: The decimal digits as an integer, never negative or
            nought.
        decimal_exponent: The power of ten they are scaled by.
        precision: How many bits to keep.
        negative: The sign, which the directed rounding modes read.
        rounding_mode: Which way to round.

    Returns:
        A normalized `(significand, binary_exponent)` pair, as
        `round_to_precision()` returns.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    A non-negative power of ten is exact: the product is an integer and the
    only rounding is the one that fits it to the precision.

    A negative power is a division, and this is where the care goes. Only
    part of it is a division: `10^-k` is `5^-k * 2^-k`, and the power of two
    is the exponent, so the divisor built here is `5^k` rather than `10^k` --
    two thirds of the bits, and the shift above it shrinks to match.

    The quotient is taken with enough bits below the precision for the
    rounding to have something to read, and the division's own remainder says
    whether anything is left under them. That remainder is the sticky bit:
    without it a quotient that stops just short of a half is indistinguishable
    from one that sits exactly on it, and half the modes would answer
    differently.

    The shift is chosen rather than guessed, and then checked: `5^k` is below
    `2^(7k/3)`, so that many bits recover what the division consumes, and the
    precision plus two more give the rounding its room. If the quotient still
    comes back too narrow -- a magnitude far smaller than the power can do
    that -- the shift grows and the division is taken again, which is the one
    loop here and runs at most twice in practice.
    """
    if decimal_exponent >= 0:
        var exact = magnitude * BigInt.from_biguint(
            BigUInt.power_of_10(decimal_exponent)
        )
        return round_to_precision(exact, 0, precision, negative, rounding_mode)

    var k = -decimal_exponent
    var power = BigInt.from_biguint(BigUInt(5).power(k))
    var shift = (7 * k + 2) // 3 + precision + 2
    while True:
        var scaled = magnitude << shift
        var quotient = scaled.truncate_divide(power)
        if quotient.bit_length() > precision:
            var remainder = scaled - quotient * power
            return round_to_precision(
                quotient,
                -shift - k,
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


# ===----------------------------------------------------------------------=== #
# The scaling both directions lean on
# ===----------------------------------------------------------------------=== #
#
# Each direction has a power of ten it cannot afford to build, and both get
# the same answer: a power of five truncated to a working width, a value
# carried in fixed point with a guard below the bits or digits kept, and a
# guard that doubles until the rounding no longer depends on what the
# truncation dropped. What follows is that machinery, with the two directions
# below it.


comptime _FIVE_POWER_SLACK = 4
"""Units in the last place the truncated power of five may be off by.

One truncation loses under a unit of the width it works in, and a squaring
doubles whatever relative error it is handed, so the kernel works `log2` of
the degree plus eight bits wide and the doubling eats the eight. What comes
back is a unit of the width asked for, and this is that with room to spare.
"""

comptime _FIXED_POINT_SLACK = 4
"""Units of the guard the scaled value may be off by.

The power of five carries `_FIVE_POWER_SLACK` units of its own width, which
the eight extra bits of the working width turn into a small fraction of a
guard unit, and the placement truncates once more for under a unit. Two
would do; this is four.
"""

comptime _INITIAL_GUARD = 32
"""Fractional bits the first attempt keeps below the digits.

Thirty-two decides every value whose digits do not crowd a boundary, which
is nearly all of them, and the loop doubles it when they do.
"""

comptime _EXPANSION_MARGIN = 4
"""When the exact expansion is this many times the scaling's working width,
the scaling is the cheaper way to the digits.

Below that the expansion wins, because it is one power of five and one
multiplication while the scaling is a power of five, a multiplication, a
change of base and the bookkeeping around them. Measured on a double at
seventeen digits: 243 nanoseconds for the expansion against 295 for the
scaling, and the other way about by a factor of nearly three once the
exponent reaches -1074. Four widths is where the two meet for every digit
count from one to three hundred, and the same test ends the Ziv loop, since
a loop that has widened that far has nothing left to win.
"""

comptime _UNREADABLE = -1
"""The fraction is too near a boundary for the truncation to be out of the way.
"""

comptime _BELOW_HALF = 0
"""The fraction does not reach the half of the last place kept."""

comptime _ABOVE_HALF = 1
"""The fraction reaches the half of the last place kept."""

comptime _NEITHER = 0
"""The scaled value is neither whole nor exactly a half."""

comptime _WHOLE = 1
"""The scaled value is a whole number, so nothing is dropped."""

comptime _HALF = 2
"""The scaled value is a whole number and exactly a half."""


def _added(left: Int, right: Int) raises -> Int:
    """`left + right`, refusing to wrap.

    Args:
        left: One addend.
        right: The other.

    Returns:
        The sum.

    Raises:
        OverflowError: If the sum is outside what an `Int` holds.

    Notes:

    The exponents here are the binary one, which fills the whole range, and
    the decimal shift, which is about seven tenths of it. Their sum is small
    -- that is the point of the pairing -- but the pieces are not, and a
    wrapped sum would answer a plausible wrong number instead of refusing.
    """
    if right > 0 and left > Int.MAX - right:
        raise OverflowError(
            message="This exponent is above what an Int holds.",
            function="the decimal conversion",
        )
    if right < 0 and left < Int.MIN - right:
        raise OverflowError(
            message="This exponent is below what an Int holds.",
            function="the decimal conversion",
        )
    return left + right


def _placed(value: BigInt, places: Int) -> BigInt:
    """`value * 2^places`, dropping the low bits when `places` is negative.

    Args:
        value: The value to place, never negative here.
        places: How far to move it, either way.

    Returns:
        The moved value, truncated toward nought when bits were dropped.
    """
    if places >= 0:
        return value << places
    return value >> (-places)


def _five_power_truncated(degree: Int, width: Int) raises -> Tuple[BigInt, Int]:
    """`5^degree` to `width` bits, as a magnitude and a power of two.

    Args:
        degree: The power, never negative.
        width: The bits the magnitude keeps.

    Returns:
        A `(magnitude, exponent)` pair whose `magnitude * 2^exponent` is
        within `_FIVE_POWER_SLACK` units of the last place of `5^degree`.

    Raises:
        OverflowError: If the exponent would not fit an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    Binary exponentiation, truncating at every step so the magnitudes stay
    the width asked for instead of growing to the two and a third bits per
    degree that an exact power takes. A squaring doubles the relative error
    it is handed, so the work is done `log2(degree) + 8` bits wider and the
    doubling spends the extra bits rather than the answer's.
    """
    # An exact power is the better answer when it fits the width: no
    # squarings, no truncation and no slack to carry. Seven thirds of the
    # degree is over the two and a third bits a power of five takes, and the
    # division rather than the multiplication keeps a degree of eighteen
    # figures from wrapping round into a yes.
    if degree <= width * 3 // 7:
        return (BigInt(5).power(degree), 0)

    var doublings = Int(bit_width(UInt(degree)))
    var work = width + doublings + 8
    var result = BigInt.one()
    var result_exponent = 0
    var base = BigInt(5)
    var base_exponent = 0
    var remaining = degree
    while remaining > 0:
        if remaining % 2 == 1:
            result = result * base
            result_exponent = _added(result_exponent, base_exponent)
            result_exponent = _added(result_exponent, _dropped(result, work))
        remaining //= 2
        if remaining > 0:
            base = base * base
            base_exponent = _added(base_exponent, base_exponent)
            base_exponent = _added(base_exponent, _dropped(base, work))
    result_exponent = _added(result_exponent, _dropped(result, width))
    return (result^, result_exponent)


def _dropped(mut value: BigInt, width: Int) -> Int:
    """Cuts `value` to `width` bits, returning how many bits went.

    Args:
        value: The value to cut, never negative here.
        width: The bits to keep.

    Returns:
        The bits dropped, which the caller adds to the exponent.
    """
    var excess = value.bit_length() - width
    if excess <= 0:
        return 0
    value = value >> excess
    return excess


def _where_the_rest_sits(rest: BigInt, guard: Int) raises -> Int:
    """Where a fraction sits against the boundaries that decide a rounding.

    Args:
        rest: The fraction, in units of `2^-guard`, so below `2^guard`.
        guard: The fractional bits it is written in.

    Returns:
        `_UNREADABLE` when the fraction is within `_FIXED_POINT_SLACK` of
        nought, of the half or of the whole unit, where the truncation could
        have put it on either side of the boundary; `_ABOVE_HALF` when it
        reaches the half and `_BELOW_HALF` when it does not.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Bit lengths, not comparisons with the half and the unit, because those
    two would have to be built -- `guard` bits of each -- and the lengths say
    the same thing. A fraction below `2^guard` reaches the half exactly when
    its length is `guard`, and it reaches the unit when the slack added to it
    does.
    """
    var slack = BigInt(_FIXED_POINT_SLACK)
    if rest < slack:
        return _UNREADABLE
    var raised = rest + slack
    if raised.bit_length() > guard:
        return _UNREADABLE
    if raised.bit_length() == guard and (rest - slack).bit_length() < guard:
        return _UNREADABLE
    return _ABOVE_HALF if rest.bit_length() == guard else _BELOW_HALF


def _scaled_to_fixed_point(
    significand: BigInt,
    binary_exponent: Int,
    decimal_shift: Int,
    integer_bits: Int,
    guard: Int,
) raises -> BigInt:
    """`significand * 2^binary_exponent * 10^decimal_shift` in fixed point.

    Args:
        significand: The significand, never negative.
        binary_exponent: The power of two it is scaled by.
        decimal_shift: The power of ten to scale it by, either sign.
        integer_bits: An upper bound on the bits the answer's whole part
            takes.
        guard: The fractional bits to keep below it.

    Returns:
        The value in units of `2^-guard`, within `_FIXED_POINT_SLACK` of
        them.

    Raises:
        OverflowError: If an exponent would not fit an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    The power of five is taken `integer_bits + guard + 8` bits wide, so its
    `_FIVE_POWER_SLACK` units of its own last place come to a small fraction
    of a guard unit once the answer is placed: a relative error of `2^-width`
    on a value below `2^integer_bits`, read in units of `2^-guard`, is
    `2^(integer_bits + guard - width)`, and the eight bits make that an
    eighth. Multiplying by the exact significand adds nothing, and the one
    truncation that places the answer adds under a unit.

    Dividing keeps the significand whole and moves the divisor instead. The
    power of five is never above the true one, so a quotient taken that way
    is never below the true value, and the two cases that must land on a
    whole number of guard units -- `_WHOLE` and `_HALF` -- then land on it
    exactly: the one truncation cannot reach the unit below, because the
    overshoot it would have to cancel is a fraction of one.
    """
    var width = integer_bits + guard + 8
    if decimal_shift >= 0:
        var power = _five_power_truncated(decimal_shift, width)
        var scaled = significand * power[0]
        var exponent = _added(_added(binary_exponent, decimal_shift), power[1])
        return _placed(scaled, _added(exponent, guard))
    var power = _five_power_truncated(-decimal_shift, width)
    var exponent = _added(_added(binary_exponent, decimal_shift), -power[1])
    var place = _added(exponent, guard)
    if place >= 0:
        return _placed(significand, place).truncate_divide(power[0])
    return significand.truncate_divide(_placed(power[0], -place))


# ===----------------------------------------------------------------------=== #
# A decimal in, without the whole power of ten
# ===----------------------------------------------------------------------=== #
#
# The way in has the same shape of problem as the way out and the same
# answer. `m * 10^d` rounded to `p` bits was taken by building `10^d` or
# `5^-d` whole, which costs what `d` is: `1e-100000` took eight milliseconds
# at 53 bits and `1e-1000000000` could not be parsed at all, though a
# `BigFloat` holds values far deeper than that.
#
# So the scaling is done in fixed point against a truncated power of five,
# with `p` bits above a guard and the guard doubling until the rounding is
# decided -- the same loop, the same kernel, the same widening.
#
# What the loop cannot settle is again the value that sits exactly on a
# boundary, and here the boundary is binary: the value is a float of `p` bits
# already, or exactly halfway between two of them. Neither reaches the loop.
# A deep positive `d` cannot: `m * 10^d` is `m * 5^d * 2^d`, and for it to
# stop inside `p` bits, or one bit past them, `5^d` has to fit in `p` bits,
# which puts `d` below half the precision -- and a `d` that small is one the
# whole power of ten is quicker for anyway. A negative `d` can, and only when
# `5^-d` divides the magnitude, which asks for a power of five no bigger than
# the magnitude itself; that division is taken, and what it does not divide
# is on no boundary at all.


comptime _POWER_LIMIT_UP = 512
"""How deep a positive decimal exponent is still worth a whole power of ten.

Added to half the precision, because the scaling widens with the precision
while the power does not. Measured at eleven, fifty-three, three hundred and
three thousand bits: the whole power wins up to a reach of about 550, 550,
550 and 1700, against the 517, 538, 662 and 2012 this gives. Where the choice
is the wrong one it costs under a factor of two either way.
"""

comptime _POWER_LIMIT_DOWN = 256
"""The same for a negative exponent, where the whole power is also a division.

A division costs several multiplications, so the power stops being worth it
sooner: measured crossovers of about 300, 290, 300 and 1700 against the 261,
282, 406 and 1756 this gives.
"""


def _power_is_worth_building(
    decimal_exponent: Int, precision: Int, guard: Int
) raises -> Bool:
    """Whether the whole power of ten is the quicker way to the answer.

    Args:
        decimal_exponent: The power of ten, never nought.
        precision: The bits the answer keeps.
        guard: The fractional bits the scaling is working in, which is what
            makes the answer change as a Ziv loop widens.

    Returns:
        Whether to take the power whole rather than scale against a
        truncated one.

    Raises:
        Error: Never, but the signature matches its callers.

    Notes:

    The power costs what its own digits are and the scaling costs what the
    precision is, several times over, so the two meet at a reach that grows
    with the precision. The limits are measured; see them for the numbers.

    The guard is in the question so that the same question ends the Ziv loop.
    A loop that has widened until the scaling is as wide as the power would
    be has nothing left to win, and handing the work over there bounds the
    worst case by what the whole power costs -- which is what this conversion
    used to cost for everything.
    """
    if decimal_exponent == Int.MIN:
        return False
    var reach = decimal_exponent if decimal_exponent > 0 else -decimal_exponent
    var limit = _POWER_LIMIT_UP if decimal_exponent > 0 else _POWER_LIMIT_DOWN
    if precision // 2 > Int.MAX - limit - guard:
        return True
    return reach <= limit + precision // 2 + guard


def _floor_log2_of_power_of_ten(exponent: Int) raises -> Int:
    """`floor(exponent * log2(10))`, within one of it.

    Args:
        exponent: The power of ten, either sign.

    Returns:
        Where the leading bit of `10^exponent` sits.

    Raises:
        OverflowError: If `10^exponent` is past the exponent range itself,
            which a value of `10^19` and more is.
        Error: Propagated from the arithmetic.

    Notes:

    The companion of `_floor_log10_of_power_of_two` below,
    and the same two paths for the same reason: whole machine words while the
    exponent has nine figures, where `log2(10)` scaled by `2^30` is within
    `2^-32` of the truth and the product stays inside an `Int`, and ninety
    bits of it in three pieces beyond that. Being out by one is allowed --
    the caller reads the bit length it gets and moves the place to match.
    """
    if exponent > -1_000_000_000 and exponent < 1_000_000_000:
        return (exponent * 3566893132) >> 30
    var numerator = ((BigInt(222930820) << 32) + BigInt(3167860911)) << 32
    numerator += BigInt(3834822512)
    var leading = (BigInt(exponent) * numerator) >> 90
    if leading > BigInt(Int.MAX) or leading < BigInt(Int.MIN):
        raise OverflowError(
            message=(
                "This power of ten is past the exponents a binary float holds."
            ),
            function="from_decimal_parts()",
        )
    return leading.to_int()


def _from_decimal_by_scaling(
    magnitude: BigInt,
    decimal_exponent: Int,
    precision: Int,
    negative: Bool,
    rounding_mode: RoundingMode,
    limit_precision: Int = -1,
) raises -> Tuple[BigInt, Int]:
    """Rounds `magnitude * 10^decimal_exponent` without building the power.

    Args:
        magnitude: The decimal digits as an integer, never negative or
            nought.
        decimal_exponent: The power of ten they are scaled by, never nought.
        precision: How many bits to keep.
        negative: The sign, which the directed rounding modes read.
        rounding_mode: Which way to round.
        limit_precision: What precision to put to the question of handing the
            work back to the whole power. The precision itself is the one to
            use; a test passes nought to keep the scaling for every reach the
            widening guard has not caught up with.

    Returns:
        A normalized `(significand, binary_exponent)` pair, as
        `round_to_precision()` returns.

    Raises:
        OverflowError: If an exponent on the way would not fit an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    One rounding, from a scaling wide enough to decide it. The place the kept
    bits start at is estimated from `log2(10)` and then corrected by the bit
    length that comes back, which says exactly how far out the estimate was.

    A value the power of five divides is a binary float already, and that is
    worth finding: the quotient is exact, so no widening can settle what it
    settles. The power it asks for is no bigger than the magnitude, because
    a larger one could not divide it.

    Every other value that reaches here sits on no rounding boundary, so the
    loop always settles. For a negative exponent the division above has shown
    the value is not a binary float, and what is not one is not halfway
    between two either. For a positive exponent the value is `m * 5^d * 2^d`:
    it stops inside the precision only if `5^d` does, and it is halfway
    between two floats only if `5^d` fits the precision and a bit more, so
    either way `d` is below half the precision -- and every `d` that small
    went to the whole power instead.

    The widening ends where that same question turns over, and hands the work
    to the whole power. A value whose bits crowd a boundary for hundreds of
    bits therefore costs what the whole power costs, which is what this
    conversion used to cost for everything.
    """
    var bits = magnitude.bit_length()

    if decimal_exponent < 0:
        var fives = -decimal_exponent
        if fives <= bits // 2:
            var power = BigInt(5).power(fives)
            var quotient = magnitude.truncate_divide(power)
            if quotient * power == magnitude:
                return round_to_precision(
                    quotient^,
                    decimal_exponent,
                    precision,
                    negative,
                    rounding_mode,
                )

    var limited = limit_precision if limit_precision >= 0 else precision
    var place = _added(
        bits - precision, _floor_log2_of_power_of_ten(decimal_exponent)
    )
    var guard = _INITIAL_GUARD
    var kept: BigInt
    var reaches_half: Bool
    var passes_half: Bool
    while True:
        if _power_is_worth_building(decimal_exponent, limited, guard):
            return _from_decimal_exactly(
                magnitude, decimal_exponent, precision, negative, rounding_mode
            )
        var scaled = _scaled_to_fixed_point(
            magnitude, -place, decimal_exponent, precision + 2, guard
        )
        var whole = scaled >> guard
        var rest = scaled - (whole << guard)
        var length = whole.bit_length()
        if length != precision:
            # The place was out by exactly what the bit length says, and the
            # estimate is never out by more than a bit or two.
            place = _added(place, length - precision)
            guard = _INITIAL_GUARD
            continue
        # The value sits on no boundary, so something is always dropped and
        # which side of the half it falls is the only question.
        var sits = _where_the_rest_sits(rest, guard)
        if sits == _UNREADABLE:
            guard += guard
            continue
        reaches_half = sits == _ABOVE_HALF
        passes_half = True
        kept = whole^
        break

    if rounds_away_from_zero(
        rounding_mode, negative, reaches_half, passes_half, test_bit(kept, 0)
    ):
        kept += BigInt.one()
        if kept.bit_length() > precision:
            # The carry ran past the precision, and a carry out of all ones
            # lands on a power of two exactly.
            kept = kept >> 1
            place = _added(place, 1)

    return (kept^, place)


# ===----------------------------------------------------------------------=== #
# A few digits, without the whole expansion
# ===----------------------------------------------------------------------=== #
#
# Rounding the exact expansion is the obvious way to a few digits and the
# wrong one, because the expansion is as long as the exponent is deep:
# `2^-1000000` has 301031 significant digits and a million decimal places,
# and every one of them gets built to keep seventeen. What follows keeps the
# digits that were asked for and no more.
#
# For `v = m * 2^e` and `d` digits, the answer is the `d`-digit decimal
# nearest `v`, which is `round(v * 10^j) * 10^-j` for `j = d - 1 - k` and
# `k = floor(log10 |v|)`. So one scaling by a power of ten, in fixed point
# and wide enough that the rounding is decided, settles it. The power of ten
# cannot be exact -- `5^j` for a deep exponent has more digits than memory
# holds -- so it is truncated to a working width, and the width doubles until
# the answer no longer depends on what the truncation dropped. That is Ziv's
# strategy, which every correctly rounded function here uses.
#
# A loop like that cannot settle when the true value sits exactly on the
# boundary it is deciding, and `v * 10^j` reaches one: `0.0625 * 10^3` is
# `62.5` exactly. That case is decided before the loop starts, from the
# exponents alone and without a digit. Write the significand as
# `2^t * 5^f * u` with `u` coprime to ten. Then
#
#     v * 10^j = u * 2^(e + t + j) * 5^(f + j)
#
# so when `f + j` is negative the value keeps a five in its denominator and
# is neither whole nor exactly a half; otherwise it is whole when `e + t + j`
# is at least nought, and exactly a half when `e + t + j` is `-1`. The rule
# was checked against CPython's `fractions.Fraction` on twenty thousand
# values, among them significands made deliberately rich in twos and fives,
# with no disagreement.


def _floor_log10_of_power_of_two(exponent: Int) raises -> Int:
    """`floor(exponent * log10(2))`, within one of it.

    Args:
        exponent: The power of two, either sign.

    Returns:
        How many decimal digits before the point `2^exponent` has, less one.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Being out by one does not matter. The caller checks the digit count it
    gets and moves the shift until the count is right, which it has to do
    anyway: the exponent bounds the value within a factor of two, and a
    factor of two straddles a power of ten.

    So the everyday range is done in whole machine words, with `log10(2)`
    scaled by `2^31`: the product of that and an exponent of nine figures
    stays inside an `Int`, and the scaled constant is within `2^-36` of the
    truth. Beyond that range the same sum is taken with `log10(2)` to
    ninety-six bits, as three pieces that each fit an `Int`, which keeps the
    answer within one for an exponent of any size.
    """
    if exponent > -2_000_000_000 and exponent < 2_000_000_000:
        return (exponent * 646456993) >> 31
    var numerator = ((BigInt(1292913986) << 32) + BigInt(2112355276)) << 32
    numerator += BigInt(1204071638)
    return ((BigInt(exponent) * numerator) >> 96).to_int()


def _boundary_kind(
    significand: BigInt, binary_exponent: Int, decimal_shift: Int
) raises -> Int:
    """Whether `significand * 2^binary_exponent * 10^decimal_shift` is whole.

    Args:
        significand: The significand, never negative or nought.
        binary_exponent: The power of two it is scaled by.
        decimal_shift: The power of ten to scale it by, either sign.

    Returns:
        `_WHOLE` if the scaled value is a whole number, `_HALF` if it is a
        whole number and exactly a half, `_NEITHER` otherwise.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The rule at the top of this section, with one shortcut. A negative shift
    only leaves the fives covered if the significand holds `5^-shift`, and
    `5^n` takes more than two bits per power, so a significand with fewer
    than twice as many bits cannot hold it. That shortcut is what keeps the
    test cheap for a large value, where the shift is deeply negative and the
    power it names could never be built.
    """
    if decimal_shift < 0:
        var fives = -decimal_shift
        if fives > significand.bit_length() // 2:
            return _NEITHER
        if not significand.truncate_modulo(BigInt(5).power(fives)).is_zero():
            return _NEITHER
    var twos = trailing_zeros(significand)
    var place = _added(binary_exponent, decimal_shift)
    if place > Int.MAX - twos:
        return _WHOLE
    place += twos
    if place >= 0:
        return _WHOLE
    if place == -1:
        return _HALF
    return _NEITHER


def _exact_expansion_bits(bits: Int, binary_exponent: Int) -> Int:
    """How many bits the exact decimal expansion's coefficient takes.

    Args:
        bits: The significand's bit length.
        binary_exponent: The power of two it is scaled by.

    Returns:
        An upper bound on the bits, saturating at `Int.MAX` rather than
        wrapping.

    Notes:

    `m * 2^e` for a positive `e` is `m` shifted, and for a negative one it is
    `m * 5^-e` over a power of ten. A power of five takes under three bits
    per power, which is the bound used here.
    """
    if binary_exponent >= 0:
        if binary_exponent > Int.MAX - bits:
            return Int.MAX
        return bits + binary_exponent
    if binary_exponent == Int.MIN:
        return Int.MAX
    var fives = -binary_exponent
    if fives > (Int.MAX - bits) // 3:
        return Int.MAX
    return bits + 3 * fives


def _rounded_from_exact(
    significand: BigInt,
    binary_exponent: Int,
    negative: Bool,
    digits: Int,
    rounding_mode: RoundingMode,
) raises -> BigDecimal:
    """The rounded decimal, by way of the exact expansion.

    Args:
        significand: The significand, never negative.
        binary_exponent: The power of two it is scaled by.
        negative: Whether the value is negative.
        digits: How many significant digits to keep.
        rounding_mode: Which way to round them.

    Returns:
        The same answer the scaled path gives, reached the long way.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    This is the way the conversion used to go, and it is kept for the one
    case the scaled path is no good at: a value whose digits crowd a rounding
    boundary for hundreds of bits makes the Ziv loop widen, and once the
    width it wants reaches the exact expansion's own size there is nothing
    left to win. Taking the expansion then bounds the whole conversion by
    what it used to cost, so the new way is never the slower one.
    """
    var exact = to_exact_bigdecimal(significand, binary_exponent, negative)
    exact.round_to_precision_inplace(
        precision=digits,
        rounding_mode=rounding_mode,
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return exact^


def to_rounded_bigdecimal(
    significand: BigInt,
    binary_exponent: Int,
    negative: Bool,
    digits: Int,
    rounding_mode: RoundingMode,
    expansion_bits: Int = 0,
) raises -> BigDecimal:
    """Returns `significand * 2^binary_exponent` as a decimal of `digits`.

    Args:
        significand: The significand, never negative.
        binary_exponent: The power of two it is scaled by.
        negative: Whether the value is negative.
        digits: How many significant digits to keep, which must be positive.
        rounding_mode: Which way to round them.
        expansion_bits: What to take the exact expansion's size to be, which
            decides between the two ways to the answer. Nought works it out
            from the exponent, which is the one to use; a test passes
            `Int.MAX` to force the scaling and one to force the expansion.

    Returns:
        The `digits`-digit decimal the rounding mode asks for, rounded once
        from the exact value.

    Raises:
        OverflowError: If an exponent on the way would not fit an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    One rounding, not two: the scaled value is carried in fixed point with
    enough bits below the digits to decide the rounding, and the decision
    reads that exact value's own half and remainder. Rounding the expansion
    to a few more digits and those digits to the count asked for would be
    two roundings, which can land a step away from the one.

    The cost follows the digits, not the exponent. Scaling by `10^j` takes
    `log2(j)` multiplications of numbers as wide as the answer, so printing
    seventeen digits of `2^-1000000` is the work of seventeen digits and not
    of the 301031 the value has.

    A short expansion is still taken whole, because for a shallow exponent it
    is the quicker of the two: one power of five against a power of five and
    a change of base. The same test ends the Ziv loop, since a loop that has
    widened until it wants the expansion's own bits has nothing left to win.
    """
    if significand.is_zero():
        return BigDecimal(BigUInt.zero(), 0, negative)

    # Three bits and a third per digit is what `10^digits` takes, and ten
    # thirds is over that with nothing to work out.
    var integer_bits = (digits * 10 + 2) // 3 + 8
    var bits = significand.bit_length()
    var expansion = (
        expansion_bits if expansion_bits
        > 0 else _exact_expansion_bits(bits, binary_exponent)
    )
    # Where the leading bit lands, which for the very largest value there is
    # would be a step past `Int.MAX`. Taking the step back costs nothing: the
    # estimate is allowed to be out by one and the digit count corrects it.
    var top = bits + binary_exponent
    if binary_exponent > Int.MAX - bits:
        top = Int.MAX
    var shift = _added(digits - 1, -_floor_log10_of_power_of_two(top))
    var kind = _boundary_kind(significand, binary_exponent, shift)
    var guard = _INITIAL_GUARD
    var coefficient: BigUInt
    var odd: Bool
    var reaches_half: Bool
    var passes_half: Bool
    while True:
        if expansion // _EXPANSION_MARGIN <= integer_bits + guard + 8:
            return _rounded_from_exact(
                significand, binary_exponent, negative, digits, rounding_mode
            )
        var scaled = _scaled_to_fixed_point(
            significand, binary_exponent, shift, integer_bits, guard
        )
        var whole = scaled >> guard
        var rest = scaled - (whole << guard)
        if kind == _WHOLE:
            # The scaling lands on a whole number of guard units exactly, so
            # the whole part is what it says and nothing is dropped.
            reaches_half = False
            passes_half = False
        elif kind == _HALF:
            # The same, half a unit up: the whole part is what it says and
            # what was dropped is the half, with nothing below it.
            reaches_half = True
            passes_half = False
        else:
            var sits = _where_the_rest_sits(rest, guard)
            if sits == _UNREADABLE:
                # The value is on neither boundary, so a wider guard puts the
                # truncation out of the way.
                guard += guard
                continue
            reaches_half = sits == _ABOVE_HALF
            passes_half = True
        # The digits themselves say whether the shift was right, and the
        # count is the one thing a base-ten magnitude answers for nothing.
        var decimals = whole.to_biguint()
        var count = 0 if whole.is_zero() else decimals.number_of_digits()
        if count != digits:
            shift = _added(shift, digits - count)
            guard = _INITIAL_GUARD
            kind = _boundary_kind(significand, binary_exponent, shift)
            continue
        coefficient = decimals^
        odd = test_bit(whole, 0)
        break

    if rounds_away_from_zero(
        rounding_mode, negative, reaches_half, passes_half, odd
    ):
        coefficient += BigUInt(1)
        if coefficient.number_of_digits() > digits:
            # The carry ran past the digit count: ten with three digits
            # asked for is 100 with one less place after the point, and the
            # carried value is the power of ten exactly.
            coefficient = BigUInt(10).power(digits - 1)
            shift -= 1

    if not reaches_half and not passes_half:
        # Nothing was dropped, so the value is this decimal exactly, and the
        # exact expansion's own shortest form is what the caller expects: a
        # half is 0.5 for any digit count, not 0.500. The places only come
        # off while there are places to lose.
        var zeros = coefficient.number_of_trailing_zeros()
        if zeros > shift:
            zeros = shift
        if zeros > 0:
            coefficient = coefficient.remove_trailing_digits_with_rounding(
                zeros, RoundingMode.ROUND_DOWN, False
            )
            shift -= zeros

    return BigDecimal(coefficient^, shift, negative)
