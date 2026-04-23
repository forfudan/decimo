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
from std.bit import bit_width

from decimo.decimal128.decimal128 import Decimal128
from decimo.rounding_mode import RoundingMode


# ===----------------------------------------------------------------------=== #
# System-level utilities for Decimal128
# ===----------------------------------------------------------------------=== #
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


# TODO: At the time when this function was implemented, Mojo's built-in
# sqrt() function only supports integral types up to 64 bits.
# Once Mojo supports sqrt() for UInt128, this function can be removed.
def sqrt(x: UInt128) -> UInt128:
    """
    Returns the square root of a UInt128 value.

    Args:
        x: The UInt128 value to calculate the square root for.

    Returns:
        The square root of the UInt128 value.
    """

    var r: UInt128 = 0

    for p in range(sys.bit_width_of[UInt128]() // 2 - 1, -1, -1):
        var new_bit = UInt128(1) << UInt128(p)
        var would_be = r | new_bit
        var squared = would_be * would_be
        if squared <= x:
            r = would_be

    return r


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

        If the value is too large, it is rounded to fit. The 29-digit
        rounded result may itself exceed `2^96 - 1`, in which case the
        function automatically retries with 28 digits:

        >>> fit_to_max_coefficient(UInt256(792281625142643375935439503560))
        (7922816251426433759354395036, 2)

        Another example where the all-nines case forces the retry:

        >>> fit_to_max_coefficient(UInt256(99999999999999999999999999999999))
        (10000000000000000000000000000, 4)

        The returned value is always ≤ 2^96 - 1.
    """

    comptime ValueType = Scalar[dtype]

    # If the value already fits, no truncation needed.
    if value <= ValueType(Decimal128.MAX_AS_UINT128):
        return (value, 0)

    var ndigits = number_of_digits(value)
    var digits_to_remove = ndigits - Decimal128.MAX_NUM_DIGITS

    # First attempt: keep MAX_NUM_DIGITS (29) digits. We just verified
    # `digits_to_remove < ndigits == number_of_digits(value)`, so the
    # `ndigits_to_remove > number_of_digits(value)` guard inside
    # `round_coefficient` would always be false here — instantiate with
    # `skip_digit_check=True` to drop the redundant `number_of_digits` call.
    var result = round_coefficient[skip_digit_check=True](
        value, digits_to_remove, sign, rounding_mode
    )

    # Because 2^96 − 1 is not at a clean decimal boundary, the 29-digit
    # rounded result may still exceed the maximum. Retry with 28 digits.
    # `digits_to_remove + 1 <= ndigits` (since `ndigits >= 30` here), so
    # the digit-check guard is still vacuous and we keep `skip_digit_check`.
    if result > ValueType(Decimal128.MAX_AS_UINT128):
        result = round_coefficient[skip_digit_check=True](
            value, digits_to_remove + 1, sign, rounding_mode
        )
        digits_to_remove += 1

    return (result, digits_to_remove)


# [Mojo Miji]
# This function replaces `round_to_keep_first_n_digits` with two
# optimisations borrowed from .NET's `DecCalc.ScaleResult`:
# 1. **Cheap half-comparison** — for HALF_UP / HALF_DOWN / HALF_EVEN,
#   `2 * remainder` is compared against `divisor` instead of computing
#   the separate cutoff `5 * 10^(n-1)` (saves one power-of-10 lookup
#   and one wide multiply).
# 2. **Caller supplies digit-removal count** — avoids a redundant
#   `number_of_digits` call when the caller already knows the value's
#   digit count.
#
# (An earlier version also used `value - truncated * divisor` to derive
# the remainder, on the assumption that `value % divisor` would issue a
# second wide-integer division. A microbenchmark plus direct inspection
# of the generated ARM64 assembly disproved this:
# LLVM lowers `urem` to `sub(a, mul(udiv, b))` and CSE-deduplicates
# the shared `udiv`, so `// + %` and the manual rewrite produce
# identical code with exactly one division. The function now uses
# the natural `// + %` form.)
@always_inline
def round_coefficient[
    dtype: DType,
    //,
    skip_digit_check: Bool = False,
](
    value: Scalar[dtype],
    ndigits_to_remove: Int,
    sign: Bool = False,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) -> Scalar[dtype] where (dtype == DType.uint128 or dtype == DType.uint256):
    """Rounds an integer coefficient by removing its last `ndigits_to_remove`
    decimal digits with the specified rounding mode.

    Parameters:
        dtype: Must be either `DType.uint128` or `DType.uint256`.
        skip_digit_check: If true, the function assumes `ndigits_to_remove` is
            valid (i.e. ≤ the number of digits in `value`) and skips the
            check that would otherwise return early for large `ndigits_to_remove`.
            This is an optimization for hot paths that have already validated
            `ndigits_to_remove` against `number_of_digits(value)`.

    Args:
        value: The coefficient to round.
        ndigits_to_remove: How many trailing decimal digits to discard.
            Must be ≥ 0.  If 0 the value is returned unchanged.
        sign: The sign of the logical number (needed for CEILING / FLOOR
            translation).
        rounding_mode: The rounding strategy.  Defaults to banker's
            rounding (`ROUND_HALF_EVEN`).

    Returns:
        The rounded coefficient with `ndigits_to_remove` fewer decimal
        digits.

    Examples:

        Remove 3 digits from 123456 with half-even rounding:

        >>> round_coefficient(UInt128(123456), ndigits_to_remove=3)
        123

        Remove 1 digit from 125 with half-even rounding (rounds to even):

        >>> round_coefficient(UInt128(125), ndigits_to_remove=1)
        12

        Remove 1 digit from 135 with half-even rounding (rounds to even):

        >>> round_coefficient(UInt128(135), ndigits_to_remove=1)
        14

        End of examples.
    """

    comptime ValueType = Scalar[dtype]

    # Nothing to remove.
    if ndigits_to_remove <= 0:
        return value

    # Fast path: if more digits would be removed than the value has, the
    # truncated quotient is 0 and the remainder is the whole value, which is
    # strictly less than `divisor / 10`. Therefore `2 * remainder < divisor`,
    # so every HALF_* and DOWN-equivalent mode rounds to 0, while UP-equivalent
    # modes round to 1 (when the value is non-zero). Handling this here avoids
    # invoking `power_of_10` with an exponent that may overflow `Scalar[dtype]`
    # when the caller passes a very large `ndigits_to_remove` (e.g. via
    # `Decimal128.round()` with a strongly negative `ndigits`).
    #
    # Hot-path callers that have already validated `ndigits_to_remove` against
    # `number_of_digits(value)` (e.g. `fit_to_max_coefficient`) instantiate
    # this with `skip_digit_check=True` to elide the redundant
    # `number_of_digits` call (~50 ns on UInt256). The branch below is then
    # constant-folded away by the compiler.
    comptime if not skip_digit_check:
        if ndigits_to_remove > number_of_digits(value):
            if value == 0:
                return ValueType(0)
            var fast_mode = rounding_mode
            if rounding_mode == RoundingMode.ceiling():
                fast_mode = (
                    RoundingMode.up() if not sign else RoundingMode.down()
                )
            elif rounding_mode == RoundingMode.floor():
                fast_mode = (
                    RoundingMode.down() if not sign else RoundingMode.up()
                )
            if fast_mode == RoundingMode.up():
                return ValueType(1)
            return ValueType(0)

    # Single divmod: writing `// + %` lets LLVM compute one division and
    # derive the remainder via `a - (a/b) * b`, then CSE-dedup the shared
    # division (verified at the ARM64 asm level).
    # An earlier `value - truncated * divisor` rewrite was strictly more
    # source code for identical generated code.
    var divisor = power_of_10_unsafe[dtype](ndigits_to_remove)
    # UInt256 // UInt256 lowers to a generic shift-subtract software loop
    # (~250 ns on aarch64). For UInt256, redirect to the Granlund-Möller
    # reciprocal multiplier (`udiv_u256_by_pow10_gm`, ~5 ns) for the
    # `1 ≤ k ≤ 29` range that covers every Decimal128 multiply/round
    # call site (since `combined_num_bits ≤ 192` implies `k ≤ 29`).
    # The `else` arm is a defensive fallback for any future caller that
    # might exceed that range; it pays the slow native u256 divide.
    # UInt128 // UInt128 already maps to compiler-rt's hardware-fast
    # `__udivti3`, so leave that path alone.
    var truncated: ValueType
    comptime if dtype == DType.uint256:
        if ndigits_to_remove >= 1 and ndigits_to_remove <= 29:
            truncated = rebind[ValueType](
                udiv_u256_by_pow10_gm(rebind[UInt256](value), ndigits_to_remove)
            )
        else:
            truncated = value // divisor
    else:
        truncated = value // divisor
    # Derive the remainder from the (already known) truncated quotient and
    # divisor — one wide multiply + one wide subtract, no second division.
    var remainder = value - truncated * divisor

    # Translate directed modes into sign-independent UP / DOWN.
    var effective_mode = rounding_mode
    if rounding_mode == RoundingMode.ceiling():
        effective_mode = RoundingMode.up() if not sign else RoundingMode.down()
    elif rounding_mode == RoundingMode.floor():
        effective_mode = RoundingMode.down() if not sign else RoundingMode.up()

    # DOWN — just truncate.
    if effective_mode == RoundingMode.down():
        pass

    # UP — round away from zero when anything was discarded.
    elif effective_mode == RoundingMode.up():
        if remainder > 0:
            truncated += 1

    # HALF_UP — round up when remainder ≥ half the divisor.
    # Equivalent to the classic `remainder >= 5 * 10^(n-1)` but uses
    # `2 * remainder >= divisor` (.NET trick #2) to avoid an extra
    # power-of-10 lookup and wide multiply.
    elif effective_mode == RoundingMode.half_up():
        var double_remainder = remainder << 1  # 2 * remainder
        if double_remainder >= divisor:
            truncated += 1

    # HALF_DOWN — round up only when remainder > half the divisor.
    elif effective_mode == RoundingMode.half_down():
        var double_remainder = remainder << 1
        if double_remainder > divisor:
            truncated += 1

    # HALF_EVEN — banker's rounding: round to nearest; if exactly half,
    # round to even.  `2 * remainder` vs `divisor` decides >, <, or ==.
    elif effective_mode == RoundingMode.half_even():
        var double_remainder = remainder << 1
        if double_remainder > divisor:
            truncated += 1
        elif double_remainder == divisor:
            # Exactly half — round to even.
            truncated += truncated % 2

    else:
        debug_assert(
            False,
            "Unknown rounding mode in round_coefficient",
        )

    return truncated


# DEPRECATED: Use `round_coefficient` instead.
# This function is kept for backward compatibility but is no longer used
# in production code.  `round_coefficient` is faster because it:
#   (1) takes ndigits_to_remove (avoids redundant number_of_digits call),
#   (2) computes remainder via multiply instead of a second division, and
#   (3) uses 2*remainder vs divisor instead of 5*power_of_10(n-1) cutoff.
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

        # Collect digits for rounding decision.
        # Use the safe `power_of_10` here (not `_unsafe`): this function
        # is DEPRECATED and not on the hot path, so prefer the variant
        # with a `debug_assert`ed bound over the trust-the-caller fast path.
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
                "Unknown rounding mode in round_to_keep_first_n_digits",
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


@always_inline
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

    comptime assert dtype.is_integral(), "must be integral"

    # Delegate to `std.bit.bit_width`, which lowers to a hardware
    # `count_leading_zeros` (single-instruction for ≤ 64-bit, two CLZs
    # for 128-bit). This replaces the previous O(n) shift-and-count loop
    # that took up to 128 iterations on a generic `UInt128` (96 in
    # practice for Decimal128 coefficients).
    if value < 0:
        value = -value

    return Int(bit_width(value))


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
# Or, simply create a module-level inline array with hard-coded powers of 10
# up to 58, which is the maximum number of digits we need to handle for
# Dec128 coefficients.
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
    Returns 10^n via a balanced bisect if/else search.

    Parameters:
        dtype: The Mojo scalar type to calculate the power of 10 for.

    Args:
        n: The exponent to raise 10 to.

    Constraints:
        `dtype` must be either `DType.uint128` or `DType.uint256`.

    Returns:
        The value of 10^n as a Mojo scalar.

    Notes:

        **WARNING**: The bound on `n` is only checked when `debug_assert`
        is enabled. Callers must guarantee `n <= 38` for `uint128` and
        `n <= 58` for `uint256`.

        Implementation is a balanced binary-search if/else tree (depth
        ~5 for uint128, ~6 for uint256). Each leaf returns a comptime
        literal which the compiler materialises with `mov`/`movk`
        immediates. No memory traffic. Does not depend on the
        `comptime InlineArray` -> stack-rebuild path.
    """

    comptime if dtype == DType.uint128:
        # 10^38 ~= 1e38 < 2^128 ~= 3.4e38, so 10^38 is the largest power
        # of 10 representable in UInt128.
        debug_assert(n <= 38, "power_of_10[uint128]: n must be <= 38")
        if n < 14:
            if n < 7:
                if n < 3:
                    if n < 1:
                        return 1
                    else:
                        if n == 1:
                            return 10
                        else:
                            return 100
                else:
                    if n < 5:
                        if n == 3:
                            return 1000
                        else:
                            return 10000
                    else:
                        if n == 5:
                            return 100000
                        else:
                            return 1000000
            else:
                if n < 10:
                    if n < 8:
                        return 10000000
                    else:
                        if n == 8:
                            return 100000000
                        else:
                            return 1000000000
                else:
                    if n < 12:
                        if n == 10:
                            return 10000000000
                        else:
                            return 100000000000
                    else:
                        if n == 12:
                            return 1000000000000
                        else:
                            return 10000000000000
        else:
            if n < 21:
                if n < 17:
                    if n < 15:
                        return 100000000000000
                    else:
                        if n == 15:
                            return 1000000000000000
                        else:
                            return 10000000000000000
                else:
                    if n < 19:
                        if n == 17:
                            return 100000000000000000
                        else:
                            return 1000000000000000000
                    else:
                        if n == 19:
                            return 10000000000000000000
                        else:
                            return 100000000000000000000
            else:
                if n < 29:
                    if n < 25:
                        if n < 23:
                            if n == 21:
                                return 1000000000000000000000
                            else:
                                return 10000000000000000000000
                        else:
                            if n == 23:
                                return 100000000000000000000000
                            else:
                                return 1000000000000000000000000
                    else:
                        if n < 27:
                            if n == 25:
                                return 10000000000000000000000000
                            else:
                                return 100000000000000000000000000
                        else:
                            if n == 27:
                                return 1000000000000000000000000000
                            else:
                                return 10000000000000000000000000000
                else:
                    # n in 29..38
                    if n < 33:
                        if n < 31:
                            if n == 29:
                                return 100000000000000000000000000000
                            else:
                                return 1000000000000000000000000000000
                        else:
                            if n == 31:
                                return 10000000000000000000000000000000
                            else:
                                return 100000000000000000000000000000000
                    else:
                        if n < 36:
                            if n < 34:
                                return 1000000000000000000000000000000000
                            else:
                                if n == 34:
                                    return 10000000000000000000000000000000000
                                else:
                                    return 100000000000000000000000000000000000
                        else:
                            if n < 38:
                                if n == 36:
                                    return 1000000000000000000000000000000000000
                                else:
                                    return (
                                        10000000000000000000000000000000000000
                                    )
                            else:
                                return 100000000000000000000000000000000000000
    else:
        debug_assert(n <= 58, "power_of_10[uint256]: n must be <= 58")
        if n < 29:
            if n < 14:
                if n < 7:
                    if n < 3:
                        if n < 1:
                            return 1
                        else:
                            if n == 1:
                                return 10
                            else:
                                return 100
                    else:
                        if n < 5:
                            if n == 3:
                                return 1000
                            else:
                                return 10000
                        else:
                            if n == 5:
                                return 100000
                            else:
                                return 1000000
                else:
                    if n < 10:
                        if n < 8:
                            return 10000000
                        else:
                            if n == 8:
                                return 100000000
                            else:
                                return 1000000000
                    else:
                        if n < 12:
                            if n == 10:
                                return 10000000000
                            else:
                                return 100000000000
                        else:
                            if n == 12:
                                return 1000000000000
                            else:
                                return 10000000000000
            else:
                if n < 21:
                    if n < 17:
                        if n < 15:
                            return 100000000000000
                        else:
                            if n == 15:
                                return 1000000000000000
                            else:
                                return 10000000000000000
                    else:
                        if n < 19:
                            if n == 17:
                                return 100000000000000000
                            else:
                                return 1000000000000000000
                        else:
                            if n == 19:
                                return 10000000000000000000
                            else:
                                return 100000000000000000000
                else:
                    if n < 25:
                        if n < 23:
                            if n == 21:
                                return 1000000000000000000000
                            else:
                                return 10000000000000000000000
                        else:
                            if n == 23:
                                return 100000000000000000000000
                            else:
                                return 1000000000000000000000000
                    else:
                        if n < 27:
                            if n == 25:
                                return 10000000000000000000000000
                            else:
                                return 100000000000000000000000000
                        else:
                            if n == 27:
                                return 1000000000000000000000000000
                            else:
                                return 10000000000000000000000000000
        else:
            if n < 44:
                if n < 36:
                    if n < 32:
                        if n < 30:
                            return 100000000000000000000000000000
                        else:
                            if n == 30:
                                return 1000000000000000000000000000000
                            else:
                                return 10000000000000000000000000000000
                    else:
                        if n < 34:
                            if n == 32:
                                return 100000000000000000000000000000000
                            else:
                                return 1000000000000000000000000000000000
                        else:
                            if n == 34:
                                return 10000000000000000000000000000000000
                            else:
                                return 100000000000000000000000000000000000
                else:
                    if n < 40:
                        if n < 38:
                            if n == 36:
                                return 1000000000000000000000000000000000000
                            else:
                                return 10000000000000000000000000000000000000
                        else:
                            if n == 38:
                                return 100000000000000000000000000000000000000
                            else:
                                return 1000000000000000000000000000000000000000
                    else:
                        if n < 42:
                            if n == 40:
                                return 10000000000000000000000000000000000000000
                            else:
                                return (
                                    100000000000000000000000000000000000000000
                                )
                        else:
                            if n == 42:
                                return (
                                    1000000000000000000000000000000000000000000
                                )
                            else:
                                return (
                                    10000000000000000000000000000000000000000000
                                )
            else:
                if n < 51:
                    if n < 47:
                        if n < 45:
                            return 100000000000000000000000000000000000000000000
                        else:
                            if n == 45:
                                return 1000000000000000000000000000000000000000000000
                            else:
                                return 10000000000000000000000000000000000000000000000
                    else:
                        if n < 49:
                            if n == 47:
                                return 100000000000000000000000000000000000000000000000
                            else:
                                return 1000000000000000000000000000000000000000000000000
                        else:
                            if n == 49:
                                return 10000000000000000000000000000000000000000000000000
                            else:
                                return 100000000000000000000000000000000000000000000000000
                else:
                    if n < 55:
                        if n < 53:
                            if n == 51:
                                return 1000000000000000000000000000000000000000000000000000
                            else:
                                return 10000000000000000000000000000000000000000000000000000
                        else:
                            if n == 53:
                                return 100000000000000000000000000000000000000000000000000000
                            else:
                                return 1000000000000000000000000000000000000000000000000000000
                    else:
                        if n < 57:
                            if n == 55:
                                return 10000000000000000000000000000000000000000000000000000000
                            else:
                                return 100000000000000000000000000000000000000000000000000000000
                        else:
                            if n == 57:
                                return 1000000000000000000000000000000000000000000000000000000000
                            else:
                                return 10000000000000000000000000000000000000000000000000000000000


# ===----------------------------------------------------------------------=== #
# `power_of_10_unsafe` - high-performance variant using string-literal rodata
#
# Yuhao's notes:
# Each entry is laid out as a contiguous little-endian byte sequence inside a
# `StringLiteral`. `StringLiteral.unsafe_ptr().bitcast[Scalar[dtype]]()[n]`
# yields the n-th power of 10 with a single indexed load - no stack
# materialisation, no per-call-site `comptime InlineArray` rebuild.
#
# Why not just use this in `power_of_10`? Because the bitcast trick is a
# workaround for Mojo's lack of module-level cached variables; it is not
# elegant Mojo. When Mojo grows real module-level variables, this entire
# section can be replaced with a single shared `var POWER_OF_10_U128 =
# InlineArray[UInt128, 29](...)` and `power_of_10` can call into it
# directly. Until then, hot paths that need every nanosecond use
# `power_of_10_unsafe`; the public `power_of_10` keeps the elegant
# bisect implementation.
#
# Total rodata cost: 30 * 16 + 59 * 32 = 2 368 bytes.
# ===----------------------------------------------------------------------=== #


comptime _POWER_OF_10_U128_BLOB = (
    "\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x0a\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x64\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\xe8\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x10\x27\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\xa0\x86\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x40\x42\x0f\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x80\x96\x98\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\xe1\xf5\x05\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\xca\x9a\x3b\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\xe4\x0b\x54\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\xe8\x76\x48\x17\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x10\xa5\xd4\xe8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\xa0\x72\x4e\x18\x09\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x40\x7a\x10\xf3\x5a\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x80\xc6\xa4\x7e\x8d\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\xc1\x6f\xf2\x86\x23\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x8a\x5d\x78\x45\x63\x01\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x64\xa7\xb3\xb6\xe0\x0d\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\xe8\x89\x04\x23\xc7\x8a\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x10\x63\x2d\x5e\xc7\x6b\x05\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\xa0\xde\xc5\xad\xc9\x35\x36\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x40\xb2\xba\xc9\xe0\x19\x1e\x02\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x80\xf6\x4a\xe1\xc7\x02\x2d\x15\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\xa1\xed\xcc\xce\x1b\xc2\xd3\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x4a\x48\x01\x14\x16\x95\x45\x08\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\xe4\xd2\x0c\xc8\xdc\xd2\xb7\x52\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\xe8\x3c\x80\xd0\x9f\x3c\x2e\x3b\x03\x00\x00\x00\x00"
    + "\x00\x00\x00\x10\x61\x02\x25\x3e\x5e\xce\x4f\x20\x00\x00\x00\x00"
    + "\x00\x00\x00\xa0\xca\x17\x72\x6d\xae\x0f\x1e\x43\x01\x00\x00\x00"
)


comptime _POWER_OF_10_U256_BLOB = (
    "\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x0a\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x64\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\xe8\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x10\x27\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\xa0\x86\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x40\x42\x0f\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x80\x96\x98\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\xe1\xf5\x05\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\xca\x9a\x3b\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\xe4\x0b\x54\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\xe8\x76\x48\x17\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x10\xa5\xd4\xe8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\xa0\x72\x4e\x18\x09\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x40\x7a\x10\xf3\x5a\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x80\xc6\xa4\x7e\x8d\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\xc1\x6f\xf2\x86\x23\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x8a\x5d\x78\x45\x63\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x64\xa7\xb3\xb6\xe0\x0d\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\xe8\x89\x04\x23\xc7\x8a\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x10\x63\x2d\x5e\xc7\x6b\x05\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\xa0\xde\xc5\xad\xc9\x35\x36\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x40\xb2\xba\xc9\xe0\x19\x1e\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x80\xf6\x4a\xe1\xc7\x02\x2d\x15\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\xa1\xed\xcc\xce\x1b\xc2\xd3\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x4a\x48\x01\x14\x16\x95\x45\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\xe4\xd2\x0c\xc8\xdc\xd2\xb7\x52\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\xe8\x3c\x80\xd0\x9f\x3c\x2e\x3b\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x10\x61\x02\x25\x3e\x5e\xce\x4f\x20\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\xa0\xca\x17\x72\x6d\xae\x0f\x1e\x43\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x40\xea\xed\x74\x46\xd0\x9c\x2c\x9f\x0c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x80\x26\x4b\x91\xc0\x22\x20\xbe\x37\x7e\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x81\xef\xac\x85\x5b\x41\x6d\x2d\xee\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x0a\x5b\xc1\x38\x93\x8d\x44\xc6\x4d\x31\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x64\x8e\x8d\x37\xc0\x87\xad\xbe\x09\xed\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\xe8\x8f\x87\x2b\x82\x4d\xc7\x72\x61\x42\x13\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x10\x9f\x4b\xb3\x15\x07\xc9\x7b\xce\x97\xc0\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\xa0\x36\xf4\x00\xd9\x46\xda\xd5\x10\xee\x85\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x40\x22\x8a\x09\x7a\xc4\x86\x5a\xa8\x4c\x3b\x4b\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x80\x56\x65\x5f\xc4\xac\x43\x89\x93\xfe\x50\xf0\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x61\xf5\xb9\xab\xbf\xa4\x5c\xc3\xf1\x29\x63\x1d\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\xca\x95\x43\xb5\x7c\x6f\x9e\xa1\x71\xa3\xdf\x25\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\xe4\xd9\xa3\x14\xdf\x5a\x30\x50\x70\x62\xbc\x7a\x0b\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\xe8\x82\x66\xce\xb6\x8c\xe3\x21\x63\xd8\x5b\xcb\x72\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x10\x1d\x01\x10\x24\x7f\xe3\x52\xdf\x73\x96\xf1\x7b\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\xa0\x22\x0b\xa0\x68\xf7\xe2\x3c\xb9\x86\xe0\x6f\xd7\x2c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x40\x5a\x6f\x40\x16\xaa\xdd\x60\x3c\x43\xc5\x5e\x6a\xc0\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x80\x86\x59\x84\xde\xa4\xa8\xc8\x5b\xa0\xb4\xb3\x27\x84\x11\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x00\x41\x7f\x2b\xb1\x70\x96\xd6\x95\x43\x0e\x05\x8d\x29\xaf\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x00\x8a\xf8\xb2\xeb\x66\xe0\x61\xda\xa3\x8e\x32\x82\x9f\xd7\x06\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x00\x64\xb5\xfd\x34\x05\xc4\xd2\x87\x66\x92\xf9\x15\x3b\x6c\x44\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x00\xe8\x15\xe9\x11\x34\xa8\x3b\x4e\x01\xb8\xbf\xdb\x4e\x3a\xac\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x00\x10\xdb\x1a\xb3\x08\x92\x54\x0e\x0d\x30\x7d\x95\x14\x47\xba\x1a\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x00\xa0\x8e\x0c\xff\x56\xb4\x4d\x8f\x82\xe0\xe3\xd6\xcd\xc6\x46\x0b\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x00\x40\x92\x7d\xf6\x65\x0b\x09\x99\x19\xc5\xe6\x64\x0a\xc4\xc3\x70\x0a\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x00\x80\xb6\xe7\xa0\xfb\x71\x5a\xfa\xff\xb2\x03\xf1\x67\xa8\xa5\x67\x68\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x00\x00\x21\x0d\x49\xd4\x73\x88\xc7\xff\xfd\x24\x6a\x0f\x94\x78\x0c\x14\x04\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x00\x00\x4a\x83\xda\x4a\x86\x54\xcb\xfd\xeb\x71\x25\x9a\xc8\xb5\x7c\xc8\x28\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x00\x00\x00\x00\x00\x00\x00\xe4\x20\x89\xec\x3e\x4d\xf1\xe9\x37\x73\x76\x05\xd6\x19\xdf\xd4\x97\x01\x00\x00\x00\x00\x00\x00\x00"
)


@always_inline
def power_of_10_unsafe[
    dtype: DType
](n: Int) -> Scalar[dtype] where (
    dtype == DType.uint128 or dtype == DType.uint256
):
    """
    Returns 10^n via a single indexed load from a string-literal rodata blob.

    Parameters:
        dtype: The Mojo scalar type to calculate the power of 10 for. Must be
            either `DType.uint128` or `DType.uint256`.

    Args:
        n: The exponent to raise 10 to.

    Constraints:
        `dtype` must be either `DType.uint128` or `DType.uint256`.

    Returns:
        The value of 10^n as a Mojo scalar.

    Notes:

        **WARNING**: This function performs **no runtime bounds check** in
        release builds (`-D ASSERT=none`). Out-of-range `n` will read past
        the end of the rodata blob and return arbitrary bits. Callers must
        guarantee `0 <= n <= 29` for `uint128` and `0 <= n <= 58` for
        `uint256`. A `debug_assert` catches violations in debug builds
        (`-D ASSERT=all`); use `power_of_10` (asserted, raises) when you
        cannot prove `n` is in range.

        Implementation: each entry is a 16-byte (uint128) or 32-byte
        (uint256) little-endian raw value packed contiguously in a
        `StringLiteral` blob. `unsafe_ptr().bitcast[Scalar[dtype]]()[n]`
        yields the n-th value with a single indexed load. The
        `StringLiteral` lives in rodata for the lifetime of the program;
        no stack materialisation, no allocation, no per-call-site
        `InlineArray` rebuild.

        TODO: Drop this function once Mojo grows module-level variables
        and the elegant `var POWER_OF_10_U128 = InlineArray[UInt128, 29]`
        approach becomes possible. See the comment block above for the
        full migration plan.
    """

    comptime if dtype == DType.uint128:
        # Developer-only bounds check: catches OOB callers in debug builds
        # (`-D ASSERT=all`) without spending a cycle in release builds. The
        # documented contract still says "no runtime bounds check"; this is
        # an extra safety net during development, not a load-bearing check.
        debug_assert(
            n >= 0 and n <= 29,
            "power_of_10_unsafe[uint128]: n out of range, must be 0..29",
        )
        # `alignment=1`: `StringLiteral` rodata is only byte-aligned, but a
        # bare `bitcast[Scalar[uint128]]()[n]` would tell LLVM the load is
        # 16-byte aligned (the natural alignment of `UInt128`). On strict
        # platforms (e.g. some ARM cores) that can fault if the compiler
        # emits an aligned-only instruction. The explicit `alignment=1`
        # forces an unaligned load (same machine code on x86_64 / Apple
        # Silicon, but portably correct).
        return (
            _POWER_OF_10_U128_BLOB.unsafe_ptr()
            .bitcast[Scalar[dtype]]()
            .load[alignment=1](n)
        )
    else:
        debug_assert(
            n >= 0 and n <= 58,
            "power_of_10_unsafe[uint256]: n out of range, must be 0..58",
        )
        return (
            _POWER_OF_10_U256_BLOB.unsafe_ptr()
            .bitcast[Scalar[dtype]]()
            .load[alignment=1](n)
        )


# ===----------------------------------------------------------------------=== #
# Granlund-Möller reciprocal-multiplication divider for `value // 10^k`.
#
# Strategy
# For a fixed divisor `d`, the unsigned quotient `floor(n/d)` can be
# computed with one wide multiply + one shift, using the well-known
# Granlund-Möller algorithm (Hacker's Delight §10-9):
#
#     ell    = ceil(log2(d))
#     m_full = ceil(2^(N+ell) / d)        (fits in N+1 bits)
#     m'     = m_full - 2^N               (fits in N bits)
#
#     t1 = mulhi_N(m', n)                 (high N bits of m' * n)
#     q  = (((n - t1) >> 1) + t1) >> (ell - 1)
#
# For `d = 10^k` with `1 ≤ k ≤ 29`, the resulting `m'` is always 256-bit
# and we precompute the table at the bottom of this file. Replacing the
# 32-step schoolbook divide with a single 256×256→high-256 multiply plus
# two shifts brings the divide down to roughly the cost of the multiply
# itself (~5 ns on aarch64), versus ~250 ns for the generic UInt256 //
# UInt256 software loop that LLVM falls back to.
#
# Coverage
# `1 ≤ k ≤ 29` covers every `Decimal128` multiply/round call site
# (since `combined_num_bits ≤ 192` implies `k ≤ 29`). For any future
# caller that exceeds that range, `round_coefficient` falls back to
# the native `value // divisor` path.
# ===----------------------------------------------------------------------=== #


comptime _U256_MASK_LO128 = UInt256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)


