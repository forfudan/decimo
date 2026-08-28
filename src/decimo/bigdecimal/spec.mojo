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
# Implements the operations of the decimal arithmetic specification that
# arithmetic, comparison and rounding do not cover
#
# ===----------------------------------------------------------------------=== #

"""Implements digit-wise, neighbour and total-ordering operations.

These come from the decimal arithmetic specification (IEEE 754-2008 decimal,
the IBM specification) and are the ones a `decimal` program reaches for when
it needs the digits themselves rather than the value: `logical_and` and its
siblings, `shift`, `rotate`, `next_plus`, `next_minus`, `remainder_near`
and `logb`. The total order itself lives with the other comparisons, in
`decimo.bigdecimal.comparison`.

One of the specification's assumptions is not ours: there is no smallest
exponent, so `next_plus(0)` has no answer here and raises. A caller that
wants `decimal`'s `Etiny` answer supplies it from its own context.
"""

from decimo.bigdecimal.bigdecimal import BigDecimal
import decimo.bigdecimal.comparison as bigdecimal_comparison
from decimo.biguint.biguint import BigUInt
from decimo.errors import ValueError, ZeroDivisionError
from decimo.rounding_mode import RoundingMode


# ===----------------------------------------------------------------------=== #
# Digit strings
# ===----------------------------------------------------------------------=== #


def _digits_in_precision(x: BigDecimal, precision: Int) -> String:
    """Returns the coefficient of `x` written in exactly `precision` digits.

    Args:
        x: The value whose coefficient is wanted.
        precision: The number of digits to return.

    Returns:
        The coefficient, padded on the left with zeros when it is shorter
        than `precision` and cut on the left when it is longer, which is what
        the specification means by "the coefficient in the current
        precision".
    """
    var text = x.coefficient.to_string()
    var length = text.byte_length()
    if length == precision:
        return text^
    if length > precision:
        return String(text[byte = length - precision : length])
    return String("0") * (precision - length) + text


def _logical_digits(x: BigDecimal, precision: Int) raises -> String:
    """Returns the digits of a logical operand, or raises if it is not one.

    Args:
        x: The operand to check.
        precision: The number of digits to return.

    Returns:
        The coefficient in `precision` digits.

    Raises:
        ValueError: If `x` is negative, has a non-zero exponent, or has a
            digit other than `0` or `1`, none of which is a logical operand.
    """
    if x.sign or x.scale != 0:
        raise ValueError(
            message=(
                "a logical operand must be a non-negative integer with an"
                " exponent of zero"
            ),
            function="logical operation",
        )
    var text = x.coefficient.to_string()
    for i in range(text.byte_length()):
        if not (text[byte=i] == "0" or text[byte=i] == "1"):
            raise ValueError(
                message="a logical operand may only have the digits 0 and 1",
                function="logical operation",
            )
    return _digits_in_precision(x, precision)


def _is_power_of_ten(value: BigUInt) -> Bool:
    """Returns whether a coefficient is a one followed by zeros.

    Args:
        value: The coefficient to look at.

    Returns:
        True for `1`, `10`, `100` and so on, which is where a step towards
        zero crosses into the decade below.
    """
    var text = value.to_string()
    if not (text[byte=0] == "1"):
        return False
    for i in range(1, text.byte_length()):
        if not (text[byte=i] == "0"):
            return False
    return True


def _from_digits(digits: String) raises -> BigDecimal:
    """Returns the non-negative integer a digit string spells.

    Args:
        digits: The digits, possibly with leading zeros.

    Returns:
        A `BigDecimal` with exponent zero and no sign.

    Raises:
        Error: If the digits cannot be parsed.
    """
    return BigDecimal(BigUInt.from_string(digits), 0, False)


# ===----------------------------------------------------------------------=== #
# Digit-wise logic
# ===----------------------------------------------------------------------=== #


