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


"""The companion operations IEEE 754 asks of a binary format.

Arithmetic, comparison and the functions are elsewhere. What is here is the
rest of what the standard asks for once those exist: the value next to a
value, the exponent of the leading bit, a scaling by a power of two, the three
sign manipulations, the name of a value's class, the four roundings to a whole
number, the fused multiply-add and the two remainders. The decimal side keeps
its own in `decimo.bigdecimal.spec`, and where the concept is the same the
answer is spelled the same way: `number_class()` returns the specification's
names, and `remainder()` is that module's `remainder_near()` under the name
IEEE 754 gives it.

Two of the standard's assumptions are not this type's, and both show up here.

There is no subnormal range. A finite non-zero significand holds exactly
`precision` bits with its top bit set, so every finite value is normal and
`number_class()` has nine names to return rather than ten.

The exponent range is an `Int` and not a field of eleven bits. `next_plus()`
and `next_minus()` step through that range, so they do reach its ends, and
there they answer what the standard says: the value above the largest finite
value at a precision is an infinity, and the value below the smallest
positive one is a zero. Both ends are the ends of an `Int`, which is why
neither agrees with a double's: `next_plus(0, 53)` is `2^(Int.MIN + 52)`
where a double answers `2^-1074`, because this type has no value between
those two and a double has a thousand.

Only three of these operations round. `fma()` and the two remainders take a
precision and a rounding mode because their answers are genuinely new values;
everything else is either exact at the precision it is given or carries its
argument's own precision, which the docstrings say one by one.
"""

from decimo.bigfloat.arithmetics import _checked_sum, _exponent_sum, add
from decimo.bigfloat.bigfloat import BigFloat
import decimo.bigfloat.comparison as bigfloat_comparison
from decimo.bigfloat.rounding import (
    _rounds_away_from_zero,
    checked_precision,
    leading_bit_position,
)
from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import test_bit, trailing_zeros
from decimo.bigint.number_theory import mod_pow
from decimo.errors import ValueError, ZeroDivisionError
from decimo.rounding_mode import RoundingMode


# ===----------------------------------------------------------------------=== #
# The ends of the range
# ===----------------------------------------------------------------------=== #


def _largest_magnitude(precision: Int, negative: Bool) raises -> BigFloat:
    """The finite value of the largest magnitude at a precision.

    Args:
        precision: The number of bits it carries.
        negative: Whether to give the negative one.

    Returns:
        `(2^precision - 1) * 2^Int.MAX`, signed.

    Raises:
        Error: Propagated from the construction.
    """
    return BigFloat(
        significand=(BigInt.one() << precision) - BigInt.one(),
        exponent=Int.MAX,
        precision=precision,
        sign=negative,
    )


def _smallest_magnitude(precision: Int, negative: Bool) raises -> BigFloat:
    """The non-zero value of the smallest magnitude at a precision.

    Args:
        precision: The number of bits it carries.
        negative: Whether to give the negative one.

    Returns:
        `2^(Int.MIN + precision - 1)`, signed.

    Raises:
        Error: Propagated from the construction.

    Notes:

    The significand has to hold `precision` bits with its top bit set, so the
    smallest magnitude is not `2^Int.MIN` but that value shifted up by the
    bits the significand is obliged to carry. A narrower precision therefore
    reaches further down, which is the opposite of what a format with a fixed
    exponent field does and follows from the exponent being the bound here.
    """
    return BigFloat(
        significand=BigInt.one() << (precision - 1),
        exponent=Int.MIN,
        precision=precision,
        sign=negative,
    )


# ===----------------------------------------------------------------------=== #
# Neighbours
# ===----------------------------------------------------------------------=== #