@always_inline
fn _mulhi_u256(a: UInt256, b: UInt256) -> UInt256:
    """Returns the high 256 bits of `a * b` (both unsigned 256-bit).

    Splits each operand into two u128 halves and uses the schoolbook
    formula:

        a * b  =  (ah*bh) << 256
               +  (ah*bl + al*bh) << 128
               +   al*bl

    The high 256 bits = `ah*bh` + (top 128 of each cross term)
    + (carry from summing the middle 128 bits).

    Each `UInt256(u128_a) * UInt256(u128_b)` cross-product is exact
    (both factors fit in 128 bits, so the 256-bit product never
    overflows the low 256 bits returned by Mojo's `*`).
    """
    var ah = UInt128(a >> 128)
    var al = UInt128(a & _U256_MASK_LO128)
    var bh = UInt128(b >> 128)
    var bl = UInt128(b & _U256_MASK_LO128)

    var ll = UInt256(al) * UInt256(bl)  # bits [  0..256)
    var lh = UInt256(al) * UInt256(bh)  # bits [128..384)
    var hl = UInt256(ah) * UInt256(bl)  # bits [128..384)
    var hh = UInt256(ah) * UInt256(bh)  # bits [256..512)

    var mid = (ll >> 128) + (lh & _U256_MASK_LO128) + (hl & _U256_MASK_LO128)
    return hh + (lh >> 128) + (hl >> 128) + (mid >> 128)


