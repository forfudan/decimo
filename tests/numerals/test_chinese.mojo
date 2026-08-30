"""
Tests for `decimo.numerals.chinese`.

Covers `decimal_string_to_chinese()`, the string-level engine, and the
`ChineseNumeralStyle` presets.  The thin wrappers around it are tested in
`tests/bigdecimal/test_bigdecimal_chinese.mojo` and
`tests/bigint/test_bigint_chinese.mojo`.
"""

from std import testing

from decimo.numerals.chinese import (
    MAX_CHINESE_NUMERAL_DIGITS,
    ChineseNumeralStyle,
    decimal_string_to_chinese,
)


# ===----------------------------------------------------------------------=== #
# Single groups of four digits (十/百/千 units)
# ===----------------------------------------------------------------------=== #


def test_single_digits() raises:
    """Digits 0 to 9 read as single characters."""
    testing.assert_equal(decimal_string_to_chinese("0"), "零")
    testing.assert_equal(decimal_string_to_chinese("1"), "一")
    testing.assert_equal(decimal_string_to_chinese("5"), "五")
    testing.assert_equal(decimal_string_to_chinese("9"), "九")


def test_leading_ten_is_simplified() raises:
    """A leading 一十 is shortened to 十."""
    testing.assert_equal(decimal_string_to_chinese("10"), "十")
    testing.assert_equal(decimal_string_to_chinese("15"), "十五")
    testing.assert_equal(decimal_string_to_chinese("19"), "十九")


def test_non_leading_ten_keeps_its_digit() raises:
    """一十 is only simplified at the very beginning of the number."""
    testing.assert_equal(decimal_string_to_chinese("115"), "一百一十五")
    testing.assert_equal(decimal_string_to_chinese("210"), "二百一十")
    testing.assert_equal(decimal_string_to_chinese("100000"), "十万")
    testing.assert_equal(decimal_string_to_chinese("1000100000"), "十亿零一十万")


def test_hundreds_and_thousands() raises:
    """Groups of up to four digits use the 十/百/千 units."""
    testing.assert_equal(decimal_string_to_chinese("100"), "一百")
    testing.assert_equal(decimal_string_to_chinese("999"), "九百九十九")
    testing.assert_equal(decimal_string_to_chinese("1200"), "一千二百")
    testing.assert_equal(decimal_string_to_chinese("9999"), "九千九百九十九")


def test_internal_zeros_within_a_group() raises:
    """Internal zeros collapse into a single 零; trailing ones are dropped."""
    testing.assert_equal(decimal_string_to_chinese("105"), "一百零五")
    testing.assert_equal(decimal_string_to_chinese("1001"), "一千零一")
    testing.assert_equal(decimal_string_to_chinese("1050"), "一千零五十")
    testing.assert_equal(decimal_string_to_chinese("1005"), "一千零五")
    testing.assert_equal(decimal_string_to_chinese("2000"), "二千")


# ===----------------------------------------------------------------------=== #
# Magnitudes: 万 within a section, 亿 multiplying across sections
# ===----------------------------------------------------------------------=== #


def test_wan_and_yi() raises:
    """The 万 (10^4) and 亿 (10^8) markers."""
    testing.assert_equal(decimal_string_to_chinese("10000"), "一万")
    testing.assert_equal(decimal_string_to_chinese("20000"), "二万")
    testing.assert_equal(decimal_string_to_chinese("100000000"), "一亿")
    testing.assert_equal(
        decimal_string_to_chinese("123456789"),
        "一亿二千三百四十五万六千七百八十九",
    )


def test_zero_between_groups() raises:
    """A gap between magnitudes is bridged by exactly one 零."""
    testing.assert_equal(decimal_string_to_chinese("10001"), "一万零一")
    testing.assert_equal(decimal_string_to_chinese("100000001"), "一亿零一")
    testing.assert_equal(decimal_string_to_chinese("100001000"), "一亿零一千")
    testing.assert_equal(decimal_string_to_chinese("100010000"), "一亿零一万")


