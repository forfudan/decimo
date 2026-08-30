"""
Tests for Decimal128 trigonometry: sin, cos, tan, cot, sec and csc.

Every expected value was checked against a reference built on CPython's
`decimal`, reducing the argument against a 140-digit quarter turn and summing
the series at 140 digits.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.decimal128.decimal128 import Decimal128
from decimo.decimal128.trigonometric import (
    cos,
    cot,
    csc,
    reduce,
    sec,
    sin,
    tan,
)
from decimo.errors import OverflowError, ZeroDivisionError


def test_trigonometric_values() raises:
    """Sine, cosine and tangent across the quadrants and across the range.

    The last four arguments are the point of the exercise. Reducing them
    against a 28-digit quarter turn -- the widest `Decimal128` itself holds --
    leaves 8 correct digits of the remainder at `1E+20` and 1 at `1.2E+27`,
    so the answer would be wrong in most of the digits it printed. The
    quarter turn is kept in four pieces of 38 digits here.
    """

    def _check(
        argument: String, sine: String, cosine: String, tangent: String
    ) raises:
        var x = Decimal128(argument)
        assert_equal(String(sin(x)), sine)
        assert_equal(String(cos(x)), cosine)
        assert_equal(String(tan(x)), tangent)

    _check(
        "0.5",
        "0.4794255386042030002732879352",
        "0.8775825618903727161162815826",
        "0.5463024898437905132551794658",
    )
    _check(
        "1",
        "0.8414709848078965066525023216",
        "0.5403023058681397174009366074",
        "1.5574077246549022305069748075",
    )
    _check(
        "1.2",
        "0.9320390859672263496701344355",
        "0.3623577544766735776383733556",
        "2.5721516221263189354099942360",
    )
    _check(
        "2.7",
        "0.4273798802338299345560530859",
        "-0.9040721420170611479825272819",
        "-0.4727276291030375079519891813",
    )
    _check(
        "-1.2",
        "-0.9320390859672263496701344355",
        "0.3623577544766735776383733556",
        "-2.5721516221263189354099942360",
    )
    _check(
        "3.5",
        "-0.3507832276896198481203688000",
        "-0.9364566872907963376986576267",
        "0.3745856401585946663305125800",
    )
    _check(
        "6.2",
        "-0.0830894028174965780005792891",
        "0.9965420970232174751394026239",
        "-0.0833777148659287977660811118",
    )
    _check(
        "100",
        "-0.5063656411097587936565576105",
        "0.8623188722876839341019385140",
        "-0.5872139151569290766778096356",
    )
    _check(
        "1000000",
        "-0.3499935021712929521176524868",
        "0.9367521275331447869385325351",
        "-0.3736244539875990291734970886",
    )
    _check(
        "1e20",
        "-0.6452512852657808442058117113",
        "0.7639704044417283004001468027",
        "-0.8446024630198842541840932340",
    )
    _check(
        "12345678901234567890123456789",
        "0.1829287606848061096390398032",
        "0.9831261712081114843673218647",
        "0.1860684478168399087099001460",
    )
    _check(
        "1570796326794896619231321691.6",
        "-0.0397409738722947475692415088",
        "0.9992100154600541163536426316",
        "-0.0397723934482354985664791609",
    )
    _check(
        "157079632679489.66192313216916",
        "-0.0000000000000039751442098585",
        "1.0000000000000000000000000000",
        "-0.0000000000000039751442098585",
    )
    _check(
        "0.0000000001",
        "0.0000000001000000000000000000",
        "0.9999999999999999999950000000",
        "0.0000000001000000000000000000",
    )


def test_reciprocal_values() raises:
    """Cotangent, secant and cosecant."""

    def _check(
        argument: String, cotangent: String, secant: String, cosecant: String
    ) raises:
        var x = Decimal128(argument)
        assert_equal(String(cot(x)), cotangent)
        assert_equal(String(sec(x)), secant)
        assert_equal(String(csc(x)), cosecant)

    _check(
        "1.2",
        "0.3887795693682049116341915050",
        "2.7597036013324064568834329392",
        "1.0729163777098972287051169224",
    )
    _check(
        "2.7",
        "-2.1153830206569885196778981812",
        "-1.1061064195263396963425488606",
        "2.3398387389057146555658140919",
    )
    _check(
        "100",
        "-1.7029569194264692160987314596",
        "1.1596638229046938325514044466",
        "-1.9748575314240999612122645488",
    )
    _check(
        "1e20",
        "-1.1839889697035577581251403412",
        "1.3089512292439527516034322927",
        "-1.5497838173047530601976829335",
    )


def test_trigonometric_exact_points() raises:
    """Zero is the one angle whose answers are exact."""
    assert_equal(String(sin(Decimal128("0"))), "0")
    assert_equal(String(cos(Decimal128("0"))), "1")
    assert_equal(String(tan(Decimal128("0"))), "0")
    assert_equal(String(sec(Decimal128("0"))), "1")

    # And the two that have no value there.
    var raised = False
    try:
        _ = csc(Decimal128("0"))
    except:
        raised = True
    assert_true(raised, "csc(0) should raise")

    raised = False
    try:
        _ = cot(Decimal128("0"))
    except:
        raised = True
    assert_true(raised, "cot(0) should raise")


def test_tangent_near_a_pole() raises:
    """An angle a hair from a pole gives a large tangent, or none at all.

    `7.8539816339744830961566084582` is the closest `Decimal128` gets to five
    quarter turns; the tangent there is past what the type holds, and saying
    so is the answer. One quarter turn along, the tangent is large but fits.
    """
    var raised = False
    try:
        _ = tan(Decimal128("7.8539816339744830961566084582"))
    except:
        raised = True
    assert_true(raised, "the tangent past a pole should overflow")

    assert_equal(
        String(tan(Decimal128("1.5707963267948966192313216916"))),
        "25156320052992586843308997627",
    )


def test_reduction_reports_what_survived() raises:
    """The reduction says how much of the remainder it stands behind.

    An argument inside the first quarter turn is passed through untouched, so
    nothing is lost; one that lands on a quarter turn has cancelled most of
    what it carried, and the count says so.
    """
    var inside = reduce(Decimal128("0.5"))
    assert_equal(inside[1], 0)
    assert_true(
        inside[2] < UInt256(1000),
        "an argument needing no reduction loses nothing",
    )

    var far = reduce(Decimal128("1570796326794896619231321691.6"))
    assert_true(
        far[2] > inside[2],
        "an argument on a quarter turn has less of its remainder left",
    )

    # Quadrants, one per turn.
    assert_equal(reduce(Decimal128("0.5"))[1], 0)
    assert_equal(reduce(Decimal128("2"))[1], 1)
    assert_equal(reduce(Decimal128("3.5"))[1], 2)
    assert_equal(reduce(Decimal128("5"))[1], 3)


def test_trigonometric_methods() raises:
    """The methods on the type give what the functions give."""
    var x = Decimal128("1.2")
    assert_equal(String(x.sin()), String(sin(x)))
    assert_equal(String(x.cos()), String(cos(x)))
    assert_equal(String(x.tan()), String(tan(x)))
    assert_equal(String(x.cot()), String(cot(x)))
    assert_equal(String(x.sec()), String(sec(x)))
    assert_equal(String(x.csc()), String(csc(x)))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
