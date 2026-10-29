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
"""Tests that each `BigFloat` method returns what its free function returns.

Every function comes as a method in two forms. `x.f()` is the free function
at `x`'s own precision, rounded half to even. `x.f(precision, rounding_mode)`
is the free function asked for that precision and that mode. The free
functions are tested on their own; this file checks only that each method
hands its arguments through unchanged, bit for bit, in every rounding mode.
"""

from std import testing

from decimo.bigfloat.bigfloat import BigFloat
import decimo.bigfloat.exponential as exponential
import decimo.bigfloat.hyperbolic as hyperbolic
import decimo.bigfloat.power as power
import decimo.bigfloat.trigonometric as trigonometric
from decimo.rounding_mode import RoundingMode


def _modes() -> List[RoundingMode]:
    """The seven rounding modes."""
    return [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_EVEN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_HALF_DOWN,
    ]


def _same(a: BigFloat, b: BigFloat, label: String) raises:
    """Asserts two floats agree in every bit, precision included."""
    testing.assert_equal(
        a.internal_representation(), b.internal_representation(), label
    )


def _argument(name: String) raises -> BigFloat:
    """An argument inside the function's domain, at 80 bits."""
    if name == "arccosh":
        return BigFloat.from_string("1.75", 80)
    return BigFloat.from_string("0.75", 80)


def test_sqrt() raises:
    """`sqrt` in both forms."""
    var x = _argument("sqrt")
    _same(x.sqrt(), exponential.sqrt(x, 80), "sqrt()")
    for mode in _modes():
        _same(
            x.sqrt(120, mode),
            exponential.sqrt(x, 120, mode),
            String("sqrt(120, ", mode, ")"),
        )
    _same(x.sqrt(120), exponential.sqrt(x, 120), "sqrt(120)")


def test_cbrt() raises:
    """`cbrt` in both forms."""
    var x = _argument("cbrt")
    _same(x.cbrt(), exponential.cbrt(x, 80), "cbrt()")
    for mode in _modes():
        _same(
            x.cbrt(120, mode),
            exponential.cbrt(x, 120, mode),
            String("cbrt(120, ", mode, ")"),
        )
    _same(x.cbrt(120), exponential.cbrt(x, 120), "cbrt(120)")


def test_exp() raises:
    """`exp` in both forms."""
    var x = _argument("exp")
    _same(x.exp(), exponential.exp(x, 80), "exp()")
    for mode in _modes():
        _same(
            x.exp(120, mode),
            exponential.exp(x, 120, mode),
            String("exp(120, ", mode, ")"),
        )
    _same(x.exp(120), exponential.exp(x, 120), "exp(120)")


def test_exp2() raises:
    """`exp2` in both forms."""
    var x = _argument("exp2")
    _same(x.exp2(), exponential.exp2(x, 80), "exp2()")
    for mode in _modes():
        _same(
            x.exp2(120, mode),
            exponential.exp2(x, 120, mode),
            String("exp2(120, ", mode, ")"),
        )
    _same(x.exp2(120), exponential.exp2(x, 120), "exp2(120)")


def test_exp10() raises:
    """`exp10` in both forms."""
    var x = _argument("exp10")
    _same(x.exp10(), exponential.exp10(x, 80), "exp10()")
    for mode in _modes():
        _same(
            x.exp10(120, mode),
            exponential.exp10(x, 120, mode),
            String("exp10(120, ", mode, ")"),
        )
    _same(x.exp10(120), exponential.exp10(x, 120), "exp10(120)")


def test_expm1() raises:
    """`expm1` in both forms."""
    var x = _argument("expm1")
    _same(x.expm1(), exponential.expm1(x, 80), "expm1()")
    for mode in _modes():
        _same(
            x.expm1(120, mode),
            exponential.expm1(x, 120, mode),
            String("expm1(120, ", mode, ")"),
        )
    _same(x.expm1(120), exponential.expm1(x, 120), "expm1(120)")


def test_ln() raises:
    """`ln` in both forms."""
    var x = _argument("ln")
    _same(x.ln(), exponential.ln(x, 80), "ln()")
    for mode in _modes():
        _same(
            x.ln(120, mode),
            exponential.ln(x, 120, mode),
            String("ln(120, ", mode, ")"),
        )
    _same(x.ln(120), exponential.ln(x, 120), "ln(120)")


def test_log2() raises:
    """`log2` in both forms."""
    var x = _argument("log2")
    _same(x.log2(), exponential.log2(x, 80), "log2()")
    for mode in _modes():
        _same(
            x.log2(120, mode),
            exponential.log2(x, 120, mode),
            String("log2(120, ", mode, ")"),
        )
    _same(x.log2(120), exponential.log2(x, 120), "log2(120)")


