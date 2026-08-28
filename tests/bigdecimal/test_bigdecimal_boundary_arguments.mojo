"""
Arguments whose result lands on a rounding boundary.

These were built backwards: pick a value whose 29th significant digit is a 5,
apply the inverse function to it at sixty digits, and the result is an
argument whose true answer continues `...5000000000000000000000000021929`.
Nine guard digits see only the zeros, read the tail as an exact tie, and round
to even -- which is the wrong way when the digits past the ninth are not zero.

`arctan` and `log10` were both one unit low or high here before their rounding
was decided rather than assumed. The values are from CPython's `decimal` at
eighty digits.
"""

from std import testing
from std.testing import assert_equal

from decimo.bigdecimal.bigdecimal import BDec
from decimo.rounding_mode import RoundingMode


def test_arctan_on_a_constructed_boundary() raises:
    # The true value continues ...678 5000000000000000000000000000000219
    var x = BDec(
        "0.719140535117048373117282825889546395318364929183100430962012"
    )
    assert_equal(String(x.arctan(28)), "0.6234567890123456789012345679")
    assert_equal(
        String(x.arctan(28, RoundingMode.ROUND_DOWN)),
        "0.6234567890123456789012345678",
    )
    assert_equal(
        String(x.arctan(28, RoundingMode.ROUND_UP)),
        "0.6234567890123456789012345679",
    )


def test_log10_on_a_constructed_boundary() raises:
    # The true value continues ...678 4999999999999999999999999999999
    var x = BDec(
        "2.65128728481795205648160305012060516526399375372733407716933"
    )
    assert_equal(String(x.log10(28)), "0.4234567890123456789012345678")
    assert_equal(
        String(x.log10(28, RoundingMode.ROUND_UP)),
        "0.4234567890123456789012345679",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
