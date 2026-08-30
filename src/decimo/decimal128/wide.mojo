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
#
# A wider number for Decimal128 to compute with
#
# ===----------------------------------------------------------------------=== #

"""Implements `Wide`, the intermediate value `Decimal128`'s series run on.

`Decimal128` holds 28 digits. A series summed in it rounds every term to
those 28 digits, and a few hundred terms of rounding is a few units in the
last place of the answer: `ln` was wrong in 63 of 80 random cases, by up to 6
units, and `exp` in 19 of 25, by up to 8.

`Wide` gives those series ten digits of room. It is a sign, a `UInt256`
mantissa held at exactly `DIGITS` digits, and a power of ten -- a small
floating-point number in base ten, and nothing more than the series and the
reductions need. It does not depend on `BigDecimal` or any other
arbitrary-precision type: `Decimal128` is a plain struct and stays one.

Thirty-eight digits is what the mantissa can hold and still be multiplied:
`10^38 * 10^38` is `10^76`, and `UInt256` reaches `1.15E+77`.
"""

from std.builtin.globals import global_constant

from decimo.decimal128.decimal128 import Decimal128
import decimo.decimal128.utility as decimal128_utility
from decimo.errors import OverflowError, ValueError
from decimo.rounding_mode import RoundingMode


@always_inline
def _drop_digits(value: UInt256, places: Int) -> UInt256:
    """Returns `value` with its last `places` digits removed.

    Args:
        value: The digits.
        places: How many to remove, from 1 up.

    Returns:
        The quotient. The reciprocal divider covers powers up to `10^48`,
        which is every shift a `Wide` asks for; the wider type shifts by up
        to 75 and pays the software divide for the few that go past.
    """
    if places <= 48:
        return decimal128_utility.udiv_u256_by_pow10_gm(value, places)
    if places > 77:
        return UInt256(0)
    return value // decimal128_utility.power_of_10[DType.uint256](places)


