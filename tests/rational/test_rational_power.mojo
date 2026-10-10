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
Tests the integer powers of a `Rational`, the in-place operators, and the
closest approximation under a limit on the denominator.

The powers and the approximations are CPython's own `fractions.Fraction` on
the same values. The approximation is the one worth a table: it walks the
continued fraction, and where two candidates are equally close the answer is
whichever `Fraction` returns, which is not the one with the smaller
denominator -- `limit_denominator(1)` of `3/2` is 1 while of `-3/2` it is -2.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigint.bigint import BigInt
from decimo.rational.rational import Rational
from decimo.traits import Numeric


def _parse(text: String) raises -> Rational:
    """Builds a rational from `numerator/denominator`.

    Args:
        text: The two parts, separated by a solidus.

    Returns:
        The value.

    Raises:
        Error: Propagated from the construction.
    """
    var parts = text.split("/")
    return Rational(BigInt(String(parts[0])), BigInt(String(parts[1])))


def test_an_integer_power_is_exact() raises:
    """Eight exponents at sixteen values, against CPython.

    A negative exponent inverts the fraction, so the sign has to move to the
    numerator to keep the denominator positive, and zero is the one value
    with no negative power at all.
    """
    var cases = [
        "3/2@0",
        "3/2@1",
        "3/2@2",
        "3/2@3",
        "3/2@-1",
        "3/2@-2",
        "3/2@7",
        "3/2@-7",
        "-3/2@0",
        "-3/2@1",
        "-3/2@2",
        "-3/2@3",
        "-3/2@-1",
        "-3/2@-2",
        "-3/2@7",
        "-3/2@-7",
        "1/2@0",
        "1/2@1",
        "1/2@2",
        "1/2@3",
        "1/2@-1",
        "1/2@-2",
        "1/2@7",
        "1/2@-7",
        "-1/2@0",
        "-1/2@1",
        "-1/2@2",
        "-1/2@3",
        "-1/2@-1",
        "-1/2@-2",
        "-1/2@7",
        "-1/2@-7",
        "5/2@0",
        "5/2@1",
        "5/2@2",
        "5/2@3",
        "5/2@-1",
        "5/2@-2",
        "5/2@7",
        "5/2@-7",
        "-5/2@0",
        "-5/2@1",
        "-5/2@2",
        "-5/2@3",
        "-5/2@-1",
        "-5/2@-2",
        "-5/2@7",
        "-5/2@-7",
        "0/1@0",
        "0/1@1",
        "0/1@2",
        "0/1@3",
        "0/1@-1",
        "0/1@-2",
        "0/1@7",
        "0/1@-7",
        "7/1@0",
        "7/1@1",
        "7/1@2",
        "7/1@3",
        "7/1@-1",
        "7/1@-2",
        "7/1@7",
        "7/1@-7",
        "-7/1@0",
        "-7/1@1",
        "-7/1@2",
        "-7/1@3",
        "-7/1@-1",
        "-7/1@-2",
        "-7/1@7",
        "-7/1@-7",
        "1234/5678@0",
        "1234/5678@1",
        "1234/5678@2",
        "1234/5678@3",
        "1234/5678@-1",
        "1234/5678@-2",
        "1234/5678@7",
        "1234/5678@-7",
        "-1234/5678@0",
        "-1234/5678@1",
        "-1234/5678@2",
        "-1234/5678@3",
        "-1234/5678@-1",
        "-1234/5678@-2",
        "-1234/5678@7",
        "-1234/5678@-7",
        "22/7@0",
        "22/7@1",
        "22/7@2",
        "22/7@3",
        "22/7@-1",
        "22/7@-2",
        "22/7@7",
        "22/7@-7",
        "355/113@0",
        "355/113@1",
        "355/113@2",
        "355/113@3",
        "355/113@-1",
        "355/113@-2",
        "355/113@7",
        "355/113@-7",
        "2/3@0",
        "2/3@1",
        "2/3@2",
        "2/3@3",
        "2/3@-1",
        "2/3@-2",
        "2/3@7",
        "2/3@-7",
        "-2/3@0",
        "-2/3@1",
        "-2/3@2",
        "-2/3@3",
        "-2/3@-1",
        "-2/3@-2",
        "-2/3@7",
        "-2/3@-7",
        "100000000000000000001/205891132094649@0",
        "100000000000000000001/205891132094649@1",
        "100000000000000000001/205891132094649@2",
        "100000000000000000001/205891132094649@3",
        "100000000000000000001/205891132094649@-1",
        "100000000000000000001/205891132094649@-2",
        "100000000000000000001/205891132094649@7",
        "100000000000000000001/205891132094649@-7",
    ]
    var expected = [
        "1",
        "3/2",
        "9/4",
        "27/8",
        "2/3",
        "4/9",
        "2187/128",
        "128/2187",
        "1",
        "-3/2",
        "9/4",
        "-27/8",
        "-2/3",
        "4/9",
        "-2187/128",
        "-128/2187",
        "1",
        "1/2",
        "1/4",
        "1/8",
        "2",
        "4",
        "1/128",
        "128",
        "1",
        "-1/2",
        "1/4",
        "-1/8",
        "-2",
        "4",
        "-1/128",
        "-128",
        "1",
        "5/2",
        "25/4",
        "125/8",
        "2/5",
        "4/25",
        "78125/128",
        "128/78125",
        "1",
        "-5/2",
        "25/4",
        "-125/8",
        "-2/5",
        "4/25",
        "-78125/128",
        "-128/78125",
        "1",
        "0",
        "0",
        "0",
        "raises",
        "raises",
        "0",
        "raises",
        "1",
        "7",
        "49",
        "343",
        "1/7",
        "1/49",
        "823543",
        "1/823543",
        "1",
        "-7",
        "49",
        "-343",
        "-1/7",
        "1/49",
        "-823543",
        "-1/823543",
        "1",
        "617/2839",
        "380689/8059921",
        "234885113/22882115719",
        "2839/617",
        "8059921/380689",
        "34040517062667048473/1486475472948909852082279",
        "1486475472948909852082279/34040517062667048473",
        "1",
        "-617/2839",
        "380689/8059921",
        "-234885113/22882115719",
        "-2839/617",
        "8059921/380689",
        "-34040517062667048473/1486475472948909852082279",
        "-1486475472948909852082279/34040517062667048473",
        "1",
        "22/7",
        "484/49",
        "10648/343",
        "7/22",
        "49/484",
        "2494357888/823543",
        "823543/2494357888",
        "1",
        "355/113",
        "126025/12769",
        "44738875/1442897",
        "113/355",
        "12769/126025",
        "710556262374296875/235260548044817",
        "235260548044817/710556262374296875",
        "1",
        "2/3",
        "4/9",
        "8/27",
        "3/2",
        "9/4",
        "128/2187",
        "2187/128",
        "1",
        "-2/3",
        "4/9",
        "-8/27",
        "-3/2",
        "9/4",
        "-128/2187",
        "-2187/128",
        "1",
        "100000000000000000001/205891132094649",
        "10000000000000000000200000000000000000001/42391158275216203514294433201",
        "1000000000000000000030000000000000000000300000000000000000001/8727963568087712425891397479476727340041449",
        "205891132094649/100000000000000000001",
        "42391158275216203514294433201/10000000000000000000200000000000000000001",
        "100000000000000000007000000000000000000210000000000000000003500000000000000000035000000000000000000210000000000000000000700000000000000000001/15684240429131529254685698284890751184639406145730291592802676915731672495230992603635422093849215049",
        "15684240429131529254685698284890751184639406145730291592802676915731672495230992603635422093849215049/100000000000000000007000000000000000000210000000000000000003500000000000000000035000000000000000000210000000000000000000700000000000000000001",
    ]
    for index in range(len(cases)):
        var parts = cases[index].split("@")
        var x = _parse(String(parts[0]))
        var exponent = Int(String(parts[1]))
        var answer = String("raises")
        try:
            answer = String(x**exponent)
        except:
            answer = String("raises")
        assert_equal(
            answer,
            expected[index],
            String(parts[0]) + " to the power " + String(exponent),
        )


