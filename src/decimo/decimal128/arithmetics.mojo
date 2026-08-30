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
import decimo.decimal128.utility as decimal128_utility
from decimo.decimal128.wide import Wide


@always_inline
def add(x1: Decimal128, x2: Decimal128) raises -> Decimal128:
    """
    Adds two Decimal128 values and returns a new Decimal128 containing the sum.
    The result is rounded half to even if it has too many digits.

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
        var fitted = decimal128_utility.fit_to_max_coefficient(summation)
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
            - decimal128_utility.number_of_digits(x2.to_uint128()),
        )
        ## If x2_coef > 7922816251426433759354395033
        if (
            (x2_coef > Decimal128.MAX_AS_UINT128 // 10)
            and (scale > 0)
            and (scale > x2_scale)
        ):
            scale -= 1
        sum_coef *= decimal128_utility.power_of_10_unsafe[DType.uint128](
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
            - decimal128_utility.number_of_digits(x1.to_uint128()),
        )
        ## If x1_coef > 7922816251426433759354395033
        if (
            (x1_coef > Decimal128.MAX_AS_UINT128 // 10)
            and (scale > 0)
            and (scale > x1_scale)
        ):
            scale -= 1
        sum_coef *= decimal128_utility.power_of_10_unsafe[DType.uint128](
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
        ) * decimal128_utility.power_of_10_unsafe[DType.uint256](
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
        ) * decimal128_utility.power_of_10_unsafe[DType.uint256](
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

    var fitted = decimal128_utility.fit_to_max_coefficient(summation)
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

    ```console
    var a = Decimal128("10.5")
    var b = Decimal128("3.2")
    var result = a - b  # Returns 7.3
    ```
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

        var fitted = decimal128_utility.fit_to_max_coefficient(summation)
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
            - decimal128_utility.number_of_digits(x2.to_uint128()),
        )
        ## If x2_coef > 7922816251426433759354395033
        if (
            (x2_coef > Decimal128.MAX_AS_UINT128 // 10)
            and (scale > 0)
            and (scale > x2_scale)
        ):
            scale -= 1
        sum_coef *= decimal128_utility.power_of_10_unsafe[DType.uint128](
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
            - decimal128_utility.number_of_digits(x1.to_uint128()),
        )
        ## If x1_coef > 7922816251426433759354395033
        if (
            (x1_coef > Decimal128.MAX_AS_UINT128 // 10)
            and (scale > 0)
            and (scale > x1_scale)
        ):
            scale -= 1
        sum_coef *= decimal128_utility.power_of_10_unsafe[DType.uint128](
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
        ) * decimal128_utility.power_of_10_unsafe[DType.uint256](
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
        ) * decimal128_utility.power_of_10_unsafe[DType.uint256](
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

    var fitted = decimal128_utility.fit_to_max_coefficient(diff)
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
            var truncated_prod = decimal128_utility.round_coefficient(
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
            var truncated_prod = decimal128_utility.round_coefficient(
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
    var x1_num_bits = decimal128_utility.number_of_bits(x1_coef)
    var x2_num_bits = decimal128_utility.number_of_bits(x2_coef)
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

    # A separate branch here for two integer-valued operands of different
    # scales cost 550-760 ns, most of it in the two `is_integer()` calls
    # that dispatched it, where the same inputs take the
    # `combined_num_bits <= 96` path below in about 5 ns. It was removed.

    # GENERAL CASES: Decimal128 multiplication with any scales

    # SUB-CASE: Both operands are small
    # The bits of the product will not exceed 96 bits
    # It can just fit into Decimal128's capacity without overflow
    # Result coefficient will be less than 2^96 - 1 = 79228162514264337593543950335
    # Examples: 1.23 * 4.56
    if combined_num_bits <= 96:
        var prod: UInt128 = x1_coef * x2_coef

        # Combined scale within max precision, so no truncation is needed
        if combined_scale <= Decimal128.MAX_SCALE:
            return Decimal128.from_uint128(
                prod, UInt32(combined_scale), is_negative
            )

        # Combined scale exceeds MAX_SCALE: round and clamp to MAX_SCALE.
        # We're in the `else` of `combined_scale <= MAX_SCALE`, so the
        # subsequent `min(MAX_SCALE, combined_scale)` always yielded
        # MAX_SCALE and the second-pass rounding branch was dead code.
        else:
            prod = decimal128_utility.round_coefficient(
                prod,
                ndigits_to_remove=combined_scale - Decimal128.MAX_SCALE,
            )
            return Decimal128.from_uint128(
                prod, UInt32(Decimal128.MAX_SCALE), is_negative
            )

    # SUB-CASE: Both operands are moderate
    # The bits of the product will not exceed 128 bits
    # Result coefficient will be less than 2^128 - 1 but more than 2^96 - 1
    # IMPORTANT: This means that the product will exceed Decimal128's capacity
    # Either raises an error if the integral part overflows
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
        # both the coefficient (<= MAX_AS_UINT128) and the scale (<=
        # MAX_SCALE) constraints are satisfied in one `round_coefficient`
        # call. Saves the extra `number_of_digits` + wide divide that the
        # old `fit_to_max_coefficient` + re-round pattern incurred.
        var ndigits = decimal128_utility.number_of_digits(prod)
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

        var rounded = decimal128_utility.round_coefficient[
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
            rounded = decimal128_utility.round_coefficient[
                skip_digit_check=True
            ](prod, ndigits_to_remove=drop)

        var final_scale = Int(combined_scale) - drop
        return Decimal128.from_uint128(
            rounded, UInt32(final_scale), is_negative
        )

    # REMAINING CASES: Both operands are big
    # The bits of the product will not exceed 192 bits
    # Result coefficient will be less than 2^192 - 1 but more than 2^128 - 1
    # IMPORTANT: This means that the product will exceed Decimal128's capacity
    # Either raises an error if the integral part overflows
    # Or truncates the product to fit into Decimal128's capacity

    var prod: UInt256 = UInt256(x1_coef) * UInt256(x2_coef)

    # Single-pass rounding: compute the total digits to drop so that
    # both the coefficient (<= MAX_AS_UINT128) and the scale (<= MAX_SCALE)
    # constraints are satisfied in one `round_coefficient` call. Saves
    # the extra UInt256 division that the old `fit_to_max_coefficient`
    # + re-round pattern incurred.
    var ndigits = decimal128_utility.number_of_digits(prod)
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

    var rounded = decimal128_utility.round_coefficient[skip_digit_check=True](
        prod, ndigits_to_remove=drop
    )
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
        rounded = decimal128_utility.round_coefficient[skip_digit_check=True](
            prod, ndigits_to_remove=drop
        )

    var final_scale = Int(combined_scale) - drop

    # Extract the 32-bit components from the UInt256 product
    var low = UInt32(rounded & 0xFFFFFFFF)
    var mid = UInt32((rounded >> 32) & 0xFFFFFFFF)
    var high = UInt32((rounded >> 64) & 0xFFFFFFFF)

    return Decimal128(low, mid, high, UInt32(final_scale), is_negative)


def divide(x1: Decimal128, x2: Decimal128) raises -> Decimal128:
    """
    Divides x1 by x2 and returns a new Decimal128 containing the quotient.
    The quotient is taken with one wide division and rounded once.

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

    # SPECIAL CASE: the divisor is one, or its coefficient is one
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
                decimal128_utility.number_of_digits(x1_coef) - diff_scale
                < Decimal128.MAX_NUM_DIGITS
            ):
                var quot = x1_coef * decimal128_utility.power_of_10_unsafe[
                    DType.uint128
                ](Int(-diff_scale))
                return Decimal128.from_uint128(quot, 0, is_negative)

            # If the result should be stored in UInt256
            else:
                var quot = UInt256(
                    x1_coef
                ) * decimal128_utility.power_of_10_unsafe[DType.uint256](
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
            var quot = UInt128(1) * decimal128_utility.power_of_10_unsafe[
                DType.uint128
            ](Int(-diff_scale))
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
            # The divisor of coefficient 1 is handled above, so that coefficient
            # is at least 2 and the quotient is smaller than the dividend's.
            var quot = x1_coef // x2_coef
            return Decimal128.from_uint128(
                quot, UInt32(diff_scale), is_negative
            )

        else:
            # If diff_scale < 0, return the quotient with scaling up
            # This may overflow, so it has to be checked

            var quot = x1_coef // x2_coef

            # If the result can be stored in UInt128
            if (
                decimal128_utility.number_of_digits(quot) - diff_scale
                < Decimal128.MAX_NUM_DIGITS
            ):
                var quot = quot * decimal128_utility.power_of_10_unsafe[
                    DType.uint128
                ](Int(-diff_scale))
                return Decimal128.from_uint128(quot, 0, is_negative)

            # If the result should be stored in UInt256
            else:
                var quot = UInt256(
                    quot
                ) * decimal128_utility.power_of_10_unsafe[DType.uint256](
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

    # REMAINING CASES: one wide division, rounded once
    #
    # The quotient does not terminate, so it is taken to one digit more than
    # the answer keeps and rounded from there. The numerator is raised until
    # the integer quotient is about thirty digits long, which fits `UInt256`
    # for any pair this type holds, and the remainder says whether anything
    # was left over -- which is what decides a tie.
    #
    # This replaced a digit-at-a-time walk with two probe steps and a bulk
    # step. That was 226 ns and wrong in the last place on 1 of 300 random
    # pairs, because the digit budget could run out before the rounding
    # position was reached.
    comptime TARGET_DIGITS = 30

    var digits_of_x1 = decimal128_utility.number_of_digits(x1_coef)
    var digits_of_x2 = decimal128_utility.number_of_digits(x2_coef)
    var shift = TARGET_DIGITS - (digits_of_x1 - digits_of_x2)
    if shift < 0:
        shift = 0
    if digits_of_x1 + shift > 58:
        shift = 58 - digits_of_x1

    var numerator = UInt256(x1_coef) * decimal128_utility.power_of_10[
        DType.uint256
    ](shift)

    var pair = decimal128_utility.udiv_u256_by_u128(numerator, x2_coef)
    var quotient = pair[0]
    var remainder = pair[1]

    # The quotient is exact as far as it goes; the remainder is everything
    # below it. `Wide` pads the mantissa with zeros, so adding one there says
    # "and something more" without disturbing a digit that is known -- which
    # is what turns an apparent tie into a rounding up.
    var wide = Wide(quotient, -(diff_scale + shift), is_negative)
    if remainder != UInt128(0):
        wide.mantissa += UInt256(1)
    return wide.to_decimal()


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


def fma(x1: Decimal128, x2: Decimal128, x3: Decimal128) raises -> Decimal128:
    """Fused multiply-add: returns `x1 * x2 + x3` with a single final rounding.

    Equivalent to Python's `decimal.Decimal.fma(other, third)`. The product
    `x1 * x2` is held at full UInt256 precision and the addend `x3` is
    aligned at the same scale before a single rounding step reduces the
    result to Decimal128's grid (<= 96-bit coefficient, scale <= 28).

    A single rounding step gives smaller error than `(x1 * x2) + x3`,
    which rounds twice (once at the multiply, once at the add). For
    operands whose product would already overflow the UInt256 working
    width after scale alignment the implementation falls back to the
    two-step `(x1 * x2) + x3` path; this is signalled in the comment
    just before the fallback.

    Args:
        x1: The first multiplicand.
        x2: The second multiplicand.
        x3: The addend.

    Returns:
        A new Decimal128 containing `x1 * x2 + x3`.

    Raises:
        OverflowError: If the result overflows Decimal128 capacity.
    """

    # NOTE: We deliberately do NOT special-case zero operands here.
    # Doing so would skip the addition-style scale-alignment rules that
    # `multiply()` and `add()` apply to exact zeros (e.g. `0.01 * 0` has
    # scale `2`, so `0.01.fma(0, 7)` must render as `"7.00"`, not
    # `"7"`). The generic path below already handles zero coefficients
    # correctly because UInt256 arithmetic is exact at zero and the
    # alignment check still falls back to the two-step path when the
    # combined working scale would overflow the 58-digit ceiling.

    # ---- Compute the exact product as a UInt256 ----
    var p_coef_256 = UInt256(x1.coefficient()) * UInt256(x2.coefficient())
    var p_scale = x1.scale() + x2.scale()
    var p_sign = x1.is_negative() != x2.is_negative()

    var b_coef_256 = UInt256(x3.coefficient())
    var b_scale = x3.scale()
    var b_sign = x3.is_negative()

    # ---- Align the two addends to a common scale ----
    # `WORK_DIGITS_CAP = 58` is not a UInt256 limit (UInt256 holds
    # around 77 decimal digits). It is the size of the rodata table backing
    # `power_of_10_unsafe[uint256]` (n must be <= 58, see
    # `decimo.decimal128.utility.power_of_10_unsafe`), and also the cap
    # of `number_of_digits[uint256]`. Beyond 58 we fall back to the
    # two-step `multiply(x1,x2) + x3` path rather than introducing a
    # slower power-of-10 path here; precision loss is bounded by one
    # extra ULP and only kicks in for operands whose combined working
    # scale exceeds 58 digits, which is rare in practice.
    comptime WORK_DIGITS_CAP = 58

    var common_scale: Int
    if p_scale > b_scale:
        var diff = p_scale - b_scale
        var b_ndigits = decimal128_utility.number_of_digits(b_coef_256)
        if b_ndigits + diff <= WORK_DIGITS_CAP:
            b_coef_256 = b_coef_256 * decimal128_utility.power_of_10_unsafe[
                DType.uint256
            ](diff)
            common_scale = p_scale
        else:
            # Fallback: scaling b would overflow UInt256. Drop to the
            # two-step path; precision loss is bounded by one extra ULP.
            return multiply(x1, x2) + x3
    elif b_scale > p_scale:
        var diff = b_scale - p_scale
        var p_ndigits = decimal128_utility.number_of_digits(p_coef_256)
        if p_ndigits + diff <= WORK_DIGITS_CAP:
            p_coef_256 = p_coef_256 * decimal128_utility.power_of_10_unsafe[
                DType.uint256
            ](diff)
            common_scale = b_scale
        else:
            return multiply(x1, x2) + x3
    else:
        common_scale = p_scale

    # ---- Combine signed magnitudes ----
    var sum_coef: UInt256
    var sum_sign: Bool
    if p_sign == b_sign:
        sum_coef = p_coef_256 + b_coef_256
        sum_sign = p_sign
    else:
        if p_coef_256 >= b_coef_256:
            sum_coef = p_coef_256 - b_coef_256
            sum_sign = p_sign
        else:
            sum_coef = b_coef_256 - p_coef_256
            sum_sign = b_sign

    # Cancellation produced an exact zero. We canonicalise to positive
    # zero, matching `add()` / `subtract()`'s zero handling (which also
    # always emit `+0` for exact-zero results, regardless of operand
    # signs). This mirrors Python `decimal.Decimal.fma` and is what the
    # default-context IBM General Decimal Arithmetic spec prescribes
    # (§4.1 "sign of zero"); IEEE 754-2008 §6.3 would prefer the sign
    # of the larger-magnitude operand, but Decimal128's add/subtract
    # already deviate from that for consistency with .NET / Python.
    if sum_coef == 0:
        var result_scale = max(0, min(common_scale, Decimal128.MAX_SCALE))
        return Decimal128(0, 0, 0, UInt32(result_scale), False)

    # ---- Single-rounding pass: shrink to fit Decimal128 grid ----
    # Mirrors the late-stage rounding from multiply(): compute the total
    # digits to drop so that both `sum_coef <= MAX_AS_UINT128` and
    # `final_scale <= MAX_SCALE` are satisfied in one round_coefficient
    # call.
    var ndigits = decimal128_utility.number_of_digits(sum_coef)
    var drop_for_scale = common_scale - Decimal128.MAX_SCALE
    var drop_for_fit: Int
    if sum_coef > UInt256(Decimal128.MAX_AS_UINT128):
        drop_for_fit = max(1, ndigits - Decimal128.MAX_NUM_DIGITS)
    else:
        drop_for_fit = 0

    var drop = max(0, max(drop_for_scale, drop_for_fit))
    if drop > common_scale:
        raise OverflowError(
            message="Decimal128 overflow in fma().",
            function="fma()",
        )

    var rounded: UInt256
    if drop == 0:
        rounded = sum_coef
    else:
        rounded = decimal128_utility.round_coefficient[skip_digit_check=True](
            sum_coef, ndigits_to_remove=drop
        )
        # Banker's-rounding carry may push the value past MAX_AS_UINT128.
        # Re-round the ORIGINAL sum_coef (not the already-rounded value)
        # with one more digit dropped to avoid double-rounding artifacts.
        if rounded > UInt256(Decimal128.MAX_AS_UINT128):
            drop += 1
            if drop > common_scale:
                raise OverflowError(
                    message="Decimal128 overflow in fma().",
                    function="fma()",
                )
            rounded = decimal128_utility.round_coefficient[
                skip_digit_check=True
            ](sum_coef, ndigits_to_remove=drop)

    var final_scale = common_scale - drop
    if final_scale < 0:
        raise OverflowError(
            message="Decimal128 overflow in fma().",
            function="fma()",
        )

    var low = UInt32(rounded & 0xFFFFFFFF)
    var mid = UInt32((rounded >> 32) & 0xFFFFFFFF)
    var high = UInt32((rounded >> 64) & 0xFFFFFFFF)
    return Decimal128(low, mid, high, UInt32(final_scale), sum_sign)
