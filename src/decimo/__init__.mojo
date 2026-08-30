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
Decimo: A decimal and arbitrary-precision arithmetic library for Mojo.

You can import the most useful objects in one line, for example:

```mojo
from decimo import Decimal, BInt, RoundingMode
```
"""

comptime DECIMO_VERSION = "0.14.0"
"""Canonical semantic version of the Decimo library (no leading `v`).

Keep in sync with `pixi.toml`'s `[project].version`.  This is the single
source of truth used by the CLI's `--version` flag and any future build
artefacts; consumers wanting the display form (with the leading `v`)
should use `DECIMO_VERSION_TAG`.
"""

comptime DECIMO_VERSION_TAG = "v" + DECIMO_VERSION
"""Display version of the Decimo library, prefixed with `v` (e.g. `v0.14.0`).
"""

# Traits
from .traits import Numeric, Parsable, Rootable

# Core types
from .decimal128.decimal128 import Decimal128, Dec128
from .bigint.bigint import BigInt, BInt, Magnitude
from .biguint.biguint import BigUInt, BUInt
from .bigdecimal.bigdecimal import BigDecimal, BDec, Decimal, PRECISION
from .bigfloat.bigfloat import BigFloat, BFlt, Float
from .rational.rational import Rational
from .rounding_mode import (
    RoundingMode,
    ROUND_DOWN,
    ROUND_HALF_UP,
    ROUND_HALF_DOWN,
    ROUND_HALF_EVEN,
    ROUND_UP,
    ROUND_CEILING,
    ROUND_FLOOR,
)

# Core functions
from .bigint.number_theory import gcd, lcm, extended_gcd, mod_inverse, mod_pow

# Numeral systems (high-level: the `to_chinese()` methods; mid-level:
# `decimo.numerals`)
from .numerals.chinese import ChineseNumeralStyle

# Expression engine (high-level: `eval`; mid-level: `decimo.expression`)
from .expression import eval, evaluate
