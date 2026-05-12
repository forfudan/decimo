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
A TOML tokenizer for Mojo, implementing the core TOML v1.0 specification.
"""

comptime WHITESPACE = " \t"
"""Characters treated as whitespace between tokens."""
comptime COMMENT_START = "#"
"""Character that begins a TOML comment."""
comptime QUOTE = '"'
"""Character for basic (double-quoted) strings."""
comptime LITERAL_QUOTE = "'"
"""Character for literal (single-quoted) strings."""


struct Token(Copyable, Movable):
    """Represents a token in the TOML document."""

    var type: TokenType
    """The token's category."""
    var value: String
    """The token's text content."""
    var line: Int
    """The line number where this token appears (1-based)."""
    var column: Int
    """The column number where this token starts (1-based)."""

    def __init__(
        out self, type: TokenType, value: String, line: Int, column: Int
    ):
        """Creates a new `Token`.

        Args:
            type: The token's category.
            value: The token's text content.
            line: The line number where this token appears.
            column: The column number where this token starts.
        """
        self.type = type
        self.value = value
        self.line = line
        self.column = column


struct SourcePosition:
    """Tracks position in the source text."""

    var line: Int
    """The current line number (1-based)."""
    var column: Int
    """The current column number (1-based)."""
    var index: Int
    """The byte offset in the source string."""

    def __init__(out self, line: Int = 1, column: Int = 1, index: Int = 0):
        """Creates a new `SourcePosition`.

        Args:
            line: The initial line number.
            column: The initial column number.
            index: The initial byte offset.
        """
        self.line = line
        self.column = column
        self.index = index

    def advance(mut self, char: String):
        """Advances the position past the given character.

        Args:
            char: The character to advance past.
        """
        if char == "\n":
            self.line += 1
            self.column = 1
        else:
            self.column += 1
        self.index += char.byte_length()


