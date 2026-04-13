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
Tokenizer for the Decimo CLI calculator.

Converts an expression string into a list of tokens for the parser.
"""

# ===----------------------------------------------------------------------=== #
# Token kinds
# ===----------------------------------------------------------------------=== #

comptime TOKEN_NUMBER = 0
comptime TOKEN_PLUS = 1
comptime TOKEN_MINUS = 2
comptime TOKEN_STAR = 3
comptime TOKEN_SLASH = 4
comptime TOKEN_LPAREN = 5
comptime TOKEN_RPAREN = 6
comptime TOKEN_UNARY_MINUS = 7
comptime TOKEN_CARET = 8
comptime TOKEN_FUNC = 9
comptime TOKEN_CONST = 10
comptime TOKEN_COMMA = 11
comptime TOKEN_VARIABLE = 12


# ===----------------------------------------------------------------------=== #
# Token
# ===----------------------------------------------------------------------=== #


struct Token(Copyable, ImplicitlyCopyable, Movable):
    """A token produced by the lexer."""

    var kind: Int
    var value: String
    var position: Int
    """0-based column index in the original expression where this token
    starts.  Used to produce clear diagnostics such as
    `Error at position 5: unexpected '*'`."""

    def __init__(out self, kind: Int, value: String = "", position: Int = 0):
        self.kind = kind
        self.value = value
        self.position = position

    def __init__(out self, *, copy: Self):
        self.kind = copy.kind
        self.value = copy.value
        self.position = copy.position

    def __init__(out self, *, deinit take: Self):
        self.kind = take.kind
        self.value = take.value^
        self.position = take.position

    def is_operator(self) -> Bool:
        """Returns True if this token is a binary or unary operator."""
        return (
            self.kind == TOKEN_PLUS
            or self.kind == TOKEN_MINUS
            or self.kind == TOKEN_STAR
            or self.kind == TOKEN_SLASH
            or self.kind == TOKEN_CARET
            or self.kind == TOKEN_UNARY_MINUS
        )

    def precedence(self) -> Int:
        """Returns the precedence level (higher binds tighter).

        | Precedence | Operators | Associativity |
        |:----------:|-----------|:-------------:|
        |  1 (low)   | +, -      | Left          |
        |     2      | *, /      | Left          |
        |     3      | ^         | Right         |
        |  4 (high)  | unary -   | Right         |
        """
        if self.kind == TOKEN_PLUS or self.kind == TOKEN_MINUS:
            return 1
        if self.kind == TOKEN_STAR or self.kind == TOKEN_SLASH:
            return 2
        if self.kind == TOKEN_CARET:
            return 3
        if self.kind == TOKEN_UNARY_MINUS:
            return 4
        return 0

    def is_left_associative(self) -> Bool:
        """Returns True if this operator is left-associative."""
        if self.kind == TOKEN_UNARY_MINUS or self.kind == TOKEN_CARET:
            return False
        return True


# ===----------------------------------------------------------------------=== #
# Tokenizer
# ===----------------------------------------------------------------------=== #


# TODO:
# Yuhao Zhu:
# I am seriously thinking that whether I should also support recognizing
# full-width digits and operators, so that users can copy-paste expressions from
# other sources without having to manually convert them. This would be a nice
# feature for Chinese-Japanese-Korean (CJK) users.
# But it would also add some complexity to the tokenizer, because these
# full-width characters have different byte numbers.
# Known function names and built-in constants.


def _is_known_function(name: String) -> Bool:
    """Returns True if `name` is a recognized function."""
    return (
        name == "sqrt"
        or name == "root"
        or name == "cbrt"
        or name == "ln"
        or name == "log"
        or name == "log10"
        or name == "exp"
        or name == "sin"
        or name == "cos"
        or name == "tan"
        or name == "cot"
        or name == "csc"
        or name == "abs"
    )


def _is_known_constant(name: String) -> Bool:
    """Returns True if `name` is a recognized constant."""
    return name == "pi" or name == "e"


def _is_alpha_or_underscore(c: UInt8) -> Bool:
    """Returns True if c is a-z, A-Z, or '_'."""
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95


def _is_alnum_or_underscore(c: UInt8) -> Bool:
    """Returns True if c is a-z, A-Z, 0-9, or '_'."""
    return _is_alpha_or_underscore(c) or (c >= 48 and c <= 57)


def tokenize(
    expr: String, known_variables: List[String] = List[String]()
) raises -> List[Token]:
    """Converts an expression string into a list of tokens.

    Handles: numbers (integer and decimal), operators (+, -, *, /, ^),
    parentheses, commas, function calls (sqrt, ln, …), built-in
    constants (pi, e), user-defined variables, and distinguishes unary
    minus from binary minus.

    Each token records its 0-based column position in the source
    expression so that downstream stages can emit user-friendly
    diagnostics that pinpoint where the problem is.

    Args:
        expr: The expression string to tokenize.
        known_variables: Optional list of known variable names. When
            provided, identifiers matching a known variable are emitted
            as TOKEN_VARIABLE tokens instead of raising an error.

    Raises:
        Error: On empty/whitespace-only input (without position info),
            unknown identifiers, or unexpected characters (with the
            column position included in the message).
    """
    var tokens = List[Token]()
    var expr_bytes = StringSlice(expr).as_bytes()
    var n = len(expr_bytes)
    var ptr = expr_bytes.unsafe_ptr()
    var i = 0

    while i < n:
        var c = ptr[i]

        # Skip whitespace (space, tab)
        if c == 32 or c == 9:
            i += 1
            continue

        # --- Number literal: digits and at most one decimal point ---
        if (c >= 48 and c <= 57) or c == 46:  # '0'-'9' or '.'
            var start = i
            var has_dot = c == 46
            i += 1
            while i < n:
                var cc = ptr[i]
                if cc >= 48 and cc <= 57:
                    i += 1
                elif cc == 46 and not has_dot:
                    has_dot = True
                    i += 1
                else:
                    break
            # Build the number string from the byte range
            var num_bytes = List[UInt8](capacity=i - start)
            for j in range(start, i):
                num_bytes.append(ptr[j])
            tokens.append(
                Token(
                    TOKEN_NUMBER,
                    String(unsafe_from_utf8=num_bytes^),
                    position=start,
                )
            )
            continue

        # --- Alphabetical identifier: function name or constant ---
        if _is_alpha_or_underscore(c):
            var start = i
            i += 1
            while i < n and _is_alnum_or_underscore(ptr[i]):
                i += 1
            var id_bytes = List[UInt8](capacity=i - start)
            for j in range(start, i):
                id_bytes.append(ptr[j])
            var name = String(unsafe_from_utf8=id_bytes^)

            # Check if it is a known constant
            if _is_known_constant(name):
                tokens.append(Token(TOKEN_CONST, name^, position=start))
                continue

            # Check if it is a known function
            if _is_known_function(name):
                tokens.append(Token(TOKEN_FUNC, name^, position=start))
                continue

            # Check if it is a known variable
            var is_variable = False
            for vi in range(len(known_variables)):
                if known_variables[vi] == name:
                    is_variable = True
                    break
            if is_variable:
                tokens.append(Token(TOKEN_VARIABLE, name^, position=start))
                continue

            raise Error(
                "Error at position "
                + String(start)
                + ": unknown identifier '"
                + name
                + "'"
            )

        # --- Operators and parentheses ---
        if c == 43:  # '+'
            tokens.append(Token(TOKEN_PLUS, "+", position=i))
            i += 1
            continue

        if c == 45:  # '-'
            # Determine if this minus is unary or binary.
            # Unary if: at the start, or after an operator, or after '(' or ','
            var pos = i
            var is_unary = len(tokens) == 0
            if not is_unary:
                var last_kind = tokens[len(tokens) - 1].kind
                is_unary = (
                    last_kind == TOKEN_PLUS
                    or last_kind == TOKEN_MINUS
                    or last_kind == TOKEN_STAR
                    or last_kind == TOKEN_SLASH
                    or last_kind == TOKEN_CARET
                    or last_kind == TOKEN_LPAREN
                    or last_kind == TOKEN_UNARY_MINUS
                    or last_kind == TOKEN_COMMA
                )
            if is_unary:
                tokens.append(Token(TOKEN_UNARY_MINUS, "neg", position=pos))
            else:
                tokens.append(Token(TOKEN_MINUS, "-", position=pos))
            i += 1
            continue

        if c == 42:  # '*'
            # Support '**' as an alias for '^'
            if i + 1 < n and ptr[i + 1] == 42:
                tokens.append(Token(TOKEN_CARET, "^", position=i))
                i += 2
            else:
                tokens.append(Token(TOKEN_STAR, "*", position=i))
                i += 1
            continue

        if c == 47:  # '/'
            tokens.append(Token(TOKEN_SLASH, "/", position=i))
            i += 1
            continue

        if c == 94:  # '^'
            tokens.append(Token(TOKEN_CARET, "^", position=i))
            i += 1
            continue

        if c == 44:  # ','
            tokens.append(Token(TOKEN_COMMA, ",", position=i))
            i += 1
            continue

        if c == 40:  # '('
            tokens.append(Token(TOKEN_LPAREN, "(", position=i))
            i += 1
            continue

        if c == 41:  # ')'
            tokens.append(Token(TOKEN_RPAREN, ")", position=i))
            i += 1
            continue

        raise Error(
            "Error at position "
            + String(i)
            + ": unexpected character '"
            + chr(Int(c))
            + "'"
        )

    if len(tokens) == 0:
        raise Error("Empty expression")

    return tokens^
