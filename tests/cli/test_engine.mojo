"""Test the engine helpers: pad_to_precision, display_calc_error."""

from std import testing

from calculator.engine import pad_to_precision


# ===----------------------------------------------------------------------=== #
# Tests: pad_to_precision
# ===----------------------------------------------------------------------=== #


def test_pad_integer() raises:
    """Integer without decimal point gets one added."""
    testing.assert_equal(pad_to_precision("42", 5), "42.00000")


def test_pad_short_fraction() raises:
    """Fractional part shorter than precision is zero-padded."""
    testing.assert_equal(pad_to_precision("3.14", 10), "3.1400000000")


def test_pad_exact_fraction() raises:
    """Fractional part already at precision is unchanged."""
    testing.assert_equal(pad_to_precision("1.234", 3), "1.234")


def test_pad_long_fraction() raises:
    """Fractional part longer than precision is unchanged (no truncation)."""
    testing.assert_equal(pad_to_precision("1.23456789", 3), "1.23456789")


def test_pad_zero_precision() raises:
    """Precision 0 returns the input unchanged."""
    testing.assert_equal(pad_to_precision("42", 0), "42")


def test_pad_negative_precision() raises:
    """Negative precision returns the input unchanged."""
    testing.assert_equal(pad_to_precision("42", -1), "42")


def test_pad_zero_value() raises:
    """Zero value gets padded normally."""
    testing.assert_equal(pad_to_precision("0", 3), "0.000")


def test_pad_already_has_dot_no_digits() raises:
    """Value with dot but no fractional digits gets padded."""
    testing.assert_equal(pad_to_precision("5.", 4), "5.0000")


def test_pad_precision_one() raises:
    """Precision 1 on integer adds '.0'."""
    testing.assert_equal(pad_to_precision("7", 1), "7.0")


# ===----------------------------------------------------------------------=== #
# Main
# ===----------------------------------------------------------------------=== #


def main() raises:
    test_pad_integer()
    test_pad_short_fraction()
    test_pad_exact_fraction()
    test_pad_long_fraction()
    test_pad_zero_precision()
    test_pad_negative_precision()
    test_pad_zero_value()
    test_pad_already_has_dot_no_digits()
    test_pad_precision_one()
    print("test_engine: all tests passed")
