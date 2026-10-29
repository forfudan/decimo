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
"""Tests the `BigFloat` constructors and the operators they make possible.

Given a precision, `BigFloat(n, p)`, `BigFloat(1.5, p)` and
`BigFloat("1.5", p)` are `from_int()`, `from_float64()` and `from_string()`
under another name. Without one, text and a `Float64` get 53 bits and an
`Int` gets 53 or its own significant bits, so unlike `from_int(n)` it never
rounds. The `Int` and the `Float64` constructors are implicit, so `1 + x`,
`x * 3` and `x == 1.5` work through them. The reflected and in-place
operators are checked against the plain ones, bit for bit.
"""

from std import testing

import decimo.bigfloat.arithmetics as arithmetics
from decimo.bigfloat.bigfloat import BigFloat
from decimo.rounding_mode import RoundingMode


def _same(a: BigFloat, b: BigFloat, label: String) raises:
    """Asserts two floats agree in every bit, precision included."""
    testing.assert_equal(
        a.internal_representation(), b.internal_representation(), label
    )


def _identity(x: BigFloat) -> BigFloat:
    """Takes a `BigFloat`, so that a call with an `Int` converts it."""
    return x.copy()


def test_int_keeps_every_bit() raises:
    """An `Int` converts at 53 bits, or at its own significant bits if more."""
    _same(BigFloat(2), BigFloat.from_int(2, 53), "2")
    _same(BigFloat(-5), BigFloat.from_int(-5, 53), "-5")
    _same(BigFloat(0), BigFloat.zero(53), "0")
    var wide = (1 << 60) + 1
    testing.assert_equal(BigFloat(wide).precision, 61)
    _same(BigFloat(wide), BigFloat.from_int(wide, 61), "2^60 + 1")
    # Trailing zeros are not significant bits.
    testing.assert_equal(BigFloat(1 << 62).precision, 53)
    _same(BigFloat(Int.MIN), BigFloat.from_int(Int.MIN, 53), "Int.MIN")
    _same(BigFloat(-wide), BigFloat.from_int(-wide, 61), "-(2^60 + 1)")
    testing.assert_equal(BigFloat(Int.MAX).precision, 63)
    _same(BigFloat(Int.MAX), BigFloat.from_int(Int.MAX, 63), "Int.MAX")


def test_int_at_a_precision() raises:
    """`BigFloat(n, precision, mode)` is `from_int(n, precision, mode)`."""
    _same(BigFloat(7, 200), BigFloat.from_int(7, 200), "7 at 200 bits")
    # 9 is 1001 in binary, so three bits must round it.
    _same(
        BigFloat(9, 3, RoundingMode.ROUND_UP),
        BigFloat.from_int(10, 3),
        "9 up",
    )
    _same(
        BigFloat(9, 3, RoundingMode.ROUND_DOWN),
        BigFloat.from_int(8, 3),
        "9 down",
    )
    with testing.assert_raises():
        _ = BigFloat(9, 0)


def test_float64() raises:
    """A `Float64` converts exactly at 53 bits, or rounds at a precision."""
    _same(BigFloat(1.5), BigFloat.from_float64(1.5), "1.5")
    _same(BigFloat(0.1), BigFloat.from_float64(0.1), "0.1")
    testing.assert_equal(BigFloat(0.1).precision, 53)
    var negative_zero = BigFloat(-0.0)
    testing.assert_true(negative_zero.is_zero() and negative_zero.sign)
    testing.assert_false(BigFloat(0).sign)
    testing.assert_true(BigFloat(Float64.MAX * 2).is_infinite())
    testing.assert_true(BigFloat(Float64.MAX * 2 - Float64.MAX * 2).is_nan())
    _same(
        BigFloat(0.1, 10, RoundingMode.ROUND_UP),
        BigFloat.from_float64(0.1, 10, RoundingMode.ROUND_UP),
        "0.1 at 10 bits, up",
    )