def logical_and(
    x: BigDecimal, y: BigDecimal, precision: Int
) raises -> BigDecimal:
    """Returns the digit-wise `and` of two logical operands.

    Args:
        x: The left operand.
        y: The right operand.
        precision: The number of digits both operands are taken in.

    Returns:
        The digit-wise `and`, as a non-negative integer.

    Raises:
        ValueError: If either operand is not a logical operand.
    """
    var left = _logical_digits(x, precision)
    var right = _logical_digits(y, precision)
    var out = String("")
    for i in range(precision):
        if left[byte=i] == "1" and right[byte=i] == "1":
            out += "1"
        else:
            out += "0"
    return _from_digits(out)


def logical_or(
    x: BigDecimal, y: BigDecimal, precision: Int
) raises -> BigDecimal:
    """Returns the digit-wise `or` of two logical operands.

    Args:
        x: The left operand.
        y: The right operand.
        precision: The number of digits both operands are taken in.

    Returns:
        The digit-wise `or`, as a non-negative integer.

    Raises:
        ValueError: If either operand is not a logical operand.
    """
    var left = _logical_digits(x, precision)
    var right = _logical_digits(y, precision)
    var out = String("")
    for i in range(precision):
        if left[byte=i] == "1" or right[byte=i] == "1":
            out += "1"
        else:
            out += "0"
    return _from_digits(out)


def logical_xor(
    x: BigDecimal, y: BigDecimal, precision: Int
) raises -> BigDecimal:
    """Returns the digit-wise `xor` of two logical operands.

    Args:
        x: The left operand.
        y: The right operand.
        precision: The number of digits both operands are taken in.

    Returns:
        The digit-wise `xor`, as a non-negative integer.

    Raises:
        ValueError: If either operand is not a logical operand.
    """
    var left = _logical_digits(x, precision)
    var right = _logical_digits(y, precision)
    var out = String("")
    for i in range(precision):
        if (left[byte=i] == "1") != (right[byte=i] == "1"):
            out += "1"
        else:
            out += "0"
    return _from_digits(out)


