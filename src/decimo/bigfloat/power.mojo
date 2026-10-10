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


"""One value raised to the power of another.

`x ** y` is `exp(y ln x)` and that is how it ends, but almost nothing about
it is that line. The reason is rounding. The loop that decides a rounding
works by bracketing the true value and asking whether both ends of the
bracket round the same way, and it cannot answer when the true value sits
exactly on a boundary. A power sits on one constantly: `2 ** 10` is exactly
`1024`, which every directed mode has to return and no bracket around it can
prove, and `4 ** 0.5` is exactly `2` although the exponent is not a whole
number at all.

So the exact answers are found first, from the integers, and only what is
left goes to the series. Three kinds are found.

A whole exponent is a power of the significand: `x` is `s * 2^e`, so `x^n` is
`s^n * 2^(en)`, and `s^n` is an integer however large. It is formed while it
is short enough to be worth forming, and one rounding finishes it.

A base that is a power of two answers any exponent that leaves a whole
result: `2^m` to the `a / 2^b` is `2^(ma / 2^b)`, exact exactly when `2^b`
divides `m`.

Anything else with a dyadic exponent -- and every binary float is dyadic --
is `b` square roots followed by a whole power. A square root is exact only
when the significand is a perfect square, which `sqrt_rem()` says for
nothing, and each exact root halves the bits, so the question answers itself
within a few steps or not at all.

What reaches the series is therefore known to be irrational, where the loop
settles.
"""

from std.bit import bit_width

import decimo.bigfloat.arithmetics as bigfloat_arithmetics
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.exponential import (
    _ZIV_LIMIT,
    _ZIV_START,
    _settled,
    exp_at_width,
    ln_at_width,
)
from decimo.bigfloat.rounding import checked_precision
from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import trailing_zeros
from decimo.bigint.exponential import sqrt_rem
from decimo.errors import OverflowError
from decimo.rounding_mode import RoundingMode


comptime _POWER_SLACK = 8
"""Units in the last place the series path may be off by.

The logarithm, the multiplication by the exponent and the exponential each
cost a unit or two of the working width, and that width carries the bits of
the answer's own exponent beyond what is returned, which is what the
multiplication amplifies.
"""

comptime _SQUARING_SLACK = 4
"""Units in the last place the squaring kernel may be off by.

The kernel widens its own working width by the bits its doublings will
consume, so what reaches here is the final rounding of a value already good
to a fraction of a unit. This constant is a bound on that rounding, not on
the squaring -- the squaring's error is paid for inside, where it is known
how many doublings there will be.
"""

comptime _MAX_HALVINGS = 62
"""How deep a dyadic exponent is followed before it is called irrational.

An exponent of `a / 2^b` needs the base to be a perfect `2^b`-th power, so a
significand of at least `2^b` bits, and a base that is a power of two needs
`2^b` to divide an exponent an `Int` holds. Past sixty-two neither can
happen, so nothing is given up by stopping.
"""


def _is_one(x: BigFloat) -> Bool:
    """Whether a value is exactly positive one.

    Args:
        x: The value.

    Returns:
        True for one at any precision, and False for minus one.

    Notes:

    `exponent + precision == 1` only places the value in `[1, 2)`, which
    `1.5` is in as well. One also needs its significand to be a single bit,
    which is what the trailing zeros say.
    """
    if x.sign or not x.is_finite() or x.is_zero():
        return False
    if x.exponent + x.precision != 1:
        return False
    return trailing_zeros(x.significand) == x.precision - 1


def _whole_degree(y: BigFloat) raises -> Optional[Int]:
    """A whole exponent as an `Int`, with its sign.

    Args:
        y: The exponent, finite and not nought.

    Returns:
        The value as an `Int`, or nothing when it is not whole or will not
        fit one.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Not fitting an `Int` is declined rather than refused. An exponent that
    large makes the answer's own exponent larger still, so the series path
    refuses it on the way through, with the message that belongs to it.
    """
    var zeros = trailing_zeros(y.significand)
    var shift = y.exponent + zeros
    if shift < 0:
        return None
    var magnitude = y.significand >> zeros
    if magnitude.bit_length() + shift > 62:
        return None
    var value = (magnitude << shift).to_int()
    return -value if y.sign else value


