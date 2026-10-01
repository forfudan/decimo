"""
Checks the hyperbolic functions and their inverses.

Three kinds of check. The tables pin the values against mpmath at fifty
digits. The identities tie the six to each other -- `cosh^2 - sinh^2 = 1`,
`tanh = sinh/cosh`, and each inverse against the function it inverts -- which
is what catches a function that is wrong in a way its own table would agree
with. And the small arguments are checked on their own, because keeping them is
the reason these are written in terms of `expm1` and `log1p` rather than of
`exp` and `ln`: `sinh(1E-60)` is `1E-60`, and the textbook form gives zero.

`a - b` and `a + b` on `BigDecimal` round to the default precision of 28, so a
check on a 50-digit result uses the exact forms from `arithmetics`.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.arithmetics import add, multiply, subtract
from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigdecimal.exponential import exp
from decimo.bigdecimal.hyperbolic import (
    arccosh,
    arccosh_rounded,
    arcsinh,
    arcsinh_rounded,
    arctanh,
    arctanh_rounded,
    cosh,
    cosh_rounded,
    sinh,
    sinh_rounded,
    tanh,
    tanh_rounded,
)
from decimo.rounding_mode import RoundingMode

comptime WIDTH = 50
"""Digits the tables and identities are checked at."""

comptime TOLERANCE = "1E-45"
"""What an identity may be off by at `WIDTH`.