def logical_invert(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Returns the digit-wise inverse of a logical operand.

    Args:
        x: The operand.
        precision: The number of digits the operand is taken in, and so the
            number of digits inverted: at precision 3, `0` inverts to `111`.

    Returns:
        The digit-wise inverse, as a non-negative integer.

    Raises:
        ValueError: If the operand is not a logical operand.
    """
    var digits = _logical_digits(x, precision)
    var out = String("")
    for i in range(precision):
        if digits[byte=i] == "1":
            out += "0"
        else:
            out += "1"
    return _from_digits(out)


# ===----------------------------------------------------------------------=== #
# Digit movement
# ===----------------------------------------------------------------------=== #


def shift(x: BigDecimal, amount: Int, precision: Int) raises -> BigDecimal:
    """Returns `x` with its coefficient shifted, zeros filling in.

    Args:
        x: The value to shift.
        amount: How far to shift, left when positive and right when
            negative. Its magnitude may not exceed `precision`.
        precision: The number of digits the coefficient is taken in.

    Returns:
        A value with the same exponent and sign as `x` and the shifted
        coefficient. Digits shifted out are lost.

    Raises:
        ValueError: If `amount` is larger than `precision` in magnitude.
    """
    if amount > precision or amount < -precision:
        raise ValueError(
            message="the shift may not be larger than the precision",
            function="shift()",
        )
    var digits = _digits_in_precision(x, precision)
    var out: String
    if amount >= 0:
        out = String(digits[byte=amount:precision]) + String("0") * amount
    else:
        out = String("0") * (-amount) + String(
            digits[byte = 0 : precision + amount]
        )
    var result = _from_digits(out)
    result.scale = x.scale
    result.sign = x.sign
    return result^


def rotate(x: BigDecimal, amount: Int, precision: Int) raises -> BigDecimal:
    """Returns `x` with its coefficient rotated.

    Args:
        x: The value to rotate.
        amount: How far to rotate, left when positive and right when
            negative. Its magnitude may not exceed `precision`.
        precision: The number of digits the coefficient is taken in, and so
            the width the digits wrap around.

    Returns:
        A value with the same exponent and sign as `x` and the rotated
        coefficient. No digit is lost.

    Raises:
        ValueError: If `amount` is larger than `precision` in magnitude.
    """
    if amount > precision or amount < -precision:
        raise ValueError(
            message="the rotation may not be larger than the precision",
            function="rotate()",
        )
    var digits = _digits_in_precision(x, precision)
    var cut = amount
    if cut < 0:
        cut += precision
    if cut == precision:
        cut = 0
    var out = String(digits[byte=cut:precision]) + String(digits[byte=0:cut])
    var result = _from_digits(out)
    result.scale = x.scale
    result.sign = x.sign
    return result^


# ===----------------------------------------------------------------------=== #
# Neighbours
# ===----------------------------------------------------------------------=== #


def _neighbour(
    x: BigDecimal, precision: Int, upwards: Bool
) raises -> BigDecimal:
    """Returns the representable value next to `x`.

    Args:
        x: The value to step from. It may not be zero.
        precision: The number of significant digits a value may have.
        upwards: Whether to step towards positive or negative infinity.

    Returns:
        The nearest value in that direction that fits in `precision` digits.

    Raises:
        ValueError: If `x` is zero. Exponents here are unbounded, so there
            is no smallest positive value to step to.
    """
    if x.coefficient.is_zero():
        raise ValueError(
            message=(
                "there is no value next to zero: exponents are unbounded, so"
                " no positive value is the smallest"
            ),
            function="next_plus()/next_minus()",
        )

    # Rounding away from zero's direction lands on the neighbour already,
    # unless `x` was representable to begin with, in which case it lands back
    # on `x` and the step is one unit in the last place.
    var stepped = x.copy()
    stepped.round_to_precision_inplace(
        precision=precision,
        rounding_mode=(
            RoundingMode.ROUND_CEILING if upwards else RoundingMode.ROUND_FLOOR
        ),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    if bigdecimal_comparison.compare(stepped, x) != 0:
        return stepped^

    # One unit in the last place the precision allows, which is not the
    # coefficient's own last digit: a value with fewer digits than the
    # precision still steps by the smaller unit.
    #
    # Stepping towards zero from an exact power of ten crosses into the
    # decade below, where that unit is ten times smaller: below `1` the
    # neighbours are `0.999`, `0.998`, ... at three digits, not `0.99`.
    var exponent = precision - 1 - stepped.adjusted()
    var towards_zero = upwards == stepped.sign
    if towards_zero and _is_power_of_ten(stepped.coefficient):
        exponent += 1
    var unit = BigDecimal(BigUInt.from_word_unsafe(1), exponent, False)
    var result: BigDecimal
    if upwards:
        result = stepped.add(unit, precision=0)
    else:
        result = stepped.subtract(unit, precision=0)
    result.round_to_precision_inplace(
        precision=precision,
        rounding_mode=RoundingMode.ROUND_HALF_EVEN,
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def next_plus(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Returns the smallest representable value larger than `x`.

    Args:
        x: The value to step from. It may not be zero.
        precision: The number of significant digits a value may have.

    Returns:
        The next value towards positive infinity.

    Raises:
        ValueError: If `x` is zero; see `_neighbour()`.
    """
    return _neighbour(x, precision, upwards=True)


def next_minus(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Returns the largest representable value smaller than `x`.

    Args:
        x: The value to step from. It may not be zero.
        precision: The number of significant digits a value may have.

    Returns:
        The next value towards negative infinity.

    Raises:
        ValueError: If `x` is zero; see `_neighbour()`.
    """
    return _neighbour(x, precision, upwards=False)


def next_toward(
    x: BigDecimal, y: BigDecimal, precision: Int
) raises -> BigDecimal:
    """Returns the value next to `x` in the direction of `y`.

    Args:
        x: The value to step from.
        y: The value that gives the direction.
        precision: The number of significant digits a value may have.

    Returns:
        `x` stepped one place towards `y`, or `x` with the sign of `y` when
        the two are numerically equal.

    Raises:
        ValueError: If a step is called for and `x` is zero.
    """
    var order = bigdecimal_comparison.compare(x, y)
    if order < 0:
        return next_plus(x, precision)
    if order > 0:
        return next_minus(x, precision)
    return x.copy_sign(y)


# ===----------------------------------------------------------------------=== #
# Remainder, magnitude and ordering
# ===----------------------------------------------------------------------=== #


def remainder_near(x: BigDecimal, y: BigDecimal) raises -> BigDecimal:
    """Returns `x - y * n`, where `n` is the integer nearest `x / y`.

    Args:
        x: The dividend.
        y: The divisor.

    Returns:
        The remainder, which is at most half of `y` in magnitude and may have
        either sign. Ties in `x / y` go to the even `n`, as in `decimal`.

    Raises:
        ZeroDivisionError: If `y` is zero.
        Error: If the underlying division fails.
    """
    if y.coefficient.is_zero():
        raise ZeroDivisionError(
            message="Division by zero.",
            function="remainder_near()",
        )
    var pair = x.__divmod__(y)
    ref quotient = pair[0]
    ref remainder = pair[1]
    if remainder.coefficient.is_zero():
        # A remainder of zero keeps the sign of the dividend, as in
        # `decimal`: `-1` divided exactly leaves `-0`.
        var zero = remainder.copy()
        zero.sign = x.sign
        return zero^

    # `remainder` is what truncated division leaves, so it is smaller than
    # `y` and carries the sign of `x`. Stepping the quotient one further
    # gives the other candidate, `|y| - |remainder|`; take it when it is the
    # smaller of the two, and on a tie take whichever leaves `n` even.
    var twice = abs(remainder).multiply(BigDecimal(2), precision=0)
    var order = bigdecimal_comparison.compare(twice, abs(y))
    var step: Bool
    if order > 0:
        step = True
    elif order == 0:
        step = quotient.is_odd()
    else:
        step = False
    if not step:
        return remainder.copy()
    if remainder.sign == y.sign:
        return remainder.subtract(y, precision=0)
    return remainder.add(y, precision=0)


def max_absolute(x: BigDecimal, y: BigDecimal) raises -> BigDecimal:
    """Returns the operand with the larger magnitude.

    Args:
        x: The left operand.
        y: The right operand.

    Returns:
        The operand whose absolute value is larger, and the larger of the two
        when the magnitudes are equal.

    Raises:
        Error: If the underlying comparison fails.
    """
    var order = bigdecimal_comparison.compare_absolute(x, y)
    if order > 0:
        return x.copy()
    if order < 0:
        return y.copy()
    return bigdecimal_comparison.max(x, y)


def min_absolute(x: BigDecimal, y: BigDecimal) raises -> BigDecimal:
    """Returns the operand with the smaller magnitude.

    Args:
        x: The left operand.
        y: The right operand.

    Returns:
        The operand whose absolute value is smaller, and the smaller of the
        two when the magnitudes are equal.

    Raises:
        Error: If the underlying comparison fails.
    """
    var order = bigdecimal_comparison.compare_absolute(x, y)
    if order < 0:
        return x.copy()
    if order > 0:
        return y.copy()
    return bigdecimal_comparison.min(x, y)


def logb(x: BigDecimal) raises -> BigDecimal:
    """Returns the exponent of the leading digit of `x`, as an integer.

    Args:
        x: The value to take the exponent of.

    Returns:
        The adjusted exponent: `2` for `123`, `-3` for `0.00123`.

    Raises:
        ZeroDivisionError: If `x` is zero. `decimal` answers `-Infinity`
            here, which is not a value decimo has.
    """
    if x.coefficient.is_zero():
        raise ZeroDivisionError(
            message="logb(0) has no answer without an infinity to give.",
            function="logb()",
        )
    return BigDecimal(x.adjusted())


def number_class(x: BigDecimal) -> String:
    """Returns the specification's name for what kind of number `x` is.

    Args:
        x: The value to describe.

    Returns:
        One of `"+Zero"`, `"-Zero"`, `"+Normal"` and `"-Normal"`. Exponents
        are unbounded here, so no finite value is ever subnormal, and there
        are no infinities or NaNs to name.
    """
    if x.coefficient.is_zero():
        return "-Zero" if x.sign else "+Zero"
    return "-Normal" if x.sign else "+Normal"
