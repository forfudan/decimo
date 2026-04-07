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

"""Implements the BigFloat type: arbitrary-precision binary floating-point.

BigFloat wraps a single MPFR handle via a C wrapper. Every arithmetic and
transcendental operation is a single MPFR call. Requires MPFR at runtime.

Usage:
    from decimo.bigfloat.bigfloat import BigFloat

    var x = BigFloat("3.14159", precision=1000)
    var r = x.sqrt()
    var bd = r.to_bigdecimal(1000)

Design:
    - Single field: `handle: Int32` (index into C wrapper's mpfr_t handle pool)
    - Precision specified in decimal digits, converted to bits internally
    - Guard bits (64 extra) ensure requested decimal digits are correct
    - RAII: destructor frees MPFR handle via `mpfrw_clear`
"""

from std.ffi import external_call, c_char

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigfloat.mpfr_wrapper import (
    mpfrw_available,
    mpfrw_init,
    mpfrw_clear,
    mpfrw_set_str,
    mpfrw_get_str,
    mpfrw_free_str,
    mpfrw_add,
    mpfrw_sub,
    mpfrw_mul,
    mpfrw_div,
    mpfrw_neg,
    mpfrw_abs,
    mpfrw_cmp,
    mpfrw_sqrt,
    mpfrw_exp,
    mpfrw_log,
    mpfrw_sin,
    mpfrw_cos,
    mpfrw_tan,
    mpfrw_pow,
    mpfrw_rootn_ui,
    mpfrw_const_pi,
)

# Guard bits added to user-requested precision to absorb binary↔decimal rounding.
comptime _GUARD_BITS: Int = 64

# Approximate bits per decimal digit: ceil(log2(10)) ≈ 3.322.
# Use 4 for safety.
comptime _BITS_PER_DIGIT: Int = 4

# Default precision in decimal digits, same as BigDecimal.
"""Default precision in decimal digits for BigFloat."""
comptime PRECISION: Int = 28

# Short alias, like BDec for BigDecimal.
"""Alias for `BigFloat`."""
comptime BFlt = BigFloat
# Short alias, like Decimal for BigDecimal.
# Mojo's built-in floating-point types are all with number suffixes
# (e.g., `Float32`, `Float64`), so `Float` is available for BigFloat.
"""Alias for `BigFloat`."""
comptime Float = BigFloat


fn _dps_to_bits(precision: Int) -> Int:
    """Converts decimal digit precision to MPFR bit precision with guard bits.
    """
    return precision * _BITS_PER_DIGIT + _GUARD_BITS


fn _read_c_string(address: Int) -> String:
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
    return String(unsafe_from_utf8=buf^)


# ===----------------------------------------------------------------------=== #
# BigFloat
# ===----------------------------------------------------------------------=== #


