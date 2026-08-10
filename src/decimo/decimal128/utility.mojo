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

"""Internal utility functions for the Decimal128 type.

WARNING: These functions are implementation details and are not meant to be
used directly by end users. They support the public Decimal128 API with
low-level helpers such as bit manipulation, rounding helpers, and
representation conversions.
"""

from std.memory import Pointer
from std import sys
from std import time
from std.bit import bit_width
from std.builtin.globals import global_constant

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
    var result = Pointer(to=dec).unsafe_bitcast[Scalar[dtype]]().unsafe_load()
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
# TODO: Currently, this won't work when you create a .mojoc package to use.
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


# ===----------------------------------------------------------------------=== #
# Power-of-10 lookup tables
#
# Yuhao's notes:
# The tables are module-level `comptime` `Array`s.  A `comptime` value has no
# runtime memory location, so reading one with a *runtime* index needs an
# explicit bridge into runtime code.  Mojo offers three:
#
#   1. `materialize[TABLE]()[n]` - the compiler's own fix-it.  It creates the
#      storage *per use site*, so under `@always_inline` LLVM often rebuilds
#      the whole table on the stack with immediate stores before the single
#      indexed load.
#   2. A `comptime for` over the index that binds the selected entry as a
#      `comptime` value and returns it immediately.  The loop is unrolled at
#      compile time and folds into a jump table of immediates - no memory
#      traffic, but the code grows linearly with the table.
#   3. `global_constant[TABLE]()` - emits the table once into static storage
#      (rodata) for the whole program and hands back a `ref` to it.  One
#      indexed load, no per-call-site setup, no code growth.  This is the
#      one to use; (1) and (2) only existed because it was not available.
#
# Measured with a standalone microbenchmark on osx-arm64.
# `global_constant` wins everywhere.
# ===----------------------------------------------------------------------=== #


comptime _POWER_OF_10_U128: Array[UInt128, 39] = [
    1,
    10,
    100,
    1000,
    10000,
    100000,
    1000000,
    10000000,
    100000000,
    1000000000,
    10000000000,
    100000000000,
    1000000000000,
    10000000000000,
    100000000000000,
    1000000000000000,
    10000000000000000,
    100000000000000000,
    1000000000000000000,
    10000000000000000000,
    100000000000000000000,
    1000000000000000000000,
    10000000000000000000000,
    100000000000000000000000,
    1000000000000000000000000,
    10000000000000000000000000,
    100000000000000000000000000,
    1000000000000000000000000000,
    10000000000000000000000000000,
    100000000000000000000000000000,
    1000000000000000000000000000000,
    10000000000000000000000000000000,
    100000000000000000000000000000000,
    1000000000000000000000000000000000,
    10000000000000000000000000000000000,
    100000000000000000000000000000000000,
    1000000000000000000000000000000000000,
    10000000000000000000000000000000000000,
    100000000000000000000000000000000000000,
]


comptime _POWER_OF_10_U256: Array[UInt256, 59] = [
    1,
    10,
    100,
    1000,
    10000,
    100000,
    1000000,
    10000000,
    100000000,
    1000000000,
    10000000000,
    100000000000,
    1000000000000,
    10000000000000,
    100000000000000,
    1000000000000000,
    10000000000000000,
    100000000000000000,
    1000000000000000000,
    10000000000000000000,
    100000000000000000000,
    1000000000000000000000,
    10000000000000000000000,
    100000000000000000000000,
    1000000000000000000000000,
    10000000000000000000000000,
    100000000000000000000000000,
    1000000000000000000000000000,
    10000000000000000000000000000,
    100000000000000000000000000000,
    1000000000000000000000000000000,
    10000000000000000000000000000000,
    100000000000000000000000000000000,
    1000000000000000000000000000000000,
    10000000000000000000000000000000000,
    100000000000000000000000000000000000,
    1000000000000000000000000000000000000,
    10000000000000000000000000000000000000,
    100000000000000000000000000000000000000,
    1000000000000000000000000000000000000000,
    10000000000000000000000000000000000000000,
    100000000000000000000000000000000000000000,
    1000000000000000000000000000000000000000000,
    10000000000000000000000000000000000000000000,
    100000000000000000000000000000000000000000000,
    1000000000000000000000000000000000000000000000,
    10000000000000000000000000000000000000000000000,
    100000000000000000000000000000000000000000000000,
    1000000000000000000000000000000000000000000000000,
    10000000000000000000000000000000000000000000000000,
    100000000000000000000000000000000000000000000000000,
    1000000000000000000000000000000000000000000000000000,
    10000000000000000000000000000000000000000000000000000,
    100000000000000000000000000000000000000000000000000000,
    1000000000000000000000000000000000000000000000000000000,
    10000000000000000000000000000000000000000000000000000000,
    100000000000000000000000000000000000000000000000000000000,
    1000000000000000000000000000000000000000000000000000000000,
    10000000000000000000000000000000000000000000000000000000000,
]


