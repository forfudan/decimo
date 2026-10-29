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


"""An arbitrary-precision binary float.

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

from std.hash.hasher import Hasher
from std.memory import bitcast

from decimo.bigdecimal.bigdecimal import BigDecimal
import decimo.bigfloat.arithmetics as bigfloat_arithmetics
import decimo.bigfloat.comparison as bigfloat_comparison
from decimo.bigfloat.conversion import (
    from_decimal_parts,
    to_exact_bigdecimal,
    to_rounded_bigdecimal,
)
import decimo.bigfloat.exponential as bigfloat_exponential
import decimo.bigfloat.hyperbolic as bigfloat_hyperbolic
import decimo.bigfloat.ieee as bigfloat_ieee
import decimo.bigfloat.power as bigfloat_power
from decimo.bigfloat.rounding import (
    checked_precision,
    round_to_precision,
)
import decimo.bigfloat.trigonometric as bigfloat_trigonometric
from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import test_bit, trailing_zeros
from decimo.errors import ValueError
from decimo.rounding_mode import RoundingMode
from decimo.traits import Numeric, Parsable, Rootable

comptime PRECISION: Int = 53
"""Bits a `BigFloat` keeps when no precision is given.

Fifty-three is what an IEEE 754 double holds, so a value built without a
stated precision carries the same significand as the `Float64` it probably
came from and loses nothing on the way in.
"""

comptime _KIND_FINITE: UInt8 = 0
comptime _KIND_INFINITY: UInt8 = 1
comptime _KIND_NAN: UInt8 = 2


struct BigFloat(
    Absable,
    Comparable,
    Copyable,
    Hashable,
    Movable,
    Numeric,
    Parsable,
    Rootable,
    Writable,
):
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
            ValueError: If `precision` is not positive, if the significand is
                negative, or if a finite non-zero significand does not hold
                exactly `precision` bits.

        Notes:

        The bit count is checked rather than assumed, because everything
        downstream reads the leading bit's position as
        `exponent + precision - 1` and never asks the significand how many
        bits it really has. A value built with the two disagreeing compares
        and rounds as though it were a different number, which is a quiet
        wrong answer rather than a loud one. `from_rounded_parts()` is the
        way in for parts that are not normalized yet.
        """
        _ = checked_precision(precision, "BigFloat()")
        if significand.sign:
            raise ValueError(
                message="A significand cannot be negative.",
                function="BigFloat()",
            )
        if (
            kind == _KIND_FINITE
            and not significand.is_zero()
            and significand.bit_length() != precision
        ):
            raise ValueError(
                message=(
                    "A finite non-zero significand must hold exactly"
                    " `precision` bits with its top bit set. Pass the parts"
                    " through `from_rounded_parts()` to normalize them."
                ),
                function="BigFloat()",
            )
        self.significand = significand.copy()
        self.exponent = exponent
        self.precision = precision
        self.sign = sign
        self.kind = kind

    @implicit
    def __init__(out self, value: Int) raises:
        """Builds the float equal to an integer, exactly.

        Args:
            value: The integer.

        Raises:
            Error: Propagated from the conversion, which does not round.

        Notes:

        The precision is the default 53 bits, or the integer's own count of
        significant bits when that is more, so no `Int` is rounded on the way
        in. This is the conversion behind `1 + x` and `x * 3`, and an operand
        rounded before the operator ran would make the answer round twice.
        """
        var integer = BigInt(value)
        var precision = PRECISION
        if value != 0:
            var bits = integer.bit_length() - trailing_zeros(integer)
            if bits > precision:
                precision = bits
        self = Self.from_bigint(integer, precision)

    def __init__(
        out self,
        value: Int,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises:
        """Builds the nearest float to an integer at a given precision.

        Args:
            value: The integer.
            precision: The number of bits to keep.
            rounding_mode: How to round when the integer does not fit.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the rounding.
        """
        self = Self.from_int(value, precision, rounding_mode)

    @implicit
    def __init__(out self, value: Float64) raises:
        """Builds the float equal to a `Float64`, exactly, at 53 bits.

        Args:
            value: The double. Its infinities and NaN carry across.

        Raises:
            Error: Propagated from the conversion, which does not round.
        """
        self = Self.from_float64(value)

    def __init__(
        out self,
        value: Float64,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises:
        """Builds the nearest float to a `Float64` at a given precision.

        Args:
            value: The double.
            precision: The number of bits to keep. At 53 or more the
                conversion is exact.
            rounding_mode: How to round below 53 bits.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the rounding.
        """
        self = Self.from_float64(value, precision, rounding_mode)

    def __init__(out self, value: StringSlice) raises:
        """Parses decimal text at the default precision.

        Args:
            value: The text, such as `"1.5"`, `"-2.5e-3"`, `"inf"` or `"nan"`.

        Raises:
            ValueError: If the text is not a number.
        """
        self = Self.from_string(value)

    def __init__(
        out self,
        value: StringSlice,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises:
        """Parses decimal text, rounded once to a given precision.

        Args:
            value: The text.
            precision: The number of bits to keep.
            rounding_mode: How to round the digits.

        Raises:
            ValueError: If the text is not a number or `precision` is not
                positive.
        """
        self = Self.from_string(value, precision, rounding_mode)

    def __init__(out self, *, copy: Self):
        """Initialize the big float from a copy of another value.

        Args:
            copy: The value to copy.
        """
        self.significand = copy.significand.copy()
        self.exponent = copy.exponent
        self.precision = copy.precision
        self.sign = copy.sign
        self.kind = copy.kind

    def copy(self) -> Self:
        """Make an explicit copy of the value.

        Returns:
            The copy.
        """
        return Self(copy=self)

    # ===------------------------------------------------------------------=== #
    # The three values that are not numbers
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def zero() -> Self:
        """Constructs a positive zero at the default precision.

        Returns:
            The zero. This is the form `Numeric` asks for, which cannot
            raise; `zero(precision, sign)` is the one that chooses.
        """
        return Self()

    @staticmethod
    def zero(precision: Int, sign: Bool = False) raises -> Self:
        """Constructs a signed zero.

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
    def one() -> Self:
        """Constructs one at the default precision.

        Returns:
            The one. This is the form `Numeric` asks for, which cannot raise;
            `one(precision)` is the one that chooses.
        """
        var result = Self()
        result.significand = BigInt(UInt64(1) << UInt64(PRECISION - 1))
        result.exponent = 1 - PRECISION
        return result^

    @staticmethod
    def one(precision: Int) raises -> Self:
        """Constructs one at a given precision.

        Args:
            precision: The number of bits the value carries.

        Returns:
            The one.

        Raises:
            ValueError: If `precision` is not positive.
        """
        return Self.from_int(1, precision)

    @staticmethod
    def infinity(precision: Int = PRECISION, sign: Bool = False) raises -> Self:
        """Constructs a signed infinity.

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
        """Constructs the NaN.

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

        A normal double is 53 bits, so a 53-bit value is read off rather than
        rounded and the answer is exact. A subnormal double has fewer bits
        than that, so a value already rounded to a precision is rounded a
        second time on the way in, and two roundings can land one step from
        what rounding the original exactly would give. Converting from a
        wider precision removes it, since then only this rounding decides.
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
    # Arithmetic
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def power_of_two(exponent: Int) raises -> Self:
        """`2^exponent`, held in a single bit.

        Args:
            exponent: The power.

        Returns:
            The value, whose significand is one bit, so multiplying or
            dividing by it is exact at every precision.

        Raises:
            Error: Propagated from the construction.

        Notes:

        Scaling by a power of two is the one operation a binary float does
        for nothing, and several of the functions lean on that: an argument
        reduction, a halving, a doubling back. Having it here rather than
        once per module is what keeps those from each having their own.
        """
        return Self(
            significand=BigInt.one(),
            exponent=exponent,
            precision=1,
            sign=False,
        )

    @staticmethod
    def from_rounded_parts(
        magnitude: BigInt,
        exponent: Int,
        precision: Int,
        negative: Bool,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
        inexact_below: Bool = False,
    ) raises -> Self:
        """Rounds a magnitude and an exponent into a value.

        Args:
            magnitude: The significand, which must not be negative and need
                not be normalized.
            exponent: The power of two it is scaled by.
            precision: How many bits the result keeps.
            negative: The sign of the result.
            rounding_mode: Which way to round.
            inexact_below: Whether something non-zero sits below the
                magnitude, as a division's remainder does.

        Returns:
            The value, normalized to `precision` bits.

        Raises:
            Error: Propagated from the rounding.

        Notes:

        This is how every operation finishes. Each one computes a magnitude
        with more bits than it keeps, says whether anything was left under
        them, and hands both here, so that the rounding happens once and in
        one place rather than once per operation.
        """
        var fitted = round_to_precision(
            magnitude,
            exponent,
            precision,
            negative,
            rounding_mode,
            inexact_below,
        )
        return Self(
            significand=fitted[0],
            exponent=fitted[1],
            precision=precision,
            sign=negative,
        )

    def __add__(self, other: Self) raises -> Self:
        """The sum, correctly rounded.

        Args:
            other: The value to add.

        Returns:
            The sum at the wider of the two precisions, rounded half to even.
            Those two choices are what an operator has to assume; `add()`
            takes both as arguments.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_arithmetics.add(
            self,
            other,
            self.precision if self.precision
            > other.precision else (other.precision),
        )

    def __sub__(self, other: Self) raises -> Self:
        """The difference, correctly rounded.

        Args:
            other: The value to take away.

        Returns:
            The difference at the wider of the two precisions, rounded half
            to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_arithmetics.subtract(
            self,
            other,
            self.precision if self.precision
            > other.precision else (other.precision),
        )

    def __mul__(self, other: Self) raises -> Self:
        """The product, correctly rounded.

        Args:
            other: The value to multiply by.

        Returns:
            The product at the wider of the two precisions, rounded half to
            even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_arithmetics.multiply(
            self,
            other,
            self.precision if self.precision
            > other.precision else (other.precision),
        )

    def sqrt(self) raises -> Self:
        """The square root, correctly rounded.

        Returns:
            The root at this value's own precision, rounded half to even. A
            negative value gives a NaN rather than raising, which is what
            `Rootable` allows and what `MPF` does.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.sqrt(self, self.precision)

    def sqrt(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the square root, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `exponential.sqrt()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.sqrt(self, precision, rounding_mode)

    def root(self, degree: Int) raises -> Self:
        """The `degree`-th root, correctly rounded.

        Args:
            degree: Which root to take. Must be positive.

        Returns:
            The root at this value's own precision, rounded half to even. An
            exact root is exact, so `BFlt(8).root(3)` is two. A negative
            value has a real root only at an odd degree and gives a NaN at an
            even one, which is what `sqrt` does.

        Raises:
            ValueError: If `degree` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.root(self, degree, self.precision)

    def root(
        self,
        degree: Int,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """The `degree`-th root, correctly rounded.

        Args:
            degree: Which root to take. Must be positive.
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `exponential.root()` returns for the same arguments.

        Raises:
            ValueError: If `degree` or `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.root(self, degree, precision, rounding_mode)

    def cbrt(self) raises -> Self:
        """Returns the cube root, correctly rounded.

        Returns:
            The root at this value's own precision, rounded half to even. A
            negative value has one, unlike a square root, because an odd
            power keeps its sign.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.cbrt(self, self.precision)

    def cbrt(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the cube root, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `exponential.cbrt()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.cbrt(self, precision, rounding_mode)

    @deprecated(
        "pass the other leg by keyword, as `x.hypot(other=y)`; the positional"
        " form will be removed in decimo v0.18.0"
    )
    def hypot(self, other: Self, /) raises -> Self:
        """Deprecated spelling of `hypot(other=...)`.

        A positional `Int` here was easy to mistake for a precision, which
        it is in `ln(p)` and the other one-argument methods.

        Args:
            other: The other leg.

        Returns:
            What `hypot(other=other)` returns.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return self.hypot(other=other)

    def hypot(self, *, other: Self) raises -> Self:
        """Returns the hypotenuse of this value and another, correctly rounded.

        Args:
            other: The other leg.

        Returns:
            The hypotenuse at the wider of the two precisions, rounded half
            to even. The sum of the squares is formed exactly, so an answer
            that is exact is exact: `BFlt(3).hypot(other=BFlt(4))` is five.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.hypot(
            self,
            other,
            self.precision if self.precision
            > other.precision else (other.precision),
        )

    def hypot(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
        *,
        other: Self,
    ) raises -> Self:
        """Returns the hypotenuse of this value and another, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.
            other: The other leg.

        Returns:
            What `exponential.hypot()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.hypot(self, other, precision, rounding_mode)

    @deprecated(
        "pass the first coordinate by keyword, as `x.arctan2(other=y)`; the"
        " positional form will be removed in decimo v0.18.0"
    )
    def arctan2(self, other: Self, /) raises -> Self:
        """Deprecated spelling of `arctan2(other=...)`.

        A positional `Int` here was easy to mistake for a precision, which
        it is in `ln(p)` and the other one-argument methods.

        Args:
            other: The first coordinate.

        Returns:
            What `arctan2(other=other)` returns.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return self.arctan2(other=other)

    def arctan2(self, *, other: Self) raises -> Self:
        """Returns the angle of the point whose coordinates are `other` and `self`.

        Args:
            other: The first coordinate, the one along the axis.

        Returns:
            The angle in `(-pi, pi]` at the wider of the two precisions,
            rounded half to even. The receiver is the second coordinate, so
            that `y.arctan2(other=x)` reads in the order the function is named for.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.arctan2(
            self,
            other,
            self.precision if self.precision
            > other.precision else (other.precision),
        )

    def arctan2(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
        *,
        other: Self,
    ) raises -> Self:
        """Returns the angle of the point whose coordinates are `other` and `self`.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.
            other: The first coordinate, the one along the axis.

        Returns:
            What `trigonometric.arctan2()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.arctan2(
            self, other, precision, rounding_mode
        )

    # ===------------------------------------------------------------------=== #
    # The circular and the hyperbolic functions
    # ===------------------------------------------------------------------=== #

    def sin(self) raises -> Self:
        """Returns the sine of this value, in radians, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.sin(self, self.precision)

    def sin(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the sine of this value, in radians, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `trigonometric.sin()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.sin(self, precision, rounding_mode)

    def cos(self) raises -> Self:
        """Returns the cosine of this value, in radians, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.cos(self, self.precision)

    def cos(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the cosine of this value, in radians, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `trigonometric.cos()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.cos(self, precision, rounding_mode)

    def tan(self) raises -> Self:
        """Returns the tangent of this value, in radians, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.tan(self, self.precision)

    def tan(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the tangent of this value, in radians, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `trigonometric.tan()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.tan(self, precision, rounding_mode)

    def cot(self) raises -> Self:
        """Returns the cotangent of this value, in radians, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.cot(self, self.precision)

    def cot(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the cotangent of this value, in radians, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `trigonometric.cot()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.cot(self, precision, rounding_mode)

    def csc(self) raises -> Self:
        """Returns the cosecant of this value, in radians, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.csc(self, self.precision)

    def csc(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the cosecant of this value, in radians, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `trigonometric.csc()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.csc(self, precision, rounding_mode)

    def sec(self) raises -> Self:
        """Returns the secant of this value, in radians, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.sec(self, self.precision)

    def sec(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the secant of this value, in radians, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `trigonometric.sec()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.sec(self, precision, rounding_mode)

    def arcsin(self) raises -> Self:
        """Returns the inverse sine of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.arcsin(self, self.precision)

    def arcsin(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the inverse sine of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `trigonometric.arcsin()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.arcsin(self, precision, rounding_mode)

    def arccos(self) raises -> Self:
        """Returns the inverse cosine of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.arccos(self, self.precision)

    def arccos(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the inverse cosine of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `trigonometric.arccos()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.arccos(self, precision, rounding_mode)

    def arctan(self) raises -> Self:
        """Returns the inverse tangent of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.arctan(self, self.precision)

    def arctan(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the inverse tangent of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `trigonometric.arctan()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_trigonometric.arctan(self, precision, rounding_mode)

    def sinh(self) raises -> Self:
        """Returns the hyperbolic sine of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.sinh(self, self.precision)

    def sinh(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the hyperbolic sine of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `hyperbolic.sinh()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.sinh(self, precision, rounding_mode)

    def cosh(self) raises -> Self:
        """Returns the hyperbolic cosine of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.cosh(self, self.precision)

    def cosh(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the hyperbolic cosine of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `hyperbolic.cosh()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.cosh(self, precision, rounding_mode)

    def tanh(self) raises -> Self:
        """Returns the hyperbolic tangent of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.tanh(self, self.precision)

    def tanh(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the hyperbolic tangent of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `hyperbolic.tanh()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.tanh(self, precision, rounding_mode)

    def arcsinh(self) raises -> Self:
        """Returns the inverse hyperbolic sine of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.arcsinh(self, self.precision)

    def arcsinh(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the inverse hyperbolic sine of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `hyperbolic.arcsinh()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.arcsinh(self, precision, rounding_mode)

    def arccosh(self) raises -> Self:
        """Returns the inverse hyperbolic cosine of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.arccosh(self, self.precision)

    def arccosh(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the inverse hyperbolic cosine of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `hyperbolic.arccosh()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.arccosh(self, precision, rounding_mode)

    def arctanh(self) raises -> Self:
        """Returns the inverse hyperbolic tangent of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.arctanh(self, self.precision)

    def arctanh(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the inverse hyperbolic tangent of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `hyperbolic.arctanh()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_hyperbolic.arctanh(self, precision, rounding_mode)

    # ===------------------------------------------------------------------=== #
    # The exponentials and the logarithms
    # ===------------------------------------------------------------------=== #
    #
    # Each of these comes in two forms. Without arguments it is the free
    # function in `decimo.bigfloat.exponential` asked for this value's own
    # precision and for the default rounding. With a precision, and optionally
    # a rounding mode, it is the free function asked for those.

    def exp(self) raises -> Self:
        """Returns `e` to the power of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.exp(self, self.precision)

    def exp(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns `e` to the power of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `exponential.exp()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.exp(self, precision, rounding_mode)

    def exp2(self) raises -> Self:
        """Returns two to the power of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even. A
            whole exponent gives an exact answer.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.exp2(self, self.precision)

    def exp2(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns two to the power of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `exponential.exp2()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.exp2(self, precision, rounding_mode)

    def exp10(self) raises -> Self:
        """Returns ten to the power of this value, correctly rounded.

        Returns:
            The value at this value's own precision, rounded half to even. A
            whole exponent at nought or above gives an exact answer.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.exp10(self, self.precision)

    def exp10(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns ten to the power of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `exponential.exp10()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.exp10(self, precision, rounding_mode)

    def expm1(self) raises -> Self:
        """Returns `exp(x) - 1`, correctly rounded, without the cancellation.

        Returns:
            The value at this value's own precision, rounded half to even.
            This keeps every bit of a small argument, where `exp(x) - 1`
            computed as it reads keeps none.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.expm1(self, self.precision)

    def expm1(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns `exp(x) - 1`, correctly rounded, without the cancellation.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `exponential.expm1()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.expm1(self, precision, rounding_mode)

    def ln(self) raises -> Self:
        """Returns the natural logarithm of this value, correctly rounded.

        Returns:
            The logarithm at this value's own precision, rounded half to even.
            A negative value gives a NaN and a zero a negative infinity,
            rather than raising.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.ln(self, self.precision)

    def ln(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the natural logarithm of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `exponential.ln()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.ln(self, precision, rounding_mode)

    def log2(self) raises -> Self:
        """Returns the base-two logarithm of this value, correctly rounded.

        Returns:
            The logarithm at this value's own precision, rounded half to even.
            A power of two gives an exact answer.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.log2(self, self.precision)

    def log2(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the base-two logarithm of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `exponential.log2()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.log2(self, precision, rounding_mode)

    def log10(self) raises -> Self:
        """Returns the base-ten logarithm of this value, correctly rounded.

        Returns:
            The logarithm at this value's own precision, rounded half to even.
            A power of ten gives an exact answer.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.log10(self, self.precision)

    def log10(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns the base-ten logarithm of this value, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `exponential.log10()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.log10(self, precision, rounding_mode)

    @deprecated(
        "pass the base by keyword, as `x.log(base=y)`; the positional"
        " form will be removed in decimo v0.18.0"
    )
    def log(self, base: Self, /) raises -> Self:
        """Deprecated spelling of `log(base=...)`.

        A positional `Int` here was easy to mistake for a precision, which
        it is in `ln(p)` and the other one-argument methods.

        Args:
            base: The base.

        Returns:
            What `log(base=base)` returns.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return self.log(base=base)

    def log(self, *, base: Self) raises -> Self:
        """Returns the logarithm of this value in an arbitrary base, correctly rounded.

        Args:
            base: The base, which must be finite, positive and not one.

        Returns:
            The logarithm at the wider of the two precisions, rounded half to
            even. An exactly representable answer is exact. A base that is
            not a base gives a NaN rather than raising.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.log(
            self,
            base,
            self.precision if self.precision
            > base.precision else (base.precision),
        )

    def log(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
        *,
        base: Self,
    ) raises -> Self:
        """Returns the logarithm of this value in an arbitrary base, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.
            base: The base, which must be finite, positive and not one.

        Returns:
            What `exponential.log()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.log(self, base, precision, rounding_mode)

    def log1p(self) raises -> Self:
        """Returns `ln(1 + x)`, correctly rounded, without the cancellation.

        Returns:
            The logarithm at this value's own precision, rounded half to even.
            This keeps every bit of a small argument, where `ln(1 + x)`
            computed as it reads keeps none.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.log1p(self, self.precision)

    def log1p(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Returns `ln(1 + x)`, correctly rounded, without the cancellation.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.

        Returns:
            What `exponential.log1p()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_exponential.log1p(self, precision, rounding_mode)

    # ===------------------------------------------------------------------=== #
    # The power
    # ===------------------------------------------------------------------=== #

    @deprecated(
        "pass the exponent by keyword, as `x.power(exponent=y)`; the positional"
        " form will be removed in decimo v0.18.0"
    )
    def power(self, exponent: Self, /) raises -> Self:
        """Deprecated spelling of `power(exponent=...)`.

        A positional `Int` here was easy to mistake for a precision, which
        it is in `ln(p)` and the other one-argument methods.

        Args:
            exponent: The exponent.

        Returns:
            What `power(exponent=exponent)` returns.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return self.power(exponent=exponent)

    def power(self, *, exponent: Self) raises -> Self:
        """Returns this value raised to a power, correctly rounded.

        Args:
            exponent: The exponent.

        Returns:
            The power at the wider of the two precisions, rounded half to
            even. An exactly representable answer is exact, which is what
            makes `BFlt(2).power(exponent=BFlt(10))` a thousand and twenty-four and not
            a value near it.

        Raises:
            OverflowError: If the answer's exponent would not fit an `Int`.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_power.power(
            self,
            exponent,
            self.precision if self.precision
            > exponent.precision else (exponent.precision),
        )

    def power(
        self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
        *,
        exponent: Self,
    ) raises -> Self:
        """Returns this value raised to a power, correctly rounded.

        Args:
            precision: How many bits the result keeps. Must be positive.
            rounding_mode: Which way to round.
            exponent: The exponent.

        Returns:
            What `power.power()` returns for the same arguments.

        Raises:
            ValueError: If `precision` is not positive.
            OverflowError: If the answer's exponent would not fit an `Int`.
            Error: Propagated from the arithmetic.
        """
        return bigfloat_power.power(self, exponent, precision, rounding_mode)

    def __pow__(self, exponent: Self) raises -> Self:
        """Returns this value raised to a power, correctly rounded.

        Args:
            exponent: The exponent.

        Returns:
            What `power()` returns, which is where the reasoning is.

        Raises:
            OverflowError: If the answer's exponent would not fit an `Int`.
            Error: Propagated from the arithmetic.
        """
        return self.power(exponent=exponent)

    def __truediv__(self, other: Self) raises -> Self:
        """Returns the quotient, correctly rounded.

        Args:
            other: The value to divide by.

        Returns:
            The quotient at the wider of the two precisions, rounded half to
            even. Dividing by zero gives an infinity, as it does for any
            float.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return bigfloat_arithmetics.divide(
            self,
            other,
            self.precision if self.precision
            > other.precision else (other.precision),
        )

    # The reflected operators are what `1 + x` reaches: `Int` has no `__add__`
    # taking a `BigFloat`, so the left operand is converted through the
    # implicit constructor and handed to these. The in-place ones round as
    # the plain operators do, to the wider of the two precisions.

    def __radd__(self, other: Self) raises -> Self:
        """The sum with the value on the left, correctly rounded.

        Args:
            other: The left-hand operand.

        Returns:
            What `other + self` returns.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return other + self

    def __rsub__(self, other: Self) raises -> Self:
        """The difference with the value on the left, correctly rounded.

        Args:
            other: The left-hand operand.

        Returns:
            What `other - self` returns.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return other - self

    def __rmul__(self, other: Self) raises -> Self:
        """The product with the value on the left, correctly rounded.

        Args:
            other: The left-hand operand.

        Returns:
            What `other * self` returns.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return other * self

    def __rtruediv__(self, other: Self) raises -> Self:
        """The quotient with the value on the left, correctly rounded.

        Args:
            other: The dividend.

        Returns:
            What `other / self` returns.

        Raises:
            Error: Propagated from the arithmetic.
        """
        return other / self

    def __rpow__(self, base: Self) raises -> Self:
        """The base on the left raised to this value, correctly rounded.

        Args:
            base: The base.

        Returns:
            What `base ** self` returns.

        Raises:
            OverflowError: If the answer's exponent would not fit an `Int`.
            Error: Propagated from the arithmetic.
        """
        return base**self

    def __iadd__(mut self, other: Self) raises:
        """Adds in place, at the wider of the two precisions.

        Args:
            other: The value to add.

        Raises:
            Error: Propagated from the arithmetic.
        """
        self = self + other

    def __isub__(mut self, other: Self) raises:
        """Subtracts in place, at the wider of the two precisions.

        Args:
            other: The value to take away.

        Raises:
            Error: Propagated from the arithmetic.
        """
        self = self - other

    def __imul__(mut self, other: Self) raises:
        """Multiplies in place, at the wider of the two precisions.

        Args:
            other: The value to multiply by.

        Raises:
            Error: Propagated from the arithmetic.
        """
        self = self * other

    def __itruediv__(mut self, other: Self) raises:
        """Divides in place, at the wider of the two precisions.

        Args:
            other: The value to divide by.

        Raises:
            Error: Propagated from the arithmetic.
        """
        self = self / other

    def __ipow__(mut self, exponent: Self) raises:
        """Raises to a power in place, at the wider of the two precisions.

        Args:
            exponent: The exponent.

        Raises:
            OverflowError: If the answer's exponent would not fit an `Int`.
            Error: Propagated from the arithmetic.
        """
        self = self**exponent

    # ===------------------------------------------------------------------=== #
    # Comparison
    # ===------------------------------------------------------------------=== #
    #
    # A NaN is unordered, so `__eq__` is False and `__ne__` is True for it
    # while the four order operators are all False. That breaks the law a
    # `Comparable` would like -- that exactly one of `<`, `==` and `>` holds
    # -- and it is what IEEE 754 asks for, so a float says so rather than
    # inventing an answer. `comparison.compare_total()` is the one to sort by.

    def __eq__(self, other: Self) -> Bool:
        """Returns whether the two are the same number.

        Args:
            other: The value to compare against.

        Returns:
            True if they are equal. A NaN is equal to nothing, itself
            included, and the two zeros are equal to each other.

        """
        return bigfloat_comparison.equal(self, other)

    def __ne__(self, other: Self) -> Bool:
        """Returns whether the two are different numbers.

        Args:
            other: The value to compare against.

        Returns:
            True unless they are equal, which makes this the one comparison a
            NaN answers yes to.

        """
        return bigfloat_comparison.not_equal(self, other)

    def __lt__(self, other: Self) -> Bool:
        """Returns whether self is less than other.

        Args:
            other: The value to compare against.

        Returns:
            True if self is below other, and False if either is a NaN.

        """
        return bigfloat_comparison.less(self, other)

    def __le__(self, other: Self) -> Bool:
        """Returns whether self is less than or equal to other.

        Args:
            other: The value to compare against.

        Returns:
            True if self is below or level with other, and False if either is
            a NaN.

        """
        return bigfloat_comparison.less_equal(self, other)

    def __gt__(self, other: Self) -> Bool:
        """Returns whether self is greater than other.

        Args:
            other: The value to compare against.

        Returns:
            True if self is above other, and False if either is a NaN.

        """
        return bigfloat_comparison.greater(self, other)

    def __ge__(self, other: Self) -> Bool:
        """Returns whether self is greater than or equal to other.

        Args:
            other: The value to compare against.

        Returns:
            True if self is above or level with other, and False if either is
            a NaN.

        """
        return bigfloat_comparison.greater_equal(self, other)

    def __hash__[H: Hasher](self, mut hasher: H):
        """Hashes this number, so that it can be the key of a dictionary.

        The precision is not part of the value. One half holds one bit at
        any precision and the rest of the significand is zeros, so the
        significand is shifted down to an odd number and the exponent is
        raised to match before either is fed. The two zeros are equal and
        hash alike, and so does every NaN, which equals nothing at all.

        Parameters:
            H: The hasher to use.

        Args:
            hasher: The hasher to feed.
        """
        if self.kind == _KIND_NAN:
            UInt8(3).__hash__(hasher)
            return
        if self.kind == _KIND_INFINITY:
            UInt8(2).__hash__(hasher)
            UInt8(self.sign).__hash__(hasher)
            return
        if self.significand.is_zero():
            UInt8(1).__hash__(hasher)
            return
        UInt8(0).__hash__(hasher)
        UInt8(self.sign).__hash__(hasher)
        var shift = self.significand.trailing_zeros()
        Int64(self.exponent + shift).__hash__(hasher)
        (self.significand >> shift).__hash__(hasher)

    # ===------------------------------------------------------------------=== #
    # The IEEE 754 companion operations
    # ===------------------------------------------------------------------=== #
    #
    # Every one of these is a line of delegation to `decimo.bigfloat.ieee`,
    # where the reasoning lives. They are here because a caller holding a
    # value reaches for `x.logb()` before reaching for a module.

    def next_plus(self, precision: Int) raises -> Self:
        """The smallest representable value above this one.

        Args:
            precision: The bits a value may hold.

        Returns:
            The next value toward positive infinity, at `precision` bits.

        Raises:
            Error: Propagated from `ieee.next_plus()`.
        """
        return bigfloat_ieee.next_plus(self, precision)

    def next_minus(self, precision: Int) raises -> Self:
        """The largest representable value below this one.

        Args:
            precision: The bits a value may hold.

        Returns:
            The next value toward negative infinity, at `precision` bits.

        Raises:
            Error: Propagated from `ieee.next_minus()`.
        """
        return bigfloat_ieee.next_minus(self, precision)

    def next_toward(self, other: Self, precision: Int) raises -> Self:
        """The value next to this one in the direction of `other`.

        Args:
            other: The value that gives the direction.
            precision: The bits a value may hold.

        Returns:
            This value stepped one place toward `other`, or itself with
            `other`'s sign when the two are numerically equal.

        Raises:
            Error: Propagated from `ieee.next_toward()`.
        """
        return bigfloat_ieee.next_toward(self, other, precision)

    def logb(self) raises -> BigInt:
        """Where this value's leading bit sits, which is `floor(log2(|x|))`.

        Returns:
            The position as a power of two, in a `BigInt` because the sum
            that gives it can leave an `Int`.

        Raises:
            Error: Propagated from `ieee.logb()`, which refuses a zero, an
                infinity and a NaN.
        """
        return bigfloat_ieee.logb(self)

    def scaleb(self, n: Int) raises -> Self:
        """This value times `2^n`, exactly.

        Args:
            n: The power of two to scale by.

        Returns:
            The scaled value, at this one's own precision.

        Raises:
            Error: Propagated from `ieee.scaleb()`.
        """
        return bigfloat_ieee.scaleb(self, n)

    def copy_sign(self, other: Self) -> Self:
        """This value with the sign of `other`.

        Args:
            other: The value whose sign is taken.

        Returns:
            A copy carrying `other`'s sign.
        """
        return bigfloat_ieee.copy_sign(self, other)

    def copy_abs(self) -> Self:
        """This value without its sign.

        Returns:
            A copy with a positive sign, which is `abs(self)`.
        """
        return bigfloat_ieee.copy_abs(self)

    def copy_negate(self) -> Self:
        """This value with its sign flipped.

        Returns:
            A copy with the other sign, which is `-self`.
        """
        return bigfloat_ieee.copy_negate(self)

    def number_class(self) -> String:
        """The specification's name for what kind of number this is.

        Returns:
            One of `NaN`, `-Infinity`, `-Normal`, `-Zero`, `+Zero`,
            `+Normal` and `+Infinity`.
        """
        return bigfloat_ieee.number_class(self)

    def is_integer(self) -> Bool:
        """Whether this value is a whole number.

        Returns:
            True when it is finite and has no fractional part.
        """
        return bigfloat_ieee.is_integer(self)

    def truncate(self) raises -> Self:
        """This value with its fractional part removed.

        Returns:
            The whole number nearest it in the direction of zero, at its own
            precision.

        Raises:
            Error: Propagated from `ieee.truncate()`.
        """
        return bigfloat_ieee.truncate(self)

    def floor(self) raises -> Self:
        """The largest whole number at or below this value.

        Returns:
            The floor, at this value's own precision.

        Raises:
            Error: Propagated from `ieee.floor()`.
        """
        return bigfloat_ieee.floor(self)

    def ceil(self) raises -> Self:
        """The smallest whole number at or above this value.

        Returns:
            The ceiling, at this value's own precision.

        Raises:
            Error: Propagated from `ieee.ceil()`.
        """
        return bigfloat_ieee.ceil(self)

    def round_to_integer(
        self, rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN
    ) raises -> Self:
        """This value rounded to a whole number in any of the seven modes.

        Args:
            rounding_mode: Which way to round.

        Returns:
            The whole number the mode asks for, at this value's own
            precision.

        Raises:
            Error: Propagated from `ieee.round_to_integer()`.
        """
        return bigfloat_ieee.round_to_integer(self, rounding_mode)

    def __trunc__(self) raises -> Self:
        """This value truncated toward zero.

        Returns:
            What `truncate()` returns, under the name `math.trunc()` asks
            for.

        Raises:
            Error: Propagated from `truncate()`.
        """
        return self.truncate()

    def __floor__(self) raises -> Self:
        """The largest whole number at or below this value.

        Returns:
            What `floor()` returns, under the name `math.floor()` asks for.

        Raises:
            Error: Propagated from `floor()`.
        """
        return self.floor()

    def __ceil__(self) raises -> Self:
        """The smallest whole number at or above this value.

        Returns:
            What `ceil()` returns, under the name `math.ceil()` asks for.

        Raises:
            Error: Propagated from `ceil()`.
        """
        return self.ceil()

    def fma(
        self,
        other: Self,
        third: Self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """`self * other + third` with a single rounding.

        Args:
            other: The value to multiply by.
            third: The value to add to the product.
            precision: How many bits the result keeps.
            rounding_mode: Which way to round, once.

        Returns:
            The float of `precision` bits nearest the exact value, the
            product having been formed without rounding.

        Raises:
            Error: Propagated from `ieee.fma()`.
        """
        return bigfloat_ieee.fma(self, other, third, precision, rounding_mode)

    def remainder(
        self,
        other: Self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """IEEE 754's remainder: `self - other * n`, `n` the nearest integer.

        Args:
            other: The divisor.
            precision: How many bits the result keeps.
            rounding_mode: Which way to round, which only a destination too
                narrow to hold the answer ever consults.

        Returns:
            The remainder, at most half of `other` in magnitude.

        Raises:
            Error: Propagated from `ieee.remainder()`.
        """
        return bigfloat_ieee.remainder(self, other, precision, rounding_mode)

    def fmod(
        self,
        other: Self,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """C's `fmod`: `self - other * n`, `n` the quotient truncated.

        Args:
            other: The divisor.
            precision: How many bits the result keeps.
            rounding_mode: Which way to round, which only a destination too
                narrow to hold the answer ever consults.

        Returns:
            The remainder, with this value's sign and a magnitude below
            `other`'s.

        Raises:
            Error: Propagated from `ieee.fmod()`.
        """
        return bigfloat_ieee.fmod(self, other, precision, rounding_mode)

    # ===------------------------------------------------------------------=== #
    # Decimal
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def from_bigdecimal(
        value: BigDecimal,
        precision: Int = PRECISION,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Builds the nearest float to a decimal value.

        Args:
            value: The decimal.
            precision: The number of bits to keep.
            rounding_mode: How to round, since almost no decimal is a binary
                float.

        Returns:
            The float nearest the decimal, in the direction the mode asks for.

        Raises:
            ValueError: If `precision` is not positive.
            Error: Propagated from the conversion.
        """
        var parts = from_decimal_parts(
            BigInt.from_biguint(value.coefficient),
            -value.scale,
            precision,
            value.sign,
            rounding_mode,
        )
        return Self(
            significand=parts[0],
            exponent=parts[1],
            precision=precision,
            sign=value.sign,
        )

    @staticmethod
    def from_string(value: StringSlice) raises -> Self:
        """Parses decimal text at the default precision.

        Args:
            value: The text to parse.

        Returns:
            The value, at `PRECISION` bits.

        Raises:
            Error: Propagated from the parsing.

        Notes:

        This exists in the shape `Parsable` asks for -- one argument and no
        more -- so that generic code bounded on that trait can fill itself
        from text. The precision it lands on is the default one, which is
        what a double holds.
        """
        return Self.from_string(value, PRECISION, RoundingMode.ROUND_HALF_EVEN)

    @staticmethod
    def from_string(
        text: StringSlice,
        precision: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> Self:
        """Parses decimal text, or one of the three names.

        Args:
            text: The text, as `BigDecimal` accepts it -- digits, an optional
                point and an optional exponent -- or `nan`, `inf`,
                `infinity`, with an optional sign on the last two. The names
                are matched without regard to case.
            precision: The number of bits to keep.
            rounding_mode: How to round the digits.

        Returns:
            The float.

        Raises:
            ValueError: If `precision` is not positive.
            Error: If the text is not a number, propagated from `BigDecimal`.

        Notes:

        The digits go to `BigDecimal`'s parser rather than to one written
        here: it already settles the point, the exponent and every way the
        text can be malformed, and a second parser would be a second set of
        answers to the same questions.
        """
        var lowered = String(text).lower()
        if lowered == "nan":
            return Self.nan(precision)
        if (
            lowered == "inf"
            or lowered == "infinity"
            or lowered == "+inf"
            or lowered == "+infinity"
        ):
            return Self.infinity(precision, False)
        if lowered == "-inf" or lowered == "-infinity":
            return Self.infinity(precision, True)
        return Self.from_bigdecimal(BigDecimal(text), precision, rounding_mode)

    def to_bigdecimal(self) raises -> BigDecimal:
        """This value as an exact decimal.

        Returns:
            The same number, with no rounding: a binary float always has a
            finite decimal expansion, because `2^-k` is `5^k / 10^k`.

        Raises:
            ValueError: If the value is infinite or a NaN, neither of which a
                `BigDecimal` can hold.
            Error: Propagated from the conversion.

        Notes:

        The digit count is whatever the value needs, which for a small
        exponent is a lot: the smallest double is 751 significant digits and
        1074 decimal places. Ask `to_bigdecimal_rounded()` for a shorter
        answer.
        """
        if self.is_nan():
            raise ValueError(
                message="A NaN is not a decimal value.",
                function="BigFloat.to_bigdecimal()",
            )
        if self.is_infinite():
            raise ValueError(
                message="An infinity is not a decimal value.",
                function="BigFloat.to_bigdecimal()",
            )
        return to_exact_bigdecimal(self.significand, self.exponent, self.sign)

    def to_bigdecimal_rounded(
        self,
        digits: Int,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> BigDecimal:
        """This value as a decimal of `digits` significant digits.

        Args:
            digits: How many significant digits to keep. Must be positive.
            rounding_mode: How to round them.

        Returns:
            The rounded decimal.

        Raises:
            ValueError: If `digits` is not positive, or the value is infinite
                or a NaN.
            Error: Propagated from the conversion.

        Notes:

        One rounding, not two. The value is scaled by the power of ten that
        puts the digits asked for before the point, and the rounding reads
        that scaled value's own half and remainder. Taking the exact
        expansion and rounding it to a few more digits, then those digits to
        the count asked for, would be two roundings, and two can land a step
        away from the one.

        The cost follows `digits` and not the exponent: `2^-1000000` has
        301031 significant digits, and seventeen of them cost the work of
        seventeen. `to_bigdecimal()` is the one to ask when every digit is
        wanted.
        """
        if digits <= 0:
            raise ValueError(
                message="A digit count must be positive.",
                function="BigFloat.to_bigdecimal_rounded()",
            )
        if self.is_nan():
            raise ValueError(
                message="A NaN is not a decimal value.",
                function="BigFloat.to_bigdecimal_rounded()",
            )
        if self.is_infinite():
            raise ValueError(
                message="An infinity is not a decimal value.",
                function="BigFloat.to_bigdecimal_rounded()",
            )
        return to_rounded_bigdecimal(
            self.significand, self.exponent, self.sign, digits, rounding_mode
        )

    def decimal_digits(self) -> Int:
        """How many decimal digits this precision is worth.

        Returns:
            The digit count that holds the value's bits and no more than one
            digit beyond them, which is `ceil(precision * log10(2)) + 1`.
        """
        return Int(Float64(self.precision) * 0.30103) + 2

    def to_string(
        self,
        digits: Int = 0,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> String:
        """This value as decimal text.

        Args:
            digits: How many significant digits. Zero asks for as many as the
                precision is worth, which is what `decimal_digits()` returns.
            rounding_mode: How to round them.

        Returns:
            The text, with `NaN`, `Infinity` and `-Infinity` spelled out.

        Raises:
            Error: Propagated from the conversion.
        """
        if self.is_nan():
            return String("NaN")
        if self.is_infinite():
            return String("-Infinity") if self.sign else String("Infinity")
        var wanted = digits if digits > 0 else self.decimal_digits()
        return String(self.to_bigdecimal_rounded(wanted, rounding_mode))

    def internal_representation(self) raises -> String:
        """The parts, for looking at what a value really holds.

        Returns:
            The significand, the power of two and the precision, as
            `significand p exponent @ precision`.

        Raises:
            Error: Propagated from the formatting.
        """
        if self.is_nan():
            return String("NaN")
        if self.is_infinite():
            return String("-Infinity") if self.sign else String("Infinity")
        var text = String("-") if self.sign else String("")
        return (
            text
            + String(self.significand)
            + "p"
            + String(self.exponent)
            + "@"
            + String(self.precision)
        )

    # ===------------------------------------------------------------------=== #
    # Text
    # ===------------------------------------------------------------------=== #

    def write_to[W: Writer](self, mut writer: W):
        """Writes the value as decimal text.

        Parameters:
            W: The writer type.

        Args:
            writer: Where to write.

        Notes:

        Decimal, not the parts: a float prints as a number. `2^-52` is a
        value, not `4503599627370496p-104@53`, and the parts are available
        from `internal_representation()` for when they are what is wanted --
        the same split `BigInt` and `BigDecimal` have.

        The digit count is what the precision is worth. A writer cannot
        answer a failure, so a conversion that raises falls back to a marker.
        It is a marker rather than the parts because the only thing that
        raises here is the allocation the conversion needs, and formatting
        the parts would ask for one too.
        """
        try:
            writer.write(self.to_string())
        except:
            writer.write("<BigFloat: unprintable>")


comptime BFlt = BigFloat
"""A short name for `BigFloat`, as `BInt` is for `BigInt`.

There is deliberately no `Float`: a name that short, in a language whose
machine floats are `Float64` and `Float32`, would be read as one of those.
"""
