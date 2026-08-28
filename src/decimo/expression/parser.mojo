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
Shunting-Yard parser for the Decimo expression engine.

Converts infix token lists to Reverse Polish Notation (RPN).
"""

from .tokenizer import (
    Token,
    TOKEN_NUMBER,
    TOKEN_PLUS,
    TOKEN_MINUS,
    TOKEN_STAR,
    TOKEN_SLASH,
    TOKEN_LPAREN,
    TOKEN_RPAREN,
    TOKEN_UNARY_MINUS,
    TOKEN_CARET,
    TOKEN_FUNC,
    TOKEN_CONST,
    TOKEN_COMMA,
    TOKEN_VARIABLE,
)


def parse_to_rpn(tokens: List[Token]) raises -> List[Token]:
    """Converts infix tokens to Reverse Polish Notation using Dijkstra's
    shunting-yard algorithm.

    Supports binary operators (+, -, *, /, ^), unary minus, function calls
    (sqrt, ln, …), constants (pi, e), and commas for multi-argument functions
    like root(x, n). A unary plus never reaches the parser: the tokenizer
    drops it.

    A unary minus is pushed onto the operator stack without popping anything
    first. A prefix operator has no left operand, so nothing already on the
    stack can be waiting to bind to one; popping by precedence would wrongly
    take `2^-2` as `(2^)` and `-2`. Whether the minus binds tighter than what
    follows is decided when that operator arrives, from the table in
    `Token.precedence()`: `-2^2` keeps the `^` above the sign, `-3*2` pops
    the sign before the `*`.

    Args:
        tokens: The list of infix tokens to convert.

    Returns:
        A new list of tokens in RPN order.

    Raises:
        Error: On mismatched parentheses, misplaced commas, or trailing
            operators — with position information when available.
    """
    var output = List[Token]()
    var op_stack = List[Token]()

    for i in range(len(tokens)):
        var kind = tokens[i].kind

        # Numbers, constants, and variables go straight to output
        if (
            kind == TOKEN_NUMBER
            or kind == TOKEN_CONST
            or kind == TOKEN_VARIABLE
        ):
            output.append(tokens[i])

        # Functions are pushed onto the operator stack
        elif kind == TOKEN_FUNC:
            op_stack.append(tokens[i])

        # Comma: pop operators until '(' (separates function arguments)
        elif kind == TOKEN_COMMA:
            var found_lparen = False
            while len(op_stack) > 0:
                if op_stack[len(op_stack) - 1].kind == TOKEN_LPAREN:
                    found_lparen = True
                    break
                output.append(op_stack.pop())
            if not found_lparen:
                raise Error(
                    "Error at position "
                    + String(tokens[i].position)
                    + ": misplaced ',' outside of a function call"
                )

        # A sign has no left operand, so nothing on the stack is competing
        # for one: push it and let the next operator decide against it.
        elif kind == TOKEN_UNARY_MINUS:
            op_stack.append(tokens[i])

        # Operators: shunt by precedence / associativity
        elif (
            kind == TOKEN_PLUS
            or kind == TOKEN_MINUS
            or kind == TOKEN_STAR
            or kind == TOKEN_SLASH
            or kind == TOKEN_CARET
        ):
            var tok_prec = tokens[i].precedence()
            var tok_left = tokens[i].is_left_associative()
            # Pop operators with higher (or equal for left-assoc) precedence
            while len(op_stack) > 0:
                var top_kind = op_stack[len(op_stack) - 1].kind
                if top_kind == TOKEN_LPAREN:
                    break
                if not op_stack[len(op_stack) - 1].is_operator():
                    break
                var top_prec = op_stack[len(op_stack) - 1].precedence()
                if tok_left:
                    if top_prec >= tok_prec:
                        output.append(op_stack.pop())
                    else:
                        break
                else:
                    # Right-associative: only pop if strictly greater
                    if top_prec > tok_prec:
                        output.append(op_stack.pop())
                    else:
                        break
            op_stack.append(tokens[i])

        elif kind == TOKEN_LPAREN:
            op_stack.append(tokens[i])

        elif kind == TOKEN_RPAREN:
            # Pop until we find the matching '('
            var found_lparen = False
            while len(op_stack) > 0:
                if op_stack[len(op_stack) - 1].kind == TOKEN_LPAREN:
                    found_lparen = True
                    break
                output.append(op_stack.pop())
            if not found_lparen:
                raise Error(
                    "Error at position "
                    + String(tokens[i].position)
                    + ": unmatched ')'"
                )
            _ = op_stack.pop()  # Discard the '('

            # If a function sits on top of the stack, pop it to output
            if (
                len(op_stack) > 0
                and op_stack[len(op_stack) - 1].kind == TOKEN_FUNC
            ):
                output.append(op_stack.pop())

    # Pop remaining operators
    while len(op_stack) > 0:
        var top = op_stack.pop()
        if top.kind == TOKEN_LPAREN:
            raise Error(
                "Error at position " + String(top.position) + ": unmatched '('"
            )
        output.append(top^)

    return output^
