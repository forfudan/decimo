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
        writer.write("\n")
        writer.write(("-" * 80))
        writer.write("\n")
        writer.write(decimo.str.ljust(String(Self.error_type), 47, " "))
        writer.write("Traceback (most recent call last)\n")
        writer.write('File "')
        try:
            writer.write(String(cwd()))
        except e:
            pass
        finally:
            writer.write("/")
        writer.write(self.file)
        writer.write('"\n')
        writer.write("----> ")
        writer.write(self.function)
        if self.message is None:
            writer.write("\n")
        else:
            writer.write("\n\n")
            writer.write(Self.error_type)
            writer.write(": ")
            writer.write(self.message.value())
            writer.write("\n")
        if self.previous_error is not None:
            writer.write("\n")
            writer.write(self.previous_error.value())