struct WideValue[DIGITS: Int](Copyable, Movable):
    """A signed number of `DIGITS` decimal digits and a power of ten.

    The value is `(-1)^sign * mantissa * 10^exponent`. The mantissa is kept
    at exactly `DIGITS` digits, or zero, so that every operation starts from
    the same shape.

    Parameters:
        DIGITS: How many digits the mantissa carries. At 38 or fewer a
            product of two mantissas still fits in `UInt256` and the
            multiplication is one instruction; above that it is done in
            halves, which costs three multiplications instead of one. The
            two widths in use are `Wide` and `Extended`.
    """

    var mantissa: UInt256
    """The digits, exactly `DIGITS` of them unless the value is zero."""

    var exponent: Int
    """The power of ten the mantissa is multiplied by."""

    var sign: Bool
    """True when the value is negative."""

    def __init__(out self):
        """Constructs zero."""
        self.mantissa = UInt256(0)
        self.exponent = 0
        self.sign = False

    def __init__(out self, var mantissa: UInt256, exponent: Int, sign: Bool):
        """Constructs a value and normalizes it.

        Args:
            mantissa: The digits, of any length.
            exponent: The power of ten they are multiplied by.
            sign: True for a negative value.
        """
        self.mantissa = mantissa
        self.exponent = exponent
        self.sign = sign
        self._normalize()

    @staticmethod
    def from_int(value: Int) -> Self:
        """Returns a whole number as a `Wide`.

        Args:
            value: The number.

        Returns:
            The same value, normalized.
        """
        var magnitude = UInt256(abs(value))
        return Self(magnitude, 0, value < 0)

    @staticmethod
    def from_decimal(value: Decimal128) -> Self:
        """Returns a `Decimal128` as a `Wide`, exactly.

        Args:
            value: The number to widen.

        Returns:
            The same value with room to compute in.
        """
        return Self(
            UInt256(value.coefficient()),
            -value.scale(),
            value.is_negative(),
        )

    def _normalize(mut self):
        """Brings the mantissa to exactly `DIGITS` digits."""
        if self.mantissa == UInt256(0):
            self.exponent = 0
            self.sign = False
            return

        var digits = decimal128_utility.number_of_digits(self.mantissa)
        if digits > Self.DIGITS:
            var drop = digits - Self.DIGITS
            # `round_coefficient` with the digit count already in hand: it
            # goes through the reciprocal divider, where the deprecated
            # `round_to_keep_first_n_digits` pays a software divide and a
            # software modulo, 313 ns against 8.
            self.mantissa = decimal128_utility.round_coefficient[
                skip_digit_check=True
            ](self.mantissa, drop, self.sign)
            self.exponent += drop
            # Rounding up can carry into one more digit: 999... becomes 1000...
            if self.mantissa >= decimal128_utility.power_of_10[DType.uint256](
                Self.DIGITS
            ):
                self.mantissa //= UInt256(10)
                self.exponent += 1
        elif digits < Self.DIGITS:
            var raise_by = Self.DIGITS - digits
            self.mantissa *= decimal128_utility.power_of_10[DType.uint256](
                raise_by
            )
            self.exponent -= raise_by

    def is_zero(self) -> Bool:
        """Returns whether the value is zero.

        Returns:
            True when the mantissa is zero.
        """
        return self.mantissa == UInt256(0)

    def __neg__(self) -> Self:
        """Returns the value with its sign flipped.

        Returns:
            The negation.
        """
        var result = self.copy()
        if not result.is_zero():
            result.sign = not result.sign
        return result^

    def __add__(self, other: Self) raises -> Self:
        """Returns the sum.

        Args:
            other: The value to add.

        Returns:
            The sum, normalized.

        Raises:
            Error: If aligning the two would need more digits than `UInt256`
                holds, which cannot happen for values a series produces.
        """
        if self.is_zero():
            return other.copy()
        if other.is_zero():
            return self.copy()

        # Line the two up on the lower exponent. Beyond `DIGITS` apart the
        # smaller one cannot change a digit of the larger.
        var gap = self.exponent - other.exponent
        if gap > Self.DIGITS:
            return self.copy()
        if gap < -Self.DIGITS:
            return other.copy()

        var left = self.mantissa
        var right = other.mantissa
        var exponent: Int
        # Lining the two up either lengthens the larger mantissa or shortens
        # the smaller one. Lengthening keeps every digit and is what a `Wide`
        # does, since 38 digits and a gap of at most 38 still fit `UInt256`.
        # At 75 they do not, and there the smaller value gives up the digits
        # below the larger one's last -- under a unit in the last place, and
        # the only way to hold the sum at all.
        comptime room = 77 - Self.DIGITS
        if gap > 0:
            exponent = other.exponent
            if gap <= room:
                left *= decimal128_utility.power_of_10[DType.uint256](gap)
            else:
                right = _drop_digits(right, gap)
                exponent = self.exponent
        elif gap < 0:
            exponent = self.exponent
            if -gap <= room:
                right *= decimal128_utility.power_of_10[DType.uint256](-gap)
            else:
                left = _drop_digits(left, -gap)
                exponent = other.exponent
        else:
            exponent = self.exponent

        if self.sign == other.sign:
            return Self(left + right, exponent, self.sign)
        if left >= right:
            return Self(left - right, exponent, self.sign)
        return Self(right - left, exponent, other.sign)

    def __sub__(self, other: Self) raises -> Self:
        """Returns the difference.

        Args:
            other: The value to subtract.

        Returns:
            The difference, normalized.

        Raises:
            Error: Propagated from the addition.
        """
        return self + (-other)

    def __mul__(self, other: Self) raises -> Self:
        """Returns the product.

        Args:
            other: The value to multiply by.

        Returns:
            The product, normalized.

        Raises:
            Error: Propagated from the normalization.

        Notes:

        Below 39 digits both mantissas are under `10^38`, so their product is
        under `10^76` and `UInt256` holds it whole.

        Wider than that it does not fit, and the product is assembled from
        halves. Splitting each mantissa at `10^h` gives four partial products,
        each inside `UInt256`, and only the top `DIGITS` digits of their sum
        are kept -- the rest is below the last digit either way. The two
        truncations cost less than two units in the last place, which at 75
        digits is forty digits below anything `Decimal128` prints.
        """
        if self.is_zero() or other.is_zero():
            return Self()

        comptime if Self.DIGITS <= 38:
            return Self(
                self.mantissa * other.mantissa,
                self.exponent + other.exponent,
                self.sign != other.sign,
            )
        else:
            # Split each mantissa at `10^half`, so that
            #
            #     a * b = ah*bh*10^(2*half)
            #           + (ah*bl + al*bh)*10^half
            #           + al*bl
            #
            # and keep the top `DIGITS` digits of that. The last piece is
            # below `10^DIGITS` and disappears entirely; the middle one loses
            # its own last digits to the shift. Together that is under two
            # units in the last place.
            comptime half = (Self.DIGITS + 1) // 2
            var split = decimal128_utility.power_of_10[DType.uint256](half)
            # Through the reciprocal divider, and the remainder derived from
            # the quotient: the plain `//` and `%` are software divides, and
            # four of them made a multiplication cost 370 ns instead of 20.
            var left_high = _drop_digits(self.mantissa, half)
            var left_low = self.mantissa - left_high * split
            var right_high = _drop_digits(other.mantissa, half)
            var right_low = other.mantissa - right_high * split
            var top = (
                left_high
                * right_high
                * decimal128_utility.power_of_10[DType.uint256](
                    2 * half - Self.DIGITS
                )
            )
            var middle = decimal128_utility.udiv_u256_by_pow10_gm(
                left_high * right_low + left_low * right_high,
                Self.DIGITS - half,
            )
            return Self(
                top + middle,
                self.exponent + other.exponent + Self.DIGITS,
                self.sign != other.sign,
            )

    def divide_by_int(self, divisor: Int) raises -> Self:
        """Returns the value divided by a whole number.

        Args:
            divisor: The number to divide by. It may not be zero.

        Returns:
            The quotient, normalized and carrying `DIGITS` digits.

        Raises:
            ValueError: If the divisor is zero.

        Notes:

        The mantissa is raised before the division so that the quotient
        keeps its digits rather than losing them to truncation. How far it
        can be raised depends on the width: at 38 digits there is room for
        another 38, at 75 for only two, which leaves the quotient a unit in
        the last place short of exact. Forty digits below what `Decimal128`
        prints, that does not reach the answer.
        """
        if divisor == 0:
            raise ValueError(
                message="Division by zero.", function="Wide.divide_by_int()"
            )
        if self.is_zero():
            return Self()
        comptime headroom = min(Self.DIGITS, 76 - Self.DIGITS)
        var scaled = self.mantissa * decimal128_utility.power_of_10[
            DType.uint256
        ](headroom)
        return Self(
            decimal128_utility.udiv_u256_by_u64(scaled, UInt64(abs(divisor)))[
                0
            ],
            self.exponent - headroom,
            self.sign != (divisor < 0),
        )

    def __truediv__(self, other: Self) raises -> Self:
        """Returns the quotient of two values.

        Args:
            other: The divisor. It may not be zero.

        Returns:
            The quotient, normalized.

        Raises:
            ValueError: If the divisor is zero.
        """
        if other.is_zero():
            raise ValueError(
                message="Division by zero.", function="Wide.__truediv__()"
            )
        if self.is_zero():
            return Self()

        comptime if Self.DIGITS <= 38:
            var scaled = self.mantissa * decimal128_utility.power_of_10[
                DType.uint256
            ](Self.DIGITS)
            return Self(
                scaled // other.mantissa,
                self.exponent - other.exponent - Self.DIGITS,
                self.sign != other.sign,
            )
        else:
            # A 75-digit dividend cannot be raised by another 75 digits to
            # divide it in one go. Newton doubles a narrow reciprocal
            # instead: `r <- r * (2 - b * r)` takes the 38 correct digits of
            # a `Wide` reciprocal to 76, which is one more than this width
            # holds. Two multiplications, no long division.
            # The iteration works on magnitudes; the sign goes on at the
            # end, or the correction term would be subtracting a negative.
            var positive_other = other.copy()
            positive_other.sign = False
            var narrow = (
                WideValue[38](UInt256(1), 0, False)
                / positive_other.to_width[38]()
            )
            var reciprocal = narrow.to_width[Self.DIGITS]()
            var two = Self.from_int(2)
            reciprocal = reciprocal * (two - positive_other * reciprocal)
            var result = self * reciprocal
            result.sign = self.sign != other.sign
            return result^

    def compare_absolute(self, other: Self) -> Int:
        """Compares the magnitudes of two values.

        Args:
            other: The value to compare against.

        Returns:
            `1` when this one is larger, `-1` when smaller, `0` when equal.
        """
        if self.is_zero():
            return 0 if other.is_zero() else -1
        if other.is_zero():
            return 1
        if self.exponent != other.exponent:
            return 1 if self.exponent > other.exponent else -1
        if self.mantissa == other.mantissa:
            return 0
        return 1 if self.mantissa > other.mantissa else -1

    def to_width[TARGET: Int](self) raises -> WideValue[TARGET]:
        """Returns the same number carried at another width.

        Parameters:
            TARGET: The width to carry it at.

        Returns:
            The value, padded with zeros when the target is wider and
            rounded when it is narrower.

        Raises:
            Error: Propagated from the construction.
        """
        return WideValue[TARGET](self.mantissa, self.exponent, self.sign)

    def scaled_by_power_of_ten(self, places: Int) -> Self:
        """Returns the value multiplied by a power of ten.

        Args:
            places: The power, which may be negative.

        Returns:
            The same digits with the exponent moved, which is exact and costs
            nothing.
        """
        var result = self.copy()
        if not result.is_zero():
            result.exponent += places
        return result^

    def to_int_truncated(self) raises -> Int:
        """Returns the value with everything after the point dropped.

        Returns:
            The whole part, truncated toward zero.

        Raises:
            Error: Propagated from the arithmetic.
        """
        if self.is_zero() or self.exponent <= -Self.DIGITS:
            return 0
        var magnitude: UInt256
        if self.exponent >= 0:
            magnitude = self.mantissa * decimal128_utility.power_of_10[
                DType.uint256
            ](self.exponent)
        else:
            magnitude = _drop_digits(self.mantissa, -self.exponent)
        var value = Int(magnitude)
        return -value if self.sign else value

    def to_int_nearest(self) raises -> Int:
        """Returns the nearest whole number.

        Returns:
            The value rounded to an integer, ties away from zero. Used to
            split an exponent into a whole multiple of `ln(2)` and a small
            remainder, where the multiple is small enough for `Int`.

        Raises:
            Error: Propagated from the arithmetic.
        """
        if self.is_zero():
            return 0
        # Half, to round away from zero by adding before truncating.
        var half = Self(UInt256(5), -1, False)
        if self.sign:
            half = -half
        var shifted = self + half
        if shifted.exponent >= 0:
            var value = Int(
                shifted.mantissa
                * decimal128_utility.power_of_10[DType.uint256](
                    shifted.exponent
                )
            )
            return -value if self.sign else value
        var drop = -shifted.exponent
        var digits = Self.DIGITS
        if drop >= digits:
            return 0
        var value = Int(_drop_digits(shifted.mantissa, drop))
        return -value if self.sign else value

    def rounded_to_integer(self) raises -> Self:
        """Returns the nearest whole number, as a value of the same width.

        Returns:
            The nearest integer, ties away from zero. `to_int_nearest` gives
            the same answer as an `Int`, which stops at 19 digits; the
            argument reduction divides values of 29 digits by a quarter turn
            and needs the whole quotient.

        Raises:
            Error: Propagated from the arithmetic.
        """
        if self.is_zero() or self.exponent >= 0:
            return self.copy()
        var drop = -self.exponent
        if drop > Self.DIGITS:
            return Self()
        # Half a unit added before truncating, which rounds away from zero.
        var half = decimal128_utility.power_of_10[DType.uint256](drop) >> 1
        return Self(_drop_digits(self.mantissa + half, drop), 0, self.sign)

    def integer_remainder(self, modulus: Int) raises -> Int:
        """Returns this whole number modulo a small one.

        Args:
            modulus: The modulus, which must be positive.

        Returns:
            The remainder, always at or above zero, of the magnitude. The
            caller applies the sign.

        Raises:
            Error: Propagated from the arithmetic.

        Notes:
            The value must already be whole. Only the last digits matter, so
            the mantissa is reduced where it stands rather than converted to
            an `Int` it would not fit in.
        """
        if self.is_zero():
            return 0
        var whole = self.mantissa
        if self.exponent < 0:
            whole = _drop_digits(whole, -self.exponent)
        elif self.exponent > 0:
            var shifted = whole % UInt256(modulus)
            for _ in range(self.exponent):
                shifted = (shifted * UInt256(10)) % UInt256(modulus)
            return Int(shifted)
        return Int(whole % UInt256(modulus))

    def to_decimal(self) raises -> Decimal128:
        """Returns the value as a `Decimal128`, rounded once.

        Returns:
            The nearest `Decimal128`, ties to even -- the only rounding in a
            computation that stayed in this type throughout.

        Raises:
            OverflowError: If the value is outside what `Decimal128` holds.
            Error: Propagated from the construction.
        """
        return self.to_decimal_decided(UInt256(0)).value()

    def to_decimal_decided(self, slack: UInt256) raises -> Optional[Decimal128]:
        """Returns the value as a `Decimal128`, or nothing if the digits
        being dropped do not say which way it rounds.

        Args:
            slack: How far the mantissa may be from the true value, in units
                of its last digit. Zero asserts the value is exact and always
                answers.

        Returns:
            The rounded value, or nothing when the answer depends on digits
            this width does not have.

        Raises:
            OverflowError: If the value is outside what `Decimal128` holds.
            Error: Propagated from the construction.

        Notes:
            A computation is trusted to `slack` units in the last place. That
            makes the mantissa an interval, and the interval settles the
            answer unless it straddles a boundary:

            - the midpoint between two neighbouring `Decimal128` values,
              where the rounding itself is in doubt;
            - a whole multiple of the digits being dropped, where the
              rounding is not in doubt but the claim that nothing was lost
              is, and that claim decides whether trailing zeros are kept.

            Three comparisons on the discarded tail, which the rounding
            computes anyway. When they say the width is not enough, the
            caller runs the same computation at `Extended`, which has
            forty-six digits below the answer instead of nine.
        """
        if self.is_zero():
            return Decimal128.ZERO()

        # `Decimal128` is a coefficient and a scale between 0 and 28, so the
        # mantissa has to be brought to an exponent in that range and to no
        # more digits than the type holds.
        var mantissa = self.mantissa
        var exponent = self.exponent

        if exponent > 0:
            # Whole number with trailing zeros: spell them out, if they fit.
            var digits = decimal128_utility.number_of_digits(mantissa)
            if digits + exponent > Decimal128.MAX_NUM_DIGITS:
                raise OverflowError(
                    message="Value too large for Decimal128.",
                    function="WideValue.to_decimal_decided()",
                )
            mantissa *= decimal128_utility.power_of_10[DType.uint256](exponent)
            exponent = 0

        # One rounding, not two. Bringing the scale inside 28 and then the
        # coefficient inside 96 bits used to round twice, and the first
        # rounding could hand the second a tie that the true value does not
        # sit on: `ln(53862.913065970264)` continues `...0954941`, which the
        # first rounding turned into `...0955` and the second carried up to
        # `...096`, one unit above the answer. So the two demands are counted
        # first and the digits go in a single step.
        var scale = -exponent
        var digits = decimal128_utility.number_of_digits(mantissa)
        var room = decimal128_utility.number_of_digits(
            Decimal128.MAX_AS_UINT256
        )

        var drop = 0
        if scale > Decimal128.MAX_SCALE:
            drop = scale - Decimal128.MAX_SCALE
        if digits - drop > room:
            drop = digits - room

        # More digits have to go than there are places after the point, so
        # what is left needs more than 29 digits before it. `tan` of an angle
        # a hair past a pole lands here; the scale used to come out negative
        # and wrap around to four billion.
        if drop > scale:
            raise OverflowError(
                message="Value too large for Decimal128.",
                function="WideValue.to_decimal_decided()",
            )

        var exact = True
        if drop > 0:
            # Dropping every digit is not the same as dropping the value.
            # `ln(1.0000000000000000000000000001)` comes to `9.99...E-29`,
            # whose 38 digits all sit below the smallest scale `Decimal128`
            # has; rounding them says `1E-28`, and returning zero here said
            # zero.
            var kept = decimal128_utility.round_coefficient(
                mantissa, drop, self.sign
            )
            # A coefficient of the right length can still be too large: 29
            # digits reach `9.9E+28` where the type stops at `7.9E+28`. One
            # more digit has to go, and it goes from the original mantissa
            # rather than from this one, so that the value is still rounded
            # only once.
            if kept > Decimal128.MAX_AS_UINT256:
                if scale - drop == 0:
                    raise OverflowError(
                        message="Value too large for Decimal128.",
                        function="WideValue.to_decimal_decided()",
                    )
                drop += 1
                kept = decimal128_utility.round_coefficient(
                    mantissa, drop, self.sign
                )

            if not Self._tail_decides(mantissa, drop, slack):
                return None

            if drop > 77 or (
                kept * decimal128_utility.power_of_10[DType.uint256](drop)
                != mantissa
            ):
                exact = False
            mantissa = kept
            scale -= drop
        elif mantissa > Decimal128.MAX_AS_UINT256:
            raise OverflowError(
                message="Value too large for Decimal128.",
                function="WideValue.to_decimal_decided()",
            )

        # Trailing zeros are dropped only when the value is exact at this
        # width -- when nothing but zeros was rounded away. `log(8, 2)` is
        # three, not 3.0000000000000000000000000000; but the two zeros that
        # end `sqrt(99)` at 29 digits are digits of the answer, since it goes
        # on `...100121`, and dropping them would claim less than is known.
        if exact:
            var strippable = Self._trailing_zeros(mantissa, scale)
            if strippable > 0:
                mantissa = _drop_digits(mantissa, strippable)
                scale -= strippable

        return Decimal128.from_uint128(
            UInt128(mantissa), UInt32(scale), self.sign
        )

    @staticmethod
    def _trailing_zeros(mantissa: UInt256, limit: Int) -> Int:
        """Returns how many zeros the mantissa ends in, up to a limit.

        Args:
            mantissa: The digits.
            limit: The most that may be counted, which for a `Decimal128` is
                the scale -- past that the zeros are before the point and
                belong to the number.

        Returns:
            The count.

        Notes:
            Found by halving rather than by stripping one at a time: a
            `UInt256` divided by a ten it does not know at compile time is a
            software divide of about 185 nanoseconds, and `1.05^12` ends in
            four zeros, which cost more than the twelve multiplications that
            produced it.
        """
        if mantissa == UInt256(0) or limit <= 0:
            return 0
        var count = 0
        var remaining = limit if limit < 77 else 77
        var step = 32
        while step > 0:
            if count + step <= remaining:
                var candidate = count + step
                var unit = decimal128_utility.power_of_10[DType.uint256](
                    candidate
                )
                if _drop_digits(mantissa, candidate) * unit == mantissa:
                    count = candidate
            step >>= 1
        return count

    @staticmethod
    def _tail_decides(mantissa: UInt256, drop: Int, slack: UInt256) -> Bool:
        """Returns whether the digits being dropped settle the rounding.

        Args:
            mantissa: The digits, before rounding.
            drop: How many of them go.
            slack: How far the mantissa may be from the true value, in units
                of its last digit.

        Returns:
            False when the true value could be on either side of the
            midpoint, or on either side of an exact multiple.
        """
        if slack == UInt256(0):
            return True
        if drop > 77:
            # More digits go than any power of ten this reaches; whatever is
            # left is far too close to zero to call.
            return False

        var unit = decimal128_utility.power_of_10[DType.uint256](drop)
        var truncated = _drop_digits(mantissa, drop)
        var remainder = mantissa - truncated * unit

        # Near an exact multiple, from either side: the rounding is clear but
        # the claim that nothing was lost is not, and that claim decides
        # whether the trailing zeros stay. A remainder of exactly zero is no
        # different: with room to be wrong the true value may sit either side
        # of the multiple, so the width that says the value terminates here
        # has to be one that was not given any room.
        if remainder <= slack:
            return False
        if unit - remainder <= slack:
            return False

        # Near the midpoint: the rounding itself is not clear. Doubled, to
        # compare against the unit rather than half of it.
        var doubled = remainder << 1
        if doubled >= unit:
            return doubled - unit > slack << 1
        return unit - doubled > slack << 1


