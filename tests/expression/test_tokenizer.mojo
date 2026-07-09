"""Test the tokenizer: lexical analysis of expression strings."""

from std import testing
from std.collections import Dict
from decimo import Decimal

from decimo.expression import (
    Token,
    tokenize,
    TOKEN_NUMBER,
    TOKEN_PLUS,
    TOKEN_MINUS,
    TOKEN_STAR,
    TOKEN_SLASH,
    TOKEN_LPAREN,
    TOKEN_RPAREN,
    TOKEN_UNARY_MINUS,
    TOKEN_CARET,
    TOKEN_FUNC,
    TOKEN_CONST,
    TOKEN_COMMA,
    TOKEN_VARIABLE,
)


# ===----------------------------------------------------------------------=== #
# Helper
# ===----------------------------------------------------------------------=== #


def assert_token(
    tokens: List[Token],
    index: Int,
    expected_kind: Int,
    expected_value: String,
    msg: String = "",
) raises:
    """Assert that tokens[index] has the expected kind and value."""
    testing.assert_equal(
        tokens[index].kind, expected_kind, msg + " (kind mismatch)"
    )
    testing.assert_equal(
        tokens[index].value, expected_value, msg + " (value mismatch)"
    )


# ===----------------------------------------------------------------------=== #
# Tests: basic tokens
# ===----------------------------------------------------------------------=== #


def test_single_number() raises:
    var toks = tokenize("42")
    testing.assert_equal(len(toks), 1, "single number token count")
    assert_token(toks, 0, TOKEN_NUMBER, "42", "single number")


def test_decimal_number() raises:
    var toks = tokenize("3.14")
    testing.assert_equal(len(toks), 1, "decimal number token count")
    assert_token(toks, 0, TOKEN_NUMBER, "3.14", "decimal number")


def test_leading_dot() raises:
    var toks = tokenize(".5")
    testing.assert_equal(len(toks), 1, "leading dot token count")
    assert_token(toks, 0, TOKEN_NUMBER, ".5", "leading dot")


def test_simple_addition() raises:
    var toks = tokenize("2 + 3")
    testing.assert_equal(len(toks), 3, "2+3 token count")
    assert_token(toks, 0, TOKEN_NUMBER, "2", "first operand")
    assert_token(toks, 1, TOKEN_PLUS, "+", "operator")
    assert_token(toks, 2, TOKEN_NUMBER, "3", "second operand")


def test_all_operators() raises:
    var toks = tokenize("1+2-3*4/5")
    testing.assert_equal(len(toks), 9, "all ops token count")
    assert_token(toks, 1, TOKEN_PLUS, "+", "plus")
    assert_token(toks, 3, TOKEN_MINUS, "-", "minus")
    assert_token(toks, 5, TOKEN_STAR, "*", "star")
    assert_token(toks, 7, TOKEN_SLASH, "/", "slash")


def test_parentheses() raises:
    var toks = tokenize("(2+3)*4")
    testing.assert_equal(len(toks), 7, "parens token count")
    assert_token(toks, 0, TOKEN_LPAREN, "(", "left paren")
    assert_token(toks, 4, TOKEN_RPAREN, ")", "right paren")


def test_whitespace_handling() raises:
    var toks_no_space = tokenize("2+3")
    var toks_spaces = tokenize("  2  +  3  ")
    testing.assert_equal(
        len(toks_no_space), len(toks_spaces), "whitespace equivalence"
    )
    assert_token(toks_spaces, 0, TOKEN_NUMBER, "2", "ws: first")
    assert_token(toks_spaces, 1, TOKEN_PLUS, "+", "ws: op")
    assert_token(toks_spaces, 2, TOKEN_NUMBER, "3", "ws: second")


# ===----------------------------------------------------------------------=== #
# Tests: unary minus detection
# ===----------------------------------------------------------------------=== #


def test_unary_minus_at_start() raises:
    var toks = tokenize("-5")
    testing.assert_equal(len(toks), 2, "-5 token count")
    assert_token(toks, 0, TOKEN_UNARY_MINUS, "neg", "unary at start")
    assert_token(toks, 1, TOKEN_NUMBER, "5", "operand after unary")


def test_unary_minus_after_lparen() raises:
    var toks = tokenize("(-5)")
    testing.assert_equal(len(toks), 4, "(-5) token count")
    assert_token(toks, 0, TOKEN_LPAREN, "(", "lparen")
    assert_token(toks, 1, TOKEN_UNARY_MINUS, "neg", "unary after lparen")
    assert_token(toks, 2, TOKEN_NUMBER, "5", "operand")
    assert_token(toks, 3, TOKEN_RPAREN, ")", "rparen")


def test_unary_minus_after_operator() raises:
    var toks = tokenize("2*-3")
    testing.assert_equal(len(toks), 4, "2*-3 token count")
    assert_token(toks, 0, TOKEN_NUMBER, "2", "first operand")
    assert_token(toks, 1, TOKEN_STAR, "*", "multiply")
    assert_token(toks, 2, TOKEN_UNARY_MINUS, "neg", "unary after *")
    assert_token(toks, 3, TOKEN_NUMBER, "3", "second operand")