def test_a_power_takes_a_big_exponent_where_one_exists() raises:
    """Nought, one and minus one have a power for any exponent at all.

    Anything else raised to an exponent that wide has more digits than there
    is memory, and is refused rather than attempted.
    """
    var huge = BigInt("1000000000000000000000000000")
    assert_equal(
        String(Rational(BigInt(1), BigInt(1)) ** huge),
        "1",
        "one to a huge power",
    )
    assert_equal(
        String(Rational(BigInt(-1), BigInt(1)) ** huge),
        "1",
        "minus one to an even huge power",
    )
    assert_equal(
        String(Rational(BigInt(-1), BigInt(1)) ** (huge + BigInt(1))),
        "-1",
        "minus one to an odd huge power",
    )
    assert_equal(
        String(Rational(BigInt(0), BigInt(1)) ** huge),
        "0",
        "nought to a huge power",
    )
    var refused = False
    try:
        _ = Rational(BigInt(3), BigInt(2)) ** huge
    except:
        refused = True
    assert_true(refused, "a power that cannot be held was attempted")


def test_the_in_place_operators() raises:
    """Each one leaves what the operator would have returned."""
    var x = Rational(BigInt(1), BigInt(2))
    x += Rational(BigInt(1), BigInt(3))
    assert_equal(String(x), "5/6", "a half plus a third, in place")
    x -= Rational(BigInt(1), BigInt(3))
    assert_equal(String(x), "1/2", "and back again")
    x *= Rational(BigInt(3), BigInt(1))
    assert_equal(String(x), "3/2", "times three, in place")
    x /= Rational(BigInt(3), BigInt(1))
    assert_equal(String(x), "1/2", "and divided back")
    x **= 3
    assert_equal(String(x), "1/8", "cubed in place")