def test_log10() raises:
    """`log10` in both forms."""
    var x = _argument("log10")
    _same(x.log10(), exponential.log10(x, 80), "log10()")
    for mode in _modes():
        _same(
            x.log10(120, mode),
            exponential.log10(x, 120, mode),
            String("log10(120, ", mode, ")"),
        )
    _same(x.log10(120), exponential.log10(x, 120), "log10(120)")


def test_log1p() raises:
    """`log1p` in both forms."""
    var x = _argument("log1p")
    _same(x.log1p(), exponential.log1p(x, 80), "log1p()")
    for mode in _modes():
        _same(
            x.log1p(120, mode),
            exponential.log1p(x, 120, mode),
            String("log1p(120, ", mode, ")"),
        )
    _same(x.log1p(120), exponential.log1p(x, 120), "log1p(120)")


def test_sin() raises:
    """`sin` in both forms."""
    var x = _argument("sin")
    _same(x.sin(), trigonometric.sin(x, 80), "sin()")
    for mode in _modes():
        _same(
            x.sin(120, mode),
            trigonometric.sin(x, 120, mode),
            String("sin(120, ", mode, ")"),
        )
    _same(x.sin(120), trigonometric.sin(x, 120), "sin(120)")


def test_cos() raises:
    """`cos` in both forms."""
    var x = _argument("cos")
    _same(x.cos(), trigonometric.cos(x, 80), "cos()")
    for mode in _modes():
        _same(
            x.cos(120, mode),
            trigonometric.cos(x, 120, mode),
            String("cos(120, ", mode, ")"),
        )
    _same(x.cos(120), trigonometric.cos(x, 120), "cos(120)")


def test_tan() raises:
    """`tan` in both forms."""
    var x = _argument("tan")
    _same(x.tan(), trigonometric.tan(x, 80), "tan()")
    for mode in _modes():
        _same(
            x.tan(120, mode),
            trigonometric.tan(x, 120, mode),
            String("tan(120, ", mode, ")"),
        )
    _same(x.tan(120), trigonometric.tan(x, 120), "tan(120)")


def test_cot() raises:
    """`cot` in both forms."""
    var x = _argument("cot")
    _same(x.cot(), trigonometric.cot(x, 80), "cot()")
    for mode in _modes():
        _same(
            x.cot(120, mode),
            trigonometric.cot(x, 120, mode),
            String("cot(120, ", mode, ")"),
        )
    _same(x.cot(120), trigonometric.cot(x, 120), "cot(120)")


def test_csc() raises:
    """`csc` in both forms."""
    var x = _argument("csc")
    _same(x.csc(), trigonometric.csc(x, 80), "csc()")
    for mode in _modes():
        _same(
            x.csc(120, mode),
            trigonometric.csc(x, 120, mode),
            String("csc(120, ", mode, ")"),
        )
    _same(x.csc(120), trigonometric.csc(x, 120), "csc(120)")


def test_sec() raises:
    """`sec` in both forms."""
    var x = _argument("sec")
    _same(x.sec(), trigonometric.sec(x, 80), "sec()")
    for mode in _modes():
        _same(
            x.sec(120, mode),
            trigonometric.sec(x, 120, mode),
            String("sec(120, ", mode, ")"),
        )
    _same(x.sec(120), trigonometric.sec(x, 120), "sec(120)")


def test_arcsin() raises:
    """`arcsin` in both forms."""
    var x = _argument("arcsin")
    _same(x.arcsin(), trigonometric.arcsin(x, 80), "arcsin()")
    for mode in _modes():
        _same(
            x.arcsin(120, mode),
            trigonometric.arcsin(x, 120, mode),
            String("arcsin(120, ", mode, ")"),
        )
    _same(x.arcsin(120), trigonometric.arcsin(x, 120), "arcsin(120)")


def test_arccos() raises:
    """`arccos` in both forms."""
    var x = _argument("arccos")
    _same(x.arccos(), trigonometric.arccos(x, 80), "arccos()")
    for mode in _modes():
        _same(
            x.arccos(120, mode),
            trigonometric.arccos(x, 120, mode),
            String("arccos(120, ", mode, ")"),
        )
    _same(x.arccos(120), trigonometric.arccos(x, 120), "arccos(120)")


def test_arctan() raises:
    """`arctan` in both forms."""
    var x = _argument("arctan")
    _same(x.arctan(), trigonometric.arctan(x, 80), "arctan()")
    for mode in _modes():
        _same(
            x.arctan(120, mode),
            trigonometric.arctan(x, 120, mode),
            String("arctan(120, ", mode, ")"),
        )
    _same(x.arctan(120), trigonometric.arctan(x, 120), "arctan(120)")


def test_sinh() raises:
    """`sinh` in both forms."""
    var x = _argument("sinh")
    _same(x.sinh(), hyperbolic.sinh(x, 80), "sinh()")
    for mode in _modes():
        _same(
            x.sinh(120, mode),
            hyperbolic.sinh(x, 120, mode),
            String("sinh(120, ", mode, ")"),
        )
    _same(x.sinh(120), hyperbolic.sinh(x, 120), "sinh(120)")