def test_binary_minus() raises:
    var toks = tokenize("5-3")
    testing.assert_equal(len(toks), 3, "5-3 token count")
    assert_token(toks, 1, TOKEN_MINUS, "-", "binary minus")


def test_double_unary_minus() raises:
    var toks = tokenize("--5")
    testing.assert_equal(len(toks), 3, "--5 token count")
    assert_token(toks, 0, TOKEN_UNARY_MINUS, "neg", "first neg")
    assert_token(toks, 1, TOKEN_UNARY_MINUS, "neg", "second neg")
    assert_token(toks, 2, TOKEN_NUMBER, "5", "operand")


# ===----------------------------------------------------------------------=== #
# Tests: multi-digit and large numbers
# ===----------------------------------------------------------------------=== #


def test_large_integer() raises:
    var toks = tokenize("123456789012345678901234567890")
    testing.assert_equal(len(toks), 1, "large integer token count")
    assert_token(
        toks,
        0,
        TOKEN_NUMBER,
        "123456789012345678901234567890",
        "large integer",
    )


def test_long_decimal() raises:
    var toks = tokenize("3.141592653589793238462643383279")
    testing.assert_equal(len(toks), 1, "long decimal token count")
    assert_token(
        toks,
        0,
        TOKEN_NUMBER,
        "3.141592653589793238462643383279",
        "long decimal",
    )


# ===----------------------------------------------------------------------=== #
# Tests: error cases
# ===----------------------------------------------------------------------=== #


def test_invalid_character() raises:
    var raised = False
    try:
        _ = tokenize("2 @ 3")
    except:
        raised = True
    testing.assert_true(raised, "should raise on invalid character '@'")


def test_empty_string() raises:
    """Empty string should raise an error since Phase 3."""
    var raised = False
    try:
        _ = tokenize("")
    except:
        raised = True
    testing.assert_true(raised, "empty string should raise an error")


# ===----------------------------------------------------------------------=== #
# Tests: caret / power operator (Phase 2)
# ===----------------------------------------------------------------------=== #


def test_caret_operator() raises:
    var toks = tokenize("2^3")
    testing.assert_equal(len(toks), 3, "2^3 token count")
    assert_token(toks, 0, TOKEN_NUMBER, "2", "base")
    assert_token(toks, 1, TOKEN_CARET, "^", "caret")
    assert_token(toks, 2, TOKEN_NUMBER, "3", "exponent")


def test_double_star_as_power() raises:
    """'**' should be tokenized as TOKEN_CARET."""
    var toks = tokenize("2**3")
    testing.assert_equal(len(toks), 3, "2**3 token count")
    assert_token(toks, 1, TOKEN_CARET, "^", "** -> ^")


def test_caret_precedence() raises:
    """Verify the caret token has precedence 3."""
    var toks = tokenize("^")
    testing.assert_equal(toks[0].precedence(), 3, "^ precedence")


def test_caret_right_associative() raises:
    """Verify the caret token is right-associative."""
    var toks = tokenize("^")
    testing.assert_equal(toks[0].is_left_associative(), False, "^ right assoc")


# ===----------------------------------------------------------------------=== #
# Tests: function names (Phase 2)
# ===----------------------------------------------------------------------=== #


def test_function_sqrt() raises:
    var toks = tokenize("sqrt(4)")
    testing.assert_equal(len(toks), 4, "sqrt(4) token count")
    assert_token(toks, 0, TOKEN_FUNC, "sqrt", "sqrt function")
    assert_token(toks, 1, TOKEN_LPAREN, "(", "lparen")
    assert_token(toks, 2, TOKEN_NUMBER, "4", "argument")
    assert_token(toks, 3, TOKEN_RPAREN, ")", "rparen")


def test_function_ln() raises:
    var toks = tokenize("ln(2)")
    testing.assert_equal(len(toks), 4, "ln(2) token count")
    assert_token(toks, 0, TOKEN_FUNC, "ln", "ln function")


def test_function_sin() raises:
    var toks = tokenize("sin(3.14)")
    assert_token(toks, 0, TOKEN_FUNC, "sin", "sin function")


def test_function_log10() raises:
    var toks = tokenize("log10(100)")
    assert_token(toks, 0, TOKEN_FUNC, "log10", "log10 function")


def test_function_abs() raises:
    var toks = tokenize("abs(-5)")
    assert_token(toks, 0, TOKEN_FUNC, "abs", "abs function")


# ===----------------------------------------------------------------------=== #
# Tests: constants (Phase 2)
# ===----------------------------------------------------------------------=== #


def test_constant_pi() raises:
    var toks = tokenize("pi")
    testing.assert_equal(len(toks), 1, "pi token count")
    assert_token(toks, 0, TOKEN_CONST, "pi", "pi constant")


