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


"""The three hyperbolic functions and their three inverses.

Each is an identity over `exp(x) - 1` or `ln(1 + x)` rather than over `exp` or
`ln`, for the reason the decimal layer gives: the textbook forms lose their
answer near zero. `(e^x - e^-x)/2` subtracts two values that agree to as many
bits as `x` is small, and `ln(x + sqrt(x^2 + 1))` rounds its argument to one
before the logarithm sees it. The forms here keep every bit, so
`sinh(2^-100000)` is `2^-100000` and not zero.

The identities, with `u = expm1(|x|)`:

- `sinh`     `u(u + 2) / (2(u + 1))`
- `cosh`     `(e^|x| + e^-|x|) / 2`
- `tanh`     `v / (v + 2)`, with `v = expm1(2|x|)`
- `arcsinh`  `log1p(|x| + x^2/(1 + sqrt(1 + x^2)))` below one, `ln` above
- `arccosh`  `log1p(t + sqrt(t(t + 2)))` with `t = x - 1`, `ln` above two
- `arctanh`  `log1p(2|x| / (1 - |x|)) / 2` below a half, `ln` above

Every one of those is exact, which is what makes the error simple to account
for: the operations around them are correctly rounded, so a kernel is off by a
handful of units in the last place of the width it works in, and that width
carries enough beyond the width it returns for the final rounding to be the
only error that survives.

Two of the six approach a constant, and that is where the care goes. `cosh`
comes down to one as its argument goes to zero, and `tanh` goes up to one as
its argument grows. In both cases the identity computes the constant exactly
and the news of which side of it the answer lies on is lost, and neither can
be recovered by widening: the loop that decides a rounding widens
geometrically and would run out long before the hundred thousand bits
`cosh(2^-100000)` would need. So both are answered directly -- `cosh` by
handing `1 + x^2/2` to the addition, which already knows how to round that,
and `tanh` by naming the two values its argument can round to and letting the
mode choose between them.

The other four need none of that. Their answers go to zero with their
arguments rather than to a constant, so the relative accuracy an exact
identity gives is the relative accuracy the answer wants, however small the
argument is.
"""

from std.bit import bit_width

import decimo.bigfloat.arithmetics as bigfloat_arithmetics
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.comparison import compare_absolute
from decimo.bigfloat.constants import ln2
from decimo.bigfloat.exponential import (
    atanh_at_width,
    exp_at_width,
    expm1_at_width,
    ln_at_width,
    round_by_deciding_at,
    sqrt,
)
from decimo.bigfloat.rounding import (
    MAX_PRECISION,
    checked_precision,
    cubic_term_is_below_a_guard_unit,
    guard_bits,
    leading_bit_position,
    rounded_beside,
)
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


comptime _HYPERBOLIC_SLACK = 4
"""Units in the last place a kernel here may be off at the width it returns.

Each is a handful of correctly rounded steps over an exact identity -- one
exponential or logarithm, a square root at most, and two or three of the four
operations -- carried at `_working_width()` and rounded once on the way out.
Four is what the decimal layer states for the same work, and the margin here
is wider, because the working width grows with the width asked for.
"""


def _working_width(width: Int) -> Int:
    """How many bits the identities are evaluated in.

    Args:
        width: The bits the kernel returns.

    Returns:
        The width plus enough to absorb a handful of roundings.

    Notes:

    The same choice `ln_at_width` makes: `bit_width(width) + 12` bits beyond
    what comes back leaves every intermediate rounding, and the two units the
    exponential and the logarithm allow themselves, far below the last place
    of the answer.
    """
    return width + Int(bit_width(UInt(width))) + 12


