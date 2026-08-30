"""
Test BigDecimal root and power operations against TOML expected values.

Python's Decimal cannot compute most non-integer exponents, so these tests
compare against pre-computed expected values in the TOML data file instead
of Python cross-checking.
"""

from std import testing

from decimo import BDec
from decimo.tests import TestCase, load_test_cases, parse_file

comptime file_path = "tests/bigdecimal/test_data/bigdecimal_exponential.toml"


def test_bigdecimal_root() raises:
    """Test BigDecimal root function against TOML expected values."""
    var toml = parse_file(file_path)
    var test_cases = load_test_cases(toml, "root_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a).root(BDec(test_case.b), precision=28)
        var mojo_str = String(result)
        if mojo_str != test_case.expected:
            print(
                test_case.description,
                "\n  Got:      ",
                mojo_str,
                "\n  Expected: ",
                test_case.expected,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "root: Some test cases failed. See above.",
    )


def test_bigdecimal_power() raises:
    """Test BigDecimal power function against TOML expected values."""
    var toml = parse_file(file_path)
    var test_cases = load_test_cases(toml, "power_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a).power(BDec(test_case.b), precision=28)
        var mojo_str = String(result)
        if mojo_str != test_case.expected:
            print(
                test_case.description,
                "\n  Got:      ",
                mojo_str,
                "\n  Expected: ",
                test_case.expected,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "power: Some test cases failed. See above.",
    )


def test_root_invalid_inputs() raises:
    """Test that root function with invalid inputs raises appropriate errors."""
    var a1 = BDec("16")
    var n1 = BDec("0")
    var exception_caught: Bool
    try:
        _ = a1.root(n1, precision=28)
        exception_caught = False
    except:
        exception_caught = True
    testing.assert_true(exception_caught, "0th root should raise an error")

    var a2 = BDec("-16")
    var n2 = BDec("2")
    try:
        _ = a2.root(n2, precision=28)
        exception_caught = False
    except:
        exception_caught = True
    testing.assert_true(
        exception_caught, "Even root of negative number should raise an error"
    )

    var a3 = BDec("-16")
    var n3 = BDec("2.5")
    try:
        _ = a3.root(n3, precision=28)
        exception_caught = False
    except:
        exception_caught = True
    testing.assert_true(
        exception_caught,
        (
            "Fractional root with even denominator of negative number should"
            " raise an error"
        ),
    )


def test_power_invalid_inputs() raises:
    """Test that power function with invalid inputs raises appropriate errors.
    """
    var base1 = BDec("0")
    var exp1 = BDec("0")
    var exception_caught: Bool
    try:
        _ = base1.power(exp1, precision=28)
        exception_caught = False
    except:
        exception_caught = True
    testing.assert_true(exception_caught, "0^0 should raise an error")

    var base2 = BDec("0")
    var exp2 = BDec("-1")
    try:
        _ = base2.power(exp2, precision=28)
        exception_caught = False
    except:
        exception_caught = True
    testing.assert_true(
        exception_caught, "0 raised to a negative power should raise an error"
    )

    var base3 = BDec("-2")
    var exp3 = BDec("0.5")
    try:
        _ = base3.power(exp3, precision=28)
        exception_caught = False
    except:
        exception_caught = True
    testing.assert_true(
        exception_caught,
        "Negative number raised to a fractional power should raise an error",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