def test_constant_e() raises:
    var toks = tokenize("e")
    testing.assert_equal(len(toks), 1, "e token count")
    assert_token(toks, 0, TOKEN_CONST, "e", "e constant")


def test_constant_in_expression() raises:
    var toks = tokenize("2*pi")
    testing.assert_equal(len(toks), 3, "2*pi token count")
    assert_token(toks, 0, TOKEN_NUMBER, "2", "number")
    assert_token(toks, 1, TOKEN_STAR, "*", "star")
    assert_token(toks, 2, TOKEN_CONST, "pi", "pi constant")


# ===----------------------------------------------------------------------=== #
# Tests: comma (Phase 2)
# ===----------------------------------------------------------------------=== #


def test_comma_in_function() raises:
    var toks = tokenize("root(27, 3)")
    testing.assert_equal(len(toks), 6, "root(27,3) token count")
    assert_token(toks, 0, TOKEN_FUNC, "root", "root function")
    assert_token(toks, 1, TOKEN_LPAREN, "(", "lparen")
    assert_token(toks, 2, TOKEN_NUMBER, "27", "first arg")
    assert_token(toks, 3, TOKEN_COMMA, ",", "comma")
    assert_token(toks, 4, TOKEN_NUMBER, "3", "second arg")
    assert_token(toks, 5, TOKEN_RPAREN, ")", "rparen")


# ===----------------------------------------------------------------------=== #
# Tests: unary minus with new tokens (Phase 2)
# ===----------------------------------------------------------------------=== #


def test_unary_minus_after_caret() raises:
    var toks = tokenize("2^-3")
    testing.assert_equal(len(toks), 4, "2^-3 token count")
    assert_token(toks, 2, TOKEN_UNARY_MINUS, "neg", "unary after ^")


def test_unary_minus_after_comma() raises:
    var toks = tokenize("root(-8, 3)")
    assert_token(toks, 2, TOKEN_UNARY_MINUS, "neg", "unary after (")


def test_unknown_identifier() raises:
    var raised = False
    try:
        _ = tokenize("foo(1)")
    except:
        raised = True
    testing.assert_true(raised, "should raise on unknown identifier 'foo'")


# ===----------------------------------------------------------------------=== #
# Tests: variable tokens (Phase 4)
# ===----------------------------------------------------------------------=== #


def _make_vars(*names: String) -> Dict[String, Decimal]:
    """Build a Dict[String, Decimal] from variadic name arguments."""
    var result = Dict[String, Decimal]()
    for i in range(len(names)):
        result[names[i]] = Decimal()
    return result^


def test_variable_token() raises:
    """Known variable names produce TOKEN_VARIABLE tokens."""
    var vars = _make_vars("x", "y")
    var toks = tokenize("x + y", vars)
    testing.assert_equal(len(toks), 3, "x + y token count")
    assert_token(toks, 0, TOKEN_VARIABLE, "x", "variable x")
    assert_token(toks, 1, TOKEN_PLUS, "+", "plus")
    assert_token(toks, 2, TOKEN_VARIABLE, "y", "variable y")


def test_variable_ans() raises:
    """The special variable 'ans' is tokenized correctly."""
    var vars = _make_vars("ans")
    var toks = tokenize("ans * 2", vars)
    testing.assert_equal(len(toks), 3, "ans * 2 token count")
    assert_token(toks, 0, TOKEN_VARIABLE, "ans", "variable ans")


def test_variable_vs_function() raises:
    """Functions take priority over variable names."""
    var vars = _make_vars("sqrt")
    var toks = tokenize("sqrt(4)", vars)
    assert_token(toks, 0, TOKEN_FUNC, "sqrt", "function, not variable")


def test_variable_vs_constant() raises:
    """Constants take priority over variable names."""
    var vars = _make_vars("pi")
    var toks = tokenize("pi", vars)
    assert_token(toks, 0, TOKEN_CONST, "pi", "constant, not variable")


def test_unknown_without_known_variables() raises:
    """Without known variables, unknown identifiers still raise."""
    var raised = False
    try:
        _ = tokenize("x + 1")
    except:
        raised = True
    testing.assert_true(raised, "should raise on unknown 'x' without vars")


def test_variable_in_expression() raises:
    """Variables work in complex expressions."""
    var vars = _make_vars("x", "ans")
    var toks = tokenize("x^2 + ans", vars)
    testing.assert_equal(len(toks), 5, "x^2 + ans token count")
    assert_token(toks, 0, TOKEN_VARIABLE, "x", "var x")
    assert_token(toks, 1, TOKEN_CARET, "^", "caret")
    assert_token(toks, 2, TOKEN_NUMBER, "2", "number 2")
    assert_token(toks, 3, TOKEN_PLUS, "+", "plus")
    assert_token(toks, 4, TOKEN_VARIABLE, "ans", "var ans")


# ===----------------------------------------------------------------------=== #
# Main
# ===----------------------------------------------------------------------=== #


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
