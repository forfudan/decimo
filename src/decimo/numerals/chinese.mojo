# ===----------------------------------------------------------------------=== #
# Copyright 2025-2026 Yuhao Zhu
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===----------------------------------------------------------------------=== #

"""Chinese numerals.

The integer part is split into *sections* of eight digits, counted from the
decimal point, and the sections are joined by 亿.  Only 万 and 亿 are used;
the rarely-agreed-upon 兆/京/垓/... units are avoided entirely.

The key point is that 亿 is a **multiplier over everything already read**,
not a label attached to one section.  A number is therefore read as a
Horner scheme in base 10^8:

```console
N = ((...(s[k] * 10^8 + s[k-1]) * 10^8 + ...) * 10^8) + s[0]
    -> read(s[k]) 亿 read(s[k-1]) 亿 ... 亿 read(s[0])
```

so 1_2345_6789_0123 reads 一萬二千三百四十五億六千七百八十九萬零一百二十三
(12345 亿 + 6789 万 + 123), and each further 亿 raises everything to its left
by another 10^8: 亿亿 is 10^16, 亿亿亿 is 10^24.  A 亿 is emitted for every
section boundary even when the section itself is zero, because it carries
magnitude: 10^16 + 5 reads 一億億零五.

Within a section, the upper four digits take 万 and both halves are read
with the 十/百/千 units, e.g. 4560_0007 -> 四千五百六十万零七.

The algorithm never converts the whole number to an integer type -- it only
ever looks at eight digits at a time -- so integers of any length are
supported.  What is capped is not the algorithm but the output: a number is
written out in full, so `1E+1000000000` would mean a billion digits and a
multi-gigabyte string.  Conversions therefore take a `max_digits` budget,
`MAX_CHINESE_NUMERAL_DIGITS` by default, and the budget is checked *before*
the digits are expanded.  Pass `max_digits=0` to lift the cap entirely.

The fractional part is a plain digit-by-digit reading after 点, zeros
included, so the written precision is preserved (1.50 -> 一點五零).

Casing (小寫/大寫) and script (簡體/繁體) are only different lookup tables:
pick a preset on `ChineseNumeralStyle` or build your own.
"""

# [Mojo Miji]
# 中文小數點前之轉換的規律大致是：
# 將所有數字分爲四位一組，從小數點前的最後一位開始向左分組。
# 所有數字首先對位轉爲漢字寫法。
# 組間自右向左循環插入「萬」「億」，組内則插入「十」「百」「千」。
# 「億」統乘其左所讀之全部，故每隔一組復現一次，「億億」即 10^16。
# 組内零後的單位省去。
# 組内四位全爲零時，其後之「萬」不讀；「億」則仍須讀，蓋其位不可失，
# 如 10^16 + 5 讀作「一億億零五」。
# 組内出現連續多個零時，則只讀一次零。組末出現的連續零不讀。
# 組首之零須讀，如「一億零一」；與鄰組之零相連者，亦只讀一次。
# 若起首爲「一十」，讀作「十」。

from decimo.errors import ValueError
from decimo.str import parse_numeric_string

comptime MAX_CHINESE_NUMERAL_DIGITS = 10_000
"""Default cap on how many digits a conversion may write out.

The reading of a number is always in plain notation, so the cost is set by
the *written* length, not by how compactly the value was given: `1E+1000000000`
is three characters of input and a billion digits of output.  Ten thousand
digits is already far past what anyone reads, while leaving room for the large
integers this library exists for.  Pass `max_digits=0` to lift the cap.
"""


def _check_digit_budget(
    num_significant_digits: Int, scale: Int, max_digits: Int, function: String
) raises -> None:
    """Raises if writing the number out in full would exceed the budget.

    The check is done on a coefficient/scale pair rather than on the expanded
    digits, so the caller can bail out before allocating them.

    Args:
        num_significant_digits: The number of digits in the coefficient.
        scale: The scale of the number: value = coefficient * 10^(-scale).
        max_digits: The largest permitted number of digits in plain notation.
            Zero or negative lifts the cap.
        function: The name of the calling function, for the error message.

    Raises:
        ValueError: If the plain-notation reading needs more than `max_digits`
            digits.
    """
    if max_digits <= 0:
        return

    # Plain notation writes `num_significant_digits - scale` integer digits
    # when `scale <= 0` (the exponent contributes trailing zeros), and `scale`
    # fractional digits otherwise; a number below 1 still writes its leading 零.
    var num_digits: Int
    if scale <= 0:
        num_digits = num_significant_digits - scale
    elif scale >= num_significant_digits:
        num_digits = 1 + scale
    else:
        num_digits = num_significant_digits

    if num_digits > max_digits:
        raise ValueError(
            message=String(
                "The number needs {} digits when written out, which exceeds"
                " the limit of {}. Raise `max_digits`, or pass `max_digits=0`"
                " to lift the limit."
            ).format(num_digits, max_digits),
            function=function,
        )


