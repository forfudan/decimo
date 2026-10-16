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

"""Tests the logarithm to an arbitrary base.

`log(x, base)` had no tests of its own. `log10()` and `ln()` are covered
several files over, and this one is built from two of the latter, which is
exactly why it needs checking separately: a function assembled from tested
parts can still assemble them wrongly, and the division it ends with belongs
to no other test.

The references come from CPython's `decimal` as `ln(x) / ln(base)` carried
thirty digits past what is asked for. That is libmpdec's logarithm, which
shares no code with decimo's.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.arithmetics import multiply, subtract
from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigdecimal.exponential import ln, log, log10


def assert_within(expected: BDec, got: BDec, room: BDec, msg: String) raises:
    """Fails unless the two agree to within `room`."""
    var residual = abs(subtract(expected, got))
    assert_true(
        residual <= room,
        msg
        + ": expected "
        + String(expected)
        + ", got "
        + String(got)
        + ", allowed "
        + String(room),
    )


def test_the_ordinary_bases_against_cpython() raises:
    """Twenty-eight digits, the default precision, from libmpdec at 58."""
    assert_equal(
        String(log(BDec("2"), BDec("3"), 28)),
        "0.6309297535714574370995271143",
        "log(2) to base 3",
    )
    assert_equal(
        String(log(BDec("10"), BDec("2"), 28)),
        "3.321928094887362347870319429",
        "log(10) to base 2",
    )
    assert_equal(
        String(log(BDec("0.5"), BDec("7"), 28)),
        "-0.3562071871080221765141770780",
        "log(0.5) to base 7",
    )
    assert_equal(
        String(log(BDec("1E50"), BDec("3"), 28)),
        "104.7951637144692302148283761",
        "log(1E50) to base 3",
    )


def test_a_deep_answer_against_cpython() raises:
    """Four hundred digits, which is where the binary kernel does the work.

    Below forty digits the logarithm is still the decimal series, so a test
    at the default precision says nothing about the route this function
    actually takes for a long request.
    """
    assert_within(
        BDec(
            "0.6309297535714574370995271143427608542995856401318804278706549438386852013809148050611726885494517455613540159383137151949234491469364754136861963933499500359666405847433116774522156125961998518686727928543408495310812088419376092901841859593822187030820289857925687909013131327577187824897548976143800469936236615357701515795825822031192160852692486078488559422009541636442439470940922153959672995129"
        ),
        log(BDec("2"), BDec("3"), 400),
        BDec("1E-399"),
        "log(2) to base 3 at 400 digits",
    )


def test_the_exact_points() raises:
    """The two answers that are whole numbers, at several precisions."""
    for precision in [10, 28, 50, 400]:
        assert_equal(
            String(log(BDec("1"), BDec("7"), precision)),
            "0",
            "log(1) to any base is zero",
        )
        assert_equal(
            String(log(BDec("7"), BDec("7"), precision)),
            "1",
            "log(b) to base b is one",
        )


def test_base_ten_agrees_with_the_common_logarithm() raises:
    """`log(x, 10)` takes a shortcut, which has to land where `log10()` does."""
    for text in [String("2"), String("0.5"), String("1E50"), String("7.25")]:
        for precision in [28, 200]:
            assert_equal(
                String(log(BDec(text), BDec("10"), precision)),
                String(log10(BDec(text), precision)),
                "log(" + text + ") to base ten",
            )


def test_the_definition_holds() raises:
    """`log(x, b) * ln(b) = ln(x)`, which no table of the three can confirm.

    The identity ties the division at the end of `log()` to the two
    logarithms that feed it, and it is checked where those logarithms are
    the binary kernel rather than the series.
    """
    for precision in [50, 300]:
        for text in [String("2"), String("0.5"), String("123456.789")]:
            for base in [String("3"), String("7.5")]:
                var left = multiply(
                    log(BDec(text), BDec(base), precision + 10),
                    ln(BDec(base), precision + 10),
                )
                var right = ln(BDec(text), precision + 10)
                # The product loses what the two factors carry, so the room
                # allowed is a unit of the last place of the wider width.
                var room = multiply(abs(right), BDec("1E-" + String(precision)))
                assert_within(
                    right,
                    left,
                    room,
                    "log(" + text + ", " + base + ") times ln(" + base + ")",
                )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
