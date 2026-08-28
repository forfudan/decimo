"""
Checks `BigDecimal` division by multiplying the quotient back.

Division is the only `BigDecimal` operation that approximates. When the
divisor has more words than the requested precision needs, both operands are
truncated first, on the argument that the low-order digits cancel. The
argument holds only while each operand keeps enough significant digits, and
the dividend's cap was written in whole words with a floor of one -- a leading
word can hold as little as one digit, so `368.3881690356602195` divided by a
two-hundred-digit number kept the `3` and threw the rest away. The quotient
came back right to one digit out of nineteen.

The oracle here needs no Python and no table of expected values. A correctly
rounded quotient `q` of `x / y` satisfies

    |x - q * y| <= 0.5 * ulp(q) * |y|

where `ulp(q)` is `10^(-q.scale)`. Both the multiply and the subtract are
exact at precision 0, so this is a real check rather than a restatement of
the division. It is also blind to how the quotient was reached, which is what
the truncation path needed.

The shapes are chosen around the truncation threshold, which is
`ceildiv(precision, DIGITS_PER_WORD) + 3` words of divisor: small over huge is
the case that was broken, and huge over small exercises the other direction.
"""

from std import testing
from std.testing import assert_true

from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigdecimal.arithmetics import multiply, subtract
from decimo.biguint.biguint import BigUInt


def digits_string(seed: UInt64, ndigits: Int, mut state: UInt64) -> String:
    """Spells `ndigits` digits from a small deterministic generator."""
    var result = String("")
    for i in range(ndigits):
        state = state * 6364136223846793005 + 1442695040888963407
        var digit = (state >> 33) % 10
        if i == 0 and digit == 0:
            digit = 7
        result += String(digit)
    return result


def assert_quotient_is_correctly_rounded(
    x: BDec, y: BDec, precision: Int, context: String
) raises:
    """`|x - q * y| <= 0.5 * ulp(q) * |y|`, with both sides exact."""
    var q = x.true_divide(y, precision)
    var residual = abs(subtract(x, multiply(q, y)))

    # `0.5 * ulp(q) * |y|` written without a division: `ulp(q)` is
    # `10^(-q.scale)`, so halving it is a coefficient of 5 one place further
    # down.
    var half_ulp = BDec(
        coefficient=BigUInt.from_word_unsafe(BigUInt.Word(5)),
        scale=q.scale + 1,
        sign=False,
    )
    var bound = multiply(half_ulp, abs(y))

    assert_true(
        residual <= bound,
        context
        + ": quotient is not correctly rounded. x = "
        + String(x)
        + ", y = "
        + String(y)
        + ", precision = "
        + String(precision)
        + ", q = "
        + String(q),
    )


def test_a_small_dividend_over_a_huge_divisor() raises:
    """The shape the dividend truncation used to destroy."""
    var state = UInt64(20260828)
    for precision in [1, 18, 19, 28, 50]:
        for dividend_digits in [1, 5, 18, 19, 20, 37]:
            for divisor_digits in [100, 145, 200]:
                var a = BDec(digits_string(0, dividend_digits, state) + ".5")
                var b = BDec(digits_string(0, divisor_digits, state))
                assert_quotient_is_correctly_rounded(
                    a, b, precision, "small over huge"
                )


def test_a_huge_dividend_over_a_small_divisor() raises:
    var state = UInt64(991)
    for precision in [1, 18, 19, 28, 50]:
        for dividend_digits in [100, 200]:
            for divisor_digits in [1, 5, 18, 19, 37]:
                var a = BDec(digits_string(0, dividend_digits, state))
                var b = BDec(digits_string(0, divisor_digits, state) + ".25")
                assert_quotient_is_correctly_rounded(
                    a, b, precision, "huge over small"
                )


