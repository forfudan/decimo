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
Tests that `BigDecimal`'s power rounds in the mode it was asked for.

An integer power used to be computed by `power()` -- which rounds to the
precision it was given -- and then rounded again, which is a rounding of an
already rounded value and leaves every mode with the same answer. `7 ** 31`
at fifteen digits ended in `846` in all seven modes, where truncation has to
end in `845`.

The expectations are exact. Each one is `base ** exponent` as a rational,
rounded to the precision asked for by a short program working in
`fractions.Fraction`, so the table holds the correctly rounded answer rather
than a transcription of a decimal one. The comparison is of values and not of
representations, because a trailing zero may sit in the coefficient or in the
scale without changing what the number is; the representation is pinned
separately, below, where it is part of the answer.
"""

from std import testing
from std.testing import assert_equal

from decimo.bigdecimal.bigdecimal import BigDecimal
import decimo.bigdecimal.exponential as bigdecimal_exponential
from decimo.biguint.biguint import BigUInt
from decimo.rounding_mode import RoundingMode


def _modes() -> List[RoundingMode]:
    """The seven modes, in the order the tables index them."""
    return [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]


def _same_value(
    got: BigDecimal, coefficient: BigUInt, scale: Int, negative: Bool
) raises -> Bool:
    """Whether a result is the value the table says, whatever its scale.

    Args:
        got: The result.
        coefficient: The expected coefficient.
        scale: The expected scale.
        negative: The expected sign.

    Returns:
        True when the two are the same number.

    Raises:
        Error: Propagated from the arithmetic.
    """
    if got.coefficient.is_zero() and coefficient.is_zero():
        return True
    if got.sign != negative:
        return False
    var left = got.coefficient.copy()
    var right = coefficient.copy()
    if got.scale < scale:
        left = left.multiply_by_power_of_ten(scale - got.scale)
    elif scale < got.scale:
        right = right.multiply_by_power_of_ten(got.scale - scale)
    return left == right


def test_an_integer_power_rounds_in_the_mode_asked_for() raises:
    """Twenty integer powers in all seven modes, against exact rationals.

    The bases cover both signs, values above and below one, and coefficients
    with and without a scale; the exponents cover both signs and reach fifty,
    where the exact power is far longer than any of these precisions keeps.
    """
    var modes = _modes()
    # base exponent precision mode expected_coefficient expected_scale negative
    var cases = [
        "3 50 20 0 71789798769185258877 -4 0",
        "3 50 20 1 71789798769185258878 -4 0",
        "3 50 20 2 71789798769185258878 -4 0",
        "3 50 20 3 71789798769185258877 -4 0",
        "3 50 20 4 71789798769185258877 -4 0",
        "3 50 20 5 71789798769185258877 -4 0",
        "3 50 20 6 71789798769185258877 -4 0",
        "7 31 15 0 157775382034845 -12 0",
        "7 31 15 1 157775382034846 -12 0",
        "7 31 15 2 157775382034846 -12 0",
        "7 31 15 3 157775382034845 -12 0",
        "7 31 15 4 157775382034846 -12 0",
        "7 31 15 5 157775382034846 -12 0",
        "7 31 15 6 157775382034846 -12 0",
        "2 -7 1 0 7 3 0",
        "2 -7 1 1 8 3 0",
        "2 -7 1 2 8 3 0",
        "2 -7 1 3 7 3 0",
        "2 -7 1 4 8 3 0",
        "2 -7 1 5 8 3 0",
        "2 -7 1 6 8 3 0",
        "2 10 20 0 10240000000000000000 16 0",
        "2 10 20 1 10240000000000000000 16 0",
        "2 10 20 2 10240000000000000000 16 0",
        "2 10 20 3 10240000000000000000 16 0",
        "2 10 20 4 10240000000000000000 16 0",
        "2 10 20 5 10240000000000000000 16 0",
        "2 10 20 6 10240000000000000000 16 0",
        "5 3 2 0 12 -1 0",
        "5 3 2 1 13 -1 0",
        "5 3 2 2 13 -1 0",
        "5 3 2 3 12 -1 0",
        "5 3 2 4 13 -1 0",
        "5 3 2 5 12 -1 0",
        "5 3 2 6 12 -1 0",
        "3 -5 20 0 41152263374485596707 22 0",
        "3 -5 20 1 41152263374485596708 22 0",
        "3 -5 20 2 41152263374485596708 22 0",
        "3 -5 20 3 41152263374485596707 22 0",
        "3 -5 20 4 41152263374485596708 22 0",
        "3 -5 20 5 41152263374485596708 22 0",
        "3 -5 20 6 41152263374485596708 22 0",
        "1.5 17 5 0 98526 2 0",
        "1.5 17 5 1 98527 2 0",
        "1.5 17 5 2 98527 2 0",
        "1.5 17 5 3 98526 2 0",
        "1.5 17 5 4 98526 2 0",
        "1.5 17 5 5 98526 2 0",
        "1.5 17 5 6 98526 2 0",
        "-3 31 15 0 617673396283947 0 1",
        "-3 31 15 1 617673396283947 0 1",
        "-3 31 15 2 617673396283947 0 1",
        "-3 31 15 3 617673396283947 0 1",
        "-3 31 15 4 617673396283947 0 1",
        "-3 31 15 5 617673396283947 0 1",
        "-3 31 15 6 617673396283947 0 1",
        "-1.5 7 3 0 170 1 1",
        "-1.5 7 3 1 171 1 1",
        "-1.5 7 3 2 170 1 1",
        "-1.5 7 3 3 171 1 1",
        "-1.5 7 3 4 171 1 1",
        "-1.5 7 3 5 171 1 1",
        "-1.5 7 3 6 171 1 1",
        "0.5 -10 5 0 10240 1 0",
        "0.5 -10 5 1 10240 1 0",
        "0.5 -10 5 2 10240 1 0",
        "0.5 -10 5 3 10240 1 0",
        "0.5 -10 5 4 10240 1 0",
        "0.5 -10 5 5 10240 1 0",
        "0.5 -10 5 6 10240 1 0",
        "123.456 5 10 0 2867880216 -1 0",
        "123.456 5 10 1 2867880217 -1 0",
        "123.456 5 10 2 2867880217 -1 0",
        "123.456 5 10 3 2867880216 -1 0",
        "123.456 5 10 4 2867880217 -1 0",
        "123.456 5 10 5 2867880217 -1 0",
        "123.456 5 10 6 2867880217 -1 0",
        "9.99 11 8 0 98905483 -3 0",
        "9.99 11 8 1 98905484 -3 0",
        "9.99 11 8 2 98905484 -3 0",
        "9.99 11 8 3 98905483 -3 0",
        "9.99 11 8 4 98905484 -3 0",
        "9.99 11 8 5 98905484 -3 0",
        "9.99 11 8 6 98905484 -3 0",
        "10 2 20 0 10000000000000000000 17 0",
        "10 2 20 1 10000000000000000000 17 0",
        "10 2 20 2 10000000000000000000 17 0",
        "10 2 20 3 10000000000000000000 17 0",
        "10 2 20 4 10000000000000000000 17 0",
        "10 2 20 5 10000000000000000000 17 0",
        "10 2 20 6 10000000000000000000 17 0",
        "0.0625 -3 6 0 409600 2 0",
        "0.0625 -3 6 1 409600 2 0",
        "0.0625 -3 6 2 409600 2 0",
        "0.0625 -3 6 3 409600 2 0",
        "0.0625 -3 6 4 409600 2 0",
        "0.0625 -3 6 5 409600 2 0",
        "0.0625 -3 6 6 409600 2 0",
        "2.5 13 12 0 149011611938 6 0",
        "2.5 13 12 1 149011611939 6 0",
        "2.5 13 12 2 149011611939 6 0",
        "2.5 13 12 3 149011611938 6 0",
        "2.5 13 12 4 149011611938 6 0",
        "2.5 13 12 5 149011611938 6 0",
        "2.5 13 12 6 149011611938 6 0",
        "-0.25 5 4 0 9765 7 1",
        "-0.25 5 4 1 9766 7 1",
        "-0.25 5 4 2 9765 7 1",
        "-0.25 5 4 3 9766 7 1",
        "-0.25 5 4 4 9766 7 1",
        "-0.25 5 4 5 9766 7 1",
        "-0.25 5 4 6 9766 7 1",
        "1.25 8 3 0 596 2 0",
        "1.25 8 3 1 597 2 0",
        "1.25 8 3 2 597 2 0",
        "1.25 8 3 3 596 2 0",
        "1.25 8 3 4 596 2 0",
        "1.25 8 3 5 596 2 0",
        "1.25 8 3 6 596 2 0",
        "0.8 -9 7 0 7450580 6 0",
        "0.8 -9 7 1 7450581 6 0",
        "0.8 -9 7 2 7450581 6 0",
        "0.8 -9 7 3 7450580 6 0",
        "0.8 -9 7 4 7450581 6 0",
        "0.8 -9 7 5 7450581 6 0",
        "0.8 -9 7 6 7450581 6 0",
        "7 -3 2 0 29 4 0",
        "7 -3 2 1 30 4 0",
        "7 -3 2 2 30 4 0",
        "7 -3 2 3 29 4 0",
        "7 -3 2 4 29 4 0",
        "7 -3 2 5 29 4 0",
        "7 -3 2 6 29 4 0",
        "1.0001 200 28 0 1020200319893934137968089116 27 0",
        "1.0001 200 28 1 1020200319893934137968089117 27 0",
        "1.0001 200 28 2 1020200319893934137968089117 27 0",
        "1.0001 200 28 3 1020200319893934137968089116 27 0",
        "1.0001 200 28 4 1020200319893934137968089116 27 0",
        "1.0001 200 28 5 1020200319893934137968089116 27 0",
        "1.0001 200 28 6 1020200319893934137968089116 27 0",
    ]
    for row in cases:
        var field = row.split(" ")
        var got = bigdecimal_exponential.power_rounded(
            BigDecimal(String(field[0])),
            BigDecimal(String(field[1])),
            Int(String(field[2])),
            modes[Int(String(field[3]))],
        )
        assert_equal(
            _same_value(
                got,
                BigUInt(String(field[4])),
                Int(String(field[5])),
                field[6] == "1",
            ),
            True,
            String("case ") + row + String(", got ") + String(got),
        )


def test_an_exact_power_keeps_the_shape_it_had() raises:
    """An exact answer arrives with the scale the multiplication gives it.

    A scale is part of what a `BigDecimal` is, so `10 ** 2` is `100` and not
    `1E+2`, and an exact power has to be built from the coefficient as it
    came rather than from a normalized one.
    """
    var modes = _modes()
    for index in range(7):
        assert_equal(
            String(
                bigdecimal_exponential.power_rounded(
                    BigDecimal("10"), BigDecimal("2"), 20, modes[index]
                )
            ),
            "100",
            "10 ** 2 is one hundred, with the scale it was built with",
        )
        assert_equal(
            String(
                bigdecimal_exponential.power_rounded(
                    BigDecimal("2"), BigDecimal("10"), 20, modes[index]
                )
            ),
            "1024",
            "2 ** 10 is exact in every mode",
        )


def test_a_power_of_ten_is_answered_however_large() raises:
    """`10 ** 400` is one digit and a scale, so no length declines it.

    The exact value is representable, which is the one thing the deciding
    loop cannot settle on, so it has to be formed rather than decided -- and
    the count that decides whether to form it has to ignore the zeros in the
    coefficient, or a power of ten looks as long as its exponent.
    """
    var modes = _modes()
    for index in range(7):
        var got = bigdecimal_exponential.power_rounded(
            BigDecimal("10"), BigDecimal("400"), 20, modes[index]
        )
        assert_equal(
            _same_value(got, BigUInt("1"), -400, False),
            True,
            String("10 ** 400 in mode ") + String(index),
        )


def test_a_tie_is_broken_by_the_mode() raises:
    """`5 ** 3` is `125`, the midpoint of `120` and `130` at two digits.

    A midpoint is the other value the deciding loop cannot settle on, and it
    is where the half modes part company: to even gives `120`, up gives
    `130`, down gives `120`.
    """
    assert_equal(
        _same_value(
            bigdecimal_exponential.power_rounded(
                BigDecimal("5"),
                BigDecimal("3"),
                2,
                RoundingMode.ROUND_HALF_EVEN,
            ),
            BigUInt("12"),
            -1,
            False,
        ),
        True,
        "half to even takes 125 down to 120",
    )
    assert_equal(
        _same_value(
            bigdecimal_exponential.power_rounded(
                BigDecimal("5"), BigDecimal("3"), 2, RoundingMode.ROUND_HALF_UP
            ),
            BigUInt("13"),
            -1,
            False,
        ),
        True,
        "half up takes 125 to 130",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
