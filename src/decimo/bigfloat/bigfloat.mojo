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


"""An arbitrary-precision binary float, written in Mojo.

A value is `(-1)^sign * significand * 2^exponent`, with the significand an
integer holding exactly `precision` bits. The precision is a property of the
value, in bits, and every operation rounds once to the precision of its
destination -- the model MPFR uses, and what `docs/plans/api_roadmap.md`
calls decimo's MPFR layer.

Unlike the decimal types, this one carries infinities and a NaN. A binary
float is expected to have them, and the reference it is checked against has
them, so a comparison can be of values rather than of "ours raises here".
They are the usual transitive flags: an operation that meets one answers with
one.

The significand is a non-negative `BigInt` rather than a bare `Magnitude`.
That is a reuse decision, not a representation one: `BigInt` already carries
the base-2^64 word storage with its inline buffer and block pool, the shifts,
the bit access and the division that the arithmetic needs. The sign field it
brings along is one byte that this type does not read.
"""

from std.memory import bitcast

from decimo.bigfloat.rounding import round_to_precision
from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import test_bit, trailing_zeros
from decimo.errors import ValueError
from decimo.rounding_mode import RoundingMode

comptime PRECISION: Int = 53
"""Bits a `BigFloat` keeps when no precision is given.

Fifty-three is what an IEEE 754 double holds, so a value built without a
stated precision carries the same significand as the `Float64` it probably
came from and loses nothing on the way in.
"""

comptime _KIND_FINITE: UInt8 = 0
comptime _KIND_INFINITY: UInt8 = 1
comptime _KIND_NAN: UInt8 = 2