def _dyadic_parts(y: BigFloat) -> Tuple[BigInt, Int]:
    """A fractional exponent as `a / 2^b` with `a` odd.

    Args:
        y: The exponent, finite, not nought, and not whole.

    Returns:
        The odd `a`, never negative, and the positive `b`.

    Notes:

    Every binary float is such a fraction; what makes this worth forming is
    that `a` is odd, which is what decides whether a power of two answers
    and how many square roots the other path needs.
    """
    var zeros = trailing_zeros(y.significand)
    return (y.significand >> zeros, -(y.exponent + zeros))


def _exact_square_root(x: BigFloat) raises -> Optional[BigFloat]:
    """The square root of a positive value, when it is exact.

    Args:
        x: The value, finite, positive and not nought.

    Returns:
        The root when `x` is the square of another float, and nothing
        otherwise.

    Raises:
        Error: Propagated from the root.

    Notes:

    `x` is `s * 2^e`, and a square needs an even exponent, so an odd one
    borrows a factor of two from the significand: `s * 2^e` is `2s * 2^(e-1)`
    and nothing is lost. What is left is a perfect square or it is not, and
    the integer root's remainder says which. The precision of the answer is
    the bits the root actually has, since that is what it is.
    """
    var magnitude = x.significand.copy()
    var exponent = x.exponent
    if exponent % 2 != 0:
        magnitude = magnitude << 1
        exponent -= 1
    var parts = sqrt_rem(magnitude)
    if not parts[1].is_zero():
        return None
    var root = parts[0].copy()
    return BigFloat(
        significand=root,
        exponent=exponent // 2,
        precision=root.bit_length(),
        sign=False,
    )


def _integer_power_at_width(
    x: BigFloat, degree: Int, width: Int
) raises -> BigFloat:
    """`x` to a whole `degree` by squaring, to `width` bits.

    Args:
        x: The base, finite and not nought.
        degree: The exponent, not nought.
        width: The bits to work in.

    Returns:
        The value, within `_SQUARING_SLACK` units of the last place.

    Raises:
        OverflowError: If the answer's exponent would not fit an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    Binary exponentiation, which costs about `log2(degree)` multiplications.
    That is the count of operations, and it is not the error: **a squaring
    doubles whatever relative error it is given**. Squaring `v(1 + d)` gives
    `v^2 (1 + 2d)`, so the error after `k` squarings is about `2^k` units of
    the width they were computed in -- about `degree` units, not `log2(degree)`
    of them. The accumulator's own multiplications double along with it, which
    costs one more bit.

    So the width is widened by the bits the doubling will consume, and the
    answer is rounded back down to the width asked for. `exp` does the same
    thing for the same reason, in `_exponential_of_small()`, which halves its
    argument and squares the result back: the bits a squaring loses have to be
    carried, not hoped for.

    Getting this wrong is not slow, it is wrong. With a slack that assumed
    `log2(degree)` units, `power(5, 50000)` at 53 bits came back a unit above
    the correctly rounded answer, and 3.5 per cent of degrees between four
    thousand and sixty thousand did the same.
    """
    var doublings = Int(bit_width(UInt(abs(degree))))
    var work = width + doublings + 8
    var result = BigFloat.from_int(1, work)
    var base = BigFloat.from_rounded_parts(
        x.significand, x.exponent, work, x.sign
    )
    var remaining = abs(degree)
    while remaining > 0:
        if remaining % 2 == 1:
            result = bigfloat_arithmetics.multiply(result, base, work)
        remaining //= 2
        if remaining > 0:
            base = bigfloat_arithmetics.multiply(base, base, work)
    if degree < 0:
        result = bigfloat_arithmetics.divide(
            BigFloat.from_int(1, work), result, work
        )
    return BigFloat.from_rounded_parts(
        result.significand, result.exponent, width, result.sign
    )


