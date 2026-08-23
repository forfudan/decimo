"""
Test BigInt arithmetic operations including addition, subtraction,
negation, multiplication, floor division, and truncate division.

Reuses TOML test data from the BigInt10 test suite, since the test cases
use decimal string representations that are valid for both BigInt10 and BigInt.
"""

from std.python import Python
from std import testing
from decimo.bigint.bigint import BigInt
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

# BigUInt TOML test data (unsigned, all positive values)
comptime file_path_biguint_arithmetics = (
    "tests/biguint/test_data/biguint_arithmetics.toml"
)
comptime file_path_biguint_truncate_divide = (
    "tests/biguint/test_data/biguint_truncate_divide.toml"
)


def _set_max_str_digits(limit: Int) raises:
    """Set Python's int-to-string digit limit (Python 3.11+). No-op if unavailable.
    """
    try:
        Python.import_module("sys").set_int_max_str_digits(limit)
    except:
        pass


def test_bigint_addition() raises:
    """Test BigInt addition using shared TOML test data."""
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_arithmetics)
    var test_cases = load_test_cases(toml, "addition_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt(test_case.a) + BigInt(test_case.b)
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


def test_bigint_subtraction() raises:
    """Test BigInt subtraction using shared TOML test data."""
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_arithmetics)
    var test_cases = load_test_cases(toml, "subtraction_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt(test_case.a) - BigInt(test_case.b)
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


def test_bigint_negation() raises:
    """Test BigInt negation using shared TOML test data."""
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_arithmetics)
    var test_cases = load_test_cases[unary=True](toml, "negation_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = -BigInt(test_case.a)
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


def test_bigint_abs() raises:
    """Test BigInt absolute value using shared TOML test data."""
    var pybuiltins = Python.import_module("builtins")
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_arithmetics)
    var test_cases = load_test_cases[unary=True](toml, "abs_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = abs(BigInt(test_case.a))
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


def test_bigint_multiply() raises:
    """Test BigInt multiplication using shared TOML test data."""
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_multiply)
    var test_cases = load_test_cases(toml, "multiplication_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt(test_case.a) * BigInt(test_case.b)
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


def test_bigint_floor_divide() raises:
    """Test BigInt floor division using shared TOML test data."""
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_floor_divide)
    var test_cases = load_test_cases(toml, "floor_divide_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt(test_case.a) // BigInt(test_case.b)
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


def test_bigint_truncate_divide() raises:
    """Test BigInt truncate division using shared TOML test data."""
    var pybuiltins = Python.import_module("builtins")
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_truncate_divide)
    var test_cases = load_test_cases(toml, "truncate_divide_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt(test_case.a).truncate_divide(BigInt(test_case.b))
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


def test_bigint_comparison() raises:
    """Test BigInt comparison operators."""
    # Basic comparisons
    var a = BigInt(42)
    var b = BigInt(100)
    var c = BigInt(-50)
    var d = BigInt(42)
    var zero = BigInt(0)

    # Equality
    testing.assert_true(a == d, "42 == 42")
    testing.assert_true(not (a == b), "42 != 100")
    testing.assert_true(a != b, "42 != 100")
    testing.assert_true(zero == BigInt(0), "0 == 0")

    # Less than
    testing.assert_true(a < b, "42 < 100")
    testing.assert_true(c < a, "-50 < 42")
    testing.assert_true(c < zero, "-50 < 0")
    testing.assert_true(not (b < a), "not (100 < 42)")

    # Greater than
    testing.assert_true(b > a, "100 > 42")
    testing.assert_true(a > c, "42 > -50")
    testing.assert_true(zero > c, "0 > -50")

    # Less than or equal
    testing.assert_true(a <= d, "42 <= 42")
    testing.assert_true(a <= b, "42 <= 100")

    # Greater than or equal
    testing.assert_true(a >= d, "42 >= 42")
    testing.assert_true(b >= a, "100 >= 42")

    # Comparisons with Int
    testing.assert_true(a == 42, "BigInt(42) == 42")
    testing.assert_true(a != 100, "BigInt(42) != 100")
    testing.assert_true(a < 100, "BigInt(42) < 100")
    testing.assert_true(a > 0, "BigInt(42) > 0")
    testing.assert_true(a <= 42, "BigInt(42) <= 42")
    testing.assert_true(a >= 42, "BigInt(42) >= 42")

    # Large number comparisons
    var large1 = BigInt("999999999999999999999999999999")
    var large2 = BigInt("1000000000000000000000000000000")
    testing.assert_true(large1 < large2, "30-digit < 31-digit")
    testing.assert_true(large2 > large1, "31-digit > 30-digit")

    # Negative number comparisons
    var neg1 = BigInt(-100)
    var neg2 = BigInt(-200)
    testing.assert_true(neg2 < neg1, "-200 < -100")
    testing.assert_true(neg1 > neg2, "-100 > -200")


def test_bigint_division_by_zero() raises:
    """Test that division by zero raises an error."""
    var a = BigInt(42)
    var zero = BigInt(0)
    var raised = False

    try:
        _ = a // zero
    except:
        raised = True

    testing.assert_true(raised, "Floor division by zero should raise")

    raised = False
    try:
        _ = a.truncate_divide(zero)
    except:
        raised = True

    testing.assert_true(raised, "Truncate division by zero should raise")

    raised = False
    try:
        _ = a / zero
    except:
        raised = True

    testing.assert_true(raised, "True division by zero should raise")


def test_bigint_true_divide_operator() raises:
    """Test `/` on BigInt: closed, truncating toward zero, as Mojo's `Int` is.

    `/` and `//` are different operations on an integer type and agree only
    when the operands share a sign, so both halves are checked here.
    """
    # Exact quotients: the sign rule is invisible, both operators agree.
    testing.assert_equal(String(BigInt(6) / BigInt(3)), "2", "6 / 3")
    testing.assert_equal(String(BigInt(-6) / BigInt(3)), "-2", "-6 / 3")
    testing.assert_equal(String(BigInt(6) / BigInt(-3)), "-2", "6 / -3")
    testing.assert_equal(String(BigInt(-6) / BigInt(-3)), "2", "-6 / -3")

    # Inexact and same-signed: truncation and flooring coincide.
    testing.assert_equal(String(BigInt(7) / BigInt(2)), "3", "7 / 2")
    testing.assert_equal(String(BigInt(-7) / BigInt(-2)), "3", "-7 / -2")
    testing.assert_equal(String(BigInt(7) // BigInt(2)), "3", "7 // 2")

    # Inexact and mixed-signed: this is where the two operators part ways.
    testing.assert_equal(String(BigInt(-7) / BigInt(2)), "-3", "-7 / 2")
    testing.assert_equal(String(BigInt(7) / BigInt(-2)), "-3", "7 / -2")
    testing.assert_equal(String(BigInt(-7) // BigInt(2)), "-4", "-7 // 2")
    testing.assert_equal(String(BigInt(7) // BigInt(-2)), "-4", "7 // -2")

    # Magnitude smaller than the divisor truncates to zero, not to -1.
    testing.assert_equal(String(BigInt(-1) / BigInt(2)), "0", "-1 / 2")
    testing.assert_equal(String(BigInt(-1) // BigInt(2)), "-1", "-1 // 2")

    # Zero dividend keeps a positive sign whatever the divisor's sign.
    var zero_quotient = BigInt(0) / BigInt(-5)
    testing.assert_equal(String(zero_quotient), "0", "0 / -5")
    testing.assert_equal(
        zero_quotient.sign, False, "0 / -5 must not be a negative zero"
    )

    # Values past 64 bits take the general path rather than a fast one.
    var big = BigInt("123456789012345678901234567891")
    testing.assert_equal(
        String(-big / BigInt(7)),
        "-17636684144620811271604938270",
        "-big / 7 truncates toward zero",
    )
    testing.assert_equal(
        String(-big // BigInt(7)),
        "-17636684144620811271604938271",
        "-big // 7 floors",
    )


def test_bigint_true_divide_matches_truncate_divide() raises:
    """`/` is the operator spelling of `truncate_divide`, over every sign pair.
    """
    var values: List[Int] = [-97, -12, -1, 0, 1, 12, 97]
    var divisors: List[Int] = [-11, -3, -1, 1, 3, 11]
    for a in values:
        for b in divisors:
            var lhs = BigInt(a)
            var rhs = BigInt(b)
            testing.assert_equal(
                String(lhs / rhs),
                String(lhs.truncate_divide(rhs)),
                String(a) + " / " + String(b),
            )


def test_bigint_zero_quotient_mixed_sign() raises:
    """Regression test: 0 // negative should be +0 with sign == False."""
    # Floor divide: 0 // -5
    var result_floor = BigInt(0) // BigInt(-5)
    testing.assert_equal(
        lhs=String(result_floor),
        rhs="0",
        msg="0 // -5 should produce numeric 0",
    )
    testing.assert_equal(
        lhs=result_floor.sign,
        rhs=False,
        msg="0 // -5 should have sign == False (no negative zero)",
    )

    # Truncate divide: 0 truncate_divide -5
    var result_trunc = BigInt(0).truncate_divide(BigInt(-5))
    testing.assert_equal(
        lhs=String(result_trunc),
        rhs="0",
        msg="0 truncate_divide -5 should produce numeric 0",
    )
    testing.assert_equal(
        lhs=result_trunc.sign,
        rhs=False,
        msg="0 truncate_divide -5 should have sign == False (no negative zero)",
    )

    # Floor divide: 0 // -1
    var result_neg1 = BigInt(0) // BigInt(-1)
    testing.assert_equal(
        lhs=String(result_neg1),
        rhs="0",
        msg="0 // -1 should produce numeric 0",
    )
    testing.assert_equal(
        lhs=result_neg1.sign,
        rhs=False,
        msg="0 // -1 should have sign == False (no negative zero)",
    )


def test_bigint_augmented_assignment() raises:
    """Test augmented assignment operators (+=, -=, *=)."""
    var a = BigInt(100)

    a += BigInt(50)
    testing.assert_equal(lhs=String(a), rhs="150", msg="+= test")

    a -= BigInt(30)
    testing.assert_equal(lhs=String(a), rhs="120", msg="-= test")

    a *= BigInt(3)
    testing.assert_equal(lhs=String(a), rhs="360", msg="*= test")


# ===----------------------------------------------------------------------=== #
# Additional tests from BigUInt TOML data (unsigned / positive only)
# ===----------------------------------------------------------------------=== #


def test_bigint_biguint_addition() raises:
    """Test BigInt addition with BigUInt TOML test data (all positive)."""
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_biguint_arithmetics)
    var test_cases = load_test_cases(toml, "addition_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt(test_case.a) + BigInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) + Python.int(test_case.b))
        if mojo_str != py_str:
            print(
                "[biguint] " + test_case.description,
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
        "[biguint] Addition: Mojo and Python results differ. See above.",
    )


def test_bigint_biguint_subtraction() raises:
    """Test BigInt subtraction with BigUInt TOML test data (a >= b cases)."""
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_biguint_arithmetics)
    var test_cases = load_test_cases(toml, "subtraction_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt(test_case.a) - BigInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) - Python.int(test_case.b))
        if mojo_str != py_str:
            print(
                "[biguint] " + test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1

    # Also test the extreme_subtraction_tests section
    var extreme_cases = load_test_cases(toml, "extreme_subtraction_tests")
    for test_case in extreme_cases:
        var result = BigInt(test_case.a) - BigInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) - Python.int(test_case.b))
        if mojo_str != py_str:
            print(
                "[biguint extreme] " + test_case.description,
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
        "[biguint] Subtraction: Mojo and Python results differ. See above.",
    )


def test_bigint_biguint_subtraction_underflow() raises:
    """Test that BigInt handles subtraction underflow (smaller - larger).

    Unlike BigUInt which errors, BigInt should return a negative result.
    """
    # 123 - 456 = -333 for signed BigInt
    var result = BigInt("123") - BigInt("456")
    testing.assert_equal(
        lhs=String(result),
        rhs="-333",
        msg="[biguint underflow] BigInt handles smaller - larger correctly",
    )


def test_bigint_floor_divide_burnikel_ziegler() raises:
    """Test floor division with large operands that exercise the
    Burnikel-Ziegler dispatch path (divisor > 64 words ≈ 617 digits).

    Uses BigInt arithmetic to construct operands, then verifies:
      a == q * b + r, 0 <= r < |b|, and sign correctness.
    """

    # --- Case 1: 1200-digit / 700-digit ---
    # a = 10^1199 + 7, b = 10^699 + 3
    var b1 = BigInt(10).power(699) + BigInt(3)
    var a1 = BigInt(10).power(1199) + BigInt(7)
    var q1 = a1 // b1
    var r1 = a1 - q1 * b1
    # Euclidean identity (numeric, not string-based)
    testing.assert_true(
        q1 * b1 + r1 == a1,
        msg="[B-Z case 1] a == q*b + r (1200-digit / 700-digit)",
    )
    # Remainder in range [0, b)
    testing.assert_true(
        r1 >= BigInt(0) and r1 < b1,
        msg="[B-Z case 1] 0 <= r < b",
    )
    # Cross-check D&C string conversion against BigInt10 path
    testing.assert_equal(
        lhs=String(a1),
        rhs=String(BigInt10.from_bigint(a1)),
        msg="[B-Z case 1] D&C to_string matches BigInt10 path",
    )

    # --- Case 2: 2000-digit / 1000-digit ---
    # a = 2*10^1999 + 13, b = 3*10^999 + 17
    var b2 = BigInt(3) * BigInt(10).power(999) + BigInt(17)
    var a2 = BigInt(2) * BigInt(10).power(1999) + BigInt(13)
    var q2 = a2 // b2
    var r2 = a2 - q2 * b2
    testing.assert_true(
        q2 * b2 + r2 == a2,
        msg="[B-Z case 2] a == q*b + r (2000-digit / 1000-digit)",
    )
    testing.assert_true(
        r2 >= BigInt(0) and r2 < b2,
        msg="[B-Z case 2] 0 <= r < b",
    )
    testing.assert_equal(
        lhs=String(a2),
        rhs=String(BigInt10.from_bigint(a2)),
        msg="[B-Z case 2] D&C to_string matches BigInt10 path",
    )

    # --- Case 3: Negative / Positive (floor semantics) ---
    # a = -(10^800 + 11), b = 10^650 + 7
    # Floor division: q rounds toward -inf, r = a - q*b >= 0
    var b3 = BigInt(10).power(650) + BigInt(7)
    var a3 = -(BigInt(10).power(800) + BigInt(11))
    var q3 = a3 // b3
    var r3 = a3 - q3 * b3
    testing.assert_true(
        q3 * b3 + r3 == a3,
        msg="[B-Z case 3] a == q*b + r (negative / positive)",
    )
    testing.assert_true(
        r3 >= BigInt(0) and r3 < b3,
        msg="[B-Z case 3] 0 <= r < b (floor semantics)",
    )
    # Quotient should be negative
    testing.assert_true(
        q3 < BigInt(0),
        msg="[B-Z case 3] q < 0 for negative/positive",
    )

    # --- Case 4: Nearly equal sizes (700-digit / 700-digit) ---
    # a = 9*10^699 + 123456789, b = 5*10^699 + 987654321
    # Quotient should be 1
    var b4 = BigInt(5) * BigInt(10).power(699) + BigInt(987654321)
    var a4 = BigInt(9) * BigInt(10).power(699) + BigInt(123456789)
    var q4 = a4 // b4
    var r4 = a4 - q4 * b4
    testing.assert_true(
        q4 * b4 + r4 == a4,
        msg="[B-Z case 4] a == q*b + r (700-digit / 700-digit)",
    )
    testing.assert_equal(
        lhs=String(q4),
        rhs="1",
        msg="[B-Z case 4] quotient is 1 when a/b ≈ 1.8",
    )


def test_bigint_biguint_multiplication() raises:
    """Test BigInt multiplication with BigUInt TOML test data (all positive)."""
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_biguint_arithmetics)
    var test_cases = load_test_cases(toml, "multiplication_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt(test_case.a) * BigInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) * Python.int(test_case.b))
        if mojo_str != py_str:
            print(
                "[biguint] " + test_case.description,
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
        "[biguint] Multiplication: Mojo and Python differ. See above.",
    )


def test_bigint_biguint_truncate_divide() raises:
    """Test BigInt truncate division with BigUInt TOML test data (all positive).
    """
    _set_max_str_digits(500000)
    var toml = parse_file(file_path_biguint_truncate_divide)
    var test_cases = load_test_cases(toml, "truncate_divide_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigInt(test_case.a).truncate_divide(BigInt(test_case.b))
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) // Python.int(test_case.b))
        if mojo_str != py_str:
            print(
                "[biguint] " + test_case.description,
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
        "[biguint] Truncate divide: Mojo and Python differ. See above.",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
