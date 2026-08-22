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

"""
Traits describing what Decimo's number types can do.

These exist so that code outside Decimo can be written once and run over
`BigInt`, `BigDecimal` and `Decimal128` alike - a matrix library being the
motivating case. Mojo's trait conformance is nominal and has to be declared
where the struct is defined, so the traits live here rather than in the
consumer.

`Numeric` covers `BigInt`, `BigDecimal` and `Decimal128` alike, division
included. Integer division is closed as long as it is understood the way Mojo's
own `Int` understands it: `/` truncates toward zero and stays in the type, and
`//` (which floors, and so differs whenever the signs differ) is a
separate operator that this trait does not require.

`Parsable` is separate from `Numeric` because the two capabilities are
independent. `BigFloat` parses but is `Movable` without being `Copyable`, so it
can never be `Numeric`; a numeric type with no decimal spelling is equally
imaginable. Splitting them lets each consumer ask for what it actually uses.

`Rootable` is separate for the same reason, and the evidence is sharper. Two
types here have a square root and can never be `Numeric`: `BigFloat`, again for
want of `Copyable`, and `BigUInt`, which is unsigned and so has no `__neg__`.
Folding `sqrt` into `Numeric` would leave both unable to advertise a capability
they demonstrably have, and would oblige every future numeric type to grow one.
A consumer that needs both asks for `T: Numeric & Rootable`.

Every operation is declared `raises`, which is the widest signature: a
non-raising implementation satisfies a raising requirement, so `BigInt.__add__`
conforms unchanged while `BigDecimal.__add__` -- which really can raise --
conforms too.

`Movable` sits alongside `Copyable` in the supertraits because every method
here hands back an owned `Self`. A caller that stores such a result, or returns
it onward, moves it; without the bound each consumer would have to spell
`T: Numeric & Movable` to do the obvious thing with a result. The two are
separate capabilities in this codebase (`BigFloat` is `Movable` but not
`Copyable`) so requiring both is a real statement, and one all three
conforming types already satisfy.
"""


trait Numeric(Copyable, Deinitable, Movable, Writable):
    """A type closed under addition, subtraction and multiplication.

    Enough for the whole of dense linear algebra: matrix addition, scaling,
    multiplication, a trace, and the elimination algorithms that divide.
    """

    @staticmethod
    def zero() -> Self:
        """Returns the additive identity.

        Returns:
            The value that leaves any other unchanged under addition.
        """
        ...

    @staticmethod
    def one() -> Self:
        """Returns the multiplicative identity.

        Returns:
            The value that leaves any other unchanged under multiplication.
        """
        ...

    def __neg__(self) raises -> Self:
        """Returns the additive inverse.

        Returns:
            The value that sums with `self` to `zero()`.

        Raises:
            Error: If the negation is not representable in this type.
        """
        ...

    def __add__(self, other: Self) raises -> Self:
        """Returns the sum of `self` and `other`.

        Args:
            other: The value to add to `self`.

        Returns:
            The sum of `self` and `other`.

        Raises:
            Error: If the sum is not representable in this type.
        """
        ...

    def __sub__(self, other: Self) raises -> Self:
        """Returns `other` subtracted from `self`.

        Args:
            other: The value to subtract from `self`.

        Returns:
            The difference of `self` and `other`.

        Raises:
            Error: If the difference is not representable in this type.
        """
        ...

    def __mul__(self, other: Self) raises -> Self:
        """Returns the product of `self` and `other`.

        Args:
            other: The value to multiply `self` by.

        Returns:
            The product of `self` and `other`.

        Raises:
            Error: If the product is not representable in this type.
        """
        ...

    def __truediv__(self, other: Self) raises -> Self:
        """Returns `self` divided by `other`.

        On an integral type this truncates toward zero, as `Int` does.

        Args:
            other: The divisor.

        Returns:
            The quotient of `self` and `other`.

        Raises:
            Error: If `other` is zero, or the quotient is not representable in
                this type.
        """
        ...


trait Rootable(Deinitable, Movable):
    """A type that can take the square root of one of its values.

    The bound that a Cholesky or QR factorisation needs, and nothing more. It
    is deliberately narrow: `sqrt` is the only operation dense linear algebra
    asks for, so it is the only one required here.

    What the root means is the implementing type's business. On an integral
    type it truncates -- `BigInt("10").sqrt()` is `3` -- exactly as
    `Numeric.__truediv__` truncates there. A negative value is the type's
    business too: four of the five implementations raise, and `BigFloat`
    returns `nan`, because it has a `nan` and every other function it offers
    returns one there as well. A caller that cannot accept either should bound
    on a type that does not do it.

    The supertraits are `Deinitable` and `Movable`, and no more. `sqrt` hands
    back an owned `Self`, so a caller that stores or returns that result moves
    it, and something has to destroy it. `Copyable` is pointedly absent:
    `BigFloat` is `Movable` without it, and requiring it would exclude a type
    that has had a square root all along.
    """

    def sqrt(self) raises -> Self:
        """Returns the square root of `self`.

        Returns:
            The non-negative value whose square is `self`, exact where the
            type can represent it. Where it cannot, the rule is the
            implementation's own: an integral type truncates, a decimal or
            floating type rounds at its working precision.

        Raises:
            Error: If `self` is negative and the type has no value standing
                for a root it cannot give, or if the root is not
                representable. A type that has such a value returns it
                instead -- `BigFloat("-4").sqrt()` is `nan` -- so generic
                code must tolerate either outcome.
        """
        ...


trait Parsable:
    """A type that can be built from its decimal string form.

    The counterpart of `Writable`: `Parsable` reads a number back out of the
    text that `write_to` produced. It is what lets a container be filled from a
    literal - a matrix parsed out of `"[[1.1, 2.2], [3.3, 4.4]]"` - without the
    container knowing which number type it holds.
    """

    @staticmethod
    def from_string(value: String) raises -> Self:
        """Returns the value the decimal literal `value` denotes.

        Args:
            value: The decimal literal to parse.

        Returns:
            The parsed value.

        Raises:
            Error: If `value` is not a decimal literal this type accepts.
        """
        ...
