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
Tokenizer for the Decimo expression engine.

Converts an expression string into a list of tokens for the parser.
"""

from std.collections import Dict

from ..bigdecimal.bigdecimal import Decimal

# ===----------------------------------------------------------------------=== #
# Token kinds
# ===----------------------------------------------------------------------=== #

comptime TOKEN_NUMBER = 0
"""Token kind for numeric literals."""
comptime TOKEN_PLUS = 1
"""Token kind for the `+` operator."""
comptime TOKEN_MINUS = 2
"""Token kind for the binary `-` operator."""
comptime TOKEN_STAR = 3
"""Token kind for the `*` operator."""
comptime TOKEN_SLASH = 4
"""Token kind for the `/` operator."""
comptime TOKEN_LPAREN = 5
"""Token kind for `(`."""
comptime TOKEN_RPAREN = 6
"""Token kind for `)`."""
comptime TOKEN_UNARY_MINUS = 7
"""Token kind for unary minus."""
comptime TOKEN_CARET = 8
"""Token kind for the `^` (power) operator."""
comptime TOKEN_FUNC = 9
"""Token kind for function names (sqrt, ln, etc.)."""
comptime TOKEN_CONST = 10
"""Token kind for built-in constants (pi, e)."""
comptime TOKEN_COMMA = 11
"""Token kind for `,` (argument separator)."""
comptime TOKEN_VARIABLE = 12
"""Token kind for user-defined variables."""


# ===----------------------------------------------------------------------=== #
# Token
# ===----------------------------------------------------------------------=== #


struct Token(Copyable, ImplicitlyCopyable, Movable):
    """A token produced by the lexer."""

    var kind: Int
    """Integer tag identifying the token type (see TOKEN_* constants)."""
    var value: String
    """The textual content of the token."""
    var position: Int
    """0-based column index in the original expression where this token
    starts.  Used to produce clear diagnostics such as
    `Error at position 5: unexpected '*'`."""

    def __init__(out self, kind: Int, value: String = "", position: Int = 0):
        """Creates a new Token.

        Args:
            kind: The token type tag.
            value: The textual content of the token.
            position: 0-based column index in the source expression.
        """
        self.kind = kind
        self.value = value
        self.position = position

    def __init__(out self, *, copy: Self):
        """Creates a copy of an existing Token.

        Args:
            copy: The token to copy from.
        """
        self.kind = copy.kind
        self.value = copy.value
        self.position = copy.position

    def __init__(out self, *, deinit move: Self):
        """Move-constructs a Token.

        Args:
            move: The token to move from.
        """
        self.kind = move.kind
        self.value = move.value^
        self.position = move.position

    def is_operator(self) -> Bool:
        """Returns True if this token is a binary or unary operator.

        Returns:
            True if the token kind is an operator.
        """
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
        |     3      | unary -   | Right         |
        |  4 (high)  | ^         | Right         |

        A unary minus sits between `*` and `^`, so `-2^2` is `-(2^2) = -4`
        and `-3*2` is `(-3)*2`. That is how Python, Julia, Mathematica and
        most calculators read it; spreadsheets rank the sign above `^` and
        give 4, and so did this table until it was changed to match Python.
        `2^-2` is unaffected: a sign inside an exponent is parsed as part of
        the exponent (see `parse_to_rpn()`).

        Returns:
            The integer precedence level, or 0 for non-operators.
        """
        if self.kind == TOKEN_PLUS or self.kind == TOKEN_MINUS:
            return 1
        if self.kind == TOKEN_STAR or self.kind == TOKEN_SLASH:
            return 2
        if self.kind == TOKEN_UNARY_MINUS:
            return 3
        if self.kind == TOKEN_CARET:
            return 4
        return 0

    def is_left_associative(self) -> Bool:
        """Returns True if this operator is left-associative.

        Returns:
            True for left-associative operators, False for right-associative.
        """
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


def is_known_function(name: String) -> Bool:
    """Returns True if `name` is a recognized function.

    Args:
        name: The identifier to check.

    Returns:
        True if the name matches a built-in function.
    """
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


def is_known_constant(name: String) -> Bool:
    """Returns True if `name` is a recognized constant.

    Args:
        name: The identifier to check.

    Returns:
        True if the name matches a built-in constant.
    """
    return name == "pi" or name == "e"


