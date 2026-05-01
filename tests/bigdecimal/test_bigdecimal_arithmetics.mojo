"""
Test BigDecimal arithmetic operations including:

1. addition
2. subtraction
3. multiplication
4. division
"""

from std.python import Python
from std import testing

from decimo import BDec
from decimo.bigdecimal.arithmetics import add, subtract, multiply
from decimo.bigdecimal.rounding import round_to_precision
from decimo.rounding_mode import RoundingMode
from decimo.tests import TestCase, parse_file, load_test_cases

comptime file_path = "tests/bigdecimal/test_data/bigdecimal_arithmetics.toml"


def test_bigdecimal_arithmetics() raises:
    # Load test cases from TOML file
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)
    var test_cases: List[TestCase]

    # BigDecimal add/sub/mul are exact (unlimited precision).
    # Set Python context precision high so Python doesn't round.
    pydecimal.getcontext().prec = 500

    # -------------------------------------------------------
    # Testing BigDecimal addition
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "addition_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a) + BDec(test_case.b)
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a) + pydecimal.Decimal(test_case.b)
        )
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
    # Testing BigDecimal subtraction
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "subtraction_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a) - BDec(test_case.b)
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a) - pydecimal.Decimal(test_case.b)
        )
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
    # Testing BigDecimal multiplication
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "multiplication_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a) * BDec(test_case.b)
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a) * pydecimal.Decimal(test_case.b)
        )
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

    # -------------------------------------------------------
    # Testing BigDecimal division
    # -------------------------------------------------------

    # Division uses precision=28, so match Python's context.
    pydecimal.getcontext().prec = 28
    test_cases = load_test_cases(toml, "division_tests")
    count_wrong = 0
    for test_case in test_cases:
        var result = BDec(test_case.a).true_divide(
            BDec(test_case.b), precision=28
        )
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a) / pydecimal.Decimal(test_case.b)
        )
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
        "Division: Mojo and Python results differ. See above.",
    )


def test_bigdecimal_arithmetics_with_precision() raises:
    """Tests `add`/`subtract`/`multiply` with `precision > 0`.

    Each precision-arg call must equal `op(x1, x2, precision=0)`
    followed by an explicit `round_to_precision(..., HALF_EVEN)` on
    every input below.

    Coverage:
    - Long, same-sign operands.
    - Wide-exponent operands, mixed and same sign.
    - Close-exponent operands where leading digits can cancel
      (mixed-sign add, same-sign sub).
    - Short operands inside the precision window.
    - Equally-long operands at high digit count.
    - Asymmetric (long * short, wide-exponent) operands.
    """
    comptime PRECISION = 50

    var inputs = List[Tuple[String, String, String]]()
    inputs.append(
        Tuple[String, String, String](
            "1234567890" * 30, "9876543210" * 30, "long_same_sign"
        )
    )
    inputs.append(
        Tuple[String, String, String](
            "1.234e200", "-9.876e-50", "wide_exp_mixed_sign"
        )
    )
    inputs.append(
        Tuple[String, String, String](
            "1.234e200", "9.876e-50", "wide_exp_same_sign"
        )
    )
    inputs.append(
        Tuple[String, String, String](
            "1." + "1" * 200 + "e10",
            "-1." + "1" * 199 + "0e10",
            "cancellation_add",
        )
    )
    inputs.append(
        Tuple[String, String, String](
            "1." + "1" * 200 + "e10",
            "1." + "1" * 199 + "0e10",
            "cancellation_sub",
        )
    )
    inputs.append(
        Tuple[String, String, String]("1.5", "2.5", "short_inside_window")
    )
    inputs.append(
        Tuple[String, String, String](
            "1234567890" * 30, "7", "asymmetric_long_short"
        )
    )
    inputs.append(
        Tuple[String, String, String](
            "9.876e200", "1.234e-50", "asymmetric_wide_exp"
        )
    )

    var count_wrong = 0
    for ref item in inputs:
        var a_str = item[0]
        var b_str = item[1]
        var desc = item[2]
        var ma = BDec(a_str)
        var mb = BDec(b_str)

        # add: precision-arg fast path must equal exact-then-round.
        var add_ref = add(ma, mb, precision=0)
        round_to_precision(
            add_ref,
            PRECISION,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        var add_fast = add(ma, mb, precision=PRECISION)
        if String(add_ref) != String(add_fast):
            print(
                "add (",
                desc,
                "):\n  fast: ",
                String(add_fast),
                "\n  ref:  ",
                String(add_ref),
            )
            count_wrong += 1

        var sub_ref = subtract(ma, mb, precision=0)
        round_to_precision(
            sub_ref,
            PRECISION,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        var sub_fast = subtract(ma, mb, precision=PRECISION)
        if String(sub_ref) != String(sub_fast):
            print(
                "sub (",
                desc,
                "):\n  fast: ",
                String(sub_fast),
                "\n  ref:  ",
                String(sub_ref),
            )
            count_wrong += 1

        var mul_ref = multiply(ma, mb, precision=0)
        round_to_precision(
            mul_ref,
            PRECISION,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        var mul_fast = multiply(ma, mb, precision=PRECISION)
        if String(mul_ref) != String(mul_fast):
            print(
                "mul (",
                desc,
                "):\n  fast: ",
                String(mul_fast),
                "\n  ref:  ",
                String(mul_ref),
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong,
        0,
        "precision-arg add/sub/mul disagreed with exact-then-round.",
    )


def main() raises:
    # print("Running BigDecimal arithmetic tests")

    testing.TestSuite.discover_tests[__functions_in_module()]().run()

    # print("All BigDecimal arithmetic tests passed!")
