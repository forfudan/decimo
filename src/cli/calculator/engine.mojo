# ===----------------------------------------------------------------------=== #
# Copyright 2025 Yuhao Zhu
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
Shared evaluation pipeline for the Decimo CLI calculator.

Provides `evaluate_and_print`, `display_calc_error`, and `pad_to_precision`
used by both one-shot/pipe/file modes (main.mojo) and the interactive REPL
(repl.mojo).
"""

from decimo import Decimal
from decimo.rounding_mode import RoundingMode
from std.collections import Dict
from .tokenizer import tokenize
from .parser import parse_to_rpn
from .evaluator import evaluate_rpn, final_round
from .display import print_error


def evaluate_and_print(
    expr: String,
    precision: Int,
    scientific: Bool,
    engineering: Bool,
    pad: Bool,
    delimiter: String,
    rounding_mode: RoundingMode,
    show_expr_on_error: Bool = False,
    variables: Dict[String, Decimal] = Dict[String, Decimal](),
) raises:
    """Tokenize, parse, evaluate, and print one expression.

    On error, displays a coloured diagnostic and raises to signal failure
    to the caller.

    Args:
        expr: The expression string to evaluate.
        precision: Number of significant digits.
        scientific: Whether to format in scientific notation.
        engineering: Whether to format in engineering notation.
        pad: Whether to pad trailing zeros to the specified precision.
        delimiter: Digit-group separator (empty string disables grouping).
        rounding_mode: Rounding mode for the final result.
        show_expr_on_error: If True, show the expression with a caret
            indicator on error. If False, show only the error message.
        variables: A name→value mapping of user-defined variables.
    """
    try:
        var tokens = tokenize(expr, variables)
        var rpn = parse_to_rpn(tokens^)
        var value = final_round(
            evaluate_rpn(rpn^, precision, variables), precision, rounding_mode
        )

        if scientific:
            print(value.to_string(scientific=True, delimiter=delimiter))
        elif engineering:
            print(value.to_string(engineering=True, delimiter=delimiter))
        elif pad:
            print(
                pad_to_precision(value.to_string(force_plain=True), precision)
            )
        else:
            print(value.to_string(delimiter=delimiter))
    except e:
        if show_expr_on_error:
            display_calc_error(String(e), expr)
        else:
            print_error(String(e))
        raise e^


def display_calc_error(error_msg: String, expr: String):
    """Parse a calculator error message and display it with colours
    and a caret indicator.

    Handles two error formats:

    1. `Error at position N: description` — with position info.
    2. `description` — without position info.

    For form (1), extracts the position and calls `print_error` with a
    visual caret under the offending column. For form (2) falls back
    to a plain coloured error.

    Args:
        error_msg: The error message string to parse and display.
        expr: The original expression string for caret display.
    """
    comptime PREFIX = "Error at position "

    if error_msg.startswith(PREFIX):
        var after_prefix = len(PREFIX)
        var colon_pos = -1
        for i in range(after_prefix, len(error_msg)):
            if error_msg[byte=i] == ":":
                colon_pos = i
                break

        if colon_pos > after_prefix:
            var pos_str = String(error_msg[byte=after_prefix:colon_pos])
            var description = String(
                error_msg[byte = colon_pos + 2 :]
            )  # skip ": "

            try:
                var pos = Int(pos_str)
                print_error(description, expr, pos)
                return
            except:
                pass  # fall through to plain display

    # Fallback: no position info — just show the message.
    print_error(error_msg)


def pad_to_precision(plain: String, precision: Int) -> String:
    """Pad trailing zeros so the fractional part has exactly
    `precision` digits.

    Args:
        plain: A plain (fixed-point) numeric string.
        precision: Target number of fractional digits.

    Returns:
        The string with trailing zeros appended as needed.
    """
    if precision <= 0:
        return plain

    var dot_pos = -1
    for i in range(len(plain)):
        if plain[byte=i] == ".":
            dot_pos = i
            break

    if dot_pos < 0:
        # No decimal point — add one with `precision` zeros
        return plain + "." + "0" * precision

    var frac_len = len(plain) - dot_pos - 1
    if frac_len >= precision:
        return plain

    return plain + "0" * (precision - frac_len)


def evaluate_and_return(
    expr: String,
    precision: Int,
    scientific: Bool,
    engineering: Bool,
    pad: Bool,
    delimiter: String,
    rounding_mode: RoundingMode,
    variables: Dict[String, Decimal] = Dict[String, Decimal](),
) raises -> Decimal:
    """Tokenize, parse, evaluate, print, and return the result.

    Like `evaluate_and_print` but also returns the `Decimal` value so the
    REPL can store it in `ans` or a named variable.

    On error, displays a coloured diagnostic and raises to signal failure
    to the caller.

    Args:
        expr: The expression string to evaluate.
        precision: Number of significant digits.
        scientific: Whether to use scientific notation.
        engineering: Whether to use engineering notation.
        pad: Whether to zero-pad results.
        delimiter: Digit-group delimiter string.
        rounding_mode: The rounding mode to apply.
        variables: Optional name→value mapping of user-defined variables.

    Returns:
        The evaluated Decimal result.
    """
    try:
        var tokens = tokenize(expr, variables)
        var rpn = parse_to_rpn(tokens^)
        var value = final_round(
            evaluate_rpn(rpn^, precision, variables), precision, rounding_mode
        )

        if scientific:
            print(value.to_string(scientific=True, delimiter=delimiter))
        elif engineering:
            print(value.to_string(engineering=True, delimiter=delimiter))
        elif pad:
            print(
                pad_to_precision(value.to_string(force_plain=True), precision)
            )
        else:
            print(value.to_string(delimiter=delimiter))

        return value^
    except e:
        display_calc_error(String(e), expr)
        raise e^
