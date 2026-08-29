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

"""Implements basic object methods for the BigUInt type.

This module contains the basic object methods for the BigUInt type.
These methods include constructors, life time methods, output dunders,
type-transfer dunders, basic arithmetic operation dunders, comparison
operation dunders, and other dunders that implement traits, as well as
mathematical methods that do not implement a trait.
"""

from std import math
from std.builtin.globals import global_constant
from std.memory import Pointer, unsafe_memcpy, memcmp
from std.sys import size_of

import decimo.biguint.arithmetics as biguint_arithmetics
import decimo.biguint.comparison as biguint_comparison
import decimo.biguint.exponential as biguint_exponential
from decimo.errors import (
    ConversionError,
    ValueError,
    IndexError,
    OverflowError,
    ZeroDivisionError,
)
import decimo.str as decimo_str
from decimo.wordlist import WordList, INLINE_WORDS
from decimo.rounding_mode import RoundingMode
from decimo.traits import Rootable
from decimo.utility import unsigned_counterpart

# Type aliases
comptime BUInt = BigUInt
"""A shorthand alias for `BigUInt`."""

comptime WORD_DTYPE = DType.uint64
"""The machine type one coefficient word is stored in.

Paired with `BigUInt.DIGITS_PER_WORD`: the word has to hold `BASE - 1`, so
the two move together. Named, rather than spelled `Self.Word` at each use, so
that a change of base is a change to this line and to the code that genuinely
depends on the width -- not a blanket text replace over three hundred sites.
Write `BigUInt.Word` for the type of a coefficient word, and a literal
`UInt32`/`UInt64`/`UInt128` only where the *machine width* is the point.
"""

comptime INLINE_WORDS_BIGUINT = 5
"""Words kept in the struct. Five of them is ninety digits, which is what
ten base-10^9 words held before the base moved."""

comptime Coefficient = WordList[WORD_DTYPE, INLINE_WORDS_BIGUINT]
"""The word storage of a `BigUInt`, little-endian."""


comptime _TWO_DIGIT_TABLE: Array[UInt8, 200] = [
    48,
    48,  # 00
    48,
    49,  # 01
    48,
    50,  # 02
    48,
    51,  # 03
    48,
    52,  # 04
    48,
    53,  # 05
    48,
    54,  # 06
    48,
    55,  # 07
    48,
    56,  # 08
    48,
    57,  # 09
    49,
    48,  # 10
    49,
    49,  # 11
    49,
    50,  # 12
    49,
    51,  # 13
    49,
    52,  # 14
    49,
    53,  # 15
    49,
    54,  # 16
    49,
    55,  # 17
    49,
    56,  # 18
    49,
    57,  # 19
    50,
    48,  # 20
    50,
    49,  # 21
    50,
    50,  # 22
    50,
    51,  # 23
    50,
    52,  # 24
    50,
    53,  # 25
    50,
    54,  # 26
    50,
    55,  # 27
    50,
    56,  # 28
    50,
    57,  # 29
    51,
    48,  # 30
    51,
    49,  # 31
    51,
    50,  # 32
    51,
    51,  # 33
    51,
    52,  # 34
    51,
    53,  # 35
    51,
    54,  # 36
    51,
    55,  # 37
    51,
    56,  # 38
    51,
    57,  # 39
    52,
    48,  # 40
    52,
    49,  # 41
    52,
    50,  # 42
    52,
    51,  # 43
    52,
    52,  # 44
    52,
    53,  # 45
    52,
    54,  # 46
    52,
    55,  # 47
    52,
    56,  # 48
    52,
    57,  # 49
    53,
    48,  # 50
    53,
    49,  # 51
    53,
    50,  # 52
    53,
    51,  # 53
    53,
    52,  # 54
    53,
    53,  # 55
    53,
    54,  # 56
    53,
    55,  # 57
    53,
    56,  # 58
    53,
    57,  # 59
    54,
    48,  # 60
    54,
    49,  # 61
    54,
    50,  # 62
    54,
    51,  # 63
    54,
    52,  # 64
    54,
    53,  # 65
    54,
    54,  # 66
    54,
    55,  # 67
    54,
    56,  # 68
    54,
    57,  # 69
    55,
    48,  # 70
    55,
    49,  # 71
    55,
    50,  # 72
    55,
    51,  # 73
    55,
    52,  # 74
    55,
    53,  # 75
    55,
    54,  # 76
    55,
    55,  # 77
    55,
    56,  # 78
    55,
    57,  # 79
    56,
    48,  # 80
    56,
    49,  # 81
    56,
    50,  # 82
    56,
    51,  # 83
    56,
    52,  # 84
    56,
    53,  # 85
    56,
    54,  # 86
    56,
    55,  # 87
    56,
    56,  # 88
    56,
    57,  # 89
    57,
    48,  # 90
    57,
    49,  # 91
    57,
    50,  # 92
    57,
    51,  # 93
    57,
    52,  # 94
    57,
    53,  # 95
    57,
    54,  # 96
    57,
    55,  # 97
    57,
    56,  # 98
    57,
    57,  # 99
]
"""Every pair of digits from `00` to `99`, as characters.

Emitting two digits per division halves the divisions a conversion does, and
a division by a constant is the expensive part of writing a number out.
"""


