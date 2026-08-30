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
Interactive REPL (Read-Eval-Print Loop) for the Decimo CLI calculator.

Launched when `decimo` is invoked with no expression and stdin is a TTY.
Reads one expression per line, evaluates it, prints the result, and loops
until the user types `exit`, `quit`, `:q`, or presses Ctrl-D.

Features:
- `ans` — automatically holds the result of the last successful evaluation.
- Variable assignment — `x = <expr>` stores a named value for later use.
- Meta-commands — lines starting with `:` change session settings without
  evaluation.  Example: `:p 100 s r down`.
- Inline temp settings — append `:settings` to an expression for one-off
  overrides.  Example: `sqrt(2):p 100`.
- Error recovery — display error and continue, don't crash the session.
"""

from std.sys import stderr
from std.collections import Dict

from decimo import Decimal
from decimo.rounding_mode import RoundingMode
from limo import LineEditor
from decimo import DECIMO_VERSION_TAG
from .display import BOLD, RESET, YELLOW, CYAN, GREEN, MAGENTA
from .display import print_error, format_about
from .engine import evaluate_and_return
from .io import strip, is_comment_or_blank
from .settings import Settings, parse_settings, split_inline_settings, to_lower
from decimo.expression import (
    is_alpha_or_underscore,
    is_alnum_or_underscore,
    is_known_function,
    is_known_constant,
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

    Supports:
    - Meta-commands: lines starting with `:` change session settings
      globally.  Example: `:p 100 s r down`.
    - Inline temp settings: append `:settings` to an expression for
      one-off overrides.  Example: `sqrt(2):p 100`.

    Args:
        precision: Initial number of significant digits.
        scientific: Initial scientific notation flag.
        engineering: Initial engineering notation flag.
        pad: Initial zero-padding flag.
        delimiter: Initial digit-group delimiter.
        rounding_mode: Initial rounding mode.

    Raises:
        Error: If the line editor cannot be initialised or an unrecoverable
            I/O error occurs while reading from stdin. Per-line evaluation
            errors are caught internally and do not propagate.
    """
    var settings = Settings(
        precision,
        scientific,
        engineering,
        pad,
        delimiter,
        rounding_mode,
    )
    _print_banner(settings)

    var variables = Dict[String, Decimal]()
    variables["ans"] = Decimal()  # "0" by default, updated after each eval

    var editor = LineEditor()

    while True:
        var maybe_line = editor.read_line("decimo> ")
        if not maybe_line:
            # EOF (Ctrl-D) — exit gracefully
            print(file=stderr)  # newline after the prompt
            break

        # Lowercase the whole line here, so meta-commands, variable names and
        # function names are all case-insensitive.
        var line = to_lower(strip(maybe_line.value()))

        # Skip blank lines and comments
        if is_comment_or_blank(line):
            continue

        # Exit commands
        if line == "exit" or line == "quit":
            break

        # == Bare commands (no `:` prefix) ================================
        # `?` — show help
        if line == "?":
            _print_help()
            continue

        # `$` — show variables
        if line == "$":
            _print_variables(variables)
            continue

        # == Meta-command: line starts with `:` ===========================
        if _is_meta_command(line):
            var cmd_str = _strip_colon_prefix(line)

            # Bare `:` — show current settings
            if cmd_str == "":
                _print_settings(settings)
                continue

            # `:help` / `:h` / `:?` — show help
            if _is_help_command(cmd_str):
                _print_help()
                continue

            # `:about` / `:a` / `:info` — show about/info
            if _is_about_command(cmd_str):
                print(format_about(), file=stderr)
                continue

            # `:version` / `:v` — show version
            if _is_version_command(cmd_str):
                print("decimo " + DECIMO_VERSION_TAG, file=stderr)
                continue

            # `:vars`
            # This displays all user-defined variables and their current values,
            # including `ans`.
            if _is_vars_command(cmd_str):
                _print_variables(variables)
                continue

            # `:q` / `:quit` / `:exit`
            # This exits the REPL session gracefully (same as Ctrl-D).
            if _is_quit_command(cmd_str):
                break

            try:
                parse_settings(cmd_str, settings)
                _print_settings(settings)
            except e:
                print_error(String(e))
            continue

        # == Check for inline temp settings: `expr:settings` ========
        var inline = split_inline_settings(line)
        if inline:
            var expr = inline.value()[0]
            var settings_str = inline.value()[1]

            # Build a temp copy of settings and apply overrides
            var temp = settings.copy()
            try:
                parse_settings(settings_str, temp)
            except e:
                print_error(String(e))
                continue

            # Evaluate expression with temp settings
            _eval_line(expr, temp, variables)
            continue

        # == Check for variable assignment: `name = expr` =================
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
                    settings.precision,
                    settings.scientific,
                    settings.engineering,
                    settings.pad,
                    settings.delimiter,
                    settings.rounding_mode,
                    variables,
                )
                variables[var_name] = result.copy()
                variables["ans"] = result^
            except:
                continue  # error already displayed
        else:
            # Regular expression — evaluate and update ans
            _eval_line(line, settings, variables)


