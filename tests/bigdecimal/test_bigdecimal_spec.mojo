"""
The specification's operations that are neither arithmetic nor comparison.

Digit-wise logic, `shift`, `rotate`, the neighbours, `remainder_near`, the
total order and `logb`. The expected values are what the decimal arithmetic
specification gives, which is also what CPython's `decimal` returns for the
same operands and precision.
"""

from std import testing
from std.testing import assert_equal, assert_true, assert_raises

from decimo.bigdecimal.bigdecimal import BDec
import decimo.bigdecimal.comparison as comparison
import decimo.bigdecimal.spec as spec


def test_digit_wise_logic() raises:
    assert_equal(
        String(spec.logical_and(BDec("1100"), BDec("1010"), 9)), "1000"
    )
    assert_equal(String(spec.logical_or(BDec("1100"), BDec("1010"), 9)), "1110")
    assert_equal(String(spec.logical_xor(BDec("1100"), BDec("1010"), 9)), "110")
    assert_equal(String(spec.logical_invert(BDec("0"), 3)), "111")
    assert_equal(String(spec.logical_invert(BDec("101"), 3)), "10")

    # The operands are taken in the current precision: the digits above it
    # are cut off, not kept.
    assert_equal(String(spec.logical_and(BDec("1100"), BDec("1010"), 3)), "0")
    assert_equal(String(spec.logical_or(BDec("1100"), BDec("1010"), 3)), "110")


def test_only_zeros_and_ones_are_logical() raises:
    for text in ["2", "-1", "1.0", "10.1"]:
        with assert_raises():
            _ = spec.logical_invert(BDec(text), 9)


def test_shift_and_rotate() raises:
    assert_equal(String(spec.shift(BDec("2.5"), 1, 3)), "25.0")
    assert_equal(String(spec.shift(BDec("1.23456789"), 1, 3)), "0.00000890")
    assert_equal(String(spec.shift(BDec("123"), -1, 3)), "12")
    assert_equal(String(spec.rotate(BDec("123"), 1, 3)), "231")
    assert_equal(String(spec.rotate(BDec("123"), -1, 3)), "312")
    # A rotation by the whole precision comes back to where it started.
    assert_equal(String(spec.rotate(BDec("123"), 3, 3)), "123")
    # The sign and the exponent are untouched.
    assert_equal(String(spec.shift(BDec("-1.23"), 1, 3)), "-2.30")

    for amount in [4, -4]:
        with assert_raises():
            _ = spec.shift(BDec("123"), amount, 3)
        with assert_raises():
            _ = spec.rotate(BDec("123"), amount, 3)


def test_neighbours() raises:
    assert_equal(String(spec.next_plus(BDec("2.5"), 3)), "2.51")
    assert_equal(String(spec.next_minus(BDec("2.5"), 3)), "2.49")
    assert_equal(String(spec.next_plus(BDec("9.99999"), 3)), "10.0")
    assert_equal(String(spec.next_minus(BDec("9.99999"), 3)), "9.99")

    # Stepping towards zero from a power of ten lands in the decade below,
    # where the last place is ten times smaller.
    assert_equal(String(spec.next_minus(BDec("1"), 3)), "0.999")
    assert_equal(String(spec.next_plus(BDec("-1"), 3)), "-0.999")
    assert_equal(String(spec.next_minus(BDec("100"), 3)), "99.9")
    assert_equal(String(spec.next_plus(BDec("1"), 3)), "1.01")

    assert_equal(String(spec.next_toward(BDec("1"), BDec("0"), 3)), "0.999")
    assert_equal(String(spec.next_toward(BDec("1"), BDec("5"), 3)), "1.01")
    assert_equal(String(spec.next_toward(BDec("1"), BDec("-1.0"), 3)), "0.999")
    # Equal operands only take the sign of the second.
    assert_equal(String(spec.next_toward(BDec("1"), BDec("1.0"), 3)), "1")
    assert_equal(
        String(spec.next_toward(BDec("1"), BDec("-1.0E0"), 3)), "0.999"
    )


def test_zero_has_no_neighbour() raises:
    # Exponents are unbounded here, so no positive value is the smallest.
    with assert_raises():
        _ = spec.next_plus(BDec("0"), 9)
    with assert_raises():
        _ = spec.next_minus(BDec("0.00"), 9)


def test_remainder_near() raises:
    assert_equal(String(spec.remainder_near(BDec("1.6"), BDec("3"))), "-1.4")
    assert_equal(String(spec.remainder_near(BDec("2.5"), BDec("3"))), "-0.5")
    assert_equal(String(spec.remainder_near(BDec("11"), BDec("3"))), "-1")
    assert_equal(String(spec.remainder_near(BDec("10"), BDec("3"))), "1")
    # A tie goes to the even multiple: 4.5 = 3 * 1.5, and 2 is the even one.
    assert_equal(String(spec.remainder_near(BDec("4.5"), BDec("3"))), "-1.5")
    assert_equal(String(spec.remainder_near(BDec("1.5"), BDec("3"))), "1.5")
    # An exact division keeps the sign of the dividend.
    assert_equal(String(spec.remainder_near(BDec("-6"), BDec("3"))), "-0")

    with assert_raises():
        _ = spec.remainder_near(BDec("1"), BDec("0"))


def test_the_total_order_separates_equal_values() raises:
    assert_equal(Int(comparison.compare_total(BDec("12.0"), BDec("12"))), -1)
    assert_equal(Int(comparison.compare_total(BDec("12"), BDec("12.0"))), 1)
    assert_equal(Int(comparison.compare_total(BDec("12"), BDec("12"))), 0)
    # The order flips below zero.
    assert_equal(Int(comparison.compare_total(BDec("-12.0"), BDec("-12"))), 1)
    assert_equal(Int(comparison.compare_total(BDec("-0"), BDec("0"))), -1)
    # A numeric comparison still decides when the values differ.
    assert_equal(Int(comparison.compare_total(BDec("1"), BDec("2"))), -1)
    assert_equal(
        Int(comparison.compare_total_absolute(BDec("-5"), BDec("2"))), 1
    )


def test_extrema_break_a_tie_by_the_total_order() raises:
    assert_equal(String(comparison.max(BDec("12.0"), BDec("12"))), "12")
    assert_equal(String(comparison.min(BDec("12.0"), BDec("12"))), "12.0")
    assert_equal(String(comparison.max(BDec("-12.0"), BDec("-12"))), "-12.0")
    assert_equal(String(comparison.min(BDec("-12.0"), BDec("-12"))), "-12")
    assert_equal(String(spec.max_absolute(BDec("-5"), BDec("2"))), "-5")
    assert_equal(String(spec.min_absolute(BDec("-5"), BDec("2"))), "2")
    assert_equal(String(spec.max_absolute(BDec("-0"), BDec("0"))), "0")


def test_logb_and_number_class() raises:
    assert_equal(String(spec.logb(BDec("123"))), "2")
    assert_equal(String(spec.logb(BDec("0.00123"))), "-3")
    assert_equal(String(spec.logb(BDec("-1"))), "0")
    with assert_raises():
        _ = spec.logb(BDec("0.000"))

    assert_equal(spec.number_class(BDec("0")), "+Zero")
    assert_equal(spec.number_class(BDec("-0")), "-Zero")
    assert_equal(spec.number_class(BDec("1E-9999")), "+Normal")
    assert_equal(spec.number_class(BDec("-2.5")), "-Normal")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
