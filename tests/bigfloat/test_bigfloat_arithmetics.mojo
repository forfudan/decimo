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
Tests the addition and subtraction of `BigFloat`.

Correct rounding is checked against a route that shares no code with the one
under test. A binary float's decimal expansion is exact, `BigDecimal`'s
addition is exact when asked for exactly -- `add()` rather than `+`, which
rounds to twenty-eight digits for Python's sake -- and `from_bigdecimal()` rounds a decimal to a binary
precision correctly -- that last one is what 924 strings were checked against
CPython for. So the exact sum can be formed in decimal and rounded there, and
the answer has to be the one the binary addition gives, for every pair, every
precision and all seven modes.

`Float64` is the second reference, for the pairs whose hardware sum is a
normal double: hardware addition is correctly rounded to 53 bits, so the bit
patterns have to match.

The rest are the cases neither reference reaches: operands far enough apart
that the smaller one is only a sticky bit, cancellation that is exact, and
exponents at the ends of `Int`.
"""

from std import testing
from std.memory import bitcast
from std.testing import assert_equal, assert_false, assert_true

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigfloat.arithmetics import add, subtract
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


def _operands() raises -> List[BigFloat]:
    """Values that make the addition work for its answer.

    Returns:
        Both signs, precisions from 53 to 200, exponents three hundred
        decades apart so that some pairs are far and some near, and a pair
        that differs only in its last bit so that subtracting them cancels.
    """
    var near_one = BigFloat.from_string("1", 200)
    near_one.significand = near_one.significand + BigInt.one()
    return [
        BigFloat.from_string("1", 53),
        BigFloat.from_string("0.1", 53),
        BigFloat.from_string("-0.1", 54),
        BigFloat.from_string("1e300", 53),
        BigFloat.from_string("-1e-300", 53),
        BigFloat.from_string("3.14159265358979323846264338327950288", 100),
        BigFloat.from_string("1", 200),
        near_one^,
    ]


def test_the_sum_is_what_the_exact_decimal_rounds_to() raises:
    """Every pair, four precisions, all seven modes, against the decimals.

    The exact sum is formed as a decimal, where nothing rounds, and then
    rounded once to the destination's precision. That is the definition of a
    correctly rounded sum, computed without any of the code it is checking.
    """
    var values = _operands()
    var modes = _modes()
    for i in range(len(values)):
        for j in range(len(values)):
            var exact = values[i].to_bigdecimal().add(values[j].to_bigdecimal())
            for precision in [1, 2, 53, 200]:
                for m in range(len(modes)):
                    var mode = modes[m]
                    var result = add(values[i], values[j], precision, mode)
                    var at = (
                        String(" at pair ")
                        + String(i)
                        + ","
                        + String(j)
                        + " precision "
                        + String(precision)
                        + " mode "
                        + String(mode)
                    )
                    if exact.coefficient.is_zero():
                        # The decimals have no signed zero to compare, so the
                        # sign of a vanished sum is checked by its own rule.
                        assert_true(result.is_zero(), "a zero sum" + at)
                        assert_equal(
                            result.sign,
                            mode == RoundingMode.ROUND_FLOOR,
                            "the sign of a vanished sum" + at,
                        )
                        continue
                    var expected = BigFloat.from_bigdecimal(
                        exact, precision, mode
                    )
                    assert_equal(
                        result.internal_representation(),
                        expected.internal_representation(),
                        "the sum" + at,
                    )


def test_the_difference_is_too() raises:
    """The same sweep for `subtract()`, which is not the same values.

    Subtracting reaches pairs that adding does not: two values of the same
    sign and nearly the same magnitude cancel, and that is where a float's
    rounding is hardest.
    """
    var values = _operands()
    var modes = _modes()
    for i in range(len(values)):
        for j in range(len(values)):
            var exact = (
                values[i].to_bigdecimal().subtract(values[j].to_bigdecimal())
            )
            for precision in [1, 53, 200]:
                for m in range(len(modes)):
                    var mode = modes[m]
                    var result = subtract(values[i], values[j], precision, mode)
                    var at = (
                        String(" at pair ")
                        + String(i)
                        + ","
                        + String(j)
                        + " precision "
                        + String(precision)
                        + " mode "
                        + String(mode)
                    )
                    if exact.coefficient.is_zero():
                        assert_true(
                            result.is_zero(), "a vanished difference" + at
                        )
                        assert_equal(
                            result.sign,
                            mode == RoundingMode.ROUND_FLOOR,
                            "the sign of a vanished difference" + at,
                        )
                        continue
                    var expected = BigFloat.from_bigdecimal(
                        exact, precision, mode
                    )
                    assert_equal(
                        result.internal_representation(),
                        expected.internal_representation(),
                        "the difference" + at,
                    )


def test_adding_doubles_matches_the_hardware() raises:
    """Where a double can answer, it has to be the same answer.

    Hardware addition is correctly rounded to 53 bits, so for every pair
    whose sum is a normal double -- which is where the double's own bounded
    exponent and subnormals cannot make it differ -- the bit patterns match.
    """
    var samples = [
        Float64(0.1),
        Float64(-0.1),
        Float64(1.0),
        Float64(2.5),
        Float64(-1024.0),
        Float64(1e300),
        Float64(-1e-300),
        Float64(0.30000000000000004),
        Float64(9007199254740993.0),
        Float64(1.7976931348623157e308),
        Float64(0.0),
        Float64(-0.0),
    ]
    var compared = 0
    for i in range(len(samples)):
        for j in range(len(samples)):
            var a = samples[i]
            var b = samples[j]
            var sum = a + b
            # Skip what a double cannot represent but a `BigFloat` can: an
            # overflow to infinity, and a subnormal result, which rounds a
            # second time on the way back into a double.
            if not (sum - sum == Float64(0)):
                continue
            if sum != Float64(0) and abs(sum) < Float64(
                2.2250738585072014e-308
            ):
                continue
            var answer = add(
                BigFloat.from_float64(a), BigFloat.from_float64(b), 53
            )
            assert_equal(
                bitcast[DType.uint64](answer.to_float64()),
                bitcast[DType.uint64](sum),
                String("the bits of ") + String(a) + " + " + String(b),
            )
            compared += 1
    assert_true(compared > 100, "the sweep compared almost nothing")


def test_a_far_operand_leaves_only_a_sticky_bit() raises:
    """One is far below the other, so it cannot change a bit, only a rounding.

    `2^-1000` is nowhere near the last bit of `1` at 53 bits, and the whole
    of its contribution is that the sum is not exactly one. Toward zero that
    changes nothing; away from zero it is a whole unit in the last place.
    """
    var one = BigFloat.from_string("1", 53)
    var tiny = BigFloat.from_string("1e-1000", 53)

    # The two neighbours of one at 53 bits, written as the parts they are.
    # Above one the unit is `2^-52`; below it the binade changes and the unit
    # is half that, which is why the two are not symmetric.
    var next_up = BigFloat(
        significand=(BigInt.one() << 52) + BigInt.one(),
        exponent=-52,
        precision=53,
        sign=False,
    )
    var next_down = BigFloat(
        significand=(BigInt.one() << 53) - BigInt.one(),
        exponent=-53,
        precision=53,
        sign=False,
    )

    assert_equal(
        add(one, tiny, 53, RoundingMode.ROUND_HALF_EVEN).to_bigdecimal(),
        BigDecimal("1"),
        "a sticky bit alone does not reach half",
    )
    assert_equal(
        add(one, tiny, 53, RoundingMode.ROUND_DOWN).to_bigdecimal(),
        BigDecimal("1"),
        "toward zero keeps the truncation",
    )
    assert_equal(
        add(one, tiny, 53, RoundingMode.ROUND_UP).internal_representation(),
        next_up.internal_representation(),
        "away from zero takes the whole unit",
    )
    assert_equal(
        add(
            one, tiny, 53, RoundingMode.ROUND_CEILING
        ).internal_representation(),
        next_up.internal_representation(),
        "and so does toward positive infinity, for a positive value",
    )

    # Taking the tiny one away instead. The sum is a hair below one, so the
    # modes that go down have to find the value below it, which is a unit of
    # half the size -- the binade changes at a power of two.
    assert_equal(
        subtract(one, tiny, 53, RoundingMode.ROUND_HALF_EVEN).to_bigdecimal(),
        BigDecimal("1"),
        "a hair below one still rounds to one",
    )
    assert_equal(
        subtract(
            one, tiny, 53, RoundingMode.ROUND_DOWN
        ).internal_representation(),
        next_down.internal_representation(),
        "toward zero finds the value below one, a unit of half the size",
    )
    assert_equal(
        subtract(
            one, tiny, 53, RoundingMode.ROUND_FLOOR
        ).internal_representation(),
        next_down.internal_representation(),
        "and so does toward negative infinity",
    )
    assert_equal(
        subtract(one, tiny, 53, RoundingMode.ROUND_UP).to_bigdecimal(),
        BigDecimal("1"),
        "away from zero rounds back up to one",
    )


def test_cancellation_is_exact() raises:
    """Subtracting two values that nearly agree loses nothing.

    The near case computes the exact difference, so two hundred-bit values
    differing in their last bit give that bit, not a zero and not a rounded
    approximation of one.
    """
    var one = BigFloat.from_string("1", 200)
    var next = BigFloat.from_string("1", 200)
    next.significand = next.significand + BigInt.one()
    var step = subtract(next, one, 200)
    var unit = BigFloat(
        significand=BigInt.one() << 199,
        exponent=-199 - 199,
        precision=200,
        sign=False,
    )
    assert_equal(
        step.internal_representation(),
        unit.internal_representation(),
        "the difference is one unit in the last place",
    )

    # And a value taken from itself vanishes, with the sign the mode gives.
    for mode in _modes():
        var vanished = subtract(one, one, 200, mode)
        assert_true(vanished.is_zero(), "a value minus itself is zero")
        assert_equal(
            vanished.sign,
            mode == RoundingMode.ROUND_FLOOR,
            "only toward negative infinity is it a negative zero",
        )


def test_the_exponents_can_sit_at_the_ends_of_int() raises:
    """The gap between the operands is wider than `Int` can hold.

    Nothing here forms `exponent + precision`, and the one comparison that
    could overflow answers without doing so. A version that subtracted the
    two exponents outright would take the near path and try to shift a
    significand by `2^63` bits.
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
    assert_equal(
        add(huge, tiny, 53).internal_representation(),
        huge.internal_representation(),
        "the tiny one cannot reach the huge one's last bit",
    )
    assert_true(
        add(huge, tiny, 53, RoundingMode.ROUND_UP) > huge,
        "but away from zero it still moves it a unit",
    )
    assert_true(
        subtract(huge, tiny, 53, RoundingMode.ROUND_DOWN) < huge,
        "and toward zero a unit the other way",
    )
    assert_equal(
        add(tiny, huge, 53).internal_representation(),
        huge.internal_representation(),
        "the order of the operands is nothing",
    )