struct ChineseNumeralStyle(Copyable, ImplicitlyCopyable, Movable):
    """Character tables that fully define one Chinese-numeral rendering.

    The same algorithm produces 小寫/大寫 (everyday/financial) and 簡體/繁體
    (simplified/traditional) output just by swapping tables.  Use one of the
    presets (`simplified()`, `simplified_financial()`, `traditional()`,
    `traditional_financial()`) or construct your own.

    Examples:

    ```mojo
    from decimo.numerals import ChineseNumeralStyle, decimal_string_to_chinese

    print(decimal_string_to_chinese("1050.07"))  # 一千零五十点零七
    print(
        decimal_string_to_chinese(
            "1050.07", ChineseNumeralStyle.simplified_financial()
        )
    )  # 壹仟零伍拾点零柒
    ```
    """

    var digits: InlineArray[StaticString, 10]
    """The words for the digits 0 to 9, e.g. 零一二三四五六七八九.
    Entry 0 doubles as the zero-filler word inserted between groups."""
    var units: InlineArray[StaticString, 3]
    """The intra-group units in ascending order: 十, 百, 千."""
    var wan: StaticString
    """The 10^4 word (万 / 萬)."""
    var yi: StaticString
    """The 10^8 word (亿 / 億).  Multiplies everything read before it, so
    repeating it raises the magnitude by another 10^8 each time."""
    var point: StaticString
    """The decimal-point word (点 / 點)."""
    var negative_sign: StaticString
    """The negative-sign word (负 / 負)."""
    var simplify_leading_ten: Bool
    """If True, a leading 一十 is shortened to 十 (十五 rather than 一十五).
    Financial styles set this to False, since dropping a digit there would
    make the amount easier to tamper with."""

    def __init__(
        out self,
        digits: InlineArray[StaticString, 10],
        units: InlineArray[StaticString, 3],
        wan: StaticString,
        yi: StaticString,
        point: StaticString,
        negative_sign: StaticString,
        simplify_leading_ten: Bool,
    ):
        """Creates a numeral style from its character tables.

        Args:
            digits: The words for the digits 0 to 9.
            units: The intra-group units 十, 百, 千 (in this order).
            wan: The 10^4 word.
            yi: The 10^8 word.
            point: The decimal-point word.
            negative_sign: The negative-sign word.
            simplify_leading_ten: Whether a leading 一十 becomes 十.
        """
        self.digits = digits
        self.units = units
        self.wan = wan
        self.yi = yi
        self.point = point
        self.negative_sign = negative_sign
        self.simplify_leading_ten = simplify_leading_ten

    @staticmethod
    def simplified() -> Self:
        """Returns the everyday simplified-Chinese style (一二三 / 万亿 / 点).

        Returns:
            The 简体小写 numeral style.
        """
        var digits: InlineArray[StaticString, 10] = [
            "零",
            "一",
            "二",
            "三",
            "四",
            "五",
            "六",
            "七",
            "八",
            "九",
        ]
        var units: InlineArray[StaticString, 3] = ["十", "百", "千"]
        return Self(digits, units, "万", "亿", "点", "负", True)

    @staticmethod
    def simplified_financial() -> Self:
        """Returns the simplified financial style (壹贰叁 / 拾佰仟).

        This is the 大写 form used on Chinese cheques and invoices.

        Returns:
            The 简体大写 numeral style.
        """
        var digits: InlineArray[StaticString, 10] = [
            "零",
            "壹",
            "贰",
            "叁",
            "肆",
            "伍",
            "陆",
            "柒",
            "捌",
            "玖",
        ]
        var units: InlineArray[StaticString, 3] = ["拾", "佰", "仟"]
        return Self(digits, units, "万", "亿", "点", "负", False)

    @staticmethod
    def traditional() -> Self:
        """Returns the everyday traditional-Chinese style (萬億 / 點).

        Returns:
            The 繁體小寫 numeral style.
        """
        var digits: InlineArray[StaticString, 10] = [
            "零",
            "一",
            "二",
            "三",
            "四",
            "五",
            "六",
            "七",
            "八",
            "九",
        ]
        var units: InlineArray[StaticString, 3] = ["十", "百", "千"]
        return Self(digits, units, "萬", "億", "點", "負", True)

    @staticmethod
    def traditional_financial() -> Self:
        """Returns the traditional financial style (壹貳參 / 拾佰仟 / 萬億).

        Returns:
            The 繁體大寫 numeral style.
        """
        var digits: InlineArray[StaticString, 10] = [
            "零",
            "壹",
            "貳",
            "參",
            "肆",
            "伍",
            "陸",
            "柒",
            "捌",
            "玖",
        ]
        var units: InlineArray[StaticString, 3] = ["拾", "佰", "仟"]
        return Self(digits, units, "萬", "億", "點", "負", False)


