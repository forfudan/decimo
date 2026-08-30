"""Test the evaluator: end-to-end expression evaluation with BigDecimal."""

from std import testing
from std.collections import Dict

from decimo.expression import (
    evaluate,
    tokenize,
    parse_to_rpn,
    evaluate_rpn,
    final_round,
)
from decimo import Decimal
from decimo.rounding_mode import RoundingMode


# ===----------------------------------------------------------------------=== #
# Tests: basic arithmetic
# ===----------------------------------------------------------------------=== #


def test_addition() raises:
    testing.assert_equal(String(evaluate("2+3")), "5", "2+3")


def test_subtraction() raises:
    testing.assert_equal(String(evaluate("10-7")), "3", "10-7")


def test_multiplication() raises:
    testing.assert_equal(String(evaluate("6*7")), "42", "6*7")


def test_division_exact() raises:
    testing.assert_equal(String(evaluate("10/2")), "5", "10/2")


def test_division_repeating() raises:
    """1/3 with precision=10 should give 10 decimal digits."""
    var result = String(evaluate("1/3", precision=10))
    testing.assert_equal(result, "0.3333333333", "1/3 p=10")


def test_zero() raises:
    testing.assert_equal(String(evaluate("0+0")), "0", "0+0")


def test_add_zero() raises:
    testing.assert_equal(String(evaluate("42+0")), "42", "42+0")


# ===----------------------------------------------------------------------=== #
# Tests: operator precedence
# ===----------------------------------------------------------------------=== #


def test_mul_before_add() raises:
    testing.assert_equal(String(evaluate("2+3*4")), "14", "2+3*4")


def test_div_before_sub() raises:
    testing.assert_equal(String(evaluate("10-6/3")), "8", "10-6/3")


def test_left_to_right() raises:
    testing.assert_equal(String(evaluate("10-3-2")), "5", "10-3-2")


# ===----------------------------------------------------------------------=== #
# Tests: parentheses
# ===----------------------------------------------------------------------=== #


def test_parens_simple() raises:
    testing.assert_equal(String(evaluate("(2+3)*4")), "20", "(2+3)*4")


def test_nested_parens() raises:
    testing.assert_equal(
        String(evaluate("((1+2)*(3+4))")), "21", "((1+2)*(3+4))"
    )


def test_parens_division() raises:
    testing.assert_equal(String(evaluate("(10+2)/(3+1)")), "3", "(10+2)/(3+1)")


# ===----------------------------------------------------------------------=== #
# Tests: unary minus
# ===----------------------------------------------------------------------=== #


def test_unary_minus_simple() raises:
    testing.assert_equal(String(evaluate("-5+3")), "-2", "-5+3")


def test_unary_minus_in_parens() raises:
    testing.assert_equal(String(evaluate("(-5+2)*3")), "-9", "(-5+2)*3")


def test_multiply_negative() raises:
    testing.assert_equal(String(evaluate("2*-3")), "-6", "2*-3")


def test_double_negative() raises:
    testing.assert_equal(String(evaluate("--5")), "5", "--5")


def test_negative_times_negative() raises:
    testing.assert_equal(String(evaluate("-2*-3")), "6", "-2*-3")


# ===----------------------------------------------------------------------=== #
# Tests: decimals
# ===----------------------------------------------------------------------=== #


def test_decimal_addition() raises:
    testing.assert_equal(String(evaluate("1.5+2.5")), "4.0", "1.5+2.5")


def test_decimal_multiplication() raises:
    testing.assert_equal(String(evaluate("0.1*0.2")), "0.02", "0.1*0.2")


def test_large_integer() raises:
    """Test with numbers exceeding 64-bit integer range."""
    var result = String(evaluate("999999999999999999999999999999 + 1"))
    testing.assert_equal(
        result,
        "1000000000000000000000000000000",
        "large integer add",
    )


# ===----------------------------------------------------------------------=== #
# Tests: precision
# ===----------------------------------------------------------------------=== #


