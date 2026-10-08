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


"""Pi, the natural logarithm of two, and Euler's number, in binary.

Each is computed rather than quoted, by a series whose terms are integers in
a fixed-point scale of two. Working in integers is what makes the error
countable: every term is one truncating division, so each costs less than a
unit in the last place of the scale, and the scale carries enough bits beyond
what is asked for to leave the total well under a unit of that.

The series are the classical ones. Pi is Machin's, sixteen arctangents of a
fifth less four of a two-hundred-and-thirty-ninth, which costs about a term
for every five bits. The logarithm of two is twice the inverse hyperbolic
tangent of a third, about a term for every three. Euler's number is the sum
of the reciprocal factorials, which costs fewer terms than either because the
terms fall away faster.

None of the three is cached. Each call recomputes, which matters once the
exponential and the logarithm start asking for the logarithm of two on every
call, and a cache is the obvious next thing. It is left out here because a
process-wide one is shared mutable state and deserves its own change.
"""

from std.bit import bit_width

from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.exponential import round_by_deciding
from decimo.bigfloat.rounding import checked_precision
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


comptime _CONSTANT_SLACK = 2
"""Units in the last place a constant's kernel may be off by.

Each kernel works in a scale wide enough that the whole series contributes
less than a unit of what it returns, and the one rounding into that width
costs half of one more.
"""


def _working_width(width: Int) -> Int:
    """How many bits the fixed-point scale carries.

    Args:
        width: The bits wanted in the answer.

    Returns:
        The width plus enough to absorb the series.

    Notes:

    A series of `n` terms, each one truncating division, is off by a few
    units of the scale per term and so by fewer than `3n` in total. A
    truncation costs one unit, and the error already in the running power or
    term is divided down with it at every step -- by `d^2` in the two
    arctangent series, and by `k` in the factorials, which is one for the
    first step and grows from there -- so no term's error reaches three.

    The term count is below the width in all three series, so `3 * width`
    units is a bound, and `bit_width(width) + 8` extra bits of scale leaves
    that below a hundredth of a unit of what is returned.
    """
    return width + Int(bit_width(UInt(width))) + 8


def _arctangent_of_reciprocal(denominator: Int, width: Int) raises -> BigInt:
    """`arctan(1 / denominator)` as an integer scaled by `2^width`.

    Args:
        denominator: The reciprocal's denominator, at least two.
        width: The scale, in bits.

    Returns:
        The scaled value, below the true one by less than two units.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The series is `1/d - 1/(3 d^3) + 1/(5 d^5) - ...`, which the running power
    of `1/d^2` walks through. The power is kept apart from the division by the
    odd number so that the two errors do not compound: the power's own error
    is divided by `d^2` at every step and so stays below one unit, and each
    term adds at most one more of its own.
    """
    var square = BigInt(denominator * denominator)
    var power = (BigInt.one() << width).truncate_divide(BigInt(denominator))
    var total = power.copy()
    var k = 1
    while True:
        power = power.truncate_divide(square)
        if power.is_zero():
            return total^
        var term = power.truncate_divide(BigInt(2 * k + 1))
        if term.is_zero():
            return total^
        if k & 1 != 0:
            total -= term
        else:
            total += term
        k += 1


def _arctangent_hyperbolic_of_reciprocal(
    denominator: Int, width: Int
) raises -> BigInt:
    """`arctanh(1 / denominator)` as an integer scaled by `2^width`.

    Args:
        denominator: The reciprocal's denominator, at least two.
        width: The scale, in bits.

    Returns:
        The scaled value, below the true one by less than two units.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The same series as the arctangent with every sign positive, which is what
    the hyperbolic one is.
    """
    var square = BigInt(denominator * denominator)
    var power = (BigInt.one() << width).truncate_divide(BigInt(denominator))
    var total = power.copy()
    var k = 1
    while True:
        power = power.truncate_divide(square)
        if power.is_zero():
            return total^
        var term = power.truncate_divide(BigInt(2 * k + 1))
        if term.is_zero():
            return total^
        total += term
        k += 1


def _pi_kernel(width: Int) raises -> BigFloat:
    """Pi to `width` bits, by Machin's formula.

    Args:
        width: The bits wanted.

    Returns:
        Pi, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var scale = _working_width(width)
    var total = BigInt(16) * _arctangent_of_reciprocal(5, scale) - BigInt(
        4
    ) * _arctangent_of_reciprocal(239, scale)
    return BigFloat.from_rounded_parts(total, -scale, width, False)


def _ln2_kernel(width: Int) raises -> BigFloat:
    """The natural logarithm of two to `width` bits.

    Args:
        width: The bits wanted.

    Returns:
        The logarithm, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var scale = _working_width(width)
    var total = BigInt(2) * _arctangent_hyperbolic_of_reciprocal(3, scale)
    return BigFloat.from_rounded_parts(total, -scale, width, False)


def _e_kernel(width: Int) raises -> BigFloat:
    """Euler's number to `width` bits, as the sum of the reciprocal factorials.

    Args:
        width: The bits wanted.

    Returns:
        The number, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var scale = _working_width(width)
    var term = BigInt.one() << scale
    var total = term.copy()
    var k = 1
    while True:
        term = term.truncate_divide(BigInt(k))
        if term.is_zero():
            return BigFloat.from_rounded_parts(total, -scale, width, False)
        total += term
        k += 1


def pi(
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """Pi, correctly rounded.

    Args:
        precision: The number of bits wanted. Must be positive.
        rounding_mode: How to round.

    Returns:
        The float of `precision` bits nearest pi.

    Raises:
        ValueError: If `precision` is not positive, or above
            `MAX_PRECISION`.
        Error: Propagated from the arithmetic.
    """
    _ = checked_precision(precision, "pi()")
    return round_by_deciding[_pi_kernel, _CONSTANT_SLACK](
        precision, rounding_mode
    )


def ln2(
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The natural logarithm of two, correctly rounded.

    Args:
        precision: The number of bits wanted. Must be positive.
        rounding_mode: How to round.

    Returns:
        The float of `precision` bits nearest the logarithm.

    Raises:
        ValueError: If `precision` is not positive, or above
            `MAX_PRECISION`.
        Error: Propagated from the arithmetic.

    Notes:

    This is the constant the exponential and the logarithm reduce their
    arguments by, so it is the one whose cost will show first.
    """
    _ = checked_precision(precision, "ln2()")
    return round_by_deciding[_ln2_kernel, _CONSTANT_SLACK](
        precision, rounding_mode
    )


def e(
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """Euler's number, correctly rounded.

    Args:
        precision: The number of bits wanted. Must be positive.
        rounding_mode: How to round.

    Returns:
        The float of `precision` bits nearest the number.

    Raises:
        ValueError: If `precision` is not positive, or above
            `MAX_PRECISION`.
        Error: Propagated from the arithmetic.
    """
    _ = checked_precision(precision, "e()")
    return round_by_deciding[_e_kernel, _CONSTANT_SLACK](
        precision, rounding_mode
    )
