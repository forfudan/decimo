"""Tests for the settings parser (4.7), meta-command detection, and inline
settings splitting (4.8)."""

from std import testing

from decimo.rounding_mode import RoundingMode
from calculator.settings import (
    Settings,
    parse_settings,
    split_inline_settings,
    to_lower,
)


# ===----------------------------------------------------------------------=== #
# Tests: Settings struct
# ===----------------------------------------------------------------------=== #


def test_settings_defaults() raises:
    """Default settings match CLI defaults."""
    var s = Settings()
    testing.assert_equal(s.precision, 50)
    testing.assert_false(s.scientific, "scientific default")
    testing.assert_false(s.engineering, "engineering default")
    testing.assert_false(s.pad, "pad default")
    testing.assert_equal(s.delimiter, "")
    testing.assert_true(
        s.rounding_mode == RoundingMode.half_even(), "rounding default"
    )


def test_settings_write_to_default() raises:
    """Default settings produces a simple summary."""
    var s = Settings()
    var text = String(s)
    testing.assert_true("Precision: 50." in text, "should contain precision")


def test_settings_write_to_custom() raises:
    """Custom settings are reflected in the summary."""
    var s = Settings(
        precision=100,
        scientific=True,
        pad=True,
        delimiter="_",
    )
    var text = String(s)
    testing.assert_true("Precision: 100." in text, "precision")
    testing.assert_true("Scientific" in text, "scientific")
    testing.assert_true("Zero-padded" in text, "pad")
    testing.assert_true("_" in text, "delimiter")


# ===----------------------------------------------------------------------=== #
# Tests: parse_settings — precision
# ===----------------------------------------------------------------------=== #


def test_parse_precision_long() raises:
    """`:precision 100` sets precision."""
    var s = Settings()
    parse_settings("precision 100", s)
    testing.assert_equal(s.precision, 100)


def test_parse_precision_short() raises:
    """`:p 200` sets precision."""
    var s = Settings()
    parse_settings("p 200", s)
    testing.assert_equal(s.precision, 200)


def test_parse_precision_case_insensitive() raises:
    """`:P 300` is case-insensitive."""
    var s = Settings()
    parse_settings("P 300", s)
    testing.assert_equal(s.precision, 300)


def test_parse_precision_missing_value() raises:
    """`:p` with no value raises."""
    var s = Settings()
    var raised = False
    try:
        parse_settings("p", s)
    except:
        raised = True
    testing.assert_true(raised, "should raise")


def test_parse_precision_invalid_value() raises:
    """`:p abc` with non-integer value raises."""
    var s = Settings()
    var raised = False
    try:
        parse_settings("p abc", s)
    except:
        raised = True
    testing.assert_true(raised, "should raise on non-integer")


def test_parse_precision_zero() raises:
    """`:p 0` rejects zero precision."""
    var s = Settings()
    var raised = False
    try:
        parse_settings("p 0", s)
    except:
        raised = True
    testing.assert_true(raised, "should reject p 0")


# ===----------------------------------------------------------------------=== #
# Tests: parse_settings — flags
# ===----------------------------------------------------------------------=== #


def test_parse_scientific_short() raises:
    """`:s` turns on scientific."""
    var s = Settings()
    parse_settings("s", s)
    testing.assert_true(s.scientific, "scientific on")
    testing.assert_false(s.engineering, "engineering off (mutual exclusion)")


def test_parse_scientific_long() raises:
    """`:scientific` turns on scientific."""
    var s = Settings()
    parse_settings("scientific", s)
    testing.assert_true(s.scientific, "scientific on")


def test_parse_scientific_alias() raises:
    """`:sci` turns on scientific."""
    var s = Settings()
    parse_settings("sci", s)
    testing.assert_true(s.scientific, "scientific on")


def test_parse_engineering_turns_off_scientific() raises:
    """`:e` turns off scientific if it was on."""
    var s = Settings(scientific=True)
    parse_settings("e", s)
    testing.assert_true(s.engineering, "engineering on")
    testing.assert_false(s.scientific, "scientific off")


def test_parse_pad() raises:
    """`:pad` turns on pad."""
    var s = Settings()
    parse_settings("pad", s)
    testing.assert_true(s.pad, "pad on")


