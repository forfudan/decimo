"""
Tests for `BigInt.to_chinese()`.

The formatting rules themselves are covered in
`tests/numerals/test_chinese.mojo`; these tests check that BigInt feeds its
digits to the shared engine correctly.
"""

from std import testing
from decimo.bigint.bigint import BigInt
from decimo.numerals.chinese import (
    MAX_CHINESE_NUMERAL_DIGITS,
    ChineseNumeralStyle,
)


def test_to_chinese_small_values() raises:
    """Values within a single group of four digits."""
    testing.assert_equal(BigInt(0).to_chinese(), "零")
    testing.assert_equal(BigInt(15).to_chinese(), "十五")
    testing.assert_equal(BigInt(105).to_chinese(), "一百零五")
    testing.assert_equal(BigInt(1050).to_chinese(), "一千零五十")


def test_to_chinese_magnitudes() raises:
    """Values spanning several 万/亿 groups."""
    testing.assert_equal(BigInt(10000).to_chinese(), "一万")
    testing.assert_equal(BigInt(123456789).to_chinese(), "一亿二千三百四十五万六千七百八十九")
    testing.assert_equal(BigInt("100000001").to_chinese(), "一亿零一")


def test_to_chinese_negative() raises:
    """Negative values are prefixed with 负."""
    testing.assert_equal(BigInt(-15).to_chinese(), "负十五")
    testing.assert_equal(BigInt("-100000001").to_chinese(), "负一亿零一")


def test_to_chinese_very_large() raises:
    """Arbitrary-precision values are not limited by any integer width."""
    testing.assert_equal(BigInt("10000000000000000").to_chinese(), "一亿亿")
    testing.assert_equal(
        BigInt("1234567890123").to_chinese(),
        "一万二千三百四十五亿六千七百八十九万零一百二十三",
    )


def test_to_chinese_with_style() raises:
    """The style argument is forwarded."""
    testing.assert_equal(
        BigInt(1050).to_chinese(ChineseNumeralStyle.simplified_financial()),
        "壹仟零伍拾",
    )
    testing.assert_equal(
        BigInt(10000).to_chinese(ChineseNumeralStyle.traditional()), "一萬"
    )


def test_to_chinese_digit_budget() raises:
    """Values with more digits than the budget raise instead of converting."""
    # The budget is the digit count of the value itself, so it can be probed
    # on a small number rather than on a 10001-digit one (which is slow to
    # build, not slow to convert).
    with testing.assert_raises():
        _ = BigInt(12345).to_chinese(max_digits=4)
    testing.assert_equal(BigInt(12345).to_chinese(max_digits=5), "一万二千三百四十五")
    testing.assert_equal(BigInt(12345).to_chinese(max_digits=0), "一万二千三百四十五")


def test_to_chinese_default_budget() raises:
    """The default cap turns away values past `MAX_CHINESE_NUMERAL_DIGITS`."""
    var huge = BigInt("1" + String("0") * MAX_CHINESE_NUMERAL_DIGITS)
    with testing.assert_raises():
        _ = huge.to_chinese()
    testing.assert_true(huge.to_chinese(max_digits=0).byte_length() > 0)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