def test_the_bottom_of_the_exponent_range_still_adds() raises:
    """Two values at `Int.MIN` add, and nothing has to reach below it.

    Making room for the bits a rounding reads lowers an exponent by two, so
    a value at the very bottom of the range looks like a problem. It is not:
    the case that lowers the exponent is only taken when the other operand
    sits below the first one's last bit, which already puts the first one
    above the bottom by more than the room it needs. A value at `Int.MIN` is
    therefore always the smaller of the two, and the smaller one is never the
    one that gets widened.
    """
    var floor_value = BigFloat(
        significand=BigInt.one() << 52,
        exponent=Int.MIN,
        precision=53,
        sign=False,
    )
    assert_true(
        add(floor_value, -floor_value, 53).is_zero(),
        "a value and its negation cancel at the bottom of the range",
    )
    assert_equal(
        add(floor_value, floor_value, 53).exponent,
        Int.MIN + 1,
        "doubling it moves the exponent up, not down",
    )
    assert_equal(
        add(floor_value, BigFloat.from_int(1), 53).internal_representation(),
        BigFloat.from_int(1).internal_representation(),
        "and against one it is the one that becomes a sticky bit",
    )
    assert_true(
        add(floor_value, BigFloat.from_int(1), 53, RoundingMode.ROUND_UP)
        > BigFloat.from_int(1),
        "which away from zero is still a whole unit",
    )


