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

"""Implements basic object methods for the BigUInt type.

This module contains the basic object methods for the BigUInt type.
These methods include constructors, life time methods, output dunders,
type-transfer dunders, basic arithmetic operation dunders, comparison
operation dunders, and other dunders that implement traits, as well as
mathematical methods that do not implement a trait.
"""

from std.memory import UnsafePointer, memcpy, memcmp

from decimo.bigint10.bigint10 import BigInt10
import decimo.biguint.arithmetics
import decimo.biguint.comparison
from decimo.errors import (
    ConversionError,
    ValueError,
    IndexError,
    OverflowError,
    ZeroDivisionError,
)
import decimo.str

# Type aliases
comptime BUInt = BigUInt
"""A shorthand alias for `BigUInt`."""


struct BigUInt(Absable, Copyable, IntableRaising, Movable, Writable):
    """Represents a base-10 arbitrary-precision unsigned integer.

    Notes:

    Internal Representation:

    Use base-10^9 (base-billion) representation for the unsigned integer.
    BigUInt uses a dynamic structure in memory, which contains:
    An pointer to an array of UInt32 words for the coefficient on the heap,
    which can be of arbitrary length stored in little-endian order.
    Each UInt32 word represents digits ranging from 0 to 10^9 - 1.

    The value of the BigUInt is calculated as follows:

    x = x[0] * 10^0 + x[1] * 10^9 + x[2] * 10^18 + ... x[n] * 10^(9n)

    You can think of the BigUInt as a list base-billion digits, where each
    digit is ranging from 0 to 999_999_999. Depending on the context, the
    following terms are used interchangeably:
    (1) words,
    (2) limbs,
    (3) base-billion digits.
    """

    var words: List[UInt32]
    """A list of UInt32 words representing the coefficient."""

    # ===------------------------------------------------------------------=== #
    # Constants
    # ===------------------------------------------------------------------=== #

    # TODO: Make these constants global, e.g., decimo.biguint.BASE
    comptime BASE = 1_000_000_000
    """The base used for the BigUInt representation."""
    comptime BASE_MAX = 999_999_999
    """The maximum value of a single word in the BigUInt representation."""
    comptime BASE_HALF = 500_000_000
    """Half of the base used for the BigUInt representation."""
    comptime VECTOR_WIDTH = 4
    """The width of the SIMD vector used for arithmetic operations (128-bit)."""

    comptime ZERO = Self.zero()
    """A `BigUInt` constant representing zero."""
    comptime ONE = Self.one()
    """A `BigUInt` constant representing one."""
    comptime MAX_UINT64 = Self(raw_words=[709551615, 446744073, 18])
    """A `BigUInt` constant representing the maximum value of `UInt64`."""
    comptime MAX_UINT128 = Self(
        raw_words=[768211455, 374607431, 938463463, 282366920, 340]
    )
    """A `BigUInt` constant representing the maximum value of `UInt128`."""

    @always_inline
    @staticmethod
    def zero() -> Self:
        """Returns a BigUInt with value 0.

        Returns:
            A `BigUInt` with value 0.
        """
        return Self()

    @always_inline
    @staticmethod
    def one() -> Self:
        """Returns a BigUInt with value 1.

        Returns:
            A `BigUInt` with value 1.
        """
        return Self(raw_words=[UInt32(1)])

    @staticmethod
    @always_inline
    def power_of_10(exponent: Int) raises -> Self:
        """Calculates 10^exponent efficiently.

        Args:
            exponent: The power of 10 to compute.

        Returns:
            A `BigUInt` representing 10 raised to the power of `exponent`.
        """
        return decimo.biguint.arithmetics.power_of_10(exponent)

    # ===------------------------------------------------------------------=== #
    # Constructors and life time dunder methods
    #
    # __init__(out self)
    # __init__(out self, var words: List[UInt32])
    # __init__(out self, var *words: UInt32)
    # __init__(out self, value: Int) raises
    # __init__(out self, value: Scalar) raises
    # __init__(out self, value: String, ignore_sign: Bool = False) raises
    # ===------------------------------------------------------------------=== #

    def __init__(out self):
        """Initializes to zero by default."""
        self.words = [UInt32(0)]

    def __init__(out self, *, uninitialized_capacity: Int):
        """Creates an uninitialized BigUInt with a given capacity.

        Args:
            uninitialized_capacity: The capacity of the BigUInt.
                This is the number of UInt32 words that can be stored in the
                BigUInt without reallocating memory.

        Notes:

        **UNSAFE**

        The words of the BigUInt is an empty list with the specified capacity.
        This allows us to create an uninitialized BigUInt and append the words
        later without worrying about memory allocation.

        The length of the words list is 0. So you cannot access the words using
        indexing until you append the words to the list.
        """
        self.words = List[UInt32](capacity=uninitialized_capacity)

    def __init__(out self, *, unsafe_uninit_length: Int):
        """Creates an uninitialized BigUInt with a given length.

        Args:
            unsafe_uninit_length: The length of the BigUInt.

        Notes:

        **UNSAFE**

        The words of the BigUInt is an uninitialized list with the specified
        length. This allows to create an uninitialized BigUInt and set the words
        later without worrying about memory allocation.

        The length of the BigUInt is `unsafe_uninit_length`, so as the capacity.
        Because the list is uninitialized, the elements may be any value at the
        time of initialization. You can access the words using indexing.
        """
        self.words = List[UInt32](unsafe_uninit_length=unsafe_uninit_length)

    def __init__(out self, var words: List[UInt32]) raises:
        """Initializes a BigUInt from a list of UInt32 words.
        The BigUInt constructed in this way is guaranteed to be valid.
        If the list is empty, the BigUInt is initialized with value 0.
        If there are leading zero words, they are removed.
        If there are words greater than `999_999_999`, there is an error.

        Args:
            words: A list of UInt32 words representing the coefficient.
                Each UInt32 word represents digits ranging from 0 to 10^9 - 1.
                The words are stored in little-endian order.

        Notes:

        This is equal to `BigUInt.from_list()`.
        """
        try:
            self = Self.from_list(words^)
        except e:
            raise ConversionError(
                message="See the above exception.",
                function="BigUInt.__init__(var words: List[UInt32])",
                previous_error=e^,
            )

    def __init__(out self, *, var raw_words: List[UInt32]):
        """Initializes a BigUInt from a list of raw words.

        Args:
            raw_words: A list of UInt32 words representing the coefficient.
                The words are stored in little-endian order.

        Notes:

        **UNSAFE**

        This way of initialization does not check whether the words are smaller
        than `999_999_999`, nor does it remove leading empty words.

        However, it always initializes a BigUInt and makes sure that the words
        list is not empty. If you want to initialize a BigUInt with an empty
        list of words, you can use `BigUInt(*, uninitialized_capacity=0)`.
        """
        if len(raw_words) == 0:
            self.words = [UInt32(0)]
        else:
            self.words = raw_words^

    # TODO: If Mojo makes Int type an alias of SIMD[DType.index, 1],
    # we can remove this method.
    def __init__(out self, value: Int) raises:
        """Initializes a BigUInt from an `Int`.
        See `from_int()` for more information.

        Args:
            value: The integer to initialize the `BigUInt` from.

        Raises:
            Error: Calling `BigUInt.from_int()`.
        """
        try:
            self = Self.from_int(value)
        except e:
            raise ConversionError(
                message="See the above exception.",
                function="BigUInt.__init__(value: Int)",
                previous_error=e^,
            )

    @implicit
    def __init__(out self, value: Scalar):
        """Initializes a BigUInt from an unsigned integral scalar.
        See `from_unsigned_integral_scalar()` for more information.

        Args:
            value: The unsigned integral scalar to initialize the `BigUInt` from.
        """
        self = Self.from_unsigned_integral_scalar(value)

    def __init__(out self, value: String, *, ignore_sign: Bool = False) raises:
        """Initializes a BigUInt from a string representation.

        Args:
            value: The string representation of the BigUInt.
            ignore_sign: A Bool value indicating whether to ignore the sign.
                If True, the sign is ignored.
                If False, the sign is considered.

        Raises:
            Error: If an error occurs in `from_string()`.

        Notes:
            This is equal to `BigUInt.from_string()`.
        """
        try:
            self = Self.from_string(value, ignore_sign=ignore_sign)
        except e:
            raise ConversionError(
                message="See the above exception.",
                function="BigUInt.__init__(value: String)",
                previous_error=e^,
            )

    # ===------------------------------------------------------------------=== #
    # Constructing methods that are not dunders
    #
    # from_list(var words: List[UInt32]) -> Self
    # from_words(*words: UInt32) -> Self
    # from_int(value: Int) -> Self
    # from_unsigned_integral_scalar[dtype: DType](value: Scalar[dtype]) -> Self
    # from_string(value: String) -> Self
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def from_list(var words: List[UInt32]) raises -> Self:
        """Initializes a BigUInt from a list of UInt32 words safely.
        If the list is empty, the BigUInt is initialized with value 0.
        If there are leading zero words, they are removed.
        The words are validated to ensure they are smaller than `999_999_999`.

        Args:
            words: A list of UInt32 words representing the coefficient.
                Each UInt32 word represents digits ranging from 0 to 10^9 - 1.
                The words are stored in little-endian order.

        Raises:
            Error: If any word is larger than `999_999_999`.

        Returns:
            The BigUInt representation of the list of UInt32 words.
        """
        # Return 0 if the list is empty
        if len(words) == 0:
            return Self()

        # Check if the words are valid
        for word in words:
            if word > UInt32(999_999_999):
                raise OverflowError(
                    message=(
                        "Word value "
                        + String(word)
                        + " exceeds maximum value of 999_999_999"
                    ),
                    function="BigUInt.from_list()",
                )

        var res = Self(raw_words=words^)
        res.remove_leading_empty_words()
        return res^

    @staticmethod
    def from_list_unsafe(var words: List[UInt32]) -> Self:
        """Initializes a BigUInt from a list of UInt32 words without checks.
        If the list is empty, the BigUInt is initialized with value 0.
        If there are leading empty words, they are removed.
        The words are not validated to ensure they are smaller than a billion.

        Args:
            words: A list of UInt32 words representing the coefficient.
                Each UInt32 word represents digits ranging from 0 to 10^9 - 1.
                The words are stored in little-endian order.

        Returns:
            The BigUInt representation of the list of UInt32 words.
        """
        var result = Self(raw_words=words^)
        result.remove_leading_empty_words()
        return result^

    @staticmethod
    def from_words(*words: UInt32) raises -> Self:
        """Initializes a BigUInt from raw words safely.

        Args:
            words: The UInt32 words representing the coefficient.
                Each UInt32 word represents digits ranging from 0 to 10^9 - 1.
                The words are stored in little-endian order.

        Raises:
            Error: If any word is larger than `999_999_999`.

        Notes:

        This method validates whether the words are smaller than `999_999_999`.

        Example:

        ```console
        BigUInt.from_words(123456789, 987654321) # 987654321_123456789
        ```
        End of examples.

        Returns:
            The `BigUInt` representation of the given words.
        """

        var list_of_words = List[UInt32](capacity=len(words))

        # Check if the words are valid
        for word in words:
            if word > UInt32(999_999_999):
                raise OverflowError(
                    message=(
                        "Word value "
                        + String(word)
                        + " exceeds maximum value of 999_999_999"
                    ),
                    function="BigUInt.from_words()",
                )
            else:
                list_of_words.append(word)

        return Self(raw_words=list_of_words^)

    @staticmethod
    def from_slice(value: Self, bounds: Tuple[Int, Int]) -> Self:
        """Initializes a BigUInt from a BigUInt slice.

        Args:
            value: The `BigUInt` to copy from.
            bounds: A tuple of two integers representing the bounds
                for the words to copy.
                The first integer is the start index (inclusive),
                and the second integer is the end index (exclusive).

        Returns:
            A new `BigUInt` containing the specified slice of words.
        """
        # Safty checks on bounds
        var start_index: Int
        var end_index: Int

        if bounds[0] < 0:
            start_index = 0
        else:
            start_index = bounds[0]

        if bounds[1] > len(value.words):
            end_index = len(value.words)
        else:
            end_index = bounds[1]

        var n_words = end_index - start_index
        if n_words <= 0:
            return Self()

        # Now we can safely copy the words
        result = BigUInt(unsafe_uninit_length=n_words)
        memcpy(
            dest=result.words._data,
            src=value.words._data + start_index,
            count=n_words,
        )
        result.remove_leading_empty_words()
        return result^

    @staticmethod
    def from_int(value: Int) raises -> Self:
        """Creates a BigUInt from an integer.

        Args:
            value: The integer value to be converted to BigUInt.

        Returns:
            The BigUInt representation of the integer value.

        Raises:
            Error: If the input value is negative.
        """
        if value == 0:
            return Self()

        if value < 0:
            raise OverflowError(
                function="BigUInt.from_int(value: Int)",
                message=(
                    "The input value "
                    + String(value)
                    + " is negative and is not compatible with BigUInt."
                ),
            )

        var list_of_words = List[UInt32]()
        var remainder: Int = value
        var quotient: Int

        while remainder != 0:
            quotient = remainder // 1_000_000_000
            remainder = remainder % 1_000_000_000
            list_of_words.append(UInt32(remainder))
            remainder = quotient

        return Self(raw_words=list_of_words^)

    @staticmethod
    def from_uint32_unsafe(unsafe_value: UInt32) -> Self:
        """Creates a BigUInt from a `UInt32` object without checking the value.

        Args:
            unsafe_value: The `UInt32` value to wrap directly as a single word.

        Returns:
            A single-word `BigUInt` containing the given value.
        """
        return Self(raw_words=[unsafe_value])

    @staticmethod
    def from_unsigned_integral_scalar[
        dtype: DType, //
    ](value: SIMD[dtype, 1]) -> Self:
        """Initializes a BigUInt from an unsigned integral scalar.
        This includes all SIMD unsigned integral types, such as UInt8, UInt16,
        UInt32, UInt64, etc.

        Constraints:
            The dtype must be integral and unsigned.

        Args:
            value: The Scalar value to be converted to BigUInt.

        Returns:
            The BigUInt representation of the Scalar value.

        Notes:
            This method can handle generic unsigned integral scalar types. For
            scalars whose width is smaller than 32 bits, we can directly convert
            them to UInt32 and initialize the BigUInt with one word. For scalars
            whose width is larger than and equal to 32 bits, we can repeatedly
            divide the value by 1_000_000_000 and take the remainder as the
            words of the BigUInt. Because the dtype is unsigned, we don't need
            to worry about negative values.
            - UInt8, UInt16: directly convert to UInt32.
            - UInt32: Check whether one word or two words are needed.
            - UInt64, UInt128, etc: repeatedly divide by 1_000_000_000.
            - UIndex (UInt): repeatedly divide by 1_000_000_000.

        Parameters:
            dtype: The scalar data type, must be integral and unsigned.
        """

        # Only allow unsigned integral types
        comptime assert (
            dtype.is_integral() and dtype.is_unsigned()
        ), "dtype must be unsigned integral."

        # Evaluate the conditions at compile time.
        # UInt8 and UInt16 can be directly converted to UInt32.
        comptime if (dtype == DType.uint8) or (dtype == DType.uint16):
            return Self(raw_words=[UInt32(value)])

        # UInt32 is special, so we have a separate method for it.
        comptime if dtype == DType.uint32:
            if value <= 999_999_999:
                # One word is enough
                return Self(raw_words=[UInt32(value)])
            else:
                # Two words are needed
                return Self(
                    raw_words=[
                        UInt32(value) % UInt32(Self.BASE),
                        UInt32(value) // UInt32(Self.BASE),
                    ]
                )

        if value == 0:
            return Self()

        var list_of_words = List[UInt32]()
        var remainder: Scalar[dtype] = value
        var quotient: Scalar[dtype]

        while remainder != 0:
            quotient = remainder // Self.BASE
            remainder = remainder % Self.BASE
            list_of_words.append(UInt32(remainder))
            remainder = quotient

        return Self(raw_words=list_of_words^)

    @staticmethod
    def from_absolute_integral_scalar[
        dtype: DType, //
    ](value: SIMD[dtype, 1]) -> Self:
        """Initializes a BigUInt from an integral scalar and ignores the sign.
        This includes all SIMD integral types, such as UInt8, UInt16, Int32,
        Int64, Int128, etc.

        Constraints:
            The dtype must be integral and unsigned.

        Args:
            value: The Scalar value to be converted to BigUInt.

        Returns:
            The BigUInt representation of the Scalar value.

        Parameters:
            dtype: The scalar data type, must be integral.
        """

        comptime assert dtype.is_integral(), "dtype must be integral."

        comptime if (dtype == DType.uint8) or (dtype == DType.uint16):
            # For types that are smaller than word size
            # We can directly convert them to UInt32
            return Self(raw_words=[UInt32(value)])

        elif (dtype == DType.int8) or (dtype == DType.int16):
            # For signed types that are smaller than 1_000_000_000,
            # we need to handle it differently
            if value < 0:
                # Because -Int16.MIN == Int16.MAX + 1,
                # we need to handle the case by converting it to Int32
                # before taking the absolute value.
                return Self(raw_words=[UInt32(-Int32(value))])
            else:
                return Self(raw_words=[UInt32(value)])

        else:
            if value == 0:
                return materialize[BigUInt.ZERO]()

            var sign = True if value < 0 else False

            var list_of_words = List[UInt32]()
            var remainder: Scalar[dtype] = value
            var quotient: Scalar[dtype]

            if sign:
                while remainder != 0:
                    quotient = remainder // (-Self.BASE)
                    remainder = remainder % (-Self.BASE)
                    list_of_words.append(UInt32(-remainder))
                    remainder = -quotient
            else:
                while remainder != 0:
                    quotient = remainder // Self.BASE
                    remainder = remainder % Self.BASE
                    list_of_words.append(UInt32(remainder))
                    remainder = quotient

            return Self(raw_words=list_of_words^)

    @staticmethod
    def from_string(value: String, ignore_sign: Bool = False) raises -> BigUInt:
        """Initializes a BigUInt from a string representation.
        The string is normalized with `decimo.str.parse_numeric_string()`.

        Args:
            value: The string representation of the BigUInt.
            ignore_sign: A Bool value indicating whether to ignore the sign.
                If True, the sign is ignored.
                If False, the sign is considered.

        Raises:
            OverflowError: If the input value is negative and `ignore_sign` is
                False.
            ConversionError: If the input value is not a valid integer string.
                The scale is larger than the number of digits.
            ConversionError: If the input value is not an integer string.
                The fractional part is not zero.

        Returns:
            The BigUInt representation of the string.
        """
        _tuple = decimo.str.parse_numeric_string(value)
        var ref coef: List[UInt8] = _tuple[0]
        var scale: Int = _tuple[1]
        var sign: Bool = _tuple[2]

        if (not ignore_sign) and sign:
            raise OverflowError(
                function="BigUInt.from_string(value: String)",
                message=(
                    'The input value "'
                    + value
                    + '" is negative but `ignore_sign` is False.\n'
                    + "Consider using `ignore_sign=True` to ignore the sign."
                ),
            )

        # Check if the number is zero
        if len(coef) == 1 and coef[0] == UInt8(0):
            return Self()

        # Check whether the number is an integer
        # If the fractional part is not zero, raise an error
        # If the fractional part is zero, remove the fractional part
        if scale > 0:
            if scale >= len(coef):
                raise ConversionError(
                    function="BigUInt.from_string(value: String)",
                    message=(
                        'The input value "'
                        + value
                        + '" is not an integer.\n'
                        + "The scale is larger than the number of digits."
                    ),
                )
            for i in range(1, scale + 1):
                if coef[-i] != 0:
                    raise ConversionError(
                        function="BigUInt.from_string(value: String)",
                        message=(
                            'The input value "'
                            + value
                            + '" is not an integer.\n'
                            + "The fractional part is not zero."
                        ),
                    )
            coef.resize(len(coef) - scale, UInt8(0))
            scale = 0

        var number_of_digits = len(coef) - scale
        var number_of_words = number_of_digits // 9
        if number_of_digits % 9 != 0:
            number_of_words += 1

        var result_words = List[UInt32](capacity=number_of_words)

        if scale == 0:
            # This is a true integer
            var end: Int = number_of_digits
            var start: Int
            while end >= 9:
                start = end - 9
                var word: UInt32 = 0
                for digit in coef[start:end]:
                    word = word * 10 + UInt32(digit)
                result_words.append(word)
                end = start
            if end > 0:
                var word: UInt32 = 0
                for digit in coef[0:end]:
                    word = word * 10 + UInt32(digit)
                result_words.append(word)

            return Self(raw_words=result_words^)

        else:  # scale < 0
            # This is a true integer with postive exponent
            var number_of_trailing_zero_words = -scale // 9
            var remaining_trailing_zero_digits = -scale % 9

            for _ in range(number_of_trailing_zero_words):
                result_words.append(UInt32(0))

            for _ in range(remaining_trailing_zero_digits):
                coef.append(UInt8(0))

            var end: Int = (
                number_of_digits + scale + remaining_trailing_zero_digits
            )
            var start: Int
            while end >= 9:
                start = end - 9
                var word: UInt32 = 0
                for digit in coef[start:end]:
                    word = word * 10 + UInt32(digit)
                result_words.append(word)
                end = start
            if end > 0:
                var word: UInt32 = 0
                for digit in coef[0:end]:
                    word = word * 10 + UInt32(digit)
                result_words.append(word)

            return Self(raw_words=result_words^)

    # ===------------------------------------------------------------------=== #
    # Output dunders, type-transfer dunders
    # ===------------------------------------------------------------------=== #

    def __int__(self) raises -> Int:
        """Returns the number as Int.

        Returns:
            The number as Int.

        Raises:
            Error: If to_int() raises an error.
        """
        try:
            return self.to_int()
        except e:
            raise ConversionError(
                message="See the above exception.",
                function="BigUInt.__int__()",
                previous_error=e^,
            )

    def write_repr_to[W: Writer](self, mut writer: W):
        """Writes the debug representation to a writer.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        writer.write('BigUInt("', self.to_string(), '")')

    # ===------------------------------------------------------------------=== #
    # Type-transfer or output methods that are not dunders
    # ===------------------------------------------------------------------=== #

    def write_to[W: Writer](self, mut writer: W):
        """Writes the BigUInt to a writer.
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
            OverflowError: If the number exceeds the size of Int (2^63-1).
        """

        # 2^63-1 = 9_223_372_036_854_775_807
        # is larger than 10^18 -1 but smaller than 10^27 - 1

        var overflow_msg = (
            "The number exceeds the size of Int (" + String(Int.MAX) + ")"
        )
        if len(self.words) > 3:
            raise OverflowError(
                function="BigUInt.to_int()",
                message=overflow_msg,
            )

        var value: Int128 = 0
        for i in range(len(self.words)):
            value += Int128(self.words[i]) * Int128(1_000_000_000) ** i

        if value > Int128(Int.MAX):
            raise OverflowError(
                function="BigUInt.to_int()",
                message=overflow_msg,
            )

        return Int(value)

    def to_uint64(self) raises -> UInt64:
        """Returns the number as UInt64.

        Returns:
            The number as UInt64.

        Raises:
            Error: If the number exceeds the size of UInt64.
        """
        if self.is_uint64_overflow():
            raise OverflowError(
                function="BigUInt.to_uint64()",
                message=(
                    "The number exceeds the size of UInt64 ("
                    + String(UInt64.MAX)
                    + ")"
                ),
            )

        if len(self.words) == 1:
            return self.words.unsafe_ptr().load[width=1]().cast[DType.uint64]()
        elif len(self.words) == 2:
            return (
                self.words.unsafe_ptr().load[width=2]().cast[DType.uint64]()
                * SIMD[DType.uint64, 2](1, 1_000_000_000)
            ).reduce_add()
        else:
            return (
                self.words.unsafe_ptr().load[width=4]().cast[DType.uint64]()
                * SIMD[DType.uint64, 4](
                    1,
                    1_000_000_000,
                    1_000_000_000_000_000_000,
                    0,
                )
            ).reduce_add()

    def to_uint64_with_first_2_words(self) -> UInt64:
        """Convert the first two words of the BigUInt to UInt64.

        Notes:
            This method quickly convert BigUInt with 2 words into UInt64.

        Returns:
            The `UInt64` representation of the first two words.
        """
        if len(self.words) == 1:
            return self.words.unsafe_ptr().load[width=1]().cast[DType.uint64]()
        else:  # len(self.words) == 2
            return (
                self.words.unsafe_ptr().load[width=2]().cast[DType.uint64]()
                * SIMD[DType.uint64, 2](1, 1_000_000_000)
            ).reduce_add()

    def to_uint128(self) -> UInt128:
        """Returns the number as UInt128.
        **UNSAFE** You need to ensure that the number of words is less than 5.

        Returns:
            The number as UInt128.
        """

        # FIXME: Due to an unknown bug in Mojo,
        # The returned value changed in the caller when we use raises
        # So I have to comment out the raises part
        # In the future, we need to fix this bug and add raises back
        #
        # if self.is_uint128_overflow():
        #     raise Error(
        #         "`BigUInt.to_int()`: The number exceeds the size"
        #         " of UInt128 (340282366920938463463374607431768211455)"
        #     )

        var result: UInt128

        if len(self.words) == 1:
            result = (
                self.words.unsafe_ptr().load[width=1]().cast[DType.uint128]()
            )
        elif len(self.words) == 2:
            result = (
                self.words.unsafe_ptr().load[width=2]().cast[DType.uint128]()
                * SIMD[DType.uint128, 2](1, 1_000_000_000)
            ).reduce_add()
        elif len(self.words) == 3:
            result = (
                self.words.unsafe_ptr().load[width=4]().cast[DType.uint128]()
                * SIMD[DType.uint128, 4](
                    1, 1_000_000_000, 1_000_000_000_000_000_000, 0
                )
            ).reduce_add()
        elif len(self.words) == 4:
            result = (
                self.words.unsafe_ptr().load[width=4]().cast[DType.uint128]()
                * SIMD[DType.uint128, 4](
                    1,
                    1_000_000_000,
                    1_000_000_000_000_000_000,
                    1_000_000_000_000_000_000_000_000_000,
                )
            ).reduce_add()
        else:
            result = (
                self.words.unsafe_ptr().load[width=8]().cast[DType.uint128]()
                * SIMD[DType.uint128, 8](
                    1,
                    1_000_000_000,
                    1_000_000_000_000_000_000,
                    1_000_000_000_000_000_000_000_000_000,
                    1_000_000_000_000_000_000_000_000_000_000_000_000,
                    0,
                    0,
                    0,
                )
            ).reduce_add()

        return result

    def to_uint128_with_first_4_words(self) -> UInt128:
        """Convert the first four words of the BigUInt to UInt128.

        Notes:
            This method quickly convert BigUInt with 4 words into UInt128.

        Returns:
            The `UInt128` representation of the first four words.
        """

        if len(self.words) == 1:
            return self.words.unsafe_ptr().load[width=1]().cast[DType.uint128]()
        elif len(self.words) == 2:
            return (
                self.words.unsafe_ptr().load[width=2]().cast[DType.uint128]()
                * SIMD[DType.uint128, 2](1, 1_000_000_000)
            ).reduce_add()
        elif len(self.words) == 3:
            return (
                self.words.unsafe_ptr().load[width=4]().cast[DType.uint128]()
                * SIMD[DType.uint128, 4](
                    1, 1_000_000_000, 1_000_000_000_000_000_000, 0
                )
            ).reduce_add()
        else:  # len(self.words) == 4
            return (
                self.words.unsafe_ptr().load[width=4]().cast[DType.uint128]()
                * SIMD[DType.uint128, 4](
                    1,
                    1_000_000_000,
                    1_000_000_000_000_000_000,
                    1_000_000_000_000_000_000_000_000_000,
                )
            ).reduce_add()

    def to_string(self, line_width: Int = 0) -> String:
        """Returns string representation of the BigUInt.

        Args:
            line_width: The width of each line. Default is 0, which means no
                line width.

        Returns:
            The string representation of the BigUInt.
        """

        if len(self.words) == 0:
            return String("Unitilialized BigUInt")

        if self.is_zero():
            debug_assert(len(self.words) == 1, "There are leading zero words.")
            return String("0")

        var result = String("")

        for i in range(len(self.words) - 1, -1, -1):
            if i == len(self.words) - 1:
                result += String(self.words[i])
            else:
                result += decimo.str.rjust(
                    String(self.words[i]), width=9, fillchar="0"
                )

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

    def to_string_with_separators(self, separator: String = "_") -> String:
        """Returns string representation of the BigUInt with separators.

        Args:
            separator: The separator string. Default is "_".

        Returns:
            The string representation of the BigUInt with separators.
        """

        var result = self.to_string()
        var end = len(result)
        var start = end - 3
        var blocks = List[String](capacity=len(result) // 3 + 1)
        while start > 0:
            blocks.append(String(result[byte=start:end]))
            end = start
            start = end - 3
        blocks.append(String(result[byte=0:end]))
        blocks.reverse()
        result = separator.join(blocks)

        return result^

    # ===------------------------------------------------------------------=== #
    # Type-conversion methods that are unsafe
    # ===------------------------------------------------------------------=== #

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
        return decimo.biguint.arithmetics.absolute(self)

    @always_inline
    def __neg__(self) raises -> Self:
        """Returns the negation of this number.
        See `negative()` for more information.

        Returns:
            The negated value.
        """
        return decimo.biguint.arithmetics.negative(self)

    @always_inline
    def __rshift__(self, shift_amount: Int) -> Self:
        """Returns the result of floored divison by 2 to the power of `shift_amount`.

        Args:
            shift_amount: The number of bit positions to shift right.

        Returns:
            The floor-divided value.
        """
        var result = self.copy()
        for _ in range(shift_amount):
            decimo.biguint.arithmetics.floor_divide_inplace_by_2(result)
        return result^

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
            The sum.
        """
        return decimo.biguint.arithmetics.add(self, other)

    @always_inline
    def __sub__(self, other: Self) raises -> Self:
        """Subtracts two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The difference.
        """
        try:
            return decimo.biguint.arithmetics.subtract(self, other)
        except e:
            raise ZeroDivisionError(
                message="See the above exception.",
                function="BigUInt.__sub__(other: Self)",
                previous_error=e^,
            )

    @always_inline
    def __mul__(self, other: Self) -> Self:
        """Multiplies two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The product.
        """
        return decimo.biguint.arithmetics.multiply(self, other)

    @always_inline
    def __floordiv__(self, other: Self) raises -> Self:
        """Divides two values using floor division.

        Args:
            other: The right-hand side operand.

        Returns:
            The quotient.
        """
        try:
            return decimo.biguint.arithmetics.floor_divide(self, other)
        except e:
            raise ZeroDivisionError(
                message="See the above exception.",
                function="BigUInt.__floordiv__(other: Self)",
                previous_error=e^,
            )

    @always_inline
    def __ceildiv__(self, other: Self) raises -> Self:
        """Returns the result of ceiling division.

        Args:
            other: The right-hand side operand.

        Returns:
            The quotient rounded up.
        """
        try:
            return decimo.biguint.arithmetics.ceil_divide(self, other)
        except e:
            raise ZeroDivisionError(
                message="See the above exception.",
                function="BigUInt.__ceildiv__(other: Self)",
                previous_error=e^,
            )

    @always_inline
    def __mod__(self, other: Self) raises -> Self:
        """Returns the remainder of division.

        Args:
            other: The right-hand side operand.

        Returns:
            The remainder.
        """
        try:
            return decimo.biguint.arithmetics.floor_modulo(self, other)
        except e:
            raise ZeroDivisionError(
                message="See the above exception.",
                function="BigUInt.__mod__(other: Self)",
                previous_error=e^,
            )

    @always_inline
    def __divmod__(self, other: Self) raises -> Tuple[Self, Self]:
        """Returns the quotient and remainder of division.

        Args:
            other: The right-hand side operand.

        Returns:
            A tuple of (quotient, remainder).
        """
        try:
            return decimo.biguint.arithmetics.floor_divide_modulo(self, other)
        except e:
            raise ValueError(
                message="See the above exception.",
                function="BigUInt.__divmod__(other: Self)",
                previous_error=e^,
            )

    @always_inline
    def __pow__(self, exponent: Self) raises -> Self:
        """Raises to a power.

        Args:
            exponent: The exponent to raise this number to.

        Returns:
            The power `self` raised to `exponent`.
        """
        try:
            return self.power(exponent)
        except e:
            raise ValueError(
                message="See the above exception.",
                function="BigUInt.__pow__(exponent: Self)",
                previous_error=e^,
            )

    @always_inline
    def __pow__(self, exponent: Int) raises -> Self:
        """Raises to a power.

        Args:
            exponent: The exponent to raise this number to.

        Returns:
            The power `self` raised to `exponent`.
        """
        try:
            return self.power(exponent)
        except e:
            raise ValueError(
                message="See the above exception.",
                function="BigUInt.__pow__(exponent: Int)",
                previous_error=e^,
            )

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
            The sum.
        """
        return decimo.biguint.arithmetics.add(self, other)

    @always_inline
    def __rsub__(self, other: Self) raises -> Self:
        """Subtracts two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The difference.
        """
        return decimo.biguint.arithmetics.subtract(other, self)

    @always_inline
    def __rmul__(self, other: Self) raises -> Self:
        """Multiplies two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The product.
        """
        return decimo.biguint.arithmetics.multiply(self, other)

    @always_inline
    def __rfloordiv__(self, other: Self) raises -> Self:
        """Divides two values using floor division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The quotient.
        """
        return decimo.biguint.arithmetics.floor_divide(other, self)

    @always_inline
    def __rmod__(self, other: Self) raises -> Self:
        """Returns the remainder of division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The remainder.
        """
        return decimo.biguint.arithmetics.floor_modulo(other, self)

    @always_inline
    def __rdivmod__(self, other: Self) raises -> Tuple[Self, Self]:
        """Returns the quotient and remainder of division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            A tuple of (quotient, remainder).
        """
        return decimo.biguint.arithmetics.floor_divide_modulo(other, self)

    @always_inline
    def __rpow__(self, base: Self) raises -> Self:
        """Raises to a power (reflected).

        Args:
            base: The base to raise to the power of `self`.

        Returns:
            The power `base` raised to `self`.
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
        """Adds `other` to `self` in place.
        See `biguint.arithmetics.add_inplace()` for more information.

        Args:
            other: The operand to add.
        """
        decimo.biguint.arithmetics.add_inplace(self, other)

    @always_inline
    def __isub__(mut self, other: Self) raises:
        """Subtracts `other` from `self` in place.
        See `biguint.arithmetics.subtract_inplace()` for more information.

        Args:
            other: The operand to subtract.
        """
        decimo.biguint.arithmetics.subtract_inplace(self, other)

    @always_inline
    def __imul__(mut self, other: Self) raises:
        """Multiplies in place.

        Args:
            other: The operand to multiply by.
        """
        self = decimo.biguint.arithmetics.multiply(self, other)

    @always_inline
    def __ifloordiv__(mut self, other: Self) raises:
        """Divides in place using floor division.

        Args:
            other: The divisor.
        """
        self = decimo.biguint.arithmetics.floor_divide(self, other)

    @always_inline
    def __imod__(mut self, other: Self) raises:
        """Computes the remainder in place.

        Args:
            other: The divisor.
        """
        self = decimo.biguint.arithmetics.floor_modulo(self, other)

    # ===------------------------------------------------------------------=== #
    # Basic binary comparison operation dunders
    # __gt__, __ge__, __lt__, __le__, __eq__, __ne__
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __gt__(self, other: Self) -> Bool:
        """Returns True if self > other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self` is greater than `other`, `False` otherwise.
        """
        return decimo.biguint.comparison.greater(self, other)

    @always_inline
    def __ge__(self, other: Self) -> Bool:
        """Returns True if self >= other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self` is greater than or equal to `other`, `False` otherwise.
        """
        return decimo.biguint.comparison.greater_equal(self, other)

    @always_inline
    def __lt__(self, other: Self) -> Bool:
        """Returns True if self < other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self` is less than `other`, `False` otherwise.
        """
        return decimo.biguint.comparison.less(self, other)

    @always_inline
    def __le__(self, other: Self) -> Bool:
        """Returns True if self <= other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self` is less than or equal to `other`, `False` otherwise.
        """
        return decimo.biguint.comparison.less_equal(self, other)

    @always_inline
    def __eq__(self, other: Self) -> Bool:
        """Returns True if self == other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self` equals `other`, `False` otherwise.
        """
        return decimo.biguint.comparison.equal(self, other)

    @always_inline
    def __ne__(self, other: Self) -> Bool:
        """Returns True if self != other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self` does not equal `other`, `False` otherwise.
        """
        return decimo.biguint.comparison.not_equal(self, other)

    # ===------------------------------------------------------------------=== #
    # Other dunders
    # ===------------------------------------------------------------------=== #

    def __merge_with__[other_type: type_of(BigInt10)](self) -> BigInt10:
        """Merges this BigUInt with a BigInt10 into a BigInt10.

        Parameters:
            other_type: The target type.

        Returns:
            A BigInt10 value.
        """
        return BigInt10(self)

    def __merge_with__[other_type: type_of(BigDecimal)](self) -> BigDecimal:
        """Merges this BigUInt with a BigDecimal into a BigDecimal.

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
    def add_inplace(mut self, other: Self) raises:
        """Adds `other` to this number in place.
        It is equal to `self += other`.
        See `add_inplace()` for more information.

        Args:
            other: The operand to add.
        """
        decimo.biguint.arithmetics.add_inplace(self, other)

    @always_inline
    def floor_divide(self, other: Self) raises -> Self:
        """Returns the result of floor dividing this number by `other`.
        It is equal to `self // other`.
        See `floor_divide()` for more information.

        Args:
            other: The divisor.

        Returns:
            The quotient.
        """
        return decimo.biguint.arithmetics.floor_divide(self, other)

    @always_inline
    def truncate_divide(self, other: Self) raises -> Self:
        """Returns the result of truncate dividing this number by `other`.
        It is equal to `self // other`.
        See `truncate_divide()` for more information.

        Args:
            other: The divisor.

        Returns:
            The quotient.
        """
        return decimo.biguint.arithmetics.truncate_divide(self, other)

    @always_inline
    def ceil_divide(self, other: Self) raises -> Self:
        """Returns the result of ceil dividing this number by `other`.
        See `ceil_divide()` for more information.

        Args:
            other: The divisor.

        Returns:
            The quotient rounded up.
        """
        return decimo.biguint.arithmetics.ceil_divide(self, other)

    @always_inline
    def floor_modulo(self, other: Self) raises -> Self:
        """Returns the result of floor modulo this number by `other`.
        See `floor_modulo()` for more information.

        Args:
            other: The divisor.

        Returns:
            The remainder.
        """
        return decimo.biguint.arithmetics.floor_modulo(self, other)

    @always_inline
    def truncate_modulo(self, other: Self) raises -> Self:
        """Returns the result of truncate modulo this number by `other`.
        See `truncate_modulo()` for more information.

        Args:
            other: The divisor.

        Returns:
            The remainder.
        """
        return decimo.biguint.arithmetics.truncate_modulo(self, other)

    @always_inline
    def ceil_modulo(self, other: Self) raises -> Self:
        """Returns the result of ceil modulo this number by `other`.
        See `ceil_modulo()` for more information.

        Args:
            other: The divisor.

        Returns:
            The remainder.
        """
        return decimo.biguint.arithmetics.ceil_modulo(self, other)

    @always_inline
    def divmod(self, other: Self) raises -> Tuple[Self, Self]:
        """Returns the result of divmod this number by `other`.
        See `divmod()` for more information.

        Args:
            other: The divisor.

        Returns:
            A tuple of (quotient, remainder).
        """
        return decimo.biguint.arithmetics.floor_divide_modulo(self, other)

    @always_inline
    def floor_divide_inplace_by_2(mut self) raises:
        """Divides this number by 2 in place.
        See `floor_divide_inplace_by_2()` for more information.
        """
        decimo.biguint.arithmetics.floor_divide_inplace_by_2(self)

    @always_inline
    def multiply_by_power_of_ten(self, n: Int) -> Self:
        """Returns the result of multiplying this number by 10^n (n>=0).
        See `multiply_by_power_of_ten()` for more information.

        Args:
            n: The power of 10 to multiply by.

        Returns:
            The product of this number and 10^n.
        """
        return decimo.biguint.arithmetics.multiply_by_power_of_ten(self, n)

    @always_inline
    def multiply_inplace_by_power_of_ten(mut self, n: Int):
        """Multiplies this number in-place by 10^n (n>=0).
        See `multiply_inplace_by_power_of_ten()` for more information.

        Args:
            n: The power of 10 to multiply by.
        """
        decimo.biguint.arithmetics.multiply_inplace_by_power_of_ten(self, n)

    @always_inline
    def floor_divide_by_power_of_ten(self, n: Int) -> Self:
        """Returns the result of floored dividing this number by 10^n (n>=0).
        It is equal to removing the last n digits of the number.
        See `floor_divide_by_power_of_ten()` for more information.

        Args:
            n: The power of 10 to divide by.

        Returns:
            The quotient after removing the last `n` digits.
        """
        return decimo.biguint.arithmetics.floor_divide_by_power_of_ten(self, n)

    @always_inline
    def multiply_inplace_by_power_of_billion(mut self, n: Int):
        """Multiplies a BigUInt in-place by (10^9)^n if n > 0.
        This equals to adding 9n zeros (n words) to the end of the number.

        Args:
            n: The power of 10^9 to multiply by. Should be non-negative.
        """
        decimo.biguint.arithmetics.multiply_inplace_by_power_of_billion(self, n)

    def power(self, exponent: Int) raises -> Self:
        """Returns the result of raising this number to the power of `exponent`.

        Args:
            exponent: The exponent to raise the number to.

        Returns:
            A `BigUInt` representing `self` raised to the power of `exponent`.

        Raises:
            Error: If the exponent is negative.
            Error: If the exponent is too large, e.g., larger than 1_000_000_000.
        """
        if exponent < 0:
            raise ValueError(
                function="BigUInt.power(exponent: Int)",
                message=(
                    "The exponent "
                    + String(exponent)
                    + " is negative.\n"
                    + "Consider using a non-negative exponent."
                ),
            )

        if exponent == 0:
            return Self(raw_words=[1])

        if exponent >= 1_000_000_000:
            raise ValueError(
                function="BigUInt.power(exponent: Int)",
                message=(
                    "The exponent "
                    + String(exponent)
                    + " is too large.\n"
                    + "Consider using an exponent below 1_000_000_000."
                ),
            )

        var result = Self(raw_words=[1])
        var base = self.copy()
        var exp = exponent
        while exp > 0:
            if exp % 2 == 1:
                result = result * base
            base = base * base
            exp //= 2

        return result^

    def power(self, exponent: Self) raises -> Self:
        """Returns the result of raising this number to the power of `exponent`.

        Args:
            exponent: The exponent to raise the number to.

        Raises:
            ValueError: If the exponent is too large.

        Returns:
            The result of raising this number to the power of `exponent`.
        """
        if len(exponent.words) > 1:
            raise ValueError(
                function="BigUInt.power(exponent: BigUInt)",
                message=(
                    "The exponent "
                    + String(exponent)
                    + " is too large.\n"
                    + "Consider using an exponent below 1_000_000_000."
                ),
            )
        var exponent_as_int = exponent.to_int()
        return self.power(exponent_as_int)

    def sqrt(self) -> Self:
        """Returns the square root of this number.

        Returns:
            The square root of x as a BigUInt.

        Notes:

        The square root is the largest integer y such that y * y <= x.
        """
        return decimo.biguint.exponential.sqrt(self)

    def isqrt(self) -> Self:
        """Returns the square root of this number.
        It is equal to `sqrt()`.

        Returns:
            The square root of x as a BigUInt.

        Notes:

        The square root is the largest integer y such that y * y <= x.
        """
        return decimo.biguint.exponential.sqrt(self)

    @always_inline
    def compare(self, other: Self) -> Int8:
        """Compares the magnitudes of two BigUInts.
        See `compare()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            A positive value if `self > other`, 0 if equal, or a negative value if `self < other`.
        """
        return decimo.biguint.comparison.compare(self, other)

    # ===------------------------------------------------------------------=== #
    # Other methods
    # ===------------------------------------------------------------------=== #

    def internal_representation(self) -> String:
        """Returns the internal representation details as a String.

        Returns:
            A formatted string showing the number and its individual words.
        """
        # Collect all labels to find max width
        var max_label_len = len("number:")
        for i in range(len(self.words)):
            var label_len = len("word :") + len(String(i))
            if label_len > max_label_len:
                max_label_len = label_len

        var col = max_label_len + 4  # 4 spaces after longest label
        var value_width = 30
        var sep_line = String("-") * (col + value_width)

        var result = String("\nInternal Representation Details of BigUInt\n")
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

        # word lines
        for i in range(len(self.words)):
            var label = "word " + String(i) + ":"
            result += label + String(" ") * (col - len(label))
            result += (
                decimo.str.rjust(String(self.words[i]), 9, fillchar="0") + "\n"
            )

        result += sep_line
        return result^

    def print_internal_representation(self):
        """Prints the internal representation details of a BigUInt."""
        print(self.internal_representation())

    @always_inline
    def is_zero(self) -> Bool:
        """Returns True if this BigUInt represents zero.

        Returns:
            `True` if the value is zero, `False` otherwise.
        """
        # Yuhao ZHU:
        # BigUInt are desgined to have no leading zero words,
        # so that we only need to check words[0] for zero.
        # If there are leading zero words, it means that we have to loop over
        # all words to check if the number is zero.
        debug_assert[assert_mode="none"](
            (len(self.words) == 1) or (self.words[-1] != 0),
            "biguint.BigUInt.is_zero(): ",
            "BigUInt should not contain leading zero words.",
        )  # 0 should have only one word by design

        return len(self.words) == 1 and self.words._data[] == 0

        # Yuhao ZHU:
        # The following code is commented out because BigUInt is designed
        # to have no leading zero words.
        # We only need to check the first word.
        # They are left here for reference.
        # return (self.words._data[] == 0) and (
        #     memcmp(self.words._data, self.words._data + 1, len(self.words) - 1)
        #     == 0
        # )

    @always_inline
    def is_zero_in_bounds(self, bounds: Tuple[Int, Int]) -> Bool:
        """Returns True if this BigUInt slice represents zero.

        Args:
            bounds: A tuple of two integers representing the start and end
                indices of the slice to check. Then end index is exclusive.

        Returns:
            True if the slice of this BigUInt represents zero, False otherwise.
        """
        for i in range(bounds[0], bounds[1]):
            if self.words[i] != 0:
                return False
        return True

    @always_inline
    def is_one(self) -> Bool:
        """Returns True if this BigUInt represents one.

        Returns:
            `True` if the value is one, `False` otherwise.
        """
        if self.words[0] != 1:
            # Least significant word is not 1
            return False
        elif len(self.words) == 1:
            # Least significant word is 1 and there is no other word
            return True
        else:
            # Least significant word is 1 and there are other words
            # Check if all other words are zero
            for i in self.words[1:]:
                if i != 0:
                    return False
            else:
                return True

    @always_inline
    def is_two(self) -> Bool:
        """Returns True if this BigUInt represents two.

        Returns:
            `True` if the value is two, `False` otherwise.
        """
        if len(self.words) != 2:
            return False
        for i in self.words[1:]:
            if i != 0:
                return False
        return True

    @always_inline
    def is_power_of_10(x: BigUInt) -> Bool:
        """Check if x is a power of 10.

        Returns:
            `True` if the value is a power of 10, `False` otherwise.
        """
        for i in range(len(x.words) - 1):
            if x.words[i] != 0:
                return False
        var word = x.words[len(x.words) - 1]
        if (
            (word == UInt32(1))
            or (word == UInt32(10))
            or (word == UInt32(100))
            or (word == UInt32(1000))
            or (word == UInt32(10_000))
            or (word == UInt32(100_000))
            or (word == UInt32(1_000_000))
            or (word == UInt32(10_000_000))
            or (word == UInt32(100_000_000))
        ):
            return True
        return False

    @always_inline
    def is_unitialized(self) -> Bool:
        """Returns True if the BigUInt is uninitialized.

        Returns:
            `True` if the words list is empty, `False` otherwise.
        """
        return len(self.words) == 0

    @always_inline
    def is_uint64_overflow(self) -> Bool:
        """Returns True if the BigUInt larger than UInt64.MAX.

        Returns:
            `True` if the value exceeds `UInt64.MAX`, `False` otherwise.
        """
        # UInt64.MAX:     18_446_744_073_709_551_615
        # word 0:         709551615
        # word 1:         446744073
        # word 2:         18
        if len(self.words) > 3:
            return True
        elif len(self.words) == 3:
            if self.words[2] > UInt32(18):
                return True
            elif self.words[2] == 18:
                if self.words[1] > UInt32(446744073):
                    return True
                elif self.words[1] == UInt32(446744073):
                    if self.words[0] > UInt32(709551615):
                        return True
        return False

    @always_inline
    def is_uint128_overflow(self) -> Bool:
        """Returns True if the BigUInt larger than UInt128.MAX.

        Returns:
            `True` if the value exceeds `UInt128.MAX`, `False` otherwise.
        """
        # UInt128.MAX:    340_282_366_920_938_463_463_374_607_431_768_211_455
        # word 0:         768211455
        # word 1:         374607431
        # word 2:         938463463
        # word 3:         282366920
        # word 4:         340
        if len(self.words) > 5:
            return True
        elif len(self.words) == 4:
            if self.words[4] > UInt32(340):
                return True
            elif self.words[4] == UInt32(340):
                if self.words[3] > UInt32(282366920):
                    return True
                elif self.words[3] == UInt32(282366920):
                    if self.words[2] > UInt32(938463463):
                        return True
                    elif self.words[2] == UInt32(938463463):
                        if self.words[1] > UInt32(374607431):
                            return True
                        elif self.words[1] == UInt32(374607431):
                            if self.words[0] > UInt32(768211455):
                                return True
        return False

    @always_inline
    def ith_digit(self, i: Int) raises -> UInt8:
        """Returns the ith least significant digit of the BigUInt.
        If the index is more than the number of digits, it returns 0.

        Args:
            i: The index of the digit to return. The least significant digit
                is at index 0.

        Returns:
            The ith least significant digit of the BigUInt.

        Raises:
            IndexError: If the index is negative.
        """
        if i < 0:
            raise IndexError(
                function="BigUInt.ith_digit(i: Int)",
                message=(
                    "The index "
                    + String(i)
                    + " is negative.\n"
                    + "Consider using a non-negative index."
                ),
            )
        if i >= len(self.words) * 9:
            return 0
        var word_index = i // 9
        var digit_index = i % 9
        if word_index >= len(self.words):
            return 0
        var word = self.words[word_index]
        for _ in range(digit_index):
            word = word // 10
        var digit = word % 10
        return UInt8(digit)

    def number_of_digits(self) -> Int:
        """Returns the number of digits in the BigUInt.

        Notes:

        Zero has 1 digit.

        Returns:
            The total number of decimal digits in the BigUInt.
        """
        if self.is_zero():
            debug_assert(len(self.words) == 1, "There are leading zero words.")
            return 1

        var result: Int = (len(self.words) - 1) * 9
        var last_word = self.words[len(self.words) - 1]
        while last_word > 0:
            result += 1
            last_word = last_word // 10
        return result

    def number_of_words(self) -> Int:
        """Returns the number of words in the BigUInt.

        Returns:
            The number of `UInt32` words in the internal representation.
        """
        return len(self.words)

    def number_of_trailing_zeros(self) -> Int:
        """Returns the number of trailing zeros in the BigUInt.

        Returns:
            The count of trailing zero digits in the decimal representation.
        """
        var result: Int = 0
        for i in range(len(self.words)):
            if self.words[i] == 0:
                result += 9
            else:
                var word = self.words[i]
                while word % 10 == 0:
                    result += 1
                    word = word // 10
                break
        return result

    @always_inline
    def remove_leading_empty_words(mut self):
        """Removes the most significant empty words of a BigUInt.

        Notes:

        The internal representation of a BigUInt is a list of words.
        The most significant zero words are the words that are
        equal to zero and are at the end of the list.

        Note that, because we are using little-endian representation,
        the least significant word is at index 0 and the most significant word
        is at index len(words) - 1. The leading / trailing is based on the
        order of the **number**, instead of the memory layout (the list).
        Thus, the leading zero words are at the end of the list, and are zeros
        at the left side of the number.

        If there is only one word and it is zero, we do not remove it.
        Otherwise, the embedded list will be empty.
        """
        if self.words[len(self.words) - 1] != 0:
            # The least significant word is not zero, so we do not remove it
            return
        else:
            var n_empty_words: Int = 0
            for i in range(len(self.words) - 1, 0, -1):
                if self.words[i] == 0:
                    n_empty_words += 1
                else:
                    break
            self.words.shrink(len(self.words) - n_empty_words)

    @always_inline
    def remove_trailing_digits_with_rounding(
        self,
        ndigits: Int,
        rounding_mode: RoundingMode,
        remove_extra_digit_due_to_rounding: Bool,
        sign: Bool = False,
    ) raises -> Self:
        """Removes trailing digits from the BigUInt with rounding.

        Args:
            ndigits: The number of digits to remove.
            rounding_mode: The rounding mode to use.
                RoundingMode.ROUND_DOWN: Round toward zero.
                RoundingMode.ROUND_UP: Round away from zero.
                RoundingMode.ROUND_HALF_UP: Round half away from zero.
                RoundingMode.ROUND_HALF_DOWN: Round half toward zero.
                RoundingMode.ROUND_HALF_EVEN: Round half to even (banker's).
                RoundingMode.ROUND_CEILING: Round toward +inf.
                RoundingMode.ROUND_FLOOR: Round toward -inf.
            remove_extra_digit_due_to_rounding: If True, remove an trailing
                digit if the rounding mode result in an extra digit.
            sign: The sign of the original number (True = negative).
                Only needed for CEILING/FLOOR modes.

        Returns:
            The BigUInt with the trailing digits removed.

        Raises:
            ValueError: If the number of digits to remove is negative.

        Notes:

        Rounding can result in an extra digit. Exmaple: remove last 1 digit of
        999 with rounding up results in 100. If
        `remove_extra_digit_due_to_rounding` is True, the result will be 10.
        """
        if ndigits < 0:
            raise ValueError(
                function="BigUInt.remove_trailing_digits_with_rounding()",
                message=(
                    "The number of digits to remove is negative: "
                    + String(ndigits)
                ),
            )
        if ndigits == 0:
            return self.copy()
        if ndigits > self.number_of_digits():
            raise ValueError(
                function="BigUInt.remove_trailing_digits_with_rounding()",
                message=(
                    "The number of digits to remove is larger than the "
                    "number of digits in the BigUInt: "
                    + String(ndigits)
                    + " > "
                    + String(self.number_of_digits())
                ),
            )

        # floor_divide_by_power_of_ten is the same as removing the last n digits
        var result = decimo.biguint.arithmetics.floor_divide_by_power_of_ten(
            self, ndigits
        )
        var round_up: Bool = False

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

        if effective_mode == RoundingMode.down():
            pass
        elif effective_mode == RoundingMode.up():
            if self.number_of_trailing_zeros() < ndigits:
                round_up = True
        elif effective_mode == RoundingMode.half_up():
            if self.ith_digit(ndigits - 1) >= 5:
                round_up = True
        elif effective_mode == RoundingMode.half_down():
            var cut_off_digit = self.ith_digit(ndigits - 1)
            if cut_off_digit > 5:
                round_up = True
            elif cut_off_digit == 5:
                # Round up only if there are non-zero digits beyond the 5
                if self.number_of_trailing_zeros() < ndigits - 1:
                    round_up = True
        elif effective_mode == RoundingMode.half_even():
            var cut_off_digit = self.ith_digit(ndigits - 1)
            if cut_off_digit > 5:
                round_up = True
            elif cut_off_digit < 5:
                pass
            else:  # cut_off_digit == 5
                if self.number_of_trailing_zeros() < ndigits - 1:
                    round_up = True
                else:
                    round_up = self.ith_digit(ndigits) % 2 == 1
        # TODO: Remove this fallback once Mojo has proper enum support,
        # which will make exhaustive matching a compile-time guarantee.
        else:
            raise ValueError(
                function="BigUInt.remove_trailing_digits_with_rounding()",
                message=("Unknown rounding mode: " + String(rounding_mode)),
            )

        if round_up:
            decimo.biguint.arithmetics.add_inplace_by_uint32(result, UInt32(1))
            # Check whether rounding results in extra digit
            if result.is_power_of_10():
                if remove_extra_digit_due_to_rounding:
                    result = (
                        decimo.biguint.arithmetics.floor_divide_by_power_of_ten(
                            result, 1
                        )
                    )
        return result^
