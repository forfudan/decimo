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
Tests the comparison of `BigFloat`.

The reference is `Float64`, which answers the same questions in hardware: for
every pair drawn from a list that includes both zeros, the subnormals, the
infinities and a NaN, all six operators have to agree with the double's. That
covers the unordered rules without having to restate them.

What a double cannot check is two floats of different precisions holding the
same number, the exponents near the ends of `Int` where the leading-bit
comparison could overflow, and the total order. Those have tests of their own,
and the cross-precision ones are checked against `BigDecimal`, whose
comparison is older than this one.
"""

from std import testing
from std.memory import bitcast
from std.testing import assert_equal, assert_false, assert_true

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.comparison import (
    compare,
    compare_absolute,
    compare_total,
    compare_total_absolute,
    is_unordered,
    max,
    min,
)
from decimo.bigint.bigint import BigInt


def _doubles() -> List[Float64]:
    """The values every pair of which is compared.

    Returns:
        Both zeros, the subnormals at both ends, ordinary values of both
        signs, the largest finite double, the infinities and a NaN.
    """
    var nan = Float64(0) / Float64(0)
    var infinity = Float64(1) / Float64(0)
    return [
        -infinity,
        -1.7976931348623157e308,
        -2.5,
        -1.0,
        -2.2250738585072014e-308,
        bitcast[DType.float64](UInt64(1) << 63 | UInt64(1)),
        Float64(-0.0),
        Float64(0.0),
        bitcast[DType.float64](UInt64(1)),
        2.2250738585072014e-308,
        0.1,
        1.0,
        2.5,
        1.7976931348623157e308,
        infinity,
        nan,
    ]


def test_every_pair_agrees_with_float64() raises:
    """All six operators, over every pair of sixteen doubles.

    A double is a binary float, so `from_float64()` is exact and the two
    types are comparing the same numbers. Where they could differ is the
    unordered rules and the two zeros, which is what makes this worth
    sweeping rather than asserting one case at a time.
    """
    var values = _doubles()
    for i in range(len(values)):
        for j in range(len(values)):
            var a = values[i]
            var b = values[j]
            var x = BigFloat.from_float64(a)
            var y = BigFloat.from_float64(b)
            var at = String(" at ") + String(a) + " and " + String(b)
            assert_equal(x == y, a == b, "equality" + at)
            assert_equal(x != y, a != b, "inequality" + at)
            assert_equal(x < y, a < b, "less" + at)
            assert_equal(x <= y, a <= b, "less or equal" + at)
            assert_equal(x > y, a > b, "greater" + at)
            assert_equal(x >= y, a >= b, "greater or equal" + at)


def test_a_nan_is_unordered() raises:
    """Every order question about a NaN answers no, and `!=` answers yes."""
    var nan = BigFloat.nan()
    for other in [BigFloat.nan(), BigFloat.from_int(1), BigFloat.infinity()]:
        assert_true(is_unordered(nan, other), "a NaN is unordered")
        assert_false(nan == other, "a NaN equals nothing")
        assert_true(nan != other, "a NaN differs from everything")
        assert_false(nan < other, "a NaN is not below")
        assert_false(nan <= other, "a NaN is not below or level")
        assert_false(nan > other, "a NaN is not above")
        assert_false(nan >= other, "a NaN is not above or level")

    # Itself included, which is the part that surprises people.
    assert_false(nan == nan, "a NaN does not equal itself")
    assert_true(nan != nan, "a NaN differs from itself")
    assert_false(nan <= nan, "a NaN is not level with itself")


def test_the_three_way_comparison_refuses_a_nan() raises:
    """`compare()` has no answer for a NaN, so it says so."""
    for pair in [
        [BigFloat.nan(), BigFloat.from_int(1)],
        [BigFloat.from_int(1), BigFloat.nan()],
        [BigFloat.nan(), BigFloat.nan()],
    ]:
        var raised = False
        try:
            _ = compare(pair[0], pair[1])
        except:
            raised = True
        assert_true(raised, "a NaN was given an order")

        raised = False
        try:
            _ = compare_absolute(pair[0], pair[1])
        except:
            raised = True
        assert_true(raised, "a NaN was given a magnitude order")


def test_the_two_zeros_compare_equal() raises:
    """`-0` and `+0` are different values and the same number."""
    var positive = BigFloat.zero(53, False)
    var negative = BigFloat.zero(53, True)
    assert_true(positive == negative, "the zeros are equal")
    assert_false(positive < negative, "neither zero is below the other")
    assert_false(positive > negative, "neither zero is above the other")
    assert_true(negative.sign, "and the sign is still there")

    # A zero sits between the negatives and the positives whichever sign it
    # carries.
    for zero in [positive.copy(), negative.copy()]:
        assert_true(zero > BigFloat.from_int(-1), "a zero is above -1")
        assert_true(zero < BigFloat.from_int(1), "a zero is below 1")


def test_the_infinities_bound_everything() raises:
    """The order runs from `-Infinity` to `+Infinity` with no gaps at the ends.
    """
    var infinity = BigFloat.infinity()
    var negative = -BigFloat.infinity()
    assert_true(infinity == BigFloat.infinity(), "an infinity equals itself")
    assert_true(negative < infinity, "the two infinities are ordered")
    for value in [
        BigFloat.from_int(0),
        BigFloat.from_int(-1),
        BigFloat.from_float64(1.7976931348623157e308),
        BigFloat.from_float64(-1.7976931348623157e308),
    ]:
        assert_true(value < infinity, "a finite value is below an infinity")
        assert_true(
            value > negative, "a finite value is above a negative infinity"
        )

    # The magnitudes of the two are the same, which is what separates
    # `compare_absolute()` from `compare()`.
    assert_equal(compare_absolute(negative, infinity), 0, "same magnitude")
    assert_equal(compare(negative, infinity), -1, "different values")


def test_the_same_number_at_different_precisions_is_equal() raises:
    """A value does not change when it is held in more bits.

    Widening a significand multiplies it by a power of two and lowers the
    exponent by the same amount, so the leading bits stay level and the
    comparison has to look past the precision to the value.
    """
    for text in ["1", "-2.5", "0.5", "1024", "0.0625"]:
        var narrow = BigFloat.from_string(text, 53)
        var wide = BigFloat.from_string(text, 200)
        assert_equal(narrow.precision, 53, "the narrow one keeps its precision")
        assert_equal(wide.precision, 200, "and so does the wide one")
        assert_true(narrow == wide, "the same number at both precisions")
        assert_false(narrow < wide, "neither is below the other")
        assert_false(narrow > wide, "neither is above the other")

    # And a number that needs the wider precision is not equal to its own
    # rounding, which is the other half of the same test. Which way the
    # rounding went is for the decimals to say, not for this test to assume.
    var digits = String("1.") + "1234567890" * 6
    var rounded = BigFloat.from_string(digits, 53)
    var exact = BigFloat.from_string(digits, 300)
    assert_false(rounded == exact, "rounding moved the value")
    assert_equal(
        rounded < exact,
        rounded.to_bigdecimal() < exact.to_bigdecimal(),
        "and it moved the way the expansions say",
    )


def test_the_order_agrees_with_the_exact_decimals() raises:
    """`BigDecimal` compares the same values, through a different route.

    Each float's exact decimal expansion is the same number it is, so the two
    comparisons have to give the same answer. The pairs mix precisions on
    purpose, which is what a double cannot check.
    """
    var values = [
        BigFloat.from_string("0.1", 53),
        BigFloat.from_string("0.1", 54),
        BigFloat.from_string("0.1", 200),
        BigFloat.from_string("-0.1", 53),
        BigFloat.from_string("3.14159265358979323846", 70),
        BigFloat.from_string("3.14159265358979323846", 71),
        BigFloat.from_string("1e-300", 53),
        BigFloat.from_string("1e300", 53),
        BigFloat.from_string("-1e300", 120),
        BigFloat.from_int(0),
    ]
    for i in range(len(values)):
        for j in range(len(values)):
            var decimal_order = Int(
                values[i].to_bigdecimal() > values[j].to_bigdecimal()
            ) - Int(values[i].to_bigdecimal() < values[j].to_bigdecimal())
            assert_equal(
                Int(compare(values[i], values[j])),
                decimal_order,
                String("pair ") + String(i) + " and " + String(j),
            )


def test_an_exponent_near_the_ends_of_int_does_not_overflow() raises:
    """The leading bits are compared without ever forming their position.

    `exponent + precision - 1` is where the top bit sits, and the gap between
    two exponents at opposite ends of `Int` is wider than `Int` can hold. A
    comparison that subtracted them would wrap and answer backwards.
    """
    var huge = BigFloat(
        significand=BigInt.one() << 52,
        exponent=Int.MAX - 60,
        precision=53,
        sign=False,
    )
    var tiny = BigFloat(
        significand=BigInt.one() << 52,
        exponent=Int.MIN + 60,
        precision=53,
        sign=False,
    )
    assert_true(huge > tiny, "the larger exponent is the larger value")
    assert_true(tiny < huge, "and the comparison is symmetric")
    assert_false(huge == tiny, "they are not equal")
    assert_true(-huge < tiny, "and negating flips it")

    # The same two against a value in the middle.
    var one = BigFloat.from_int(1)
    assert_true(tiny < one, "the tiny one is below one")
    assert_true(huge > one, "the huge one is above one")

    # A precision difference cannot bridge a gap that wide.
    var wide = BigFloat(
        significand=BigInt.one() << 999,
        exponent=Int.MIN + 60,
        precision=1000,
        sign=False,
    )
    assert_true(huge > wide, "a thousand bits do not close the gap")


def test_the_total_order_covers_every_value() raises:
    """A sequence in the total order, checked pair by pair.

    `compare()` has nothing to say about a NaN, so sorting needs an order
    that does. This one runs from `-Infinity` up to the NaN, which goes last
    because the type has one NaN rather than a signed pair, puts `-0` before
    `+0`, and separates equal numbers by their precision.
    """
    var ordered = [
        -BigFloat.infinity(),
        BigFloat.from_int(-2),
        BigFloat.from_int(-1),
        BigFloat.zero(53, True),
        BigFloat.zero(53, False),
        BigFloat.from_string("1", 200),
        BigFloat.from_string("1", 53),
        BigFloat.from_int(2),
        BigFloat.infinity(),
        BigFloat.nan(),
    ]
    for i in range(len(ordered)):
        assert_equal(
            compare_total(ordered[i], ordered[i]),
            0,
            "a value is level with itself",
        )
        for j in range(i + 1, len(ordered)):
            assert_equal(
                compare_total(ordered[i], ordered[j]),
                -1,
                String("position ") + String(i) + " before " + String(j),
            )
            assert_equal(
                compare_total(ordered[j], ordered[i]),
                1,
                String("position ") + String(j) + " after " + String(i),
            )

    # The magnitude order ignores the signs, so the two zeros meet.
    assert_equal(
        compare_total_absolute(
            BigFloat.zero(53, True), BigFloat.zero(53, False)
        ),
        0,
        "the zeros have the same magnitude",
    )
    assert_equal(
        compare_total_absolute(BigFloat.from_int(-2), BigFloat.from_int(1)),
        1,
        "two is the larger magnitude",
    )

    # Negating a NaN leaves it alone, so it does not move in the order.
    assert_equal(
        compare_total(-BigFloat.nan(), BigFloat.nan()),
        0,
        "there is one NaN, so negating it changes nothing",
    )


def test_max_and_min_pass_over_a_nan() raises:
    """A NaN is not an answer, so the other operand is.

    This is what IEEE 754 asks of `maxNum` and `minNum`: a NaN stands for a
    missing value rather than a large one, so it loses to anything that is a
    number, and only two NaNs give a NaN.
    """
    var one = BigFloat.from_int(1)
    var two = BigFloat.from_int(2)
    assert_true(max(one, two) == two, "two is the larger")
    assert_true(min(one, two) == one, "one is the smaller")
    assert_true(max(two, one) == two, "the order of the operands is nothing")
    assert_true(min(two, one) == one, "either way round")

    assert_true(max(BigFloat.nan(), two) == two, "a NaN loses to a number")
    assert_true(min(BigFloat.nan(), two) == two, "in both directions")
    assert_true(max(two, BigFloat.nan()) == two, "whichever side it is on")
    assert_true(min(two, BigFloat.nan()) == two, "and for the minimum too")
    assert_true(
        max(BigFloat.nan(), BigFloat.nan()).is_nan(),
        "two NaNs leave only a NaN",
    )
    assert_true(
        min(BigFloat.nan(), BigFloat.nan()).is_nan(), "for the minimum as well"
    )

    # The zeros are equal, so which one comes back is a choice, and the choice
    # is the one the name suggests.
    assert_false(
        max(BigFloat.zero(53, True), BigFloat.zero(53, False)).sign,
        "the larger zero is the positive one",
    )
    assert_true(
        min(BigFloat.zero(53, True), BigFloat.zero(53, False)).sign,
        "and the smaller is the negative one",
    )

    # An infinity is a number, so it wins or loses like one.
    assert_true(max(BigFloat.infinity(), two).is_infinite(), "infinity wins")
    assert_true(min(-BigFloat.infinity(), two).is_infinite(), "and loses")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
