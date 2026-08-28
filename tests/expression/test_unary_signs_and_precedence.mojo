"""
Pins the sign handling and the precedence table of the expression evaluator.

Two things a table of expected results does not catch on its own.

The first is the shape of the sign handling. The tokenizer decides whether a
`-` or `+` is a sign or an operator by looking at what came before it -- the
start of the expression, an operator, an opening parenthesis, a comma. A `-`
in sign position becomes a unary-minus token; a `+` in sign position is
dropped, since it does nothing. Both are pinned here position by position.
Unary plus used to be an error ("missing operand for '+'"); it was accepted
because every calculator and Python accept it.

The second is the precedence table itself, which is a set of choices rather
than a fact. A unary minus binds between `*` and `^`, so `-2^2` is -4, the
way Python reads it. Spreadsheets rank the sign above `^` and give 4, and so
did this evaluator once. A sign inside an exponent is part of the exponent,
so `2^-2` is 0.25 under both readings; that case is what makes the parser
push a sign without popping. These are documented in `Token.precedence()`
and `parse_to_rpn()` and are worth a test, because a rewrite flips them
without anyone noticing.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.expression.evaluator import evaluate


def assert_evaluates_to(expression: String, expected: String) raises:
    assert_equal(
        String(evaluate(expression)),
        expected,
        expression + " should be " + expected,
    )


def assert_rejected(expression: String) raises:
    with testing.assert_raises():
        _ = evaluate(expression)


def test_a_minus_is_read_as_a_sign_in_every_leading_position() raises:
    """The positions the tokenizer calls a sign, one at a time."""
    assert_evaluates_to("-3", "-3")  # at the start
    assert_evaluates_to("(-3)", "-3")  # after '('
    assert_evaluates_to("5+-3", "2")  # after an operator
    assert_evaluates_to("5--3", "8")
    assert_evaluates_to("5*-3", "-15")
    assert_evaluates_to("6/-3", "-2")
    assert_evaluates_to("2^-3", "0.125")
    assert_evaluates_to("--3", "3")  # after another sign
    assert_evaluates_to("---3", "-3")
    assert_evaluates_to("root(-8, 3)", "-2")  # after ','


def test_a_plus_is_read_as_a_sign_in_the_same_positions() raises:
    """Every expression here is the `+` counterpart of a line above."""
    assert_evaluates_to("+3", "3")
    assert_evaluates_to("(+3)", "3")
    assert_evaluates_to("5++3", "8")
    assert_evaluates_to("5-+3", "2")
    assert_evaluates_to("5*+3", "15")
    assert_evaluates_to("6/+3", "2")
    assert_evaluates_to("2^+3", "8")
    assert_evaluates_to("-+3", "-3")
    assert_evaluates_to("+-3", "-3")
    assert_evaluates_to("++3", "3")
    assert_evaluates_to("root(+8, +3)", "2")

    # A sign still needs an operand.
    assert_rejected("+")
    assert_rejected("3+")
    assert_rejected("3*+")


def test_the_documented_precedence_table() raises:
    """The table in `Token.precedence()`, one row at a time."""
    # '^' above unary minus; a sign inside an exponent is the exponent's
    assert_evaluates_to("-2^2", "-4")
    assert_evaluates_to("(-2)^2", "4")
    assert_evaluates_to("-(2^2)", "-4")
    assert_evaluates_to("2^-2", "0.25")
    assert_evaluates_to("-2^-2", "-0.25")
    assert_evaluates_to("2*-3^2", "-18")
    assert_evaluates_to("-2^2^2", "-16")
    assert_evaluates_to("2^-1^2", "0.5")

    # unary minus above '*' and '/'
    assert_evaluates_to("-3*2", "-6")
    assert_evaluates_to("-6/2", "-3")
    assert_evaluates_to("-3*-2", "6")

    # '^' above '*' and '/', and right-associative
    assert_evaluates_to("2+3*4^2", "50")
    assert_evaluates_to("2^3^2", "512")
    assert_evaluates_to("(2^3)^2", "64")

    # '*' and '/' above '+' and '-', and left-associative
    assert_evaluates_to("2+3*4", "14")
    assert_evaluates_to("2*3+4", "10")
    assert_evaluates_to("6/2*3", "9")
    assert_evaluates_to("10-3-2", "5")
    assert_evaluates_to("100/10/2", "5")
    assert_evaluates_to("2-3+4", "3")


def test_nesting_does_not_run_out() raises:
    """Two hundred parentheses deep, which the shunting yard holds on a stack.
    """
    var deep = String("")
    for _ in range(200):
        deep += "("
    deep += "1+1"
    for _ in range(200):
        deep += ")"
    assert_evaluates_to(deep, "2")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
