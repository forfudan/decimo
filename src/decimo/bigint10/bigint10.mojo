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

"""Implements basic object methods for the BigInt10 type.

This module contains the basic object methods for the BigInt10 type.
These methods include constructors, life time methods, output dunders,
type-transfer dunders, basic arithmetic operation dunders, comparison
operation dunders, and other dunders that implement traits, as well as
mathematical methods that do not implement a trait.
"""

from std.memory import UnsafePointer
from std.python import PythonObject

import decimo.bigint10.arithmetics as bigint10_arithmetics
import decimo.bigint10.comparison as bigint10_comparison
import decimo.biguint.arithmetics as biguint_arithmetics
from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.biguint.biguint import BigUInt
from decimo.errors import (
    ValueError,
    OverflowError,
    ConversionError,
    ZeroDivisionError,
)
import decimo.str as decimo_str


struct BigInt10(
    Absable,
    Comparable,
    Copyable,
    IntableRaising,
    Movable,
    Writable,
):
    """Represents a base-10 arbitrary-precision signed integer.

    Notes:

    Internal Representation:

    - A base-10 unsigned integer (BigUInt) for magnitude.
    - A Bool value for the sign.
    """

    var magnitude: BigUInt
    """The absolute value stored as a `BigUInt`."""
    var sign: Bool
    """The sign flag. `True` if negative, `False` if non-negative."""

    # ===------------------------------------------------------------------=== #
    # Constructors and life time dunder methods
    #
    # __init__(out self)
    # __init__(out self, empty: Bool)
    # __init__(out self, empty: Bool, capacity: Int)
    # __init__(out self, *words: UInt32, sign: Bool) raises
    # __init__(out self, value: Int) raises
    # __init__(out self, value: String) raises
    # ===------------------------------------------------------------------=== #

    def __init__(out self):
        """Initializes a BigInt10 with value 0."""
        self.magnitude = BigUInt()
        self.sign = False

    @implicit
    def __init__(out self, magnitude: BigUInt):
        """Constructs a BigInt10 from a BigUInt object.

        Args:
            magnitude: The `BigUInt` to construct from.
        """
        self.magnitude = magnitude.copy()
        self.sign = False

    def __init__(out self, magnitude: BigUInt, sign: Bool):
        """Initializes a BigInt10 from a BigUInt and a sign.

        Args:
            magnitude: The magnitude of the BigInt10.
            sign: The sign of the BigInt10.
        """
        self.magnitude = magnitude.copy()
        self.sign = sign

    def __init__(out self, var words: List[UInt32], sign: Bool) raises:
        """Initializes a BigInt10 from a list of UInt32 words and a sign.
        The BigInt10 constructed in this way is guaranteed to be valid.
        If the list is empty, the BigInt10 is initialized with value 0.
        If there are leading zero words, they are removed.
        If there are words greater than `999_999_999`, there is an error.

        Args:
            words: A list of UInt32 words representing the coefficient.
                Each UInt32 word represents digits ranging from 0 to 10^9 - 1.
                The words are stored in little-endian order.
            sign: The sign of the BigInt10.

        Raises:
            ConversionError: If any word exceeds 999_999_999.

        Notes:
            This is equal to `BigInt10.from_list()`.
        """
        try:
            self = Self.from_list(words^, sign=sign)
        except e:
            raise ConversionError(
                message="See the above exception.",
                function=(
                    "BigInt10.__init__(var words: List[UInt32], sign: Bool)"
                ),
                previous_error=e^,
            )

    def __init__(out self, *, var raw_words: List[UInt32], sign: Bool):
        """Initializes a BigInt10 from a list of raw words.

        Args:
            raw_words: A list of UInt32 words representing the coefficient.
                The words are stored in little-endian order.
            sign: The sign of the BigInt10.

        Notes:

        **UNSAFE**

        This way of initialization does not check whether the words are smaller
        than `999_999_999`, nor does it remove leading empty words.

        However, it always initializes a BigInt10 and makes sure that the words
        list is not empty.
        """

        self.magnitude = BigUInt(raw_words=raw_words^)
        self.sign = sign

    def __init__(out self, value: String) raises:
        """Initializes a BigInt10 from a string representation.
        See `from_string()` for more information.

        Args:
            value: The string representation of the integer.

        Raises:
            ConversionError: If the string cannot be parsed.
        """
        try:
            self = Self.from_string(value)
        except e:
            raise ConversionError(
                message="Cannot initialize BigInt10 from String.",
                function="BigInt10.__init__()",
                previous_error=e^,
            )

    # TODO: If Mojo makes Int type an alias of SIMD[DType.index, 1],
    # we can remove this method.
    @implicit
    def __init__(out self, value: Int):
        """Initializes a BigInt10 from an `Int` object.
        See `from_int()` for more information.

        Args:
            value: The integer value to convert.
        """
        self = Self.from_int(value)

    @implicit
    def __init__(out self, value: Scalar):
        """Constructs a BigInt10 from an integral scalar.
        This includes all SIMD integral types, such as Int8, Int16, UInt32, etc.

        Constraints:
            The dtype of the scalar must be integral.

        Args:
            value: The scalar value to convert.
        """
        self = Self.from_integral_scalar(value)

    def __init__(out self, *, py: PythonObject) raises:
        """Constructs a BigInt10 from a Python int object.

        Args:
            py: The Python integer object to convert from.

        Raises:
            ConversionError: If the Python object cannot be converted.
        """
        self = Self.from_python_int(py)

    # ===------------------------------------------------------------------=== #
    # Constructing methods that are not dunders
    #
    # from_words(*words: UInt32, sign: Bool) -> Self
    # from_int(value: Int) -> Self
    # from_string(value: String) -> Self
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def from_list(var words: List[UInt32], sign: Bool) raises -> Self:
        """Initializes a BigInt10 from a list of UInt32 words safely.
        If the list is empty, the BigInt10 is initialized with value 0.
        If there are leading zero words, they are removed.
        The words are validated to ensure they are smaller than `999_999_999`.

        Args:
            words: A list of UInt32 words representing the coefficient.
                Each UInt32 word represents digits ranging from 0 to 10^9 - 1.
                The words are stored in little-endian order.
            sign: The sign of the BigInt10.

        Raises:
            ConversionError: If any word exceeds 999_999_999.

        Returns:
            The BigInt10 representation of the list of UInt32 words.
        """
        try:
            return Self(BigUInt.from_list(words^), sign)
        except e:
            raise ConversionError(
                message="See the above exception.",
                function=(
                    "BigInt10.from_list(var words: List[UInt32], sign: Bool)"
                ),
                previous_error=e^,
            )

    @staticmethod
    def from_words(*words: UInt32, sign: Bool) raises -> Self:
        """Initializes a BigInt10 from raw words.

        Args:
            words: The UInt32 words representing the coefficient.
                Each UInt32 word represents digits ranging from 0 to 10^9 - 1.
                The words are stored in little-endian order.
            sign: The sign of the BigInt10.

        Notes:

        This method validates whether the words are smaller than `999_999_999`.

        Returns:
            A new `BigInt10` from the given words.

        Raises:
            ValueError: If any word exceeds 999_999_999.
        """

        var list_of_words = List[UInt32](capacity=len(words))

        # Check if the words are valid
        for word in words:
            if word > UInt32(999_999_999):
                raise ValueError(
                    message="Word value exceeds maximum value of 999_999_999",
                    function="BigInt10.__init__()",
                )
            else:
                list_of_words.append(word)

        return Self(BigUInt(raw_words=list_of_words^), sign)

    @staticmethod
    def from_int(value: Int) -> Self:
        """Creates a BigInt10 from an integer.

        Args:
            value: The integer value to convert.

        Returns:
            A new `BigInt10` from the given integer.
        """
        if value == 0:
            return Self()

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
            quotient = remainder // BigUInt.BASE
            remainder = remainder % BigUInt.BASE
            words.append(UInt32(remainder))
            remainder = quotient

        if is_min:
            words[0] += 1

        return Self(BigUInt(raw_words=words^), sign)

    @staticmethod
    def from_integral_scalar[dtype: DType, //](value: SIMD[dtype, 1]) -> Self:
        """Initializes a BigInt10 from an integral scalar.
        This includes all SIMD integral types, such as Int8, Int16, UInt32, etc.

        Constraints:
            The dtype must be integral.

        Args:
            value: The Scalar value to be converted to BigInt10.

        Returns:
            The BigInt10 representation of the Scalar value.

        Parameters:
            dtype: The data type of the input scalar.
        """

        comptime assert dtype.is_integral(), "dtype must be integral."

        if value == 0:
            return Self()

        return Self(
            magnitude=BigUInt.from_absolute_integral_scalar(value),
            sign=True if value < 0 else False,
        )

    @staticmethod
    def from_string(value: String) raises -> Self:
        """Initializes a BigInt10 from a string representation.
        The string is normalized with `decimo_str.parse_numeric_string()`.

        Args:
            value: The string representation of the BigInt10.

        Returns:
            The BigInt10 representation of the string.

        Raises:
            ConversionError: If the string cannot be parsed.
        """
        try:
            _tuple = decimo_str.parse_numeric_string(value)
        except e:
            raise ConversionError(
                function="BigInt10.from_string(value: String)",
                message=(
                    'The input value "'
                    + value
                    + '" cannot be parsed as an integer.\n'
                    + String(e)
                ),
            )
        var ref coef: List[UInt8] = _tuple[0]
        var sign: Bool = _tuple[2]

        # Check if the number is zero
        if len(coef) == 1 and coef[0] == UInt8(0):
            return Self(UInt32(0), sign=False)

        magnitude = BigUInt.from_string(value, ignore_sign=True)

        return Self(magnitude=magnitude^, sign=sign)

    @staticmethod
    def from_python_int(value: PythonObject) raises -> Self:
        """Initializes a BigInt10 from a Python integer object.

        Args:
            value: A Python integer object (PythonObject).

        Returns:
            The BigInt10 representation of the Python integer.

        Raises:
            ConversionError: If the conversion from Python int fails.

        Examples:
        ```mojo
        from std.python import Python
        from decimo.bigint10.bigint10 import BigInt10

        def main() raises:
            var py = Python.import_module("builtins")
            var py_int = py.int("123456789012345678901234567890")
            var mojo_bigint = BigInt10.from_python_int(py_int)
            print(mojo_bigint)  # 123456789012345678901234567890
        ```
        End of examples.

        Notes:
        This method converts the Python integer to a string representation
        using Python's `str()` function, then uses `BigInt10.from_string()`
        to parse it. This approach handles arbitrarily large Python integers
        since Python's int type is already arbitrary-precision.
        """
        try:
            # Convert Python int to string using Python's str() function
            var py_str = String(value)
            # Use the existing from_string() method to parse the string
            return Self.from_string(py_str)
        except e:
            raise ConversionError(
                message="Failed to convert Python int to BigInt10.",
                function="BigInt10.from_python_int()",
                previous_error=e^,
            )

    # ===------------------------------------------------------------------=== #
    # Output dunders, type-transfer dunders
    # ===------------------------------------------------------------------=== #

    def __int__(self) raises -> Int:
        """Returns the number as Int.
        See `to_int()` for more information.

        Returns:
            The `Int` representation of this value.

        Raises:
            OverflowError: If the number exceeds the size of Int.
        """
        return self.to_int()

    def write_repr_to[W: Writer](self, mut writer: W):
        """Writes the debug representation to a writer.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        writer.write('BigInt10("', self.to_string(), '")')

    # ===------------------------------------------------------------------=== #
    # Type-transfer or output methods that are not dunders
    # ===------------------------------------------------------------------=== #

    def write_to[W: Writer](self, mut writer: W):
        """Writes the BigInt10 to a writer.
        This implement the `write` method of the `Writer` trait.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        writer.write(self.to_string())

    def to_int(self) raises -> Int:
        """Returns the number as Int.

        Returns:
            The number as Int.

        Raises:
            OverflowError: If the number exceeds the size of Int.
        """

        # 2^63-1 = 9_223_372_036_854_775_807
        # is larger than 10^18 -1 but smaller than 10^27 - 1

        if len(self.magnitude.words) > 3:
            raise OverflowError(
                message="The number exceeds the size of Int.",
                function="BigInt10.to_int()",
            )

        var value: Int128 = 0
        for i in range(len(self.magnitude.words)):
            value += (
                Int128(self.magnitude.words[i]) * Int128(1_000_000_000) ** i
            )

        value = -value if self.sign else value

        # Intermediate variables made due to a bug in Mojo compiler, see:
        # https://github.com/modular/modular/issues/5931
        # TODO: Remove these intermediate variables after the bug is fixed.
        var int_min = Int.MIN
        var int_max = Int.MAX
        if value < Int128(int_min) or value > Int128(int_max):
            raise OverflowError(
                message="The number exceeds the size of Int.",
                function="BigInt10.to_int()",
            )
        return Int(value)

    def to_string(self, line_width: Int = 0) -> String:
        """Returns string representation of the BigInt10.

        Args:
            line_width: The maximum line width for the string representation.
                Default is 0, which means no line width limit.

        Returns:
            The string representation of the BigInt10.
        """

        if self.magnitude.is_unitialized():
            return String("Unitilialized BigInt10")

        if self.is_zero():
            return String("0")

        var result = String("-") if self.sign else String("")
        result += self.magnitude.to_string()

        if line_width > 0:
            var start = 0
            var end = line_width
            var lines = List[String](
                capacity=result.byte_length() // line_width + 1
            )
            while end < result.byte_length():
                lines.append(String(result[byte=start:end]))
                start = end
                end += line_width
            lines.append(String(result[byte=start:]))
            result = String("\n").join(lines^)

        return result^

    def to_string_with_separators(self, separator: String = "_") -> String:
        """Returns string representation of the BigInt10 with separators.

        Args:
            separator: The separator string. Default is "_".

        Returns:
            The string representation of the BigInt10 with separators.
        """

        var result = self.to_string()
        var end = result.byte_length()
        var start = end - 3
        var blocks = List[String](capacity=result.byte_length() // 3 + 1)
        while start > 0:
            blocks.append(String(result[byte=start:end]))
            end = start
            start = end - 3
        blocks.append(String(result[byte=0:end]))
        blocks.reverse()
        result = separator.join(blocks)

        return result^

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
        return bigint10_arithmetics.absolute(self)

    @always_inline
    def __neg__(self) -> Self:
        """Returns the negation of this number.
        See `negative()` for more information.

        Returns:
            The negated value.
        """
        return bigint10_arithmetics.negative(self)

    # ===------------------------------------------------------------------=== #
    # Basic binary arithmetic operation dunders
    # These methods are called to implement the binary arithmetic operations
    # (+, -, *, @, /, //, %, divmod(), pow(), **, <<, >>, &, ^, |)
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __add__(self, other: Self) -> Self:
        """Adds two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The sum of the two values.
        """
        return bigint10_arithmetics.add(self, other)

    @always_inline
    def __sub__(self, other: Self) -> Self:
        """Subtracts two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The difference of the two values.
        """
        return bigint10_arithmetics.subtract(self, other)

    @always_inline
    def __mul__(self, other: Self) -> Self:
        """Multiplies two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The product of the two values.
        """
        return bigint10_arithmetics.multiply(self, other)

    @always_inline
    def __floordiv__(self, other: Self) raises -> Self:
        """Divides two values using floor division.

        Args:
            other: The right-hand side operand.

        Returns:
            The floor division quotient.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        try:
            return bigint10_arithmetics.floor_divide(self, other)
        except e:
            raise ZeroDivisionError(
                message="See the above exception.",
                function="BigInt10.__floordiv__()",
                previous_error=e^,
            )

    @always_inline
    def __mod__(self, other: Self) raises -> Self:
        """Returns the remainder of division.

        Args:
            other: The right-hand side operand.

        Returns:
            The remainder of the floor division.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        try:
            return bigint10_arithmetics.floor_modulo(self, other)
        except e:
            raise ZeroDivisionError(
                message="See the above exception.",
                function="BigInt10.__mod__()",
                previous_error=e^,
            )

    @always_inline
    def __pow__(self, exponent: Self) raises -> Self:
        """Raises to a power.

        Args:
            exponent: The exponent.

        Returns:
            The result of raising to the given power.

        Raises:
            OverflowError: If the exponent is too large.
        """
        return self.power(exponent)

    # ===------------------------------------------------------------------=== #
    # Basic binary right-side arithmetic operation dunders
    # These methods are called to implement the binary arithmetic operations
    # (+, -, *, @, /, //, %, divmod(), pow(), **, <<, >>, &, ^, |)
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __radd__(self, other: Self) -> Self:
        """Adds two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The sum of the two values.
        """
        return bigint10_arithmetics.add(self, other)

    @always_inline
    def __rsub__(self, other: Self) -> Self:
        """Subtracts two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The difference of the two values.
        """
        return bigint10_arithmetics.subtract(other, self)

    @always_inline
    def __rmul__(self, other: Self) -> Self:
        """Multiplies two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The product of the two values.
        """
        return bigint10_arithmetics.multiply(self, other)

    @always_inline
    def __rfloordiv__(self, other: Self) raises -> Self:
        """Divides two values using floor division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The floor division quotient.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint10_arithmetics.floor_divide(other, self)

    @always_inline
    def __rmod__(self, other: Self) raises -> Self:
        """Returns the remainder of division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The remainder of the floor division.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint10_arithmetics.floor_modulo(other, self)

    @always_inline
    def __rpow__(self, base: Self) raises -> Self:
        """Raises to a power (reflected).

        Args:
            base: The base to raise to this power.

        Returns:
            The result of raising to the given power.

        Raises:
            OverflowError: If the exponent is too large.
            ValueError: If the exponent is negative or too large.
        """
        return base.power(self)

    # ===------------------------------------------------------------------=== #
    # Basic binary augmented arithmetic assignments dunders
    # These methods are called to implement the binary augmented arithmetic
    # assignments
    # (+=, -=, *=, @=, /=, //=, %=, **=, <<=, >>=, &=, ^=, |=)
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __iadd__(mut self, other: Self):
        """Adds in place.

        Args:
            other: The right-hand side operand.
        """
        bigint10_arithmetics.add_inplace(self, other)

    @always_inline
    def __iadd__(mut self, other: Int):
        """Adds in place.

        Args:
            other: The right-hand side operand.
        """
        # Optimize the case `i += 1`
        if (self >= 0) and (other >= 0) and (other <= 999_999_999):
            biguint_arithmetics.add_by_uint32_inplace(
                self.magnitude, UInt32(other)
            )
        else:
            bigint10_arithmetics.add_inplace(self, Self(other))

    @always_inline
    def __isub__(mut self, other: Self):
        """Subtracts in place.

        Args:
            other: The right-hand side operand.
        """
        self = bigint10_arithmetics.subtract(self, other)

    @always_inline
    def __imul__(mut self, other: Self):
        """Multiplies in place.

        Args:
            other: The right-hand side operand.
        """
        self = bigint10_arithmetics.multiply(self, other)

    @always_inline
    def __ifloordiv__(mut self, other: Self) raises:
        """Divides in place using floor division.

        Args:
            other: The right-hand side operand.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        self = bigint10_arithmetics.floor_divide(self, other)

    @always_inline
    def __imod__(mut self, other: Self) raises:
        """Computes the remainder in place.

        Args:
            other: The right-hand side operand.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        self = bigint10_arithmetics.floor_modulo(self, other)

    # ===------------------------------------------------------------------=== #
    # Basic binary comparison operation dunders
    # __gt__, __ge__, __lt__, __le__, __eq__, __ne__
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __gt__(self, other: Self) -> Bool:
        """Checks if this value is greater than `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self > other`, `False` otherwise.
        """
        return bigint10_comparison.greater(self, other)

    @always_inline
    def __gt__(self, other: Int) -> Bool:
        """Checks if this value is greater than `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self > other`, `False` otherwise.
        """
        return bigint10_comparison.greater(self, Self.from_int(other))

    @always_inline
    def __ge__(self, other: Self) -> Bool:
        """Checks if this value is greater than or equal to `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self >= other`, `False` otherwise.
        """
        return bigint10_comparison.greater_equal(self, other)

    @always_inline
    def __ge__(self, other: Int) -> Bool:
        """Checks if this value is greater than or equal to `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self >= other`, `False` otherwise.
        """
        return bigint10_comparison.greater_equal(self, Self.from_int(other))

    @always_inline
    def __lt__(self, other: Self) -> Bool:
        """Checks if this value is less than `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self < other`, `False` otherwise.
        """
        return bigint10_comparison.less(self, other)

    @always_inline
    def __lt__(self, other: Int) -> Bool:
        """Checks if this value is less than `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self < other`, `False` otherwise.
        """
        return bigint10_comparison.less(self, Self.from_int(other))

    @always_inline
    def __le__(self, other: Self) -> Bool:
        """Checks if this value is less than or equal to `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self <= other`, `False` otherwise.
        """
        return bigint10_comparison.less_equal(self, other)

    @always_inline
    def __le__(self, other: Int) -> Bool:
        """Checks if this value is less than or equal to `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self <= other`, `False` otherwise.
        """
        return bigint10_comparison.less_equal(self, Self.from_int(other))

    @always_inline
    def __eq__(self, other: Self) -> Bool:
        """Checks if this value is equal to `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self == other`, `False` otherwise.
        """
        return bigint10_comparison.equal(self, other)

    @always_inline
    def __eq__(self, other: Int) -> Bool:
        """Checks if this value is equal to `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self == other`, `False` otherwise.
        """
        return bigint10_comparison.equal(self, Self.from_int(other))

    @always_inline
    def __ne__(self, other: Self) -> Bool:
        """Checks if this value is not equal to `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self != other`, `False` otherwise.
        """
        return bigint10_comparison.not_equal(self, other)

    @always_inline
    def __ne__(self, other: Int) -> Bool:
        """Checks if this value is not equal to `other`.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self != other`, `False` otherwise.
        """
        return bigint10_comparison.not_equal(self, Self.from_int(other))

    # ===------------------------------------------------------------------=== #
    # Other dunders
    # ===------------------------------------------------------------------=== #

    def __merge_with__[other_type: type_of(BigDecimal)](self) -> BigDecimal:
        """Merges this BigInt10 with a BigDecimal into a BigDecimal.

        Parameters:
            other_type: The target type.

        Returns:
            A BigDecimal value.
        """
        return BigDecimal(self)

    # ===------------------------------------------------------------------=== #
    # Mathematical methods that do not implement a trait (not a dunder)
    # ===------------------------------------------------------------------=== #

    @always_inline
    def floor_divide(self, other: Self) raises -> Self:
        """Performs a floor division of two BigInts.
        See `floor_divide()` for more information.

        Args:
            other: The divisor.

        Returns:
            The floor division quotient.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint10_arithmetics.floor_divide(self, other)

    @always_inline
    def truncate_divide(self, other: Self) raises -> Self:
        """Performs a truncated division of two BigInts.
        See `truncate_divide()` for more information.

        Args:
            other: The divisor.

        Returns:
            The truncated division quotient.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint10_arithmetics.truncate_divide(self, other)

    @always_inline
    def floor_modulo(self, other: Self) raises -> Self:
        """Performs a floor modulo of two BigInts.
        See `floor_modulo()` for more information.

        Args:
            other: The divisor.

        Returns:
            The floor division remainder.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint10_arithmetics.floor_modulo(self, other)

    @always_inline
    def truncate_modulo(self, other: Self) raises -> Self:
        """Performs a truncated modulo of two BigInts.
        See `truncate_modulo()` for more information.

        Args:
            other: The divisor.

        Returns:
            The truncated division remainder.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint10_arithmetics.truncate_modulo(self, other)

    def power(self, exponent: Int) raises -> Self:
        """Raises the BigInt10 to the power of an integer exponent.
        See `power()` for more information.

        Args:
            exponent: The exponent.

        Returns:
            The result of raising to the given power.

        Raises:
            ValueError: If the exponent is negative or too large.
        """
        var magnitude = self.magnitude.power(exponent)
        var sign = False
        if self.sign:
            sign = exponent % 2 == 1
        return Self(magnitude^, sign)

    def power(self, exponent: Self) raises -> Self:
        """Raises the BigInt10 to the power of another BigInt10.
        See `power()` for more information.

        Args:
            exponent: The exponent.

        Returns:
            The result of raising to the given power.

        Raises:
            OverflowError: If the exponent is too large.
            ValueError: If the exponent is negative or too large.
        """
        if exponent > Self(BigUInt(raw_words=[0, 1]), sign=False):
            raise OverflowError(
                message="The exponent is too large.",
                function="BigInt10.power()",
            )
        var exponent_as_int = exponent.to_int()
        return self.power(exponent_as_int)

    @always_inline
    def compare_magnitudes(self, other: Self) -> Int8:
        """Compares the magnitudes of two BigInts.
        See `compare_magnitudes()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            1 if `self` magnitude is greater, -1 if less, 0 if equal.
        """
        return bigint10_comparison.compare_magnitudes(self, other)

    @always_inline
    def compare(self, other: Self) -> Int8:
        """Compares two BigInts.
        See `compare()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            1 if `self` is greater, -1 if less, 0 if equal.
        """
        return bigint10_comparison.compare(self, other)

    # ===------------------------------------------------------------------=== #
    # Other methods
    # ===------------------------------------------------------------------=== #

    @always_inline
    def is_zero(self) -> Bool:
        """Returns True if this BigInt10 represents zero.

        Returns:
            `True` if zero, `False` otherwise.
        """
        return self.magnitude.is_zero()

    @always_inline
    def is_one_or_minus_one(self) -> Bool:
        """Returns True if this BigInt10 represents one or negative one.

        Returns:
            `True` if the value is 1 or -1, `False` otherwise.
        """
        return self.magnitude.is_one()

    @always_inline
    def is_negative(self) -> Bool:
        """Returns True if this BigInt10 is negative.

        Returns:
            `True` if negative, `False` otherwise.
        """
        return self.sign

    @always_inline
    def number_of_words(self) -> Int:
        """Returns the number of words in the BigInt10.

        Returns:
            The number of internal words.
        """
        return len(self.magnitude.words)

    # ===------------------------------------------------------------------=== #
    # Internal methods
    # ===------------------------------------------------------------------=== #

    def internal_representation(self) raises -> String:
        """Returns the internal representation details as a String.

        Returns:
            A formatted string showing the internal representation.

        Raises:
            Error: Propagated from string formatting / write operations.
        """
        # Collect all labels to find max width
        var max_label_len = "number:".byte_length()
        for i in range(len(self.magnitude.words)):
            var label_len = "word :".byte_length() + String(i).byte_length()
            if label_len > max_label_len:
                max_label_len = label_len

        var col = max_label_len + 4  # 4 spaces after longest label
        var value_width = 30
        var sep_line = String("-") * (col + value_width)

        var result = String("\nInternal Representation Details of BigInt10\n")
        result += sep_line + "\n"

        # number line
        var string_of_number = self.to_string(line_width=value_width).split(
            "\n"
        )
        result += "number:" + String(" ") * (col - "number:".byte_length())
        for i in range(len(string_of_number)):
            if i > 0:
                result += String(" ") * col
            result += string_of_number[i] + "\n"

        # word lines
        for i in range(len(self.magnitude.words)):
            var label = "word " + String(i) + ":"
            result += label + String(" ") * (col - label.byte_length())
            result += (
                decimo_str.rjust(
                    String(self.magnitude.words[i]), 9, fillchar="0"
                )
                + "\n"
            )

        result += sep_line
        return result^

    def print_internal_representation(self) raises:
        """Prints the internal representation details of a BigInt10.

        Raises:
            Error: Propagated from string formatting / write operations.
        """
        print(self.internal_representation())
