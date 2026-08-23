"""Test the shunting-yard parser: infix to RPN conversion."""

from std import testing

from decimo.expression import (
    Token,
    tokenize,
    TOKEN_NUMBER,
    TOKEN_PLUS,
    TOKEN_MINUS,
    TOKEN_STAR,
    TOKEN_SLASH,
    TOKEN_UNARY_MINUS,
    TOKEN_CARET,
    TOKEN_FUNC,
    TOKEN_CONST,
    TOKEN_COMMA,
    parse_to_rpn,
)

# ===----------------------------------------------------------------------=== #
# Helper: convert token list to a compact string for easy assertion
# e.g. "2 3 +" for RPN of "2+3"
# ===----------------------------------------------------------------------=== #


def rpn_to_string(rpn: List[Token]) -> String:
    """Convert an RPN token list to a space-separated string."""
    var parts = List[String](capacity=len(rpn))
    for i in range(len(rpn)):
        parts.append(rpn[i].value)
    return String(" ").join(parts)


def parse_expr(expr: String) raises -> String:
    """Tokenize and parse an expression, return RPN as string."""
    var tokens = tokenize(expr)
    var rpn = parse_to_rpn(tokens^)
    return rpn_to_string(rpn^)


# ===----------------------------------------------------------------------=== #
# Tests: basic operator precedence
# ===----------------------------------------------------------------------=== #


def test_simple_addition() raises:
    testing.assert_equal(parse_expr("2+3"), "2 3 +", "simple addition")


def test_simple_subtraction() raises:
    testing.assert_equal(parse_expr("5-3"), "5 3 -", "simple subtraction")


def test_mul_before_add() raises:
    """Multiplication has higher precedence than addition."""
    testing.assert_equal(parse_expr("2+3*4"), "2 3 4 * +", "mul before add")


def test_div_before_sub() raises:
    """Division has higher precedence than subtraction."""
    testing.assert_equal(parse_expr("10-6/3"), "10 6 3 / -", "div before sub")


def test_left_associativity_add() raises:
    """Addition is left-associative: 1+2+3 = (1+2)+3."""
    testing.assert_equal(parse_expr("1+2+3"), "1 2 + 3 +", "left assoc add")


def test_left_associativity_mul() raises:
    """Multiplication is left-associative: 2*3*4 = (2*3)*4."""
    testing.assert_equal(parse_expr("2*3*4"), "2 3 * 4 *", "left assoc mul")


# ===----------------------------------------------------------------------=== #
# Tests: parentheses
# ===----------------------------------------------------------------------=== #


def test_parens_override_precedence() raises:
    """Parentheses override normal precedence."""
    testing.assert_equal(parse_expr("(2+3)*4"), "2 3 + 4 *", "parens override")


def test_nested_parens() raises:
    testing.assert_equal(
        parse_expr("((1+2)*(3+4))"), "1 2 + 3 4 + *", "nested parens"
    )


def test_parens_around_single() raises:
    testing.assert_equal(parse_expr("(42)"), "42", "parens around single")


# ===----------------------------------------------------------------------=== #
# Tests: unary minus in RPN
# ===----------------------------------------------------------------------=== #


def test_unary_minus_simple() raises:
    testing.assert_equal(parse_expr("-5"), "5 neg", "unary minus simple")


def test_unary_minus_in_expr() raises:
    testing.assert_equal(parse_expr("-5+3"), "5 neg 3 +", "unary minus in expr")


def test_unary_minus_after_mul() raises:
    testing.assert_equal(
        parse_expr("2*-3"), "2 3 neg *", "unary minus after mul"
    )


# ===----------------------------------------------------------------------=== #
# Tests: complex expressions
# ===----------------------------------------------------------------------=== #


def test_complex_mixed() raises:
    """100*12-23/17 should parse correctly."""
    testing.assert_equal(
        parse_expr("100*12-23/17"),
        "100 12 * 23 17 / -",
        "100*12-23/17",
    )


def test_complex_parens() raises:
    """(1+2)*(3-4)/(5+6)."""
    testing.assert_equal(
        parse_expr("(1+2)*(3-4)/(5+6)"),
        "1 2 + 3 4 - * 5 6 + /",
        "complex with parens",
    )


