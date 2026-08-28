"""
Pins the sign handling and the precedence table of the expression evaluator.

Two things a table of expected results does not catch on its own.

The first is the shape of the sign handling. The tokenizer decides whether a
`-` is a sign or an operator by looking at what came before it -- the start of
the expression, an operator, an opening parenthesis, a comma. The `+` branch
has none of that and emits a binary token unconditionally, so `+3` is an
error: "missing operand for '+'". That is the documented scope --
`parse_to_rpn()` lists what it supports as "binary operators (+, -, *, /, ^),
unary minus" -- and `test_double_plus` in the error suite pins `1 ++ 2` as
invalid. So it is pinned here from the other side too, positively: every
position where a `-` is read as a sign, and the same position with a `+`
rejected. If unary plus is ever added, this file is where the expectation
lives.

The second is the precedence table itself, which is a set of choices rather
than a fact. This evaluator binds a unary minus tighter than `^`, so `-2^2` is
4, the way a spreadsheet reads it. Python binds it looser and gives -4. That is
documented in `Token.precedence()` and is worth a test, because it is exactly
the kind of thing a rewrite flips without anyone noticing.
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
    """The positions the tokenizer calls unary, one at a time."""
    assert_evaluates_to("-3", "-3")  # at the start
    assert_evaluates_to("(-3)", "-3")  # after '('
    assert_evaluates_to("5+-3", "2")  # after an operator
    assert_evaluates_to("5--3", "8")
    assert_evaluates_to("5*-3", "-15")
    assert_evaluates_to("6/-3", "-2")
    assert_evaluates_to("2^-3", "0.125")
    assert_evaluates_to("--3", "3")  # after another sign
    assert_evaluates_to("---3", "-3")


def test_a_plus_is_never_read_as_a_sign() raises:
    """The documented scope is unary minus only, and this is the other half.

    Every expression here is the `+` counterpart of a line above, and every one
    of them is an error today. The suite already pins `1 ++ 2`; these are the
    rest of the positions, so that adding unary plus is a deliberate act with
    a visible diff rather than something that leaks in.
    """
    assert_rejected("+3")
    assert_rejected("(+3)")
    assert_rejected("5++3")
    assert_rejected("5-+3")
    assert_rejected("5*+3")
    assert_rejected("6/+3")
    assert_rejected("2^+3")
    assert_rejected("-+3")


def test_the_documented_precedence_table() raises:
    """The table in `Token.precedence()`, one row at a time.

    A unary minus binds tighter than `^` here, which is the spreadsheet
    reading rather than Python's. `^` is right-associative; everything else is
    left.
    """
    # unary minus above '^'
    assert_evaluates_to("-2^2", "4")
    assert_evaluates_to("(-2)^2", "4")
    assert_evaluates_to("-(2^2)", "-4")

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