def test_the_top_of_the_exponent_range_is_refused() raises:
    """A sum whose normalized exponent is a step past the top has no answer.

    Two values at `Int.MAX` add to one whose leading bit is a place higher,
    and normalizing that to the same precision asks for `Int.MAX + 1`. The
    other direction is a value of one bit at `Int.MIN` widened to a
    destination of fifty-three, which lowers the exponent by fifty-two. Both
    refuse, because wrapping round would answer the largest number with the
    smallest.
    """
    var top = BigFloat(
        significand=BigInt.one() << 52,
        exponent=Int.MAX,
        precision=53,
        sign=False,
    )
    var raised = False
    try:
        _ = add(top, top, 53)
    except:
        raised = True
    assert_true(raised, "an exponent above Int.MAX was invented")

    # One step down and the same sum is fine, which is what says the refusal
    # is about the range and not about the operands.
    var below = BigFloat(
        significand=BigInt.one() << 52,
        exponent=Int.MAX - 1,
        precision=53,
        sign=False,
    )
    assert_equal(
        add(below, below, 53).exponent,
        Int.MAX,
        "a sum that lands exactly on the top is still an answer",
    )

    var narrow = BigFloat(
        significand=BigInt.one(),
        exponent=Int.MIN,
        precision=1,
        sign=False,
    )
    raised = False
    try:
        _ = add(narrow, BigFloat.zero(), 53)
    except:
        raised = True
    assert_true(raised, "widening below Int.MIN was invented")

    # At its own precision it needs no widening and comes back unchanged.
    assert_equal(
        add(narrow, BigFloat.zero(), 1).internal_representation(),
        narrow.internal_representation(),
        "and with nothing to widen there is nothing to refuse",
    )


