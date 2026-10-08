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
Tests pi, the logarithm of two, and Euler's number, and the loop that decides
a rounding.

The three constants are checked against references computed another way. Pi
comes from Chudnovsky's series, which shares no formula with the Machin one
under test. The logarithm and the number come from CPython's own `decimal`
module, which is a different implementation of each. Every value is taken to
four hundred digits and then rounded to the bits asked for by a short program
working in exact rationals, so the table below is the correctly rounded
answer and not a transcription of one.

The driver that decides those roundings has a test of its own: a kernel that
sits exactly on a rounding boundary at every width it is asked for can never
settle, and the loop has to give up and say so rather than widen for ever.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.constants import e, ln2, pi
from decimo.bigfloat.exponential import round_by_deciding
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


def test_the_constants_are_correctly_rounded() raises:
    """Three constants at four precisions in all seven modes.

    The widest is four hundred bits, which is where a series that is a little
    wrong stops looking right.
    """
    var modes = _modes()
    var which = [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
    ]
    var precisions = [
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        113,
        113,
        113,
        113,
        113,
        113,
        113,
        400,
        400,
        400,
        400,
        400,
        400,
        400,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        113,
        113,
        113,
        113,
        113,
        113,
        113,
        400,
        400,
        400,
        400,
        400,
        400,
        400,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        113,
        113,
        113,
        113,
        113,
        113,
        113,
        400,
        400,
        400,
        400,
        400,
        400,
        400,
    ]
    var picks = [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
    ]
    var significands = [
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("7074237752028440"),
        String("7074237752028441"),
        String("7074237752028441"),
        String("7074237752028440"),
        String("7074237752028440"),
        String("7074237752028440"),
        String("7074237752028440"),
        String("8156040833015188200833743081374136"),
        String("8156040833015188200833743081374137"),
        String("8156040833015188200833743081374137"),
        String("8156040833015188200833743081374136"),
        String("8156040833015188200833743081374136"),
        String("8156040833015188200833743081374136"),
        String("8156040833015188200833743081374136"),
        String(
            "2028094311682742809715567837825223629790287900044816300897797759403807726343497624686380840231704203856891694931831894059"
        ),
        String(
            "2028094311682742809715567837825223629790287900044816300897797759403807726343497624686380840231704203856891694931831894060"
        ),
        String(
            "2028094311682742809715567837825223629790287900044816300897797759403807726343497624686380840231704203856891694931831894060"
        ),
        String(
            "2028094311682742809715567837825223629790287900044816300897797759403807726343497624686380840231704203856891694931831894059"
        ),
        String(
            "2028094311682742809715567837825223629790287900044816300897797759403807726343497624686380840231704203856891694931831894059"
        ),
        String(
            "2028094311682742809715567837825223629790287900044816300897797759403807726343497624686380840231704203856891694931831894059"
        ),
        String(
            "2028094311682742809715567837825223629790287900044816300897797759403807726343497624686380840231704203856891694931831894059"
        ),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("6243314768165359"),
        String("6243314768165360"),
        String("6243314768165360"),
        String("6243314768165359"),
        String("6243314768165359"),
        String("6243314768165359"),
        String("6243314768165359"),
        String("7198051856247353947080814903691237"),
        String("7198051856247353947080814903691238"),
        String("7198051856247353947080814903691238"),
        String("7198051856247353947080814903691237"),
        String("7198051856247353947080814903691238"),
        String("7198051856247353947080814903691238"),
        String("7198051856247353947080814903691238"),
        String(
            "1789879222497203190815761498240779176894896805856420935579692301363062920687047601279850318367644315849030039181347319086"
        ),
        String(
            "1789879222497203190815761498240779176894896805856420935579692301363062920687047601279850318367644315849030039181347319087"
        ),
        String(
            "1789879222497203190815761498240779176894896805856420935579692301363062920687047601279850318367644315849030039181347319087"
        ),
        String(
            "1789879222497203190815761498240779176894896805856420935579692301363062920687047601279850318367644315849030039181347319086"
        ),
        String(
            "1789879222497203190815761498240779176894896805856420935579692301363062920687047601279850318367644315849030039181347319087"
        ),
        String(
            "1789879222497203190815761498240779176894896805856420935579692301363062920687047601279850318367644315849030039181347319087"
        ),
        String(
            "1789879222497203190815761498240779176894896805856420935579692301363062920687047601279850318367644315849030039181347319087"
        ),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("6121026514868073"),
        String("6121026514868074"),
        String("6121026514868074"),
        String("6121026514868073"),
        String("6121026514868073"),
        String("6121026514868073"),
        String("6121026514868073"),
        String("7057063099260103890616691862818426"),
        String("7057063099260103890616691862818427"),
        String("7057063099260103890616691862818427"),
        String("7057063099260103890616691862818426"),
        String("7057063099260103890616691862818426"),
        String("7057063099260103890616691862818426"),
        String("7057063099260103890616691862818426"),
        String(
            "1754820730036057131751068110207841707631642701020512920509980936322743960692449046712617228088912792693699020939494749825"
        ),
        String(
            "1754820730036057131751068110207841707631642701020512920509980936322743960692449046712617228088912792693699020939494749826"
        ),
        String(
            "1754820730036057131751068110207841707631642701020512920509980936322743960692449046712617228088912792693699020939494749826"
        ),
        String(
            "1754820730036057131751068110207841707631642701020512920509980936322743960692449046712617228088912792693699020939494749825"
        ),
        String(
            "1754820730036057131751068110207841707631642701020512920509980936322743960692449046712617228088912792693699020939494749826"
        ),
        String(
            "1754820730036057131751068110207841707631642701020512920509980936322743960692449046712617228088912792693699020939494749826"
        ),
        String(
            "1754820730036057131751068110207841707631642701020512920509980936322743960692449046712617228088912792693699020939494749826"
        ),
    ]
    var exponents = [
        1,
        2,
        2,
        1,
        2,
        2,
        2,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -111,
        -111,
        -111,
        -111,
        -111,
        -111,
        -111,
        -398,
        -398,
        -398,
        -398,
        -398,
        -398,
        -398,
        -1,
        0,
        0,
        -1,
        -1,
        -1,
        -1,
        -53,
        -53,
        -53,
        -53,
        -53,
        -53,
        -53,
        -113,
        -113,
        -113,
        -113,
        -113,
        -113,
        -113,
        -400,
        -400,
        -400,
        -400,
        -400,
        -400,
        -400,
        1,
        2,
        2,
        1,
        1,
        1,
        1,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -111,
        -111,
        -111,
        -111,
        -111,
        -111,
        -111,
        -398,
        -398,
        -398,
        -398,
        -398,
        -398,
        -398,
    ]
    for i in range(len(which)):
        var got = pi(precisions[i], modes[picks[i]])
        if which[i] == 1:
            got = ln2(precisions[i], modes[picks[i]])
        elif which[i] == 2:
            got = e(precisions[i], modes[picks[i]])
        assert_equal(
            got.internal_representation(),
            significands[i]
            + "p"
            + String(exponents[i])
            + "@"
            + String(precisions[i]),
            String("constant ")
            + String(which[i])
            + " at "
            + String(precisions[i])
            + " bits, "
            + String(modes[picks[i]]),
        )