An identity here is up to four rounded functions deep, so the last handful of
digits belongs to the arithmetic rather than to the functions.
"""


def assert_close(expected: BDec, got: BDec, msg: String) raises:
    """Fails unless the two agree to within `TOLERANCE` relative to `expected`.
    """
    var scale = abs(expected)
    if scale < BDec("1"):
        scale = BDec("1")
    assert_within(expected, got, multiply(scale, BDec(TOLERANCE)), msg)


def assert_within(expected: BDec, got: BDec, room: BDec, msg: String) raises:
    """Fails unless the two agree to within `room`, which the caller sizes."""
    var residual = abs(subtract(expected, got))
    assert_true(
        residual <= room,
        msg
        + ": expected "
        + String(expected)
        + ", got "
        + String(got)
        + ", allowed "
        + String(room),
    )


def test_tables_against_mpmath() raises:
    """Fifty digits, from mpmath at eighty."""
    var arguments = [
        "1E-60",
        "0.001",
        "0.5",
        "1",
        "3",
        "-2",
    ]
    var sinh_expected = [
        "1E-60",
        "0.0010000001666666750000001984127011684303601491103097",
        "0.52109530549374736162242562641149155910592898261148",
        "1.1752011936438014568823818505956008151557179813341",
        "10.017874927409901898974593619465828060178104123183",
        "-3.6268604078470187676682139828012617048863420123211",
    ]
    var cosh_expected = [
        "1.0000000000000000000000000000000000000000000000000",
        "1.0000005000000416666680555555803571431327160514704",
        "1.1276259652063807852262251614026720125478471180987",
        "1.5430806348152437784779056207570616826015291123659",
        "10.067661995777765841953936035115889836809803715371",
        "3.7621956910836314595622134777737461082939735582307",
    ]
    for i in range(len(arguments)):
        assert_equal(
            sinh(BDec(arguments[i]), WIDTH),
            BDec(sinh_expected[i]),
            "sinh(" + arguments[i] + ")",
        )
        assert_equal(
            cosh(BDec(arguments[i]), WIDTH),
            BDec(cosh_expected[i]),
            "cosh(" + arguments[i] + ")",
        )

    var tanh_arguments = ["1E-60", "0.5", "1", "5", "-3"]
    var tanh_expected = [
        "1E-60",
        "0.46211715726000975850231848364367254873028928033011",
        "0.76159415595576488811945828260479359041276859725794",
        "0.99990920426259513121099044753447302108981261599055",
        "-0.99505475368673045133188018525548847509781385470028",
    ]
    for i in range(len(tanh_arguments)):
        assert_equal(
            tanh(BDec(tanh_arguments[i]), WIDTH),
            BDec(tanh_expected[i]),
            "tanh(" + tanh_arguments[i] + ")",
        )


def test_inverse_tables_against_mpmath() raises:
    """Fifty digits, from mpmath at eighty."""
    var arcsinh_arguments = ["1E-60", "0.5", "1", "3", "-2"]
    var arcsinh_expected = [
        "1E-60",
        "0.48121182505960344749775891342436842313518433438566",
        "0.88137358701954302523260932497979230902816032826164",
        "1.8184464592320668234836989635607089937862539427681",
        "-1.4436354751788103424932767402731052694055530031570",
    ]
    for i in range(len(arcsinh_arguments)):
        assert_equal(
            arcsinh(BDec(arcsinh_arguments[i]), WIDTH),
            BDec(arcsinh_expected[i]),
            "arcsinh(" + arcsinh_arguments[i] + ")",
        )

    var arccosh_arguments = [
        "1.0000000000000000000000000000000000000000001",
        "1.5",
        "2",
        "10",
    ]
    var arccosh_expected = [
        "4.4721359549995793928183473374625524708812366819553E-22",
        "0.96242365011920689499551782684873684627036866877132",
        "1.3169578969248167086250463473079684440269819714675",
        "2.9932228461263808979126677137741829130836604511810",
    ]
    for i in range(len(arccosh_arguments)):
        assert_equal(
            arccosh(BDec(arccosh_arguments[i]), WIDTH),
            BDec(arccosh_expected[i]),
            "arccosh(" + arccosh_arguments[i] + ")",
        )

    var arctanh_arguments = [
        "1E-60",
        "0.1",
        "0.5",
        "0.9",
        "0.9999999999",
        "-0.5",
    ]
    var arctanh_expected = [
        "1E-60",
        "0.10033534773107558063572655206003894526336286914596",
        "0.54930614433405484569762261846126285232374527891137",
        "1.4722194895832202300045137159439267686186896306496",
        "11.859499055225201074797948334150888488709923395741",
        "-0.54930614433405484569762261846126285232374527891137",
    ]
    for i in range(len(arctanh_arguments)):
        assert_equal(
            arctanh(BDec(arctanh_arguments[i]), WIDTH),
            BDec(arctanh_expected[i]),
            "arctanh(" + arctanh_arguments[i] + ")",
        )


def test_the_hyperbolic_identity() raises:
    """`cosh(x)^2 - sinh(x)^2 = 1`, which no table of either can confirm."""
    var arguments = [
        BDec("1E-30"),
        BDec("0.001"),
        BDec("0.5"),
        BDec("1"),
        BDec("3"),
        BDec("-2"),
        BDec("20"),
    ]
    for x in arguments:
        var c = cosh(x, WIDTH + 4)
        var s = sinh(x, WIDTH + 4)
        # The identity cancels: both squares are about `cosh(x)^2` and their
        # difference is one, so the digits of the answer start where the
        # squares' own last digits are. At `x = 20` that alone is 37 digits of
        # the 54 the squares carry. The room allowed is therefore the error of
        # the squares, not of the one they produce.
        var room = multiply(multiply(c, c), BDec(TOLERANCE))
        if room < BDec(TOLERANCE):
            room = BDec(TOLERANCE)
        assert_within(
            BDec("1"),
            subtract(multiply(c, c), multiply(s, s)),
            room,
            "cosh^2 - sinh^2 at " + String(x),
        )


def test_tanh_is_the_ratio() raises:
    """`tanh(x) = sinh(x) / cosh(x)`, computed here by a different route."""
    for x in [BDec("1E-30"), BDec("0.5"), BDec("1"), BDec("-3"), BDec("12")]:
        assert_close(
            sinh(x, WIDTH + 4).true_divide(
                cosh(x, WIDTH + 4), precision=WIDTH + 4
            ),
            tanh(x, WIDTH),
            "tanh as a ratio at " + String(x),
        )


def test_sinh_and_cosh_against_the_textbook_form() raises:
    """Where the textbook form is still accurate, it is the reference.

    At `|x| >= 1/2` nothing cancels in `(e^x - e^-x)/2`, so it pins the
    `expm1` form the kernel uses instead.
    """
    for x in [BDec("0.5"), BDec("1"), BDec("3"), BDec("-2")]:
        var up = exp(x, WIDTH + 4)
        var down = exp(-x, WIDTH + 4)
        assert_close(
            subtract(up, down).true_divide(BDec("2"), precision=WIDTH + 4),
            sinh(x, WIDTH),
            "sinh against (e^x - e^-x)/2 at " + String(x),
        )
        assert_close(
            add(up, down).true_divide(BDec("2"), precision=WIDTH + 4),
            cosh(x, WIDTH),
            "cosh against (e^x + e^-x)/2 at " + String(x),
        )


def test_the_inverses_undo_their_functions() raises:
    """Each inverse against the function it inverts, both ways round."""
    for x in [BDec("1E-30"), BDec("0.001"), BDec("0.5"), BDec("1"), BDec("3")]:
        assert_close(
            x,
            arcsinh(sinh(x, WIDTH + 4), WIDTH),
            "arcsinh(sinh) at " + String(x),
        )
        assert_close(
            x,
            sinh(arcsinh(x, WIDTH + 4), WIDTH),
            "sinh(arcsinh) at " + String(x),
        )

    # `arccosh(cosh(x))` cannot start from a tiny `x`, and no implementation
    # could. `cosh(1E-30)` is `1 + 5E-61`, which is one to every digit carried
    # here, so the argument is gone before `arccosh` is reached. The round trip
    # is only meaningful where `cosh(x) - 1` survives the width.
    for x in [BDec("0.001"), BDec("0.5"), BDec("1"), BDec("3")]:
        assert_close(
            x,
            arccosh(cosh(x, WIDTH + 4), WIDTH),
            "arccosh(cosh) at " + String(x),
        )

    for x in [BDec("1E-30"), BDec("0.001"), BDec("0.5"), BDec("0.9")]:
        assert_close(
            x,
            arctanh(tanh(x, WIDTH + 4), WIDTH),
            "arctanh(tanh) at " + String(x),
        )
        assert_close(
            x,
            tanh(arctanh(x, WIDTH + 4), WIDTH),
            "tanh(arctanh) at " + String(x),
        )


def test_the_small_arguments_survive() raises:
    """The reason for the `expm1` and `log1p` forms, stated as a test.

    Each of these functions is its own argument to fifty digits near zero, and
    the textbook forms return zero there instead.
    """
    var tiny = BDec("1E-60")
    var expected = BDec("1E-60")
    assert_equal(sinh(tiny, WIDTH), expected, "sinh of a tiny argument")
    assert_equal(tanh(tiny, WIDTH), expected, "tanh of a tiny argument")
    assert_equal(arcsinh(tiny, WIDTH), expected, "arcsinh of a tiny argument")
    assert_equal(arctanh(tiny, WIDTH), expected, "arctanh of a tiny argument")

    # What the textbook form would have given, for the contrast.
    var naive = subtract(exp(tiny, WIDTH), exp(-tiny, WIDTH)).true_divide(
        BDec("2"), precision=WIDTH
    )
    assert_true(
        naive.coefficient.is_zero(),
        "(e^x - e^-x)/2 was expected to lose a tiny argument, got "
        + String(naive),
    )


def test_the_even_and_odd_symmetries() raises:
    """`cosh` is even, the other five are odd."""
    for x in [BDec("1E-30"), BDec("0.5"), BDec("1"), BDec("4")]:
        assert_equal(
            cosh(x, WIDTH), cosh(-x, WIDTH), "cosh is even at " + String(x)
        )
        assert_equal(
            -sinh(x, WIDTH), sinh(-x, WIDTH), "sinh is odd at " + String(x)
        )
        assert_equal(
            -tanh(x, WIDTH), tanh(-x, WIDTH), "tanh is odd at " + String(x)
        )
        assert_equal(
            -arcsinh(x, WIDTH),
            arcsinh(-x, WIDTH),
            "arcsinh is odd at " + String(x),
        )
    for x in [BDec("1E-30"), BDec("0.5"), BDec("0.9")]:
        assert_equal(
            -arctanh(x, WIDTH),
            arctanh(-x, WIDTH),
            "arctanh is odd at " + String(x),
        )


def test_the_exact_points() raises:
    """The three arguments whose answers are exact."""
    assert_equal(String(sinh(BDec("0"), WIDTH)), "0")
    assert_equal(String(tanh(BDec("0"), WIDTH)), "0")
    assert_equal(String(arcsinh(BDec("0"), WIDTH)), "0")
    assert_equal(String(arctanh(BDec("0"), WIDTH)), "0")
    assert_equal(String(arccosh(BDec("1"), WIDTH)), "0")
    assert_equal(cosh(BDec("0"), WIDTH), BDec("1"), "cosh(0) is one")


def test_tanh_saturates_instead_of_computing_a_huge_exponential() raises:
    """Far from zero `tanh` is one to the digits asked for.

    Without the shortcut this would reach for `e^2000000`, a number of 868589
    digits, to answer `1`. The test is that it returns at all.
    """
    assert_equal(String(tanh(BDec("1000000"), WIDTH)), "1")
    assert_equal(String(tanh(BDec("-1000000"), WIDTH)), "-1")
    # `tanh(x)` falls short of one by `2e^-2x`, which at fifty digits is
    # resolvable up to about `x = 57`. At 50 it is `7E-44` short and the
    # answer has to show it.
    assert_true(
        tanh(BDec("50"), WIDTH) < BDec("1"),
        "tanh(50) at fifty digits should still be under one",
    )


def test_outside_the_domains_raises() raises:
    """`arccosh` needs `x >= 1` and `arctanh` needs `|x| < 1`."""
    for x in [BDec("0.9999999999"), BDec("0"), BDec("-1"), BDec("-5")]:
        var raised = False
        try:
            _ = arccosh(x, WIDTH)
        except:
            raised = True
        assert_true(raised, "arccosh accepted " + String(x))

    for x in [BDec("1"), BDec("-1"), BDec("1.0000000001"), BDec("-3")]:
        var raised = False
        try:
            _ = arctanh(x, WIDTH)
        except:
            raised = True
        assert_true(raised, "arctanh accepted " + String(x))


def test_rounding_modes_are_carried_through() raises:
    """The expected values are mpmath at sixty digits, rounded once per mode."""
    # sinh(0.3) = 0.30452029344714261896...
    assert_equal(
        String(sinh_rounded(BDec("0.3"), 9, RoundingMode.ROUND_HALF_EVEN)),
        "0.304520293",
    )
    assert_equal(
        String(sinh_rounded(BDec("0.3"), 9, RoundingMode.ROUND_UP)),
        "0.304520294",
    )
    # cosh(0.3) = 1.04533851412886290822...
    assert_equal(
        String(cosh_rounded(BDec("0.3"), 9, RoundingMode.ROUND_HALF_EVEN)),
        "1.04533851",
    )
    assert_equal(
        String(cosh_rounded(BDec("0.3"), 9, RoundingMode.ROUND_UP)),
        "1.04533852",
    )
    # tanh(0.3) = 0.29131261245159090561...
    assert_equal(
        String(tanh_rounded(BDec("0.3"), 9, RoundingMode.ROUND_HALF_EVEN)),
        "0.291312612",
    )
    assert_equal(
        String(tanh_rounded(BDec("0.3"), 9, RoundingMode.ROUND_UP)),
        "0.291312613",
    )
    # arcsinh(0.3) = 0.29567304756342243910...
    assert_equal(
        String(arcsinh_rounded(BDec("0.3"), 9, RoundingMode.ROUND_HALF_EVEN)),
        "0.295673048",
    )
    assert_equal(
        String(arcsinh_rounded(BDec("0.3"), 9, RoundingMode.ROUND_DOWN)),
        "0.295673047",
    )
    # arccosh(1.3) = 0.75643291085695963970...
    assert_equal(
        String(arccosh_rounded(BDec("1.3"), 9, RoundingMode.ROUND_HALF_EVEN)),
        "0.756432911",
    )
    assert_equal(
        String(arccosh_rounded(BDec("1.3"), 9, RoundingMode.ROUND_DOWN)),
        "0.756432910",
    )
    # arctanh(0.3) = 0.30951960420311172007...
    assert_equal(
        String(arctanh_rounded(BDec("0.3"), 9, RoundingMode.ROUND_HALF_EVEN)),
        "0.309519604",
    )
    assert_equal(
        String(arctanh_rounded(BDec("0.3"), 9, RoundingMode.ROUND_UP)),
        "0.309519605",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
