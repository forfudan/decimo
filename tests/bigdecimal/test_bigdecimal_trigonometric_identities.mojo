"""
Checks the trigonometric functions against identities rather than a table.

The existing suite compares each function to a table of expected values at one
precision. That pins the values it lists and nothing else. What it cannot see
is a function that is self-consistently wrong -- an argument reduction that
lands on the wrong multiple of `2*pi` gives a sine and a cosine that still
satisfy `sin^2 + cos^2 = 1`, because they belong to the same wrong angle.

So there are two kinds of check here. The identities catch a function that
disagrees with its siblings, and the reduction check catches the case they
cannot, by reducing the argument by hand against `pi` and comparing.

One trap worth naming, because it cost a false positive while this was being
written: `a - b` and `a + b` on `BigDecimal` round to the default precision of
28. An expression checking a 50-digit result has to use the exact forms from
`arithmetics`, or unary minus, or it measures the operator instead.
"""

from std import testing
from std.testing import assert_true

from decimo.bigdecimal.arithmetics import add, multiply, subtract
from decimo.bigdecimal.bigdecimal import BDec
from decimo.rounding_mode import RoundingMode

comptime SLACK = 3


def digits_agreeing(expected: BDec, got: BDec) raises -> Int:
    """Leading digits of `expected` that `got` reproduces; 999 when equal."""
    var residual = abs(subtract(expected, got))
    if residual.coefficient.is_zero():
        return 999
    var target = abs(expected)
    if target.coefficient.is_zero():
        target = BDec("1")
    var digits = 0
    var scaled = residual.copy()
    while digits < 300:
        if scaled >= target:
            break
        scaled = multiply(scaled, BDec("10"))
        digits += 1
    return digits


def assert_agrees(
    expected: BDec, got: BDec, precision: Int, what: String
) raises:
    var agreeing = digits_agreeing(expected, got)
    assert_true(
        agreeing >= precision - SLACK,
        what
        + " at precision "
        + String(precision)
        + " agreed to only "
        + String(agreeing)
        + " digits",
    )


def sweep_arguments() raises -> List[BDec]:
    var values = List[BDec]()
    for text in [
        String("0.0001"),
        String("0.5"),
        String("1"),
        String("-1.3"),
        String("3"),
        String("100"),
    ]:
        values.append(BDec(text))
    return values^


def test_the_pythagorean_identity() raises:
    var one = BDec("1")
    for precision in [20, 50]:
        for x in sweep_arguments():
            var s = x.sin(precision)
            var c = x.cos(precision)
            assert_agrees(
                one,
                add(multiply(s, s), multiply(c, c)),
                precision,
                "sin^2 + cos^2 at " + String(x),
            )


def test_the_four_derived_functions_match_their_definitions() raises:
    var one = BDec("1")
    for precision in [30]:
        for x in sweep_arguments():
            var s = x.sin(precision)
            var c = x.cos(precision)
            var wide = precision + 10
            assert_agrees(
                s.true_divide(c, wide),
                x.tan(precision),
                precision,
                "tan at " + String(x),
            )
            assert_agrees(
                c.true_divide(s, wide),
                x.cot(precision),
                precision,
                "cot at " + String(x),
            )
            assert_agrees(
                one.true_divide(s, wide),
                x.csc(precision),
                precision,
                "csc at " + String(x),
            )
            assert_agrees(
                one.true_divide(c, wide),
                x.sec(precision),
                precision,
                "sec at " + String(x),
            )


def test_parity_and_the_arctangent_inverse() raises:
    for precision in [30]:
        for x in sweep_arguments():
            var negated = -x
            assert_agrees(
                -x.sin(precision),
                negated.sin(precision),
                precision,
                "sin is odd at " + String(x),
            )
            assert_agrees(
                x.cos(precision),
                negated.cos(precision),
                precision,
                "cos is even at " + String(x),
            )
            # `arctan` is the expensive one, so it is checked on the two
            # arguments inside its principal range rather than all of them.
            if abs(x) < BDec("1.1") and abs(x) > BDec("0.001"):
                assert_agrees(
                    x,
                    x.tan(precision).arctan(precision + 10),
                    precision,
                    "arctan undoes tan at " + String(x),
                )