def _neighbour(x: BigFloat, precision: Int, upwards: Bool) raises -> BigFloat:
    """The representable value next to `x` at `precision` bits.

    Args:
        x: The value to step from.
        precision: The bits a value may hold. Must be positive.
        upwards: Whether to step toward positive or negative infinity.

    Returns:
        The nearest value in that direction that `precision` bits hold.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    Nothing here rounds. The step is `x` truncated toward zero at `precision`
    bits, which is exact, and then one unit in the last place that precision
    allows -- which is not the last place of `x`'s own significand, since a
    value carrying fewer bits than the precision steps by the smaller unit.

    Away from zero, the unit goes on whether or not the truncation lost
    anything: a truncation that lost nothing is `x` itself, and one that lost
    something sits below `x`, so in both cases the grid point above the
    truncation is the grid point above `x`.

    Toward zero, a truncation that lost something is already the answer,
    being the largest grid point below `x`. One that lost nothing has the
    unit taken off, and there the power of two is the case to watch: the
    values below a power of two are spaced half as far apart as those above
    it, so the significand is widened by a bit before the unit comes off. The
    predecessor of one at 53 bits is `1 - 2^-53`, not `1 - 2^-52`. This is the
    binary form of what the decimal `_neighbour()` does when it finds a power
    of ten.

    The ends of the exponent range are where the standard's own answers
    appear, and they are the reason this function never refuses. `x` written
    at `precision` bits has the exponent `x.exponent + x.precision -
    precision`, and that sum leaving the range is not an error but an answer:
    above the top, `x` is beyond the largest finite value at this precision,
    so the step outward is an infinity and the step inward is that largest
    value; below the bottom, `x` is inside the smallest one, so the step
    outward is that smallest value and the step inward is a zero. A carry out
    of the top binade is the same thing one unit later. These are the only
    places this module names an infinity it did not receive, and it names one
    because the question asked is which value comes next and not what two
    values add up to.
    """
    _ = checked_precision(precision, "next_plus()/next_minus()")

    if x.is_nan():
        return BigFloat.nan(precision)

    var outward = upwards != x.sign

    if x.is_infinite():
        if outward:
            # Stepping outward from an infinity stays on it.
            return BigFloat.infinity(precision, x.sign)
        return _largest_magnitude(precision, x.sign)

    if x.is_zero():
        # Both zeros have the same two neighbours, nothing lying between them.
        return _smallest_magnitude(precision, not upwards)

    # The exponent `x` takes when written at `precision` bits. Both operands
    # of the sum are bounded by `MAX_PRECISION`, so the difference cannot
    # wrap; the sum can, and where it does the answer is an end of the range.
    var adjust = x.precision - precision
    if adjust > 0 and x.exponent > Int.MAX - adjust:
        if outward:
            return BigFloat.infinity(precision, x.sign)
        return _largest_magnitude(precision, x.sign)
    if adjust < 0 and x.exponent < Int.MIN - adjust:
        if outward:
            return _smallest_magnitude(precision, x.sign)
        return BigFloat.zero(precision, x.sign)
    var exponent = x.exponent + adjust

    # `x` truncated toward zero at `precision` bits, which holds exactly that
    # many with its top bit set. The downward shift is the only one that can
    # lose anything, and `width` says whether it did.
    var width = x.precision - trailing_zeros(x.significand)
    var magnitude: BigInt
    if adjust <= 0:
        magnitude = x.significand << -adjust
    else:
        magnitude = x.significand >> adjust

    if outward:
        magnitude = magnitude + BigInt.one()
        if magnitude.bit_length() > precision:
            if exponent == Int.MAX:
                # The largest magnitude there is: an infinity is what is next.
                return BigFloat.infinity(precision, x.sign)
            magnitude = magnitude >> 1
            exponent += 1
    elif width <= precision:
        # The truncation is `x` itself, so a unit comes off it.
        if trailing_zeros(magnitude) == precision - 1:
            # A power of two, so the step below it is half the step above.
            if exponent == Int.MIN:
                # The smallest magnitude there is: zero is what is next.
                return BigFloat.zero(precision, x.sign)
            magnitude = (magnitude << 1) - BigInt.one()
            exponent -= 1
        else:
            magnitude = magnitude - BigInt.one()

    return BigFloat(
        significand=magnitude^,
        exponent=exponent,
        precision=precision,
        sign=x.sign,
    )


