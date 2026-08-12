"""
Test BigUInt arithmetic operations including addition, subtraction, and multiplication.
BigUInt is an unsigned integer type, so it doesn't support negative values.
"""


from std.python import Python
from std.random import random_ui64
from std import testing
from std.testing import assert_equal, assert_true
from decimo.biguint.biguint import BigUInt
from decimo.tests import TestCase, parse_file, load_test_cases

comptime file_path_arithmetics = (
    "tests/biguint/test_data/biguint_arithmetics.toml"
)
comptime file_path_truncate_divide = (
    "tests/biguint/test_data/biguint_truncate_divide.toml"
)


def _set_max_str_digits(limit: Int) raises:
    """Set Python's int-to-string digit limit (Python 3.11+). No-op if unavailable.
    """
    try:
        Python.import_module("sys").set_int_max_str_digits(limit)
    except:
        pass


def test_biguint_arithmetics() raises:
    # Load test cases from TOML file
    _set_max_str_digits(500000)

    var toml = parse_file(file_path_arithmetics)
    var test_cases: List[TestCase]

    # -------------------------------------------------------
    # Testing BigUInt addition
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "addition_tests")
    assert_true(len(test_cases) > 0, "No addition test cases found")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigUInt(test_case.a) + BigUInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) + Python.int(test_case.b))
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
        "Addition: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigUInt inplace addition
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "addition_tests")
    assert_true(len(test_cases) > 0, "No inplace addition test cases found")
    count_wrong = 0
    for test_case in test_cases:
        var result = BigUInt(test_case.a)
        result += BigUInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) + Python.int(test_case.b))
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
        "Inplace addition: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigUInt subtraction
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "subtraction_tests")
    assert_true(len(test_cases) > 0, "No subtraction test cases found")
    count_wrong = 0
    for test_case in test_cases:
        var result = BigUInt(test_case.a) - BigUInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) - Python.int(test_case.b))
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
        "Subtraction: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigUInt multiplication
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "multiplication_tests")
    assert_true(len(test_cases) > 0, "No multiplication test cases found")
    count_wrong = 0
    for test_case in test_cases:
        var result = BigUInt(test_case.a) * BigUInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) * Python.int(test_case.b))
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
        "Multiplication: Mojo and Python results differ. See above.",
    )

    # Special case: Test underflow handling
    test_cases = load_test_cases(toml, "subtraction_underflow")
    assert_true(len(test_cases) > 0, "No underflow test cases found")
    for test_case in test_cases:
        try:
            var result = BigUInt(test_case.a) - BigUInt(test_case.b)
            print(
                "Implementation allows underflow, result is: " + String(result)
            )
        except:
            print("Implementation correctly throws error on underflow")


def test_biguint_truncate_divide() raises:
    # Load test cases from TOML file
    _set_max_str_digits(500000)

    var toml = parse_file(file_path_truncate_divide)
    var test_cases: List[TestCase]

    # -------------------------------------------------------
    # Testing BigUInt truncate division
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "truncate_divide_tests")
    assert_true(len(test_cases) > 0, "No truncate division test cases found")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigUInt(test_case.a) // BigUInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) // Python.int(test_case.b))
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
        "Truncate divide: Mojo and Python results differ. See above.",
    )


def test_biguint_truncate_divide_random_numbers_against_python() raises:
    # print("------------------------------------------------------")
    # print("Testing BigUInt truncate division on random numbers with python...")

    _set_max_str_digits(500000)

    var number_a: String
    var number_b: String
    var decimo_result: String
    var python_result: String

    for _test_case in range(10):
        number_a = String("")
        number_b = String("")
        for _i in range(12345):
            number_a += String(random_ui64(0, 999_999_999_999_999_999))
        for _i in range(789):
            number_b += String(random_ui64(0, 999_999_999_999_999_999))
        decimo_result = String(BigUInt(number_a) // BigUInt(number_b))
        python_result = String(Python.int(number_a) // Python.int(number_b))
        assert_equal(
            lhs=decimo_result,
            rhs=python_result,
            msg="Python int division does not match BigUInt division\n"
            + "number a: \n"
            + number_a
            + "\n\nnumber b: \n"
            + number_b
            + "\n\nDecimo BigUInt division: \n"
            + decimo_result
            + "\n\nPython int division: \n"
            + python_result,
        )
    # print("BigUInt truncate division tests passed!")


def main() raises:
    # test_biguint_arithmetics()
    # test_biguint_truncate_divide()
    # test_biguint_truncate_divide_random_numbers_against_python()
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
    # print("All BigUInt arithmetic tests passed!")
    # print("------------------------------------------------------")
