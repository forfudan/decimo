"""
Tests BigDecimal trigonometric functions.
"""

from std.python import Python
from std import testing

from decimo import BigDecimal
from decimo.tests import TestCase, parse_file, load_test_cases
from decimo.toml.parser import TOMLDocument
import decimo.bigdecimal.trigonometric

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


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