comptime Wide = WideValue[38]
"""The width the series run at.

Ten digits more than `Decimal128` holds, and the widest whose mantissas
multiply inside `UInt256` in one instruction.
"""


comptime Extended = WideValue[75]
"""The width a second attempt runs at.

Reached only when the first attempt cannot say which way the answer rounds.
Forty-six digits past what `Decimal128` keeps, against the nine a `Wide`
has, so a tie the first width could not resolve is resolved here.
"""


# ===----------------------------------------------------------------------=== #
# Constants, at the width the series work in
#
# `Decimal128` holds these to 28 digits, which is what they were multiplied by
# a moment before the answer was rounded: `q * ln(10)` with `q` up to 28 threw
# away more than the answer's last digit was worth. At 38 they do not.
# ===----------------------------------------------------------------------=== #


def wide_ln2() -> Wide:
    """Returns `ln(2)` to 38 digits.

    Returns:
        0.69314718055994530941723212145817656808, the correctly rounded
        value of 0.693147180559945309417232121458176568075500134...
    """
    return Wide(UInt256(69314718055994530941723212145817656808), -38, False)


def wide_ln10() -> Wide:
    """Returns `ln(10)` to 38 digits.

    Returns:
        2.3025850929940456840179914546843642076, the correctly rounded value
        of 2.30258509299404568401799145468436420760110148...
    """
    return Wide(UInt256(23025850929940456840179914546843642076), -37, False)