def test_precision_20() raises:
    var result = String(evaluate("1/7", precision=20))
    testing.assert_equal(
        result,
        "0.14285714285714285714",
        "1/7 p=20",
    )


def test_precision_5() raises:
    var result = String(evaluate("1/3", precision=5))
    testing.assert_equal(result, "0.33333", "1/3 p=5")


# ===----------------------------------------------------------------------=== #
# Tests: a long expression at the default precision
# ===----------------------------------------------------------------------=== #


def test_showcase_expression() raises:
    """100 * 12 - 23/17 at default precision (50 significant digits)."""
    var result = String(evaluate("100*12-23/17"))
    # 50 significant digits: 4 integer digits + 46 decimal digits.
    testing.assert_equal(
        result,
        "1198.6470588235294117647058823529411764705882352941",
        "100*12-23/17",
    )


# ===----------------------------------------------------------------------=== #
# Tests: power operator (Phase 2)
# ===----------------------------------------------------------------------=== #


def test_power_simple() raises:
    testing.assert_equal(String(evaluate("2^10")), "1024", "2^10")


def test_power_double_star() raises:
    """** alias for ^."""
    testing.assert_equal(String(evaluate("2**10")), "1024", "2**10")


def test_power_zero() raises:
    testing.assert_equal(String(evaluate("5^0")), "1", "5^0")


def test_power_one() raises:
    testing.assert_equal(String(evaluate("7^1")), "7", "7^1")


def test_power_large() raises:
    """2^256 should produce the correct value."""
    var result = String(evaluate("2^256"))
    # BigDecimal may render this in scientific notation
    testing.assert_true(
        result.startswith(
            "1.1579208923731619542357098500868790785326998466564"
        ),
        "2^256 starts correctly: " + result,
    )


def test_power_right_associative() raises:
    """2^3^2 = 2^(3^2) = 2^9 = 512."""
    testing.assert_equal(String(evaluate("2^3^2")), "512", "2^3^2")


def test_power_with_subtraction() raises:
    """10^2 - 1 = 99."""
    testing.assert_equal(String(evaluate("10^2-1")), "99", "10^2-1")


def test_power_negative_exponent() raises:
    """2^-3 = 0.125."""
    testing.assert_equal(String(evaluate("2^-3")), "0.125", "2^-3")


# ===----------------------------------------------------------------------=== #
# Tests: built-in functions (Phase 2)
# ===----------------------------------------------------------------------=== #


def test_sqrt_perfect() raises:
    testing.assert_equal(String(evaluate("sqrt(9)")), "3", "sqrt(9)")


def test_sqrt_irrational() raises:
    """Irrational sqrt(2) with precision 20."""
    var result = String(evaluate("sqrt(2)", precision=20))
    testing.assert_true(
        result.startswith("1.414213562373095048"),
        "sqrt(2) p=20 starts correctly: " + result,
    )


def test_ln_1() raises:
    testing.assert_equal(String(evaluate("ln(1)")), "0", "ln(1)")


def test_exp_0() raises:
    testing.assert_equal(String(evaluate("exp(0)")), "1", "exp(0)")


def test_abs_negative() raises:
    testing.assert_equal(String(evaluate("abs(-42)")), "42", "abs(-42)")


def test_abs_positive() raises:
    testing.assert_equal(String(evaluate("abs(7)")), "7", "abs(7)")


def test_root_cube() raises:
    """Cube root(27, 3) = 3."""
    testing.assert_equal(String(evaluate("root(27, 3)")), "3", "root(27,3)")


def test_function_in_expression() raises:
    """1 + sqrt(4) = 3."""
    testing.assert_equal(String(evaluate("1+sqrt(4)")), "3", "1+sqrt(4)")


def test_nested_functions() raises:
    """Nested sqrt(abs(-9)) = 3."""
    testing.assert_equal(
        String(evaluate("sqrt(abs(-9))")), "3", "sqrt(abs(-9))"
    )


