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

Features:
- `ans` — automatically holds the result of the last successful evaluation.
- Variable assignment — `x = <expr>` stores a named value for later use.
- Error recovery — display error and continue, don't crash the session.

Architecture notes for future PRs:

- Meta-commands (4.6): Lines starting with `:` are intercepted before
  evaluation.  Examples: `:precision 100`, `:vars`, `:help`.
"""

from std.sys import stderr
from std.collections import Dict

from decimo import Decimal
from decimo.rounding_mode import RoundingMode
from .display import BOLD, RESET, YELLOW
from .display import write_prompt, print_error
from .engine import evaluate_and_return
from .io import read_line, strip, is_comment_or_blank
from .tokenizer import (
    _is_alpha_or_underscore,
    _is_alnum_or_underscore,
    _is_known_function,
    _is_known_constant,
)


def run_repl(
    precision: Int,
    scientific: Bool,
    engineering: Bool,
    pad: Bool,
    delimiter: String,
    rounding_mode: RoundingMode,
) raises:
    """Runs the interactive REPL.

    Prints a welcome banner, then loops: prompt → read → eval → print.
    Errors are caught per-line and displayed without crashing the session.
    The loop exits on `exit`, `quit`, or EOF (Ctrl-D).

    Maintains a variable store with:
    - `ans`: automatically updated after each successful evaluation.
    - User-defined variables via `name = expr` assignment syntax.
    """
    _print_banner(
        precision, scientific, engineering, pad, delimiter, rounding_mode
    )

    var variables = Dict[String, Decimal]()
    variables["ans"] = Decimal()  # "0" by default, updated after each eval

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

        # Check for variable assignment: `name = expr`
        var assignment = _parse_assignment(line)

        if assignment:
            var var_name = assignment.value()[0]
            var expr = assignment.value()[1]

            # Validate the variable name
            var err = _validate_variable_name(var_name)
            if err:
                print_error(err.value())
                continue

            # Evaluate the expression and store the result
            try:
                var result = evaluate_and_return(
                    expr,
                    precision,
                    scientific,
                    engineering,
                    pad,
                    delimiter,
                    rounding_mode,
                    variables,
                )
                variables[var_name] = result.copy()
                variables["ans"] = result^
            except:
                continue  # error already displayed
        else:
            # Regular expression — evaluate and update ans
            try:
                var result = evaluate_and_return(
                    line,
                    precision,
                    scientific,
                    engineering,
                    pad,
                    delimiter,
                    rounding_mode,
                    variables,
                )
                variables["ans"] = result^
            except:
                continue  # error already displayed


def _parse_assignment(line: String) -> Optional[Tuple[String, String]]:
    """Detect `name = expr` assignment syntax.

    Returns (variable_name, expression) if the line is an assignment,
    or None if it is a regular expression.

    The first `=` that is not `==` and is preceded by a valid identifier
    (with optional whitespace) triggers assignment mode.  If the identifier
    is a function name followed by `(`, it is not an assignment (e.g.
    `sqrt(2)` is not `sqrt = ...`).
    """
    var line_bytes = StringSlice(line).as_bytes()
    var n = len(line_bytes)

    # Skip leading whitespace to find the identifier start
    var i = 0
    while i < n and (line_bytes[i] == 32 or line_bytes[i] == 9):
        i += 1

    if i >= n:
        return None

    # Must start with alpha or underscore
    if not _is_alpha_or_underscore(line_bytes[i]):
        return None

    var name_start = i
    i += 1
    while i < n and _is_alnum_or_underscore(line_bytes[i]):
        i += 1
    var name_end = i

    # Skip whitespace after name
    while i < n and (line_bytes[i] == 32 or line_bytes[i] == 9):
        i += 1

    # Check for '=' (but not '==')
    if i >= n or line_bytes[i] != 61:  # '='
        return None
    if i + 1 < n and line_bytes[i + 1] == 61:  # '=='
        return None

    # Extract name and expression
    var name_bytes = List[UInt8](capacity=name_end - name_start)
    for j in range(name_start, name_end):
        name_bytes.append(line_bytes[j])
    var var_name = String(unsafe_from_utf8=name_bytes^)

    var expr_start = i + 1
    # Skip whitespace after '='
    while expr_start < n and (
        line_bytes[expr_start] == 32 or line_bytes[expr_start] == 9
    ):
        expr_start += 1

    if expr_start >= n:
        return None  # `x =` with no expression — treat as regular expression

    var expr_bytes = List[UInt8](capacity=n - expr_start)
    for j in range(expr_start, n):
        expr_bytes.append(line_bytes[j])
    var expr = String(unsafe_from_utf8=expr_bytes^)

    return (var_name^, expr^)


def _validate_variable_name(name: String) -> Optional[String]:
    """Validate a variable name for assignment.

    Returns an error message if the name is invalid, or None if valid.
    Rejects:
    - `ans` (read-only built-in)
    - Built-in function names (sqrt, sin, etc.)
    - Built-in constant names (pi, e)
    """
    if name == "ans":
        return (
            "cannot assign to 'ans' (read-only; it always holds the last"
            " result)"
        )
    if _is_known_function(name):
        return "cannot assign to '" + name + "' (built-in function)"
    if _is_known_constant(name):
        return "cannot assign to '" + name + "' (built-in constant)"
    return None


def _print_banner(
    precision: Int,
    scientific: Bool,
    engineering: Bool,
    pad: Bool,
    delimiter: String,
    rounding_mode: RoundingMode,
):
    """Prints the REPL welcome banner to stderr."""
    comptime message = (
        BOLD
        + YELLOW
        + "Decimo — arbitrary-precision calculator, written in pure Mojo 🔥\n"
        + RESET
        + """Type an expression to evaluate, e.g., `pi + sin(-ln(1.23)) * sqrt(e^2)`.
You can assign variables with `name = expression`, e.g., `x = 1.023^365`.
You can use `ans` to refer to the last result.
Type 'exit' or 'quit', or press Ctrl-D, to quit."""
    )
    print(message, file=stderr)

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
    if not (rounding_mode == RoundingMode.half_even()):
        settings += " Rounding: " + String(rounding_mode) + "."
    print(settings, file=stderr)