def test_cosh() raises:
    """`cosh` in both forms."""
    var x = _argument("cosh")
    _same(x.cosh(), hyperbolic.cosh(x, 80), "cosh()")
    for mode in _modes():
        _same(
            x.cosh(120, mode),
            hyperbolic.cosh(x, 120, mode),
            String("cosh(120, ", mode, ")"),
        )
    _same(x.cosh(120), hyperbolic.cosh(x, 120), "cosh(120)")


def test_tanh() raises:
    """`tanh` in both forms."""
    var x = _argument("tanh")
    _same(x.tanh(), hyperbolic.tanh(x, 80), "tanh()")
    for mode in _modes():
        _same(
            x.tanh(120, mode),
            hyperbolic.tanh(x, 120, mode),
            String("tanh(120, ", mode, ")"),
        )
    _same(x.tanh(120), hyperbolic.tanh(x, 120), "tanh(120)")


def test_arcsinh() raises:
    """`arcsinh` in both forms."""
    var x = _argument("arcsinh")
    _same(x.arcsinh(), hyperbolic.arcsinh(x, 80), "arcsinh()")
    for mode in _modes():
        _same(
            x.arcsinh(120, mode),
            hyperbolic.arcsinh(x, 120, mode),
            String("arcsinh(120, ", mode, ")"),
        )
    _same(x.arcsinh(120), hyperbolic.arcsinh(x, 120), "arcsinh(120)")


def test_arccosh() raises:
    """`arccosh` in both forms."""
    var x = _argument("arccosh")
    _same(x.arccosh(), hyperbolic.arccosh(x, 80), "arccosh()")
    for mode in _modes():
        _same(
            x.arccosh(120, mode),
            hyperbolic.arccosh(x, 120, mode),
            String("arccosh(120, ", mode, ")"),
        )
    _same(x.arccosh(120), hyperbolic.arccosh(x, 120), "arccosh(120)")


def test_arctanh() raises:
    """`arctanh` in both forms."""
    var x = _argument("arctanh")
    _same(x.arctanh(), hyperbolic.arctanh(x, 80), "arctanh()")
    for mode in _modes():
        _same(
            x.arctanh(120, mode),
            hyperbolic.arctanh(x, 120, mode),
            String("arctanh(120, ", mode, ")"),
        )
    _same(x.arctanh(120), hyperbolic.arctanh(x, 120), "arctanh(120)")


def test_hypot() raises:
    """`hypot` in both forms."""
    var x = _argument("hypot")
    var other = BigFloat.from_string("0.6", 64)
    # The form without a precision takes the wider of the two.
    _same(x.hypot(other=other), exponential.hypot(x, other, 80), "hypot()")
    for mode in _modes():
        _same(
            x.hypot(120, mode, other=other),
            exponential.hypot(x, other, 120, mode),
            String("hypot(120, ", mode, ")"),
        )


def test_arctan2() raises:
    """`arctan2` in both forms."""
    var x = _argument("arctan2")
    var other = BigFloat.from_string("0.6", 64)
    # The form without a precision takes the wider of the two.
    _same(
        x.arctan2(other=other), trigonometric.arctan2(x, other, 80), "arctan2()"
    )
    for mode in _modes():
        _same(
            x.arctan2(120, mode, other=other),
            trigonometric.arctan2(x, other, 120, mode),
            String("arctan2(120, ", mode, ")"),
        )


def test_log() raises:
    """`log` in both forms."""
    var x = _argument("log")
    var base = BigFloat.from_string("3", 64)
    # The form without a precision takes the wider of the two.
    _same(x.log(base=base), exponential.log(x, base, 80), "log()")
    for mode in _modes():
        _same(
            x.log(120, mode, base=base),
            exponential.log(x, base, 120, mode),
            String("log(120, ", mode, ")"),
        )


def test_power() raises:
    """`power` in both forms."""
    var x = _argument("power")
    var exponent = BigFloat.from_string("0.75", 64)
    # The form without a precision takes the wider of the two.
    _same(x.power(exponent=exponent), power.power(x, exponent, 80), "power()")
    for mode in _modes():
        _same(
            x.power(120, mode, exponent=exponent),
            power.power(x, exponent, 120, mode),
            String("power(120, ", mode, ")"),
        )


def test_root() raises:
    """`root` in both forms."""
    var x = _argument("root")
    _same(x.root(3), exponential.root(x, 3, 80), "root(3)")
    for mode in _modes():
        _same(
            x.root(3, 120, mode),
            exponential.root(x, 3, 120, mode),
            String("root(3, 120, ", mode, ")"),
        )


def test_precision_is_checked() raises:
    """A precision that is not positive is refused, as the free function
    refuses it."""
    var x = _argument("exp")
    with testing.assert_raises():
        _ = x.exp(0)
    with testing.assert_raises():
        _ = x.sin(-1, RoundingMode.ROUND_UP)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
