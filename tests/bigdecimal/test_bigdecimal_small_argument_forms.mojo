"""
Checks `expm1`, `log1p` and `hypot`.

`expm1` and `log1p` exist for one reason, so that is what most of these check:
near zero they keep an answer that `exp(x) - 1` and `ln(1 + x)` throw away.
`exp(1E-60)` rounds to one at any working precision worth having, and the
subtraction then returns zero; `1 + 1E-60` rounds to one before the logarithm
is even reached. The round-trip identities pin the two against each other, and
the tables pin them against mpmath at fifty digits.

`hypot` has no overflow to avoid here, the exponent being unbounded, so what it
is checked for is exactness on the Pythagorean triples, symmetry in its two
legs, and the shortcut it takes when one leg cannot reach the digits asked for.

`a - b` and `a + b` on `BigDecimal` round to the default precision of 28, so a
check on a 50-digit result uses the exact forms from `arithmetics`.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.arithmetics import add, subtract
from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigdecimal.exponential import (
    exp,
    expm1,
    expm1_rounded,
    hypot,
    hypot_rounded,
    ln,
    log1p,
    log1p_rounded,
    sqrt,
)
from decimo.rounding_mode import RoundingMode

comptime WIDTH = 50
"""Digits the tables and identities are checked at."""

comptime TOLERANCE = "1E-46"
"""What a round trip may be off by at `WIDTH`.

