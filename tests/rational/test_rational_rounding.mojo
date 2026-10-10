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
Tests the four roundings of a `Rational` to a whole value, and the rounding
to a count of decimal places.

Every expectation is CPython's own `fractions.Fraction` on the same value:
`math.floor`, `math.ceil`, `math.trunc`, `round` and `round(x, n)`. The point
of the table is the cases where the five disagree -- a negative value, a half,
a half above an even quotient -- since any one of them alone would pass a
rounding that went the wrong way at the halves.
"""

from std import testing
from std.math import ceil, floor, trunc
from std.testing import assert_equal

from decimo.bigint.bigint import BigInt
from decimo.rational.rational import Rational


def _parse(text: String) raises -> Rational:
    """Builds a rational from `numerator/denominator`.

    Args:
        text: The two parts, separated by a solidus.

    Returns:
        The value, which is not reduced on the way in -- the constructor
        does that, and the table is written in lowest terms anyway.

    Raises:
        Error: Propagated from the construction.
    """
    var parts = text.split("/")
    return Rational(BigInt(String(parts[0])), BigInt(String(parts[1])))


def _values() -> List[String]:
    """The values every rounding is checked at.

    Returns:
        The list, as `numerator/denominator`.
    """
    return [
        "3/2",
        "-3/2",
        "1/2",
        "-1/2",
        "5/2",
        "-5/2",
        "0/1",
        "7/1",
        "-7/1",
        "1234/5678",
        "-1234/5678",
        "22/7",
        "355/113",
        "2/3",
        "-2/3",
        "100000000000000000001/205891132094649",
    ]


def test_the_four_roundings_to_a_whole_value() raises:
    """Floor, ceiling, truncation and the nearest, against CPython.

    The four differ below zero and at the halves: `-3/2` floors to -2,
    ceilings to -1, truncates to -1 and rounds to -2, and `5/2` rounds to 2
    rather than 3 because a half goes to the even side.
    """
    var values = _values()
    var expected_floor = [
        "1",
        "-2",
        "0",
        "-1",
        "2",
        "-3",
        "0",
        "7",
        "-7",
        "0",
        "-1",
        "3",
        "3",
        "0",
        "-1",
        "485693",
    ]
    var expected_ceil = [
        "2",
        "-1",
        "1",
        "0",
        "3",
        "-2",
        "0",
        "7",
        "-7",
        "1",
        "0",
        "4",
        "4",
        "1",
        "0",
        "485694",
    ]
    var expected_trunc = [
        "1",
        "-1",
        "0",
        "0",
        "2",
        "-2",
        "0",
        "7",
        "-7",
        "0",
        "0",
        "3",
        "3",
        "0",
        "0",
        "485693",
    ]
    var expected_round = [
        "2",
        "-2",
        "0",
        "0",
        "2",
        "-2",
        "0",
        "7",
        "-7",
        "0",
        "0",
        "3",
        "3",
        "1",
        "-1",
        "485694",
    ]
    for index in range(len(values)):
        var x = _parse(values[index])
        assert_equal(
            String(floor(x)),
            expected_floor[index],
            String("the floor of ") + values[index],
        )
        assert_equal(
            String(ceil(x)),
            expected_ceil[index],
            String("the ceiling of ") + values[index],
        )
        assert_equal(
            String(trunc(x)),
            expected_trunc[index],
            String("the truncation of ") + values[index],
        )
        assert_equal(
            String(round(x)),
            expected_round[index],
            String("the nearest whole value to ") + values[index],
        )


def test_rounding_to_decimal_places() raises:
    """`round(x, n)` for seven counts, above and below the point.

    A negative count rounds above the decimal point, which is where a
    reading of the sign as "shift the other way" goes wrong, and the halves
    are in the table for the same reason as above.
    """
    var cases = [
        "3/2@-3",
        "3/2@-2",
        "3/2@-1",
        "3/2@0",
        "3/2@1",
        "3/2@2",
        "3/2@3",
        "-3/2@-3",
        "-3/2@-2",
        "-3/2@-1",
        "-3/2@0",
        "-3/2@1",
        "-3/2@2",
        "-3/2@3",
        "1/2@-3",
        "1/2@-2",
        "1/2@-1",
        "1/2@0",
        "1/2@1",
        "1/2@2",
        "1/2@3",
        "-1/2@-3",
        "-1/2@-2",
        "-1/2@-1",
        "-1/2@0",
        "-1/2@1",
        "-1/2@2",
        "-1/2@3",
        "5/2@-3",
        "5/2@-2",
        "5/2@-1",
        "5/2@0",
        "5/2@1",
        "5/2@2",
        "5/2@3",
        "-5/2@-3",
        "-5/2@-2",
        "-5/2@-1",
        "-5/2@0",
        "-5/2@1",
        "-5/2@2",
        "-5/2@3",
        "0/1@-3",
        "0/1@-2",
        "0/1@-1",
        "0/1@0",
        "0/1@1",
        "0/1@2",
        "0/1@3",
        "7/1@-3",
        "7/1@-2",
        "7/1@-1",
        "7/1@0",
        "7/1@1",
        "7/1@2",
        "7/1@3",
        "-7/1@-3",
        "-7/1@-2",
        "-7/1@-1",
        "-7/1@0",
        "-7/1@1",
        "-7/1@2",
        "-7/1@3",
        "1234/5678@-3",
        "1234/5678@-2",
        "1234/5678@-1",
        "1234/5678@0",
        "1234/5678@1",
        "1234/5678@2",
        "1234/5678@3",
        "-1234/5678@-3",
        "-1234/5678@-2",
        "-1234/5678@-1",
        "-1234/5678@0",
        "-1234/5678@1",
        "-1234/5678@2",
        "-1234/5678@3",
        "22/7@-3",
        "22/7@-2",
        "22/7@-1",
        "22/7@0",
        "22/7@1",
        "22/7@2",
        "22/7@3",
        "355/113@-3",
        "355/113@-2",
        "355/113@-1",
        "355/113@0",
        "355/113@1",
        "355/113@2",
        "355/113@3",
        "2/3@-3",
        "2/3@-2",
        "2/3@-1",
        "2/3@0",
        "2/3@1",
        "2/3@2",
        "2/3@3",
        "-2/3@-3",
        "-2/3@-2",
        "-2/3@-1",
        "-2/3@0",
        "-2/3@1",
        "-2/3@2",
        "-2/3@3",
        "100000000000000000001/205891132094649@-3",
        "100000000000000000001/205891132094649@-2",
        "100000000000000000001/205891132094649@-1",
        "100000000000000000001/205891132094649@0",
        "100000000000000000001/205891132094649@1",
        "100000000000000000001/205891132094649@2",
        "100000000000000000001/205891132094649@3",
    ]
    var expected = [
        "0",
        "0",
        "0",
        "2",
        "3/2",
        "3/2",
        "3/2",
        "0",
        "0",
        "0",
        "-2",
        "-3/2",
        "-3/2",
        "-3/2",
        "0",
        "0",
        "0",
        "0",
        "1/2",
        "1/2",
        "1/2",
        "0",
        "0",
        "0",
        "0",
        "-1/2",
        "-1/2",
        "-1/2",
        "0",
        "0",
        "0",
        "2",
        "5/2",
        "5/2",
        "5/2",
        "0",
        "0",
        "0",
        "-2",
        "-5/2",
        "-5/2",
        "-5/2",
        "0",
        "0",
        "0",
        "0",
        "0",
        "0",
        "0",
        "0",
        "0",
        "10",
        "7",
        "7",
        "7",
        "7",
        "0",
        "0",
        "-10",
        "-7",
        "-7",
        "-7",
        "-7",
        "0",
        "0",
        "0",
        "0",
        "1/5",
        "11/50",
        "217/1000",
        "0",
        "0",
        "0",
        "0",
        "-1/5",
        "-11/50",
        "-217/1000",
        "0",
        "0",
        "0",
        "3",
        "31/10",
        "157/50",
        "3143/1000",
        "0",
        "0",
        "0",
        "3",
        "31/10",
        "157/50",
        "1571/500",
        "0",
        "0",
        "0",
        "1",
        "7/10",
        "67/100",
        "667/1000",
        "0",
        "0",
        "0",
        "-1",
        "-7/10",
        "-67/100",
        "-667/1000",
        "486000",
        "485700",
        "485690",
        "485694",
        "2428468/5",
        "48569357/100",
        "19427743/40",
    ]
    for index in range(len(cases)):
        var parts = cases[index].split("@")
        var x = _parse(String(parts[0]))
        var places = Int(String(parts[1]))
        assert_equal(
            String(round(x, places)),
            expected[index],
            String("rounding ")
            + String(parts[0])
            + " to "
            + String(places)
            + " decimal places",
        )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
