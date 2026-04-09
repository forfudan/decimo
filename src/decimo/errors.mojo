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
Implements error handling for Decimo.

The error messages follow the Python traceback format as closely as possible:

```
Traceback (most recent call last):
  File "/path/to/file.mojo", line 42, in my_function
ValueError: description of what went wrong
```

File name and line number are automatically captured at the raise site using
`call_location()`. Function name must be provided manually since Mojo does not
have a built-in way to get the current function name at runtime.
"""

from std.reflection import call_location


# ===--- ANSI Color Codes ---=== #
# Mimics Python/Rich traceback coloring style.

comptime _RESET = "\033[0m"
comptime _BOLD = "\033[1m"
comptime _DIM = "\033[2m"

comptime _RED = "\033[31m"
comptime _GREEN = "\033[32m"
comptime _YELLOW = "\033[33m"
comptime _BLUE = "\033[34m"
comptime _MAGENTA = "\033[35m"
comptime _CYAN = "\033[36m"
comptime _WHITE = "\033[37m"

# Semantic aliases for error formatting.
comptime _CLR_ERROR_TYPE = _BOLD + _RED  # Error type name (e.g., ValueError)
comptime _CLR_TRACEBACK = _BOLD  # "Traceback (most recent call last):"
comptime _CLR_FILE_PATH = _MAGENTA  # File path
comptime _CLR_LINE_NUM = _GREEN  # Line number
comptime _CLR_FUNC_NAME = _YELLOW  # Function name
comptime _CLR_MSG_TEXT = _BOLD  # Error message text
comptime _CLR_CHAIN_MSG = _DIM  # Chained error separator message

comptime OverflowError = DecimoError[error_type="OverflowError"]
"""Type for overflow errors in Decimo."""

comptime IndexError = DecimoError[error_type="IndexError"]
"""Type for index errors in Decimo."""

comptime KeyError = DecimoError[error_type="KeyError"]
"""Type for key errors in Decimo."""

comptime ValueError = DecimoError[error_type="ValueError"]
"""Type for value errors in Decimo."""

comptime ZeroDivisionError = DecimoError[error_type="ZeroDivisionError"]
"""Type for divided-by-zero errors in Decimo."""

comptime ConversionError = DecimoError[error_type="ConversionError"]
"""Type for conversion errors in Decimo."""


struct DecimoError[error_type: StringLiteral = "DecimoError"](Writable):
    """Base type for all Decimo errors.

    The error message format mimics Python's traceback:

    ```
    Traceback (most recent call last):
      File "/path/to/file.mojo", line 42, in my_function
    ValueError: description of what went wrong
    ```

    File name and line number are automatically captured at the raise site.
    Function name must be provided manually since Mojo does not yet support
    runtime introspection of the current function name.

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

    @always_inline
    def __init__(
        out self,
        *,
        message: String,
        function: String,
        previous_error: Optional[Error] = None,
    ):
        """Creates a new `DecimoError` with auto-captured file and line.

        File name and line number are automatically captured from the call site.

        Args:
            message: A message describing the error.
            function: The function name where the error occurred.
            previous_error: An optional previous error that caused this one.
        """
        var loc = call_location()
        self.file = String(loc.file_name)
        self.line = loc.line
        self.function = function
        self.message = message
        if previous_error is None:
            self.previous_error = None
        else:
            self.previous_error = String(previous_error.value())

    def write_to[W: Writer](self, mut writer: W):
        """Writes a Python-style formatted error traceback to a writer.

        Output format (colored with ANSI codes):

        ```
        Traceback (most recent call last):
          File "/path/to/file.mojo", line 42, in my_function
        ValueError: description of what went wrong
        ```

        When a previous error is chained:

        ```
        Traceback (most recent call last):
          File "/path/to/inner.mojo", line 10
        ValueError: inner error message

        The above exception was the direct cause of the following exception:

        Traceback (most recent call last):
          File "/path/to/outer.mojo", line 20, in outer_function
        DecimoError: outer error message
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
            writer.write("\n")

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
