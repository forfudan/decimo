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
"""Tests the keyword forms of the four `BigDecimal` methods of two values.

`log`, `power`, `arctan2` and `hypot` take the other value by keyword, so
that a positional `Int` is always a precision, as it is in `ln(p)`. Each
form must return what the free function returns for the same arguments.
"""

from std import testing

from decimo.bigdecimal.bigdecimal import PRECISION, BigDecimal
import decimo.bigdecimal.exponential as exponential
import decimo.bigdecimal.trigonometric as trigonometric
from decimo.rounding_mode import RoundingMode


def test_log() raises:
    """`x.log(base=b)` is `log(x, b, precision)`."""
    var x = BigDecimal("1000000")
    var base = BigDecimal("7")
    testing.assert_equal(x.log(base=base), exponential.log(x, base, PRECISION))
    testing.assert_equal(x.log(60, base=base), exponential.log(x, base, 60))
    testing.assert_equal(
        x.log(base=base, precision=60), exponential.log(x, base, 60)
    )
    # An Int base converts, and is read as the base, not the precision.
    testing.assert_true(x.log(base=100) == BigDecimal(3))


def test_power() raises:
    """`x.power(exponent=e)` is `power_rounded(x, e, precision, mode)`."""
    var x = BigDecimal("2.5")
    var e = BigDecimal("0.3")
    var up = RoundingMode.ROUND_UP
    testing.assert_equal(
        x.power(exponent=e),
        exponential.power_rounded(
            x, e, PRECISION, RoundingMode.ROUND_HALF_EVEN
        ),
    )
    testing.assert_equal(
        x.power(60, up, exponent=e), exponential.power_rounded(x, e, 60, up)
    )
    testing.assert_true(BigDecimal("2").power(exponent=10) == BigDecimal(1024))


def test_arctan2() raises:
    """`y.arctan2(other=x)` is `arctan2_rounded(y, x, precision, mode)`."""
    var y = BigDecimal("1")
    var x = BigDecimal("-3")
    var down = RoundingMode.ROUND_DOWN
    testing.assert_equal(
        y.arctan2(other=x),
        trigonometric.arctan2_rounded(
            y, x, PRECISION, RoundingMode.ROUND_HALF_EVEN
        ),
    )
    testing.assert_equal(
        y.arctan2(60, down, other=x),
        trigonometric.arctan2_rounded(y, x, 60, down),
    )


def test_hypot() raises:
    """`x.hypot(other=y)` is `hypot_rounded(x, y, precision, mode)`."""
    var x = BigDecimal("1.5")
    var y = BigDecimal("2.25")
    var up = RoundingMode.ROUND_UP
    testing.assert_equal(
        x.hypot(other=y),
        exponential.hypot_rounded(
            x, y, PRECISION, RoundingMode.ROUND_HALF_EVEN
        ),
    )
    testing.assert_equal(
        x.hypot(60, up, other=y), exponential.hypot_rounded(x, y, 60, up)
    )
    testing.assert_true(BigDecimal("3").hypot(other=4) == BigDecimal(5))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
