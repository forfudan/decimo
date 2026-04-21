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
Display utilities for the Decimo CLI calculator.

Provides coloured error and warning output to stderr, and a
visual caret indicator that points at the offending position
in an expression.  Modelled after ArgMojo's colour system.

```text
  decimo "1 + @ * 2"
  Error: unexpected character '@'
    1 + @ * 2
        ^
```
"""

from std.sys import stderr
from std.sys.defines import MOJO_VERSION
from decimo import DECIMO_VERSION_TAG

# == ANSI colour codes ========================================================

comptime RESET = "\x1b[0m"
"""ANSI escape code to reset all attributes."""
comptime BOLD = "\x1b[1m"
"""ANSI escape code for bold text."""

# Bright foreground colours.
comptime RED = "\x1b[91m"
"""ANSI escape code for bright red."""
comptime GREEN = "\x1b[92m"
"""ANSI escape code for bright green."""
comptime YELLOW = "\x1b[93m"
"""ANSI escape code for bright yellow."""
comptime BLUE = "\x1b[94m"
"""ANSI escape code for bright blue."""
comptime MAGENTA = "\x1b[95m"
"""ANSI escape code for bright magenta."""
comptime CYAN = "\x1b[96m"
"""ANSI escape code for bright cyan."""
comptime WHITE = "\x1b[97m"
"""ANSI escape code for bright white."""
comptime ORANGE = "\x1b[33m"  # dark yellow — renders as orange on most terminals
"""ANSI escape code for orange (dark yellow)."""

# Semantic aliases.
comptime ERROR_COLOR = RED
"""Colour used for error labels."""
comptime WARNING_COLOR = ORANGE
"""Colour used for warning labels."""
comptime HINT_COLOR = YELLOW
"""Colour used for hint labels."""
comptime CARET_COLOR = GREEN
"""Colour used for caret indicators."""


# == Public API ===============================================================


def print_error(message: String):
    """Print a coloured error message to stderr.

    Format:  `Error: <message>`

    The label `Error` is displayed in bold red.  The message text
    follows in the default terminal colour.

    Args:
        message: Human-readable error description.
    """
    _write_stderr(
        BOLD + ERROR_COLOR + "Error" + RESET + BOLD + ": " + RESET + message
    )


def print_error(message: String, expr: String, position: Int):
    """Print a coloured error message with a caret pointing at
    the offending position in `expr`.

    Example output (colours omitted for docstring):

    ```text
    Error: unexpected character '@'
      1 + @ * 2
          ^
    ```

    Args:
        message: Human-readable error description.
        expr: The original expression string.
        position: 0-based column index to place the caret indicator.
    """
    _write_stderr(
        BOLD + ERROR_COLOR + "Error" + RESET + BOLD + ": " + RESET + message
    )
    _write_caret(expr, position)


def print_warning(message: String):
    """Prints a coloured warning message to stderr.

    Format:  `Warning: <message>`

    The label `Warning` is displayed in bold orange/yellow.

    Args:
        message: Human-readable warning description.
    """
    _write_stderr(
        BOLD + WARNING_COLOR + "Warning" + RESET + BOLD + ": " + RESET + message
    )


def print_warning(message: String, expr: String, position: Int):
    """Prints a coloured warning message with a caret indicator.

    Args:
        message: Human-readable warning description.
        expr: The original expression string.
        position: 0-based column index to place the caret indicator.
    """
    _write_stderr(
        BOLD + WARNING_COLOR + "Warning" + RESET + BOLD + ": " + RESET + message
    )
    _write_caret(expr, position)


def print_hint(message: String):
    """Prints a coloured hint message to stderr.

    Format:  `Hint: <message>`

    The label `Hint` is displayed in bold yellow.

    Args:
        message: Human-readable hint text.
    """
    _write_stderr(
        BOLD + HINT_COLOR + "Hint" + RESET + BOLD + ": " + RESET + message
    )


def write_prompt(prompt: String):
    """Writes a REPL prompt to stderr (no trailing newline).

    The prompt is written to stderr so that stdout remains clean for
    piping results.

    Args:
        prompt: The prompt string to display.
    """
    var styled = BOLD + GREEN + prompt + RESET
    print(styled, end="", file=stderr, flush=True)


# === About / Info ============================================================


def format_about(use_color: Bool = True) -> String:
    """Returns a formatted about/info string.

    Used by both ``--about`` (CLI, printed to stdout) and ``:about``
    (REPL, printed to stderr).  When *use_color* is False the output
    contains no ANSI escape codes, suitable for piped/redirected output.

    Args:
        use_color: Whether to include ANSI colour codes.  Defaults to True.

    Returns:
        A formatted multi-line string containing information about Decimo.
    """
    var title_color = BOLD + ORANGE if use_color else ""
    var label_color = BOLD + MAGENTA if use_color else ""
    var reset = RESET if use_color else ""
    return (
        title_color
        + "Decimo — arbitrary-precision calculator 🔥"
        + reset
        + "\n"
        + label_color
        + "  Version       "
        + reset
        + DECIMO_VERSION_TAG
        + "\n"
        + label_color
        + "  Author        "
        + reset
        + "ZHU Yuhao (朱宇浩) <dr.yuhao.zhu@outlook.com>"
        + "\n"
        + label_color
        + "  License       "
        + reset
        + "Apache-2.0"
        + "\n"
        + label_color
        + "  Mojo          "
        + reset
        + "v"
        + String(MOJO_VERSION.major)
        + "."
        + String(MOJO_VERSION.minor)
        + "."
        + String(MOJO_VERSION.patch)
        + "\n"
        + label_color
        + "  GitHub        "
        + reset
        + "https://github.com/forfudan/decimo"
        + "\n"
        + label_color
        + "  Documentation "
        + reset
        + "https://github.com/forfudan/decimo/blob/main/docs/user_manual.md"
    )


# == Internal helpers =========================================================


def _write_stderr(msg: String):
    """Writes a line to stderr."""
    print(msg, file=stderr)


def _write_caret(expr: String, position: Int):
    """Prints the expression line and a green caret (^) under the
    given column position to stderr.

    ```text
      1 + @ * 2
          ^
    ```
    """
    # Expression line — indented by 2 spaces.
    _write_stderr("  " + expr)

    # Caret line — spaces + coloured '^'.
    var caret_col = position if position >= 0 else 0
    if caret_col > len(expr):
        caret_col = len(expr)
    _write_stderr("  " + " " * caret_col + CARET_COLOR + "^" + RESET)
