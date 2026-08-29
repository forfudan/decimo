"""
Tests for the text `BigDecimal` produces: the quick path and the general one
have to agree, at every shape and on both sides of the buffer the quick path
keeps on the stack.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.bigdecimal import BigDecimal


def test_text_is_the_same_by_every_route() raises:
    """`to_string()`, `__str__()` and `String()` give one answer.

    `to_string()` and `__str__()` lay the digits out in one buffer; `String()`
    goes through the writer. They are three code paths and one result.
    """

    def _check(text: String, expected: String) raises:
        var value = BigDecimal(text)
        assert_equal(value.to_string(), expected)
        assert_equal(value.__str__(), expected)
        assert_equal(String(value), expected)

    # Whole numbers, with and without a sign.
    _check("123", "123")
    _check("-123", "-123")
    _check("0", "0")
    _check("-0", "-0")

    # A point inside the digits.
    _check("1.5", "1.5")
    _check("-1.5", "-1.5")
    _check("123.456", "123.456")
    _check("1.230", "1.230")

    # A point before them, which needs the zeros written out.
    _check("0.5", "0.5")
    _check("0.001", "0.001")
    _check("-0.001", "-0.001")
    _check("0.000001", "0.000001")

    # Where the quick path hands over to scientific notation.
    _check("1E+5", "1E+5")
    _check("-0.0000001", "-1E-7")
    _check("1.5E-8", "1.5E-8")


def test_text_across_the_stack_buffer() raises:
    """The quick path lays short values out on the stack and longer ones on
    the heap; both have to produce the same digits.

    The boundary is 32 bytes, so these run from side to side of it.
    """
    for length in range(25, 40):
        var digits = String("")
        for index in range(length):
            digits += String((index % 9) + 1)

        var whole = BigDecimal(digits)
        assert_equal(whole.to_string(), digits)
        assert_equal(String(whole), digits)

        var fractional = BigDecimal(digits + ".25")
        assert_equal(fractional.to_string(), digits + ".25")
        assert_equal(String(fractional), digits + ".25")

        var negative = BigDecimal("-" + digits)
        assert_equal(negative.to_string(), "-" + digits)
        assert_equal(String(negative), "-" + digits)

        var small = BigDecimal("0." + digits)
        assert_equal(small.to_string(), "0." + digits)
        assert_equal(String(small), "0." + digits)


def test_text_round_trips() raises:
    """Reading back what was written gives the same value, digit for digit.

    Which is what says the digits went into the buffer in the right order
    and the point landed between the right two. Every sample here stays in
    plain notation; below `1E-6` the text is written with an exponent and is
    no longer the same string.
    """
    var samples = [
        "0",
        "1",
        "-1",
        "1.5",
        "0.001",
        "123456789012345678901234567890",
        "-123456789012345678901234567890.123456789",
        "0.00001234",
        "99999999999999999999.99999999999999999999",
    ]
    for sample in samples:
        var value = BigDecimal(sample)
        assert_equal(BigDecimal(value.to_string()), value)
        assert_equal(value.to_string(), sample)


def test_the_other_formats_still_work() raises:
    """The quick path only handles plain notation; everything else goes the
    way it always did."""
    var value = BigDecimal("1234.5678")
    assert_equal(value.to_string(scientific=True), "1.2345678E+3")
    assert_equal(value.to_string(delimiter="_"), "1_234.567_8")
    assert_equal(BigDecimal("123456").to_eng_string(), "123456")
    assert_equal(BigDecimal("1.23E+5").to_eng_string(), "123E+3")
    assert_equal(
        BigDecimal("1E+40").to_string(force_plain=True),
        "10000000000000000000000000000000000000000",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