def _saturation_magnitude(width: Int) raises -> BigFloat:
    """The `|x|` past which `e^-2|x|` cannot reach the last place of `width`.

    Args:
        width: The bits in question.

    Returns:
        A bound on `|x|`. Past it `tanh(x)` is within half a unit of one.

    Raises:
        Error: Propagated from the construction.

    Notes:

    `tanh` falls short of one by `2e^-2|x|/(1 + e^-2|x|)`, which is below
    `2e^-2|x|`, and that is below `2^-width` -- half a unit in the last place
    of one at `width` bits -- once `2|x| > (width + 1) ln 2`. So the bound is
    `(width + 4) ln 2 / 2`, from above.

    It is computed in integers against `3466/10000`, which is above
    `ln 2 / 2 = 0.3465735902...`, rather than as a `Float64` multiply by a
    constant written out in decimal. A constant a hair below the true one is
    not conservative, and no fixed cushion rescues it, because the shortfall
    grows with the width: at ten billion bits a cushion of four is already
    too small. The division comes before the multiplication so that the
    product cannot leave an `Int` at the widest precision this layer takes.
    """
    var whole = (width + 4) // 10000
    var rest = (width + 4) % 10000
    var bound = whole * 3466 + (rest * 3466) // 10000 + 1
    return BigFloat.from_int(bound, Int(bit_width(UInt(bound))) + 1)


def _expm1_at(x: BigFloat, width: Int) raises -> BigFloat:
    """`exp(x) - 1`, without the cancellation the name avoids.

    Args:
        x: The argument.
        width: The bits to work in.

    Returns:
        The value, within a handful of units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Below a half in magnitude the series is the whole of it, and it is the
    series the exponential already carries. Above a half there is nothing to
    cancel: `exp(x) - 1` is at least 0.64 while `exp(x)` is at most about
    1.65 times that, so taking the one away costs less than two units.
    """
    if compare_absolute(x, BigFloat.power_of_two(-1)) <= 0:
        return expm1_at_width(x, width)
    return bigfloat_arithmetics.subtract(
        exp_at_width(x, width), BigFloat.from_int(1, width), width
    )


