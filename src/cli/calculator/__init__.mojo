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
Front end of the Decimo CLI calculator.

Provides the REPL, settings, terminal output and I/O helpers, and
re-exports the expression evaluator from `decimo.expression`.

```mojo
from calculator import evaluate
var result = evaluate("100 * 12 - 23/17", precision=50)
```
"""

from decimo.expression import (
    Token,
    tokenize,
    parse_to_rpn,
    evaluate_rpn,
    final_round,
    eval,
    evaluate,
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
from .engine import (
    evaluate_and_print,
    evaluate_and_return,
    display_calc_error,
    pad_to_precision,
)
from .display import print_error, print_warning, print_hint, write_prompt
from .io import (
    stdin_is_tty,
    stdout_is_tty,
    read_line,
    read_stdin,
    split_into_lines,
    strip_comment,
    is_blank,
    is_comment_or_blank,
    strip,
    filter_expression_lines,
    read_file_text,
    file_exists,
)
from .repl import run_repl
from .settings import Settings, parse_settings, split_inline_settings
