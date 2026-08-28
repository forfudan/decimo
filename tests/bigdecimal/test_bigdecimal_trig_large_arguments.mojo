"""
Sine, cosine and tangent of a very large argument.

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


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
