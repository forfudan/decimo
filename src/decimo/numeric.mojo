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
`BigInt`, `BigDecimal` and `Decimal128` alike --- a matrix library being the
motivating case. Mojo's trait conformance is nominal and has to be declared
where the struct is defined, so the traits live here rather than in the
consumer.

One trait covers `BigInt`, `BigDecimal` and `Decimal128` alike, division
included. Integer division is closed as long as it is understood the way Mojo's
own `Int` understands it: `/` truncates toward zero and stays in the type, and
`//` --- which floors, and so differs whenever the signs differ --- is a
separate operator that this trait does not require.

Every operation is declared `raises`, which is the widest signature: a
non-raising implementation satisfies a raising requirement, so `BigInt.__add__`
conforms unchanged while `BigDecimal.__add__` -- which really can raise --
conforms too.
"""


trait Numeric(Copyable, Deinitable, Writable):
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