def test_function_with_power() raises:
    """Power of sqrt(2)^2 should be very close to 2."""
    var result = String(evaluate("sqrt(2)^2"))
    testing.assert_true(
        result.startswith("1.999999999999999999") or result.startswith("2"),
        "sqrt(2)^2 should be close to 2: " + result,
    )


# ===----------------------------------------------------------------------=== #
# Tests: built-in constants (Phase 2)
# ===----------------------------------------------------------------------=== #


def test_pi_constant() raises:
    """Constant pi with precision 20."""
    var result = String(evaluate("pi", precision=20))
    testing.assert_true(
        result.startswith("3.1415926535897932"),
        "pi p=20 starts correctly: " + result,
    )


def test_e_constant() raises:
    """Constant e with precision 20."""
    var result = String(evaluate("e", precision=20))
    testing.assert_true(
        result.startswith("2.7182818284590452"),
        "e p=20 starts correctly: " + result,
    )


def test_pi_in_expression() raises:
    """Expression 2*pi should start with 6.2831853..."""
    var result = String(evaluate("2*pi", precision=20))
    testing.assert_true(
        result.startswith("6.283185307179586"),
        "2*pi p=20: " + result,
    )


def test_ln_e_is_one() raises:
    """Expression ln(e) should be approximately 1."""
    var result = String(evaluate("ln(e)", precision=20))
    testing.assert_true(
        result.startswith("1.0000000000000000000"),
        "ln(e) ≈ 1",
    )


# ===----------------------------------------------------------------------=== #
# Tests: one case per remaining function
# ===----------------------------------------------------------------------=== #


def test_cbrt_27() raises:
    """Tests cbrt(27) ≈ 3."""
    var result = String(evaluate("cbrt(27)"))
    testing.assert_true(
        result == "3" or result.startswith("3."),
        "cbrt(27) should be 3, got: " + result,
    )


def test_log10_1000() raises:
    """Tests log10(1000) = 3."""
    testing.assert_equal(String(evaluate("log10(1000)")), "3", "log10(1000)")


def test_log10_1() raises:
    """Tests log10(1) = 0."""
    testing.assert_equal(String(evaluate("log10(1)")), "0", "log10(1)")


def test_log_base_2() raises:
    """Tests log(8, 2) ≈ 3."""
    var result = String(evaluate("log(8, 2)"))
    testing.assert_true(
        result == "3" or result.startswith("3."),
        "log(8,2) should be 3, got: " + result,
    )


def test_log_base_100() raises:
    """Tests log(1000000, 100) ≈ 3."""
    var result = String(evaluate("log(1000000, 100)"))
    testing.assert_true(
        result == "3" or result.startswith("3."),
        "log(1000000,100) should be 3, got: " + result,
    )


def test_cos_0() raises:
    """Tests cos(0) = 1."""
    testing.assert_equal(String(evaluate("cos(0)")), "1", "cos(0)")


def test_tan_0() raises:
    """Tests tan(0) = 0."""
    testing.assert_equal(String(evaluate("tan(0)")), "0", "tan(0)")


def test_cot_pi_over_4() raises:
    """Tests cot(pi/4) is very close to 1."""
    var result = String(evaluate("cot(pi/4)", precision=20))
    testing.assert_true(
        result == "1" or result.startswith("1.") or result.startswith("0.9999"),
        "cot(pi/4) ≈ 1: " + result,
    )


def test_csc_pi_over_2() raises:
    """Tests csc(pi/2) is very close to 1."""
    var result = String(evaluate("csc(pi/2)", precision=20))
    testing.assert_true(
        result == "1" or result.startswith("1.") or result.startswith("0.9999"),
        "csc(pi/2) ≈ 1: " + result,
    )


# ===----------------------------------------------------------------------=== #
# Tests: rounding modes
# ===----------------------------------------------------------------------=== #


def test_rounding_half_even_tie() raises:
    """2.5 rounded to 1 significant digit with half_even → 2 (round to even)."""
    var result = String(
        evaluate("2.5", precision=1, rounding_mode=RoundingMode.half_even())
    )
    testing.assert_equal(result, "2", "2.5 half_even p=1")


