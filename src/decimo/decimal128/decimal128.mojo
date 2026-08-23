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

"""Implements basic object methods for the Decimal128 type.

This module contains the basic object methods for the Decimal128 type.
These methods include constructors, life time methods, output dunders,
type-transfer dunders, basic arithmetic operation dunders, comparison
operation dunders, and other dunders that implement traits, as well as
mathematical methods that do not implement a trait.
"""

from std.collections import Span
from std.memory import Pointer
from std.sys import bit_width_of
from std.hashlib.hasher import Hasher

import decimo.decimal128.arithmetics as decimal128_arithmetics
import decimo.decimal128.comparison as decimal128_comparison
import decimo.decimal128.constants as decimal128_constants
import decimo.decimal128.exponential as decimal128_exponential
import decimo.decimal128.rounding as decimal128_rounding
from decimo.rounding_mode import RoundingMode
from decimo.errors import (
    ValueError,
    OverflowError,
    ConversionError,
)
import decimo.decimal128.utility as decimal128_utility
from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.traits import Numeric, Parsable, Rootable

comptime Dec128 = Decimal128
"""A 128-bit fixed-point decimal number."""


struct Decimal128(
    Absable,
    Boolable,
    Comparable,
    Floatable,
    Hashable,
    IntableRaising,
    Numeric,
    Parsable,
    Rootable,
    Roundable,
    TrivialRegisterPassable,
    Writable,
):
    """A 128-bit fixed-point decimal number.

    Notes:

    Internal Representation:

    Each decimal128 uses a 128-bit on memory, where:
    - 96 bits for the coefficient (significand), which is 96-bit unsigned
    integers stored as three 32 bit integer (little-endian).
        - Bit 0 to 31 are stored in the low field: least significant bits.
        - Bit 32 to 63 are stored in the mid field: middle bits.
        - Bit 64 to 95 are stored in the high field: most significant bits.
    - 32 bits for the flags, which contain the sign and scale information.
        - Bits 0 to 15 are unused and must be zero.
        - Bits 16 to 23 must contain a scale (exponent) between 0 and 28.
        - Bits 24 to 30 are unused and must be zero.
        - Bit 31 contains the sign: 0 mean positive, and 1 means negative.

    The value of the coefficient is: `high * 2**64 + mid * 2**32 + low`
    The final value is: `(-1)**sign * coefficient * 10**(-scale)`
    """

    # ===------------------------------------------------------------------=== #
    # Organization of fields and methods:
    # - Internal representation fields
    # - Constants (aliases)
    # - Special values (methods)
    # - Constructors and life time methods
    # - Constructing methods that are not dunders
    # - Output dunders, type-transfer dunders, and other type-transfer methods
    # - Basic unary arithmetic operation dunders
    # - Basic binary arithmetic operation dunders
    # - Basic binary arithmetic operation dunders with reflected operands
    # - Basic binary augmented arithmetic operation dunders
    # - Basic comparison operation dunders
    # - Other dunders that implements traits
    # - Mathematical methods that do not implement a trait (not a dunder)
    # - Other methods
    # - Internal methods
    # ===------------------------------------------------------------------=== #

    # Internal representation fields
    var low: UInt32
    """Least significant 32 bits of coefficient."""
    var mid: UInt32
    """Middle 32 bits of coefficient."""
    var high: UInt32
    """Most significant 32 bits of coefficient."""
    var flags: UInt32
    """Scale information and the sign."""

    # Constants
    comptime MAX_SCALE: Int = 28
    """The maximum scale (exponent) value for `Decimal128` (28)."""
    comptime MAX_AS_UINT128 = UInt128(79228162514264337593543950335)
    """The maximum coefficient value as `UInt128`."""
    comptime MAX_AS_INT128 = Int128(79228162514264337593543950335)
    """The maximum coefficient value as `Int128`."""
    comptime MAX_AS_UINT256 = UInt256(79228162514264337593543950335)
    """The maximum coefficient value as `UInt256`."""
    comptime MAX_AS_INT256 = Int256(79228162514264337593543950335)
    """The maximum coefficient value as `Int256`."""
    comptime MAX_AS_STRING = String("79228162514264337593543950335")
    """Maximum value as a string."""
    comptime MAX_NUM_DIGITS = 29
    """Number of digits of the max value 79228162514264337593543950335."""
    comptime SIGN_MASK = UInt32(0x80000000)
    """Sign mask. `0b1000_0000_0000_0000_0000_0000_0000_0000`.
    1 bit for sign (0 is positive and 1 is negative)."""
    comptime SCALE_MASK = UInt32(0x00FF0000)
    """Scale mask. `0b0000_0000_1111_1111_0000_0000_0000_0000`.
    Bits 16 to 23 must contain a scale between 0 and 28."""
    comptime SCALE_SHIFT = UInt32(16)
    """Bits 16 to 23 must contain a scale between 0 and 28."""
    # TODO: Move these special values to top of the module
    # when Mojo support global variables in the future.

    # `zero()` and `one()` are the `Numeric` spelling of `ZERO()` and `ONE()`
    # below, which predate the trait and stay as they are.
    @always_inline
    @staticmethod
    def zero() -> Self:
        """Returns a Decimal128 representing 0.

        Returns:
            A `Decimal128` representing zero.
        """
        return Self.ZERO()

    @always_inline
    @staticmethod
    def one() -> Self:
        """Returns a Decimal128 representing 1.

        Returns:
            A `Decimal128` representing one.
        """
        return Self.ONE()

    # Special values
    @always_inline
    @staticmethod
    def ZERO() -> Self:
        """Returns a Decimal128 representing 0.

        Returns:
            A `Decimal128` representing zero.
        """
        return Self(0, 0, 0, 0)

    @always_inline
    @staticmethod
    def ONE() -> Self:
        """Returns a Decimal128 representing 1.

        Returns:
            A `Decimal128` representing one.
        """
        return Self(1, 0, 0, 0)

    @always_inline
    @staticmethod
    def MAX() -> Self:
        """
        Returns the maximum possible Decimal128 value.
        This is equivalent to 79228162514264337593543950335.

        Returns:
            The maximum `Decimal128` value.
        """
        return Self(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0)

    @always_inline
    @staticmethod
    def MIN() -> Self:
        """Returns the minimum possible Decimal128 value (negative of MAX).
        This is equivalent to -79228162514264337593543950335.

        Returns:
            The minimum `Decimal128` value.
        """
        return Self(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, Decimal128.SIGN_MASK)

    @always_inline
    @staticmethod
    def PI() -> Self:
        """Returns the value of pi (π) as a Decimal128.

        Returns:
            The value of pi (π).
        """
        return decimal128_constants.PI()

    @always_inline
    @staticmethod
    def E() -> Self:
        """Returns the value of Euler's number (e) as a Decimal128.

        Returns:
            The value of Euler's number (e).
        """
        return decimal128_constants.E()

    # ===------------------------------------------------------------------=== #
    # Constructors and life time dunder methods
    # ===------------------------------------------------------------------=== #

    def __init__(out self):
        """Initializes a decimal128 instance with value 0."""
        self.low = 0x00000000
        self.mid = 0x00000000
        self.high = 0x00000000
        self.flags = 0x00000000

    def __init__(
        out self, low: UInt32, mid: UInt32, high: UInt32, flags: UInt32
    ):
        """Initializes a Decimal128 with four raw words of internal representation.
        ***WARNING***: This method does not check the flags at runtime.
        If you are not sure about the flags, use `Decimal128.from_words()` instead.

        Args:
            low: The least significant 32 bits of the coefficient.
            mid: The middle 32 bits of the coefficient.
            high: The most significant 32 bits of the coefficient.
            flags: The raw flags word containing scale and sign.
        """

        # Developer-only sanity check: catches invalid scale at construction
        # time so downstream hot paths (e.g. `is_integer()`, `is_one()`) can
        # safely use `power_of_10_unsafe` without a fallback. Compiled out
        # in release builds (`-D ASSERT=none`).
        debug_assert(
            ((flags & Self.SCALE_MASK) >> Self.SCALE_SHIFT)
            <= UInt32(Self.MAX_SCALE),
            "Decimal128(low, mid, high, flags): scale must be <= MAX_SCALE",
        )

        self.low = low
        self.mid = mid
        self.high = high
        self.flags = flags

    def __init__(
        out self,
        low: UInt32,
        mid: UInt32,
        high: UInt32,
        scale: UInt32,
        sign: Bool,
    ) raises:
        """Initializes a Decimal128 with five components.
        See `Decimal128.from_components()` for more information.

        Args:
            low: The least significant 32 bits of the coefficient.
            mid: The middle 32 bits of the coefficient.
            high: The most significant 32 bits of the coefficient.
            scale: The number of decimal places (0-28).
            sign: `True` if the number is negative, `False` otherwise.

        Raises:
            ConversionError: If the initialization fails.
        """

        try:
            self = Decimal128.from_components(low, mid, high, scale, sign)
        except e:
            raise ConversionError(
                message="Cannot initialize with five components.",
                function="Decimal128.__init__()",
                previous_error=e^,
            )

    @always_inline
    @implicit
    def __init__(out self, value: Int):
        """Initializes a Decimal128 from an integer.
        See `from_int()` for more information.

        Args:
            value: The integer value to convert.
        """
        self = Decimal128.from_int(value)

    def __init__(out self, value: Int, scale: UInt32) raises:
        """Initializes a Decimal128 from an integer.
        See `from_int()` for more information.

        Args:
            value: The integer value to convert.
            scale: The number of decimal places (0-28).

        Raises:
            ConversionError: If the value cannot be represented.
        """
        try:
            self = Decimal128.from_int(value, scale)
        except e:
            raise ConversionError(
                message="Cannot initialize Decimal128 from Int.",
                function="Decimal128.__init__()",
                previous_error=e^,
            )

    @always_inline
    def __init__(out self, value: String) raises:
        """Initializes a Decimal128 from a string representation.
        See `from_string()` for more information.

        Args:
            value: The string representation of the decimal number.

        Raises:
            ConversionError: If the string cannot be parsed.
        """
        try:
            self = Decimal128.from_string(value)
        except e:
            raise ConversionError(
                message="Cannot initialize Decimal128 from String.",
                function="Decimal128.__init__()",
                previous_error=e^,
            )

    def __init__(out self, value: Float64) raises:
        """Initializes a Decimal128 from a floating-point value.
        See `from_float_scalar()` for more information.

        Args:
            value: The floating-point value to convert.

        Raises:
            ConversionError: If the float cannot be converted.
        """

        try:
            self = Decimal128.from_float_scalar(value)
        except e:
            raise ConversionError(
                message="Cannot initialize Decimal128 from Float64.",
                function="Decimal128.__init__()",
                previous_error=e^,
            )

    # ===------------------------------------------------------------------=== #
    # Constructing methods that are not dunders
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def from_components(
        low: UInt32,
        mid: UInt32,
        high: UInt32,
        scale: UInt32,
        sign: Bool,
    ) raises -> Self:
        """Initializes a Decimal128 with five components.

        Args:
            low: Least significant 32 bits of coefficient.
            mid: Middle 32 bits of coefficient.
            high: Most significant 32 bits of coefficient.
            scale: Number of decimal128 places (0-28).
            sign: True if the number is negative.

        Returns:
            A Decimal128 instance with the given components.

        Raises:
            ValueError: If the scale exceeds 28.
        """

        if scale > UInt32(Self.MAX_SCALE):
            raise ValueError(
                message=String(
                    "Scale must be between 0 and 28, but got {}."
                ).format(scale),
                function="Decimal128.from_components()",
            )

        var flags: UInt32 = 0
        flags |= (scale << Self.SCALE_SHIFT) & Self.SCALE_MASK
        flags |= UInt32(sign) << 31

        return Self(low, mid, high, flags)

    @staticmethod
    def from_words(
        low: UInt32, mid: UInt32, high: UInt32, flags: UInt32
    ) raises -> Self:
        """Initializes a Decimal128 with four raw words of internal representation.
        Compared to `__init__()` with four words, this method checks the flags.

        Args:
            low: Least significant 32 bits of coefficient.
            mid: Middle 32 bits of coefficient.
            high: Most significant 32 bits of coefficient.
            flags: Scale information and the sign.

        Returns:
            A Decimal128 instance with the given words.

        Raises:
            ValueError: If the `flags` word has invalid bits set.
            ValueError: If the scale is greater than MAX_SCALE.
        """

        # Check whether the `flags` word is valid.
        if (flags & 0b0111_1111_0000_0000_1111_1111_1111_1111) != 0:
            raise ValueError(
                message=String(
                    "Flags must have bits 0-15 and 24-30 set to zero,"
                    " but got {}"
                ).format(flags),
                function="Decimal128.from_words()",
            )

        var scale = (flags & 0x00FF0000) >> Self.SCALE_SHIFT
        if scale > UInt32(Self.MAX_SCALE):
            raise ValueError(
                message=String(
                    "Scale must be between 0 and 28, but got {}"
                ).format(scale),
                function="Decimal128.from_words()",
            )

        return Self(low, mid, high, flags)

    @staticmethod
    def from_int(value: Int) -> Self:
        """Initializes a Decimal128 from an integer.

        Args:
            value: The integer value to convert to Decimal128.

        Returns:
            The Decimal128 representation of the integer.

        Notes:

        Since Int is a 64-bit type in Mojo, the `high` field will always be 0.

        Examples:
        ```mojo
        from decimo import Decimal128
        var dec1 = Decimal128.from_int(-123) # -123
        var dec2 = Decimal128.from_int(1) # 1
        ```
        End of examples.
        """

        var low: UInt32
        var mid: UInt32
        var flags: UInt32

        if value >= 0:
            flags = 0
            low = UInt32(value & 0xFFFFFFFF)
            mid = UInt32((value >> 32) & 0xFFFFFFFF)
        else:
            var abs_value = -value
            flags = Self.SIGN_MASK
            low = UInt32(abs_value & 0xFFFFFFFF)
            mid = UInt32((abs_value >> 32) & 0xFFFFFFFF)

        return Self(low, mid, 0, flags)

    @staticmethod
    def from_int(value: Int, scale: UInt32) raises -> Self:
        """Initializes a Decimal128 from an integer and a scale.

        Args:
            value: The integer value to convert to Decimal128.
            scale: The number of decimal128 places (0-28).

        Returns:
            The Decimal128 representation of the integer.

        Raises:
            ValueError: If the scale exceeds 28.

        Notes:

        Since Int is a 64-bit type in Mojo, the `high` field will always be 0.

        Examples:
        ```mojo
        from decimo import Decimal128
        var dec1 = Decimal128.from_int(-123, scale=2) # -1.23
        var dec2 = Decimal128.from_int(1, scale=5) # 0.00001
        ```
        End of examples.
        """

        var low: UInt32
        var mid: UInt32
        var flags: UInt32

        if scale > UInt32(Self.MAX_SCALE):
            raise ValueError(
                message=String(
                    "Scale must be between 0 and 28, but got {}"
                ).format(scale),
                function="Decimal128.from_int()",
            )

        if value >= 0:
            flags = 0
            low = UInt32(value & 0xFFFFFFFF)
            mid = UInt32((value >> 32) & 0xFFFFFFFF)

        else:
            var abs_value = -value
            flags = Self.SIGN_MASK
            low = UInt32(abs_value & 0xFFFFFFFF)
            mid = UInt32((abs_value >> 32) & 0xFFFFFFFF)

        flags |= (scale << Self.SCALE_SHIFT) & Self.SCALE_MASK

        return Self(low, mid, 0, flags)

    # This method is primarily intended for the bench harness, where a high
    # precision BigDecimal reference value can be quantised to the
    # Decimal128 grid so that the two string representations are
    # directly comparable.
    @staticmethod
    def from_decimal(value: BigDecimal) raises -> Self:
        """Initializes a Decimal128 from a BigDecimal with rounding.

        The BigDecimal value is rendered to its plain string form
        (`force_plain = True`) and then parsed via `from_string()`,
        which applies banker's rounding (`ROUND_HALF_EVEN`) when the value has
        more than 28 fractional digits and raises `OverflowError` when
        the integral part does not fit in 96 bits.

        Args:
            value: The BigDecimal value to convert to Decimal128.

        Returns:
            The Decimal128 representation of `value`, rounded to at most
            28 fractional digits using banker's rounding.

        Raises:
            OverflowError: If the integral part of `value` does not fit
                in the 96-bit Decimal128 coefficient.

        Examples:

        ```mojo
        from decimo.prelude import *
        var bd = BigDecimal("3.14159265358979323846264338327950288")
        var d  = Decimal128.from_decimal(bd)
        print(d)  # 3.1415926535897932384626433833
        ```
        End of examples.
        """
        return Self.from_string(value.to_string(force_plain=True))

    @staticmethod
    @no_inline
    def _raise_from_uint128_value_too_large(value: UInt128) raises -> None:
        raise ValueError(
            message=String("Value must fit in 96 bits, but got {}").format(
                value
            ),
            function="Decimal128.from_uint128()",
        )

    @staticmethod
    @no_inline
    def _raise_from_uint128_scale_too_large(scale: UInt32) raises -> None:
        raise ValueError(
            message=String("Scale must be between 0 and 28, but got {}").format(
                scale
            ),
            function="Decimal128.from_uint128()",
        )

    @staticmethod
    @no_inline
    def _raise_from_string_invalid_char(
        code: UInt8, value: String
    ) raises -> None:
        # Non-ASCII bytes (>127) carry the raw byte hex + original input so
        # users can diagnose UTF-8 encoding issues. ASCII fall-through uses
        # `chr()`. Both branches allocate via `String.format(...)` -- kept
        # `@no_inline` so the allocation does not bloat the hot scan loop in
        # `from_string` (Lesson #4 from decimal128_enhancement).
        if code > 127:
            raise ValueError(
                message=String(
                    "Invalid non-ASCII byte {} in decimal128 string: {}"
                ).format(hex(Int(code)), value),
                function="Decimal128.from_string()",
            )
        raise ValueError(
            message=String("Invalid character in decimal128 string: {}").format(
                chr(Int(code))
            ),
            function="Decimal128.from_string()",
        )

    @staticmethod
    @always_inline
    def from_uint128(
        value: UInt128, scale: UInt32 = 0, sign: Bool = False
    ) raises -> Self:
        """Initializes a Decimal128 from a UInt128 value.

        Args:
            value: The UInt128 value to convert to Decimal128.
            scale: The number of decimal128 places (0-28).
            sign: True if the number is negative.

        Returns:
            The Decimal128 representation of the UInt128 value.

        Raises:
            ValueError: If the value does not fit in 96 bits.
            ValueError: If the scale exceeds 28.
        """

        if value >> 96 != 0:
            Self._raise_from_uint128_value_too_large(value)

        if scale > UInt32(Self.MAX_SCALE):
            Self._raise_from_uint128_scale_too_large(scale)

        var result = Pointer(to=value).unsafe_bitcast[Decimal128]()[]
        result.flags |= (scale << Self.SCALE_SHIFT) & Self.SCALE_MASK
        result.flags |= UInt32(sign) << 31

        return result

    @staticmethod
    def from_string(value: String) raises -> Self:
        """Initializes a Decimal128 from a string representation.

        Args:
            value: The string representation of the Decimal128.

        Returns:
            The Decimal128 representation of the string.

        Raises:
            ValueError: If the string contains invalid characters.
            OverflowError: If the exponent is too large.

        Notes:

        Only the following characters are allowed in the input string:
        - Digits 0-9.
        - Decimal point ".". It can only appear once.
        - Negative sign "-". It can only appear before the first digit.
        - Positive sign "+". It can only appear before the first digit or after
            exponent "e" or "E".
        - Exponential notation "e" or "E". It can only appear once after the
            digits.
        - Space " ". It can appear anywhere in the string it is ignored.
        - Comma ",". It can appear anywhere between digits it is ignored.
        - Underscore "_". It can appear anywhere between digits it is ignored.
        """

        var value_string_slice = StringSlice(value)
        var value_bytes = value_string_slice.as_bytes()
        var value_bytes_len = len(value_bytes)

        if value_bytes_len == 0:
            return Decimal128.ZERO()

        # NOTE: A previous version did a separate full-input pass to reject
        # non-ASCII bytes. That pre-scan is now folded into the main loop:
        # any unrecognised byte ends up in the catch-all `else` branch,
        # which raises ValueError. Non-ASCII bytes (`code > 127`) are
        # special-cased there to include the offending byte value and the
        # original input string in the error message.

        # Yuhao's notes:
        # We scan each char in the string input.
        var mantissa_sign_read = False
        var mantissa_start = False
        var mantissa_significant_start = False
        var decimal_point_read = False
        var exponent_notation_read = False
        var exponent_sign_read = False
        # var exponent_start = False
        var unexpected_end_char = False

        var mantissa_sign: Bool = False  # True if negative
        var exponent_sign: Bool = False  # True if negative
        var coef: UInt128 = 0
        var scale: UInt32 = 0
        var raw_exponent: UInt32 = 0
        var num_mantissa_digits: UInt32 = 0

        for code in value_bytes:
            # HOT PATH: digit '0'-'9' (ASCII 48-57). Checked first so the
            # common case takes one branch.
            if code >= 48 and code <= 57:
                unexpected_end_char = False
                var d = Int(code) - 48

                # Exponent part
                if exponent_notation_read:
                    # Raise / skip if exponent overflows. Use `>=` (not
                    # `>`) so that we catch the digit *before* the
                    # multiply pushes `raw_exponent` past the cap.
                    if raw_exponent >= UInt32(Decimal128.MAX_NUM_DIGITS * 2):
                        if not exponent_sign:
                            raise OverflowError(
                                message=String(
                                    "Exponent part is too large: {}"
                                ).format(raw_exponent),
                                function="Decimal128.from_string()",
                            )
                        # Negative exponent past the cap → safely ignored.
                        continue
                    raw_exponent = raw_exponent * 10 + UInt32(d)
                    exponent_sign_read = True
                    continue

                # Mantissa part
                # Skip the digit if mantissa is too long.
                if num_mantissa_digits > Decimal128.MAX_NUM_DIGITS + 8:  # 37
                    continue

                mantissa_sign_read = True
                mantissa_start = True

                # Leading zeros before the first significant digit do not
                # contribute to `coef` / `num_mantissa_digits` (mirrors the
                # previous separate '0' branch). Trailing zeros after a
                # significant digit do (e.g. "123.45000").
                if d != 0 or mantissa_significant_start:
                    num_mantissa_digits += 1
                    coef = coef * 10 + UInt128(d)
                    mantissa_significant_start = True

                if decimal_point_read:
                    scale += 1
            # If the char is " ", skip it
            elif code == 32:
                pass
            # If the char is "," or "_", skip it
            elif code == 44 or code == 95:
                unexpected_end_char = True
            # If the char is "."
            elif code == 46:
                unexpected_end_char = False
                if decimal_point_read:
                    raise ValueError(
                        message="Decimal point can only appear once.",
                        function="Decimal128.from_string()",
                    )
                else:
                    decimal_point_read = True
                    mantissa_sign_read = True
            # If the char is "-"
            elif code == 45:
                unexpected_end_char = True
                if exponent_sign_read:
                    raise ValueError(
                        message="Minus sign cannot appear twice in exponent.",
                        function="Decimal128.from_string()",
                    )
                elif exponent_notation_read:
                    exponent_sign = True
                    exponent_sign_read = True
                elif mantissa_sign_read:
                    raise ValueError(
                        message=(
                            "Minus sign can only appear once at the beginning."
                        ),
                        function="Decimal128.from_string()",
                    )
                else:
                    mantissa_sign = True
                    mantissa_sign_read = True
            # If the char is "+"
            elif code == 43:
                unexpected_end_char = True
                if exponent_sign_read:
                    raise ValueError(
                        message="Plus sign cannot appear twice in exponent.",
                        function="Decimal128.from_string()",
                    )
                elif exponent_notation_read:
                    exponent_sign_read = True
                elif mantissa_sign_read:
                    raise ValueError(
                        message=(
                            "Plus sign can only appear once at the beginning."
                        ),
                        function="Decimal128.from_string()",
                    )
                else:
                    mantissa_sign_read = True
            # If the char is "e" or "E"
            elif code == 101 or code == 69:
                unexpected_end_char = True
                if exponent_notation_read:
                    raise ValueError(
                        message="Exponential notation can only appear once.",
                        function="Decimal128.from_string()",
                    )
                if not mantissa_start:
                    raise ValueError(
                        message="Exponential notation must follow a number.",
                        function="Decimal128.from_string()",
                    )
                else:
                    exponent_notation_read = True
            else:
                # Non-ASCII bytes (>127) are typically a stray UTF-8 lead/
                # continuation byte; surfacing the raw byte via `chr()` is
                # garbled and not actionable. Defer the message build to a
                # `@no_inline` helper -- the `String.format(...)` allocation
                # would otherwise inline into the hot scan loop body and
                # bloat it (Lesson #4: keep `.format`-bearing raises out of
                # `@always_inline`-eligible parents).
                Self._raise_from_string_invalid_char(code, value)

        if unexpected_end_char:
            raise ValueError(
                message="Unexpected end character in decimal128 string.",
                function="Decimal128.from_string()",
            )

        # print("DEBUG: coef = ", coef)
        # print("DEBUG: scale = ", scale)
        # print("DEBUG: raw_exponent = ", raw_exponent)
        # print("DEBUG: exponent_sign = ", exponent_sign)

        if raw_exponent != 0:
            # If exponent is negative, increase the scale
            if exponent_sign:
                scale = scale + raw_exponent
            # If exponent is positive, decrease the scale until 0
            # then increase the coefficient
            else:
                if scale >= raw_exponent:
                    scale = scale - raw_exponent
                else:
                    var exponent_delta = Int(raw_exponent) - Int(scale)
                    # `power_of_10_unsafe[uint128]` is only defined for
                    # `0 <= n <= 29`. Anything past that would read garbage
                    # from the rodata blob (and may even silently parse to
                    # a wrong value if the garbage happens to fit in 96
                    # bits). Bail out with a clean OverflowError instead.
                    if exponent_delta > Decimal128.MAX_NUM_DIGITS:
                        raise OverflowError(
                            message=String(
                                "Exponent is too large to fit in Decimal128: {}"
                            ).format(raw_exponent),
                            function="Decimal128.from_string()",
                        )
                    coef = coef * decimal128_utility.power_of_10_unsafe[
                        DType.uint128
                    ](exponent_delta)
                    scale = 0

        # print("DEBUG: coef = ", coef)
        # print("DEBUG: scale = ", scale)

        # TODO: The following part can be written into a function
        # because it is used in many cases
        if coef <= Decimal128.MAX_AS_UINT128:
            if scale > UInt32(Decimal128.MAX_SCALE):
                coef = decimal128_utility.round_coefficient(
                    coef,
                    ndigits_to_remove=Int(scale - UInt32(Decimal128.MAX_SCALE)),
                )
                scale = UInt32(Decimal128.MAX_SCALE)

            return Decimal128.from_uint128(coef, scale, mantissa_sign)

        else:
            var fitted = decimal128_utility.fit_to_max_coefficient(coef)
            var truncated_coef = fitted[0]
            var truncated_digits = UInt32(fitted[1])
            # Guard against integral-digit overflow: if more digits were removed
            # than the current scale provides, integral digits were lost and
            # the value no longer fits Decimal128.
            if truncated_digits > scale:
                raise OverflowError(
                    message=(
                        "Cannot fit Decimal128 coefficient without removing"
                        " integral digits."
                    ),
                    function="Decimal128.from_string()",
                )
            var scale_of_truncated_coef = scale - truncated_digits

            if scale_of_truncated_coef > UInt32(Decimal128.MAX_SCALE):
                truncated_coef = decimal128_utility.round_coefficient(
                    truncated_coef,
                    ndigits_to_remove=Int(
                        scale_of_truncated_coef - UInt32(Decimal128.MAX_SCALE)
                    ),
                )
                scale_of_truncated_coef = UInt32(Decimal128.MAX_SCALE)

            return Decimal128.from_uint128(
                truncated_coef, scale_of_truncated_coef, mantissa_sign
            )

    @staticmethod
    def from_integral_scalar[
        dtype: DType, //
    ](value: Scalar[dtype]) raises -> Self where dtype.is_integral():
        """Initializes a Decimal128 from an integral scalar, with scale 0.
        This includes all SIMD integral types, both signed (Int8, Int16, Int32,
        Int64, Int128, Int256 and the platform-sized `Int`) and unsigned
        (UInt8 ... UInt256 and `UInt`).

        Constraints:
            The dtype must be integral.

        Args:
            value: The integral scalar to convert to Decimal128.

        Returns:
            The Decimal128 representation of the integral scalar.

        Raises:
            OverflowError: If the magnitude exceeds the 96-bit coefficient,
                which only 128- and 256-bit scalars can do.

        Notes:

        The `from_int()` fast path is taken only where `Int` can hold the value
        without reinterpreting it. `Int` is 64-bit and signed, so that is every
        signed scalar up to 64 bits but only unsigned scalars narrower than 64:
        `Int(UInt64.MAX)` would come out as -1. Everything else goes through the
        256-bit path, which range checks first - that is also what makes the
        negation there safe, since `Int256.MIN` has no positive counterpart and
        is rejected before it is negated.

        Examples:
        ```mojo
        from decimo import Decimal128
        var a = Decimal128.from_integral_scalar(Int8(-123))  # -123
        # 18446744073709551615
        var b = Decimal128.from_integral_scalar(UInt64.MAX)
        ```
        End of examples.

        Parameters:
            dtype: The data type of the scalar value.
        """

        comptime width = bit_width_of[Scalar[dtype]]()
        comptime fits_in_int = (width <= 64) if dtype.is_signed() else (
            width < 64
        )

        comptime if fits_in_int:
            return Self.from_int(Int(value))

        elif dtype.is_unsigned():
            var magnitude = UInt256(value)
            if magnitude > UInt256(Self.MAX_AS_UINT128):
                raise OverflowError(
                    message=String(
                        "The value {} is too large (>=2^96) to be transformed"
                        " into Decimal128."
                    ).format(value),
                    function="Decimal128.from_integral_scalar()",
                )
            return Self.from_uint128(UInt128(magnitude), 0, False)

        else:
            var signed = Int256(value)
            if (signed > Self.MAX_AS_INT256) or (signed < -Self.MAX_AS_INT256):
                raise OverflowError(
                    message=String(
                        "The value {} is out of range (>=2^96 in magnitude) to"
                        " be transformed into Decimal128."
                    ).format(value),
                    function="Decimal128.from_integral_scalar()",
                )
            var is_negative = signed < 0
            var magnitude = UInt256(-signed) if is_negative else UInt256(signed)
            return Self.from_uint128(UInt128(magnitude), 0, is_negative)

    @staticmethod
    def from_float(value: Float64) raises -> Self:
        """Initializes a Decimal128 from a Float64.

        Deprecated: use `from_float_scalar()`, which accepts any floating-point
        scalar and is the name that lines up with `from_integral_scalar()`.
        This forwards to it unchanged.

        Args:
            value: The floating-point value to convert to Decimal128.

        Returns:
            The Decimal128 representation of the floating-point value.

        Raises:
            OverflowError: If the value is too large for Decimal128.
            ValueError: If the value is infinity or NaN.
        """
        return Self.from_float_scalar(value)

    @staticmethod
    def from_float_scalar[
        dtype: DType, //
    ](value: Scalar[dtype]) raises -> Self where dtype.is_floating_point():
        """Initializes a Decimal128 from a floating-point scalar.
        This includes all SIMD floating-point types, such as Float16,
        BFloat16, Float32, Float64, and the 8-bit formats. Narrower formats are
        widened to Float64 first, which is exact: every one of them has both
        fewer significand bits and a narrower exponent range.

        The reliability of this method is limited by the precision of Float64.
        Float64 is reliable up to 15 significant digits and marginally
        reliable up to 16 siginficant digits. Be careful when using this method.

        Args:
            value: The floating-point value to convert to Decimal128.

        Returns:
            The Decimal128 representation of the floating-point value.

        Raises:
            OverflowError: If the value is too large for Decimal128.
            ValueError: If the value is infinity or NaN (IEEE 754 special values).

        Example:
        ```mojo
        from decimo import Decimal128
        # 3.1415926535897932 (17 significant digits)
        print(Decimal128.from_float_scalar(3.1415926535897932383279502))
        # 12345678901234567168 (20 digits, but only 15 are reliable)
        print(Decimal128.from_float_scalar(12345678901234567890.1234567890))
        ```
        .
        """

        var widened = value.cast[DType.float64]()

        # CASE: Zero
        if widened == Float64(0):
            return Decimal128.ZERO()

        # Get the positive value of the input
        var abs_value: Float64
        var is_negative: Bool = widened < 0
        if is_negative:
            abs_value = -widened
        else:
            abs_value = widened

        # Early exit if the value is too large
        if UInt128(abs_value) > Decimal128.MAX_AS_UINT128:
            raise OverflowError(
                message=String(
                    "The float value {} is too large (>=2^96) to be"
                    " transformed into Decimal128."
                ).format(value),
                function="Decimal128.from_float_scalar()",
            )

        # Extract binary exponent using IEEE 754 bit manipulation
        var bits: UInt64 = (
            Pointer(to=abs_value).unsafe_bitcast[UInt64]().unsafe_load()
        )
        var biased_exponent: Int = Int((bits >> 52) & 0x7FF)

        # print("DEBUG: biased_exponent = ", biased_exponent)

        # CASE: Denormalized number that is very close to zero
        if biased_exponent == 0:
            return Self(0, 0, 0, UInt32(Decimal128.MAX_SCALE), is_negative)

        # CASE: IEEE 754 Infinity or NaN — Decimal128 does not support these
        if biased_exponent == 0x7FF:
            raise ValueError(
                message=(
                    "Cannot convert IEEE 754 infinity or NaN to Decimal128."
                ),
                function="Decimal128.from_float_scalar()",
            )

        # Get unbias exponent
        var binary_exp: Int = biased_exponent - 1023
        # print("DEBUG: binary_exp = ", binary_exp)

        # Convert binary exponent to approximate decimal128 exponent
        # log10(2^exp) = exp * log10(2)
        var decimal_exp: Int = Int(Float64(binary_exp) * 0.301029995663981)
        # print("DEBUG: decimal_exp = ", decimal_exp)

        # Fine-tune decimal128 exponent
        var power_check: Float64 = abs_value / Float64(10) ** decimal_exp
        if power_check >= 10.0:
            decimal_exp += 1
        elif power_check < 1.0:
            decimal_exp -= 1

        # print("DEBUG: decimal_exp = ", decimal_exp)

        var coefficient: UInt128 = UInt128(abs_value)
        var remainder = abs(abs_value - Float64(coefficient))
        # print("DEBUG: integer_part = ", coefficient)
        # print("DEBUG: remainder = ", remainder)

        var scale = 0
        var temp_coef: UInt128
        var num_trailing_zeros: Int = 0
        while scale < Decimal128.MAX_SCALE:
            remainder *= 10
            var int_part = UInt128(remainder)
            remainder = abs(remainder - Float64(int_part))
            temp_coef = coefficient * 10 + int_part
            if temp_coef > Decimal128.MAX_AS_UINT128:
                break
            coefficient = temp_coef
            scale += 1
            if int_part == 0:
                num_trailing_zeros += 1
            else:
                num_trailing_zeros = 0
            # print("DEBUG: coefficient = ", coefficient)
            # print("DEBUG: scale = ", scale)
            # print("DEBUG: remainder = ", remainder)

        coefficient = coefficient // decimal128_utility.power_of_10_unsafe[
            DType.uint128
        ](Int(num_trailing_zeros))
        scale -= num_trailing_zeros

        var low = UInt32(coefficient & 0xFFFFFFFF)
        var mid = UInt32((coefficient >> 32) & 0xFFFFFFFF)
        var high = UInt32((coefficient >> 64) & 0xFFFFFFFF)

        # Return both the significant digits and the scale
        return Self(low, mid, high, UInt32(scale), is_negative)

    # ===------------------------------------------------------------------=== #
    # Output dunders, type-transfer dunders
    # ===------------------------------------------------------------------=== #

    def __float__(self) -> Float64:
        """Converts this Decimal128 to a floating-point value.
        Because Decimal128 is fixed-point, this may lose precision.

        Returns:
            The floating-point representation of this Decimal128.
        """

        var result = Float64(self.coefficient()) / (Float64(10) ** self.scale())
        result = -result if self.is_negative() else result

        return result

    def __int__(self) raises -> Int:
        """Returns the integral part of the Decimal128 as Int.
        See `to_int()` for more information.

        Returns:
            The `Int` representation.

        Raises:
            ConversionError: If the conversion fails.
        """
        return self.to_int()

    def write_repr_to[W: Writer](self, mut writer: W):
        """Writes the debug representation to a writer.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        # Stream the value directly through `write_to` to avoid materialising
        # an intermediate `String(self)` allocation.
        writer.write('Decimal128("')
        self.write_to(writer)
        writer.write('")')

    # ===------------------------------------------------------------------=== #
    # Type-transfer or output methods that are not dunders
    # ===------------------------------------------------------------------=== #

    def write_to[W: Writer](self, mut writer: W):
        """Writes the Decimal128 to a writer.
        This implement the `write` method of the `Writer` trait.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        var coef = self.coefficient()
        var scale = self.scale()
        var is_neg = self.is_negative()

        # Special-case zero (preserves trailing zero digits per scale).
        if coef == 0:
            if is_neg:
                writer.write("-")
            if scale == 0:
                writer.write("0")
            else:
                writer.write("0.")
                for _ in range(scale):
                    writer.write("0")
            return

        # Extract decimal digits into a right-aligned stack buffer. The
        # Decimal128 coefficient is at most 96 bits (~7.92e28), i.e. at
        # most 29 digits, so 32 bytes is plenty.
        #
        # Speed trick: split off 9-digit chunks at a time via a single
        # UInt128 division by 10^9 (a 30-bit divisor), then format the
        # 9-digit chunk with cheap UInt32 divisions. A 28-digit
        # coefficient costs only ~3 wide divisions instead of 28.
        comptime BUF_SIZE = 32
        comptime ZERO_ASCII = UInt8(48)
        comptime TEN9: UInt128 = 1_000_000_000
        var buf = Array[UInt8, BUF_SIZE](uninitialized=True)
        var pos = BUF_SIZE

        while coef >= TEN9:
            var q = coef // TEN9
            var r32 = UInt32(coef - q * TEN9)
            coef = q
            # Always emit 9 digits because there are more above.
            for _ in range(9):
                pos -= 1
                buf.unsafe_ptr()[unsafe_offset=pos] = (
                    UInt8(r32 % UInt32(10)) + ZERO_ASCII
                )
                r32 //= UInt32(10)

        var top = UInt32(coef)
        while top > 0:
            pos -= 1
            buf.unsafe_ptr()[unsafe_offset=pos] = (
                UInt8(top % UInt32(10)) + ZERO_ASCII
            )
            top //= UInt32(10)

        var n_digits = BUF_SIZE - pos

        if is_neg:
            writer.write("-")

        if scale == 0:
            writer.write(
                StringSlice(
                    unsafe_from_utf8=Span(
                        unsafe_ptr=buf.unsafe_ptr().unsafe_offset(pos),
                        length=n_digits,
                    )
                )
            )
        elif scale >= n_digits:
            # Pre-fill the (scale - n_digits) leading zeros directly into
            # the buffer, just before the existing digits, so we can
            # write the entire fractional component in a single
            # StringSlice instead of a per-byte loop. (scale ≤ 28 and
            # BUF_SIZE = 32, so the prefix always fits.)
            var zeros_count = scale - n_digits
            var frac_start = pos - zeros_count
            var p = buf.unsafe_ptr().unsafe_offset(frac_start)
            for i in range(zeros_count):
                p[unsafe_offset=i] = ZERO_ASCII
            writer.write("0.")
            writer.write(
                StringSlice(
                    unsafe_from_utf8=Span(
                        unsafe_ptr=buf.unsafe_ptr().unsafe_offset(frac_start),
                        length=scale,
                    )
                )
            )
        else:
            var int_len = n_digits - scale
            writer.write(
                StringSlice(
                    unsafe_from_utf8=Span(
                        unsafe_ptr=buf.unsafe_ptr().unsafe_offset(pos),
                        length=int_len,
                    )
                )
            )
            writer.write(".")
            writer.write(
                StringSlice(
                    unsafe_from_utf8=Span(
                        unsafe_ptr=buf.unsafe_ptr().unsafe_offset(
                            pos + int_len
                        ),
                        length=scale,
                    )
                )
            )

    def repr_words(self) -> String:
        """Returns a string representation of the Decimal128's internal words.
        `Decimal128.from_words(low, mid, high, flags)`.

        Returns:
            A string in the format `Decimal128(low, mid, high, flags)`.
        """
        return (
            "Decimal128("
            + hex(self.low)
            + ", "
            + hex(self.mid)
            + ", "
            + hex(self.high)
            + ", "
            + hex(self.flags)
            + ")"
        )

    def repr_components(self) -> String:
        """Returns a string representation of the Decimal128's five components.
        `Decimal128.from_components(low, mid, high, scale, sign)`.

        Returns:
            A string in the format `Decimal128(low=, mid=, high=, scale=, sign=)`.
        """
        var scale = UInt8((self.flags & Self.SCALE_MASK) >> Self.SCALE_SHIFT)
        var sign = Bool((self.flags & Self.SIGN_MASK) == Self.SIGN_MASK)
        return (
            "Decimal128(low="
            + hex(self.low)
            + ", mid="
            + hex(self.mid)
            + ", high="
            + hex(self.high)
            + ", scale="
            + String(scale)
            + ", sign="
            + String(sign)
            + ")"
        )

    def to_int(self) raises -> Int:
        """Returns the integral part of the Decimal128 as Int.
        If the Decimal128 is too large to fit in Int, an error is raised.

        Returns:
            The signed integral part of the Decimal128.

        Raises:
            ConversionError: If the conversion fails.
        """
        try:
            return Int(self.to_int64())
        except e:
            raise ConversionError(
                message="Cannot convert Decimal128 to Int.",
                function="Decimal128.to_int()",
                previous_error=e^,
            )

    def to_int64(self) raises -> Int64:
        """Returns the integral part of the Decimal128 as Int64.
        If the Decimal128 is too large to fit in Int64, an error is raised.

        Returns:
            The signed integral part of the Decimal128.

        Raises:
            OverflowError: If the value exceeds the Int64 range.
        """
        var result = self.to_int128()

        if result > Int128(Int64.MAX):
            raise OverflowError(
                message="Decimal128 is too large to fit in Int64.",
                function="Decimal128.to_int64()",
            )

        if result < Int128(Int64.MIN):
            raise OverflowError(
                message="Decimal128 is too small to fit in Int64.",
                function="Decimal128.to_int64()",
            )

        return Int64(result & 0xFFFF_FFFF_FFFF_FFFF)

    def to_int128(self) -> Int128:
        """Returns the signed integral part of the Decimal128.

        Returns:
            The signed integral part as `Int128`.
        """

        var res = Int128(self.to_uint128())

        return -res if self.is_negative() else res

    def to_uint128(self) -> UInt128:
        """Returns the absolute integral part of the Decimal128 as UInt128.

        Returns:
            The absolute integral part as `UInt128`.
        """
        var res: UInt128

        if self.is_zero():
            res = 0

        # If scale is 0, the number is already an integer
        elif self.scale() == 0:
            res = self.coefficient()

        # If scale is not 0, check whether integer part is 0
        elif self.number_of_significant_digits() <= self.scale():
            # Value is less than 1, so integer part is 0
            res = 0

        # Otherwise, get the integer part by dividing by 10^scale
        else:
            res = self.coefficient() // decimal128_utility.power_of_10_unsafe[
                DType.uint128
            ](self.scale())

        return res

    def to_string(
        self,
        scientific: Bool = False,
        engineering: Bool = False,
        delimiter: String = "",
    ) -> String:
        """Returns a string representation of the Decimal128.

        - Default (`scientific=False`, `engineering=False`): plain
          fixed-point notation that preserves trailing zeros after the
          decimal point to match the scale (e.g. `Decimal128("1.2300")`
          renders as `"1.2300"`). Streamed via `write_to` for speed.
        - `scientific=True`: scientific notation `M.NNNNe±XX` where the
          coefficient's trailing zeros are first stripped and the exponent
          uses the `E+N` / `E-N` style. A one-digit coefficient gets a
          `.0` mantissa suffix (e.g. `5E+0` is rendered as `"5.0E+0"`).
        - `engineering=True`: engineering notation where the exponent is
          always a multiple of 3 (e.g. `12345` -> `"12.345E+3"`,
          `0.00123` -> `"1.23E-3"`, `0.5` -> `"500E-3"`). Trailing zeros
          in the coefficient are stripped first.
        - When both `scientific` and `engineering` are True, **engineering
          wins** (matches `BigDecimal.to_string`).

        Args:
            scientific: If True, format in scientific notation with one
                digit before the decimal point.
            engineering: If True, format in engineering notation with the
                exponent rounded down to the nearest multiple of 3.
            delimiter: A string inserted every 3 digits in both the
                integer and fractional parts of the mantissa (e.g. `"_"`
                gives `"1_234.567_89"`). The optional `E±N` exponent
                suffix on scientific / engineering notation is preserved
                verbatim. An empty string (default) disables grouping.

        Returns:
            The string representation of this `Decimal128`.
        """
        # Default plain fixed-point path with no grouping: stream via
        # write_to (fast path; avoids the intermediate buffer rebuild).
        if not scientific and not engineering and not delimiter:
            var out = String()
            self.write_to(out)
            return out^

        # Default plain fixed-point path with grouping: build via write_to
        # then apply the digit-group separator pass.
        if not scientific and not engineering:
            var out = String()
            self.write_to(out)
            return _insert_digit_separators(out^, delimiter)

        var scale: Int = self.scale()
        var coef = self.coefficient()
        var result: String

        # Special case: zero. When `scale == 0` we emit `"0"` (or `"-0"`)
        # without an exponent suffix; otherwise we emit `0E-<scale>`.
        if coef == 0:
            if scale == 0:
                result = String("-0") if self.is_negative() else String("0")
            else:
                var sign = String("-") if self.is_negative() else String("")
                result = sign + String("0E-") + String(scale)
            if delimiter:
                return _insert_digit_separators(result^, delimiter)
            return result^

        # Strip trailing zeros from the coefficient. Both scientific and
        # engineering notations conventionally drop them so the mantissa
        # only carries significant digits.
        while coef % 10 == 0:
            coef = coef // 10
            scale -= 1

        var coef_str = String(coef)
        var ndigits_coef = coef_str.byte_length()
        # `leftdigits` is the number of digits to the left of the decimal
        # point in plain notation (matches the convention used by
        # `BigDecimal.to_string`). For a coefficient of `n` digits with
        # scale `s`, `leftdigits = n - s`.
        var leftdigits = ndigits_coef - scale
        # The "adjusted exponent" is the exponent that would appear if the
        # mantissa had exactly one digit before the decimal point. This is
        # the standard scientific-notation exponent.
        var adjusted_exp = leftdigits - 1
        var sign = String("-") if self.is_negative() else String("")

        if engineering:
            # Engineering notation: exponent is the largest multiple of 3
            # that is `<= adjusted_exp` (rounding toward -infinity so that
            # the mantissa stays in `[1, 1000)`).
            var eng_exp: Int
            if adjusted_exp >= 0:
                eng_exp = (adjusted_exp // 3) * 3
            else:
                eng_exp = -((-adjusted_exp + 2) // 3) * 3
            var lead_digits = adjusted_exp - eng_exp + 1  # always 1, 2, or 3

            # Right-pad the coefficient with zeros if there are fewer
            # significant digits than `lead_digits` (e.g. coef="5" with
            # lead_digits=3 -> coef="500", giving "500E-3").
            if ndigits_coef < lead_digits:
                coef_str = coef_str + "0" * (lead_digits - ndigits_coef)

            result = sign
            if coef_str.byte_length() <= lead_digits:
                result += coef_str
            else:
                result += coef_str[byte=:lead_digits]
                result += "."
                result += coef_str[byte=lead_digits:]

            # Append exponent. Omit the `E` suffix entirely when
            # `eng_exp == 0` (matches `BigDecimal.to_eng_string`).
            if eng_exp != 0:
                result += "E"
                if eng_exp > 0:
                    result += "+"
                result += String(eng_exp)
        else:
            # Scientific notation: 1 digit before the decimal point.
            # A one-digit coefficient gets a `.0` mantissa suffix to
            # preserve the historical Decimal128 scientific format (e.g.
            # `5.0E+0`).
            result = sign
            if ndigits_coef == 1:
                result = result + coef_str + String(".0")
            else:
                result = (
                    result + coef_str[byte=0] + String(".") + coef_str[byte=1:]
                )

            # Exponent: explicit sign in `E+N` style, plain `E-N` for negative.
            if adjusted_exp >= 0:
                result += "E+" + String(adjusted_exp)
            else:
                result += "E" + String(adjusted_exp)

        if delimiter:
            return _insert_digit_separators(result^, delimiter)
        return result^

    @always_inline
    def to_scientific_string(self) -> String:
        """Returns the number in scientific notation (trailing zeros stripped).

        Convenience alias for `to_string(scientific=True)`.

        Examples:

        ```mojo
        from decimo.prelude import *
        print(Dec128("123456.789").to_scientific_string())  # "1.23456789E+5"
        print(Dec128("0.00123").to_scientific_string())     # "1.23E-3"
        ```

        Returns:
            The number formatted in scientific notation.
        """
        return self.to_string(scientific=True)

    @always_inline
    def to_eng_string(self) -> String:
        """Returns the number in engineering notation (exponent is a multiple
        of 3, trailing zeros stripped).

        Convenience alias for `to_string(engineering=True)`.

        Examples:

        ```mojo
        from decimo.prelude import *
        print(Dec128("123456.789").to_eng_string())  # "123.456789E+3"
        print(Dec128("0.00123").to_eng_string())     # "1.23E-3"
        ```

        Returns:
            The number formatted in engineering notation.
        """
        return self.to_string(engineering=True)

    @always_inline
    def to_string_with_separators(self, separator: String = "_") -> String:
        """Returns the plain-notation string with digit-group separators
        inserted every 3 digits.

        Convenience alias for `to_string(delimiter=separator)`. Groups
        both the integer and fractional parts.

        Args:
            separator: The separator string (default: `"_"`).

        Examples:

        ```mojo
        from decimo.prelude import *
        print(Dec128("1234567.89").to_string_with_separators())       # "1_234_567.89"
        print(Dec128("1234567.89").to_string_with_separators(","))    # "1,234,567.89"
        print(Dec128("-9876543210.123456").to_string_with_separators())
        # "-9_876_543_210.123_456"
        ```

        Returns:
            The plain-notation string with digit-group separators.
        """
        return self.to_string(delimiter=separator)

    def as_tuple(self) -> Tuple[Bool, UInt128, Int]:
        """Returns a tuple representation of the number.
        Tuple(sign, signficand, exponent).

        Returns:
            A tuple representation of the number.
        """
        return Tuple[Bool, UInt128, Int](
            self.is_negative(), self.coefficient(), self.scale()
        )

    # ===------------------------------------------------------------------=== #
    # Basic unary operation dunders
    # neg
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __abs__(self) -> Self:
        """Returns the absolute value of this Decimal128.
        See `absolute()` for more information.

        Returns:
            The absolute value.
        """
        return decimal128_arithmetics.absolute(self)

    @always_inline
    def __neg__(self) -> Self:
        """Returns the negation of this Decimal128.
        See `negative()` for more information.

        Returns:
            The negated value.
        """
        return decimal128_arithmetics.negative(self)

    @always_inline
    def __bool__(self) -> Bool:
        """Returns True if the value is nonzero.

        This enables `if x:` syntax, consistent with Python's `decimal.Decimal`.

        Returns:
            True if the value is nonzero, False otherwise.
        """
        return not self.is_zero()

    @always_inline
    def __pos__(self) -> Self:
        """Returns the value unchanged (unary plus).

        This enables `+x` syntax, consistent with Python's `decimal.Decimal`.

        Returns:
            A copy of this value.
        """
        return self

    # ===------------------------------------------------------------------=== #
    # Basic binary arithmetic operation dunders
    # These methods are called to implement the binary arithmetic operations
    # (+, -, *, @, /, //, %, divmod(), pow(), **, <<, >>, &, ^, |)
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __add__(self, other: Self) raises -> Self:
        """Adds two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The sum.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_arithmetics.add(self, other)

    @always_inline
    def __sub__(self, other: Self) raises -> Self:
        """Subtracts two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The difference.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_arithmetics.subtract(self, other)

    @always_inline
    def __mul__(self, other: Self) raises -> Self:
        """Multiplies two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The product.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_arithmetics.multiply(self, other)

    @always_inline
    def __truediv__(self, other: Self) raises -> Self:
        """Divides two values using true division.

        Args:
            other: The right-hand side operand.

        Returns:
            The quotient.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
            ZeroDivisionError: If the divisor is zero.
        """
        return decimal128_arithmetics.divide(self, other)

    @always_inline
    def __floordiv__(self, other: Self) raises -> Self:
        """Performs truncate division with // operator.

        Args:
            other: The right-hand side operand.

        Returns:
            The truncated quotient.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
            ZeroDivisionError: If the divisor is zero.
        """
        return decimal128_arithmetics.truncate_divide(self, other)

    @always_inline
    def __mod__(self, other: Self) raises -> Self:
        """Performs truncate modulo.

        Args:
            other: The right-hand side operand.

        Returns:
            The remainder.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
            ZeroDivisionError: If the divisor is zero.
        """
        return decimal128_arithmetics.modulo(self, other)

    @always_inline
    def __divmod__(self, other: Self) raises -> Tuple[Self, Self]:
        """Returns `(self // other, self % other)` in a single call.

        Equivalent to `(self // other, self % other)` but amortises the
        divide pipeline: the truncated quotient is computed once and
        reused to derive the remainder as `self - quotient * other`,
        avoiding the second full `divide()` that the two-step path
        would perform. The identity
        `self == (self // other) * other + (self % other)` always
        holds.

        Args:
            other: The right-hand side operand.

        Returns:
            A `(quotient, remainder)` tuple.

        Raises:
            ZeroDivisionError: If `other` is zero.
            OverflowError: If the result overflows.
        """
        var q = decimal128_arithmetics.truncate_divide(self, other)
        return (q, self - q * other)

    @always_inline
    def __pow__(self, exponent: Self) raises -> Self:
        """Raises to a power.

        Args:
            exponent: The exponent to raise to.

        Returns:
            The value raised to the given power.

        Raises:
            ValueError: If the base is negative with a non-integer exponent.
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_exponential.power(self, exponent)

    @always_inline
    def __pow__(self, exponent: Int) raises -> Self:
        """Raises to a power.

        Args:
            exponent: The exponent to raise to.

        Returns:
            The value raised to the given power.

        Raises:
            ValueError: If the base is zero and the exponent is negative.
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_exponential.power(self, exponent)

    # ===------------------------------------------------------------------=== #
    # Basic binary arithmetic operation dunders with reflected operands
    # These methods are called to implement the binary arithmetic operations
    # with reflected operands
    # (+, -, *, @, /, //, %, divmod(), pow(), **, <<, >>, &, ^, |)
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __radd__(self, other: Self) raises -> Self:
        """Adds two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The sum.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_arithmetics.add(other, self)

    @always_inline
    def __rsub__(self, other: Self) raises -> Self:
        """Subtracts two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The difference.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_arithmetics.subtract(other, self)

    @always_inline
    def __rmul__(self, other: Self) raises -> Self:
        """Multiplies two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The product.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_arithmetics.multiply(other, self)

    @always_inline
    def __rtruediv__(self, other: Self) raises -> Self:
        """Divides two values using true division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The quotient.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
            ZeroDivisionError: If the divisor is zero.
        """
        return decimal128_arithmetics.divide(other, self)

    @always_inline
    def __rfloordiv__(self, other: Self) raises -> Self:
        """Performs truncate division with // operator (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The truncated quotient.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
            ZeroDivisionError: If the divisor is zero.
        """
        return decimal128_arithmetics.truncate_divide(other, self)

    @always_inline
    def __rmod__(self, other: Self) raises -> Self:
        """Performs truncate modulo (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The remainder.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
            ZeroDivisionError: If the divisor is zero.
        """
        return decimal128_arithmetics.modulo(other, self)

    # ===------------------------------------------------------------------=== #
    # Basic binary augmented arithmetic assignments dunders
    # These methods are called to implement the binary augmented arithmetic
    # assignments
    # (+=, -=, *=, @=, /=, //=, %=, **=, <<=, >>=, &=, ^=, |=)
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __iadd__(mut self, other: Self) raises:
        """Adds in place.

        Args:
            other: The right-hand side operand.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        self = decimal128_arithmetics.add(self, other)

    @always_inline
    def __isub__(mut self, other: Self) raises:
        """Subtracts in place.

        Args:
            other: The right-hand side operand.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        self = decimal128_arithmetics.subtract(self, other)

    @always_inline
    def __imul__(mut self, other: Self) raises:
        """Multiplies in place.

        Args:
            other: The right-hand side operand.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        self = decimal128_arithmetics.multiply(self, other)

    @always_inline
    def __itruediv__(mut self, other: Self) raises:
        """Divides in place using true division.

        Args:
            other: The right-hand side operand.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
            ZeroDivisionError: If the divisor is zero.
        """
        self = decimal128_arithmetics.divide(self, other)

    @always_inline
    def __ifloordiv__(mut self, other: Self) raises:
        """Performs truncate division with // operator.

        Args:
            other: The right-hand side operand.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
            ZeroDivisionError: If the divisor is zero.
        """
        self = decimal128_arithmetics.truncate_divide(self, other)

    @always_inline
    def __imod__(mut self, other: Self) raises:
        """Performs truncate modulo.

        Args:
            other: The right-hand side operand.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
            ZeroDivisionError: If the divisor is zero.
        """
        self = decimal128_arithmetics.modulo(self, other)

    # ===------------------------------------------------------------------=== #
    # Basic binary comparison operation dunders
    # __gt__, __ge__, __lt__, __le__, __eq__, __ne__
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __gt__(self, other: Decimal128) -> Bool:
        """Greater than comparison operator.
        See `greater()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `True` if this value is greater than `other`, `False` otherwise.
        """
        return decimal128_comparison.greater(self, other)

    @always_inline
    def __lt__(self, other: Decimal128) -> Bool:
        """Less than comparison operator.
        See `less()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `True` if this value is less than `other`, `False` otherwise.
        """
        return decimal128_comparison.less(self, other)

    @always_inline
    def __ge__(self, other: Decimal128) -> Bool:
        """Greater than or equal comparison operator.
        See `greater_equal()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `True` if this value is greater than or equal to `other`, `False` otherwise.
        """
        return decimal128_comparison.greater_equal(self, other)

    @always_inline
    def __le__(self, other: Decimal128) -> Bool:
        """Less than or equal comparison operator.
        See `less_equal()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `True` if this value is less than or equal to `other`, `False` otherwise.
        """
        return decimal128_comparison.less_equal(self, other)

    @always_inline
    def __eq__(self, other: Decimal128) -> Bool:
        """Equality comparison operator.
        See `equal()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `True` if the values are equal, `False` otherwise.
        """
        return decimal128_comparison.equal(self, other)

    @always_inline
    def __ne__(self, other: Decimal128) -> Bool:
        """Inequality comparison operator.
        See `not_equal()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `True` if the values are not equal, `False` otherwise.
        """
        return decimal128_comparison.not_equal(self, other)

    # ===------------------------------------------------------------------=== #
    # min / max / clamp
    # ===------------------------------------------------------------------=== #

    @always_inline
    def max(self, other: Decimal128) -> Self:
        """Returns the larger of `self` and `other`.
        See `max()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `self` if `self >= other`, otherwise `other`.
        """
        return decimal128_comparison.max(self, other)

    @always_inline
    def min(self, other: Decimal128) -> Self:
        """Returns the smaller of `self` and `other`.
        See `min()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `self` if `self <= other`, otherwise `other`.
        """
        return decimal128_comparison.min(self, other)

    @always_inline
    def clamp(self, lower: Decimal128, upper: Decimal128) raises -> Self:
        """Clamps `self` into the closed interval `[lower, upper]`.
        See `clamp()` for more information.

        Args:
            lower: The inclusive lower bound.
            upper: The inclusive upper bound.

        Returns:
            `lower` if `self < lower`, `upper` if `self > upper`, otherwise `self`.

        Raises:
            ValueError: If `lower > upper`.
        """
        return decimal128_comparison.clamp(self, lower, upper)

    # ===------------------------------------------------------------------=== #
    # Other dunders that implements traits
    # round, hash
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __round__(self, ndigits: Int) -> Self:
        """Rounds this Decimal128 to the specified number of decimal128 places.
        If `ndigits` is not given, rounds to 0 decimal128 places.
        If rounding causes overflow, returns the value itself.

        raises:
            Error: Calling `round()` failed.

        Args:
            ndigits: The number of decimal places to round to.

        Returns:
            The rounded `Decimal128` value.
        """
        try:
            return decimal128_rounding.round(
                self,
                ndigits=ndigits,
                rounding_mode=RoundingMode.half_even(),
            )
        except e:
            return self

    @always_inline
    def __round__(self) -> Self:
        """**OVERLOAD**.

        Returns:
            The `Decimal128` rounded to 0 decimal places.
        """
        try:
            return decimal128_rounding.round(
                self, ndigits=0, rounding_mode=RoundingMode.half_even()
            )
        except e:
            return self

    # [Mojo Miji]
    # What will happen if we run `hash()` on a Decimal128 value, e.g., `a`?
    # - a default hasher, i.e., `AHasher` will be created.
    # - `hasher.update(a)` will be called.
    # - This `__hash__` method will be invoked with the hasher as the argument.
    # - `hasher.update()` will be called three times to feed the normalized
    #   sign, coefficient, and scale into the hasher.
    # - `AHasher._update_with_simd()` will be called to update the hash state.
    def __hash__[H: Hasher](self, mut hasher: H):
        """Hashes this Decimal128 in a way that respects numeric equality
        (`a == b` implies `hash(a) == hash(b)`). The hash is computed on the
        normalized `(sign, coefficient, scale)` triple, so e.g.
        `Decimal128("1.0")` and `Decimal128("1.00")` hash identically — both
        normalize to coefficient=1, scale=0.

        Parameters:
            H: The `Hasher` implementation type.

        Args:
            hasher: The hasher to update.
        """
        var n = self.normalize()
        # Feed the three semantically meaningful fields. After normalize(),
        # zero is canonical (+0, scale 0, coef 0) so all zero-valued
        # Decimal128 inputs converge to the same hash. For non-zero values
        # equal under `==`, normalize() yields identical (coef, scale, sign)
        # triples by construction.
        hasher.update(UInt8(n.is_negative()))
        hasher.update(n.coefficient())
        hasher.update(UInt8(n.scale()))

    # ===------------------------------------------------------------------=== #
    # Mathematical methods that do not implement a trait (not a dunder)
    # exp, ln, round, sqrt, root, log10, power, quantize
    # ===------------------------------------------------------------------=== #

    @always_inline
    def round(
        self,
        ndigits: Int = 0,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Rounds this Decimal128 to the specified number of decimal128 places.
        Compared to `__round__`, this method:
        (1) Allows specifying the rounding mode.
        (2) Raises an error if the operation would result in overflow.
        See `round()` for more information.

        Args:
            ndigits: The number of decimal places to round to.
            rounding_mode: The rounding mode to apply.

        Returns:
            The rounded `Decimal128` value.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_rounding.round(
            self, ndigits=ndigits, rounding_mode=rounding_mode
        )

    @always_inline
    def quantize(
        self,
        exp: Decimal128,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Quantizes this Decimal128 to the specified exponent.
        See `quantize()` for more information.

        Args:
            exp: A `Decimal128` whose scale determines the target precision.
            rounding_mode: The rounding mode to apply.

        Returns:
            The quantized `Decimal128` value.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_rounding.quantize(self, exp, rounding_mode)

    @always_inline
    def fma(self, other: Self, third: Self) raises -> Self:
        """Returns `self * other + third` with a single final rounding step.

        Fused multiply-add (FMA):
        Equivalent to Python's `decimal.Decimal.fma(other, third)`. This is
        more accurate than `(self * other) + third` (which rounds twice)
        because the product is held at full UInt256 precision and the
        addend `third` is aligned at the same scale before a single
        rounding step. See `decimo.decimal128.arithmetics.fma` for the
        implementation.

        Examples:

        ```mojo
        from decimo.prelude import *
        # Single-rounding advantage: pi*pi requires rounding to fit
        # Decimal128's 29-digit grid; subtracting 9.8 then exposes the
        # rounding noise that a two-step (a*b)+c would carry.
        var pi = Dec128("3.141592653589793238462643383")
        # fma keeps the full UInt256 product and reclaims one extra
        # digit of precision over the naive (a*b)+c path:
        print(pi.fma(pi, Dec128("-9.8")))
        # 0.0696044010893586188344909981   (28 fractional digits)
        print((pi * pi) + Dec128("-9.8"))
        # 0.069604401089358618834490998    (27 fractional digits)
        ```

        Args:
            other: The multiplier.
            third: The addend.

        Returns:
            A new `Decimal128` containing `self * other + third`.

        Raises:
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_arithmetics.fma(self, other, third)

    @always_inline
    def exp(self) raises -> Self:
        """Calculates the exponential of this Decimal128.
        See `exp()` for more information.

        Returns:
            The value of e raised to this power.

        Raises:
            OverflowError: If the exponent is too large.
        """
        return decimal128_exponential.exp(self)

    @always_inline
    def ln(self) raises -> Self:
        """Calculates the natural logarithm of this Decimal128.
        See `ln()` for more information.

        Returns:
            The natural logarithm of this value.

        Raises:
            ValueError: If the value is non-positive.
        """
        return decimal128_exponential.ln(self)

    @always_inline
    def log10(self) raises -> Self:
        """Computes the base-10 logarithm of this Decimal128.

        Returns:
            The base-10 logarithm of this value.

        Raises:
            ValueError: If the value is non-positive.
        """
        return decimal128_exponential.log10(self)

    @always_inline
    def log(self, base: Decimal128) raises -> Self:
        """Computes the logarithm of this Decimal128 with an arbitrary base.

        Args:
            base: The logarithm base.

        Returns:
            The logarithm of this value in the given base.

        Raises:
            ValueError: If the value or base is non-positive, or the base equals 1.
        """
        return decimal128_exponential.log(self, base)

    @always_inline
    def power(self, exponent: Int) raises -> Self:
        """Raises this Decimal128 to the power of an integer.

        Args:
            exponent: The integer exponent to raise to.

        Returns:
            The value raised to the given power.

        Raises:
            ValueError: If the base is zero and the exponent is negative.
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_exponential.power(self, Self(exponent))

    @always_inline
    def power(self, exponent: Decimal128) raises -> Self:
        """Raises this Decimal128 to the power of another Decimal128.

        Args:
            exponent: The `Decimal128` exponent to raise to.

        Returns:
            The value raised to the given power.

        Raises:
            ValueError: If the base is negative with a non-integer exponent.
            OverflowError: If the result overflows Decimal128 capacity.
        """
        return decimal128_exponential.power(self, exponent)

    @always_inline
    def root(self, n: Int) raises -> Self:
        """Calculates the n-th root of this Decimal128.

        See `root()` for more information.

        Args:
            n: The degree of the root to compute.

        Returns:
            The n-th root of this value.

        Raises:
            ValueError: If `n` is non-positive, or `n` is even and the value is negative.
        """
        return decimal128_exponential.root(self, n)

    @always_inline
    def sqrt(self) raises -> Self:
        """Calculates the square root of this Decimal128.

        See `sqrt()` for more information.

        Returns:
            The square root of this value.

        Raises:
            ValueError: If the value is negative.
        """
        return decimal128_exponential.sqrt(self)

    @always_inline
    def cbrt(self) raises -> Self:
        """Calculates the cube root of this Decimal128.

        See `cbrt()` for more information.

        Returns:
            The cube root of this value.

        Raises:
            Any error raised by `cbrt()`.
        """
        return decimal128_exponential.cbrt(self)

    # ===------------------------------------------------------------------=== #
    # Integer-part / fractional-part / sign helpers
    # trunc, floor, ceil, fract, signum, unpack
    # ===------------------------------------------------------------------=== #

    @always_inline
    def trunc(self) raises -> Self:
        """Returns the integer part of this Decimal128, discarding any
        fractional digits (rounding toward zero). The result has scale 0.

        Returns:
            A new `Decimal128` with the fractional part removed.

        Raises:
            Error: Should not occur in practice — truncation toward zero can
                only shrink the magnitude. Propagated for signature parity
                with `round()`.

        Example:

        ```mojo
        from decimo import Decimal128
        print(Decimal128("3.7").trunc())   # 3
        print(Decimal128("-3.7").trunc())  # -3
        print(Decimal128("3.0").trunc())   # 3
        ```
        End of example.
        """
        return decimal128_rounding.round(
            self, ndigits=0, rounding_mode=RoundingMode.ROUND_DOWN
        )

    @always_inline
    def floor(self) raises -> Self:
        """Returns the largest integer less than or equal to this Decimal128
        (rounding toward negative infinity). The result has scale 0.

        Returns:
            A new `Decimal128` rounded toward negative infinity.

        Raises:
            Error: If rounding causes overflow (only possible at the negative
                extreme of the representable range).

        Example:

        ```mojo
        from decimo import Decimal128
        print(Decimal128("3.7").floor())   # 3
        print(Decimal128("-3.2").floor())  # -4
        print(Decimal128("3.0").floor())   # 3
        ```
        End of example.
        """
        return decimal128_rounding.round(
            self, ndigits=0, rounding_mode=RoundingMode.ROUND_FLOOR
        )

    @always_inline
    def ceil(self) raises -> Self:
        """Returns the smallest integer greater than or equal to this
        Decimal128 (rounding toward positive infinity). The result has
        scale 0.

        Returns:
            A new `Decimal128` rounded toward positive infinity.

        Raises:
            Error: If rounding causes overflow (only possible at the positive
                extreme of the representable range).

        Example:

        ```mojo
        from decimo import Decimal128
        print(Decimal128("3.2").ceil())   # 4
        print(Decimal128("-3.7").ceil())  # -3
        print(Decimal128("3.0").ceil())   # 3
        ```
        End of example.
        """
        return decimal128_rounding.round(
            self, ndigits=0, rounding_mode=RoundingMode.ROUND_CEILING
        )

    @always_inline
    def fract(self) raises -> Self:
        """Returns the fractional part of this Decimal128, defined as
        `self - self.trunc()`. Nonzero results have the same sign as
        `self` and preserve the original scale. Exact-zero results are
        canonicalized to positive zero by `subtract`, so e.g.
        `Decimal128("-3.000").fract()` returns `0.000` (positive), not
        `-0.000`.

        Returns:
            A new `Decimal128` containing the fractional part.

        Raises:
            Error: Propagated from the underlying subtraction. Should not
                occur in practice since the magnitude is bounded by `self`.

        Example:

        ```mojo
        from decimo import Decimal128
        print(Decimal128("3.75").fract())   # 0.75
        print(Decimal128("-3.75").fract())  # -0.75
        print(Decimal128("3").fract())      # 0
        ```
        End of example.
        """
        return self - self.trunc()

    @always_inline
    def signum(self) -> Self:
        """Returns the sign of this Decimal128 as a Decimal128:
        `1` if positive, `-1` if negative, `0` if zero.

        Returns:
            A new `Decimal128` with value -1, 0, or 1.

        Example:

        ```mojo
        from decimo import Decimal128
        print(Decimal128("3.7").signum())    # 1
        print(Decimal128("-3.7").signum())   # -1
        print(Decimal128("0").signum())      # 0
        print(Decimal128("0.000").signum())  # 0
        ```
        End of example.
        """
        if self.is_zero():
            return Decimal128.ZERO()
        if self.is_negative():
            return Decimal128(-1)
        return Decimal128.ONE()

    @always_inline
    def unpack(self) -> Tuple[UInt32, UInt32, UInt32, UInt32, Bool]:
        """Returns the raw internal components of this Decimal128 as a tuple
        `(low, mid, high, scale, sign)`.

        The coefficient (96-bit little-endian, in `low`/`mid`/`high`),
        the scale (number of decimal places, 0..=28),
        and the sign (`True` for negative) can be inspected without going
        through `coefficient()` / `scale()` / `is_negative()` individually.

        Returns:
            A tuple `(low, mid, high, scale, sign)`:

            - `low`: The low 32 bits of the coefficient.
            - `mid`: The middle 32 bits of the coefficient.
            - `high`: The high 32 bits of the coefficient.
            - `scale`: The scale (0..=28).
            - `sign`: `True` if negative, `False` otherwise.

        Example:

        ```mojo
        from decimo import Decimal128
        var parts = Decimal128("-123.45").unpack()
        # parts[0] == 12345, parts[1] == 0, parts[2] == 0,
        # parts[3] == 2, parts[4] == True
        ```
        End of example.
        """
        return Tuple[UInt32, UInt32, UInt32, UInt32, Bool](
            self.low,
            self.mid,
            self.high,
            UInt32(self.scale()),
            self.is_negative(),
        )

    # ===------------------------------------------------------------------=== #
    # Canonicalization / introspection helpers
    # normalize, same_quantum, adjusted, compare_total,
    # is_signed, canonical, is_canonical
    # ===------------------------------------------------------------------=== #

    def normalize(self) -> Self:
        """Returns the canonical (trailing-zero-stripped) form of this
        Decimal128. Mirrors Python `Decimal.normalize()`: the result has the
        same numeric value as `self` but the smallest scale that still
        represents it exactly. Zero is canonicalized to a positive zero with
        scale 0 regardless of the input's sign or scale (matches Python's
        `Decimal("-0.000").normalize() == Decimal("0")`).

        Returns:
            A new `Decimal128` with all trailing zeros stripped from the
            coefficient (and the scale lowered by the same amount).

        Notes:

        Two decimals that compare equal (`==`) but differ only in scale
        (e.g. `Decimal128("1.0")` vs `Decimal128("1.00")`) normalize to
        the same `(coefficient, scale, sign)` triple. This is the
        invariant `__hash__` relies on.

        Performance: trailing-zero stripping uses a 9-digit chunk pre-pass
        (one `UInt128 // 10^9` per fully-zero chunk) followed by a 1-digit
        tail loop. Each `% / //` pair is CSE-folded by LLVM to one
        `__udivmodti4` call (Lesson #2), so the loop touches each digit
        once.

        Example:

        ```mojo
        from decimo import Decimal128
        print(Decimal128("1.000").normalize())      # 1
        print(Decimal128("123.4500").normalize())   # 123.45
        print(Decimal128("-0.00").normalize())      # 0  (sign cleared)
        print(Decimal128("100").normalize())        # 100 (no trailing
                                                    # fractional zeros to
                                                    # strip; scale is
                                                    # already 0)
        ```
        End of example.
        """

        # Zero collapses to canonical (+0, scale 0). This matches Python
        # `Decimal` and IBM GDA: signed-zero / scaled-zero distinctions are
        # eliminated by `normalize`. Hashing relies on this so that every
        # zero-valued Decimal128 hashes the same.
        if self.is_zero():
            return Decimal128.ZERO()

        var scale = self.scale()

        # Already at scale 0: no trailing fractional digits to strip and the
        # coefficient itself may legitimately end in zeros (e.g. "100"). No
        # further work to do; return as-is. This is the hot path for integer
        # values.
        if scale == 0:
            return self

        var coef = self.coefficient()
        var sign = self.is_negative()

        # 9-digit chunk pre-pass: when scale >= 9, peel a whole `10^9`
        # block off the coefficient if and only if the low 9 digits are
        # zero. `power_of_10_unsafe[uint128](9)` is well within the
        # `0..29` contract. Each iteration consumes one `__udivmodti4`
        # (LLVM CSE-folds `// + %`).
        comptime CHUNK = 9
        var pow9 = decimal128_utility.power_of_10_unsafe[DType.uint128](CHUNK)
        while scale >= CHUNK and coef % pow9 == 0:
            coef = coef // pow9
            scale -= CHUNK

        # 1-digit tail. After the chunk pre-pass the residual scale is in
        # `0..(CHUNK + 27)` worst case (27 since MAX_SCALE = 28 and we only
        # strip when the chunk is exact); in practice this loop runs at
        # most 8 iterations.
        while scale > 0 and coef % 10 == 0:
            coef = coef // 10
            scale -= 1

        # `from_uint128` revalidates 96-bit fit + scale range. Both must
        # already hold for `self` (we only shrink coef + scale), so the
        # raise paths are dead; we still call the public constructor to
        # avoid duplicating the bit-pack / mask code.
        try:
            return Decimal128.from_uint128(coef, scale=UInt32(scale), sign=sign)
        except:
            # Unreachable: `coef <= self.coefficient()` (only divided by
            # positive powers of 10) and `scale <= self.scale() <= 28`.
            # `from_uint128` cannot raise on these inputs.
            return self

    @always_inline
    def same_quantum(self, other: Decimal128) -> Bool:
        """Returns True iff `self` and `other` have the same scale, i.e.
        the same number of fractional digits. Mirrors Python
        `Decimal.same_quantum()` and IBM GDA `same-quantum`.

        Args:
            other: The Decimal128 to compare scales against.

        Returns:
            `True` if `self.scale() == other.scale()`, `False` otherwise.

        Example:

        ```mojo
        from decimo import Decimal128
        print(Decimal128("1.23").same_quantum(Decimal128("4.56")))   # True
        print(Decimal128("1.230").same_quantum(Decimal128("1.23")))  # False
        ```
        End of example.
        """
        return (self.flags & Self.SCALE_MASK) == (other.flags & Self.SCALE_MASK)

    @always_inline
    def adjusted(self) -> Int:
        """Returns the adjusted exponent of this Decimal128.

        The adjusted exponent is the exponent of the most significant digit.
        Defined as `number_of_significant_digits() - 1 - scale()`.
        Useful for order-of-magnitude probes (e.g. `floor(log10(|self|))` on
        positive values) without going through `log10`.

        Mirrors Python `Decimal.adjusted()` and IBM GDA `adjusted-exponent`.
        For zero, returns 0 (matching Python's behaviour for `Decimal(0)`;
        IBM GDA leaves this implementation-defined).

        Returns:
            The adjusted exponent as an `Int`.

        Example:

        ```mojo
        from decimo import Decimal128
        print(Decimal128("123.45").adjusted())    # 2  (1.2345e2)
        print(Decimal128("0.00123").adjusted())   # -3 (1.23e-3)
        print(Decimal128("100").adjusted())       # 2  (1.00e2)
        print(Decimal128("0").adjusted())         # 0
        ```
        End of example.
        """
        if self.is_zero():
            return 0
        return self.number_of_significant_digits() - 1 - self.scale()

    @always_inline
    def compare_total(self, other: Decimal128) -> Int8:
        """Returns the IBM GDA total ordering of `self` vs `other`.

        Notes:

        Unlike `compare()` (which treats `1.0 == 1.00` and collapses every zero
        to a single equivalence class), `compare_total` produces a strict total
        order on the *representation*: numerically equal values that differ
        in scale or signed-zero status receive a deterministic order.

        Ordering rules (IBM GDA §5.5.13, "compare-total"):

        1. Negatives precede positives (including signed zero: `-0 < +0`).
        2. Among same-sign non-zero values: usual numeric order.
        3. Among numerically equal values (incl. same-signed zeros), the
           *lower* scale comes first for positives; reversed for negatives,
           so the global sequence stays monotonic across the zero boundary:
           `... -0.00 < -0.0 < -0 < +0 < +0.0 < +0.00 ...`.

        Args:
            other: The Decimal128 to compare against.

        Returns:
            `-1` if `self` precedes `other`, `0` if identical
            representations, `+1` otherwise.

        Example:

        ```mojo
        from decimo import Decimal128
        print(Decimal128("1.0").compare_total(Decimal128("1.00")))    # -1
        print(Decimal128("1").compare_total(Decimal128("1.0")))       # -1
        print(Decimal128("-1.0").compare_total(Decimal128("-1")))     # -1
        print(Decimal128("-0.00").compare_total(Decimal128("0.00")))  # -1
        ```
        End of example.
        """
        return decimal128_comparison.compare_total(self, other)

    @always_inline
    def is_signed(self) -> Bool:
        """Returns True iff the sign bit is set. Alias of `is_negative()`,
        provided for parity with Python `Decimal.is_signed()`. Note that a
        scaled negative zero (e.g. `Decimal128("-0.00")`) is *signed* even
        though it compares equal to positive zero.

        Returns:
            `True` if the sign bit is set, `False` otherwise.
        """
        return self.is_negative()

    @always_inline
    def canonical(self) -> Self:
        """Returns `self` unchanged. Provided for parity with Python
        `Decimal.canonical()` / IBM GDA `canonical`. Decimal128 has no
        non-canonical encodings (no NaN payloads, no Inf, no subnormal
        representations), so every value is already its own canonical form.

        Returns:
            `self`.
        """
        return self

    @always_inline
    def is_canonical(self) -> Bool:
        """Returns `True` unconditionally. Provided for parity with Python
        `Decimal.is_canonical()` / IBM GDA `is-canonical`. Decimal128 has no
        non-canonical encodings.

        Returns:
            `True`.
        """
        return True

    @always_inline
    def coefficient(self) -> UInt128:
        """Returns the unscaled integer coefficient as an UInt128 value.
        This is the absolute value of the decimal128 digits without considering
        the scale.
        The value of the coefficient is: `high * 2**64 + mid * 2**32 + low`.

        Returns:
            Int128: The coefficient as a unsigned 128-bit signed integer.
        """

        # Fast implementation using bitcast
        # Use bitcast to directly convert the three 32-bit parts to a UInt128
        # UInt128 must little-endian on memory
        return decimal128_utility.bitcast[DType.uint128](self)

        # Alternative implementation using arithmetic
        # Combine the three 32-bit parts into a single Int128
        # return (
        #     UInt128(self.high) << 64
        #     | UInt128(self.mid) << 32
        #     | UInt128(self.low)
        # )

    def extend_precision(self, var precision_diff: Int) raises -> Self:
        """Returns a number with additional decimal128 places (trailing zeros).
        This multiplies the coefficient by 10^precision_diff and increases
        the scale accordingly, preserving the numeric value.

        Args:
            precision_diff: The number of decimal128 places to add.

        Returns:
            A new Decimal128 with increased precision.

        Raises:
            ValueError: If precision_diff is negative.

        Examples:
        ```mojo
        from decimo import Decimal128
        var d1 = Decimal128("5")            # 5
        var d2 = d1.extend_precision(2)  # Result: 5.00 (same value, different representation)
        print(d1)                        # 5
        print(d2)                        # 5.00
        print(d2.scale())                # 2

        var d3 = Decimal128("123.456")      # 123.456
        var d4 = d3.extend_precision(3)  # Result: 123.456000
        print(d3)                        # 123.456
        print(d4)                        # 123.456000
        print(d4.scale())                # 6
        ```
        End of examples.
        """
        if precision_diff < 0:
            raise ValueError(
                message="precision_diff must be greater than or equal to 0.",
                function="Decimal128.extend_precision()",
            )

        if precision_diff == 0:
            return self

        var result = self

        # Update the scale in the flags
        var new_scale = self.scale() + precision_diff

        # TODO: Check if multiplication by 10^level would cause overflow
        # If yes, then raise an error
        if new_scale > Decimal128.MAX_SCALE + 1:
            # Cannot scale beyond max precision, limit the scaling
            precision_diff = Decimal128.MAX_SCALE + 1 - self.scale()
            new_scale = Decimal128.MAX_SCALE + 1

        # With UInt128, we can represent the coefficient as a single value
        var coefficient = (
            UInt128(self.high) << 64
            | UInt128(self.mid) << 32
            | UInt128(self.low)
        )

        # TODO: Check if multiplication by 10^level would cause overflow
        # If yes, then raise an error
        var max_coefficient = ~UInt128(
            0
        ) / decimal128_utility.power_of_10_unsafe[DType.uint128](
            Int(precision_diff)
        )
        if coefficient > max_coefficient:
            # Handle overflow case - limit to maximum value or raise error
            coefficient = ~UInt128(0)
        else:
            # No overflow - safe to multiply
            coefficient *= UInt128(10**precision_diff)

        # Extract the 32-bit components from the UInt128
        result.low = UInt32(coefficient & 0xFFFFFFFF)
        result.mid = UInt32((coefficient >> 32) & 0xFFFFFFFF)
        result.high = UInt32((coefficient >> 64) & 0xFFFFFFFF)

        # Set the new scale
        result.flags = (self.flags & ~Decimal128.SCALE_MASK) | (
            (UInt32(new_scale) << UInt32(Decimal128.SCALE_SHIFT))
            & UInt32(Decimal128.SCALE_MASK)
        )

        return result

    def internal_representation(self) -> String:
        """Returns the internal representation details as a String.

        Returns:
            A formatted string showing all internal fields.
        """
        # All labels
        var labels = List[String]()
        labels.append("Decimal128:")
        labels.append("coefficient:")
        labels.append("scale:")
        labels.append("is negative:")
        labels.append("is zero:")
        labels.append("low:")
        labels.append("mid:")
        labels.append("high:")
        labels.append("low byte:")
        labels.append("mid byte:")
        labels.append("high byte:")
        labels.append("flags byte:")

        var max_label_len = 0
        for i in range(len(labels)):
            if labels[i].byte_length() > max_label_len:
                max_label_len = labels[i].byte_length()

        var col = max_label_len + 4  # 4 spaces after longest label

        def pad(label: String) {imm col} -> String:
            return label + String(" ") * (col - label.byte_length())

        var sep_line = String("-") * (col + 30)

        var result = String("\nInternal Representation Details of Decimal128\n")
        result += sep_line + "\n"
        result += pad("Decimal128:") + String(self) + "\n"
        result += pad("coefficient:") + String(self.coefficient()) + "\n"
        result += pad("scale:") + String(self.scale()) + "\n"
        result += pad("is negative:") + String(self.is_negative()) + "\n"
        result += pad("is zero:") + String(self.is_zero()) + "\n"
        result += pad("low:") + String(self.low) + "\n"
        result += pad("mid:") + String(self.mid) + "\n"
        result += pad("high:") + String(self.high) + "\n"
        result += pad("low byte:") + hex(self.low) + "\n"
        result += pad("mid byte:") + hex(self.mid) + "\n"
        result += pad("high byte:") + hex(self.high) + "\n"
        result += pad("flags byte:") + hex(self.flags) + "\n"
        result += sep_line
        return result^

    @always_inline
    def is_integer(self) -> Bool:
        """Determines whether this Decimal128 value represents an integer.
        A Decimal128 represents an integer when it has no fractional part
        (i.e., all digits after the decimal128 point are zero).

        Returns:
            True if this Decimal128 represents an integer value, False otherwise.
        """

        # If value is zero, it's an integer regardless of scale
        if self.is_zero():
            return True

        var scale = self.scale()

        # If scale is 0, it's already an integer
        if scale == 0:
            return True

        # Cheap pre-check (fast reject):
        # 10^scale == 2^scale * 5^scale, so a necessary condition for the
        # coefficient to be divisible by 10^scale is that its low `scale`
        # bits are all zero (i.e. divisible by 2^scale). The maximum scale
        # for Decimal128 is 28 (< 32), so we only need to inspect `self.low`
        # (the low 32 bits of the 96-bit coefficient) -- no UInt128 modulus
        # is required for the negative answer.
        #
        # `1 << scale` is a UInt32 literal; the compiler folds it to a
        # constant when `scale` is known, otherwise it remains a single
        # variable shift + AND. This dispatches the common "fractional
        # coefficient" case in O(1) integer ops with no division.
        if (self.low & ((UInt32(1) << UInt32(scale)) - 1)) != 0:
            return False

        # Slow path: low bits are clear, so the coefficient is divisible by
        # 2^scale. We still need to check divisibility by 5^scale via the
        # full UInt128 modulus.
        # Safe to use `_unsafe` here: the raw `Decimal128(low, mid, high,
        # flags)` constructor `debug_assert`s that the scale bits stay in
        # `0..MAX_SCALE`, and every other constructor path validates scale
        # explicitly, so `scale` is guaranteed to be within the unsafe
        # blob's `0..29` range.
        return (
            self.coefficient()
            % decimal128_utility.power_of_10_unsafe[DType.uint128](scale)
        ) == 0

    @always_inline
    def is_negative(self) -> Bool:
        """Returns True if this Decimal128 is negative.

        Returns:
            `True` if negative, `False` otherwise.
        """
        return (self.flags & Self.SIGN_MASK) != 0

    @always_inline
    def is_positive(self) -> Bool:
        """Returns True if this Decimal128 represents a strictly positive
        value (i.e. nonzero and not negative).

        Returns:
            `True` if strictly positive, `False` otherwise.
        """
        return not self.is_negative() and not self.is_zero()

    def is_odd(self) -> Bool:
        """Returns True if the integer part of this Decimal128 is odd.

        The fractional part (if any) is ignored. The sign is also ignored;
        e.g. `-13.5` is odd because its integer part `-13` is odd.

        Returns:
            `True` if the integer part's units digit is odd, `False`
            otherwise.
        """
        var coef = self.coefficient()
        var scale = self.scale()
        if scale > 0:
            coef = coef // decimal128_utility.power_of_10_unsafe[DType.uint128](
                scale
            )
        return Bool(coef & 1)

    @always_inline
    def is_one(self) -> Bool:
        """Returns True if this Decimal128 represents the value 1.
        If 10^scale == coefficient, then it's one.
        `1` and `1.00` are considered ones.

        Returns:
            `True` if this value equals 1, `False` otherwise.
        """
        if self.is_negative():
            return False

        var scale = self.scale()
        var coef = self.coefficient()

        if scale == 0 and coef == 1:
            return True

        if coef == decimal128_utility.power_of_10_unsafe[DType.uint128](scale):
            return True

        return False

    @always_inline
    def is_zero(self) -> Bool:
        """Returns True if this Decimal128 represents zero.
        A decimal128 is zero when all coefficient parts (low, mid, high) are zero,
        regardless of its sign or scale.

        Returns:
            `True` if this value is zero, `False` otherwise.
        """
        return self.low == 0 and self.mid == 0 and self.high == 0

    @always_inline
    def scale(self) -> Int:
        """Returns the scale (number of decimal128 places) of this Decimal128.

        Returns:
            The scale as an `Int`.
        """
        return Int((self.flags & Self.SCALE_MASK) >> Self.SCALE_SHIFT)

    @always_inline
    def number_of_significant_digits(self) -> Int:
        """Returns the number of significant digits in the Decimal128.
        The number of significant digits is the total number of digits in the
        coefficient, excluding leading zeros but including trailing zeros.

        Returns:
            The number of significant digits in the Decimal128.

        Example:

        ```mojo
        from decimo import Decimal128
        print(Decimal128("123.4500").number_of_significant_digits())
        # 7
        print(Decimal128("0.0001234500").number_of_significant_digits())
        # 7
        ```
        End of example.
        """

        var coef = self.coefficient()

        # Special case for zero
        if coef == 0:
            return 0  # Zero has zero significant digit
        else:
            return decimal128_utility.number_of_digits(coef)

    def number_of_trailing_zeros(self) -> Int:
        """Returns the number of trailing zero digits in the coefficient.

        Trailing zeros conveyed by the scale (e.g. `Decimal128("1.2300")`
        has coefficient `12300` and 2 trailing zeros) are counted; pure
        zero values return 0.

        Examples:

        ```mojo
        from decimo.prelude import *
        print(Dec128("1.2300").number_of_trailing_zeros())    # 2
        print(Dec128("12000").number_of_trailing_zeros())     # 3
        print(Dec128("0").number_of_trailing_zeros())         # 0
        ```

        Returns:
            The count of trailing zero digits in the coefficient.
        """
        var coef = self.coefficient()
        if coef == 0:
            return 0
        var n = 0
        while coef % 10 == 0:
            coef = coef // 10
            n += 1
        return n


# ===----------------------------------------------------------------------=== #
# Module-level helpers
# ===----------------------------------------------------------------------=== #


def _insert_digit_separators(s: String, delimiter: String) -> String:
    """Insert `delimiter` every 3 digits in both the integer and
    fractional parts of a numeric string.

    The function is aware of an optional leading `-` sign and a trailing
    exponent suffix (`E+3`, `E-12`, etc.). Only the mantissa digits are
    grouped; the sign and exponent are preserved verbatim. Mirrors the
    `_insert_digit_separators` helper in `bigdecimal.mojo`.
    """
    if not delimiter:
        return s

    var sb = StringSlice(s).as_bytes()
    var n = len(sb)
    var ptr = sb.unsafe_ptr()

    # Locate optional leading minus (ASCII 45).
    var start = 0
    if n > 0 and ptr[unsafe_offset=0] == 45:
        start = 1

    # Locate optional exponent suffix 'E' (ASCII 69); it bounds the
    # mantissa so the exponent itself is left untouched.
    var e_pos = n
    for i in range(start, n):
        if ptr[unsafe_offset=i] == 69:
            e_pos = i
            break

    # Locate optional decimal point '.' (ASCII 46) within the mantissa.
    var dot_pos = -1
    for i in range(start, e_pos):
        if ptr[unsafe_offset=i] == 46:
            dot_pos = i
            break

    var int_end = dot_pos if dot_pos >= 0 else e_pos
    var int_part = String(s[byte=start:int_end])
    var frac_part = String("")
    if dot_pos >= 0:
        frac_part = String(s[byte = dot_pos + 1 : e_pos])
    var exp_part = String(
        s[byte=e_pos:n]
    )  # includes leading 'E', empty if none

    # --- Group integer part right-to-left every 3 digits ---
    var int_len = int_part.byte_length()
    var int_grouped: String
    if int_len > 3:
        var blocks = List[String](capacity=int_len // 3 + 1)
        var end_i = int_len
        var start_i = end_i - 3
        while start_i > 0:
            blocks.append(String(int_part[byte=start_i:end_i]))
            end_i = start_i
            start_i -= 3
        blocks.append(String(int_part[byte=0:end_i]))
        int_grouped = String("")
        var i = len(blocks) - 1
        while i >= 0:
            int_grouped += blocks[i]
            if i > 0:
                int_grouped += delimiter
            i -= 1
    else:
        int_grouped = int_part^

    # --- Group fractional part left-to-right every 3 digits ---
    var frac_grouped: String
    var frac_len = frac_part.byte_length()
    if frac_len > 3:
        frac_grouped = String("")
        var i = 0
        while i < frac_len:
            var end_j = i + 3
            if end_j > frac_len:
                end_j = frac_len
            frac_grouped += frac_part[byte=i:end_j]
            if end_j < frac_len:
                frac_grouped += delimiter
            i = end_j
    else:
        frac_grouped = frac_part^

    var prefix = String("-") if start == 1 else String("")
    if dot_pos >= 0:
        return prefix + int_grouped + "." + frac_grouped + exp_part
    return prefix + int_grouped + exp_part