def next_plus(x: BigFloat, precision: Int) raises -> BigFloat:
    """The smallest representable value above `x`.

    Args:
        x: The value to step from.
        precision: The bits a value may hold. Must be positive.

    Returns:
        The next value toward positive infinity, at `precision` bits. A NaN
        gives a NaN.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    See `_neighbour()` for what happens at the ends of the exponent range and
    why the answers there are not a double's.
    """
    return _neighbour(x, precision, upwards=True)


def next_minus(x: BigFloat, precision: Int) raises -> BigFloat:
    """The largest representable value below `x`.

    Args:
        x: The value to step from.
        precision: The bits a value may hold. Must be positive.

    Returns:
        The next value toward negative infinity, at `precision` bits. A NaN
        gives a NaN.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    See `_neighbour()` for what happens at the ends of the exponent range and
    why the answers there are not a double's.
    """
    return _neighbour(x, precision, upwards=False)


def next_toward(x: BigFloat, y: BigFloat, precision: Int) raises -> BigFloat:
    """The value next to `x` in the direction of `y`.

    Args:
        x: The value to step from.
        y: The value that gives the direction.
        precision: The bits a value may hold. Must be positive.

    Returns:
        `x` stepped one place toward `y`, or `x` with the sign of `y` when the
        two are numerically equal. A NaN in either place gives a NaN.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    The equal case is the one answer that is not at `precision`: nothing was
    stepped, so `x` comes back as it was with only its sign replaced. That is
    what the decimal `next_toward()` does and what C's `nextafter` does, and
    it is what makes `next_toward(+0, -0)` the negative zero -- the one place
    where two values that compare equal have different answers.
    """
    _ = checked_precision(precision, "next_toward()")

    if x.is_nan() or y.is_nan():
        return BigFloat.nan(precision)

    var order = bigfloat_comparison.compare(x, y)
    if order < 0:
        return next_plus(x, precision)
    if order > 0:
        return next_minus(x, precision)
    return copy_sign(x, y)


# ===----------------------------------------------------------------------=== #
# Exponent
# ===----------------------------------------------------------------------=== #


def logb(x: BigFloat) raises -> BigInt:
    """Where the leading bit of `x` sits, which is `floor(log2(|x|))`.

    Args:
        x: The value to take the exponent of.

    Returns:
        The position of the leading bit as a power of two: `3` for a value in
        `[8, 16)` and `-2` for one in `[1/4, 1/2)`.

    Raises:
        ZeroDivisionError: If `x` is zero. IEEE 754 answers `-Infinity` and
            raises the divide-by-zero flag; the answer here is an integer and
            there is no integer infinity to give, so the flag is all that is
            left and it becomes the refusal. This is what the decimal
            `logb()` does, for the same reason.
        ValueError: If `x` is infinite or a NaN. The standard's answers are
            `+Infinity` and a NaN, and an integer is neither.
        Error: Propagated from the arithmetic.

    Notes:

    The answer is a `BigInt` and not an `Int` because the position is
    `exponent + precision - 1`, and that sum can leave an `Int` while the
    value itself is an ordinary one: a value whose exponent is `Int.MAX` has
    a leading bit above `Int.MAX` as soon as it carries more than one bit.
    `rounding.leading_bit_position()` is where that sum is formed, and this
    is the operation it was written for.
    """
    if x.is_nan():
        raise ValueError(
            message="A NaN has no leading bit to take the exponent of.",
            function="logb()",
        )
    if x.is_infinite():
        raise ValueError(
            message=(
                "logb(Infinity) has no answer without an integer infinity to"
                " give."
            ),
            function="logb()",
        )
    if x.is_zero():
        raise ZeroDivisionError(
            message="logb(0) has no answer without an infinity to give.",
            function="logb()",
        )
    return leading_bit_position(x)


