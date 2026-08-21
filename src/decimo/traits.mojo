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
        """Returns the additive identity."""
        ...

    @staticmethod
    def one() -> Self:
        """Returns the multiplicative identity."""
        ...

    def __neg__(self) raises -> Self:
        """Returns the additive inverse."""
        ...

    def __add__(self, other: Self) raises -> Self:
        """Returns the sum of `self` and `other`."""
        ...

    def __sub__(self, other: Self) raises -> Self:
        """Returns `other` subtracted from `self`."""
        ...

    def __mul__(self, other: Self) raises -> Self:
        """Returns the product of `self` and `other`."""
        ...

    def __truediv__(self, other: Self) raises -> Self:
        """Returns `self` divided by `other`.

        On an integral type this truncates toward zero, as `Int` does.
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
