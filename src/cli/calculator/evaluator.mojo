# ===----------------------------------------------------------------------=== #
# Copyright 2025-2026 Yuhao Zhu
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===----------------------------------------------------------------------=== #

"""
RPN evaluator for the Decimo CLI calculator.

Evaluates a Reverse Polish Notation token list using BigDecimal arithmetic.
"""

from decimo import Decimal
from decimo.rounding_mode import RoundingMode
from std.collections import Dict

from .tokenizer import (
    Token,
    TOKEN_NUMBER,
    TOKEN_PLUS,
    TOKEN_MINUS,
    TOKEN_STAR,
    TOKEN_SLASH,
    TOKEN_UNARY_MINUS,
    TOKEN_CARET,
    TOKEN_FUNC,
    TOKEN_CONST,
    TOKEN_VARIABLE,
)
from .parser import parse_to_rpn
from .tokenizer import tokenize


# ===----------------------------------------------------------------------=== #
# Helper: dispatch a function call by name
# ===----------------------------------------------------------------------=== #


def _call_func(
    name: String, mut stack: List[Decimal], precision: Int, position: Int
) raises:
    """Pop argument(s) from `stack`, call the named Decimo function,
    and push the result back.

    Single-argument functions:
        sqrt, cbrt, ln, log10, exp, sin, cos, tan, cot, csc, abs

    Two-argument functions:
        root(x, n)   — the n-th root of x.
        log(x, base) — logarithm of x with the given base.

    Args:
        name: The function name.
        stack: The operand stack (modified in place).
        precision: Decimal precision for the computation.
        position: 0-based column of the function token in the source
            expression, used for diagnostic messages.
    """
    if name == "root":
        # root(x, n): x was pushed first, then n
        if len(stack) < 2:
            raise Error(
                "Error at position "
                + String(position)
                + ": root() requires two arguments, e.g. root(27, 3)"
            )
        var n_val = stack.pop()
        var x_val = stack.pop()
        stack.append(x_val.root(n_val, precision))
        return

    if name == "log":
        # log(x, base): x was pushed first, then base
        if len(stack) < 2:
            raise Error(
                "Error at position "
                + String(position)
                + ": log() requires two arguments, e.g. log(100, 10)"
            )
        var base_val = stack.pop()
        var x_val = stack.pop()
        stack.append(x_val.log(base_val, precision))
        return

    # All remaining functions take exactly one argument
    if len(stack) < 1:
        raise Error(
            "Error at position "
            + String(position)
            + ": "
            + name
            + "() requires one argument"
        )
    var a = stack.pop()

    if name == "sqrt":
        if a.is_negative():
            raise Error(
                "Error at position "
                + String(position)
                + ": sqrt() is undefined for negative numbers (got "
                + String(a)
                + ")"
            )
        stack.append(a.sqrt(precision))
    elif name == "cbrt":
        stack.append(a.cbrt(precision))
    elif name == "ln":
        if a.is_negative() or a.is_zero():
            raise Error(
                "Error at position "
                + String(position)
                + ": ln() is undefined for "
                + (
                    "zero" if a.is_zero() else "negative numbers (got "
                    + String(a)
                    + ")"
                )
            )
        stack.append(a.ln(precision))
    elif name == "log10":
        if a.is_negative() or a.is_zero():
            raise Error(
                "Error at position "
                + String(position)
                + ": log10() is undefined for "
                + (
                    "zero" if a.is_zero() else "negative numbers (got "
                    + String(a)
                    + ")"
                )
            )
        stack.append(a.log10(precision))
    elif name == "exp":
        stack.append(a.exp(precision))
    elif name == "sin":
        stack.append(a.sin(precision))
    elif name == "cos":
        stack.append(a.cos(precision))
    elif name == "tan":
        stack.append(a.tan(precision))
    elif name == "cot":
        stack.append(a.cot(precision))
    elif name == "csc":
        stack.append(a.csc(precision))
    elif name == "abs":
        stack.append(abs(a))
    else:
        raise Error(
            "Error at position "
            + String(position)
            + ": unknown function '"
            + name
            + "'"
        )


# ===----------------------------------------------------------------------=== #
# Evaluator
# ===----------------------------------------------------------------------=== #


