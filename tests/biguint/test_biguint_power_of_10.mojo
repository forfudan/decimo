"""
Tests `BigUInt.power_of_10()`.

It had no test, and it was wrong: a `zero()` already carries one word, and
the whole-word loop appended one more than it needed, so every power from
`10^18` up came back a whole word -- a factor of `10^18` -- too large.
Nothing in the library exercised it above seventeen until a decimal
conversion did.

The check is the digit count, which is the one thing a power of ten is: the
`n`-th has `n` zeros after its one.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.biguint.biguint import BigUInt


def test_the_digit_count_is_the_exponent() raises:
    """`10^n` is a one and `n` zeros, across every word boundary."""
    for n in [
        0,
        1,
        2,
        5,
        17,
        18,
        19,
        20,
        35,
        36,
        37,
        53,
        54,
        55,
        71,
        72,
        100,
        180,
        181,
    ]:
        var power = String(BigUInt.power_of_10(n))
        assert_equal(
            power.byte_length(),
            n + 1,
            "the width of 10^" + String(n),
        )
        assert_true(
            power.startswith("1"), "10^" + String(n) + " does not start at one"
        )


def test_against_repeated_multiplication() raises:
    """The same values built the slow way, which cannot be off by a word."""
    var running = BigUInt.one()
    for n in range(0, 60):
        assert_equal(
            String(BigUInt.power_of_10(n)),
            String(running),
            "10^" + String(n) + " against a running product",
        )
        running = running * BigUInt(10)


def test_the_word_boundaries_exactly() raises:
    """The powers either side of a word, written out.

    Eighteen digits is one word in base 10^18, which is where the off-by-one
    word lived.
    """
    assert_equal(String(BigUInt.power_of_10(17)), "1" + "0" * 17)
    assert_equal(String(BigUInt.power_of_10(18)), "1" + "0" * 18)
    assert_equal(String(BigUInt.power_of_10(19)), "1" + "0" * 19)
    assert_equal(String(BigUInt.power_of_10(36)), "1" + "0" * 36)


def test_a_negative_exponent_raises() raises:
    var raised = False
    try:
        _ = BigUInt.power_of_10(-1)
    except:
        raised = True
    assert_true(raised, "a negative exponent was accepted")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