def _eval_line(
    expr: String,
    settings: Settings,
    mut variables: Dict[String, Decimal],
):
    """Evaluate an expression with the given settings and update `ans`."""
    try:
        var result = evaluate_and_return(
            expr,
            settings.precision,
            settings.scientific,
            settings.engineering,
            settings.pad,
            settings.delimiter,
            settings.rounding_mode,
            variables,
        )
        variables["ans"] = result^
    except:
        pass  # error already displayed by evaluate_and_return


def _is_meta_command(line: String) -> Bool:
    """Check if a line is a meta-command (starts with `:` after whitespace)."""
    var bytes = StringSlice(line).as_bytes()
    var n = len(bytes)
    var i = 0
    while i < n and (bytes[i] == 32 or bytes[i] == 9):
        i += 1
    return i < n and bytes[i] == 58  # ':'


def _strip_colon_prefix(line: String) -> String:
    """Strip leading whitespace and the `:` prefix from a meta-command."""
    var bytes = StringSlice(line).as_bytes()
    var n = len(bytes)
    var i = 0
    while i < n and (bytes[i] == 32 or bytes[i] == 9):
        i += 1
    if i < n and bytes[i] == 58:  # ':'
        i += 1
    var result = List[UInt8](capacity=n - i)
    for j in range(i, n):
        result.append(bytes[j])
    return String(unsafe_from_utf8=result^)


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
    if not is_alpha_or_underscore(line_bytes[i]):
        return None

    var name_start = i
    i += 1
    while i < n and is_alnum_or_underscore(line_bytes[i]):
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
    if is_known_function(name):
        return "cannot assign to '" + name + "' (built-in function)"
    if is_known_constant(name):
        return "cannot assign to '" + name + "' (built-in constant)"
    return None


def _print_banner(settings: Settings):
    """Prints the REPL welcome banner to stderr."""
    comptime title = (
        BOLD + YELLOW + "Decimo — an arbitrary-precision calculator 🔥\n" + RESET
    )
    comptime hints = "Type ? for help, : for settings, :q to quit."
    print(title + hints, file=stderr)
    print(String(settings), file=stderr)


# ===----------------------------------------------------------------------=== #
# Meta-command detection helpers
# ===----------------------------------------------------------------------=== #


def _is_help_command(cmd: String) -> Bool:
    """Match: help, h, ?."""
    return cmd == "help" or cmd == "h" or cmd == "?"


def _is_vars_command(cmd: String) -> Bool:
    """Match: vars."""
    return cmd == "vars"


def _is_about_command(cmd: String) -> Bool:
    """Match: about, a, info."""
    return cmd == "about" or cmd == "a" or cmd == "info"