struct TokenType(Copyable, ImplicitlyCopyable, Movable):
    """
    TokenType mimics an enum for token types in TOML.
    """

    # Aliases for TokenType static methods to mimic enum constants
    comptime KEY = TokenType.key()
    """Token type for TOML keys."""
    comptime STRING = TokenType.string()
    """Token type for string values."""
    comptime INTEGER = TokenType.integer()
    """Token type for integer values."""
    comptime FLOAT = TokenType.float()
    """Token type for floating-point values."""
    comptime BOOLEAN = TokenType.boolean()
    """Token type for boolean values."""
    comptime DATETIME = TokenType.datetime()
    """Token type for datetime values."""
    comptime ARRAY_START = TokenType.array_start()
    """Token type for array opening bracket `[`."""
    comptime ARRAY_END = TokenType.array_end()
    """Token type for array closing bracket `]`."""
    comptime TABLE_START = TokenType.table_start()
    """Token type for table header opening bracket `[`."""
    comptime TABLE_END = TokenType.table_end()
    """Token type for table header closing bracket `]`."""
    comptime ARRAY_OF_TABLES_START = TokenType.array_of_tables_start()
    """Token type for array-of-tables opening `[[`."""
    comptime EQUAL = TokenType.equal()
    """Token type for the `=` separator."""
    comptime COMMA = TokenType.comma()
    """Token type for the `,` separator."""
    comptime NEWLINE = TokenType.newline()
    """Token type for newline characters."""
    comptime DOT = TokenType.dot()
    """Token type for the `.` separator in dotted keys."""
    comptime EOF = TokenType.eof()
    """Token type for end of file."""
    comptime ERROR = TokenType.error()
    """Token type for lexer errors."""
    comptime INLINE_TABLE_START = TokenType.inline_table_start()
    """Token type for inline table opening brace `{`."""
    comptime INLINE_TABLE_END = TokenType.inline_table_end()
    """Token type for inline table closing brace `}`."""

    # Attributes
    var value: Int
    """The underlying integer identifier."""

    # Token type constants (lowercase method names)
    @staticmethod
    def key() -> TokenType:
        """Creates a `TokenType` representing a TOML key.

        Returns:
            A `TokenType` for keys.
        """
        return TokenType(0)

    @staticmethod
    def string() -> TokenType:
        """Creates a `TokenType` representing a string value.

        Returns:
            A `TokenType` for strings.
        """
        return TokenType(1)

    @staticmethod
    def integer() -> TokenType:
        """Creates a `TokenType` representing an integer value.

        Returns:
            A `TokenType` for integers.
        """
        return TokenType(2)

    @staticmethod
    def float() -> TokenType:
        """Creates a `TokenType` representing a floating-point value.

        Returns:
            A `TokenType` for floats.
        """
        return TokenType(3)

    @staticmethod
    def boolean() -> TokenType:
        """Creates a `TokenType` representing a boolean value.

        Returns:
            A `TokenType` for booleans.
        """
        return TokenType(4)

    @staticmethod
    def datetime() -> TokenType:
        """Creates a `TokenType` representing a datetime value.

        Returns:
            A `TokenType` for datetimes.
        """
        return TokenType(5)

    @staticmethod
    def array_start() -> TokenType:
        """Creates a `TokenType` representing an array opening bracket `[`.

        Returns:
            A `TokenType` for array starts.
        """
        return TokenType(6)

    @staticmethod
    def array_end() -> TokenType:
        """Creates a `TokenType` representing an array closing bracket `]`.

        Returns:
            A `TokenType` for array ends.
        """
        return TokenType(7)

    @staticmethod
    def table_start() -> TokenType:
        """Creates a `TokenType` representing a table header opening `[`.

        Returns:
            A `TokenType` for table starts.
        """
        return TokenType(8)

    @staticmethod
    def table_end() -> TokenType:
        """Creates a `TokenType` representing a table header closing `]`.

        Returns:
            A `TokenType` for table ends.
        """
        return TokenType(9)

    @staticmethod
    def array_of_tables_start() -> TokenType:
        """Creates a `TokenType` representing an array-of-tables opening `[[`.

        Returns:
            A `TokenType` for array-of-tables starts.
        """
        return TokenType(16)

    @staticmethod
    def equal() -> TokenType:
        """Creates a `TokenType` representing the `=` separator.

        Returns:
            A `TokenType` for equals signs.
        """
        return TokenType(10)

    @staticmethod
    def comma() -> TokenType:
        """Creates a `TokenType` representing the `,` separator.

        Returns:
            A `TokenType` for commas.
        """
        return TokenType(11)

    @staticmethod
    def newline() -> TokenType:
        """Creates a `TokenType` representing a newline character.

        Returns:
            A `TokenType` for newlines.
        """
        return TokenType(12)

    @staticmethod
    def dot() -> TokenType:
        """Creates a `TokenType` representing the `.` separator in dotted keys.

        Returns:
            A `TokenType` for dots.
        """
        return TokenType(13)

    @staticmethod
    def eof() -> TokenType:
        """Creates a `TokenType` representing end of file.

        Returns:
            A `TokenType` for end of file.
        """
        return TokenType(14)

    @staticmethod
    def error() -> TokenType:
        """Creates a `TokenType` representing a lexer error.

        Returns:
            A `TokenType` for errors.
        """
        return TokenType(15)

    @staticmethod
    def inline_table_start() -> TokenType:
        """Creates a `TokenType` representing an inline table opening brace `{`.

        Returns:
            A `TokenType` for inline table starts.
        """
        return TokenType(17)

    @staticmethod
    def inline_table_end() -> TokenType:
        """Creates a `TokenType` representing an inline table closing brace `}`.

        Returns:
            A `TokenType` for inline table ends.
        """
        return TokenType(18)

    # Constructor
    def __init__(out self, value: Int):
        """Creates a new `TokenType` from an integer identifier.

        Args:
            value: The integer identifier for this token type.
        """
        self.value = value

    # Comparison operators
    def __eq__(self, other: TokenType) -> Bool:
        """Checks equality between two token types.

        Args:
            other: The token type to compare against.

        Returns:
            `True` if the token types are equal, `False` otherwise.
        """
        return self.value == other.value

    def __ne__(self, other: TokenType) -> Bool:
        """Checks inequality between two token types.

        Args:
            other: The token type to compare against.

        Returns:
            `True` if the token types differ, `False` otherwise.
        """
        return self.value != other.value


