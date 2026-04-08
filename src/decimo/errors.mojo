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
"""

from std.pathlib.path import cwd
import decimo.str


# ===--- ANSI Color Codes ---=== #
# Mimics Python/Rich traceback coloring style.

comptime _RESET = "\033[0m"
comptime _BOLD = "\033[1m"
comptime _DIM = "\033[2m"
comptime _UNDERLINE = "\033[4m"

comptime _RED = "\033[31m"
comptime _GREEN = "\033[32m"
comptime _YELLOW = "\033[33m"
comptime _BLUE = "\033[34m"
comptime _MAGENTA = "\033[35m"
comptime _CYAN = "\033[36m"
comptime _WHITE = "\033[37m"

# Semantic aliases for error formatting.
comptime _ERROR_TYPE = _BOLD + _RED  # Error type name (e.g., ValueError)
comptime _TRACEBACK = _DIM  # "Traceback (most recent call last)"
comptime _FILE_KEYWORD = _DIM  # "File" keyword
comptime _FILE_PATH = _CYAN  # File path
comptime _LINE_NUMBER = _GREEN  # Line numbers
comptime _FUNC_ARROW = _BOLD + _RED  # "---->" prefix
comptime _FUNC_NAME = _BOLD + _YELLOW  # Function name
comptime _MSG_TEXT = _WHITE  # Error message text
comptime _SEPARATOR = _DIM  # Separator line

comptime OverflowError = DecimoError[error_type="OverflowError"]
"""Type for overflow errors in Decimo.

Fields:

file: The file where the error occurred.\\
function: The function where the error occurred.\\
message: An optional message describing the error.\\
previous_error: An optional previous error that caused this error.
"""

comptime IndexError = DecimoError[error_type="IndexError"]
"""Type for index errors in Decimo.

Fields:

file: The file where the error occurred.\\
function: The function where the error occurred.\\
message: An optional message describing the error.\\
previous_error: An optional previous error that caused this error.
"""

comptime KeyError = DecimoError[error_type="KeyError"]
"""Type for key errors in Decimo.

Fields:

file: The file where the error occurred.\\
function: The function where the error occurred.\\
message: An optional message describing the error.\\
previous_error: An optional previous error that caused this error.
"""

comptime ValueError = DecimoError[error_type="ValueError"]
"""Type for value errors in Decimo.

Fields:

file: The file where the error occurred.\\
function: The function where the error occurred.\\ 
message: An optional message describing the error.\\
previous_error: An optional previous error that caused this error.
"""


comptime ZeroDivisionError = DecimoError[error_type="ZeroDivisionError"]

"""Type for divided-by-zero errors in Decimo.

Fields:

file: The file where the error occurred.\\
function: The function where the error occurred.\\
message: An optional message describing the error.\\
previous_error: An optional previous error that caused this error.
"""

comptime ConversionError = DecimoError[error_type="ConversionError"]

"""Type for conversion errors in Decimo.

Fields:

file: The file where the error occurred.\\
function: The function where the error occurred.\\
message: An optional message describing the error.\\
previous_error: An optional previous error that caused this error.
"""


struct DecimoError[error_type: String = "DecimoError"](Writable):
    """Base type for all Decimo errors.

    Parameters:
        error_type: The type of the error, e.g., "OverflowError", "IndexError".

    Fields:

    file: The file where the error occurred.\\
    function: The function where the error occurred.\\
    message: An optional message describing the error.\\
    previous_error: An optional previous error that caused this error.
    """

    var file: String
    """The source file where the error occurred."""
    var function: String
    """The function name where the error occurred."""
    var message: Optional[String]
    """An optional message describing the error."""
    var previous_error: Optional[String]
    """An optional formatted string of a previous error that caused this one."""

    def __init__(
        out self,
        file: String,
        function: String,
        message: Optional[String],
        previous_error: Optional[Error],
    ):
        """Creates a new `DecimoError` with the given context.

        Args:
            file: The source file where the error occurred.
            function: The function name where the error occurred.
            message: An optional message describing the error.
            previous_error: An optional previous error that caused this one.
        """
        self.file = file
        self.function = function
        self.message = message
        if previous_error is None:
            self.previous_error = None
        else:
            self.previous_error = "\n".join(
                String(previous_error.value()).split("\n")[3:]
            )

    def write_to[W: Writer](self, mut writer: W):
        """Writes a formatted error traceback to a writer.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        # Separator line
        writer.write("\n")
        writer.write(_SEPARATOR)
        writer.write(("-" * 80))
        writer.write(_RESET)
        writer.write("\n")

        # Error type (bold red) + Traceback header (dim)
        writer.write(_ERROR_TYPE)
        writer.write(decimo.str.ljust(String(Self.error_type), 47, " "))
        writer.write(_RESET)
        writer.write(_TRACEBACK)
        writer.write("Traceback (most recent call last)")
        writer.write(_RESET)
        writer.write("\n")

        # File path (cyan)
        writer.write(_FILE_KEYWORD)
        writer.write("File ")
        writer.write(_RESET)
        writer.write('"')
        writer.write(_FILE_PATH)
        try:
            writer.write(String(cwd()))
        except e:
            pass
        finally:
            writer.write("/")
        writer.write(self.file)
        writer.write(_RESET)
        writer.write('"')
        writer.write("\n")

        # Function name (bold yellow with red arrow)
        writer.write(_FUNC_ARROW)
        writer.write("----> ")
        writer.write(_RESET)
        writer.write(_FUNC_NAME)
        writer.write(self.function)
        writer.write(_RESET)

        # Error message
        if self.message is None:
            writer.write("\n")
        else:
            writer.write("\n\n")
            writer.write(_ERROR_TYPE)
            writer.write(Self.error_type)
            writer.write(_RESET)
            writer.write(": ")
            writer.write(_MSG_TEXT)
            writer.write(self.message.value())
            writer.write(_RESET)
            writer.write("\n")

        # Chained previous error
        if self.previous_error is not None:
            writer.write("\n")
            writer.write(self.previous_error.value())
