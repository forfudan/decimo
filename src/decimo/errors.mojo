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
Implements error handling for Decimo.

The error messages follow the Python traceback format as closely as possible:

```
Traceback (most recent call last):
  File "./src/decimo/bigint/bigint.mojo", line 42, in my_function
ValueError: description of what went wrong
```

A raise site names the kind, the enclosing function and the message:

```mojo
raise ValueError(function="my_function", message="what went wrong")
```

File name and line number are automatically captured at the raise site using
`call_location()`. The absolute path is automatically shortened to a relative
path (e.g. `./src/...`, `./tests/...`) for readability and privacy.
Function name must be provided manually since Mojo does not have a built-in way
to get the current function name at runtime.

Every kind returns a plain `Error`, so the enclosing function needs nothing
beyond a bare `raises`. Set `_USE_COLOUR` to `False` to emit the tracebacks
without ANSI escapes.
"""

from std.reflection import call_location


# ===----------------------------------------------------------------------=== #
# ANSI colour codes
#
# Mimics Python/Rich traceback colouring style. Set `_USE_COLOUR` to False to
# emit plain text - worth doing if the escapes ever show up as literal
# `\033[1m` noise in a log file rather than as colour in a terminal.
# ===----------------------------------------------------------------------=== #

comptime _USE_COLOUR = True

comptime _RESET = "\033[0m" if _USE_COLOUR else ""
comptime _BOLD = "\033[1m" if _USE_COLOUR else ""
comptime _DIM = "\033[2m" if _USE_COLOUR else ""

comptime _RED = "\033[31m" if _USE_COLOUR else ""
comptime _GREEN = "\033[32m" if _USE_COLOUR else ""
comptime _YELLOW = "\033[33m" if _USE_COLOUR else ""
comptime _BLUE = "\033[34m" if _USE_COLOUR else ""
comptime _MAGENTA = "\033[35m" if _USE_COLOUR else ""
comptime _CYAN = "\033[36m" if _USE_COLOUR else ""
comptime _WHITE = "\033[37m" if _USE_COLOUR else ""

# Semantic aliases for error formatting.
comptime _CLR_ERROR_TYPE = _BOLD + _RED  # Error type name (e.g., ValueError)
comptime _CLR_TRACEBACK = _BOLD  # "Traceback (most recent call last):"
comptime _CLR_FILE_PATH = _MAGENTA  # File path
comptime _CLR_LINE_NUM = _GREEN  # Line number
comptime _CLR_FUNC_NAME = _YELLOW  # Function name
comptime _CLR_MSG_TEXT = _BOLD  # Error message text
comptime _CLR_CHAIN_MSG = _DIM  # Chained error separator message


# ===----------------------------------------------------------------------=== #
# Path shortening
# ===----------------------------------------------------------------------=== #


@always_inline
def _shorten_path(full_path: String) -> String:
    """Shorten an absolute file path to a relative path.

    Looks for known directory markers (`src/`, `tests/`, `benches/`) and
    returns a `./`-prefixed relative path from the rightmost marker found.
    If no marker is found, returns just the filename.

    Uses `rfind` (reverse search) to handle paths that contain a marker more
    than once, e.g. `/home/user/src/projects/decimo/src/decimo/bigint.mojo`
    correctly shortens to `./src/decimo/bigint.mojo`.  When more than one
    marker type appears, the rightmost position wins to produce the shortest
    possible relative path.

    Args:
        full_path: The absolute file path to shorten.

    Returns:
        A shortened relative path string.

    Notes:

    Forwards to a `@no_inline` implementation so the multi-`rfind` +
    string slicing work stays out of every inlined `raise` site.
    """
    return _shorten_path_implementation(full_path)


@no_inline
def _shorten_path_implementation(full_path: String) -> String:
    var src_idx = full_path.rfind("src/")
    var tests_idx = full_path.rfind("tests/")
    var benches_idx = full_path.rfind("benches/")

    # We need to handle the cases like the following paths:
    # .../tests/.../src/...
    # .../benches/.../src/...
    var idx = src_idx
    if tests_idx > idx:
        idx = tests_idx
    if benches_idx > idx:
        idx = benches_idx

    if idx >= 0:
        return "./" + String(full_path[byte=idx:])
    var last_slash = full_path.rfind("/")
    if last_slash >= 0:
        return String(full_path[byte = last_slash + 1 :])
    return full_path


# ===----------------------------------------------------------------------=== #
# Error kinds
#
# Each kind is a function that wraps a `BaseError` payload in a plain `Error`,
# rather than a type alias for the payload itself.
#
# [Mojo Miji]
# A typed raise is invariant in Mojo 1.0.0: a function declared
# `raises ValueError` may not call one declared with a bare `raises`, so it can
# reach neither `std.testing` nor any ordinary helper, and the restriction
# spreads up the call chain from wherever it is introduced. Spelling the kinds
# as functions leaves `raises ValueError` unwritable, which keeps that dead end
# out of reach.
#
# Each one is `@always_inline` so that the `call_location()` inside reports the
# `raise` site rather than a line in this file.
# ===----------------------------------------------------------------------=== #


@always_inline
def DecimoError(
    *,
    function: String,
    message: String,
    previous_error: Optional[Error] = None,
) -> Error:
    """Builds an `Error` describing general errors in Decimo.

    Args:
        function: The function where the error occurred.
        message: A message describing the error.
        previous_error: An optional previous error that caused this error.

    Returns:
        An `Error` carrying a `BaseError["DecimoError"]` payload.
    """
    var loc = call_location()
    return Error(
        BaseError[error_type="DecimoError"](
            _shorten_path(String(loc.file_name())),
            loc.line(),
            function,
            message,
            previous_error,
        )
    )


@always_inline
def OverflowError(
    *,
    function: String,
    message: String,
    previous_error: Optional[Error] = None,
) -> Error:
    """Builds an `Error` describing overflow errors in Decimo.

    Args:
        function: The function where the error occurred.
        message: A message describing the error.
        previous_error: An optional previous error that caused this error.

    Returns:
        An `Error` carrying a `BaseError["OverflowError"]` payload.
    """
    var loc = call_location()
    return Error(
        BaseError[error_type="OverflowError"](
            _shorten_path(String(loc.file_name())),
            loc.line(),
            function,
            message,
            previous_error,
        )
    )


@always_inline
def IndexError(
    *,
    function: String,
    message: String,
    previous_error: Optional[Error] = None,
) -> Error:
    """Builds an `Error` describing index errors in Decimo.

    Args:
        function: The function where the error occurred.
        message: A message describing the error.
        previous_error: An optional previous error that caused this error.

    Returns:
        An `Error` carrying a `BaseError["IndexError"]` payload.
    """
    var loc = call_location()
    return Error(
        BaseError[error_type="IndexError"](
            _shorten_path(String(loc.file_name())),
            loc.line(),
            function,
            message,
            previous_error,
        )
    )


@always_inline
def KeyError(
    *,
    function: String,
    message: String,
    previous_error: Optional[Error] = None,
) -> Error:
    """Builds an `Error` describing key errors in Decimo.

    Args:
        function: The function where the error occurred.
        message: A message describing the error.
        previous_error: An optional previous error that caused this error.

    Returns:
        An `Error` carrying a `BaseError["KeyError"]` payload.
    """
    var loc = call_location()
    return Error(
        BaseError[error_type="KeyError"](
            _shorten_path(String(loc.file_name())),
            loc.line(),
            function,
            message,
            previous_error,
        )
    )


@always_inline
def ValueError(
    *,
    function: String,
    message: String,
    previous_error: Optional[Error] = None,
) -> Error:
    """Builds an `Error` describing value errors in Decimo.

    Args:
        function: The function where the error occurred.
        message: A message describing the error.
        previous_error: An optional previous error that caused this error.

    Returns:
        An `Error` carrying a `BaseError["ValueError"]` payload.
    """
    var loc = call_location()
    return Error(
        BaseError[error_type="ValueError"](
            _shorten_path(String(loc.file_name())),
            loc.line(),
            function,
            message,
            previous_error,
        )
    )


@always_inline
def ZeroDivisionError(
    *,
    function: String,
    message: String,
    previous_error: Optional[Error] = None,
) -> Error:
    """Builds an `Error` describing divided-by-zero errors in Decimo.

    Args:
        function: The function where the error occurred.
        message: A message describing the error.
        previous_error: An optional previous error that caused this error.

    Returns:
        An `Error` carrying a `BaseError["ZeroDivisionError"]` payload.
    """
    var loc = call_location()
    return Error(
        BaseError[error_type="ZeroDivisionError"](
            _shorten_path(String(loc.file_name())),
            loc.line(),
            function,
            message,
            previous_error,
        )
    )


@always_inline
def ConversionError(
    *,
    function: String,
    message: String,
    previous_error: Optional[Error] = None,
) -> Error:
    """Builds an `Error` describing conversion errors in Decimo.

    Args:
        function: The function where the error occurred.
        message: A message describing the error.
        previous_error: An optional previous error that caused this error.

    Returns:
        An `Error` carrying a `BaseError["ConversionError"]` payload.
    """
    var loc = call_location()
    return Error(
        BaseError[error_type="ConversionError"](
            _shorten_path(String(loc.file_name())),
            loc.line(),
            function,
            message,
            previous_error,
        )
    )


@always_inline
def RuntimeError(
    *,
    function: String,
    message: String,
    previous_error: Optional[Error] = None,
) -> Error:
    """Builds an `Error` describing runtime infrastructure errors in Decimo.

    Resource allocation failures and missing native libraries are the two
    cases this covers.

    Args:
        function: The function where the error occurred.
        message: A message describing the error.
        previous_error: An optional previous error that caused this error.

    Returns:
        An `Error` carrying a `BaseError["RuntimeError"]` payload.
    """
    var loc = call_location()
    return Error(
        BaseError[error_type="RuntimeError"](
            _shorten_path(String(loc.file_name())),
            loc.line(),
            function,
            message,
            previous_error,
        )
    )


# ===----------------------------------------------------------------------=== #
# The payload
# ===----------------------------------------------------------------------=== #


struct BaseError[error_type: String = "BaseError"](Writable):
    """Base type for all Decimo errors.

    The error message format mimics Python's traceback:

    ```
    Traceback (most recent call last):
      File "./src/decimo/bigint/bigint.mojo", line 42, in my_function
    ValueError: description of what went wrong
    ```

    File name and line number are captured at the raise site by the error kind
    that builds the payload; the function name is supplied by the caller, since
    Mojo does not yet support runtime introspection of the current function
    name.

    Parameters:
        error_type: The type of the error, e.g., "OverflowError", "IndexError".
    """

    var file: String
    """The source file where the error occurred (auto-captured)."""
    var line: Int
    """The line number where the error occurred (auto-captured)."""
    var function: String
    """The function name where the error occurred."""
    var message: String
    """A message describing the error."""
    var previous_error: Optional[String]
    """An optional formatted string of a previous error that caused this one."""

    def __init__(
        out self,
        file: String,
        line: Int,
        function: String,
        message: String,
        previous_error: Optional[Error],
    ):
        """Creates a new `BaseError`.

        Args:
            file: The file where the error occurred, already shortened.
            line: The line number where the error occurred.
            function: The function name where the error occurred.
            message: A message describing the error.
            previous_error: An optional previous error that caused this one.
        """
        self.file = file
        self.line = line
        self.function = function
        self.message = message
        if previous_error is None:
            self.previous_error = None
        else:
            self.previous_error = String(previous_error.value())

    def write_to[W: Writer, //](self, mut writer: W):
        """Writes a Python-style formatted error traceback to a writer.

        Output format (colored with ANSI codes):

        ```
        Traceback (most recent call last):
          File "./src/decimo/bigint/bigint.mojo", line 42, in my_function
        ValueError: description of what went wrong
        ```

        When a previous error is chained:

        ```
        Traceback (most recent call last):
          File "./src/decimo/bigint/bigint.mojo", line 10, in inner_function
        ValueError: inner error message

        The above exception was the direct cause of the following exception:

        Traceback (most recent call last):
          File "./src/decimo/bigint/bigint.mojo", line 20, in outer_function
        BaseError: outer error message
        ```

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        # Chained previous error (printed FIRST, like Python)
        if self.previous_error is not None:
            writer.write(self.previous_error.value())
            writer.write("\n")
            writer.write(_CLR_CHAIN_MSG)
            writer.write(
                "The above exception was the direct cause of the following"
                " exception:"
            )
            writer.write(_RESET)
            writer.write("\n\n")

        # "Traceback (most recent call last):"
        writer.write(_CLR_TRACEBACK)
        writer.write("Traceback (most recent call last):")
        writer.write(_RESET)
        writer.write("\n")

        # '  File "/path/to/file.mojo", line 42, in function_name'
        writer.write("  File ")
        writer.write('"')
        writer.write(_CLR_FILE_PATH)
        writer.write(self.file)
        writer.write(_RESET)
        writer.write('"')
        writer.write(", line ")
        writer.write(_CLR_LINE_NUM)
        writer.write(String(self.line))
        writer.write(_RESET)
        writer.write(", in ")
        writer.write(_CLR_FUNC_NAME)
        writer.write(self.function)
        writer.write(_RESET)
        writer.write("\n")

        # "ValueError: description of what went wrong"
        writer.write(_CLR_ERROR_TYPE)
        writer.write(Self.error_type)
        writer.write(_RESET)
        writer.write(": ")
        writer.write(_CLR_MSG_TEXT)
        writer.write(self.message)
        writer.write(_RESET)
        writer.write("\n")