# Precomputed Granlund-Möller reciprocals for `d = 10^k`, `k ∈ [0, 29]`.
# Index 0 is unused (zero-padded so callers can use `k` as the index).
# Each entry is the 256-bit `m' = ceil(2^(256+ell)/d) - 2^256`
# stored little-endian, 32 bytes per slot.
#
# Generated offline (Python, verified against random 2k inputs per `k`):
#   N = 256
#   for k in range(1, 30):
#       d   = 10**k
#       ell = (d-1).bit_length()
#       m   = -((-(1 << (N+ell))) // d)        # ceil
#       mp  = m - (1 << N)
#       blob.extend(mp.to_bytes(32, "little"))
comptime _GM_RECIPROCAL_BLOB = (
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + "\x9a\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99"
    + "\xaf\x47\xe1\x7a\x14\xae\x47\xe1\x7a\x14\xae\x47\xe1\x7a\x14\xae\x47\xe1\x7a\x14\xae\x47\xe1\x7a\x14\xae\x47\xe1\x7a\x14\xae\x47"
    + "\xbf\x9f\x1a\x2f\xdd\x24\x06\x81\x95\x43\x8b\x6c\xe7\xfb\xa9\xf1\xd2\x4d\x62\x10\x58\x39\xb4\xc8\x76\xbe\x9f\x1a\x2f\xdd\x24\x06"
    + "\x98\xff\x90\x7e\xfb\x3a\x70\xce\x88\xd2\xde\xe0\x0b\x93\xa9\x82\x51\x49\x9d\x80\x26\xc2\x86\xa7\x57\xca\x32\xc4\xb1\x2e\x6e\xa3"
    + "\x79\xcc\x40\x65\xfc\xfb\x8c\x0b\x07\x42\xb2\x80\x09\xdc\xba\x9b\xa7\x3a\xe4\x66\xb8\x01\x9f\x1f\x46\x08\x8f\x36\x8e\x58\x8b\x4f"
    + "\x2e\x3d\x9a\xea\xc9\xfc\xa3\x6f\xd2\x34\x28\x9a\x07\xb0\xc8\xaf\x1f\x62\x83\x85\x93\x34\x7f\x4c\x6b\xd3\xd8\x5e\x0b\x7a\x6f\x0c"
    + "\x49\xc8\xf6\x10\x43\x61\x06\x19\xb7\x87\x73\xc3\xa5\x19\x41\x19\x99\x36\xd2\x08\xec\x20\x65\x7a\x78\x85\xf4\xca\xab\x29\x7f\xad"
    + "\xa1\x06\x5f\xda\x68\xe7\xd1\xe0\xf8\xd2\xc2\x02\xeb\x7a\x9a\x7a\x7a\xf8\x74\x6d\x56\x1a\x84\xfb\xf9\x9d\xc3\x08\x23\xee\x98\x57"
    + "\x4e\x05\x4c\x48\xba\x52\x0e\xe7\x93\x75\x35\x02\xbc\xc8\xae\xfb\x61\x60\x2a\xf1\x11\x15\xd0\x62\x2e\x4b\x69\x6d\x82\xbe\xe0\x12"
    + "\x16\xa2\x79\x40\x5d\x84\xb0\x71\xb9\x55\x22\x9d\xf9\x0d\x7e\x5f\x36\x9a\x10\xb5\x1c\x88\xe6\x6a\x7d\xab\xdb\x7b\x9d\xfd\xcd\xb7"
    + "\xab\x81\x94\x33\xe4\x69\xc0\x27\x61\x11\xb5\x7d\x94\x71\xfe\xe5\x91\xae\x73\x2a\x4a\xd3\x1e\xef\xfd\x55\x49\x96\x17\xfe\xd7\x5f"
    + "\x89\x34\xdd\xc2\xe9\x87\x33\x86\x1a\x41\xf7\xca\x76\xf4\x31\xeb\xa7\x8b\x5c\x88\x6e\x0f\x7f\xf2\x97\x11\xa1\xde\x12\x98\x79\x19"
    + "\x0e\x54\xc8\x37\xa9\x0c\xec\x09\xc4\x01\xf2\x77\x24\x87\xe9\x11\x73\xdf\x60\x0d\xe4\x4b\xcb\x50\x26\x1c\x68\x97\x84\x26\x5c\xc2"
    + "\x0b\x10\x6d\xf9\x20\x0a\xf0\x07\xd0\x67\x8e\xf9\xe9\x38\x21\xdb\x28\x19\xe7\x3d\x83\x09\x09\xa7\x1e\xb0\xb9\x12\x6a\xb8\x49\x68"
    + "\xd6\x0c\x24\x61\x1a\x08\xc0\x6c\xa6\xec\x71\x94\x21\xc7\x4d\xaf\x20\x14\xec\x97\x02\x6e\x3a\x1f\xb2\x59\x61\x75\xee\xf9\x3a\x20"
    + "\x56\xe1\x6c\x9b\x90\xa6\x99\x47\x0a\xe1\x4f\xba\x35\xd8\xe2\x7e\x67\x53\x13\xf3\xd0\x7c\x5d\x98\xb6\xc2\x9b\x88\x7d\x29\x2b\xcd"
    + "\x45\xb4\xf0\x15\xda\x1e\xae\x9f\x6e\x1a\x73\xfb\x2a\xe0\x1b\xff\x85\x0f\xa9\xf5\x73\xfd\x7d\x13\x92\x68\x49\x6d\x64\x54\xef\x70"
    + "\x6b\xc3\xf3\x77\xae\x18\x58\x19\xf2\xe1\x28\xc9\x88\xe6\xaf\x65\x9e\x3f\x87\xc4\x5c\x64\xfe\x75\x0e\xba\x3a\x24\x1d\xdd\x25\x27"
    + "\x11\x9f\x1f\xf3\xe3\x8d\x26\xc2\xe9\xcf\xa7\x0e\x0e\xa4\x4c\x3c\xca\x65\xd8\xa0\xc7\xd3\x63\x56\x4a\xc3\x2a\x6d\xfb\x94\x3c\xd8"
    + "\x74\xb2\x7f\xc2\x1c\x0b\x52\x9b\x54\xa6\xec\x3e\x0b\x50\x3d\x30\x08\xeb\x79\x4d\x39\x76\xe9\x11\xd5\x35\x22\x24\xc9\x10\xca\x79"
    + "\x29\xf5\x32\x35\x4a\x6f\x0e\x49\xdd\x51\xbd\x98\xa2\xd9\xfd\x8c\x06\xbc\x94\xd7\x2d\xf8\xed\xa7\xdd\xf7\xb4\xe9\xa0\x40\x3b\x2e"
    + "\x42\x88\x51\x88\x43\xe5\xe3\x74\xc8\x4f\x95\x27\x04\x29\x96\xe1\x70\xc6\xba\x25\x16\x8d\x49\xa6\x62\x59\xee\x75\x01\x01\x92\xe3"
    + "\xcf\x39\x41\xa0\xcf\x1d\x83\x5d\xa0\x0c\x11\x86\x36\x87\xde\x1a\x27\x05\x2f\x1e\x78\x0a\x6e\xeb\x4e\x14\x25\x2b\x01\x34\xdb\x82"
    + "\xd9\xc7\xcd\x19\xa6\xe4\x68\xe4\x19\x0a\x74\x9e\x2b\x6c\x18\xaf\x85\x6a\xf2\xe4\x2c\xd5\x24\x89\xa5\x76\xea\x88\x9a\x29\x7c\x35"
    + "\xc1\x3f\x49\x29\x70\x07\xdb\xd3\x8f\x76\x86\xfd\x78\x13\x27\x18\x09\x44\xea\x07\x7b\xbb\x07\x75\xa2\x8a\xdd\xa7\x5d\x0f\x2d\xef"
    + "\xcd\xff\xa0\xba\x59\x6c\xe2\x0f\x73\xf8\xd1\xca\x60\xdc\xb8\x79\x3a\x03\x55\x06\xfc\x95\x6c\x2a\xb5\x3b\xb1\xec\x4a\x0c\x24\x8c"
    + "\x0b\x33\xe7\x2e\xae\x56\xe8\x3f\x8f\x93\x41\xa2\x80\xe3\x93\x94\xfb\x68\xaa\x9e\xc9\x44\xbd\xee\x90\xfc\xc0\x23\x6f\xa3\xe9\x3c"
    + "\x11\xb8\x3e\x7e\xe3\xbd\x73\x99\x4b\x1f\x9c\x03\x01\x6c\xb9\xed\xf8\xa7\x10\x31\xdc\x3a\x95\x17\x1b\x94\x01\x06\xe5\x6b\x0f\xfb"
    + "\xa7\xf9\xfe\x64\x1c\xcb\x8f\x47\x09\x19\xb0\xcf\x00\xf0\x2d\xbe\x60\x86\x40\x27\xb0\xc8\xdd\x12\x7c\x76\x34\x6b\xea\xef\xa5\x95"
)


