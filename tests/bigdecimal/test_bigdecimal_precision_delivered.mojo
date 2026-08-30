"""
Checks that the transcendental functions deliver the precision they are asked
for, across magnitudes.

Every one of these seeds a Newton or a series with a `Float64`, and a `Float64`
holds about sixteen digits over a range of about 10^308. Both of those limits
have bitten this library already, silently, because a short answer is still a
well-formed answer:

- the reciprocal-square-root seeds added their second word at an offset that
  described a nine-digit word, so the seed was worth eight digits where the
  doubling schedule credits it with sixteen, and `arctan` at fifty digits came
  back right to forty-three;
- `root()` built the whole radicand as a `Float64` before taking its root, so
  above 308 digits it seeded Newton with infinity and returned nothing correct
  at all.

Neither was visible to the test suite, because nothing measured how many
digits came back. This file measures it, from outside, where it costs nothing
at runtime -- an in-line residual check would want a way to run `BigDecimal`
work only under assertions, and Mojo offers `is_defined` but no way to read
what `-D ASSERT` was set to.

Worth knowing about the seeds while reading this: their accuracy is a
performance parameter, not a correctness one. The reciprocal-square-root seed
can be truncated to a single digit and `sqrt` still returns 400 correct
digits, because an exact integer Newton refinement follows it. What a seed has
to get right is landing in the convergence basin, and a seed outside it is
caught by `test_sqrt_via_reciprocal_iteration_matches_sqrt_exact` already. The
failures this file exists for are the other kind: a seed at the wrong
magnitude entirely, or a schedule that stops early.

The oracle is each function's inverse, computed at a wider precision than the
function under test so that what is measured is the function and not the
check.
"""

from std import testing
from std.testing import assert_true

from decimo.bigdecimal.arithmetics import multiply, subtract
from decimo.bigdecimal.bigdecimal import BDec

comptime SLACK = 3
"""Digits allowed to be lost to the round trip's own rounding."""


def correct_digits(x: BDec, back: BDec) raises -> Int:
    """Leading digits of `x` that `back` reproduces, or 999 when exact."""
    var residual = abs(subtract(x, back))
    if residual.coefficient.is_zero():
        return 999
    var target = abs(x)
    if target.coefficient.is_zero():
        return 0
    var digits = 0
    var scaled = residual.copy()
    while digits < 500:
        if scaled >= target:
            break
        scaled = multiply(scaled, BDec("10"))
        digits += 1
    return digits


def assert_round_trip(x: BDec, back: BDec, precision: Int, what: String) raises:
    var got = correct_digits(x, back)
    assert_true(
        got >= precision - SLACK,
        what
        + " at precision "
        + String(precision)
        + " delivered "
        + String(got)
        + " digits",
    )


def value_at(exponent: Int) raises -> BDec:
    """A 25-digit value placed at `exponent`, never a round power of ten."""
    var text = String("7")
    for i in range(24):
        text += String((i * 7 + 3) % 10)
    if exponent != 0:
        text += "E" + String(exponent)
    return BDec(text)


def test_sqrt_delivers_its_precision() raises:
    """Squaring is exact, so this measures `sqrt` alone."""
    for precision in [20, 50, 120]:
        for exponent in [-4000, -320, -310, 0, 310, 320, 4000]:
            var x = value_at(exponent)
            var r = x.sqrt(precision)
            assert_round_trip(x, multiply(r, r), precision, "sqrt")


def test_ln_and_exp_invert_each_other() raises:
    for precision in [20, 50]:
        for exponent in [-320, -310, 0, 310, 320]:
            var x = value_at(exponent)
            var logarithm = x.ln(precision)
            assert_round_trip(x, logarithm.exp(precision + 15), precision, "ln")

    for precision in [20, 50]:
        for magnitude in [-700, -1, 0, 1, 700]:
            var x = BDec(String(magnitude) + ".5")
            var e = x.exp(precision)
            assert_round_trip(x, e.ln(precision + 15), precision, "exp")


def test_log10_of_a_power_of_ten_is_exact() raises:
    """No round trip needed: the answer is an integer."""
    for k in [-4000, -400, -310, -20, 0, 20, 310, 400, 4000]:
        var text = String("1E") + String(k)
        assert_true(
            BDec(text).log10(30) == BDec(String(k)),
            "log10(10^" + String(k) + ") is not " + String(k),
        )


def test_power_delivers_its_precision() raises:
    """Exponents whose reciprocal is exact, so the round trip measures `power`.
    """
    var pairs = [("0.5", "2"), ("1.25", "0.8"), ("0.125", "8")]
    for precision in [30, 60]:
        for exponent in [-3000, 0]:
            var x = value_at(exponent)
            for pair in pairs:
                var y = x.power(BDec(pair[0]), precision)
                assert_round_trip(
                    x,
                    y.power(BDec(pair[1]), precision + 20),
                    precision,
                    "power by " + pair[0],
                )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