@always_inline
def power_of_10[
    dtype: DType
](n: Int) -> Scalar[dtype] where (
    dtype == DType.uint128 or dtype == DType.uint256
):
    """
    Returns 10^n via a single indexed load from a program-lifetime table.

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
        is enabled. Callers must guarantee `0 <= n <= 38` for `uint128`
        and `0 <= n <= 58` for `uint256`. An out-of-range `n` reads past
        the table and returns garbage in release builds.

        Implementation: `global_constant` places the table in static
        read-only storage once for the whole program; the lookup is one
        `adrp`/`ldr` pair, independent of table size. This replaced a
        balanced bisect if/else tree of comptime literals, which was
        ~18x slower for `uint128` and ~23x slower for `uint256`. See the
        notes above the tables.
    """

    comptime if dtype == DType.uint128:
        # 10^38 ~= 1e38 < 2^128 ~= 3.4e38, so 10^38 is the largest power
        # of 10 representable in UInt128.
        debug_assert(
            n >= 0 and n <= 38, "power_of_10[uint128]: n must be in 0..38"
        )
        ref table = global_constant[_POWER_OF_10_U128]()
        return rebind[Scalar[dtype]](table[n])
    else:
        debug_assert(
            n >= 0 and n <= 58, "power_of_10[uint256]: n must be in 0..58"
        )
        ref table = global_constant[_POWER_OF_10_U256]()
        return rebind[Scalar[dtype]](table[n])


