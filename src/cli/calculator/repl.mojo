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
Interactive REPL (Read-Eval-Print Loop) for the Decimo CLI calculator.

Launched when `decimo` is invoked with no expression and stdin is a TTY.
Reads one expression per line, evaluates it, prints the result, and loops
until the user types `exit`, `quit`, or presses Ctrl-D.

Architecture notes for future PRs:

- `ans` variable (4.4): The evaluator will need a `variables` dict
  passed into `evaluate_rpn`.  The REPL will inject `ans` after each
  successful evaluation.  The tokenizer already treats unknown identifiers
  as errors, so it will need a `known_names: Set[String]` parameter.

- Variable assignment (4.5): The REPL will detect `name = expr` syntax
  *before* calling the evaluator (simple string split on first `=` that
  is not inside parentheses).  The result is stored in the variables dict.

- Meta-commands (4.6): Lines starting with `:` are intercepted before
  evaluation.  Examples: `:precision 100`, `:vars`, `:help`.
"""

from std.sys import stderr

from decimo.rounding_mode import RoundingMode
from .tokenizer import tokenize
from .parser import parse_to_rpn
from .evaluator import evaluate_rpn, final_round
from .display import print_error, print_hint, write_prompt
from .io import read_line, strip, is_comment_or_blank


def run_repl(
    precision: Int,
    scientific: Bool,
    engineering: Bool,
    pad: Bool,
    delimiter: String,
    rounding_mode: RoundingMode,
) raises:
    """Run the interactive REPL.

    Prints a welcome banner, then loops: prompt → read → eval → print.
    Errors are caught per-line and displayed without crashing the session.
    The loop exits on `exit`, `quit`, or EOF (Ctrl-D).
    """
    _print_banner(precision, scientific, engineering, pad, delimiter)

    while True:
        write_prompt("decimo> ")

        var maybe_line = read_line()
        if not maybe_line:
            # EOF (Ctrl-D) — exit gracefully
            print(file=stderr)  # newline after the prompt
            break

        var line = strip(maybe_line.value())

        # Skip blank lines and comments
        if is_comment_or_blank(line):
            continue

        # Exit commands
        if line == "exit" or line == "quit":
            break

        # Evaluate the expression — errors are caught and printed,
        # then the loop continues.
        try:
            _evaluate_and_print(
                line,
                precision,
                scientific,
                engineering,
                pad,
                delimiter,
                rounding_mode,
            )
        except:
            pass  # error already displayed by _evaluate_and_print


def _evaluate_and_print(
    expr: String,
    precision: Int,
    scientific: Bool,
    engineering: Bool,
    pad: Bool,
    delimiter: String,
    rounding_mode: RoundingMode,
) raises:
    """Evaluate one expression and print the result.

    On error, displays a coloured diagnostic with caret and re-raises
    so the REPL loop knows to continue.
    """
    try:
        var tokens = tokenize(expr)
        var rpn = parse_to_rpn(tokens^)

        try:
            var value = final_round(
                evaluate_rpn(rpn^, precision), precision, rounding_mode
            )

            if scientific:
                print(value.to_string(scientific=True, delimiter=delimiter))
            elif engineering:
                print(value.to_string(engineering=True, delimiter=delimiter))
            elif pad:
                print(
                    _pad_to_precision(
                        value.to_string(force_plain=True), precision
                    )
                )
            else:
                print(value.to_string(delimiter=delimiter))
        except eval_err:
            _display_calc_error(String(eval_err), expr)
            raise eval_err^

    except parse_err:
        _display_calc_error(String(parse_err), expr)
        raise parse_err^


def _print_banner(
    precision: Int,
    scientific: Bool,
    engineering: Bool,
    pad: Bool,
    delimiter: String,
):
    """Print the REPL welcome banner to stderr."""
    print(
        "Decimo — arbitrary-precision calculator",
        file=stderr,
    )
    print(
        "Type an expression, or 'exit' to quit.",
        file=stderr,
    )

    # Build settings line: "Precision: N. Engineering notation."
    var settings = "Precision: " + String(precision) + "."
    if scientific:
        settings += " Scientific notation."
    elif engineering:
        settings += " Engineering notation."
    if pad:
        settings += " Zero-padded."
    if delimiter:
        settings += " Delimiter: '" + delimiter + "'."
    print(settings, file=stderr)


def _display_calc_error(error_msg: String, expr: String):
    """Parse and display an error with optional caret indicator.

    Handles two error formats:
    1. `Error at position N: description` → caret display
    2. `description` → plain error
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
            var description = String(error_msg[byte = colon_pos + 2 :])

            try:
                var pos = Int(pos_str)
                print_error(description, expr, pos)
                return
            except:
                pass

    print_error(error_msg)


def _pad_to_precision(plain: String, precision: Int) -> String:
    """Pad trailing zeros so the fractional part has exactly
    `precision` digits.
    """
    if precision <= 0:
        return plain

    var dot_pos = -1
    for i in range(len(plain)):
        if plain[byte=i] == ".":
            dot_pos = i
            break

    if dot_pos < 0:
        return plain + "." + "0" * precision

    var frac_len = len(plain) - dot_pos - 1
    if frac_len >= precision:
        return plain

    return plain + "0" * (precision - frac_len)