def test_stacked_yi_for_large_magnitudes() raises:
    """Each further 亿 multiplies everything to its left by another 10^8."""
    # 10^12 -> 一万亿, 10^16 -> 一亿亿, 10^20 -> 一万亿亿.
    testing.assert_equal(decimal_string_to_chinese("1000000000000"), "一万亿")
    testing.assert_equal(decimal_string_to_chinese("10000000000000000"), "一亿亿")
    testing.assert_equal(
        decimal_string_to_chinese("100000000000000000000"), "一万亿亿"
    )
    # 1_2345_6789_0123 is 12345亿 + 6789万 + 123, i.e. the whole 一万二千三百
    # 四十五 is what 亿 multiplies -- not 一万 and 二千三百四十五 separately.
    testing.assert_equal(
        decimal_string_to_chinese("1234567890123"),
        "一万二千三百四十五亿六千七百八十九万零一百二十三",
    )


def test_yi_is_emitted_for_zero_sections() raises:
    """A zero section carries no words but still counts for a 亿."""
    # 10^16 + 5: the middle section of eight digits is entirely zero.
    testing.assert_equal(
        decimal_string_to_chinese("10000000000000005"), "一亿亿零五"
    )
    testing.assert_equal(
        decimal_string_to_chinese("10000000023456789"),
        "一亿亿零二千三百四十五万六千七百八十九",
    )


def test_unlimited_length() raises:
    """Integers far beyond any fixed-width type still convert."""
    testing.assert_equal(
        decimal_string_to_chinese("12345678901234567890123456789012345"),
        "一百二十三亿四千五百六十七万八千九百零一亿二千三百四十五万六千七百八十九亿零一百二十三万四千五百六十七亿八千九百零一万二千三百四十五",
    )


def test_unlimited_big_length() raises:
    """An 85-digit integer in the 繁體 style, well past 亿亿."""
    testing.assert_equal(
        decimal_string_to_chinese(
            "1234567890123456000077192370915780023409000070983127058120003078900000123456789012345",
            style=ChineseNumeralStyle.traditional(),
        ),
        (
            "一萬二千三百四十五億六千七百八十九萬零一百二十三億"
            "四千五百六十萬零七億七千一百九十二萬三千七百零九億"
            "一千五百七十八萬零二十三億四千零九十萬零七億"
            "零九百八十三萬一千二百七十億五千八百一十二萬零三億"
            "零七百八十九萬億零一百二十三萬四千五百六十七億"
            "八千九百零一萬二千三百四十五"
        ),
    )


# ===----------------------------------------------------------------------=== #
# Sign and fractional part
# ===----------------------------------------------------------------------=== #


def test_negative_numbers() raises:
    """Negative numbers are prefixed with 负."""
    testing.assert_equal(decimal_string_to_chinese("-15"), "负十五")
    testing.assert_equal(decimal_string_to_chinese("-100000001"), "负一亿零一")


def test_fractional_part_is_read_digit_by_digit() raises:
    """Digits after 点 are read one by one, zeros included."""
    testing.assert_equal(decimal_string_to_chinese("1050.07"), "一千零五十点零七")
    testing.assert_equal(decimal_string_to_chinese("0.5"), "零点五")
    testing.assert_equal(decimal_string_to_chinese("0.00123"), "零点零零一二三")
    testing.assert_equal(decimal_string_to_chinese("3.14159"), "三点一四一五九")


def test_written_precision_is_preserved() raises:
    """Trailing zeros of the fractional part survive the conversion."""
    testing.assert_equal(decimal_string_to_chinese("1.50"), "一点五零")
    testing.assert_equal(decimal_string_to_chinese("2.000"), "二点零零零")


def test_scientific_notation_input() raises:
    """Exponents are expanded before the reading."""
    testing.assert_equal(decimal_string_to_chinese("1.23e5"), "十二万三千")
    testing.assert_equal(decimal_string_to_chinese("1e3"), "一千")
    testing.assert_equal(decimal_string_to_chinese("5e-2"), "零点零五")