struct BigUInt(Absable, Copyable, IntableRaising, Movable, Rootable, Writable):
    """Represents a base-10 arbitrary-precision unsigned integer.

    Notes:

    Internal Representation:

    Use base-10^18 representation for the unsigned integer.
    BigUInt uses a dynamic structure in memory, which contains:
    An pointer to an array of Self.Word words for the coefficient on the heap,
    which can be of arbitrary length stored in little-endian order.
    Each Self.Word word represents digits ranging from 0 to `Self.BASE_MAX`.

    The value of the BigUInt is calculated as follows:

    x = x[0] * BASE^0 + x[1] * BASE^1 + x[2] * BASE^2 + ... x[n] * BASE^n

    You can think of the BigUInt as a list of base-10^18 digits, where each
    digit is ranging from 0 to `Self.BASE_MAX`. Depending on the context, the
    following terms are used interchangeably:
    (1) words,
    (2) limbs,
    (3) base-10^18 digits.

    Representation invariant:

    Every `BigUInt` that leaves a function must satisfy all three of these.
    Code may break them *inside* a function as long as it repairs them before
    returning; `remove_leading_empty_words()` is the usual repair.

    1. `words` is never empty. It always holds at least one word.
    2. There are no leading zero words: `words[len(words) - 1] != 0`, unless
       `len(words) == 1`. Zero is therefore exactly `[0]` and has no other
       spelling, which is what lets `is_zero()` and comparison stay cheap.
    3. Every word is a valid base-10^18 digit: `words[i] < BASE`.

    Call `assert_invariant()` to check the first two. It is a `debug_assert`,
    so it costs nothing in a normal build and fires in the test suite.

    Changing the base:

    `DIGITS_PER_WORD` is the one number that decides the representation, and
    `BASE`, `BASE_MAX` and `BASE_HALF` are derived from it. `WORD_DTYPE` is
    the machine type that has to hold `BASE - 1`, and the two move together.
    Code that converts between a digit position and a word position divides by
    the constant rather than by a literal.

    What is *not* mechanical, and has to be rewritten by hand:

    - The Comba accumulator in `multiply_slices_schoolbook`, and Knuth D's
      quotient estimate. Both size an intermediate against `BASE^2`, so both
      need a wider type when the base grows, and both type-check either way.
    - `ntt.mojo`'s packing, which cuts words into six-digit coefficients.
    - `MAX_UINT64` and `MAX_UINT128` here, and `is_uint64_overflow()` and
      `is_uint128_overflow()`, which spell those limits out word by word.
    - Anything that reassembles several words into one machine integer.

    That last one is worth being blunt about, because getting it wrong is what
    the base-10^18 change actually cost. Those sites were left alone at the
    time on the reasoning that a wider word would not fit the machine integer
    anyway, so a literal there "makes someone look". It does not: nobody
    looked, and `to_uint64()`, `to_uint128()`, `to_int()` and
    `_rational_root_decomposition()` all returned wrong answers for months of
    nothing in particular happening.

    A site that cannot be correct in the new base is not future work. Either
    rewrite it -- these are Horner loops now, with the base named once -- or
    delete it if nothing calls it, which is what happened to five of them.

    A guard-digit count is not a word width. `BUFFER_DIGITS`, `GUARD_DIGITS`
    and the like happen to be 9 and stay 9: they say how many extra digits to
    carry, not how many fit in a word.
    """

    var words: Coefficient
    """A list of Self.Word words representing the coefficient.

    Little-endian: `words[0]` is the least significant base-10^18 digit.
    Subject to the representation invariant documented on the struct.
    """

    # ===------------------------------------------------------------------=== #
    # Constants
    # ===------------------------------------------------------------------=== #

    # TODO: Make these constants global, e.g., decimo.biguint.BASE
    comptime Word = Scalar[WORD_DTYPE]
    """The type of one coefficient word. See `WORD_DTYPE`."""
    comptime BITS_ALWAYS_IN_ONE_WORD = Self._bits_always_in_one_word()
    """Widest unsigned scalar, in bits, that always fits a single word.

    `2^k - 1 < BASE`. Twenty-nine bits at nine digits a word, fifty-nine at
    eighteen -- which is why a `UInt32` used to need the two-word branch below
    and now never does.
    """
    comptime DIGITS_PER_WORD = 18
    """How many decimal digits one word holds.

    The base is `10 ** DIGITS_PER_WORD`, so this is the one number that decides
    the internal representation. Everything else here is derived from it, and
    code that converts between a digit position and a word position divides by
    it. Write `DIGITS_PER_WORD` rather than a literal `9` wherever the `9`
    means "digits in a word" -- a literal reads the same as an unrelated nine
    and does not move when the base does.
    """
    comptime BASE = 10**Self.DIGITS_PER_WORD
    """The base used for the BigUInt representation."""
    comptime BASE_MAX = Self.BASE - 1
    """The maximum value of a single word in the BigUInt representation."""
    comptime BASE_HALF = Self.BASE // 2
    """Half of the base used for the BigUInt representation."""
    comptime VECTOR_WIDTH = 4
    """The width of the SIMD vector used for arithmetic operations (128-bit)."""

    comptime ZERO = Self.zero()
    """A `BigUInt` constant representing zero."""
    comptime ONE = Self.one()
    """A `BigUInt` constant representing one."""
    comptime MAX_UINT64 = Self(raw_words=[446744073709551615, 18])
    """A `BigUInt` constant representing the maximum value of `UInt64`.

    Words spelled out in the current base, so this moves with
    `DIGITS_PER_WORD`. Same for `MAX_UINT128` and for the two overflow
    predicates below.
    """
    comptime MAX_UINT128 = Self(
        raw_words=[374607431768211455, 282366920938463463, 340]
    )
    """A `BigUInt` constant representing the maximum value of `UInt128`."""

    @staticmethod
    def _bits_always_in_one_word() -> Int:
        """Largest `k` with `2^k - 1 < BASE`. See `BITS_ALWAYS_IN_ONE_WORD`."""
        var bits = 0
        var limit = 1
        while limit * 2 <= Self.BASE:
            limit *= 2
            bits += 1
        return bits

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
        return Self.from_word_unsafe(Self.Word(1))

    @staticmethod
    @always_inline
    def power_of_10(exponent: Int) raises -> Self:
        """Calculates 10^exponent efficiently.

        Args:
            exponent: The power of 10 to compute.

        Returns:
            A `BigUInt` representing 10 raised to the power of `exponent`.

        Raises:
            ValueError: If the exponent is negative.
        """
        return biguint_arithmetics.power_of_10(exponent)

    # ===------------------------------------------------------------------=== #
    # Constructors and life time dunder methods
    #
    # __init__(out self)
    # __init__(out self, var words: List[Self.Word])
    # __init__(out self, var *words: Self.Word)
    # __init__(out self, value: Int) raises
    # __init__(out self, value: Scalar) raises
    # __init__(out self, value: String, ignore_sign: Bool = False) raises
    # ===------------------------------------------------------------------=== #

    def __init__(out self):
        """Initializes to zero by default."""
        self.words = [Self.Word(0)]

    def __init__(out self, *, uninitialized_capacity: Int):
        """Creates an uninitialized BigUInt with a given capacity.

        Args:
            uninitialized_capacity: The capacity of the BigUInt.
                This is the number of words that can be stored in the
                BigUInt without reallocating memory.

        Notes:

        **UNSAFE**

        The words of the BigUInt is an empty list with the specified capacity.
        This allows us to create an uninitialized BigUInt and append the words
        later without worrying about memory allocation.

        The length of the words list is 0. So you cannot access the words using
        indexing until you append the words to the list.
        """
        self.words = Coefficient(capacity=uninitialized_capacity)

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
        self.words = Coefficient(unsafe_uninit_length=unsafe_uninit_length)

    def __init__(
        out self, *, unsafe_uninit_length: Int, unsafe_uninit_capacity: Int
    ):
        """Creates an uninitialized BigUInt with a given length and capacity.

        As `__init__(unsafe_uninit_length=)`, but reserves room for more words
        than the value starts with. Use it when the result may grow by a known
        amount -- a carry word out of an addition, say. Allocating the larger
        buffer once is a single `malloc`; allocating the exact length and then
        calling `reserve()` is two, plus a copy, and at these sizes an
        allocation is most of what the operation costs.

        Args:
            unsafe_uninit_length: The length of the BigUInt.
            unsafe_uninit_capacity: The capacity to allocate. Must be at least
                `unsafe_uninit_length`.

        Notes:

        **UNSAFE**

        The words are uninitialized and may hold any value, exactly as with
        `__init__(unsafe_uninit_length=)`.
        """
        debug_assert(
            unsafe_uninit_capacity >= unsafe_uninit_length,
            "BigUInt.__init__(): capacity ",
            unsafe_uninit_capacity,
            " is below length ",
            unsafe_uninit_length,
        )
        self.words = Coefficient(capacity=unsafe_uninit_capacity)
        self.words.resize(unsafe_uninit_length=unsafe_uninit_length)

    def __init__(out self, var words: List[Self.Word]) raises:
        """Initializes a BigUInt from a list of words.
        The BigUInt constructed in this way is guaranteed to be valid.
        If the list is empty, the BigUInt is initialized with value 0.
        If there are leading zero words, they are removed.
        If there are words greater than `Self.BASE_MAX`, there is an error.

        Args:
            words: A list of words representing the coefficient.
                Each word represents digits ranging from 0 to `Self.BASE_MAX`.
                The words are stored in little-endian order.

        Raises:
            ConversionError: If any word exceeds `Self.BASE_MAX`.

        Notes:

        This is equal to `BigUInt.from_list()`.
        """
        try:
            self = Self.from_list(words^)
        except e:
            raise ConversionError(
                message="See the above exception.",
                function="BigUInt.__init__(var words: List[Self.Word])",
                previous_error=e^,
            )

    def __init__(out self, *, var raw_words: List[Self.Word]):
        """Initializes a BigUInt from a list of raw words.

        Args:
            raw_words: A list of words representing the coefficient.
                The words are stored in little-endian order.

        Notes:

        **UNSAFE**

        This way of initialization does not check whether the words are smaller
        than `Self.BASE`, nor does it remove leading empty words. A value built
        this way can therefore violate the representation invariant; call
        `remove_leading_empty_words()` before handing it out.

        However, it always initializes a BigUInt and makes sure that the words
        list is not empty. If you want to initialize a BigUInt with an empty
        list of words, you can use `BigUInt(*, uninitialized_capacity=0)`.
        """
        if len(raw_words) == 0:
            self.words = Coefficient(Self.Word(0), __list_literal__=None)
        else:
            self.words = Coefficient(raw_words^)

    @implicit
    def __init__(
        out self, value: Scalar
    ) raises where value.dtype.is_integral():
        """Initializes a BigUInt from any integral scalar.
        This includes all SIMD integral types, both unsigned (UInt8, UInt32,
        UInt64, ...) and signed (Int8, Int32, Int64, the platform-sized `Int`,
        ...). Signed values must be non-negative.
        See `from_integral_scalar()` for more information.

        Constraints:
            The dtype of the scalar must be integral.

        Args:
            value: The integral scalar to initialize the `BigUInt` from.

        Raises:
            OverflowError: If the value is negative.
        """
        self = Self.from_integral_scalar(value)

    def __init__(out self, value: String, *, ignore_sign: Bool = False) raises:
        """Initializes a BigUInt from a string representation.

        Args:
            value: The string representation of the BigUInt.
            ignore_sign: A Bool value indicating whether to ignore the sign.
                If True, the sign is ignored.
                If False, the sign is considered.

        Raises:
            ConversionError: If the string cannot be parsed.

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
    # from_list(var words: List[Self.Word]) -> Self
    # from_words(*words: Self.Word) -> Self
    # from_integral_scalar[dtype: DType](value: Scalar[dtype]) -> Self
    # from_unsigned_integral_scalar[dtype: DType](value: Scalar[dtype]) -> Self
    # from_absolute_integral_scalar[dtype: DType](value: Scalar[dtype]) -> Self
    # from_string(value: String) -> Self
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def from_list(var words: List[Self.Word]) raises -> Self:
        """Initializes a BigUInt from a list of words safely.
        If the list is empty, the BigUInt is initialized with value 0.
        If there are leading zero words, they are removed.
        The words are validated to ensure they are smaller than `Self.BASE`.

        Args:
            words: A list of words representing the coefficient.
                Each word represents digits ranging from 0 to `Self.BASE_MAX`.
                The words are stored in little-endian order.

        Raises:
            OverflowError: If any word exceeds `Self.BASE_MAX`.

        Returns:
            The BigUInt representation of the list of Self.Word words.
        """
        # Return 0 if the list is empty
        if len(words) == 0:
            return Self()

        # Check if the words are valid
        for word in words:
            if word > Self.Word(Self.BASE_MAX):
                raise OverflowError(
                    message=(
                        "Word value "
                        + String(word)
                        + " exceeds maximum value of "
                        + String(Self.BASE_MAX)
                    ),
                    function="BigUInt.from_list()",
                )

        var res = Self(raw_words=words^)
        res.remove_leading_empty_words()
        return res^

    @staticmethod
    def from_list_unsafe(var words: List[Self.Word]) -> Self:
        """Initializes a BigUInt from a list of words without checks.
        If the list is empty, the BigUInt is initialized with value 0.
        If there are leading empty words, they are removed.
        The words are not validated to be smaller than `Self.BASE`.

        Args:
            words: A list of words representing the coefficient.
                Each word represents digits ranging from 0 to `Self.BASE_MAX`.
                The words are stored in little-endian order.

        Returns:
            The BigUInt representation of the list of Self.Word words.
        """
        var result = Self(raw_words=words^)
        result.remove_leading_empty_words()
        return result^

    @staticmethod
    def from_words(*words: Self.Word) raises -> Self:
        """Initializes a BigUInt from raw words safely.

        Args:
            words: The words representing the coefficient.
                Each word represents digits ranging from 0 to `Self.BASE_MAX`.
                The words are stored in little-endian order.

        Raises:
            OverflowError: If any word exceeds `Self.BASE_MAX`.

        Notes:

        This method validates whether the words are smaller than `Self.BASE`,
        and removes leading zero words, as `from_list()` does.

        Example:

        ```console
        BigUInt.from_words(123456789, 987654321)
        # 987654321000000000123456789
        ```
        End of examples.

        Returns:
            The `BigUInt` representation of the given words.
        """

        var list_of_words = List[Self.Word](capacity=len(words))

        # Check if the words are valid
        for word in words:
            if word > Self.Word(Self.BASE_MAX):
                raise OverflowError(
                    message=(
                        "Word value "
                        + String(word)
                        + " exceeds maximum value of "
                        + String(Self.BASE_MAX)
                    ),
                    function="BigUInt.from_words()",
                )
            else:
                list_of_words.append(word)

        var result = Self(raw_words=list_of_words^)
        result.remove_leading_empty_words()
        return result^

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
        var result = BigUInt(unsafe_uninit_length=n_words)
        unsafe_memcpy(
            dest=result.words.unsafe_ptr(),
            src=value.words.unsafe_ptr().unsafe_offset(start_index),
            count=n_words,
        )
        result.remove_leading_empty_words()
        return result^

    @staticmethod
    def zero_with_capacity(capacity: Int) -> Self:
        """Creates a zero whose buffer already has room for `capacity` words.

        Args:
            capacity: The number of words to reserve room for. A capacity below
                one is raised to one, since the value itself needs a word.

        Returns:
            A single-word zero `BigUInt` with the given capacity.

        Notes:
            For an argument that a function is about to overwrite with a small
            result, such as the remainder of a division. A plain `zero()` has
            room for one word, so a two-word remainder reallocates on the way
            in; starting at the width it will need makes it a store.

            The clamp is not defensive dressing. The value is one word long, so
            a capacity below that leaves the word written outside the buffer: a
            negative capacity faults on the spot, and a capacity of zero
            corrupts quietly, in a release build in both cases. The
            `debug_assert` reports the caller that got it wrong, and the clamp
            keeps a release build from writing out of bounds when it does.
        """
        debug_assert(
            capacity >= 1,
            "BigUInt.zero_with_capacity(): capacity ",
            capacity,
            " is below the one word the value itself needs",
        )
        var result = Self(
            unsafe_uninit_length=1, unsafe_uninit_capacity=max(capacity, 1)
        )
        result.words[0] = 0
        return result^

    @staticmethod
    def from_word_unsafe(unsafe_value: Self.Word) -> Self:
        """Creates a BigUInt from a `Self.Word` object without checking the value.

        Args:
            unsafe_value: The `Self.Word` value to wrap directly as a single word.

        Returns:
            A single-word `BigUInt` containing the given value.
        """
        # Built straight into the result's own storage. `raw_words=[value]`
        # allocates a `List` for the literal and then allocates again to copy
        # it into the `WordList` -- two calls to the allocator to carry one
        # word, on the path that every single-word addition takes.
        var result = Self(uninitialized_capacity=1)
        result.words.append(unsafe_value)
        return result^

    @staticmethod
    def from_integral_scalar[
        dtype: DType, //
    ](value: SIMD[dtype, 1]) raises -> Self where dtype.is_integral():
        """Initializes a BigUInt from any integral scalar.
        This includes all SIMD integral types, both unsigned (UInt8, UInt16,
        UInt32, UInt64, UInt128, UInt256 and the platform-sized `UInt`) and
        signed (Int8, Int16, Int32, Int64, Int128, Int256 and the
        platform-sized `Int`). Signed values must be non-negative.

        Constraints:
            The dtype must be integral.

        Args:
            value: The Scalar value to be converted to BigUInt.

        Returns:
            The BigUInt representation of the Scalar value.

        Raises:
            OverflowError: If the value is negative.

        Notes:
            This is the general entry point and the one backing
            `BigUInt(value)`. It has to be able to raise, because a signed
            scalar can be negative. Code that already holds an unsigned scalar,
            and that cannot or does not want to raise, should call
            `from_unsigned_integral_scalar()` directly instead.

        Parameters:
            dtype: The scalar data type, must be integral.
        """

        # Reject negatives. For an unsigned dtype this branch does not exist
        # at all, so nothing is added to the unsigned path.
        comptime if dtype.is_signed():
            if value < 0:
                raise OverflowError(
                    function="BigUInt.from_integral_scalar()",
                    message=(
                        "The input value "
                        + String(value)
                        + " is negative and is not compatible with BigUInt."
                    ),
                )

        # The value is now known to be non-negative, so move it into an
        # unsigned word of the same width and hand it to the unsigned path.
        # Casting to the unsigned counterpart rather than to a fixed type keeps
        # the full range, so `Int.MIN`-style asymmetry never has to be
        # special-cased.
        comptime unsigned_dtype = unsigned_counterpart[dtype]()
        return Self.from_unsigned_integral_scalar(Scalar[unsigned_dtype](value))

    @staticmethod
    def from_unsigned_integral_scalar[
        dtype: DType, //
    ](value: Scalar[dtype]) -> Self:
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
            An unsigned scalar can never be out of range for a BigUInt, so this
            method cannot fail and is not marked `raises`. That is why it is
            kept alongside the general `from_integral_scalar()`: it is the
            entry point usable from non-raising code, such as the single-word
            fast paths in `decimo.biguint.arithmetics`.

            A scalar no wider than `BITS_ALWAYS_IN_ONE_WORD` cannot fill a
            word, so it converts with no division at all: `UInt8`, `UInt16`
            and, at eighteen digits a word, `UInt32` as well. Anything wider is
            peeled one word at a time by repeated division by `BASE`. The
            number of words that can produce is known at compile time from the
            scalar width, so the word list is allocated exactly once and never
            grows.

        Parameters:
            dtype: The scalar data type, must be integral and unsigned.
        """

        # Not a `where` clause: the only in-library caller reaches this through
        # `unsigned_counterpart[dtype]()`, whose result the compiler cannot
        # evaluate while discharging a constraint. An in-body assert checks the
        # same thing at instantiation without demanding a proof from the caller.
        comptime assert (
            dtype.is_integral() and dtype.is_unsigned()
        ), "dtype must be unsigned integral."

        comptime value_bits = size_of[Scalar[dtype]]() * 8

        # A scalar no wider than `BITS_ALWAYS_IN_ONE_WORD` cannot fill a
        # word, so it converts with no division at all. That is `UInt8` and
        # `UInt16` at nine digits a word, and `UInt32` as well at eighteen.
        #
        # The base-10^9 version tested `value <= BASE_MAX` for a 32-bit
        # scalar. Correct then; at eighteen digits `BASE_MAX` does not fit a
        # `UInt32` and the comparison truncated it, which is why this branch
        # is a width test now and not a value test.
        comptime if value_bits <= Self.BITS_ALWAYS_IN_ONE_WORD:
            return Self.from_word_unsafe(Self.Word(value))

        else:
            if value == 0:
                return Self()

            # Upper bound on the number of words, evaluated at
            # compile time so that the list is allocated once and never grows.
            # A `w`-bit unsigned value has at most `floor(w * log10(2)) + 1`
            # decimal digits; 30103/100000 is log10(2) rounded up, which is
            # exact for every width in use (up to 256 bits).
            comptime decimal_digits = value_bits * 30103 // 100000 + 1
            comptime number_of_words = math.ceildiv(
                decimal_digits, Self.DIGITS_PER_WORD
            )

            var result = Self(uninitialized_capacity=number_of_words)
            var remainder: Scalar[dtype] = value
            var quotient: Scalar[dtype]

            while remainder != 0:
                quotient = remainder // Self.BASE
                result.words.append(Self.Word(remainder % Self.BASE))
                remainder = quotient

            return result^

    @staticmethod
    def from_absolute_integral_scalar[
        dtype: DType, //
    ](value: Scalar[dtype]) -> Self where dtype.is_integral():
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

        comptime if (dtype == DType.uint8) or (dtype == DType.uint16):
            # For types that are smaller than word size
            # We can directly convert them to Self.Word
            return Self.from_word_unsafe(Self.Word(value))

        elif (dtype == DType.int8) or (dtype == DType.int16):
            # For signed types that are smaller than 1_000_000_000,
            # we need to handle it differently
            if value < 0:
                # Because -Int16.MIN == Int16.MAX + 1,
                # we need to handle the case by converting it to Int32
                # before taking the absolute value.
                return Self.from_word_unsafe(Self.Word(-Int32(value)))
            else:
                return Self.from_word_unsafe(Self.Word(value))

        else:
            if value == 0:
                return materialize[BigUInt.ZERO]()

            var sign = True if value < 0 else False

            # Built straight into the result's own storage. Filling a
            # `List[Self.Word]` and handing that to `raw_words=` cost 36 ns for
            # the integer 2 -- an allocation for the list, another for the
            # copy into place, to carry a single word. A 64-bit value needs
            # two words, which is inside `WordList`'s inline
            # capacity, so the common case now allocates nothing at all.
            var result = Self(uninitialized_capacity=3)
            var remainder: Scalar[dtype] = value
            var quotient: Scalar[dtype]

            if sign:
                while remainder != 0:
                    quotient = remainder // (-Self.BASE)
                    remainder = remainder % (-Self.BASE)
                    result.words.append(Self.Word(-remainder))
                    remainder = -quotient
            else:
                while remainder != 0:
                    quotient = remainder // Self.BASE
                    remainder = remainder % Self.BASE
                    result.words.append(Self.Word(remainder))
                    remainder = quotient

            return result^

    @staticmethod
    def _from_digits(value: StringSlice) raises -> Optional[BigUInt]:
        """Reads `[+]?digits` into words without an intermediate list.

        Args:
            value: The text to read.

        Returns:
            The value, or nothing when the text is not of that shape -- a
            sign, a point, an exponent, a separator, no digits at all -- in
            which case the caller falls back to `parse_numeric_string()`.

        Raises:
            Error: If building the value fails.

        Notes:
            The general parser writes a `List[UInt8]` of one digit per byte
            and reads it back into words, which for a short value is most of
            what the parse costs: 78 nanoseconds for a single digit against
            8 here. `BigDecimal` has had this path for a while; this is the
            same one, without the point.
        """
        var bytes = value.as_bytes()
        var length = len(bytes)
        var start = 0
        if length > 0 and bytes[0] == 0x2B:
            start = 1
        var digits = length - start
        if digits <= 0:
            return None
        for index in range(start, length):
            var character = bytes[index]
            if character < 0x30 or character > 0x39:
                return None

        var result = Self(
            uninitialized_capacity=math.ceildiv(digits, Self.DIGITS_PER_WORD)
        )
        # Right to left, since a word holds the lowest `DIGITS_PER_WORD`.
        var index = length - 1
        var remaining = digits
        while remaining > 0:
            var word: Self.Word = 0
            var place: Self.Word = 1
            var taken = 0
            while taken < Self.DIGITS_PER_WORD and remaining > 0:
                word += Self.Word(bytes[index] - 0x30) * place
                place *= 10
                taken += 1
                remaining -= 1
                index -= 1
            result.words.append(word)
        result.remove_leading_empty_words()
        return result^

    @staticmethod
    def from_string(
        value: StringSlice, ignore_sign: Bool = False
    ) raises -> BigUInt:
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
        # Nearly every string is digits and nothing else.
        var packed = Self._from_digits(value)
        if packed:
            return packed.take()

        var _tuple = decimo_str.parse_numeric_string(value)
        ref coef: List[UInt8] = _tuple[0]
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
                if coef[len(coef) - i] != 0:
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
        var number_of_words = math.ceildiv(
            number_of_digits, Self.DIGITS_PER_WORD
        )

        var result_words = List[Self.Word](capacity=number_of_words)

        if scale == 0:
            # This is a true integer
            var end: Int = number_of_digits
            var start: Int
            while end >= Self.DIGITS_PER_WORD:
                start = end - Self.DIGITS_PER_WORD
                var word: Self.Word = 0
                for i in range(start, end):
                    word = word * 10 + Self.Word(coef[i])
                result_words.append(word)
                end = start
            if end > 0:
                var word: Self.Word = 0
                for i in range(end):
                    word = word * 10 + Self.Word(coef[i])
                result_words.append(word)

            return Self(raw_words=result_words^)

        else:  # scale < 0
            # This is a true integer with postive exponent
            var number_of_trailing_zero_words = -scale // Self.DIGITS_PER_WORD
            var remaining_trailing_zero_digits = -scale % Self.DIGITS_PER_WORD

            for _ in range(number_of_trailing_zero_words):
                result_words.append(Self.Word(0))

            for _ in range(remaining_trailing_zero_digits):
                coef.append(UInt8(0))

            var end: Int = (
                number_of_digits + scale + remaining_trailing_zero_digits
            )
            var start: Int
            while end >= Self.DIGITS_PER_WORD:
                start = end - Self.DIGITS_PER_WORD
                var word: Self.Word = 0
                for i in range(start, end):
                    word = word * 10 + Self.Word(coef[i])
                result_words.append(word)
                end = start
            if end > 0:
                var word: Self.Word = 0
                for i in range(end):
                    word = word * 10 + Self.Word(coef[i])
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
            ConversionError: If the number exceeds the size of Int.
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

        Notes:

        Horner from the top word down, testing before each multiply rather
        than after summing. The form this replaces built the whole value in an
        `Int128` and compared once at the end, guarded by a word count -- and
        that count was 3, one word more than `Int.MAX` needs at eighteen
        digits a word. A three-word value reached `word * BASE^2 = 10^54`,
        which no `Int128` holds, so it wrapped and the comparison passed:
        `to_int()` of `10^21` returned 6873995514006732800 instead of raising.
        Testing first cannot overflow, whatever the base.
        """
        comptime LIMIT = UInt128(Int.MAX)
        comptime LIMIT_BEFORE_SHIFT = LIMIT // UInt128(Self.BASE)

        var overflow_msg = (
            "The number exceeds the size of Int (" + String(Int.MAX) + ")"
        )

        var value = UInt128(0)
        for i in range(len(self.words) - 1, -1, -1):
            if value > LIMIT_BEFORE_SHIFT:
                raise OverflowError(
                    function="BigUInt.to_int()", message=overflow_msg
                )
            value = value * UInt128(Self.BASE) + UInt128(self.words[i])
            if value > LIMIT:
                raise OverflowError(
                    function="BigUInt.to_int()", message=overflow_msg
                )

        return Int(value)

    def to_uint64(self) raises -> UInt64:
        """Returns the number as UInt64.

        Returns:
            The number as UInt64.

        Raises:
            OverflowError: If the number exceeds the size of UInt64.

        Notes:

        `is_uint64_overflow()` has already ruled out anything that does not
        fit, so Horner from the top word down cannot overflow on the way.

        This used to reassemble the words with a SIMD dot product against
        `(1, 10^9, 10^18, 0)`. Those multipliers are the base spelled out, so
        once a word held eighteen digits every value of more than one word
        came back scaled by `10^9` instead of `10^18` -- `to_uint64()` of
        `10^18` returned `10^9`. The loop below names the base once.
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

        var result = UInt64(0)
        for i in range(len(self.words) - 1, -1, -1):
            result = result * UInt64(Self.BASE) + UInt64(self.words[i])
        return result

    def to_uint128_with_first_2_words(self) -> UInt128:
        """Convert the first two words of the BigUInt to UInt128.

        Notes:
            Two words are below `BASE^2 = 10^36`, which is 120 bits, so this
            is a `UInt128` where the base-10^9 version of it was a `UInt64`.
            The caller must know there are at most two words.

        Returns:
            The `UInt128` representation of the first two words.
        """
        if len(self.words) == 1:
            return UInt128(self.words[0])
        else:  # len(self.words) == 2
            return UInt128(self.words[1]) * UInt128(Self.BASE) + UInt128(
                self.words[0]
            )

    def to_uint128(self) -> UInt128:
        """Returns the number as UInt128.

        **UNSAFE** The caller must know the value fits. `is_uint128_overflow()`
        answers that; a value that does not fit wraps silently.

        Returns:
            The number as UInt128.

        Notes:

        Horner, with the base named once. The SIMD form this replaces spelled
        its multipliers out as powers of `10^9`, so every value of more than
        one word came back wrong the moment a word held eighteen digits.

        It also loaded `width=4` for a three-word value and `width=8` for a
        five-word one, reading past the end of the allocation in both cases.
        The extra lanes were multiplied by zero so the answer was unaffected,
        which is why it never showed up.
        """
        # FIXME: Due to an unknown bug in Mojo, the returned value changed in
        # the caller when this function raised, so the overflow check is left
        # to the caller. Restore it when that is fixed.
        var result = UInt128(0)
        for i in range(len(self.words) - 1, -1, -1):
            result = result * UInt128(Self.BASE) + UInt128(self.words[i])
        return result

    def write_digits_into(
        self,
        pointer: Pointer[UInt8, MutUntrackedOrigin],
        total_length: Int,
    ):
        """Writes the decimal digits into a buffer, right-aligned.

        Args:
            pointer: The start of a buffer with room for `total_length`
                bytes.
            total_length: How many bytes to fill, which must be exactly the
                number of digits the value has.

        Notes:
            The digits go in from the right, one word at a time: every word
            but the most significant is exactly `DIGITS_PER_WORD` of them,
            zero-padded. The caller owns the buffer, so a value being turned
            into text costs no allocation of its own -- a `String` around it
            is the caller's to make, or not.
        """
        ref pairs = global_constant[_TWO_DIGIT_TABLE]()
        var position = total_length
        var word_count = len(self.words)
        for index in range(word_count - 1):
            var value = self.words[index]
            # `DIGITS_PER_WORD` is even, so the word is exactly that many
            # digits in pairs.
            for _ in range(Self.DIGITS_PER_WORD // 2):
                var remainder = Int(value % 100)
                value //= 100
                position -= 2
                pointer[unsafe_offset=position] = pairs[remainder * 2]
                pointer[unsafe_offset=position + 1] = pairs[remainder * 2 + 1]
        var most_significant = self.words[word_count - 1]
        while position >= 2:
            var remainder = Int(most_significant % 100)
            most_significant //= 100
            position -= 2
            pointer[unsafe_offset=position] = pairs[remainder * 2]
            pointer[unsafe_offset=position + 1] = pairs[remainder * 2 + 1]
        if position == 1:
            pointer[unsafe_offset=0] = UInt8(most_significant % 10) + 48

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

        var n_words = len(self.words)

        var result: String
        if n_words == 1:
            # Single word: the digits are exactly `String(word)`, no padding
            # and no buffer of our own.
            result = String(self.words[0])
        else:
            # The most significant word decides the length; every other one
            # contributes exactly `DIGITS_PER_WORD`.
            var total_len = self.number_of_digits()

            # Short values are laid out on the stack and copied into the
            # `String`'s own storage; longer ones get one heap buffer that
            # the `String` then owns. Either way the digits are written once,
            # two at a time, straight from the words.
            comptime STACK_BYTES = 64
            if total_len <= STACK_BYTES:
                var buffer = Array[UInt8, STACK_BYTES](uninitialized=True)
                self.write_digits_into(
                    buffer.unsafe_ptr().unsafe_origin_cast[
                        MutUntrackedOrigin
                    ](),
                    total_len,
                )
                result = String(
                    StringSlice(
                        unsafe_from_utf8=Span(
                            unsafe_ptr=buffer.unsafe_ptr(), length=total_len
                        )
                    )
                )
            else:
                var buffer = List[UInt8](unsafe_uninit_length=total_len)
                self.write_digits_into(
                    buffer.unsafe_ptr().unsafe_origin_cast[
                        MutUntrackedOrigin
                    ](),
                    total_len,
                )
                result = String(unsafe_from_utf8=buffer^)

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
        """Returns string representation of the BigUInt with separators.

        Args:
            separator: The separator string. Default is "_".

        Returns:
            The string representation of the BigUInt with separators.
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
        return biguint_arithmetics.absolute(self)

    @always_inline
    def __neg__(self) raises -> Self:
        """Returns the negation of this number.
        See `negative()` for more information.

        Returns:
            The negated value.

        Raises:
            OverflowError: If the number is non-zero (negative of unsigned is undefined).
        """
        return biguint_arithmetics.negative(self)

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
            biguint_arithmetics.floor_divide_by_2_inplace(result)
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
        return biguint_arithmetics.add(self, other)

    @always_inline
    def __sub__(self, other: Self) raises -> Self:
        """Subtracts two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The difference.

        Raises:
            OverflowError: If the result would be negative.
        """
        try:
            return biguint_arithmetics.subtract(self, other)
        except e:
            raise e^

    @always_inline
    def __mul__(self, other: Self) -> Self:
        """Multiplies two values.

        Args:
            other: The right-hand side operand.

        Returns:
            The product.
        """
        return biguint_arithmetics.multiply(self, other)

    @always_inline
    def __floordiv__(self, other: Self) raises -> Self:
        """Divides two values using floor division.

        Args:
            other: The right-hand side operand.

        Returns:
            The quotient.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        try:
            return biguint_arithmetics.floor_divide(self, other)
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

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        try:
            return biguint_arithmetics.ceil_divide(self, other)
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

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        try:
            return biguint_arithmetics.floor_modulo(self, other)
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

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        try:
            return biguint_arithmetics.floor_divide_modulo(self, other)
        except e:
            raise e^

    @always_inline
    def __pow__(self, exponent: Self) raises -> Self:
        """Raises to a power.

        Args:
            exponent: The exponent to raise this number to.

        Returns:
            The power `self` raised to `exponent`.

        Raises:
            ValueError: If the exponent is too large.
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

        Raises:
            ValueError: If the exponent is negative or too large.
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

        Raises:
            Error: Propagated from underlying operations.
        """
        return biguint_arithmetics.add(self, other)

    @always_inline
    def __rsub__(self, other: Self) raises -> Self:
        """Subtracts two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The difference.

        Raises:
            OverflowError: If the result would be negative.
        """
        return biguint_arithmetics.subtract(other, self)

    @always_inline
    def __rmul__(self, other: Self) raises -> Self:
        """Multiplies two values (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The product.

        Raises:
            Error: Propagated from underlying operations.
        """
        return biguint_arithmetics.multiply(self, other)

    @always_inline
    def __rfloordiv__(self, other: Self) raises -> Self:
        """Divides two values using floor division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The quotient.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return biguint_arithmetics.floor_divide(other, self)

    @always_inline
    def __rmod__(self, other: Self) raises -> Self:
        """Returns the remainder of division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            The remainder.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return biguint_arithmetics.floor_modulo(other, self)

    @always_inline
    def __rdivmod__(self, other: Self) raises -> Tuple[Self, Self]:
        """Returns the quotient and remainder of division (reflected).

        Args:
            other: The left-hand side operand.

        Returns:
            A tuple of (quotient, remainder).

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return biguint_arithmetics.floor_divide_modulo(other, self)

    @always_inline
    def __rpow__(self, base: Self) raises -> Self:
        """Raises to a power (reflected).

        Args:
            base: The base to raise to the power of `self`.

        Returns:
            The power `base` raised to `self`.

        Raises:
            ValueError: If the exponent is too large.
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
        biguint_arithmetics.add_inplace(self, other)

    @always_inline
    def __isub__(mut self, other: Self) raises:
        """Subtracts `other` from `self` in place.
        See `biguint.arithmetics.subtract_inplace()` for more information.

        Args:
            other: The operand to subtract.

        Raises:
            OverflowError: If the result would be negative.
        """
        biguint_arithmetics.subtract_inplace(self, other)

    @always_inline
    def __imul__(mut self, other: Self) raises:
        """Multiplies in place.

        Args:
            other: The operand to multiply by.

        Raises:
            Error: Propagated from underlying operations.
        """
        self = biguint_arithmetics.multiply(self, other)

    @always_inline
    def __ifloordiv__(mut self, other: Self) raises:
        """Divides in place using floor division.

        Args:
            other: The divisor.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        self = biguint_arithmetics.floor_divide(self, other)

    @always_inline
    def __imod__(mut self, other: Self) raises:
        """Computes the remainder in place.

        Args:
            other: The divisor.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        self = biguint_arithmetics.floor_modulo(self, other)

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
        return biguint_comparison.greater(self, other)

    @always_inline
    def __ge__(self, other: Self) -> Bool:
        """Returns True if self >= other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self` is greater than or equal to `other`, `False` otherwise.
        """
        return biguint_comparison.greater_equal(self, other)

    @always_inline
    def __lt__(self, other: Self) -> Bool:
        """Returns True if self < other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self` is less than `other`, `False` otherwise.
        """
        return biguint_comparison.less(self, other)

    @always_inline
    def __le__(self, other: Self) -> Bool:
        """Returns True if self <= other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self` is less than or equal to `other`, `False` otherwise.
        """
        return biguint_comparison.less_equal(self, other)

    @always_inline
    def __eq__(self, other: Self) -> Bool:
        """Returns True if self == other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self` equals `other`, `False` otherwise.
        """
        return biguint_comparison.equal(self, other)

    @always_inline
    def __ne__(self, other: Self) -> Bool:
        """Returns True if self != other.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self` does not equal `other`, `False` otherwise.
        """
        return biguint_comparison.not_equal(self, other)

    # ===------------------------------------------------------------------=== #
    # Other dunders
    # ===------------------------------------------------------------------=== #

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

        Raises:
            Error: Propagated from underlying operations.
        """
        biguint_arithmetics.add_inplace(self, other)

    @always_inline
    def floor_divide(self, other: Self) raises -> Self:
        """Returns the result of floor dividing this number by `other`.
        It is equal to `self // other`.
        See `floor_divide()` for more information.

        Args:
            other: The divisor.

        Returns:
            The quotient.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return biguint_arithmetics.floor_divide(self, other)

    @always_inline
    def truncate_divide(self, other: Self) raises -> Self:
        """Returns the result of truncate dividing this number by `other`.
        It is equal to `self // other`.
        See `truncate_divide()` for more information.

        Args:
            other: The divisor.

        Returns:
            The quotient.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return biguint_arithmetics.truncate_divide(self, other)

    @always_inline
    def ceil_divide(self, other: Self) raises -> Self:
        """Returns the result of ceil dividing this number by `other`.
        See `ceil_divide()` for more information.

        Args:
            other: The divisor.

        Returns:
            The quotient rounded up.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return biguint_arithmetics.ceil_divide(self, other)

    @always_inline
    def floor_modulo(self, other: Self) raises -> Self:
        """Returns the result of floor modulo this number by `other`.
        See `floor_modulo()` for more information.

        Args:
            other: The divisor.

        Returns:
            The remainder.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return biguint_arithmetics.floor_modulo(self, other)

    @always_inline
    def truncate_modulo(self, other: Self) raises -> Self:
        """Returns the result of truncate modulo this number by `other`.
        See `truncate_modulo()` for more information.

        Args:
            other: The divisor.

        Returns:
            The remainder.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return biguint_arithmetics.truncate_modulo(self, other)

    @always_inline
    def ceil_modulo(self, other: Self) raises -> Self:
        """Returns the result of ceil modulo this number by `other`.
        See `ceil_modulo()` for more information.

        Args:
            other: The divisor.

        Returns:
            The remainder.

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return biguint_arithmetics.ceil_modulo(self, other)

    @always_inline
    def divmod(self, other: Self) raises -> Tuple[Self, Self]:
        """Returns the result of divmod this number by `other`.
        See `divmod()` for more information.

        Args:
            other: The divisor.

        Returns:
            A tuple of (quotient, remainder).

        Raises:
            ZeroDivisionError: If the divisor is zero.
        """
        return biguint_arithmetics.floor_divide_modulo(self, other)

    @always_inline
    def floor_divide_by_2_inplace(mut self) raises:
        """Divides this number by 2 in place.
        See `decimo.biguint.arithmetics.floor_divide_by_2_inplace()`
        for more information.

        Raises:
            Error: Propagated from underlying operations.
        """
        biguint_arithmetics.floor_divide_by_2_inplace(self)

    @always_inline
    def multiply_by_power_of_ten(self, n: Int) -> Self:
        """Returns the result of multiplying this number by 10^n (n>=0).
        See `multiply_by_power_of_ten()` for more information.

        Args:
            n: The power of 10 to multiply by.

        Returns:
            The product of this number and 10^n.
        """
        return biguint_arithmetics.multiply_by_power_of_ten(self, n)

    @always_inline
    def multiply_by_power_of_ten_inplace(mut self, n: Int):
        """Multiplies this number in-place by 10^n (n>=0).
        See
        `decimo.biguint.arithmetics.multiply_by_power_of_ten_inplace()`
        for more information.

        Args:
            n: The power of 10 to multiply by.
        """
        biguint_arithmetics.multiply_by_power_of_ten_inplace(self, n)

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
        return biguint_arithmetics.floor_divide_by_power_of_ten(self, n)

    @always_inline
    def multiply_by_power_of_base_inplace(mut self, n: Int):
        """Multiplies a BigUInt in-place by `BASE^n` if n > 0.
        This equals to appending `n` zero words to the end of the number.

        Args:
            n: The power of `BASE` to multiply by. Should be non-negative.
        """
        biguint_arithmetics.multiply_by_power_of_base_inplace(self, n)

    def power(self, exponent: Int) raises -> Self:
        """Returns the result of raising this number to the power of `exponent`.

        Args:
            exponent: The exponent to raise the number to.

        Returns:
            A `BigUInt` representing `self` raised to the power of `exponent`.

        Raises:
            ValueError: If the exponent is negative.
            ValueError: If the exponent is too large, e.g., larger than 1_000_000_000.
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
            return Self.from_word_unsafe(1)

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

        var result = Self.from_word_unsafe(1)
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
        return biguint_exponential.sqrt(self)

    def isqrt(self) -> Self:
        """Returns the square root of this number.
        It is equal to `sqrt()`.

        Returns:
            The square root of x as a BigUInt.

        Notes:

        The square root is the largest integer y such that y * y <= x.
        """
        return biguint_exponential.sqrt(self)

    @always_inline
    def compare(self, other: Self) -> Int8:
        """Compares the magnitudes of two BigUInts.
        See `compare()` for more information.

        Args:
            other: The value to compare against.

        Returns:
            A positive value if `self > other`, 0 if equal, or a negative value if `self < other`.
        """
        return biguint_comparison.compare(self, other)

    # ===------------------------------------------------------------------=== #
    # Other methods
    # ===------------------------------------------------------------------=== #

    def internal_representation(self) -> String:
        """Returns the internal representation details as a String.

        Returns:
            A formatted string showing the number and its individual words.
        """
        # Collect all labels to find max width
        var max_label_len = "number:".byte_length()
        for i in range(len(self.words)):
            var label_len = "word :".byte_length() + String(i).byte_length()
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
        result += "number:" + String(" ") * (col - "number:".byte_length())
        for i in range(len(string_of_number)):
            if i > 0:
                result += String(" ") * col
            result += string_of_number[i] + "\n"

        # word lines
        for i in range(len(self.words)):
            var label = "word " + String(i) + ":"
            result += label + String(" ") * (col - label.byte_length())
            result += (
                decimo_str.rjust(
                    String(self.words[i]), Self.DIGITS_PER_WORD, fillchar="0"
                )
                + "\n"
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
            (len(self.words) == 1) or (self.words[len(self.words) - 1] != 0),
            "biguint.BigUInt.is_zero(): ",
            "BigUInt should not contain leading zero words.",
        )  # 0 should have only one word by design

        return len(self.words) == 1 and self.words.unsafe_ptr()[] == 0

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
            for index in range(1, len(self.words)):
                if self.words[index] != 0:
                    return False
            return True

    @always_inline
    def is_two(self) -> Bool:
        """Returns True if this BigUInt represents two.

        Returns:
            `True` if the value is two, `False` otherwise.
        """
        if len(self.words) != 2:
            return False
        for index in range(1, len(self.words)):
            if self.words[index] != 0:
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
        # Divide the tens out and see whether 1 is what is left. This used to
        # enumerate `10^0` through `10^8` -- the nine values a nine-digit word
        # can hold -- so at eighteen digits it answered `False` for `10^9`
        # through `10^17`, which is a word's whole upper half.
        var word = x.words[len(x.words) - 1]
        if word == 0:
            return False
        while word % 10 == 0:
            word //= 10
        return word == 1

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
        # word 0:         446_744_073_709_551_615
        # word 1:         18
        if len(self.words) > 2:
            return True
        elif len(self.words) == 2:
            if self.words[1] > Self.Word(18):
                return True
            elif self.words[1] == Self.Word(18):
                if self.words[0] > Self.Word(446_744_073_709_551_615):
                    return True
        return False

    @always_inline
    def is_uint128_overflow(self) -> Bool:
        """Returns True if the BigUInt larger than UInt128.MAX.

        Returns:
            `True` if the value exceeds `UInt128.MAX`, `False` otherwise.
        """
        # UInt128.MAX:    340_282_366_920_938_463_463_374_607_431_768_211_455
        # word 0:         374_607_431_768_211_455
        # word 1:         282_366_920_938_463_463
        # word 2:         340
        #
        # The base-10^9 version of this compared `words[4]` under
        # `len(self.words) == 4`, which read one past the end, and let a
        # five-word value -- the only length that can actually overflow --
        # fall through to `False`. See `test_uint128_overflow_boundary`.
        if len(self.words) > 3:
            return True
        elif len(self.words) == 3:
            if self.words[2] > Self.Word(340):
                return True
            elif self.words[2] == Self.Word(340):
                if self.words[1] > Self.Word(282_366_920_938_463_463):
                    return True
                elif self.words[1] == Self.Word(282_366_920_938_463_463):
                    if self.words[0] > Self.Word(374_607_431_768_211_455):
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
        if i >= len(self.words) * Self.DIGITS_PER_WORD:
            return 0
        var word_index = i // Self.DIGITS_PER_WORD
        var digit_index = i % Self.DIGITS_PER_WORD
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

        var result: Int = (len(self.words) - 1) * Self.DIGITS_PER_WORD
        var last_word = self.words[len(self.words) - 1]
        while last_word > 0:
            result += 1
            last_word = last_word // 10
        return result

    def number_of_words(self) -> Int:
        """Returns the number of words in the BigUInt.

        Returns:
            The number of `Self.Word` words in the internal representation.
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
                result += Self.DIGITS_PER_WORD
            else:
                var word = self.words[i]
                while word % 10 == 0:
                    result += 1
                    word = word // 10
                break
        return result

    @always_inline
    def assert_invariant(self, context: StaticString = "") -> None:
        """Checks the representation invariant documented on the struct.

        A `debug_assert`, so it compiles away entirely unless the build sets
        `-D ASSERT=all`. Call it at the end of any function that rebuilds
        `words` by hand, and the test suite will catch a malformed result at
        the point that produced it rather than wherever it later misbehaves.

        Args:
            context: Name of the calling function, shown if the check fires.
        """
        debug_assert(
            len(self.words) > 0,
            "BigUInt.assert_invariant(): empty words. ",
            context,
        )
        debug_assert(
            len(self.words) == 1 or self.words[len(self.words) - 1] != 0,
            "BigUInt.assert_invariant(): leading zero word. ",
            context,
        )

    def copy_with_extra_capacity(self, extra_words: Int) -> Self:
        """Copies `self`, leaving room for `extra_words` more words.

        For the common shape "copy a value, then grow it by a bounded amount":
        multiplying by a single word can add one word, adding can carry into
        one. A plain `copy()` allocates exactly what it holds, so the growth
        then reallocates and copies again -- two allocations where one would
        do, and at small sizes an allocation is most of the operation.

        Args:
            extra_words: Number of words of spare capacity. Must not be
                negative.

        Returns:
            A copy of `self` whose capacity is `len(words) + extra_words`.
        """
        debug_assert(
            extra_words >= 0,
            "BigUInt.copy_with_extra_capacity(): negative extra_words ",
            extra_words,
        )
        var count = len(self.words)
        var result = Self(
            unsafe_uninit_length=count,
            unsafe_uninit_capacity=count + extra_words,
        )
        unsafe_memcpy(
            dest=result.words.unsafe_ptr(),
            src=self.words.unsafe_ptr(),
            count=count,
        )
        return result^

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
            self.assert_invariant("remove_leading_empty_words")

    @always_inline
    def remove_trailing_digits_with_rounding(
        self,
        ndigits_to_remove: Int,
        rounding_mode: RoundingMode,
        remove_extra_digit_due_to_rounding: Bool,
        sign: Bool = False,
    ) raises -> Self:
        """Removes trailing digits from the BigUInt with rounding.

        Args:
            ndigits_to_remove: The number of digits to remove.
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

        Thin wrapper around
        `remove_trailing_digits_with_rounding_inplace`: copies `self`
        once and delegates to the in-place variant. Keeps a single
        source of truth for the rounding logic.

        Argument validation is performed here (before the copy) so the
        raised error's `function` tag points at this out-of-place API
        rather than at the inner `_inplace` helper. The in-place path
        re-validates with its own tag for callers that invoke it
        directly.
        """
        # Pre-flight validation so errors are tagged with the
        # user-facing function name. Cheap (three comparisons +
        # one `number_of_digits()` only on the bounds path).
        if ndigits_to_remove < 0:
            raise ValueError(
                function="BigUInt.remove_trailing_digits_with_rounding()",
                message=(
                    "The number of digits to remove is negative: "
                    + String(ndigits_to_remove)
                ),
            )
        if ndigits_to_remove == 0:
            return self.copy()
        var ndigits_self = self.number_of_digits()
        if ndigits_to_remove > ndigits_self:
            raise ValueError(
                function="BigUInt.remove_trailing_digits_with_rounding()",
                message=(
                    "The number of digits to remove is larger than the "
                    "number of digits in the BigUInt: "
                    + String(ndigits_to_remove)
                    + " > "
                    + String(ndigits_self)
                ),
            )
        var result = self.copy()
        result.remove_trailing_digits_with_rounding_inplace(
            ndigits_to_remove=ndigits_to_remove,
            rounding_mode=rounding_mode,
            remove_extra_digit_due_to_rounding=(
                remove_extra_digit_due_to_rounding
            ),
            sign=sign,
            ndigits_before_removal=ndigits_self,
        )
        return result^

    @always_inline
    def remove_trailing_digits_with_rounding_inplace(
        mut self,
        ndigits_to_remove: Int,
        rounding_mode: RoundingMode,
        remove_extra_digit_due_to_rounding: Bool,
        sign: Bool = False,
        ndigits_before_removal: Int = -1,
    ) raises:
        """In-place sibling of `remove_trailing_digits_with_rounding`.

        Drops the lowest `ndigits_to_remove` decimal digits of `self`, applying the
        same rounding rules, but reuses the existing `words` storage via
        `floor_divide_by_power_of_ten_inplace` instead of allocating a
        fresh coefficient buffer. Saves one alloc and one full-buffer
        copy per call, which compounds across every `precision > 0`
        invocation of `add` / `subtract` / `multiply` (each ends in a
        `round_to_precision_inplace` call).

        Args:
            ndigits_to_remove: The number of digits to remove.
            rounding_mode: The rounding mode to use. See
                `remove_trailing_digits_with_rounding` for the full list.
            remove_extra_digit_due_to_rounding: If True, also drop one
                more trailing digit when rounding produces an extra
                leading digit (e.g. 999 → 1000 → 100).
            sign: The sign of the original number (True = negative).
                Only consulted for CEILING / FLOOR modes.
            ndigits_before_removal: Optional pre-computed value of
                `self.number_of_digits()`. If `>= 0`, used directly
                instead of recomputing (saves one `number_of_digits()`
                pass when the caller already has it, e.g.
                `round_to_precision_inplace`). Must be correct — no
                validation is performed beyond the bounds check.

        Raises:
            ValueError: If `ndigits_to_remove` is negative or exceeds the digit
                count of `self`.
        """
        if ndigits_to_remove < 0:
            raise ValueError(
                function=(
                    "BigUInt.remove_trailing_digits_with_rounding_inplace()"
                ),
                message=(
                    "The number of digits to remove is negative: "
                    + String(ndigits_to_remove)
                ),
            )
        if ndigits_to_remove == 0:
            return
        var ndigits_self = (
            ndigits_before_removal if ndigits_before_removal
            >= 0 else self.number_of_digits()
        )
        if ndigits_to_remove > ndigits_self:
            raise ValueError(
                function=(
                    "BigUInt.remove_trailing_digits_with_rounding_inplace()"
                ),
                message=(
                    "The number of digits to remove is larger than the "
                    "number of digits in the BigUInt: "
                    + String(ndigits_to_remove)
                    + " > "
                    + String(ndigits_self)
                ),
            )

        # Resolve the rounding decision against the *pre-truncation*
        # digits of `self`, mirroring the out-of-place variant.
        var effective_mode = rounding_mode
        if rounding_mode == RoundingMode.ceiling():
            effective_mode = (
                RoundingMode.up() if not sign else RoundingMode.down()
            )
        elif rounding_mode == RoundingMode.floor():
            effective_mode = (
                RoundingMode.down() if not sign else RoundingMode.up()
            )

        var round_up: Bool = False
        if effective_mode == RoundingMode.down():
            pass
        elif effective_mode == RoundingMode.up():
            if self.number_of_trailing_zeros() < ndigits_to_remove:
                round_up = True
        elif effective_mode == RoundingMode.half_up():
            if self.ith_digit(ndigits_to_remove - 1) >= 5:
                round_up = True
        elif effective_mode == RoundingMode.half_down():
            var cut_off_digit = self.ith_digit(ndigits_to_remove - 1)
            if cut_off_digit > 5:
                round_up = True
            elif cut_off_digit == 5:
                if self.number_of_trailing_zeros() < ndigits_to_remove - 1:
                    round_up = True
        elif effective_mode == RoundingMode.half_even():
            var cut_off_digit = self.ith_digit(ndigits_to_remove - 1)
            if cut_off_digit > 5:
                round_up = True
            elif cut_off_digit < 5:
                pass
            else:  # cut_off_digit == 5
                if self.number_of_trailing_zeros() < ndigits_to_remove - 1:
                    round_up = True
                else:
                    round_up = self.ith_digit(ndigits_to_remove) % 2 == 1
        # TODO: Remove this fallback once Mojo has proper enum support.
        else:
            raise ValueError(
                function=(
                    "BigUInt.remove_trailing_digits_with_rounding_inplace()"
                ),
                message=("Unknown rounding mode: " + String(rounding_mode)),
            )

        # Drop the digits in place, then apply the carry from rounding.
        biguint_arithmetics.floor_divide_by_power_of_ten_inplace(
            self, ndigits_to_remove
        )
        if round_up:
            biguint_arithmetics.add_by_word_inplace(self, Self.Word(1))
            if self.is_power_of_10():
                if remove_extra_digit_due_to_rounding:
                    biguint_arithmetics.floor_divide_by_power_of_ten_inplace(
                        self, 1
                    )