def _is_version_command(cmd: String) -> Bool:
    """Match: version, v."""
    return cmd == "version" or cmd == "v"


def _is_quit_command(cmd: String) -> Bool:
    """Match: q, quit, exit."""
    return cmd == "q" or cmd == "quit" or cmd == "exit"


# ===----------------------------------------------------------------------=== #
# Meta-command display helpers
# ===----------------------------------------------------------------------=== #


def _print_settings(settings: Settings):
    """Display all current settings to stderr."""
    print(
        BOLD + CYAN + "Current settings" + RESET + BOLD + ":" + RESET,
        file=stderr,
    )
    print("  Precision     : " + String(settings.precision), file=stderr)
    print(
        "  Scientific    : " + ("on" if settings.scientific else "off"),
        file=stderr,
    )
    print(
        "  Engineering   : " + ("on" if settings.engineering else "off"),
        file=stderr,
    )
    print(
        "  Pad           : " + ("on" if settings.pad else "off"),
        file=stderr,
    )
    print(
        "  Delimiter     : "
        + ("'" + settings.delimiter + "'" if settings.delimiter else "(none)"),
        file=stderr,
    )
    print("  Rounding mode : " + String(settings.rounding_mode), file=stderr)


def _print_variables(variables: Dict[String, Decimal]) raises:
    """Display `ans` and all user-defined variables to stderr."""
    var count = len(variables)
    if count == 0:
        print("No variables defined.", file=stderr)
        return

    print(
        BOLD + CYAN + "Variables" + RESET + BOLD + ":" + RESET,
        file=stderr,
    )

    # Always show `ans` first if present
    if "ans" in variables:
        print(
            "  ans = " + variables["ans"].to_string(),
            file=stderr,
        )

    # Show user-defined variables
    for entry in variables.items():
        if entry.key != "ans":
            print(
                "  " + entry.key + " = " + entry.value.to_string(),
                file=stderr,
            )