@always_inline
def power_of_10_unsafe[
    dtype: DType
](n: Int) -> Scalar[dtype] where (
    dtype == DType.uint128 or dtype == DType.uint256
):
    """
    Returns 10^n via a single indexed load, with a narrower documented range.

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
        release builds (`-D ASSERT=none`). Callers must guarantee
        `0 <= n <= 29` for `uint128` and `0 <= n <= 58` for `uint256`. A
        `debug_assert` catches violations in debug builds
        (`-D ASSERT=all`). An out-of-range `n` reads past the table and
        returns garbage; earlier revisions returned `0`, which was never
        a contract - do not rely on either.

        This is now the same single indexed load as `power_of_10`; the
        two differ only in the documented range they assert (`0..29` here
        versus `0..38` there for `uint128`). The stricter assert is kept
        because most `Decimal128` call sites can prove `n <= 29` and want
        the tighter debug-build check. The historical performance gap
        between the two is gone - both compile to the same single load.

        Migration note: this used to read from a packed `StringLiteral`
        rodata blob via `unsafe_ptr().bitcast[Scalar[dtype]]().load[
        alignment=1](n)`. Mojo 1.0.0b1 changed `StringLiteral` to
        always-UTF-8-encode arbitrary byte literals (e.g. `\\x9a` became
        the 2-byte sequence `[0xC2, 0x9A]`), corrupting the blob. Mojo
        1.1 then renamed `InlineArray` to `Array` and dropped its
        `ImplicitlyCopyable` conformance, forcing a `materialize` /
        `comptime for` workaround until `global_constant` arrived and
        restored the original single-load-from-rodata behaviour.
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
        ref table = global_constant[_POWER_OF_10_U128]()
        return rebind[Scalar[dtype]](table[n])
    else:
        debug_assert(
            n >= 0 and n <= 58,
            "power_of_10_unsafe[uint256]: n out of range, must be 0..58",
        )
        ref table = global_constant[_POWER_OF_10_U256]()
        return rebind[Scalar[dtype]](table[n])


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
def _mulhi_u256(a: UInt256, b: UInt256) -> UInt256:
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
comptime _GM_RECIPROCAL: Array[UInt256, 30] = [
    0,  # k=0 unused
    69475253542389717254142591005212744711961990799384338423674550404747877783962,  # k=1
    32421784986448534718599875802432614198915595706379357931048123522215676299183,  # k=2
    2779010141695588690165703640208509788478479631975373536946982016189915111359,  # k=3
    73921669769102659158407716829546360373527558210544936082789721630651741962136,  # k=4
    35978917967818888242011976461899506728168049635307836058340260502938767641721,  # k=5
    5624716526791871508895384167782023811880442775118156038780691600768388185390,  # k=6
    78474799985256711668375205673663982810970699239573388085723656965977298880585,  # k=7
    39621422140742130249985967537193604678122562458530597660687408771199213176481,  # k=8
    8538719865130465115274577028017302171844053033696365320658410215376744613198,  # k=9
    83137205326598461438581914250040428186912475653298522936728006749350669165078,  # k=10
    43351346413815530066151334398294760978875983589510705541490888597897909404075,  # k=11
    11522659283589184968206870516898227212446789938480451625301194076735701595273,  # k=12
    87911508396132413203273583832249908251876854700953061024156460927525000336398,  # k=13
    47170788869442691477904670064062345030847486827634336011433651940437374341131,  # k=14
    14578213248090914097609539049512294454023992528979356001255404750767273544918,  # k=15
    92800394739335179810317853484432415838400378845751308025683198005975515455830,  # k=16
    51081897944004904763540085785808351100066306143472933612655041603197786436677,  # k=17
    17707100507740684726117871626909099309399047981650234082232516480975603221355,  # k=18
    97806614354774812815931185608267303607000467570024712955246576774308842938129,  # k=19
    55086873636356611168030751484876261314946377122891657556305744617864448422516,  # k=20
    20911081061622049849710404186163427481303104765185213237153078892708932810025,  # k=21
    102932983240984997013679237703074228682046958423680679603119476633082170280002,  # k=22
    59187968745324758526229193160721801374983569805816430874604064504883110296015,  # k=23
    24191957148796567736269157526839859529332858911525031891791734802323862308825,  # k=24
    108182384980464225632173243048156519958894565057824389450541326088466057478081,  # k=25
    63387490136908141421024397436787634396461655113131398752541544069190220054477,  # k=26
    27551574262063274052105320947692525946515327157377006194141718453769550115595,  # k=27
    113557772361690955737511104521520786226386514251187548334301299930779157968913,  # k=28
    67687800041889525505294686615479047410455214467821925859549523143040700447143,  # k=29
]


# Per-`k` shift amount (`ell - 1`), 30 entries (index 0 unused).
# Same offline generation; max value is 96 (k=29), comfortably ≤ 255.
comptime _GM_SHIFT: Array[UInt8, 30] = [
    0,  # k=0 unused
    3,  # k=1
    6,  # k=2
    9,  # k=3
    13,  # k=4
    16,  # k=5
    19,  # k=6
    23,  # k=7
    26,  # k=8
    29,  # k=9
    33,  # k=10
    36,  # k=11
    39,  # k=12
    43,  # k=13
    46,  # k=14
    49,  # k=15
    53,  # k=16
    56,  # k=17
    59,  # k=18
    63,  # k=19
    66,  # k=20
    69,  # k=21
    73,  # k=22
    76,  # k=23
    79,  # k=24
    83,  # k=25
    86,  # k=26
    89,  # k=27
    93,  # k=28
    96,  # k=29
]


@always_inline
def udiv_u256_by_pow10_gm(value: UInt256, k: Int) -> UInt256:
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
        `_GM_RECIPROCAL` and `_GM_SHIFT` tables, which
        `global_constant` places in program-lifetime rodata.
    """
    # `global_constant` emits each table once into program-lifetime rodata
    # and hands back a `ref`, so this is two indexed loads with no
    # per-call-site setup. `materialize` rebuilt the 30 x UInt256
    # reciprocal table on the stack at every inlined site: 19.05 ns/call
    # for the whole divider versus 3.93 ns here (osx-arm64, release
    # build). See the notes above the power-of-10 tables.
    ref reciprocals = global_constant[_GM_RECIPROCAL]()
    ref shifts = global_constant[_GM_SHIFT]()
    var mp = reciprocals[k]
    var shift = Int(shifts[k])
    var t1 = _mulhi_u256(mp, value)
    var t = ((value - t1) >> 1) + t1
    return t >> UInt256(shift)


@always_inline
def udiv_u256_by_u64(n: UInt256, d: UInt64) -> Tuple[UInt256, UInt64]:
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