def test_invalid_input_raises() raises:
    """Non-numeric input is rejected by the underlying parser."""
    with testing.assert_raises():
        _ = decimal_string_to_chinese("abc")
    with testing.assert_raises():
        _ = decimal_string_to_chinese("")


# ===----------------------------------------------------------------------=== #
# Digit budget
# ===----------------------------------------------------------------------=== #


def test_digit_budget_boundary() raises:
    """The budget counts the digits of the plain-notation reading."""
    # 1e9999 writes 10000 digits: exactly the default cap.
    _ = decimal_string_to_chinese("1e" + String(MAX_CHINESE_NUMERAL_DIGITS - 1))
    with testing.assert_raises():
        _ = decimal_string_to_chinese("1e" + String(MAX_CHINESE_NUMERAL_DIGITS))

    _ = decimal_string_to_chinese("1e3", max_digits=4)
    with testing.assert_raises():
        _ = decimal_string_to_chinese("1e3", max_digits=3)


def test_digit_budget_counts_fractional_digits() raises:
    """A value far below 1 is bounded by its fractional expansion."""
    # 1e-4 is 0.0001: one leading 零 plus four fractional digits.
    _ = decimal_string_to_chinese("1e-4", max_digits=5)
    with testing.assert_raises():
        _ = decimal_string_to_chinese("1e-4", max_digits=4)
    with testing.assert_raises():
        _ = decimal_string_to_chinese("1e-1000000000")


def test_digit_budget_rejects_compact_input_early() raises:
    """A short string naming a huge magnitude never gets expanded."""
    # These parse into a couple of digits but would write out a billion, so
    # the check has to happen before the digits are materialized -- if it did
    # not, this test would exhaust memory rather than raise.
    with testing.assert_raises():
        _ = decimal_string_to_chinese("1e1000000000")
    with testing.assert_raises():
        _ = decimal_string_to_chinese("123.456e999999999")


def test_digit_budget_can_be_lifted() raises:
    """`max_digits=0` restores the unbounded behaviour."""
    var big = decimal_string_to_chinese("1e20000", max_digits=0)
    testing.assert_true(big.byte_length() > 0)
    testing.assert_equal(
        decimal_string_to_chinese("1e20000", max_digits=20001), big
    )


# ===----------------------------------------------------------------------=== #
# Styles
# ===----------------------------------------------------------------------=== #


def test_simplified_financial_style() raises:
    """The 大写 style swaps digits and units, and keeps 一十."""
    var style = ChineseNumeralStyle.simplified_financial()
    testing.assert_equal(
        decimal_string_to_chinese("1050.07", style), "壹仟零伍拾点零柒"
    )
    testing.assert_equal(decimal_string_to_chinese("15", style), "壹拾伍")
    testing.assert_equal(decimal_string_to_chinese("100000000", style), "壹亿")


def test_traditional_style() raises:
    """The 繁體 style swaps 万/亿/点/负 for 萬/億/點/負."""
    var style = ChineseNumeralStyle.traditional()
    testing.assert_equal(
        decimal_string_to_chinese("-1050.07", style), "負一千零五十點零七"
    )
    testing.assert_equal(decimal_string_to_chinese("10000", style), "一萬")
    testing.assert_equal(decimal_string_to_chinese("100000000", style), "一億")


def test_traditional_financial_style() raises:
    """The 繁體大寫 style combines both tables."""
    var style = ChineseNumeralStyle.traditional_financial()
    testing.assert_equal(
        decimal_string_to_chinese("-1050.07", style), "負壹仟零伍拾點零柒"
    )
    testing.assert_equal(decimal_string_to_chinese("23", style), "貳拾參")


def test_custom_style() raises:
    """A hand-built style works like the presets."""
    var digits: Array[StaticString, 10] = [
        "0",
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "7",
        "8",
        "9",
    ]
    var units: Array[StaticString, 3] = ["T", "H", "K"]
    var style = ChineseNumeralStyle(digits, units, "W", "Y", ".", "-", False)
    testing.assert_equal(decimal_string_to_chinese("10001.5", style), "1W01.5")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
