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


"""Tests the IEEE 754 companion operations of `BigFloat`.

The reference is CPython, and at 53 bits inside the range of a double it is
an exact one: `math.nextafter`, `math.frexp`, `math.ldexp`, `math.copysign`,
`float.is_integer`, `math.trunc`, `math.floor`, `math.ceil`, `math.fma`,
`math.remainder` and `math.fmod` all answer these questions exactly, and
every one of them was used.

Past 53 bits there is no such oracle, so the expectations come from a program
working in exact integers and `fractions.Fraction` -- never a float, and
never a value recalled from anywhere. That program's answers were first
checked against the CPython functions above on 26,323 cases where a double's
format and this one agree, which is what makes it usable where they do not,
and then the two were run against each other over 54,100 cases: all seven
rounding modes, precisions from one bit to two hundred, exponents from
`Int.MIN` to `Int.MAX`, the signed zeros, both infinities and the NaN. The
rows below are a sample of those, kept as a regression table, with the ends
of the exponent range written out by hand underneath because that is where
this type's answers are its own rather than a double's.

Two of the sampled operations earn their rows in particular. Of the 12,223
`fma` cases on finite non-zero factors, 5,233 give a different answer if the
product is rounded before `z` is added, which is the whole point of the
operation. And of the 8,580 remainder cases, 584 have a quotient above `2^64`
-- which is what the modular reduction in `_remainder()` is for, since the
shift that would form that quotient cannot be allocated.
"""

from std import testing
from std.testing import assert_equal, assert_false, assert_true

from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.ieee import (
    ceil,
    copy_abs,
    copy_negate,
    copy_sign,
    floor,
    fma,
    fmod,
    is_integer,
    logb,
    next_minus,
    next_plus,
    next_toward,
    number_class,
    remainder,
    round_to_integer,
    scaleb,
    truncate,
)
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


