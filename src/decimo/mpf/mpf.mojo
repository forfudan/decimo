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

"""Implements the MPF type: arbitrary-precision binary floating-point.

MPF wraps a single MPFR handle via a C wrapper. Every arithmetic and
transcendental operation is a single MPFR call. Requires MPFR at runtime.

Usage:
    from decimo.mpf.mpf import MPF

    var x = MPF("3.14159", precision=1000)
    var r = x.sqrt()
    var bd = r.to_bigdecimal(1000)

Design:
    - Single field: `handle: Int32` (index into C wrapper's mpfr_t handle pool)
    - Precision specified in decimal digits, converted to bits internally
    - Guard bits (64 extra) ensure requested decimal digits are correct
    - RAII: destructor frees MPFR handle via `decimo_mpfrw_clear`
"""

from std import math
from std.ffi import c_char, external_call
from std.memory import Pointer

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.biguint.biguint import BigUInt
from decimo.errors import ConversionError, RuntimeError, ValueError
from decimo.mpf.mpfr_wrapper import (
    decimo_mpfrw_abs,
    decimo_mpfrw_add,
    decimo_mpfrw_available,
    decimo_mpfrw_clear,
    decimo_mpfrw_cmp,
    decimo_mpfrw_const_pi,
    decimo_mpfrw_cos,
    decimo_mpfrw_div,
    decimo_mpfrw_exp,
    decimo_mpfrw_free_raw_str,
    decimo_mpfrw_free_str,
    decimo_mpfrw_get_raw_digits,
    decimo_mpfrw_get_str,
    decimo_mpfrw_init,
    decimo_mpfrw_log,
    decimo_mpfrw_mul,
    decimo_mpfrw_neg,
    decimo_mpfrw_pow,
    decimo_mpfrw_rootn_ui,
    decimo_mpfrw_set_str,
    decimo_mpfrw_sin,
    decimo_mpfrw_sqrt,
    decimo_mpfrw_sub,
    decimo_mpfrw_tan,
)
from decimo.traits import Rootable

# Guard bits added to user-requested precision to absorb binary↔decimal rounding.
comptime _GUARD_BITS: Int = 64

# Bits per decimal digit: log2(10) ≈ 3.322. Rounded up to 4 for safety.
comptime _BITS_PER_DIGIT: Int = 4

# Default precision in decimal digits, same as BigDecimal.
comptime PRECISION: Int = 28
"""Default precision in decimal digits for MPF."""

# The short aliases `BFlt` and `Float` that this type used to carry are
# deliberately not here. They belong to the name `BigFloat`, which since
# v0.16.0 is the float written in Mojo rather than the one borrowed from MPFR.


def _dps_to_bits(precision: Int) -> Int:
    """Converts decimal digit precision to MPFR bit precision with guard bits.
    """
    return precision * _BITS_PER_DIGIT + _GUARD_BITS


def _read_c_string(address: Int) -> String:
    """Reads a null-terminated C string at the given raw address into a Mojo
    String.

    The caller is responsible for freeing the C string afterward.
    """
    var length = external_call["strlen", Int](
        address
    )  # Exclude null terminator
    if length == 0:
        return String("")
    var buf = List[Byte](capacity=length)
    for _ in range(length):
        buf.append(0)
    external_call["memcpy", NoneType](buf.unsafe_ptr(), address, length)
    return String(unsafe_from_utf8=buf)


# ===----------------------------------------------------------------------=== #
# MPF
# ===----------------------------------------------------------------------=== #


