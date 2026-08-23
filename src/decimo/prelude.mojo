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
Provides a list of things that can be imported at one time.
The list contains the functions or types that are the most essential for a user.

You can use the following code to import them:

```mojo
from decimo.prelude import *
```
"""

import decimo
import decimo as dm
from decimo.decimal128.decimal128 import Decimal128, Dec128
from decimo.bigdecimal.bigdecimal import BigDecimal, BDec, Decimal
from decimo.bigint.bigint import BigInt, BInt
from decimo.rounding_mode import (
    RoundingMode,
    ROUND_DOWN,
    ROUND_HALF_UP,
    ROUND_HALF_EVEN,
    ROUND_UP,
    ROUND_CEILING,
    ROUND_FLOOR,
)
