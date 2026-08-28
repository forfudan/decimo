"""
Ties in `BigDecimal` division when the operands are truncated.

When the divisor has more words than the requested precision needs, the
division runs on truncated copies of both operands. The truncated quotient is
right to `precision + 36` digits, which is enough to round -- except at a tie.
The true quotient can be as close to `...5000...` as the input likes, so the
truncated path has to notice the tie zone and redo the division on the full
operands. Before it did, `(1.5 * y - 1e-100) / y` and `(2.5 * y + 1e-100) / y`
both rounded to 2 at one digit; the answers are 1 and 3.

The operands are built with `add()` and `subtract()`, not `+` and `-`: the
operators round to 28 digits and would hide the tiny offset that puts the
quotient on one side of the tie. The 401-digit divisor keeps these on the
truncated path whatever the guard becomes.
"""

from std import testing
from std.testing import assert_equal

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigdecimal.arithmetics import true_divide


def _one_followed_by_zeros(n: Int) -> String:
    var text = String("1")
    for _ in range(n):
        text += "0"
    return text^


def _divisor(ndigits: Int) raises -> BigDecimal:
    """`10^(ndigits - 1) + 7`, an odd divisor that never divides exactly."""
    return BigDecimal(_one_followed_by_zeros(ndigits - 1)).add(BigDecimal("7"))


def test_quotient_just_below_and_above_a_tie() raises:
    """One digit: 1.4999...9 rounds to 1 and 2.5000...01 rounds to 3."""
    var eps = BigDecimal("1E-100")
    for ndigits in [41, 201, 401]:
        var y = _divisor(ndigits)

        var below = y.multiply(BigDecimal("1.5")).subtract(eps)
        assert_equal(
            String(true_divide(below, y, 1)),
            "1",
            "1.5 - tiny at " + String(ndigits) + " digits",
        )

        var above = y.multiply(BigDecimal("2.5")).add(eps)
        assert_equal(
            String(true_divide(above, y, 1)),
            "3",
            "2.5 + tiny at " + String(ndigits) + " digits",
        )


def test_tie_at_default_precision() raises:
    """The same at 28 digits, with the kept digit even and odd."""
    var eps = BigDecimal("1E-100")
    for ndigits in [41, 201, 401]:
        var y = _divisor(ndigits)

        var even = y.multiply(
            BigDecimal("1.0000000000000000000000000005")
        ).subtract(eps)
        assert_equal(
            String(true_divide(even, y, 28)),
            "1.000000000000000000000000000",
            "below tie, even kept digit, " + String(ndigits) + " digits",
        )

        var odd = y.multiply(
            BigDecimal("1.0000000000000000000000000015")
        ).subtract(eps)
        assert_equal(
            String(true_divide(odd, y, 28)),
            "1.000000000000000000000000001",
            "below tie, odd kept digit, " + String(ndigits) + " digits",
        )


def test_exact_tie_rounds_to_even() raises:
    """`2.5 * y / y` is exactly 2.5 and rounds to 2; `3.5 * y / y` to 4."""
    for ndigits in [41, 201, 401]:
        var y = _divisor(ndigits)
        assert_equal(
            String(true_divide(y.multiply(BigDecimal("2.5")), y, 1)), "2"
        )
        assert_equal(
            String(true_divide(y.multiply(BigDecimal("3.5")), y, 1)), "4"
        )


def test_exact_quotient_stays_exact() raises:
    """`2 * y / y` on the truncated path is `2`, not `2.000...`."""
    var y = _divisor(401)
    assert_equal(String(true_divide(y.multiply(BigDecimal("2")), y, 28)), "2")
    assert_equal(
        String(true_divide(y.multiply(BigDecimal("1.25")), y, 28)), "1.25"
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