def _sum[T: Numeric](values: List[T]) raises -> T:
    """Adds a list of anything the `Numeric` trait covers.

    Parameters:
        T: The type being added.

    Args:
        values: What to add.

    Returns:
        The sum, from `T.zero()`.

    Raises:
        Error: Propagated from the addition.
    """
    var total = T.zero()
    for value in values:
        total = total + value
    return total^


def test_a_rational_is_numeric() raises:
    """Generic code written against the trait takes this type.

    The conformance is what the test is for: the type had every operation
    the trait asks for and did not claim it, so a routine bounded by
    `Numeric` would not take a rational.
    """
    assert_equal(
        String(
            _sum(
                [
                    Rational(BigInt(1), BigInt(2)),
                    Rational(BigInt(1), BigInt(3)),
                    Rational(BigInt(1), BigInt(6)),
                ]
            )
        ),
        "1",
        "a half, a third and a sixth",
    )


def test_the_closest_value_under_a_limit() raises:
    """Seven limits at sixteen values, against CPython.

    A value whose denominator is already within the limit comes back
    unchanged, which is the case a walk of the continued fraction would
    otherwise answer with its own last convergent.
    """
    var cases = [
        "3/2@1",
        "3/2@2",
        "3/2@3",
        "3/2@10",
        "3/2@100",
        "3/2@1000",
        "3/2@999999999999",
        "-3/2@1",
        "-3/2@2",
        "-3/2@3",
        "-3/2@10",
        "-3/2@100",
        "-3/2@1000",
        "-3/2@999999999999",
        "1/2@1",
        "1/2@2",
        "1/2@3",
        "1/2@10",
        "1/2@100",
        "1/2@1000",
        "1/2@999999999999",
        "-1/2@1",
        "-1/2@2",
        "-1/2@3",
        "-1/2@10",
        "-1/2@100",
        "-1/2@1000",
        "-1/2@999999999999",
        "5/2@1",
        "5/2@2",
        "5/2@3",
        "5/2@10",
        "5/2@100",
        "5/2@1000",
        "5/2@999999999999",
        "-5/2@1",
        "-5/2@2",
        "-5/2@3",
        "-5/2@10",
        "-5/2@100",
        "-5/2@1000",
        "-5/2@999999999999",
        "0/1@1",
        "0/1@2",
        "0/1@3",
        "0/1@10",
        "0/1@100",
        "0/1@1000",
        "0/1@999999999999",
        "7/1@1",
        "7/1@2",
        "7/1@3",
        "7/1@10",
        "7/1@100",
        "7/1@1000",
        "7/1@999999999999",
        "-7/1@1",
        "-7/1@2",
        "-7/1@3",
        "-7/1@10",
        "-7/1@100",
        "-7/1@1000",
        "-7/1@999999999999",
        "1234/5678@1",
        "1234/5678@2",
        "1234/5678@3",
        "1234/5678@10",
        "1234/5678@100",
        "1234/5678@1000",
        "1234/5678@999999999999",
        "-1234/5678@1",
        "-1234/5678@2",
        "-1234/5678@3",
        "-1234/5678@10",
        "-1234/5678@100",
        "-1234/5678@1000",
        "-1234/5678@999999999999",
        "22/7@1",
        "22/7@2",
        "22/7@3",
        "22/7@10",
        "22/7@100",
        "22/7@1000",
        "22/7@999999999999",
        "355/113@1",
        "355/113@2",
        "355/113@3",
        "355/113@10",
        "355/113@100",
        "355/113@1000",
        "355/113@999999999999",
        "2/3@1",
        "2/3@2",
        "2/3@3",
        "2/3@10",
        "2/3@100",
        "2/3@1000",
        "2/3@999999999999",
        "-2/3@1",
        "-2/3@2",
        "-2/3@3",
        "-2/3@10",
        "-2/3@100",
        "-2/3@1000",
        "-2/3@999999999999",
        "100000000000000000001/205891132094649@1",
        "100000000000000000001/205891132094649@2",
        "100000000000000000001/205891132094649@3",
        "100000000000000000001/205891132094649@10",
        "100000000000000000001/205891132094649@100",
        "100000000000000000001/205891132094649@1000",
        "100000000000000000001/205891132094649@999999999999",
    ]
    var expected = [
        "1",
        "3/2",
        "3/2",
        "3/2",
        "3/2",
        "3/2",
        "3/2",
        "-2",
        "-3/2",
        "-3/2",
        "-3/2",
        "-3/2",
        "-3/2",
        "-3/2",
        "0",
        "1/2",
        "1/2",
        "1/2",
        "1/2",
        "1/2",
        "1/2",
        "-1",
        "-1/2",
        "-1/2",
        "-1/2",
        "-1/2",
        "-1/2",
        "-1/2",
        "2",
        "5/2",
        "5/2",
        "5/2",
        "5/2",
        "5/2",
        "5/2",
        "-3",
        "-5/2",
        "-5/2",
        "-5/2",
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
        "7",
        "7",
        "7",
        "7",
        "7",
        "7",
        "7",
        "-7",
        "-7",
        "-7",
        "-7",
        "-7",
        "-7",
        "-7",
        "0",
        "0",
        "1/3",
        "2/9",
        "5/23",
        "153/704",
        "617/2839",
        "0",
        "0",
        "-1/3",
        "-2/9",
        "-5/23",
        "-153/704",
        "-617/2839",
        "3",
        "3",
        "3",
        "22/7",
        "22/7",
        "22/7",
        "22/7",
        "3",
        "3",
        "3",
        "22/7",
        "311/99",
        "355/113",
        "355/113",
        "1",
        "1/2",
        "2/3",
        "2/3",
        "2/3",
        "2/3",
        "2/3",
        "-1",
        "-1/2",
        "-2/3",
        "-2/3",
        "-2/3",
        "-2/3",
        "-2/3",
        "485694",
        "971387/2",
        "971387/2",
        "3399855/7",
        "19427743/40",
        "314243743/647",
        "199598799733677569/410956228419",
    ]
    for index in range(len(cases)):
        var parts = cases[index].split("@")
        var x = _parse(String(parts[0]))
        var limit = BigInt(String(parts[1]))
        assert_equal(
            String(x.limit_denominator(limit)),
            expected[index],
            String(parts[0]) + " under a denominator of " + String(parts[1]),
        )


def test_a_limit_below_one_is_refused() raises:
    """There is no fraction with a denominator of nought."""
    for limit in [BigInt(0), BigInt(-1), BigInt(-1000)]:
        var refused = False
        try:
            _ = Rational(BigInt(22), BigInt(7)).limit_denominator(limit)
        except:
            refused = True
        assert_true(
            refused,
            String("a limit of ") + String(limit) + " was accepted",
        )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
