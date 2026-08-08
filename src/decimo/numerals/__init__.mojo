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
Sub-package for writing numbers in non-Latin numeral systems.

Each module renders a decimal string -- not a particular numeric type -- so
the conversions are shared by every Decimo type and are not limited by any
integer width.  The numeric types expose thin wrappers around them, e.g.
`BigInt.to_chinese()` and `BigDecimal.to_chinese()`.

Modules:
- chinese: Chinese numerals (簡體/繁體, 小寫/大寫).

```mojo
from decimo import BigDecimal, ChineseNumeralStyle
from decimo.numerals import decimal_string_to_chinese

print(BigDecimal("1050.07").to_chinese())      # 一千零五十点零七
print(decimal_string_to_chinese("1050.07", ChineseNumeralStyle.traditional()))
# 一千零五十點零七
```
"""

from .chinese import (
    MAX_CHINESE_NUMERAL_DIGITS,
    ChineseNumeralStyle,
    decimal_string_to_chinese,
)