def test_none_of_them_is_ever_exact() raises:
    """An irrational number is between two floats at every precision.

    So the two directed modes must differ, and by exactly one unit in the
    last place: a value that came back the same both ways would mean the
    series had stopped short and the rounding had nothing left to decide.
    """
    for precision in [1, 2, 17, 53, 113, 200]:
        for which in [0, 1, 2]:
            var down = pi(precision, RoundingMode.ROUND_DOWN)
            var up = pi(precision, RoundingMode.ROUND_UP)
            if which == 1:
                down = ln2(precision, RoundingMode.ROUND_DOWN)
                up = ln2(precision, RoundingMode.ROUND_UP)
            elif which == 2:
                down = e(precision, RoundingMode.ROUND_DOWN)
                up = e(precision, RoundingMode.ROUND_UP)
            assert_true(down < up, "the two sides differ")
            # One unit apart, which the significands show unless the step
            # carried into the next binade.
            var stepped = BigFloat.from_rounded_parts(
                down.significand + BigInt.one(),
                down.exponent,
                precision,
                False,
            )
            assert_equal(
                up.internal_representation(),
                stepped.internal_representation(),
                "and by exactly one unit in the last place",
            )


def test_a_wider_answer_truncates_to_a_narrower_one() raises:
    """Truncating a truncation is truncating once, so these have to agree.

    `pi` at four hundred bits toward zero is a prefix of pi's bits, and
    taking fifty-three of those is the same as asking for fifty-three toward
    zero. This is the one check that does not depend on the reference at all:
    it only says the series and the rounding are consistent with themselves.
    """
    for which in [0, 1, 2]:
        var wide = pi(400, RoundingMode.ROUND_DOWN)
        var narrow = pi(53, RoundingMode.ROUND_DOWN)
        if which == 1:
            wide = ln2(400, RoundingMode.ROUND_DOWN)
            narrow = ln2(53, RoundingMode.ROUND_DOWN)
        elif which == 2:
            wide = e(400, RoundingMode.ROUND_DOWN)
            narrow = e(53, RoundingMode.ROUND_DOWN)
        var cut = BigFloat.from_rounded_parts(
            wide.significand,
            wide.exponent,
            53,
            False,
            RoundingMode.ROUND_DOWN,
        )
        assert_equal(
            cut.internal_representation(),
            narrow.internal_representation(),
            "the wide answer cut down is the narrow answer",
        )