def scaleb(x: BigFloat, n: Int) raises -> BigFloat:
    """`x * 2^n`, exactly.

    Args:
        x: The value to scale.
        n: The power of two to scale by.

    Returns:
        The scaled value, at `x`'s own precision. The significand is
        untouched, so nothing is lost and nothing rounds.

    Raises:
        OverflowError: If `x` is finite and non-zero and the scaled exponent
            is outside `Int`. The guard is the arithmetic module's, so a
            scaling that leaves the range is refused rather than wrapped
            round to the other end of it.
        Error: Propagated from the construction.

    Notes:

    This is the one operation a binary float does for nothing, which is why
    `BigFloat.power_of_two()` exists and why several of the functions reduce
    their arguments with it. The name is IEEE 754's `scaleB`, and it is the
    name the decimal `scaleb()` borrowed for its power of ten.

    A zero, an infinity and a NaN come back unchanged, signs included, and
    without `n` being looked at: scaling any of the three gives itself, so an
    `n` that would take a finite value's exponent out of range is no reason to
    refuse one of them.
    """
    if not x.is_finite() or x.is_zero():
        return x.copy()
    return BigFloat(
        significand=x.significand,
        exponent=_checked_sum(x.exponent, n, "scaled value"),
        precision=x.precision,
        sign=x.sign,
    )


# ===----------------------------------------------------------------------=== #
# Sign
# ===----------------------------------------------------------------------=== #
#
# The three that never raise and never look at a value. They are here rather
# than beside `__neg__` and `__abs__` because they are IEEE 754's `copySign`,
# `copyAbs` and `copyNegate` under the standard's own names, and a caller
# reaching for one of those is reaching for this module.


def copy_sign(x: BigFloat, y: BigFloat) -> BigFloat:
    """`x` with the sign of `y`.

    Args:
        x: The value whose magnitude is kept.
        y: The value whose sign is taken.

    Returns:
        A copy of `x` carrying `y`'s sign, with its precision and its kind
        unchanged.

    Notes:

    Neither argument's value is read, so this works on an infinity and on a
    zero exactly as it does on anything else, and it cannot fail.

    A NaN comes back as the NaN. This type keeps one, and it carries no sign
    to replace and none to lend: `copy_sign(nan, y)` is that NaN, and
    `copy_sign(x, nan)` is `copy_abs(x)`, the sign a NaN lends being the
    positive one.
    """
    var result = x.copy()
    if not result.is_nan():
        result.sign = y.sign
    return result^


def copy_abs(x: BigFloat) -> BigFloat:
    """`x` without its sign.

    Args:
        x: The value.

    Returns:
        A copy of `x` with a positive sign, which for a finite non-zero value
        is `abs(x)` and for a zero is the positive zero.
    """
    return abs(x)


def copy_negate(x: BigFloat) -> BigFloat:
    """`x` with its sign flipped.

    Args:
        x: The value.

    Returns:
        A copy of `x` with the other sign. A zero gives the other zero, and
        the NaN gives itself, having no sign to flip.
    """
    return -x


# ===----------------------------------------------------------------------=== #
# Class
# ===----------------------------------------------------------------------=== #


def number_class(x: BigFloat) -> String:
    """The specification's name for what kind of number `x` is.

    Args:
        x: The value to describe.

    Returns:
        One of `"NaN"`, `"-Infinity"`, `"-Normal"`, `"-Zero"`, `"+Zero"`,
        `"+Normal"` and `"+Infinity"`.

    Notes:

    These are the names the decimal arithmetic specification gives, which is
    what the decimal `number_class()` returns and what Python's
    `decimal.Context.number_class` prints, so a caller who knows one knows
    the other. Two of the ten names are missing and neither is an omission.

    `"+Subnormal"` and `"-Subnormal"` cannot occur. A subnormal value is one
    whose leading bit has been pushed below the bottom of the exponent range
    and which therefore carries fewer significant bits than the format
    allows. Here a finite non-zero significand always holds exactly
    `precision` bits with its top bit set, and a value too small for that is
    refused rather than represented short, so every finite non-zero value is
    normal whatever its exponent.

    `"sNaN"` cannot occur either, for the reason `BigFloat.nan()` gives:
    there is one NaN and it does not signal.
    """
    if x.is_nan():
        return "NaN"
    if x.is_infinite():
        return "-Infinity" if x.sign else "+Infinity"
    if x.is_zero():
        return "-Zero" if x.sign else "+Zero"
    return "-Normal" if x.sign else "+Normal"


# ===----------------------------------------------------------------------=== #
# Whole numbers
# ===----------------------------------------------------------------------=== #