def is_alpha_or_underscore(c: UInt8) -> Bool:
    """Returns True if c is a-z, A-Z, or '_'.

    Args:
        c: The byte value to check.

    Returns:
        True if the byte is an ASCII letter or underscore.
    """
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95


def is_alnum_or_underscore(c: UInt8) -> Bool:
    """Returns True if c is a-z, A-Z, 0-9, or '_'.

    Args:
        c: The byte value to check.

    Returns:
        True if the byte is an ASCII alphanumeric character or underscore.
    """
    return is_alpha_or_underscore(c) or (c >= 48 and c <= 57)


def _in_sign_position(tokens: List[Token]) -> Bool:
    """Whether a `+` or `-` read next would be a sign rather than an operator.

    True at the start of the expression, after another operator or sign,
    after `(` and after `,`.
    """
    if len(tokens) == 0:
        return True
    var last_kind = tokens[len(tokens) - 1].kind
    return (
        last_kind == TOKEN_PLUS
        or last_kind == TOKEN_MINUS
        or last_kind == TOKEN_STAR
        or last_kind == TOKEN_SLASH
        or last_kind == TOKEN_CARET
        or last_kind == TOKEN_LPAREN
        or last_kind == TOKEN_UNARY_MINUS
        or last_kind == TOKEN_COMMA
    )


def tokenize(
    expr: String,
    known_variables: Dict[String, Decimal] = Dict[String, Decimal](),
) raises -> List[Token]:
    """Converts an expression string into a list of tokens.

    Handles: numbers (integer and decimal), operators (+, -, *, /, ^),
    parentheses, commas, function calls (sqrt, ln, …), built-in
    constants (pi, e), user-defined variables, and distinguishes a sign
    from a binary operator: a leading `-` becomes a unary-minus token and a
    leading `+` is dropped.

    Each token records its 0-based column position in the source
    expression so that downstream stages can emit user-friendly
    diagnostics that pinpoint where the problem is.

    Args:
        expr: The expression string to tokenize.
        known_variables: Optional name→value mapping of user-defined
            variables.  Identifiers matching a key are emitted as
            TOKEN_VARIABLE tokens instead of raising an error.

    Returns:
        A list of tokens representing the expression.

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
        var c = ptr[unsafe_offset=i]

        # Skip whitespace (space, tab, newline, carriage return)
        if c == 32 or c == 9 or c == 10 or c == 13:
            i += 1
            continue

        # --- Number literal: digits and at most one decimal point ---
        if (c >= 48 and c <= 57) or c == 46:  # '0'-'9' or '.'
            var start = i
            var has_dot = c == 46
            i += 1
            while i < n:
                var cc = ptr[unsafe_offset=i]
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
                num_bytes.append(ptr[unsafe_offset=j])
            tokens.append(
                Token(
                    TOKEN_NUMBER,
                    String(unsafe_from_utf8=num_bytes^),
                    position=start,
                )
            )
            continue

        # --- Alphabetical identifier: function name or constant ---
        if is_alpha_or_underscore(c):
            var start = i
            i += 1
            while i < n and is_alnum_or_underscore(ptr[unsafe_offset=i]):
                i += 1
            var id_bytes = List[UInt8](capacity=i - start)
            for j in range(start, i):
                id_bytes.append(ptr[unsafe_offset=j])
            var name = String(unsafe_from_utf8=id_bytes^)

            # Check if it is a known constant
            if is_known_constant(name):
                tokens.append(Token(TOKEN_CONST, name^, position=start))
                continue

            # Check if it is a known function
            if is_known_function(name):
                tokens.append(Token(TOKEN_FUNC, name^, position=start))
                continue

            # Check if it is a known variable
            if name in known_variables:
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
            # A '+' in sign position (`+3`, `2*+3`, `(+3)`) is a unary plus.
            # It does nothing, so no token is emitted; the '+' is simply
            # skipped. It used to be rejected with "missing operand for '+'".
            if not _in_sign_position(tokens):
                tokens.append(Token(TOKEN_PLUS, "+", position=i))
            i += 1
            continue

        if c == 45:  # '-'
            var pos = i
            if _in_sign_position(tokens):
                tokens.append(Token(TOKEN_UNARY_MINUS, "neg", position=pos))
            else:
                tokens.append(Token(TOKEN_MINUS, "-", position=pos))
            i += 1
            continue

        if c == 42:  # '*'
            # Support '**' as an alias for '^'
            if i + 1 < n and ptr[unsafe_offset=i + 1] == 42:
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