def test_parse_no_scientific() raises:
    """`:s` again toggles scientific off."""
    var s = Settings(scientific=True)
    parse_settings("s", s)
    testing.assert_false(s.scientific, "scientific toggled off")


def test_parse_no_engineering() raises:
    """`:e` again toggles engineering off."""
    var s = Settings(engineering=True)
    parse_settings("e", s)
    testing.assert_false(s.engineering, "engineering toggled off")


def test_parse_no_pad() raises:
    """`:pad` again toggles pad off."""
    var s = Settings(pad=True)
    parse_settings("pad", s)
    testing.assert_false(s.pad, "pad toggled off")


# ===----------------------------------------------------------------------=== #
# Tests: parse_settings — delimiter
# ===----------------------------------------------------------------------=== #


def test_parse_delimiter_long() raises:
    """`:delimiter ,` sets delimiter."""
    var s = Settings()
    parse_settings("delimiter ,", s)
    testing.assert_equal(s.delimiter, ",")


def test_parse_delimiter_off() raises:
    """`:delimiter off` clears delimiter."""
    var s = Settings(delimiter="_")
    parse_settings("delimiter off", s)
    testing.assert_equal(s.delimiter, "")


def test_parse_delimiter_none() raises:
    """`:delimiter none` clears delimiter."""
    var s = Settings(delimiter=",")
    parse_settings("delimiter none", s)
    testing.assert_equal(s.delimiter, "")


# ===----------------------------------------------------------------------=== #
# Tests: parse_settings — rounding mode
# ===----------------------------------------------------------------------=== #


def test_parse_rounding_short() raises:
    """`:r down` sets rounding mode."""
    var s = Settings()
    parse_settings("r down", s)
    testing.assert_true(s.rounding_mode == RoundingMode.down(), "rounding down")


def test_parse_rounding_long() raises:
    """`:rounding-mode half-up` sets rounding mode."""
    var s = Settings()
    parse_settings("rounding-mode half-up", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.half_up(), "rounding half-up"
    )


def test_parse_rounding_underscore() raises:
    """`:r half_even` with underscore form works."""
    var s = Settings()
    parse_settings("r half_even", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.half_even(), "rounding half-even"
    )


def test_parse_rounding_abbreviation() raises:
    """`:r hu` short form for half-up."""
    var s = Settings()
    parse_settings("r hu", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.half_up(), "rounding half-up"
    )


def test_parse_rounding_ceiling() raises:
    """`:r ceil` alias for ceiling."""
    var s = Settings()
    parse_settings("r ceil", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.ceiling(), "rounding ceiling"
    )


def test_parse_rounding_floor_short() raises:
    """`:r f` alias for floor."""
    var s = Settings()
    parse_settings("r f", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.floor(), "rounding floor"
    )


def test_parse_rounding_invalid() raises:
    """`:r xyz` raises on unknown rounding mode."""
    var s = Settings()
    var raised = False
    try:
        parse_settings("r xyz", s)
    except:
        raised = True
    testing.assert_true(raised, "should raise on unknown rounding mode")


def test_parse_rounding_bankers() raises:
    """`:r bankers` alias for half-even."""
    var s = Settings()
    parse_settings("r bankers", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.half_even(), "rounding bankers"
    )


def test_parse_rounding_b() raises:
    """`:r b` alias for half-even (banker's rounding)."""
    var s = Settings()
    parse_settings("r b", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.half_even(), "rounding b"
    )


# ===----------------------------------------------------------------------=== #
# Tests: parse_settings — standalone rounding modes (no `r` prefix)
# ===----------------------------------------------------------------------=== #


def test_standalone_d_is_down() raises:
    """`d` directly sets rounding to down."""
    var s = Settings()
    parse_settings("d", s)
    testing.assert_true(s.rounding_mode == RoundingMode.down(), "d = down")


def test_standalone_u_is_up() raises:
    """`u` directly sets rounding to up."""
    var s = Settings()
    parse_settings("u", s)
    testing.assert_true(s.rounding_mode == RoundingMode.up(), "u = up")


def test_standalone_he_is_half_even() raises:
    """`he` directly sets rounding to half-even."""
    var s = Settings()
    s.rounding_mode = RoundingMode.down()  # change first
    parse_settings("he", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.half_even(), "he = half-even"
    )


