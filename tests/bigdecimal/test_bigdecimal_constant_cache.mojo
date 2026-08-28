"""
Checks that `MathCache` delivers the precision it promises.

Each getter says it returns its constant "to at least the specified
precision". The underlying `compute_ln2()` and `compute_ln1d25()` say the
opposite in their own docstrings -- that their last few digits are not
accurate, because neither carries a buffer. `get_ln10()` bridged the two by
computing at `precision + 9`; the other two passed the requested precision
straight through, and returned a value short by one in the last digit:

    get_ln1d25(5)  ->  0.22313     where ln(1.25) truncates to 0.22314

For `ln(2)` it only showed above 90 digits, because `compute_ln2()` answered
from a 90-digit table below that. At 91 to 130 digits about half the
precisions came back short. Both tables now hold 1100 digits, so the series
only runs above that; the last test here goes past the table on purpose.

Two things are checked here, and the second is what found it: the value has to
agree with a reference computed far wider, and a cold cache has to give the
same answer as a warm one asked for the same precision. A cache that returns
something different on the second call is wrong whichever call is right.
"""

from std import testing
from std.testing import assert_true, assert_equal

from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigdecimal.exponential import MathCache, ln, log10
from decimo.rounding_mode import RoundingMode

comptime REFERENCE_PRECISION = 200
"""Well past anything asked for below."""


def truncated(value: BDec, precision: Int) raises -> BDec:
    """The getters truncate rather than round, so the reference must too."""
    var out = value.copy()
    out.round_to_precision_inplace(
        precision=precision,
        rounding_mode=RoundingMode.down(),
        remove_extra_digit_due_to_rounding=False,
        fill_zeros_to_precision=False,
    )
    return out^


def test_a_cold_cache_delivers_the_precision_it_promises() raises:
    var reference = MathCache()
    var ln2 = reference.get_ln2(REFERENCE_PRECISION)
    var ln1d25 = reference.get_ln1d25(REFERENCE_PRECISION)
    var ln10 = reference.get_ln10(REFERENCE_PRECISION)

    # Below the 90-digit table in `compute_ln2()` and above it.
    for precision in [1, 2, 3, 5, 7, 9, 11, 28, 50, 89, 90, 91, 100, 130]:
        var cache = MathCache()
        assert_true(
            cache.get_ln2(precision) == truncated(ln2, precision),
            "ln(2) is short at precision " + String(precision),
        )
        var second = MathCache()
        assert_true(
            second.get_ln1d25(precision) == truncated(ln1d25, precision),
            "ln(1.25) is short at precision " + String(precision),
        )
        var third = MathCache()
        assert_true(
            third.get_ln10(precision) == truncated(ln10, precision),
            "ln(10) is short at precision " + String(precision),
        )


def test_a_warm_cache_agrees_with_a_cold_one() raises:
    """Asking for more, then less, must not change the answer.

    This is the check that found the defect: the warm path truncates a wider
    cached value and was right, while the cold path returned what the series
    gave it and was one out.
    """
    var warm = MathCache()
    _ = warm.get_ln2(130)
    _ = warm.get_ln1d25(130)
    _ = warm.get_ln10(130)

    for precision in [3, 5, 7, 9, 28, 50, 91, 129, 130]:
        var cold_two = MathCache()
        assert_true(
            warm.get_ln2(precision) == cold_two.get_ln2(precision),
            "ln(2) differs warm and cold at " + String(precision),
        )
        var cold_quarter = MathCache()
        assert_true(
            warm.get_ln1d25(precision) == cold_quarter.get_ln1d25(precision),
            "ln(1.25) differs warm and cold at " + String(precision),
        )
        var cold_ten = MathCache()
        assert_true(
            warm.get_ln10(precision) == cold_ten.get_ln10(precision),
            "ln(10) differs warm and cold at " + String(precision),
        )


def test_the_cache_upgrades_rather_than_reusing_a_short_value() raises:
    """A request for more digits than are cached must recompute."""
    var reference = MathCache()
    var ln2 = reference.get_ln2(REFERENCE_PRECISION)

    var cache = MathCache()
    _ = cache.get_ln2(10)
    assert_true(
        cache.get_ln2(120) == truncated(ln2, 120),
        "the cache reused a ten-digit value for a request of 120",
    )


def test_the_shared_cache_agrees_with_a_fresh_one() raises:
    """The two-argument `ln()` and `log10()` use one process-wide cache.

    Past the 1100-digit tables the cache holds computed values, and a later
    call at a lower precision truncates what is stored rather than computing
    afresh. Both must agree with a cache nobody has touched, in either order:
    high then low, and low after the cache has been grown.
    """
    var x = BDec("3.7")
    for precision in [1200, 300, 1150]:
        var fresh = MathCache()
        assert_equal(
            String(ln(x, precision)),
            String(ln(x, precision, fresh)),
            "ln at " + String(precision) + " through the shared cache",
        )
        # A second call answers from the cache.
        assert_equal(
            String(ln(x, precision)),
            String(ln(x, precision, fresh)),
            "ln at " + String(precision) + " on a warm shared cache",
        )

    # log10 is the ln(10) user; it reads the same cache after ln() grew it.
    var fresh = MathCache()
    var expected = ln(x, 1200, fresh).true_divide(fresh.get_ln10(1200), 1150)
    assert_equal(String(log10(x, 1150)), String(expected), "log10 shared")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
