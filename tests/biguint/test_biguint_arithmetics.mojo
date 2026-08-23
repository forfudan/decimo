"""
Test BigUInt arithmetic operations including addition, subtraction, and multiplication.
BigUInt is an unsigned integer type, so it doesn't support negative values.
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
        number_a = random_decimal_string(123)
        number_b = random_decimal_string(45)
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


def test_biguint_truncate_divide_huge_random_numbers_against_python() raises:
    # Some two hundred thousand digits over a divisor of some fourteen
    # thousand. The smaller random cases above already clear
    # `CUTOFF_BURNIKEL_ZIEGLER` (32 words, 288 digits) and so take the
    # Burnikel-Ziegler path too; what this size adds is the depth. A divisor
    # of ~1,570 words recurses six levels deep on blocks of n = 2048 words,
    # against two levels on n = 128 for the cases above, and the dividend
    # splits into thirteen blocks, so the remainder is carried across twelve
    # iterations of the outer loop rather than two. At that block size the
    # multiplications *inside* the division cross `CUTOFF_KARATSUBA` (64) and
    # `CUTOFF_TOOM3` (256), which the smaller cases never reach. One case
    # rather than ten: the size is what is being covered, and it costs a
    # fraction of a second.

    _set_max_str_digits(500000)

    var decimo_result: String
    var python_result: String

    var number_a = random_decimal_string(12345)
    var number_b = random_decimal_string(789)
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


def _bz_digit_run(count: Int, seed: Int) -> String:
    """Builds a `count`-digit decimal string with no leading zero."""
    var out = String(1 + seed % 9)
    var x = seed
    for j in range(count - 1):
        x = (x * 1103515245 + 12345 + j) % 2147483647
        out += String(x % 10)
    return out^


def test_biguint_divide_bz_block_padding_sizes() raises:
    """Burnikel-Ziegler stays correct at every divisor block padding.

    The divisor is padded to `n = j * 2^k` words, with `2^k` the smallest
    power of two that brings the block size `j` down to the cutoff, so that
    halving `n` stays even all the way down to `j` - the recursion falls back
    to schoolbook the moment it meets an odd block size. `j` is derived from
    the divisor rather than pinned at the cutoff, which is what keeps the
    padding small; the sizes below land on different `(j, k)` pairs, including
    ones needing almost none and ones needing almost a whole block.

    `q * b + r == a` with `r < b` pins each result without a stored expected
    value.
    """
    var divisor_digits = [400, 600, 900, 1800, 3600]
    var dividend_scales = [2, 3]

    for i in range(len(divisor_digits)):
        var nb = divisor_digits[i]
        var b = BigUInt(_bz_digit_run(nb, 20260823 + i))
        for j in range(len(dividend_scales)):
            var na = nb * dividend_scales[j] // 2 + 7 * j
            var a = BigUInt(_bz_digit_run(na, 27182818 + i * 3 + j))

            var q = a // b
            var r = a - q * b
            var case_label = (
                String("a=")
                + String(na)
                + " digits, b="
                + String(nb)
                + " digits"
            )
            assert_equal(
                String(q * b + r), String(a), "q*b+r != a for " + case_label
            )
            assert_true(r < b, "remainder out of range for " + case_label)


def main() raises:
    # test_biguint_arithmetics()
    # test_biguint_truncate_divide()
    # test_biguint_truncate_divide_random_numbers_against_python()
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
    # print("All BigUInt arithmetic tests passed!")
    # print("------------------------------------------------------")