def evaluate_rpn(
    rpn: List[Token],
    precision: Int,
    variables: Dict[String, Decimal] = Dict[String, Decimal](),
) raises -> Decimal:
    """Evaluate an RPN token list using BigDecimal arithmetic.

    Internally uses `working_precision = precision + GUARD_DIGITS` for all
    computations to absorb intermediate rounding errors.  The caller is
    responsible for rounding the final result to `precision` significant
    digits (see `final_round`).

    Args:
        rpn: The Reverse Polish Notation token list.
        precision: Number of significant digits.
        variables: A name→value mapping of user-defined variables (e.g.
            `ans`, `x`).  If a TOKEN_VARIABLE token's name is not found
            in this dict, an error is raised.

    Returns:
        The evaluated Decimal result before final rounding.

    Raises:
        Error: On division by zero, missing operands, or other runtime
            errors — with source position when available.
    """
    # BigUInt uses base-1e9 words (~9 decimal digits per word).
    # Adding 9 guard digits gives roughly one extra internal word of
    # precision beyond the user-requested amount, which absorbs
    # accumulated rounding errors from intermediate operations.
    comptime GUARD_DIGITS = 9
    var working_precision = precision + GUARD_DIGITS
    var stack = List[Decimal]()

    for i in range(len(rpn)):
        var kind = rpn[i].kind

        if kind == TOKEN_NUMBER:
            stack.append(Decimal.from_string(rpn[i].value))

        elif kind == TOKEN_CONST:
            if rpn[i].value == "pi":
                stack.append(Decimal.pi(working_precision))
            elif rpn[i].value == "e":
                stack.append(Decimal.e(working_precision))
            else:
                raise Error(
                    "Error at position "
                    + String(rpn[i].position)
                    + ": unknown constant '"
                    + rpn[i].value
                    + "'"
                )

        elif kind == TOKEN_VARIABLE:
            var var_name = rpn[i].value
            if var_name in variables:
                stack.append(variables[var_name].copy())
            else:
                raise Error(
                    "Error at position "
                    + String(rpn[i].position)
                    + ": undefined variable '"
                    + var_name
                    + "'"
                )

        elif kind == TOKEN_UNARY_MINUS:
            if len(stack) < 1:
                raise Error(
                    "Error at position "
                    + String(rpn[i].position)
                    + ": missing operand for negation"
                )
            var a = stack.pop()
            stack.append(-a)

        elif kind == TOKEN_PLUS:
            if len(stack) < 2:
                raise Error(
                    "Error at position "
                    + String(rpn[i].position)
                    + ": missing operand for '+'"
                )
            var b = stack.pop()
            var a = stack.pop()
            stack.append(a + b)

        elif kind == TOKEN_MINUS:
            if len(stack) < 2:
                raise Error(
                    "Error at position "
                    + String(rpn[i].position)
                    + ": missing operand for '-'"
                )
            var b = stack.pop()
            var a = stack.pop()
            stack.append(a - b)

        elif kind == TOKEN_STAR:
            if len(stack) < 2:
                raise Error(
                    "Error at position "
                    + String(rpn[i].position)
                    + ": missing operand for '*'"
                )
            var b = stack.pop()
            var a = stack.pop()
            var product = a * b
            # Multiplication can grow digits unboundedly; trim to
            # working precision to prevent intermediate blowup.
            product.round_to_precision(
                working_precision, RoundingMode.half_even(), False, False
            )
            stack.append(product^)

        elif kind == TOKEN_SLASH:
            if len(stack) < 2:
                raise Error(
                    "Error at position "
                    + String(rpn[i].position)
                    + ": missing operand for '/'"
                )
            var b = stack.pop()
            if b.is_zero():
                raise Error(
                    "Error at position "
                    + String(rpn[i].position)
                    + ": division by zero"
                )
            var a = stack.pop()
            stack.append(a.true_divide(b, working_precision))

        elif kind == TOKEN_CARET:
            if len(stack) < 2:
                raise Error(
                    "Error at position "
                    + String(rpn[i].position)
                    + ": missing operand for '^'"
                )
            var b = stack.pop()
            var a = stack.pop()
            stack.append(a.power(b, working_precision))

        elif kind == TOKEN_FUNC:
            _call_func(rpn[i].value, stack, working_precision, rpn[i].position)

        else:
            raise Error(
                "Error at position "
                + String(rpn[i].position)
                + ": unexpected token in evaluation"
            )

    if len(stack) != 1:
        raise Error(
            "Invalid expression: expected a single result but got "
            + String(len(stack))
            + " values"
        )

    return stack.pop()


def final_round(
    value: Decimal,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.half_even(),
) raises -> Decimal:
    """Round a BigDecimal to `precision` significant digits.

    This should be called on the result of `evaluate_rpn` before
    displaying it to the user, so that guard digits are removed and
    the last visible digit is correctly rounded.

    Args:
        value: The Decimal value to round.
        precision: Number of significant digits.
        rounding_mode: The rounding mode to apply.

    Returns:
        A new Decimal rounded to the requested precision.
    """
    if value.is_zero():
        return value.copy()
    var result = value.copy()
    result.round_to_precision(precision, rounding_mode, False, False)
    return result^


def evaluate(
    expr: String,
    precision: Int = 50,
    rounding_mode: RoundingMode = RoundingMode.half_even(),
) raises -> Decimal:
    """Evaluate a math expression string and return a BigDecimal result.

    This is the main entry point for the calculator engine.
    It tokenizes, parses (shunting-yard), and evaluates (RPN) the expression.
    The result is rounded to `precision` significant digits.

    Args:
        expr: The math expression to evaluate (e.g. "100 * 12 - 23/17").
        precision: The number of significant digits (default: 50).
        rounding_mode: The rounding mode for the final result
            (default: half_even).

    Returns:
        The result as a BigDecimal, rounded to `precision` significant digits.
    """
    var tokens = tokenize(expr)
    var rpn = parse_to_rpn(tokens^)
    var result = evaluate_rpn(rpn^, precision)
    return final_round(result, precision, rounding_mode)