def _chinese_group_to_string(
    group: InlineArray[UInt8, 4], style: ChineseNumeralStyle
) -> String:
    """Reads one group of four digits (0..9999) with the 十/百/千 units.

    Internal runs of zeros collapse into a single zero word; leading and
    trailing zeros of the group produce no word at all (they are the caller's
    business, since whether they need a 零 depends on the neighbouring
    groups).  Returns an empty string when all four digits are zero.

    Args:
        group: The four digit values, most significant first.
        style: The numeral style to render with.

    Returns:
        The reading of the group, e.g. `[1, 0, 0, 1]` -> 一千零一.
    """
    var result = String("")
    var pending_zero = False

    for i in range(4):
        var digit = Int(group[i])
        if digit == 0:
            # A zero only matters if a non-zero digit precedes it in this
            # group; trailing zeros are dropped when the loop ends.
            if result.byte_length() != 0:
                pending_zero = True
            continue
        if pending_zero:
            result += style.digits[0]
            pending_zero = False
        result += style.digits[digit]
        if i < 3:
            result += style.units[2 - i]  # 千, 百, 十

    return result^


def _chinese_section_to_string(
    section: InlineArray[UInt8, 8], style: ChineseNumeralStyle
) -> String:
    """Reads one section of eight digits (0..99999999) with 十/百/千 and 万.

    The upper four digits take 万; a 零 bridges the two halves when the lower
    one does not fill its four digits.  Leading zeros of the section produce
    no word (whether they need a 零 depends on the preceding section, so that
    is the caller's business).  Returns an empty string for an all-zero
    section.

    Args:
        section: The eight digit values, most significant first.
        style: The numeral style to render with.

    Returns:
        The reading of the section, e.g. `4560_0007` -> 四千五百六十万零七.
    """
    var upper = InlineArray[UInt8, 4](fill=0)
    var lower = InlineArray[UInt8, 4](fill=0)
    var upper_is_zero = True
    var lower_is_zero = True

    for i in range(4):
        upper[i] = section[i]
        if upper[i] != 0:
            upper_is_zero = False
        lower[i] = section[i + 4]
        if lower[i] != 0:
            lower_is_zero = False

    if upper_is_zero:
        return _chinese_group_to_string(lower, style)

    var result = _chinese_group_to_string(upper, style) + style.wan
    if not lower_is_zero:
        # 4567_8901 needs no 零, but 4560_0007 does: the lower half is short.
        if lower[0] == 0:
            result += style.digits[0]
        result += _chinese_group_to_string(lower, style)

    return result^