# ===----------------------------------------------------------------------=== #
# Fixed point, for the series themselves
#
# A `Wide` normalizes after every operation -- counts its digits, shifts,
# rounds -- which a series of forty terms pays forty times over. Inside a
# series none of that is needed: every value there is between -2 and 2, so a
# fixed scale holds them all, an addition is an addition, and a multiplication
# is one division by a constant.
#
# The series run here and hand a `Fixed` back to `Wide` at the end.
# ===----------------------------------------------------------------------=== #

comptime FIXED_SCALE = 37
"""Decimal places a `Fixed` carries.

Values in a series are below two, so the mantissa stays under `2E+37` and the
product of two under `4E+74`, which `Int256` holds.
"""


comptime FIXED_ONE = Int256(10) ** FIXED_SCALE
"""One, in fixed point."""


def fixed_from_wide(value: Wide) raises -> Int256:
    """Returns a `Wide` as a fixed-point value.

    Args:
        value: The value, whose magnitude must be below two.

    Returns:
        Its mantissa at `FIXED_SCALE` decimal places.

    Raises:
        Error: Propagated from the arithmetic.
    """
    if value.is_zero():
        return Int256(0)
    var shift = FIXED_SCALE + value.exponent
    if shift < -FIXED_SCALE:
        # Below what the fixed scale can hold.
        return Int256(0)
    var magnitude: UInt256
    if shift >= 0:
        magnitude = value.mantissa * decimal128_utility.power_of_10[
            DType.uint256
        ](shift)
    else:
        magnitude = decimal128_utility.udiv_u256_by_pow10_gm(
            value.mantissa, -shift
        )
    var result = Int256(magnitude)
    return -result if value.sign else result


