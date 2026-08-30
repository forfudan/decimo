"""Test error handling and edge cases for the Decimo CLI calculator.

Covers clear diagnostics for malformed expressions,
and proper handling of edge cases (empty expression, division by zero,
negative sqrt, etc.).
"""

from std import testing

from decimo.expression import evaluate, tokenize


# ===----------------------------------------------------------------------=== #
# Helper: assert that an expression raises an error whose message
# contains the expected substring.
# ===----------------------------------------------------------------------=== #


def assert_error_contains(expr: String, expected_substr: String) raises:
    """Evaluate `expr` and assert that it raises an Error containing
    `expected_substr` in its message.
    """
    try:
        var result = evaluate(expr)
        raise Error(
            "Expected an error for '"
            + expr
            + "' but got result: "
            + String(result)
        )
    except e:
        var msg = String(e)
        if expected_substr not in msg:
            raise Error(
                "Error message for '"
                + expr
                + "' was '"
                + msg
                + "', expected it to contain '"
                + expected_substr
                + "'"
            )


def assert_tokenize_error_contains(
    expr: String, expected_substr: String
) raises:
    """Tokenize `expr` and assert that it raises an Error containing
    `expected_substr`.
    """
    try:
        var tokens = tokenize(expr)
        raise Error(
            "Expected a tokenizer error for '"
            + expr
            + "' but got "
            + String(len(tokens))
            + " tokens"
        )
    except e:
        var msg = String(e)
        if expected_substr not in msg:
            raise Error(
                "Tokenizer error for '"
                + expr
                + "' was '"
                + msg
                + "', expected it to contain '"
                + expected_substr
                + "'"
            )


# ===----------------------------------------------------------------------=== #
# Tests: empty and whitespace-only expressions
# ===----------------------------------------------------------------------=== #


def test_empty_expression() raises:
    assert_tokenize_error_contains("", "Empty expression")


def test_whitespace_only() raises:
    assert_tokenize_error_contains("   ", "Empty expression")


def test_tabs_only() raises:
    assert_tokenize_error_contains("\t\t", "Empty expression")


# ===----------------------------------------------------------------------=== #
# Tests: unknown identifiers
# ===----------------------------------------------------------------------=== #


def test_unknown_identifier() raises:
    assert_error_contains("foo + 1", "unknown identifier 'foo'")


def test_unknown_identifier_position() raises:
    assert_error_contains("1 + bar", "position 4")


# ===----------------------------------------------------------------------=== #
# Tests: unexpected characters
# ===----------------------------------------------------------------------=== #


def test_unexpected_character() raises:
    assert_error_contains("1 @ 2", "unexpected character '@'")


def test_unexpected_character_position() raises:
    assert_error_contains("1 + 2 # 3", "position 6")


# ===----------------------------------------------------------------------=== #
# Tests: mismatched parentheses
# ===----------------------------------------------------------------------=== #


def test_missing_closing_paren() raises:
    assert_error_contains("(1 + 2", "unmatched '('")


def test_missing_opening_paren() raises:
    assert_error_contains("1 + 2)", "unmatched ')'")


def test_nested_missing_close() raises:
    assert_error_contains("((1+2) * 3", "unmatched '('")


def test_extra_closing_paren() raises:
    assert_error_contains("(1+2))", "unmatched ')'")


# ===----------------------------------------------------------------------=== #
# Tests: division by zero
# ===----------------------------------------------------------------------=== #


def test_division_by_zero() raises:
    assert_error_contains("1/0", "division by zero")


def test_division_by_zero_expression() raises:
    assert_error_contains("10 / (5-5)", "division by zero")


def test_division_by_zero_decimal() raises:
    assert_error_contains("1 / 0.0", "division by zero")


# ===----------------------------------------------------------------------=== #
# Tests: negative sqrt
# ===----------------------------------------------------------------------=== #


def test_sqrt_negative() raises:
    assert_error_contains("sqrt(-4)", "sqrt() is undefined for negative")


