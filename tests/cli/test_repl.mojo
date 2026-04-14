"""Test REPL helpers: _parse_assignment, _validate_variable_name."""

from std import testing

from calculator.repl import _parse_assignment, _validate_variable_name


# ===----------------------------------------------------------------------=== #
# Tests: _parse_assignment
# ===----------------------------------------------------------------------=== #


def test_simple_assignment() raises:
    """Simple `x = 1` is recognized as assignment."""
    var result = _parse_assignment("x = 1")
    testing.assert_true(Bool(result), "should parse as assignment")
    testing.assert_equal(result.value()[0], "x")
    testing.assert_equal(result.value()[1], "1")


def test_assignment_with_expression() raises:
    """Assignment with a compound expression."""
    var result = _parse_assignment("total = 2 + 3 * 4")
    testing.assert_true(Bool(result), "should parse as assignment")
    testing.assert_equal(result.value()[0], "total")
    testing.assert_equal(result.value()[1], "2 + 3 * 4")


def test_assignment_whitespace_around_eq() raises:
    """Whitespace around `=` is handled."""
    var result = _parse_assignment("y  =  42")
    testing.assert_true(Bool(result), "should parse with whitespace")
    testing.assert_equal(result.value()[0], "y")
    testing.assert_equal(result.value()[1], "42")


def test_assignment_underscore_name() raises:
    """Variable names with underscores are valid."""
    var result = _parse_assignment("my_var = 10")
    testing.assert_true(Bool(result), "underscore name ok")
    testing.assert_equal(result.value()[0], "my_var")
    testing.assert_equal(result.value()[1], "10")


def test_double_eq_not_assignment() raises:
    """`==` is not treated as assignment."""
    var result = _parse_assignment("x == 5")
    testing.assert_false(Bool(result), "`==` is not assignment")


def test_no_eq_not_assignment() raises:
    """A plain expression without `=` is not assignment."""
    var result = _parse_assignment("2 + 3")
    testing.assert_false(Bool(result), "no `=` means not assignment")


def test_number_start_not_assignment() raises:
    """Lines starting with a number are not assignments."""
    var result = _parse_assignment("3x = 5")
    testing.assert_false(Bool(result), "starts with digit")


def test_empty_expr_not_assignment() raises:
    """`x =` (no expression after `=`) returns None."""
    var result = _parse_assignment("x = ")
    testing.assert_false(Bool(result), "empty expression after =")


def test_blank_line_not_assignment() raises:
    """Blank input is not assignment."""
    var result = _parse_assignment("")
    testing.assert_false(Bool(result), "blank line")


def test_leading_whitespace() raises:
    """Leading whitespace before the name is handled."""
    var result = _parse_assignment("  x = 7")
    testing.assert_true(Bool(result), "leading spaces ok")
    testing.assert_equal(result.value()[0], "x")
    testing.assert_equal(result.value()[1], "7")


# ===----------------------------------------------------------------------=== #
# Tests: _validate_variable_name
# ===----------------------------------------------------------------------=== #


def test_valid_name() raises:
    """A normal user name is accepted."""
    var err = _validate_variable_name("total")
    testing.assert_false(Bool(err), "normal name should be valid")


def test_reject_ans() raises:
    """`ans` is rejected as a variable name."""
    var err = _validate_variable_name("ans")
    testing.assert_true(Bool(err), "ans should be rejected")


def test_reject_function_sqrt() raises:
    """Built-in function name `sqrt` is rejected."""
    var err = _validate_variable_name("sqrt")
    testing.assert_true(Bool(err), "sqrt should be rejected")


def test_reject_function_sin() raises:
    """Built-in function name `sin` is rejected."""
    var err = _validate_variable_name("sin")
    testing.assert_true(Bool(err), "sin should be rejected")


def test_reject_constant_pi() raises:
    """Built-in constant `pi` is rejected."""
    var err = _validate_variable_name("pi")
    testing.assert_true(Bool(err), "pi should be rejected")


def test_reject_constant_e() raises:
    """Built-in constant `e` is rejected."""
    var err = _validate_variable_name("e")
    testing.assert_true(Bool(err), "e should be rejected")


def test_valid_name_with_underscore() raises:
    """Names with underscores are valid."""
    var err = _validate_variable_name("my_var")
    testing.assert_false(Bool(err), "underscore name is valid")


# ===----------------------------------------------------------------------=== #
# Main
# ===----------------------------------------------------------------------=== #


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