def test_rounding_half_up_tie() raises:
    """2.5 rounded to 1 significant digit with half_up → 3 (round away from 0).
    """
    var result = String(
        evaluate("2.5", precision=1, rounding_mode=RoundingMode.half_up())
    )
    testing.assert_equal(result, "3", "2.5 half_up p=1")


def test_rounding_floor() raises:
    """1.9 rounded to 1 significant digit with floor → 1."""
    var result = String(
        evaluate("1.9", precision=1, rounding_mode=RoundingMode.floor())
    )
    testing.assert_equal(result, "1", "1.9 floor p=1")


def test_rounding_ceiling() raises:
    """1.1 rounded to 1 significant digit with ceiling → 2."""
    var result = String(
        evaluate("1.1", precision=1, rounding_mode=RoundingMode.ceiling())
    )
    testing.assert_equal(result, "2", "1.1 ceiling p=1")


def test_rounding_half_even_division() raises:
    """1/3 with half_even should produce a correctly rounded trailing digit."""
    var result = String(
        evaluate("1/3", precision=4, rounding_mode=RoundingMode.half_even())
    )
    testing.assert_equal(result, "0.3333", "1/3 half_even p=4")


def test_rounding_half_up_division() raises:
    """2/3 with half_up should round trailing 6… → 7."""
    var result = String(
        evaluate("2/3", precision=4, rounding_mode=RoundingMode.half_up())
    )
    testing.assert_equal(result, "0.6667", "2/3 half_up p=4")


# ===----------------------------------------------------------------------=== #
# Tests: variable evaluation (Phase 4)
# ===----------------------------------------------------------------------=== #


def _eval_with_vars(
    expr: String, variables: Dict[String, Decimal], precision: Int = 50
) raises -> Decimal:
    """Helper to evaluate an expression with variables."""
    var tokens = tokenize(expr, variables)
    var rpn = parse_to_rpn(tokens^)
    return final_round(evaluate_rpn(rpn^, precision, variables), precision)


def test_variable_simple() raises:
    """Simple variable reference."""
    var vars = Dict[String, Decimal]()
    vars["x"] = Decimal(42)
    testing.assert_equal(String(_eval_with_vars("x", vars)), "42")


def test_variable_in_arithmetic() raises:
    """Variable used in arithmetic."""
    var vars = Dict[String, Decimal]()
    vars["x"] = Decimal(10)
    testing.assert_equal(String(_eval_with_vars("x + 5", vars)), "15")


def test_variable_ans() raises:
    """The 'ans' variable works like any other variable."""
    var vars = Dict[String, Decimal]()
    vars["ans"] = Decimal(100)
    testing.assert_equal(String(_eval_with_vars("ans * 2", vars)), "200")


def test_multiple_variables() raises:
    """Multiple variables in one expression."""
    var vars = Dict[String, Decimal]()
    vars["x"] = Decimal(3)
    vars["y"] = Decimal(4)
    testing.assert_equal(String(_eval_with_vars("x + y", vars)), "7")


def test_variable_with_function() raises:
    """Variable as argument to a function."""
    var vars = Dict[String, Decimal]()
    vars["x"] = Decimal(4)
    testing.assert_equal(String(_eval_with_vars("sqrt(x)", vars)), "2")


def test_variable_in_power() raises:
    """Variable as base in exponentiation."""
    var vars = Dict[String, Decimal]()
    vars["x"] = Decimal(2)
    testing.assert_equal(String(_eval_with_vars("x ^ 10", vars)), "1024")


def test_undefined_variable_raises() raises:
    """Referencing an undefined variable raises an error."""
    var vars = Dict[String, Decimal]()
    vars["x"] = Decimal(1)
    var raised = False
    try:
        _ = _eval_with_vars("y + 1", vars)
    except:
        raised = True
    testing.assert_true(raised, "should raise on undefined variable 'y'")


# ===----------------------------------------------------------------------=== #
# Main
# ===----------------------------------------------------------------------=== #


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