def test_string() raises:
    """`BigFloat(text)` is `from_string(text)`, with or without a precision."""
    _same(BigFloat("1.5"), BigFloat.from_string("1.5"), "1.5")
    _same(BigFloat("0.1"), BigFloat.from_string("0.1"), "0.1")
    _same(
        BigFloat("0.1", 200, RoundingMode.ROUND_DOWN),
        BigFloat.from_string("0.1", 200, RoundingMode.ROUND_DOWN),
        "0.1 at 200 bits, down",
    )
    var text = String("-2.5e-3")
    _same(BigFloat(text), BigFloat.from_string(text), "a String variable")
    testing.assert_true(BigFloat("nan").is_nan())
    with testing.assert_raises():
        _ = BigFloat("one")


def test_implicit_conversion() raises:
    """An `Int` or a `Float64` passes where a `BigFloat` is asked for."""
    var three: BigFloat = 3
    _same(three, BigFloat.from_int(3, 53), "var three: BigFloat = 3")
    _same(_identity(2), BigFloat.from_int(2, 53), "an Int argument")
    _same(_identity(0.25), BigFloat.from_float64(0.25), "a Float64 argument")


def test_reflected_operators() raises:
    """`1 + x` is `BigFloat(1) + x`, and so on for each operator."""
    var x = BigFloat("0.7", 200)
    _same(1 + x, BigFloat(1) + x, "1 + x")
    _same(2 - x, BigFloat(2) - x, "2 - x")
    _same(3 * x, BigFloat(3) * x, "3 * x")
    _same(3 / x, BigFloat(3) / x, "3 / x")
    _same(2**x, BigFloat(2) ** x, "2 ** x")
    _same(0.25 + x, BigFloat(0.25) + x, "0.25 + x")
    _same(x + 1, x + BigFloat(1), "x + 1")
    testing.assert_equal((1 + x).precision, 200)
    _same(1 / BigFloat(0), BigFloat.infinity(53), "1 / 0")


def test_a_literal_lifts_a_narrow_float() raises:
    """A literal has 53 bits at least, so a 10-bit float comes out at 53."""
    var x = BigFloat(1.5, 10)
    testing.assert_equal((x + 1).precision, 53)
    testing.assert_equal((2 * x).precision, 53)
    x *= 2
    testing.assert_equal(x.precision, 53)


def test_a_wide_int_rounds_once() raises:
    """An `Int` past 53 bits enters exactly, so the sum rounds once."""
    var x = BigFloat(1.5)
    var n = (1 << 60) + 1
    _same(
        x + n,
        arithmetics.add(x, BigFloat.from_int(n, 61), 61),
        "1.5 + (2^60 + 1)",
    )
    var wide = BigFloat.from_int(n, 61)
    _same(n - x, arithmetics.subtract(wide, x, 61), "(2^60 + 1) - 1.5")
    _same(n / x, arithmetics.divide(wide, x, 61), "(2^60 + 1) / 1.5")


def test_in_place_operators() raises:
    """Each in-place operator gives what the plain one gives."""
    var y = BigFloat("0.3", 120)
    var cases: List[String] = ["+=", "-=", "*=", "/=", "**="]
    for op in cases:
        var x = BigFloat(1.5)
        var expected: BigFloat
        if op == "+=":
            x += y
            expected = BigFloat(1.5) + y
        elif op == "-=":
            x -= y
            expected = BigFloat(1.5) - y
        elif op == "*=":
            x *= y
            expected = BigFloat(1.5) * y
        elif op == "/=":
            x /= y
            expected = BigFloat(1.5) / y
        else:
            x **= y
            expected = BigFloat(1.5) ** y
        _same(x, expected, op)
        testing.assert_equal(x.precision, 120)
    var z = BigFloat(1.5)
    z += 1
    z *= 2
    z -= 0.5
    z /= 3
    _same(z, BigFloat(1.5), "((1.5 + 1) * 2 - 0.5) / 3")


def test_comparison_with_a_literal() raises:
    """A literal on the right of a comparison converts.

    Mojo has no reflected comparisons, so `1 < x` does not compile.
    """
    var x = BigFloat(1.5)
    testing.assert_true(x == 1.5)
    testing.assert_true(x < 2)
    testing.assert_true(x > 1)
    testing.assert_true(BigFloat(0.1) == 0.1)
    testing.assert_true(BigFloat("0.1", 200) != 0.1)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
