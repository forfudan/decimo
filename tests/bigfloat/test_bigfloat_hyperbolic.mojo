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
Tests the hyperbolic functions of `BigFloat`, and their inverses.

The reference is CPython's `decimal`, through identities over its `exp`, `ln`
and `sqrt` alone. Each identity is picked so that the reference does not
cancel where the function under test does not either -- `arccosh` near one
goes through `t = x - 1` on both sides -- and the reference's working
precision is raised by twice the leading zeros of the argument, which is what
a cancelling form would have cost. Every expectation is then rounded to bits
in exact integers, with the seven modes written out from their definitions, so
the table is the correctly rounded answer and not a transcription of one.

A platform's `math` module is not the reference and cannot be: the correctly
rounded `arccosh(2)` at 53 bits is 0.39 units from the true value, and macOS's
own `acosh` answers the double on the other side, 0.61 units away. Two
80-digit routes to `ln(2 + sqrt 3)` agree on which is which.

Four tests need no reference at all. The three laws -- `cosh^2 - sinh^2 = 1`,
`tanh = sinh/cosh`, and each inverse undoing its function -- hold to the last
few bits, and the parities hold exactly.
"""

from std import testing
from std.testing import assert_equal, assert_false, assert_true

from decimo.bigfloat.arithmetics import add, divide, multiply, subtract
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.comparison import compare_absolute
from decimo.bigfloat.hyperbolic import (
    arccosh,
    arcsinh,
    arctanh,
    cosh,
    sinh,
    tanh,
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


def _assert_close(
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


def _applied(
    which: Int, x: BigFloat, precision: Int, rounding_mode: RoundingMode
) raises -> BigFloat:
    """The function at that index, applied.

    Args:
        which: Which of the six, in the order the module lists them.
        x: The argument.
        precision: The bits wanted.
        rounding_mode: How to round.

    Returns:
        The value.

    Raises:
        Error: Propagated from the function.

    Notes:

    A conditional expression, not an assignment and five overrides: an
    argument outside one function's domain is inside another's, and calling
    all six to keep one answer would reach a NaN or an infinity that the test
    did not ask about.
    """
    return sinh(x, precision, rounding_mode) if which == 0 else (
        cosh(x, precision, rounding_mode) if which
        == 1 else (
            tanh(x, precision, rounding_mode) if which
            == 2 else (
                arcsinh(x, precision, rounding_mode) if which
                == 3 else (
                    arccosh(x, precision, rounding_mode) if which
                    == 4 else arctanh(x, precision, rounding_mode)
                )
            )
        )
    )


def test_the_values_are_what_the_reference_rounds_to() raises:
    """Twenty-five arguments at three precisions in all seven modes.

    The arguments take each function to the places it behaves differently:
    the two sides of every branch its identity has, an argument small enough
    that the answer is the argument, and one large enough to saturate.
    """
    var modes = _modes()
    # function significand exponent precision negative destination mode
    # expected_significand expected_exponent expected_negative
    var cases = [
        "0 1 0 1 0 1 0 1 0 0",
        "0 1 0 1 0 1 1 1 1 0",
        "0 1 0 1 0 1 2 1 1 0",
        "0 1 0 1 0 1 3 1 0 0",
        "0 1 0 1 0 1 4 1 0 0",
        "0 1 0 1 0 1 5 1 0 0",
        "0 1 0 1 0 1 6 1 0 0",
        "0 1 0 1 0 53 0 5292635657779586 -52 0",
        "0 1 0 1 0 53 1 5292635657779587 -52 0",
        "0 1 0 1 0 53 2 5292635657779587 -52 0",
        "0 1 0 1 0 53 3 5292635657779586 -52 0",
        "0 1 0 1 0 53 4 5292635657779586 -52 0",
        "0 1 0 1 0 53 5 5292635657779586 -52 0",
        "0 1 0 1 0 53 6 5292635657779586 -52 0",
        "0 1 0 1 0 113 0 6101993465903089943188936687814223 -112 0",
        "0 1 0 1 0 113 1 6101993465903089943188936687814224 -112 0",
        "0 1 0 1 0 113 2 6101993465903089943188936687814224 -112 0",
        "0 1 0 1 0 113 3 6101993465903089943188936687814223 -112 0",
        "0 1 0 1 0 113 4 6101993465903089943188936687814224 -112 0",
        "0 1 0 1 0 113 5 6101993465903089943188936687814224 -112 0",
        "0 1 0 1 0 113 6 6101993465903089943188936687814224 -112 0",
        "0 1 -1 1 0 1 0 1 -1 0",
        "0 1 -1 1 0 1 1 1 0 0",
        "0 1 -1 1 0 1 2 1 0 0",
        "0 1 -1 1 0 1 3 1 -1 0",
        "0 1 -1 1 0 1 4 1 -1 0",
        "0 1 -1 1 0 1 5 1 -1 0",
        "0 1 -1 1 0 1 6 1 -1 0",
        "0 1 -1 1 0 53 0 4693609247292310 -53 0",
        "0 1 -1 1 0 53 1 4693609247292311 -53 0",
        "0 1 -1 1 0 53 2 4693609247292311 -53 0",
        "0 1 -1 1 0 53 3 4693609247292310 -53 0",
        "0 1 -1 1 0 53 4 4693609247292311 -53 0",
        "0 1 -1 1 0 53 5 4693609247292311 -53 0",
        "0 1 -1 1 0 53 6 4693609247292311 -53 0",
        "0 1 -1 1 0 113 0 5411363035424861461747011558682214 -113 0",
        "0 1 -1 1 0 113 1 5411363035424861461747011558682215 -113 0",
        "0 1 -1 1 0 113 2 5411363035424861461747011558682215 -113 0",
        "0 1 -1 1 0 113 3 5411363035424861461747011558682214 -113 0",
        "0 1 -1 1 0 113 4 5411363035424861461747011558682214 -113 0",
        "0 1 -1 1 0 113 5 5411363035424861461747011558682214 -113 0",
        "0 1 -1 1 0 113 6 5411363035424861461747011558682214 -113 0",
        "0 3 -1 2 1 1 0 1 1 1",
        "0 3 -1 2 1 1 1 1 2 1",
        "0 3 -1 2 1 1 2 1 1 1",
        "0 3 -1 2 1 1 3 1 2 1",
        "0 3 -1 2 1 1 4 1 1 1",
        "0 3 -1 2 1 1 5 1 1 1",
        "0 3 -1 2 1 1 6 1 1 1",
        "0 3 -1 2 1 53 0 4794711080266336 -51 1",
        "0 3 -1 2 1 53 1 4794711080266337 -51 1",
        "0 3 -1 2 1 53 2 4794711080266336 -51 1",
        "0 3 -1 2 1 53 3 4794711080266337 -51 1",
        "0 3 -1 2 1 53 4 4794711080266336 -51 1",
        "0 3 -1 2 1 53 5 4794711080266336 -51 1",
        "0 3 -1 2 1 53 6 4794711080266336 -51 1",
        "0 3 -1 2 1 113 0 5527925512815785231171841913352779 -111 1",
        "0 3 -1 2 1 113 1 5527925512815785231171841913352780 -111 1",
        "0 3 -1 2 1 113 2 5527925512815785231171841913352779 -111 1",
        "0 3 -1 2 1 113 3 5527925512815785231171841913352780 -111 1",
        "0 3 -1 2 1 113 4 5527925512815785231171841913352779 -111 1",
        "0 3 -1 2 1 113 5 5527925512815785231171841913352779 -111 1",
        "0 3 -1 2 1 113 6 5527925512815785231171841913352779 -111 1",
        "0 1 4 1 0 1 0 1 22 0",
        "0 1 4 1 0 1 1 1 23 0",
        "0 1 4 1 0 1 2 1 23 0",
        "0 1 4 1 0 1 3 1 22 0",
        "0 1 4 1 0 1 4 1 22 0",
        "0 1 4 1 0 1 5 1 22 0",
        "0 1 4 1 0 1 6 1 22 0",
        "0 1 4 1 0 53 0 4770694259277795 -30 0",
        "0 1 4 1 0 53 1 4770694259277796 -30 0",
        "0 1 4 1 0 53 2 4770694259277796 -30 0",
        "0 1 4 1 0 53 3 4770694259277795 -30 0",
        "0 1 4 1 0 53 4 4770694259277796 -30 0",
        "0 1 4 1 0 53 5 4770694259277796 -30 0",
        "0 1 4 1 0 53 6 4770694259277796 -30 0",
        "0 1 4 1 0 113 0 5500236003425803751544687017512978 -90 0",
        "0 1 4 1 0 113 1 5500236003425803751544687017512979 -90 0",
        "0 1 4 1 0 113 2 5500236003425803751544687017512979 -90 0",
        "0 1 4 1 0 113 3 5500236003425803751544687017512978 -90 0",
        "0 1 4 1 0 113 4 5500236003425803751544687017512978 -90 0",
        "0 1 4 1 0 113 5 5500236003425803751544687017512978 -90 0",
        "0 1 4 1 0 113 6 5500236003425803751544687017512978 -90 0",
        "0 1 -40 1 0 1 0 1 -40 0",
        "0 1 -40 1 0 1 1 1 -39 0",
        "0 1 -40 1 0 1 2 1 -39 0",
        "0 1 -40 1 0 1 3 1 -40 0",
        "0 1 -40 1 0 1 4 1 -40 0",
        "0 1 -40 1 0 1 5 1 -40 0",
        "0 1 -40 1 0 1 6 1 -40 0",
        "0 1 -40 1 0 53 0 4503599627370496 -92 0",
        "0 1 -40 1 0 53 1 4503599627370497 -92 0",
        "0 1 -40 1 0 53 2 4503599627370497 -92 0",
        "0 1 -40 1 0 53 3 4503599627370496 -92 0",
        "0 1 -40 1 0 53 4 4503599627370496 -92 0",
        "0 1 -40 1 0 53 5 4503599627370496 -92 0",
        "0 1 -40 1 0 53 6 4503599627370496 -92 0",
        "0 1 -40 1 0 113 0 5192296858534827628530497045047978 -152 0",
        "0 1 -40 1 0 113 1 5192296858534827628530497045047979 -152 0",
        "0 1 -40 1 0 113 2 5192296858534827628530497045047979 -152 0",
        "0 1 -40 1 0 113 3 5192296858534827628530497045047978 -152 0",
        "0 1 -40 1 0 113 4 5192296858534827628530497045047979 -152 0",
        "0 1 -40 1 0 113 5 5192296858534827628530497045047979 -152 0",
        "0 1 -40 1 0 113 6 5192296858534827628530497045047979 -152 0",
        "1 1 0 1 0 1 0 1 0 0",
        "1 1 0 1 0 1 1 1 1 0",
        "1 1 0 1 0 1 2 1 1 0",
        "1 1 0 1 0 1 3 1 0 0",
        "1 1 0 1 0 1 4 1 1 0",
        "1 1 0 1 0 1 5 1 1 0",
        "1 1 0 1 0 1 6 1 1 0",
        "1 1 0 1 0 53 0 6949417371956560 -52 0",
        "1 1 0 1 0 53 1 6949417371956561 -52 0",
        "1 1 0 1 0 53 2 6949417371956561 -52 0",
        "1 1 0 1 0 53 3 6949417371956560 -52 0",
        "1 1 0 1 0 53 4 6949417371956560 -52 0",
        "1 1 0 1 0 53 5 6949417371956560 -52 0",
        "1 1 0 1 0 53 6 6949417371956560 -52 0",
        "1 1 0 1 0 113 0 8012132732617117838044447037822628 -112 0",
        "1 1 0 1 0 113 1 8012132732617117838044447037822629 -112 0",
        "1 1 0 1 0 113 2 8012132732617117838044447037822629 -112 0",
        "1 1 0 1 0 113 3 8012132732617117838044447037822628 -112 0",
        "1 1 0 1 0 113 4 8012132732617117838044447037822629 -112 0",
        "1 1 0 1 0 113 5 8012132732617117838044447037822629 -112 0",
        "1 1 0 1 0 113 6 8012132732617117838044447037822629 -112 0",
        "1 3 -1 2 1 1 0 1 1 0",
        "1 3 -1 2 1 1 1 1 2 0",
        "1 3 -1 2 1 1 2 1 2 0",
        "1 3 -1 2 1 1 3 1 1 0",
        "1 3 -1 2 1 1 4 1 1 0",
        "1 3 -1 2 1 1 5 1 1 0",
        "1 3 -1 2 1 1 6 1 1 0",
        "1 3 -1 2 1 53 0 5297155533316130 -51 0",
        "1 3 -1 2 1 53 1 5297155533316131 -51 0",
        "1 3 -1 2 1 53 2 5297155533316131 -51 0",
        "1 3 -1 2 1 53 3 5297155533316130 -51 0",
        "1 3 -1 2 1 53 4 5297155533316130 -51 0",
        "1 3 -1 2 1 53 5 5297155533316130 -51 0",
        "1 3 -1 2 1 53 6 5297155533316130 -51 0",
        "1 3 -1 2 1 113 0 6107204527607317825576624045458083 -111 0",
        "1 3 -1 2 1 113 1 6107204527607317825576624045458084 -111 0",
        "1 3 -1 2 1 113 2 6107204527607317825576624045458084 -111 0",
        "1 3 -1 2 1 113 3 6107204527607317825576624045458083 -111 0",
        "1 3 -1 2 1 113 4 6107204527607317825576624045458084 -111 0",
        "1 3 -1 2 1 113 5 6107204527607317825576624045458084 -111 0",
        "1 3 -1 2 1 113 6 6107204527607317825576624045458084 -111 0",
        "1 1 4 1 0 1 0 1 22 0",
        "1 1 4 1 0 1 1 1 23 0",
        "1 1 4 1 0 1 2 1 23 0",
        "1 1 4 1 0 1 3 1 22 0",
        "1 1 4 1 0 1 4 1 22 0",
        "1 1 4 1 0 1 5 1 22 0",
        "1 1 4 1 0 1 6 1 22 0",
        "1 1 4 1 0 53 0 4770694259277916 -30 0",
        "1 1 4 1 0 53 1 4770694259277917 -30 0",
        "1 1 4 1 0 53 2 4770694259277917 -30 0",
        "1 1 4 1 0 53 3 4770694259277916 -30 0",
        "1 1 4 1 0 53 4 4770694259277917 -30 0",
        "1 1 4 1 0 53 5 4770694259277917 -30 0",
        "1 1 4 1 0 53 6 4770694259277917 -30 0",
        "1 1 4 1 0 113 0 5500236003425943063343299964274347 -90 0",
        "1 1 4 1 0 113 1 5500236003425943063343299964274348 -90 0",
        "1 1 4 1 0 113 2 5500236003425943063343299964274348 -90 0",
        "1 1 4 1 0 113 3 5500236003425943063343299964274347 -90 0",
        "1 1 4 1 0 113 4 5500236003425943063343299964274348 -90 0",
        "1 1 4 1 0 113 5 5500236003425943063343299964274348 -90 0",
        "1 1 4 1 0 113 6 5500236003425943063343299964274348 -90 0",
        "1 1 -20 1 0 1 0 1 0 0",
        "1 1 -20 1 0 1 1 1 1 0",
        "1 1 -20 1 0 1 2 1 1 0",
        "1 1 -20 1 0 1 3 1 0 0",
        "1 1 -20 1 0 1 4 1 0 0",
        "1 1 -20 1 0 1 5 1 0 0",
        "1 1 -20 1 0 1 6 1 0 0",
        "1 1 -20 1 0 53 0 4503599627372544 -52 0",
        "1 1 -20 1 0 53 1 4503599627372545 -52 0",
        "1 1 -20 1 0 53 2 4503599627372545 -52 0",
        "1 1 -20 1 0 53 3 4503599627372544 -52 0",
        "1 1 -20 1 0 53 4 4503599627372544 -52 0",
        "1 1 -20 1 0 53 5 4503599627372544 -52 0",
        "1 1 -20 1 0 53 6 4503599627372544 -52 0",
        "1 1 -20 1 0 113 0 5192296858537188811771931330783914 -112 0",
        "1 1 -20 1 0 113 1 5192296858537188811771931330783915 -112 0",
        "1 1 -20 1 0 113 2 5192296858537188811771931330783915 -112 0",
        "1 1 -20 1 0 113 3 5192296858537188811771931330783914 -112 0",
        "1 1 -20 1 0 113 4 5192296858537188811771931330783915 -112 0",
        "1 1 -20 1 0 113 5 5192296858537188811771931330783915 -112 0",
        "1 1 -20 1 0 113 6 5192296858537188811771931330783915 -112 0",
        "2 1 0 1 0 1 0 1 -1 0",
        "2 1 0 1 0 1 1 1 0 0",
        "2 1 0 1 0 1 2 1 0 0",
        "2 1 0 1 0 1 3 1 -1 0",
        "2 1 0 1 0 1 4 1 0 0",
        "2 1 0 1 0 1 5 1 0 0",
        "2 1 0 1 0 1 6 1 0 0",
        "2 1 0 1 0 53 0 6859830313939860 -53 0",
        "2 1 0 1 0 53 1 6859830313939861 -53 0",
        "2 1 0 1 0 53 2 6859830313939861 -53 0",
        "2 1 0 1 0 53 3 6859830313939860 -53 0",
        "2 1 0 1 0 53 4 6859830313939860 -53 0",
        "2 1 0 1 0 53 5 6859830313939860 -53 0",
        "2 1 0 1 0 53 6 6859830313939860 -53 0",
        "2 1 0 1 0 113 0 7908845886895203223803782963119143 -113 0",
        "2 1 0 1 0 113 1 7908845886895203223803782963119144 -113 0",
        "2 1 0 1 0 113 2 7908845886895203223803782963119144 -113 0",
        "2 1 0 1 0 113 3 7908845886895203223803782963119143 -113 0",
        "2 1 0 1 0 113 4 7908845886895203223803782963119143 -113 0",
        "2 1 0 1 0 113 5 7908845886895203223803782963119143 -113 0",
        "2 1 0 1 0 113 6 7908845886895203223803782963119143 -113 0",
        "2 1 -1 1 1 1 0 1 -2 1",
        "2 1 -1 1 1 1 1 1 -1 1",
        "2 1 -1 1 1 1 2 1 -2 1",
        "2 1 -1 1 1 1 3 1 -1 1",
        "2 1 -1 1 1 1 4 1 -1 1",
        "2 1 -1 1 1 1 5 1 -1 1",
        "2 1 -1 1 1 1 6 1 -1 1",
        "2 1 -1 1 1 53 0 8324762628950771 -54 1",
        "2 1 -1 1 1 53 1 8324762628950772 -54 1",
        "2 1 -1 1 1 53 2 8324762628950771 -54 1",
        "2 1 -1 1 1 53 3 8324762628950772 -54 1",
        "2 1 -1 1 1 53 4 8324762628950771 -54 1",
        "2 1 -1 1 1 53 5 8324762628950771 -54 1",
        "2 1 -1 1 1 53 6 8324762628950771 -54 1",
        "2 1 -1 1 1 113 0 9597797855664774325766210009324296 -114 1",
        "2 1 -1 1 1 113 1 9597797855664774325766210009324297 -114 1",
        "2 1 -1 1 1 113 2 9597797855664774325766210009324296 -114 1",
        "2 1 -1 1 1 113 3 9597797855664774325766210009324297 -114 1",
        "2 1 -1 1 1 113 4 9597797855664774325766210009324297 -114 1",
        "2 1 -1 1 1 113 5 9597797855664774325766210009324297 -114 1",
        "2 1 -1 1 1 113 6 9597797855664774325766210009324297 -114 1",
        "2 5 0 3 0 1 0 1 -1 0",
        "2 5 0 3 0 1 1 1 0 0",
        "2 5 0 3 0 1 2 1 0 0",
        "2 5 0 3 0 1 3 1 -1 0",
        "2 5 0 3 0 1 4 1 0 0",
        "2 5 0 3 0 1 5 1 0 0",
        "2 5 0 3 0 1 6 1 0 0",
        "2 5 0 3 0 53 0 9006381439442705 -53 0",
        "2 5 0 3 0 53 1 9006381439442706 -53 0",
        "2 5 0 3 0 53 2 9006381439442706 -53 0",
        "2 5 0 3 0 53 3 9006381439442705 -53 0",
        "2 5 0 3 0 53 4 9006381439442705 -53 0",
        "2 5 0 3 0 53 5 9006381439442705 -53 0",
        "2 5 0 3 0 53 6 9006381439442705 -53 0",
        "2 5 0 3 0 113 0 10383650840225463950349005682731749 -113 0",
        "2 5 0 3 0 113 1 10383650840225463950349005682731750 -113 0",
        "2 5 0 3 0 113 2 10383650840225463950349005682731750 -113 0",
        "2 5 0 3 0 113 3 10383650840225463950349005682731749 -113 0",
        "2 5 0 3 0 113 4 10383650840225463950349005682731750 -113 0",
        "2 5 0 3 0 113 5 10383650840225463950349005682731750 -113 0",
        "2 5 0 3 0 113 6 10383650840225463950349005682731750 -113 0",
        "2 1 -40 1 0 1 0 1 -41 0",
        "2 1 -40 1 0 1 1 1 -40 0",
        "2 1 -40 1 0 1 2 1 -40 0",
        "2 1 -40 1 0 1 3 1 -41 0",
        "2 1 -40 1 0 1 4 1 -40 0",
        "2 1 -40 1 0 1 5 1 -40 0",
        "2 1 -40 1 0 1 6 1 -40 0",
        "2 1 -40 1 0 53 0 9007199254740991 -93 0",
        "2 1 -40 1 0 53 1 4503599627370496 -92 0",
        "2 1 -40 1 0 53 2 4503599627370496 -92 0",
        "2 1 -40 1 0 53 3 9007199254740991 -93 0",
        "2 1 -40 1 0 53 4 4503599627370496 -92 0",
        "2 1 -40 1 0 53 5 4503599627370496 -92 0",
        "2 1 -40 1 0 53 6 4503599627370496 -92 0",
        "2 1 -40 1 0 113 0 10384593717069655257060989795128661 -153 0",
        "2 1 -40 1 0 113 1 10384593717069655257060989795128662 -153 0",
        "2 1 -40 1 0 113 2 10384593717069655257060989795128662 -153 0",
        "2 1 -40 1 0 113 3 10384593717069655257060989795128661 -153 0",
        "2 1 -40 1 0 113 4 10384593717069655257060989795128661 -153 0",
        "2 1 -40 1 0 113 5 10384593717069655257060989795128661 -153 0",
        "2 1 -40 1 0 113 6 10384593717069655257060989795128661 -153 0",
        "3 1 0 1 0 1 0 1 -1 0",
        "3 1 0 1 0 1 1 1 0 0",
        "3 1 0 1 0 1 2 1 0 0",
        "3 1 0 1 0 1 3 1 -1 0",
        "3 1 0 1 0 1 4 1 0 0",
        "3 1 0 1 0 1 5 1 0 0",
        "3 1 0 1 0 1 6 1 0 0",
        "3 1 0 1 0 53 0 7938707516150822 -53 0",
        "3 1 0 1 0 53 1 7938707516150823 -53 0",
        "3 1 0 1 0 53 2 7938707516150823 -53 0",
        "3 1 0 1 0 53 3 7938707516150822 -53 0",
        "3 1 0 1 0 53 4 7938707516150823 -53 0",
        "3 1 0 1 0 53 5 7938707516150823 -53 0",
        "3 1 0 1 0 53 6 7938707516150823 -53 0",
        "3 1 0 1 0 113 0 9152706614154291559812342711297187 -113 0",
        "3 1 0 1 0 113 1 9152706614154291559812342711297188 -113 0",
        "3 1 0 1 0 113 2 9152706614154291559812342711297188 -113 0",
        "3 1 0 1 0 113 3 9152706614154291559812342711297187 -113 0",
        "3 1 0 1 0 113 4 9152706614154291559812342711297187 -113 0",
        "3 1 0 1 0 113 5 9152706614154291559812342711297187 -113 0",
        "3 1 0 1 0 113 6 9152706614154291559812342711297187 -113 0",
        "3 1 -1 1 1 1 0 1 -2 1",
        "3 1 -1 1 1 1 1 1 -1 1",
        "3 1 -1 1 1 1 2 1 -2 1",
        "3 1 -1 1 1 1 3 1 -1 1",
        "3 1 -1 1 1 1 4 1 -1 1",
        "3 1 -1 1 1 1 5 1 -1 1",
        "3 1 -1 1 1 1 6 1 -1 1",
        "3 1 -1 1 1 53 0 8668741584098825 -54 1",
        "3 1 -1 1 1 53 1 8668741584098826 -54 1",
        "3 1 -1 1 1 53 2 8668741584098825 -54 1",
        "3 1 -1 1 1 53 3 8668741584098826 -54 1",
        "3 1 -1 1 1 53 4 8668741584098826 -54 1",
        "3 1 -1 1 1 53 5 8668741584098826 -54 1",
        "3 1 -1 1 1 53 6 8668741584098826 -54 1",
        "3 1 -1 1 1 113 0 9994378590187160089544165381728455 -114 1",
        "3 1 -1 1 1 113 1 9994378590187160089544165381728456 -114 1",
        "3 1 -1 1 1 113 2 9994378590187160089544165381728455 -114 1",
        "3 1 -1 1 1 113 3 9994378590187160089544165381728456 -114 1",
        "3 1 -1 1 1 113 4 9994378590187160089544165381728455 -114 1",
        "3 1 -1 1 1 113 5 9994378590187160089544165381728455 -114 1",
        "3 1 -1 1 1 113 6 9994378590187160089544165381728455 -114 1",
        "3 1 10 1 0 1 0 1 2 0",
        "3 1 10 1 0 1 1 1 3 0",
        "3 1 10 1 0 1 2 1 3 0",
        "3 1 10 1 0 1 3 1 2 0",
        "3 1 10 1 0 1 4 1 3 0",
        "3 1 10 1 0 1 5 1 3 0",
        "3 1 10 1 0 1 6 1 3 0",
        "3 1 10 1 0 53 0 8584558074662728 -50 0",
        "3 1 10 1 0 53 1 8584558074662729 -50 0",
        "3 1 10 1 0 53 2 8584558074662729 -50 0",
        "3 1 10 1 0 53 3 8584558074662728 -50 0",
        "3 1 10 1 0 53 4 8584558074662729 -50 0",
        "3 1 10 1 0 53 5 8584558074662729 -50 0",
        "3 1 10 1 0 53 6 8584558074662729 -50 0",
        "3 1 10 1 0 113 0 9897321611825010818175387543494730 -110 0",
        "3 1 10 1 0 113 1 9897321611825010818175387543494731 -110 0",
        "3 1 10 1 0 113 2 9897321611825010818175387543494731 -110 0",
        "3 1 10 1 0 113 3 9897321611825010818175387543494730 -110 0",
        "3 1 10 1 0 113 4 9897321611825010818175387543494731 -110 0",
        "3 1 10 1 0 113 5 9897321611825010818175387543494731 -110 0",
        "3 1 10 1 0 113 6 9897321611825010818175387543494731 -110 0",
        "3 1 -40 1 0 1 0 1 -41 0",
        "3 1 -40 1 0 1 1 1 -40 0",
        "3 1 -40 1 0 1 2 1 -40 0",
        "3 1 -40 1 0 1 3 1 -41 0",
        "3 1 -40 1 0 1 4 1 -40 0",
        "3 1 -40 1 0 1 5 1 -40 0",
        "3 1 -40 1 0 1 6 1 -40 0",
        "3 1 -40 1 0 53 0 9007199254740991 -93 0",
        "3 1 -40 1 0 53 1 4503599627370496 -92 0",
        "3 1 -40 1 0 53 2 4503599627370496 -92 0",
        "3 1 -40 1 0 53 3 9007199254740991 -93 0",
        "3 1 -40 1 0 53 4 4503599627370496 -92 0",
        "3 1 -40 1 0 53 5 4503599627370496 -92 0",
        "3 1 -40 1 0 53 6 4503599627370496 -92 0",
        "3 1 -40 1 0 113 0 10384593717069655257060991226784426 -153 0",
        "3 1 -40 1 0 113 1 10384593717069655257060991226784427 -153 0",
        "3 1 -40 1 0 113 2 10384593717069655257060991226784427 -153 0",
        "3 1 -40 1 0 113 3 10384593717069655257060991226784426 -153 0",
        "3 1 -40 1 0 113 4 10384593717069655257060991226784427 -153 0",
        "3 1 -40 1 0 113 5 10384593717069655257060991226784427 -153 0",
        "3 1 -40 1 0 113 6 10384593717069655257060991226784427 -153 0",
        "4 1 0 1 0 1 0 0 0 0",
        "4 1 0 1 0 1 1 0 0 0",
        "4 1 0 1 0 1 2 0 0 0",
        "4 1 0 1 0 1 3 0 0 0",
        "4 1 0 1 0 1 4 0 0 0",
        "4 1 0 1 0 1 5 0 0 0",
        "4 1 0 1 0 1 6 0 0 0",
        "4 1 0 1 0 53 0 0 0 0",
        "4 1 0 1 0 53 1 0 0 0",
        "4 1 0 1 0 53 2 0 0 0",
        "4 1 0 1 0 53 3 0 0 0",
        "4 1 0 1 0 53 4 0 0 0",
        "4 1 0 1 0 53 5 0 0 0",
        "4 1 0 1 0 53 6 0 0 0",
        "4 1 0 1 0 113 0 0 0 0",
        "4 1 0 1 0 113 1 0 0 0",
        "4 1 0 1 0 113 2 0 0 0",
        "4 1 0 1 0 113 3 0 0 0",
        "4 1 0 1 0 113 4 0 0 0",
        "4 1 0 1 0 113 5 0 0 0",
        "4 1 0 1 0 113 6 0 0 0",
        "4 1 1 1 0 1 0 1 0 0",
        "4 1 1 1 0 1 1 1 1 0",
        "4 1 1 1 0 1 2 1 1 0",
        "4 1 1 1 0 1 3 1 0 0",
        "4 1 1 1 0 1 4 1 0 0",
        "4 1 1 1 0 1 5 1 0 0",
        "4 1 1 1 0 1 6 1 0 0",
        "4 1 1 1 0 53 0 5931051093853236 -52 0",
        "4 1 1 1 0 53 1 5931051093853237 -52 0",
        "4 1 1 1 0 53 2 5931051093853237 -52 0",
        "4 1 1 1 0 53 3 5931051093853236 -52 0",
        "4 1 1 1 0 53 4 5931051093853237 -52 0",
        "4 1 1 1 0 53 5 5931051093853237 -52 0",
        "4 1 1 1 0 53 6 5931051093853237 -52 0",
        "4 1 1 1 0 113 0 6838036351025359127306539193896274 -112 0",
        "4 1 1 1 0 113 1 6838036351025359127306539193896275 -112 0",
        "4 1 1 1 0 113 2 6838036351025359127306539193896275 -112 0",
        "4 1 1 1 0 113 3 6838036351025359127306539193896274 -112 0",
        "4 1 1 1 0 113 4 6838036351025359127306539193896275 -112 0",
        "4 1 1 1 0 113 5 6838036351025359127306539193896275 -112 0",
        "4 1 1 1 0 113 6 6838036351025359127306539193896275 -112 0",
        "4 3 -1 2 0 1 0 1 -1 0",
        "4 3 -1 2 0 1 1 1 0 0",
        "4 3 -1 2 0 1 2 1 0 0",
        "4 3 -1 2 0 1 3 1 -1 0",
        "4 3 -1 2 0 1 4 1 0 0",
        "4 3 -1 2 0 1 5 1 0 0",
        "4 3 -1 2 0 1 6 1 0 0",
        "4 3 -1 2 0 53 0 8668741584098825 -53 0",
        "4 3 -1 2 0 53 1 8668741584098826 -53 0",
        "4 3 -1 2 0 53 2 8668741584098826 -53 0",
        "4 3 -1 2 0 53 3 8668741584098825 -53 0",
        "4 3 -1 2 0 53 4 8668741584098826 -53 0",
        "4 3 -1 2 0 53 5 8668741584098826 -53 0",
        "4 3 -1 2 0 53 6 8668741584098826 -53 0",
        "4 3 -1 2 0 113 0 9994378590187160089544165381728455 -113 0",
        "4 3 -1 2 0 113 1 9994378590187160089544165381728456 -113 0",
        "4 3 -1 2 0 113 2 9994378590187160089544165381728456 -113 0",
        "4 3 -1 2 0 113 3 9994378590187160089544165381728455 -113 0",
        "4 3 -1 2 0 113 4 9994378590187160089544165381728455 -113 0",
        "4 3 -1 2 0 113 5 9994378590187160089544165381728455 -113 0",
        "4 3 -1 2 0 113 6 9994378590187160089544165381728455 -113 0",
        "4 1 30 1 0 1 0 1 4 0",
        "4 1 30 1 0 1 1 1 5 0",
        "4 1 30 1 0 1 2 1 5 0",
        "4 1 30 1 0 1 3 1 4 0",
        "4 1 30 1 0 1 4 1 4 0",
        "4 1 30 1 0 1 5 1 4 0",
        "4 1 30 1 0 1 6 1 4 0",
        "4 1 30 1 0 53 0 6048211181660191 -48 0",
        "4 1 30 1 0 53 1 6048211181660192 -48 0",
        "4 1 30 1 0 53 2 6048211181660192 -48 0",
        "4 1 30 1 0 53 3 6048211181660191 -48 0",
        "4 1 30 1 0 53 4 6048211181660192 -48 0",
        "4 1 30 1 0 53 5 6048211181660192 -48 0",
        "4 1 30 1 0 53 6 6048211181660192 -48 0",
        "4 1 30 1 0 113 0 6973112735739624136164170693773222 -108 0",
        "4 1 30 1 0 113 1 6973112735739624136164170693773223 -108 0",
        "4 1 30 1 0 113 2 6973112735739624136164170693773223 -108 0",
        "4 1 30 1 0 113 3 6973112735739624136164170693773222 -108 0",
        "4 1 30 1 0 113 4 6973112735739624136164170693773223 -108 0",
        "4 1 30 1 0 113 5 6973112735739624136164170693773223 -108 0",
        "4 1 30 1 0 113 6 6973112735739624136164170693773223 -108 0",
        "5 1 -1 1 0 1 0 1 -1 0",
        "5 1 -1 1 0 1 1 1 0 0",
        "5 1 -1 1 0 1 2 1 0 0",
        "5 1 -1 1 0 1 3 1 -1 0",
        "5 1 -1 1 0 1 4 1 -1 0",
        "5 1 -1 1 0 1 5 1 -1 0",
        "5 1 -1 1 0 1 6 1 -1 0",
        "5 1 -1 1 0 53 0 4947709893870346 -53 0",
        "5 1 -1 1 0 53 1 4947709893870347 -53 0",
        "5 1 -1 1 0 53 2 4947709893870347 -53 0",
        "5 1 -1 1 0 53 3 4947709893870346 -53 0",
        "5 1 -1 1 0 53 4 4947709893870347 -53 0",
        "5 1 -1 1 0 53 5 4947709893870347 -53 0",
        "5 1 -1 1 0 53 6 4947709893870347 -53 0",
        "5 1 -1 1 0 113 0 5704321135199183160453707651679547 -113 0",
        "5 1 -1 1 0 113 1 5704321135199183160453707651679548 -113 0",
        "5 1 -1 1 0 113 2 5704321135199183160453707651679548 -113 0",
        "5 1 -1 1 0 113 3 5704321135199183160453707651679547 -113 0",
        "5 1 -1 1 0 113 4 5704321135199183160453707651679547 -113 0",
        "5 1 -1 1 0 113 5 5704321135199183160453707651679547 -113 0",
        "5 1 -1 1 0 113 6 5704321135199183160453707651679547 -113 0",
        "5 1 -1 1 1 1 0 1 -1 1",
        "5 1 -1 1 1 1 1 1 0 1",
        "5 1 -1 1 1 1 2 1 -1 1",
        "5 1 -1 1 1 1 3 1 0 1",
        "5 1 -1 1 1 1 4 1 -1 1",
        "5 1 -1 1 1 1 5 1 -1 1",
        "5 1 -1 1 1 1 6 1 -1 1",
        "5 1 -1 1 1 53 0 4947709893870346 -53 1",
        "5 1 -1 1 1 53 1 4947709893870347 -53 1",
        "5 1 -1 1 1 53 2 4947709893870346 -53 1",
        "5 1 -1 1 1 53 3 4947709893870347 -53 1",
        "5 1 -1 1 1 53 4 4947709893870347 -53 1",
        "5 1 -1 1 1 53 5 4947709893870347 -53 1",
        "5 1 -1 1 1 53 6 4947709893870347 -53 1",
        "5 1 -1 1 1 113 0 5704321135199183160453707651679547 -113 1",
        "5 1 -1 1 1 113 1 5704321135199183160453707651679548 -113 1",
        "5 1 -1 1 1 113 2 5704321135199183160453707651679547 -113 1",
        "5 1 -1 1 1 113 3 5704321135199183160453707651679548 -113 1",
        "5 1 -1 1 1 113 4 5704321135199183160453707651679547 -113 1",
        "5 1 -1 1 1 113 5 5704321135199183160453707651679547 -113 1",
        "5 1 -1 1 1 113 6 5704321135199183160453707651679547 -113 1",
        "5 1 -40 1 0 1 0 1 -40 0",
        "5 1 -40 1 0 1 1 1 -39 0",
        "5 1 -40 1 0 1 2 1 -39 0",
        "5 1 -40 1 0 1 3 1 -40 0",
        "5 1 -40 1 0 1 4 1 -40 0",
        "5 1 -40 1 0 1 5 1 -40 0",
        "5 1 -40 1 0 1 6 1 -40 0",
        "5 1 -40 1 0 53 0 4503599627370496 -92 0",
        "5 1 -40 1 0 53 1 4503599627370497 -92 0",
        "5 1 -40 1 0 53 2 4503599627370497 -92 0",
        "5 1 -40 1 0 53 3 4503599627370496 -92 0",
        "5 1 -40 1 0 53 4 4503599627370496 -92 0",
        "5 1 -40 1 0 53 5 4503599627370496 -92 0",
        "5 1 -40 1 0 53 6 4503599627370496 -92 0",
        "5 1 -40 1 0 113 0 5192296858534827628530497760875861 -152 0",
        "5 1 -40 1 0 113 1 5192296858534827628530497760875862 -152 0",
        "5 1 -40 1 0 113 2 5192296858534827628530497760875862 -152 0",
        "5 1 -40 1 0 113 3 5192296858534827628530497760875861 -152 0",
        "5 1 -40 1 0 113 4 5192296858534827628530497760875861 -152 0",
        "5 1 -40 1 0 113 5 5192296858534827628530497760875861 -152 0",
        "5 1 -40 1 0 113 6 5192296858534827628530497760875861 -152 0",
        "5 3 -2 2 0 1 0 1 -1 0",
        "5 3 -2 2 0 1 1 1 0 0",
        "5 3 -2 2 0 1 2 1 0 0",
        "5 3 -2 2 0 1 3 1 -1 0",
        "5 3 -2 2 0 1 4 1 0 0",
        "5 3 -2 2 0 1 5 1 0 0",
        "5 3 -2 2 0 1 6 1 0 0",
        "5 3 -2 2 0 53 0 8763600222181975 -53 0",
        "5 3 -2 2 0 53 1 8763600222181976 -53 0",
        "5 3 -2 2 0 53 2 8763600222181976 -53 0",
        "5 3 -2 2 0 53 3 8763600222181975 -53 0",
        "5 3 -2 2 0 53 4 8763600222181975 -53 0",
        "5 3 -2 2 0 53 5 8763600222181975 -53 0",
        "5 3 -2 2 0 53 6 8763600222181975 -53 0",
        "5 3 -2 2 0 113 0 10103743153930941452656796255594011 -113 0",
        "5 3 -2 2 0 113 1 10103743153930941452656796255594012 -113 0",
        "5 3 -2 2 0 113 2 10103743153930941452656796255594012 -113 0",
        "5 3 -2 2 0 113 3 10103743153930941452656796255594011 -113 0",
        "5 3 -2 2 0 113 4 10103743153930941452656796255594012 -113 0",
        "5 3 -2 2 0 113 5 10103743153930941452656796255594012 -113 0",
        "5 3 -2 2 0 113 6 10103743153930941452656796255594012 -113 0",
    ]
    for row in cases:
        var field = row.split(" ")
        var x = BigFloat(
            significand=BigInt(String(field[1])),
            exponent=Int(String(field[2])),
            precision=Int(String(field[3])),
            sign=field[4] == "1",
        )
        var destination = Int(String(field[5]))
        var got = _applied(
            Int(String(field[0])), x, destination, modes[Int(String(field[6]))]
        )
        var want = String("-") if field[9] == "1" else String("")
        want += (
            String(field[7])
            + "p"
            + String(field[8])
            + "@"
            + String(destination)
        )
        assert_equal(got.internal_representation(), want, String("case ") + row)


def test_the_laws_hold_to_the_precision_asked_for() raises:
    """`cosh^2 - sinh^2 = 1` and `tanh = sinh/cosh`.

    The first subtracts two values that agree to `2x log2 e` bits, so the
    arguments stay small enough that the cancellation leaves something: at
    two, `cosh^2` and `sinh^2` still differ in their fifth bit. The second
    cancels nothing and is held to three units in the last place.
    """
    var precision = 120
    for text in ["0.25", "0.5", "1", "2"]:
        var x = BigFloat.from_string(text, precision)
        var c = cosh(x, precision)
        var s = sinh(x, precision)
        _assert_close(
            subtract(
                multiply(c, c, precision), multiply(s, s, precision), precision
            ),
            BigFloat.from_int(1, precision),
            16,
            String("cosh^2 - sinh^2 at ") + text,
        )
        _assert_close(
            tanh(x, precision),
            divide(s, c, precision),
            3,
            String("tanh against sinh over cosh at ") + text,
        )


def test_each_inverse_undoes_its_function() raises:
    """Three round trips, each two correctly rounded steps wide.

    What a round trip is allowed to lose is the inverse's own condition
    number, not a number picked to make the test pass. For `arcsinh(sinh(x))`
    that number is `tanh(x)/x`, which never exceeds one, so four units in the
    last place covers two roundings and nothing else. For
    `arccosh(cosh(x))` it is `coth(x)/x`, which is 1.31 at one and falls from
    there -- and below one `cosh` is flat, so the trip is not asked about
    arguments there at all.

    `arctanh(tanh(x))` is the one that grows: the number is 1.01 at an eighth,
    1.8 at one, 6.8 at two and 33.6 at three, because `arctanh` is steep
    exactly where `tanh` has flattened out. So the trip stops at two and the
    allowance is sixteen units. Letting it run to three and keeping the
    tolerance at eight is the test I first wrote, and it failed on
    arithmetic that was right.
    """
    var precision = 140
    for text in ["0.125", "0.5", "1", "2", "3"]:
        var x = BigFloat.from_string(text, precision)
        _assert_close(
            arcsinh(sinh(x, precision), precision),
            x,
            4,
            String("arcsinh of sinh at ") + text,
        )
    for text in ["0.125", "0.5", "1", "2"]:
        var x = BigFloat.from_string(text, precision)
        _assert_close(
            arctanh(tanh(x, precision), precision),
            x,
            16,
            String("arctanh of tanh at ") + text,
        )
    for text in ["1", "1.5", "2", "10"]:
        var x = BigFloat.from_string(text, precision)
        _assert_close(
            arccosh(cosh(x, precision), precision),
            x,
            8,
            String("arccosh of cosh at ") + text,
        )


def test_the_parities_are_exact() raises:
    """`sinh`, `tanh`, `arcsinh` and `arctanh` are odd; `cosh` is even.

    A parity is not an approximation: the identities run on the magnitude and
    put the sign back, so the two sides have to be the same bits, in every
    mode that is itself symmetric.
    """
    for text in ["0.25", "1", "3"]:
        var x = BigFloat.from_string(text, 90)
        for which in [0, 2, 3, 5]:
            if which == 5 and text != "0.25":
                continue  # `arctanh` wants an argument inside (-1, 1)
            assert_equal(
                _applied(
                    which, -x, 90, RoundingMode.ROUND_HALF_EVEN
                ).internal_representation(),
                (
                    -_applied(which, x, 90, RoundingMode.ROUND_HALF_EVEN)
                ).internal_representation(),
                String("function ") + String(which) + " is odd at " + text,
            )
        assert_equal(
            cosh(-x, 90).internal_representation(),
            cosh(x, 90).internal_representation(),
            String("cosh is even at ") + text,
        )


def test_cosh_of_a_tiny_argument_knows_it_is_above_one() raises:
    """The identity gives exactly one there, and the answer is not one.

    `cosh(x)` is `1 + x^2/2`, which no width reaches once `x` is small
    enough, so the function answers from the series instead of from the
    identity. The three nearest modes and the two that round toward zero take
    one; the two that round away take the float above it.
    """
    var tiny = BigFloat(
        significand=BigInt.one(), exponent=-30000, precision=1, sign=False
    )
    var one = BigFloat.from_int(1, 53)
    var next_up = BigFloat.from_rounded_parts(
        one.significand + BigInt.one(), one.exponent, 53, False
    )
    for mode in _modes():
        var takes_one = (
            mode == RoundingMode.ROUND_HALF_EVEN
            or mode == RoundingMode.ROUND_HALF_UP
            or mode == RoundingMode.ROUND_HALF_DOWN
            or mode == RoundingMode.ROUND_DOWN
            or mode == RoundingMode.ROUND_FLOOR
        )
        var expected = one.copy() if takes_one else next_up.copy()
        assert_equal(
            cosh(tiny, 53, mode).internal_representation(),
            expected.internal_representation(),
            String("cosh of a tiny argument, ") + String(mode),
        )
        # The sign of the argument cannot matter: `cosh` is even.
        assert_equal(
            cosh(-tiny, 53, mode).internal_representation(),
            expected.internal_representation(),
            String("cosh of a tiny negative argument, ") + String(mode),
        )

    # And an argument small but not that small still comes through the
    # identity, which has to agree with the series at the boundary.
    for bits in [20, 26, 27, 28, 40]:
        var small = BigFloat(
            significand=BigInt.one(), exponent=-bits, precision=1, sign=False
        )
        _assert_close(
            cosh(small, 53),
            add(
                BigFloat.from_int(1, 53),
                divide(
                    multiply(small, small, 60), BigFloat.from_int(2, 60), 60
                ),
                53,
            ),
            1,
            String("cosh near the boundary at 2^-") + String(bits),
        )


def test_tanh_saturates_the_way_each_mode_asks() raises:
    """Past the bound `tanh` is a unit below one, and the mode picks a side.

    The true value is strictly between the largest float below one and one
    itself, so there is no rounding to do -- only a choice, and five of the
    seven modes choose one. Answering one in every mode, which reading a
    half-even kernel would give, is wrong for `DOWN` and for one side of each
    directed mode.
    """
    var one = BigFloat.from_int(1, 53)
    var below_one = BigFloat(
        significand=(BigInt.one() << 53) - BigInt.one(),
        exponent=-53,
        precision=53,
        sign=False,
    )
    for text in ["25", "100", "1000", "1e18"]:
        var big = BigFloat.from_string(text, 53)
        for mode in _modes():
            var takes_one = (
                mode == RoundingMode.ROUND_HALF_EVEN
                or mode == RoundingMode.ROUND_HALF_UP
                or mode == RoundingMode.ROUND_HALF_DOWN
                or mode == RoundingMode.ROUND_UP
                or mode == RoundingMode.ROUND_CEILING
            )
            assert_equal(
                tanh(big, 53, mode).internal_representation(),
                (
                    one.copy() if takes_one else below_one.copy()
                ).internal_representation(),
                String("tanh of ") + text + ", " + String(mode),
            )
            # Mirrored for a negative argument, where `CEILING` and `FLOOR`
            # swap and the other five do not move.
            var negative_takes_one = (
                mode == RoundingMode.ROUND_HALF_EVEN
                or mode == RoundingMode.ROUND_HALF_UP
                or mode == RoundingMode.ROUND_HALF_DOWN
                or mode == RoundingMode.ROUND_UP
                or mode == RoundingMode.ROUND_FLOOR
            )
            var expected = (
                one.copy() if negative_takes_one else below_one.copy()
            )
            assert_equal(
                tanh(-big, 53, mode).internal_representation(),
                (-expected).internal_representation(),
                String("tanh of -") + text + ", " + String(mode),
            )

    # Just inside the bound it is still a rounding and not a choice, so the
    # answer is below one in every mode.
    var inside = BigFloat.from_string("8", 53)
    for mode in _modes():
        assert_true(
            compare_absolute(tanh(inside, 53, mode), one) < 0,
            String("tanh of 8 is below one, ") + String(mode),
        )


def test_the_special_values_follow_the_house_rules() raises:
    """The infinities, the NaN, the zeros, and the two domains."""
    var infinity = BigFloat.infinity()
    for which in [0, 3]:  # sinh and arcsinh carry an infinity through
        assert_true(
            _applied(
                which, infinity, 53, RoundingMode.ROUND_HALF_EVEN
            ).is_infinite(),
            String("function ") + String(which) + " of an infinity",
        )
        assert_true(
            _applied(which, -infinity, 53, RoundingMode.ROUND_HALF_EVEN).sign,
            String("function ") + String(which) + " keeps the sign",
        )
    for which in range(6):
        assert_true(
            _applied(
                which, BigFloat.nan(), 53, RoundingMode.ROUND_HALF_EVEN
            ).is_nan(),
            String("function ") + String(which) + " of a NaN",
        )

    # `cosh` is even, so both infinities give a positive one.
    assert_true(cosh(infinity, 53).is_infinite(), "cosh of an infinity")
    assert_false(cosh(-infinity, 53).sign, "which is positive")

    # `tanh` of an infinity is exactly one in every mode: the shortfall there
    # is not small, it is nothing.
    for mode in _modes():
        assert_equal(
            tanh(infinity, 53, mode).internal_representation(),
            BigFloat.from_int(1, 53).internal_representation(),
            String("tanh of an infinity, ") + String(mode),
        )
        assert_equal(
            tanh(-infinity, 53, mode).internal_representation(),
            (-BigFloat.from_int(1, 53)).internal_representation(),
            String("tanh of a negative infinity, ") + String(mode),
        )

    # The zeros. Four of the six are odd and keep the sign of a zero.
    for which in [0, 2, 3, 5]:
        for sign in [False, True]:
            var zero = BigFloat.zero(53, sign)
            var answer = _applied(which, zero, 53, RoundingMode.ROUND_HALF_EVEN)
            assert_true(
                answer.is_zero(),
                String("function ") + String(which) + " of a zero",
            )
            assert_equal(
                answer.sign,
                sign,
                String("function ") + String(which) + " keeps a zero's sign",
            )
    assert_equal(
        cosh(BigFloat.zero(), 53).internal_representation(),
        BigFloat.from_int(1, 53).internal_representation(),
        "cosh of a zero is one",
    )
    assert_true(
        arccosh(BigFloat.from_int(1), 53).is_zero(), "arccosh of one is zero"
    )
    assert_false(
        arccosh(BigFloat.from_int(1), 53).sign, "and it is a positive zero"
    )

    # The domains. An argument outside gives a NaN, as `sqrt` and `ln` do,
    # and the ends of `arctanh` give the infinity it runs off to.
    for text in ["0.5", "0", "-3"]:
        assert_true(
            arccosh(BigFloat.from_string(text, 53), 53).is_nan(),
            String("arccosh of ") + text + " has no real value",
        )
    for text in ["1", "-1"]:
        var end = BigFloat.from_string(text, 53)
        assert_true(
            arctanh(end, 53).is_infinite(),
            String("arctanh of ") + text + " is an infinity",
        )
        assert_equal(
            arctanh(end, 53).sign,
            end.sign,
            String("arctanh of ") + text + " keeps the side it ran off",
        )
    for text in ["1.5", "-2", "1e30"]:
        assert_true(
            arctanh(BigFloat.from_string(text, 53), 53).is_nan(),
            String("arctanh of ") + text + " has no real value",
        )
    assert_true(
        arctanh(BigFloat.infinity(), 53).is_nan(),
        "arctanh of an infinity has no real value",
    )


def test_a_tiny_argument_comes_back_as_itself() raises:
    """The four that go to zero keep an argument no width could reach.

    `sinh(x)`, `tanh(x)`, `arcsinh(x)` and `arctanh(x)` are all `x` to within
    the cube of `x`, so at `2^-100000` the answer is the argument. These are
    the cases that would have come back as zero from a textbook form, and the
    ones the loop that decides a rounding could never widen its way to.
    """
    var tiny = BigFloat(
        significand=BigInt.one(), exponent=-100000, precision=1, sign=False
    )
    var expected = BigFloat.from_rounded_parts(BigInt.one(), -100000, 53, False)
    for which in [0, 2, 3, 5]:
        for sign in [False, True]:
            var argument = -tiny if sign else tiny.copy()
            var answer = _applied(
                which, argument, 53, RoundingMode.ROUND_HALF_EVEN
            )
            assert_equal(
                answer.internal_representation(),
                (
                    -expected if sign else expected.copy()
                ).internal_representation(),
                String("function ") + String(which) + " of a tiny argument",
            )


def test_the_edges_of_the_exponent_range_are_answered() raises:
    """Four arguments where the answer is representable and the route was not.

    An argument at `2^-100000` has a correction too small to compute, and the
    loop that decides a rounding widens geometrically, so it would run out of
    widenings before it could tell which side of `x` the answer is on. The
    four functions whose answer is `x` moved a hair now say which way, and
    the two directions have to differ: the hyperbolic sine and the inverse
    tangent sit above `x`, the hyperbolic tangent and the inverse sine below.

    At the other end, an argument at `2^(Int.MAX-1)` has an inverse
    hyperbolic sine of about `Int.MAX ln 2`, an ordinary number -- but
    forming `x^2` to get there has no exponent. And `2^(Int.MIN+52)` has a
    hyperbolic cosine of one, where squaring underflows instead.
    """
    var tiny = BigFloat(
        significand=BigInt.one(), exponent=-100000, precision=1, sign=False
    )
    # The successor is one unit in the last place above; the predecessor is
    # half a unit below, since `x` is a power of two and the binade changes.
    var above = BigFloat.from_rounded_parts(
        (BigInt.one() << 52) + BigInt.one(), -100052, 53, False
    )
    var below = BigFloat.from_rounded_parts(
        (BigInt.one() << 53) - BigInt.one(), -100053, 53, False
    )
    var exactly = BigFloat.from_rounded_parts(BigInt.one(), -100000, 53, False)
    assert_equal(
        sinh(tiny, 53, RoundingMode.ROUND_UP).internal_representation(),
        above.internal_representation(),
        "the hyperbolic sine of a tiny argument is above it",
    )
    assert_equal(
        arctanh(tiny, 53, RoundingMode.ROUND_UP).internal_representation(),
        above.internal_representation(),
        "and so is the inverse hyperbolic tangent",
    )
    assert_equal(
        tanh(tiny, 53, RoundingMode.ROUND_DOWN).internal_representation(),
        below.internal_representation(),
        "the hyperbolic tangent is below it",
    )
    assert_equal(
        arcsinh(tiny, 53, RoundingMode.ROUND_DOWN).internal_representation(),
        below.internal_representation(),
        "and so is the inverse hyperbolic sine",
    )
    for mode in _modes():
        assert_equal(
            sinh(tiny, 53, mode).is_zero(),
            False,
            "none of them collapses to nought",
        )
    assert_equal(
        sinh(tiny, 53, RoundingMode.ROUND_DOWN).internal_representation(),
        exactly.internal_representation(),
        "and toward zero the sine is the argument itself",
    )

    # The top of the range: the answer is `Int.MAX ln 2`, near 6.39e18.
    var huge = BigFloat(
        significand=BigInt.one(),
        exponent=Int.MAX - 1,
        precision=1,
        sign=False,
    )
    var at_the_top = arcsinh(huge, 53)
    assert_true(at_the_top.is_finite(), "the inverse sine of a huge argument")
    assert_true(
        at_the_top.exponent > 0, "is an ordinary number with a large exponent"
    )
    assert_true(arccosh(huge, 53).is_finite(), "and so is the inverse cosine")

    # The bottom: the cosine is one, and above it, so toward zero it is one.
    var bottom = BigFloat(
        significand=BigInt.one() << 52,
        exponent=Int.MIN + 52,
        precision=53,
        sign=False,
    )
    assert_equal(
        cosh(bottom, 53).internal_representation(),
        BigFloat.from_int(1, 53).internal_representation(),
        "the hyperbolic cosine at the bottom of the range is one",
    )
    assert_equal(
        cosh(bottom, 53, RoundingMode.ROUND_DOWN).internal_representation(),
        BigFloat.from_int(1, 53).internal_representation(),
        "and toward zero it is still one, since the truth is above it",
    )


def test_a_precision_must_fit_the_guard_bits() raises:
    """A precision has to be positive, and to leave room for guard bits."""
    for precision in [0, -1, Int.MAX, Int.MAX // 4 + 1]:
        for which in range(6):
            var argument = BigFloat.from_string("1.5", 53)
            var raised = False
            try:
                _ = _applied(
                    which, argument, precision, RoundingMode.ROUND_HALF_EVEN
                )
            except:
                raised = True
            assert_true(
                raised,
                String("function ")
                + String(which)
                + " took a precision of "
                + String(precision),
            )


def test_the_inverse_cosine_of_an_infinity() raises:
    """`arccosh` at both infinities, which nothing reached.

    The loop that pushes an infinity through these functions covers the sine
    and its inverse, and the cosine and tangent are done by hand; the inverse
    cosine was left out of both. It rises without bound, so a positive
    infinity is its own answer, and it is undefined below one, so a negative
    infinity is not a number.
    """
    var p = 53
    assert_equal(
        arccosh(BigFloat.infinity(p, False), p).is_infinite(),
        True,
        "the inverse cosine of a positive infinity",
    )
    assert_equal(
        arccosh(BigFloat.infinity(p, False), p).sign,
        False,
        "and it is the positive one",
    )
    assert_equal(
        arccosh(BigFloat.infinity(p, True), p).is_nan(),
        True,
        "the inverse cosine of a negative infinity is not a number",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
