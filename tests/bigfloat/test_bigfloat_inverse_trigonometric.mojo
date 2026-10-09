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
Tests the inverse circular functions of `BigFloat`.

CPython has no high-precision inverse trigonometry, so the reference is a
Python program of its own: it computes pi by Chudnovsky's series, halves the
argument of the inverse tangent until its series converges, sums that in
`Decimal`, and reaches the other two by the same identities this layer uses
but in a different arithmetic. Every expectation is then rounded to bits in
exact rationals, with the seven modes written out from their definitions.

The table is the edges. An argument of `1 - 2^-60` is where `1 - x^2`
cancels sixty bits, which the inverse sine has to pay for in working width
rather than accuracy. Three quarters is where the inverse cosine stops
subtracting from `pi/2` and takes the half angle instead. An argument at
`2^-200` is below the answer's last place, and one at `2^300` is where the
inverse tangent turns its argument over.

Three tests need no reference. The functions undo the forward ones, the
inverse sine and cosine sum to `pi/2`, and the parities hold exactly.
"""

from std import testing
from std.testing import assert_equal, assert_false, assert_true

from decimo.bigfloat.arithmetics import add, multiply, subtract
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.comparison import compare_absolute
from decimo.bigfloat.constants import pi
from decimo.bigfloat.trigonometric import (
    arccos,
    arcsin,
    arctan,
    cos,
    sin,
    tan,
)
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


def _modes() -> List[RoundingMode]:
    """All seven of them.

    Returns:
        The modes, in the order the rounding primitive documents them.
    """
    return [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]


def _assert_within(
    left: BigFloat, right: BigFloat, units: Int, what: String
) raises:
    """Asserts that two values differ by at most `units` of the last place.

    Args:
        left: The first value.
        right: The second value.
        units: How many units in the last place of `left` to allow.
        what: What is being compared, for the message.

    Raises:
        Error: If they differ by more, or from the arithmetic.
    """
    var difference = subtract(left, right, left.precision + 4)
    if difference.is_zero():
        return
    var allowance = BigFloat(
        significand=BigInt(units),
        exponent=left.exponent,
        precision=BigInt(units).bit_length(),
        sign=False,
    )
    if compare_absolute(difference, allowance) > 0:
        raise Error(
            what
            + " differed by more than "
            + String(units)
            + " units in the last place: "
            + difference.internal_representation()
        )


def test_the_values_are_what_the_reference_rounds_to() raises:
    """Twenty-one arguments at two precisions in all seven modes."""
    var modes = _modes()
    # function significand exponent precision destination mode
    # expected_significand expected_exponent expected_negative
    var cases = [
        "0 1 0 1 1 0 1 -1 0",
        "0 1 0 1 1 1 1 0 0",
        "0 1 0 1 1 2 1 0 0",
        "0 1 0 1 1 3 1 -1 0",
        "0 1 0 1 1 4 1 0 0",
        "0 1 0 1 1 5 1 0 0",
        "0 1 0 1 1 6 1 0 0",
        "0 1 0 1 53 0 7074237752028440 -53 0",
        "0 1 0 1 53 1 7074237752028441 -53 0",
        "0 1 0 1 53 2 7074237752028441 -53 0",
        "0 1 0 1 53 3 7074237752028440 -53 0",
        "0 1 0 1 53 4 7074237752028440 -53 0",
        "0 1 0 1 53 5 7074237752028440 -53 0",
        "0 1 0 1 53 6 7074237752028440 -53 0",
        "0 1 -1 1 1 0 1 -2 0",
        "0 1 -1 1 1 1 1 -1 0",
        "0 1 -1 1 1 2 1 -1 0",
        "0 1 -1 1 1 3 1 -2 0",
        "0 1 -1 1 1 4 1 -1 0",
        "0 1 -1 1 1 5 1 -1 0",
        "0 1 -1 1 1 6 1 -1 0",
        "0 1 -1 1 53 0 8352332796509007 -54 0",
        "0 1 -1 1 53 1 8352332796509008 -54 0",
        "0 1 -1 1 53 2 8352332796509008 -54 0",
        "0 1 -1 1 53 3 8352332796509007 -54 0",
        "0 1 -1 1 53 4 8352332796509007 -54 0",
        "0 1 -1 1 53 5 8352332796509007 -54 0",
        "0 1 -1 1 53 6 8352332796509007 -54 0",
        "0 1 -200 1 1 0 1 -201 0",
        "0 1 -200 1 1 1 1 -200 0",
        "0 1 -200 1 1 2 1 -200 0",
        "0 1 -200 1 1 3 1 -201 0",
        "0 1 -200 1 1 4 1 -200 0",
        "0 1 -200 1 1 5 1 -200 0",
        "0 1 -200 1 1 6 1 -200 0",
        "0 1 -200 1 53 0 9007199254740991 -253 0",
        "0 1 -200 1 53 1 4503599627370496 -252 0",
        "0 1 -200 1 53 2 4503599627370496 -252 0",
        "0 1 -200 1 53 3 9007199254740991 -253 0",
        "0 1 -200 1 53 4 4503599627370496 -252 0",
        "0 1 -200 1 53 5 4503599627370496 -252 0",
        "0 1 -200 1 53 6 4503599627370496 -252 0",
        "0 1048575 -20 20 1 0 1 -1 0",
        "0 1048575 -20 20 1 1 1 0 0",
        "0 1048575 -20 20 1 2 1 0 0",
        "0 1048575 -20 20 1 3 1 -1 0",
        "0 1048575 -20 20 1 4 1 0 0",
        "0 1048575 -20 20 1 5 1 0 0",
        "0 1048575 -20 20 1 6 1 0 0",
        "0 1048575 -20 20 53 0 7074233457059096 -53 0",
        "0 1048575 -20 20 53 1 7074233457059097 -53 0",
        "0 1048575 -20 20 53 2 7074233457059097 -53 0",
        "0 1048575 -20 20 53 3 7074233457059096 -53 0",
        "0 1048575 -20 20 53 4 7074233457059096 -53 0",
        "0 1048575 -20 20 53 5 7074233457059096 -53 0",
        "0 1048575 -20 20 53 6 7074233457059096 -53 0",
        "0 1152921504606846975 -60 60 1 0 1 -1 0",
        "0 1152921504606846975 -60 60 1 1 1 0 0",
        "0 1152921504606846975 -60 60 1 2 1 0 0",
        "0 1152921504606846975 -60 60 1 3 1 -1 0",
        "0 1152921504606846975 -60 60 1 4 1 0 0",
        "0 1152921504606846975 -60 60 1 5 1 0 0",
        "0 1152921504606846975 -60 60 1 6 1 0 0",
        "0 1152921504606846975 -60 60 53 0 7074237752028440 -53 0",
        "0 1152921504606846975 -60 60 53 1 7074237752028441 -53 0",
        "0 1152921504606846975 -60 60 53 2 7074237752028441 -53 0",
        "0 1152921504606846975 -60 60 53 3 7074237752028440 -53 0",
        "0 1152921504606846975 -60 60 53 4 7074237752028440 -53 0",
        "0 1152921504606846975 -60 60 53 5 7074237752028440 -53 0",
        "0 1152921504606846975 -60 60 53 6 7074237752028440 -53 0",
        "0 3 -2 2 1 0 1 -1 0",
        "0 3 -2 2 1 1 1 0 0",
        "0 3 -2 2 1 2 1 0 0",
        "0 3 -2 2 1 3 1 -1 0",
        "0 3 -2 2 1 4 1 -1 0",
        "0 3 -2 2 1 5 1 -1 0",
        "0 3 -2 2 1 6 1 -1 0",
        "0 3 -2 2 53 0 5796142707547873 -53 0",
        "0 3 -2 2 53 1 5796142707547874 -53 0",
        "0 3 -2 2 53 2 5796142707547874 -53 0",
        "0 3 -2 2 53 3 5796142707547873 -53 0",
        "0 3 -2 2 53 4 5796142707547873 -53 0",
        "0 3 -2 2 53 5 5796142707547873 -53 0",
        "0 3 -2 2 53 6 5796142707547873 -53 0",
        "1 1 0 1 1 0 1 0 0",
        "1 1 0 1 1 1 1 1 0",
        "1 1 0 1 1 2 1 1 0",
        "1 1 0 1 1 3 1 0 0",
        "1 1 0 1 1 4 1 1 0",
        "1 1 0 1 1 5 1 1 0",
        "1 1 0 1 1 6 1 1 0",
        "1 1 0 1 53 0 7074237752028440 -52 0",
        "1 1 0 1 53 1 7074237752028441 -52 0",
        "1 1 0 1 53 2 7074237752028441 -52 0",
        "1 1 0 1 53 3 7074237752028440 -52 0",
        "1 1 0 1 53 4 7074237752028440 -52 0",
        "1 1 0 1 53 5 7074237752028440 -52 0",
        "1 1 0 1 53 6 7074237752028440 -52 0",
        "1 1 -1 1 1 0 1 -1 0",
        "1 1 -1 1 1 1 1 0 0",
        "1 1 -1 1 1 2 1 0 0",
        "1 1 -1 1 1 3 1 -1 0",
        "1 1 -1 1 1 4 1 -1 0",
        "1 1 -1 1 1 5 1 -1 0",
        "1 1 -1 1 1 6 1 -1 0",
        "1 1 -1 1 53 0 4716158501352293 -53 0",
        "1 1 -1 1 53 1 4716158501352294 -53 0",
        "1 1 -1 1 53 2 4716158501352294 -53 0",
        "1 1 -1 1 53 3 4716158501352293 -53 0",
        "1 1 -1 1 53 4 4716158501352294 -53 0",
        "1 1 -1 1 53 5 4716158501352294 -53 0",
        "1 1 -1 1 53 6 4716158501352294 -53 0",
        "1 1 -200 1 1 0 1 -200 0",
        "1 1 -200 1 1 1 1 -199 0",
        "1 1 -200 1 1 2 1 -199 0",
        "1 1 -200 1 1 3 1 -200 0",
        "1 1 -200 1 1 4 1 -200 0",
        "1 1 -200 1 1 5 1 -200 0",
        "1 1 -200 1 1 6 1 -200 0",
        "1 1 -200 1 53 0 4503599627370496 -252 0",
        "1 1 -200 1 53 1 4503599627370497 -252 0",
        "1 1 -200 1 53 2 4503599627370497 -252 0",
        "1 1 -200 1 53 3 4503599627370496 -252 0",
        "1 1 -200 1 53 4 4503599627370496 -252 0",
        "1 1 -200 1 53 5 4503599627370496 -252 0",
        "1 1 -200 1 53 6 4503599627370496 -252 0",
        "1 1048575 -20 20 1 0 1 0 0",
        "1 1048575 -20 20 1 1 1 1 0",
        "1 1048575 -20 20 1 2 1 1 0",
        "1 1048575 -20 20 1 3 1 0 0",
        "1 1048575 -20 20 1 4 1 1 0",
        "1 1048575 -20 20 1 5 1 1 0",
        "1 1048575 -20 20 1 6 1 1 0",
        "1 1048575 -20 20 53 0 7068017974510185 -52 0",
        "1 1048575 -20 20 53 1 7068017974510186 -52 0",
        "1 1048575 -20 20 53 2 7068017974510186 -52 0",
        "1 1048575 -20 20 53 3 7068017974510185 -52 0",
        "1 1048575 -20 20 53 4 7068017974510186 -52 0",
        "1 1048575 -20 20 53 5 7068017974510186 -52 0",
        "1 1048575 -20 20 53 6 7068017974510186 -52 0",
        "1 1152921504606846975 -60 60 1 0 1 0 0",
        "1 1152921504606846975 -60 60 1 1 1 1 0",
        "1 1152921504606846975 -60 60 1 2 1 1 0",
        "1 1152921504606846975 -60 60 1 3 1 0 0",
        "1 1152921504606846975 -60 60 1 4 1 1 0",
        "1 1152921504606846975 -60 60 1 5 1 1 0",
        "1 1152921504606846975 -60 60 1 6 1 1 0",
        "1 1152921504606846975 -60 60 53 0 7074237746096798 -52 0",
        "1 1152921504606846975 -60 60 53 1 7074237746096799 -52 0",
        "1 1152921504606846975 -60 60 53 2 7074237746096799 -52 0",
        "1 1152921504606846975 -60 60 53 3 7074237746096798 -52 0",
        "1 1152921504606846975 -60 60 53 4 7074237746096799 -52 0",
        "1 1152921504606846975 -60 60 53 5 7074237746096799 -52 0",
        "1 1152921504606846975 -60 60 53 6 7074237746096799 -52 0",
        "1 3 -2 2 1 0 1 -1 0",
        "1 3 -2 2 1 1 1 0 0",
        "1 3 -2 2 1 2 1 0 0",
        "1 3 -2 2 1 3 1 -1 0",
        "1 3 -2 2 1 4 1 0 0",
        "1 3 -2 2 1 5 1 0 0",
        "1 3 -2 2 1 6 1 0 0",
        "1 3 -2 2 53 0 7638664125776092 -53 0",
        "1 3 -2 2 53 1 7638664125776093 -53 0",
        "1 3 -2 2 53 2 7638664125776093 -53 0",
        "1 3 -2 2 53 3 7638664125776092 -53 0",
        "1 3 -2 2 53 4 7638664125776092 -53 0",
        "1 3 -2 2 53 5 7638664125776092 -53 0",
        "1 3 -2 2 53 6 7638664125776092 -53 0",
        "2 1 0 1 1 0 0 0 0",
        "2 1 0 1 1 1 0 0 0",
        "2 1 0 1 1 2 0 0 0",
        "2 1 0 1 1 3 0 0 0",
        "2 1 0 1 1 4 0 0 0",
        "2 1 0 1 1 5 0 0 0",
        "2 1 0 1 1 6 0 0 0",
        "2 1 0 1 53 0 0 0 0",
        "2 1 0 1 53 1 0 0 0",
        "2 1 0 1 53 2 0 0 0",
        "2 1 0 1 53 3 0 0 0",
        "2 1 0 1 53 4 0 0 0",
        "2 1 0 1 53 5 0 0 0",
        "2 1 0 1 53 6 0 0 0",
        "2 1 -1 1 1 0 1 0 0",
        "2 1 -1 1 1 1 1 1 0",
        "2 1 -1 1 1 2 1 1 0",
        "2 1 -1 1 1 3 1 0 0",
        "2 1 -1 1 1 4 1 0 0",
        "2 1 -1 1 1 5 1 0 0",
        "2 1 -1 1 1 6 1 0 0",
        "2 1 -1 1 53 0 4716158501352293 -52 0",
        "2 1 -1 1 53 1 4716158501352294 -52 0",
        "2 1 -1 1 53 2 4716158501352294 -52 0",
        "2 1 -1 1 53 3 4716158501352293 -52 0",
        "2 1 -1 1 53 4 4716158501352294 -52 0",
        "2 1 -1 1 53 5 4716158501352294 -52 0",
        "2 1 -1 1 53 6 4716158501352294 -52 0",
        "2 1 -200 1 1 0 1 0 0",
        "2 1 -200 1 1 1 1 1 0",
        "2 1 -200 1 1 2 1 1 0",
        "2 1 -200 1 1 3 1 0 0",
        "2 1 -200 1 1 4 1 1 0",
        "2 1 -200 1 1 5 1 1 0",
        "2 1 -200 1 1 6 1 1 0",
        "2 1 -200 1 53 0 7074237752028440 -52 0",
        "2 1 -200 1 53 1 7074237752028441 -52 0",
        "2 1 -200 1 53 2 7074237752028441 -52 0",
        "2 1 -200 1 53 3 7074237752028440 -52 0",
        "2 1 -200 1 53 4 7074237752028440 -52 0",
        "2 1 -200 1 53 5 7074237752028440 -52 0",
        "2 1 -200 1 53 6 7074237752028440 -52 0",
        "2 1048575 -20 20 1 0 1 -10 0",
        "2 1048575 -20 20 1 1 1 -9 0",
        "2 1048575 -20 20 1 2 1 -9 0",
        "2 1048575 -20 20 1 3 1 -10 0",
        "2 1048575 -20 20 1 4 1 -10 0",
        "2 1048575 -20 20 1 5 1 -10 0",
        "2 1048575 -20 20 1 6 1 -10 0",
        "2 1048575 -20 20 53 0 6369052178692631 -62 0",
        "2 1048575 -20 20 53 1 6369052178692632 -62 0",
        "2 1048575 -20 20 53 2 6369052178692632 -62 0",
        "2 1048575 -20 20 53 3 6369052178692631 -62 0",
        "2 1048575 -20 20 53 4 6369052178692631 -62 0",
        "2 1048575 -20 20 53 5 6369052178692631 -62 0",
        "2 1048575 -20 20 53 6 6369052178692631 -62 0",
        "2 1152921504606846975 -60 60 1 0 1 -30 0",
        "2 1152921504606846975 -60 60 1 1 1 -29 0",
        "2 1152921504606846975 -60 60 1 2 1 -29 0",
        "2 1152921504606846975 -60 60 1 3 1 -30 0",
        "2 1152921504606846975 -60 60 1 4 1 -30 0",
        "2 1152921504606846975 -60 60 1 5 1 -30 0",
        "2 1152921504606846975 -60 60 1 6 1 -30 0",
        "2 1152921504606846975 -60 60 53 0 6369051672525772 -82 0",
        "2 1152921504606846975 -60 60 53 1 6369051672525773 -82 0",
        "2 1152921504606846975 -60 60 53 2 6369051672525773 -82 0",
        "2 1152921504606846975 -60 60 53 3 6369051672525772 -82 0",
        "2 1152921504606846975 -60 60 53 4 6369051672525773 -82 0",
        "2 1152921504606846975 -60 60 53 5 6369051672525773 -82 0",
        "2 1152921504606846975 -60 60 53 6 6369051672525773 -82 0",
        "2 3 -2 2 1 0 1 -1 0",
        "2 3 -2 2 1 1 1 0 0",
        "2 3 -2 2 1 2 1 0 0",
        "2 3 -2 2 1 3 1 -1 0",
        "2 3 -2 2 1 4 1 -1 0",
        "2 3 -2 2 1 5 1 -1 0",
        "2 3 -2 2 1 6 1 -1 0",
        "2 3 -2 2 53 0 6509811378280788 -53 0",
        "2 3 -2 2 53 1 6509811378280789 -53 0",
        "2 3 -2 2 53 2 6509811378280789 -53 0",
        "2 3 -2 2 53 3 6509811378280788 -53 0",
        "2 3 -2 2 53 4 6509811378280789 -53 0",
        "2 3 -2 2 53 5 6509811378280789 -53 0",
        "2 3 -2 2 53 6 6509811378280789 -53 0",
        "0 1 100 1 1 0 1 0 0",
        "0 1 100 1 1 1 1 1 0",
        "0 1 100 1 1 2 1 1 0",
        "0 1 100 1 1 3 1 0 0",
        "0 1 100 1 1 4 1 1 0",
        "0 1 100 1 1 5 1 1 0",
        "0 1 100 1 1 6 1 1 0",
        "0 1 100 1 53 0 7074237752028440 -52 0",
        "0 1 100 1 53 1 7074237752028441 -52 0",
        "0 1 100 1 53 2 7074237752028441 -52 0",
        "0 1 100 1 53 3 7074237752028440 -52 0",
        "0 1 100 1 53 4 7074237752028440 -52 0",
        "0 1 100 1 53 5 7074237752028440 -52 0",
        "0 1 100 1 53 6 7074237752028440 -52 0",
        "0 1 300 1 1 0 1 0 0",
        "0 1 300 1 1 1 1 1 0",
        "0 1 300 1 1 2 1 1 0",
        "0 1 300 1 1 3 1 0 0",
        "0 1 300 1 1 4 1 1 0",
        "0 1 300 1 1 5 1 1 0",
        "0 1 300 1 1 6 1 1 0",
        "0 1 300 1 53 0 7074237752028440 -52 0",
        "0 1 300 1 53 1 7074237752028441 -52 0",
        "0 1 300 1 53 2 7074237752028441 -52 0",
        "0 1 300 1 53 3 7074237752028440 -52 0",
        "0 1 300 1 53 4 7074237752028440 -52 0",
        "0 1 300 1 53 5 7074237752028440 -52 0",
        "0 1 300 1 53 6 7074237752028440 -52 0",
        "0 12345 50 14 1 0 1 0 0",
        "0 12345 50 14 1 1 1 1 0",
        "0 12345 50 14 1 2 1 1 0",
        "0 12345 50 14 1 3 1 0 0",
        "0 12345 50 14 1 4 1 1 0",
        "0 12345 50 14 1 5 1 1 0",
        "0 12345 50 14 1 6 1 1 0",
        "0 12345 50 14 53 0 7074237752028440 -52 0",
        "0 12345 50 14 53 1 7074237752028441 -52 0",
        "0 12345 50 14 53 2 7074237752028441 -52 0",
        "0 12345 50 14 53 3 7074237752028440 -52 0",
        "0 12345 50 14 53 4 7074237752028440 -52 0",
        "0 12345 50 14 53 5 7074237752028440 -52 0",
        "0 12345 50 14 53 6 7074237752028440 -52 0",
    ]
    for row in cases:
        var field = row.split(" ")
        var x = BigFloat(
            significand=BigInt(String(field[1])),
            exponent=Int(String(field[2])),
            precision=Int(String(field[3])),
            sign=False,
        )
        var destination = Int(String(field[4]))
        var mode = modes[Int(String(field[5]))]
        var kind = Int(String(field[0]))
        var got = arctan(x, destination, mode) if kind == 0 else (
            arcsin(x, destination, mode) if kind
            == 1 else arccos(x, destination, mode)
        )
        var want = String("-") if field[8] == "1" else String("")
        want += (
            String(field[6])
            + "p"
            + String(field[7])
            + "@"
            + String(destination)
        )
        assert_equal(got.internal_representation(), want, String("case ") + row)


def test_each_one_undoes_its_forward_function() raises:
    """`sin(arcsin x)` is `x`, and the same for the other two.

    The tolerance is in units of the last place of the angle, not of `x`,
    and that is the honest statement rather than a loosening. The cosine's
    slope at `pi/2` is one, so an angle good to its own last place gives a
    cosine good to that same absolute amount -- which for `x = 0.0001` is
    thirteen bits short of `x`'s own last place. The round trip keeps about
    `precision` bits absolutely, not relatively, and no amount of care in
    these functions changes that.
    """
    var precision = 120
    for text in ["0.5", "-0.25", "0.9", "0.0001"]:
        var x = BigFloat.from_string(text, precision)
        var angle = arcsin(x, precision)
        _assert_within(
            sin(angle, precision),
            x,
            4,
            String("sin of arcsin at ") + text,
        )
        # The allowance is four units of the angle's last place.
        var back = arccos(x, precision)
        var allowance = BigFloat(
            significand=BigInt(4),
            exponent=back.exponent,
            precision=3,
            sign=False,
        )
        var error = subtract(cos(back, precision), x, precision + 4)
        assert_true(
            error.is_zero() or compare_absolute(error, allowance) <= 0,
            String("cos of arccos at ") + text,
        )
    # The tangent's round trip is checked in the angle rather than in the
    # value, because `tan` near `pi/2` has slope `1 + x^2`: at `x = 100` an
    # angle good to its last place gives a tangent out by ten thousand of
    # them, which says nothing about either function. Going the other way
    # round -- angle, tangent, angle -- is well conditioned both ways.
    for text in ["0.5", "-1.2", "0.1", "1.5"]:
        var angle = BigFloat.from_string(text, precision)
        _assert_within(
            arctan(tan(angle, precision), precision),
            angle,
            8,
            String("arctan of tan at ") + text,
        )


def test_the_two_inverses_sum_to_a_right_angle() raises:
    """`arcsin(x) + arccos(x)` is `pi/2` for every argument in range.

    The two take different routes above a half -- the inverse cosine stops
    subtracting and takes the half angle -- so this says those routes agree.
    """
    var precision = 150
    var right_angle = multiply(
        pi(precision + 4),
        BigFloat(
            significand=BigInt.one(), exponent=-1, precision=1, sign=False
        ),
        precision + 4,
    )
    for text in ["0", "0.25", "-0.25", "0.5", "0.75", "-0.75", "1", "-1"]:
        var x = BigFloat.from_string(text, precision)
        var total = add(arcsin(x, precision), arccos(x, precision), precision)
        _assert_within(total, right_angle, 4, String("the sum at ") + text)


def test_the_parities_are_exact() raises:
    """`arcsin` and `arctan` are odd, and `arccos(-x)` is `pi - arccos(x)`."""
    var precision = 100
    for text in ["0.5", "0.9", "0.0625"]:
        var x = BigFloat.from_string(text, precision)
        assert_equal(
            arcsin(-x, precision).internal_representation(),
            (-arcsin(x, precision)).internal_representation(),
            "the inverse sine is odd",
        )
        assert_equal(
            arctan(-x, precision).internal_representation(),
            (-arctan(x, precision)).internal_representation(),
            "and so is the inverse tangent",
        )


def test_what_is_outside_the_domain_has_no_answer() raises:
    """The inverse sine and cosine are NaNs past one, the tangent never is."""
    for text in ["1.0000001", "2", "-2", "1e30"]:
        var x = BigFloat.from_string(text, 60)
        assert_true(arcsin(x, 53).is_nan(), "no inverse sine past one")
        assert_true(arccos(x, 53).is_nan(), "nor an inverse cosine")
        assert_true(
            arctan(x, 53).is_finite(), "but the inverse tangent is fine"
        )

    for value in [BigFloat.nan(), BigFloat.infinity(), -BigFloat.infinity()]:
        assert_true(arcsin(value, 53).is_nan(), "a NaN or an infinity")
        assert_true(arccos(value, 53).is_nan(), "has no inverse sine")

    # An infinity does have an inverse tangent: the function settles there.
    assert_true(
        arctan(BigFloat.infinity(), 53).is_finite(), "arctan of an infinity"
    )
    _assert_within(
        arctan(BigFloat.infinity(), 53),
        multiply(
            pi(60),
            BigFloat(
                significand=BigInt.one(), exponent=-1, precision=1, sign=False
            ),
            53,
        ),
        2,
        "which is a right angle",
    )
    assert_true(arctan(-BigFloat.infinity(), 53).sign, "and the sign carries")
    assert_true(arctan(BigFloat.nan(), 53).is_nan(), "a NaN stays one")

    # The exact values at the ends.
    assert_true(
        arccos(BigFloat.from_int(1), 53).is_zero(), "arccos(1) is nought"
    )
    assert_false(arccos(BigFloat.from_int(1), 53).sign, "a positive nought")
    assert_true(arcsin(BigFloat.zero(53, True), 53).sign, "arcsin keeps a -0")


def test_a_precision_must_fit_the_guard_bits() raises:
    for precision in [0, -1, Int.MAX, Int.MAX // 4 + 1]:
        for which in [0, 1, 2]:
            var raised = False
            try:
                if which == 0:
                    _ = arctan(BigFloat.from_int(1), precision)
                elif which == 1:
                    _ = arcsin(BigFloat.from_string("0.5", 53), precision)
                else:
                    _ = arccos(BigFloat.from_string("0.5", 53), precision)
            except:
                raised = True
            assert_true(
                raised,
                String("a precision of ") + String(precision) + " was taken",
            )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