def _integer_power(
    x: BigFloat, degree: Int, precision: Int, rounding_mode: RoundingMode
) raises -> BigFloat:
    """`x` to a whole `degree`, correctly rounded.

    Args:
        x: The base, finite and not nought.
        degree: The exponent, not nought.
        precision: The bits the answer keeps.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `x^degree`.

    Raises:
        OverflowError: If the answer's exponent would not fit an `Int`.
        Error: If the rounding cannot be decided, or propagated from the
            arithmetic.

    Notes:

    The exact power is formed when it is short enough to matter. `x` is
    `t * 2^f` with `t` odd, so `x^n` is `t^n * 2^(fn)` and `t^n` is odd too:
    its bits are the answer's significant bits, and there is no rounding to
    decide once they are in hand.

    How short is short enough follows from what the deciding loop cannot do.
    It cannot settle on a value that is representable, nor on one exactly
    between two that are, and both of those have at most `precision + 1`
    bits. An odd `t` above one has at least two bits, so `t^n` has at least
    `n + 1`, which bounds `n` by the precision. Four times the precision is
    a wide margin on that bound, and past it the loop settles by itself.

    A base that is a power of two is the exception and is always exact: `t`
    is one, and the answer is a power of two whatever the exponent.

    A negative exponent is one correctly rounded division of exact operands,
    which is what `1 / x^n` is, and not a reciprocal taken at a working
    width and rounded twice.
    """
    var negative = x.sign and degree % 2 != 0
    var magnitude = abs(degree)
    var zeros = trailing_zeros(x.significand)
    var odd = x.significand >> zeros
    var shift = x.exponent + zeros

    if odd.is_one():
        # A power of two raised to anything is a power of two.
        if shift != 0 and abs(shift) > Int.MAX // magnitude:
            raise OverflowError(
                message="The exponent of this power would not fit in an Int.",
                function="power()",
            )
        var exponent = shift * degree
        if degree < 0:
            exponent = -(shift * magnitude)
        return BigFloat.from_rounded_parts(
            BigInt.one(), exponent, precision, negative, rounding_mode
        )

    if odd.bit_length() * magnitude <= 4 * precision + 24:
        if shift != 0 and abs(shift) > Int.MAX // magnitude:
            raise OverflowError(
                message="The exponent of this power would not fit in an Int.",
                function="power()",
            )
        var significand = odd**magnitude
        var exponent = shift * magnitude
        if degree > 0:
            return BigFloat.from_rounded_parts(
                significand, exponent, precision, negative, rounding_mode
            )
        var exact = BigFloat(
            significand=significand,
            exponent=exponent,
            precision=significand.bit_length(),
            sign=negative,
        )
        return bigfloat_arithmetics.divide(
            BigFloat.from_int(1, precision), exact, precision, rounding_mode
        )

    # Too long to form, so the answer is neither representable nor a
    # midpoint, and the loop below can settle on it.
    var width = precision + _ZIV_START
    for _ in range(_ZIV_LIMIT):
        var wide = _integer_power_at_width(x, degree, width)
        if wide.is_zero():
            return BigFloat.zero(precision, wide.sign)
        var settled = _settled(
            wide, width, _SQUARING_SLACK, precision, rounding_mode
        )
        if settled:
            return settled.take()
        width += width - precision
    raise Error(
        "the rounding of this power could not be decided; the squaring is"
        " further from the true value than its stated bound allows"
    )