# ===----------------------------------------------------------------------=== #
# Tests: error handling
# ===----------------------------------------------------------------------=== #


def test_mismatched_lparen() raises:
    var raised = False
    try:
        var tokens = tokenize("(2+3")
        _ = parse_to_rpn(tokens^)
    except:
        raised = True
    testing.assert_true(raised, "should raise on missing ')'")


def test_mismatched_rparen() raises:
    var raised = False
    try:
        var tokens = tokenize("2+3)")
        _ = parse_to_rpn(tokens^)
    except:
        raised = True
    testing.assert_true(raised, "should raise on missing '('")


# ===----------------------------------------------------------------------=== #
# Tests: power operator (Phase 2)
# ===----------------------------------------------------------------------=== #


def test_caret_simple() raises:
    testing.assert_equal(parse_expr("2^3"), "2 3 ^", "simple power")


def test_caret_right_associative() raises:
    """2^3^4 should be parsed as 2^(3^4), i.e. RPN: 2 3 4 ^ ^."""
    testing.assert_equal(parse_expr("2^3^4"), "2 3 4 ^ ^", "right assoc ^")


def test_caret_vs_mul_precedence() raises:
    """^ binds tighter than *: 2*3^4 = 2*(3^4)."""
    testing.assert_equal(parse_expr("2*3^4"), "2 3 4 ^ *", "^ before *")


def test_caret_vs_add_precedence() raises:
    """^ binds tighter than +: 1+2^3 = 1+(2^3)."""
    testing.assert_equal(parse_expr("1+2^3"), "1 2 3 ^ +", "^ before +")


def test_caret_with_parens() raises:
    testing.assert_equal(parse_expr("(2+3)^4"), "2 3 + 4 ^", "(2+3)^4")


def test_double_star() raises:
    """** is alias for ^."""
    testing.assert_equal(parse_expr("2**3"), "2 3 ^", "** as ^")


# ===----------------------------------------------------------------------=== #
# Tests: function calls (Phase 2)
# ===----------------------------------------------------------------------=== #


def test_func_single_arg() raises:
    """Sqrt(4) should produce RPN: 4 sqrt."""
    testing.assert_equal(parse_expr("sqrt(4)"), "4 sqrt", "sqrt(4)")


def test_func_nested_expr() raises:
    """Sqrt(2+2) should produce RPN: 2 2 + sqrt."""
    testing.assert_equal(parse_expr("sqrt(2+2)"), "2 2 + sqrt", "sqrt(2+2)")


def test_func_in_expression() raises:
    """1+sqrt(4) should produce RPN: 1 4 sqrt +."""
    testing.assert_equal(parse_expr("1+sqrt(4)"), "1 4 sqrt +", "1+sqrt(4)")


def test_func_two_args() raises:
    """Root(27, 3) should produce RPN: 27 3 root."""
    testing.assert_equal(parse_expr("root(27, 3)"), "27 3 root", "root(27,3)")


def test_func_chained() raises:
    """Nested sqrt(abs(-9)) should produce RPN: 9 neg abs sqrt."""
    testing.assert_equal(
        parse_expr("sqrt(abs(-9))"), "9 neg abs sqrt", "chained functions"
    )


def test_func_with_power() raises:
    """Function sqrt(2)^2 should produce RPN: 2 sqrt 2 ^."""
    testing.assert_equal(parse_expr("sqrt(2)^2"), "2 sqrt 2 ^", "sqrt(2)^2")


# ===----------------------------------------------------------------------=== #
# Tests: constants (Phase 2)
# ===----------------------------------------------------------------------=== #


def test_constant_pi_rpn() raises:
    """Constant pi alone should produce RPN: pi."""
    testing.assert_equal(parse_expr("pi"), "pi", "pi alone")


def test_constant_in_expression() raises:
    """2*pi should produce RPN: 2 pi *."""
    testing.assert_equal(parse_expr("2*pi"), "2 pi *", "2*pi")


def test_constant_e_in_function() raises:
    """Expression ln(e) should produce RPN: e ln."""
    testing.assert_equal(parse_expr("ln(e)"), "e ln", "ln(e)")


# ===----------------------------------------------------------------------=== #
# Main
# ===----------------------------------------------------------------------=== #


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