def test_both_operands_huge() raises:
    var state = UInt64(4242)
    for precision in [1, 19, 28, 100]:
        for dividend_digits in [145, 300]:
            for divisor_digits in [145, 300, 600]:
                var a = BDec(digits_string(0, dividend_digits, state))
                var b = BDec(digits_string(0, divisor_digits, state))
                assert_quotient_is_correctly_rounded(
                    a, b, precision, "huge over huge"
                )


def test_across_the_word_boundary() raises:
    """Digit counts either side of a word, where the padding is decided."""
    var state = UInt64(13579)
    for precision in [17, 18, 19, 37]:
        for dividend_digits in range(1, 40):
            var a = BDec(digits_string(0, dividend_digits, state))
            var b = BDec(digits_string(0, 40 - dividend_digits, state))
            assert_quotient_is_correctly_rounded(
                a, b, precision, "word boundary"
            )


def test_the_regression_cases_from_the_truncated_dividend() raises:
    """Three cases that came back wrong, with CPython's answers written out.

    The first is the worst of them: nineteen digits asked for, one correct.
    """
    var a = BDec("368.3881690356602195")
    var b = BDec(
        "9635493331702278028986302504728799577754338059616032097353650399330"
        "3742923467566867007901660508541946376093399366319470953454097861943"
        "75325423323268476928916800635569917093063516875931688154.5735955588"
    )
    testing.assert_equal(
        String(a.true_divide(b, 19)), "3.823241388415532444E-188"
    )

    var c = BDec("97793770130607300.415")
    var d = BDec(
        "-96950112160124140830994528744199905846288234253721621549190955815"
        "0770756066333066742447833369727001615.601080484726695113151398656029"
        "4235269674403"
    )
    testing.assert_equal(
        String(c.true_divide(d, 18)), "-1.00870198034520850E-85"
    )

    var e = BDec("52728273102.36383042")
    var f = BDec(
        "0.0000872873839703793791723211670879947088823307078641263145807955"
        "142676091581775236199618362220351628860415191128053832962918684731"
        "7517531603304401075236334658480474"
    )
    testing.assert_equal(String(e.true_divide(f, 18)), "604076679858534.387")


def assert_inexact_quotient_is_truncated(
    x: BDec, y: BDec, digits: Int, context: String
) raises:
    """`true_divide_inexact` truncates, so `0 <= |x| - |q||y| < ulp(q)|y|`."""
    var q = x.true_divide_inexact(y, digits)
    var residual = subtract(abs(x), multiply(abs(q), abs(y)))
    var ulp = BDec(
        coefficient=BigUInt.from_word_unsafe(BigUInt.Word(1)),
        scale=q.scale,
        sign=False,
    )
    var bound = multiply(ulp, abs(y))

    assert_true(
        residual >= BDec("0"),
        context
        + ": quotient overshot. x = "
        + String(x)
        + ", y = "
        + String(y),
    )
    assert_true(
        residual < bound,
        context
        + ": quotient is short of the digits asked for. x = "
        + String(x)
        + ", y = "
        + String(y)
        + ", digits = "
        + String(digits)
        + ", q = "
        + String(q),
    )


def test_inexact_division_keeps_the_digits_it_promises() raises:
    """The same truncation defect lived in the inexact sibling.

    `true_divide_inexact` is public and it is what `root()` divides with, so a
    dividend cut down to one word costs significant digits with nothing to say
    so -- it does not claim correct rounding, only a digit count.
    """
    var state = UInt64(31337)
    for digits in [1, 5, 18, 19, 28, 50]:
        for dividend_digits in [1, 5, 18, 19, 37]:
            for divisor_digits in [100, 145, 200]:
                var a = BDec(digits_string(0, dividend_digits, state) + ".5")
                var b = BDec(digits_string(0, divisor_digits, state))
                assert_inexact_quotient_is_truncated(
                    a, b, digits, "small over huge"
                )
                assert_inexact_quotient_is_truncated(
                    b, a, digits, "huge over small"
                )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
