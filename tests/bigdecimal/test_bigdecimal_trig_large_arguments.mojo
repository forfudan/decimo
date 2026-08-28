"""
Sine, cosine and tangent where the reduction is delicate.

Two shapes of argument cost the reduction its digits: one far from zero, and
one very close to a multiple of `pi/2`. Both used to be met with a fixed
budget of ninety-nine digits, and both could exhaust it silently.

`sin(x)` reduces `x` modulo `2*pi`, and everything above the remainder
cancels. An argument of `10^k` therefore spends `k` digits of pi before the
remainder starts, so a reduction budget that does not count `k` runs out. The
old budget was a flat ninety-nine digits: right up to `10^99`, half wrong by
`10^105`, and at `10^150` it returned `-0.8939514546180310700365995531` where
the true value is `-0.9507438768330459768719272005` -- nothing correct in it
at all, and nothing to say so.

The expected values here were computed independently: pi by Machin's formula
to `28 + k + 40` digits, the argument reduced against it, then the Taylor
series, all in CPython's `decimal`.
"""

from std import testing
from std.testing import assert_equal

from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigdecimal.trigonometric import sin, cos, tan, cot, csc, sec


def test_sine_of_a_large_argument() raises:
    assert_equal(
        String(sin(BDec("1E+20"), 28)), "-0.6452512852657808442058117113"
    )
    assert_equal(
        String(sin(BDec("1E+105"), 28)), "-0.8350242863139418836996674337"
    )
    assert_equal(
        String(sin(BDec("1E+150"), 28)), "-0.9507438768330459768719272005"
    )
    assert_equal(
        String(sin(BDec("1E+300"), 28)), "-0.9857504251603769966090475314"
    )


def test_cosine_of_a_large_argument() raises:
    assert_equal(
        String(cos(BDec("1E+20"), 28)), "0.7639704044417283004001468027"
    )
    assert_equal(
        String(cos(BDec("1E+105"), 28)), "0.5502130871452368583126114139"
    )
    assert_equal(
        String(cos(BDec("1E+150"), 28)), "-0.3099775486458170915883718138"
    )
    assert_equal(
        String(cos(BDec("1E+300"), 28)), "-0.1682144443742450728518756644"
    )


def test_tangent_of_a_large_argument() raises:
    assert_equal(
        String(tan(BDec("1E+20"), 28)), "-0.8446024630198842541840932340"
    )
    assert_equal(
        String(tan(BDec("1E+105"), 28)), "-1.517637994847485169454298238"
    )
    assert_equal(
        String(tan(BDec("1E+150"), 28)), "3.067137865263183258766505146"
    )
    assert_equal(
        String(tan(BDec("1E+300"), 28)), "5.860081925944898104682611488"
    )


def test_the_reciprocals_follow() raises:
    # `cot`, `csc` and `sec` are one over the three above, so they inherit
    # the budget rather than carrying their own.
    assert_equal(
        String(cot(BDec("1E+150"), 28)), "0.3260368603985763635056888982"
    )
    assert_equal(
        String(csc(BDec("1E+150"), 28)), "-1.051807983587575157655389916"
    )
    assert_equal(
        String(sec(BDec("1E+150"), 28)), "-3.226040093447568562295395823"
    )


def test_an_argument_next_to_a_multiple_of_pi() raises:
    # pi itself, taken to 250 digits. `sin` of it is the tail of pi that the
    # literal cut off, about `1.5E-250`, and the subtraction `pi - x` eats
    # 250 digits to find it. The old budget of `precision + 99` returned
    # `3.9E-127` here: nothing in it was right.
    var near_zero = BDec(
        "3.14159265358979323846264338327950288419716939937510582097494459"
        "2307816406286208998628034825342117067982148086513282306647093844"
        "6095505822317253594081284811174502841027019385211055596446229489"
        "54930381964428810975665933446128475648233786783165271201909"
    )
    assert_equal(
        String(sin(near_zero, 28)), "1.456485669234603486104543266E-250"
    )
    assert_equal(String(cos(near_zero, 28)), "-1.000000000000000000000000000")
    assert_equal(
        String(tan(near_zero, 28)), "-1.456485669234603486104543266E-250"
    )


def test_an_argument_next_to_a_pole() raises:
    # Half of pi, to 250 digits, where `cos` is about `-4.3E-250` and `tan`
    # is its reciprocal.
    var near_pole = BDec(
        "1.57079632679489661923132169163975144209858469968755291048747229"
        "6153908203143104499314017412671058533991074043256641153323546922"
        "3047752911158626797040642405587251420513509692605527798223114744"
        "77465190982214405487832966723064237824116893391582635600955"
    )
    assert_equal(
        String(cos(near_pole, 28)), "-4.271757165382698256947728367E-250"
    )
    assert_equal(
        String(tan(near_pole, 28)), "-2.340957037782394595000617291E+249"
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
