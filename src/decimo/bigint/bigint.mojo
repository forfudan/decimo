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

"""Implements basic object methods for the BigInt type.

This module contains the basic object methods for the BigInt type.
These methods include constructors, life time methods, output dunders,
type-transfer dunders, basic arithmetic operation dunders, comparison
operation dunders, and other dunders that implement traits, as well as
mathematical methods that do not implement a trait.

BigInt is the core binary-represented arbitrary-precision signed integer
for the Decimo library. It uses base-2^64 representation with UInt64 words
in little-endian order, and a separate sign bit.
"""

from std.bit import bit_width, count_leading_zeros, pop_count
from std.memory import Pointer, unsafe_memcpy, unsafe_memset_zero
from std.sys import size_of

import decimo.bigint.arithmetics as bigint_arithmetics
import decimo.bigint.bitwise as bigint_bitwise
import decimo.bigint.comparison as bigint_comparison
import decimo.bigint.exponential as bigint_exponential
import decimo.bigint.number_theory as bigint_number_theory
import decimo.bigint.special as bigint_special
import decimo.str as decimo_str
from decimo.traits import Numeric, Parsable, Rootable
import decimo.numerals.chinese as decimo_chinese
from decimo.numerals.chinese import ChineseNumeralStyle
from decimo.biguint.biguint import BigUInt
from decimo.wordlist import WordList
from decimo.utility import unsigned_counterpart
from decimo.errors import (
    ConversionError,
    OverflowError,
    ValueError,
    ZeroDivisionError,
)

comptime INLINE_WORDS = 7
"""How many words a `BigInt` keeps inside itself before it allocates.

It has to cover *results*, not operands, and what sets it is the hundred-digit
case: a hundred digits is six 64-bit words and their sum is seven. At six the
cliff is plain -- every addition of two hundred-digit values allocates.

This was twelve while a word was 32 bits, chosen the same way: eleven words
for a hundred digits and twelve for their sum. Seven words is 448 bits against
that twelve's 384, so the inline range went *up* slightly even as the struct
grew by one word. Best of seven, three passes alternating between builds,
`-D ASSERT=none`, addition (ns):

    digits             10     28     40    100    120    150
    inline  6         5.0    5.3    5.9   46.8   47.7   47.3
    inline  7         5.4    5.1    5.4   10.0   45.4   44.5
    inline 10         6.8    6.0    6.1   12.7   11.1    8.6

Ten pushes the cliff past 150 digits and pays for it everywhere below forty,
where inline storage is the whole point -- an 80-byte struct is moved on every
operation whether or not the words are there. Seven is the first that covers a
hundred digits and the cheapest that does. At 1000 digits and above every
setting is within noise of the plain `List` this replaced.

GMP has no inline buffer at all, and pays for it. Adding two 100-digit
`mpz_t` takes about 15 ns into a fresh result and about 5 ns into a reused
one, so two thirds of it is `malloc` and `free`. An immutable value type
cannot reuse a destination, so this is where we come out ahead rather than
behind -- 1.4x at a hundred digits and 2.7x at ten. `docs/benchmarks.md`
carries the current figures.
"""

comptime Magnitude = WordList[DType.uint64, INLINE_WORDS]
"""The word storage for a `BigInt` magnitude, little-endian, base 2^64."""

# Type aliases
comptime BInt = BigInt
"""An arbitrary-precision signed integer, similar to Python's `int`."""


