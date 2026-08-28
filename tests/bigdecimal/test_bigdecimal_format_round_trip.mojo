"""
Round-trips `to_string()` across its flag matrix.

The formatting flags have spot checks -- a handful of values with a handful of
expected strings. What none of them pin is the property that makes the
formatter usable: whatever combination of flags is asked for, the string still
names the same number, and the flags that only rearrange the output can be
undone.

`__str__` itself matches CPython over 933 values spanning both of its
notation boundaries, so what is swept here is the part CPython has no
equivalent for: `force_plain`, `force_exponent`, `delimiter` and `line_width`.

Four properties:

- parse-back: `BDec(x.to_string(flags)) == x`, for every flag combination that
  produces something parseable;
- `force_plain` really is plain: no exponent character, at any magnitude;
- `delimiter` only inserts: strip the delimiter and the plain string is back;
- `line_width` only wraps: join the lines and the single-line string is back.
"""

from std import testing
from std.testing import assert_true, assert_equal

from decimo.bigdecimal.bigdecimal import BDec


def sweep_values() raises -> List[BDec]:
    """Values either side of both notation boundaries, both signs."""
    var values = List[BDec]()
    for text in [
        String("0"),
        String("-0"),
        String("1"),
        String("-1"),
        String("123.456"),
        String("-123.4500"),
        String("0.000001"),
        String("0.0000001"),
        String("1000000"),
        String("10000000"),
        String("1E+1"),
        String("1E-1"),
        String("0E+5"),
        String("0E-5"),
        String("1.5E+300"),
        String("1.5E-300"),
        String("999999999999999999"),
        String("1000000000000000000"),
        String("123456789012345678901234567890.123456789"),
        String("-70000000000000000000000000000000000000E-17"),
    ]:
        values.append(BDec(text))
    return values^


def test_every_flag_combination_parses_back_to_the_same_number() raises:
    for value in sweep_values():
        for scientific in [False, True]:
            for engineering in [False, True]:
                for force_plain in [False, True]:
                    for force_exponent in [False, True]:
                        var text = value.to_string(
                            scientific=scientific,
                            engineering=engineering,
                            force_plain=force_plain,
                            force_exponent=force_exponent,
                        )
                        var parsed = BDec(text)
                        assert_true(
                            parsed == value,
                            "round trip changed the value: "
                            + String(value)
                            + " printed as "
                            + text,
                        )


def test_force_plain_never_shows_an_exponent() raises:
    for value in sweep_values():
        var text = value.to_string(force_plain=True)
        assert_true(
            text.find("E") == -1 and text.find("e") == -1,
            "force_plain produced an exponent: " + text,
        )
        assert_true(
            BDec(text) == value,
            "force_plain changed the value: " + String(value) + " -> " + text,
        )


def test_a_delimiter_only_inserts_characters() raises:
    for value in sweep_values():
        var plain = value.to_string()
        for delimiter in [String("_"), String(","), String(" ")]:
            var grouped = value.to_string(delimiter=delimiter)
            var stripped = String("")
            for i in range(grouped.byte_length()):
                var character = String(grouped[byte = i : i + 1])
                if character != delimiter:
                    stripped += character
            assert_equal(
                stripped,
                plain,
                "removing '" + delimiter + "' did not give the plain string",
            )


def test_line_width_only_wraps() raises:
    var long_value = BDec(
        "123456789012345678901234567890123456789012345678901234567890.5"
    )
    var single = long_value.to_string()
    for width in [10, 20, 33, 80]:
        var wrapped = long_value.to_string(line_width=width)
        var joined = String("")
        for line in wrapped.split("\n"):
            joined += String(line)
        assert_equal(
            joined,
            single,
            "joining the lines at width "
            + String(width)
            + " did not give the single-line string",
        )
        for line in wrapped.split("\n"):
            assert_true(
                String(line).byte_length() <= width,
                "a line ran past the requested width of " + String(width),
            )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