def is_integer(x: BigFloat) -> Bool:
    """Whether `x` is a whole number.

    Args:
        x: The value to ask about.

    Returns:
        True when `x` is finite and has no fractional part. Both zeros are
        whole numbers; an infinity and a NaN are not.

    Notes:

    A non-negative exponent answers on its own, the value then being an
    integer times a power of two. A negative one asks whether the
    significand's trailing zeros reach as far down as the exponent does,
    which is one call and no division.

    The comparison is written so that `-exponent` is never formed for an
    exponent that cannot be negated. A significand of `precision` bits has at
    most `precision - 1` trailing zeros, so an exponent at or below
    `-precision` cannot be reached whatever they are, and that is settled
    first: `Int.MIN` has no positive counterpart, and this is the one place
    an exponent of `Int.MIN` would be negated.
    """
    if not x.is_finite():
        return False
    if x.is_zero():
        return True
    if x.exponent >= 0:
        return True
    if x.exponent <= -x.precision:
        return False
    return trailing_zeros(x.significand) >= -x.exponent


def _to_integral(x: BigFloat, rounding_mode: RoundingMode) raises -> BigFloat:
    """Rounds `x` to a whole number, keeping it a float.

    Args:
        x: The value to round.
        rounding_mode: Which way to round what sits below the point.

    Returns:
        The whole number, at `x`'s own precision.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The precision of the answer is `x`'s own, and that is always enough to
    hold the answer exactly, so this rounds once and nothing rounds again on
    the way out. The whole part of a `p`-bit significand scaled by `2^-k` is
    that significand with `k` bits dropped, which is `p - k` bits; rounding
    away from zero can carry it to `p - k + 1`, and `k` is at least one
    wherever there is anything to drop. A magnitude below one is the
    remaining case, and the answer there is one bit or none.

    Keeping `x`'s precision rather than taking one as an argument is also
    what makes the four public roundings agree with each other and with
    themselves: the answer of any of them is already whole, so passing it
    through any of them again changes nothing.

    What is dropped is read exactly as the rounding primitive reads it -- the
    leading dropped bit, and whether anything sits below it -- and the seven
    modes are then that primitive's, so `round_to_integer()` means the same
    thing by `HALF_EVEN` as every other operation on this type does.
    """
    if not x.is_finite():
        return x.copy()
    if x.is_zero():
        return x.copy()
    if x.exponent >= 0:
        # Already whole, and already in the representation this would build.
        return x.copy()

    var leading_dropped: Bool
    var rest_below: Bool
    var lowest_kept = False

    if x.exponent <= -x.precision:
        # The magnitude is below one, so the whole significand goes and the
        # whole part is nought. The value is exactly a half when its leading
        # bit sits at `-1` and nothing else is set, which is the one case the
        # half-way modes have to be able to see.
        leading_dropped = x.exponent == -x.precision
        rest_below = (
            trailing_zeros(x.significand)
            < x.precision - 1 if leading_dropped else True
        )
        if not _rounds_away_from_zero(
            rounding_mode, x.sign, leading_dropped, rest_below, lowest_kept
        ):
            # A value rounding to nought keeps its sign, as IEEE 754 asks:
            # the whole part of `-0.25` is `-0`.
            return BigFloat.zero(x.precision, x.sign)
        return BigFloat.from_rounded_parts(BigInt.one(), 0, x.precision, x.sign)

    var dropped = -x.exponent
    var kept = x.significand >> dropped
    leading_dropped = test_bit(x.significand, dropped - 1)
    rest_below = False
    if dropped >= 2:
        rest_below = trailing_zeros(x.significand) < dropped - 1
    lowest_kept = test_bit(kept, 0)

    if _rounds_away_from_zero(
        rounding_mode, x.sign, leading_dropped, rest_below, lowest_kept
    ):
        kept = kept + BigInt.one()
    return BigFloat.from_rounded_parts(kept^, 0, x.precision, x.sign)


