"""
Test Decimal128 conversion methods: __str__, __int__, __float__
Merges former to_string, to_int, to_float test files.
"""

from std import testing

from decimo import Dec128, Decimal128
from decimo.tests import TestCase, load_test_cases, parse_file
from decimo.toml.parser import TOMLDocument

comptime file_path = "tests/decimal128/test_data/decimal128_conversions.toml"


def test_str_conversion() raises:
    """Test __str__ using TOML data-driven test cases."""
    var toml = parse_file(file_path)
    var test_cases = load_test_cases[unary=True](toml, "str_conversion_tests")
    var count_wrong = 0
    for tc in test_cases:
        var result = String(Dec128(tc.a))
        try:
            testing.assert_equal(
                lhs=result, rhs=tc.expected, msg=tc.description
            )
        except e:
            print(
                tc.description,
                "\n  Expected:",
                tc.expected,
                "\n  Got:",
                result,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(count_wrong, 0, "Some str conversion tests failed.")


def test_int_conversion() raises:
    """Test __int__ conversion."""
    # Positive integer
    testing.assert_equal(Int(Dec128(123)), 123)

    # Negative integer
    testing.assert_equal(Int(Dec128(-456)), -456)

    # Zero
    testing.assert_equal(Int(Dec128(0)), 0)

    # Decimal truncation: Decimal128(789987, scale=3) = 789.987 -> 789
    testing.assert_equal(Int(Decimal128(789987, 3)), 789)

    # Negative decimal truncation: Decimal128(-123456, scale=3) = -123.456 -> -123
    testing.assert_equal(Int(Decimal128(-123456, 3)), -123)

    # Large number
    testing.assert_equal(Int(Dec128(9999999999)), 9999999999)


def test_float_basic_integers() raises:
    """Test __float__ conversion for basic integers."""
    testing.assert_equal(Float64(Dec128(0)), 0.0)
    testing.assert_equal(Float64(Dec128(1)), 1.0)
    testing.assert_equal(Float64(Dec128(10)), 10.0)
    testing.assert_equal(Float64(Dec128(123456)), 123456.0)


def test_float_decimals() raises:
    """Test __float__ conversion for decimal values."""
    testing.assert_equal(Float64(Dec128("3.14")), 3.14)
    testing.assert_true(
        abs(Float64(Dec128("3.14159265358979323846")) - 3.14159265358979323846)
        < 1e-15
    )
    testing.assert_equal(Float64(Dec128("0.0001")), 0.0001)
    testing.assert_true(
        abs(Float64(Dec128("0.33333333333333")) - 0.33333333333333) < 1e-14
    )


def test_float_negatives() raises:
    """Test __float__ conversion for negative values."""
    testing.assert_equal(Float64(Dec128("-123")), -123.0)
    testing.assert_equal(Float64(Dec128("-0.5")), -0.5)
    testing.assert_equal(Float64(Dec128("-0")), 0.0)


def test_float_edge_cases() raises:
    """Test __float__ conversion edge cases."""
    # Very small positive
    var very_small = Dec128("0." + "0" * 20 + "1")
    var very_small_float = Float64(very_small)
    testing.assert_true(very_small_float > 0.0 and very_small_float < 1e-19)

    # Precision edge
    testing.assert_true(
        abs(Float64(Dec128("0.1234567890123456")) - 0.1234567890123456) < 1e-15
    )

    # Large number
    testing.assert_equal(Float64(Dec128("1e15")), 1e15)

    # Beyond safe integer precision
    testing.assert_true(
        abs(Float64(Dec128("9007199254740993")) - 9007199254740993.0) <= 1.0
    )


def test_float_special_values() raises:
    """Test __float__ conversion of special values."""
    testing.assert_equal(Float64(Dec128("5.0000")), 5.0)
    testing.assert_equal(Float64(Dec128("000123.456")), 123.456)
    testing.assert_equal(Float64(Dec128("1.23e5")), 123000.0)
    testing.assert_true(abs(Float64(Dec128("0.1")) - 0.1) < 1e-15)

    # Large decimal
    var max_decimal = Dec128("79228162514264337593543950335")
    var max_float = Float64(max_decimal)
    testing.assert_true(
        abs(
            (max_float - 79228162514264337593543950335)
            / 79228162514264337593543950335
        )
        < 1e-10
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
