"""
Tests BigDecimal trigonometric functions.
"""

from std import testing
from std.python import Python

from decimo import BigDecimal
import decimo.bigdecimal.trigonometric
from decimo.tests import TestCase, load_test_cases, parse_file
from decimo.toml.parser import TOMLDocument

comptime file_path = "tests/bigdecimal/test_data/bigdecimal_trigonometric.toml"


def run_test[
    func: def(BigDecimal, Int) thin raises -> BigDecimal
](toml: TOMLDocument, table_name: String, msg: String) raises:
    """Run a specific test case from the TOML document."""
    var test_cases = load_test_cases(toml, table_name)
    var count_wrong = 0
    for test_case in test_cases:
        var _bdec = BigDecimal(test_case.a)
        var result = func(_bdec, 50)
        try:
            testing.assert_equal(
                lhs=result,
                rhs=BigDecimal(test_case.expected),
                msg=test_case.description,
            )
        except e:
            print(
                test_case.description,
                "\n  Expected:",
                test_case.expected,
                "\n  Got:",
            )
            print(test_case.description)
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "Some test cases failed. See above for details.",
    )


def run_test_two[
    func: def(BigDecimal, BigDecimal, Int) thin raises -> BigDecimal
](toml: TOMLDocument, table_name: String, msg: String) raises:
    """Run the cases of a two-argument function, whose second operand is `b`."""
    var test_cases = load_test_cases(toml, table_name)
    var count_wrong = 0
    for test_case in test_cases:
        var result = func(BigDecimal(test_case.a), BigDecimal(test_case.b), 50)
        try:
            testing.assert_equal(
                lhs=result,
                rhs=BigDecimal(test_case.expected),
                msg=test_case.description,
            )
        except e:
            print(
                test_case.description,
                "\n  Expected:",
                test_case.expected,
                "\n  Got:",
                result,
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "Some test cases failed. See above for details.",
    )


def test_bigdecimal_trignometric() raises:
    # Load test cases from TOML file
    var toml = parse_file(file_path)

    run_test[func=decimo.bigdecimal.trigonometric.sin](
        toml,
        "sin_tests",
        "sin",
    )
    run_test[func=decimo.bigdecimal.trigonometric.cos](
        toml,
        "cos_tests",
        "cos",
    )
    run_test[func=decimo.bigdecimal.trigonometric.tan](
        toml,
        "tan_tests",
        "tan",
    )
    run_test[func=decimo.bigdecimal.trigonometric.cot](
        toml,
        "cot_tests",
        "cot",
    )
    run_test[func=decimo.bigdecimal.trigonometric.arctan](
        toml,
        "arctan_tests",
        "arctan",
    )
    run_test[func=decimo.bigdecimal.trigonometric.arcsin](
        toml,
        "arcsin_tests",
        "arcsin",
    )
    run_test[func=decimo.bigdecimal.trigonometric.arccos](
        toml,
        "arccos_tests",
        "arccos",
    )
    run_test_two[func=decimo.bigdecimal.trigonometric.arctan2](
        toml,
        "arctan2_tests",
        "arctan2",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