def _kernel_on_the_boundary(width: Int) raises -> BigFloat:
    """A value sitting exactly on a ten-bit rounding boundary, at any width.

    Args:
        width: The bits asked for.

    Returns:
        `2^(width-1) + 2^(width-11)`, whose first ten bits are followed by a
        one and then zeros -- an exact half of the tenth bit's last place,
        however wide the value is asked for.

    Raises:
        Error: Propagated from the construction.
    """
    var significand = (BigInt.one() << (width - 1)) + (
        BigInt.one() << (width - 11)
    )
    return BigFloat(
        significand=significand, exponent=0, precision=width, sign=False
    )


def test_the_loop_gives_up_rather_than_widening_for_ever() raises:
    """A kernel that never settles has to end in an error, not a hang.

    This one answers with an exact half at every width, so no amount of extra
    width decides the rounding. That cannot happen to a real series, whose
    value is somewhere definite, which is why the limit is a guard against a
    kernel that is wrong about its own error rather than a case anyone meets.
    """
    var raised = False
    try:
        _ = round_by_deciding[_kernel_on_the_boundary, 2](
            10, RoundingMode.ROUND_HALF_EVEN
        )
    except:
        raised = True
    assert_true(raised, "the loop widened for ever instead of giving up")

    # The same kernel with a mode that has nothing to decide at a half comes
    # straight back, which says the giving up is about the boundary and not
    # about the kernel.
    assert_true(
        round_by_deciding[_kernel_on_the_boundary, 2](
            10, RoundingMode.ROUND_DOWN
        ).precision
        == 10,
        "a mode that truncates settles at once",
    )


def test_a_precision_must_fit_the_guard_bits() raises:
    """A precision has to be positive, and to leave room for guard bits.

    The loop asks for twelve bits beyond the precision before it starts, and
    the series carry more on top of that, so a precision near `Int.MAX` would
    wrap rather than round.
    """
    for precision in [0, -1, Int.MAX, Int.MAX // 4 + 1]:
        for which in [0, 1, 2]:
            var raised = False
            try:
                if which == 0:
                    _ = pi(precision)
                elif which == 1:
                    _ = ln2(precision)
                else:
                    _ = e(precision)
            except:
                raised = True
            assert_true(
                raised,
                String("a constant at ")
                + String(precision)
                + " bits was accepted",
            )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