def test_a_zero_operand_still_rounds_the_other() raises:
    """Adding nothing is not always the identity, because of the destination.

    `0 + x` is `x` when the destination holds it, and the rounding of `x`
    when it does not. The precision is the result's, not the operand's.
    """
    var wide = BigFloat.from_string(
        "3.14159265358979323846264338327950288", 200
    )
    var zero = BigFloat.zero()
    assert_equal(
        add(wide, zero, 200).internal_representation(),
        wide.internal_representation(),
        "a wide destination keeps every bit",
    )
    assert_equal(
        add(wide, zero, 53).internal_representation(),
        BigFloat.from_string(
            "3.14159265358979323846264338327950288", 53
        ).internal_representation(),
        "a narrow one rounds, zero or no zero",
    )
    assert_equal(
        subtract(zero, wide, 53).internal_representation(),
        BigFloat.from_string(
            "-3.14159265358979323846264338327950288", 53
        ).internal_representation(),
        "and taking a value from nothing negates it",
    )


def test_the_special_values_follow_ieee() raises:
    """A NaN spreads, two opposite infinities make one, and the zeros add up."""
    var nan = BigFloat.nan()
    var infinity = BigFloat.infinity()
    var one = BigFloat.from_int(1)

    for other in [nan.copy(), infinity.copy(), one.copy(), BigFloat.zero()]:
        assert_true(add(nan, other, 53).is_nan(), "a NaN spreads")
        assert_true(add(other, nan, 53).is_nan(), "from either side")
        assert_true(subtract(nan, other, 53).is_nan(), "and through a minus")

    assert_true(
        add(infinity, infinity, 53).is_infinite(), "two infinities agree"
    )
    assert_false(add(infinity, infinity, 53).sign, "on their sign")
    assert_true(
        add(infinity, -infinity, 53).is_nan(),
        "two opposite infinities are no value",
    )
    assert_true(
        subtract(infinity, infinity, 53).is_nan(), "which a minus reaches too"
    )
    assert_true(add(infinity, one, 53).is_infinite(), "an infinity swallows")
    assert_true(
        subtract(one, infinity, 53).is_infinite(), "and carries its sign"
    )
    assert_true(
        subtract(one, infinity, 53).sign, "which the subtraction flipped"
    )

    # The zeros. Like signs keep theirs; opposite signs cancel, and only the
    # mode that comes down from above makes that negative.
    assert_false(
        add(BigFloat.zero(53, False), BigFloat.zero(53, False), 53).sign,
        "two positive zeros stay positive",
    )
    assert_true(
        add(BigFloat.zero(53, True), BigFloat.zero(53, True), 53).sign,
        "two negative zeros stay negative",
    )
    assert_false(
        add(BigFloat.zero(53, True), BigFloat.zero(53, False), 53).sign,
        "opposite zeros give a positive one",
    )
    assert_true(
        add(
            BigFloat.zero(53, True),
            BigFloat.zero(53, False),
            53,
            RoundingMode.ROUND_FLOOR,
        ).sign,
        "except coming down from above",
    )


def test_the_operators_take_the_wider_precision() raises:
    """`+` and `-` have to assume something, and this is what they assume."""
    var narrow = BigFloat.from_string("1", 53)
    var wide = BigFloat.from_string("0.1", 200)
    assert_equal((narrow + wide).precision, 200, "the wider of the two")
    assert_equal((wide - narrow).precision, 200, "either way round")
    assert_equal(
        (narrow + wide).internal_representation(),
        add(
            narrow, wide, 200, RoundingMode.ROUND_HALF_EVEN
        ).internal_representation(),
        "and half to even",
    )


def test_a_precision_must_be_positive() raises:
    for precision in [0, -1]:
        var raised = False
        try:
            _ = add(BigFloat.from_int(1), BigFloat.from_int(2), precision)
        except:
            raised = True
        assert_true(raised, "a precision of nought was accepted")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
