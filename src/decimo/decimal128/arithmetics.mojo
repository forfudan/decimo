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
# Implements basic arithmetic functions for the Decimal128 type
#
# ===----------------------------------------------------------------------=== #
#
# List of functions in this module:
#
# add(x1: Decimal128, x2: Decimal128): Adds two Decimal128 values and returns a new Decimal128 containing the sum
# subtract(x1: Decimal128, x2: Decimal128): Subtracts the x2 Decimal128 from x1 and returns a new Decimal128
# multiply(x1: Decimal128, x2: Decimal128): Multiplies two Decimal128 values and returns a new Decimal128 containing the product
# true_divide(x1: Decimal128, x2: Decimal128): Divides x1 by x2 and returns a new Decimal128 containing the quotient
#
# ===----------------------------------------------------------------------=== #

"""
Implements functions for mathematical operations on Decimal128 objects.
"""

from std import time
from std import testing

from decimo.decimal128.decimal128 import Decimal128
from decimo.rounding_mode import RoundingMode
from decimo.errors import (
    OverflowError,
    ZeroDivisionError,
)
import decimo.decimal128.utility


@always_inline
def add(x1: Decimal128, x2: Decimal128) raises -> Decimal128:
    """
    Adds two Decimal128 values and returns a new Decimal128 containing the sum.
    The results will be rounded (up to even) if digits are too many.

    Args:
        x1: The first Decimal128 operand.
        x2: The second Decimal128 operand.

    Returns:
        A new Decimal128 containing the sum of x1 and x2.

    Raises:
        OverflowError: If the result overflows Decimal128 capacity.
    """
    var x1_coef = x1.coefficient()
    var x2_coef = x2.coefficient()
    var x1_scale = x1.scale()
    var x2_scale = x2.scale()

    # CASE: Same scale (UInt128 fast path)
    #
    # NOTE: Placed FIRST because it dominates real-world workloads (financial /
    # fixed-precision code where both operands carry the same scale) and is a
    # single UInt128 add. Two same-scale integers are also handled here: their
    # coefficients are proportional and the UInt128 sum with the preserved
    # scale gives the right answer (e.g. coef=1000 + coef=2000 with scale=3
    # gives "3.000"). The previous version separated this case from a
    # `is_integer()` branch; benchmarking showed the dispatch test alone cost
    # ~250 ns of UInt128 modulus while the same-scale path completes in ~3 ns,
    # so the integer branch was a net loss and is gone.
    if x1_scale == x2_scale:
        var summation: UInt128
        var is_negative: Bool

        if x1.is_negative() == x2.is_negative():
            is_negative = x1.is_negative()
            summation = x1_coef + x2_coef
        else:  # Different signs
            if x1_coef > x2_coef:
                summation = x1_coef - x2_coef
                is_negative = x1.is_negative()
            elif x1_coef < x2_coef:
                summation = x2_coef - x1_coef
                is_negative = x2.is_negative()
            else:
                return Decimal128.from_uint128(
                    UInt128(0), UInt32(x1_scale), False
                )

        if summation < Decimal128.MAX_AS_UINT128:
            # Canonicalize -0 + -0 (or any all-zero result) to +0.
            return Decimal128.from_uint128(
                summation,
                UInt32(x1_scale),
                False if summation == 0 else is_negative,
            )

        # >= 29 digits: drop trailing digits to fit. If we'd need to drop more
        # digits than `x1_scale` provides, the result truly overflows.
        var fitted = decimo.decimal128.utility.fit_to_max_coefficient(summation)
        if UInt32(fitted[1]) > UInt32(x1_scale):
            raise OverflowError(
                message="Decimal128 overflow in addition.",
                function="add()",
            )
        var final_scale = UInt32(x1_scale) - UInt32(fitted[1])
        return Decimal128.from_uint128(fitted[0], final_scale, is_negative)

    # CASE: One operand is zero (different scales)
    #
    # Promote the non-zero operand to max(x1_scale, x2_scale) so e.g.
    # `0.000 + 5` returns "5.000". Skips the UInt256 work below. Both-zero
    # returns positive zero at the higher scale (so `0.0 + -0.00 == 0.00`).
    if x1_coef == 0 and x2_coef == 0:
        return Decimal128(0, 0, 0, UInt32(max(x1_scale, x2_scale)), False)

    if x1_coef == 0:
        if x1_scale <= x2_scale:
            return x2
        var sum_coef = x2_coef
        var scale = min(
            max(x1_scale, x2_scale),
            Decimal128.MAX_NUM_DIGITS
            - decimo.decimal128.utility.number_of_digits(x2.to_uint128()),
        )
        ## If x2_coef > 7922816251426433759354395033
        if (
            (x2_coef > Decimal128.MAX_AS_UINT128 // 10)
            and (scale > 0)
            and (scale > x2_scale)
        ):
            scale -= 1
        sum_coef *= decimo.decimal128.utility.power_of_10_unsafe[DType.uint128](
            Int(scale - x2_scale)
        )
        return Decimal128.from_uint128(
            sum_coef, UInt32(scale), x2.is_negative()
        )

    if x2_coef == 0:
        if x2_scale <= x1_scale:
            return x1
        var sum_coef = x1_coef
        var scale = min(
            max(x1_scale, x2_scale),
            Decimal128.MAX_NUM_DIGITS
            - decimo.decimal128.utility.number_of_digits(x1.to_uint128()),
        )
        ## If x1_coef > 7922816251426433759354395033
        if (
            (x1_coef > Decimal128.MAX_AS_UINT128 // 10)
            and (scale > 0)
            and (scale > x1_scale)
        ):
            scale -= 1
        sum_coef *= decimo.decimal128.utility.power_of_10_unsafe[DType.uint128](
            Int(scale - x1_scale)
        )
        return Decimal128.from_uint128(
            sum_coef, UInt32(scale), x1.is_negative()
        )

    # CASE: Different scales, both non-zero (UInt256 path)
    var summation: UInt256
    var is_negative: Bool

    if x1_scale > x2_scale:
        # Scale up x2_coef to match x1_scale
        var x1_coef_scaled: UInt256 = UInt256(x1_coef)
        var x2_coef_scaled: UInt256 = UInt256(
            x2_coef
        ) * decimo.decimal128.utility.power_of_10_unsafe[DType.uint256](
            Int(x1_scale - x2_scale)
        )

        if x1.is_negative() == x2.is_negative():
            is_negative = x1.is_negative()
            summation = x1_coef_scaled + x2_coef_scaled
        else:  # Different signs
            if x1_coef_scaled > x2_coef_scaled:
                summation = x1_coef_scaled - x2_coef_scaled
                is_negative = x1.is_negative()
            elif x1_coef_scaled < x2_coef_scaled:
                summation = x2_coef_scaled - x1_coef_scaled
                is_negative = x2.is_negative()
            else:
                return Decimal128.from_uint128(
                    UInt128(0), UInt32(x1_scale), False
                )

    else:  # x1_scale < x2_scale
        # Scale up x1_coef to match x2_scale
        var x1_coef_scaled: UInt256 = UInt256(
            x1_coef
        ) * decimo.decimal128.utility.power_of_10_unsafe[DType.uint256](
            Int(x2_scale - x1_scale)
        )
        var x2_coef_scaled: UInt256 = UInt256(x2_coef)

        if x1.is_negative() == x2.is_negative():
            is_negative = x1.is_negative()
            summation = x2_coef_scaled + x1_coef_scaled
        else:  # Different signs
            if x1_coef_scaled > x2_coef_scaled:
                summation = x1_coef_scaled - x2_coef_scaled
                is_negative = x1.is_negative()
            elif x1_coef_scaled < x2_coef_scaled:
                summation = x2_coef_scaled - x1_coef_scaled
                is_negative = x2.is_negative()
            else:
                return Decimal128.from_uint128(
                    UInt128(0), UInt32(x2_scale), False
                )

    if summation < Decimal128.MAX_AS_UINT256:
        return Decimal128.from_uint128(
            UInt128(summation & 0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFF),
            UInt32(max(x1_scale, x2_scale)),
            is_negative,
        )

    var fitted = decimo.decimal128.utility.fit_to_max_coefficient(summation)
    var working_scale = UInt32(max(x1_scale, x2_scale))
    if UInt32(fitted[1]) > working_scale:
        raise OverflowError(
            message="Addition result exceeds Decimal128 precision.",
            function="add()",
        )
    var final_scale = working_scale - UInt32(fitted[1])
    return Decimal128.from_uint128(
        UInt128(fitted[0] & 0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFF),
        final_scale,
        is_negative,
    )


@always_inline
def subtract(x1: Decimal128, x2: Decimal128) raises -> Decimal128:
    """
    Subtracts the x2 Decimal128 from x1 and returns a new Decimal128.

    Args:
        x1: The Decimal128 to subtract from.
        x2: The Decimal128 to subtract.

    Returns:
        A new Decimal128 containing the difference.

    Raises:
        OverflowError: If the result overflows Decimal128 capacity.

    Examples:
    ---------
    ```console
    var a = Decimal128("10.5")
    var b = Decimal128("3.2")
    var result = a - b  # Returns 7.3
    ```
    .
    """
    var x1_coef = x1.coefficient()
    var x2_coef = x2.coefficient()
    var x1_scale = x1.scale()

    # CASE: Same scale (UInt128 fast path)
    #
    # x1 - x2 = x1 + (-x2). The "same effective sign" branch (which adds the
    # coefficients) is reached when x1.is_negative() *differs* from
    # x2.is_negative(). Inlined here so the common case avoids both the
    # `negative()` allocation and the dispatch through `add()` below.
    if x1_scale == x2.scale():
        var summation: UInt128
        var is_negative: Bool

        if x1.is_negative() != x2.is_negative():
            is_negative = x1.is_negative()
            summation = x1_coef + x2_coef
        else:  # Different effective signs
            if x1_coef > x2_coef:
                summation = x1_coef - x2_coef
                is_negative = x1.is_negative()
            elif x1_coef < x2_coef:
                summation = x2_coef - x1_coef
                # Result takes the sign of -x2.
                is_negative = not x2.is_negative()
            else:
                return Decimal128.from_uint128(
                    UInt128(0), UInt32(x1_scale), False
                )

        if summation < Decimal128.MAX_AS_UINT128:
            # Canonicalize -0 - +0 (or any all-zero result) to +0.
            return Decimal128.from_uint128(
                summation,
                UInt32(x1_scale),
                False if summation == 0 else is_negative,
            )

        var fitted = decimo.decimal128.utility.fit_to_max_coefficient(summation)
        if UInt32(fitted[1]) > UInt32(x1_scale):
            raise OverflowError(
                message="Decimal128 overflow in subtraction.",
                function="subtract()",
            )
        var final_scale = UInt32(x1_scale) - UInt32(fitted[1])
        return Decimal128.from_uint128(fitted[0], final_scale, is_negative)

    # CASE: One operand is zero (different scales)
    #
    # Same as the corresponding case in add() but with x2's sign flipped
    # since x1 - x2 = x1 + (-x2). Both-zero returns positive zero at the
    # higher scale (so `0.0 - -0.00 == 0.00`).
    if x1_coef == 0 and x2_coef == 0:
        return Decimal128(0, 0, 0, UInt32(max(x1_scale, x2.scale())), False)

    var x2_scale = x2.scale()

    if x1_coef == 0:
        if x1_scale <= x2_scale:
            return negative(x2)
        var sum_coef = x2_coef
        var scale = min(
            max(x1_scale, x2_scale),
            Decimal128.MAX_NUM_DIGITS
            - decimo.decimal128.utility.number_of_digits(x2.to_uint128()),
        )
        ## If x2_coef > 7922816251426433759354395033
        if (
            (x2_coef > Decimal128.MAX_AS_UINT128 // 10)
            and (scale > 0)
            and (scale > x2_scale)
        ):
            scale -= 1
        sum_coef *= decimo.decimal128.utility.power_of_10_unsafe[DType.uint128](
            Int(scale - x2_scale)
        )
        # Sign of result is sign of -x2.
        return Decimal128.from_uint128(
            sum_coef, UInt32(scale), not x2.is_negative()
        )

    if x2_coef == 0:
        if x2_scale <= x1_scale:
            return x1
        var sum_coef = x1_coef
        var scale = min(
            max(x1_scale, x2_scale),
            Decimal128.MAX_NUM_DIGITS
            - decimo.decimal128.utility.number_of_digits(x1.to_uint128()),
        )
        ## If x1_coef > 7922816251426433759354395033
        if (
            (x1_coef > Decimal128.MAX_AS_UINT128 // 10)
            and (scale > 0)
            and (scale > x1_scale)
        ):
            scale -= 1
        sum_coef *= decimo.decimal128.utility.power_of_10_unsafe[DType.uint128](
            Int(scale - x1_scale)
        )
        return Decimal128.from_uint128(
            sum_coef, UInt32(scale), x1.is_negative()
        )

    # CASE: Different scales, both non-zero (UInt256 path)
    #
    # Same as add() with x2's effective sign flipped: the "same effective
    # sign" branch (which adds the coefficients) fires when x1 and x2 have
    # *different* original signs (because then x1 and -x2 agree).
    var diff: UInt256
    var is_negative: Bool

    if x1_scale > x2_scale:
        var x1_coef_scaled: UInt256 = UInt256(x1_coef)
        var x2_coef_scaled: UInt256 = UInt256(
            x2_coef
        ) * decimo.decimal128.utility.power_of_10_unsafe[DType.uint256](
            Int(x1_scale - x2_scale)
        )

        if x1.is_negative() != x2.is_negative():
            is_negative = x1.is_negative()
            diff = x1_coef_scaled + x2_coef_scaled
        else:  # Same original signs -> different effective signs
            if x1_coef_scaled > x2_coef_scaled:
                diff = x1_coef_scaled - x2_coef_scaled
                is_negative = x1.is_negative()
            elif x1_coef_scaled < x2_coef_scaled:
                diff = x2_coef_scaled - x1_coef_scaled
                # Sign of -x2.
                is_negative = not x2.is_negative()
            else:
                return Decimal128.from_uint128(
                    UInt128(0), UInt32(x1_scale), False
                )

    else:  # x1_scale < x2_scale
        var x1_coef_scaled: UInt256 = UInt256(
            x1_coef
        ) * decimo.decimal128.utility.power_of_10_unsafe[DType.uint256](
            Int(x2_scale - x1_scale)
        )
        var x2_coef_scaled: UInt256 = UInt256(x2_coef)

        if x1.is_negative() != x2.is_negative():
            is_negative = x1.is_negative()
            diff = x2_coef_scaled + x1_coef_scaled
        else:
            if x1_coef_scaled > x2_coef_scaled:
                diff = x1_coef_scaled - x2_coef_scaled
                is_negative = x1.is_negative()
            elif x1_coef_scaled < x2_coef_scaled:
                diff = x2_coef_scaled - x1_coef_scaled
                is_negative = not x2.is_negative()
            else:
                return Decimal128.from_uint128(
                    UInt128(0), UInt32(x2_scale), False
                )

    if diff < Decimal128.MAX_AS_UINT256:
        return Decimal128.from_uint128(
            UInt128(diff & 0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFF),
            UInt32(max(x1_scale, x2_scale)),
            is_negative,
        )

    var fitted = decimo.decimal128.utility.fit_to_max_coefficient(diff)
    var working_scale = UInt32(max(x1_scale, x2_scale))
    if UInt32(fitted[1]) > working_scale:
        raise OverflowError(
            message="Subtraction result exceeds Decimal128 precision.",
            function="subtract()",
        )
    var final_scale = working_scale - UInt32(fitted[1])
    return Decimal128.from_uint128(
        UInt128(fitted[0] & 0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFF),
        final_scale,
        is_negative,
    )


def negative(x: Decimal128) -> Decimal128:
    """
    Returns the negative of a Decimal128 number.

    Args:
        x: The Decimal128 value to compute the negative of.

    Returns:
        A new Decimal128 containing the negative of x.
    """

    var result = x

    if x.is_zero():
        # Set the sign bit to 0 and keep the scale bits
        result.flags &= ~Decimal128.SIGN_MASK

    else:
        result.flags ^= Decimal128.SIGN_MASK  # Flip sign bit

    return result


def absolute(x: Decimal128) -> Decimal128:
    """
    Returns the absolute value of a Decimal128 number.

    Args:
        x: The Decimal128 value to compute the absolute value of.

    Returns:
        A new Decimal128 containing the absolute value of x.
    """
    if x.is_negative():
        return -x
    return x


@always_inline
def multiply(x1: Decimal128, x2: Decimal128) raises -> Decimal128:
    """
    Multiplies two Decimal128 values and returns a new Decimal128 containing the product.

    Args:
        x1: The first Decimal128 operand.
        x2: The second Decimal128 operand.

    Returns:
        A new Decimal128 containing the product of x1 and x2.

    Raises:
        OverflowError: If the product overflows Decimal128 capacity.
    """

    var x1_coef = x1.coefficient()
    var x2_coef = x2.coefficient()
    var x1_scale = x1.scale()
    var x2_scale = x2.scale()
    var combined_scale = x1_scale + x2_scale
    var is_negative = x1.is_negative() != x2.is_negative()

    # SPECIAL CASE: true one
    # Return the other operand
    if x1.low == 1 and x1.mid == 0 and x1.high == 0 and x1.flags == 0:
        return x2
    if x2.low == 1 and x2.mid == 0 and x2.high == 0 and x2.flags == 0:
        return x1

    # SPECIAL CASE: zero
    # Return zero while preserving the scale
    if x1_coef == 0 or x2_coef == 0:
        return Decimal128(
            0,
            0,
            0,
            scale=UInt32(min(combined_scale, Decimal128.MAX_SCALE)),
            sign=is_negative,
        )

    # SPECIAL CASE: Both operands have coefficient of 1
    if x1_coef == 1 and x2_coef == 1:
        # If the combined scale exceeds the maximum precision,
        # return 0 with leading zeros after the decimal point and correct sign
        if combined_scale > Decimal128.MAX_SCALE:
            return Decimal128(
                0,
                0,
                0,
                UInt32(Decimal128.MAX_SCALE),
                is_negative,
            )
        # Otherwise, return 1 with correct sign and scale
        var final_scale = UInt32(min(Decimal128.MAX_SCALE, combined_scale))
        return Decimal128(1, 0, 0, final_scale, is_negative)

    # SPECIAL CASE: First operand has coefficient of 1
    if x1_coef == 1:
        # If x1 is 1, return x2 with correct sign
        if x1_scale == 0:
            var result = x2
            result.flags &= ~Decimal128.SIGN_MASK
            if is_negative:
                result.flags |= Decimal128.SIGN_MASK
            return result
        else:
            var prod = x2_coef
            # Rounding may be needed.
            var truncated_prod = decimo.decimal128.utility.round_coefficient(
                prod,
                ndigits_to_remove=combined_scale - Decimal128.MAX_SCALE,
            )
            var final_scale = UInt32(min(Decimal128.MAX_SCALE, combined_scale))
            return Decimal128.from_uint128(
                truncated_prod, final_scale, is_negative
            )

    # SPECIAL CASE: Second operand has coefficient of 1
    if x2_coef == 1:
        # If x2 is 1, return x1 with correct sign
        if x2_scale == 0:
            var result = x1
            result.flags &= ~Decimal128.SIGN_MASK
            if is_negative:
                result.flags |= Decimal128.SIGN_MASK
            return result
        else:
            var prod = x1_coef
            # Rounding may be needed.
            var truncated_prod = decimo.decimal128.utility.round_coefficient(
                prod,
                ndigits_to_remove=combined_scale - Decimal128.MAX_SCALE,
            )
            var final_scale = UInt32(min(Decimal128.MAX_SCALE, combined_scale))
            return Decimal128.from_uint128(
                truncated_prod, final_scale, is_negative
            )

    # Determine the number of bits in the coefficients
    # Used to determine the appropriate multiplication method
    # The coefficient of result would be the sum of the two numbers of bits
    var x1_num_bits = decimo.decimal128.utility.number_of_bits(x1_coef)
    var x2_num_bits = decimo.decimal128.utility.number_of_bits(x2_coef)
    var combined_num_bits = x1_num_bits + x2_num_bits

    # SPECIAL CASE: Both operands are true integers
    if x1_scale == 0 and x2_scale == 0:
        # Small integers, use UInt64 multiplication
        if combined_num_bits <= 64:
            var prod: UInt64 = UInt64(x1_coef) * UInt64(x2_coef)
            var low = UInt32(prod & 0xFFFFFFFF)
            var mid = UInt32((prod >> 32) & 0xFFFFFFFF)
            return Decimal128(low, mid, 0, 0, is_negative)

        # Moderate integers, use UInt128 multiplication
        elif combined_num_bits <= 128:
            var prod: UInt128 = UInt128(x1_coef) * UInt128(x2_coef)
            if prod > Decimal128.MAX_AS_UINT128:
                raise OverflowError(
                    message=String(
                        "The product {} exceeds Decimal128 capacity."
                    ).format(prod),
                    function="multiply()",
                )
            else:
                return Decimal128.from_uint128(prod, 0, is_negative)

        # Large integers, it will definitely overflow
        else:
            var prod: UInt256 = UInt256(x1_coef) * UInt256(x2_coef)
            raise OverflowError(
                message=String(
                    "The product {} exceeds Decimal128 capacity."
                ).format(prod),
                function="multiply()",
            )

    # NOTE: A previous version had a separate branch here for
    # `x1.is_integer() and x2.is_integer()` (e.g. `123.0 * 456.00`) that
    # divided each coefficient by `10^scale`, multiplied the integral parts
    # in UInt256, and rescaled. Empirically that branch was a catastrophic
    # net loss: the dispatch alone (two `is_integer()` calls, each up to
    # ~125 ns of UInt128 modulus even with the cheap pre-check) plus the
    # UInt256 multiply + UInt256 power-of-10 rescale cost ~550-760 ns,
    # while the same inputs fall through to the `combined_num_bits <= 96`
    # UInt128 fast path below in ~5 ns (the integral parts already share
    # all trailing zeros that disappear during rounding). Removing the
    # branch made `Both integer, different scale` cases drop from
    # 548-759 ns to ~4-7 ns (~100x).

    # GENERAL CASES: Decimal128 multiplication with any scales

    # SUB-CASE: Both operands are small
    # The bits of the product will not exceed 96 bits
    # It can just fit into Decimal128's capacity without overflow
    # Result coefficient will less than 2^96 - 1 = 79228162514264337593543950335
    # Examples: 1.23 * 4.56
    if combined_num_bits <= 96:
        var prod: UInt128 = x1_coef * x2_coef

        # Combined scale more than max precision, no need to truncate
        if combined_scale <= Decimal128.MAX_SCALE:
            return Decimal128.from_uint128(
                prod, UInt32(combined_scale), is_negative
            )

        # Combined scale exceeds MAX_SCALE: round and clamp to MAX_SCALE.
        # We're in the `else` of `combined_scale <= MAX_SCALE`, so the
        # subsequent `min(MAX_SCALE, combined_scale)` always yielded
        # MAX_SCALE and the second-pass rounding branch was dead code.
        else:
            prod = decimo.decimal128.utility.round_coefficient(
                prod,
                ndigits_to_remove=combined_scale - Decimal128.MAX_SCALE,
            )
            return Decimal128.from_uint128(
                prod, UInt32(Decimal128.MAX_SCALE), is_negative
            )

    # SUB-CASE: Both operands are moderate
    # The bits of the product will not exceed 128 bits
    # Result coefficient will less than 2^128 - 1 but more than 2^96 - 1
    # IMPORTANT: This means that the product will exceed Decimal128's capacity
    # Either raises an error if intergral part overflows
    # Or truncates the product to fit into Decimal128's capacity

    if combined_num_bits <= 128:
        var prod: UInt128 = x1_coef * x2_coef

        # Fast path: product already fits Decimal128 capacity and the
        # combined scale is in range — return without any rounding work.
        if (
            prod <= Decimal128.MAX_AS_UINT128
            and combined_scale <= Decimal128.MAX_SCALE
        ):
            return Decimal128.from_uint128(
                prod, UInt32(combined_scale), is_negative
            )

        # Single-pass rounding: compute the total digits to drop so that
        # both the coefficient (≤ MAX_AS_UINT128) and the scale (≤
        # MAX_SCALE) constraints are satisfied in one `round_coefficient`
        # call. Saves the extra `number_of_digits` + wide divide that the
        # old `fit_to_max_coefficient` + re-round pattern incurred.
        var ndigits = decimo.decimal128.utility.number_of_digits(prod)
        var drop_for_scale = Int(combined_scale) - Decimal128.MAX_SCALE
        var drop_for_fit: Int
        if prod > Decimal128.MAX_AS_UINT128:
            # 29-digit values that still exceed MAX_AS_UINT128 need one
            # explicit digit removed (`max(1, ndigits - 29)` handles both
            # the boundary and any larger overflow uniformly).
            drop_for_fit = max(1, ndigits - Decimal128.MAX_NUM_DIGITS)
        else:
            drop_for_fit = 0

        var drop = max(drop_for_scale, drop_for_fit)
        if drop > Int(combined_scale):
            raise OverflowError(
                message="Decimal128 overflow in multiplication.",
                function="multiply()",
            )

        var rounded = decimo.decimal128.utility.round_coefficient[
            skip_digit_check=True
        ](prod, ndigits_to_remove=drop)
        # Rounding-up may carry into a new most-significant digit, pushing
        # the result past MAX_AS_UINT128. Drop one more digit if so.
        if rounded > Decimal128.MAX_AS_UINT128:
            drop += 1
            if drop > Int(combined_scale):
                raise OverflowError(
                    message="Decimal128 overflow in multiplication.",
                    function="multiply()",
                )
            rounded = decimo.decimal128.utility.round_coefficient[
                skip_digit_check=True
            ](prod, ndigits_to_remove=drop)

        var final_scale = Int(combined_scale) - drop
        return Decimal128.from_uint128(
            rounded, UInt32(final_scale), is_negative
        )

    # REMAINING CASES: Both operands are big
    # The bits of the product will not exceed 192 bits
    # Result coefficient will less than 2^192 - 1 but more than 2^128 - 1
    # IMPORTANT: This means that the product will exceed Decimal128's capacity
    # Either raises an error if intergral part overflows
    # Or truncates the product to fit into Decimal128's capacity

    var prod: UInt256 = UInt256(x1_coef) * UInt256(x2_coef)

    # Single-pass rounding: compute the total digits to drop so that
    # both the coefficient (≤ MAX_AS_UINT128) and the scale (≤ MAX_SCALE)
    # constraints are satisfied in one `round_coefficient` call. Saves
    # the extra UInt256 division that the old `fit_to_max_coefficient`
    # + re-round pattern incurred.
    var ndigits = decimo.decimal128.utility.number_of_digits(prod)
    var drop_for_scale = Int(combined_scale) - Decimal128.MAX_SCALE
    var drop_for_fit: Int
    if prod > UInt256(Decimal128.MAX_AS_UINT128):
        drop_for_fit = max(1, ndigits - Decimal128.MAX_NUM_DIGITS)
    else:
        drop_for_fit = 0

    var drop = max(drop_for_scale, drop_for_fit)
    if drop > Int(combined_scale):
        raise OverflowError(
            message="Decimal128 overflow in multiplication.",
            function="multiply()",
        )

    var rounded = decimo.decimal128.utility.round_coefficient[
        skip_digit_check=True
    ](prod, ndigits_to_remove=drop)
    # Rounding-up may carry into a new most-significant digit, pushing
    # the result past MAX_AS_UINT128. Re-round the ORIGINAL `prod` (not
    # the already-rounded value) with one more digit dropped to avoid
    # double-rounding artifacts.
    if rounded > UInt256(Decimal128.MAX_AS_UINT128):
        drop += 1
        if drop > Int(combined_scale):
            raise OverflowError(
                message="Decimal128 overflow in multiplication.",
                function="multiply()",
            )
        rounded = decimo.decimal128.utility.round_coefficient[
            skip_digit_check=True
        ](prod, ndigits_to_remove=drop)

    var final_scale = Int(combined_scale) - drop

    # Extract the 32-bit components from the UInt256 product
    var low = UInt32(rounded & 0xFFFFFFFF)
    var mid = UInt32((rounded >> 32) & 0xFFFFFFFF)
    var high = UInt32((rounded >> 64) & 0xFFFFFFFF)

    return Decimal128(low, mid, high, UInt32(final_scale), is_negative)


def divide(x1: Decimal128, x2: Decimal128) raises -> Decimal128:
    """
    Divides x1 by x2 and returns a new Decimal128 containing the quotient.
    Uses a simpler string-based long division approach as fallback.

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        A new Decimal128 containing the result of x1 / x2.

    Raises:
        ZeroDivisionError: If the divisor is zero.
        OverflowError: If the result overflows Decimal128 capacity.
    """

    # Treatment for special cases
    # 對各類特殊情況進行處理

    # SPECIAL CASE: zero divisor
    # 特例: 除數爲零
    # Check for division by zero
    if x2.is_zero():
        raise ZeroDivisionError(
            message="Division by zero.",
            function="divide()",
        )

    # SPECIAL CASE: zero dividend
    # If dividend is zero, return zero with appropriate scale
    # The final scale is the (scale 1 - scale 2) floored to 0
    # For example, 0.000 / 1234.0 = 0.00
    # For example, 0.00 / 1.3456 = 0
    if x1.is_zero():
        var result = Decimal128.ZERO()
        var result_scale = max(0, x1.scale() - x2.scale())
        result.flags = (
            UInt32(result_scale) << Decimal128.SCALE_SHIFT
        ) & Decimal128.SCALE_MASK
        return result

    var x1_coef = x1.coefficient()
    var x2_coef = x2.coefficient()
    var x1_scale = x1.scale()
    var x2_scale = x2.scale()
    var diff_scale = x1_scale - x2_scale
    var is_negative = x1.is_negative() != x2.is_negative()

    # SPECIAL CASE: one dividend or coefficient of dividend is one
    # 特例: 除數爲一或者除數的係數爲一
    # Return divisor with appropriate scale and sign
    # For example, 1.412 / 1 = 1.412
    # For example, 10.123 / 0.0001 = 101230
    # For example, 1991.10180000 / 0.01 = 199110.180000
    if x2_coef == 1:
        # SUB-CASE: divisor is 1
        # If divisor is 1, return dividend with correct sign
        if x2_scale == 0:
            return Decimal128(
                x1.low, x1.mid, x1.high, UInt32(x1_scale), is_negative
            )

        # SUB-CASE: divisor is of coefficient 1 with positive scale
        # diff_scale > 0, then final scale is diff_scale
        elif diff_scale > 0:
            return Decimal128(
                x1.low, x1.mid, x1.high, UInt32(diff_scale), is_negative
            )

        # diff_scale < 0, then times 10 ** (-diff_scale)
        else:
            # If the result can be stored in UInt128
            if (
                decimo.decimal128.utility.number_of_digits(x1_coef) - diff_scale
                < Decimal128.MAX_NUM_DIGITS
            ):
                var quot = (
                    x1_coef
                    * decimo.decimal128.utility.power_of_10_unsafe[
                        DType.uint128
                    ](Int(-diff_scale))
                )
                return Decimal128.from_uint128(quot, 0, is_negative)

            # If the result should be stored in UInt256
            else:
                var quot = UInt256(
                    x1_coef
                ) * decimo.decimal128.utility.power_of_10_unsafe[DType.uint256](
                    Int(-diff_scale)
                )
                if quot > Decimal128.MAX_AS_UINT256:
                    raise OverflowError(
                        message="Decimal128 overflow in division.",
                        function="divide()",
                    )
                else:
                    var low = UInt32(quot & 0xFFFFFFFF)
                    var mid = UInt32((quot >> 32) & 0xFFFFFFFF)
                    var high = UInt32((quot >> 64) & 0xFFFFFFFF)
                    return Decimal128(low, mid, high, 0, is_negative)

    # SPECIAL CASE: The coefficients are equal
    # 特例: 係數相等
    # For example, 1234.5678 / 1234.5678 = 1.0000
    # Return 1 with appropriate scale and sign
    if x1_coef == x2_coef:
        # SUB-CASE: The scales are equal
        # If the scales are equal, return 1 with the scale of 0
        # For example, 1234.5678 / 1234.5678 = 1
        # SUB-CASE: The scales are positive
        # If the scales are positive, return 1 with the difference in scales
        # For example, 0.1234 / 1234 = 0.0001
        if diff_scale >= 0:
            return Decimal128(1, 0, 0, UInt32(diff_scale), is_negative)

        # SUB-CASE: The scales are negative
        # diff_scale < 0, then times 1e-diff_scale
        # For example, 1234 / 0.1234 = 10000
        # Since -diff_scale is less than 28, the result would not overflow
        else:
            var quot = UInt128(
                1
            ) * decimo.decimal128.utility.power_of_10_unsafe[DType.uint128](
                Int(-diff_scale)
            )
            return Decimal128.from_uint128(quot, 0, is_negative)

    # SPECIAL CASE: Modulus of coefficients is zero (exact division)
    # 特例: 係數的餘數爲零 (可除盡)
    # For example, 32 / 2 = 16
    # For example, 18.00 / 3.0 = 6.0
    # For example, 123456780000 / 1000 = 123456780
    # For example, 246824.68 / 12.341234 = 20000
    if x1_coef % x2_coef == 0:
        if diff_scale >= 0:
            # If diff_scale >= 0, return the quotient with diff_scale
            # Yuhao's notes:
            # Because the dividor == 1 has been handled before dividor shoud be greater than 1
            # High will be zero because the quotient is less than 2^48
            # For safety, we still calcuate the high word
            var quot = x1_coef // x2_coef
            return Decimal128.from_uint128(
                quot, UInt32(diff_scale), is_negative
            )

        else:
            # If diff_scale < 0, return the quotient with scaling up
            # Posibly overflow, so we need to check

            var quot = x1_coef // x2_coef

            # If the result can be stored in UInt128
            if (
                decimo.decimal128.utility.number_of_digits(quot) - diff_scale
                < Decimal128.MAX_NUM_DIGITS
            ):
                var quot = quot * decimo.decimal128.utility.power_of_10_unsafe[
                    DType.uint128
                ](Int(-diff_scale))
                return Decimal128.from_uint128(quot, 0, is_negative)

            # If the result should be stored in UInt256
            else:
                var quot = UInt256(
                    quot
                ) * decimo.decimal128.utility.power_of_10_unsafe[DType.uint256](
                    Int(-diff_scale)
                )
                if quot > Decimal128.MAX_AS_UINT256:
                    raise OverflowError(
                        message="Decimal128 overflow in division.",
                        function="divide()",
                    )
                else:
                    var low = UInt32(quot & 0xFFFFFFFF)
                    var mid = UInt32((quot >> 32) & 0xFFFFFFFF)
                    var high = UInt32((quot >> 64) & 0xFFFFFFFF)
                    return Decimal128(low, mid, high, 0, is_negative)

    # REMAINING CASES: Perform long division
    # 其他情況: 進行長除法
    #
    # Example: 123456.789 / 12.8 = 964506.1640625
    # x1_coef = 123456789, x2_coef = 128
    # x1_scale = 3, x2_scale = 1, diff_scale = 2
    # Step 0: 123456789 // 128 -> quot = 964506, rem = 21
    # Step 1: (21 * 10) // 128 -> quot = 1, rem = 82
    # Step 2: (82 * 10) // 128 -> quot = 6, rem = 52
    # Step 3: (52 * 10) // 128 -> quot = 4, rem = 8
    # Step 4: (8 * 10) // 128 -> quot = 0, rem = 80
    # Step 5: (80 * 10) // 128 -> quot = 6, rem = 32
    # Step 6: (32 * 10) // 128 -> quot = 2, rem = 64
    # Step 7: (64 * 10) // 128 -> quot = 5, rem = 0
    # Result: 9645061640625 with scale 9 (= step_counter + diff_scale)
    #
    # Example: 12345678.9 / 1.28 = 9645061.640625
    # x1_coef = 123456789, x2_coef = 128
    # x1_scale = 1, x2_scale = 2, diff_scale = -1
    # Result: 9645061640625 with scale 6 (= step_counter + diff_scale)
    #
    # Long division algorithm
    # Stop when remainder is zero or precision is reached or the optimal number of steps is reached
    #
    # Yuhao's notes: How to determine the optimal number of steps?
    # First, we need to consider that the max scale (precision) is 28
    # Second, we need to consider the significant digits of the quotient
    # EXAMPLE: 1 / 1.1111111111111111111111111111 ~= 0.900000000000000000000000000090
    # If we only consider the precision, we just need 28 steps
    # Then quotient of coefficients would be zeros
    # Approach 1: The optimal number of steps should be approximately
    #             max_len - diff_digits - digits_of_first_quotient + 1
    # Approach 2: Times 10**(-diff_digits) to the dividend and then perform the long division
    #             The number of steps is set to be max_len - digits_of_first_quotient + 1
    #             so that we just need to scale up one than loop -diff_digits times
    #
    # Get intitial quotient and remainder
    # Yuhao's notes: remainder should be positive beacuse the previous cases have been handled
    # 朱宇浩注: 餘數應該爲正,因爲之前的特例已經處理過了

    var x1_ndigits = decimo.decimal128.utility.number_of_digits(x1_coef)
    var x2_ndigits = decimo.decimal128.utility.number_of_digits(x2_coef)
    var diff_digits = x1_ndigits - x2_ndigits
    # Here is an estimation of the maximum possible number of digits of the quotient's integral part
    # If it is higher than 28, we need to use UInt256 to store the quotient
    var est_max_ndigits_quot_int_part = diff_digits - diff_scale + 1
    var is_use_uint128 = (
        est_max_ndigits_quot_int_part < Decimal128.MAX_NUM_DIGITS
    )

    # SUB-CASE: Use UInt128 to store the quotient
    # If the quotient's integral part is less than 28 digits, we can use UInt128
    # if is_use_uint128:
    var quot: UInt128
    var rem: UInt128
    var adjusted_scale = 0

    # The adjusted dividend coefficient will not exceed 2^96 - 1
    if diff_digits < 0:
        var adjusted_x1_coef = (
            x1_coef
            * decimo.decimal128.utility.power_of_10_unsafe[DType.uint128](
                Int(-diff_digits)
            )
        )
        quot = adjusted_x1_coef // x2_coef
        rem = adjusted_x1_coef % x2_coef
        adjusted_scale = -diff_digits
    else:
        quot = x1_coef // x2_coef
        rem = x1_coef % x2_coef

    if is_use_uint128:
        # Long division producing exactly the final coefficient
        # (no extra +1 "rounding digit" padding). Total digits is
        # bounded by `MAX_NUM_DIGITS = 29`, scale by `MAX_SCALE = 28`.
        # Rounding (banker's, round-half-to-even) is decided directly
        # from the final residual remainder via a three-branch test on
        # `2 * rem` against `x2_coef`:
        #   2*rem  > x2_coef  → next-digit > 5 (or 5+nonzero-tail) → up
        #   2*rem == x2_coef  → exact half       → bump only if `quot`
        #                                          last-kept digit odd
        #   2*rem  < x2_coef  → next-digit < 5                     → drop
        # See the detailed derivation just before the rounding block.

        # The final step counter stands for the number of decimal points.
        var step_counter = 0
        var ndigits_initial_quot = decimo.decimal128.utility.number_of_digits(
            quot
        )
        # Two-phase long division.
        #
        # Phase 1: a short probe loop (up to PROBE_STEPS digits) catches
        # fast-terminating cases like `10.5 / 2.5 = 4.2` or `123.45 / -2
        # = -61.725` in 1-3 cheap UInt128 div-mod iterations.
        #
        # Phase 2: if the remainder is still non-zero after the probe, we
        # know the result either does not terminate or terminates only
        # after many more digits. Scale the remaining work up by a single
        # `10^k` factor and finish with one big `UInt256 / UInt128`
        # divide (~12 ns for u64 divisors via schoolbook, ~236 ns for
        # full UInt256/UInt256 software fallback). This collapses ~25
        # iterations of the per-digit loop into one division.
        comptime PROBE_STEPS = 2
        # No `+1` padding here: we compute the exact final digit count
        # and recover the rounding signal from the remainder.
        var max_steps = min(
            Decimal128.MAX_NUM_DIGITS - ndigits_initial_quot,
            Decimal128.MAX_SCALE - diff_scale - adjusted_scale,
        )
        while (
            (rem != 0)
            and (step_counter < PROBE_STEPS)
            and (step_counter < max_steps)
        ):
            rem *= 10
            quot = quot * 10 + (rem // x2_coef)
            rem = rem % x2_coef
            step_counter += 1

        if (rem != 0) and (step_counter < max_steps):
            var bulk_steps = max_steps - step_counter
            # bulk_steps bound: max_steps ≤ MAX_NUM_DIGITS = 29. Entry
            # to this arm requires the probe loop to have exited via
            # `step_counter >= PROBE_STEPS = 2`, so in practice
            # `bulk_steps ≤ 29 - 2 = 27`, well within
            # `power_of_10_unsafe`'s `0 ≤ n ≤ 29` range for `uint128`.
            var scale_factor = decimo.decimal128.utility.power_of_10_unsafe[
                DType.uint128
            ](bulk_steps)
            # `rem * 10^bulk_steps` always fits in UInt256: rem < x2_coef
            # ≤ 2^96 and bulk_steps ≤ 27 so 10^bulk_steps < 2^90, giving
            # rem * 10^bulk_steps < 2^186.
            var rem_scaled: UInt256 = UInt256(rem) * UInt256(scale_factor)

            var quot_added_u128: UInt128
            var rem_after_u128: UInt128
            if x2_coef <= UInt128(0xFFFF_FFFF_FFFF_FFFF):
                # Fast path: 4-step schoolbook over u64 limbs.
                var pair = decimo.decimal128.utility.udiv_u256_by_u64(
                    rem_scaled, UInt64(x2_coef)
                )
                # `quot_added < 10^bulk_steps ≤ 10^27 < 2^90`, fits UInt128.
                quot_added_u128 = UInt128(
                    pair[0] & UInt256(0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF)
                )
                rem_after_u128 = UInt128(pair[1])
            else:
                # Rare 96-bit-divisor fallback: software UInt256 divide.
                var x2_256 = UInt256(x2_coef)
                var quot_added_256 = rem_scaled // x2_256
                var rem_after_256 = rem_scaled - quot_added_256 * x2_256
                quot_added_u128 = UInt128(
                    quot_added_256
                    & UInt256(0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF)
                )
                rem_after_u128 = UInt128(
                    rem_after_256
                    & UInt256(0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF)
                )

            # UInt128 fold (was UInt256 in the previous design).
            # `quot * 10^bulk_steps` fits UInt128: post-bulk total
            # digits = ndigits_initial_quot + step_counter + bulk_steps
            # = ndigits_initial_quot + max_steps ≤ MAX_NUM_DIGITS = 29,
            # so the product is < 10^29 < 2^97. Adding `quot_added_u128`
            # (< 10^27) keeps it < 2 * 10^29 < 2^98, well below 2^128.
            quot = quot * scale_factor + quot_added_u128
            step_counter = max_steps

            if rem_after_u128 == 0:
                # Exact division. The per-digit loop would have stopped
                # at the first zero remainder, so its `quot` carries no
                # trailing zeros from beyond that point. Bisect-strip
                # the equivalent zeros so the final scale matches.
                rem = 0
                var pow16 = UInt128(10000000000000000)
                while (step_counter >= 16) and (quot % pow16 == 0):
                    quot = quot // pow16
                    step_counter -= 16
                var pow8 = UInt128(100000000)
                while (step_counter >= 8) and (quot % pow8 == 0):
                    quot = quot // pow8
                    step_counter -= 8
                var pow4 = UInt128(10000)
                while (step_counter >= 4) and (quot % pow4 == 0):
                    quot = quot // pow4
                    step_counter -= 4
                var pow2 = UInt128(100)
                while (step_counter >= 2) and (quot % pow2 == 0):
                    quot = quot // pow2
                    step_counter -= 2
                while (step_counter >= 1) and (quot % 10 == 0):
                    quot = quot // 10
                    step_counter -= 1
            else:
                # Inexact: forward the bulk-divide remainder for the
                # unified rounding step below.
                rem = rem_after_u128

        # Banker's rounding (round-half-to-even) derived directly from
        # the residual remainder, matching the .NET / rust_decimal
        # convention for fixed-precision decimal divide.
        #
        # Compare `2*rem` against the divisor `x2_coef`:
        #   2*rem  > x2_coef  → next-digit > 5             → round up
        #   2*rem == x2_coef  → next-digit == 5, exact tail → banker's
        #   2*rem  < x2_coef  → next-digit < 5             → drop
        #
        # Why the equality test really is "exact half (no further tail)":
        # `2*rem == x2_coef` ⇒ `rem*10 == 5*x2_coef`, so
        # `next_digit = (rem*10) // x2_coef == 5` and
        # `next_rem    = (rem*10) %  x2_coef == 0` — i.e. the exact
        # value is `quot.5` with all-zeros after, the textbook midpoint.
        # Banker's rounds to the nearest even (round up only if the kept
        # last digit `quot & 1` is odd).
        #
        # The strict `2*rem > x2_coef` arm covers the "5 with non-zero
        # tail" case (e.g. 1/7 truncated at 28 frac digits → next is 5
        # but the true value is strictly > .5 of the unit), which is
        # *not* a banker's tie — rounding up is mathematically required.
        #
        # 朱宇浩注: 採用銀行家捨去法 (四捨六入五成雙)。
        # 當餘數的兩倍嚴格大於除數時,下一位數字大於 5 (或等於 5 但其後仍有非零尾,
        # 如 1/7 在第 28 位之後),四捨五入向上;當餘數的兩倍等於除數時,下一位
        # 數字恰爲 5 且其後全爲零 (即恰好爲半),依銀行家法捨入到偶數;當餘數的
        # 兩倍小於除數時,直接捨去。此實作與 .NET System.Decimal、rust_decimal
        # 的除法默認捨入規則一致。
        if rem != 0:
            var double_rem = rem << 1
            if double_rem > x2_coef:
                quot += 1
            elif (double_rem == x2_coef) and ((quot & 1) == 1):
                # Exact half + last-kept-digit odd → bump to even.
                quot += 1

        var scale_of_quot = step_counter + diff_scale + adjusted_scale

        # If the scale is negative, we need to scale up the quotient
        if scale_of_quot < 0:
            quot = quot * decimo.decimal128.utility.power_of_10_unsafe[
                DType.uint128
            ](Int(-scale_of_quot))
            scale_of_quot = 0

        # print(
        #     String(
        #         "quot: {}, rem: {}, step_counter: {}, scale_of_quot: {}"
        #     ).format(quot, rem, step_counter, scale_of_quot)
        # )

        # TODO: 可以考慮先降 scale 再判斷是否超出最大值.
        # TODO: 爲降 scale 引入 round_to_remove_last_n_digits 函數
        # If quot is within MAX, return the result
        if quot <= Decimal128.MAX_AS_UINT128:
            if scale_of_quot > Decimal128.MAX_SCALE:
                quot = decimo.decimal128.utility.round_coefficient(
                    quot,
                    ndigits_to_remove=scale_of_quot - Decimal128.MAX_SCALE,
                )
                scale_of_quot = Decimal128.MAX_SCALE

            return Decimal128.from_uint128(
                quot, UInt32(scale_of_quot), is_negative
            )

        # Otherwise, we need to truncate the first 29 or 28 digits
        else:
            var fitted = decimo.decimal128.utility.fit_to_max_coefficient(quot)
            var truncated_quot = fitted[0]
            var scale_of_truncated_quot = scale_of_quot - fitted[1]

            if scale_of_truncated_quot > Decimal128.MAX_SCALE:
                truncated_quot = decimo.decimal128.utility.round_coefficient(
                    truncated_quot,
                    ndigits_to_remove=scale_of_truncated_quot
                    - Decimal128.MAX_SCALE,
                )
                scale_of_truncated_quot = Decimal128.MAX_SCALE

            return Decimal128.from_uint128(
                truncated_quot, UInt32(scale_of_truncated_quot), is_negative
            )

    # SUB-CASE: Use UInt256 to store the quotient
    # Also the FALLBACK approach for the remaining cases
    # If the quotient's integral part is possibly more than 28 digits, we use UInt256
    # It is almost the same also the case above, so we just use the same code

    else:
        # Maximum number of steps is MAX_NUM_DIGITS - ndigits_initial_quot + 1
        # The extra digit is used for rounding up when it is 5 and not exact division
        # 最大步數加一,用於捨去項爲5且非精確相除時向上捨去

        var quot256: UInt256 = UInt256(quot)
        var rem256: UInt256 = UInt256(rem)
        var x2_coef256: UInt256 = UInt256(x2_coef)
        # digit is the temporary quotient digit
        var digit = UInt256(0)
        # The final step counter stands for the number of decimal points
        var step_counter = 0
        var ndigits_initial_quot = decimo.decimal128.utility.number_of_digits(
            quot256
        )
        while (
            (rem256 != 0)
            and (
                step_counter
                < (Decimal128.MAX_NUM_DIGITS - ndigits_initial_quot + 1)
            )
            and (
                step_counter
                < Decimal128.MAX_SCALE - diff_scale - adjusted_scale + 1
            )
        ):
            # Multiply remainder by 10
            rem256 *= 10
            # Calculate next quotient digit
            digit = rem256 // x2_coef256
            quot256 = quot256 * 10 + digit
            # Calculate new remainder. Writing `// + %` is fine here:
            # LLVM lowers `urem` to `sub(a, mul(udiv, b))` and CSE-dedups
            # the shared `udiv`, so the loop performs exactly one
            # division per iteration (verified at the ARM64 asm level).
            # Hoisting `UInt256(x2_coef)` into `x2_coef256` above
            # the loop avoids the per-iteration lift.
            rem256 = rem256 % x2_coef256
            # Increment step counter
            step_counter += 1
            # Check if division is exact

        else:
            if digit == 5:
                # Not exact division, round up the last digit
                quot256 += 1

        var scale_of_quot = step_counter + diff_scale + adjusted_scale

        # If the scale is negative, we need to scale up the quotient
        if scale_of_quot < 0:
            quot256 = quot256 * decimo.decimal128.utility.power_of_10_unsafe[
                DType.uint256
            ](Int(-scale_of_quot))
            scale_of_quot = 0

        # If quot is within MAX, return the result
        if quot256 <= Decimal128.MAX_AS_UINT256:
            if scale_of_quot > Decimal128.MAX_SCALE:
                quot256 = decimo.decimal128.utility.round_coefficient(
                    quot256,
                    ndigits_to_remove=scale_of_quot - Decimal128.MAX_SCALE,
                )
                scale_of_quot = Decimal128.MAX_SCALE

            var low = UInt32(quot256 & 0xFFFFFFFF)
            var mid = UInt32((quot256 >> 32) & 0xFFFFFFFF)
            var high = UInt32((quot256 >> 64) & 0xFFFFFFFF)

            return Decimal128(
                low, mid, high, UInt32(scale_of_quot), is_negative
            )

        # Otherwise, we need to truncate the first 29 or 28 digits
        else:
            var fitted = decimo.decimal128.utility.fit_to_max_coefficient(
                quot256
            )
            var truncated_quot = fitted[0]
            var digits_removed = fitted[1]

            # If digits_removed > scale_of_quot, we've lost integral digits
            if digits_removed > scale_of_quot:
                raise OverflowError(
                    message="Decimal128 overflow in division.",
                    function="divide()",
                )

            var scale_of_truncated_quot = scale_of_quot - digits_removed

            if scale_of_truncated_quot > Decimal128.MAX_SCALE:
                truncated_quot = decimo.decimal128.utility.round_coefficient(
                    truncated_quot,
                    ndigits_to_remove=scale_of_truncated_quot
                    - Decimal128.MAX_SCALE,
                )
                scale_of_truncated_quot = Decimal128.MAX_SCALE

            var low = UInt32(truncated_quot & 0xFFFFFFFF)
            var mid = UInt32((truncated_quot >> 32) & 0xFFFFFFFF)
            var high = UInt32((truncated_quot >> 64) & 0xFFFFFFFF)

            return Decimal128(
                low, mid, high, UInt32(scale_of_truncated_quot), is_negative
            )


def truncate_divide(x1: Decimal128, x2: Decimal128) raises -> Decimal128:
    """Returns the integral part of the quotient (truncating towards zero).
    The following identity always holds: x_1 == (x_1 // x_2) * x_2 + x_1 % x_2.

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        A new Decimal128 containing the integral part of x1 / x2.

    Raises:
        ZeroDivisionError: If the divisor is zero.
        OverflowError: If the result overflows.
    """
    try:
        return divide(x1, x2).round(0, RoundingMode.down())
    except e:
        raise e^


def modulo(x1: Decimal128, x2: Decimal128) raises -> Decimal128:
    """Returns the remainder of the division of x1 by x2.
    The following identity always holds: x_1 == (x_1 // x_2) * x_2 + x_1 % x_2.

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        A new Decimal128 containing the remainder of x1 / x2.

    Raises:
        ZeroDivisionError: If the divisor is zero.
        OverflowError: If the result overflows.
    """
    try:
        return x1 - (truncate_divide(x1, x2) * x2)
    except e:
        raise e^