# Per-`k` shift amount (`ell - 1`), 30 entries (index 0 unused).
# Same offline generation; max value is 96 (k=29), comfortably ≤ 255.
comptime _GM_SHIFT_BLOB = (
    "\x00\x03\x06\x09\x0d\x10\x13\x17\x1a\x1d"
    + "\x21\x24\x27\x2b\x2e\x31\x35\x38\x3b\x3f"
    + "\x42\x45\x49\x4c\x4f\x53\x56\x59\x5d\x60"
)


@always_inline
fn udiv_u256_by_pow10_gm(value: UInt256, k: Int) -> UInt256:
    """Returns `floor(value / 10^k)` using one mulhi-256 plus a shift.

    Args:
        value: The UInt256 dividend.
        k: The exponent. Must satisfy `1 ≤ k ≤ 29`.

    Returns:
        The quotient `floor(value / 10^k)`.

    Notes:
        Caller must guarantee `1 ≤ k ≤ 29`. No bounds check (not even
        via `debug_assert`) is performed — out-of-range `k` will read
        past the precomputed reciprocal table and return garbage.

        For `k = 0` or `k > 29`, use `udiv_u256_by_pow10` instead.

        Cost: ~5 ns on aarch64 (single 256×256→high-256 multiply +
        two shifts), versus ~22 ns for `udiv_u256_by_pow10`.

        Algorithm: Granlund-Möller saturating reciprocal (Hacker's
        Delight §10-9). The 256-bit reciprocal `m'` and shift amount
        `ell - 1` for each `d = 10^k` are precomputed in the
        `_GM_RECIPROCAL_BLOB` and `_GM_SHIFT_BLOB` rodata blobs.
    """
    # `alignment=1`: see the corresponding note in `power_of_10_unsafe`.
    # `StringLiteral.unsafe_ptr()` only guarantees byte alignment, so we
    # must request an explicitly unaligned 32-byte load to remain portable.
    var mp = (
        _GM_RECIPROCAL_BLOB.unsafe_ptr().bitcast[UInt256]().load[alignment=1](k)
    )
    var shift = Int(_GM_SHIFT_BLOB.unsafe_ptr()[k])
    var t1 = _mulhi_u256(mp, value)
    var t = ((value - t1) >> 1) + t1
    return t >> UInt256(shift)


