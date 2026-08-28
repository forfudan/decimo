"""
Checks `root()` across magnitudes, including radicands too large for `Float64`.

Newton needs a seed, and `root()` built one by forming the whole radicand as a
`Float64` before taking its root. Above 308 digits that is infinity, and the
five or so iterations the schedule allows cannot walk back from there. The
cube root of `10^330` came back as `3.1E+123` where the answer is `1E+110`,
and a three-thousand-digit radicand had no correct digits at all.

The oracle is the inverse operation: `root(x, n) ** n` has to reproduce `x` to
the precision that was asked for. Raising back is computed at a wider
precision than the root, so what it measures is the root rather than itself.

The magnitudes bracket the `Float64` range on purpose -- 306 and 309 digits
sit either side of where the old seed overflowed.
"""

from std import testing
from std.testing import assert_true

from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigdecimal.arithmetics import multiply, subtract


def correct_digits(x: BDec, back: BDec) raises -> Int:
    """How many leading digits of `x` the round trip reproduces."""
    var residual = abs(subtract(x, back))
    if residual.coefficient.is_zero():
        return 999
    var digits = 0
    var scaled = residual.copy()
    var target = abs(x)
    while digits < 400:
        if scaled >= target:
            break
        scaled = multiply(scaled, BDec("10"))
        digits += 1
    return digits


def radicand(ndigits: Int) raises -> BDec:
    """A deterministic value with `ndigits` digits, never a round power."""
    var text = String("7")
    for i in range(ndigits - 1):
        text += String((i * 7 + 3) % 10)
    return BDec(text)


def assert_root_reaches_its_precision(x: BDec, n: Int, precision: Int) raises:
    var r = x.root(n, precision)
    var back = r.power(n, precision + 40)
    var got = correct_digits(x, back)
    assert_true(
        got >= precision - 2,
        "root("
        + String(x.coefficient.number_of_digits())
        + " digits, "
        + String(n)
        + ") at precision "
        + String(precision)
        + " reproduced only "
        + String(got)
        + " digits",
    )


def test_root_across_the_float64_range() raises:
    for ndigits in [1, 20, 306, 309, 400]:
        var x = radicand(ndigits)
        for n in [2, 3, 5, 11]:
            for precision in [10, 20, 50]:
                assert_root_reaches_its_precision(x, n, precision)


def test_root_far_beyond_the_float64_range() raises:
    """Three thousand digits, where the old seed was infinite."""
    var x = radicand(3001)
    for n in [2, 3, 5, 97]:
        assert_root_reaches_its_precision(x, n, 20)


def test_exact_roots_of_powers_of_ten() raises:
    """`10^(3k)` has an exact cube root, which makes an error unmissable."""
    for k in range(0, 400, 30):
        var text = String("1")
        for _ in range(k):
            text += "0"
        var x = BDec(text)
        var expected = String("1")
        for _ in range(k // 3):
            expected += "0"
        assert_true(
            x.root(3, 30) == BDec(expected),
            "cube root of 10^"
            + String(k)
            + " gave "
            + String(x.root(3, 30))
            + ", want 10^"
            + String(k // 3),
        )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