def _exact_dyadic_power(
    x: BigFloat, y: BigFloat, precision: Int, rounding_mode: RoundingMode
) raises -> Optional[BigFloat]:
    """`x ** y` for a fractional `y`, when the answer is exact.

    Args:
        x: The base, finite, positive and not nought.
        y: The exponent, finite and not whole.
        precision: The bits the answer keeps.
        rounding_mode: Which way to round, which an exact answer only needs
            when it is longer than the precision.

    Returns:
        The correctly rounded answer when `x ** y` is exact, and nothing when
        it is not.

    Raises:
        OverflowError: If the answer's exponent would not fit an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    `y` is `a / 2^b` with `a` odd, so `x ** y` is the `2^b`-th root of `x`
    raised to `a`. The root has to be exact for the answer to be, and it is
    taken one square root at a time: each either comes out exact or ends the
    search, and an exact one halves the significand's bits, so no more than
    `log2(precision)` of them can succeed in a row.

    A base that is a power of two skips the roots. `2^m` to the `a / 2^b` is
    `2^(ma / 2^b)`, which is a float exactly when `2^b` divides `m`, since
    `a` is odd and can divide nothing out of it.
    """
    var parts = _dyadic_parts(y)
    var halvings = parts[1]
    if halvings > _MAX_HALVINGS:
        return None
    if parts[0].bit_length() > 62:
        return None
    var degree = parts[0].to_int()
    if y.sign:
        degree = -degree

    var zeros = trailing_zeros(x.significand)
    var odd = x.significand >> zeros
    if odd.is_one():
        # The base is a power of two, so only the exponent has to divide.
        var shift = x.exponent + zeros
        var step = 1 << halvings
        if shift % step != 0:
            return None
        return _integer_power(
            BigFloat.power_of_two(shift // step),
            degree,
            precision,
            rounding_mode,
        )

    var root = BigFloat(
        significand=x.significand,
        exponent=x.exponent,
        precision=x.precision,
        sign=False,
    )
    for _ in range(halvings):
        var next = _exact_square_root(root)
        if not next:
            return None
        root = next.take()
    return _integer_power(root, degree, precision, rounding_mode)


def _power_at_width(x: BigFloat, y: BigFloat, width: Int) raises -> BigFloat:
    """`x ** y` to `width` bits, as `exp(y ln x)`.

    Args:
        x: The base, finite, positive and not nought or one.
        y: The exponent, finite and not nought.
        width: The bits wanted.

    Returns:
        The value, within `_POWER_SLACK` units of the last place.

    Raises:
        OverflowError: If the answer's exponent would not fit an `Int`.
        Error: Propagated from the arithmetic.

    Notes:

    The logarithm is good to its own last place, so the product `y ln x` is
    good to its own as well -- but the exponential turns an absolute error in
    its argument into a relative error in its answer, and that argument is as
    large as the answer's exponent. So the working width carries the bits of
    `y ln x` on top of the bits wanted, counted from a narrow logarithm
    rather than guessed.

    An argument whose `y ln x` needs more than sixty-four bits has no answer
    with an exponent an `Int` holds, and is refused here rather than carried
    into a width nothing could compute.
    """
    var rough = bigfloat_arithmetics.multiply(y, ln_at_width(x, 64), 64)
    var span = 0
    if not rough.is_zero():
        var leading = rough.exponent + rough.precision - 1
        if leading > 0:
            span = leading
    if span > 64:
        raise OverflowError(
            message="The exponent of this power would not fit in an Int.",
            function="power()",
        )

    var work = width + span + Int(bit_width(UInt(width))) + 16
    var product = bigfloat_arithmetics.multiply(y, ln_at_width(x, work), work)
    var value = exp_at_width(product, work)
    return BigFloat.from_rounded_parts(
        value.significand, value.exponent, width, value.sign
    )


def power(
    x: BigFloat,
    y: BigFloat,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """One value raised to the power of another, correctly rounded.

    Args:
        x: The base.
        y: The exponent.
        precision: How many bits the result keeps. Must be positive.
        rounding_mode: Which way to round.

    Returns:
        The float of `precision` bits nearest `x ** y`.

    Raises:
        ValueError: If `precision` is not positive.
        OverflowError: If the answer's exponent would not fit an `Int`.
        Error: If the rounding cannot be decided, or propagated from the
            arithmetic.

    Notes:

    The special values follow IEEE 754's `pow`, which answers before it looks
    at anything else in two places: a nought exponent gives one for every
    base, a NaN included, and a base of one gives one for every exponent, a
    NaN included. Those two are the standard's own choice and they are worth
    stating because they are the surprising ones.

    After that a NaN in either place gives a NaN; a negative base with a
    fractional exponent gives a NaN, there being no real answer; an infinite
    exponent gives nought or an infinity according to whether the base is
    inside or outside the unit circle; and an infinite or nought base gives
    nought or an infinity according to the exponent's sign, carrying the
    base's sign when the exponent is an odd whole number.

    There is no overflow to an infinity for finite arguments. This type's
    exponent is as wide as an `Int`, and an answer that asks for more is
    refused rather than answered with an infinity it did not earn, which is
    what `exp` does for the same reason.
    """
    _ = checked_precision(precision, "power()")

    # IEEE 754 answers these two before examining anything else.
    if y.is_zero():
        return BigFloat.from_int(1, precision)
    if _is_one(x):
        return BigFloat.from_int(1, precision)

    if x.is_nan() or y.is_nan():
        return BigFloat.nan(precision)

    var whole = _whole_degree(y)
    var odd_whole = False
    if whole:
        odd_whole = whole.value() % 2 != 0
    var is_whole = False
    if y.is_finite():
        var zeros = trailing_zeros(y.significand)
        is_whole = y.exponent + zeros >= 0

    if y.is_infinite():
        # Which side of one the base sits on decides, and a base of minus
        # one sits on neither: `pow(-1, inf)` is one.
        var inside = _below_one_in_magnitude(x)
        if _is_one_in_magnitude(x):
            return BigFloat.from_int(1, precision)
        if inside == (not y.sign):
            return BigFloat.zero(precision, False)
        return BigFloat.infinity(precision, False)

    if x.is_infinite():
        if y.sign:
            return BigFloat.zero(precision, x.sign and odd_whole)
        return BigFloat.infinity(precision, x.sign and odd_whole)

    if x.is_zero():
        if y.sign:
            return BigFloat.infinity(precision, x.sign and odd_whole)
        return BigFloat.zero(precision, x.sign and odd_whole)

    if x.sign and not is_whole:
        return BigFloat.nan(precision)

    if is_whole:
        if whole:
            return _integer_power(x, whole.value(), precision, rounding_mode)
    else:
        var exact = _exact_dyadic_power(x, y, precision, rounding_mode)
        if exact:
            return exact.take()

    # What is left is irrational, where the loop settles.
    var width = precision + _ZIV_START
    for _ in range(_ZIV_LIMIT):
        var wide = _power_at_width(x, y, width)
        if wide.is_zero():
            return BigFloat.zero(precision, False)
        var settled = _settled(
            wide, width, _POWER_SLACK, precision, rounding_mode
        )
        if settled:
            return settled.take()
        width += width - precision
    raise Error(
        "the rounding of this power could not be decided; the series is"
        " further from the true value than its stated bound allows"
    )


def _is_one_in_magnitude(x: BigFloat) -> Bool:
    """Whether `|x|` is exactly one.

    Args:
        x: The value.

    Returns:
        True for one and minus one at any precision.
    """
    if not x.is_finite() or x.is_zero():
        return False
    if x.exponent + x.precision != 1:
        return False
    return trailing_zeros(x.significand) == x.precision - 1


def _below_one_in_magnitude(x: BigFloat) -> Bool:
    """Whether `|x|` is below one.

    Args:
        x: The value, finite.

    Returns:
        True when `|x| < 1`, which for a nought is so.
    """
    if x.is_zero():
        return True
    return x.exponent + x.precision <= 0