def test_sqrt_negative_expression() raises:
    assert_error_contains("sqrt(-1)", "sqrt() is undefined for negative")


# ===----------------------------------------------------------------------=== #
# Tests: logarithm of zero / negative
# ===----------------------------------------------------------------------=== #


def test_ln_zero() raises:
    assert_error_contains("ln(0)", "ln() is undefined for zero")


def test_ln_negative() raises:
    assert_error_contains("ln(-1)", "ln() is undefined for negative")


def test_log10_zero() raises:
    assert_error_contains("log10(0)", "log10() is undefined for zero")


def test_log10_negative() raises:
    assert_error_contains("log10(-5)", "log10() is undefined for negative")


# ===----------------------------------------------------------------------=== #
# Tests: misplaced commas
# ===----------------------------------------------------------------------=== #


def test_comma_outside_function() raises:
    assert_error_contains("1, 2", "misplaced ','")


# ===----------------------------------------------------------------------=== #
# Tests: trailing operators
# ===----------------------------------------------------------------------=== #


def test_trailing_plus() raises:
    assert_error_contains("1 +", "missing operand for '+'")


def test_trailing_star() raises:
    assert_error_contains("1 *", "missing operand for '*'")


def test_trailing_slash() raises:
    assert_error_contains("1 /", "missing operand for '/'")


def test_leading_star() raises:
    assert_error_contains("* 1", "missing operand for '*'")


def test_leading_slash() raises:
    assert_error_contains("/ 1", "missing operand for '/'")


# ===----------------------------------------------------------------------=== #
# Tests: consecutive operators (not unary minus)
# ===----------------------------------------------------------------------=== #


def test_double_plus_is_a_unary_plus() raises:
    """`1 ++ 2` is `1 + (+2)`: the second `+` is a sign and does nothing.

    It used to be rejected with "missing operand". A trailing `+` still is.
    """
    testing.assert_equal(String(evaluate("1 ++ 2")), "3")
    assert_error_contains("1 +", "missing operand")


def test_double_star() raises:
    """1 * * 2 should fail."""
    assert_error_contains("1 * * 2", "missing operand")


# ===----------------------------------------------------------------------=== #
# Tests: position information in errors
# ===----------------------------------------------------------------------=== #


def test_position_in_unknown_char() raises:
    """The '@' is at position 4 in '1 + @'."""
    assert_error_contains("1 + @", "position 4")


def test_position_in_div_by_zero() raises:
    """The '/' is at position 1 in '1/0'."""
    assert_error_contains("1/0", "position 1")


def test_position_in_sqrt_negative() raises:
    """'sqrt' starts at position 0 in 'sqrt(-1)'."""
    assert_error_contains("sqrt(-1)", "position 0")


# ===----------------------------------------------------------------------=== #
# Tests: edge cases that should still work
# ===----------------------------------------------------------------------=== #


def test_negative_zero() raises:
    """Negation of zero should not raise an error."""
    var result = String(evaluate("-0"))
    testing.assert_true(
        result == "0" or result == "-0",
        "-0 should evaluate without error, got: " + result,
    )


def test_deeply_nested_parens() raises:
    """((((1)))) should be fine."""
    testing.assert_equal(String(evaluate("((((1))))")), "1", "((((1))))")


def test_many_operations() raises:
    """1+2+3+4+5+6+7+8+9+10 = 55."""
    testing.assert_equal(
        String(evaluate("1+2+3+4+5+6+7+8+9+10")), "55", "sum 1..10"
    )


def test_function_of_constant() raises:
    """Compute sqrt(pi) — should not crash."""
    var result = String(evaluate("sqrt(pi)", precision=10))
    testing.assert_true(
        result.startswith("1.77245385"),
        "sqrt(pi) starts correctly: " + result,
    )


# ===----------------------------------------------------------------------=== #
# Main
# ===----------------------------------------------------------------------=== #


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