def _integer_digits_to_chinese(
    digits: List[UInt8], style: ChineseNumeralStyle
) -> String:
    """Converts a non-negative integer, given as digit values, to Chinese.

    Args:
        digits: The digit values (0 to 9) of the integer, most significant
            first.  May be empty, which reads as zero.
        style: The numeral style to render with.

    Returns:
        The Chinese reading of the integer, e.g. 一千零五十.
    """
    var num_digits = len(digits)

    # Skip leading zeros; an all-zero (or empty) input reads as 零.
    var first = 0
    while first < num_digits and digits[first] == 0:
        first += 1
    var num_significant = num_digits - first
    if num_significant == 0:
        return String(style.digits[0])

    # Sections of eight digits, counted from the right; the leftmost section
    # is the one that may be short, so `padding` digits of it are zero.
    var num_sections = (num_significant + 7) // 8
    var padding = num_sections * 8 - num_significant

    var result = String("")
    var pending_zero = False

    for section_index in range(num_sections):
        var section = InlineArray[UInt8, 8](fill=0)
        var is_zero_section = True
        for i in range(8):
            var position = section_index * 8 + i - padding
            if position >= 0:
                section[i] = digits[first + position]
                if section[i] != 0:
                    is_zero_section = False

        if is_zero_section:
            # An all-zero section is a gap between magnitudes, e.g. the middle
            # section of 1_00000000_00000005 (一亿亿零五).  It needs a 零, but
            # only if a non-zero section follows, so just record it for now.
            if result.byte_length() != 0:
                pending_zero = True
        else:
            # A section whose own leading digit is zero also needs a 零 in
            # front, e.g. the last section of 1_00000001 (一亿零一).
            if result.byte_length() != 0 and section[0] == 0:
                pending_zero = True

            # Consecutive zeros -- from any combination of the two rules above
            # -- always collapse into a single 零.
            if pending_zero:
                result += style.digits[0]
                pending_zero = False

            result += _chinese_section_to_string(section, style)

        # 亿 multiplies everything read so far, so one is emitted at every
        # section boundary -- including after a zero section, which carries no
        # words of its own but still counts for a factor of 10^8.
        if section_index < num_sections - 1:
            result += style.yi

    # 一十五 -> 十五, but only at the very beginning of the number: 一百一十五
    # keeps its 一十.
    if style.simplify_leading_ten:
        var leading_ten = String(style.digits[1]) + style.units[0]
        if result.startswith(leading_ten):
            result = String(result[byte = style.digits[1].byte_length() :])

    return result^


def decimal_string_to_chinese(
    value: String,
    style: ChineseNumeralStyle = ChineseNumeralStyle.simplified(),
    max_digits: Int = MAX_CHINESE_NUMERAL_DIGITS,
) raises -> String:
    """Converts the string of a number into Chinese numerals.

    The integer part is read with the 十/百/千/万 units within each section of
    eight digits, and the sections are joined by 亿, which multiplies
    everything read before it (see the module notes for the magnitude
    system).  The fractional part is read digit by digit after the
    decimal-point word, zeros included, so the written precision is
    preserved.

    Args:
        value: The string representation of a number.  It accepts everything
            `parse_numeric_string()` accepts, including scientific notation
            and digit separators.
        style: The numeral style to render with.  Defaults to the everyday
            simplified-Chinese style.
        max_digits: The largest number of digits the reading may write out.
            The reading is always in plain notation, so a compact input such
            as `1E+1000000000` would otherwise expand into a billion digits.
            The budget is checked before the digits are materialized.  Pass
            `0` to lift the cap.

    Returns:
        The Chinese reading of the number.

    Examples:

    ```console
    decimal_string_to_chinese("15")             -> 十五
    decimal_string_to_chinese("1050.07")        -> 一千零五十点零七
    decimal_string_to_chinese("-100000001")     -> 负一亿零一
    decimal_string_to_chinese("1.50")           -> 一点五零
    decimal_string_to_chinese("1.23e5")         -> 十二万三千
    ```
    End of examples.

    Raises:
        ValueError: If the string is empty, contains invalid characters, has
            malformed numeric syntax, or needs more than `max_digits` digits
            when written out in full.
    """

    var parsed = parse_numeric_string(value)
    var ref coefficient: List[UInt8] = parsed[0]
    var scale: Int = parsed[1]
    var sign: Bool = parsed[2]
    var num_digits = len(coefficient)

    _check_digit_budget(
        num_digits, scale, max_digits, "decimal_string_to_chinese()"
    )

    # The coefficient holds the significant digits and `scale` says where the
    # decimal point sits: value = coefficient * 10^(-scale).
    var integer_digits = List[UInt8]()
    var fraction_digits = List[UInt8]()

    if scale <= 0:
        # An integer, possibly with trailing zeros carried by the exponent.
        for i in range(num_digits):
            integer_digits.append(coefficient[i])
        for _ in range(-scale):
            integer_digits.append(0)
    elif scale >= num_digits:
        # No integer digits at all, e.g. 0.00123 -> 零点零零一二三.
        for _ in range(scale - num_digits):
            fraction_digits.append(0)
        for i in range(num_digits):
            fraction_digits.append(coefficient[i])
    else:
        for i in range(num_digits - scale):
            integer_digits.append(coefficient[i])
        for i in range(num_digits - scale, num_digits):
            fraction_digits.append(coefficient[i])

    var result = String("")
    if sign:
        result += style.negative_sign
    result += _integer_digits_to_chinese(integer_digits, style)

    if len(fraction_digits) != 0:
        result += style.point
        for i in range(len(fraction_digits)):
            result += style.digits[Int(fraction_digits[i])]

    return result^