def _modes() -> List[RoundingMode]:
    """All seven of them, in the order the rounding primitive documents them.

    Returns:
        The modes.
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


def _parse(
    sign: StringSlice,
    significand: StringSlice,
    exponent: StringSlice,
    precision: StringSlice,
) raises -> BigFloat:
    """A value from the four fields a table row spells it with.

    Args:
        sign: `1` for a negative value.
        significand: The significand, as decimal digits.
        exponent: The power of two.
        precision: The bits the significand holds.

    Returns:
        The value.

    Raises:
        Error: Propagated from the construction.
    """
    return BigFloat(
        significand=BigInt(String(significand)),
        exponent=Int(String(exponent)),
        precision=Int(String(precision)),
        sign=String(sign) == "1",
    )


def test_the_neighbours_are_what_the_reference_steps_to() raises:
    """One hundred and ten steps, at precisions from one bit to two hundred.

    The rows include the ends of the exponent range, where a step can land on
    a zero or an infinity, and values whose own precision is wider than the
    one being stepped at, where the step is to a value the destination holds
    rather than by a unit of the argument's last place.
    """
    # op sign significand exponent precision destination expected
    var cases = [
        (
            "np 1 8618666776790173885971950546553630 -9223372036854775808 113"
            " 113 -8618666776790173885971950546553629p-9223372036854775808@113"
        ),
        "np 1 4 -9223372036854775807 3 53 -0p0@53",
        "np 0 4757611548438660 9223372036854775806 53 2 Infinity",
        "np 1 9691232725759754741 197 64 53 -4732047229374880p208@53",
        (
            "np 0 2 -9223372036854775807 2 53"
            " 4503599627370496p-9223372036854775808@53"
        ),
        "np 0 1 393 1 53 4503599627370497p341@53",
        "np 1 4988504958727022 -32 53 11 -1134p10@11",
        "np 0 9003611858698103 50 53 11 1024p93@11",
        (
            "np 1 5192296858534827628530496329220096 9223372036854775694 113 1"
            " -1p9223372036854775805@1"
        ),
        (
            "np 0 5192296858534827628530496329220096 -7 113 113"
            " 5192296858534827628530496329220097p-7@113"
        ),
        "np 0 3 9223372036854775807 2 2 Infinity",
        "np 0 5841807765618196 -44 53 11 1329p-2@11",
        "np 1 8775502204871601 -218 53 11 -1995p-176@11",
        "np 1 5 -9223372036854775806 3 1 -1p-9223372036854775804@1",
        "np 1 7 -278 3 3 -6p-278@3",
        "np 1 3 9223372036854775806 2 1 -1p9223372036854775807@1",
        (
            "np 1 5192296858534827628530496329220097 9223372036854775806 113"
            " 200 -803469022129495137770981046170581456003606407563930780041215p9223372036854775719@200"
        ),
        "np 1 1 -9223372036854775808 1 53 -0p0@53",
        "np 1 6 -9223372036854775802 3 200 -0p0@200",
        "np 0 1 366 1 1 1p367@1",
        "np 1 5326611719876692 -12 53 11 -1211p30@11",
        "np 1 3 -6 2 2 -2p-6@2",
        "np 0 4503599627370497 -42 53 53 4503599627370498p-42@53",
        "np 0 94957 368 17 17 94958p368@17",
        (
            "np 1 10384593717069655257060992658440191 -9223372036854775582 113"
            " 1 -1p-9223372036854775470@1"
        ),
        (
            "np 0 7 -9223372036854775802 3 53"
            " 4503599627370496p-9223372036854775808@53"
        ),
        "np 1 3 -226 2 2 -2p-226@2",
        "np 0 5629499534213120 -51 53 53 5629499534213121p-51@53",
        "np 0 4 -91 3 53 4503599627370497p-141@53",
        (
            "np 1 8618666776790173885971950546553630 -9223372036854775695 113 1"
            " -1p-9223372036854775583@1"
        ),
        (
            "np 0 9007199254740991 -9223372036854775807 53 53"
            " 4503599627370496p-9223372036854775806@53"
        ),
        "np 0 9007199254740991 9223372036854775806 53 1 Infinity",
        "np 0 2 308 2 2 3p308@2",
        (
            "np 1 4503599627370496 -9223372036854775807 53 2"
            " -3p-9223372036854775757@2"
        ),
        "np 1 3 9223372036854775807 2 1 -1p9223372036854775807@1",
        "np 0 65536 -7 17 17 65537p-7@17",
        (
            "np 0 1 -9223372036854775807 1 200"
            " 803469022129495137770981046170581301261101496891396417650688p-9223372036854775808@200"
        ),
        "np 1 2 -11 2 2 -3p-12@2",
        "np 0 3 -9223372036854775807 2 1 1p-9223372036854775805@1",
        "np 0 6 -9223372036854775808 3 3 7p-9223372036854775808@3",
        "np 1 4693079787075283 36 53 53 -4693079787075282p36@53",
        "np 1 7335476515461358 -195 53 11 -1667p-153@11",
        (
            "np 0 7 9223372036854775804 3 53"
            " 7881299347898369p9223372036854775754@53"
        ),
        (
            "np 1 4503599627370497 -9223372036854775755 53 2"
            " -2p-9223372036854775704@2"
        ),
        "np 0 86518 304 17 11 1352p310@11",
        "np 1 5 -9223372036854775802 3 1 -1p-9223372036854775800@1",
        "np 1 4985194856987896 -43 53 53 -4985194856987895p-43@53",
        (
            "np 0 10384593717069655257060992658440191 -9223372036854775807 113"
            " 53 4503599627370496p-9223372036854775746@53"
        ),
        "np 0 8234446219916488522673543763043794 -305 113 11 1624p-203@11",
        (
            "np 0 4503599627370497 -9223372036854775702 53 200"
            " 803469022129495137770981046170581301261101496891396417650688p-9223372036854775808@200"
        ),
        (
            "np 1 10384593717069655257060992658440191 -9223372036854775808 113"
            " 113 -10384593717069655257060992658440190p-9223372036854775808@113"
        ),
        "np 0 5621259607211694 -98 53 53 5621259607211695p-98@53",
        "np 1 6 -208 3 3 -5p-208@3",
        "np 1 7 -9223372036854775806 3 200 -0p0@200",
        "np 0 9007199254740991 -8 53 11 1024p35@11",
        (
            "nm 1 8618666776790173885971950546553630 -9223372036854775808 113"
            " 113 -8618666776790173885971950546553631p-9223372036854775808@113"
        ),
        (
            "nm 1 4 -9223372036854775807 3 53"
            " -4503599627370496p-9223372036854775808@53"
        ),
        (
            "nm 0 4757611548438660 9223372036854775806 53 2"
            " 3p9223372036854775807@2"
        ),
        "nm 1 9691232725759754741 197 64 53 -4732047229374881p208@53",
        "nm 0 2 -9223372036854775807 2 53 0p0@53",
        "nm 0 1 393 1 53 9007199254740991p340@53",
        "nm 1 4988504958727022 -32 53 11 -1135p10@11",
        "nm 0 9003611858698103 50 53 11 2047p92@11",
        (
            "nm 1 5192296858534827628530496329220096 9223372036854775694 113 1"
            " -1p9223372036854775807@1"
        ),
        (
            "nm 0 5192296858534827628530496329220096 -7 113 113"
            " 10384593717069655257060992658440191p-8@113"
        ),
        "nm 0 3 9223372036854775807 2 2 2p9223372036854775807@2",
        "nm 0 5841807765618196 -44 53 11 1328p-2@11",
        "nm 1 8775502204871601 -218 53 11 -1996p-176@11",
        "nm 1 5 -9223372036854775806 3 1 -1p-9223372036854775803@1",
        "nm 1 7 -278 3 3 -4p-277@3",
        "nm 1 3 9223372036854775806 2 1 -Infinity",
        (
            "nm 1 5192296858534827628530496329220097 9223372036854775806 113"
            " 200 -803469022129495137770981046170581456003606407563930780041217p9223372036854775719@200"
        ),
        (
            "nm 1 1 -9223372036854775808 1 53"
            " -4503599627370496p-9223372036854775808@53"
        ),
        (
            "nm 1 6 -9223372036854775802 3 200"
            " -803469022129495137770981046170581301261101496891396417650688p-9223372036854775808@200"
        ),
        "nm 0 1 366 1 1 1p365@1",
        "nm 1 5326611719876692 -12 53 11 -1212p30@11",
        "nm 1 3 -6 2 2 -2p-5@2",
        "nm 0 4503599627370497 -42 53 53 4503599627370496p-42@53",
        "nm 0 94957 368 17 17 94956p368@17",
        (
            "nm 1 10384593717069655257060992658440191 -9223372036854775582 113"
            " 1 -1p-9223372036854775469@1"
        ),
        "nm 0 7 -9223372036854775802 3 53 0p0@53",
        "nm 1 3 -226 2 2 -2p-225@2",
        "nm 0 5629499534213120 -51 53 53 5629499534213119p-51@53",
        "nm 0 4 -91 3 53 9007199254740991p-142@53",
        (
            "nm 1 8618666776790173885971950546553630 -9223372036854775695 113 1"
            " -1p-9223372036854775582@1"
        ),
        (
            "nm 0 9007199254740991 -9223372036854775807 53 53"
            " 9007199254740990p-9223372036854775807@53"
        ),
        (
            "nm 0 9007199254740991 9223372036854775806 53 1"
            " 1p9223372036854775807@1"
        ),
        "nm 0 2 308 2 2 3p307@2",
        (
            "nm 1 4503599627370496 -9223372036854775807 53 2"
            " -3p-9223372036854775756@2"
        ),
        "nm 1 3 9223372036854775807 2 1 -Infinity",
        "nm 0 65536 -7 17 17 131071p-8@17",
        "nm 0 1 -9223372036854775807 1 200 0p0@200",
        "nm 1 2 -11 2 2 -3p-11@2",
        "nm 0 3 -9223372036854775807 2 1 1p-9223372036854775806@1",
        "nm 0 6 -9223372036854775808 3 3 5p-9223372036854775808@3",
        "nm 1 4693079787075283 36 53 53 -4693079787075284p36@53",
        "nm 1 7335476515461358 -195 53 11 -1668p-153@11",
        (
            "nm 0 7 9223372036854775804 3 53"
            " 7881299347898367p9223372036854775754@53"
        ),
        (
            "nm 1 4503599627370497 -9223372036854775755 53 2"
            " -3p-9223372036854775704@2"
        ),
        "nm 0 86518 304 17 11 1351p310@11",
        "nm 1 5 -9223372036854775802 3 1 -1p-9223372036854775799@1",
        "nm 1 4985194856987896 -43 53 53 -4985194856987897p-43@53",
        (
            "nm 0 10384593717069655257060992658440191 -9223372036854775807 113"
            " 53 9007199254740991p-9223372036854775747@53"
        ),
        "nm 0 8234446219916488522673543763043794 -305 113 11 1623p-203@11",
        "nm 0 4503599627370497 -9223372036854775702 53 200 0p0@200",
        (
            "nm 1 10384593717069655257060992658440191 -9223372036854775808 113"
            " 113 -5192296858534827628530496329220096p-9223372036854775807@113"
        ),
        "nm 0 5621259607211694 -98 53 53 5621259607211693p-98@53",
        "nm 1 6 -208 3 3 -7p-208@3",
        (
            "nm 1 7 -9223372036854775806 3 200"
            " -803469022129495137770981046170581301261101496891396417650688p-9223372036854775808@200"
        ),
        "nm 0 9007199254740991 -8 53 11 2047p34@11",
    ]
    for row in cases:
        var field = row.split(" ")
        var x = _parse(field[1], field[2], field[3], field[4])
        var destination = Int(String(field[5]))
        var got = next_plus(x, destination) if field[0] == "np" else next_minus(
            x, destination
        )
        assert_equal(
            got.internal_representation(),
            String(field[6]),
            String("case ") + row,
        )


def test_the_neighbours_at_the_ends_of_the_exponent_range() raises:
    """The four identities the exponent range's ends are designed to have.

    The exponent is an `Int`, so unlike the decimal side there is a smallest
    positive value and a largest finite one at every precision, and the
    standard's answers apply: below the smallest is a zero and above the
    largest is an infinity. The four steps therefore round-trip, which is the
    property worth asserting -- the values themselves are enormous and say
    little on their own.
    """
    for precision in [1, 2, 53, 113]:
        var smallest = next_plus(BigFloat.zero(precision), precision)
        assert_equal(
            smallest.exponent,
            Int.MIN,
            "the smallest positive value sits at the bottom exponent",
        )
        assert_equal(
            next_minus(smallest, precision).internal_representation(),
            BigFloat.zero(precision).internal_representation(),
            "and steps back to a zero",
        )
        var below = next_minus(BigFloat.zero(precision), precision)
        assert_true(below.sign, "the step below a zero is negative")
        assert_equal(
            next_plus(below, precision).internal_representation(),
            BigFloat.zero(precision, True).internal_representation(),
            "and steps back to the negative zero",
        )

        var largest = next_minus(BigFloat.infinity(precision), precision)
        assert_equal(
            largest.exponent,
            Int.MAX,
            "the largest finite value sits at the top exponent",
        )
        assert_equal(
            largest.significand.bit_length(),
            precision,
            "with every bit of its significand set",
        )
        assert_true(
            next_plus(largest, precision).is_infinite(),
            "and steps back to an infinity",
        )
        assert_true(
            next_plus(BigFloat.infinity(precision), precision).is_infinite(),
            "a step outward from an infinity stays on it",
        )
        assert_true(
            next_minus(
                BigFloat.infinity(precision, True), precision
            ).is_infinite(),
            "and so does the other one",
        )
        assert_true(
            next_plus(BigFloat.nan(precision), precision).is_nan(),
            "a NaN steps to a NaN",
        )


def test_next_toward_steps_and_copies_the_sign() raises:
    """The direction comes from the comparison, and a tie copies the sign."""
    var one = BigFloat.from_float64(1.0)
    var two = BigFloat.from_float64(2.0)
    assert_equal(
        next_toward(one, two, 53).internal_representation(),
        next_plus(one, 53).internal_representation(),
        "toward a larger value is a step up",
    )
    assert_equal(
        next_toward(two, one, 53).internal_representation(),
        next_minus(two, 53).internal_representation(),
        "toward a smaller value is a step down",
    )
    assert_equal(
        next_toward(one, one, 53).internal_representation(),
        one.internal_representation(),
        "toward itself is itself",
    )
    # The two zeros compare equal, so this is the one place where two values
    # that compare equal give different answers.
    assert_true(
        next_toward(BigFloat.zero(53, False), BigFloat.zero(53, True), 53).sign,
        "toward the negative zero gives the negative zero",
    )
    assert_false(
        next_toward(BigFloat.zero(53, True), BigFloat.zero(53, False), 53).sign,
        "and the other way round gives the positive one",
    )
    assert_true(
        next_toward(one, BigFloat.nan(), 53).is_nan(),
        "a NaN as the direction gives a NaN",
    )
    # An equal pair keeps the argument's own precision, nothing having been
    # stepped; a step is at the precision asked for.
    assert_equal(
        next_toward(one, one, 7).precision,
        53,
        "an equal pair comes back untouched",
    )
    assert_equal(
        next_toward(one, two, 7).precision,
        7,
        "a step is at the precision asked for",
    )


def test_logb_is_the_leading_bit_position() raises:
    """Forty-five values, and the three that have no answer."""
    # sign significand exponent precision expected
    var cases = [
        "0 2 -9223372036854775807 2 -9223372036854775806",
        "1 4503599627370496 -1126 53 -1074",
        "0 2 308 2 309",
        "0 5841807765618196 -44 53 8",
        "1 7106853526329694 -143 53 -91",
        "0 6 -27 3 -25",
        "1 3 9223372036854775806 2 9223372036854775807",
        "0 18098125771866690742 -123 64 -60",
        "1 6718365449215196 -36 53 16",
        "0 2 -9223372036854775804 2 -9223372036854775803",
        "0 3 -9223372036854775807 2 -9223372036854775806",
        "1 5843798630986447 -119 53 -67",
        "0 1 366 1 366",
        "0 2 -287 2 -286",
        "0 7927298453794917 -234 53 -182",
        "0 4507999739652543 59 53 111",
        "1 7048226953580464 -69 53 -17",
        "0 6 -9223372036854775806 3 -9223372036854775804",
        (
            "1 10384593717069655257060992658440191 -9223372036854775695 113"
            " -9223372036854775583"
        ),
        "0 5621259607211694 -98 53 -46",
        "0 1 -9223372036854775808 1 -9223372036854775808",
        (
            "0 5192296858534827628530496329220096 9223372036854775807 113"
            " 9223372036854775919"
        ),
        "0 4856799838180920 -23 53 29",
        "1 9007199254740991 -9223372036854775756 53 -9223372036854775704",
        "1 6974054154281934 10 53 62",
        "1 7287249723216163 -200 53 -148",
        "1 5663121134418846 -224 53 -172",
        "0 129404 -88 17 -72",
        "1 1 79 1 79",
        "1 6031112255894975 32 53 84",
        "0 5196015499408696 -45 53 7",
        "1 5270117806226951 133 53 185",
        "0 7440706404158016 -43 53 9",
        "0 10694317593848718525 -392 64 -329",
        "0 4503599627370496 -7 53 45",
        "0 4503599627370497 0 53 52",
        "0 9003611858698103 50 53 102",
        "0 6740893541143794 141 53 193",
        "1 7854051913253426 -103 53 -51",
        "0 1 50 1 50",
        "0 8145976407005108482055388084417880 207 113 319",
        (
            "0 8618666776790173885971950546553630 9223372036854775694 113"
            " 9223372036854775806"
        ),
        "1 2 -9223372036854775804 2 -9223372036854775803",
        "1 5083278507167645 -61 53 -9",
        "1 66742 102 17 118",
    ]
    for row in cases:
        var field = row.split(" ")
        var x = _parse(field[0], field[1], field[2], field[3])
        assert_equal(
            String(logb(x)),
            String(field[4]),
            String("case ") + row,
        )

    # The position can be outside an `Int` while the value is an ordinary
    # one, which is why the answer is a `BigInt`.
    var high = BigFloat(
        significand=(BigInt.one() << 53) - BigInt.one(),
        exponent=Int.MAX,
        precision=53,
        sign=False,
    )
    assert_equal(
        String(logb(high)),
        String(BigInt(Int.MAX) + BigInt(52)),
        "a leading bit above Int.MAX is still an answer",
    )

    for which in [0, 1, 2, 3]:
        var raised = False
        try:
            if which == 0:
                _ = logb(BigFloat.zero())
            elif which == 1:
                _ = logb(BigFloat.zero(53, True))
            elif which == 2:
                _ = logb(BigFloat.infinity())
            else:
                _ = logb(BigFloat.nan())
        except:
            raised = True
        assert_true(
            raised,
            String("logb answered case ") + String(which),
        )


def test_scaleb_is_exact_and_refuses_to_wrap() raises:
    """Forty-five scalings, the three special values, and both overflows."""
    # sign significand exponent precision n expected
    var cases = [
        "0 1 50 1 1 1p51@1",
        "0 9223372036854775808 -7 64 -37 9223372036854775808p-44@64",
        "1 6 9223372036854775807 3 -1000 -6p9223372036854774807@3",
        "0 8199519493431715 -126 53 -1000 8199519493431715p-1126@53",
        "0 1 -268 1 -1 1p-269@1",
        "0 5291781364267403 -89 53 1000 5291781364267403p911@53",
        "0 4503599627370496 -53 53 1 4503599627370496p-52@53",
        "0 1 -268 1 0 1p-268@1",
        "0 7821211670638759 124 53 1000 7821211670638759p1124@53",
        "1 4693079787075283 36 53 -1 -4693079787075283p35@53",
        "1 8207977844022428 -45 53 0 -8207977844022428p-45@53",
        "1 4605506877953451 -202 53 0 -4605506877953451p-202@53",
        "0 1 40 1 1 1p41@1",
        "0 8199519493431715 -126 53 -37 8199519493431715p-163@53",
        "0 5772084751525002 185 53 0 5772084751525002p185@53",
        "0 4503599627370497 -105 53 1 4503599627370497p-104@53",
        "1 2 -371 2 1 -2p-370@2",
        "0 111631 -159 17 1 111631p-158@17",
        "1 7262686251997112 3 53 0 -7262686251997112p3@53",
        "1 65536 3 17 -1 -65536p2@17",
        "0 7430177058399976 -18 53 37 7430177058399976p19@53",
        "0 1 174 1 -37 1p137@1",
        "0 5049817356396901 62 53 0 5049817356396901p62@53",
        "1 6 210 3 -1 -6p209@3",
        "1 4503599627370496 -51 53 -37 -4503599627370496p-88@53",
        "1 4503599627370496 -7 53 1 -4503599627370496p-6@53",
        "1 8165182887704884 -40 53 37 -8165182887704884p-3@53",
        "0 7368598785373671 -28 53 1000 7368598785373671p972@53",
        "0 2 -287 2 0 2p-287@2",
        "0 6314228780213667 98 53 -1000 6314228780213667p-902@53",
        "1 7635019515546878 -221 53 -1000 -7635019515546878p-1221@53",
        "1 7134830333310201 -186 53 37 -7134830333310201p-149@53",
        "1 5663121134418846 -224 53 -37 -5663121134418846p-261@53",
        "0 4838335682833238 -244 53 0 4838335682833238p-244@53",
        "1 7128763200983225 -52 53 -37 -7128763200983225p-89@53",
        (
            "1 5192296858534827628530496329220096 9223372036854775806 113 -1"
            " -5192296858534827628530496329220096p9223372036854775805@113"
        ),
        "0 8950472828530190 -198 53 37 8950472828530190p-161@53",
        "1 7885893483396721 -43 53 0 -7885893483396721p-43@53",
        (
            "0 8234446219916488522673543763043794 -305 113 -1"
            " 8234446219916488522673543763043794p-306@113"
        ),
        "1 8128756405888245 37 53 -37 -8128756405888245p0@53",
        (
            "0 4 -9223372036854775802 3 4611686018427387904"
            " 4p-4611686018427387898@3"
        ),
        (
            "1 5192296858534827628530496329220097 9223372036854775694 113 -1000"
            " -5192296858534827628530496329220097p9223372036854774694@113"
        ),
        "0 8616303558427664 -43 53 0 8616303558427664p-43@53",
        "0 1 -3 1 1000 1p997@1",
        (
            "1 5192296858534827628530496329220096 9223372036854775694 113 -1000"
            " -5192296858534827628530496329220096p9223372036854774694@113"
        ),
    ]
    for row in cases:
        var field = row.split(" ")
        var x = _parse(field[0], field[1], field[2], field[3])
        assert_equal(
            scaleb(x, Int(String(field[4]))).internal_representation(),
            String(field[5]),
            String("case ") + row,
        )

    # The special values come back untouched, whatever `n` is.
    for n in [0, 1, Int.MAX, Int.MIN]:
        assert_true(scaleb(BigFloat.nan(), n).is_nan(), "a NaN scales to one")
        assert_true(
            scaleb(BigFloat.infinity(53, True), n).is_infinite(),
            "an infinity scales to one",
        )
        assert_true(
            scaleb(BigFloat.infinity(53, True), n).sign,
            "keeping its sign",
        )
        assert_true(
            scaleb(BigFloat.zero(53, True), n).is_zero(),
            "and a zero to a zero",
        )
        assert_true(
            scaleb(BigFloat.zero(53, True), n).sign, "keeping its sign too"
        )

    var top = BigFloat(
        significand=BigInt.one(), exponent=Int.MAX, precision=1, sign=False
    )
    var bottom = BigFloat(
        significand=BigInt.one(), exponent=Int.MIN, precision=1, sign=False
    )
    for which in [0, 1]:
        var raised = False
        try:
            if which == 0:
                _ = scaleb(top, 1)
            else:
                _ = scaleb(bottom, -1)
        except:
            raised = True
        assert_true(
            raised,
            String("a scaling out of the exponent range was taken, case ")
            + String(which),
        )


def test_the_sign_copies_never_look_at_the_value() raises:
    """All three, on every kind of value, including the two zeros."""
    var positive = BigFloat.from_float64(1.5)
    var negative = BigFloat.from_float64(-1.5)

    assert_equal(
        copy_sign(positive, negative).internal_representation(),
        negative.internal_representation(),
        "a sign copied onto the same magnitude",
    )
    assert_equal(
        copy_sign(negative, positive).internal_representation(),
        positive.internal_representation(),
        "and the other way round",
    )
    assert_equal(
        copy_abs(negative).internal_representation(),
        positive.internal_representation(),
        "copy_abs is abs",
    )
    assert_equal(
        copy_negate(positive).internal_representation(),
        negative.internal_representation(),
        "copy_negate is negation",
    )

    # The zeros, which is where the three are not the same as arithmetic.
    assert_true(
        copy_sign(BigFloat.zero(), negative).sign, "a zero takes a sign"
    )
    assert_true(copy_negate(BigFloat.zero()).sign, "and can be negated")
    assert_false(
        copy_abs(BigFloat.zero(53, True)).sign, "and can lose its sign"
    )

    # The infinities and the NaN. A NaN has no sign here, so it neither takes
    # one nor lends one.
    assert_true(
        copy_sign(BigFloat.infinity(), negative).is_infinite(),
        "an infinity stays an infinity",
    )
    assert_true(
        copy_sign(BigFloat.infinity(), negative).sign, "and takes the sign"
    )
    assert_true(
        copy_sign(BigFloat.nan(), negative).is_nan(), "a NaN stays the NaN"
    )
    assert_false(
        copy_sign(negative, BigFloat.nan()).sign,
        "and the sign it lends is the positive one",
    )
    assert_true(copy_negate(BigFloat.nan()).is_nan(), "a NaN negates to one")
    assert_true(copy_abs(BigFloat.nan()).is_nan(), "and abs of one is one")

    # The precision is carried across, not replaced.
    var wide = BigFloat.from_string("1.5", 200)
    assert_equal(
        copy_sign(wide, negative).precision, 200, "the precision survives"
    )


def test_number_class_names_the_seven_kinds() raises:
    """The seven a binary float without subnormals can be."""
    assert_equal(number_class(BigFloat.nan()), "NaN", "the NaN")
    assert_equal(number_class(BigFloat.infinity()), "+Infinity", "an infinity")
    assert_equal(
        number_class(BigFloat.infinity(53, True)), "-Infinity", "the other"
    )
    assert_equal(number_class(BigFloat.zero()), "+Zero", "a zero")
    assert_equal(
        number_class(BigFloat.zero(53, True)), "-Zero", "the other zero"
    )
    assert_equal(number_class(BigFloat.from_float64(1.5)), "+Normal", "a value")
    assert_equal(
        number_class(BigFloat.from_float64(-1.5)), "-Normal", "a negative one"
    )

    # No value is ever subnormal, whatever its exponent: the significand
    # always holds its full precision.
    var tiny = BigFloat(
        significand=BigInt.one(), exponent=Int.MIN, precision=1, sign=False
    )
    assert_equal(
        number_class(tiny),
        "+Normal",
        "a value at the bottom of the exponent range is still normal",
    )


def test_is_integer_reads_the_trailing_zeros() raises:
    """Whole numbers, fractions, and the cases that cannot be reached."""
    assert_true(is_integer(BigFloat.from_float64(2.0)), "two is whole")
    assert_true(is_integer(BigFloat.from_float64(-4.0)), "and minus four")
    assert_false(is_integer(BigFloat.from_float64(1.5)), "three halves is not")
    assert_false(is_integer(BigFloat.from_float64(-0.25)), "nor a quarter")
    assert_true(is_integer(BigFloat.zero()), "a zero is whole")
    assert_true(is_integer(BigFloat.zero(53, True)), "and so is the other")
    assert_false(is_integer(BigFloat.infinity()), "an infinity is not")
    assert_false(is_integer(BigFloat.nan()), "nor is a NaN")

    # A value far above the point, where the exponent alone answers.
    var high = BigFloat(
        significand=BigInt.one(), exponent=Int.MAX, precision=1, sign=False
    )
    assert_true(is_integer(high), "a power of two that large is whole")

    # A value far below it, where negating the exponent would overflow if the
    # precision were not consulted first.
    var low = BigFloat(
        significand=BigInt.one(), exponent=Int.MIN, precision=1, sign=False
    )
    assert_false(is_integer(low), "and one that small is not")

    # Trailing zeros exactly reaching the point, and one short of it.
    var reaching = BigFloat(
        significand=BigInt(0b1100), exponent=-2, precision=4, sign=False
    )
    assert_true(is_integer(reaching), "three with two zeros below it")
    var short = BigFloat(
        significand=BigInt(0b1100), exponent=-3, precision=4, sign=False
    )
    assert_false(is_integer(short), "and the same bits one place lower")


def test_the_roundings_to_a_whole_number() raises:
    """Ninety rows over all seven modes, and the three named roundings."""
    var modes = _modes()
    # sign significand exponent precision mode expected
    var cases = [
        "1 7159282641069312 -43 53 2 -7151223627055104p-43@53",
        "1 4503599627370496 -56 53 5 -0p0@53",
        (
            "1 1524793041903491993134654299275007375288348469745773572225673"
            " -344 200 6 -0p0@200"
        ),
        "0 4 -91 3 1 4p-2@3",
        "0 8020506804089068 -43 53 4 8022036836253696p-43@53",
        "0 4946543799024035 -20 53 6 4946543798910976p-20@53",
        "0 4503599627370497 -56 53 6 0p0@53",
        "0 4757611548438660 -9223372036854775756 53 4 0p0@53",
        "0 6465168051726267 -56 53 1 4503599627370496p-52@53",
        "1 6242009209695831 -14 53 5 -6242009209700352p-14@53",
        "1 6761283346919146 -99 53 3 -4503599627370496p-52@53",
        "0 4503599627370496 -1074 53 1 4503599627370496p-52@53",
        "0 7612567650439753 -166 53 1 4503599627370496p-52@53",
        "0 3 -9223372036854775807 2 3 0p0@2",
        "1 4503599627370496 -35 53 3 -4503599627370496p-35@53",
        "1 8160357848141483 -71 53 1 -4503599627370496p-52@53",
        "0 1 -2 1 6 0p0@1",
        "1 8393010543162061 -63 53 6 -0p0@53",
        "0 6103000160861147 -48 53 4 6192449487634432p-48@53",
        "0 6730556051714706 -208 53 6 0p0@53",
        "0 6913655986311817 -53 53 4 4503599627370496p-52@53",
        (
            "0 5192296858534827628530496329220097 -9223372036854775695 113 2"
            " 5192296858534827628530496329220096p-112@113"
        ),
        "1 4 -9223372036854775807 3 4 -0p0@3",
        "1 8427442592093908 -45 53 5 -8444249301319680p-45@53",
        "0 1 -133 1 2 1p0@1",
        "1 8393010543162061 -63 53 3 -4503599627370496p-52@53",
        "0 4503599627370496 -105 53 1 4503599627370496p-52@53",
        "0 7289095236008992 -44 53 2 7300757208432640p-44@53",
        "1 2 -371 2 6 -0p0@2",
        "0 5623326970468278 -43 53 6 5620703441190912p-43@53",
        "0 1 -9223372036854775807 1 0 0p0@1",
        "0 1 -177 1 6 0p0@1",
        "1 6054129892188666 -163 53 2 -0p0@53",
        (
            "0 1298292036970166521000973810584086973285136930400884627443725"
            " -371 200 5 0p0@200"
        ),
        "1 8111841058159772 -59 53 5 -0p0@53",
        "0 6503082623012079 -156 53 3 0p0@53",
        "1 5 -9223372036854775807 3 4 -0p0@3",
        "0 3 -263 2 4 0p0@2",
        "1 8384259453450449 -43 53 4 -8382676650164224p-43@53",
        "0 9007199254740991 -99 53 1 4503599627370496p-52@53",
        "1 8684292029818906 -109 53 2 -0p0@53",
        "0 8736554208067760 -43 53 3 8734520371052544p-43@53",
        "0 4 -9223372036854775805 3 5 0p0@3",
        (
            "1 5192296858534827628530496329220096 -9223372036854775807 113 4"
            " -0p0@113"
        ),
        "0 6826265422024900 -44 53 6 6825768185233408p-44@53",
        "0 5841807765618196 -44 53 4 5840605766746112p-44@53",
        "1 7048226953580464 -69 53 6 -0p0@53",
        (
            "1 5192296858534827628530496329220097 -9223372036854775696 113 5"
            " -0p0@113"
        ),
        "1 9007199254740991 -9223372036854775702 53 5 -0p0@53",
        "1 5039064640229396 -7 53 2 -5039064640229376p-7@53",
        "1 7346514577956487 -124 53 1 -4503599627370496p-52@53",
        "0 4757611548438660 -9223372036854775702 53 6 0p0@53",
        "0 6726000402477848777805226520456120 -334 113 4 0p0@113",
        "1 4503599627370497 -9223372036854775808 53 6 -0p0@53",
        "1 2 -370 2 4 -0p0@2",
        "1 7881299347898368 -51 53 5 -6755399441055744p-51@53",
        "1 5540387740821467 -49 53 5 -5629499534213120p-49@53",
        "1 4503599627370496 -77 53 1 -4503599627370496p-52@53",
        (
            "1 1186355499180986313119437448176114865426867585542407893259944"
            " -309 200 0 -0p0@200"
        ),
        "1 9007199254740991 -9223372036854775808 53 1 -4503599627370496p-52@53",
        "0 8340055682314848 -43 53 6 8338696185053184p-43@53",
        "1 7 -9223372036854775802 3 3 -4p-2@3",
        "0 4503599627370496 -7 53 2 4503599627370496p-7@53",
        "0 65536 -7 17 4 65536p-7@17",
        "1 123475 -255 17 4 -0p0@17",
        "0 6618393530861898 -43 53 0 6614661952700416p-43@53",
        "0 7545063175596616 -290 53 5 0p0@53",
        (
            "1 1501811781304310270498565773973645589386785052920291733526153"
            " -76 200 4"
            " -1501811781304310270498565773973645589362192100754222366064640p-76@200"
        ),
        "1 6 -228 3 1 -4p-2@3",
        "1 4503599627370496 -53 53 0 -0p0@53",
        (
            "1 1241265883521262003707475445775263861483847417925051315040289"
            " -302 200 2 -0p0@200"
        ),
        "0 5827044391762040 -149 53 4 0p0@53",
        "0 2 -13 2 3 0p0@2",
        "0 5708172802043008 -44 53 0 5699868278390784p-44@53",
        "0 5150180762015262 -95 53 4 0p0@53",
        "0 9007199254740991 -9223372036854775807 53 6 0p0@53",
        (
            "1 7005254751962697148846172790176074 -218 113 1"
            " -5192296858534827628530496329220096p-112@113"
        ),
        "0 7408903361268171 -201 53 1 4503599627370496p-52@53",
        "1 4626249013895879 -6 53 3 -4626249013895936p-6@53",
        "0 131071 -3 17 0 131064p-3@17",
        "1 8028585859111900 -94 53 6 -0p0@53",
        (
            "1 5192296858534827628530496329220097 -9223372036854775696 113 1"
            " -5192296858534827628530496329220096p-112@113"
        ),
        "0 5708172802043008 -44 53 1 5717460464435200p-44@53",
        "0 7519311392524389 -39 53 2 7519560022360064p-39@53",
        "0 8616303558427664 -43 53 5 8620171161763840p-43@53",
        "0 9007199254740991 -113 53 4 0p0@53",
        "0 1 -9223372036854775807 1 2 1p0@1",
        "1 7460755644004508 -60 53 5 -0p0@53",
        "0 3 -9223372036854775806 2 0 0p0@2",
        "1 8865314385406270 -56 53 5 -0p0@53",
    ]
    for row in cases:
        var field = row.split(" ")
        var x = _parse(field[0], field[1], field[2], field[3])
        var mode = modes[Int(String(field[4]))]
        assert_equal(
            round_to_integer(x, mode).internal_representation(),
            String(field[5]),
            String("case ") + row,
        )

    # The three named ones are the three directed modes.
    for text in ["1.5", "-1.5", "0.5", "-0.5", "2.5", "-2.5", "7.25"]:
        var x = BigFloat.from_string(text, 53)
        assert_equal(
            truncate(x).internal_representation(),
            round_to_integer(
                x, RoundingMode.ROUND_DOWN
            ).internal_representation(),
            String("truncate of ") + text,
        )
        assert_equal(
            floor(x).internal_representation(),
            round_to_integer(
                x, RoundingMode.ROUND_FLOOR
            ).internal_representation(),
            String("floor of ") + text,
        )
        assert_equal(
            ceil(x).internal_representation(),
            round_to_integer(
                x, RoundingMode.ROUND_CEILING
            ).internal_representation(),
            String("ceil of ") + text,
        )

    # The sign of a value that rounds to nothing survives, as IEEE 754 asks.
    assert_true(
        truncate(BigFloat.from_string("-0.5", 53)).sign,
        "the whole part of minus a half is the negative zero",
    )
    assert_true(
        ceil(BigFloat.from_string("-0.5", 53)).sign,
        "and so is its ceiling",
    )
    assert_false(
        floor(BigFloat.from_string("0.5", 53)).sign,
        "while the floor of a half is the positive zero",
    )

    # All four are idempotent, because the answer carries the argument's own
    # precision and that is always wide enough to hold it.
    for text in ["1.5", "-7.25", "1024.5", "-0.75"]:
        var x = BigFloat.from_string(text, 53)
        for mode in modes:
            var once = round_to_integer(x, mode)
            assert_equal(
                round_to_integer(once, mode).internal_representation(),
                once.internal_representation(),
                String("rounding ") + text + " twice",
            )
            assert_equal(
                once.precision, 53, "and it keeps the argument's precision"
            )

    # The special values come back as they were.
    assert_true(truncate(BigFloat.nan()).is_nan(), "a NaN truncates to one")
    assert_true(
        floor(BigFloat.infinity(53, True)).is_infinite(),
        "an infinity floors to one",
    )
    assert_true(
        ceil(BigFloat.zero(53, True)).is_zero(), "and a zero ceils to one"
    )
    assert_true(ceil(BigFloat.zero(53, True)).sign, "keeping its sign")


def test_fma_rounds_once() raises:
    """One hundred and ten products, formed exactly before anything is added."""
    var modes = _modes()
    # x y z precision mode expected
    var cases = [
        (
            "1 7999256728263826 76 53 1 7277527488529944 -245 53 1"
            " 3638425670484256146165758312859 -165 102 53 4 0p0@53"
        ),
        (
            "1 4733557159166205 73 53 0 2 -255 2 0 4733557159166206 -181 53 53"
            " 1 4503599627370496p-233@53"
        ),
        (
            "0 1 -133 1 0 8050326092510465 135 53 1 8050326092510465 2 53 53 1"
            " 0p0@53"
        ),
        (
            "0 14509277398891067407 321 64 1 6 -377 3 0 43527832196673202222"
            " -55 66 53 2 4503599627370496p-107@53"
        ),
        (
            "1 7932959896078932 76 53 0 6027443891020492 132 53 0 3 -263 2 53 0"
            " -5308583646371935p261@53"
        ),
        (
            "0 6873072780563756 -157 53 0 4503599627370497 -70 53 1"
            " 7738392003359309304324885476682 -225 103 113 0"
            " 5192296858534827628530496329220096p-337@113"
        ),
        (
            "0 990736157987923236535076659039655285694138511655657187322662"
            " -154 200 0 4677285404516690 -214 53 1 5767435512575368 -169 53 53"
            " 1 7700470065544497p-223@53"
        ),
        (
            "1 6 212 3 1 8827593384349092 -251 53 1 6620695038261819 -36 53 53"
            " 1 0p0@53"
        ),
        (
            "1 8242551700418358215229040186380642 322 113 0 7440706404158016"
            " -43 53 0 6061490430604191 0 53 113 1"
            " -6809043020961793868463422733462823p332@113"
        ),
        (
            "0 7399319981661109 148 53 1 6809839270917848 -56 53 0"
            " 6298522473650368868309764446680 95 103 113 4"
            " 5192296858534827628530496329220096p-17@113"
        ),
        (
            "0 8909750032513394 -243 53 1 7460755644004508 -60 53 0"
            " 8508603883743187576863015216659456 -310 113 113 0 0p0@113"
        ),
        (
            "1 4988298355266533 -191 53 0 7699980742311499 -119 53 0"
            " 38409801272456428326474655762968 -310 105 113 3"
            " 5192296858534827628530496329220096p-422@113"
        ),
        (
            "0 6598945705711306 136 53 1 7943187207250919896988918159650495 294"
            " 113 0 5047540860918772 543 53 53 0 -7746762963715905p487@53"
        ),
        (
            "0 8136581383079035 -189 53 0 4503599627370497 -14 53 1"
            " 9380839650535543073332884026981120 -211 113 113 4 0p0@113"
        ),
        (
            "1 5068802756918066 130 53 1 6413909923889913 66 53 0"
            " 6143185792190158 96 53 1 5 1p301@1"
        ),
        (
            "0 4503599627370497 0 53 0 7553619249852401 -114 53 1"
            " 34018476838933886219866992013296 -114 105 113 6"
            " 5192296858534827628530496329220096p-226@113"
        ),
        (
            "1 6735686028535395 -88 53 1 4719171943037143 -29 53 1"
            " 8137436293880708365460576045180160 -125 113 113 6 0p0@113"
        ),
        (
            "1 1501811781304310270498565773973645589386785052920291733526153"
            " -76 200 0 8756882062098907 -63 53 0"
            " 13151188648352521268864723838761165167452966974076902146351240508055357214772"
            " -139 253 53 3 4503599627370496p-191@53"
        ),
        (
            "0 4780314938069163 -15 53 1 4605506877953451 -202 53 0"
            " 22015773326061155356150932531513 -217 105 53 4 0p0@53"
        ),
        (
            "0 7301375983394451 302 53 1 6974054154281934 10 53 0"
            " 25460095754483206076800892574117 313 105 113 0 0p0@113"
        ),
        (
            "0 1 -7 1 0 4794347271567176 -76 53 1 4794347271567176 -83 53 113 6"
            " 0p0@113"
        ),
        (
            "0 4503599627370496 -1074 53 0 6433105921105373796697065913410455"
            " -29 113 1 6433105921105373796697065913410454 -1051 113 113 4"
            " 5192296858534827628530496329220096p-1163@113"
        ),
        (
            "1 10456009150891364461 -393 64 0 6697079045226961 -45 53 0"
            " 70024719781135906296116274714433021 -438 116 113 1 0p0@113"
        ),
        (
            "1 4503599627370496 -52 53 1 5938531173064642 -248 53 1"
            " 5938531173064642 -248 53 53 2 0p0@53"
        ),
        (
            "1 5753576846732584 92 53 0 5323696531599177 75 53 0"
            " 3828787137904948379970099185422 170 102 53 4"
            " 4503599627370496p118@53"
        ),
        (
            "0 990736157987923236535076659039655285694138511655657187322662"
            " -154 200 0 4677285404516690 -214 53 1"
            " 1158488942870963706997183412108143270981960889621648415969835580785798557195"
            " -366 250 113 4 0p0@113"
        ),
        (
            "0 7289095236008992 -44 53 1 4733557159166205 73 53 0"
            " 1078229654320457585739831328606 34 100 113 3"
            " 5192296858534827628530496329220096p-78@113"
        ),
        (
            "0 7589321596607178 -34 53 1 8576724678224251 -114 53 0"
            " 32545760914300528790949720136840 -147 105 53 4"
            " 4503599627370496p-199@53"
        ),
        (
            "1 5284416202223256 -43 53 0 5401612074950823 -237 53 0"
            " 3568045795874363714979933367461 -277 102 53 0 0p0@53"
        ),
        (
            "1 2 260 2 0 4503599627370496 -112 53 0 4503599627370496 149 53 53"
            " 5 0p0@53"
        ),
        (
            "0 10052753342537863868966602459626137 -79 113 0 4503599627370496"
            " -1052 53 1 10052753342537863868966602459626136 -1079 113 113 1"
            " 5192296858534827628530496329220096p-1191@113"
        ),
        (
            "1 2 316 2 1 6567502680442744 -155 53 0 1 -3 1 53 2"
            " 6567502680442745p162@53"
        ),
        (
            "1 7838334092631976 -22 53 0 7462936747596903 57 53 0"
            " 7312123942480600096564547046291 38 103 113 3 -0p0@113"
        ),
        (
            "0 8002892608832214 26 53 0 6687995426695261 -199 53 1"
            " 26761654584101576775781228968927 -172 105 113 4 0p0@113"
        ),
        (
            "0 1503314349405300515515515792066887010107828844792064886614684"
            " -259 200 0 8145976407005108482055388084417880 207 113 1"
            " 382686350705244129203496046096636006835804293817979564356634969933541141383895645870125004685"
            " -47 308 113 0 0p0@113"
        ),
        (
            "1 5187792600806607 6 53 0 8149813412857918 126 53 0"
            " 21139770860589374199655943332114 133 105 53 4"
            " 4503599627370496p81@53"
        ),
        (
            "1 8125699271269991 69 53 1 14247111133856382227 100 64 1"
            " 115767740558079380262772275010849956 169 117 113 1"
            " 5192296858534827628530496329220096p57@113"
        ),
        (
            "0 9007199254740991 -8 53 1 6280175646580295 -168 53 0"
            " 56566793403520554407635109372346 -176 106 53 0"
            " 4503599627370496p-228@53"
        ),
        (
            "0 1 -7 1 0 4794347271567176 -76 53 1"
            " 5527506069942960134597095536459776 -143 113 113 1 0p0@113"
        ),
        (
            "0 17716213667480501390 -27 64 0 16792791271067938219 -312 64 1"
            " 7874883263265288 -264 53 53 1 8201566467757866p-319@53"
        ),
        (
            "1 3 -42 2 1 8068671004264910 -134 53 1 12103006506397365 -175 54"
            " 53 4 0p0@53"
        ),
        (
            "1 5289795478465058 120 53 0 8821134507934346 -91 53 0"
            " 11665499358750799440919579770517 31 104 113 1 0p0@113"
        ),
        (
            "0 5962691063943776 -45 53 0 7419830671446762 45 53 1"
            " 691283719384555549522864769583 6 100 113 1 0p0@113"
        ),
        (
            "1 12612215396459330400 -83 64 0 7321131129146807 0 53 0"
            " 2885490085828845052488875828688525 -78 112 113 0 0p0@113"
        ),
        (
            "1 6123222447660355 -190 53 0 18098125771866690742 -123 64 0"
            " 6926178124179656855443907139933338 -309 113 113 5"
            " -5192296858534827628530496329220096p-424@113"
        ),
        (
            "0 71089 -20 17 1 7134830333310201 -186 53 1 4503599627370496 -1126"
            " 53 200 4"
            " -1380751383680942233396028839524296295090756707663978610819072p-337@200"
        ),
        (
            "0 9007199254740991 -71 53 0 1 -3 1 1 9007199254740990 -74 53 113 2"
            " 5192296858534827628530496329220096p-186@113"
        ),
        (
            "0 7539095722883855 5 53 0 5461689405189921 67 53 1"
            " 41176199234387399497842099625455 72 106 113 0 0p0@113"
        ),
        (
            "0 9007199254740991 -71 53 0 1 -3 1 1 9007199254740990 -74 53 53 5"
            " 4503599627370496p-126@53"
        ),
        (
            "1 6475685214330921 -186 53 0 6511984072451163 17 53 0"
            " 5397703548663098016952767143823744 -176 113 113 1 0p0@113"
        ),
        (
            "0 6039050092487389 45 53 0 5793228934393029 60 53 1"
            " 7768363670567622 157 53 53 3 -4721016254676924p103@53"
        ),
        (
            "0 8556401883145915 80 53 1 6755399441055744 -52 53 0"
            " 25669205649437746 79 55 113 4"
            " 5192296858534827628530496329220096p-33@113"
        ),
        (
            "1 6062329963599862 103 53 0 7589321596607178 -34 53 0"
            " 11502242929626809990464597252359 71 104 53 3 -0p0@53"
        ),
        (
            "1 4719171943037143 -29 53 0 5629499534213120 -51 53 0"
            " 6801043521331000572849008106536960 -88 113 113 3 -0p0@113"
        ),
        (
            "1 2 260 2 0 4503599627370496 -112 53 0 4503599627370496 149 53 53"
            " 0 0p0@53"
        ),
        (
            "1 4503599627370496 -91 53 0 8776711105684801 138 53 0"
            " 8776711105684801 99 53 53 2 0p0@53"
        ),
        (
            "1 8145426293142482 -43 53 0 7109993609662264 -108 53 0"
            " 7412982898203907858559904089503744 -158 113 113 4 0p0@113"
        ),
        (
            "1 6367153574545937 -173 53 0 4503599627370496 -21 53 0"
            " 6367153574545937 -142 53 53 4 0p0@53"
        ),
        (
            "0 8349218654226376 -209 53 0 8579843901385365 -4 53 1"
            " 9169279072230028370383196593566720 -220 113 113 3 -0p0@113"
        ),
        (
            "1 8663226597798046 101 53 0 9223372036854775808 -7 64 0"
            " 8663226597798046 157 53 53 6 0p0@53"
        ),
        (
            "1 5898388399348433 99 53 1 4965065971445561 -364 53 1"
            " 29285887527974155094075530155912 -265 105 113 4"
            " 5192296858534827628530496329220096p-377@113"
        ),
        (
            "0 66555 147 17 0 8268870298948468 -203 53 1 137583665686628821934"
            " -54 67 113 2 5192296858534827628530496329220096p-166@113"
        ),
        (
            "0 8817058230855052 -44 53 0 4503599627370496 -14 53 1"
            " 8817058230855052 -6 53 53 4 0p0@53"
        ),
        (
            "0 8817058230855052 -44 53 0 4503599627370496 -14 53 1"
            " 8817058230855052 -6 53 53 4 0p0@53"
        ),
        (
            "0 8008820959849432 -44 53 0 6392319247508369 -26 53 1"
            " 6399367546436746837269424987051 -67 103 113 6 0p0@113"
        ),
        (
            "1 6462025067682409 -117 53 1 7738089547012466 -59 53 1"
            " 25001864314382886101586225955297 -175 105 113 5 0p0@113"
        ),
        (
            "1 14247111133856382227 100 64 1 123596 283 17 1"
            " 7562947557357953544633800753938432 351 113 113 5 0p0@113"
        ),
        (
            "0 4503599627370496 -52 53 0 1 85 1 1 4503599627370496 33 53 53 1"
            " 0p0@53"
        ),
        (
            "1 14247111133856382227 100 64 1 123596 283 17 1"
            " 440221486925028354432073 385 79 53 2 0p0@53"
        ),
        (
            "1 5187792600806607 6 53 0 4503599627370496 971 53 0"
            " 5187792600806607 1029 53 53 1 0p0@53"
        ),
        (
            "1 5753576846732584 92 53 1 5187792600806607 6 53 1"
            " 6627668057402116 150 53 53 5 6559029952828928p92@53"
        ),
        (
            "0 4 -54 3 0 4 -54 3 1 9007199254740991 -157 53 53 1"
            " 4503599627370496p-209@53"
        ),
        (
            "1 12612215396459330400 -83 64 0 7321131129146807 0 53 0"
            " 5770980171657690104977751657377050 -79 113 113 4 0p0@113"
        ),
        (
            "1 8125699271269991 69 53 1 14247111133856382227 100 64 1"
            " 115767740558079380262772275010849956 169 117 53 0"
            " 4503599627370496p117@53"
        ),
        (
            "1 7889113893125380 -237 53 0 5787985038830598 -13 53 0"
            " 5707759147880039089933324297156 -247 103 113 5"
            " 5192296858534827628530496329220096p-359@113"
        ),
        (
            "1 8111841058159772 -59 53 1 1 11 1 1 8111841058159772 -48 53 53 3"
            " -0p0@53"
        ),
        (
            "0 85325 -31 17 1 6462025067682409 -117 53 0 551372288900001547926"
            " -148 69 53 0 4503599627370496p-200@53"
        ),
        (
            "1 6758994031762052 -112 53 1 2 3 2 1 6758994031762052 -108 53 53 5"
            " 0p0@53"
        ),
        (
            "1 4 216 3 0 6826265422024900 -44 53 0 6826265422024900 174 53 113"
            " 3 -0p0@113"
        ),
        (
            "1 6367153574545937 -173 53 0 4503599627370496 -21 53 0"
            " 7340828279228365695570040441536512 -202 113 113 3 -0p0@113"
        ),
        (
            "0 921535770148562649693524985402621687453968230055369100562849 195"
            " 200 0 4503599627370496 -7 53 1"
            " 921535770148562649693524985402621687453968230055369100562848 240"
            " 200 113 2 5192296858534827628530496329220096p128@113"
        ),
        (
            "1 4 216 3 0 6826265422024900 -44 53 0 6826265422024900 174 53 53 0"
            " 0p0@53"
        ),
        (
            "1 6758994031762052 -112 53 1 2 3 2 1 6758994031762051 -108 53 53 6"
            " 4503599627370496p-160@53"
        ),
        (
            "1 11855334997726162089 -233 64 1 7498672993190619 107 53 1"
            " 88899280372676740168256325668243090 -126 117 53 6"
            " 4503599627370496p-178@53"
        ),
        (
            "1 5753576846732584 92 53 0 5323696531599177 75 53 0"
            " 3828787137904948379970099185421 170 102 53 6 0p0@53"
        ),
        (
            "0 9007199254740991 -50 53 1 7849712484939279 -171 53 0"
            " 70703924444276126348025507285489 -221 106 53 1 0p0@53"
        ),
        (
            "0 8626456148685310 -39 53 1 4503599627370496 -1052 53 0"
            " 8626456148685311 -1039 53 53 0 4503599627370496p-1091@53"
        ),
        (
            "0 13023737004943954292 40 64 1 8775502204871601 -218 53 0"
            " 28572458200638382995791853768215373 -176 115 113 4 0p0@113"
        ),
        (
            "1 8070043029254763 -26 53 0 6875239086721005 -7 53 0"
            " 55483475266252729403574448396815 -33 106 53 5 0p0@53"
        ),
        (
            "1 7235693061071738 141 53 1 7386346875550832 -72 53 1"
            " 6841003370763784628138882251010048 62 113 113 6 0p0@113"
        ),
        (
            "1 8336364341961348 148 53 1 6349351964572803 -204 53 1"
            " 6775105447939449221127162626360832 -63 113 113 1 0p0@113"
        ),
        (
            "0 6047143992095067 -226 53 1 6533234533518244 -32 53 0"
            " 9876852489578216708597006725587 -256 103 53 5 0p0@53"
        ),
        (
            "1 4536897908922706 -13 53 1 5187792600806607 6 53 1"
            " 5226149602527248 45 53 53 4 7588494343374136p-9@53"
        ),
        (
            "0 13023737004943954292 40 64 1 69598 -364 17 0"
            " 7786140465407115183294601517596672 -357 113 113 3 -0p0@113"
        ),
        (
            "0 6098479293878372 -28 53 1 8921915090431691 -70 53 0"
            " 13602528610184662599071782071763 -96 104 53 0 0p0@53"
        ),
        (
            "1 2 3 2 0 4503599627370496 -1125 53 0"
            " 5192296858534827628530496329220096 -1181 113 113 0 0p0@113"
        ),
        (
            "0 5460321068886217 -176 53 0 7399319981661109 148 53 1"
            " 40402662791294930265132175034653 -28 105 53 0 0p0@53"
        ),
        (
            "1 7838334092631976 -22 53 0 7462936747596903 57 53 0"
            " 7312123942480600096564547046291 38 103 113 2 0p0@113"
        ),
        (
            "1 5187792600806607 6 53 0 4503599627370496 971 53 0"
            " 5187792600806607 1029 53 53 6 0p0@53"
        ),
        (
            "0 6174393266069566 36 53 0 4503599627370496 -49 53 1"
            " 6174393266069566 39 53 53 4 0p0@53"
        ),
        (
            "0 6598945705711306 136 53 0 18446744073709551615 -3 64 1"
            " 60864531294780564393687054948029594 134 116 113 1"
            " 5192296858534827628530496329220096p22@113"
        ),
        (
            "1 4527172411012352 108 53 0 5244593612633647 18 53 0"
            " 92746794961275972535219405499 134 97 53 1 0p0@53"
        ),
        (
            "1 8919445437588652 -141 53 0 1 -2 1 0"
            " 10283420454163385288570278198116352 -203 113 113 1 0p0@113"
        ),
        (
            "1 8919445437588652 -141 53 0 1 -2 1 0 8919445437588652 -143 53 113"
            " 5 0p0@113"
        ),
        (
            "0 6143185792190158 96 53 1 4503599627370496 -21 53 0"
            " 7082611006611282136354393799262208 67 113 113 4 0p0@113"
        ),
        (
            "1 10384593717069655257060992658440191 11 113 1 5977790540751226"
            " -85 53 1 31038463045721799258209919478387063093211265462083 -73"
            " 165 113 6 0p0@113"
        ),
        (
            "1 8171636095052138 32 53 0 4722552935385928 -66 53 0"
            " 2411936501724629779051019469629 -30 101 53 4 0p0@53"
        ),
        (
            "0 7291335331815127 50 53 1 5192296858534827628530496329220096 3"
            " 113 0 7291335331815127 165 53 113 3 -0p0@113"
        ),
        (
            "0 1 -385 1 1 5030622424832675 -219 53 0 5030622424832675 -604 53"
            " 53 4 0p0@53"
        ),
        (
            "0 7321131129146807 0 53 1 7949606680465021 2 53 0 6461510541380764"
            " 55 53 53 2 7612604534959764p0@53"
        ),
    ]
    for row in cases:
        var field = row.split(" ")
        var x = _parse(field[0], field[1], field[2], field[3])
        var y = _parse(field[4], field[5], field[6], field[7])
        var z = _parse(field[8], field[9], field[10], field[11])
        var precision = Int(String(field[12]))
        var mode = modes[Int(String(field[13]))]
        assert_equal(
            fma(x, y, z, precision, mode).internal_representation(),
            String(field[14]),
            String("case ") + row,
        )


def test_fma_is_not_a_multiply_and_an_add() raises:
    """The case the operation exists for: a product that cancels with `z`.

    The value above one at 53 bits is `1 + 2^-52`, and its square is
    `1 + 2^-51 + 2^-104`, which 53 bits cannot hold; rounded to 53 bits it is
    `1 + 2^-51` exactly. Adding `-(1 + 2^-51)` to the rounded product
    therefore leaves nothing at all, while the true sum is `2^-104` -- so the
    fused answer and the two-step answer do not differ in a last bit, they
    differ by everything there is.
    """
    var one_plus = next_plus(BigFloat.from_float64(1.0), 53)
    var product_rounded = one_plus * one_plus
    var z = -product_rounded

    var two_step = product_rounded + z
    assert_true(two_step.is_zero(), "the two-step answer vanishes")

    var fused = fma(one_plus, one_plus, z, 53)
    assert_false(fused.is_zero(), "the fused answer does not")
    assert_true(
        fused == BigFloat.power_of_two(-104),
        "and it is the term the rounded product threw away: "
        + fused.internal_representation(),
    )


def test_fma_special_values_follow_ieee() raises:
    """A NaN anywhere, an infinity times a zero, and the signed zeros."""
    var two = BigFloat.from_float64(2.0)
    var three = BigFloat.from_float64(3.0)

    assert_true(fma(BigFloat.nan(), two, three, 53).is_nan(), "a NaN factor")
    assert_true(fma(two, BigFloat.nan(), three, 53).is_nan(), "the other one")
    assert_true(fma(two, three, BigFloat.nan(), 53).is_nan(), "a NaN term")
    assert_true(
        fma(BigFloat.infinity(), BigFloat.zero(), three, 53).is_nan(),
        "an infinity times a zero is no value at all",
    )
    assert_true(
        fma(BigFloat.zero(), BigFloat.infinity(), BigFloat.nan(), 53).is_nan(),
        "and says so whatever is added to it",
    )
    assert_true(
        fma(BigFloat.infinity(), two, BigFloat.infinity(53, True), 53).is_nan(),
        "an infinity plus the other infinity is a NaN",
    )
    assert_true(
        fma(BigFloat.infinity(), two, three, 53).is_infinite(),
        "an infinite product stays infinite",
    )
    assert_true(
        fma(BigFloat.infinity(), -two, three, 53).sign,
        "with the sign the two factors give it",
    )
    assert_true(
        fma(two, three, BigFloat.infinity(53, True), 53).sign,
        "and an infinite term carries its own",
    )

    # The zeros. A zero factor gives the product's sign, and an exact
    # cancellation gives the positive zero in every mode but FLOOR.
    assert_true(
        fma(BigFloat.zero(), -two, BigFloat.zero(53, True), 53).sign,
        "minus nothing plus minus nothing is the negative zero",
    )
    assert_false(
        fma(two, three, -(two * three), 53).sign,
        "a product cancelling exactly leaves the positive zero",
    )
    assert_true(
        fma(two, three, -(two * three), 53, RoundingMode.ROUND_FLOOR).sign,
        "except toward negative infinity",
    )


def test_the_remainders_are_what_the_reference_gives() raises:
    """One hundred and ten pairs, across both remainders."""
    var modes = _modes()
    # op x y precision mode expected
    var cases = [
        (
            "rm 0 5840592823970075 -202 53 1 1 -43 1 200 1"
            " 1041996579005784504517086588683241914543024388448546560409600p-349@200"
        ),
        (
            "rm 0 22558476828073263079823275 -4 85 0 4503599627370497 -7 53 113"
            " 6 0p0@113"
        ),
        "rm 1 70 218 7 1 4 216 3 53 0 -0p0@53",
        (
            "rm 0 6759989003042833 -46 53 0 10694317593848718525 -392 64 53 5"
            " 6720192577418341p-383@53"
        ),
        (
            "rm 0 5422968019881170 -170 53 1 6 -39 3 113 3"
            " 6252256448916212161489275893841920p-230@113"
        ),
        (
            "rm 0 5623326970468279 -41 53 0 5623326970468278 -43 53 53 6"
            " 4503599627370496p-93@53"
        ),
        "rm 1 5129932393999565 -81 53 1 7 -278 3 1 3 1p-278@1",
        (
            "rm 1 5910534054034724097458977516518 -393 103 1 5370070677938068"
            " -397 53 103 6 5070602400912917605986812821504p-495@103"
        ),
        (
            "rm 1 30593277675139055 -381 55 1 6118655535027811 -381 53 55 0"
            " -0p0@55"
        ),
        (
            "rm 0 4838335682833238 -244 53 0 6486952527849577 -230 53 113 1"
            " 5578221255245093114150197592588288p-304@113"
        ),
        (
            "rm 0 25689514943838957262983969 91 85 0 6751637721226533 85 53 85"
            " 0 0p0@85"
        ),
        (
            "rm 0 227562625357740840604153970132437518600845622427526264184762212365097"
            " 119 228 0"
            " 1603333628361172404913593488551132506626462807671482182384788 116"
            " 200 53 0 0p0@53"
        ),
        (
            "rm 0 1164253790391502352001234840862 -38 100 0 8340055682314848"
            " -43 53 113 0 5192296858534827628530496329220096p-150@113"
        ),
        (
            "rm 1 882932825122119840058367513117774 24 110 1 7425180971429010"
            " 22 53 53 0 4503599627370496p-28@53"
        ),
        (
            "rm 1 5608196852396203435 -168 63 1 6280175646580295 -168 53 113 6"
            " -0p0@113"
        ),
        "rm 1 4912701369221120 -24 53 1 5629499534213120 -51 53 53 6 -0p0@53",
        "rm 1 530565 6 20 1 4 3 3 53 0 -0p0@53",
        (
            "rm 1 2296419836381320004827799105390 94 101 1 4678634700490144 88"
            " 53 113 0 5192296858534827628530496329220096p-18@113"
        ),
        (
            "rm 1 632952711958584383375553037732004346649857494338619510856881103491"
            " -76 219 1"
            " 1301676134943483155608814091094326327955084693599705735169076 -78"
            " 200 113 6 -0p0@113"
        ),
        (
            "rm 0 11632953234385567541 -197 64 0 5143838464029139 -113 53 113 4"
            " 6548770481449656024169727804833792p-246@113"
        ),
        "rm 0 8596866698881802309 29 63 0 5735067844484191 27 53 53 6 0p0@53",
        (
            "rm 0 75760715863760911 -999 57 0 4503599627370496 -1052 53 53 6"
            " 0p0@53"
        ),
        (
            "rm 1 7559681588844148 -200 53 1 8682371159351995 -220 53 53 1"
            " -6837789172482048p-232@53"
        ),
        (
            "rm 0 381145934040917479406956 68 79 0 5461689405189921 67 53 79 6"
            " 302231454903657293676544p-10@79"
        ),
        (
            "rm 1 5010651710573929835623909911 -240 93 1 7277527488529944 -245"
            " 53 53 0 -0p0@53"
        ),
        (
            "rm 1 1934949440129207849914321283124209853906422928329292970433944203674028699633"
            " -309 251 1"
            " 953774668064511106233906109598841819556226601253522922371351 -310"
            " 200 113 0 -0p0@113"
        ),
        (
            "rm 0 130841588966758540034863725819455 -20 107 0 4946543799024035"
            " -20 53 53 0 0p0@53"
        ),
        "rm 0 16865406392292 -3 44 0 131071 -3 17 44 0 8796093022208p-46@44",
        (
            "rm 1 425657881986743586197672 -182 79 1 6475685214330921 -186 53"
            " 113 6 5192296858534827628530496329220096p-294@113"
        ),
        (
            "rm 0 923950723256079334671137389462 -41 100 0 4754958509986044 -44"
            " 53 53 6 4503599627370496p-93@53"
        ),
        "rm 0 351546642920537428 -2 59 0 1 -3 1 59 0 0p0@59",
        (
            "rm 0 25884222573917389519426386435 -197 95 0 6603266227301084 -199"
            " 53 95 6 0p0@95"
        ),
        (
            "rm 1 1934949440129207849914321283124209853906422928329292970433944203674028699633"
            " -309 251 1"
            " 953774668064511106233906109598841819556226601253522922371351 -310"
            " 200 53 0 -0p0@53"
        ),
        (
            "rm 0 357682551580916072337673 -112 79 0 7553619249852401 -114 53"
            " 53 0 0p0@53"
        ),
        (
            "rm 1 1459091043187365800294 -88 71 1 6735686028535395 -88 53 53 0"
            " 4503599627370496p-140@53"
        ),
        "rm 1 5679105332740096 16 53 1 4503599627370496 -7 53 53 6 -0p0@53",
        (
            "rm 0 948705779503732045535 -81 70 0 4503599627370497 -84 53 113 0"
            " 0p0@113"
        ),
        (
            "rm 0 2692387258015405264605 -28 72 0 6482884367505015 -28 53 53 6"
            " 0p0@53"
        ),
        "rm 0 351546642920537427 -2 59 0 1 -3 1 59 0 0p0@59",
        "rm 0 91778379582487934 -77 57 0 1 -77 1 113 6 0p0@113",
        (
            "rm 0 6916708103152328 -44 53 0 5623326970468278 -43 53 53 0"
            " -8659891675568456p-45@53"
        ),
        (
            "rm 0 7521968744001529302864876798406 61 103 0 5793228934393029 60"
            " 53 103 6 5070602400912917605986812821504p-41@103"
        ),
        (
            "rm 0 63012433891529062142679930913 -242 96 0 8909750032513394 -243"
            " 53 53 6 0p0@53"
        ),
        (
            "rm 1 360031711429143713614256913281139 54 109 1 6811641415242711"
            " 54 53 109 6 -0p0@109"
        ),
        (
            "rm 0 10211388503519525669256234 -90 84 0 9007199254740991 -92 53"
            " 53 6 4503599627370496p-142@53"
        ),
        (
            "rm 1 8895306941137919 -10 53 1 5629499534213120 -51 53 113 6"
            " 5192296858534827628530496329220096p-122@113"
        ),
        (
            "rm 1 13318288649445076435858290905792068219448289256491669581672922749697795"
            " 250 233 1"
            " 932495526627778068968013115586145426712297880257307712261414 248"
            " 200 53 0 -0p0@53"
        ),
        "rm 0 1 224 1 1 7335476515461358 -195 53 53 2 4904001777848592p-196@53",
        (
            "rm 1 360031711429143713614256913281138 54 109 1 6811641415242711"
            " 54 53 113 6 5192296858534827628530496329220096p-58@113"
        ),
        (
            "rm 0 27597983748685015026474996111 -210 95 0 5884429418197488 -215"
            " 53 95 0 0p0@95"
        ),
        "rm 0 6618393530861898 -43 53 0 111631 -159 17 11 3 -1084p-161@11",
        (
            "rm 1 1540521197707908266948123762814 -23 101 1 7837393662637870"
            " -25 53 113 6 5192296858534827628530496329220096p-135@113"
        ),
        (
            "rm 0 8482903470824090111092 61 73 0 5793228934393029 60 53 53 0"
            " 4503599627370496p9@53"
        ),
        (
            "rm 0 16865406392292 -3 44 0 131071 -3 17 113 0"
            " 5192296858534827628530496329220096p-115@113"
        ),
        (
            "rm 1 6425759914680319 -14 53 1 5629499534213120 -51 53 53 6"
            " 4503599627370496p-66@53"
        ),
        (
            "fm 0 5840592823970075 -202 53 1 1 -43 1 200 1"
            " 1041996579005784504517086588683241914543024388448546560409600p-349@200"
        ),
        (
            "fm 0 22558476828073263079823275 -4 85 0 4503599627370497 -7 53 113"
            " 6 0p0@113"
        ),
        "fm 1 70 218 7 1 4 216 3 53 0 -0p0@53",
        (
            "fm 0 6759989003042833 -46 53 0 10694317593848718525 -392 64 53 5"
            " 6720192577418341p-383@53"
        ),
        (
            "fm 0 5422968019881170 -170 53 1 6 -39 3 113 3"
            " 6252256448916212161489275893841920p-230@113"
        ),
        (
            "fm 0 5623326970468279 -41 53 0 5623326970468278 -43 53 53 6"
            " 4503599627370496p-93@53"
        ),
        "fm 1 5129932393999565 -81 53 1 7 -278 3 1 3 -1p-275@1",
        (
            "fm 1 5910534054034724097458977516518 -393 103 1 5370070677938068"
            " -397 53 103 6 -6046162076028759455549985128448p-447@103"
        ),
        (
            "fm 1 30593277675139055 -381 55 1 6118655535027811 -381 53 55 0"
            " -0p0@55"
        ),
        (
            "fm 0 4838335682833238 -244 53 0 6486952527849577 -230 53 113 1"
            " 5578221255245093114150197592588288p-304@113"
        ),
        (
            "fm 0 25689514943838957262983969 91 85 0 6751637721226533 85 53 85"
            " 0 0p0@85"
        ),
        (
            "fm 0 227562625357740840604153970132437518600845622427526264184762212365097"
            " 119 228 0"
            " 1603333628361172404913593488551132506626462807671482182384788 116"
            " 200 53 0 0p0@53"
        ),
        (
            "fm 0 1164253790391502352001234840862 -38 100 0 8340055682314848"
            " -43 53 113 0 5192296858534827628530496329220096p-150@113"
        ),
        (
            "fm 1 882932825122119840058367513117774 24 110 1 7425180971429010"
            " 22 53 53 0 -7425180971429006p22@53"
        ),
        (
            "fm 1 5608196852396203435 -168 63 1 6280175646580295 -168 53 113 6"
            " -0p0@113"
        ),
        "fm 1 4912701369221120 -24 53 1 5629499534213120 -51 53 53 6 -0p0@53",
        "fm 1 530565 6 20 1 4 3 3 53 0 -0p0@53",
        (
            "fm 1 2296419836381320004827799105390 94 101 1 4678634700490144 88"
            " 53 113 0 -5394098558394827890481390765998080p28@113"
        ),
        (
            "fm 1 632952711958584383375553037732004346649857494338619510856881103491"
            " -76 219 1"
            " 1301676134943483155608814091094326327955084693599705735169076 -78"
            " 200 113 6 -0p0@113"
        ),
        (
            "fm 0 11632953234385567541 -197 64 0 5143838464029139 -113 53 113 4"
            " 6548770481449656024169727804833792p-246@113"
        ),
        "fm 0 8596866698881802309 29 63 0 5735067844484191 27 53 53 6 0p0@53",
        (
            "fm 0 75760715863760911 -999 57 0 4503599627370496 -1052 53 53 6"
            " 0p0@53"
        ),
        (
            "fm 1 7559681588844148 -200 53 1 8682371159351995 -220 53 53 1"
            " -6837789172482048p-232@53"
        ),
        (
            "fm 0 381145934040917479406956 68 79 0 5461689405189921 67 53 79 6"
            " 302231454903657293676544p-10@79"
        ),
        (
            "fm 1 5010651710573929835623909911 -240 93 1 7277527488529944 -245"
            " 53 53 0 -0p0@53"
        ),
        (
            "fm 1 1934949440129207849914321283124209853906422928329292970433944203674028699633"
            " -309 251 1"
            " 953774668064511106233906109598841819556226601253522922371351 -310"
            " 200 113 0 -0p0@113"
        ),
        (
            "fm 0 130841588966758540034863725819455 -20 107 0 4946543799024035"
            " -20 53 53 0 0p0@53"
        ),
        "fm 0 16865406392292 -3 44 0 131071 -3 17 44 0 8796093022208p-46@44",
        (
            "fm 1 425657881986743586197672 -182 79 1 6475685214330921 -186 53"
            " 113 6 -7465956740666699336125741562593280p-246@113"
        ),
        (
            "fm 0 923950723256079334671137389462 -41 100 0 4754958509986044 -44"
            " 53 53 6 4503599627370496p-93@53"
        ),
        "fm 0 351546642920537428 -2 59 0 1 -3 1 59 0 0p0@59",
        (
            "fm 0 25884222573917389519426386435 -197 95 0 6603266227301084 -199"
            " 53 95 6 0p0@95"
        ),
        (
            "fm 1 1934949440129207849914321283124209853906422928329292970433944203674028699633"
            " -309 251 1"
            " 953774668064511106233906109598841819556226601253522922371351 -310"
            " 200 53 0 -0p0@53"
        ),
        (
            "fm 0 357682551580916072337673 -112 79 0 7553619249852401 -114 53"
            " 53 0 0p0@53"
        ),
        (
            "fm 1 1459091043187365800294 -88 71 1 6735686028535395 -88 53 53 0"
            " -6735686028535394p-88@53"
        ),
        "fm 1 5679105332740096 16 53 1 4503599627370496 -7 53 53 6 -0p0@53",
        (
            "fm 0 948705779503732045535 -81 70 0 4503599627370497 -84 53 113 0"
            " 0p0@113"
        ),
        (
            "fm 0 2692387258015405264605 -28 72 0 6482884367505015 -28 53 53 6"
            " 0p0@53"
        ),
        "fm 0 351546642920537427 -2 59 0 1 -3 1 59 0 0p0@59",
        "fm 0 91778379582487934 -77 57 0 1 -77 1 113 6 0p0@113",
        (
            "fm 0 6916708103152328 -44 53 0 5623326970468278 -43 53 53 0"
            " 6916708103152328p-44@53"
        ),
        (
            "fm 0 7521968744001529302864876798406 61 103 0 5793228934393029 60"
            " 53 103 6 5070602400912917605986812821504p-41@103"
        ),
        (
            "fm 0 63012433891529062142679930913 -242 96 0 8909750032513394 -243"
            " 53 53 6 0p0@53"
        ),
        (
            "fm 1 360031711429143713614256913281139 54 109 1 6811641415242711"
            " 54 53 109 6 -0p0@109"
        ),
        (
            "fm 0 10211388503519525669256234 -90 84 0 9007199254740991 -92 53"
            " 53 6 4503599627370496p-142@53"
        ),
        (
            "fm 1 8895306941137919 -10 53 1 5629499534213120 -51 53 113 6"
            " -6487835771968078076860127005114368p-111@113"
        ),
        (
            "fm 1 13318288649445076435858290905792068219448289256491669581672922749697795"
            " 250 233 1"
            " 932495526627778068968013115586145426712297880257307712261414 248"
            " 200 53 0 -0p0@53"
        ),
        "fm 0 1 224 1 1 7335476515461358 -195 53 53 2 4904001777848592p-196@53",
        (
            "fm 1 360031711429143713614256913281138 54 109 1 6811641415242711"
            " 54 53 113 6 -7853287869303937732672238869544960p-6@113"
        ),
        (
            "fm 0 27597983748685015026474996111 -210 95 0 5884429418197488 -215"
            " 53 95 0 0p0@95"
        ),
        "fm 0 6618393530861898 -43 53 0 111631 -159 17 11 3 1740p-153@11",
        (
            "fm 1 1540521197707908266948123762814 -23 101 1 7837393662637870"
            " -25 53 113 6 -9035899693724615719963817165193216p-85@113"
        ),
        (
            "fm 0 8482903470824090111092 61 73 0 5793228934393029 60 53 53 0"
            " 4503599627370496p9@53"
        ),
        (
            "fm 0 16865406392292 -3 44 0 131071 -3 17 113 0"
            " 5192296858534827628530496329220096p-115@113"
        ),
        (
            "fm 1 6425759914680319 -14 53 1 5629499534213120 -51 53 53 6"
            " -5629362095259648p-51@53"
        ),
    ]
    for row in cases:
        var field = row.split(" ")
        var x = _parse(field[1], field[2], field[3], field[4])
        var y = _parse(field[5], field[6], field[7], field[8])
        var precision = Int(String(field[9]))
        var mode = modes[Int(String(field[10]))]
        var got = remainder(x, y, precision, mode) if field[
            0
        ] == "rm" else fmod(x, y, precision, mode)
        assert_equal(
            got.internal_representation(),
            String(field[11]),
            String("case ") + row,
        )


def test_the_two_remainders_differ_as_they_should() raises:
    """`remainder` takes the nearer multiple, `fmod` the one toward zero."""
    var five = BigFloat.from_float64(5.0)
    var three = BigFloat.from_float64(3.0)
    assert_equal(
        String(remainder(five, three, 53)),
        "-1",
        "five from six is minus one",
    )
    assert_equal(String(fmod(five, three, 53)), "2", "five from three is two")

    # A tie in the quotient goes to the even multiple.
    var two = BigFloat.from_float64(2.0)
    assert_equal(
        String(remainder(five, two, 53)),
        "1",
        "five halves ties to two, leaving one",
    )
    assert_equal(
        String(remainder(BigFloat.from_float64(7.0), two, 53)),
        "-1",
        "seven halves ties to four, leaving minus one",
    )

    # An exponent difference no shift could hold: the quotient here is
    # `2^(2^64 - 1)`, and the division is exact.
    var top = BigFloat(
        significand=BigInt.one(), exponent=Int.MAX, precision=1, sign=False
    )
    var bottom = BigFloat(
        significand=BigInt.one(), exponent=Int.MIN, precision=1, sign=False
    )
    assert_true(
        remainder(top, bottom, 53).is_zero(),
        "a power of two divides another exactly, however far apart",
    )
    assert_true(
        fmod(top, bottom, 53).is_zero(), "and the truncating one agrees"
    )
    assert_false(fmod(top, bottom, 53).sign, "leaving the dividend's sign")
    assert_true(fmod(-top, bottom, 53).sign, "which can be the negative zero")


def test_the_remainder_special_values_follow_ieee() raises:
    """The NaNs, the infinities and the zeros, for both remainders."""
    var two = BigFloat.from_float64(2.0)
    var pairs = [
        [BigFloat.nan(), two.copy()],
        [two.copy(), BigFloat.nan()],
        [BigFloat.infinity(), two.copy()],
        [two.copy(), BigFloat.zero()],
    ]
    for nearest in [True, False]:
        for pair in pairs:
            var got = remainder(pair[0], pair[1], 53) if nearest else fmod(
                pair[0], pair[1], 53
            )
            assert_true(
                got.is_nan(),
                String("a NaN was expected, nearest=") + String(nearest),
            )
        var left = remainder(two, BigFloat.infinity(), 53) if nearest else fmod(
            two, BigFloat.infinity(), 53
        )
        assert_equal(
            left.internal_representation(),
            two.internal_representation(),
            "an infinite divisor leaves the dividend",
        )
        var nought = remainder(
            BigFloat.zero(53, True), two, 53
        ) if nearest else fmod(BigFloat.zero(53, True), two, 53)
        assert_true(nought.is_zero(), "a zero dividend leaves a zero")
        assert_true(nought.sign, "keeping its sign")


def test_the_methods_agree_with_the_free_functions() raises:
    """Every wrapper on the struct, against the function it delegates to."""
    var x = BigFloat.from_string("1.5", 53)
    var y = BigFloat.from_string("-2.25", 53)
    var z = BigFloat.from_string("0.125", 53)

    assert_equal(
        x.next_plus(53).internal_representation(),
        next_plus(x, 53).internal_representation(),
        "next_plus",
    )
    assert_equal(
        x.next_minus(53).internal_representation(),
        next_minus(x, 53).internal_representation(),
        "next_minus",
    )
    assert_equal(
        x.next_toward(y, 53).internal_representation(),
        next_toward(x, y, 53).internal_representation(),
        "next_toward",
    )
    assert_equal(String(x.logb()), String(logb(x)), "logb")
    assert_equal(
        x.scaleb(5).internal_representation(),
        scaleb(x, 5).internal_representation(),
        "scaleb",
    )
    assert_equal(
        x.copy_sign(y).internal_representation(),
        copy_sign(x, y).internal_representation(),
        "copy_sign",
    )
    assert_equal(
        y.copy_abs().internal_representation(),
        copy_abs(y).internal_representation(),
        "copy_abs",
    )
    assert_equal(
        x.copy_negate().internal_representation(),
        copy_negate(x).internal_representation(),
        "copy_negate",
    )
    assert_equal(x.number_class(), number_class(x), "number_class")
    assert_equal(x.is_integer(), is_integer(x), "is_integer")
    assert_equal(
        x.truncate().internal_representation(),
        truncate(x).internal_representation(),
        "truncate",
    )
    assert_equal(
        x.floor().internal_representation(),
        floor(x).internal_representation(),
        "floor",
    )
    assert_equal(
        x.ceil().internal_representation(),
        ceil(x).internal_representation(),
        "ceil",
    )
    assert_equal(
        x.round_to_integer().internal_representation(),
        round_to_integer(x).internal_representation(),
        "round_to_integer",
    )
    assert_equal(
        x.__trunc__().internal_representation(),
        truncate(x).internal_representation(),
        "__trunc__",
    )
    assert_equal(
        x.__floor__().internal_representation(),
        floor(x).internal_representation(),
        "__floor__",
    )
    assert_equal(
        x.__ceil__().internal_representation(),
        ceil(x).internal_representation(),
        "__ceil__",
    )
    assert_equal(
        x.fma(y, z, 53).internal_representation(),
        fma(x, y, z, 53).internal_representation(),
        "fma",
    )
    assert_equal(
        x.remainder(y, 53).internal_representation(),
        remainder(x, y, 53).internal_representation(),
        "remainder",
    )
    assert_equal(
        x.fmod(y, 53).internal_representation(),
        fmod(x, y, 53).internal_representation(),
        "fmod",
    )


def test_a_precision_must_be_one_the_rounding_accepts() raises:
    """The four operations that take a precision refuse an absurd one."""
    var one = BigFloat.from_float64(1.0)
    var two = BigFloat.from_float64(2.0)
    for precision in [0, -1, Int.MAX, Int.MAX // 4 + 1]:
        for which in [0, 1, 2, 3, 4, 5]:
            var raised = False
            try:
                if which == 0:
                    _ = next_plus(one, precision)
                elif which == 1:
                    _ = next_minus(one, precision)
                elif which == 2:
                    _ = next_toward(one, two, precision)
                elif which == 3:
                    _ = fma(one, two, two, precision)
                elif which == 4:
                    _ = remainder(one, two, precision)
                else:
                    _ = fmod(one, two, precision)
            except:
                raised = True
            assert_true(
                raised,
                String("a precision of ")
                + String(precision)
                + " was taken by case "
                + String(which),
            )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
