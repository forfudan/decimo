"""
Test BigDecimal exponential operations (sqrt and ln) against Python's decimal module.

Root and power tests are in test_bigdecimal_exponential_toml.mojo (compared
against TOML expected values), because Python's Decimal cannot compute most
non-integer exponents.
"""

from std.python import Python
from std import testing

from decimo import BDec
import decimo.bigdecimal.exponential as bigdecimal_exponential
from decimo.tests import TestCase, parse_file, load_test_cases

comptime file_path = "tests/bigdecimal/test_data/bigdecimal_exponential.toml"


def test_bigdecimal_exponential() raises:
    # Load test cases from TOML file
    var pydecimal = Python.import_module("decimal")
    pydecimal.getcontext().prec = 28
    var toml = parse_file(file_path)
    var test_cases: List[TestCase]

    # -------------------------------------------------------
    # Testing BigDecimal square root
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "sqrt_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a).sqrt(precision=28)
        var mojo_str = String(result)
        var py_str = String(pydecimal.Decimal(test_case.a).sqrt())
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
        "sqrt: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal natural logarithm (ln)
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "ln_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a).ln(precision=28)
        var mojo_str = String(result)
        var py_str = String(pydecimal.Decimal(test_case.a).ln())
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
        "ln: Mojo and Python results differ. See above.",
    )


def test_sqrt_multi_precision() raises:
    """Test sqrt at various precisions against Python's decimal module.

    Exercises both perfect squares (whose natural digit count may exceed the
    requested precision) and irrationals at precisions 1, 2, 3, 5, 10, 28, 50.
    This catches the bug where exact results skip rounding and return more
    significant digits than requested.
    """
    var pydecimal = Python.import_module("decimal")

    # Inputs: perfect squares, decimal perfect squares, irrationals, sci notation
    var inputs = [
        "0",
        "1",
        "4",
        "9",
        "25",
        "100",
        "10000",
        "90000",
        "0.25",
        "0.01",
        "2.25",
        "2",
        "3",
        "5",
        "10",
        "0.5",
        "1E+10",
        "1E-10",
        "1E+100",
        "1E-100",
    ]

    var precisions = [1, 2, 3, 5, 10, 28, 50]

    var count_wrong = 0
    for i in range(len(inputs)):
        for j in range(len(precisions)):
            var prec = precisions[j]
            pydecimal.getcontext().prec = prec
            var our_result = String(BDec(inputs[i]).sqrt(precision=prec))
            var py_result = String(pydecimal.Decimal(inputs[i]).sqrt())
            try:
                testing.assert_equal(
                    lhs=our_result,
                    rhs=py_result,
                    msg="sqrt(" + inputs[i] + ") at precision=" + String(prec),
                )
            except e:
                print(
                    "FAIL: sqrt("
                    + inputs[i]
                    + ") at precision="
                    + String(prec),
                    "\n  Expected (Python):",
                    py_result,
                    "\n  Got (Decimo):   ",
                    our_result,
                )
                count_wrong += 1

    # Restore default precision
    pydecimal.getcontext().prec = 28
    testing.assert_equal(
        count_wrong,
        0,
        "Some multi-precision sqrt test cases failed. See above for details.",
    )


def test_negative_sqrt() raises:
    """Test that square root of negative number raises an error."""
    var negative_number = BDec("-1")

    var exception_caught: Bool
    try:
        _ = negative_number.sqrt(precision=28)
        exception_caught = False
    except:
        exception_caught = True

    testing.assert_true(
        exception_caught, "Square root of negative number should raise an error"
    )


def test_ln_invalid_inputs() raises:
    """Test that natural logarithm with invalid inputs raises appropriate errors.
    """
    # Test 1: ln of zero should raise an error
    var zero = BDec("0")
    var exception_caught: Bool
    try:
        _ = zero.ln()
        exception_caught = False
    except:
        exception_caught = True
    testing.assert_true(exception_caught, "ln(0) should raise an error")

    # Test 2: ln of negative number should raise an error
    var negative = BDec("-1")
    try:
        _ = negative.ln()
        exception_caught = False
    except:
        exception_caught = True
    testing.assert_true(
        exception_caught, "ln of negative number should raise an error"
    )


def test_sqrt_reciprocal_matches_sqrt_exact() raises:
    """Test that `sqrt_reciprocal()` delivers every digit it is asked for.

    `sqrt_exact()` is the oracle here: it reproduces CPython's
    `Decimal.sqrt()`, which the tests above check directly.

    Both the inputs and the precisions are swept rather than spot-checked. A
    reciprocal-sqrt iteration only doubles the number of correct digits, so `n`
    iterations reach `seed * 2^n` and nothing caps them at the precision each
    iteration nominally runs at. Two separate regressions therefore hide here,
    and both are invisible to a spot check: one shows up only at precisions
    where the halving schedule lands with little slack (1500 and 3000 here, but
    not 1000 or 2000), and the other only for inputs whose `Float64` seed is
    poor - `sqrt_reciprocal(1234.5678, 1500)` was correct to 1248 of 1500
    digits while `sqrt_reciprocal(10005, 1500)` was correct in full, because
    `12.345678 ** -0.5` is accurate to ten digits and `1.0005 ** -0.5` is
    exact. Neither raises, and both return the full requested digit count.
    """
    var inputs = ["10005", "2", "1234.5678"]
    var precisions = [20, 50, 100, 200, 400, 800, 1000, 1009, 1500, 2000, 3000]

    for i in range(len(inputs)):
        var x = BDec(inputs[i])
        for j in range(len(precisions)):
            var prec = precisions[j]
            var got = List[Byte](
                String(
                    bigdecimal_exponential.sqrt_reciprocal(x, prec)
                ).as_bytes()
            )
            var want = List[Byte](
                String(bigdecimal_exponential.sqrt_exact(x, prec)).as_bytes()
            )

            var agree = 0
            while (
                agree < len(got)
                and agree < len(want)
                and got[agree] == want[agree]
            ):
                agree += 1

            # The two round the final digit differently (half-up against
            # half-even), so only the last digit is allowed to differ.
            testing.assert_true(
                agree >= len(want) - 1,
                String("sqrt_reciprocal(")
                + inputs[i]
                + String(", ")
                + String(prec)
                + String(") agrees with sqrt_exact() for only ")
                + String(agree)
                + String(" of ")
                + String(len(want))
                + String(" characters"),
            )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
