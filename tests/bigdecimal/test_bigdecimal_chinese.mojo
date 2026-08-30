"""
Tests for `BigDecimal.to_chinese()`.

The formatting rules themselves are covered in
`tests/numerals/test_chinese.mojo`; these tests check that BigDecimal feeds
its digits to the shared engine correctly.
"""

from std import testing

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.numerals.chinese import ChineseNumeralStyle


def test_to_chinese() raises:
    """The BigDecimal wrapper matches the string-level engine."""
    testing.assert_equal(BigDecimal("1050.07").to_chinese(), "一千零五十点零七")
    testing.assert_equal(BigDecimal("-100000001").to_chinese(), "负一亿零一")
    testing.assert_equal(BigDecimal("0").to_chinese(), "零")
    testing.assert_equal(BigDecimal("1.50").to_chinese(), "一点五零")


def test_to_chinese_with_style() raises:
    """The style argument is forwarded."""
    testing.assert_equal(
        BigDecimal("1050.07").to_chinese(
            ChineseNumeralStyle.simplified_financial()
        ),
        "壹仟零伍拾点零柒",
    )


def test_to_chinese_uses_plain_notation() raises:
    """Values that print in scientific notation are expanded first."""
    testing.assert_equal(BigDecimal("1E+10").to_chinese(), "一百亿")
    testing.assert_equal(BigDecimal("1.2E+5").to_chinese(), "十二万")
    testing.assert_equal(BigDecimal("1E-8").to_chinese(), "零点零零零零零零零一")


def test_to_chinese_digit_budget() raises:
    """A huge exponent is rejected before the plain expansion is built."""
    # `to_string(force_plain=True)` on this would be a gigabyte of digits, so
    # BigDecimal has to check the budget itself rather than leave it to the
    # engine -- if it did not, this test would exhaust memory rather than raise.
    with testing.assert_raises():
        _ = BigDecimal("1E+1000000000").to_chinese()
    with testing.assert_raises():
        _ = BigDecimal("1E-1000000000").to_chinese()
    with testing.assert_raises():
        _ = BigDecimal("1E+10").to_chinese(max_digits=10)
    testing.assert_equal(BigDecimal("1E+10").to_chinese(max_digits=11), "一百亿")
    testing.assert_equal(BigDecimal("1E+10").to_chinese(max_digits=0), "一百亿")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