def _print_help():
    """Display REPL-specific help to stderr.

    All description columns are aligned at visible column 30
    (2-char indent + 28-char command column).
    """
    # Colour aliases — zero visible width, used for styling only.
    comptime TITLE_COLOR = BOLD + YELLOW  # Title and important highlights
    comptime HEADING_COLOR = BOLD + CYAN  # section Heading
    comptime LONG_NAME_COLOR = BOLD + GREEN  # Long name / command
    comptime SHORT_NAME_COLOR = BOLD + YELLOW  # Short name / alias
    comptime VALUE_NAME_COLOR = MAGENTA  # Value placeholder

    var w = stderr

    # --- title ---
    print(
        TITLE_COLOR + "Decimo REPL help" + RESET + BOLD + ":" + RESET + "\n",
        file=w,
    )

    # --- expressions ---
    print(HEADING_COLOR + "Expressions" + RESET + BOLD + ":" + RESET, file=w)
    print("  Type any math expression to evaluate it.", file=w)
    print(
        "  Example: "
        + SHORT_NAME_COLOR
        + "pi + sin(-ln(1.23)) * sqrt(e^2)"
        + RESET
        + "\n",
        file=w,
    )

    # --- variables (col 28) ---
    print(HEADING_COLOR + "Variables" + RESET + BOLD + ":" + RESET, file=w)
    #     |name = expr       |                 <- 11 + 17 = 28
    print(
        "  "
        + VALUE_NAME_COLOR
        + "name"
        + RESET
        + " = "
        + VALUE_NAME_COLOR
        + "expr"
        + RESET
        + "                 Assign a value:  x = 1.023^365",
        file=w,
    )
    #     |ans               |                 <- 3 + 25 = 28
    print(
        "  "
        + LONG_NAME_COLOR
        + "ans"
        + RESET
        + "                         Refers to the last result.\n",
        file=w,
    )

    # --- functions ---
    print(HEADING_COLOR + "Functions" + RESET + BOLD + ":" + RESET, file=w)
    print(
        "  "
        + LONG_NAME_COLOR
        + "sqrt"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "cbrt"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "root"
        + RESET
        + "("
        + VALUE_NAME_COLOR
        + "x"
        + RESET
        + ","
        + VALUE_NAME_COLOR
        + "n"
        + RESET
        + ")  "
        + LONG_NAME_COLOR
        + "abs"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "exp"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "ln"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "log10"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "log"
        + RESET
        + "("
        + VALUE_NAME_COLOR
        + "x"
        + RESET
        + ","
        + VALUE_NAME_COLOR
        + "base"
        + RESET
        + ")",
        file=w,
    )
    print(
        "  "
        + LONG_NAME_COLOR
        + "sin"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "cos"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "tan"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "cot"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "csc"
        + RESET
        + "\n",
        file=w,
    )

    # --- constants ---
    print(HEADING_COLOR + "Constants" + RESET + BOLD + ":" + RESET, file=w)
    print(
        "  "
        + LONG_NAME_COLOR
        + "pi"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "e"
        + RESET
        + "\n",
        file=w,
    )

    # --- settings commands (col 28) ---
    print(
        HEADING_COLOR + "Settings commands" + RESET + BOLD + ":" + RESET, file=w
    )
    #     |:p, :precision N  |            <- 16 + 12 = 28
    print(
        "  "
        + SHORT_NAME_COLOR
        + ":p"
        + RESET
        + ", "
        + LONG_NAME_COLOR
        + ":precision"
        + RESET
        + " "
        + VALUE_NAME_COLOR
        + "N"
        + RESET
        + "            Set precision to "
        + VALUE_NAME_COLOR
        + "N"
        + RESET
        + " digits.",
        file=w,
    )
    #     |:N                |            <- 2 + 26 = 28
    print(
        "  "
        + SHORT_NAME_COLOR
        + ":"
        + RESET
        + VALUE_NAME_COLOR
        + "N"
        + RESET
        + "                          Shortcut for :p "
        + VALUE_NAME_COLOR
        + "N"
        + RESET
        + " (e.g. "
        + SHORT_NAME_COLOR
        + ":100"
        + RESET
        + ").",
        file=w,
    )
    #     |:s, :scientific, :sci|         <- 21 + 7 = 28
    print(
        "  "
        + SHORT_NAME_COLOR
        + ":s"
        + RESET
        + ", "
        + LONG_NAME_COLOR
        + ":scientific"
        + RESET
        + ", "
        + LONG_NAME_COLOR
        + ":sci"
        + RESET
        + "       Toggle scientific notation.",
        file=w,
    )
    #     |:e, :engineering, :eng|        <- 22 + 6 = 28
    print(
        "  "
        + SHORT_NAME_COLOR
        + ":e"
        + RESET
        + ", "
        + LONG_NAME_COLOR
        + ":engineering"
        + RESET
        + ", "
        + LONG_NAME_COLOR
        + ":eng"
        + RESET
        + "      Toggle engineering notation.",
        file=w,
    )
    #     |:pad              |            <- 4 + 24 = 28
    print(
        "  "
        + SHORT_NAME_COLOR
        + ":pad"
        + RESET
        + "                        Toggle zero-padding.",
        file=w,
    )
    #     |:r, :round, :rm MODE|          <- 20 + 8 = 28
    print(
        "  "
        + SHORT_NAME_COLOR
        + ":r"
        + RESET
        + ", "
        + LONG_NAME_COLOR
        + ":round"
        + RESET
        + ", "
        + LONG_NAME_COLOR
        + ":rm"
        + RESET
        + " "
        + VALUE_NAME_COLOR
        + "MODE"
        + RESET
        + "        Set rounding mode ("
        + SHORT_NAME_COLOR
        + "he"
        + RESET
        + "/"
        + SHORT_NAME_COLOR
        + "hu"
        + RESET
        + "/"
        + SHORT_NAME_COLOR
        + "hd"
        + RESET
        + "/"
        + SHORT_NAME_COLOR
        + "u"
        + RESET
        + "/"
        + SHORT_NAME_COLOR
        + "d"
        + RESET
        + "/"
        + SHORT_NAME_COLOR
        + "c"
        + RESET
        + "/"
        + SHORT_NAME_COLOR
        + "f"
        + RESET
        + "/"
        + SHORT_NAME_COLOR
        + "b"
        + RESET
        + ").",
        file=w,
    )
    #     |:delimiter C      |            <- 12 + 16 = 28
    print(
        "  "
        + LONG_NAME_COLOR
        + ":delimiter"
        + RESET
        + " "
        + VALUE_NAME_COLOR
        + "C"
        + RESET
        + "                Set digit-group delimiter.",
        file=w,
    )
    #     |:p 100 s r d      |            <- 12 + 16 = 28
    print(
        "  "
        + SHORT_NAME_COLOR
        + ":p 100 s r d"
        + RESET
        + "                Combine multiple settings in one line.\n",
        file=w,
    )

    # --- inline temp settings (col 28) ---
    print(
        HEADING_COLOR + "Inline temp settings" + RESET + BOLD + ":" + RESET,
        file=w,
    )
    #     |expr:settings     |            <- 13 + 15 = 28
    print(
        "  "
        + VALUE_NAME_COLOR
        + "expr"
        + RESET
        + ":"
        + VALUE_NAME_COLOR
        + "settings"
        + RESET
        + "               Override settings for one expression only.",
        file=w,
    )
    print(
        "  Example: " + SHORT_NAME_COLOR + "sqrt(2):p 100" + RESET + "\n",
        file=w,
    )

    # --- info commands (col 28) ---
    print(HEADING_COLOR + "Info commands" + RESET + BOLD + ":" + RESET, file=w)
    #     |:                 |            <- 1 + 27 = 28
    print(
        "  "
        + SHORT_NAME_COLOR
        + ":"
        + RESET
        + "                           Show current settings.",
        file=w,
    )
    #     |?, :help, :h, :?  |            <- 16 + 12 = 28
    print(
        "  "
        + SHORT_NAME_COLOR
        + "?"
        + RESET
        + ", "
        + LONG_NAME_COLOR
        + ":help"
        + RESET
        + ", "
        + SHORT_NAME_COLOR
        + ":h"
        + RESET
        + ", "
        + SHORT_NAME_COLOR
        + ":?"
        + RESET
        + "            Show this help.",
        file=w,
    )
    #     |$, :vars          |            <- 8 + 20 = 28
    print(
        "  "
        + SHORT_NAME_COLOR
        + "$"
        + RESET
        + ", "
        + LONG_NAME_COLOR
        + ":vars"
        + RESET
        + "                    List all variables.",
        file=w,
    )
    #     |:about, :a, :info|             <- 17 + 11 = 28
    print(
        "  "
        + LONG_NAME_COLOR
        + ":about"
        + RESET
        + ", "
        + SHORT_NAME_COLOR
        + ":a"
        + RESET
        + ", "
        + LONG_NAME_COLOR
        + ":info"
        + RESET
        + "           Show version, author, license, and links.",
        file=w,
    )
    #     |:version, :v      |            <- 12 + 16 = 28
    print(
        "  "
        + LONG_NAME_COLOR
        + ":version"
        + RESET
        + ", "
        + SHORT_NAME_COLOR
        + ":v"
        + RESET
        + "                Show version number.\n",
        file=w,
    )

    # --- quit ---
    print(HEADING_COLOR + "Quit" + RESET + BOLD + ":" + RESET, file=w)
    print(
        "  "
        + SHORT_NAME_COLOR
        + ":q"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "exit"
        + RESET
        + "  "
        + LONG_NAME_COLOR
        + "quit"
        + RESET
        + "  "
        + SHORT_NAME_COLOR
        + "Ctrl-D"
        + RESET,
        file=w,
    )