def test_standalone_hu_is_half_up() raises:
    """`hu` directly sets rounding to half-up."""
    var s = Settings()
    parse_settings("hu", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.half_up(), "hu = half-up"
    )


def test_standalone_hd_is_half_down() raises:
    """`hd` directly sets rounding to half-down."""
    var s = Settings()
    parse_settings("hd", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.half_down(), "hd = half-down"
    )


def test_standalone_c_is_ceiling() raises:
    """`c` directly sets rounding to ceiling."""
    var s = Settings()
    parse_settings("c", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.ceiling(), "c = ceiling"
    )


def test_standalone_f_is_floor() raises:
    """`f` directly sets rounding to floor."""
    var s = Settings()
    parse_settings("f", s)
    testing.assert_true(s.rounding_mode == RoundingMode.floor(), "f = floor")


def test_standalone_b_is_bankers() raises:
    """`b` directly sets rounding to half-even (banker's)."""
    var s = Settings()
    s.rounding_mode = RoundingMode.down()  # change first
    parse_settings("b", s)
    testing.assert_true(
        s.rounding_mode == RoundingMode.half_even(), "b = bankers"
    )


def test_standalone_down_word() raises:
    """`down` directly sets rounding to down."""
    var s = Settings()
    parse_settings("down", s)
    testing.assert_true(s.rounding_mode == RoundingMode.down(), "down = down")


def test_standalone_in_one_liner() raises:
    """`p 100 s d` sets precision, scientific, and rounding down."""
    var s = Settings()
    parse_settings("p 100 s d", s)
    testing.assert_equal(s.precision, 100)
    testing.assert_true(s.scientific, "scientific on")
    testing.assert_true(s.rounding_mode == RoundingMode.down(), "rounding down")


# ===----------------------------------------------------------------------=== #
# Tests: parse_settings — standalone integer precision
# ===----------------------------------------------------------------------=== #


def test_standalone_precision_basic() raises:
    """`100` sets precision to 100."""
    var s = Settings()
    parse_settings("100", s)
    testing.assert_equal(s.precision, 100)


def test_standalone_precision_one() raises:
    """`1` is the minimum valid precision."""
    var s = Settings()
    parse_settings("1", s)
    testing.assert_equal(s.precision, 1)


def test_standalone_precision_large() raises:
    """`5000` sets a large precision."""
    var s = Settings()
    parse_settings("5000", s)
    testing.assert_equal(s.precision, 5000)


def test_standalone_precision_with_other_settings() raises:
    """`100 s` sets precision and toggles scientific."""
    var s = Settings()
    parse_settings("100 s", s)
    testing.assert_equal(s.precision, 100)
    testing.assert_true(s.scientific, "scientific on")


def test_standalone_precision_with_rounding() raises:
    """`200 d` sets precision and rounding down."""
    var s = Settings()
    parse_settings("200 d", s)
    testing.assert_equal(s.precision, 200)
    testing.assert_true(s.rounding_mode == RoundingMode.down(), "rounding down")


def test_standalone_precision_zero_raises() raises:
    """`0` is below the minimum and should raise."""
    var s = Settings()
    var raised = False
    try:
        parse_settings("0", s)
    except:
        raised = True
    testing.assert_true(raised, "expected error for precision 0")


def test_standalone_precision_after_flag() raises:
    """`s 100` toggles scientific then sets precision."""
    var s = Settings()
    parse_settings("s 100", s)
    testing.assert_true(s.scientific, "scientific on")
    testing.assert_equal(s.precision, 100)


# ===----------------------------------------------------------------------=== #
# Tests: parse_settings — multi-token (4.7 one-liner)
# ===----------------------------------------------------------------------=== #


def test_parse_multi_p_s() raises:
    """`:p 100 s` sets precision and scientific."""
    var s = Settings()
    parse_settings("p 100 s", s)
    testing.assert_equal(s.precision, 100)
    testing.assert_true(s.scientific, "scientific on")


def test_parse_multi_p_s_r() raises:
    """`:p 100 s r down` sets precision, scientific, and rounding."""
    var s = Settings()
    parse_settings("p 100 s r down", s)
    testing.assert_equal(s.precision, 100)
    testing.assert_true(s.scientific, "scientific on")
    testing.assert_true(s.rounding_mode == RoundingMode.down(), "rounding down")


