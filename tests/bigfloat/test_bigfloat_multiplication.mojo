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
Tests the multiplication and division of `BigFloat`.

The product of two significands is an integer, so multiplication is checked
the way addition was: the exact product is formed in decimal, where nothing
rounds, and rounded there instead. A quotient has no such route -- almost no
quotient is a finite decimal -- so its expectations come from a short Python
program that works in exact integers and implements the seven modes from
their definitions. The table below is that program's output, and a sweep of
600 random pairs against the same program is where the implementation was
actually settled.

The quotients in the table are the ones worth writing down: a third and a
seventh at four precisions, three halves and five halves where the quotient
is an exact tie and the three half modes have to disagree, quotients that
come out exact, and a numerator far below its denominator, which is what
makes the first shift too short and the loop widen it.
"""

from std import testing
from std.testing import assert_equal, assert_false, assert_true

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigfloat.arithmetics import divide, multiply
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


def _modes() -> List[RoundingMode]:
    """All seven of them.

    Returns:
        The modes, in the order the rounding primitive documents them.
    """
    return [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]


def test_the_quotient_is_the_one_exact_integers_give() raises:
    """Eighteen quotients in all seven modes, against exact integer rounding.

    The expectations come from a Python program that divides the two
    significands as integers, keeps the remainder, and applies each mode's
    definition to it. Nothing in the computation is a float, so the table is
    independent of everything it checks.
    """
    var modes = _modes()
    var numerators = [
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("355"),
        String("355"),
        String("355"),
        String("355"),
        String("355"),
        String("355"),
        String("355"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("5"),
        String("5"),
        String("5"),
        String("5"),
        String("5"),
        String("5"),
        String("5"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
        String("9"),
        String("9"),
        String("9"),
        String("9"),
        String("9"),
        String("9"),
        String("9"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("9007199254740991"),
        String("9007199254740991"),
        String("9007199254740991"),
        String("9007199254740991"),
        String("9007199254740991"),
        String("9007199254740991"),
        String("9007199254740991"),
    ]
    var denominators = [
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("3"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
        String("7"),
        String("10"),
        String("10"),
        String("10"),
        String("10"),
        String("10"),
        String("10"),
        String("10"),
        String("113"),
        String("113"),
        String("113"),
        String("113"),
        String("113"),
        String("113"),
        String("113"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("4"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("2"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("18446744073709551617"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("9007199254740993"),
        String("9007199254740993"),
        String("9007199254740993"),
        String("9007199254740993"),
        String("9007199254740993"),
        String("9007199254740993"),
        String("9007199254740993"),
    ]
    var precisions = [
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        24,
        24,
        24,
        24,
        24,
        24,
        24,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
        53,
    ]
    var picks = [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
    ]
    var significands = [
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("2"),
        String("3"),
        String("3"),
        String("2"),
        String("3"),
        String("3"),
        String("3"),
        String("11184810"),
        String("11184811"),
        String("11184811"),
        String("11184810"),
        String("11184811"),
        String("11184811"),
        String("11184811"),
        String("6004799503160661"),
        String("6004799503160662"),
        String("6004799503160662"),
        String("6004799503160661"),
        String("6004799503160661"),
        String("6004799503160661"),
        String("6004799503160661"),
        String("6004799503160661"),
        String("6004799503160662"),
        String("6004799503160662"),
        String("6004799503160661"),
        String("6004799503160661"),
        String("6004799503160661"),
        String("6004799503160661"),
        String("5146971002709138"),
        String("5146971002709139"),
        String("5146971002709139"),
        String("5146971002709138"),
        String("5146971002709138"),
        String("5146971002709138"),
        String("5146971002709138"),
        String("7205759403792793"),
        String("7205759403792794"),
        String("7205759403792794"),
        String("7205759403792793"),
        String("7205759403792794"),
        String("7205759403792794"),
        String("7205759403792794"),
        String("7074238352727991"),
        String("7074238352727992"),
        String("7074238352727992"),
        String("7074238352727991"),
        String("7074238352727992"),
        String("7074238352727992"),
        String("7074238352727992"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("1"),
        String("2"),
        String("3"),
        String("3"),
        String("2"),
        String("3"),
        String("2"),
        String("2"),
        String("3"),
        String("2"),
        String("2"),
        String("3"),
        String("2"),
        String("3"),
        String("2"),
        String("4"),
        String("5"),
        String("5"),
        String("4"),
        String("5"),
        String("4"),
        String("4"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("9007199254740991"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("9007199254740991"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370497"),
        String("4503599627370497"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("4503599627370496"),
        String("9007199254740990"),
        String("9007199254740991"),
        String("9007199254740991"),
        String("9007199254740990"),
        String("9007199254740990"),
        String("9007199254740990"),
        String("9007199254740990"),
    ]
    var exponents = [
        -2,
        -1,
        -1,
        -2,
        -2,
        -2,
        -2,
        -3,
        -3,
        -3,
        -3,
        -3,
        -3,
        -3,
        -25,
        -25,
        -25,
        -25,
        -25,
        -25,
        -25,
        -54,
        -54,
        -54,
        -54,
        -54,
        -54,
        -54,
        -53,
        -53,
        -53,
        -53,
        -53,
        -53,
        -53,
        -55,
        -55,
        -55,
        -55,
        -55,
        -55,
        -55,
        -56,
        -56,
        -56,
        -56,
        -56,
        -56,
        -56,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        -1,
        0,
        0,
        -1,
        0,
        -1,
        0,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -52,
        -52,
        -52,
        -52,
        -52,
        -52,
        -52,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -51,
        -53,
        -53,
        -53,
        -53,
        -53,
        -53,
        -53,
        -117,
        -116,
        -116,
        -117,
        -116,
        -116,
        -116,
        12,
        12,
        12,
        12,
        12,
        12,
        12,
        -53,
        -53,
        -53,
        -53,
        -53,
        -53,
        -53,
    ]
    for i in range(len(numerators)):
        var x = BigFloat.from_bigint(
            BigInt(numerators[i]), numerators[i].byte_length() * 4 + 4
        )
        var y = BigFloat.from_bigint(
            BigInt(denominators[i]), denominators[i].byte_length() * 4 + 4
        )
        var got = divide(x, y, precisions[i], modes[picks[i]])
        assert_equal(
            got.internal_representation(),
            significands[i]
            + "p"
            + String(exponents[i])
            + "@"
            + String(precisions[i]),
            String("the quotient of ")
            + numerators[i]
            + " over "
            + denominators[i]
            + " at "
            + String(precisions[i])
            + " bits, "
            + String(modes[picks[i]]),
        )


def test_the_product_is_what_the_exact_decimal_rounds_to() raises:
    """The exact product formed in decimal, then rounded once there.

    A product of significands is an integer and a binary float's expansion is
    exact, so the decimal route gives the same number by a different road.
    """
    var values = [
        BigFloat.from_string("1", 53),
        BigFloat.from_string("0.1", 53),
        BigFloat.from_string("-0.1", 54),
        BigFloat.from_string("1e300", 53),
        BigFloat.from_string("-1e-300", 53),
        BigFloat.from_string("3.14159265358979323846264338327950288", 100),
        BigFloat.from_string("1", 200),
    ]
    var modes = _modes()
    for i in range(len(values)):
        for j in range(len(values)):
            var exact = (
                values[i].to_bigdecimal().multiply(values[j].to_bigdecimal())
            )
            for precision in [1, 2, 53, 200]:
                for m in range(len(modes)):
                    var mode = modes[m]
                    var result = multiply(values[i], values[j], precision, mode)
                    var expected = BigFloat.from_bigdecimal(
                        exact, precision, mode
                    )
                    assert_equal(
                        result.internal_representation(),
                        expected.internal_representation(),
                        String("the product of pair ")
                        + String(i)
                        + ","
                        + String(j)
                        + " at "
                        + String(precision)
                        + " bits",
                    )


def test_a_product_that_fits_is_exact() raises:
    """Nothing rounds when the destination is wide enough to hold it.

    Two significands of `p` bits make a product of at most `2p`, so a
    destination that wide keeps it whole in every mode.
    """
    var a = BigFloat.from_string("1.4142135623730951", 53)
    var b = BigFloat.from_string("2.7182818284590452", 53)
    var wide = multiply(a, b, 106)
    for mode in _modes():
        assert_equal(
            multiply(a, b, 106, mode).internal_representation(),
            wide.internal_representation(),
            "a product that fits does not depend on the mode",
        )
    assert_equal(
        wide.to_bigdecimal(),
        a.to_bigdecimal().multiply(b.to_bigdecimal()),
        "and it is the exact product",
    )

    # Multiplying is commutative, which a rounding could break and does not.
    for precision in [1, 7, 53, 106]:
        assert_equal(
            multiply(a, b, precision).internal_representation(),
            multiply(b, a, precision).internal_representation(),
            "the order of the operands is nothing",
        )


def test_dividing_by_a_power_of_two_only_moves_the_exponent() raises:
    """A power of two divides exactly, whatever the precision.

    The significand comes back unchanged and the exponent takes the whole of
    the change, so this is the one division where no rounding happens at all.
    """
    var value = BigFloat.from_string("3.14159265358979323846", 70)
    for shift in [1, 2, 64, 1000]:
        var power = BigFloat(
            significand=BigInt.one(),
            exponent=shift,
            precision=1,
            sign=False,
        )
        var quotient = divide(value, power, 70)
        assert_equal(
            String(quotient.significand),
            String(value.significand),
            "the significand is untouched",
        )
        assert_equal(
            quotient.exponent,
            value.exponent - shift,
            "and the exponent carries the division",
        )


def test_the_special_values_follow_ieee() raises:
    """Zero times an infinity is nothing; dividing by zero is an infinity."""
    var nan = BigFloat.nan()
    var infinity = BigFloat.infinity()
    var one = BigFloat.from_int(1)
    var zero = BigFloat.zero()

    for other in [nan.copy(), infinity.copy(), one.copy(), BigFloat.zero()]:
        assert_true(multiply(nan, other, 53).is_nan(), "a NaN spreads")
        assert_true(divide(other, nan, 53).is_nan(), "through a division too")

    assert_true(
        multiply(infinity, zero, 53).is_nan(),
        "an infinity times a zero has no answer",
    )
    assert_true(
        multiply(zero, -infinity, 53).is_nan(),
        "from either side",
    )
    assert_true(
        multiply(infinity, one, 53).is_infinite(),
        "an infinity swallows",
    )
    assert_true(
        multiply(-one, infinity, 53).sign,
        "and takes the sign it is given",
    )

    # The zeros keep the sign the two operands give them.
    assert_true(multiply(-one, zero, 53).is_zero(), "a zero product")
    assert_true(multiply(-one, zero, 53).sign, "is signed like a product")
    assert_false(
        multiply(BigFloat.zero(53, True), -one, 53).sign,
        "two negatives make a positive zero",
    )

    # Division by zero. IEEE 754 calls it an exception and flags it; with no
    # flags to raise, the value it specifies is the whole of the answer.
    assert_true(divide(one, zero, 53).is_infinite(), "one over zero")
    assert_true(
        divide(-one, zero, 53).sign, "which carries the sign of the pair"
    )
    assert_true(divide(zero, zero, 53).is_nan(), "zero over zero has no value")
    assert_true(
        divide(infinity, infinity, 53).is_nan(), "nor has infinity over it"
    )
    assert_true(
        divide(one, infinity, 53).is_zero(), "a finite value over it is zero"
    )
    assert_true(divide(zero, one, 53).is_zero(), "and zero over anything is")


def test_an_exponent_outside_int_is_refused() raises:
    """The unbounded exponent is unbounded until an `Int` says otherwise.

    Multiplying two values near the top of the range asks for an exponent
    above it, and dividing one near the top by one near the bottom asks the
    same. Wrapping round would answer with a tiny number instead of a huge
    one, so both refuse.
    """
    var huge = BigFloat(
        significand=BigInt.one(),
        exponent=Int.MAX - 10,
        precision=1,
        sign=False,
    )
    var tiny = BigFloat(
        significand=BigInt.one(),
        exponent=Int.MIN + 10,
        precision=1,
        sign=False,
    )
    var raised = False
    try:
        _ = multiply(huge, huge, 53)
    except:
        raised = True
    assert_true(raised, "a product above the range was invented")

    raised = False
    try:
        _ = divide(huge, tiny, 53)
    except:
        raised = True
    assert_true(raised, "a quotient above the range was invented")

    raised = False
    try:
        _ = multiply(tiny, tiny, 53)
    except:
        raised = True
    assert_true(raised, "a product below the range was invented")

    # The two together are fine, since the exponents cancel.
    assert_true(
        multiply(huge, tiny, 53).is_finite(), "the exponents cancel out"
    )


def test_the_operators_take_the_wider_precision() raises:
    """`*` and `/` assume the same two things `+` and `-` do."""
    var narrow = BigFloat.from_string("1", 53)
    var wide = BigFloat.from_string("3", 200)
    assert_equal((narrow * wide).precision, 200, "the wider of the two")
    assert_equal((narrow / wide).precision, 200, "for a division as well")
    assert_equal(
        (narrow / wide).internal_representation(),
        divide(
            narrow, wide, 200, RoundingMode.ROUND_HALF_EVEN
        ).internal_representation(),
        "and half to even",
    )


def test_a_precision_must_be_positive() raises:
    for precision in [0, -1]:
        var raised = False
        try:
            _ = multiply(BigFloat.from_int(2), BigFloat.from_int(3), precision)
        except:
            raised = True
        assert_true(raised, "a product of no bits was accepted")

        raised = False
        try:
            _ = divide(BigFloat.from_int(2), BigFloat.from_int(3), precision)
        except:
            raised = True
        assert_true(raised, "a quotient of no bits was accepted")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