def wide_from_fixed(value: Int256) raises -> Wide:
    """Returns a fixed-point value as a `Wide`.

    Args:
        value: The mantissa at `FIXED_SCALE` decimal places.

    Returns:
        The same number, normalized.

    Raises:
        Error: Propagated from the construction.
    """
    if value == Int256(0):
        return Wide()
    var negative = value < Int256(0)
    var magnitude = UInt256(-value if negative else value)
    return Wide(magnitude, -FIXED_SCALE, negative)


@always_inline
def fixed_multiply(left: Int256, right: Int256) -> Int256:
    """Returns the product of two fixed-point values.

    Args:
        left: The first factor.
        right: The second factor.

    Returns:
        Their product, at the same scale. Truncated toward zero rather than
        rounded, which costs less than one unit in the last place of a value
        carrying nine digits more than the answer keeps.

    Notes:
        The scaling division goes through the reciprocal divider, which is
        the whole point of the fixed-point form: a series term costs one
        multiplication and one multiply-high instead of a software divide.
    """
    var negative = (left < Int256(0)) != (right < Int256(0))
    var magnitude = UInt256(abs(left)) * UInt256(abs(right))
    var scaled = Int256(
        decimal128_utility.udiv_u256_by_pow10_gm(magnitude, FIXED_SCALE)
    )
    return -scaled if negative else scaled