@always_inline
fn udiv_u256_by_u64(n: UInt256, d: UInt64) -> Tuple[UInt256, UInt64]:
    """Schoolbook UInt256 / UInt64 division, hardware-fast on aarch64.

    Args:
        n: The 256-bit dividend.
        d: The 64-bit divisor. Must be non-zero.

    Returns:
        A tuple `(quotient, remainder)` with the 256-bit quotient and
        the 64-bit remainder (`r < d`).

    Notes:
        Splits `n` into four 64-bit limbs (high to low) and processes one
        limb per step:

            temp = (rem << 64) | limb_i
            q_i  = temp // d
            rem  = temp - q_i * d

        Each step is a 128-bit / 64-bit divide (hardware-supported via
        `__udivti3`/`udiv` on M-series). Standalone cost ~12 ns vs ~236
        ns for the generic `UInt256 // UInt256` software loop.

        Used by `arithmetics.divide()` to replace the per-digit long
        division loop with one big scaled divide whenever the divisor
        coefficient fits in 64 bits (which covers all currently-tracked
        bench cases — `Decimal128` divisors above 2^64 are rare).
    """
    debug_assert(d != UInt64(0), "udiv_u256_by_u64: divisor must be non-zero")
    var l3 = UInt128((n >> 192) & UInt256(0xFFFF_FFFF_FFFF_FFFF))
    var l2 = UInt128((n >> 128) & UInt256(0xFFFF_FFFF_FFFF_FFFF))
    var l1 = UInt128((n >> 64) & UInt256(0xFFFF_FFFF_FFFF_FFFF))
    var l0 = UInt128(n & UInt256(0xFFFF_FFFF_FFFF_FFFF))
    var d128 = UInt128(d)

    var rem: UInt128 = 0
    var t: UInt128 = (rem << 64) | l3
    var q3 = t // d128
    rem = t - q3 * d128
    t = (rem << 64) | l2
    var q2 = t // d128
    rem = t - q2 * d128
    t = (rem << 64) | l1
    var q1 = t // d128
    rem = t - q1 * d128
    t = (rem << 64) | l0
    var q0 = t // d128
    rem = t - q0 * d128

    var quot = (
        (UInt256(q3) << 192)
        | (UInt256(q2) << 128)
        | (UInt256(q1) << 64)
        | UInt256(q0)
    )
    return (quot, UInt64(rem))
