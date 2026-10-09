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

"""Sub-package for the pure-Mojo binary float.

Modules:
- bigfloat: Core struct with constructors, conversions, dunders
- arithmetics: add, subtract, multiply, divide
- comparison: compare, compare_total, equal, less, max, min
- constants: pi, ln2, e
- conversion: the bridge to and from the decimal types
- exponential: sqrt, exp, ln
- hyperbolic: sinh, cosh, tanh and their inverses
- ieee: the IEEE 754 companion operations -- the neighbours, logb, scaleb,
  the sign copies, number_class, the roundings to a whole number, fma and
  the two remainders
- rounding: round_to_precision and the fixed-point helpers the series use
- trigonometric: sin, cos, tan and their inverses
"""

from .ieee import (
    ceil,
    copy_abs,
    copy_negate,
    copy_sign,
    floor,
    fma,
    fmod,
    is_integer,
    logb,
    next_minus,
    next_plus,
    next_toward,
    number_class,
    remainder,
    round_to_integer,
    scaleb,
    truncate,
)