@always_inline
def fixed_divide_by_int(value: Int256, divisor: Int) -> Int256:
    """Returns a fixed-point value divided by a small whole number.

    Args:
        value: The dividend.
        divisor: The divisor, which must be positive.

    Returns:
        The quotient, truncated toward zero.
    """
    var negative = value < Int256(0)
    var quotient = Int256(
        decimal128_utility.udiv_u256_by_u64(
            UInt256(abs(value)), UInt64(divisor)
        )[0]
    )
    return -quotient if negative else quotient


# ===----------------------------------------------------------------------=== #
# Precomputed exponentials, to the width a `Wide` carries
#
# `exp` splits its argument into a whole part, two decimal digits, and a
# residual below 0.01, and looks the first three up here. The residual then
# needs about a dozen series terms instead of the thirty-odd a plain
# reduction leaves. `Decimal128` has the same table at its own width; these
# carry ten digits more, so the multiplications that assemble the answer no
# longer decide its last digit.
# ===----------------------------------------------------------------------=== #

comptime _E_POWER_OF_TWO_MANTISSA: Array[UInt256, 7] = [
    27182818284590452353602874713526624978,  # e^1
    73890560989306502272304274605750078132,  # e^2
    54598150033144239078110261202860878403,  # e^4
    29809579870417282747435920994528886738,  # e^8
    88861105205078726367630237407814503508,  # e^16
    78962960182680695160978022635108224220,  # e^32
    62351490808116168829092387089284697448,  # e^64
]


comptime _E_POWER_OF_TWO_EXPONENT: Array[Int, 7] = [
    -37,  # e^1
    -37,  # e^2
    -36,  # e^4
    -34,  # e^8
    -31,  # e^16
    -24,  # e^32
    -10,  # e^64
]


comptime _E_TENTH_MANTISSA: Array[UInt256, 10] = [
    10000000000000000000000000000000000000,  # e^0.0
    11051709180756476248117078264902466682,  # e^0.1
    12214027581601698339210719946396741703,  # e^0.2
    13498588075760031039837443133280073304,  # e^0.3
    14918246976412703178248529528372222806,  # e^0.4
    16487212707001281468486507878141635717,  # e^0.5
    18221188003905089748753676681628645134,  # e^0.6
    20137527074704765216245493885830652700,  # e^0.7
    22255409284924676045795375313950767571,  # e^0.8
    24596031111569496638001265636024706954,  # e^0.9
]


comptime _E_TENTH_EXPONENT: Array[Int, 10] = [
    -37,  # e^0.0
    -37,  # e^0.1
    -37,  # e^0.2
    -37,  # e^0.3
    -37,  # e^0.4
    -37,  # e^0.5
    -37,  # e^0.6
    -37,  # e^0.7
    -37,  # e^0.8
    -37,  # e^0.9
]


