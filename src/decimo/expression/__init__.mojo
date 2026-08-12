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
Decimo expression engine.

Parses and evaluates arbitrary-precision arithmetic expressions such as
`"100 + e * pi"` or `"sqrt(2) + 1/3"` using BigDecimal arithmetic.

High-level API — evaluate a string in one call:

```mojo
from decimo import eval

var r = eval("100 + e * pi", precision=50)
```

Mid-level API — import the individual stages (tokenizer, parser,
evaluator) for advanced use:

```mojo
from decimo.expression import tokenize, parse_to_rpn, evaluate_rpn

var rpn = parse_to_rpn(tokenize("1 + 2 * 3"))
var value = evaluate_rpn(rpn^, precision=50)
```
"""

from .tokenizer import (
    Token,
    tokenize,
    is_known_function,
    is_known_constant,
    is_alpha_or_underscore,
    is_alnum_or_underscore,
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
from .parser import parse_to_rpn
from .evaluator import evaluate_rpn, final_round, eval, evaluate