def truncate(x: BigFloat) raises -> BigFloat:
    """`x` with its fractional part removed.

    Args:
        x: The value to truncate.

    Returns:
        The whole number nearest `x` in the direction of zero, at `x`'s own
        precision. A zero, an infinity and a NaN come back unchanged.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    This is IEEE 754's `roundToIntegralTowardZero` and C's `trunc`. The sign
    survives a value that truncates to nothing, so `truncate(-0.5)` is `-0`
    and not `+0`.
    """
    return _to_integral(x, RoundingMode.ROUND_DOWN)


def floor(x: BigFloat) raises -> BigFloat:
    """The largest whole number at or below `x`.

    Args:
        x: The value.

    Returns:
        The floor, at `x`'s own precision. A zero, an infinity and a NaN come
        back unchanged.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    This is IEEE 754's `roundToIntegralTowardNegative` and C's `floor`.
    """
    return _to_integral(x, RoundingMode.ROUND_FLOOR)


def ceil(x: BigFloat) raises -> BigFloat:
    """The smallest whole number at or above `x`.

    Args:
        x: The value.

    Returns:
        The ceiling, at `x`'s own precision. A zero, an infinity and a NaN
        come back unchanged.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    This is IEEE 754's `roundToIntegralTowardPositive` and C's `ceil`. A
    negative value whose ceiling is nothing keeps its sign, so `ceil(-0.5)`
    is `-0`, which is what the standard asks for and what C answers.
    """
    return _to_integral(x, RoundingMode.ROUND_CEILING)


