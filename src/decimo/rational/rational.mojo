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

from decimo.bigint.bigint import BigInt
from decimo.bigint.number_theory import gcd
from decimo.bigint.arithmetics import absolute, negative
from decimo.bigint.comparison import compare_magnitudes
from decimo.errors import ValueError, ZeroDivisionError


struct Rational(
    Absable,
    Comparable,
    Copyable,
    Movable,
    Writable,
):
    """An arbitrary-precision exact rational number p/q.

    The fraction is always stored in lowest terms with a positive denominator.
    """

    var numerator: BigInt
    """The numerator of the rational number."""
    var denominator: BigInt
    """The denominator of the rational number. Always positive."""

    # ===------------------------------------------------------------------=== #
    # Constants
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def zero() -> Self:
        """Returns the value 0/1.

        Returns:
            A Rational representing zero.
        """
        return Self(BigInt(), BigInt(UInt32(1)), raw=True)

    @staticmethod
    def one() -> Self:
        """Returns the value 1/1.

        Returns:
            A Rational representing one.
        """
        return Self(BigInt(UInt32(1)), BigInt(UInt32(1)), raw=True)

    @staticmethod
    def two() -> Self:
        """Returns the value 2/1.

        Returns:
            A Rational representing two.
        """
        return Self(BigInt(UInt32(2)), BigInt(UInt32(1)), raw=True)

    @staticmethod
    def minus_one() -> Self:
        """Returns the value -1/1.

        Returns:
            A Rational representing minus one.
        """
        return Self(BigInt(UInt32(-1)), BigInt(UInt32(1)), raw=True)

    @staticmethod
    def one_half() -> Self:
        """Returns the value 1/2.

        Returns:
            A Rational representing one half.
        """
        return Self(BigInt(UInt32(1)), BigInt(UInt32(2)), raw=True)

    @staticmethod
    def one_third() -> Self:
        """Returns the value 1/3.

        Returns:
            A Rational representing one third.
        """
        return Self(BigInt(UInt32(1)), BigInt(UInt32(3)), raw=True)

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

    def __init__(out self, value: Int):
        """Initializes a rational number from an Int (denominator = 1).

        Args:
            value: The integer value.
        """
        self.numerator = BigInt(value)
        self.denominator = BigInt(UInt32(1))

    def __init__(
        out self, var numerator: BigInt, var denominator: BigInt, *, raw: Bool
    ):
        """Initializes a Rational without normalization.
        Caller must ensure the invariants hold.

        Args:
            numerator: The numerator (already in lowest terms).
            denominator: The denominator (already positive, coprime with numerator).
            raw: This is a raw constructor wihtout normalization.
                Caller must ensure invariants.

        Returns:
            A new Rational.
        """
        self.numerator = numerator^
        self.denominator = denominator^

    # TODO:
    # Initializes a Rational from a integral scalar, from_scalar()
    # Initialzies a Rational from a decimal string, from_decimal()
    # Initializes a Rational from a string like "123/456", from_string()
    # Initializes a Rational from a float, from_float(). Do not make it `__init__`.
    #   Note that float can be converted to rational exactly by interpreting
    #   its bits as a fraction of binary integers.
    #   Maybe we can use it as a bridge Float -> Rational -> Decimal conversion,
    #   so that we do not need the Float -> String -> Decimal path.

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
        return String.write(self)

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
        """
        var num = (
            self.numerator * other.denominator
            - other.numerator * self.denominator
        )
        var den = self.denominator * other.denominator
        return Self(num, den)

    def __mul__(self, other: Self) raises -> Self:
        """Returns self * other.

        Uses the formula: (a/b) * (c/d) = (a*c) / (b*d),
        then normalizes to lowest terms.

        Args:
            other: The other rational.

        Returns:
            The product.
        """
        var num = self.numerator * other.numerator
        var den = self.denominator * other.denominator
        return Self(num, den)

    def __truediv__(self, other: Self) raises -> Self:
        """Returns self / other.

        Uses the formula: (a/b) / (c/d) = (a*d) / (b*c).

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
        var num = self.numerator * other.denominator
        var den = self.denominator * other.numerator
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
