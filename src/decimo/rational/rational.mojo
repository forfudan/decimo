# ===----------------------------------------------------------------------=== #
# Copyright 2026 Yuhao Zhu
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

"""Implements the Rational type: an arbitrary-precision exact rational number.

A Rational represents any value p/q where p and q are BigInt integers and
q != 0. The fraction is always stored in lowest terms with a positive
denominator (the sign is carried by the numerator).

Invariants maintained by all constructors and operations:
    1. gcd(abs(numerator), denominator) == 1  (lowest terms)
    2. denominator > 0                        (sign in numerator)
    3. If value is zero: numerator == 0, denominator == 1
"""

from std.memory import bitcast

from decimo.bigdecimal.bigdecimal import BigDecimal, PRECISION
from decimo.bigint.bigint import BigInt
from decimo.bigint.number_theory import gcd
from decimo.errors import ConversionError, ValueError, ZeroDivisionError
from decimo.rounding_mode import RoundingMode
from decimo.traits import Parsable


struct Rational(
    Absable,
    Comparable,
    Copyable,
    FloatableRaising,
    IntableRaising,
    Movable,
    Parsable,
    Writable,
):
    """An arbitrary-precision exact rational number p/q.

    The fraction is always stored in lowest terms with a positive denominator.
    """

    var numerator: BigInt
    """The numerator of the rational number."""
    var denominator: BigInt
    """The denominator of the rational number. Always positive."""

    comptime _SIGNIFICAND_BITS = 53
    """Bits in the significand of a Float64, the implicit leading one
    included."""
    comptime _MIN_FLOAT_EXPONENT = -1074
    """The exponent every Float64 subnormal is written at: the smallest
    positive Float64 is 1 * 2^-1074."""
    comptime _MAX_FLOAT_EXPONENT = 971
    """The largest exponent a 53-bit significand can carry before the value
    leaves the range of a Float64."""
    comptime _FLOAT_INFINITY_BITS = UInt64(0x7FF0_0000_0000_0000)
    """The bit pattern of a positive Float64 infinity."""

    # ===------------------------------------------------------------------=== #
    # Constants
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def zero() -> Self:
        """Returns the value 0/1.

        Returns:
            A Rational representing zero.
        """
        return Self(BigInt.zero(), BigInt.one(), raw=True)

    @staticmethod
    def one() -> Self:
        """Returns the value 1/1.

        Returns:
            A Rational representing one.
        """
        return Self(BigInt.one(), BigInt.one(), raw=True)

    @staticmethod
    def two() -> Self:
        """Returns the value 2/1.

        Returns:
            A Rational representing two.
        """
        return Self(BigInt(UInt32(2)), BigInt.one(), raw=True)

    @staticmethod
    def minus_one() -> Self:
        """Returns the value -1/1.

        Returns:
            A Rational representing minus one.
        """
        return Self(BigInt.negative_one(), BigInt.one(), raw=True)

    @staticmethod
    def one_half() -> Self:
        """Returns the value 1/2.

        Returns:
            A Rational representing one half.
        """
        return Self(BigInt.one(), BigInt(UInt32(2)), raw=True)

    @staticmethod
    def one_third() -> Self:
        """Returns the value 1/3.

        Returns:
            A Rational representing one third.
        """
        return Self(BigInt.one(), BigInt(UInt32(3)), raw=True)

    # ===------------------------------------------------------------------=== #
    # Constructors
    # ===------------------------------------------------------------------=== #

    def __init__(out self, numerator: BigInt, denominator: BigInt) raises:
        """Initializes a rational number from a numerator and denominator.

        The result is automatically normalized to lowest terms with a
        positive denominator.

        Args:
            numerator: The numerator.
            denominator: The denominator (must not be zero).

        Raises:
            ZeroDivisionError: If the denominator is zero.
        """
        if denominator.is_zero():
            raise ZeroDivisionError(
                message="Rational denominator cannot be zero",
                function="Rational.__init__()",
            )

        if numerator.is_zero():
            self.numerator = BigInt()
            self.denominator = BigInt(UInt32(1))
            return

        self.numerator = numerator.copy()
        self.denominator = denominator.copy()
        self._normalize()

    def __init__(out self, value: BigInt):
        """Initializes a rational number from an integer (denominator = 1).

        Args:
            value: The integer value.
        """
        self.numerator = value.copy()
        self.denominator = BigInt(UInt32(1))

    @implicit
    def __init__(out self, value: Scalar) where value.dtype.is_integral():
        """Initializes a rational number from an integral scalar
        (denominator = 1). This includes all SIMD integral types, such as
        Int8, Int16, UInt32, etc.

        Constraints:
            The dtype of the scalar must be integral. A floating-point value
            is not accepted here, because whether `Rational(0.1)` should mean
            1/10 or the binary float that literal denotes is a question the
            caller has to answer: use `from_float_scalar()` for the latter and
            `Rational("0.1")` for the former.

        Args:
            value: The integral scalar value to convert.
        """
        self = Self.from_integral_scalar(value)

    def __init__(
        out self, var numerator: BigInt, var denominator: BigInt, *, raw: Bool
    ):
        """Initializes a Rational without normalization.
        Caller must ensure the invariants hold.

        Args:
            numerator: The numerator (already in lowest terms).
            denominator: The denominator (already positive, coprime with numerator).
            raw: This is a raw constructor without normalization.
                Caller must ensure invariants.

        Returns:
            A new Rational.
        """
        self.numerator = numerator^
        self.denominator = denominator^

    def __init__(out self, value: String) raises:
        """Initializes a rational number from a string representation.
        See `from_string()` for the accepted formats.

        Args:
            value: The string representation, e.g. "3/7", "1.5", "-42",
                "7e-3".

        Raises:
            ConversionError: If the string cannot be parsed as a rational.
            ZeroDivisionError: If the parsed denominator is zero.
        """
        self = Self.from_string(value)

    def __init__(out self, value: BigDecimal) raises:
        """Initializes a rational number from a decimal, losslessly.

        Args:
            value: The decimal value to convert.

        Raises:
            Error: If the conversion fails.
        """
        self = Self.from_bigdecimal(value)

    # ===------------------------------------------------------------------=== #
    # Constructing methods that are not dunders
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def from_integral_scalar[
        dtype: DType, //
    ](value: Scalar[dtype]) -> Self where dtype.is_integral():
        """Creates a Rational from an integral scalar, with denominator 1.
        This includes all SIMD integral types:
        Int8, Int16, Int32, Int64, Int128, Int256,
        UInt8, UInt16, UInt32, UInt64, UInt128, UInt256,
        and the platform-sized Int (DType.int) and UInt (DType.uint).

        Constraints:
            The dtype must be integral.

        Args:
            value: The Scalar value to be converted to Rational.

        Returns:
            The value as a Rational, already in lowest terms.

        Parameters:
            dtype: The data type of the scalar value.
        """
        return Self(BigInt.from_integral_scalar(value))

    @staticmethod
    def from_string(value: String) raises -> Self:
        """Creates a Rational from a string representation.

        Two forms are accepted:

        - A single decimal literal, e.g. "42", "-1.5", "7e-3". It is read
          exactly, so "1.5" is 3/2 and "7e-3" is 7/1000.
        - Two decimal literals separated by "/", e.g. "3/7". Each side is
          read exactly and the first is divided by the second, so "3/7" is
          3/7 and "1.5/2.5" is 3/5.

        Each side accepts everything `BigDecimal` accepts, including signs,
        spaces, commas, underscores and scientific notation.

        Args:
            value: The string to parse, e.g. "3/7", "1.5", "-42", "7e-3".

        Returns:
            The parsed value, in lowest terms.

        Raises:
            ConversionError: If the string is not one of the two forms above.
            ZeroDivisionError: If the denominator is zero.
        """
        var separator = value.find("/")

        if separator < 0:
            return Self._from_decimal_literal(value, literal=value)

        if value.find("/", separator + 1) >= 0:
            raise ConversionError(
                function="Rational.from_string(value: String)",
                message=(
                    'The input value "'
                    + value
                    + '" cannot be parsed as a rational.\n'
                    + 'It contains more than one "/".'
                ),
            )

        var numerator = Self._from_decimal_literal(
            String(value[byte=:separator]), literal=value
        )
        var denominator = Self._from_decimal_literal(
            String(value[byte = separator + 1 :]), literal=value
        )

        if denominator.is_zero():
            raise ZeroDivisionError(
                function="Rational.from_string(value: String)",
                message=(
                    'The input value "' + value + '" has a zero denominator.'
                ),
            )

        return numerator / denominator

    @staticmethod
    def _from_decimal_literal(value: String, *, literal: String) raises -> Self:
        """Reads one decimal literal exactly, as a Rational.

        Args:
            value: The decimal literal, i.e. one side of a "p/q" string, or
                the whole string when there is no "/".
            literal: The full string the caller was given, quoted in the
                error message so that it names what the user wrote.

        Returns:
            The exact value of the literal.

        Raises:
            ConversionError: If `value` is not a decimal literal.
        """
        try:
            return Self.from_bigdecimal(BigDecimal(value))
        except e:
            raise ConversionError(
                function="Rational.from_string(value: String)",
                message=(
                    'The input value "'
                    + literal
                    + '" cannot be parsed as a rational.'
                ),
                previous_error=e^,
            )

    @staticmethod
    def from_bigdecimal(value: BigDecimal) raises -> Self:
        """Creates a Rational from a BigDecimal, losslessly.

        A decimal is `coefficient * 10^(-scale)`, which is already a
        fraction, so the conversion is exact for every input.

        Args:
            value: The decimal value to convert.

        Returns:
            The same value as a Rational in lowest terms.

        Raises:
            Error: If the underlying integer arithmetic fails.
        """
        var numerator = BigInt.from_biguint(value.coefficient, value.sign)

        if value.scale > 0:
            return Self(numerator, BigInt(10) ** value.scale)

        if value.scale < 0:
            # A negative scale means trailing zeros: 4.2E+4 is 42 * 10^3.
            numerator = numerator * (BigInt(10) ** (-value.scale))

        return Self(numerator)

    @staticmethod
    def from_float_scalar[
        dtype: DType, //
    ](value: Scalar[dtype]) raises -> Self where dtype.is_floating_point():
        """Creates a Rational from a floating-point scalar, losslessly.
        This includes all SIMD floating-point types, such as Float16,
        BFloat16, Float32, Float64, and the 8-bit formats.

        Every finite binary float is a fraction whose denominator is a power
        of two, so the result is the exact value of `value`, not the decimal
        literal that was written to produce it: `from_float_scalar(0.1)` is
        3602879701896397/36028797018963968, not 1/10.

        Constraints:
            The dtype must be floating-point.

        Args:
            value: The floating-point value to convert.

        Returns:
            The exact value of `value` as a Rational in lowest terms.

        Raises:
            ConversionError: If `value` is infinite or NaN, neither of which
                is a rational number.

        Parameters:
            dtype: The data type of the scalar value.

        Notes:

        Every narrower binary format is a subset of Float64 - fewer
        significand bits and a narrower exponent range - so widening first is
        exact, and one decoder then serves them all.
        """
        var widened = value.cast[DType.float64]()
        var bits = widened.to_bits()
        var exponent_field = Int((bits >> 52) & 0x7FF)
        var mantissa_field = bits & 0x000F_FFFF_FFFF_FFFF
        var negative = Bool((bits >> 63) != 0)

        if exponent_field == 0x7FF:
            raise ConversionError(
                function="Rational.from_float_scalar(value: Scalar[dtype])",
                message=(
                    "The input value "
                    + String(value)
                    + " is not a rational number."
                ),
            )

        var mantissa = UInt64(mantissa_field)
        var exponent: Int
        if exponent_field == 0:
            # Subnormal: no implicit leading bit, fixed exponent.
            exponent = -1074
        else:
            # Normal: restore the implicit leading bit. The bias is 1023 and
            # the mantissa is read as a 53-bit integer, hence 1023 + 52.
            mantissa |= UInt64(1) << 52
            exponent = exponent_field - 1075

        if mantissa == 0:
            return Self.zero()

        var numerator = BigInt(mantissa)
        if negative:
            numerator = -numerator

        if exponent >= 0:
            return Self(numerator << exponent)

        return Self(numerator, BigInt(1) << (-exponent))

    # ===------------------------------------------------------------------=== #
    # Normalization
    # ===------------------------------------------------------------------=== #

    def _normalize(mut self) raises:
        """Normalizes the fraction to lowest terms with positive denominator.

        Ensures:
            1. gcd(|numerator|, denominator) == 1
            2. denominator > 0
            3. Zero is represented as 0/1
        """
        # Ensure denominator is positive
        if self.denominator.is_negative():
            self.numerator = -self.numerator
            self.denominator = -self.denominator

        # Reduce to lowest terms
        # TODO: This can be optimized by several methods. I can figure out some
        #   methods, but need to do some research to figure out which is the best.
        # 1. Prime factorization of numerator and denominator, cancel common factors.
        # 2. Combine gcd with division.
        # 3. Since we know that the division will be exact, we can add a method
        #   to Integer, e.g., `exact_divide`. The user must ensure the exactness.
        var g = gcd(self.numerator, self.denominator)
        if g > BigInt(1):
            self.numerator = self.numerator // g
            self.denominator = self.denominator // g

    # ===------------------------------------------------------------------=== #
    # Lifecycle: copy
    # ===------------------------------------------------------------------=== #

    def copy(self) -> Self:
        """Returns a deep copy.

        Returns:
            A copy of this Rational.
        """
        return Self(self.numerator.copy(), self.denominator.copy(), raw=True)

    # ===------------------------------------------------------------------=== #
    # String / display
    # ===------------------------------------------------------------------=== #

    @no_inline
    def __str__(self) -> String:
        """Returns the string representation in the form "p/q" or "p" if integer.

        Returns:
            The string representation.
        """
        return String(self)

    @no_inline
    def __repr__(self) -> String:
        """Returns the repr string in the form "Rational(p, q)".

        Returns:
            The repr string.
        """
        return (
            "Rational("
            + self.numerator.to_string()
            + ", "
            + self.denominator.to_string()
            + ")"
        )

    def write_to[W: Writer](self, mut writer: W):
        """Writes the string representation to a writer.

        If the denominator is 1, writes just the numerator.
        Otherwise writes "numerator/denominator".

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        writer.write(self.numerator.to_string())
        if not self.denominator.is_one():
            writer.write("/", self.denominator.to_string())

    # ===------------------------------------------------------------------=== #
    # Type-transfer dunders and other type-transfer methods
    # ===------------------------------------------------------------------=== #

    def __float__(self) raises -> Float64:
        """Converts the Rational to a floating-point number.
        See `to_float()` for more information.

        Returns:
            The nearest Float64 to this value.

        Raises:
            Error: If the underlying arithmetic fails.
        """
        return self.to_float()

    def __int__(self) raises -> Int:
        """Returns the value truncated toward zero, as an Int.
        See `to_int()` for more information.

        Returns:
            The truncated value.

        Raises:
            OverflowError: If the truncated value exceeds the size of Int.
        """
        return self.to_int()

    def to_float(self) raises -> Float64:
        """Returns the nearest Float64 to this value.

        The result is correctly rounded. The division is carried out on the
        exact integers and the 53-bit significand is rounded once, ties to
        even, so no intermediate is rounded twice. A value too large for a
        Float64 becomes `inf`, matching `BigInt.__float__()`; one too small
        becomes zero.

        Returns:
            The nearest Float64, ties to even.

        Raises:
            Error: If the underlying arithmetic fails.
        """
        if self.numerator.is_zero():
            return Float64(0)

        var negative = self.numerator.is_negative()
        var dividend = abs(self.numerator)
        var divisor = self.denominator.copy()

        # |numerator| / denominator lies in (2^(b - 1), 2^(b + 1)) for
        # b = bits(numerator) - bits(denominator), so scaling by this shift
        # leaves a quotient of 53 or 54 bits.
        var shift = Self._SIGNIFICAND_BITS - (
            dividend.bit_length() - divisor.bit_length()
        )
        var division = Self._shifted_divmod(dividend, divisor, shift)
        if division[0].bit_length() > Self._SIGNIFICAND_BITS:
            # One bit too many: take one binary place back and redo it.
            shift -= 1
            division = Self._shifted_divmod(dividend, divisor, shift)

        # The value is now `significand * 2^exponent`.
        var exponent = -shift
        if exponent < Self._MIN_FLOAT_EXPONENT:
            # Below the smallest normal Float64. Such a value is held with
            # fewer than 53 bits, so the significand has to be rounded at the
            # fixed exponent of the subnormal range instead.
            exponent = Self._MIN_FLOAT_EXPONENT
            division = Self._shifted_divmod(dividend, divisor, -exponent)

        var significand = division[0].copy()
        var remainder = division[1].copy()

        if not remainder.is_zero():
            # `2 * remainder` against the divisor is the exact comparison of
            # the dropped tail against one half of the last kept bit.
            var half = (remainder * BigInt(2)).compare(division[2])
            if (half > 0) or (
                half == 0 and not (significand % BigInt(2)).is_zero()
            ):
                significand = significand + BigInt(1)
                if significand.bit_length() > Self._SIGNIFICAND_BITS:
                    # The significand reached 2^53: carry it to the exponent.
                    significand = significand >> 1
                    exponent += 1

        var bits: UInt64
        if exponent > Self._MAX_FLOAT_EXPONENT:
            bits = Self._FLOAT_INFINITY_BITS
        else:
            # A 53-bit significand at `exponent` is written with its leading
            # bit implicit and `exponent + 1075` in the exponent field; a
            # shorter one, which only happens at the subnormal exponent,
            # keeps every bit and leaves that field zero. Adding the fields
            # rather than packing them gets both cases right, because the
            # leading bit of a 53-bit significand carries into the field
            # exactly where the implicit bit would have been dropped.
            bits = UInt64(significand.to_int()) + (
                UInt64(exponent - Self._MIN_FLOAT_EXPONENT) << 52
            )

        if negative:
            bits |= UInt64(1) << 63

        return bitcast[DType.float64](bits)

    @staticmethod
    def _shifted_divmod(
        dividend: BigInt, divisor: BigInt, shift: Int
    ) raises -> Tuple[BigInt, BigInt, BigInt]:
        """Divides `dividend * 2^shift` by `divisor`, exactly.

        A negative `shift` scales the divisor instead, which is the same
        quotient without the fractional shift.

        Args:
            dividend: The dividend, before scaling.
            divisor: The divisor, before scaling.
            shift: The power of two to scale the dividend by.

        Returns:
            The quotient, the remainder, and the scaled divisor, which the
            caller needs in order to weigh the remainder against it.

        Raises:
            Error: If the underlying division fails.
        """
        var scaled_dividend = dividend.copy()
        var scaled_divisor = divisor.copy()
        if shift >= 0:
            scaled_dividend = dividend << shift
        else:
            scaled_divisor = divisor << (-shift)

        var division = scaled_dividend.__divmod__(scaled_divisor)
        return (division[0].copy(), division[1].copy(), scaled_divisor^)

    def to_integer(self) raises -> BigInt:
        """Returns the value truncated toward zero, as a BigInt.

        Truncation, not flooring: `(-7/2).to_integer()` is -3, as
        `math.trunc()` gives in Python.

        Returns:
            The integer part of this value.

        Raises:
            Error: If the underlying division fails.
        """
        return self.numerator.truncate_divide(self.denominator)

    def to_int(self) raises -> Int:
        """Returns the value truncated toward zero, as an Int.

        Returns:
            The integer part of this value.

        Raises:
            OverflowError: If the truncated value exceeds the size of Int.
        """
        return self.to_integer().to_int()

    def to_bigdecimal(
        self,
        precision: Int = PRECISION,
        rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
    ) raises -> BigDecimal:
        """Returns this value as a BigDecimal of at most `precision` digits.

        The division is carried out on the exact integers and rounded once,
        by `rounding_mode`, so there is no intermediate result to round
        twice. Where the value has an exact decimal form within `precision`
        significant digits, that form is returned with no trailing padding:
        `Rational(1, 2).to_bigdecimal()` is `0.5`, not `0.500...0`.

        Args:
            precision: The maximum number of significant digits. Must be
                positive.
            rounding_mode: How to round a value that needs more digits than
                `precision`.

        Returns:
            The value as a BigDecimal.

        Raises:
            ValueError: If `precision` is not positive.
            Error: If the underlying integer arithmetic fails.
        """
        if precision <= 0:
            raise ValueError(
                function=(
                    "Rational.to_bigdecimal(precision: Int, rounding_mode:"
                    " RoundingMode)"
                ),
                message=(
                    "The precision must be positive, got "
                    + String(precision)
                    + "."
                ),
            )

        if self.numerator.is_zero():
            return BigDecimal.zero()

        var sign = self.numerator.is_negative()
        var dividend = abs(self.numerator)
        var divisor = self.denominator.copy()

        # |numerator| / denominator lies in (10^(d - 1), 10^(d + 1)) for
        # d = digits(numerator) - digits(denominator), so scaling by this
        # exponent leaves a quotient of `precision` or `precision + 1` digits.
        var exponent = precision - (
            dividend.number_of_digits() - divisor.number_of_digits()
        )
        var scaled_dividend = dividend.copy()
        var scaled_divisor = divisor.copy()
        if exponent >= 0:
            scaled_dividend = dividend * (BigInt(10) ** exponent)
        else:
            scaled_divisor = divisor * (BigInt(10) ** (-exponent))

        var division = scaled_dividend.__divmod__(scaled_divisor)
        if division[0].number_of_digits() > precision:
            # One digit too many: take one decimal place back and redo it.
            exponent -= 1
            scaled_dividend = dividend.copy()
            scaled_divisor = divisor.copy()
            if exponent >= 0:
                scaled_dividend = dividend * (BigInt(10) ** exponent)
            else:
                scaled_divisor = divisor * (BigInt(10) ** (-exponent))
            division = scaled_dividend.__divmod__(scaled_divisor)

        var quotient = division[0].copy()
        var remainder = division[1].copy()

        if remainder.is_zero():
            # The value fits exactly. Drop the padding zeros the scaling
            # added, so that 1/2 reads as 0.5 rather than 0.500...0.
            while exponent > 0 and (quotient % BigInt(10)).is_zero():
                quotient = quotient // BigInt(10)
                exponent -= 1
        else:
            # `2 * remainder` against the divisor is the exact comparison of
            # the dropped tail against one half of the last kept digit.
            var half = (remainder * BigInt(2)).compare(scaled_divisor)
            var round_away: Bool
            if rounding_mode == RoundingMode.ROUND_DOWN:
                round_away = False
            elif rounding_mode == RoundingMode.ROUND_UP:
                round_away = True
            elif rounding_mode == RoundingMode.ROUND_CEILING:
                round_away = not sign
            elif rounding_mode == RoundingMode.ROUND_FLOOR:
                round_away = sign
            elif rounding_mode == RoundingMode.ROUND_HALF_UP:
                round_away = half >= 0
            elif rounding_mode == RoundingMode.ROUND_HALF_DOWN:
                round_away = half > 0
            else:  # ROUND_HALF_EVEN
                round_away = (half > 0) or (
                    half == 0 and not (quotient % BigInt(2)).is_zero()
                )

            if round_away:
                quotient = quotient + BigInt(1)
                if quotient.number_of_digits() > precision:
                    # 999...9 became 1000...0: drop the digit it gained.
                    quotient = quotient // BigInt(10)
                    exponent -= 1

        return BigDecimal(
            coefficient=quotient.to_biguint(),
            scale=exponent,
            sign=sign,
        )

    # ===------------------------------------------------------------------=== #
    # Comparison operators
    # ===------------------------------------------------------------------=== #

    def __eq__(self, other: Self) -> Bool:
        """Returns True if two rationals are equal.

        Since both are in lowest terms, we can compare directly.

        Args:
            other: The other rational.

        Returns:
            True if equal.
        """
        return (
            self.numerator == other.numerator
            and self.denominator == other.denominator
        )

    def __ne__(self, other: Self) -> Bool:
        """Returns True if two rationals are not equal.

        Args:
            other: The other rational.

        Returns:
            True if not equal.
        """
        return not self.__eq__(other)

    def __lt__(self, other: Self) -> Bool:
        """Returns True if self < other.

        Compares by cross-multiplication: a/b < c/d iff a*d < c*b
        (since both denominators are positive).

        Args:
            other: The other rational.

        Returns:
            True if self is less than other.
        """
        return (
            self.numerator * other.denominator
            < other.numerator * self.denominator
        )

    def __le__(self, other: Self) -> Bool:
        """Returns True if self <= other.

        Args:
            other: The other rational.

        Returns:
            True if self is less than or equal to other.
        """
        return not other.__lt__(self)

    def __gt__(self, other: Self) -> Bool:
        """Returns True if self > other.

        Args:
            other: The other rational.

        Returns:
            True if self is greater than other.
        """
        return other.__lt__(self)

    def __ge__(self, other: Self) -> Bool:
        """Returns True if self >= other.

        Args:
            other: The other rational.

        Returns:
            True if self is greater than or equal to other.
        """
        return not self.__lt__(other)

    # ===------------------------------------------------------------------=== #
    # Unary operators
    # ===------------------------------------------------------------------=== #

    def __neg__(self) -> Self:
        """Returns the negation of this rational.

        Returns:
            The negated value.
        """
        if self.numerator.is_zero():
            return Self(BigInt(0), BigInt(1), raw=True)
        return Self(-self.numerator, self.denominator.copy(), raw=True)

    def __abs__(self) -> Self:
        """Returns the absolute value.

        Returns:
            The absolute value.
        """
        return Self(abs(self.numerator), self.denominator.copy(), raw=True)

    # ===------------------------------------------------------------------=== #
    # Arithmetic operators
    # ===------------------------------------------------------------------=== #

    def __add__(self, other: Self) raises -> Self:
        """Returns self + other.

        Uses the formula: a/b + c/d = (a*d + c*b) / (b*d),
        then normalizes to lowest terms.

        Args:
            other: The other rational.

        Returns:
            The sum.

        Raises:
            Error: Propagated from underlying BigInt arithmetic.
        """
        var num = (
            self.numerator * other.denominator
            + other.numerator * self.denominator
        )
        var den = self.denominator * other.denominator
        return Self(num, den)

    def __sub__(self, other: Self) raises -> Self:
        """Returns self - other.

        Args:
            other: The other rational.

        Returns:
            The difference.

        Raises:
            Error: Propagated from underlying BigInt arithmetic.
        """
        var num = (
            self.numerator * other.denominator
            - other.numerator * self.denominator
        )
        var den = self.denominator * other.denominator
        return Self(num, den)

    def __mul__(self, other: Self) raises -> Self:
        """Returns self * other.

        Uses cross-GCD pre-reduction to keep intermediates small:
        gcd_ad = gcd(a, d), gcd_bc = gcd(b, c), then
        (a/gcd_ad * c/gcd_bc) / (d/gcd_ad * b/gcd_bc).

        Args:
            other: The other rational.

        Returns:
            The product.

        Raises:
            Error: Propagated from underlying BigInt arithmetic.
        """
        # (a/b) * (c/d) = (a*c) / (b*d) = (a/gcd_ad * c/gcd_bc) / (b/gcd_bc * d/gcd_ad)
        var gcd_ad = gcd(self.numerator, other.denominator)
        var gcd_bc = gcd(self.denominator, other.numerator)
        var num = (self.numerator // gcd_ad) * (other.numerator // gcd_bc)
        var den = (self.denominator // gcd_bc) * (other.denominator // gcd_ad)
        return Self(num, den)

    def __truediv__(self, other: Self) raises -> Self:
        """Returns self / other.

        Uses cross-GCD pre-reduction: reduce self.numerator with
        other.numerator, and self.denominator with other.denominator,
        then cross-multiply to keep intermediates small.

        Args:
            other: The other rational.

        Returns:
            The quotient.

        Raises:
            ZeroDivisionError: If other is zero.
        """
        if other.numerator.is_zero():
            raise ZeroDivisionError(
                message="Division by zero",
                function="Rational.__truediv__()",
            )
        # (a/b) / (c/d) = (a*d) / (b*c) = (a/gcd_ac * d/gcd_bd) / (b/gcd_bd * c/gcd_ac)
        var gcd_ac = gcd(self.numerator, other.numerator)
        var gcd_bd = gcd(self.denominator, other.denominator)
        var num = (self.numerator // gcd_ac) * (other.denominator // gcd_bd)
        var den = (self.denominator // gcd_bd) * (other.numerator // gcd_ac)
        return Self(num, den)

    # ===------------------------------------------------------------------=== #
    # Query methods
    # ===------------------------------------------------------------------=== #

    def is_zero(self) -> Bool:
        """Returns True if the value is zero.

        Returns:
            True if numerator is zero.
        """
        return self.numerator.is_zero()

    def is_integer(self) -> Bool:
        """Returns True if the value is an integer (denominator == 1).

        Returns:
            True if the denominator is 1.
        """
        return self.denominator.is_one()

    def is_positive(self) -> Bool:
        """Returns True if the value is positive (> 0).

        Returns:
            True if positive.
        """
        return self.numerator.is_positive()

    def is_negative(self) -> Bool:
        """Returns True if the value is negative (< 0).

        Returns:
            True if negative.
        """
        return self.numerator.is_negative()

    def sign(self) -> Int:
        """Returns the sign of the rational: -1, 0, or 1.

        Returns:
            -1 if negative, 0 if zero, 1 if positive.
        """
        if self.numerator.is_zero():
            return 0
        if self.numerator.is_negative():
            return -1
        return 1

    def reciprocal(self) raises -> Self:
        """Returns the reciprocal (1/self).

        Returns:
            The reciprocal.

        Raises:
            ZeroDivisionError: If self is zero.
        """
        if self.numerator.is_zero():
            raise ZeroDivisionError(
                message="Cannot take reciprocal of zero",
                function="Rational.reciprocal()",
            )
        # No need to go through __init__ normalization since self is already
        # in lowest terms. Just need to handle sign convention.
        if self.numerator.is_negative():
            return Self(-self.denominator, -self.numerator, raw=True)
        return Self(self.denominator.copy(), self.numerator.copy(), raw=True)
