"""
Test BigUInt exponential functions.
"""


from std.python import Python
from std import testing
from std.testing import assert_equal, assert_true
from decimo.biguint.biguint import BigUInt
from decimo.tests import (
    TestCase,
    load_test_cases,
    parse_file,
    random_decimal_string,
)

comptime file_path_sqrt = "tests/biguint/test_data/biguint_sqrt.toml"


def _set_max_str_digits(limit: Int) raises:
    """Set Python's int-to-string digit limit (Python 3.11+). No-op if unavailable.
    """
    try:
        Python.import_module("sys").set_int_max_str_digits(limit)
    except:
        pass


def test_biguint_sqrt() raises:
    # Load test cases from TOML file
    var pymath = Python.import_module("math")
    _set_max_str_digits(25000)

    var toml = parse_file(file_path_sqrt)
    var test_cases: List[TestCase]

    # -------------------------------------------------------
    # Testing BigUInt sqrt
    # -------------------------------------------------------

    test_cases = load_test_cases[unary=True](toml, "sqrt_tests")
    assert_true(len(test_cases) > 0, "No sqrt test cases found")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigUInt(test_case.a).sqrt()
        var mojo_str = String(result)
        var py_str = String(pymath.isqrt(Python.int(test_case.a)))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    assert_equal(
        count_wrong,
        0,
        "sqrt: Mojo and Python results differ. See above.",
    )


def test_biguint_sqrt_random_numbers_against_python() raises:
    # print("------------------------------------------------------")
    # print("Testing BigUInt sqrt on random numbers with python...")

    var pymath = Python.import_module("math")
    _set_max_str_digits(25000)

    var number_a: String
    var decimo_result: String
    var python_result: String

    for _test_case in range(10):
        number_a = random_decimal_string(666)
        decimo_result = String(BigUInt(number_a).sqrt())
        python_result = String(pymath.isqrt(Python.int(number_a)))
        assert_equal(
            lhs=decimo_result,
            rhs=python_result,
            msg="Python int isqrt does not match BigUInt sqrt\n"
            + "number a: \n"
            + number_a
            + "\n\nDecimo BigUInt sqrt: \n"
            + decimo_result
            + "\n\nPython int sqrt: \n"
            + python_result,
        )
    # print("BigUInt sqrt tests passed!")


def main() raises:
    # test_biguint_sqrt()
    # test_biguint_sqrt_random_numbers_against_python()
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
    # print("All BigUInt exponential tests passed!")
    # print("------------------------------------------------------")