def _log1p_at(x: BigFloat, width: Int) raises -> BigFloat:
    """`ln(1 + x)`, without the cancellation the name avoids.

    Args:
        x: The argument, which must be above minus one.
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


def _at_width(value: BigFloat, width: Int, negative: Bool) raises -> BigFloat:
    """Rounds a working value into the width a kernel returns, with a sign.

    Args:
        value: The value computed at the working width.
        width: The bits to keep.
        negative: Whether the answer is negative, since the identities here
            all run on a magnitude.

    Returns:
        The value at `width` bits with that sign.

    Raises:
        Error: Propagated from the rounding.
    """
    return BigFloat.from_rounded_parts(
        value.significand, value.exponent, width, negative
    )


# ===----------------------------------------------------------------------=== #
# The kernels
# ===----------------------------------------------------------------------=== #


def _sinh_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`sinh(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_HYPERBOLIC_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    With `u = expm1(|x|)`, so that `e^|x|` is `u + 1`:

        sinh(|x|) = ((u + 1) - 1/(u + 1)) / 2 = u(u + 2) / (2(u + 1))

    which is the subtraction done in advance, on paper, where it cannot lose
    anything. Every factor is proportional to `u` for a small argument, and
    `u` is `x` to within its own square, so nothing cancels. `sinh` is odd,
    so the sign is put back at the end.

    A large argument needs no special case, unlike in the decimal layer: `u`
    is then enormous but a binary float holds it in its exponent, and the
    `u + 2` and `u + 1` the identity asks for round to `u` with a sticky bit,
    which is what `u/2` -- the right answer there -- comes out of.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_infinite():
        return BigFloat.infinity(width, x.sign)
    if x.is_zero():
        return BigFloat.zero(width, x.sign)

    var working = _working_width(width)
    var one = BigFloat.from_int(1, working)
    var two = BigFloat.from_int(2, working)
    var u = _expm1_at(abs(x), working)
    var numerator = bigfloat_arithmetics.multiply(
        u, bigfloat_arithmetics.add(u, two, working), working
    )
    var denominator = bigfloat_arithmetics.multiply(
        two, bigfloat_arithmetics.add(u, one, working), working
    )
    return _at_width(
        bigfloat_arithmetics.divide(numerator, denominator, working),
        width,
        x.sign,
    )


def _cosh_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`cosh(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_HYPERBOLIC_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `(e^|x| + e^-|x|)/2` as it reads. Both terms are positive, so there is
    nothing to cancel and no call for `expm1`: what the reciprocal adds to a
    large `e^|x|` is below its last place, and the addition handles that as
    the sticky bit it is. `cosh` is even, so the argument's sign is dropped.

    Near zero this returns exactly one, which is within a unit of the truth
    and so inside what the kernel promises -- but it is not enough to decide
    a rounding, and `cosh()` answers that case without coming here.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_infinite():
        return BigFloat.infinity(width, False)
    if x.is_zero():
        return BigFloat.from_int(1, width)

    var working = _working_width(width)
    var one = BigFloat.from_int(1, working)
    var two = BigFloat.from_int(2, working)
    var exponential = exp_at_width(abs(x), working)
    var reciprocal = bigfloat_arithmetics.divide(one, exponential, working)
    return _at_width(
        bigfloat_arithmetics.divide(
            bigfloat_arithmetics.add(exponential, reciprocal, working),
            two,
            working,
        ),
        width,
        False,
    )


def _tanh_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`tanh(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_HYPERBOLIC_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    With `v = expm1(2|x|)`:

        tanh(|x|) = (e^2|x| - 1) / (e^2|x| + 1) = v / (v + 2)

    and `v` is `2x` for a small argument, which leaves `tanh(x) = x` as it
    should be. `tanh` is odd.

    A saturating argument is not this function's business: `tanh()` settles
    that before it gets here, because the quotient would come out as exactly
    one and no width would say which side of one the answer is on.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_infinite():
        return BigFloat.from_int(1, width, RoundingMode.ROUND_HALF_EVEN) if (
            not x.sign
        ) else -BigFloat.from_int(1, width, RoundingMode.ROUND_HALF_EVEN)
    if x.is_zero():
        return BigFloat.zero(width, x.sign)

    var working = _working_width(width)
    var two = BigFloat.from_int(2, working)
    var doubled = bigfloat_arithmetics.multiply(
        abs(x), BigFloat.power_of_two(1), working
    )
    var v = _expm1_at(doubled, working)
    return _at_width(
        bigfloat_arithmetics.divide(
            v, bigfloat_arithmetics.add(v, two, working), working
        ),
        width,
        x.sign,
    )


def _is_far_above_one(x: BigFloat, width: Int) raises -> Bool:
    """Whether `x` is large enough that `ln(2|x|)` is the whole answer.

    Args:
        x: The argument, finite and not zero.
        width: The bits wanted in the answer.

    Returns:
        True when `|x|` is at least `2^(width/2 + 2)`.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Both inverse functions are `ln(2x)` plus a tail in `1/(4x^2)`, and past
    this point that tail is below `2^-(width+4)` while the answer is above
    one, so it cannot reach the last place. The test is on the leading bit's
    position and in a `BigInt`, which is the point: deciding the branch by
    forming `x^2` first would overflow the exponent for an argument near the
    top of the range, and refuse an answer that is perfectly representable.
    `arcsinh(2^(Int.MAX-1))` is about `Int.MAX * ln 2`, an ordinary number.
    """
    return leading_bit_position(x) >= BigInt(width // 2 + 2)


def _arcsinh_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`arcsinh(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_HYPERBOLIC_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `arcsinh(x) = ln(x + sqrt(x^2 + 1))`, and for `|x|` up to one that
    argument is one plus something small, which `log1p` takes without the sum
    ever being formed:

        x + sqrt(x^2 + 1) = 1 + x + x^2 / (1 + sqrt(1 + x^2))

    The rearranged tail is what keeps a tiny argument. Written as
    `sqrt(1 + x^2) - 1` it would cancel away to nothing; written as a
    quotient it does not. Past one the logarithm is far enough from zero to
    be taken as it reads. `arcsinh` is odd.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_infinite():
        return BigFloat.infinity(width, x.sign)
    if x.is_zero():
        return BigFloat.zero(width, x.sign)

    var working = _working_width(width)
    var one = BigFloat.from_int(1, working)
    var magnitude = abs(x)

    # Far above one the answer is `ln|x| + ln 2`, which forms no square and
    # so reaches the top of the exponent range.
    if _is_far_above_one(x, width):
        return _at_width(
            bigfloat_arithmetics.add(
                ln_at_width(magnitude, working), ln2(working), working
            ),
            width,
            x.sign,
        )

    var square = bigfloat_arithmetics.multiply(magnitude, magnitude, working)
    var root = sqrt(bigfloat_arithmetics.add(one, square, working), working)

    var result: BigFloat
    if compare_absolute(magnitude, one) <= 0:
        var tail = bigfloat_arithmetics.divide(
            square, bigfloat_arithmetics.add(one, root, working), working
        )
        result = _log1p_at(
            bigfloat_arithmetics.add(magnitude, tail, working), working
        )
    else:
        result = ln_at_width(
            bigfloat_arithmetics.add(magnitude, root, working), working
        )
    return _at_width(result, width, x.sign)


def _arccosh_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`arccosh(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_HYPERBOLIC_SLACK` units of the last place, or a
        NaN where the function has no real value.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `arccosh(x) = ln(x + sqrt(x^2 - 1))`. Near one the answer is small and the
    logarithm's argument is one plus something small, so with `t = x - 1`:

        x + sqrt(x^2 - 1) = 1 + t + sqrt(t(t + 2))

    and `log1p` takes that tail. The square root of the product is where the
    accuracy near one comes from: `x^2 - 1` would cancel to nothing there,
    while `t(t + 2)` is formed from `t` alone and keeps every bit of it, so
    `arccosh(1 + 2^-200)` comes out at its full `2^-99.5` and not as zero.

    An argument below one has no real inverse hyperbolic cosine, and the
    answer is a NaN rather than a refusal -- the same choice `sqrt` and `ln`
    make for the values outside their domains.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.sign:
        return BigFloat.nan(width)
    if x.is_infinite():
        return BigFloat.infinity(width, False)

    var working = _working_width(width)
    var one = BigFloat.from_int(1, working)
    var two = BigFloat.from_int(2, working)
    if compare_absolute(x, one) < 0:
        return BigFloat.nan(width)

    var t = bigfloat_arithmetics.subtract(x, one, working)
    if t.is_zero():
        return BigFloat.zero(width, False)

    # Far above one the answer is `ln x + ln 2`, which forms no square and so
    # reaches the top of the exponent range.
    if _is_far_above_one(x, width):
        return _at_width(
            bigfloat_arithmetics.add(
                ln_at_width(x, working), ln2(working), working
            ),
            width,
            False,
        )

    var result: BigFloat
    if compare_absolute(x, two) <= 0:
        var root = sqrt(
            bigfloat_arithmetics.multiply(
                t, bigfloat_arithmetics.add(t, two, working), working
            ),
            working,
        )
        result = _log1p_at(bigfloat_arithmetics.add(t, root, working), working)
    else:
        var root = sqrt(
            bigfloat_arithmetics.subtract(
                bigfloat_arithmetics.multiply(x, x, working), one, working
            ),
            working,
        )
        result = ln_at_width(
            bigfloat_arithmetics.add(x, root, working), working
        )
    return _at_width(result, width, False)


def _arctanh_kernel(x: BigFloat, width: Int) raises -> BigFloat:
    """`arctanh(x)` to `width` bits.

    Args:
        x: The argument.
        width: The bits wanted.

    Returns:
        The value, within `_HYPERBOLIC_SLACK` units of the last place, an
        infinity at the ends of the interval, or a NaN outside it.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `arctanh(x) = ln((1 + x)/(1 - x)) / 2`, and that quotient is one plus
    `2x/(1 - x)`, which `log1p` takes directly:

        arctanh(x) = log1p(2|x| / (1 - |x|)) / 2

    For a small argument the tail is `2x` to within its own square and
    nothing is lost. Nearer the ends the quotient grows without bound and the
    plain logarithm is the better form. `arctanh` is odd.

    At exactly `-1` or `1` the function runs off to an infinity, which is the
    value returned; past them it has no real value and the answer is a NaN.
    """
    if x.is_nan():
        return BigFloat.nan(width)
    if x.is_infinite():
        return BigFloat.nan(width)
    if x.is_zero():
        return BigFloat.zero(width, x.sign)

    var working = _working_width(width)
    var one = BigFloat.from_int(1, working)
    var two = BigFloat.from_int(2, working)
    var magnitude = abs(x)
    var against_one = compare_absolute(x, one)
    if against_one == 0:
        return BigFloat.infinity(width, x.sign)
    if against_one > 0:
        return BigFloat.nan(width)

    var result: BigFloat
    if compare_absolute(magnitude, BigFloat.power_of_two(-1)) <= 0:
        var tail = bigfloat_arithmetics.divide(
            bigfloat_arithmetics.multiply(
                magnitude, BigFloat.power_of_two(1), working
            ),
            bigfloat_arithmetics.subtract(one, magnitude, working),
            working,
        )
        result = _log1p_at(tail, working)
    else:
        result = ln_at_width(
            bigfloat_arithmetics.divide(
                bigfloat_arithmetics.add(one, magnitude, working),
                bigfloat_arithmetics.subtract(one, magnitude, working),
                working,
            ),
            working,
        )
    return _at_width(
        bigfloat_arithmetics.divide(result, two, working), width, x.sign
    )


# ===----------------------------------------------------------------------=== #
# What a saturating argument makes of `tanh`
# ===----------------------------------------------------------------------=== #


def _saturated_tanh(
    precision: Int, rounding_mode: RoundingMode, negative: Bool
) raises -> BigFloat:
    """`tanh` of an argument past `_saturation_magnitude(precision)`.

    Args:
        precision: The bits wanted.
        rounding_mode: How to round.
        negative: Whether the argument was negative.

    Returns:
        The correctly rounded value, which is one only in the modes that
        round that way.

    Raises:
        Error: Propagated from the construction.

    Notes:

    `tanh` never reaches one: it falls short by just under `2e^-2|x|`, and
    past the bound that shortfall is below `2^-precision`, which is half a
    unit in the last place of one. So the true value sits strictly between
    the largest float below one and one itself, and which of the two is the
    answer is the mode's to say:

    - the three nearest modes take one, the shortfall being under half a unit;
    - `UP` rounds away from zero, so it takes one as well;
    - `CEILING` takes one above zero, and the value below one under it;
    - `FLOOR` is `CEILING` mirrored;
    - `DOWN` rounds toward zero, so it always takes the value below one.

    Answering one in every mode, which is what reading a half-even kernel
    would give, is wrong for `DOWN` and for one side of each directed mode.
    """
    var takes_one: Bool
    if (
        rounding_mode == RoundingMode.ROUND_HALF_EVEN
        or rounding_mode == RoundingMode.ROUND_HALF_UP
        or rounding_mode == RoundingMode.ROUND_HALF_DOWN
        or rounding_mode == RoundingMode.ROUND_UP
    ):
        takes_one = True
    elif rounding_mode == RoundingMode.ROUND_CEILING:
        takes_one = not negative
    elif rounding_mode == RoundingMode.ROUND_FLOOR:
        takes_one = negative
    else:  # ROUND_DOWN, toward zero
        takes_one = False

    if takes_one:
        return BigFloat(
            significand=BigInt.one() << (precision - 1),
            exponent=-(precision - 1),
            precision=precision,
            sign=negative,
        )
    # The largest float below one: `(2^p - 1) * 2^-p`, which holds exactly
    # `p` bits with its top bit set.
    return BigFloat(
        significand=(BigInt.one() << precision) - BigInt.one(),
        exponent=-precision,
        precision=precision,
        sign=negative,
    )


# ===----------------------------------------------------------------------=== #
# The functions
# ===----------------------------------------------------------------------=== #


def sinh(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The hyperbolic sine of a value, correctly rounded.

    Args:
        x: The argument.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `sinh(x)`.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If the answer's exponent would not fit in an `Int`,
            which an argument from `2^62` up already asks for.
        Error: Propagated from the arithmetic.

    Notes:

    `sinh` of an infinity is that infinity, and of a NaN a NaN. `sinh(0)` is
    a signed zero, since the function is odd.
    """
    _ = checked_precision(precision, "sinh()")
    # Near zero the answer is `x + x^3/6`, which is `x` moved by less
    # than it takes to compute: at `2^-100000` the cubic term's own
    # exponent is outside an `Int`, and the loop that decides a
    # rounding would run out of widenings before it could tell which
    # side of `x` the answer is on. The side is all the rounding
    # needs, and one guard unit stands in for it.
    if (
        x.is_finite()
        and not x.is_zero()
        and cubic_term_is_below_a_guard_unit(x, guard_bits(x, precision))
    ):
        return rounded_beside(x, precision, rounding_mode, False)

    return round_by_deciding_at[_sinh_kernel, _HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )


