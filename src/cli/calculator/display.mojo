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

# ── ANSI colour codes ────────────────────────────────────────────────────────

comptime RESET = "\x1b[0m"
comptime BOLD = "\x1b[1m"

# Bright foreground colours.
comptime RED = "\x1b[91m"
comptime GREEN = "\x1b[92m"
comptime YELLOW = "\x1b[93m"
comptime BLUE = "\x1b[94m"
comptime MAGENTA = "\x1b[95m"
comptime CYAN = "\x1b[96m"
comptime WHITE = "\x1b[97m"
comptime ORANGE = "\x1b[33m"  # dark yellow — renders as orange on most terminals

# Semantic aliases.
comptime ERROR_COLOR = RED
comptime WARNING_COLOR = ORANGE
comptime HINT_COLOR = YELLOW
comptime CARET_COLOR = GREEN


# ── Public API ───────────────────────────────────────────────────────────────


def print_error(message: String):
    """Print a coloured error message to stderr.

    Format:  `Error: <message>`

    The label `Error` is displayed in bold red.  The message text
    follows in the default terminal colour.
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
    """
    _write_stderr(
        BOLD + WARNING_COLOR + "Warning" + RESET + BOLD + ": " + RESET + message
    )


def print_warning(message: String, expr: String, position: Int):
    """Prints a coloured warning message with a caret indicator."""
    _write_stderr(
        BOLD + WARNING_COLOR + "Warning" + RESET + BOLD + ": " + RESET + message
    )
    _write_caret(expr, position)


def print_hint(message: String):
    """Prints a coloured hint message to stderr.

    Format:  `Hint: <message>`

    The label `Hint` is displayed in bold cyan.
    """
    _write_stderr(
        BOLD + HINT_COLOR + "Hint" + RESET + BOLD + ": " + RESET + message
    )


def write_prompt(prompt: String):
    """Writes a REPL prompt to stderr (no trailing newline).

    The prompt is written to stderr so that stdout remains clean for
    piping results.
    """
    var styled = BOLD + GREEN + prompt + RESET
    print(styled, end="", file=stderr, flush=True)


# ── Internal helpers ─────────────────────────────────────────────────────────


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