struct MPF(Comparable, Movable, Rootable, Writable):
    """Arbitrary-precision binary floating-point type backed by MPFR.

    Each MPF owns a single MPFR handle (index into the C wrapper's pool).
    Precision is specified in decimal digits and converted to bits internally.
    Arithmetic and transcendental operations are single MPFR calls.

    MPF is Movable but not Copyable. Transfer ownership with `^`:

        var a = MPF("2.0", 100)
        var b = a^  # moves a into b; a is consumed
    """

    var handle: Int32
    """The MPFR context handle (index into the C wrapper's handle pool)."""
    var precision: Int
    """The number of significant decimal digits."""

    # ===------------------------------------------------------------------=== #
    # Constructors
    # ===------------------------------------------------------------------=== #

    def __init__(out self, value: String, precision: Int = PRECISION) raises:
        """Creates a MPF from a decimal string.

        Args:
            value: A decimal number string (e.g. "3.14159", "-1.5e10").
            precision: Number of significant decimal digits.

        Raises:
            ValueError: If the precision is negative.
            RuntimeError: If MPFR is not available or handle pool is exhausted.
            ConversionError: If the string is not a valid number.
        """
        if precision < 0:
            raise ValueError(
                message="Precision must be non-negative",
                function="MPF.__init__()",
            )
        if not decimo_mpfrw_available():
            raise RuntimeError(
                message=(
                    "MPF requires MPFR (brew install mpfr / apt"
                    " install libmpfr-dev)"
                ),
                function="MPF.__init__()",
            )
        var bits = _dps_to_bits(precision)
        self.handle = decimo_mpfrw_init(bits)
        if self.handle < 0:
            raise RuntimeError(
                message="MPFR handle pool exhausted",
                function="MPF.__init__()",
            )
        self.precision = precision
        var s_bytes = value.as_bytes()
        var result_code = decimo_mpfrw_set_str(
            self.handle,
            s_bytes.unsafe_ptr().unsafe_bitcast[c_char](),
            Int32(len(s_bytes)),
        )
        if result_code != 0:
            decimo_mpfrw_clear(self.handle)
            raise ConversionError(
                message="Invalid number string: " + value,
                function="MPF.__init__()",
            )

    def __init__(out self, value: Int, precision: Int = PRECISION) raises:
        """Creates a MPF from an integer.

        Args:
            value: The integer to convert.
            precision: The number of significant decimal digits.

        Raises:
            ConversionError: If the integer cannot be represented as a MPF.
        """
        self = Self(String(value), precision)

    def __init__(
        out self, decimal: BigDecimal, precision: Int = PRECISION
    ) raises:
        """Creates a MPF from a BigDecimal.

        Args:
            decimal: The `BigDecimal` to convert.
            precision: The number of significant decimal digits.

        Raises:
            ConversionError: If the BigDecimal string cannot be parsed as a MPF.
        """
        self = Self(decimal.to_string(), precision)

    def __init__(out self, *, _handle: Int32, _precision: Int):
        """Internal: wraps an existing MPFR handle. Caller transfers ownership.

        Args:
            _handle: The MPFR context handle to take ownership of.
            _precision: The number of significant decimal digits.
        """
        self.handle = _handle
        self.precision = _precision

    # ===------------------------------------------------------------------=== #
    # Lifecycle
    # ===------------------------------------------------------------------=== #

    def __init__(out self, *, deinit move: Self):
        """Moves a MPF, transferring handle ownership.

        Args:
            move: The instance to move from.
        """
        self.handle = move.handle
        self.precision = move.precision

    def __deinit__(deinit self):
        """Frees the MPFR handle."""
        if self.handle >= 0:
            decimo_mpfrw_clear(self.handle)

    # ===------------------------------------------------------------------=== #
    # String conversion
    # ===------------------------------------------------------------------=== #

    def to_string(self, digits: Int = -1) raises -> String:
        """Exports the value as a decimal string.

        Args:
            digits: Number of significant digits. Defaults to the MPF's
                precision.

        Returns:
            A decimal string representation.

        Raises:
            ConversionError: If string export fails.
        """
        var d = digits if digits > 0 else self.precision
        var address = decimo_mpfrw_get_str(self.handle, Int32(d))
        if address == 0:
            raise ConversionError(
                message="Failed to export string",
                function="MPF.to_string()",
            )
        var result = _read_c_string(address)
        decimo_mpfrw_free_str(address)
        return result

    def write_to[W: Writer](self, mut writer: W):
        """Writes the decimal string representation to a Writer.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        if self.handle < 0:
            writer.write("MPF(<moved>)")
            return
        var address = decimo_mpfrw_get_str(self.handle, Int32(self.precision))
        if address == 0:
            writer.write("MPF(<error>)")
            return
        var s = _read_c_string(address)
        decimo_mpfrw_free_str(address)
        writer.write(s)

    def write_repr_to[W: Writer](self, mut writer: W):
        """Writes a repr-style string to a Writer.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        if self.handle < 0:
            writer.write('MPF("<moved>")')
            return
        var address = decimo_mpfrw_get_str(self.handle, Int32(self.precision))
        if address == 0:
            writer.write('MPF("<error>")')
            return
        var s = _read_c_string(address)
        decimo_mpfrw_free_str(address)
        writer.write('MPF("', s, '")')

    # ===------------------------------------------------------------------=== #
    # Conversion
    # ===------------------------------------------------------------------=== #

    def to_bigdecimal(self, precision: Int = -1) raises -> BigDecimal:
        """Converts this MPF to a BigDecimal.

        Uses MPFR's raw digit export to build a BigDecimal directly,
        bypassing full string parsing for efficiency.

        Data flow (1 memcpy, 0 intermediate lists):
          C: mpfr_get_str → MPFR-allocated digit buffer + exponent
          memcpy → Mojo-owned byte buffer  (single copy)
          byte buffer → pack into base-10⁹ UInt32 words  (in-place read)

        Args:
            precision: Number of significant decimal digits for the conversion.
                Defaults to the MPF's own precision.

        Returns:
            A BigDecimal with the requested number of significant digits.

        Raises:
            ConversionError: If raw digit export fails.
        """
        var d = precision if precision > 0 else self.precision

        # 1. Get raw digits + exponent in one call
        # decimo_mpfrw_get_raw_digits calls mpfr_get_str (resolved as p_get_str
        # via dlsym).  It returns a pure ASCII digit string like
        # "31415926535897932385" (possibly "-" prefixed for negatives) and
        # writes the base-10 exponent to out_exp.
        # Meaning: value = 0.<digits> × 10^exp.
        var exp = Int(0)
        var address = decimo_mpfrw_get_raw_digits(
            self.handle, Int32(d), Pointer(to=exp)
        )
        if address == 0:
            raise ConversionError(
                message="mpfr_get_str failed",
                function="MPF.to_bigdecimal()",
            )

        # 2. Single memcpy into a Mojo-owned buffer
        comptime ASCII_MINUS: UInt8 = 45  # ord("-")
        comptime ASCII_ZERO: UInt8 = 48  # ord("0")
        var n = external_call["strlen", Int](address)
        var buf = List[UInt8](unsafe_uninit_length=n)
        external_call["memcpy", NoneType](buf.unsafe_ptr(), address, n)
        decimo_mpfrw_free_raw_str(address)  # Free MPFR allocation immediately.

        # 3. Read bytes from the Mojo buffer (no further copies)
        var ptr = buf.unsafe_ptr()

        # Detect sign (negative values have '-' prefix from MPFR).
        var sign = False
        var digit_start = 0
        if n > 0 and ptr[unsafe_offset=0] == ASCII_MINUS:
            sign = True
            digit_start = 1

        var num_digits = n - digit_start

        # scale = number_of_significant_digits - exponent
        # e.g. digits "31415" with exp=1 → 3.1415 → scale = 5 - 1 = 4
        var scale = num_digits - exp

        # 4. Pack ASCII bytes directly into the coefficient's words
        var number_of_words = math.ceildiv(num_digits, BigUInt.DIGITS_PER_WORD)
        var words = List[BigUInt.Word](capacity=number_of_words)
        var end = num_digits
        while end >= BigUInt.DIGITS_PER_WORD:
            var start = end - BigUInt.DIGITS_PER_WORD
            var word: BigUInt.Word = 0
            for j in range(start, end):
                word = word * 10 + BigUInt.Word(
                    ptr[unsafe_offset=digit_start + j] - ASCII_ZERO
                )
            words.append(word)
            end = start
        if end > 0:
            var word: BigUInt.Word = 0
            for j in range(0, end):
                word = word * 10 + BigUInt.Word(
                    ptr[unsafe_offset=digit_start + j] - ASCII_ZERO
                )
            words.append(word)

        var coefficient = BigUInt(raw_words=words^)
        return BigDecimal(coefficient=coefficient^, scale=scale, sign=sign)

    # ===------------------------------------------------------------------=== #
    # Comparison
    # ===------------------------------------------------------------------=== #

    def __eq__(self, other: Self) -> Bool:
        """Checks whether two MPF values are equal.

        Args:
            other: The value to compare against.

        Returns:
            `True` if the values are equal, `False` otherwise.
        """
        return decimo_mpfrw_cmp(self.handle, other.handle) == 0

    def __ne__(self, other: Self) -> Bool:
        """Checks whether two MPF values are not equal.

        Args:
            other: The value to compare against.

        Returns:
            `True` if the values are not equal, `False` otherwise.
        """
        return decimo_mpfrw_cmp(self.handle, other.handle) != 0

    def __lt__(self, other: Self) -> Bool:
        """Checks whether this value is strictly less than another.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self < other`, `False` otherwise.
        """
        var c = decimo_mpfrw_cmp(self.handle, other.handle)
        return c != -2 and c < 0

    def __le__(self, other: Self) -> Bool:
        """Checks whether this value is less than or equal to another.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self <= other`, `False` otherwise.
        """
        var c = decimo_mpfrw_cmp(self.handle, other.handle)
        return c != -2 and c <= 0

    def __gt__(self, other: Self) -> Bool:
        """Checks whether this value is strictly greater than another.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self > other`, `False` otherwise.
        """
        var c = decimo_mpfrw_cmp(self.handle, other.handle)
        return c != -2 and c > 0

    def __ge__(self, other: Self) -> Bool:
        """Checks whether this value is greater than or equal to another.

        Args:
            other: The value to compare against.

        Returns:
            `True` if `self >= other`, `False` otherwise.
        """
        var c = decimo_mpfrw_cmp(self.handle, other.handle)
        return c != -2 and c >= 0

    # ===------------------------------------------------------------------=== #
    # Unary operators
    # ===------------------------------------------------------------------=== #

    def __neg__(self) raises -> Self:
        """Negates this value.

        Returns:
            The negated value.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var h = decimo_mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.__neg__()",
            )
        decimo_mpfrw_neg(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def __abs__(self) raises -> Self:
        """Computes the absolute value.

        Returns:
            The absolute value.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var h = decimo_mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.__abs__()",
            )
        decimo_mpfrw_abs(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    # ===------------------------------------------------------------------=== #
    # Binary arithmetic operators
    # ===------------------------------------------------------------------=== #

    def __add__(self, other: Self) raises -> Self:
        """Adds two MPF values.

        Args:
            other: The right-hand side operand.

        Returns:
            The sum.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var prec = max(self.precision, other.precision)
        var h = decimo_mpfrw_init(_dps_to_bits(prec))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.__add__()",
            )
        decimo_mpfrw_add(h, self.handle, other.handle)
        return Self(_handle=h, _precision=prec)

    def __sub__(self, other: Self) raises -> Self:
        """Subtracts two MPF values.

        Args:
            other: The right-hand side operand.

        Returns:
            The difference.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var prec = max(self.precision, other.precision)
        var h = decimo_mpfrw_init(_dps_to_bits(prec))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.__sub__()",
            )
        decimo_mpfrw_sub(h, self.handle, other.handle)
        return Self(_handle=h, _precision=prec)

    def __mul__(self, other: Self) raises -> Self:
        """Multiplies two MPF values.

        Args:
            other: The right-hand side operand.

        Returns:
            The product.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var prec = max(self.precision, other.precision)
        var h = decimo_mpfrw_init(_dps_to_bits(prec))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.__mul__()",
            )
        decimo_mpfrw_mul(h, self.handle, other.handle)
        return Self(_handle=h, _precision=prec)

    def __truediv__(self, other: Self) raises -> Self:
        """Divides two MPF values.

        Args:
            other: The right-hand side operand.

        Returns:
            The quotient.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var prec = max(self.precision, other.precision)
        var h = decimo_mpfrw_init(_dps_to_bits(prec))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.__truediv__()",
            )
        decimo_mpfrw_div(h, self.handle, other.handle)
        return Self(_handle=h, _precision=prec)

    def __pow__(self, exponent: Self) raises -> Self:
        """Raises this value to the given power.

        Args:
            exponent: The exponent to raise to.

        Returns:
            The result of `self` raised to `exponent`.

        Raises:
            Error: Propagated from `power()`.
        """
        return self.power(exponent)

    # ===------------------------------------------------------------------=== #
    # Transcendental and math methods
    # ===------------------------------------------------------------------=== #

    def sqrt(self) raises -> Self:
        """Computes the square root.

        Returns:
            The square root of this value.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var h = decimo_mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.sqrt()",
            )
        decimo_mpfrw_sqrt(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def exp(self) raises -> Self:
        """Computes the exponential function e^self.

        Returns:
            The exponential of this value.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var h = decimo_mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.exp()",
            )
        decimo_mpfrw_exp(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def ln(self) raises -> Self:
        """Computes the natural logarithm.

        Returns:
            The natural logarithm of this value.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var h = decimo_mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.ln()",
            )
        decimo_mpfrw_log(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def sin(self) raises -> Self:
        """Computes the sine.

        Returns:
            The sine of this value.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var h = decimo_mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.sin()",
            )
        decimo_mpfrw_sin(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def cos(self) raises -> Self:
        """Computes the cosine.

        Returns:
            The cosine of this value.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var h = decimo_mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.cos()",
            )
        decimo_mpfrw_cos(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def tan(self) raises -> Self:
        """Computes the tangent.

        Returns:
            The tangent of this value.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var h = decimo_mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.tan()",
            )
        decimo_mpfrw_tan(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def power(self, exponent: Self) raises -> Self:
        """Computes self raised to the given exponent.

        Args:
            exponent: The exponent to raise to.

        Returns:
            The result of `self` raised to `exponent`.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var prec = max(self.precision, exponent.precision)
        var h = decimo_mpfrw_init(_dps_to_bits(prec))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.power()",
            )
        decimo_mpfrw_pow(h, self.handle, exponent.handle)
        return Self(_handle=h, _precision=prec)

    def root(self, n: Int) raises -> Self:
        """Computes the n-th root.

        This is the spelling `BigDecimal.root` and `Decimal128.root` share.

        Args:
            n: The root degree (e.g. 2 for square root, 3 for cube root).

        Returns:
            The n-th root of this value.

        Raises:
            ValueError: If `n` is not positive, or is larger than `UInt32.MAX`.
            RuntimeError: If MPFR handle allocation fails.
        """
        if n <= 0:
            raise ValueError(
                message="Cannot compute non-positive root.",
                function="MPF.root()",
            )
        # The degree reaches MPFR as a `UInt32`. Without this bound a larger
        # `n` would wrap and quietly compute a different root.
        if n > Int(UInt32.MAX):
            raise ValueError(
                message="Root degree is too large.",
                function="MPF.root()",
            )
        return self.root(UInt32(n))

    def root(self, n: UInt32) raises -> Self:
        """Computes the n-th root.

        Args:
            n: The root degree (e.g. 2 for square root, 3 for cube root).

        Returns:
            The n-th root of this value.

        Raises:
            RuntimeError: If MPFR handle allocation fails.
        """
        var h = decimo_mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.root()",
            )
        decimo_mpfrw_rootn_ui(h, self.handle, n)
        return Self(_handle=h, _precision=self.precision)

    @staticmethod
    def pi(precision: Int = PRECISION) raises -> MPF:
        """Returns π to the specified number of decimal digits.

        Args:
            precision: The number of significant decimal digits.

        Returns:
            A `MPF` containing π at the requested precision.

        Raises:
            ValueError: If the precision is negative.
            RuntimeError: If MPFR is not available or handle allocation fails.
        """
        if precision < 0:
            raise ValueError(
                message="Precision must be non-negative",
                function="MPF.pi()",
            )
        if not decimo_mpfrw_available():
            raise RuntimeError(
                message=(
                    "MPF requires MPFR (brew install mpfr / apt"
                    " install libmpfr-dev)"
                ),
                function="MPF.pi()",
            )
        var h = decimo_mpfrw_init(_dps_to_bits(precision))
        if h < 0:
            raise RuntimeError(
                message="Handle allocation failed.",
                function="MPF.pi()",
            )
        decimo_mpfrw_const_pi(h)
        return MPF(_handle=h, _precision=precision)
