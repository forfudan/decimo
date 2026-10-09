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
Tests that `BigDecimal` refuses a precision it cannot honour.

A precision of nought or less used to be accepted and answered with a nought:
`BigDecimal("2").sqrt(0)` came back as `0E+2`, which is not a square root of
anything, and `exp`, `ln` and the trigonometric functions did the same. The
binary float has refused this since it was written, through
`checked_precision()`; the decimal layer had no equivalent gate.

The gate sits in `round_to_precision_inplace()`, which is where every one of
those functions ends. That placement matters for what this file has to pin:
the four arithmetic methods document `precision = 0` as meaning "the exact,
unrounded result", and they must keep working, because they test the
precision before asking for a rounding at all.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.bigdecimal import BigDecimal


def _refuses(precision: Int) raises -> Bool:
    """Whether a square root at this precision raises.

    Args:
        precision: The precision to ask for.

    Returns:
        True when the call raised.

    Raises:
        Error: Never; the inner failure is caught.
    """
    try:
        _ = BigDecimal("2").sqrt(precision)
        return False
    except:
        return True


def test_a_non_positive_precision_is_refused() raises:
    """Nought and negative precisions raise instead of answering nought."""
    assert_true(_refuses(0), "a precision of nought")
    assert_true(_refuses(-1), "a precision of minus one")
    assert_true(_refuses(-28), "a precision of minus twenty-eight")
    assert_equal(String(BigDecimal("4").sqrt(1)), "2", "one digit still works")


def test_every_function_that_rounds_refuses_it() raises:
    """The gate is at the rounding, so it covers all of them at once.

    Each of these used to return a nought with a scale, which is the shape a
    coefficient takes when every digit is removed.
    """
    var raised = 0
    var total = 0
    for precision in [0, -3]:
        total += 6
        try:
            _ = BigDecimal("2").sqrt(precision)
        except:
            raised += 1
        try:
            _ = BigDecimal("2").exp(precision)
        except:
            raised += 1
        try:
            _ = BigDecimal("2").ln(precision)
        except:
            raised += 1
        try:
            _ = BigDecimal("2").sin(precision)
        except:
            raised += 1
        try:
            _ = BigDecimal("2").cbrt(precision)
        except:
            raised += 1
        try:
            _ = BigDecimal("8").power(BigDecimal("0.5"), precision)
        except:
            raised += 1
    assert_equal(raised, total, "every one of them refused")


def test_the_exact_arithmetic_still_takes_nought() raises:
    """`precision = 0` means exact for the four arithmetic methods.

    They are the reason the gate could not simply be put at the top of every
    function that takes a precision: here nought is the documented way to ask
    for an answer with no rounding at all, and it has to keep working.
    """
    assert_equal(
        String(BigDecimal("0.1").add(BigDecimal("0.2"))),
        "0.3",
        "an exact sum",
    )
    assert_equal(
        String(BigDecimal("1.5").multiply(BigDecimal("1.5"))),
        "2.25",
        "an exact product",
    )
    assert_equal(
        String(BigDecimal("0.3").subtract(BigDecimal("0.1"))),
        "0.2",
        "an exact difference",
    )
    assert_equal(
        String(BigDecimal("5").factorial()), "120", "an exact factorial"
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