struct BigFloat(Absable, Copyable, Movable, Writable):
    """An arbitrary-precision binary floating-point number.

    The value is `(-1)^sign * significand * 2^exponent`. For a finite
    non-zero value the significand holds exactly `precision` bits with its
    top bit set, which makes the representation unique. Zero has a zero
    significand and keeps its sign, so `+0` and `-0` are different values
    that compare equal.

    Parameters are not used: the precision is a field, so one function can
    take floats of different precisions and a precision can be chosen at run
    time.
    """

    var significand: BigInt
    """The significand, never negative. Exactly `precision` bits when finite
    and non-zero."""
    var exponent: Int
    """The power of two the significand is scaled by."""
    var precision: Int
    """How many bits the significand holds. Always positive."""
    var sign: Bool
    """True for a negative value, including negative zero."""
    var kind: UInt8
    """Finite, an infinity, or a NaN."""

    # ===------------------------------------------------------------------=== #
    # Life cycle
    # ===------------------------------------------------------------------=== #

    def __init__(out self):
        """A positive zero at the default precision."""
        self.significand = BigInt.zero()
        self.exponent = 0
        self.precision = PRECISION
        self.sign = False
        self.kind = _KIND_FINITE

    def __init__(
        out self,
        *,
        significand: BigInt,
        exponent: Int,
        precision: Int,
        sign: Bool,
        kind: UInt8 = _KIND_FINITE,
    ) raises:
        """Builds a value from its parts, already normalized.

        Args:
            significand: The significand, which must not be negative.
            exponent: The power of two.
            precision: The number of bits. Must be positive.
            sign: Whether the value is negative.
            kind: Finite, infinite or NaN.

        Raises:
            ValueError: If `precision` is not positive, or the significand is
                negative.
        """
        if precision <= 0:
            raise ValueError(
                message="A precision must be at least one bit.",
                function="BigFloat()",
            )
        if significand.sign:
            raise ValueError(
                message="A significand cannot be negative.",
                function="BigFloat()",
            )
        self.significand = significand.copy()
        self.exponent = exponent
        self.precision = precision
        self.sign = sign
        self.kind = kind

    def __init__(out self, *, copy: Self):
        """A copy of another value.

        Args:
            copy: The value to copy.
        """
        self.significand = copy.significand.copy()
        self.exponent = copy.exponent
        self.precision = copy.precision
        self.sign = copy.sign
        self.kind = copy.kind

    def copy(self) -> Self:
        """An explicit copy.

        Returns:
            The copy.
        """
        return Self(copy=self)

    # ===------------------------------------------------------------------=== #
    # The three values that are not numbers
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def zero(precision: Int = PRECISION, sign: Bool = False) raises -> Self:
        """A signed zero.

        Args:
            precision: The number of bits the value carries.
            sign: Whether it is negative zero.

        Returns:
            The zero.

        Raises:
            ValueError: If `precision` is not positive.
        """
        return Self(
            significand=BigInt.zero(),
            exponent=0,
            precision=precision,
            sign=sign,
        )

    @staticmethod
    def infinity(precision: Int = PRECISION, sign: Bool = False) raises -> Self:
        """A signed infinity.

        Args:
            precision: The number of bits the value carries.
            sign: Whether it is negative infinity.

        Returns:
            The infinity.

        Raises:
            ValueError: If `precision` is not positive.
        """
        return Self(
            significand=BigInt.zero(),
            exponent=0,
            precision=precision,
            sign=sign,
            kind=_KIND_INFINITY,
        )

    @staticmethod
    def nan(precision: Int = PRECISION) raises -> Self:
        """The NaN.

        There is one, not two: no signalling NaN, which decimo has no signals
        to raise.

        Args:
            precision: The number of bits the value carries.

        Returns:
            The NaN.

        Raises:
            ValueError: If `precision` is not positive.
        """
        return Self(
            significand=BigInt.zero(),
            exponent=0,
            precision=precision,
            sign=False,
            kind=_KIND_NAN,
        )

    def is_nan(self) -> Bool:
        """Whether this value is the NaN.

        Returns:
            True for a NaN.
        """
        return self.kind == _KIND_NAN

    def is_infinite(self) -> Bool:
        """Whether this value is an infinity.

        Returns:
            True for either infinity.
        """
        return self.kind == _KIND_INFINITY

    def is_finite(self) -> Bool:
        """Whether this value is a finite number.

        Returns:
            True for anything that is neither infinite nor a NaN.
        """
        return self.kind == _KIND_FINITE

    def is_zero(self) -> Bool:
        """Whether this value is a zero of either sign.

        Returns:
            True for a zero.
        """
        return self.kind == _KIND_FINITE and self.significand.is_zero()

    # ===------------------------------------------------------------------=== #
    # Construction from other numbers
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def from_bigint(
        value: BigInt,
        precision: Int = PRECISION,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Builds the nearest float to an integer.

        Args:
            value: The integer.
            precision: The number of bits to keep.
            rounding_mode: How to round when the integer does not fit.

        Returns:
            The float, rounded once if the integer has more bits than asked
            for.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the rounding.
        """
        if value.is_zero():
            return Self.zero(precision)
        var magnitude = abs(value)
        var rounded = round_to_precision(
            magnitude, 0, precision, value.sign, rounding_mode
        )
        return Self(
            significand=rounded[0],
            exponent=rounded[1],
            precision=precision,
            sign=value.sign,
        )

    @staticmethod
    def from_int(
        value: Int,
        precision: Int = PRECISION,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Builds the nearest float to a native integer.

        Args:
            value: The integer.
            precision: The number of bits to keep.
            rounding_mode: How to round when the integer does not fit.

        Returns:
            The float.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the rounding.
        """
        return Self.from_bigint(BigInt(value), precision, rounding_mode)

    @staticmethod
    def from_float64(
        value: Float64,
        precision: Int = PRECISION,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Builds a float from a `Float64`, exactly where it fits.

        Args:
            value: The double.
            precision: The number of bits to keep. At 53 or more the
                conversion is exact, a double having no more than that.
            rounding_mode: How to round below 53 bits.

        Returns:
            The float, carrying the infinities and the NaN across.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the rounding.

        Notes:

        The bits are read rather than the decimal text: a double is a binary
        float already, so its significand and exponent are there to be taken
        and nothing has to be parsed or rounded on the way in.
        """
        var bits = bitcast[DType.uint64](value)
        var sign = (bits >> 63) != 0
        var biased = Int((bits >> 52) & 0x7FF)
        var fraction = bits & 0xF_FFFF_FFFF_FFFF

        if biased == 0x7FF:
            if fraction != 0:
                return Self.nan(precision)
            return Self.infinity(precision, sign)

        var magnitude: BigInt
        var exponent: Int
        if biased == 0:
            if fraction == 0:
                return Self.zero(precision, sign)
            # Subnormal: no implicit leading one, and the exponent is the
            # smallest a normal value has.
            magnitude = BigInt(UInt64(fraction))
            exponent = -1074
        else:
            magnitude = BigInt(UInt64(fraction | 0x10_0000_0000_0000))
            exponent = biased - 1075

        var rounded = round_to_precision(
            magnitude, exponent, precision, sign, rounding_mode
        )
        return Self(
            significand=rounded[0],
            exponent=rounded[1],
            precision=precision,
            sign=sign,
        )

    def to_float64(self) raises -> Float64:
        """The nearest `Float64` to this value.

        Returns:
            The double, with the infinities and the NaN carried across.

        Raises:
            Error: Propagated from the rounding.

        Notes:

        A value too large for a double becomes an infinity and one too small
        becomes a zero, which is what a double has to say about them.
        """
        if self.is_nan():
            return Float64(0) / Float64(0)
        if self.is_infinite():
            var infinity = Float64(1) / Float64(0)
            return -infinity if self.sign else infinity
        if self.is_zero():
            return Float64(-0.0) if self.sign else Float64(0.0)

        # The bits are built rather than the value scaled. `ldexp` and a
        # multiplication by `2 ** exponent` both fail at the ends: the power
        # underflows to zero below `2^-1074` and overflows above `2^1024`,
        # and either one then swallows the significand. Writing the fields
        # is the exact inverse of `from_float64()` and says what happens at
        # both ends instead of inheriting it.
        #
        # The value is `significand * 2^exponent` with the significand
        # holding `precision` bits, so its leading bit sits at
        # `precision - 1 + exponent`. That sum is formed only after the range
        # is checked, because an exponent near the ends of `Int` overflows it:
        # the comparison below subtracts instead, which cannot, and once it
        # holds the sum is bounded above by 1024.
        if self.exponent > 1024 - self.precision:
            var past = Float64(1) / Float64(0)
            return -past if self.sign else past

        var leading = self.precision - 1 + self.exponent
        if leading < -1080:
            # Below half the smallest subnormal by a wide margin, so the
            # answer is a zero whatever the bits are, and the subnormal path's
            # own arithmetic is kept away from an exponent that would
            # underflow it.
            return Float64(-0.0) if self.sign else Float64(0.0)
        var biased = leading + 1023
        var sign_bit = UInt64(1) << 63 if self.sign else UInt64(0)

        if biased > 2046:
            var overflow = Float64(1) / Float64(0)
            return -overflow if self.sign else overflow

        if biased >= 1:
            # Normal: fifty-three bits of significand, the top one implicit.
            var fitted = round_to_precision(
                self.significand,
                self.exponent,
                53,
                self.sign,
                RoundingMode.half_even(),
            )
            # The rounding can carry into a wider exponent, which moves the
            # leading bit and so the field as well.
            var fitted_leading = 52 + fitted[1]
            var fitted_biased = fitted_leading + 1023
            if fitted_biased > 2046:
                var overflow = Float64(1) / Float64(0)
                return -overflow if self.sign else overflow
            if fitted_biased < 1:
                # Rounding down out of the normal range; fall through to the
                # subnormal path with the original value.
                return self._to_subnormal_float64(sign_bit)
            var mantissa = fitted[0] - (BigInt.one() << 52)
            var bits = (
                sign_bit
                | (UInt64(fitted_biased) << 52)
                | UInt64(mantissa.to_int())
            )
            return bitcast[DType.float64](bits)

        return self._to_subnormal_float64(sign_bit)

    def _to_subnormal_float64(self, sign_bit: UInt64) raises -> Float64:
        """The nearest double below the normal range.

        Args:
            sign_bit: The sign in its place, so this does not re-derive it.

        Returns:
            The double, which may be a zero or the smallest normal if the
            rounding carries that far.

        Raises:
            Error: Propagated from the arithmetic.

        Notes:

        Every double below `2^-1022` is a multiple of `2^-1074`, so the
        answer is this value divided by that quantum and rounded to an
        integer, once. Rounding to 53 bits first and then to the quantum
        would round twice and can land a tick away from the nearest double.

        An integer of `2^52` or more means the rounding carried up into the
        normal range, and the IEEE encoding takes care of it: writing it into
        the low 53 bits leaves a biased exponent of one, which is `2^-1022`.
        """
        var shift = self.exponent + 1074
        var quantums: BigInt
        if shift >= 0:
            quantums = self.significand << shift
        else:
            var dropped = -shift
            quantums = self.significand >> dropped
            var leading_dropped = test_bit(self.significand, dropped - 1)
            var rest_below = False
            if dropped >= 2:
                rest_below = trailing_zeros(self.significand) < dropped - 1
            if leading_dropped and (rest_below or test_bit(quantums, 0)):
                quantums = quantums + BigInt.one()

        if quantums.is_zero():
            return bitcast[DType.float64](sign_bit)
        return bitcast[DType.float64](sign_bit | UInt64(quantums.to_int()))

    # ===------------------------------------------------------------------=== #
    # Sign
    # ===------------------------------------------------------------------=== #

    def __neg__(self) -> Self:
        """The value with its sign flipped.

        Returns:
            The negation. A NaN negates to itself, and a zero to the other
            zero.
        """
        var result = self.copy()
        if not result.is_nan():
            result.sign = not result.sign
        return result^

    def __abs__(self) -> Self:
        """The value without its sign.

        Returns:
            The magnitude.
        """
        var result = self.copy()
        result.sign = False
        return result^

    # ===------------------------------------------------------------------=== #
    # Text
    # ===------------------------------------------------------------------=== #

    def write_to[W: Writer](self, mut writer: W):
        """Writes the value as its parts.

        Parameters:
            W: The writer type.

        Args:
            writer: Where to write.

        Notes:

        This is the representation, not a decimal rendering: the decimal
        conversion is a separate piece of work and lands with the parsing it
        belongs to. What it prints is enough to see what a value is -- the
        significand, the power of two and the precision.
        """
        if self.is_nan():
            writer.write("NaN")
            return
        if self.is_infinite():
            writer.write("-Infinity" if self.sign else "Infinity")
            return
        if self.sign:
            writer.write("-")
        writer.write(self.significand)
        writer.write("p")
        writer.write(self.exponent)
        writer.write("@")
        writer.write(self.precision)