def round_to_integer(
    x: BigFloat,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """`x` rounded to a whole number in any of the seven modes.

    Args:
        x: The value to round.
        rounding_mode: Which way to round. The default is half to even, which
            is IEEE 754's `roundToIntegralTiesToEven`.

    Returns:
        The whole number the mode asks for, at `x`'s own precision. A zero, an
        infinity and a NaN come back unchanged.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `truncate()`, `floor()` and `ceil()` are this with the three directed
    modes, and they are named separately because those three are what the
    standard and C name. The four others are reachable only here: `HALF_UP`
    takes a half away from zero, `HALF_DOWN` takes it toward zero,
    `HALF_EVEN` takes it to the even neighbour, and `UP` goes away from zero
    whenever anything at all is dropped, which is `truncate()` mirrored.
    """
    return _to_integral(x, rounding_mode)


# ===----------------------------------------------------------------------=== #
# Fused multiply-add
# ===----------------------------------------------------------------------=== #


def fma(
    x: BigFloat,
    y: BigFloat,
    z: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """`x * y + z` with a single rounding.

    Args:
        x: The first factor.
        y: The second factor.
        z: The value added to the product.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round, once.

    Returns:
        The float of `precision` bits nearest the exact value of `x * y + z`.

    Raises:
        ValueError: If `precision` is not positive, or if the exact product
            needs more bits than a precision may have, which asks for two
            operands whose precisions together reach a quarter of `Int.MAX`.
        OverflowError: If the product's exponent is outside `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    `add(multiply(x, y, precision), z, precision)` is a different function
    and a worse one: it rounds the product to `precision` before `z` is
    added, so a product whose bits reach below `z`'s last place has already
    lost them and the addition cannot see what it is adding. The case that
    shows it is a product that very nearly cancels with `z`, where the
    leading bits of the answer are exactly the bits a rounded product threw
    away.

    So the product is formed exactly and never rounded. It is a `BigInt`
    times a power of two, which is a `BigFloat` in its own right -- a
    significand of up to `x.precision + y.precision` bits -- and the addition
    then rounds once, with all the sticky-bit and cancellation work the
    addition already does. None of that is repeated here.

    The product's trailing zeros come off before its exponent is formed, for
    the reason `_exponent_sum()` gives: two exponents can add to a value
    outside `Int` while the product itself sits inside it, and stripping
    zeros moves the exponent upward, which is the direction that helps.

    The special values are IEEE 754's. A NaN anywhere gives a NaN. An
    infinity times a zero gives a NaN whatever `z` is, the product being no
    value at all. Everything else is the product's special value handed to
    the addition, which already knows that an infinity plus the other
    infinity is a NaN and that two zeros of opposite signs cancel to a
    positive one in every mode but `FLOOR`.
    """
    _ = checked_precision(precision, "fma()")

    if x.is_nan() or y.is_nan() or z.is_nan():
        return BigFloat.nan(precision)

    var negative = x.sign != y.sign

    if x.is_infinite() or y.is_infinite():
        if x.is_zero() or y.is_zero():
            return BigFloat.nan(precision)
        return add(
            BigFloat.infinity(precision, negative), z, precision, rounding_mode
        )

    if x.is_zero() or y.is_zero():
        return add(
            BigFloat.zero(precision, negative), z, precision, rounding_mode
        )

    var magnitude = x.significand * y.significand
    var shed = trailing_zeros(magnitude)
    if shed > 0:
        magnitude = magnitude >> shed
    var product = BigFloat(
        significand=magnitude,
        exponent=_exponent_sum(x.exponent, y.exponent, shed),
        precision=magnitude.bit_length(),
        sign=negative,
    )
    return add(product, z, precision, rounding_mode)


# ===----------------------------------------------------------------------=== #
# Remainders
# ===----------------------------------------------------------------------=== #


def _remainder(
    x: BigFloat,
    y: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode,
    nearest: Bool,
    function: String,
) raises -> BigFloat:
    """`x - y * n`, with `n` an integer that `nearest` chooses.

    Args:
        x: The dividend.
        y: The divisor.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round, if the destination is too narrow
            to hold the answer.
        nearest: Whether `n` is the integer nearest `x / y`, ties to even, or
            the one `x / y` truncates to.
        function: The caller's name, for the messages.

    Returns:
        The remainder.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    The quotient is never formed as a float and `n` is never formed at all.
    What the answer needs of `x / y` is three things -- the remainder of the
    integer division, whether that remainder is above, below or exactly at a
    half of the divisor, and whether the quotient is odd -- and all three come
    out of one modular reduction.

    Writing `|x|` as `N * 2^e` and `|y|` as `D * 2^e` over the lower of the
    two exponents makes both of them integers, and then `N mod 2D` carries
    everything: the remainder is it modulo `D`, and the quotient is odd
    exactly when it is at or above `D`. Reducing modulo `2D` rather than `D`
    is the whole trick, since a tie has to be broken by a parity that
    `N mod D` has thrown away.

    `N` is where this could go wrong. The two exponents can be an `Int`
    apart, so `x`'s significand shifted up to meet `y` can be a quintillion
    bits, and neither allocating it nor dividing by it is possible. It is
    never built: `2^d mod 2D` comes out of `mod_pow()` in a few dozen
    multiplications of numbers the size of `y`, and multiplying by `x`'s
    significand leaves the same residue. The other direction needs no such
    care, because a `y` far above `x` is answered before it is reached -- a
    leading bit two or more places below `y`'s makes `|x / y|` less than a
    half, which makes `n` nought and the remainder `x` itself. That bound is
    also what caps the shift in the cases that remain, at the operands' own
    precisions.

    The answer is exact whenever `precision` is at least the wider of the two
    operands' precisions, which is the classical result that the remainder of
    two values of a format lies in that format: the answer is a multiple of
    the smaller operand's last place and is bounded by the larger operand, so
    the bits between the two are all it needs. A narrower destination rounds,
    which is what the mode is for.
    """
    _ = checked_precision(precision, function)

    if x.is_nan() or y.is_nan():
        return BigFloat.nan(precision)
    if x.is_infinite() or y.is_zero():
        # Neither has a remainder: no multiple of a finite value reaches an
        # infinity, and every multiple of zero is zero.
        return BigFloat.nan(precision)
    if x.is_zero():
        return BigFloat.zero(precision, x.sign)
    if y.is_infinite():
        return BigFloat.from_rounded_parts(
            x.significand, x.exponent, precision, x.sign, rounding_mode
        )

    if leading_bit_position(x) + BigInt(2) <= leading_bit_position(y):
        # `|x|` is below half of `|y|`, so the nearest integer to the
        # quotient is nought, and so is the one it truncates to.
        return BigFloat.from_rounded_parts(
            x.significand, x.exponent, precision, x.sign, rounding_mode
        )

    var exponent: Int
    var divisor: BigInt
    var residue: BigInt
    if x.exponent >= y.exponent:
        exponent = y.exponent
        divisor = y.significand.copy()
        var twice = divisor << 1
        # The exponent difference is taken in a `BigInt`, because it can be
        # wider than an `Int` holds. It is only ever used as a power of two
        # to reduce modulo `2D`, which costs its logarithm and not itself.
        var power = mod_pow(
            BigInt(2), BigInt(x.exponent) - BigInt(y.exponent), twice
        )
        residue = (x.significand * power).truncate_modulo(twice)
    else:
        # The shift is bounded by `x`'s own precision, and the case answered
        # just above is exactly the one that would make it larger: with `x`'s
        # leading bit no more than one place below `y`'s,
        # `y.exponent - x.exponent` is at most
        # `x.precision - y.precision + 1`.
        var shift = y.exponent - x.exponent
        debug_assert(
            shift > 0 and shift <= x.precision,
            "a remainder shifted a divisor by more than a precision",
        )
        exponent = x.exponent
        divisor = y.significand << shift
        residue = x.significand.truncate_modulo(divisor << 1)

    var quotient_is_odd = residue >= divisor
    var remainder_magnitude = residue.truncate_modulo(divisor)

    var step = False
    if nearest and not remainder_magnitude.is_zero():
        var twice = remainder_magnitude << 1
        if twice > divisor:
            step = True
        elif twice == divisor:
            step = quotient_is_odd

    if step:
        # The other candidate, `|y| - |remainder|`, which lies on the far
        # side of a multiple of `y` from `x`, so the sign flips.
        return BigFloat.from_rounded_parts(
            divisor - remainder_magnitude,
            exponent,
            precision,
            not x.sign,
            rounding_mode,
        )
    if remainder_magnitude.is_zero():
        # An exact division leaves a zero of the dividend's sign, as IEEE 754
        # and C's `fmod` both ask.
        return BigFloat.zero(precision, x.sign)
    return BigFloat.from_rounded_parts(
        remainder_magnitude^, exponent, precision, x.sign, rounding_mode
    )


def remainder(
    x: BigFloat,
    y: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """IEEE 754's remainder: `x - y * n` with `n` the nearest integer.

    Args:
        x: The dividend.
        y: The divisor.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round, which only a destination too
            narrow to hold the answer ever consults.

    Returns:
        The remainder, which is at most half of `y` in magnitude and may have
        either sign. A tie in `x / y` goes to the even `n`.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    This is Python's `math.remainder`, C's `remainder` and the decimal
    `remainder_near()`, and it is not `%`: the sign of the answer follows
    whichever side of `y * n` the dividend fell on, not the sign of either
    operand. `remainder(5, 3)` is `-1` and not `2`, six being nearer to five
    than three is.

    An exact division leaves a zero of the dividend's sign. An infinite
    divisor leaves the dividend, no multiple of an infinity being available
    to take off it. An infinite dividend and a zero divisor both give a NaN.

    See `_remainder()` for how the quotient is reached without being formed.
    """
    return _remainder(x, y, precision, rounding_mode, True, "remainder()")


def fmod(
    x: BigFloat,
    y: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """C's `fmod`: `x - y * n` with `n` the quotient truncated.

    Args:
        x: The dividend.
        y: The divisor.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round, which only a destination too
            narrow to hold the answer ever consults.

    Returns:
        The remainder, which has the sign of `x` and a magnitude below `y`'s.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    This is here beside `remainder()` because the two are different answers
    to the same question and a caller wanting one will reach for the other by
    mistake. `fmod` keeps the sign of the dividend and can be nearly as large
    as the divisor; `remainder` is never more than half the divisor and takes
    its sign from the side the dividend fell on. `fmod(5, 3)` is `2` where
    `remainder(5, 3)` is `-1`.

    It is Python's `math.fmod` and C's `fmod`, and it is what `%` means for a
    float in most languages. It costs what `remainder()` costs, sharing all
    of its machinery and skipping only the step that looks at the half and
    the parity.
    """
    return _remainder(x, y, precision, rounding_mode, False, "fmod()")
