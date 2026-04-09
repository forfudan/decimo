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

"""Implements basic object methods for the BigDecimal type.

This module contains the basic object methods for the BigDecimal type.
These methods include constructors, life time methods, output dunders,
type-transfer dunders, basic arithmetic operation dunders, comparison
operation dunders, and other dunders that implement traits, as well as
mathematical methods that do not implement a trait.
"""

from std.memory import UnsafePointer
from std.python import PythonObject
from std import testing

from decimo.errors import DecimoError, ConversionError, ValueError
from decimo.rounding_mode import RoundingMode
from decimo.bigdecimal.rounding import round_to_precision
from decimo.bigint10.bigint10 import BigInt10
import decimo.str

comptime BDec = BigDecimal
"""An arbitrary-precision decimal, similar to Python's `decimal.Decimal`."""
comptime Decimal = BigDecimal
"""An arbitrary-precision decimal, similar to Python's `decimal.Decimal`."""

comptime PRECISION = 28  # Same as Python's decimal module default precision of 28 places.
"""Default precision for BigDecimal operations.
This will be configurable in future when Mojo supports global variables.
"""


struct BigDecimal(
    Absable,
    Comparable,
    Copyable,
    FloatableRaising,
    IntableRaising,
    Movable,
    Roundable,
    Writable,
):
    """An arbitrary-precision decimal, similar to Python's `decimal.Decimal`.

    Notes:

    Internal Representation:

    - A base-10 unsigned integer (BigUInt) for coefficient.
    - A Int value for the scale
    - A Bool value for the sign.

    Final value:
    (-1)**sign * coefficient * 10^(-scale)
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
    var coefficient: BigUInt
    """The coefficient of the BigDecimal."""
    var scale: Int
    """The scale of the BigDecimal."""
    var sign: Bool
    """Sign information."""

    # ===------------------------------------------------------------------=== #
    # Constructors and life time dunder methods
    # ===------------------------------------------------------------------=== #

    def __init__(out self):
        """Initializes to zero by default."""
        self.coefficient = BigUInt()
        self.scale = 0
        self.sign = False

    @implicit
    def __init__(out self, coefficient: BigUInt):
        """Constructs a BigDecimal from a BigUInt object.

        Args:
            coefficient: The unsigned integer coefficient.
        """
        self.coefficient = coefficient.copy()
        self.scale = 0
        self.sign = False

    def __init__(out self, coefficient: BigUInt, scale: Int, sign: Bool):
        """Constructs a BigDecimal from its components.

        Args:
            coefficient: The unsigned integer coefficient.
            scale: The number of decimal places (power of 10 divisor).
            sign: Whether the value is negative.
        """
        self.coefficient = coefficient.copy()
        self.scale = scale
        self.sign = sign

    @implicit
    def __init__(out self, value: BigInt10):
        """Constructs a BigDecimal from a big integer.

        Args:
            value: The `BigInt10` to convert.
        """
        self.coefficient = value.magnitude.copy()
        self.scale = 0
        self.sign = value.sign

    def __init__(out self, value: String) raises:
        """Constructs a BigDecimal from a string representation.

        Args:
            value: The string to parse (e.g. "123.456" or "1.23E+5").
        """
        # The string is normalized with `decimo.str.parse_numeric_string()`.
        self = Self.from_string(value)

    @implicit
    def __init__(out self, value: Int):
        """Constructs a BigDecimal from an `Int` object.
        See `from_int()` for more information.

        Args:
            value: The integer to convert.
        """
        self = Self.from_int(value)

    @implicit
    def __init__(out self, value: UInt):
        """Constructs a BigDecimal from an `UInt` object.
        See `from_uint()` for more information.

        Args:
            value: The unsigned integer to convert.
        """
        self = Self.from_uint(value)

    @implicit
    def __init__[dtype: DType, //](out self, value: SIMD[dtype, 1]):
        """Constructs a BigDecimal from an integral scalar.
        This includes all SIMD integral types, such as Int8, Int16, UInt32, etc.

        Constraints:
            The dtype of the scalar must be integral.

        Parameters:
            dtype: The data type of the scalar.

        Args:
            value: The integral scalar to convert.
        """
        comptime assert dtype.is_integral(), (
            "\n***********************************************************\n"
            "BigDecimal does not allow floating-point numbers as input to"
            " avoid unintentional loss of precision. If you want to create"
            " a BigDecimal from a floating-point number, please consider"
            " wrapping it with quotation marks or using the"
            " `BigDecimal.from_float()` (or `BDec.from_float()`) method"
            " instead."
            "\n***********************************************************"
        )

        self = Self.from_integral_scalar(value)

    def __init__(out self, *, py: PythonObject) raises:
        """Constructs a BigDecimal from a Python Decimal object.

        Args:
            py: A Python `decimal.Decimal` object.
        """
        self = Self.from_python_decimal(py)

    # ===------------------------------------------------------------------=== #
    # Constructing methods that are not dunders
    # from_int(value: Int) -> Self
    # from_scalar(value: Scalar) -> Self
    # from_string(value: String) -> Self
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def from_raw_components(
        var words: List[UInt32], scale: Int = 0, sign: Bool = False
    ) -> Self:
        """**UNSAFE** Creates a BigDecimal from its raw components.
        The raw components are words, scale, and sign.

        Args:
            words: The raw words of the coefficient.
            scale: The scale of the BigDecimal.
            sign: The sign of the BigDecimal.

        Returns:
            A BigDecimal object constructed from the raw components.

        Notes:

        This method is unsafe because it does not check the validity of the
        words. It is the caller's responsibility to ensure that the words
        represent a valid BigUInt.
        """
        var coefficient = BigUInt(raw_words=words^)
        return Self(coefficient=coefficient^, scale=scale, sign=sign)

    @staticmethod
    def from_raw_components(
        word: UInt32, scale: Int = 0, sign: Bool = False
    ) -> Self:
        """**UNSAFE** Creates a BigDecimal from its raw components.
        The raw components are a single word, scale, and sign.

        Args:
            word: The single raw UInt32 word for the coefficient.
            scale: The number of decimal places.
            sign: Whether the value is negative.

        Returns:
            A `BigDecimal` constructed from the raw components.
        """
        return Self(BigUInt(raw_words=[word]), scale, sign)

    @staticmethod
    def from_int(value: Int) -> Self:
        """Creates a BigDecimal from an integer.

        Args:
            value: The integer to convert.

        Returns:
            A `BigDecimal` representing the given integer.
        """
        if value == 0:
            return Self(coefficient=BigUInt.zero(), scale=0, sign=False)

        var words = List[UInt32](capacity=2)
        var sign: Bool
        var remainder: Int
        var quotient: Int
        var is_min: Bool = False
        if value < 0:
            sign = True
            # Handle the case of Int.MIN due to asymmetry of Int.MIN and Int.MAX
            if value == Int.MIN:
                is_min = True
                remainder = Int.MAX
            else:
                remainder = -value
        else:
            sign = False
            remainder = value

        while remainder != 0:
            quotient = remainder // 1_000_000_000
            remainder = remainder % 1_000_000_000
            words.append(UInt32(remainder))
            remainder = quotient

        if is_min:
            words[0] += 1

        return Self(coefficient=BigUInt(raw_words=words^), scale=0, sign=sign)

    # TODO: This method is no longer needed as UInt is now an alias for SIMD.
    @staticmethod
    def from_uint(value: UInt) -> Self:
        """Creates a BigDecimal from an unsigned integer.

        Args:
            value: The unsigned integer to convert.

        Returns:
            A `BigDecimal` representing the given unsigned integer.
        """
        return Self(
            coefficient=BigUInt.from_unsigned_integral_scalar(value),
            scale=0,
            sign=False,
        )

    @staticmethod
    def from_integral_scalar[dtype: DType, //](value: SIMD[dtype, 1]) -> Self:
        """Initializes a BigDecimal from an integral scalar.
        This includes all SIMD integral types, such as Int8, Int16, UInt32, etc.

        Args:
            value: The Scalar value to be converted to BigDecimal.

        Returns:
            The BigDecimal representation of the Scalar value.

        Parameters:
            dtype: The data type of the scalar.
        """

        comptime assert dtype.is_integral(), "dtype must be integral."

        if value == 0:
            return Self(coefficient=BigUInt.zero(), scale=0, sign=False)

        return Self(
            coefficient=BigUInt.from_absolute_integral_scalar(value),
            scale=0,
            sign=True if value < 0 else False,
        )

    @staticmethod
    def from_float[dtype: DType, //](value: Scalar[dtype]) raises -> Self:
        """Initializes a BigDecimal from a floating-point scalar.

        Args:
            value: The Scalar value to be converted to BigDecimal.

        Returns:
            The BigDecimal representation of the Scalar value.

        Notes:

        If the value is a floating-point number, it is converted to a string
        with full precision before converting to BigDecimal.

        Parameters:
            dtype: The data type of the scalar.
        """

        comptime assert (
            dtype.is_floating_point()
        ), "dtype must be floating-point."

        if value == 0:
            return Self(coefficient=BigUInt.zero(), scale=0, sign=False)

        if value != value:  # Check for NaN
            raise Error(
                ValueError(
                    message="Cannot convert NaN to BigDecimal.",
                    function="BigDecimal.from_scalar()",
                )
            )
        # Convert to string with full precision
        try:
            return Self.from_string(String(value))
        except e:
            raise Error(
                ConversionError(
                    message="Cannot convert scalar to BigDecimal.",
                    function="BigDecimal.from_scalar()",
                    previous_error=e^,
                )
            )

    @staticmethod
    def from_string(value: String) raises -> Self:
        """Initializes a BigDecimal from a string representation.
        The string is normalized with `decimo.str.parse_numeric_string()`.

        Args:
            value: The string representation of the BigDecimal.

        Returns:
            The BigDecimal representation of the string.
        """
        _tuple = decimo.str.parse_numeric_string(value)
        var ref coef: List[UInt8] = _tuple[0]
        var scale: Int = _tuple[1]
        var sign: Bool = _tuple[2]

        var number_of_digits = len(coef)
        var number_of_words = number_of_digits // 9
        if number_of_digits % 9 != 0:
            number_of_words += 1

        coefficient_words = List[UInt32](capacity=number_of_words)

        var end: Int = number_of_digits
        var start: Int
        while end >= 9:
            start = end - 9
            var word: UInt32 = 0
            for digit in coef[start:end]:
                word = word * 10 + UInt32(digit)
            coefficient_words.append(word)
            end = start
        if end > 0:
            var word: UInt32 = 0
            for digit in coef[0:end]:
                word = word * 10 + UInt32(digit)
            coefficient_words.append(word)

        coefficient = BigUInt(raw_words=coefficient_words^)

        return Self(coefficient=coefficient^, scale=scale, sign=sign)

    @staticmethod
    def from_python_decimal(value: PythonObject) raises -> Self:
        """Initializes a BigDecimal from a Python Decimal object.
        Only finite Decimal values are supported for conversion.

        Args:
            value: A Python Decimal object (from decimal module).

        Returns:
            The BigDecimal representation of the Python Decimal.

        Raises:
            Error: If the conversion from Python Decimal fails, or if
                the as_tuple() method returns invalid data.

        Examples:
        ```mojo
        from std.python import Python
        from decimo.prelude import *

        def main() raises:
            var decimal = Python.import_module("decimal")
            var py_dec = decimal.Decimal("123.456")
            var mojo_dec = BigDecimal.from_python_decimal(py_dec)
            print(mojo_dec)  # 123.456
        ```
        End of examples.

        Notes:

        This method uses Python's `as_tuple()` API to extract the decimal's
        components: (sign, digits, exponent). The digits are individual
        base-10 digits (0-9), not the internal limb representation.

        Why use as_tuple() instead of direct memory copy?

        Python's decimal module (libmpdec) uses a base-10^9 representation
        on 64-bit systems (base 10^4 on 32-bit), which matches BigDecimal's
        internal representation. Theoretically, we could directly memcpy the
        internal limbs for better performance.

        However, this approach is NOT used because:

        1. No API for direct access: Python's PythonObject doesn't expose
           the internal mpd_t pointer. Accessing it would require unsafe
           pointer manipulation, breaking abstraction boundaries.
        2. Platform dependency: 32-bit systems use base 10^4, requiring
           platform-specific code paths and runtime detection.
        3. Maintenance burden: Direct memory access depends on CPython
           internal implementation details that may change between versions.
        4. Safety concerns: Unsafe pointer operations risk memory safety
           violations, GC issues, and data races.
        5. Marginal performance gain: The time complexity of as_tuple() is still
           O(n) compared to O(n) for direct memory copy.

        The as_tuple() API provides:
        - Safe, stable interface across Python versions.
        - Portable across all platforms (32/64-bit, CPython/PyPy).
        - Clean, maintainable code.
        - Adequate performance for real-world use cases.
        """
        try:
            # Get DecimalTuple: (sign, digits, exponent)
            var tuple_repr = value.as_tuple()

            # Extract components
            # Convert PythonObject to Int via String
            var sign_int = Int(py=tuple_repr[0])
            var sign = True if sign_int == 1 else False
            var digits_tuple = tuple_repr[1]
            # When Python's Decimal.as_tuple() is called on these special
            # values, the exponent field is a string ('F' for infinity,
            # 'n' for NaN) rather than an integer.
            # Thus, only finite decimal values are supported for conversion.
            var exponent = Int(py=tuple_repr[2])

            # Convert digits tuple to coefficient string
            # digits are individual base-10 digits (0-9)
            var num_digits = len(digits_tuple)

            # Handle special case: zero
            if num_digits == 1 and Int(py=digits_tuple[0]) == 0:
                return Self(coefficient=BigUInt.zero(), scale=0, sign=False)

            # Build coefficient from digits
            var number_of_words = num_digits // 9
            if num_digits % 9 != 0:
                number_of_words += 1

            var coefficient_words = List[UInt32](capacity=number_of_words)

            # Process digits from right to left, grouping into 9-digit words
            var end = num_digits
            var start: Int
            while end >= 9:
                start = end - 9
                var word: UInt32 = 0
                for i in range(start, end):
                    var digit = Int(py=digits_tuple[i])
                    word = word * 10 + UInt32(digit)
                coefficient_words.append(word)
                end = start

            # Handle remaining digits
            if end > 0:
                var word: UInt32 = 0
                for i in range(0, end):
                    var digit = Int(py=digits_tuple[i])
                    word = word * 10 + UInt32(digit)
                coefficient_words.append(word)

            var coefficient = BigUInt(raw_words=coefficient_words^)

            # In Python's Decimal.as_tuple():
            # - exponent is the power of 10 to multiply by
            # - In BigDecimal, scale is the number of decimal places
            # - So scale = -exponent
            var scale = -exponent

            return Self(coefficient=coefficient^, scale=scale, sign=sign)

        except e:
            raise Error(
                ConversionError(
                    message="Failed to convert Python Decimal to BigDecimal.",
                    function="BigDecimal.from_python_decimal()",
                    previous_error=e^,
                ),
            )

    # ===------------------------------------------------------------------=== #
    # Output dunders, type-transfer dunders
    # __int__()
    # __float__()
    # ===------------------------------------------------------------------=== #

    def __int__(self) raises -> Int:
        """Converts the BigDecimal to an integer.

        Returns:
            The integer representation, truncating any fractional part.
        """
        return Int(self.to_string())

    def __float__(self) raises -> Float64:
        """Converts the BigDecimal to a floating-point number.

        Returns:
            The `Float64` representation of this value.
        """
        return Float64(self.to_string())

    # ===------------------------------------------------------------------=== #
    # Type-transfer or output methods that are not dunders
    # ===------------------------------------------------------------------=== #

    def to_string(
        self,
        scientific: Bool = False,
        engineering: Bool = False,
        force_plain: Bool = False,
        delimiter: String = "",
        line_width: Int = 0,
    ) -> String:
        """Returns string representation of the number.

        This method follows CPython's ``Decimal.__str__`` logic exactly for
        the default and scientific-notation paths.

        - Engineering notation (``engineering=True``) is tried first.
          The exponent is always a multiple of 3 (e.g. ``12.34E+6``,
          ``500E-3``).  Trailing zeros in the mantissa are stripped.
        - Scientific notation is used when:
          1. ``scientific`` parameter is True, OR
          2. The internal exponent > 0 (i.e., scale < 0), OR
          3. There are more than 6 leading zeros after the decimal
             point (adjusted exponent < -6), unless ``force_plain=True``.
        - Otherwise, plain (fixed-point) notation is used.

        When both ``engineering`` and ``scientific`` are True, engineering
        notation takes precedence.

        Args:
            scientific: If True, the number is always represented in
                scientific notation (trailing zeros stripped).  The format is
                otherwise determined by the CPython-compatible rules above.
            engineering: If True, the number is represented in engineering
                notation (exponent is a multiple of 3, trailing zeros
                stripped).
            force_plain: If True, suppress the CPython-compatible
                auto-detection of scientific notation (the ``scale < 0`` and
                ``leftdigits <= -6`` rules are not applied).  Useful when a
                guaranteed fixed-point string is needed regardless of
                magnitude.  Has no effect when ``scientific`` or
                ``engineering`` is True.
            delimiter: A string inserted every 3 digits in both the integer
                and fractional parts (e.g. ``"_"`` gives ``1_234.567_89``).
                An empty string (default) disables grouping.
            line_width: The maximum line width for the string representation.
                If 0, the string is returned as a single line.
                If greater than 0, the string is split into multiple lines.

        Returns:
            A string representation of the number.
        """

        if self.coefficient.is_unitialized():
            return String("Unitilialized maginitude of BigDecimal")

        var result = String("-") if self.sign else String("")
        var coefficient_string = self.coefficient.to_string()
        var num_digits = len(coefficient_string)

        # CPython-compatible logic for Decimal.__str__:
        #
        # In CPython, a Decimal stores (_sign, _int, _exp) where:
        #   value = (-1)**_sign * int(_int) * 10**_exp
        #
        # Mapping to Decimo:
        #   CPython _exp  = -self.scale
        #   CPython _int  = coefficient_string (digit string)
        #
        # leftdigits = _exp + len(_int) = num_digits - self.scale
        #
        # CPython uses plain notation when:
        #   _exp <= 0 (i.e., scale >= 0) AND leftdigits > -6
        # Otherwise, scientific notation with 1 digit before the point.

        var leftdigits = num_digits - self.scale

        # Determine whether to use scientific notation
        var use_scientific = scientific or (
            not force_plain and (self.scale < 0 or leftdigits <= -6)
        )

        if engineering:
            # Engineering notation: exponent is always a multiple of 3.
            # Examples: 12345 -> 12.345E+3, 0.001 -> 1E-3, 0.5 -> 500E-3.
            var adjusted_exp = leftdigits - 1
            var eng_exp: Int
            if adjusted_exp >= 0:
                eng_exp = (adjusted_exp // 3) * 3
            else:
                eng_exp = -((-adjusted_exp + 2) // 3) * 3
            var lead_digits = adjusted_exp - eng_exp + 1  # always 1, 2, or 3

            # Strip trailing zeros (artifacts of working precision)
            var coef = coefficient_string
            var cb = StringSlice(coef).as_bytes()
            var clen = len(cb)
            var cptr = cb.unsafe_ptr()
            while clen > 1 and cptr[clen - 1] == 48:  # '0'
                clen -= 1
            if clen < num_digits:
                var trimmed = List[UInt8](capacity=clen)
                for i in range(clen):
                    trimmed.append(cptr[i])
                coef = String(unsafe_from_utf8=trimmed^)

            # Zero-pad the right side if fewer sig-digits than lead_digits
            # e.g. coef="5", lead_digits=3  ->  coef="500"  (500E-3)
            if len(coef) < lead_digits:
                coef = coef + "0" * (lead_digits - len(coef))

            # Build mantissa
            if len(coef) <= lead_digits:
                result += coef
            else:
                result += coef[byte=:lead_digits]
                result += "."
                result += coef[byte=lead_digits:]

            # Append exponent (omit the 'E' suffix when eng_exp == 0)
            if eng_exp != 0:
                result += "E"
                if eng_exp > 0:
                    result += "+"
                result += String(eng_exp)

        elif use_scientific:
            # Scientific notation: 1 digit on left of the decimal point
            var exponent = leftdigits - 1
            # When the caller explicitly requests scientific notation, strip
            # trailing zeros that are artifacts of working precision (e.g.
            # "5.0000...0E-1" -> "5E-1").  When scientific notation is
            # triggered automatically by CPython-compatibility rules we
            # preserve all digits so that __str__ stays round-trip safe.
            var coef = coefficient_string
            if scientific:
                var cb = StringSlice(coef).as_bytes()
                var clen = len(cb)
                var cptr = cb.unsafe_ptr()
                while clen > 1 and cptr[clen - 1] == 48:  # ord('0')
                    clen -= 1
                if clen < num_digits:
                    var trimmed = List[UInt8](capacity=clen)
                    for i in range(clen):
                        trimmed.append(cptr[i])
                    coef = String(unsafe_from_utf8=trimmed^)
            result += coef[byte=0]
            if len(coef) > 1:
                result += "."
                result += coef[byte=1:]
            result += "E"
            if exponent > 0:
                result += "+"
            result += String(exponent)

        else:
            # Plain notation (scale >= 0 and leftdigits > -6)
            if leftdigits <= 0:
                # All digits are after the decimal point with leading zeros.
                # Example: coefficient "123", scale 5 -> leftdigits = -2
                #          -> "0.00123"
                result += "0."
                result += "0" * (-leftdigits)
                result += coefficient_string

            elif leftdigits >= num_digits:
                # All digits are before the decimal point (scale == 0).
                # Example: coefficient "12345", scale 0 -> "12345"
                result += coefficient_string
                # leftdigits - num_digits trailing zeros (always 0 here
                # since scale >= 0 implies leftdigits <= num_digits,
                # with equality when scale == 0).

            else:
                # Decimal point falls within the digit string.
                # Example: coefficient "123456", scale 3 -> "123.456"
                result += coefficient_string[byte=:leftdigits]
                result += "."
                result += coefficient_string[byte=leftdigits:]

        # Insert digit-group separators if requested
        if delimiter:
            result = _insert_digit_separators(result^, delimiter)

        # Split the result in multiple lines if line_width > 0
        if line_width > 0:
            var start = 0
            var end = line_width
            var lines = List[String](capacity=len(result) // line_width + 1)
            while end < len(result):
                lines.append(String(result[byte=start:end]))
                start = end
                end += line_width
            lines.append(String(result[byte=start:]))
            result = String("\n").join(lines^)

        return result^

    def write_to[W: Writer](self, mut writer: W):
        """Writes the BigDecimal to a writer.
        This implement the `write` method of the `Writer` trait.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        writer.write(self.to_string())

    def write_repr_to[W: Writer](self, mut writer: W):
        """Writes the debug representation to a writer.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        writer.write('BigDecimal("', self.to_string(), '")')

    def to_scientific_string(self) -> String:
        """Returns the number in scientific notation (trailing zeros stripped).

        Convenience alias for `to_string(scientific=True)`.

        Examples:

        ```
        BigDecimal("123456.789").to_scientific_string()  # "1.23456789E+5"
        BigDecimal("0.00123").to_scientific_string()     # "1.23E-3"
        ```

        Returns:
            The number formatted in scientific notation.
        """
        return self.to_string(scientific=True)

    def to_eng_string(self) -> String:
        """Returns the number in engineering notation (exponent is a multiple
        of 3, trailing zeros stripped).

        Convenience alias for `to_string(engineering=True)`.

        Examples:

        ```
        BigDecimal("123456.789").to_eng_string()  # "123.456789E+3"
        BigDecimal("0.00123").to_eng_string()     # "1.23E-3"
        ```

        Returns:
            The number formatted in engineering notation.
        """
        return self.to_string(engineering=True)

    def to_string_with_separators(self, separator: String = "_") -> String:
        """Returns a string with digit-group separators inserted every 3 digits.

        Groups both the integer and fractional parts.  Convenience alias for
        `to_string(delimiter=separator)`.

        Args:
            separator: The separator character (default: `"_"`).

        Examples:

        ```
        BigDecimal("1234567.89").to_string_with_separators()       # "1_234_567.89"
        BigDecimal("1234567.89").to_string_with_separators(",")    # "1,234,567.89"
        BigDecimal("-9876543210.123456").to_string_with_separators()
        # "-9_876_543_210.123_456"
        ```

        Returns:
            The number formatted with digit-group separators.
        """
        return self.to_string(delimiter=separator)

    # ===------------------------------------------------------------------=== #
    # Basic unary operation dunders
    # neg
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __abs__(self) -> Self:
        """Returns the absolute value of this number.
        See `absolute()` for more information.

        Returns:
            The absolute value.
        """
        return Self(
            coefficient=self.coefficient,
            scale=self.scale,
            sign=False,
        )

    @always_inline
    def __neg__(self) -> Self:
        """Returns the negation of this number.
        See `negative()` for more information.

        Returns:
            The negated value.
        """
        return Self(
            coefficient=self.coefficient,
            scale=self.scale,
            sign=not self.sign,
        )

    @always_inline
    def __bool__(self) -> Bool:
        """Returns True if the number is nonzero.

        This enables `if x:` syntax, consistent with Python's `decimal.Decimal`.

        Returns:
            True if the number is nonzero, False otherwise.
        """
        return not self.coefficient.is_zero()

    @always_inline
    def __pos__(self) -> Self:
        """Returns the number unchanged (unary plus).

        This enables `+x` syntax, consistent with Python's `decimal.Decimal`.
        In Python, unary plus applies context rounding. Here it returns a copy.

        Returns:
            A copy of this number.
        """
        return self.copy()

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
            The sum of the two values.
        """
        return decimo.bigdecimal.arithmetics.add(self, other)

    @always_inline
    def __sub__(self, other: Self) raises -> Self:
        """Subtracts two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The difference of the two values.
        """
        return decimo.bigdecimal.arithmetics.subtract(self, other)

    @always_inline
    def __mul__(self, other: Self) -> Self:
        """Multiplies two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The product of the two values.
        """
        return decimo.bigdecimal.arithmetics.multiply(self, other)

    @always_inline
    def __truediv__(self, other: Self) raises -> Self:
        """Divides two values using true division.

        Args:
            other: The right-hand side operand.

        Returns:
            The quotient of the two values.
        """
        return decimo.bigdecimal.arithmetics.true_divide(
            self, other, precision=PRECISION
        )

    @always_inline
    def __floordiv__(self, other: Self) raises -> Self:
        """Returns the result of floor division.
        See `arithmetics.truncate_divide()` for more information.

        Args:
            other: The right-hand side operand.

        Returns:
            The integer quotient, truncated toward zero.
        """
        return decimo.bigdecimal.arithmetics.truncate_divide(self, other)

    @always_inline
    def __mod__(self, other: Self) raises -> Self:
        """Returns the result of modulo operation.
        See `arithmetics.truncate_modulo()` for more information.

        Args:
            other: The right-hand side operand.

        Returns:
            The remainder after truncated division.
        """
        return decimo.bigdecimal.arithmetics.truncate_modulo(
            self, other, precision=PRECISION
        )

    @always_inline
    def __pow__(self, exponent: Self) raises -> Self:
        """Returns the result of exponentiation.

        Args:
            exponent: The power to raise this value to.

        Returns:
            This value raised to the given exponent.
        """
        return decimo.bigdecimal.exponential.power(
            self, exponent, precision=PRECISION
        )

    def __divmod__(self, other: Self) raises -> Tuple[Self, Self]:
        """Returns `(self // other, self % other)`.

        This enables `divmod(a, b)` syntax, consistent with Python's
        `decimal.Decimal`.

        Notes:

        Uses truncated division (toward zero), matching Python's
        `decimal.Decimal.__divmod__()` behavior.

        Args:
            other: The right-hand side operand.

        Returns:
            A tuple of `(quotient, remainder)` from truncated division.
        """
        var quotient = decimo.bigdecimal.arithmetics.truncate_divide(
            self, other
        )
        var remainder = decimo.bigdecimal.arithmetics.subtract(
            self,
            decimo.bigdecimal.arithmetics.multiply(quotient, other),
        )
        return (quotient^, remainder^)

    def __rdivmod__(self, other: Self) raises -> Tuple[Self, Self]:
        """Returns `divmod(other, self)` for right-side divmod.

        Args:
            other: The left-hand side operand.

        Returns:
            A tuple of `(quotient, remainder)` from truncated division.
        """
        var quotient = decimo.bigdecimal.arithmetics.truncate_divide(
            other, self
        )
        var remainder = decimo.bigdecimal.arithmetics.subtract(
            other,
            decimo.bigdecimal.arithmetics.multiply(quotient, self),
        )
        return (quotient^, remainder^)

    # ===------------------------------------------------------------------=== #
    # Basic binary right-side arithmetic operation dunders
    # These methods are called to implement the binary arithmetic operations
    # (+, -, *, @, /, //, %, divmod(), pow(), **, <<, >>, &, ^, |)
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __radd__(self, other: Self) raises -> Self:
        """Adds two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The sum of the two values.
        """
        return decimo.bigdecimal.arithmetics.add(self, other)

    @always_inline
    def __rsub__(self, other: Self) raises -> Self:
        """Subtracts two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The difference `other - self`.
        """
        return decimo.bigdecimal.arithmetics.subtract(other, self)

    @always_inline
    def __rmul__(self, other: Self) raises -> Self:
        """Multiplies two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The product of the two values.
        """
        return decimo.bigdecimal.arithmetics.multiply(self, other)

    @always_inline
    def __rfloordiv__(self, other: Self) raises -> Self:
        """Divides two values using floor division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The integer quotient `other // self`, truncated toward zero.
        """
        return decimo.bigdecimal.arithmetics.truncate_divide(other, self)

    @always_inline
    def __rmod__(self, other: Self) raises -> Self:
        """Returns the remainder of division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The remainder `other % self`.
        """
        return decimo.bigdecimal.arithmetics.truncate_modulo(
            other, self, precision=PRECISION
        )

    @always_inline
    def __rpow__(self, base: Self) raises -> Self:
        """Raises to a power (reflected).

        Args:
            base: The base to raise to the power of self.

        Returns:
            The base raised to the power of self.
        """
        return decimo.bigdecimal.exponential.power(
            base, self, precision=PRECISION
        )

    @always_inline
    def __rtruediv__(self, other: Self) raises -> Self:
        """Divides two values using true division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The quotient `other / self`.
        """
        return decimo.bigdecimal.arithmetics.true_divide(
            other, self, precision=PRECISION
        )

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
        decimo.bigdecimal.arithmetics.add_inplace(self, other)

    @always_inline
    def __isub__(mut self, other: Self) raises:
        """Subtracts in place.

        Args:
            other: The right-hand side operand.
        """
        decimo.bigdecimal.arithmetics.subtract_inplace(self, other)

    @always_inline
    def __imul__(mut self, other: Self) raises:
        """Multiplies in place.

        Args:
            other: The right-hand side operand.
        """
        decimo.bigdecimal.arithmetics.multiply_inplace(self, other)

    @always_inline
    def __itruediv__(mut self, other: Self) raises:
        """Divides in place using true division.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.bigdecimal.arithmetics.true_divide(
            self, other, precision=PRECISION
        )

    @always_inline
    def __ifloordiv__(mut self, other: Self) raises:
        """Divides in place using floor division.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.bigdecimal.arithmetics.truncate_divide(self, other)

    @always_inline
    def __imod__(mut self, other: Self) raises:
        """Computes the remainder in place.

        Args:
            other: The right-hand side operand.
        """
        self = decimo.bigdecimal.arithmetics.truncate_modulo(
            self, other, precision=PRECISION
        )

    # ===------------------------------------------------------------------=== #
    # Basic binary comparison operation dunders
    # __gt__, __ge__, __lt__, __le__, __eq__, __ne__
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __gt__(self, other: Self) -> Bool:
        """Returns whether self is greater than other.

        Args:
            other: The value to compare against.

        Returns:
            True if self is greater than other, False otherwise.
        """
        return decimo.bigdecimal.comparison.compare(self, other) > 0

    @always_inline
    def __ge__(self, other: Self) -> Bool:
        """Returns whether self is greater than or equal to other.

        Args:
            other: The value to compare against.

        Returns:
            True if self is greater than or equal to other, False otherwise.
        """
        return decimo.bigdecimal.comparison.compare(self, other) >= 0

    @always_inline
    def __lt__(self, other: Self) -> Bool:
        """Returns whether self is less than other.

        Args:
            other: The value to compare against.

        Returns:
            True if self is less than other, False otherwise.
        """
        return decimo.bigdecimal.comparison.compare(self, other) < 0

    @always_inline
    def __le__(self, other: Self) -> Bool:
        """Returns whether self is less than or equal to other.

        Args:
            other: The value to compare against.

        Returns:
            True if self is less than or equal to other, False otherwise.
        """
        return decimo.bigdecimal.comparison.compare(self, other) <= 0

    @always_inline
    def __eq__(self, other: Self) -> Bool:
        """Returns whether self equals other.

        Args:
            other: The value to compare against.

        Returns:
            True if the two values are equal, False otherwise.
        """
        return decimo.bigdecimal.comparison.compare(self, other) == 0

    @always_inline
    def __ne__(self, other: Self) -> Bool:
        """Returns whether self does not equal other.

        Args:
            other: The value to compare against.

        Returns:
            True if the two values are not equal, False otherwise.
        """
        return decimo.bigdecimal.comparison.compare(self, other) != 0

    # ===------------------------------------------------------------------=== #
    # Other dunders that implements traits
    # round
    # ===------------------------------------------------------------------=== #

    def __round__(self, ndigits: Int) -> Self:
        """Rounds the number to the specified number of decimal places.
        If `ndigits` is not given, rounds to 0 decimal places.
        If rounding causes errors, returns the value itself.

        Args:
            ndigits: The number of decimal places to round to.

        Returns:
            A new `BigDecimal` rounded to the specified decimal places.
        """
        try:
            return decimo.bigdecimal.rounding.round(
                self,
                ndigits=ndigits,
                rounding_mode=RoundingMode.half_even(),
            )
        except e:
            return self.copy()

    def __round__(self) -> Self:
        """Rounds the number to the specified number of decimal places.
        If `ndigits` is not given, rounds to 0 decimal places.
        If rounding causes errors, returns the value itself.

        Returns:
            A new `BigDecimal` rounded to 0 decimal places.
        """
        try:
            return decimo.bigdecimal.rounding.round(
                self, ndigits=0, rounding_mode=RoundingMode.half_even()
            )
        except e:
            return self.copy()

    # ===------------------------------------------------------------------=== #
    # Other dunders
    # ===------------------------------------------------------------------=== #

    def __ceil__(self) raises -> Self:
        """Returns the smallest integer value >= self.

        Equivalent to `math.ceil()` in Python. Returns a BigDecimal with
        scale 0.

        Returns:
            The ceiling of this value.
        """
        if self.scale <= 0:
            return self.copy()
        # Truncate toward zero first
        var truncated = decimo.bigdecimal.rounding.round(
            self, ndigits=0, rounding_mode=RoundingMode.down()
        )
        # If positive and there was a fractional part, add 1
        if not self.sign and truncated != self:
            return truncated + Self(1)
        return truncated^

    def __floor__(self) raises -> Self:
        """Returns the largest integer value <= self.

        Equivalent to `math.floor()` in Python. Returns a BigDecimal with
        scale 0.

        Returns:
            The floor of this value.
        """
        if self.scale <= 0:
            return self.copy()
        # Truncate toward zero first
        var truncated = decimo.bigdecimal.rounding.round(
            self, ndigits=0, rounding_mode=RoundingMode.down()
        )
        # If negative and there was a fractional part, subtract 1
        if self.sign and truncated != self:
            return truncated - Self(1)
        return truncated^

    def __trunc__(self) raises -> Self:
        """Returns self truncated toward zero (removes fractional part).

        Equivalent to `math.trunc()` in Python. Returns a BigDecimal
        with scale 0.

        Returns:
            The truncated integer part of this value.
        """
        if self.scale <= 0:
            return self.copy()
        return decimo.bigdecimal.rounding.round(
            self, ndigits=0, rounding_mode=RoundingMode.down()
        )

    # ===------------------------------------------------------------------=== #
    # Mathematical methods that do not implement a trait (not a dunder)
    # ===------------------------------------------------------------------=== #

    # === Comparisons === #

    @always_inline
    def compare(self, other: Self) raises -> Int8:
        """Compares two BigDecimal numbers.
        See `comparison.compare()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            1 if self > other, 0 if equal, -1 if self < other.
        """
        return decimo.bigdecimal.comparison.compare(self, other)

    @always_inline
    def compare_absolute(self, other: Self) raises -> Int8:
        """Compares two BigDecimal numbers by absolute value.
        See `comparison.compare_absolute()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            1 if |self| > |other|, 0 if equal, -1 if |self| < |other|.
        """
        return decimo.bigdecimal.comparison.compare_absolute(self, other)

    # === Extrema === #

    @always_inline
    def max(self, other: Self) raises -> Self:
        """Returns the maximum of two BigDecimal numbers.

        Args:
            other: The value to compare against.

        Returns:
            The larger of the two values.
        """
        return decimo.bigdecimal.comparison.max(self, other)

    @always_inline
    def min(self, other: Self) raises -> Self:
        """Returns the minimum of two BigDecimal numbers.

        Args:
            other: The value to compare against.

        Returns:
            The smaller of the two values.
        """
        return decimo.bigdecimal.comparison.min(self, other)

    # === Constants === #

    @always_inline
    @staticmethod
    def pi(precision: Int) raises -> Self:
        """Returns the mathematical constant pi to the specified precision.

        Args:
            precision: The number of significant digits to compute.

        Returns:
            The value of π to the specified precision.
        """
        return decimo.bigdecimal.constants.pi(precision=precision)

    @always_inline
    @staticmethod
    def e(precision: Int) raises -> Self:
        """Returns the mathematical constant e to the specified precision.

        Args:
            precision: The number of significant digits to compute.

        Returns:
            The value of e to the specified precision.
        """
        return decimo.bigdecimal.exponential.exp(
            x=Self(BigUInt.one()), precision=precision
        )

    # === Exponentional operations === #

    @always_inline
    def exp(self, precision: Int = PRECISION) raises -> Self:
        """Returns the exponential of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The value of e raised to the power of self.
        """
        return decimo.bigdecimal.exponential.exp(self, precision)

    @always_inline
    def ln(self, precision: Int = PRECISION) raises -> Self:
        """Returns the natural logarithm of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The natural logarithm (base e) of this value.
        """
        return decimo.bigdecimal.exponential.ln(self, precision)

    @always_inline
    def ln(
        self,
        precision: Int,
        mut cache: decimo.bigdecimal.exponential.MathCache,
    ) raises -> Self:
        """Returns the natural logarithm using a cache for ln(2)/ln(1.25).

        Args:
            precision: The number of significant digits for the result.
            cache: The shared math constant cache for ln(2) and ln(1.25).

        Returns:
            The natural logarithm (base e) of this value.
        """
        return decimo.bigdecimal.exponential.ln(self, precision, cache)

    @always_inline
    def log(self, base: Self, precision: Int = PRECISION) raises -> Self:
        """Returns the logarithm of the BigDecimal number with the given base.

        Args:
            base: The logarithmic base.
            precision: The number of significant digits for the result.

        Returns:
            The logarithm of this value in the given base.
        """
        return decimo.bigdecimal.exponential.log(self, base, precision)

    @always_inline
    def log10(self, precision: Int = PRECISION) raises -> Self:
        """Returns the base-10 logarithm of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The base-10 logarithm of this value.
        """
        return decimo.bigdecimal.exponential.log10(self, precision)

    @always_inline
    def root(self, root: Self, precision: Int = PRECISION) raises -> Self:
        """Returns the root of the BigDecimal number.

        Args:
            root: The degree of the root (e.g. 2 for square root, 3 for cube root).
            precision: The number of significant digits for the result.

        Returns:
            The nth root of this value.
        """
        return decimo.bigdecimal.exponential.root(self, root, precision)

    @always_inline
    def sqrt(self, precision: Int = PRECISION) raises -> Self:
        """Returns the square root of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The square root of this value.
        """
        return decimo.bigdecimal.exponential.sqrt(self, precision)

    @always_inline
    def cbrt(self, precision: Int = PRECISION) raises -> Self:
        """Returns the cube root of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The cube root of this value.
        """
        return decimo.bigdecimal.exponential.cbrt(self, precision)

    @always_inline
    def power(self, exponent: Self, precision: Int = PRECISION) raises -> Self:
        """Returns the result of exponentiation with the given precision.
        See `exponential.power()` for more information.

        Args:
            exponent: The power to raise this value to.
            precision: The number of significant digits for the result.

        Returns:
            This value raised to the given exponent.
        """
        return decimo.bigdecimal.exponential.power(self, exponent, precision)

    # === Trigonometric operations === #
    @always_inline
    def sin(self, precision: Int = PRECISION) raises -> Self:
        """Returns the sine of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The sine of this value.
        """
        return decimo.bigdecimal.trigonometric.sin(self, precision)

    @always_inline
    def cos(self, precision: Int = PRECISION) raises -> Self:
        """Returns the cosine of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The cosine of this value.
        """
        return decimo.bigdecimal.trigonometric.cos(self, precision)

    @always_inline
    def tan(self, precision: Int = PRECISION) raises -> Self:
        """Returns the tangent of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The tangent of this value.
        """
        return decimo.bigdecimal.trigonometric.tan(self, precision)

    @always_inline
    def cot(self, precision: Int = PRECISION) raises -> Self:
        """Returns the cotangent of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The cotangent of this value.
        """
        return decimo.bigdecimal.trigonometric.cot(self, precision)

    @always_inline
    def csc(self, precision: Int = PRECISION) raises -> Self:
        """Returns the cosecant of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The cosecant of this value.
        """
        return decimo.bigdecimal.trigonometric.csc(self, precision)

    @always_inline
    def sec(self, precision: Int = PRECISION) raises -> Self:
        """Returns the secant of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The secant of this value.
        """
        return decimo.bigdecimal.trigonometric.sec(self, precision)

    @always_inline
    def arctan(self, precision: Int = PRECISION) raises -> Self:
        """Returns the arctangent of the BigDecimal number.

        Args:
            precision: The number of significant digits for the result.

        Returns:
            The arctangent of this value in radians.
        """
        return decimo.bigdecimal.trigonometric.arctan(self, precision)

    # === Arithmetic operations === #

    @always_inline
    def true_divide(
        self, other: Self, precision: Int = PRECISION
    ) raises -> Self:
        """Returns the result of true division of two BigDecimal numbers.
        See `arithmetics.true_divide()` for more information.

        Args:
            other: The divisor.
            precision: The number of significant digits for the result.

        Returns:
            The quotient of the division.
        """
        return decimo.bigdecimal.arithmetics.true_divide(self, other, precision)

    @always_inline
    def true_divide_inexact(
        self, other: Self, number_of_significant_digits: Int
    ) raises -> Self:
        """Returns the result of true division with inexact precision.
        See `arithmetics.true_divide_inexact()` for more information.

        Args:
            other: The divisor.
            number_of_significant_digits: The number of significant digits for the result.

        Returns:
            The quotient of the division with the specified significant digits.
        """
        return decimo.bigdecimal.arithmetics.true_divide_inexact(
            self, other, number_of_significant_digits
        )

    @always_inline
    def true_divide_inexact_by_uint32(
        self, y: UInt32, number_of_significant_digits: Int
    ) raises -> Self:
        """Returns the result of division by a small UInt32 integer.
        See `arithmetics.true_divide_inexact_by_uint32()` for more information.

        Args:
            y: The small unsigned integer divisor.
            number_of_significant_digits: The number of significant digits for the result.

        Returns:
            The quotient of dividing this value by the given `UInt32`.
        """
        return decimo.bigdecimal.arithmetics.true_divide_inexact_by_uint32(
            self, y, number_of_significant_digits
        )

    @always_inline
    def truncate_divide(self, other: Self) raises -> Self:
        """Returns the result of truncating division of two BigDecimal numbers.
        See `arithmetics.truncate_divide()` for more information.

        Args:
            other: The divisor.

        Returns:
            The integer quotient, truncated toward zero.
        """
        return decimo.bigdecimal.arithmetics.truncate_divide(self, other)

    # === Rounding operations === #

    @always_inline
    def round(
        self,
        ndigits: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Rounds the number to the specified number of decimal places.

        Args:
            ndigits: Number of decimal places to round to.
            rounding_mode: Rounding mode to use. Default is `ROUND_HALF_EVEN`.
                RoundingMode.ROUND_DOWN: Round down.
                RoundingMode.ROUND_UP: Round up.
                RoundingMode.ROUND_HALF_UP: Round half up.
                RoundingMode.ROUND_HALF_EVEN: Round half even.

        Notes:
            If `ndigits` is negative, the last `ndigits` digits of the integer part of
            the number will be dropped and the scale will be `ndigits`.
            Examples:
                round(123.456, 2) -> 123.46
                round(123.456, -1) -> 12E+1
                round(123.456, -2) -> 1E+2
                round(123.456, -3) -> 0E+3
                round(678.890, -3) -> 1E+3

        Returns:
            A new `BigDecimal` rounded to the specified decimal places.
        """
        return decimo.bigdecimal.rounding.round(self, ndigits, rounding_mode)

    @always_inline
    def round_to_precision(
        mut self,
        precision: Int,
        rounding_mode: RoundingMode,
        remove_extra_digit_due_to_rounding: Bool,
        fill_zeros_to_precision: Bool,
    ) raises:
        """Rounds the number to the specified precision in-place.

        Notes:

        Note that precision is the number of significant digits,
        not the number of decimal places. If you want to round to a
        specific number of decimal places, use `round()` instead.

        See `rounding.round_to_precision()` for more information.

        Args:
            precision: The number of significant digits to round to.
            rounding_mode: The rounding strategy to use.
            remove_extra_digit_due_to_rounding: Whether to remove an extra leading digit caused by rounding up.
            fill_zeros_to_precision: Whether to pad with trailing zeros to reach the target precision.
        """
        decimo.bigdecimal.rounding.round_to_precision(
            self,
            precision,
            rounding_mode,
            remove_extra_digit_due_to_rounding,
            fill_zeros_to_precision,
        )

    @always_inline
    def quantize(
        self,
        exp: Self,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Rounds this BigDecimal according to the scale of another BigDecimal.

        This method adjusts the scale (exponent) of this number to match the
        scale of `exp`, performing rounding if necessary. Unlike `round()`,
        which specifies the number of decimal places, `quantize()` uses the
        scale of another decimal as a template.

        Args:
            exp: A BigDecimal whose scale will be used as the target scale.
                The actual value of `exp` is ignored; only its scale matters.
            rounding_mode: The rounding mode to use. Default is ROUND_HALF_EVEN.

        Returns:
            A new BigDecimal with the same value (subject to rounding) and
            the same scale as `exp`.

        Examples:

        ```mojo
        from decimo import BigDecimal

        var x = BigDecimal("1.2345")

        # Use different scale templates
        print(x.quantize(BigDecimal("0.01")))   # "1.23" (scale=2)
        print(x.quantize(BigDecimal("0.1")))    # "1.2"  (scale=1)
        print(x.quantize(BigDecimal("1")))      # "1"    (scale=0)

        # Important: \"100\" and \"1E+2\" have different scales!
        print(x.quantize(BigDecimal("100")))    # "1"    (scale=0, same as above)
        print(x.quantize(BigDecimal("1E+2")))   # "0"    (scale=-2, rounds to hundreds)

        # Align currency amounts
        var price = BigDecimal("19.999")
        var cent = BigDecimal("0.01")
        print(price.quantize(cent))  # "20.00" (rounded to cents)
        ```

        Notes:
            See `decimo.bigdecimal.rounding.quantize()` for detailed examples
            and technical information.
        """
        return decimo.bigdecimal.rounding.quantize(self, exp, rounding_mode)

    def fma(self, a: Self, b: Self) raises -> Self:
        """Fused multiply-add: returns `self * a + b` with no intermediate
        rounding.

        Matches Python's `decimal.Decimal.fma(other, third)`.

        Because BigDecimal multiplication and addition are both exact
        (no precision loss), this method is semantically equivalent to
        `self * a + b`.  It is provided for IEEE 754 / Python `Decimal`
        API compatibility and to express intent clearly in numerical
        algorithms.

        Args:
            a: The value to multiply by.
            b: The value to add after multiplication.

        Returns:
            The exact result of `self * a + b`.

        Examples:

        ```
        BigDecimal("2").fma(BigDecimal("3"), BigDecimal("4"))    # 10 (2*3+4)
        BigDecimal("1.5").fma(BigDecimal("2"), BigDecimal("0.1"))  # 3.1
        ```
        """
        return self * a + b

    # ===------------------------------------------------------------------=== #
    # Other methods
    # ===------------------------------------------------------------------=== #

    def adjusted(self) -> Int:
        """Returns the adjusted exponent.

        This is the exponent of the number when written with a single leading
        digit in scientific notation.  Equivalently,
        `as_tuple_exponent + number_of_digits - 1` where `as_tuple_exponent`
        is `-scale`.

        For zero, the adjusted exponent is always 0 regardless of scale,
        matching Python's behavior.

        Examples:

        ```
        BigDecimal("123.45").adjusted()   # 2   (1.2345E+2)
        BigDecimal("0.00123").adjusted()  # -3  (1.23E-3)
        BigDecimal("100").adjusted()      # 2   (1E+2)
        BigDecimal("1").adjusted()        # 0   (1E0)
        BigDecimal("0.00").adjusted()     # 0   (zero has no order of magnitude)
        ```

        Returns:
            The adjusted exponent of this number.
        """
        if self.coefficient.is_zero():
            return 0
        return self.coefficient.number_of_digits() - 1 - self.scale

    def as_tuple(self) -> Tuple[Bool, List[UInt8], Int]:
        """Returns a 3-tuple `(sign, digits, exponent)`.

        The components are:
        - `sign`: `False` for positive/zero, `True` for negative.
        - `digits`: each decimal digit of the coefficient as a `UInt8` in 0–9,
          most-significant first. Equivalent to Python's `digits` tuple.
        - `exponent`: `-scale`, i.e. the power of 10 such that
          `value = coefficient × 10^exponent`. Negative exponent means digits
          after the decimal point; positive means trailing zeros.

        Returns:
            `Tuple[Bool, List[UInt8], Int]`

        Examples:

        ```
        var sign, digits, exp = BigDecimal("7.25").as_tuple()
        # sign=False, digits=[7, 2, 5], exp=-2
        # => 7.25 matches Python: Decimal("7.25").as_tuple()
        #    -> DecimalTuple(sign=0, digits=(7, 2, 5), exponent=-2)

        var sign, digits, exp = BigDecimal("-0.001").as_tuple()
        # sign=True, digits=[1], exp=-3

        var sign, digits, exp = BigDecimal("1E+5").as_tuple()
        # sign=False, digits=[1], exp=5
        ```

        Notes:

        To reconstruct the value from the tuple, join the digits into a
        coefficient string, parse as BigUInt, then apply sign and exponent.

        This method is designed to match Python's `decimal.Decimal.as_tuple()`
        output, except that the `digits` are returned as a `List[UInt8]`
        instead of a `Tuple[int]` for better performance in Mojo.
        """
        var coef_str = self.coefficient.to_string()
        var cb = StringSlice(coef_str).as_bytes()
        var n = len(cb)
        var ptr = cb.unsafe_ptr()
        var digits = List[UInt8](capacity=n)
        for i in range(n):
            digits.append(ptr[i] - 48)  # 48 == ord('0')
        return (self.sign, digits^, -self.scale)

    @always_inline
    def copy_abs(self) -> Self:
        """Returns a copy with the sign set to positive.

        Equivalent to `abs(self)`. Matches Python's
        `decimal.Decimal.copy_abs()`.

        Returns:
            A copy of this number with positive sign.
        """
        return self.__abs__()

    @always_inline
    def copy_negate(self) -> Self:
        """Returns a copy with the sign inverted.

        Equivalent to `-self`. Matches Python's
        `decimal.Decimal.copy_negate()`.

        Returns:
            A copy of this number with the opposite sign.
        """
        return self.__neg__()

    @always_inline
    def copy_sign(self, other: Self) -> Self:
        """Returns a copy of `self` with the sign of `other`.

        Matches Python's `decimal.Decimal.copy_sign(other)`.

        Args:
            other: The BigDecimal whose sign to copy.

        Returns:
            A copy of this number with the sign taken from `other`.
        """
        return Self(
            coefficient=self.coefficient,
            scale=self.scale,
            sign=other.sign,
        )

    @always_inline
    def same_quantum(self, other: Self) -> Bool:
        """Returns True if both operands have the same scale (exponent).

        Matches Python's `decimal.Decimal.same_quantum(other)`.  Two numbers
        are in the same quantum when they have the same scale, meaning they
        are expressed with the same number of decimal places.

        Args:
            other: The BigDecimal to compare quantum with.

        Examples:

        ```
        BigDecimal("1.23").same_quantum(BigDecimal("4.56"))   # True  (both scale=2)
        BigDecimal("1.2").same_quantum(BigDecimal("4.56"))    # False (scale 1 vs 2)
        BigDecimal("100").same_quantum(BigDecimal("1"))       # True  (both scale=0)
        ```

        Returns:
            True if both values have the same scale, False otherwise.
        """
        return self.scale == other.scale

    @always_inline
    def scaleb(self, n: Int) -> Self:
        """Multiplies the value by 10^n by adjusting the scale.

        Matches Python's `decimal.Decimal.scaleb(other)`.  The name
        comes from the IEEE 754 "scaleB" (scale Binary/Base) operation.

        This operation is O(1) — it only changes the exponent without
        touching the coefficient digits.

        Args:
            n: The power of ten to scale by.  Positive values make the
                number larger, negative values make it smaller.

        Returns:
            A new BigDecimal whose value is `self * 10^n`.

        Examples:

        ```
        BigDecimal("1.23").scaleb(2)   # 123
        BigDecimal("1.23").scaleb(-2)  # 0.0123
        BigDecimal("100").scaleb(-1)   # 10
        ```
        """
        var result = self.copy()
        result.scale -= n
        return result^

    def extend_precision(self, precision_diff: Int) -> Self:
        """Returns a number with additional decimal places (trailing zeros).
        This multiplies the coefficient by 10^precision_diff and increases
        the scale accordingly, preserving the numeric value.
        If `precision_diff` is negative, nothing is done and the
        original number is returned.

        Args:
            precision_diff: The number of decimal places to add, which must be
                non-negative.

        Returns:
            A new BigDecimal with increased precision.

        Notes:

        In debug mode, negative `precision_diff` raises an assertion error.

        Examples:

        ```
        print(BigDecimal("123.456").extend_precision(5))  # Output: 123.45600000
        print(BigDecimal("123456").extend_precision(3))  # Output: 123456.000
        print(BigDecimal("123456").extend_precision(-1))  # Output: 123456 (no change)
        ```
        """
        debug_assert(
            precision_diff >= 0,
            "bigdecimal.BigDecimal.extend_precision(): ",
            "precision_diff must be non-negative, got: ",
            precision_diff,
        )

        if precision_diff <= 0:
            return self.copy()

        return Self(
            decimo.biguint.arithmetics.multiply_by_power_of_ten(
                self.coefficient, precision_diff
            ),
            self.scale + precision_diff,
            self.sign,
        )

    def extend_precision_inplace(mut self, precision_diff: Int):
        """Add additional decimal places (trailing zeros) in-place.
        This multiplies the coefficient by 10^precision_diff and increases
        the scale accordingly, preserving the numeric value.
        If `precision_diff` is negative, nothing is done and the
        original number is returned.

        Args:
            precision_diff: The number of decimal places to add, which must be
                non-negative.

        Notes:

        In debug mode, negative `precision_diff` raises an assertion error.

        Examples:
        ```
        BigDecimal("123.456).extend_precision_inplace(5)  # Output: 123.45600000
        BigDecimal("123456").extend_precision_inplace(3)  # Output: 123456.000
        BigDecimal("123456").extend_precision_inplace(-1)  # Output: 123456 (no change)
        ```
        """
        debug_assert(
            precision_diff >= 0,
            "bigdecimal.BigDecimal.extend_precision(): ",
            "precision_diff must be non-negative, got: ",
            precision_diff,
        )

        if precision_diff <= 0:
            return

        decimo.biguint.arithmetics.multiply_inplace_by_power_of_ten(
            self.coefficient, precision_diff
        )
        self.scale += precision_diff

    def internal_representation(self) -> String:
        """Returns the internal representation of the BigDecimal as a String.

        Returns:
            A formatted string showing the coefficient, scale, sign, and words.
        """
        # Collect all labels to find max width
        var fixed_labels = List[String]()
        fixed_labels.append("number:")
        fixed_labels.append("coefficient:")
        fixed_labels.append("negative:")
        fixed_labels.append("scale:")
        var max_label_len = 0
        for i in range(len(fixed_labels)):
            if len(fixed_labels[i]) > max_label_len:
                max_label_len = len(fixed_labels[i])
        for i in range(len(self.coefficient.words)):
            var label_len = len("word :") + len(String(i))
            if label_len > max_label_len:
                max_label_len = label_len

        var col = max_label_len + 4  # 4 spaces after longest label
        var value_width = 30
        var sep_line = String("-") * (col + value_width)

        var result = String("\nInternal Representation Details of BigDecimal\n")
        result += sep_line + "\n"

        # number line
        var string_of_number = self.to_string(line_width=value_width).split(
            "\n"
        )
        result += "number:" + String(" ") * (col - len("number:"))
        for i in range(len(string_of_number)):
            if i > 0:
                result += String(" ") * col
            result += string_of_number[i] + "\n"

        # coefficient line
        var string_of_coefficient = self.coefficient.to_string(
            line_width=value_width
        ).split("\n")
        var coeff_label = String("coefficient:")
        result += coeff_label + String(" ") * (col - len(coeff_label))
        for i in range(len(string_of_coefficient)):
            if i > 0:
                result += String(" ") * col
            result += string_of_coefficient[i] + "\n"

        # negative line
        result += "negative:" + String(" ") * (col - len("negative:"))
        result += String(self.sign) + "\n"

        # scale line
        result += "scale:" + String(" ") * (col - len("scale:"))
        result += String(self.scale) + "\n"

        # word lines
        for i in range(len(self.coefficient.words)):
            var label = "word " + String(i) + ":"
            result += label + String(" ") * (col - len(label))
            result += (
                decimo.str.rjust(
                    String(self.coefficient.words[i]), 9, fillchar="0"
                )
                + "\n"
            )

        result += sep_line
        return result^

    def print_internal_representation(self):
        """Prints the internal representation of the BigDecimal."""
        print(self.internal_representation())

    def print_representation_as_components(self):
        """Prints the representation of the BigDecimal as components."""
        print(
            (
                "BigDecimal(\n    coefficient=BigUInt(\n       "
                " words=List[UInt32](\n            "
            ),
            end="",
        )
        ref words = self.coefficient.words
        for i in range(len(words)):
            if i != len(words) - 1:
                print(words[i], end=",\n            ")
            else:
                print(words[i], end=",\n        ),\n    ),\n")
        print(
            "    scale=",
            self.scale,
            ",\n    sign=",
            self.sign,
            ")",
            sep="",
        )

    def is_integer(self) -> Bool:
        """Returns True if this number represents an integer value.

        Returns:
            True if there is no fractional part, False otherwise.
        """
        var number_of_trailing_zeros = self.number_of_trailing_zeros()
        if number_of_trailing_zeros >= self.scale:
            return True
        else:
            return False

    @always_inline
    def is_negative(self) -> Bool:
        """Returns True if this number represents a negative value.

        Returns:
            True if negative, False otherwise.
        """
        return self.sign

    @always_inline
    def is_positive(self) -> Bool:
        """Returns True if this number represents a strictly positive value.

        Returns:
            True if strictly positive, False otherwise.
        """
        return not self.sign and not self.coefficient.is_zero()

    def is_odd(self) raises -> Bool:
        """Returns True if this number represents an odd value.

        Returns:
            True if the integer part is odd, False otherwise.
        """
        if self.scale < 0:
            return False

        var cutoff_digit = self.coefficient.ith_digit(self.scale)
        if cutoff_digit % 2 == 0:
            return False
        else:
            return True

    def is_one(self) raises -> Bool:
        """Returns True if this number represents one.

        Returns:
            True if the value equals 1, False otherwise.
        """
        if self.sign:
            return False
        if self.scale < 0:
            return False
        var number_of_digits = self.coefficient.number_of_digits()
        if number_of_digits - self.scale != 1:
            return False
        if number_of_digits - self.number_of_trailing_zeros() != 1:
            return False
        if self.coefficient.ith_digit(self.scale) != 1:
            return False
        return True

    @always_inline
    def is_zero(self) -> Bool:
        """Returns True if this number represents zero.

        Returns:
            True if the value equals 0, False otherwise.
        """
        return self.coefficient.is_zero()

    def normalize(self) raises -> Self:
        """Removes trailing zeros from coefficient while adjusting scale.

        For example,
        1.2345000 (coefficient = 123450000, scale = 7) is normalized to
        1.2345 (coefficient = 12345, scale = 4).

        Notes:

        Only call it when necessary. Do not normalize after every operation.
        The information conveyed by trailing zeros in the coefficient may be
        useful for some applications, as it indicates the precision of the
        number. Normalization may cause loss of this information.

        Returns:
            A new `BigDecimal` with trailing zeros removed.
        """
        if self.coefficient.is_zero():
            return Self(BigUInt(raw_words=[0]), 0, False)

        var number_of_digits_to_remove = self.number_of_trailing_zeros()

        var number_of_words_to_remove = number_of_digits_to_remove // 9
        var number_of_remaining_digits_to_remove = (
            number_of_digits_to_remove % 9
        )

        words = List[UInt32](self.coefficient.words[number_of_words_to_remove:])
        var coefficient = BigUInt(raw_words=words^)

        if number_of_remaining_digits_to_remove == 0:
            pass
        elif number_of_remaining_digits_to_remove == 1:
            coefficient = coefficient // BigUInt(raw_words=[UInt32(10)])
        elif number_of_remaining_digits_to_remove == 2:
            coefficient = coefficient // BigUInt(raw_words=[UInt32(100)])
        elif number_of_remaining_digits_to_remove == 3:
            coefficient = coefficient // BigUInt(raw_words=[UInt32(1_000)])
        elif number_of_remaining_digits_to_remove == 4:
            coefficient = coefficient // BigUInt(raw_words=[UInt32(10_000)])
        elif number_of_remaining_digits_to_remove == 5:
            coefficient = coefficient // BigUInt(raw_words=[UInt32(100_000)])
        elif number_of_remaining_digits_to_remove == 6:
            coefficient = coefficient // BigUInt(raw_words=[UInt32(1_000_000)])
        elif number_of_remaining_digits_to_remove == 7:
            coefficient = coefficient // BigUInt(raw_words=[UInt32(10_000_000)])
        else:  # number_of_remaining_digits_to_remove == 8
            coefficient = coefficient // BigUInt(
                raw_words=[UInt32(100_000_000)]
            )

        return Self(
            coefficient,
            self.scale - number_of_digits_to_remove,
            self.sign,
        )

    def number_of_trailing_zeros(self) -> Int:
        """Returns the number of trailing zeros in the coefficient.

        Returns:
            The count of trailing zero digits.
        """
        if self.coefficient.is_zero():
            return 0

        # Count trailing zero words
        var number_of_zero_words = 0
        while self.coefficient.words[number_of_zero_words] == UInt32(0):
            number_of_zero_words += 1

        # Count trailing zeros in the last non-zero word
        var number_of_trailing_zeros = 0
        var last_non_zero_word = self.coefficient.words[number_of_zero_words]
        while (last_non_zero_word % UInt32(10)) == 0:
            last_non_zero_word = last_non_zero_word // UInt32(10)
            number_of_trailing_zeros += 1

        return number_of_zero_words * 9 + number_of_trailing_zeros

    def number_of_digits(self) -> Int:
        """Returns the total number of digits in the coefficient.

        This counts all digits stored in the coefficient, including any
        trailing zeros that were explicitly provided (e.g. `"1.0000"` has 5).
        Equivalent to `len(coefficient_as_string)`.

        Examples:

        ```
        BigDecimal("123.456").number_of_digits()   # 6
        BigDecimal("0.00123").number_of_digits()   # 3
        BigDecimal("100.00").number_of_digits()    # 5  (trailing zeros in fractional part)
        BigDecimal("100").number_of_digits()       # 3
        ```

        Returns:
            The total count of decimal digits in the coefficient.
        """
        return self.coefficient.number_of_digits()