struct BigFloat(Comparable, Movable, Writable):
    """Arbitrary-precision binary floating-point type backed by MPFR.

    Each BigFloat owns a single MPFR handle (index into the C wrapper's pool).
    Precision is specified in decimal digits and converted to bits internally.
    Arithmetic and transcendental operations are single MPFR calls.

    BigFloat is Movable but not Copyable. Transfer ownership with `^`:

        var a = BigFloat("2.0", 100)
        var b = a^  # moves a into b; a is consumed
    """

    var handle: Int32
    var precision: Int

    # ===------------------------------------------------------------------=== #
    # Constructors
    # ===------------------------------------------------------------------=== #

    def __init__(out self, value: String, precision: Int = PRECISION) raises:
        """Creates a BigFloat from a decimal string.

        Args:
            value: A decimal number string (e.g. "3.14159", "-1.5e10").
            precision: Number of significant decimal digits.
        """
        if not mpfrw_available():
            raise Error(
                "BigFloat requires MPFR"
                " (brew install mpfr / apt install libmpfr-dev)"
            )
        var bits = _dps_to_bits(precision)
        self.handle = mpfrw_init(bits)
        if self.handle < 0:
            raise Error("BigFloat: MPFR handle pool exhausted")
        self.precision = precision
        var s_bytes = value.as_bytes()
        var result_code = mpfrw_set_str(
            self.handle,
            s_bytes.unsafe_ptr().bitcast[c_char](),
            Int32(len(value)),
        )
        if result_code != 0:
            mpfrw_clear(self.handle)
            raise Error("BigFloat: invalid number string: " + value)

    def __init__(out self, value: Int, precision: Int = PRECISION) raises:
        """Creates a BigFloat from an integer."""
        self = Self(String(value), precision)

    def __init__(out self, bd: BigDecimal, precision: Int = PRECISION) raises:
        """Creates a BigFloat from a BigDecimal."""
        self = Self(bd.to_string(), precision)

    def __init__(out self, *, _handle: Int32, _precision: Int):
        """Internal: wraps an existing MPFR handle. Caller transfers ownership.
        """
        self.handle = _handle
        self.precision = _precision

    # ===------------------------------------------------------------------=== #
    # Lifecycle
    # ===------------------------------------------------------------------=== #

    def __init__(out self, *, deinit take: Self):
        """Moves a BigFloat, transferring handle ownership."""
        self.handle = take.handle
        self.precision = take.precision

    fn __del__(deinit self):
        """Frees the MPFR handle."""
        if self.handle >= 0:
            mpfrw_clear(self.handle)

    # ===------------------------------------------------------------------=== #
    # String conversion
    # ===------------------------------------------------------------------=== #

    def to_string(self, digits: Int = -1) raises -> String:
        """Exports the value as a decimal string.

        Args:
            digits: Number of significant digits. Defaults to the BigFloat's
                precision.

        Returns:
            A decimal string representation.
        """
        var d = digits if digits > 0 else self.precision
        var address = mpfrw_get_str(self.handle, Int32(d))
        if address == 0:
            raise Error("BigFloat: failed to export string")
        var result = _read_c_string(address)
        mpfrw_free_str(address)
        return result

    def write_to[W: Writer](self, mut writer: W):
        """Writes the decimal string representation to a Writer."""
        if self.handle < 0:
            writer.write("BigFloat(<moved>)")
            return
        var address = mpfrw_get_str(self.handle, Int32(self.precision))
        if address == 0:
            writer.write("BigFloat(<error>)")
            return
        var s = _read_c_string(address)
        mpfrw_free_str(address)
        writer.write(s)

    def write_repr_to[W: Writer](self, mut writer: W):
        """Writes a repr-style string to a Writer."""
        if self.handle < 0:
            writer.write('BigFloat("<moved>")')
            return
        var address = mpfrw_get_str(self.handle, Int32(self.precision))
        if address == 0:
            writer.write('BigFloat("<error>")')
            return
        var s = _read_c_string(address)
        mpfrw_free_str(address)
        writer.write('BigFloat("', s, '")')

    # ===------------------------------------------------------------------=== #
    # Conversion
    # ===------------------------------------------------------------------=== #

    def to_bigdecimal(self, precision: Int = -1) raises -> BigDecimal:
        """Converts this BigFloat to a BigDecimal.

        Args:
            precision: Number of significant decimal digits for the conversion.
                Defaults to the BigFloat's own precision.

        Returns:
            A BigDecimal with the requested number of significant digits.
        """
        var d = precision if precision > 0 else self.precision
        return BigDecimal(self.to_string(d))

    # ===------------------------------------------------------------------=== #
    # Comparison
    # ===------------------------------------------------------------------=== #

    def __eq__(self, other: Self) -> Bool:
        """Returns True if self == other."""
        return mpfrw_cmp(self.handle, other.handle) == 0

    def __ne__(self, other: Self) -> Bool:
        """Returns True if self != other."""
        return mpfrw_cmp(self.handle, other.handle) != 0

    def __lt__(self, other: Self) -> Bool:
        """Returns True if self < other."""
        var c = mpfrw_cmp(self.handle, other.handle)
        return c != -2 and c < 0

    def __le__(self, other: Self) -> Bool:
        """Returns True if self <= other."""
        var c = mpfrw_cmp(self.handle, other.handle)
        return c != -2 and c <= 0

    def __gt__(self, other: Self) -> Bool:
        """Returns True if self > other."""
        var c = mpfrw_cmp(self.handle, other.handle)
        return c != -2 and c > 0

    def __ge__(self, other: Self) -> Bool:
        """Returns True if self >= other."""
        var c = mpfrw_cmp(self.handle, other.handle)
        return c != -2 and c >= 0

    # ===------------------------------------------------------------------=== #
    # Unary operators
    # ===------------------------------------------------------------------=== #

    def __neg__(self) raises -> Self:
        """Returns -self."""
        var h = mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_neg(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def __abs__(self) raises -> Self:
        """Returns |self|."""
        var h = mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_abs(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    # ===------------------------------------------------------------------=== #
    # Binary arithmetic operators
    # ===------------------------------------------------------------------=== #

    def __add__(self, other: Self) raises -> Self:
        """Returns self + other."""
        var prec = max(self.precision, other.precision)
        var h = mpfrw_init(_dps_to_bits(prec))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_add(h, self.handle, other.handle)
        return Self(_handle=h, _precision=prec)

    def __sub__(self, other: Self) raises -> Self:
        """Returns self - other."""
        var prec = max(self.precision, other.precision)
        var h = mpfrw_init(_dps_to_bits(prec))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_sub(h, self.handle, other.handle)
        return Self(_handle=h, _precision=prec)

    def __mul__(self, other: Self) raises -> Self:
        """Returns self * other."""
        var prec = max(self.precision, other.precision)
        var h = mpfrw_init(_dps_to_bits(prec))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_mul(h, self.handle, other.handle)
        return Self(_handle=h, _precision=prec)

    def __truediv__(self, other: Self) raises -> Self:
        """Returns self / other."""
        var prec = max(self.precision, other.precision)
        var h = mpfrw_init(_dps_to_bits(prec))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_div(h, self.handle, other.handle)
        return Self(_handle=h, _precision=prec)

    def __pow__(self, exponent: Self) raises -> Self:
        """Returns self ** exponent."""
        return self.power(exponent)

    # ===------------------------------------------------------------------=== #
    # Transcendental and math methods
    # ===------------------------------------------------------------------=== #

    def sqrt(self) raises -> Self:
        """Computes the square root."""
        var h = mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_sqrt(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def exp(self) raises -> Self:
        """Computes e^self."""
        var h = mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_exp(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def ln(self) raises -> Self:
        """Computes the natural logarithm."""
        var h = mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_log(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def sin(self) raises -> Self:
        """Computes the sine."""
        var h = mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_sin(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def cos(self) raises -> Self:
        """Computes the cosine."""
        var h = mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_cos(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def tan(self) raises -> Self:
        """Computes the tangent."""
        var h = mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_tan(h, self.handle)
        return Self(_handle=h, _precision=self.precision)

    def power(self, exponent: Self) raises -> Self:
        """Computes self raised to the given exponent."""
        var prec = max(self.precision, exponent.precision)
        var h = mpfrw_init(_dps_to_bits(prec))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_pow(h, self.handle, exponent.handle)
        return Self(_handle=h, _precision=prec)

    def root(self, n: UInt32) raises -> Self:
        """Computes the n-th root."""
        var h = mpfrw_init(_dps_to_bits(self.precision))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_rootn_ui(h, self.handle, n)
        return Self(_handle=h, _precision=self.precision)

    @staticmethod
    def pi(precision: Int = PRECISION) raises -> BigFloat:
        """Returns π to the specified number of decimal digits."""
        if not mpfrw_available():
            raise Error(
                "BigFloat requires MPFR"
                " (brew install mpfr / apt install libmpfr-dev)"
            )
        var h = mpfrw_init(_dps_to_bits(precision))
        if h < 0:
            raise Error("BigFloat: handle allocation failed")
        mpfrw_const_pi(h)
        return BigFloat(_handle=h, _precision=precision)