struct BigInt(
    Absable,
    Comparable,
    Copyable,
    FloatableRaising,
    IntableRaising,
    Movable,
    Numeric,
    Parsable,
    Rootable,
    Writable,
):
    """An arbitrary-precision signed integer, similar to Python's `int`.

    Notes:

    Internal Representation:

    Uses base-2^64 representation for the integer magnitude.
    BigInt uses a dynamic structure in memory, which contains:
    - A `Magnitude` of words for the magnitude, little-endian ordered.
      Each UInt64 word uses the full 64-bit range [0, 2^64 - 1].
    - A Bool for the sign (True = negative, False = non-negative).

    The absolute value is calculated as:

    |x| = words[0] + words[1] * 2^64 + words[2] * 2^128 + ... + words[n] * 2^(64n)

    The actual value is: (-1)^sign * |x|.

    This is analogous to GMP and most modern bigint libraries that use
    native-word-sized limbs with a separate sign.

    Arithmetic intermediate results use UInt128 for single products
    (UInt64 * UInt64 → UInt128, which is `MUL` plus `UMULH` on arm64) and for
    accumulation, which allows efficient schoolbook and Karatsuba
    multiplication on 64-bit hardware.

    Representation invariant:

    1. `words` is never empty. It always holds at least one word.
    2. There are no leading zero words: `words[len(words) - 1] != 0`, unless
       `len(words) == 1`.
    3. Unlike `BigUInt`, a word here uses the full `[0, 2^64 - 1]` range, so
       there is no per-word bound to check.

    Note that the sign of zero is *not* canonical: `is_zero()` scans the words
    rather than trusting the leading-zero rule, and `is_negative()` is
    `sign and not is_zero()`, so a zero carrying `sign = True` compares and
    prints correctly. Do not write code that reads `sign` alone to decide
    whether a value is negative.

    Call `assert_invariant()` to check the first two. It is a `debug_assert`,
    so it costs nothing in a normal build and fires in the test suite.
    """

    var words: Magnitude
    """A list of UInt64 words representing the magnitude in little-endian order.
    Each word uses the full [0, 2^64 - 1] range."""

    var sign: Bool
    """True if the number is negative, False if zero or positive."""

    # ===------------------------------------------------------------------=== #
    # Constants
    # ===------------------------------------------------------------------=== #

    comptime BITS_PER_WORD = 64
    """Number of bits per word."""
    comptime WORD_MAX: UInt64 = ~UInt64(0)
    """The maximum value of a single word (2^64 - 1)."""

    comptime ZERO = Self.zero()
    """The value 0."""
    comptime ONE = Self.one()
    """The value 1."""

    @always_inline
    @staticmethod
    def zero() -> Self:
        """Returns a BigInt with value 0.

        Returns:
            A `BigInt` with value 0.
        """
        return Self()

    @always_inline
    @staticmethod
    def one() -> Self:
        """Returns a BigInt with value 1.

        Returns:
            A `BigInt` with value 1.
        """
        return Self(raw_words=[UInt64(1)], sign=False)

    @always_inline
    @staticmethod
    def negative_one() -> Self:
        """Returns a BigInt with value -1.

        Returns:
            A `BigInt` with value -1.
        """
        return Self(raw_words=[UInt64(1)], sign=True)

    # ===------------------------------------------------------------------=== #
    # Constructors and life time dunder methods
    # ===------------------------------------------------------------------=== #

    def __init__(out self):
        """Initializes a BigInt with value 0."""
        self.words = [UInt64(0)]
        self.sign = False

    def __init__(out self, *, uninitialized_capacity: Int):
        """Creates an uninitialized BigInt with a given word capacity.
        The words list is empty; caller must append words before use.

        Args:
            uninitialized_capacity: The initial capacity for the words list.
        """
        self.words = Magnitude(capacity=uninitialized_capacity)
        self.sign = False

    def __init__(out self, *, var raw_words: Magnitude, sign: Bool):
        """Initializes a BigInt from a list of raw words without
        validation. The caller must ensure words are in valid little-endian
        form with no unnecessary leading zeros.

        Args:
            raw_words: A list of UInt64 words in little-endian order.
            sign: True if negative, False if non-negative.

        Notes:
            **UNSAFE**: Does not strip leading zeros or check for -0.
            Always ensures at least one word exists.
        """
        if len(raw_words) == 0:
            self.words = [UInt64(0)]
            self.sign = False
        else:
            self.words = raw_words^
            self.sign = sign

    def __init__(out self, value: String) raises:
        """Initializes a BigInt from a decimal string representation.

        Args:
            value: The string representation of the integer.

        Raises:
            ConversionError: If the string cannot be converted to a BigInt.
        """
        self = Self.from_string(value)

    @implicit
    def __init__(out self, value: Scalar) where value.dtype.is_integral():
        """Constructs a BigInt from an integral scalar.
        This includes all SIMD integral types, such as Int8, Int16, UInt32, etc.

        Constraints:
            The dtype of the scalar must be integral.

        Args:
            value: The integral scalar value to convert.
        """
        self = Self.from_integral_scalar(value)

    # ===------------------------------------------------------------------=== #
    # Constructing methods that are not dunders
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def from_integral_scalar[
        dtype: DType, //
    ](value: SIMD[dtype, 1]) -> Self where dtype.is_integral():
        """Initializes a BigInt from an integral scalar.
        This includes all SIMD integral types:
        Int8, Int16, Int32, Int64, Int128, Int256,
        UInt8, UInt16, UInt32, UInt64, UInt128, UInt256,
        and the platform-sized Int (DType.int) and UInt (DType.uint).

        Constraints:
            The dtype must be integral.

        Args:
            value: The Scalar value to be converted to BigInt.

        Returns:
            The BigInt representation of the Scalar value.

        Parameters:
            dtype: The data type of the scalar value.
        """

        if value == 0:
            return Self()

        # Determine the sign of the value
        var sign = False
        comptime if dtype.is_signed():
            sign = value < 0

        # Keep the magnitude in an unsigned word of the same width.
        # The unsigned counterpart has the same bit width, just a larger range.
        comptime unsigned_dtype = unsigned_counterpart[dtype]()
        var magnitude: Scalar[unsigned_dtype]

        # [Mojo Miji]
        # Use the overflow trick here:
        # Bit at position SIGNED_MAX + 1 will be interpreted by SIGNED type
        # as SIGNED_MIN, and then it increases until it reaches -1.
        # So bit position of SIGNED negative value x (x < 0) is
        # SIGNED_MAX + 1 + |SIGNED_MIN| - |x|
        # = SIGNED_MAX + 1 + (SIGNED_MAX + 1) + x
        # = 2 * SIGNED_MAX + 2 + x
        # So UNSIGNED 0 - (bit position of SIGNED x)
        # = UNSIGNED_MAX + 1 - (2 * SIGNED_MAX + 2 + x)
        # = UNSIGNED_MAX + 1 - 2 * (UNSIGNED_MAX - 1) / 2 - 2 -x
        # = UNSIGNED_MAX + 1 - UNSIGNED_MAX + 1 - 2 - x
        # = - x
        # = |x|
        # Yes, it is the magnitude of the signed negative value x.
        comptime if dtype.is_signed():
            if sign:
                magnitude = Scalar[unsigned_dtype](0) - Scalar[unsigned_dtype](
                    value
                )
            else:
                magnitude = Scalar[unsigned_dtype](value)
        else:
            magnitude = Scalar[unsigned_dtype](value)

        # Split the magnitude into base-2^64 words, least significant first.
        # The peeling loop below is parameterized by `BITS_PER_WORD` for
        # future extension to other word sizes (e.g. 64-bit words).
        comptime value_bits = size_of[Scalar[unsigned_dtype]]() * 8
        comptime number_of_words = (
            value_bits + Self.BITS_PER_WORD - 1
        ) // Self.BITS_PER_WORD  # Trick to round up division
        var words = Magnitude(capacity=number_of_words)

        comptime for i in range(number_of_words):
            words.append(
                UInt64(magnitude & Scalar[unsigned_dtype](Self.WORD_MAX))
            )

            comptime if i < number_of_words - 1:  # No need after reading the last word
                magnitude >>= (
                    Self.BITS_PER_WORD
                )  # Pop the least significant bits (word)

        # Trim the leading zero words, but keep at least one.
        while len(words) > 1 and words[len(words) - 1] == 0:
            words.shrink(len(words) - 1)

        return Self(raw_words=words^, sign=sign)

    @staticmethod
    def from_string(value: String) raises -> Self:
        """Creates a BigInt from a string representation.
        The string is normalized with `decimo.str.parse_numeric_string()`.

        Supports signs, commas, underscores, spaces, scientific notation,
        and decimal points (the fractional part must be zero for integers).

        Uses divide-and-conquer base conversion for large numbers
        (O(M(n)·log n)) and simple multiply-and-add for small numbers (O(n²)).

        Args:
            value: The string representation (e.g. "12345", "-98765",
                "1_000_000", "1.23e5", "1,234,567").

        Returns:
            The BigInt representation.

        Raises:
            ConversionError: If the string cannot be parsed as an integer.
        """
        # Use the shared string parser for format handling
        var _tuple: Tuple[List[UInt8], Int, Bool]
        try:
            _tuple = decimo_str.parse_numeric_string(value)
        except e:
            raise ConversionError(
                function="BigInt.from_string(value: String)",
                message=(
                    'The input value "'
                    + value
                    + '" cannot be parsed as an integer.\n'
                    + String(e)
                ),
            )
        ref coef: List[UInt8] = _tuple[0]
        var scale: Int = _tuple[1]
        var sign: Bool = _tuple[2]

        # Check if the number is zero
        if len(coef) == 1 and coef[0] == UInt8(0):
            return Self()

        # Handle scale: positive scale means fractional digits exist.
        # For BigInt (integer type), the fractional part must be zero.
        if scale > 0:
            if scale >= len(coef):
                raise ConversionError(
                    function="BigInt.from_string(value: String)",
                    message=(
                        'The input value "'
                        + value
                        + '" is not an integer.\n'
                        + "The scale is larger than the number of digits."
                    ),
                )
            # Check that the fractional digits are all zero
            var coef_len = len(coef)
            for i in range(1, scale + 1):
                if coef[coef_len - i] != 0:
                    raise ConversionError(
                        function="BigInt.from_string(value: String)",
                        message=(
                            'The input value "'
                            + value
                            + '" is not an integer.\n'
                            + "The fractional part is not zero."
                        ),
                    )
            # Remove fractional zeros from coefficient
            coef.resize(len(coef) - scale, UInt8(0))

        # Handle negative scale: it means trailing zeros to append.
        # e.g. "1.234e8" -> coef=[1,2,3,4], scale=-4, meaning 12340000
        if scale < 0:
            var zeros_to_add = -scale
            for _ in range(zeros_to_add):
                coef.append(0)

        var digit_count = len(coef)

        # coef already contains digit values 0-9, pass directly.
        # Choose conversion strategy based on digit count.
        var result: Self
        if digit_count <= _DC_FROM_STR_ENTRY_THRESHOLD:
            result = _from_decimal_digits_simple(coef, 0, digit_count)
        else:
            try:
                result = _from_decimal_digits_dc(coef, 0, digit_count)
            except e:
                # Fallback to simple O(n²) method if D&C raises an Error
                result = _from_decimal_digits_simple(coef, 0, digit_count)

        result.sign = sign
        return result^

    @staticmethod
    def from_biguint(magnitude: BigUInt, sign: Bool = False) -> Self:
        """Converts a base-10^9 magnitude and a sign to a base-2^64 BigInt.

        Args:
            magnitude: The unsigned base-10^9 magnitude to convert.
            sign: Whether the result is negative. Ignored when the magnitude
                is zero, which is always stored unsigned.

        Returns:
            The BigInt (base-2^64) representation.
        """
        if magnitude.is_zero():
            return Self()

        # Convert from base 10^9 to base 2^64 using repeated division
        var div_words = Magnitude(capacity=len(magnitude.words))
        for word in magnitude.words:
            div_words.append(UInt64(word))
        var result = Self(uninitialized_capacity=len(magnitude.words))

        var all_zero = False
        while not all_zero:
            # The dividend is base 10^9 and the divisor is 2^64, so the
            # running remainder is up to `2^64 - 1` and `remainder * 10^9`
            # needs the wider type.
            var remainder = UInt128(0)
            for i in range(len(div_words) - 1, -1, -1):
                var temp = remainder * UInt128(BigUInt.BASE) + UInt128(
                    div_words[i]
                )
                div_words[i] = UInt64(temp >> 64)
                remainder = temp & UInt128(~UInt64(0))

            # Remove leading zeros from dividend
            while len(div_words) > 1 and div_words[len(div_words) - 1] == 0:
                div_words.shrink(len(div_words) - 1)

            result.words.append(UInt64(remainder))

            # Check if dividend is zero
            all_zero = True
            for word in div_words:
                if word != 0:
                    all_zero = False
                    break

        result.sign = sign
        return result^

    # ===------------------------------------------------------------------=== #
    # Output dunders, type-transfer dunders
    # ===------------------------------------------------------------------=== #

    def __int__(self) raises -> Int:
        """Returns the number as Int.
        See `to_int()` for more information.

        Returns:
            The `Int` representation.

        Raises:
            OverflowError: If the number exceeds the size of Int.
        """
        return self.to_int()

    def __float__(self) raises -> Float64:
        """Converts the BigInt to a floating-point number.

        Matches Python's `float(n)` for `int` objects.

        Note: Large values may lose precision or overflow to `inf`.

        Returns:
            The value as a Float64.

        Raises:
            Error: Propagated from Float64 conversion.
        """
        return Float64(self.to_string())

    def write_repr_to[W: Writer](self, mut writer: W):
        """Writes the debug representation to a writer.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        writer.write('BigInt("', self.to_string(), '")')

    def write_to[W: Writer](self, mut writer: W):
        """Writes the decimal string representation to a writer.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        writer.write(self.to_string())

    # ===------------------------------------------------------------------=== #
    # Type-transfer or output methods that are not dunders
    # ===------------------------------------------------------------------=== #

    def to_int(self) raises -> Int:
        """Returns the number as Int.

        Returns:
            The number as Int.

        Raises:
            OverflowError: If the number exceeds the size of Int.
        """
        # A word is as wide as an `Int`, so anything past the first is an
        # overflow on its own.
        if len(self.words) > 1:
            raise OverflowError(
                message="The number exceeds the size of Int",
                function="BigInt.to_int()",
            )

        var magnitude: UInt64 = self.words[0]

        if self.sign:
            # Negative: check against Int.MIN magnitude (2^63)
            if magnitude > UInt64(9_223_372_036_854_775_808):
                raise OverflowError(
                    message="The number exceeds the size of Int",
                    function="BigInt.to_int()",
                )
            if magnitude == UInt64(9_223_372_036_854_775_808):
                return Int.MIN
            return -Int(magnitude)
        else:
            # Positive: check against Int.MAX (2^63 - 1)
            if magnitude > UInt64(9_223_372_036_854_775_807):
                raise OverflowError(
                    message="The number exceeds the size of Int",
                    function="BigInt.to_int()",
                )
            return Int(magnitude)

    def to_biguint(self) -> BigUInt:
        """Converts the magnitude of the BigInt to a base-10^9 BigUInt.

        The sign is dropped: the result is the absolute value. Use
        `is_negative()` to recover it.

        Returns:
            The magnitude as a `BigUInt` (base-10^9).
        """
        if self.is_zero():
            return BigUInt()

        var effective_words = len(self.words)
        while effective_words > 1 and self.words[effective_words - 1] == 0:
            effective_words -= 1

        # Above the divide-and-conquer threshold, split on powers of 10^9:
        # repeated division is O(n^2), while the recursion is O(M(n) log n)
        # and lands each half on a base-10^18 word boundary, so the words go
        # straight into the result with no decimal string in between.
        var chunks: List[UInt64]
        if effective_words > _DC_TO_STR_ENTRY_THRESHOLD:
            try:
                chunks = _magnitude_to_chunks_dc(self.words, effective_words)
            except:
                # Fall through to the simple path if D&C raises.
                chunks = _magnitude_to_chunks_simple(
                    self.words, effective_words
                )
        else:
            chunks = _magnitude_to_chunks_simple(self.words, effective_words)

        # A chunk is `10^18`, which is `(10^9)^2`, so each one splits into
        # exactly two of `BigUInt`'s words. That is the whole reason the chunk
        # is eighteen digits rather than the nineteen a word would hold.
        var words = List[UInt32](capacity=2 * len(chunks))
        for i in range(len(chunks)):
            var chunk = chunks[i]
            words.append(UInt32(chunk % 1_000_000_000))
            words.append(UInt32(chunk // 1_000_000_000))
        while len(words) > 1 and words[len(words) - 1] == 0:
            words.shrink(len(words) - 1)
        return BigUInt(raw_words=words^)

    def to_string(self, line_width: Int = 0) -> String:
        """Returns the decimal string representation of the BigInt.

        Uses divide-and-conquer base conversion for large numbers (O(M(n)·log n))
        and simple repeated division by 10^9 for small numbers (O(n²)).

        Args:
            line_width: The maximum line width for the string representation.
                Default is 0, which means no line width limit.

        Returns:
            The decimal string (e.g. "-12345").
        """
        if self.is_zero():
            return String("0")

        # Get effective word count (excluding leading zeros)
        var eff_words = len(self.words)
        while eff_words > 1 and self.words[eff_words - 1] == 0:
            eff_words -= 1

        # Choose conversion strategy based on magnitude size
        var magnitude_str: String
        if eff_words <= _DC_TO_STR_ENTRY_THRESHOLD:
            magnitude_str = _magnitude_to_decimal_simple(self.words, eff_words)
        else:
            try:
                magnitude_str = _magnitude_to_decimal_dc(self.words, eff_words)
            except e:
                # Fallback to simple O(n²) method if D&C raises an Error
                magnitude_str = _magnitude_to_decimal_simple(
                    self.words, eff_words
                )

        var result: String
        if self.sign:
            result = String("-") + magnitude_str
        else:
            result = magnitude_str^

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

    def to_decimal_string(self, line_width: Int = 0) -> String:
        """Returns the decimal string representation of the BigInt.

        Deprecated: Use `to_string(line_width=...)` instead.

        Args:
            line_width: The maximum line width for the output.

        Returns:
            The decimal string representation.
        """
        return self.to_string(line_width=line_width)

    def to_string_with_separators(self, separator: String = "_") -> String:
        """Returns string representation of the BigInt with separators.

        Args:
            separator: The separator string. Default is "_".

        Returns:
            The string representation of the BigInt with separators.
        """

        var result = self.to_string()
        var start_idx = 0
        if self.sign:
            start_idx = 1  # Skip the minus sign

        var digits_part = String(result[byte=start_idx:])
        var end = digits_part.byte_length()
        var start = end - 3
        var blocks = List[String](capacity=digits_part.byte_length() // 3 + 1)
        while start > 0:
            blocks.append(String(digits_part[byte=start:end]))
            end = start
            start = end - 3
        blocks.append(String(digits_part[byte=0:end]))
        blocks.reverse()
        var formatted = separator.join(blocks)

        if self.sign:
            return String("-") + formatted
        return formatted^

    def to_chinese(
        self,
        style: ChineseNumeralStyle = ChineseNumeralStyle.simplified(),
        max_digits: Int = decimo_chinese.MAX_CHINESE_NUMERAL_DIGITS,
    ) raises -> String:
        """Returns the number written in Chinese numerals.

        The digits are read with the 十/百/千/万 units within each section of
        eight digits, and the sections are joined by 亿, which multiplies
        everything read before it.  See `decimo.numerals.chinese` for the
        details of the magnitude system.

        Args:
            style: The numeral style to render with.  Defaults to the everyday
                simplified-Chinese style; `ChineseNumeralStyle` also offers
                financial (大写) and traditional (繁体) presets.
            max_digits: The largest number of digits the reading may write out.
                Values with more digits than this -- `factorial(10000)`, say --
                raise instead, since their reading is far past anything usable.
                Pass `0` to lift the cap.

        Examples:

        ```console
        BigInt("15").to_chinese()           -> 十五
        BigInt("-100000001").to_chinese()   -> 负一亿零一
        BigInt("123456789").to_chinese()    -> 一亿二千三百四十五万六千七百八十九
        BigInt("1050").to_chinese(
            ChineseNumeralStyle.simplified_financial()
        )                                   -> 壹仟零伍拾
        ```
        End of examples.

        Returns:
            The Chinese reading of the number.

        Raises:
            ValueError: If the number cannot be rendered as a decimal string,
                or has more than `max_digits` digits.
        """
        decimo_chinese._check_digit_budget(
            self.number_of_digits(), 0, max_digits, "BigInt.to_chinese()"
        )
        return decimo_chinese.decimal_string_to_chinese(
            self.to_string(), style, max_digits
        )

    def to_hex_string(self) -> String:
        """Returns a hexadecimal string representation of the BigInt.

        Returns:
            The hexadecimal string (e.g. "0x1A2B3C").
        """
        if self.is_zero():
            return "0x0"

        var result = String()
        if self.sign:
            result += "-"
        result += "0x"

        var first_word = True
        for i in range(len(self.words) - 1, -1, -1):
            var word = self.words[i]
            if first_word:
                if word != 0:
                    result += hex(word)[byte=2:]
                    first_word = False
            else:
                var h = hex(word)[byte=2:]
                for _ in range(8 - h.byte_length()):
                    result += "0"
                result += h

        if first_word:
            result += "0"

        return result

    def to_binary_string(self) -> String:
        """Returns a binary string representation of the BigInt.

        Returns:
            The binary string (e.g. "0b110101").
        """
        if self.is_zero():
            return "0b0"

        var result = String()
        if self.sign:
            result += "-"
        result += "0b"

        var first_word = True
        for i in range(len(self.words) - 1, -1, -1):
            var word = self.words[i]
            if first_word:
                if word != 0:
                    result += bin(word)[byte=2:]
                    first_word = False
            else:
                var b = bin(word)[byte=2:]
                for _ in range(BigInt.BITS_PER_WORD - b.byte_length()):
                    result += "0"
                result += b

        if first_word:
            result += "0"

        return result

    # ===------------------------------------------------------------------=== #
    # Unary arithmetic dunders
    # ===------------------------------------------------------------------=== #

    def __neg__(self) -> Self:
        """Returns the negation of the BigInt.

        Returns:
            The negated value.
        """
        if self.is_zero():
            return Self()
        return Self(raw_words=self.words.copy(), sign=not self.sign)

    def __abs__(self) -> Self:
        """Returns the absolute value of the BigInt.

        Returns:
            The absolute value.
        """
        return Self(raw_words=self.words.copy(), sign=False)

    @always_inline
    def __bool__(self) -> Bool:
        """Returns True if the number is nonzero.

        This enables `if n:` syntax, consistent with Python's `int`.

        Returns:
            `True` if non-zero, `False` otherwise.
        """
        return not self.is_zero()

    @always_inline
    def __pos__(self) -> Self:
        """Returns the number unchanged (unary plus).

        This enables `+n` syntax, consistent with Python's `int`.

        Returns:
            A copy of this value.
        """
        return Self(raw_words=self.words.copy(), sign=self.sign)

    @always_inline
    def __ceil__(self) -> Self:
        """Returns self unchanged. Integers are already integers.

        This enables `math.ceil()` compatibility with Python's `int`.

        Returns:
            A copy of this value.
        """
        return Self(raw_words=self.words.copy(), sign=self.sign)

    @always_inline
    def __floor__(self) -> Self:
        """Returns self unchanged. Integers are already integers.

        This enables `math.floor()` compatibility with Python's `int`.

        Returns:
            A copy of this value.
        """
        return Self(raw_words=self.words.copy(), sign=self.sign)

    @always_inline
    def __trunc__(self) -> Self:
        """Returns self unchanged. Integers are already integers.

        This enables `math.trunc()` compatibility with Python's `int`.

        Returns:
            A copy of this value.
        """
        return Self(raw_words=self.words.copy(), sign=self.sign)

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
        return bigint_arithmetics.add(self, other)

    @always_inline
    def __sub__(self, other: Self) -> Self:
        """Subtracts two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The difference of the two values.
        """
        return bigint_arithmetics.subtract(self, other)

    @always_inline
    def __mul__(self, other: Self) -> Self:
        """Multiplies two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The product of the two values.
        """
        return bigint_arithmetics.multiply(self, other)

    @always_inline
    def __truediv__(self, other: Self) raises -> Self:
        """Divides two values, truncating toward zero.

        `/` on integers is closed and truncating, matching Mojo's own `Int`:
        `Int(-7) / Int(2)` is `-3` while `Int(-7) // Int(2)` is `-4`. The two
        operators are therefore different operations on a `BigInt`, not
        synonyms, and they differ exactly when the operands have opposite
        signs.

        Args:
            other: The right-hand side operand.

        Returns:
            The quotient, rounded toward zero.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        try:
            return bigint_arithmetics.truncate_divide(self, other)
        except e:
            raise ZeroDivisionError(
                message="See the above exception.",
                function="BigInt.__truediv__()",
                previous_error=e^,
            )

    @always_inline
    def __floordiv__(self, other: Self) raises -> Self:
        """Divides two values using floor division.

        Args:
            other: The right-hand side operand.

        Returns:
            The quotient, rounded toward negative infinity.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        try:
            return bigint_arithmetics.floor_divide(self, other)
        except e:
            raise ZeroDivisionError(
                message="See the above exception.",
                function="BigInt.__floordiv__()",
                previous_error=e^,
            )

    @always_inline
    def __mod__(self, other: Self) raises -> Self:
        """Returns the remainder of division.

        Args:
            other: The right-hand side operand.

        Returns:
            The floor remainder with the same sign as the divisor.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        try:
            return bigint_arithmetics.floor_modulo(self, other)
        except e:
            raise ZeroDivisionError(
                message="See the above exception.",
                function="BigInt.__mod__()",
                previous_error=e^,
            )

    @always_inline
    def __divmod__(self, other: Self) raises -> Tuple[Self, Self]:
        """Returns the quotient and remainder of division.

        Args:
            other: The right-hand side operand.

        Returns:
            A tuple of (quotient, remainder) using floor division.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        try:
            return bigint_arithmetics.floor_divmod(self, other)
        except e:
            raise ZeroDivisionError(
                message="See the above exception.",
                function="BigInt.__divmod__()",
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
            ValueError: If the exponent is negative.
            OverflowError: If the exponent is too large to fit in Int.
        """
        return self.power(exponent)

    @always_inline
    def __pow__(self, exponent: Int) raises -> Self:
        """Raises to a power.

        Args:
            exponent: The exponent.

        Returns:
            The result of raising to the given power.

        Raises:
            ValueError: If the exponent is negative or too large.
        """
        return self.power(exponent)

    @always_inline
    def __lshift__(self, shift: Int) -> Self:
        """Returns self << shift (multiply by 2^shift).

        Args:
            shift: The number of bits to shift left.

        Returns:
            The left-shifted value.
        """
        return bigint_arithmetics.left_shift(self, shift)

    @always_inline
    def __rshift__(self, shift: Int) -> Self:
        """Returns self >> shift (floor divide by 2^shift).

        Args:
            shift: The number of bits to shift right.

        Returns:
            The right-shifted value.
        """
        return bigint_arithmetics.right_shift(self, shift)

    # ===------------------------------------------------------------------=== #
    # Basic binary right-side arithmetic operation dunders
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __radd__(self, other: Self) -> Self:
        """Adds two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The sum of the two values.
        """
        return bigint_arithmetics.add(self, other)

    @always_inline
    def __rsub__(self, other: Self) -> Self:
        """Subtracts two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The difference of the two values.
        """
        return bigint_arithmetics.subtract(other, self)

    @always_inline
    def __rmul__(self, other: Self) -> Self:
        """Multiplies two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The product of the two values.
        """
        return bigint_arithmetics.multiply(self, other)

    @always_inline
    def __rfloordiv__(self, other: Self) raises -> Self:
        """Divides two values using floor division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The quotient, rounded toward negative infinity.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint_arithmetics.floor_divide(other, self)

    @always_inline
    def __rmod__(self, other: Self) raises -> Self:
        """Returns the remainder of division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The floor remainder with the same sign as the divisor.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint_arithmetics.floor_modulo(other, self)

    @always_inline
    def __rdivmod__(self, other: Self) raises -> Tuple[Self, Self]:
        """Returns the quotient and remainder of division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            A tuple of (quotient, remainder) using floor division.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint_arithmetics.floor_divmod(other, self)

    @always_inline
    def __rpow__(self, base: Self) raises -> Self:
        """Raises to a power (reflected).

        Args:
            base: The base to raise to this power.

        Returns:
            The result of raising the base to this power.

        Raises:
            ValueError: If the exponent is negative.
        """
        return base.power(self)

    # ===------------------------------------------------------------------=== #
    # Basic binary augmented arithmetic assignments dunders
    # (+=, -=, *=, //=, %=)
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __iadd__(mut self, other: Self):
        """True in-place addition: mutates self.words directly.

        Args:
            other: The right-hand side operand.
        """
        bigint_arithmetics.add_inplace(self, other)

    @always_inline
    def __iadd__(mut self, other: Int):
        """True in-place addition with Int: mutates self.words directly.

        Args:
            other: The right-hand side operand.
        """
        bigint_arithmetics.add_int_inplace(self, other)

    @always_inline
    def __isub__(mut self, other: Self):
        """True in-place subtraction: mutates self.words directly.

        Args:
            other: The right-hand side operand.
        """
        bigint_arithmetics.subtract_inplace(self, other)

    @always_inline
    def __imul__(mut self, other: Self):
        """True in-place multiplication: computes product into self.words.

        Args:
            other: The right-hand side operand.
        """
        bigint_arithmetics.multiply_inplace(self, other)

    @always_inline
    def __ifloordiv__(mut self, other: Self) raises:
        """True in-place floor division: moves quotient into self.words.

        Args:
            other: The right-hand side operand.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        bigint_arithmetics.floor_divide_inplace(self, other)

    @always_inline
    def __imod__(mut self, other: Self) raises:
        """True in-place modulo: moves remainder into self.words.

        Args:
            other: The right-hand side operand.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        bigint_arithmetics.floor_modulo_inplace(self, other)

    @always_inline
    def __ilshift__(mut self, shift: Int):
        """True in-place left shift: mutates self.words directly.

        Args:
            shift: The number of bits to shift left.
        """
        bigint_arithmetics.left_shift_inplace(self, shift)

    @always_inline
    def __irshift__(mut self, shift: Int):
        """True in-place right shift: mutates self.words directly.

        Args:
            shift: The number of bits to shift right.
        """
        bigint_arithmetics.right_shift_inplace(self, shift)

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
            `True` if self is greater than other, `False` otherwise.
        """
        return bigint_comparison.greater(self, other)

    @always_inline
    def __gt__(self, other: Scalar) -> Bool where other.dtype.is_integral():
        """Returns True if self > other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if self is greater than other, `False` otherwise.
        """
        return bigint_comparison.greater(self, Self.from_integral_scalar(other))

    @always_inline
    def __ge__(self, other: Self) -> Bool:
        """Returns True if self >= other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if self is greater than or equal to other, `False` otherwise.
        """
        return bigint_comparison.greater_equal(self, other)

    @always_inline
    def __ge__(self, other: Scalar) -> Bool where other.dtype.is_integral():
        """Returns True if self >= other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if self is greater than or equal to other, `False` otherwise.
        """
        return bigint_comparison.greater_equal(
            self, Self.from_integral_scalar(other)
        )

    @always_inline
    def __lt__(self, other: Self) -> Bool:
        """Returns True if self < other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if self is less than other, `False` otherwise.
        """
        return bigint_comparison.less(self, other)

    @always_inline
    def __lt__(self, other: Scalar) -> Bool where other.dtype.is_integral():
        """Returns True if self < other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if self is less than other, `False` otherwise.
        """
        return bigint_comparison.less(self, Self.from_integral_scalar(other))

    @always_inline
    def __le__(self, other: Self) -> Bool:
        """Returns True if self <= other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if self is less than or equal to other, `False` otherwise.
        """
        return bigint_comparison.less_equal(self, other)

    @always_inline
    def __le__(self, other: Scalar) -> Bool where other.dtype.is_integral():
        """Returns True if self <= other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if self is less than or equal to other, `False` otherwise.
        """
        return bigint_comparison.less_equal(
            self, Self.from_integral_scalar(other)
        )

    @always_inline
    def __eq__(self, other: Self) -> Bool:
        """Returns True if self == other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if the two values are equal, `False` otherwise.
        """
        return bigint_comparison.equal(self, other)

    @always_inline
    def __eq__(self, other: Scalar) -> Bool where other.dtype.is_integral():
        """Returns True if self == other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if the two values are equal, `False` otherwise.
        """
        return bigint_comparison.equal(self, Self.from_integral_scalar(other))

    @always_inline
    def __ne__(self, other: Self) -> Bool:
        """Returns True if self != other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if the two values are not equal, `False` otherwise.
        """
        return bigint_comparison.not_equal(self, other)

    @always_inline
    def __ne__(self, other: Scalar) -> Bool where other.dtype.is_integral():
        """Returns True if self != other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if the two values are not equal, `False` otherwise.
        """
        return bigint_comparison.not_equal(
            self, Self.from_integral_scalar(other)
        )

    # ===------------------------------------------------------------------=== #
    # Mathematical methods that do not implement a trait (not a dunder)
    # ===------------------------------------------------------------------=== #

    @always_inline
    def truncate_divide(self, other: Self) raises -> Self:
        """Performs a truncated division of two BigInt numbers.
        See `truncate_divide()` for more information.

        Args:
            other: The divisor.

        Returns:
            The quotient, truncated toward zero.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint_arithmetics.truncate_divide(self, other)

    @always_inline
    def floor_modulo(self, other: Self) raises -> Self:
        """Performs a floor modulo of two BigInt numbers.
        See `floor_modulo()` for more information.

        Args:
            other: The divisor.

        Returns:
            The floor remainder with the same sign as the divisor.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint_arithmetics.floor_modulo(self, other)

    @always_inline
    def truncate_modulo(self, other: Self) raises -> Self:
        """Performs a truncated modulo of two BigInt numbers.
        See `truncate_modulo()` for more information.

        Args:
            other: The divisor.

        Returns:
            The truncated remainder with the same sign as the dividend.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return bigint_arithmetics.truncate_modulo(self, other)

    def power(self, exponent: Int) raises -> Self:
        """Raises the BigInt to the power of an integer exponent.

        Args:
            exponent: The non-negative exponent.

        Returns:
            The result of self raised to the given exponent.

        Raises:
            ValueError: If the exponent is negative.
            ValueError: If the exponent is too large (>= 1_000_000_000).
        """
        return bigint_arithmetics.power(self, exponent)

    def power(self, exponent: Self) raises -> Self:
        """Raises the BigInt to the power of another BigInt.

        Args:
            exponent: The exponent (must be non-negative and fit in Int).

        Returns:
            The result of self raised to the given exponent.

        Raises:
            ValueError: If the exponent is negative.
            OverflowError: If the exponent is too large to fit in Int.
        """
        if exponent.is_negative():
            raise ValueError(
                message="Exponent must be non-negative",
                function="BigInt.power()",
            )
        var exp_int: Int
        try:
            exp_int = exponent.to_int()
        except e:
            raise OverflowError(
                message="Exponent too large to fit in Int",
                function="BigInt.power()",
            )
        return self.power(exp_int)

    def sqrt(self) raises -> Self:
        """Returns the integer square root of this BigInt.

        The result is the largest integer y such that y * y <= self
        (for non-negative self). Only defined for non-negative values.

        Returns:
            The integer square root.

        Raises:
            Error: If the value is negative.
        """
        return bigint_exponential.sqrt(self)

    def isqrt(self) raises -> Self:
        """Returns the integer square root of this BigInt.
        It is equal to `sqrt()`.

        Returns:
            The integer square root.

        Raises:
            Error: If the value is negative.
        """
        return bigint_exponential.sqrt(self)

    def factorial(self) raises -> Self:
        """Returns the factorial of this value.

        Returns:
            `self!` (`0! == 1`).

        Raises:
            ValueError: If `self` is negative or larger than 10^6.
        """
        return bigint_special.factorial(self)

    def permutation(self, k: Int) raises -> Self:
        """Returns the number of `k`-permutations of `self` items.

        `P(n, k) = n! / (n - k)!`, where `n = self`.

        Args:
            k: The number of ordered positions to fill (non-negative).

        Returns:
            `P(self, k)`; 0 when `k > self`, and `P(self, 0) == 1`.

        Raises:
            ValueError: If `self` or `k` is negative, if `k` is larger than
                10^6, or if `self` is larger than `2^32 - 1`.
        """
        return bigint_special.permutation(self, k)

    @always_inline
    def compare_magnitudes(self, other: Self) -> Int8:
        """Compares the magnitudes (absolute values) of two BigInt numbers.
        See `compare_magnitudes()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            1 if |self| > |other|, 0 if equal, -1 if |self| < |other|.
        """
        return bigint_comparison.compare_magnitudes(self, other)

    @always_inline
    def compare(self, other: Self) -> Int8:
        """Compares two BigInt numbers.
        See `compare()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            1 if self > other, 0 if equal, -1 if self < other.
        """
        return bigint_comparison.compare(self, other)

    # ===------------------------------------------------------------------=== #
    # Bitwise operations
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __and__(self, other: Self) -> Self:
        """Returns self & other (bitwise AND, Python two's complement semantics).

        Args:
            other: The right-hand side operand.

        Returns:
            The bitwise AND of the two values.
        """
        return bigint_bitwise.bitwise_and(self, other)

    @always_inline
    def __and__(self, other: Scalar) -> Self where other.dtype.is_integral():
        """Returns self & other where other is an integral scalar.

        Args:
            other: The right-hand side operand.

        Returns:
            The bitwise AND of the two values.
        """
        return bigint_bitwise.bitwise_and(self, Self(other))

    @always_inline
    def __or__(self, other: Self) -> Self:
        """Returns self | other (bitwise OR, Python two's complement semantics).

        Args:
            other: The right-hand side operand.

        Returns:
            The bitwise OR of the two values.
        """
        return bigint_bitwise.bitwise_or(self, other)

    @always_inline
    def __or__(self, other: Scalar) -> Self where other.dtype.is_integral():
        """Returns self | other where other is an integral scalar.

        Args:
            other: The right-hand side operand.

        Returns:
            The bitwise OR of the two values.
        """
        return bigint_bitwise.bitwise_or(self, Self(other))

    @always_inline
    def __xor__(self, other: Self) -> Self:
        """Returns self ^ other (bitwise XOR, Python two's complement semantics).

        Args:
            other: The right-hand side operand.

        Returns:
            The bitwise XOR of the two values.
        """
        return bigint_bitwise.bitwise_xor(self, other)

    @always_inline
    def __xor__(self, other: Scalar) -> Self where other.dtype.is_integral():
        """Returns self ^ other where other is an integral scalar.

        Args:
            other: The right-hand side operand.

        Returns:
            The bitwise XOR of the two values.
        """
        return bigint_bitwise.bitwise_xor(self, Self(other))

    @always_inline
    def __invert__(self) -> Self:
        """Returns ~self (bitwise NOT, Python two's complement semantics).

        Returns:
            The bitwise complement, equal to -(self + 1).
        """
        return bigint_bitwise.bitwise_not(self)

    @always_inline
    def __iand__(mut self, other: Self):
        """True in-place bitwise AND: mutates self.words directly.

        Args:
            other: The right-hand side operand.
        """
        bigint_bitwise.bitwise_and_inplace(self, other)

    @always_inline
    def __ior__(mut self, other: Self):
        """True in-place bitwise OR: mutates self.words directly.

        Args:
            other: The right-hand side operand.
        """
        bigint_bitwise.bitwise_or_inplace(self, other)

    @always_inline
    def __ixor__(mut self, other: Self):
        """True in-place bitwise XOR: mutates self.words directly.

        Args:
            other: The right-hand side operand.
        """
        bigint_bitwise.bitwise_xor_inplace(self, other)

    # ===------------------------------------------------------------------=== #
    # Number-theoretic methods
    # ===------------------------------------------------------------------=== #

    @always_inline
    def gcd(self, other: Self) raises -> Self:
        """Returns the greatest common divisor of self and other.

        Args:
            other: The second value for the GCD computation.

        Returns:
            The greatest common divisor of the two values.

        Raises:
            Error: Propagated from underlying BigInt arithmetic.
        """
        return bigint_number_theory.gcd(self, other)

    @always_inline
    def extended_gcd(self, other: Self) raises -> Tuple[Self, Self, Self]:
        """Returns a tuple (g, x, y) such that g = gcd(self, other) and
        self*x + other*y = g.

        This is useful for solving linear Diophantine equations and for
        computing modular inverses.

        Returns:
            A tuple (g, x, y) where g is the gcd of self and other, and
            x and y are the coefficients satisfying the equation.

        Args:
            other: The second value for the extended GCD computation.

        Raises:
            Error: Propagated from underlying arithmetic operations.
        """
        return bigint_number_theory.extended_gcd(self, other)

    @always_inline
    def lcm(self, other: Self) raises -> Self:
        """Returns the least common multiple of self and other.

        Args:
            other: The second value for the LCM computation.

        Returns:
            The least common multiple of the two values.

        Raises:
            Error: Propagated from underlying arithmetic operations.
        """
        return bigint_number_theory.lcm(self, other)

    @always_inline
    def mod_pow(self, exponent: Self, modulus: Self) raises -> Self:
        """Returns (self ** exponent) % modulus efficiently using modular
        exponentiation.

        Args:
            exponent: The exponent.
            modulus: The modulus.

        Returns:
            The result of (self ** exponent) % modulus.

        Raises:
            ValueError: If the exponent is negative or the modulus is not positive.
        """
        return bigint_number_theory.mod_pow(self, exponent, modulus)

    @always_inline
    def mod_pow(self, exponent: Int, modulus: Self) raises -> Self:
        """Returns (self ** exponent) % modulus efficiently using modular
        exponentiation.

        Args:
            exponent: The exponent.
            modulus: The modulus.

        Returns:
            The result of (self ** exponent) % modulus.

        Raises:
            ValueError: If the exponent is negative or the modulus is not positive.
        """
        return bigint_number_theory.mod_pow(
            self, Self.from_integral_scalar(exponent), modulus
        )

    @always_inline
    def mod_inverse(self, modulus: Self) raises -> Self:
        """Returns the modular inverse of self modulo modulus, i.e. a number x
        such that (self * x) % modulus == 1.

        Args:
            modulus: The modulus.

        Returns:
            The modular multiplicative inverse.

        Raises:
            ValueError: If the modulus is not positive or the modular inverse does not exist.
        """
        return bigint_number_theory.mod_inverse(self, modulus)

    # ===------------------------------------------------------------------=== #
    # Instance query methods
    # ===------------------------------------------------------------------=== #

    @always_inline
    def assert_invariant(self, context: StaticString = "") -> None:
        """Checks the representation invariant documented on the struct.

        A `debug_assert`, so it compiles away entirely unless the build sets
        `-D ASSERT=all`.

        Args:
            context: Name of the calling function, shown if the check fires.
        """
        debug_assert(
            len(self.words) > 0,
            "BigInt.assert_invariant(): empty words. ",
            context,
        )
        debug_assert(
            len(self.words) == 1 or self.words[len(self.words) - 1] != 0,
            "BigInt.assert_invariant(): leading zero word. ",
            context,
        )

    @always_inline
    def is_zero(self) -> Bool:
        """Returns True if the value is zero.

        Returns:
            `True` if the value is zero, `False` otherwise.
        """
        if len(self.words) == 1 and self.words[0] == 0:
            return True
        for word in self.words:
            if word != 0:
                return False
        return True

    @always_inline
    def is_negative(self) -> Bool:
        """Returns True if the value is strictly negative.

        Returns:
            `True` if the value is negative, `False` otherwise.
        """
        return self.sign and not self.is_zero()

    @always_inline
    def is_positive(self) -> Bool:
        """Returns True if the value is strictly positive.

        Returns:
            `True` if the value is positive, `False` otherwise.
        """
        return not self.sign and not self.is_zero()

    def is_one(self) -> Bool:
        """Returns True if the value is exactly 1.

        Returns:
            `True` if the value is 1, `False` otherwise.
        """
        return not self.sign and len(self.words) == 1 and self.words[0] == 1

    def is_one_or_minus_one(self) -> Bool:
        """Returns True if the value is 1 or -1.

        Returns:
            `True` if the value is 1 or -1, `False` otherwise.
        """
        return len(self.words) == 1 and self.words[0] == 1

    def bit_length(self) -> Int:
        """Returns the number of bits needed to represent the magnitude,
        excluding leading zeros.

        Returns:
            The position of the highest set bit, or 0 if the value is zero.
        """
        if self.is_zero():
            return 0

        var n_words = len(self.words)
        var msw = self.words[n_words - 1]

        # `std.bit.bit_width` lowers to a hardware `clz`, replacing the
        # bit-at-a-time probe loop.
        return (n_words - 1) * 64 + Int(bit_width(msw))

    def bit_count(self) -> Int:
        """Returns the number of ones in the binary representation of the
        absolute value (population count).

        Matches Python 3.10+ `int.bit_count()`.

        Returns:
            The number of set bits in the magnitude, or 0 if the value is zero.

        Examples:

        ```
        BigInt(13).bit_count()   # 3 (13 = 0b1101)
        BigInt(-7).bit_count()   # 3 (7 = 0b111)
        BigInt(0).bit_count()    # 0
        ```
        """
        # `std.bit.pop_count` lowers to a single `cnt` instruction, making
        # this O(words) instead of O(set bits).
        var count = 0
        for i in range(len(self.words)):
            count += Int(pop_count(self.words[i]))
        return count

    def number_of_words(self) -> Int:
        """Returns the number of words in the magnitude.

        Returns:
            The number of `UInt64` words used to represent the magnitude.
        """
        return len(self.words)

    def number_of_digits(self) -> Int:
        """Returns the number of decimal digits in the magnitude.

        Notes:
            Zero has 1 digit.

        Returns:
            The number of decimal digits.
        """
        if self.is_zero():
            return 1

        # Convert to base-10^9 and use its digit counting
        return self.to_biguint().number_of_digits()

    # ===------------------------------------------------------------------=== #
    # Internal utility methods
    # ===------------------------------------------------------------------=== #

    def copy(self) -> Self:
        """Returns a deep copy of this BigInt.

        Returns:
            A new `BigInt` with the same value.
        """
        var new_words = Magnitude(capacity=len(self.words))
        for word in self.words:
            new_words.append(word)
        return Self(raw_words=new_words^, sign=self.sign)

    def _normalize(mut self):
        """Strips leading zero words and normalizes -0 to +0."""
        while len(self.words) > 1 and self.words[len(self.words) - 1] == 0:
            self.words.shrink(len(self.words) - 1)

        # Normalize -0 to +0
        if self.is_zero():
            self.sign = False

    def internal_representation(self) -> String:
        """Returns the internal representation details as a String.

        Returns:
            A string showing the sign and word-level magnitude representation.
        """
        # Collect all labels to find max width
        var fixed_labels = List[String]()
        fixed_labels.append("number:")
        fixed_labels.append("number (hex):")
        fixed_labels.append("sign:")
        var max_label_len = 0
        for i in range(len(fixed_labels)):
            if fixed_labels[i].byte_length() > max_label_len:
                max_label_len = fixed_labels[i].byte_length()
        # Check word labels
        for i in range(len(self.words)):
            var label_len = "word :".byte_length() + String(i).byte_length()
            if label_len > max_label_len:
                max_label_len = label_len

        var col = max_label_len + 4  # 4 spaces after longest label
        var value_width = 30
        var sep_line = String("-") * (col + value_width)

        var result = String("\nInternal Representation Details of BigInt\n")
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

        # number (hex) line
        var hex_str = self.to_hex_string()
        var hex_label = String("number (hex):")
        result += hex_label + String(" ") * (col - hex_label.byte_length())
        var hex_start = 0
        var first_hex_line = True
        while hex_start + value_width < hex_str.byte_length():
            if not first_hex_line:
                result += String(" ") * col
            result += (
                String(hex_str[byte = hex_start : hex_start + value_width])
                + "\n"
            )
            hex_start += value_width
            first_hex_line = False
        if not first_hex_line:
            result += String(" ") * col
        result += String(hex_str[byte=hex_start:]) + "\n"

        # sign line
        result += "sign:" + String(" ") * (col - "sign:".byte_length())
        result += String("negative" if self.sign else "non-negative") + "\n"

        # word lines
        for i in range(len(self.words)):
            var label = "word " + String(i) + ":"
            result += label + String(" ") * (col - label.byte_length())
            result += "0x" + decimo_str.rjust(
                String(hex(self.words[i])[byte=2:]), 8, fillchar="0"
            )
            result += "  (" + String(self.words[i]) + ")\n"

        result += sep_line
        return result^

    def print_internal_representation(self):
        """Prints the internal representation details."""
        print(self.internal_representation())


# ===----------------------------------------------------------------------=== #
# Module-level private helpers for from_string
# These operate on the magnitude words only (sign is handled by caller).
# ===----------------------------------------------------------------------=== #


def _multiply_add_inplace(mut x: BigInt, mul: UInt64, add: UInt64):
    """Computes x = x * mul + add in a single pass over the word array.

    Fuses the multiply-by-scalar and add-scalar operations into one O(n) pass
    instead of two separate O(n) passes, halving memory traffic. This is the
    inner loop of the simple base-conversion path, a chunk at a time.

    Correctness: at each word position i,
        product = x.words[i] * mul + carry
    where carry starts at `add` and propagates upward. This correctly computes
    x * mul + add because the carry chain handles both the multiplication
    carry and the initial addend.

    Overflow safety: product <= (2^64-1)*(2^64-1) + carry, which is what the
    128-bit accumulator is for; the carry out is below `mul` and so fits a
    word again.

    Args:
        x: The BigInt to modify in-place.
        mul: The UInt64 multiplier (e.g. 10^18).
        add: The UInt64 addend (e.g. a chunk value).
    """
    if mul == 0:
        x.words = [UInt64(add)]
        x.sign = False
        return

    var carry: UInt64 = add
    for i in range(len(x.words)):
        var product = UInt128(x.words[i]) * UInt128(mul) + UInt128(carry)
        x.words[i] = UInt64(product)
        carry = UInt64(product >> 64)

    if carry > 0:
        x.words.append(UInt64(carry))


# ===----------------------------------------------------------------------=== #
# Divide-and-conquer base conversion (decimal string → binary)
# ===----------------------------------------------------------------------=== #

# Thresholds for D&C from_string, measured in decimal digit count.
# The simple multiply-and-add method has very low constant factors
# (one sequential pass of word-sized multiply-adds), so D&C only wins at
# much larger sizes
# than for to_string (where the saved divisions are each expensive).
# Entry threshold: only enter D&C when the digit count is large enough
# that the O(n²) simple method is significantly slower than the O(M(n)·log n)
# D&C method despite the power-table construction overhead.
# Base threshold: within the recursion, switch to simple method.
# Entry lowered from 10000 to 2000 in 2026-08 when the multiply kernels became
# product-scanning: D&C spends its time multiplying and the simple method does
# not, so the crossover moved down with them. At 8 000 digits that is 0.18 ms
# -> 0.11 ms, and nothing above or below regresses.
comptime _DC_FROM_STR_ENTRY_THRESHOLD = 2000
comptime _DC_FROM_STR_BASE_THRESHOLD = 256


def _from_decimal_digits_simple(
    digits: List[UInt8], start: Int, end: Int
) -> BigInt:
    """Converts a range of digit values to a BigInt using the simple
    O(n²) multiply-and-add method (9 digits at a time).

    Optimizations over the naive approach:
    - Pre-allocates the word array to its maximum possible size, avoiding
      all dynamic growth (append / reallocation) during conversion.
    - Handles the first (possibly shorter) chunk separately so the main
      loop always processes exactly 9 digits with a compile-time constant
      10^9 multiplier — no inner loop to compute 10^chunk_size.
    - Uses raw pointer access for both the digit array and the word array
      to eliminate bounds-checking overhead in the hot inner loop.
    - Tracks the live word count in a local variable, trimming once at end.

    Args:
        digits: List of digit values (0-9).
        start: Start index (inclusive) in the digits list.
        end: End index (exclusive) in the digits list.

    Returns:
        The unsigned BigInt value (sign is False).
    """
    if start >= end:
        return BigInt()

    var digit_count = end - start

    # ---- Fast path: <= 19 digits -> a single word, no allocation ----
    # `10^19 - 1` is below `2^64`, so nineteen digits always fit one word and
    # the running value cannot overflow on the way in either. This is the one
    # place that uses all nineteen; the chunk base below stops at eighteen for
    # a different reason.
    if digit_count <= 19:
        var dp = digits.unsafe_ptr().unsafe_offset(start)
        var val: UInt64 = UInt64(dp[])
        for j in range(1, digit_count):
            val = val * 10 + UInt64(dp[unsafe_offset=j])
        var result = BigInt()
        result.words[0] = val
        return result^

    # ---- General path: pre-allocate and multiply-add by 10^18 chunks ----

    # Pre-allocate words: ceil(digit_count * log2(10) / 64) + 2.
    # 107/2048 ≈ 0.052246 > log2(10)/64 ≈ 0.051905, so always sufficient.
    # The +2 guarantees room for a carry word at the end of every iteration.
    var max_words = (digit_count * 107 + 2047) // 2048 + 2

    var result = BigInt()
    result.words = Magnitude(capacity=max_words)
    result.words.resize(unsafe_uninit_length=max_words)
    var wp = result.words.unsafe_ptr()  # stable pointer: no reallocation occurs

    # Handle the first chunk to align the rest to chunk boundaries.
    var first_chunk = digit_count % _DECIMAL_CHUNK_DIGITS
    if first_chunk == 0:
        first_chunk = _DECIMAL_CHUNK_DIGITS

    var dp = digits.unsafe_ptr().unsafe_offset(start)
    var chunk_val: UInt64 = UInt64(dp[])
    for j in range(1, first_chunk):
        chunk_val = chunk_val * 10 + UInt64(dp[unsafe_offset=j])
    dp = dp.unsafe_offset(first_chunk)

    wp[] = chunk_val
    var word_count: Int = 1
    var remaining = digit_count - first_chunk

    # Main loop: full 18-digit chunks with constant multiplier 10^18.
    comptime MUL18 = UInt128(_DECIMAL_CHUNK_BASE)

    while remaining > 0:
        # Parse a chunk's worth of digit values into one word
        var cv: UInt64 = UInt64(dp[])
        for j in range(1, _DECIMAL_CHUNK_DIGITS):
            cv = cv * 10 + UInt64(dp[unsafe_offset=j])
        dp = dp.unsafe_offset(_DECIMAL_CHUNK_DIGITS)
        remaining -= _DECIMAL_CHUNK_DIGITS

        # Fused multiply-add: result = result * 10^18 + cv (one O(n) pass).
        # The carry stays below 10^18 and so inside a word.
        var carry: UInt64 = cv
        for k in range(word_count):
            var product = UInt128(wp[unsafe_offset=k]) * MUL18 + UInt128(carry)
            wp[unsafe_offset=k] = UInt64(product)
            carry = UInt64(product >> 64)
        if carry > 0:
            wp[unsafe_offset=word_count] = carry
            word_count += 1

    # Trim pre-allocated words to the actual live word count.
    while len(result.words) > word_count:
        result.words.shrink(len(result.words) - 1)

    return result^


def _from_decimal_digits_dc(
    digits: List[UInt8], start: Int, end: Int
) raises -> BigInt:
    """Converts a range of digit values to a BigInt using
    divide-and-conquer base conversion. Complexity: O(M(n) · log n)
    where M(n) is the multiplication cost.

    Algorithm:
    1. Precompute a power table: powers[k] = 10^(2^k) as BigInt values.
    2. **Balanced split**: choose the largest power-of-2 boundary ≤ digit_count/2.
       This keeps both halves close in size, which is optimal for Karatsuba
       multiplication (balanced operands give the best O(n^1.585) constant).
    3. Recursively convert both halves.
    4. Combine: result = high * powers[k] + low.

    The balanced split also reduces the power-table size: we only build up
    to floor(log2(digit_count/2)) instead of ceil(log2(digit_count)), saving
    one expensive squaring at the top level.

    Args:
        digits: List of digit values (0-9).
        start: Start index (inclusive) in the digits list.
        end: End index (exclusive) in the digits list.

    Returns:
        The unsigned BigInt value (sign is False).
    """
    var digit_count = end - start

    # For balanced D&C, the top-level split uses 2^k ≤ digit_count/2.
    # We only need power table entries up to that level, saving one
    # expensive squaring compared to the "largest 2^k < digit_count" approach.
    var half = digit_count >> 1
    var top_level = 0
    var tmp = half
    while tmp > 0:
        tmp >>= 1
        top_level += 1
    top_level -= 1  # floor(log2(half)): 2^top_level ≤ half < 2^(top_level+1)

    # Build power table: powers[k] = 10^(2^k). Indices 0..top_level.
    var num_powers = top_level + 1
    var power_table = List[BigInt](capacity=num_powers)
    power_table.append(BigInt(10))
    for k in range(1, num_powers):
        # Compute 10^(2^k) = (10^(2^(k-1)))^2 directly from the table.
        var sq = power_table[k - 1] * power_table[k - 1]
        power_table.append(sq^)

    # Run the recursive D&C conversion
    return _dc_from_str_recursive(digits, start, end, power_table, top_level)


def _dc_from_str_recursive(
    digits: List[UInt8],
    start: Int,
    end: Int,
    power_table: List[BigInt],
    max_level: Int,
) raises -> BigInt:
    """Recursively converts a range of digit values to BigInt
    using the precomputed power table with balanced splitting.

    At each level, splits the digit range into high and low parts where
    the low part has 2^level digits (the largest power-of-2 ≤ digit_count/2),
    then:
        result = high * 10^(2^level) + low

    The balanced split ensures high and low are within a 2:1 ratio, keeping
    the combine multiplication efficient under Karatsuba.

    Note on max_level: the high part receives `level` (not `level - 1`)
    because high ≥ digit_count/2, so it may legitimately need the same level.
    The low part receives `level - 1` since it has exactly 2^level digits.

    Args:
        digits: List of digit values (0-9).
        start: Start index (inclusive).
        end: End index (exclusive).
        power_table: Precomputed table where powers[k] = 10^(2^k).
        max_level: Maximum level accessible in power_table for this sub-problem.

    Returns:
        The unsigned BigInt value for digits[start:end].
    """
    var digit_count = end - start

    # Base case: small enough for simple O(n²) conversion
    if digit_count <= _DC_FROM_STR_BASE_THRESHOLD:
        return _from_decimal_digits_simple(digits, start, end)

    # Find the largest level k such that 2^k ≤ digit_count / 2.
    # This balanced split keeps operands close in size for Karatsuba.
    var level = min(max_level, len(power_table) - 1)
    var half = digit_count >> 1
    while level >= 0 and (1 << level) > half:
        level -= 1

    if level < 0:
        # digit_count ≤ 2 (can't split meaningfully), use simple method
        return _from_decimal_digits_simple(digits, start, end)

    # Split: low part has exactly 2^level digits, high part gets the rest.
    var low_len = 1 << level
    var split = end - low_len

    # Recursively convert both halves.
    # High part may need the same `level` (since high ≥ digit_count/2),
    # so pass `level` rather than `level - 1`.
    var high = _dc_from_str_recursive(digits, start, split, power_table, level)
    var low = _dc_from_str_recursive(digits, split, end, power_table, level - 1)

    # Combine: result = high * 10^(2^level) + low
    # Use _add_magnitudes_inplace directly to avoid BigInt.__iadd__ overhead
    # (which creates a new BigInt via arithmetics.add).
    var result = high * power_table[level]
    bigint_arithmetics._add_magnitudes_inplace(result.words, low.words)
    return result^


# ===----------------------------------------------------------------------=== #
# Divide-and-conquer base conversion (binary → decimal string)
# ===----------------------------------------------------------------------=== #

# The thresholds (in UInt64 words) below which we use the simple O(n^2) method
# of repeated division by 10^9. Above them, the D&C method is used.
#
# - _DC_TO_STR_ENTRY_THRESHOLD (64): gates the top-level decision to enter D&C
#   (~616 decimal digits; below this the simple O(n^2) path is faster)
# - _DC_TO_STR_BASE_THRESHOLD (48): base-case size within the recursion
#   (~462 decimal digits; recursion bottoms out to the simple path here)
#
# These were derived rather than measured, and the derivation was wrong. It
# said D&C only wins once its internal divisions reach Burnikel-Ziegler, so
# with a divisor half the dividend the entry point had to be `2 * 64 = 128`
# words. But what D&C actually buys is the balanced split -- it replaces a
# quadratic walk of `x % 10^9` with two half-sized problems, and that pays
# long before any division inside it is large enough for B-Z. Measured, best
# of seven, `String(BigInt)` in microseconds:
#
#     digits            700    900   1233   1500   3000   10000
#     entry 128/64    10.65  18.23  36.37  31.24  87.93   492.9
#     entry  64/48    10.28  14.85  26.03  33.55  84.31   477.6
#
# That is on the *old* Knuth D, so the derived pair was already losing 1.4x at
# 1233 digits before anything else here changed. Faster division widened it,
# since D&C divides and the simple path only ever divides by a single word:
#
#     digits            700    900   1233   1500   3000   10000
#     entry 128/64    10.57  18.10  36.03  25.39  67.68   374.3
#     entry  64/48     8.35  11.83  18.80  24.90  66.28   376.0
#
# 32 ties with 48 for the base case everywhere except 900 digits, where 48
# stops one level earlier and wins by 7%. 24 and 96 are worse at every width.
comptime _DC_TO_STR_ENTRY_THRESHOLD = 64
comptime _DC_TO_STR_BASE_THRESHOLD = 48

# Base for extracting decimal chunks, both ways.
#
# Nineteen digits is the most that fit a word, but eighteen is the right
# number, for two reasons that agree. It carries exactly twice what `10^9`
# carried in a half-as-wide word, so the density is unchanged and the
# three-digit grouping people read numbers by survives; and `to_biguint()`
# hands these chunks straight to `BigUInt`, whose own base is `10^9`, where
# only a whole number of nine-digit groups splits cleanly.
comptime _DECIMAL_CHUNK_DIGITS = 18
comptime _DECIMAL_CHUNK_BASE: UInt64 = 1_000_000_000_000_000_000


def _magnitude_to_decimal_simple(words: Magnitude, eff_words: Int) -> String:
    """Converts a magnitude (unsigned word list) to a decimal string using
    the simple O(n²) method of repeated division by a power of ten.

    Optimizations over naive approach:
    - Divides by `10^18`, collecting chunks, then writes digits
      to a byte buffer in one pass (no string concatenation).
    - Tracks effective dividend length (`div_len`) instead of scanning
      for is_zero.
    - Uses `unsafe_ptr()` for the inner division loop.

    Args:
        words: The magnitude in little-endian UInt64 words.
        eff_words: Effective number of words (excluding trailing zeros).

    Returns:
        The unsigned decimal string (no sign prefix).
    """
    if eff_words == 1 and words[0] == 0:
        return String("0")

    # Fast path for single-word values. `String(UInt64)` rather than
    # `String(Int(...))`: a word above `2^63` is not an `Int`.
    if eff_words == 1:
        return String(words[0])

    var chunks = _magnitude_to_chunks_simple(words, eff_words)
    var num_chunks = len(chunks)
    if num_chunks == 0:
        return String("0")

    # --- Build the decimal string in a byte buffer ---
    # The chunks stay `UInt64` rather than being narrowed to `Int` the way
    # the base-10^9 form did; nothing here needs a signed type.
    var max_digits = num_chunks * _DECIMAL_CHUNK_DIGITS
    var buf = List[UInt8](capacity=max_digits + 1)

    # Most-significant chunk: no zero-padding.
    var msb = chunks[num_chunks - 1]
    var msb_digits = Array[UInt8, 20](fill=0)
    var msb_len = 0
    if msb == 0:
        buf.append(48)  # '0'
    else:
        var v = msb
        while v > 0:
            msb_digits[msb_len] = UInt8(v % 10) + 48
            msb_len += 1
            v //= 10
        for j in range(msb_len - 1, -1, -1):
            buf.append(msb_digits[j])

    # Remaining chunks: zero-padded to exactly a chunk's width.
    for ci in range(num_chunks - 2, -1, -1):
        var val = chunks[ci]
        var padded = Array[UInt8, _DECIMAL_CHUNK_DIGITS](fill=48)  # '0'
        for d in range(_DECIMAL_CHUNK_DIGITS):
            padded[_DECIMAL_CHUNK_DIGITS - 1 - d] = UInt8(val % 10) + 48
            val //= 10
        for d in range(_DECIMAL_CHUNK_DIGITS):
            buf.append(padded[d])

    return String(unsafe_from_utf8=buf^)


def _magnitude_to_chunks_simple(
    words: Magnitude, eff_words: Int
) -> List[UInt64]:
    """Converts a magnitude from base 2^64 to base 10^18 by repeated division.

    Complexity is O(n^2); this is the base case of the divide-and-conquer
    conversion and the whole of the conversion for small inputs. The result is
    the natural intermediate of decimal output as well, so
    `_magnitude_to_decimal_simple()` formats what this returns rather than
    repeating the division loop.

    Args:
        words: The magnitude in little-endian UInt64 words.
        eff_words: Effective number of words (excluding trailing zeros).

    Returns:
        The magnitude in little-endian base-10^18 words, with no trailing zero
        word except for the value zero itself.
    """
    if eff_words <= 0 or (eff_words == 1 and words[0] == 0):
        return [UInt64(0)]

    # Allocate dividend buffer and get raw pointer for fast inner loop.
    var dividend = Magnitude(capacity=eff_words)
    for i in range(eff_words):
        dividend.append(words[i])
    var dp = dividend.unsafe_ptr()

    # Estimate the chunk count: ceil(bits * log10(2) / 18) + 1, with 78/259
    # just over log10(2).
    var est_chunks = (eff_words * 64 * 78 + 4661) // 4662 + 1

    var chunks = List[UInt64](capacity=est_chunks)
    var div_len = eff_words

    # There is no hardware 128-by-64 divide, so the digit comes from a
    # precomputed reciprocal instead, which wants a normalized divisor.
    # `10^18` is four bits short of one, and scaling it means scaling the
    # dividend by the same four bits -- which this loop cannot do once and
    # keep, because it divides the dividend in place and the next pass needs
    # it unscaled. So the scaled words are formed as the walk goes, from the
    # two words straddling each boundary. The quotient is unaffected by the
    # scaling and the remainder comes back out of it at the end.
    comptime SHIFT = Int(count_leading_zeros(_DECIMAL_CHUNK_BASE))
    comptime CARRY_SHIFT = UInt64(64 - SHIFT)
    comptime DIVISOR = _DECIMAL_CHUNK_BASE << UInt64(SHIFT)
    var reciprocal = bigint_arithmetics._reciprocal_word(DIVISOR)

    while div_len > 0:
        # The top word of the scaled dividend is what the top word shifts
        # out, which is below `2^SHIFT` and so below the divisor.
        var remainder = dp[unsafe_offset=div_len - 1] >> CARRY_SHIFT
        for i in range(div_len - 1, -1, -1):
            var below = dp[
                unsafe_offset=i - 1
            ] >> CARRY_SHIFT if i > 0 else UInt64(0)
            var step = bigint_arithmetics._divide_two_by_one(
                remainder,
                (dp[unsafe_offset=i] << UInt64(SHIFT)) | below,
                DIVISOR,
                reciprocal,
            )
            dp[unsafe_offset=i] = step[0]
            remainder = step[1]

        while div_len > 0 and dp[unsafe_offset=div_len - 1] == 0:
            div_len -= 1

        chunks.append(remainder >> UInt64(SHIFT))

    if len(chunks) == 0:
        chunks.append(UInt64(0))

    return chunks^


def _magnitude_to_chunks_dc(
    words: Magnitude, eff_words: Int
) raises -> List[UInt64]:
    """Converts a magnitude from base 2^64 to base 10^18, divide and conquer.

    Same recursion as `_magnitude_to_decimal_dc()`, but splitting on powers of
    `10^18` instead of powers of `10`, so that each half lands on a chunk
    boundary and the digits can be written straight into the output
    buffer. Nothing here builds a decimal string: the caller wants words, and
    going out through a string and back costs a full formatting pass plus a
    full parse over the whole number.

    Complexity: O(M(n) . log n), where M(n) is the multiplication cost.

    Args:
        words: The magnitude in little-endian UInt64 words.
        eff_words: Effective number of words (excluding trailing zeros).

    Returns:
        The magnitude in little-endian base-10^18 words, with no trailing zero
        word except for the value zero itself.

    Raises:
        Error: If an arithmetic error occurs during the internal divisions.
    """
    # Estimate the output length from the bit length, rounding up throughout.
    var top_word = words[eff_words - 1]
    var bits_in_top = 64 - bigint_arithmetics._count_leading_zeros(top_word)
    var total_bits = (eff_words - 1) * 64 + bits_in_top

    # digits <= floor(bits * log10(2)) + 1, with 78/259 just over log10(2).
    var est_digits = (total_bits * 78 + 258) // 259 + 1
    var est_words = (
        est_digits + _DECIMAL_CHUNK_DIGITS - 1
    ) // _DECIMAL_CHUNK_DIGITS

    # Smallest `max_level` with `2^max_level >= est_words`; the split is then
    # always at a level strictly below it.
    var max_level = 0
    var tmp = est_words - 1
    while tmp > 0:
        tmp >>= 1
        max_level += 1

    # Power table: power_table[k] = (10^18)^(2^k), whose remainder therefore
    # occupies exactly 2^k chunks. The base itself is past `Int.MAX`, so it
    # goes in as the single word it is rather than through an `Int`.
    var num_powers = max_level
    var power_table = List[BigInt](capacity=num_powers)
    power_table.append(BigInt(raw_words=[_DECIMAL_CHUNK_BASE], sign=False))
    for k in range(1, num_powers):
        var sq = power_table[k - 1] * power_table[k - 1]
        power_table.append(sq^)

    var trimmed = Magnitude(capacity=eff_words)
    for i in range(eff_words):
        trimmed.append(words[i])
    var n = BigInt(raw_words=trimmed^, sign=False)

    # `2^max_level` words is an upper bound on the output length, so every
    # write below is in range and the buffer needs zeroing only once.
    var capacity = 1 << max_level
    var out = List[UInt64](capacity=capacity)
    out.resize(unsafe_uninit_length=capacity)
    unsafe_memset_zero(ptr=out.unsafe_ptr(), count=capacity)

    _dc_to_chunks_recursive(n, power_table, num_powers - 1, out, 0)

    var length = capacity
    while length > 1 and out[length - 1] == 0:
        length -= 1
    out.shrink(length)
    return out^


def _dc_to_chunks_recursive(
    n: BigInt,
    power_table: List[BigInt],
    max_level: Int,
    mut out: List[UInt64],
    offset: Int,
) raises:
    """Writes the base-10^18 words of `n` into `out` starting at `offset`.

    The caller guarantees that `out` is zero-filled and long enough, so a
    short value simply leaves the high words of its slot alone.

    Args:
        n: The non-negative value to convert.
        power_table: Table with `power_table[k] = (10^18)^(2^k)`.
        max_level: Highest level of `power_table` usable for this subproblem.
        out: The destination buffer, in little-endian base-10^18 words.
        offset: Index in `out` at which this subproblem's words begin.

    Raises:
        Error: If an arithmetic error occurs during the internal divisions.
    """
    var eff = len(n.words)
    while eff > 1 and n.words[eff - 1] == 0:
        eff -= 1

    if eff <= _DC_TO_STR_BASE_THRESHOLD:
        var chunks = _magnitude_to_chunks_simple(n.words, eff)
        for i in range(len(chunks)):
            out[offset + i] = chunks[i]
        return

    # Largest level `k` with `power_table[k] <= n`.
    var level = -1
    for k in range(min(max_level + 1, len(power_table))):
        if n >= power_table[k]:
            level = k
        else:
            break

    if level < 0:
        var chunks = _magnitude_to_chunks_simple(n.words, eff)
        for i in range(len(chunks)):
            out[offset + i] = chunks[i]
        return

    var qr = bigint_arithmetics.floor_divmod(n, power_table[level])

    # The low part occupies exactly 2^level base-10^18 words, so the high part
    # starts that far along.
    _dc_to_chunks_recursive(qr[1], power_table, level - 1, out, offset)
    _dc_to_chunks_recursive(
        qr[0], power_table, level - 1, out, offset + (1 << level)
    )


def _magnitude_to_decimal_dc(words: Magnitude, eff_words: Int) raises -> String:
    """Converts a magnitude to a decimal string using divide-and-conquer
    base conversion. Complexity: O(M(n) · log n) where M(n) is the
    multiplication cost.

    Algorithm:
    1. Precompute a power table: powers[k] = 10^(2^k) as BigInt values.
    2. Find the largest k such that powers[k] ≤ the number.
    3. divmod(number, powers[k]) → (high, low).
    4. The low part has exactly 2^k decimal digits (zero-padded).
    5. Recursively convert high and low halves.

    Args:
        words: The magnitude in little-endian UInt64 words.
        eff_words: Effective number of words (excluding trailing zeros).

    Returns:
        The unsigned decimal string (no sign prefix).
    """
    # Estimate decimal digits from bit length
    # bit_length = (eff_words - 1) * 64 + bits_in_top_word
    var top_word = words[eff_words - 1]
    var bits_in_top = 64 - bigint_arithmetics._count_leading_zeros(top_word)
    var total_bits = (eff_words - 1) * 64 + bits_in_top

    # Conservative overestimate: digits <= floor(bits * log10(2)) + 1
    # log10(2) ≈ 0.30103 ≈ 78/259 (slightly over)
    var est_digits = (total_bits * 78 + 258) // 259 + 1

    # Find max_level such that 2^max_level >= est_digits.
    # We only need powers[0..max_level-1] because 10^(2^max_level) > n,
    # so the first split is always at a level < max_level.
    # Use bit-counting instead of `1 << max_level` to avoid overflow
    # when est_digits approaches the Int word size.
    var max_level = 0
    var tmp = est_digits - 1
    while tmp > 0:
        tmp >>= 1
        max_level += 1

    # Build power table: powers[k] = 10^(2^k) as BigInt
    # powers[0] = 10^1, powers[1] = 10^2, powers[2] = 10^4, ...
    # Only build up to max_level - 1 (the highest level that can be used).
    var num_powers = max_level  # indices 0 to max_level - 1
    var power_table = List[BigInt](capacity=num_powers)
    power_table.append(BigInt(10))
    for k in range(1, num_powers):
        var sq = power_table[k - 1] * power_table[k - 1]
        power_table.append(sq^)

    # Create unsigned BigInt from the magnitude words
    var trimmed = Magnitude(capacity=eff_words)
    for i in range(eff_words):
        trimmed.append(words[i])
    var n = BigInt(raw_words=trimmed^, sign=False)

    # Run the recursive D&C conversion
    return _dc_to_str_recursive(n, power_table, num_powers - 1)


def _dc_to_str_recursive(
    n: BigInt,
    power_table: List[BigInt],
    max_level: Int,
) raises -> String:
    """Recursively converts a non-negative BigInt to decimal string
    using the precomputed power table.

    At each level, divides by powers[level] = 10^(2^level) to split the number
    into a high part and a low part with exactly 2^level decimal digits.

    Args:
        n: The non-negative number to convert.
        power_table: Precomputed table where powers[k] = 10^(2^k).
        max_level: Maximum level accessible in power_table for this subproblem.

    Returns:
        The decimal string representation.
    """
    # Base case: small enough for simple O(n²) conversion
    var eff = len(n.words)
    while eff > 1 and n.words[eff - 1] == 0:
        eff -= 1

    if eff <= _DC_TO_STR_BASE_THRESHOLD:
        return _magnitude_to_decimal_simple(n.words, eff)

    # Find the largest level k such that powers[k] <= n
    var level = -1
    for k in range(min(max_level + 1, len(power_table))):
        if n >= power_table[k]:
            level = k
        else:
            break

    if level < 0:
        # n < 10, use simple method
        return _magnitude_to_decimal_simple(n.words, eff)

    # Divide n by powers[level] = 10^(2^level)
    var qr = bigint_arithmetics.floor_divmod(n, power_table[level])
    var q = qr[0].copy()
    var r = qr[1].copy()

    # The low part has exactly 2^level decimal digits
    var low_width = 1 << level

    # Recurse on high and low parts
    var high_str = _dc_to_str_recursive(q, power_table, level - 1)
    var low_str = _dc_to_str_recursive(r, power_table, level - 1)

    # Zero-pad low_str to exactly low_width digits.
    # Build the result in a pre-allocated byte buffer to avoid O(n) concatenations.
    var padding = low_width - low_str.byte_length()
    if padding <= 0:
        return high_str + low_str

    var total_len = high_str.byte_length() + padding + low_str.byte_length()
    var buf = List[UInt8](capacity=total_len)
    # Copy high_str bytes
    for i in range(high_str.byte_length()):
        buf.append(high_str.unsafe_ptr()[unsafe_offset=i])
    # Write zero padding
    for _ in range(padding):
        buf.append(48)  # ASCII '0'
    # Copy low_str bytes
    for i in range(low_str.byte_length()):
        buf.append(low_str.unsafe_ptr()[unsafe_offset=i])

    return String(unsafe_from_utf8=buf^)
