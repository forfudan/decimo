# ===----------------------------------------------------------------------=== #
# Test BigDecimal constants (pi)
# ===----------------------------------------------------------------------=== #
#
# Reference digits were produced independently of the implementation under
# test, with the Machin-like arctan series `pi = 16*atan(1/5) - 4*atan(1/239)`
# evaluated in exact integer arithmetic, then rounded half-even. Chudnovsky
# binary splitting and a Machin arctan share no code and no series, so a
# systematic error in one cannot hide in the other.

from std import testing

import decimo.bigdecimal.constants as decimo_constants
from decimo.rounding_mode import RoundingMode
from decimo.bigdecimal.bigdecimal import BigDecimal


def test_pi_small_precisions() raises:
    """Test pi() at precisions that fit comfortably in a single word."""
    testing.assert_equal(
        String(BigDecimal.pi(1)),
        "3",
    )
    testing.assert_equal(
        String(BigDecimal.pi(2)),
        "3.1",
    )
    testing.assert_equal(
        String(BigDecimal.pi(5)),
        "3.1416",
    )
    testing.assert_equal(
        String(BigDecimal.pi(10)),
        "3.141592654",
    )
    testing.assert_equal(
        String(BigDecimal.pi(16)),
        "3.141592653589793",
    )
    testing.assert_equal(
        String(BigDecimal.pi(20)),
        "3.1415926535897932385",
    )
    testing.assert_equal(
        String(BigDecimal.pi(50)),
        "3.1415926535897932384626433832795028841971693993751",
    )
    testing.assert_equal(
        String(BigDecimal.pi(100)),
        "3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117068",
    )
    testing.assert_equal(
        String(BigDecimal.pi(200)),
        "3.1415926535897932384626433832795028841971693993751058209749445923078164062862089986280348253421170679821480865132823066470938446095505822317253594081284811174502841027019385211055596446229489549303820",
    )


def test_pi_500_digits() raises:
    """Test pi() at 500 significant digits."""
    var expected = String(
        "3.1415926535897932384626433832795028841971693993751058209749"
        "445923078164062862089986280348253421170679821480865132823066"
        "470938446095505822317253594081284811174502841027019385211055"
        "596446229489549303819644288109756659334461284756482337867831"
        "652712019091456485669234603486104543266482133936072602491412"
        "737245870066063155881748815209209628292540917153643678925903"
        "600113305305488204665213841469519415116094330572703657595919"
        "530921861173819326117931051185480744623799627495673518857527"
        "248912279381830119491"
    )
    testing.assert_equal(String(BigDecimal.pi(500)), expected)


def test_pi_1000_digits() raises:
    """Test pi() at 1000 significant digits."""
    var expected = String(
        "3.1415926535897932384626433832795028841971693993751058209749"
        "445923078164062862089986280348253421170679821480865132823066"
        "470938446095505822317253594081284811174502841027019385211055"
        "596446229489549303819644288109756659334461284756482337867831"
        "652712019091456485669234603486104543266482133936072602491412"
        "737245870066063155881748815209209628292540917153643678925903"
        "600113305305488204665213841469519415116094330572703657595919"
        "530921861173819326117931051185480744623799627495673518857527"
        "248912279381830119491298336733624406566430860213949463952247"
        "371907021798609437027705392171762931767523846748184676694051"
        "320005681271452635608277857713427577896091736371787214684409"
        "012249534301465495853710507922796892589235420199561121290219"
        "608640344181598136297747713099605187072113499999983729780499"
        "510597317328160963185950244594553469083026425223082533446850"
        "352619311881710100031378387528865875332083814206171776691473"
        "035982534904287554687311595628638823537875937519577818577805"
        "32171226806613001927876611195909216420199"
    )
    testing.assert_equal(String(BigDecimal.pi(1000)), expected)


def test_pi_prefixes_are_consistent() raises:
    """Every precision must agree with a longer one on the digits they share.

    Guards against an off-by-one in the term count or in the guard digits: a
    series stopped one term early shows up as a prefix that diverges partway
    through, which last-digit spot checks would miss.

    The last few digits are excluded because rounding at the requested
    precision can carry backwards into them - `pi(13)` is 3.141592653590,
    whose 12th digit is a 9 where the untruncated expansion has an 8.
    """
    var reference = String(BigDecimal.pi(220)).replace(".", "")
    for precision in range(4, 200):
        var digits = String(BigDecimal.pi(precision)).replace(".", "")
        testing.assert_equal(
            digits[byte = 0 : precision - 3],
            reference[byte = 0 : precision - 3],
            "pi(" + String(precision) + ") disagrees with pi(220)",
        )


def test_pi_negative_precision_raises() raises:
    """Test that pi() rejects a negative precision."""
    var raised = False
    try:
        var _ = BigDecimal.pi(-1)
    except:
        raised = True
    testing.assert_true(raised, "pi(-1) should raise")


def test_the_two_pi_algorithms_agree_with_each_other() raises:
    """Chudnovsky against Machin, which is what Machin is kept for.

    `pi()` always takes Chudnovsky with binary splitting; `pi_machin()` has
    no caller in the library. It stays because it is an independent
    derivation -- a different series, a different convergence argument -- and
    two algorithms that agree to a thousand digits check each other in a way
    no table can. Chudnovsky is 250 to 2500 times faster over this range
    (0.05 ms against 133 ms at 1000 digits), which is why it is the path and
    Machin is the check. Machin is 7.5 s at 2000 digits, so this stops at
    1000.
    """
    for precision in [1, 2, 7, 28, 100, 500, 1000]:
        var chudnovsky = decimo_constants.pi_chudnovsky_binary_split(precision)
        var machin = decimo_constants.pi_machin(precision)
        testing.assert_true(
            chudnovsky == machin,
            "Chudnovsky and Machin disagree at "
            + String(precision)
            + " digits",
        )


def test_the_1024_digit_table_matches_the_algorithm() raises:
    """`PI_1024` is a literal; a wrong digit in it would be wrong forever.

    The table was checked once against an independent 1100-digit Machin
    computation in Python's `decimal` and matched to its full length. This
    pins the cheaper half of that: at every precision up to its own, rounding
    the table gives exactly what `pi()` computes, so the table is a valid
    cache should it ever be switched back on.
    """
    var table = materialize[decimo_constants.PI_1024]()
    for precision in [1, 5, 28, 100, 500, 1000, 1023, 1024]:
        var rounded = table.copy()
        rounded.round_to_precision_inplace(
            precision,
            RoundingMode.half_even(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )
        testing.assert_true(
            rounded == BigDecimal.pi(precision),
            "the table rounded to "
            + String(precision)
            + " digits differs from pi()",
        )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