def cosh(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The hyperbolic cosine of a value, correctly rounded.

    Args:
        x: The argument.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `cosh(x)`, which is never below
        one.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If the answer's exponent would not fit in an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    An argument whose square is far below the last place of one does not
    reach the identity at all. `cosh(x)` is `1 + x^2/2 + x^4/24 + ...`, and
    once `x^2/2` is below `2^-(precision+4)` the quartic term is nowhere near
    a rounding boundary, so `1 + x^2/2` rounds exactly as `cosh(x)` does --
    to one in the three nearest modes and toward zero, and to the next float
    up away from zero. The addition settles all of that.

    This is not a shortcut but the only way to answer those arguments. The
    identity gives exactly one for any argument below the working width's
    last place, which says nothing about which side of one the truth is on,
    and the loop that decides a rounding widens too slowly ever to find out:
    `cosh(2^-100000)` would want a hundred thousand bits.
    """
    _ = checked_precision(precision, "cosh()")

    # The hyperbolic cosine of a nought is exactly one, and an exactly
    # representable answer is the one thing the loop below cannot settle on.
    if x.is_zero():
        return BigFloat.from_int(1, precision)

    if x.is_finite():
        # Whether `x^2/2` can reach the last place is a question about `x`'s
        # leading bit, so it is asked that way. Forming the square to ask it
        # would underflow the exponent for an argument near the bottom of the
        # range -- `2^(Int.MIN + 52)` squared has no exponent -- and refuse an
        # answer that is simply one.
        var leading = leading_bit_position(x)
        if (leading + leading) < BigInt(-(precision + 5)):
            # One, moved away from zero by a hair: that is what `1 + x^2/2`
            # is here, and the side is all the rounding needs. Toward zero it
            # is one, away from it the value above.
            return rounded_beside(
                BigFloat.from_int(1, 1), precision, rounding_mode, False
            )

    return round_by_deciding_at[_cosh_kernel, _HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )


def tanh(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The hyperbolic tangent of a value, correctly rounded.

    Args:
        x: The argument.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `tanh(x)`. Mathematically that
        lies strictly inside `(-1, 1)`; at a finite precision an argument
        past `_saturation_magnitude()` falls short of one by less than half a
        unit in the last place, and what comes back there is one or the float
        below it, whichever the mode asks for.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    `tanh` of an infinity is exactly one, with the sign of the argument, in
    every mode: there the shortfall is not small, it is nothing.

    A saturating argument is settled before the identity is reached, because
    `v/(v + 2)` comes out as exactly one there -- `v + 2` rounds to `v` -- and
    no width would say which side of one the answer lies on. See
    `_saturated_tanh()` for which mode takes which value.
    """
    _ = checked_precision(precision, "tanh()")

    if x.is_nan():
        return BigFloat.nan(precision)
    if x.is_infinite():
        return BigFloat(
            significand=BigInt.one() << (precision - 1),
            exponent=-(precision - 1),
            precision=precision,
            sign=x.sign,
        )
    if (
        not x.is_zero()
        and compare_absolute(x, _saturation_magnitude(precision)) > 0
    ):
        return _saturated_tanh(precision, rounding_mode, x.sign)

    # Near zero the answer is `x - x^3/3`, which is `x` moved by less
    # than it takes to compute: at `2^-100000` the cubic term's own
    # exponent is outside an `Int`, and the loop that decides a
    # rounding would run out of widenings before it could tell which
    # side of `x` the answer is on. The side is all the rounding
    # needs, and one guard unit stands in for it.
    if (
        x.is_finite()
        and not x.is_zero()
        and cubic_term_is_below_a_guard_unit(x, guard_bits(x, precision))
    ):
        return rounded_beside(x, precision, rounding_mode, True)

    return round_by_deciding_at[_tanh_kernel, _HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )


def arcsinh(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The inverse hyperbolic sine of a value, correctly rounded.

    Args:
        x: The argument, which may be anything.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `arcsinh(x)`.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    `arcsinh` of an infinity is that infinity, and of a NaN a NaN.
    """
    _ = checked_precision(precision, "arcsinh()")
    # Near zero the answer is `x - x^3/6`, which is `x` moved by less
    # than it takes to compute: at `2^-100000` the cubic term's own
    # exponent is outside an `Int`, and the loop that decides a
    # rounding would run out of widenings before it could tell which
    # side of `x` the answer is on. The side is all the rounding
    # needs, and one guard unit stands in for it.
    if (
        x.is_finite()
        and not x.is_zero()
        and cubic_term_is_below_a_guard_unit(x, guard_bits(x, precision))
    ):
        return rounded_beside(x, precision, rounding_mode, True)

    return round_by_deciding_at[_arcsinh_kernel, _HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )


def arccosh(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The inverse hyperbolic cosine of a value, correctly rounded.

    Args:
        x: The argument, which has a real answer only from one up.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `arccosh(x)`, which is never
        negative, or a NaN for an argument below one.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    An argument below one gives a NaN rather than a refusal, which is what
    `sqrt` does for a negative value and `ln` for one below zero.
    `arccosh(1)` is a positive zero.
    """
    _ = checked_precision(precision, "arccosh()")
    return round_by_deciding_at[_arccosh_kernel, _HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )


def arctanh(
    x: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The inverse hyperbolic tangent of a value, correctly rounded.

    Args:
        x: The argument, which has a finite answer strictly inside `(-1, 1)`.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `arctanh(x)`, a signed infinity
        at either end of the interval, or a NaN outside it.

    Raises:
        ValueError: If `precision` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    The ends are infinities rather than refusals, because that is the value
    the function approaches there, and this type has an infinity to say it
    with. Past them there is no real value and the answer is a NaN.
    """
    _ = checked_precision(precision, "arctanh()")
    # Near zero the answer is `x + x^3/3`, which is `x` moved by less
    # than it takes to compute: at `2^-100000` the cubic term's own
    # exponent is outside an `Int`, and the loop that decides a
    # rounding would run out of widenings before it could tell which
    # side of `x` the answer is on. The side is all the rounding
    # needs, and one guard unit stands in for it.
    if (
        x.is_finite()
        and not x.is_zero()
        and cubic_term_is_below_a_guard_unit(x, guard_bits(x, precision))
    ):
        return rounded_beside(x, precision, rounding_mode, False)

    return round_by_deciding_at[_arctanh_kernel, _HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )
