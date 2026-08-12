"""
Test BigInt10 arithmetic operations including addition, subtraction, and negation.
"""

from std.python import Python
from std import testing
from decimo.bigint10.bigint10 import BigInt10
from decimo.tests import TestCase, parse_file, load_test_cases

comptime file_path_arithmetics = (
    "tests/bigint10/test_data/bigint10_arithmetics.toml"
)
comptime file_path_multiply = "tests/bigint10/test_data/bigint10_multiply.toml"
comptime file_path_floor_divide = (
    "tests/bigint10/test_data/bigint10_floor_divide.toml"
)
comptime file_path_truncate_divide = (
    "tests/bigint10/test_data/bigint10_truncate_divide.toml"
)


def _set_max_str_digits(limit: Int) raises:
    """Set Python's int-to-string digit limit (Python 3.11+). No-op if unavailable.
    """
    try:
        Python.import_module("sys").set_int_max_str_digits(limit)
    except:
        pass


def test_bigint10_arithmetics() raises:
    # Load test cases from TOML file
    var pybuiltins = Python.import_module("builtins")
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_arithmetics)
    var test_cases: List[TestCase]

    # -------------------------------------------------------
    # Testing BigInt10 addition
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "addition_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt10(test_case.a) + BigInt10(test_case.b)
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
    testing.assert_equal(
        count_wrong,
        0,
        "Addition: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigInt10 subtraction
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "subtraction_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BigInt10(test_case.a) - BigInt10(test_case.b)
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
    testing.assert_equal(
        count_wrong,
        0,
        "Subtraction: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigInt10 negation
    # -------------------------------------------------------

    test_cases = load_test_cases[unary=True](toml, "negation_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = -BigInt10(test_case.a)
        var mojo_str = String(result)
        var py_str = String(-Python.int(test_case.a))
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
    testing.assert_equal(
        count_wrong,
        0,
        "Negation: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigInt10 absolute value
    # -------------------------------------------------------

    test_cases = load_test_cases[unary=True](toml, "abs_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = abs(BigInt10(test_case.a))
        var mojo_str = String(result)
        var py_str = String(pybuiltins.abs(Python.int(test_case.a)))
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
    testing.assert_equal(
        count_wrong,
        0,
        "Abs: Mojo and Python results differ. See above.",
    )


def test_bigint10_multiply() raises:
    # Load test cases from TOML file
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_multiply)
    var test_cases: List[TestCase]

    # -------------------------------------------------------
    # Testing BigInt10 multiplication
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "multiplication_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt10(test_case.a) * BigInt10(test_case.b)
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
    testing.assert_equal(
        count_wrong,
        0,
        "Multiplication: Mojo and Python results differ. See above.",
    )


def test_bigint10_floor_divide() raises:
    # Load test cases from TOML file
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_floor_divide)
    var test_cases: List[TestCase]

    # -------------------------------------------------------
    # Testing BigInt10 floor division
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "floor_divide_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt10(test_case.a) // BigInt10(test_case.b)
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
    testing.assert_equal(
        count_wrong,
        0,
        "Floor divide: Mojo and Python results differ. See above.",
    )


def test_bigint10_truncate_divide() raises:
    # Load test cases from TOML file
    var pybuiltins = Python.import_module("builtins")
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_truncate_divide)
    var test_cases: List[TestCase]

    # -------------------------------------------------------
    # Testing BigInt10 truncate division
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "truncate_divide_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt10(test_case.a).truncate_divide(
            BigInt10(test_case.b)
        )
        var mojo_str = String(result)
        # Truncation division: sign(a/b) * (|a| // |b|)
        var pa = Python.int(test_case.a)
        var pb = Python.int(test_case.b)
        var abs_q = pybuiltins.abs(pa) // pybuiltins.abs(pb)
        var py_q = abs_q
        if Bool(pa < 0) != Bool(pb < 0):
            py_q = -abs_q
        var py_str = String(py_q)
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
    testing.assert_equal(
        count_wrong,
        0,
        "Truncate divide: Mojo and Python results differ. See above.",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
