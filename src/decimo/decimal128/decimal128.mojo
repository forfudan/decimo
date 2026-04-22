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

"""Implements basic object methods for the Decimal128 type.

This module contains the basic object methods for the Decimal128 type.
These methods include constructors, life time methods, output dunders,
type-transfer dunders, basic arithmetic operation dunders, comparison
operation dunders, and other dunders that implement traits, as well as
mathematical methods that do not implement a trait.
"""

from std.memory import UnsafePointer

import decimo.decimal128.arithmetics
import decimo.decimal128.comparison
import decimo.decimal128.constants
import decimo.decimal128.exponential
import decimo.decimal128.rounding
from decimo.rounding_mode import RoundingMode
from decimo.errors import (
    ValueError,
    OverflowError,
    ConversionError,
)
import decimo.decimal128.utility

comptime Dec128 = Decimal128
"""A 128-bit fixed-point decimal number."""


struct Decimal128(
    Absable,
    Comparable,
    Floatable,
    IntableRaising,
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

    # Special values
    @always_inline
    @staticmethod
    def ZERO() -> Decimal128:
        """Returns a Decimal128 representing 0.

        Returns:
            A `Decimal128` representing zero.
        """
        return Self(0, 0, 0, 0)

    @always_inline
    @staticmethod
    def ONE() -> Decimal128:
        """Returns a Decimal128 representing 1.

        Returns:
            A `Decimal128` representing one.
        """
        return Self(1, 0, 0, 0)

    @always_inline
    @staticmethod
    def MAX() -> Decimal128:
        """
        Returns the maximum possible Decimal128 value.
        This is equivalent to 79228162514264337593543950335.

        Returns:
            The maximum `Decimal128` value.
        """
        return Self(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0)

    @always_inline
    @staticmethod
    def MIN() -> Decimal128:
        """Returns the minimum possible Decimal128 value (negative of MAX).
        This is equivalent to -79228162514264337593543950335.

        Returns:
            The minimum `Decimal128` value.
        """
        return Self(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, Decimal128.SIGN_MASK)

    @always_inline
    @staticmethod
    def PI() -> Decimal128:
        """Returns the value of pi (π) as a Decimal128.

        Returns:
            The value of pi (π).
        """
        return decimo.decimal128.constants.PI()

    @always_inline
    @staticmethod
    def E() -> Decimal128:
        """Returns the value of Euler's number (e) as a Decimal128.

        Returns:
            The value of Euler's number (e).
        """
        return decimo.decimal128.constants.E()

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
        See `from_float` for more information.

        Args:
            value: The floating-point value to convert.

        Raises:
            ConversionError: If the float cannot be converted.
        """

        try:
            self = Decimal128.from_float(value)
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

    @staticmethod
    def from_uint128(
        value: UInt128, scale: UInt32 = 0, sign: Bool = False
    ) raises -> Decimal128:
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
            raise ValueError(
                message=String("Value must fit in 96 bits, but got {}").format(
                    value
                ),
                function="Decimal128.from_uint128()",
            )

        if scale > UInt32(Self.MAX_SCALE):
            raise ValueError(
                message=String(
                    "Scale must be between 0 and 28, but got {}"
                ).format(scale),
                function="Decimal128.from_uint128()",
            )

        var result = UnsafePointer(to=value).bitcast[Decimal128]()[]
        result.flags |= (scale << Self.SCALE_SHIFT) & Self.SCALE_MASK
        result.flags |= UInt32(sign) << 31

        return result

    @staticmethod
    def from_string(value: String) raises -> Decimal128:
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

        # Check for non-ASCII characters (each non-ASCII char is multi-byte)
        for byte in value_bytes:
            if byte > 127:
                raise ValueError(
                    message=String(
                        "Invalid characters in decimal128 string: {}"
                    ).format(value),
                    function="Decimal128.from_string()",
                )

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
            # If the char is " ", skip it
            if code == 32:
                pass
            # If the char is "," or "_", skip it
            elif code == 44 or code == 95:
                unexpected_end_char = True
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
            # If the char is a digit 0
            elif code == 48:
                unexpected_end_char = False

                # Exponent part
                if exponent_notation_read:
                    exponent_sign_read = True
                    # exponent_start = True
                    raw_exponent = raw_exponent * 10

                # Mantissa part
                else:
                    # Skip the digit if mantissa is too long
                    if (
                        num_mantissa_digits > Decimal128.MAX_NUM_DIGITS + 8
                    ):  # 37
                        continue

                    mantissa_sign_read = True
                    mantissa_start = True

                    if mantissa_significant_start:
                        num_mantissa_digits += 1
                        coef = coef * 10

                    if decimal_point_read:
                        scale += 1

            # If the char is a digit 1 - 9
            elif code >= 49 and code <= 57:
                unexpected_end_char = False

                # Exponent part
                if exponent_notation_read:
                    # Raise an error if the exponent part is too large
                    if (not exponent_sign) and (
                        raw_exponent > Decimal128.MAX_NUM_DIGITS * 2
                    ):
                        raise OverflowError(
                            message=String(
                                "Exponent part is too large: {}"
                            ).format(raw_exponent),
                            function="Decimal128.from_string()",
                        )

                    # Skip the digit if exponent is negatively too large
                    elif (exponent_sign) and (
                        raw_exponent > Decimal128.MAX_NUM_DIGITS * 2
                    ):
                        continue

                    else:
                        # exponent_start = True
                        raw_exponent = raw_exponent * 10 + UInt32(code - 48)

                # Mantissa part
                else:
                    # Skip the digit if mantissa is too long
                    if (
                        num_mantissa_digits > Decimal128.MAX_NUM_DIGITS + 8
                    ):  # 37
                        continue

                    mantissa_significant_start = True
                    mantissa_start = True

                    num_mantissa_digits += 1
                    coef = coef * 10 + UInt128(code - 48)

                    if decimal_point_read:
                        scale += 1

            else:
                raise ValueError(
                    message=String(
                        "Invalid character in decimal128 string: {}"
                    ).format(chr(Int(code))),
                    function="Decimal128.from_string()",
                )

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
                    coef = coef * (UInt128(10) ** UInt128(raw_exponent - scale))
                    scale = 0

        # print("DEBUG: coef = ", coef)
        # print("DEBUG: scale = ", scale)

        # TODO: The following part can be written into a function
        # because it is used in many cases
        if coef <= Decimal128.MAX_AS_UINT128:
            if scale > UInt32(Decimal128.MAX_SCALE):
                coef = decimo.decimal128.utility.round_coefficient(
                    coef,
                    ndigits_to_remove=Int(scale - UInt32(Decimal128.MAX_SCALE)),
                )
                scale = UInt32(Decimal128.MAX_SCALE)

            return Decimal128.from_uint128(coef, scale, mantissa_sign)

        else:
            var fitted = decimo.decimal128.utility.fit_to_max_coefficient(coef)
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
                truncated_coef = decimo.decimal128.utility.round_coefficient(
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
    def from_float(value: Float64) raises -> Decimal128:
        """Initializes a Decimal128 from a floating-point value.
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
        print(Decimal128.from_float(Float64(3.1415926535897932383279502)))
        # 3.1415926535897932 (17 significant digits)
        print(Decimal128.from_float(12345678901234567890.12345678901234567890))
        # 12345678901234567168 (20 significant digits, but only 15 are reliable)
        ```
        .
        """

        # CASE: Zero
        if value == Float64(0):
            return Decimal128.ZERO()

        # Get the positive value of the input
        var abs_value: Float64
        var is_negative: Bool = value < 0
        if is_negative:
            abs_value = -value
        else:
            abs_value = value

        # Early exit if the value is too large
        if UInt128(abs_value) > Decimal128.MAX_AS_UINT128:
            raise OverflowError(
                message=String(
                    "The float value {} is too large (>=2^96) to be"
                    " transformed into Decimal128."
                ).format(value),
                function="Decimal128.from_float()",
            )

        # Extract binary exponent using IEEE 754 bit manipulation
        var bits: UInt64 = UnsafePointer(to=abs_value).bitcast[UInt64]().load()
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
                function="Decimal128.from_float()",
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

        coefficient = coefficient // UInt128(10) ** num_trailing_zeros
        scale -= num_trailing_zeros

        var low = UInt32(coefficient & 0xFFFFFFFF)
        var mid = UInt32((coefficient >> 32) & 0xFFFFFFFF)
        var high = UInt32((coefficient >> 64) & 0xFFFFFFFF)

        # Return both the significant digits and the scale
        return Self(low, mid, high, UInt32(scale), is_negative)

    @always_inline
    def copy(self) -> Self:
        """Returns a copy of the Decimal128.

        Returns:
            A copy of this `Decimal128`.
        """
        return Self(self.low, self.mid, self.high, self.flags)

    @always_inline
    def clone(self) -> Self:
        """Returns a copy of the Decimal128.

        Returns:
            A copy of this `Decimal128`.
        """
        return Self(self.low, self.mid, self.high, self.flags)

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
        writer.write('Decimal128("', self.to_str(), '")')

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
        writer.write(self.to_str())

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
            res = self.coefficient() // UInt128(10) ** UInt128(self.scale())

        return res

    def to_str(self) -> String:
        """Returns string representation of the Decimal128.
        Preserves trailing zeros after decimal128 point to match the scale.

        Returns:
            The string representation of this `Decimal128`.
        """
        # Get the coefficient as a string (absolute value)
        var coef = String(self.coefficient())
        var scale = self.scale()
        var result: String

        # Handle zero as a special case
        if coef == "0":
            if scale == 0:
                result = "0"
            else:
                result = "0." + "0" * scale

        # For non-zero values, format according to scale
        elif scale == 0:
            # No decimal128 places needed
            result = coef
        elif scale >= len(coef):
            # Need leading zeros after decimal128 point
            result = "0." + "0" * (scale - len(coef)) + coef
        else:
            # Insert decimal128 point at appropriate position
            var insert_pos = len(coef) - scale
            result = coef[byte=:insert_pos] + "." + coef[byte=insert_pos:]

            # Ensure we have exactly 'scale' digits after decimal128 point
            var decimal_point_pos = result.find(".")
            var current_decimals = len(result) - decimal_point_pos - 1

            if current_decimals < scale:
                # Add trailing zeros if needed
                result += "0" * (scale - current_decimals)

        # Add negative sign if needed
        if self.is_negative():
            result = "-" + result

        return result

    def to_str_scientific(self) raises -> String:
        """Returns a string representation of this Decimal128 in scientific notation.

        Returns:
            A string representation of this Decimal128 in scientific notation.

        Raises:
            Error: If significant_digits is not between 1 and 28.

        Notes:

        Scientific notation format: M.NNNNe±XX where:
        - M is the first significant digit.
        - NNNN is the remaining significant digits.
        - ±XX is the exponent.
        """
        var scale: Int = self.scale()
        var coef = self.coefficient()

        # Special case: zero
        if self.is_zero():
            if scale == 0:
                return String("0")
            else:
                return String("0E-") + String("0") * self.scale()

        while coef % 10 == 0:
            coef = coef // 10
            scale -= 1

        # 0.00100: coef=100, scale=5
        # => 0.001: coef=1, scale=3, ndigits_fractional_part=0
        # => 1.0e-3: coef=1, exponent=-3
        var ndigits_coef = decimo.decimal128.utility.number_of_digits(coef)
        var ndigits_fractional_part = ndigits_coef - 1
        var exponent = ndigits_fractional_part - scale

        # Format in scientific notation:
        # sign, first digit, decimal128 point, remaining digits
        var coef_str = String(coef)
        var result: String = String("-") if self.is_negative() else String("")
        if len(coef_str) == 1:
            result = result + coef_str + String(".0")
        else:
            result = result + coef_str[byte=0] + String(".") + coef_str[byte=1:]

        # Add exponent (E+XX or E-XX)
        if exponent >= 0:
            result += "E+" + String(exponent)
        else:
            result += "E" + String(exponent)

        return result

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
        return decimo.decimal128.arithmetics.absolute(self)

    @always_inline
    def __neg__(self) -> Self:
        """Returns the negation of this Decimal128.
        See `negative()` for more information.

        Returns:
            The negated value.
        """
        return decimo.decimal128.arithmetics.negative(self)

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
        """
        return decimo.decimal128.arithmetics.add(self, other)

    @always_inline
    def __add__(self, other: Int) raises -> Self:
        """Adds two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The sum.
        """
        return decimo.decimal128.arithmetics.add(self, Self(other))

    @always_inline
    def __sub__(self, other: Self) raises -> Self:
        """Subtracts two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The difference.
        """
        return decimo.decimal128.arithmetics.subtract(self, other)

    @always_inline
    def __sub__(self, other: Int) raises -> Self:
        """Subtracts two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The difference.
        """
        return decimo.decimal128.arithmetics.subtract(self, Self(other))

    @always_inline
    def __mul__(self, other: Self) raises -> Self:
        """Multiplies two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The product.
        """
        return decimo.decimal128.arithmetics.multiply(self, other)

    @always_inline
    def __mul__(self, other: Int) raises -> Self:
        """Multiplies two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The product.
        """
        return decimo.decimal128.arithmetics.multiply(self, Self(other))

    @always_inline
    def __truediv__(self, other: Self) raises -> Self:
        """Divides two values using true division.

        Args:
            other: The right-hand side operand.

        Returns:
            The quotient.
        """
        return decimo.decimal128.arithmetics.divide(self, other)

    @always_inline
    def __truediv__(self, other: Int) raises -> Self:
        """Divides two values using true division.

        Args:
            other: The right-hand side operand.

        Returns:
            The quotient.
        """
        return decimo.decimal128.arithmetics.divide(self, Self(other))

    @always_inline
    def __floordiv__(self, other: Self) raises -> Self:
        """Performs truncate division with // operator.

        Args:
            other: The right-hand side operand.

        Returns:
            The truncated quotient.
        """
        return decimo.decimal128.arithmetics.truncate_divide(self, other)

    @always_inline
    def __floordiv__(self, other: Int) raises -> Self:
        """Performs truncate division with // operator.

        Args:
            other: The right-hand side operand.

        Returns:
            The truncated quotient.
        """
        return decimo.decimal128.arithmetics.truncate_divide(self, Self(other))

    @always_inline
    def __mod__(self, other: Self) raises -> Self:
        """Performs truncate modulo.

        Args:
            other: The right-hand side operand.

        Returns:
            The remainder.
        """
        return decimo.decimal128.arithmetics.modulo(self, other)

    @always_inline
    def __mod__(self, other: Int) raises -> Self:
        """Performs truncate modulo.

        Args:
            other: The right-hand side operand.

        Returns:
            The remainder.
        """
        return decimo.decimal128.arithmetics.modulo(self, Self(other))

    @always_inline
    def __pow__(self, exponent: Self) raises -> Self:
        """Raises to a power.

        Args:
            exponent: The exponent to raise to.

        Returns:
            The value raised to the given power.
        """
        return decimo.decimal128.exponential.power(self, exponent)

    @always_inline
    def __pow__(self, exponent: Int) raises -> Self:
        """Raises to a power.

        Args:
            exponent: The exponent to raise to.

        Returns:
            The value raised to the given power.
        """
        return decimo.decimal128.exponential.power(self, exponent)

    # ===------------------------------------------------------------------=== #
    # Basic binary arithmetic operation dunders with reflected operands
    # These methods are called to implement the binary arithmetic operations
    # with reflected operands
    # (+, -, *, @, /, //, %, divmod(), pow(), **, <<, >>, &, ^, |)
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __radd__(self, other: Int) raises -> Self:
        """Adds two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The sum.
        """
        return decimo.decimal128.arithmetics.add(Self(other), self)

    @always_inline
    def __rsub__(self, other: Int) raises -> Self:
        """Subtracts two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The difference.
        """
        return decimo.decimal128.arithmetics.subtract(Self(other), self)

    @always_inline
    def __rmul__(self, other: Int) raises -> Self:
        """Multiplies two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The product.
        """
        return decimo.decimal128.arithmetics.multiply(Self(other), self)

    @always_inline
    def __rtruediv__(self, other: Int) raises -> Self:
        """Divides two values using true division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The quotient.
        """
        return decimo.decimal128.arithmetics.divide(Self(other), self)

    @always_inline
    def __rfloordiv__(self, other: Int) raises -> Self:
        """Performs truncate division with // operator (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The truncated quotient.
        """
        return decimo.decimal128.arithmetics.truncate_divide(Self(other), self)

    @always_inline
    def __rmod__(self, other: Int) raises -> Self:
        """Performs truncate modulo (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The remainder.
        """
        return decimo.decimal128.arithmetics.modulo(Self(other), self)

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
        """
        self = decimo.decimal128.arithmetics.add(self, other)

    @always_inline
    def __iadd__(mut self, other: Int) raises:
        """Adds in place.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.decimal128.arithmetics.add(self, Self(other))

    @always_inline
    def __isub__(mut self, other: Self) raises:
        """Subtracts in place.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.decimal128.arithmetics.subtract(self, other)

    @always_inline
    def __isub__(mut self, other: Int) raises:
        """Subtracts in place.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.decimal128.arithmetics.subtract(self, Self(other))

    @always_inline
    def __imul__(mut self, other: Self) raises:
        """Multiplies in place.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.decimal128.arithmetics.multiply(self, other)

    @always_inline
    def __imul__(mut self, other: Int) raises:
        """Multiplies in place.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.decimal128.arithmetics.multiply(self, Self(other))

    @always_inline
    def __itruediv__(mut self, other: Self) raises:
        """Divides in place using true division.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.decimal128.arithmetics.divide(self, other)

    @always_inline
    def __itruediv__(mut self, other: Int) raises:
        """Divides in place using true division.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.decimal128.arithmetics.divide(self, Self(other))

    @always_inline
    def __ifloordiv__(mut self, other: Self) raises:
        """Performs truncate division with // operator.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.decimal128.arithmetics.truncate_divide(self, other)

    @always_inline
    def __ifloordiv__(mut self, other: Int) raises:
        """Performs truncate division with // operator.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.decimal128.arithmetics.truncate_divide(self, Self(other))

    @always_inline
    def __imod__(mut self, other: Self) raises:
        """Performs truncate modulo.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.decimal128.arithmetics.modulo(self, other)

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
        return decimo.decimal128.comparison.greater(self, other)

    @always_inline
    def __lt__(self, other: Decimal128) -> Bool:
        """Less than comparison operator.
        See `less()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `True` if this value is less than `other`, `False` otherwise.
        """
        return decimo.decimal128.comparison.less(self, other)

    @always_inline
    def __ge__(self, other: Decimal128) -> Bool:
        """Greater than or equal comparison operator.
        See `greater_equal()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `True` if this value is greater than or equal to `other`, `False` otherwise.
        """
        return decimo.decimal128.comparison.greater_equal(self, other)

    @always_inline
    def __le__(self, other: Decimal128) -> Bool:
        """Less than or equal comparison operator.
        See `less_equal()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `True` if this value is less than or equal to `other`, `False` otherwise.
        """
        return decimo.decimal128.comparison.less_equal(self, other)

    @always_inline
    def __eq__(self, other: Decimal128) -> Bool:
        """Equality comparison operator.
        See `equal()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `True` if the values are equal, `False` otherwise.
        """
        return decimo.decimal128.comparison.equal(self, other)

    @always_inline
    def __ne__(self, other: Decimal128) -> Bool:
        """Inequality comparison operator.
        See `not_equal()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            `True` if the values are not equal, `False` otherwise.
        """
        return decimo.decimal128.comparison.not_equal(self, other)

    # ===------------------------------------------------------------------=== #
    # Other dunders that implements traits
    # round
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
            return decimo.decimal128.rounding.round(
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
            return decimo.decimal128.rounding.round(
                self, ndigits=0, rounding_mode=RoundingMode.half_even()
            )
        except e:
            return self

    # ===------------------------------------------------------------------=== #
    # Mathematical methods that do not implement a trait (not a dunder)
    # exp, ln, round, sqrt
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
        """
        return decimo.decimal128.rounding.round(
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
        """
        return decimo.decimal128.rounding.quantize(self, exp, rounding_mode)

    @always_inline
    def exp(self) raises -> Self:
        """Calculates the exponential of this Decimal128.
        See `exp()` for more information.

        Returns:
            The value of e raised to this power.
        """
        return decimo.decimal128.exponential.exp(self)

    @always_inline
    def ln(self) raises -> Self:
        """Calculates the natural logarithm of this Decimal128.
        See `ln()` for more information.

        Returns:
            The natural logarithm of this value.
        """
        return decimo.decimal128.exponential.ln(self)

    @always_inline
    def log10(self) raises -> Decimal128:
        """Computes the base-10 logarithm of this Decimal128.

        Returns:
            The base-10 logarithm of this value.
        """
        return decimo.decimal128.exponential.log10(self)

    @always_inline
    def log(self, base: Decimal128) raises -> Decimal128:
        """Computes the logarithm of this Decimal128 with an arbitrary base.

        Args:
            base: The logarithm base.

        Returns:
            The logarithm of this value in the given base.
        """
        return decimo.decimal128.exponential.log(self, base)

    @always_inline
    def power(self, exponent: Int) raises -> Decimal128:
        """Raises this Decimal128 to the power of an integer.

        Args:
            exponent: The integer exponent to raise to.

        Returns:
            The value raised to the given power.
        """
        return decimo.decimal128.exponential.power(self, Self(exponent))

    @always_inline
    def power(self, exponent: Decimal128) raises -> Decimal128:
        """Raises this Decimal128 to the power of another Decimal128.

        Args:
            exponent: The `Decimal128` exponent to raise to.

        Returns:
            The value raised to the given power.
        """
        return decimo.decimal128.exponential.power(self, exponent)

    @always_inline
    def root(self, n: Int) raises -> Self:
        """Calculates the n-th root of this Decimal128.
        See `root()` for more information.

        Args:
            n: The degree of the root to compute.

        Returns:
            The n-th root of this value.
        """
        return decimo.decimal128.exponential.root(self, n)

    @always_inline
    def sqrt(self) raises -> Self:
        """Calculates the square root of this Decimal128.
        See `sqrt()` for more information.

        Returns:
            The square root of this value.
        """
        return decimo.decimal128.exponential.sqrt(self)

    # ===------------------------------------------------------------------=== #
    # Other methods
    # ===------------------------------------------------------------------=== #

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
        return decimo.decimal128.utility.bitcast[DType.uint128](self)

        # Alternative implementation using arithmetic
        # Combine the three 32-bit parts into a single Int128
        # return (
        #     UInt128(self.high) << 64
        #     | UInt128(self.mid) << 32
        #     | UInt128(self.low)
        # )

    def extend_precision(self, var precision_diff: Int) raises -> Decimal128:
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
        var max_coefficient = ~UInt128(0) / UInt128(10) ** precision_diff
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
            if len(labels[i]) > max_label_len:
                max_label_len = len(labels[i])

        var col = max_label_len + 4  # 4 spaces after longest label

        def pad(label: String) -> String:
            return label + String(" ") * (col - len(label))

        var sep_line = String("-") * (col + 30)

        var result = String("\nInternal Representation Details of Decimal128\n")
        result += sep_line + "\n"
        result += pad("Decimal128:") + self.to_str() + "\n"
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

    def print_internal_representation(self):
        """Prints the internal representation details of a Decimal128."""
        print(self.internal_representation())

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
            % decimo.decimal128.utility.power_of_10_unsafe[DType.uint128](scale)
        ) == 0

    @always_inline
    def is_negative(self) -> Bool:
        """Returns True if this Decimal128 is negative.

        Returns:
            `True` if negative, `False` otherwise.
        """
        return (self.flags & Self.SIGN_MASK) != 0

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

        if coef == decimo.decimal128.utility.power_of_10_unsafe[DType.uint128](
            scale
        ):
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
            return decimo.decimal128.utility.number_of_digits(coef)
