"""
`sqrt()` at the edges of the seed's range.

The reciprocal-sqrt iteration normalises its input into `[1, 100)` and seeds
from a `Float64`, so a correct seed lies in `(0.1, 1]`. The seed is checked
against its residual and rebuilt when it fails, so what the schedule is told
about it stays true. These inputs put the seed exactly on the edges of that
range --
`1.0` for `1`, `100`, `1E-400`, and just above `0.1` for `99.99...` -- where
a float rounding could push it over the line, and check the result against
`sqrt_exact()`, which reproduces CPython.
"""

from std import testing
from std.testing import assert_equal

from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigdecimal.exponential import sqrt, sqrt_exact


def test_sqrt_at_the_seed_edges() raises:
    var inputs: List[String] = [
        "1",
        "100",
        "0.01",
        "1E-400",
        "1E+400",
        "99.999999999999999999999999999999",
        "9999.9999999999999999999999",
        "0.0099999999999999999999999",
        "1.0000000000000000000000001",
    ]
    for text in inputs:
        var x = BDec(text)
        for precision in [28, 200, 1500]:
            assert_equal(
                String(sqrt(x, precision)),
                String(sqrt_exact(x, precision)),
                "sqrt(" + text + ", " + String(precision) + ")",
            )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