def test_parse_multi_all() raises:
    """Full one-liner with all options."""
    var s = Settings()
    parse_settings("p 200 e pad delimiter _ r ceiling", s)
    testing.assert_equal(s.precision, 200)
    testing.assert_false(s.scientific, "scientific off")
    testing.assert_true(s.engineering, "engineering on")
    testing.assert_true(s.pad, "pad on")
    testing.assert_equal(s.delimiter, "_")
    testing.assert_true(
        s.rounding_mode == RoundingMode.ceiling(), "rounding ceiling"
    )


def test_parse_unknown_token() raises:
    """Unknown settings token raises error."""
    var s = Settings()
    var raised = False
    try:
        parse_settings("p 100 xyz", s)
    except:
        raised = True
    testing.assert_true(raised, "should raise on unknown token")


def test_parse_empty_string() raises:
    """Empty input is a no-op."""
    var s = Settings(precision=42)
    parse_settings("", s)
    testing.assert_equal(s.precision, 42)


def test_parse_whitespace_only() raises:
    """Whitespace-only input is a no-op."""
    var s = Settings(precision=42)
    parse_settings("   ", s)
    testing.assert_equal(s.precision, 42)


# ===----------------------------------------------------------------------=== #
# Tests: split_inline_settings (4.8)
# ===----------------------------------------------------------------------=== #


def test_inline_basic() raises:
    """Basic inline settings detected."""
    var result = split_inline_settings("sqrt(2):p 100")
    testing.assert_true(Bool(result), "should detect inline settings")
    testing.assert_equal(result.value()[0], "sqrt(2)")
    testing.assert_equal(result.value()[1], "p 100")


def test_inline_complex() raises:
    """Inline settings with multiple options."""
    var result = split_inline_settings("1/3:p 200 s r down")
    testing.assert_true(Bool(result), "should detect")
    testing.assert_equal(result.value()[0], "1/3")
    testing.assert_equal(result.value()[1], "p 200 s r down")


def test_inline_with_space() raises:
    """Inline settings with space around colon."""
    var result = split_inline_settings("pi :p 100")
    testing.assert_true(Bool(result), "should detect")
    testing.assert_equal(result.value()[0], "pi ")
    testing.assert_equal(result.value()[1], "p 100")


def test_inline_meta_command_not_detected() raises:
    """Lines starting with `:` are meta-commands, not inline settings."""
    var result = split_inline_settings(":p 100")
    testing.assert_false(Bool(result), "meta-command is not inline")


def test_inline_no_colon() raises:
    """No colon → no inline settings."""
    var result = split_inline_settings("1 + 2 * 3")
    testing.assert_false(Bool(result), "no colon")


def test_inline_empty() raises:
    """Empty line → no inline settings."""
    var result = split_inline_settings("")
    testing.assert_false(Bool(result), "empty")


def test_inline_colon_inside_parens_ignored() raises:
    """Colon after closing paren splits correctly."""
    var result = split_inline_settings("sqrt(2):p 100")
    testing.assert_true(Bool(result), "colon after paren")
    testing.assert_equal(result.value()[0], "sqrt(2)")


# ===----------------------------------------------------------------------=== #
# Tests: to_lower (4.13)
# ===----------------------------------------------------------------------=== #


def test_to_lower_basic() raises:
    """Uppercase letters are lowered."""
    testing.assert_equal(to_lower("ABC"), "abc")


def test_to_lower_mixed() raises:
    """Mixed case is fully lowered."""
    testing.assert_equal(to_lower("Hello World"), "hello world")


def test_to_lower_already_lower() raises:
    """Lowercase stays unchanged."""
    testing.assert_equal(to_lower("abc"), "abc")


def test_to_lower_with_digits() raises:
    """Digits and special chars are preserved."""
    testing.assert_equal(to_lower("PI + SIN(1.23)"), "pi + sin(1.23)")


def test_to_lower_empty() raises:
    """Empty string stays empty."""
    testing.assert_equal(to_lower(""), "")


# ===----------------------------------------------------------------------=== #
# Main
# ===----------------------------------------------------------------------=== #


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