comptime _E_HUNDREDTH_MANTISSA: Array[UInt256, 10] = [
    10000000000000000000000000000000000000,  # e^0.00
    10100501670841680575421654569028600338,  # e^0.01
    10202013400267558101601439204831514353,  # e^0.02
    10304545339535168556124399538311981329,  # e^0.03
    10408107741923882267570447579168547441,  # e^0.04
    10512710963760240396975176363356452202,  # e^0.05
    10618365465453596222246848771683723284,  # e^0.06
    10725081812542164790531039498891146056,  # e^0.07
    10832870676749585544359877586748885002,  # e^0.08
    10941742837052103578728976235448860118,  # e^0.09
]


comptime _E_HUNDREDTH_EXPONENT: Array[Int, 10] = [
    -37,  # e^0.00
    -37,  # e^0.01
    -37,  # e^0.02
    -37,  # e^0.03
    -37,  # e^0.04
    -37,  # e^0.05
    -37,  # e^0.06
    -37,  # e^0.07
    -37,  # e^0.08
    -37,  # e^0.09
]


def wide_e_power_of_two(index: Int) -> Wide:
    """Returns `e**(2**index)` to the width a `Wide` carries.

    Args:
        index: The bit position, from 0 to 6. A `Decimal128` overflows above
            `e**66`, so the seven entries cover every whole part.

    Returns:
        The constant.
    """
    ref mantissas = global_constant[_E_POWER_OF_TWO_MANTISSA]()
    ref exponents = global_constant[_E_POWER_OF_TWO_EXPONENT]()
    return Wide(mantissas[index], exponents[index], False)


def wide_e_tenth(digit: Int) -> Wide:
    """Returns `e**(digit / 10)` to the width a `Wide` carries.

    Args:
        digit: The digit, from 0 to 9.

    Returns:
        The constant.
    """
    ref mantissas = global_constant[_E_TENTH_MANTISSA]()
    ref exponents = global_constant[_E_TENTH_EXPONENT]()
    return Wide(mantissas[digit], exponents[digit], False)


def wide_e_hundredth(digit: Int) -> Wide:
    """Returns `e**(digit / 100)` to the width a `Wide` carries.

    Args:
        digit: The digit, from 0 to 9.

    Returns:
        The constant.
    """
    ref mantissas = global_constant[_E_HUNDREDTH_MANTISSA]()
    ref exponents = global_constant[_E_HUNDREDTH_EXPONENT]()
    return Wide(mantissas[digit], exponents[digit], False)


# ===----------------------------------------------------------------------=== #
# The same constants at the second width
#
# Narrowing any of these to 38 digits gives the constant above it, which a
# test checks: one value, written twice, so the second attempt cannot quietly
# disagree with the first.
# ===----------------------------------------------------------------------=== #


def extended_ln2() -> Extended:
    """Returns `ln(2)` to 75 digits.

    Returns:
        The correctly rounded value.
    """
    return Extended(
        UInt256(
            693147180559945309417232121458176568075500134360255254120680009493393621970
        ),
        -75,
        False,
    )


def extended_ln10() -> Extended:
    """Returns `ln(10)` to 75 digits.

    Returns:
        The correctly rounded value.
    """
    return Extended(
        UInt256(
            230258509299404568401799145468436420760110148862877297603332790096757260968
        ),
        -74,
        False,
    )


comptime _EXTENDED_E_POWER_OF_TWO_MANTISSA: Array[UInt256, 7] = [
    271828182845904523536028747135266249775724709369995957496696762772407663035,  # e^1
    738905609893065022723042746057500781318031557055184732408712782252257379608,  # e^2
    545981500331442390781102612028608784027907370386140687258265939585536620999,  # e^4
    298095798704172827474359209945288867375596793913283570220896353038773072517,  # e^8
    888611052050787263676302374078145035080271982185663883978398831704898093732,  # e^16
    789629601826806951609780226351082242199561951153523306550800205987543078540,  # e^32
    623514908081161688290923870892846974483139184623579991438859169901398477629,  # e^64
]


comptime _EXTENDED_E_POWER_OF_TWO_EXPONENT: Array[Int, 7] = [
    -74,  # e^1
    -74,  # e^2
    -73,  # e^4
    -71,  # e^8
    -68,  # e^16
    -61,  # e^32
    -47,  # e^64
]


comptime _EXTENDED_E_TENTH_MANTISSA: Array[UInt256, 10] = [
    100000000000000000000000000000000000000000000000000000000000000000000000000,  # e^0.0
    110517091807564762481170782649024666822454719473751871879286328944096796675,  # e^0.1
    122140275816016983392107199463967417030758094152050364127342509859920623308,  # e^0.2
    134985880757600310398374431332800733037829969735936580304991798993961258740,  # e^0.3
    149182469764127031782485295283722228064328277393742528159563315007236509871,  # e^0.4
    164872127070012814684865078781416357165377610071014801157507931164066102119,  # e^0.5
    182211880039050897487536766816286451338223880854643538632054747658881965030,  # e^0.6
    201375270747047652162454938858306527001754239414586731156898930087978130086,  # e^0.7
    222554092849246760457953753139507675705363413504848459611858395555662261021,  # e^0.8
    245960311115694966380012656360247069542177230644008302074854573665746655294,  # e^0.9
]


comptime _EXTENDED_E_TENTH_EXPONENT: Array[Int, 10] = [
    -74,  # e^0.0
    -74,  # e^0.1
    -74,  # e^0.2
    -74,  # e^0.3
    -74,  # e^0.4
    -74,  # e^0.5
    -74,  # e^0.6
    -74,  # e^0.7
    -74,  # e^0.8
    -74,  # e^0.9
]