Each round trip is two rounded functions, so the last few digits belong to
them rather than to the identity.
"""


def assert_close(expected: BDec, got: BDec, msg: String) raises:
    """Fails unless the two agree to within `TOLERANCE`."""
    var residual = abs(subtract(expected, got))
    assert_true(
        residual <= BDec(TOLERANCE),
        msg + ": expected " + String(expected) + ", got " + String(got),
    )


def test_expm1_against_mpmath() raises:
    """Fifty digits, from mpmath at seventy."""
    var arguments = [
        "1E-60",
        "1E-20",
        "0.001",
        "0.5",
        "1",
        "2",
        "-0.5",
        "-3",
    ]
    var expected = [
        "1.0000000000000000000000000000000000000000000000000E-60",
        "1.0000000000000000000050000000000000000000166666667E-20",
        "0.0010005001667083416680557539930583115630762005807015",
        "0.64872127070012814684865078781416357165377610071015",
        "1.7182818284590452353602874713526624977572470937000",
        "6.3890560989306502272304274605750078131803155705518",
        "-0.39346934028736657639620046500881954655808186451281",
        "-0.95021293163213605702065758434993822336830040781158",
    ]
    for i in range(len(arguments)):
        assert_equal(
            expm1(BDec(arguments[i]), WIDTH),
            BDec(expected[i]),
            "expm1(" + arguments[i] + ")",
        )


def test_log1p_against_mpmath() raises:
    """Fifty digits, from mpmath at seventy."""
    var arguments = [
        "1E-60",
        "1E-20",
        "0.001",
        "0.5",
        "1",
        "9",
        "-0.5",
        "-0.9999",
    ]
    var expected = [
        "1.0000000000000000000000000000000000000000000000000E-60",
        "9.9999999999999999999500000000000000000003333333333E-21",
        "0.00099950033308353316680939892053501146075506239316655",
        "0.40546510810816438197801311546434913657199042346249",
        "0.69314718055994530941723212145817656807550013436026",
        "2.3025850929940456840179914546843642076011014886288",
        "-0.69314718055994530941723212145817656807550013436026",
        "-9.2103403719761827360719658187374568304044059545151",
    ]
    for i in range(len(arguments)):
        assert_equal(
            log1p(BDec(arguments[i]), WIDTH),
            BDec(expected[i]),
            "log1p(" + arguments[i] + ")",
        )


def test_expm1_keeps_what_the_naive_form_discards() raises:
    """The reason the function exists, stated as a test.

    `exp(1E-60)` is one to fifty digits, so `exp(x) - 1` is zero there, while
    the answer is `1E-60` to every digit asked for.
    """
    var tiny = BDec("1E-60")
    var naive = subtract(exp(tiny, WIDTH), BDec("1"))
    assert_true(
        naive.coefficient.is_zero(),
        "exp(x) - 1 was expected to lose a tiny argument entirely, got "
        + String(naive),
    )
    assert_equal(
        expm1(tiny, WIDTH),
        BDec("1.0000000000000000000000000000000000000000000000000E-60"),
        "expm1 of a tiny argument",
    )


def test_log1p_keeps_what_the_naive_form_discards() raises:
    """`1 + 1E-60` rounds to one, and `ln(1)` is zero."""
    var tiny = BDec("1E-60")
    var naive = ln(add(BDec("1"), tiny).round_to_precision(WIDTH), WIDTH)
    assert_true(
        naive.coefficient.is_zero(),
        "ln(1 + x) was expected to lose a tiny argument entirely, got "
        + String(naive),
    )
    assert_equal(
        log1p(tiny, WIDTH),
        BDec("1.0000000000000000000000000000000000000000000000000E-60"),
        "log1p of a tiny argument",
    )


def test_the_two_round_trip() raises:
    """`log1p(expm1(x)) = x` and `expm1(log1p(x)) = x`.

    Each one's small-argument branch is the other's, so the trip through both
    is where a mismatch between the series and the plain form would show.
    """
    var arguments = [
        BDec("1E-40"),
        BDec("0.001"),
        BDec("0.25"),
        BDec("0.5"),
        BDec("1"),
        BDec("3"),
        BDec("-0.25"),
        BDec("-0.75"),
    ]
    for x in arguments:
        assert_close(
            x, log1p(expm1(x, WIDTH + 2), WIDTH), "log1p(expm1) at " + String(x)
        )
        assert_close(
            x, expm1(log1p(x, WIDTH + 2), WIDTH), "expm1(log1p) at " + String(x)
        )


def test_the_branch_boundaries() raises:
    """Each kernel switches form at a threshold, and both forms must agree.

    `expm1` sums a series up to `|x| = 1` and subtracts beyond it, `log1p` up
    to `|x| = 1/2`. At and just past each threshold the naive form is still
    accurate -- `exp(1)` is `e`, nowhere near one -- so it serves as the
    reference the series branch is held to.
    """
    # At the threshold itself the two routes must give the same value. The
    # naive form is still accurate here -- `exp(1)` is `e`, nowhere near one --
    # so it is a reference rather than a second guess.
    assert_close(
        subtract(exp(BDec("1"), WIDTH + 2), BDec("1")),
        expm1(BDec("1"), WIDTH),
        "expm1 at its threshold against exp(x) - 1",
    )
    assert_close(
        ln(BDec("1.5"), WIDTH + 2),
        log1p(BDec("0.5"), WIDTH),
        "log1p at its threshold against ln(1 + x)",
    )
    # And just past it, where the other branch answers.
    assert_close(
        subtract(exp(BDec("1.0000000001"), WIDTH + 2), BDec("1")),
        expm1(BDec("1.0000000001"), WIDTH),
        "expm1 past its threshold",
    )
    assert_close(
        ln(BDec("1.5000000001"), WIDTH + 2),
        log1p(BDec("0.5000000001"), WIDTH),
        "log1p past its threshold",
    )


def test_log1p_outside_its_domain_raises() raises:
    """`1 + x` must be positive."""
    for x in [BDec("-1"), BDec("-1.0000000001"), BDec("-2"), BDec("-1E20")]:
        var raised = False
        try:
            _ = log1p(x, WIDTH)
        except:
            raised = True
        assert_true(raised, "log1p accepted " + String(x))


def test_both_are_zero_at_zero() raises:
    """Neither function has anything to round at zero."""
    assert_equal(String(expm1(BDec("0"), WIDTH)), "0")
    assert_equal(String(log1p(BDec("0"), WIDTH)), "0")


def test_hypot_is_exact_on_the_triples() raises:
    """A Pythagorean triple has an integer hypotenuse, and nothing rounds."""
    var legs = [
        ("3", "4", "5"),
        ("5", "12", "13"),
        ("8", "15", "17"),
        ("20", "21", "29"),
    ]
    for triple in legs:
        assert_equal(
            String(hypot(BDec(triple[0]), BDec(triple[1]), WIDTH)),
            triple[2],
            "hypot(" + triple[0] + ", " + triple[1] + ")",
        )


def test_hypot_ignores_the_signs_and_the_order() raises:
    """Both legs enter squared, so neither sign nor order can matter."""
    var expected = hypot(BDec("5"), BDec("12"), WIDTH)
    assert_equal(expected, hypot(BDec("12"), BDec("5"), WIDTH), "order")
    assert_equal(expected, hypot(BDec("-5"), BDec("12"), WIDTH), "left sign")
    assert_equal(expected, hypot(BDec("5"), BDec("-12"), WIDTH), "right sign")
    assert_equal(expected, hypot(BDec("-5"), BDec("-12"), WIDTH), "both signs")


def test_hypot_with_one_leg_at_zero_is_the_other() raises:
    """A degenerate triangle is the length of the leg that is left."""
    assert_equal(String(hypot(BDec("7"), BDec("0"), WIDTH)), "7")
    assert_equal(String(hypot(BDec("0"), BDec("-7"), WIDTH)), "7")
    assert_equal(String(hypot(BDec("0"), BDec("0"), WIDTH)), "0")


def test_hypot_drops_a_leg_it_cannot_reach() raises:
    """A leg whose square sits below the last digit cannot change the answer.

    `1E50` and `1` differ by fifty digits, so the square of the smaller sits a
    hundred below the square of the larger -- far past the fifty asked for.
    The shortcut returns the larger leg, which is also what the full
    computation rounds to.
    """
    assert_equal(
        String(hypot(BDec("1E50"), BDec("1"), WIDTH)),
        "1E+50",
        "a negligible leg",
    )
    # Just inside the threshold the smaller leg does reach the answer.
    var reached = hypot(BDec("1E20"), BDec("1"), WIDTH)
    assert_true(
        reached > BDec("1E20"),
        "a leg within reach should lengthen the hypotenuse, got "
        + String(reached),
    )


def test_hypot_agrees_with_the_square_root_of_the_sum() raises:
    """The definition, spelled out, for legs with no exact hypotenuse."""
    assert_close(
        sqrt(BDec("2"), WIDTH),
        hypot(BDec("1"), BDec("1"), WIDTH),
        "hypot(1, 1) against sqrt(2)",
    )
    assert_close(
        sqrt(BDec("34"), WIDTH),
        hypot(BDec("3"), BDec("5"), WIDTH),
        "hypot(3, 5) against sqrt(34)",
    )


def test_rounding_modes_are_carried_through() raises:
    """The expected values are mpmath at sixty digits, rounded once per mode."""
    # expm1(0.3) = 0.34985880757600310398...
    var x = BDec("0.3")
    assert_equal(
        String(expm1_rounded(x, 9, RoundingMode.ROUND_HALF_EVEN)), "0.349858808"
    )
    assert_equal(
        String(expm1_rounded(x, 9, RoundingMode.ROUND_DOWN)), "0.349858807"
    )
    assert_equal(
        String(expm1_rounded(x, 9, RoundingMode.ROUND_UP)), "0.349858808"
    )
    assert_equal(
        String(expm1_rounded(x, 9, RoundingMode.ROUND_FLOOR)), "0.349858807"
    )

    # log1p(0.3) = 0.26236426446749105204...
    assert_equal(
        String(log1p_rounded(x, 9, RoundingMode.ROUND_HALF_EVEN)), "0.262364264"
    )
    assert_equal(
        String(log1p_rounded(x, 9, RoundingMode.ROUND_UP)), "0.262364265"
    )
    assert_equal(
        String(log1p_rounded(x, 9, RoundingMode.ROUND_CEILING)), "0.262364265"
    )

    # hypot(3, 5) = sqrt(34) = 5.8309518948453004709...
    var three = BDec("3")
    var five = BDec("5")
    assert_equal(
        String(hypot_rounded(three, five, 9, RoundingMode.ROUND_HALF_EVEN)),
        "5.83095189",
    )
    assert_equal(
        String(hypot_rounded(three, five, 9, RoundingMode.ROUND_UP)),
        "5.83095190",
    )
    assert_equal(
        String(hypot_rounded(three, five, 9, RoundingMode.ROUND_FLOOR)),
        "5.83095189",
    )
    # An exact hypotenuse is on a boundary rather than beside one, and every
    # mode has to leave it alone.
    assert_equal(
        String(hypot_rounded(three, BDec("4"), 9, RoundingMode.ROUND_UP)), "5"
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