struct Tokenizer:
    """Tokenizes TOML source text."""

    var source: String
    """The TOML source string to tokenize."""
    var position: SourcePosition
    """The current position in the source."""
    var current_char: String
    """The character at the current position."""

    def __init__(out self, source: String):
        """Creates a new `Tokenizer` for the given source.

        Args:
            source: The TOML source string to tokenize.
        """
        self.source = source
        self.position = SourcePosition()
        if source.byte_length() > 0:
            self.current_char = String(source[byte=0])
        else:
            self.current_char = ""

    def _get_char(self, index: Int) -> String:
        """Get character at given index or empty string if out of bounds."""
        if index >= self.source.byte_length():
            return ""
        return String(self.source[byte=index])

    def _advance(mut self):
        """Move to the next character."""
        self.position.advance(self.current_char)
        self.current_char = self._get_char(self.position.index)

    def _skip_whitespace(mut self):
        """Skip whitespace characters."""
        while self.current_char and self.current_char in WHITESPACE:
            self._advance()

    def _skip_comment(mut self):
        """Skip comment lines."""
        if self.current_char == COMMENT_START:
            while self.current_char:
                # Stop at LF or CR
                if self.current_char == "\n":
                    break
                if self.current_char == "\r":
                    # If next char is \n, treat as CRLF and break
                    if self._get_char(self.position.index + 1) == "\n":
                        break
                    else:
                        break
                self._advance()

    def _read_string(mut self) -> Token:
        """Read a quoted string value (basic or literal).

        Handles:
        - Basic strings ("..."): escape sequences \\, \", \n, \t, \r, \b, \f
        - Literal strings ('...'): no escape processing
        - Multi-line basic strings (triple double quotes)
        - Multi-line literal strings (triple single quotes)
        """
        start_line = self.position.line
        start_column = self.position.column
        quote_char = self.current_char

        # Check for multi-line string (triple quotes)
        var is_multiline = False
        if (
            self._get_char(self.position.index + 1) == quote_char
            and self._get_char(self.position.index + 2) == quote_char
        ):
            is_multiline = True
            self._advance()  # skip 1st quote
            self._advance()  # skip 2nd quote
            self._advance()  # skip 3rd quote
            # A newline immediately after the opening delimiter is trimmed
            if self.current_char == "\n":
                self._advance()
            elif (
                self.current_char == "\r"
                and self._get_char(self.position.index + 1) == "\n"
            ):
                self._advance()
                self._advance()
        else:
            # Single-line: skip opening quote
            self._advance()

        var is_literal = quote_char == "'"
        var chars = List[String]()

        while self.current_char:
            if is_multiline:
                # Check for closing triple quotes
                if (
                    self.current_char == quote_char
                    and self._get_char(self.position.index + 1) == quote_char
                    and self._get_char(self.position.index + 2) == quote_char
                ):
                    self._advance()  # skip 1st
                    self._advance()  # skip 2nd
                    self._advance()  # skip 3rd
                    return Token(
                        TokenType.STRING,
                        String.join("", chars),
                        start_line,
                        start_column,
                    )
                # Multi-line strings allow newlines
                if not is_literal and self.current_char == "\\":
                    # Process escape sequence
                    var next_ch = self._get_char(self.position.index + 1)
                    if next_ch == "\n" or next_ch == "\r":
                        # Line ending backslash: skip whitespace continuation
                        self._advance()  # skip backslash
                        while self.current_char and (
                            self.current_char == " "
                            or self.current_char == "\t"
                            or self.current_char == "\n"
                            or self.current_char == "\r"
                        ):
                            self._advance()
                        continue
                    chars.append(self._read_escape_sequence())
                else:
                    chars.append(self.current_char)
                    self._advance()
            else:
                # Single-line string
                if self.current_char == quote_char:
                    # Closing quote
                    self._advance()
                    return Token(
                        TokenType.STRING,
                        String.join("", chars),
                        start_line,
                        start_column,
                    )
                if self.current_char == "\n" or self.current_char == "\r":
                    # Newlines not allowed in single-line strings
                    return Token(
                        TokenType.ERROR,
                        "Newline in single-line string",
                        start_line,
                        start_column,
                    )
                if not is_literal and self.current_char == "\\":
                    # Process escape sequence
                    chars.append(self._read_escape_sequence())
                else:
                    chars.append(self.current_char)
                    self._advance()

        return Token(
            TokenType.ERROR, "Unterminated string", start_line, start_column
        )

    def _read_escape_sequence(mut self) -> String:
        """Read and return the character for a backslash escape sequence.

        Assumes current_char is '\\'. Advances past the full sequence.
        Handles: \\, \", \', \n, \t, \r, \b, \f.
        """
        self._advance()  # skip the backslash
        var esc = self.current_char
        self._advance()  # skip the escape character

        if esc == "\\":
            return "\\"
        elif esc == '"':
            return '"'
        elif esc == "'":
            return "'"
        elif esc == "n":
            return "\n"
        elif esc == "t":
            return "\t"
        elif esc == "r":
            return "\r"
        elif esc == "b":
            return "\x08"
        elif esc == "f":
            return "\x0c"
        elif esc == "u":
            # \uXXXX — 4-digit unicode codepoint
            var hex_str = String("")
            for _ in range(4):
                if not self.current_char:
                    return "\\u" + hex_str  # Truncated escape
                var ch = self.current_char
                if not (
                    (ch >= "0" and ch <= "9")
                    or (ch >= "a" and ch <= "f")
                    or (ch >= "A" and ch <= "F")
                ):
                    return "\\u" + hex_str  # Invalid hex digit
                hex_str += ch
                self._advance()
            var codepoint: Int = 0
            for i in range(hex_str.byte_length()):
                var ch = String(hex_str[byte=i])
                codepoint *= 16
                if ch >= "0" and ch <= "9":
                    codepoint += ord(ch) - ord("0")
                elif ch >= "a" and ch <= "f":
                    codepoint += ord(ch) - ord("a") + 10
                elif ch >= "A" and ch <= "F":
                    codepoint += ord(ch) - ord("A") + 10
            return chr(codepoint)
        elif esc == "U":
            # \UXXXXXXXX — 8-digit unicode codepoint
            var hex_str = String("")
            for _ in range(8):
                if not self.current_char:
                    return "\\U" + hex_str  # Truncated escape
                var ch = self.current_char
                if not (
                    (ch >= "0" and ch <= "9")
                    or (ch >= "a" and ch <= "f")
                    or (ch >= "A" and ch <= "F")
                ):
                    return "\\U" + hex_str  # Invalid hex digit
                hex_str += ch
                self._advance()
            var codepoint: Int = 0
            for i in range(hex_str.byte_length()):
                var ch = String(hex_str[byte=i])
                codepoint *= 16
                if ch >= "0" and ch <= "9":
                    codepoint += ord(ch) - ord("0")
                elif ch >= "a" and ch <= "f":
                    codepoint += ord(ch) - ord("a") + 10
                elif ch >= "A" and ch <= "F":
                    codepoint += ord(ch) - ord("A") + 10
            return chr(codepoint)
        else:
            # Unknown escape: keep as-is (backslash + char)
            return "\\" + esc

    def _read_number(mut self, sign: String = "") -> Token:
        """Read a number value.

        Handles:
        - Plain integers: 42
        - Signed numbers: +42, -42, +3.14, -3.14
        - Underscored numbers: 1_000, 1_000.5
        - Hex: 0xFF, Octal: 0o77, Binary: 0b1010
        - Scientific notation: 1e10, 1.5e-3, 6.022E+23
        - Float: 3.14
        """
        start_line = self.position.line
        start_column = self.position.column
        var result = sign
        var is_float = False

        # Check for hex/octal/binary prefixes: 0x, 0o, 0b
        if (
            self.current_char == "0"
            and self._get_char(self.position.index + 1) in "xXoObB"
        ):
            result += self.current_char  # '0'
            self._advance()
            result += self.current_char  # 'x'/'o'/'b'
            self._advance()
            # Determine valid digit set based on the base prefix
            var base_char = String(
                result[byte=result.byte_length() - 1]
            )  # 'x'/'o'/'b'
            var digits_found = False

            if base_char == "x" or base_char == "X":
                # Hexadecimal: 0-9, a-f, A-F
                while self.current_char and (
                    self.current_char.is_ascii_digit()
                    or self.current_char in "abcdefABCDEF_"
                ):
                    if self.current_char != "_":
                        result += self.current_char
                        digits_found = True
                    self._advance()
            elif base_char == "o" or base_char == "O":
                # Octal: 0-7 only
                while self.current_char and (self.current_char in "01234567_"):
                    if self.current_char != "_":
                        result += self.current_char
                        digits_found = True
                    self._advance()
            else:
                # Binary: 0-1 only
                while self.current_char and (self.current_char in "01_"):
                    if self.current_char != "_":
                        result += self.current_char
                        digits_found = True
                    self._advance()

            if not digits_found:
                return Token(TokenType.ERROR, result, start_line, start_column)
            return Token(TokenType.INTEGER, result, start_line, start_column)

        # Read digits, dots, underscores, and exponents
        while self.current_char and (
            self.current_char.is_ascii_digit()
            or self.current_char == "."
            or self.current_char == "_"
            or self.current_char == "e"
            or self.current_char == "E"
        ):
            if self.current_char == ".":
                is_float = True
                result += self.current_char
                self._advance()
            elif self.current_char == "e" or self.current_char == "E":
                is_float = True
                result += self.current_char
                self._advance()
                # Optional sign after exponent
                if self.current_char == "+" or self.current_char == "-":
                    result += self.current_char
                    self._advance()
            elif self.current_char == "_":
                # Skip underscores (TOML allows them as visual separators)
                self._advance()
            else:
                result += self.current_char
                self._advance()

        if is_float:
            return Token(TokenType.FLOAT, result, start_line, start_column)
        else:
            return Token(TokenType.INTEGER, result, start_line, start_column)

    def _read_key(mut self) -> Token:
        """Read a key identifier."""
        start_line = self.position.line
        start_column = self.position.column
        result = String("")

        while self.current_char and (
            self.current_char.is_ascii_digit()
            or self.current_char.isupper()
            or self.current_char.islower()
            or self.current_char == "_"
            or self.current_char == "-"
        ):
            result += self.current_char
            self._advance()

        return Token(TokenType.KEY, result, start_line, start_column)

    def next_token(mut self) -> Token:
        """Returns the next token from the source.

        Returns:
            The next `Token` from the source.
        """
        self._skip_whitespace()

        if not self.current_char:
            return Token(
                TokenType.EOF, "", self.position.line, self.position.column
            )

        if self.current_char == COMMENT_START:
            self._skip_comment()
            return self.next_token()

        # Handle CRLF and LF newlines
        if self.current_char == "\r":
            # Check for CRLF
            if self._get_char(self.position.index + 1) == "\n":
                token = Token(
                    TokenType.NEWLINE,
                    "\r\n",
                    self.position.line,
                    self.position.column,
                )
                self._advance()  # Skip \r
                self._advance()  # Skip \n
                return token^
            else:
                token = Token(
                    TokenType.NEWLINE,
                    "\r",
                    self.position.line,
                    self.position.column,
                )
                self._advance()
                return token^
        elif self.current_char == "\n":
            token = Token(
                TokenType.NEWLINE,
                "\n",
                self.position.line,
                self.position.column,
            )
            self._advance()
            return token^

        if self.current_char == "=":
            token = Token(
                TokenType.EQUAL, "=", self.position.line, self.position.column
            )
            self._advance()
            return token^

        if self.current_char == ",":
            token = Token(
                TokenType.COMMA, ",", self.position.line, self.position.column
            )
            self._advance()
            return token^

        if self.current_char == ".":
            token = Token(
                TokenType.DOT, ".", self.position.line, self.position.column
            )
            self._advance()
            return token^

        if self.current_char == "[":
            # Check if next char is also [
            if self._get_char(self.position.index + 1) == "[":
                # This is an array of tables start
                token = Token(
                    TokenType.ARRAY_OF_TABLES_START,
                    "[[",
                    self.position.line,
                    self.position.column,
                )
                self._advance()  # Skip first [
                self._advance()  # Skip second [
                return token^
            else:
                # Regular table start
                token = Token(
                    TokenType.TABLE_START,
                    "[",
                    self.position.line,
                    self.position.column,
                )
                self._advance()
                return token^

        if self.current_char == "]":
            token = Token(
                TokenType.ARRAY_END,
                "]",
                self.position.line,
                self.position.column,
            )
            self._advance()
            return token^

        if self.current_char == "{":
            token = Token(
                TokenType.INLINE_TABLE_START,
                "{",
                self.position.line,
                self.position.column,
            )
            self._advance()
            return token^

        if self.current_char == "}":
            token = Token(
                TokenType.INLINE_TABLE_END,
                "}",
                self.position.line,
                self.position.column,
            )
            self._advance()
            return token^

        if self.current_char == QUOTE or self.current_char == LITERAL_QUOTE:
            return self._read_string()

        # Handle sign prefixes: +42, -42, +3.14, -3.14, +inf, -inf, +nan, -nan
        if self.current_char == "+" or self.current_char == "-":
            var sign_char = self.current_char
            var next_ch = self._get_char(self.position.index + 1)
            if next_ch.is_ascii_digit():
                self._advance()  # skip the sign
                return self._read_number(sign_char)
            # +inf, -inf, +nan, -nan
            var next2 = self._get_char(self.position.index + 2)
            var next3 = self._get_char(self.position.index + 3)
            if next_ch == "i" and next2 == "n" and next3 == "f":
                var start_line = self.position.line
                var start_col = self.position.column
                self._advance()  # skip sign
                self._advance()  # skip i
                self._advance()  # skip n
                self._advance()  # skip f
                if sign_char == "-":
                    return Token(
                        TokenType.FLOAT,
                        "-inf",
                        start_line,
                        start_col,
                    )
                return Token(TokenType.FLOAT, "inf", start_line, start_col)
            if next_ch == "n" and next2 == "a" and next3 == "n":
                var start_line = self.position.line
                var start_col = self.position.column
                self._advance()  # skip sign
                self._advance()  # skip n
                self._advance()  # skip a
                self._advance()  # skip n
                return Token(TokenType.FLOAT, "nan", start_line, start_col)

        if self.current_char.is_ascii_digit():
            return self._read_number()

        if (
            self.current_char.is_ascii_digit()
            or self.current_char.isupper()
            or self.current_char.islower()
            or self.current_char == "_"
        ):
            return self._read_key()

        # Unrecognized character
        token = Token(
            TokenType.ERROR,
            "Unexpected character: " + self.current_char,
            self.position.line,
            self.position.column,
        )
        self._advance()
        return token^

    def tokenize(mut self) -> List[Token]:
        """Tokenizes the entire source text.

        Returns:
            A list of all tokens from the source.
        """
        var tokens = List[Token]()
        var token = self.next_token()

        while token.type != TokenType.EOF and token.type != TokenType.ERROR:
            tokens.append(token^)
            token = self.next_token()

        # Add EOF token
        if token.type == TokenType.EOF:
            tokens.append(token^)

        return tokens^