comptime _EXTENDED_E_HUNDREDTH_MANTISSA: Array[UInt256, 10] = [
    100000000000000000000000000000000000000000000000000000000000000000000000000,  # e^0.00
    101005016708416805754216545690286003380736220152429251516440403125437419073,  # e^0.01
    102020134002675581016014392048315143530350899119392557727424105598976469800,  # e^0.02
    103045453395351685561243995383119813290502514298822332566994548298465627553,  # e^0.03
    104081077419238822675704475791685474408297705031231203523395718605284804417,  # e^0.04
    105127109637602403969751763633564522017482129605506252878393847916627986965,  # e^0.05
    106183654654535962222468487716837232842826042033007905977294622488557261465,  # e^0.06
    107250818125421647905310394988911460557495897309301363136858199638418466387,  # e^0.07
    108328706767495855443598775867488850019871357283659396897714913615925800957,  # e^0.08
    109417428370521035787289762354488601184651990874708511349553727382967794369,  # e^0.09
]


comptime _EXTENDED_E_HUNDREDTH_EXPONENT: Array[Int, 10] = [
    -74,  # e^0.00
    -74,  # e^0.01
    -74,  # e^0.02
    -74,  # e^0.03
    -74,  # e^0.04
    -74,  # e^0.05
    -74,  # e^0.06
    -74,  # e^0.07
    -74,  # e^0.08
    -74,  # e^0.09
]


def extended_e_power_of_two(index: Int) -> Extended:
    """Returns `e**(2**index)` to 75 digits.

    Args:
        index: The bit position, from 0 to 6.

    Returns:
        The constant.
    """
    ref mantissas = global_constant[_EXTENDED_E_POWER_OF_TWO_MANTISSA]()
    ref exponents = global_constant[_EXTENDED_E_POWER_OF_TWO_EXPONENT]()
    return Extended(mantissas[index], exponents[index], False)


def extended_e_tenth(digit: Int) -> Extended:
    """Returns `e**(digit / 10)` to 75 digits.

    Args:
        digit: The digit, from 0 to 9.

    Returns:
        The constant.
    """
    ref mantissas = global_constant[_EXTENDED_E_TENTH_MANTISSA]()
    ref exponents = global_constant[_EXTENDED_E_TENTH_EXPONENT]()
    return Extended(mantissas[digit], exponents[digit], False)


def extended_e_hundredth(digit: Int) -> Extended:
    """Returns `e**(digit / 100)` to 75 digits.

    Args:
        digit: The digit, from 0 to 9.

    Returns:
        The constant.
    """
    ref mantissas = global_constant[_EXTENDED_E_HUNDREDTH_MANTISSA]()
    ref exponents = global_constant[_EXTENDED_E_HUNDREDTH_EXPONENT]()
    return Extended(mantissas[digit], exponents[digit], False)


# ===----------------------------------------------------------------------=== #
# Reading a constant at whichever width the caller is working in
# ===----------------------------------------------------------------------=== #


def ln2_at[WIDTH: Int]() raises -> WideValue[WIDTH]:
    """Returns `ln(2)` at the given width.

    Parameters:
        WIDTH: The width to return it at.

    Returns:
        The constant.

    Raises:
        Error: Propagated from the construction.
    """
    comptime if WIDTH <= 38:
        return wide_ln2().to_width[WIDTH]()
    else:
        return extended_ln2().to_width[WIDTH]()


def ln10_at[WIDTH: Int]() raises -> WideValue[WIDTH]:
    """Returns `ln(10)` at the given width.

    Parameters:
        WIDTH: The width to return it at.

    Returns:
        The constant.

    Raises:
        Error: Propagated from the construction.
    """
    comptime if WIDTH <= 38:
        return wide_ln10().to_width[WIDTH]()
    else:
        return extended_ln10().to_width[WIDTH]()


def e_power_of_two_at[WIDTH: Int](index: Int) raises -> WideValue[WIDTH]:
    """Returns `e**(2**index)` at the given width.

    Parameters:
        WIDTH: The width to return it at.

    Args:
        index: The bit position, from 0 to 6.

    Returns:
        The constant.

    Raises:
        Error: Propagated from the construction.
    """
    comptime if WIDTH <= 38:
        return wide_e_power_of_two(index).to_width[WIDTH]()
    else:
        return extended_e_power_of_two(index).to_width[WIDTH]()


def e_tenth_at[WIDTH: Int](digit: Int) raises -> WideValue[WIDTH]:
    """Returns `e**(digit / 10)` at the given width.

    Parameters:
        WIDTH: The width to return it at.

    Args:
        digit: The digit, from 0 to 9.

    Returns:
        The constant.

    Raises:
        Error: Propagated from the construction.
    """
    comptime if WIDTH <= 38:
        return wide_e_tenth(digit).to_width[WIDTH]()
    else:
        return extended_e_tenth(digit).to_width[WIDTH]()


def e_hundredth_at[WIDTH: Int](digit: Int) raises -> WideValue[WIDTH]:
    """Returns `e**(digit / 100)` at the given width.

    Parameters:
        WIDTH: The width to return it at.

    Args:
        digit: The digit, from 0 to 9.

    Returns:
        The constant.

    Raises:
        Error: Propagated from the construction.
    """
    comptime if WIDTH <= 38:
        return wide_e_hundredth(digit).to_width[WIDTH]()
    else:
        return extended_e_hundredth(digit).to_width[WIDTH]()
