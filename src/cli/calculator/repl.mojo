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
from .display import write_prompt
from .engine import evaluate_and_print
from .io import read_line, strip, is_comment_or_blank


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
    """
    _print_banner(
        precision, scientific, engineering, pad, delimiter, rounding_mode
    )

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

        # Evaluate the expression.  evaluate_and_print displays the
        # error itself before raising, so we catch and continue.
        # Mojo has no typed exceptions, so we cannot selectively catch
        # only user-input errors here.
        try:
            evaluate_and_print(
                line,
                precision,
                scientific,
                engineering,
                pad,
                delimiter,
                rounding_mode,
                show_expr_on_error=True,
            )
        except:
            continue  # error already displayed; proceed to next prompt


def _print_banner(
    precision: Int,
    scientific: Bool,
    engineering: Bool,
    pad: Bool,
    delimiter: String,
    rounding_mode: RoundingMode,
):
    """Prints the REPL welcome banner to stderr."""
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
    if not (rounding_mode == RoundingMode.half_even()):
        settings += " Rounding: " + String(rounding_mode) + "."
    print(settings, file=stderr)
