# ===----------------------------------------------------------------------=== #
# Copyright 2025 Yuhao Zhu
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
# Implements internal utility functions for the Decimal128 type
# WARNING: These functions are not meant to be used directly by the user.
#
# ===----------------------------------------------------------------------=== #

from std.memory import UnsafePointer
from std import sys
from std import time

from decimo.decimal128.decimal128 import Decimal128


# UNSAFE
def bitcast[dtype: DType](dec: Decimal128) -> Scalar[dtype]:
    """
    Direct memory bit copy from Decimal128 (low, mid, high) to Mojo's Scalar type.
    This performs a bitcast/reinterpretation rather than bit manipulation.
    ***UNSAFE***: This function is unsafe and should be used with caution.

    Parameters:
        dtype: The Mojo scalar type to bitcast to.

    Args:
        dec: The Decimal128 to bitcast.

    Constraints:
        `dtype` must be `DType.uint128` or `DType.uint256`.

    Returns:
        The bitcasted Decimal128 (low, mid, high) as a Mojo scalar.

    """

    # Compile-time checker: ensure the dtype is either uint128 or uint256
    comptime assert (
        dtype == DType.uint128 or dtype == DType.uint256
    ), "must be uint128 or uint256"

    # Bitcast the Decimal128 to the desired Mojo scalar type
    var result = UnsafePointer(to=dec).bitcast[Scalar[dtype]]().load()
    # Mask out the bits in flags
    result &= Scalar[dtype](0xFFFFFFFF_FFFFFFFF_FFFFFFFF)
    return result


def fit_to_max_coefficient[
    dtype: DType, //
](
    value: Scalar[dtype],
    sign: Bool = False,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) -> Tuple[Scalar[dtype], Int] where (
    dtype == DType.uint128 or dtype == DType.uint256
):
    """Rounds a coefficient to fit within Decimal128's 96-bit maximum (2^96 − 1).

    Because 2^96 − 1 = 79_228_162_514_264_337_593_543_950_335 has 29 decimal
    digits but not every 29-digit number fits (e.g. 9.9…9 × 10^28 > 2^96 − 1),
    the function first tries keeping 29 digits. If the rounded result still
    exceeds the maximum, it retries with 28 digits.

    Parameters:
        dtype: Must be either `DType.uint128` or `DType.uint256`.

    Args:
        value: The coefficient to fit.
        sign: The sign of the original number (needed for CEILING/FLOOR modes).
        rounding_mode: The rounding strategy for discarded digits.
            Defaults to banker's rounding (ROUND_HALF_EVEN).

    Constraints:
        `dtype` must be either `DType.uint128` or `DType.uint256`.

    Returns:
        A tuple of:
        - The rounded coefficient, guaranteed ≤ `Decimal128.MAX_AS_UINT128`.
        - The number of digits removed from the original value.

        The caller can compute the new scale as:
        `new_scale = original_scale - digits_removed`.

    Examples:

        If the value already fits (≤ 2^96 - 1), it is returned unchanged
        with `digits_removed = 0`.

        >>> fit_to_max_coefficient(UInt128(123456))
        (123456, 0)

        If the value is too large, it is rounded to fit:

        >>> fit_to_max_coefficient(UInt256(792281625142643375935439503560))
        (79228162514264337593543950356, 1)

        If rounding 29 digits still overflows (because the 29-digit rounded
        value > 2^96 - 1), the function automatically retries with 28 digits:

        >>> fit_to_max_coefficient(UInt256(99999999999999999999999999999999))
        (10000000000000000000000000000, 4).

        The returned value is always ≤ 2^96 - 1.
    """

    comptime ValueType = Scalar[dtype]

    # If the value already fits, no truncation needed.
    if value <= ValueType(Decimal128.MAX_AS_UINT128):
        return (value, 0)

    var ndigits = number_of_digits(value)
    var digits_to_remove = ndigits - Decimal128.MAX_NUM_DIGITS

    # First attempt: keep MAX_NUM_DIGITS (29) digits.
    var result = round_to_keep_first_n_digits(
        value, sign, Decimal128.MAX_NUM_DIGITS, rounding_mode
    )

    # Because 2^96 − 1 is not at a clean decimal boundary, the 29-digit
    # rounded result may still exceed the maximum. Retry with 28 digits.
    if result > ValueType(Decimal128.MAX_AS_UINT128):
        result = round_to_keep_first_n_digits(
            value, sign, Decimal128.MAX_NUM_DIGITS - 1, rounding_mode
        )
        digits_to_remove += 1

    return (result, digits_to_remove)


