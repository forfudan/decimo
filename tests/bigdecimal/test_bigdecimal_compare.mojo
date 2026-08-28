"""
Test BigDecimal comparison operations.
"""

from std.python import Python
from std import testing

from decimo import BDec
from decimo.bigdecimal.comparison import compare_absolute, compare
from decimo.tests import TestCase, parse_file, load_test_cases

comptime file_path = "tests/bigdecimal/test_data/bigdecimal_compare.toml"


def test_bigdecimal_compare() raises:
    # Load test cases from TOML file
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)
    var test_cases: List[TestCase]
    var count_wrong: Int

    # -------------------------------------------------------
    # Testing BigDecimal compare_absolute
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "compare_absolute_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = compare_absolute(BDec(test_case.a), BDec(test_case.b))
        var mojo_val = Int(result)
        var py_cmp = (
            pydecimal.Decimal(test_case.a)
            .copy_abs()
            .compare(pydecimal.Decimal(test_case.b).copy_abs())
        )
        var py_val = Int(py=py_cmp)
        if mojo_val != py_val:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_val,
                "\n  Python: ",
                py_val,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "compare_absolute: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal > operator
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "greater_than_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a) > BDec(test_case.b)
        var py_result = Bool(
            pydecimal.Decimal(test_case.a) > pydecimal.Decimal(test_case.b)
        )
        if result != py_result:
            print(
                test_case.description,
                "\n  Mojo:   ",
                result,
                "\n  Python: ",
                py_result,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        ">: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal < operator
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "less_than_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a) < BDec(test_case.b)
        var py_result = Bool(
            pydecimal.Decimal(test_case.a) < pydecimal.Decimal(test_case.b)
        )
        if result != py_result:
            print(
                test_case.description,
                "\n  Mojo:   ",
                result,
                "\n  Python: ",
                py_result,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "<: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal >= operator
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "greater_than_or_equal_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a) >= BDec(test_case.b)
        var py_result = Bool(
            pydecimal.Decimal(test_case.a) >= pydecimal.Decimal(test_case.b)
        )
        if result != py_result:
            print(
                test_case.description,
                "\n  Mojo:   ",
                result,
                "\n  Python: ",
                py_result,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        ">=: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal <= operator
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "less_than_or_equal_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a) <= BDec(test_case.b)
        var py_result = Bool(
            pydecimal.Decimal(test_case.a) <= pydecimal.Decimal(test_case.b)
        )
        if result != py_result:
            print(
                test_case.description,
                "\n  Mojo:   ",
                result,
                "\n  Python: ",
                py_result,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "<=: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal == operator
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "equal_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a) == BDec(test_case.b)
        var py_result = Bool(
            pydecimal.Decimal(test_case.a) == pydecimal.Decimal(test_case.b)
        )
        if result != py_result:
            print(
                test_case.description,
                "\n  Mojo:   ",
                result,
                "\n  Python: ",
                py_result,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "==: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal != operator
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "not_equal_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a) != BDec(test_case.b)
        var py_result = Bool(
            pydecimal.Decimal(test_case.a) != pydecimal.Decimal(test_case.b)
        )
        if result != py_result:
            print(
                test_case.description,
                "\n  Mojo:   ",
                result,
                "\n  Python: ",
                py_result,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "!=: Mojo and Python results differ. See above.",
    )


def test_the_comparison_operators_agree_with_each_other() raises:
    """Every pair satisfies trichotomy, and the derived operators follow.

    The cases above check each operator against Python one at a time, from a
    table. What they cannot see is the operators disagreeing among themselves
    -- `a < b` and `a == b` both true, or `a <= b` not matching `a < b or
    a == b`. The values below are chosen so that equal numbers arrive with
    different scales, which is where an ordering built on the coefficient
    rather than the value comes apart.
    """
    var values: List[String] = [
        "0",
        "-0",
        "0.0",
        "-0.00",
        "0E+5",
        "0E-5",
        "1",
        "1.0",
        "1.00",
        "1E+0",
        "-1",
        "0.1",
        "0.10",
        "1E-1",
        "10",
        "1E+1",
        "1.5",
        "-1.5",
        "999999999999999999",
        "1000000000000000000",
        "1000000000000000001",
        "-1000000000000000000",
        "1E+300",
        "1E-300",
        "-1E+300",
        "123456789012345678901234567890",
        "123456789012345678901234567891",
    ]

    for left_text in values:
        for right_text in values:
            var a = BDec(left_text)
            var b = BDec(right_text)
            var context = left_text + " against " + right_text

            var holds = Int(a < b) + Int(a == b) + Int(a > b)
            testing.assert_equal(holds, 1, "trichotomy failed for " + context)
            testing.assert_equal(
                a <= b, a < b or a == b, "<= disagrees for " + context
            )
            testing.assert_equal(
                a >= b, a > b or a == b, ">= disagrees for " + context
            )
            testing.assert_equal(
                a != b, not (a == b), "!= disagrees for " + context
            )
            testing.assert_equal(
                a < b, b > a, "the reversed operator disagrees for " + context
            )


def main() raises:
    # print("Running BigDecimal comparison tests")

    # Run compare_absolute tests
    testing.TestSuite.discover_tests[__functions_in_module()]().run()

    # print("All BigDecimal comparison tests passed!")
