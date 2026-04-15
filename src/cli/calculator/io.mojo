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
I/O utilities for the Decimo CLI calculator.

Provides functions for detecting whether stdin is a pipe or terminal,
reading lines from stdin, reading expression files, and line-level text
processing (comment stripping, whitespace handling).

The text-processing primitives (`strip_comment`, `is_blank`, `strip`)
are designed to be composable and reusable across all input modes —
pipe, file, and future REPL.
"""

from std.ffi import external_call


# ===----------------------------------------------------------------------=== #
# stdin detection
# ===----------------------------------------------------------------------=== #


def stdin_is_tty() -> Bool:
    """Returns True if stdin is connected to a terminal (TTY),
    False if it is a pipe or redirected file.

    Returns:
        True if stdin is a TTY, False otherwise.
    """
    return external_call["isatty", Int32](Int32(0)) != 0


# ===----------------------------------------------------------------------=== #
# stdin reading
# ===----------------------------------------------------------------------=== #


def read_line() -> Optional[String]:
    """Reads a single line from stdin (up to and including the newline).

    Returns the line content (without the trailing newline), or None
    on EOF (e.g. Ctrl-D on an empty line).

    This is designed for REPL use: it reads one character at a time
    via `getchar()` and stops at `\\n` or EOF.

    Returns:
        The line content without trailing newline, or None on EOF.
    """
    var chars = List[UInt8]()

    while True:
        var c = external_call["getchar", Int32]()
        if c < 0:  # EOF
            if len(chars) == 0:
                return None
            break
        if UInt8(c) == 10:  # '\n'
            break
        chars.append(UInt8(c))

    # Strip trailing \r if present (Windows line endings from copy-paste)
    if len(chars) > 0 and chars[len(chars) - 1] == 13:
        _ = chars.pop()

    if len(chars) == 0:
        return String("")

    return String(unsafe_from_utf8=chars^)


def read_stdin() -> String:
    """Reads all data from stdin and return it as a String.

    Uses the C `getchar()` function to read one byte at a time until
    EOF. This avoids FFI conflicts with the POSIX `read()` syscall.

    Returns:
        The full stdin content, or an empty string if stdin is empty.
    """
    var chunks = List[UInt8]()

    while True:
        var c = external_call["getchar", Int32]()
        if c < 0:  # EOF is -1
            break
        chunks.append(UInt8(c))

    if len(chunks) == 0:
        return String("")

    # String(unsafe_from_utf8=...) adds its own null terminator.
    return String(unsafe_from_utf8=chunks^)


# ===----------------------------------------------------------------------=== #
# Line splitting and text processing
# ===----------------------------------------------------------------------=== #


def split_into_lines(text: String) -> List[String]:
    """Splits a string into individual lines.

    Handles both `\\n` and `\\r\\n` line endings.
    Trailing empty lines from a final newline are not included.

    Args:
        text: The input string to split.

    Returns:
        A list of line strings without line terminators.
    """
    var lines = List[String]()
    var start = 0
    var text_len = len(text)

    for i in range(text_len):
        if text[byte=i] == "\n":
            # Handle \r\n
            var end = i
            if end > start and text[byte=end - 1] == "\r":
                end -= 1
            lines.append(String(text[byte=start:end]))
            start = i + 1

    # Handle last line without trailing newline
    if start < text_len:
        var last = String(text[byte=start:text_len])
        # Strip trailing \r if present
        if len(last) > 0 and last[byte=len(last) - 1] == "\r":
            last = String(last[byte = 0 : len(last) - 1])
        if len(last) > 0:
            lines.append(last)

    return lines^


def strip_comment(line: String) -> String:
    """Removes a `#`-style comment from a line.

    Returns everything before the first `#` character. If there is
    no `#`, the line is returned unchanged.

    This is a composable primitive — use it in combination with
    `strip()` and `is_blank()` for full line processing.

    Args:
        line: The input line to process.

    Returns:
        The line content before any `#` comment.

    Examples::

        strip_comment("1+2 # add")    → `1+2 `.
        strip_comment("# comment")    → `""`.
        strip_comment("sqrt(2)")      → `sqrt(2)`.
        strip_comment("")             → `""`.
    """
    var n = len(line)
    if n == 0:
        return String("")

    var bytes = StringSlice(line).as_bytes()
    var ptr = bytes.unsafe_ptr()

    for i in range(n):
        if ptr[i] == 35:  # '#'
            if i == 0:
                return String("")
            return String(line[byte=0:i])

    return line


def is_blank(line: String) -> Bool:
    """Returns True if the line is empty or contains only whitespace
    (spaces and tabs).

    This is a composable primitive — combine with `strip_comment()`
    to check for comment-or-blank lines.

    Args:
        line: The input line to check.

    Returns:
        True if the line is empty or whitespace-only.
    """
    var n = len(line)
    if n == 0:
        return True

    var bytes = StringSlice(line).as_bytes()
    var ptr = bytes.unsafe_ptr()

    for i in range(n):
        var c = ptr[i]
        if c != 32 and c != 9:  # not space, not tab
            return False

    return True


def is_comment_or_blank(line: String) -> Bool:
    """Returns True if the line is blank, whitespace-only, or a comment
    (first non-whitespace character is `#`).

    Equivalent to `is_blank(strip_comment(line))`.  Provided as a
    convenience for callers that do not need the intermediate results.

    Args:
        line: The input line to check.

    Returns:
        True if the line is blank or a comment.
    """
    return is_blank(strip_comment(line))


def strip(s: String) -> String:
    """Strips leading and trailing whitespace from a string.

    Removes spaces (32), tabs (9), carriage returns (13), and
    newlines (10).

    Args:
        s: The input string to strip.

    Returns:
        The string with leading and trailing whitespace removed.
    """
    var bytes = StringSlice(s).as_bytes()
    var ptr = bytes.unsafe_ptr()
    var start = 0
    var end = len(s)

    while start < end:
        var c = ptr[start]
        # space=32, tab=9, \r=13, \n=10
        if c != 32 and c != 9 and c != 13 and c != 10:
            break
        start += 1

    while end > start:
        var c = ptr[end - 1]
        if c != 32 and c != 9 and c != 13 and c != 10:
            break
        end -= 1

    if start >= end:
        return String("")
    return String(s[byte=start:end])


def filter_expression_lines(lines: List[String]) -> List[String]:
    """Filters a list of lines to only those that are valid expressions.

    Removes blank lines and comment lines (starting with `#`).
    Also strips inline comments and leading/trailing whitespace from
    each expression line.

    Args:
        lines: The input list of lines to filter.

    Returns:
        A new list containing only non-empty expression lines.
    """
    var result = List[String]()
    for i in range(len(lines)):
        var line = strip(strip_comment(lines[i]))
        if len(line) > 0:
            result.append(line)
    return result^


# ===----------------------------------------------------------------------=== #
# File reading
# ===----------------------------------------------------------------------=== #


def read_file_text(path: String) raises -> String:
    """Reads the entire contents of a file and returns it as a String.

    Uses POSIX `open()` + `dup2()` + `getchar()` to read the file
    by temporarily redirecting stdin.  This avoids FFI signature conflicts
    with Mojo's stdlib and ArgMojo for `read`/`fclose`.

    The original stdin is saved via `dup()` before redirection and
    restored afterwards, so callers (e.g. a future REPL `:load` command)
    can continue reading from the real stdin after this call returns.

    Args:
        path: The file path to read.

    Returns:
        The file contents as a string, or an empty string if the file is empty.

    Raises:
        If the file cannot be opened.
    """
    var c_path = _to_cstr(path)

    # Save original stdin so we can restore it after reading.
    var saved_stdin = external_call["dup", Int32](Int32(0))
    if saved_stdin < 0:
        raise Error("cannot save stdin (dup failed)")

    # open(path, O_RDONLY=0)
    var fd = external_call["open", Int32](c_path.unsafe_ptr(), Int32(0))
    if fd < 0:
        # Restore stdin before raising.
        _ = external_call["dup2", Int32](saved_stdin, Int32(0))
        _ = external_call["close", Int32](saved_stdin)
        raise Error("cannot open file: " + path)

    # Redirect stdin (fd 0) to the file
    var dup_result = external_call["dup2", Int32](fd, Int32(0))
    # Close the original fd — dup2 made a copy on fd 0.
    _ = external_call["close", Int32](fd)

    if dup_result < 0:
        # Restore stdin before raising.
        _ = external_call["dup2", Int32](saved_stdin, Int32(0))
        _ = external_call["close", Int32](saved_stdin)
        raise Error("cannot redirect stdin to file: " + path)

    # Read all bytes via getchar()
    var chunks = List[UInt8]()
    while True:
        var c = external_call["getchar", Int32]()
        if c < 0:  # EOF
            break
        chunks.append(UInt8(c))

    # Restore original stdin.
    _ = external_call["dup2", Int32](saved_stdin, Int32(0))
    _ = external_call["close", Int32](saved_stdin)

    if len(chunks) == 0:
        return String("")

    return String(unsafe_from_utf8=chunks^)


def file_exists(path: String) -> Bool:
    """Returns True if the given path exists as a readable file.

    Uses the POSIX `access()` syscall with `R_OK` (4).

    Args:
        path: The file path to check.

    Returns:
        True if the file exists and is readable.
    """
    var c_path = _to_cstr(path)
    # access(path, R_OK=4) returns 0 on success
    return external_call["access", Int32](c_path.unsafe_ptr(), Int32(4)) == 0


# ===----------------------------------------------------------------------=== #
# Internal helpers
# ===----------------------------------------------------------------------=== #


def _to_cstr(s: String) -> List[UInt8]:
    """Converts a Mojo String to a null-terminated C string (List[UInt8])."""
    var bytes = StringSlice(s).as_bytes()
    var c = List[UInt8](capacity=len(bytes) + 1)
    for i in range(len(bytes)):
        c.append(bytes[i])
    c.append(0)
    return c^
