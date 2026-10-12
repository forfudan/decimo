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
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.bigdecimal import BDec
import decimo.bigdecimal.cache as bigdecimal_cache
import decimo.bigdecimal.constants as decimo_constants
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


# ===----------------------------------------------------------------------=== #
# Pi and Euler's number, kept by `bigdecimal.cache`
# ===----------------------------------------------------------------------=== #
#
# These two are kept at the widest precision they have been asked for, and a
# narrower request is a rounding of what is kept. The rounding is decided
# against the kept value rather than assumed, so what has to be checked is
# that the answer never depends on what came before it: the same precision
# must give the same digits whether the cache is cold, warm at that width, or
# warm at a far wider one.


def test_pi_from_a_cold_cache_agrees_with_the_series() raises:
    """Above the table, pi answers from the cache; the series is the reference.

    Ascending precisions, so each request is wider than what is kept and
    recomputes. The series shares no state with the cache.
    """
    for precision in [1025, 1026, 1100, 1500, 2000]:
        assert_equal(
            String(decimo_constants.pi(precision)),
            String(decimo_constants.pi_chudnovsky_binary_split(precision)),
            "pi at " + String(precision) + " digits",
        )


def test_pi_from_a_wide_cache_agrees_with_the_series() raises:
    """A wide request first, then narrower ones answered from it.

    This is the direction that can go wrong. A value kept at 4,000 digits is
    cut down and the rounding decided against it, and every answer has to be
    the digits the series gives at that precision -- not the digits of the
    wide value with the tail chopped off, which differ whenever the first
    dropped digit is a five or more.
    """
    var wide = decimo_constants.pi(4000)
    assert_true(wide.coefficient.is_zero() == False, "pi is not zero")
    for precision in [3999, 2000, 1500, 1100, 1026, 1025]:
        assert_equal(
            String(decimo_constants.pi(precision)),
            String(decimo_constants.pi_chudnovsky_binary_split(precision)),
            "pi at " + String(precision) + " digits, from a wide cache",
        )


def test_pi_gives_the_same_digits_twice() raises:
    """A cold call and a warm one at the same precision must agree."""
    for precision in [1025, 1700, 2500]:
        var cold = String(decimo_constants.pi(precision))
        var warm = String(decimo_constants.pi(precision))
        assert_equal(
            cold, warm, "pi at " + String(precision) + " digits, twice"
        )


def test_e_agrees_with_the_exponential() raises:
    """`BDec.e()` is kept too, and must stay what `exp(1)` gives.

    Both sides of the floor the cache keeps nothing below, and both
    directions across it.
    """
    for precision in [1, 2, 63, 64, 65, 100, 1024, 1100, 2000, 300, 70]:
        assert_equal(
            String(BDec.e(precision)),
            String(BDec.one().exp(precision)),
            "e at " + String(precision) + " digits",
        )


def test_a_kept_value_that_straddles_a_boundary_does_not_settle() raises:
    """The deciding, on its own.

    A value whose own error reaches across a rounding boundary cannot say
    which way the digit before it goes, and the cache has to answer that it
    does not know rather than guess. Without this the harness would pass on a
    cache that simply truncated whatever it held.
    """
    var straddles = BDec("1.4999999999999999")
    var undecided = bigdecimal_cache._settled_from(
        straddles.copy(), 17, 1, 1, RoundingMode.half_even()
    )
    assert_true(
        not Bool(undecided),
        "a value one unit short of 1.5 cannot decide its first digit",
    )

    var clear = BDec("1.2345678901234567")
    var decided = bigdecimal_cache._settled_from(
        clear.copy(), 17, 1, 1, RoundingMode.half_even()
    )
    assert_true(Bool(decided), "a value nowhere near a boundary decides")
    assert_equal(String(decided.value()), "1", "1.2345... to one digit")


def test_a_kept_value_is_cut_before_it_is_tested() raises:
    """A value far wider than the request still gives the series' digits.

    The cut is where a cache earns its keep and where it can lose the
    rounding, so it is checked against the series at a precision many times
    narrower than what is held.
    """
    var wide = decimo_constants.pi_chudnovsky_binary_split(2000)
    for precision in [100, 500, 1200]:
        var settled = bigdecimal_cache._settled_from(
            wide.copy(), 2000, 1, precision, RoundingMode.half_even()
        )
        assert_true(
            Bool(settled),
            "2,000 digits of pi decide " + String(precision) + " of them",
        )
        assert_equal(
            String(settled.value()),
            String(decimo_constants.pi_chudnovsky_binary_split(precision)),
            "pi cut from 2,000 digits to " + String(precision),
        )


def test_the_cache_answers_a_narrower_request_and_refuses_a_wider_one() raises:
    """`keep()` and `held()`, on their own.

    What is stored is the series' own value, so this test leaves the shared
    cache holding nothing that is not true.
    """
    var wide = decimo_constants.pi_chudnovsky_binary_split(2200)
    bigdecimal_cache.keep(bigdecimal_cache.PI, 2200, wide)

    var narrower = bigdecimal_cache.held(bigdecimal_cache.PI, 1200)
    assert_true(
        Bool(narrower), "2,200 digits kept must answer a request for 1,200"
    )
    assert_true(
        narrower.value().digits >= 2200,
        "the width reported back is the width it was computed at",
    )

    var wider = bigdecimal_cache.held(bigdecimal_cache.PI, 10_000_000)
    assert_true(
        not Bool(wider), "the cache must not answer beyond what it holds"
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