def test_the_argument_reduction_lands_on_the_right_multiple() raises:
    """The identities above cannot see a reduction that is off by a period.

    A sine and a cosine of the same wrong angle still satisfy every identity
    between them, so the argument is reduced here by hand against `pi` and the
    two answers compared.
    """
    comptime PRECISION = 40
    var wide = PRECISION + 40
    var two_pi = multiply(BDec.pi(wide + 40), BDec("2"))

    for text in [
        String("10"),
        String("1000"),
        String("1000000"),
        String("1E+20"),
        String("1E+40"),
        String("-1E+20"),
    ]:
        var x = BDec(text)
        var periods = x.true_divide(two_pi, wide).round(
            0, RoundingMode.half_even()
        )
        var reduced = subtract(x, multiply(two_pi, periods))
        assert_agrees(
            reduced.sin(wide),
            x.sin(PRECISION),
            PRECISION,
            "sine of " + text + " after reduction",
        )


def test_zero_and_the_poles() raises:
    comptime PRECISION = 30
    var zero = BDec("0")
    testing.assert_equal(String(zero.sin(PRECISION)), "0")
    testing.assert_equal(String(zero.cos(PRECISION)), "1")
    testing.assert_equal(String(zero.tan(PRECISION)), "0")
    testing.assert_equal(String(zero.sec(PRECISION)), "1")

    # The two that are a reciprocal of the sine have no value at zero.
    with testing.assert_raises():
        _ = zero.cot(PRECISION)
    with testing.assert_raises():
        _ = zero.csc(PRECISION)

    # `tan^2 + 1 == sec^2` however large the two grow near a pole.
    var half_pi = BDec.pi(PRECISION + 30).true_divide(BDec("2"), PRECISION + 30)
    for offset in [String("1E-5"), String("1E-15"), String("-1E-15")]:
        var x = add(half_pi, BDec(offset))
        var tangent = x.tan(PRECISION)
        var secant = x.sec(PRECISION)
        assert_agrees(
            multiply(secant, secant),
            add(multiply(tangent, tangent), BDec("1")),
            PRECISION,
            "tan^2 + 1 = sec^2 at an offset of " + offset,
        )


def test_the_derived_three_at_depth_against_cpython() raises:
    """Four hundred digits of `csc`, `sec` and `cot`, from CPython at 440.

    The three are a sine or a cosine and a division, and that sine is now
    the binary kernel. The tests above ask for a hundred digits at most and
    weigh the three against decimo's own sine and cosine, which cannot catch
    a kernel that is wrong in the same way twice. The reference here is a
    Taylor sum carried out in CPython's `decimal`, which shares nothing with
    either route.
    """
    var x = BDec("1.2")
    assert_agrees(
        BDec(
            "1.072916377709897228705116922435239154837639006697757870610040595095132250296565662389278218177089320840921809288662541547237469395219741649308140521849864921759414774049177445805669119820715472296566123216145529402532567772554405036189807462247550603286588155258759795784932197204110327083536032432022171714739243317982857798338812705739639731118333836279009229287707972389582684542566914186807107717"
        ),
        x.csc(400),
        400,
        "csc(1.2)",
    )
    assert_agrees(
        BDec(
            "2.759703601332406456883432939237783860073115323011027652111642182419992047301659897310069302809899999836590359062895965247038727083494332533485123965850772109411474161851718257281585458425387946867256455383695322393970038793355681171307169105561767265191119142153708867456663855946209003018168057881802563092861541314847742594792970481954543303441810422297879540826809668953112649171090415591113242763"
        ),
        x.sec(400),
        400,
        "sec(1.2)",
    )
    assert_agrees(
        BDec(
            "0.3887795693682049116341915049719034095949849259409758245726565785777032339215846735538929511710443387765328516565703076939565290015857820537208893299545736014235670731325952989624341049345700657309084054142067031933146450011140120932371460585816725781955559801252647581775908636830178663704592870320915209646703136146896536884190167902300400004930370132563899233551215088836963548564563717291277435677"
        ),
        x.cot(400),
        400,
        "cot(1.2)",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