def sqrt(x: UInt128) -> UInt128:
    """
    Returns the square root of a UInt128 value.

    Args:
        x: The UInt128 value to calculate the square root for.

    Returns:
        The square root of the UInt128 value.
    """

    if x < 0:
        return 0

    var r: UInt128 = 0

    for p in range(sys.bit_width_of[UInt128]() // 2 - 1, -1, -1):
        var new_bit = UInt128(1) << UInt128(p)
        var would_be = r | new_bit
        var squared = would_be * would_be
        if squared <= x:
            r = would_be

    return r


def round_to_keep_first_n_digits[
    dtype: DType, //
](
    value: Scalar[dtype],
    sign: Bool,
    ndigits: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) -> Scalar[dtype]:
    """
    Rounds and keeps the first n digits of a integral value.
    Default to use banker's rounding (ROUND_HALF_EVEN) for any truncated digits.
    `792281625142643375935439503356` with digits 2 will be truncated to `79`.
    `997` with digits 2 will be truncated to `100`.

    Parameters:
        dtype: Must be either uint128 or uint256.

    Args:
        value: The integral value to truncate.
        sign: The sign of the original number.
        ndigits: The number of significant digits to evaluate.
        rounding_mode: The rounding mode to use.

    Constraints:
        `dtype` must be either `DType.uint128` or `DType.uint256`.

    Returns:
        The truncated value.

    Notes:

    This function is useful in two cases:

    (1) When you want to evaluate whether the coefficient will overflow after
    rounding, just look the first N digits (after rounding). If the truncated
    value is larger than the maximum, then it will overflow. Then you need to
    either raise an error (in case scale = 0 or integral part overflows),
    or keep only the first 28 digits in the coefficient.

    (2) When you want to round a value.

    There are some examples:

    - When you want to apply a scale of 31 to the coefficient `997`, it will be
    `0.0000000000000000000000000000997` with 31 digits. However, we can only
    store 28 digits in the coefficient (Decimal128.MAX_SCALE = 28).
    Therefore, we need to truncate the coefficient to 0 (`3 - (31 - 28)`) digits
    and round it to the nearest even number.
    The truncated ceofficient will be `1`.
    Note that `truncated_digits = 1` which is not equal to
    `ndigits = 0`, meaning there is a rounding to next digit.
    The final decimal value will be `0.0000000000000000000000000001`.

    - When you want to apply a scale of 29 to the coefficient `234567`, it will
    be `0.00000000000000000000000234567` with 29 digits. However, we can only
    store 28 digits in the coefficient (Decimal128.MAX_SCALE = 28).
    Therefore, we need to truncate the coefficient to 5 (`6 - (29 - 28)`) digits
    and round it to the nearest even number.
    The truncated coefficient will be `23457`.
    The final decimal value will be `0.0000000000000000000000023457`.

    - When you want to apply a scale of 5 to the coefficient `234567`, it will
    be `2.34567` with 5 digits.
    Since `ndigits_to_keep = 6 - (5 - 28) = 29`,
    it is greater and equal to the number of digits of the input value.
    The function will return the value as it is.

    - It can also be used for rounding function. For example, if you want to
    round `12.34567` (`1234567` with scale `5`) to 2 digits,
    the function input will be `234567` and `4 = (7 - 5) + 2`.
    That is (number of digits - scale) + number of rounding points.
    The output is `1235`.
    """

    comptime ValueType = Scalar[dtype]

    comptime assert (
        dtype == DType.uint128 or dtype == DType.uint256
    ), "must be uint128 or uint256"

    # CASE: The number of digits is less than 0
    # Return 0.
    #
    # Example:
    # 123_456 keep -1 digits => 0
    if ndigits < 0:
        return 0

    var ndigits_of_x: Int
    ndigits_of_x = number_of_digits(value)

    # CASE: If the number of digits is greater than or equal to the specified digits
    # Return the value.
    #
    # Example:
    # 123_456 keep 7 digits => 123_456
    if ndigits >= ndigits_of_x:
        return value

    # CASE: If the number of digits is less than the specified digits
    # Return the value.
    #
    # Example:
    # 123_456 keep 4 digits => 1_235
    else:
        # Calculate how many digits we need to truncate
        # Calculate how many digits to keep (MAX_NUM_DIGITS = 29)
        var ndigits_to_remove = ndigits_of_x - ndigits

        # Collect digits for rounding decision
        var divisor = power_of_10[dtype](ndigits_to_remove)
        var truncated_value = value // divisor
        var remainder = value % divisor

        # Translate CEILING/FLOOR to UP/DOWN based on sign.
        # CEILING (toward +inf): positive -> UP, negative -> DOWN
        # FLOOR (toward -inf): positive -> DOWN, negative -> UP
        var effective_mode = rounding_mode
        if rounding_mode == RoundingMode.ceiling():
            effective_mode = (
                RoundingMode.up() if not sign else RoundingMode.down()
            )
        elif rounding_mode == RoundingMode.floor():
            effective_mode = (
                RoundingMode.down() if not sign else RoundingMode.up()
            )

        # If RoundingMode is down(), just truncate the value
        if effective_mode == RoundingMode.down():
            pass

        # If RoundingMode is up(), round up the value if remainder is greater than 0
        elif effective_mode == RoundingMode.up():
            if remainder > 0:
                truncated_value += 1

        # If RoundingMode is half_up(), round up the value if remainder is >= 0.5
        elif effective_mode == RoundingMode.half_up():
            var cutoff_value = 5 * power_of_10[dtype](ndigits_to_remove - 1)
            if remainder >= cutoff_value:
                truncated_value += 1

        # If RoundingMode is half_down(), round up only if remainder is > 0.5
        elif effective_mode == RoundingMode.half_down():
            var cutoff_value = 5 * power_of_10[dtype](ndigits_to_remove - 1)
            if remainder > cutoff_value:
                truncated_value += 1

        # If RoundingMode is ROUND_HALF_EVEN, round to nearest even digit if equidistant
        elif effective_mode == RoundingMode.half_even():
            var cutoff_value: ValueType = 5 * power_of_10[dtype](
                ndigits_to_remove - 1
            )
            if remainder > cutoff_value:
                truncated_value += 1
            elif remainder == cutoff_value:
                # If truncated_value is even, do not round up
                # If truncated_value is odd, round up
                truncated_value += truncated_value % 2

        # TODO: Remove this fallback once Mojo has proper enum support,
        # which will make exhaustive matching a compile-time guarantee.
        else:
            debug_assert(
                False,
                "Unknown rounding mode in round_to_keep_first_n_digits: "
                + String(rounding_mode),
            )

        return truncated_value


@always_inline
def number_of_digits[dtype: DType, //](value: Scalar[dtype]) -> Int:
    """
    Returns the number of (significant) digits in an integral value using binary search.
    This implementation is significantly faster than loop division.

    Parameters:
        dtype: The Mojo scalar type to calculate the number of digits for.

    Args:
        value: The integral value to calculate the number of digits for.

    Constraints:
        `dtype` must be either `DType.uint128` or `DType.uint256`.

    Returns:
        The number of digits in the integral value.
    """

    comptime assert (
        dtype == DType.uint128 or dtype == DType.uint256
    ), "must be uint128 or uint256"

    comptime ValueType = Scalar[dtype]

    # Handle edge cases
    if value == 0:
        return 0
    # Binary search to determine the number of digits
    # First check small numbers with direct comparison (most common case)
    if value < 10:
        return 1
    if value < 100:
        return 2
    if value < 1000:
        return 3
    if value < 10000:
        return 4
    if value < 100000:
        return 5
    if value < 1000000:
        return 6
    if value < 10000000:
        return 7
    if value < 100000000:
        return 8
    if value < 1000000000:
        return 9

    # For larger numbers, use binary search with limited indentation
    # Medium range: 10^10 to 10^19
    if value < ValueType(10) ** 19:  # < 10^19
        if value < ValueType(10) ** 13:  # < 10^13
            if value < ValueType(10) ** 10:  # < 10^10
                return 10
            if value < ValueType(10) ** 11:  # < 10^11
                return 11
            if value < ValueType(10) ** 12:  # < 10^12
                return 12
            return 13
        if value < ValueType(10) ** 16:  # < 10^16
            if value < ValueType(10) ** 14:  # < 10^14
                return 14
            if value < ValueType(10) ** 15:  # < 10^15
                return 15
            return 16
        if value < ValueType(10) ** 17:  # < 10^17
            return 17
        if value < ValueType(10) ** 18:  # < 10^18
            return 18
        return 19

    # Large range: 10^19 to 10^38 (UInt128 max is ~10^38)
    if value < ValueType(10) ** 37:  # < 10^37
        if value < ValueType(10) ** 28:  # < 10^28
            if value < ValueType(10) ** 22:  # < 10^22
                if value < ValueType(10) ** 20:  # < 10^20
                    return 20
                if value < ValueType(10) ** 21:  # < 10^21
                    return 21
                return 22
            if value < ValueType(10) ** 24:  # < 10^24
                if value < ValueType(10) ** 23:  # < 10^23
                    return 23
                return 24
            if value < ValueType(10) ** 25:  # < 10^25
                return 25
            if value < ValueType(10) ** 26:  # < 10^26
                return 26
            if value < ValueType(10) ** 27:  # < 10^27
                return 27
            return 28
        if value < ValueType(10) ** 31:  # < 10^31
            if value < ValueType(10) ** 29:  # < 10^29
                return 29
            if value < ValueType(10) ** 30:  # < 10^30
                return 30
            return 31
        if value < ValueType(10) ** 33:  # < 10^33
            if value < ValueType(10) ** 32:  # < 10^32
                return 32
            return 33
        if value < ValueType(10) ** 34:  # < 10^34
            return 34
        if value < ValueType(10) ** 35:  # < 10^35
            return 35
        if value < ValueType(10) ** 36:  # < 10^36
            return 36
        return 37

    # Very large range: 10^37 to 10^77 (UInt256 max is ~10^77)
    if value < ValueType(10) ** 38:  # < 10^38
        return 38

    # For UInt128, the maximum number of digits is 39
    # We can already return the result here
    if dtype == DType.uint128:
        return 39

    if value < ValueType(10) ** 39:  # < 10^39
        return 39

    # Use additional binary searches for UInt256 range (10^39 to 10^77)
    if value < ValueType(10) ** 58:  # < 10^58
        if value < ValueType(10) ** 47:  # < 10^47
            if value < ValueType(10) ** 43:  # < 10^43
                if value < ValueType(10) ** 40:  # < 10^40
                    return 40
                if value < ValueType(10) ** 41:  # < 10^41
                    return 41
                if value < ValueType(10) ** 42:  # < 10^42
                    return 42
                return 43
            if value < ValueType(10) ** 44:  # < 10^44
                return 44
            if value < ValueType(10) ** 45:  # < 10^45
                return 45
            if value < ValueType(10) ** 46:  # < 10^46
                return 46
            return 47
        if value < ValueType(10) ** 52:  # < 10^52
            if value < ValueType(10) ** 48:  # < 10^48
                return 48
            if value < ValueType(10) ** 49:  # < 10^49
                return 49
            if value < ValueType(10) ** 50:  # < 10^50
                return 50
            if value < ValueType(10) ** 51:  # < 10^51
                return 51
            return 52
        if value < ValueType(10) ** 54:  # < 10^54
            if value < ValueType(10) ** 53:  # < 10^53
                return 53
            return 54
        if value < ValueType(10) ** 56:  # < 10^56
            if value < ValueType(10) ** 55:  # < 10^55
                return 55
            return 56
        if value < ValueType(10) ** 57:  # < 10^57
            return 57
        return 58

    # Digits more than 58 is not possible for Decimal128 products
    return 59


def number_of_bits[dtype: DType, //](var value: Scalar[dtype]) -> Int:
    """
    Returns the number of significant bits in an integer value.

    Constraints:
        `dtype` must be integral.

    Parameters:
        dtype: The scalar type of the input value.

    Args:
        value: The integer value to count bits in.

    Returns:
        The number of significant bits in the value.
    """

    comptime assert dtype.is_integral(), "must be intergral"

    if value < 0:
        value = -value

    var count = 0
    while value > 0:
        value >>= 1
        count += 1

    return count


# ===----------------------------------------------------------------------=== #
# Cache for powers of 10
#
# Yuhao's notes:
# This is a module-level cache for powers of 10.
# It is used to store the powers of 10 up to the required value.
# The cache is initialized with the first value (10^0 = 1).
# When a new power of 10 is requested, it is calculated and added to the cache.
# This cache is used to avoid recalculating the same powers of 10 multiple times.
#
# TODO: Currently, this won't work when you create a mojopkg to use.
# When Mojo supports module-level variables, this part can be used.
# ===----------------------------------------------------------------------=== #


# # Module-level cache for powers of 10
# var _power_of_10_as_uint128_cache = List[UInt128]()
# var _power_of_10_as_uint256_cache = List[UInt256]()


# # Initialize with the first value
# @always_inline
# def _init_power_of_10_as_uint128_cache():
#     if len(_power_of_10_as_uint128_cache) == 0:
#         _power_of_10_as_uint128_cache.append(1)  # 10^0 = 1


# @always_inline
# def _init_power_of_10_as_uint256_cache():
#     if len(_power_of_10_as_uint256_cache) == 0:
#         _power_of_10_as_uint256_cache.append(1)  # 10^0 = 1


# @always_inline
# def power_of_10_as_uint128(n: Int) raises -> UInt128:
#     """
#     Returns 10^n using cached values when available.
#     """

#     # Check for negative exponent
#     if n < 0:
#         raise Error(
#             "power_of_10() requires non-negative exponent, got {}".format(n)
#         )

#     # Initialize cache if needed
#     if len(_power_of_10_as_uint128_cache) == 0:
#         _init_power_of_10_as_uint128_cache()

#     # Extend cache if needed
#     while len(_power_of_10_as_uint128_cache) <= n:
#         var next_power = _power_of_10_as_uint128_cache[
#             len(_power_of_10_as_uint128_cache) - 1
#         ] * 10
#         _power_of_10_as_uint128_cache.append(next_power)

#     return _power_of_10_as_uint128_cache[n]


# @always_inline
# def power_of_10_as_uint256(n: Int) raises -> UInt256:
#     """
#     Returns 10^n using cached values when available.
#     """

#     # Check for negative exponent
#     if n < 0:
#         raise Error(
#             "power_of_10() requires non-negative exponent, got {}".format(n)
#         )

#     # Initialize cache if needed
#     if len(_power_of_10_as_uint256_cache) == 0:
#         _init_power_of_10_as_uint256_cache()

#     # Extend cache if needed
#     while len(_power_of_10_as_uint256_cache) <= n:
#         var next_power = _power_of_10_as_uint256_cache[
#             len(_power_of_10_as_uint256_cache) - 1
#         ] * 10
#         _power_of_10_as_uint256_cache.append(next_power)

#     return _power_of_10_as_uint256_cache[n]


@always_inline
def power_of_10[
    dtype: DType
](n: Int) -> Scalar[dtype] where (
    dtype == DType.uint128 or dtype == DType.uint256
):
    """
    Returns 10^n using cached values when available.

    Parameters:
        dtype: The Mojo scalar type to calculate the power of 10 for.

    Args:
        n: The exponent to raise 10 to.

    Constraints:
        `dtype` must be either `DType.uint128` or `DType.uint256`.

    Returns:
        The value of 10^n as a Mojo scalar.

    Notes:

        **WARNING**: The overflow is only checked when debug mode is enabled.
        Make sure that the n is less than 29 for UInt128 and 77 for UInt256.

        The powers of 10 are hardcoded up to 10^58. This covers all values
        needed for Decimal128 arithmetic (max scale 28 × 2 = 56 for products
        of two max-scale numbers, plus 2 for rounding headroom). For larger
        values, the function falls back to the `**` operator.
    """

    comptime if dtype == DType.uint128:
        debug_assert(
            n <= 29,
            "power_of_10() for uint128 only supports n up to 29, got {}".format(
                n
            ),
        )
    else:
        debug_assert(
            n <= 77,
            "power_of_10() for uint256 only supports n up to 77, got {}".format(
                n
            ),
        )

    comptime ValueType = Scalar[dtype]

    if n == 0:
        return ValueType(1)
    if n == 1:
        return ValueType(10)
    if n == 2:
        return ValueType(100)
    if n == 3:
        return ValueType(1000)
    if n == 4:
        return ValueType(10000)
    if n == 5:
        return ValueType(100000)
    if n == 6:
        return ValueType(1000000)
    if n == 7:
        return ValueType(10000000)
    if n == 8:
        return ValueType(100000000)
    if n == 9:
        return ValueType(1000000000)
    if n == 10:
        return ValueType(10000000000)
    if n == 11:
        return ValueType(100000000000)
    if n == 12:
        return ValueType(1000000000000)
    if n == 13:
        return ValueType(10000000000000)
    if n == 14:
        return ValueType(100000000000000)
    if n == 15:
        return ValueType(1000000000000000)
    if n == 16:
        return ValueType(10000000000000000)
    if n == 17:
        return ValueType(100000000000000000)
    if n == 18:
        return ValueType(1000000000000000000)
    if n == 19:
        return ValueType(10000000000000000000)
    if n == 20:
        return ValueType(100000000000000000000)
    if n == 21:
        return ValueType(1000000000000000000000)
    if n == 22:
        return ValueType(10000000000000000000000)
    if n == 23:
        return ValueType(100000000000000000000000)
    if n == 24:
        return ValueType(1000000000000000000000000)
    if n == 25:
        return ValueType(10000000000000000000000000)
    if n == 26:
        return ValueType(100000000000000000000000000)
    if n == 27:
        return ValueType(1000000000000000000000000000)
    if n == 28:
        return ValueType(10000000000000000000000000000)
    if n == 29:
        return ValueType(100000000000000000000000000000)
    if n == 30:
        return ValueType(1000000000000000000000000000000)
    if n == 31:
        return ValueType(10000000000000000000000000000000)
    if n == 32:
        return ValueType(100000000000000000000000000000000)
    if n == 33:
        return ValueType(1000000000000000000000000000000000)
    if n == 34:
        return ValueType(10000000000000000000000000000000000)
    if n == 35:
        return ValueType(100000000000000000000000000000000000)
    if n == 36:
        return ValueType(1000000000000000000000000000000000000)
    if n == 37:
        return ValueType(10000000000000000000000000000000000000)
    if n == 38:
        return ValueType(100000000000000000000000000000000000000)
    if n == 39:
        return ValueType(1000000000000000000000000000000000000000)
    if n == 40:
        return ValueType(10000000000000000000000000000000000000000)
    if n == 41:
        return ValueType(100000000000000000000000000000000000000000)
    if n == 42:
        return ValueType(1000000000000000000000000000000000000000000)
    if n == 43:
        return ValueType(10000000000000000000000000000000000000000000)
    if n == 44:
        return ValueType(100000000000000000000000000000000000000000000)
    if n == 45:
        return ValueType(1000000000000000000000000000000000000000000000)
    if n == 46:
        return ValueType(10000000000000000000000000000000000000000000000)
    if n == 47:
        return ValueType(100000000000000000000000000000000000000000000000)
    if n == 48:
        return ValueType(1000000000000000000000000000000000000000000000000)
    if n == 49:
        return ValueType(10000000000000000000000000000000000000000000000000)
    if n == 50:
        return ValueType(100000000000000000000000000000000000000000000000000)
    if n == 51:
        return ValueType(1000000000000000000000000000000000000000000000000000)
    if n == 52:
        return ValueType(10000000000000000000000000000000000000000000000000000)
    if n == 53:
        return ValueType(100000000000000000000000000000000000000000000000000000)
    if n == 54:
        return ValueType(
            1000000000000000000000000000000000000000000000000000000
        )
    if n == 55:
        return ValueType(
            10000000000000000000000000000000000000000000000000000000
        )
    if n == 56:
        return ValueType(
            100000000000000000000000000000000000000000000000000000000
        )
    if n == 57:
        return ValueType(
            1000000000000000000000000000000000000000000000000000000000
        )
    if n == 58:
        return ValueType(
            10000000000000000000000000000000000000000000000000000000000
        )

    return ValueType(10) ** n
