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

"""Smoke tests for BigFloat: verify MPFR pipeline works end-to-end."""

from decimo.bigfloat.bigfloat import BigFloat, PRECISION
from decimo.bigfloat.mpfr_wrapper import mpfrw_available
from decimo.traits import Rootable


def test_mpfr_available() raises:
    print("test_mpfr_available ... ", end="")
    if not mpfrw_available():
        print("SKIPPED (MPFR not installed)")
        return
    print("OK")


def test_construct_from_string() raises:
    print("test_construct_from_string ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var x = BigFloat("3.14159")
    print("OK  value =", x)


def test_construct_from_int() raises:
    print("test_construct_from_int ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var x = BigFloat(42)
    print("OK  value =", x)


def test_sqrt() raises:
    print("test_sqrt ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var x = BigFloat("2.0", precision=50)
    var s = x.sqrt()
    var result = s.to_string(50)
    # sqrt(2) ≈ 1.4142135623730950488...
    if not result.startswith("1.4142"):
        raise Error("FAIL test_sqrt got: " + result)
    print("OK  sqrt(2) =", result)


def test_exp() raises:
    print("test_exp ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var x = BigFloat("1.0", precision=50)
    var e = x.exp()
    var result = e.to_string(50)
    # exp(1) ≈ 2.71828182845904523536...
    if not result.startswith("2.7182"):
        raise Error("FAIL test_exp got: " + result)
    print("OK  exp(1) =", result)


def test_ln() raises:
    print("test_ln ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var x = BigFloat("2.0", precision=30)
    var result = x.ln()
    var s = result.to_string(15)
    # ln(2) ≈ 0.693147180559945...
    if not s.startswith("0.69314"):
        raise Error("FAIL test_ln got: " + s)
    print("OK  ln(2) =", s)


def test_trig() raises:
    print("test_trig ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var pi = BigFloat.pi(50)
    var s = pi.sin()
    var c = pi.cos()
    var sin_s = s.to_string(20)
    var cos_s = c.to_string(20)
    # sin(π) ≈ 0, cos(π) ≈ -1
    print("OK  sin(π) =", sin_s, " cos(π) =", cos_s)


def test_arithmetic() raises:
    print("test_arithmetic ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var a = BigFloat("10.0")
    var b = BigFloat("3.0")
    var sum_ = a + b
    var diff = a - b
    var prod = a * b
    var quot = a / b
    print("OK  10+3=", sum_, " 10-3=", diff, " 10*3=", prod, " 10/3=", quot)


def test_comparison() raises:
    print("test_comparison ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var a = BigFloat("1.0")
    var b = BigFloat("2.0")
    var c = BigFloat("1.0")
    var ok = True
    if not (a < b):
        ok = False
    if not (b > a):
        ok = False
    if not (a == c):
        ok = False
    if not (a != b):
        ok = False
    if not (a <= c):
        ok = False
    if not (b >= a):
        ok = False
    if ok:
        print("OK")
    else:
        raise Error("FAIL test_comparison")


def test_pi() raises:
    print("test_pi ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var pi = BigFloat.pi(100)
    var s = pi.to_string(50)
    # π ≈ 3.14159265358979323846...
    if not s.startswith("3.14159265358979"):
        raise Error("FAIL test_pi got: " + s)
    print("OK  π =", s)


def test_to_bigdecimal() raises:
    print("test_to_bigdecimal ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var x = BigFloat("2.0", precision=50)
    var s = x.sqrt()
    var bd = s.to_bigdecimal(30)
    var bd_s = String(bd)
    # Should start with 1.4142...
    if not bd_s.startswith("1.4142"):
        raise Error("FAIL test_to_bigdecimal got: " + bd_s)
    print("OK  BigDecimal(sqrt(2)) =", bd_s)


def test_power_and_root() raises:
    print("test_power_and_root ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var x = BigFloat("8.0", precision=30)
    var third = BigFloat("0.333333333333333333", precision=30)
    var cube_root = x.root(UInt32(3))
    # The `Int` spelling `BigDecimal` and `Decimal128` share.
    var cube_root_int = x.root(3)
    var power_result = x.power(third)
    if not cube_root_int.to_string(10).startswith("2"):
        raise Error(
            "FAIL test_power_and_root got: " + cube_root_int.to_string(10)
        )
    var raised = False
    try:
        _ = x.root(0)
    except:
        raised = True
    if not raised:
        raise Error("FAIL test_power_and_root: root(0) did not raise")
    # One past `UInt32.MAX`, which would wrap to 0 if it reached the cast.
    raised = False
    try:
        _ = x.root(Int(UInt32.MAX) + 1)
    except:
        raised = True
    if not raised:
        raise Error("FAIL test_power_and_root: oversized root did not raise")
    print("OK  cbrt(8) =", cube_root, " 8^(1/3) =", power_result)


def test_neg_and_abs() raises:
    print("test_neg_and_abs ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var x = BigFloat("-5.0")
    var neg_x = -x
    var abs_x = x.__abs__()
    print("OK  -(-5) =", neg_x, " |(-5)| =", abs_x)


def test_high_precision_sqrt() raises:
    print("test_high_precision_sqrt ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var x = BigFloat("2.0", precision=1000)
    var s = x.sqrt()
    var result = s.to_string(100)
    # Verify many digits of sqrt(2)
    if not result.startswith(
        "1.41421356237309504880168872420969807856967187537694"
    ):
        raise Error("FAIL test_high_precision_sqrt got: " + result)
    print("OK  sqrt(2) to 100 digits verified")


def _root_of[T: Rootable](var x: T) raises -> T:
    """Returns `x.sqrt()` through the trait alone.

    `Rootable` carries `Deinitable` and `Movable` and nothing else, which is
    what lets it reach `BigFloat`: a type that moves without copying.
    """
    return x^.sqrt()


def test_rootable_conformance() raises:
    print("test_rootable_conformance ... ", end="")
    if not mpfrw_available():
        print("SKIPPED")
        return
    var s = _root_of(BigFloat("2.0", precision=50))
    var result = s.to_string(50)
    if not result.startswith("1.4142"):
        raise Error("FAIL test_rootable_conformance got: " + result)
    # `Rootable` lets a type with a `nan` return one where the four exact
    # types raise. `BigFloat` has one, and every function of it outside its
    # domain gives one, so `sqrt` does too.
    var negative = _root_of(BigFloat("-4.0", precision=50))
    if String(negative) != "nan":
        raise Error(
            "FAIL test_rootable_conformance: sqrt(-4) gave " + String(negative)
        )
    print("OK  sqrt(2) through Rootable =", result, " sqrt(-4) = nan")


def test_negative_precision_is_refused() raises:
    """A negative precision is an error here as it is on `BigDecimal`.

    It used to be accepted and stored: `BigFloat("2", precision=-1)` gave a
    value that printed and computed as if the precision were 1, because the
    bit conversion floors at MPFR's minimum and `mpfr_get_str` treats a
    non-positive digit count as "choose for me". No wrong result came of it,
    but `BigDecimal.sqrt(-1)` raises and this did not. Zero stays accepted on
    both types.
    """
    print("test_negative_precision_is_refused ... ", end="")
    # Each call must raise the validation error itself, not fail for some
    # other reason (MPFR missing, handle pool empty) that a broad catch would
    # count as a pass.
    var messages = List[String]()
    try:
        _ = BigFloat("2", precision=-1)
        messages.append(String("no error"))
    except e:
        messages.append(String(e))
    try:
        _ = BigFloat(2, precision=-1)
        messages.append(String("no error"))
    except e:
        messages.append(String(e))
    try:
        _ = BigFloat.pi(-1)
        messages.append(String("no error"))
    except e:
        messages.append(String(e))
    for message in messages:
        if "Precision must be non-negative" not in message:
            raise Error(
                "FAIL test_negative_precision_is_refused: got '" + message + "'"
            )
    _ = BigFloat("2", precision=0)
    print("OK")


def main() raises:
    test_mpfr_available()
    test_construct_from_string()
    test_construct_from_int()
    test_sqrt()
    test_exp()
    test_ln()
    test_trig()
    test_arithmetic()
    test_comparison()
    test_pi()
    test_to_bigdecimal()
    test_power_and_root()
    test_neg_and_abs()
    test_high_precision_sqrt()
    test_rootable_conformance()
    test_negative_precision_is_refused()
    print("\nAll BigFloat smoke tests completed.")