# ===----------------------------------------------------------------------=== #
# Module-level helpers
# ===----------------------------------------------------------------------=== #


def _insert_digit_separators(s: String, delimiter: String) -> String:
    """Insert ``delimiter`` every 3 digits in both the integer and
    fractional parts of a numeric string.

    The function is aware of an optional leading ``-`` sign and a trailing
    exponent suffix (``E+3``, ``E-12``, …).  Only the mantissa digits are
    grouped; the sign and exponent are preserved verbatim.

    Examples (with ``delimiter = "_"``):
      ``"1234567"``          → ``"1_234_567"``
      ``"1234567.891011"``   → ``"1_234_567.891_011"``
      ``"12.345678E+6"``     → ``"12.345_678E+6"``
      ``"-0.00123"``         → ``"-0.001_23"``
    """
    if not delimiter:
        return s

    var sb = StringSlice(s).as_bytes()
    var n = len(sb)
    var ptr = sb.unsafe_ptr()

    # Locate optional leading minus (ASCII 45)
    var start = 0
    if n > 0 and ptr[0] == 45:
        start = 1

    # Locate optional exponent suffix 'E' (ASCII 69)
    var e_pos = n  # points past end if no 'E'
    for i in range(start, n):
        if ptr[i] == 69:
            e_pos = i
            break

    # Locate optional decimal point '.' (ASCII 46) within the mantissa
    var dot_pos = -1
    for i in range(start, e_pos):
        if ptr[i] == 46:
            dot_pos = i
            break

    # Determine integer-part and fractional-part ranges within `s`
    var int_end = dot_pos if dot_pos >= 0 else e_pos
    var int_part = String(s[byte=start:int_end])

    var frac_part = String("")
    if dot_pos >= 0:
        frac_part = String(s[byte = dot_pos + 1 : e_pos])

    # --- Group integer part (right-to-left every 3 digits) ---
    var int_len = len(int_part)
    if int_len > 3:
        var blocks = List[String](capacity=int_len // 3 + 1)
        var end_i = int_len
        var start_i = end_i - 3
        while start_i > 0:
            blocks.append(String(int_part[byte=start_i:end_i]))
            end_i = start_i
            start_i = end_i - 3
        blocks.append(String(int_part[byte=0:end_i]))
        blocks.reverse()
        int_part = delimiter.join(blocks)

    # --- Group fractional part (left-to-right every 3 digits) ---
    var frac_len = len(frac_part)
    if frac_len > 3:
        var blocks = List[String](capacity=frac_len // 3 + 1)
        var i = 0
        while i + 3 < frac_len:
            blocks.append(String(frac_part[byte = i : i + 3]))
            i += 3
        blocks.append(String(frac_part[byte=i:]))
        frac_part = delimiter.join(blocks)

    # --- Rebuild ---
    var result = String(s[byte=:start])  # sign (if any)
    result += int_part
    if dot_pos >= 0:
        result += "."
        result += frac_part
    if e_pos < n:
        result += String(s[byte=e_pos:])  # exponent suffix
    return result^
