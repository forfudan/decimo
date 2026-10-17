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
Tests the cotangent, the cosecant and the secant of `BigFloat`.

The reference is the one the sine's tests use, written again for these
three: a Python program computes pi by Chudnovsky's series, reduces the
argument by `pi/2` in `Decimal`, sums the series there, divides, and rounds
the quotient to the bits asked for in exact rationals. Different language,
different pi, different arithmetic, same answer.

The arguments are the sine's, because the edges are the same ones. An
argument at `2^300` needs three hundred bits of pi before the first bit is
right. `243068958312725669170431586 * 2^-87` sits a hair from `pi/2`, where
the cotangent is `3.5e-26` and the secant is `2.8e20`, and both are correct
to the last bit only if the reduction keeps the remainder's own precision.
`2^-200` is where the cotangent and the cosecant are `2^200` exactly and the
secant is one.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigfloat.arithmetics import multiply
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.trigonometric import cos, cot, csc, sec, sin, tan
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


def test_the_values_are_what_the_reference_rounds_to() raises:
    """Seven arguments, three functions, two precisions, seven modes.

    The whole table is 294 rows, and every one of them is a value the
    Python reference rounded, not a value this library produced and was
    then asked to reproduce.
    """
    var modes = _modes()
    # function significand exponent precision destination mode
    # expected_significand expected_exponent expected_negative
    var cases = [
        "0 1 0 1 1 0 1 -1 0",
        "0 1 0 1 1 1 1 0 0",
        "0 1 0 1 1 2 1 0 0",
        "0 1 0 1 1 3 1 -1 0",
        "0 1 0 1 1 4 1 -1 0",
        "0 1 0 1 1 5 1 -1 0",
        "0 1 0 1 1 6 1 -1 0",
        "0 1 0 1 53 0 5783456131718397 -53 0",
        "0 1 0 1 53 1 5783456131718398 -53 0",
        "0 1 0 1 53 2 5783456131718398 -53 0",
        "0 1 0 1 53 3 5783456131718397 -53 0",
        "0 1 0 1 53 4 5783456131718398 -53 0",
        "0 1 0 1 53 5 5783456131718398 -53 0",
        "0 1 0 1 53 6 5783456131718398 -53 0",
        "0 1 -1 1 1 0 1 0 0",
        "0 1 -1 1 1 1 1 1 0",
        "0 1 -1 1 1 2 1 1 0",
        "0 1 -1 1 1 3 1 0 0",
        "0 1 -1 1 1 4 1 1 0",
        "0 1 -1 1 1 5 1 1 0",
        "0 1 -1 1 1 6 1 1 0",
        "0 1 -1 1 53 0 8243783821410466 -52 0",
        "0 1 -1 1 53 1 8243783821410467 -52 0",
        "0 1 -1 1 53 2 8243783821410467 -52 0",
        "0 1 -1 1 53 3 8243783821410466 -52 0",
        "0 1 -1 1 53 4 8243783821410467 -52 0",
        "0 1 -1 1 53 5 8243783821410467 -52 0",
        "0 1 -1 1 53 6 8243783821410467 -52 0",
        "0 1 100 1 1 0 1 -1 1",
        "0 1 100 1 1 1 1 0 1",
        "0 1 100 1 1 2 1 -1 1",
        "0 1 100 1 1 3 1 0 1",
        "0 1 100 1 1 4 1 -1 1",
        "0 1 100 1 1 5 1 -1 1",
        "0 1 100 1 1 6 1 -1 1",
        "0 1 100 1 53 0 5051837258996506 -53 1",
        "0 1 100 1 53 1 5051837258996507 -53 1",
        "0 1 100 1 53 2 5051837258996506 -53 1",
        "0 1 100 1 53 3 5051837258996507 -53 1",
        "0 1 100 1 53 4 5051837258996507 -53 1",
        "0 1 100 1 53 5 5051837258996507 -53 1",
        "0 1 100 1 53 6 5051837258996507 -53 1",
        "0 1 300 1 1 0 1 -3 0",
        "0 1 300 1 1 1 1 -2 0",
        "0 1 300 1 1 2 1 -2 0",
        "0 1 300 1 1 3 1 -3 0",
        "0 1 300 1 1 4 1 -2 0",
        "0 1 300 1 1 5 1 -2 0",
        "0 1 300 1 1 6 1 -2 0",
        "0 1 300 1 53 0 7817031104532210 -55 0",
        "0 1 300 1 53 1 7817031104532211 -55 0",
        "0 1 300 1 53 2 7817031104532211 -55 0",
        "0 1 300 1 53 3 7817031104532210 -55 0",
        "0 1 300 1 53 4 7817031104532211 -55 0",
        "0 1 300 1 53 5 7817031104532211 -55 0",
        "0 1 300 1 53 6 7817031104532211 -55 0",
        "0 12345 487 14 1 0 1 1 0",
        "0 12345 487 14 1 1 1 2 0",
        "0 12345 487 14 1 2 1 2 0",
        "0 12345 487 14 1 3 1 1 0",
        "0 12345 487 14 1 4 1 1 0",
        "0 12345 487 14 1 5 1 1 0",
        "0 12345 487 14 1 6 1 1 0",
        "0 12345 487 14 53 0 4949187132112257 -51 0",
        "0 12345 487 14 53 1 4949187132112258 -51 0",
        "0 12345 487 14 53 2 4949187132112258 -51 0",
        "0 12345 487 14 53 3 4949187132112257 -51 0",
        "0 12345 487 14 53 4 4949187132112257 -51 0",
        "0 12345 487 14 53 5 4949187132112257 -51 0",
        "0 12345 487 14 53 6 4949187132112257 -51 0",
        "0 243068958312725669170431586 -87 88 1 0 1 -88 0",
        "0 243068958312725669170431586 -87 88 1 1 1 -87 0",
        "0 243068958312725669170431586 -87 88 1 2 1 -87 0",
        "0 243068958312725669170431586 -87 88 1 3 1 -88 0",
        "0 243068958312725669170431586 -87 88 1 4 1 -88 0",
        "0 243068958312725669170431586 -87 88 1 5 1 -88 0",
        "0 243068958312725669170431586 -87 88 1 6 1 -88 0",
        "0 243068958312725669170431586 -87 88 53 0 4908338078426400 -140 0",
        "0 243068958312725669170431586 -87 88 53 1 4908338078426401 -140 0",
        "0 243068958312725669170431586 -87 88 53 2 4908338078426401 -140 0",
        "0 243068958312725669170431586 -87 88 53 3 4908338078426400 -140 0",
        "0 243068958312725669170431586 -87 88 53 4 4908338078426400 -140 0",
        "0 243068958312725669170431586 -87 88 53 5 4908338078426400 -140 0",
        "0 243068958312725669170431586 -87 88 53 6 4908338078426400 -140 0",
        "0 1 -200 1 1 0 1 199 0",
        "0 1 -200 1 1 1 1 200 0",
        "0 1 -200 1 1 2 1 200 0",
        "0 1 -200 1 1 3 1 199 0",
        "0 1 -200 1 1 4 1 200 0",
        "0 1 -200 1 1 5 1 200 0",
        "0 1 -200 1 1 6 1 200 0",
        "0 1 -200 1 53 0 9007199254740991 147 0",
        "0 1 -200 1 53 1 4503599627370496 148 0",
        "0 1 -200 1 53 2 4503599627370496 148 0",
        "0 1 -200 1 53 3 9007199254740991 147 0",
        "0 1 -200 1 53 4 4503599627370496 148 0",
        "0 1 -200 1 53 5 4503599627370496 148 0",
        "0 1 -200 1 53 6 4503599627370496 148 0",
        "1 1 0 1 1 0 1 0 0",
        "1 1 0 1 1 1 1 1 0",
        "1 1 0 1 1 2 1 1 0",
        "1 1 0 1 1 3 1 0 0",
        "1 1 0 1 1 4 1 0 0",
        "1 1 0 1 1 5 1 0 0",
        "1 1 0 1 1 6 1 0 0",
        "1 1 0 1 53 0 5352055755551267 -52 0",
        "1 1 0 1 53 1 5352055755551268 -52 0",
        "1 1 0 1 53 2 5352055755551268 -52 0",
        "1 1 0 1 53 3 5352055755551267 -52 0",
        "1 1 0 1 53 4 5352055755551268 -52 0",
        "1 1 0 1 53 5 5352055755551268 -52 0",
        "1 1 0 1 53 6 5352055755551268 -52 0",
        "1 1 -1 1 1 0 1 1 0",
        "1 1 -1 1 1 1 1 2 0",
        "1 1 -1 1 1 2 1 2 0",
        "1 1 -1 1 1 3 1 1 0",
        "1 1 -1 1 1 4 1 1 0",
        "1 1 -1 1 1 5 1 1 0",
        "1 1 -1 1 1 6 1 1 0",
        "1 1 -1 1 53 0 4696870801336796 -51 0",
        "1 1 -1 1 53 1 4696870801336797 -51 0",
        "1 1 -1 1 53 2 4696870801336797 -51 0",
        "1 1 -1 1 53 3 4696870801336796 -51 0",
        "1 1 -1 1 53 4 4696870801336796 -51 0",
        "1 1 -1 1 53 5 4696870801336796 -51 0",
        "1 1 -1 1 53 6 4696870801336796 -51 0",
        "1 1 100 1 1 0 1 0 1",
        "1 1 100 1 1 1 1 1 1",
        "1 1 100 1 1 2 1 0 1",
        "1 1 100 1 1 3 1 1 1",
        "1 1 100 1 1 4 1 0 1",
        "1 1 100 1 1 5 1 0 1",
        "1 1 100 1 1 6 1 0 1",
        "1 1 100 1 53 0 5163591243165749 -52 1",
        "1 1 100 1 53 1 5163591243165750 -52 1",
        "1 1 100 1 53 2 5163591243165749 -52 1",
        "1 1 100 1 53 3 5163591243165750 -52 1",
        "1 1 100 1 53 4 5163591243165749 -52 1",
        "1 1 100 1 53 5 5163591243165749 -52 1",
        "1 1 100 1 53 6 5163591243165749 -52 1",
        "1 1 300 1 1 0 1 0 0",
        "1 1 300 1 1 1 1 1 0",
        "1 1 300 1 1 2 1 1 0",
        "1 1 300 1 1 3 1 0 0",
        "1 1 300 1 1 4 1 0 0",
        "1 1 300 1 1 5 1 0 0",
        "1 1 300 1 1 6 1 0 0",
        "1 1 300 1 53 0 4608382630332012 -52 0",
        "1 1 300 1 53 1 4608382630332013 -52 0",
        "1 1 300 1 53 2 4608382630332013 -52 0",
        "1 1 300 1 53 3 4608382630332012 -52 0",
        "1 1 300 1 53 4 4608382630332012 -52 0",
        "1 1 300 1 53 5 4608382630332012 -52 0",
        "1 1 300 1 53 6 4608382630332012 -52 0",
        "1 12345 487 14 1 0 1 1 1",
        "1 12345 487 14 1 1 1 2 1",
        "1 12345 487 14 1 2 1 1 1",
        "1 12345 487 14 1 3 1 2 1",
        "1 12345 487 14 1 4 1 1 1",
        "1 12345 487 14 1 5 1 1 1",
        "1 12345 487 14 1 6 1 1 1",
        "1 12345 487 14 53 0 5437375807278586 -51 1",
        "1 12345 487 14 53 1 5437375807278587 -51 1",
        "1 12345 487 14 53 2 5437375807278586 -51 1",
        "1 12345 487 14 53 3 5437375807278587 -51 1",
        "1 12345 487 14 53 4 5437375807278587 -51 1",
        "1 12345 487 14 53 5 5437375807278587 -51 1",
        "1 12345 487 14 53 6 5437375807278587 -51 1",
        "1 243068958312725669170431586 -87 88 1 0 1 0 0",
        "1 243068958312725669170431586 -87 88 1 1 1 1 0",
        "1 243068958312725669170431586 -87 88 1 2 1 1 0",
        "1 243068958312725669170431586 -87 88 1 3 1 0 0",
        "1 243068958312725669170431586 -87 88 1 4 1 0 0",
        "1 243068958312725669170431586 -87 88 1 5 1 0 0",
        "1 243068958312725669170431586 -87 88 1 6 1 0 0",
        "1 243068958312725669170431586 -87 88 53 0 4503599627370496 -52 0",
        "1 243068958312725669170431586 -87 88 53 1 4503599627370497 -52 0",
        "1 243068958312725669170431586 -87 88 53 2 4503599627370497 -52 0",
        "1 243068958312725669170431586 -87 88 53 3 4503599627370496 -52 0",
        "1 243068958312725669170431586 -87 88 53 4 4503599627370496 -52 0",
        "1 243068958312725669170431586 -87 88 53 5 4503599627370496 -52 0",
        "1 243068958312725669170431586 -87 88 53 6 4503599627370496 -52 0",
        "1 1 -200 1 1 0 1 200 0",
        "1 1 -200 1 1 1 1 201 0",
        "1 1 -200 1 1 2 1 201 0",
        "1 1 -200 1 1 3 1 200 0",
        "1 1 -200 1 1 4 1 200 0",
        "1 1 -200 1 1 5 1 200 0",
        "1 1 -200 1 1 6 1 200 0",
        "1 1 -200 1 53 0 4503599627370496 148 0",
        "1 1 -200 1 53 1 4503599627370497 148 0",
        "1 1 -200 1 53 2 4503599627370497 148 0",
        "1 1 -200 1 53 3 4503599627370496 148 0",
        "1 1 -200 1 53 4 4503599627370496 148 0",
        "1 1 -200 1 53 5 4503599627370496 148 0",
        "1 1 -200 1 53 6 4503599627370496 148 0",
        "2 1 0 1 1 0 1 0 0",
        "2 1 0 1 1 1 1 1 0",
        "2 1 0 1 1 2 1 1 0",
        "2 1 0 1 1 3 1 0 0",
        "2 1 0 1 1 4 1 1 0",
        "2 1 0 1 1 5 1 1 0",
        "2 1 0 1 1 6 1 1 0",
        "2 1 0 1 53 0 8335332976479273 -52 0",
        "2 1 0 1 53 1 8335332976479274 -52 0",
        "2 1 0 1 53 2 8335332976479274 -52 0",
        "2 1 0 1 53 3 8335332976479273 -52 0",
        "2 1 0 1 53 4 8335332976479274 -52 0",
        "2 1 0 1 53 5 8335332976479274 -52 0",
        "2 1 0 1 53 6 8335332976479274 -52 0",
        "2 1 -1 1 1 0 1 0 0",
        "2 1 -1 1 1 1 1 1 0",
        "2 1 -1 1 1 2 1 1 0",
        "2 1 -1 1 1 3 1 0 0",
        "2 1 -1 1 1 4 1 0 0",
        "2 1 -1 1 1 5 1 0 0",
        "2 1 -1 1 1 6 1 0 0",
        "2 1 -1 1 53 0 5131824426489782 -52 0",
        "2 1 -1 1 53 1 5131824426489783 -52 0",
        "2 1 -1 1 53 2 5131824426489783 -52 0",
        "2 1 -1 1 53 3 5131824426489782 -52 0",
        "2 1 -1 1 53 4 5131824426489782 -52 0",
        "2 1 -1 1 53 5 5131824426489782 -52 0",
        "2 1 -1 1 53 6 5131824426489782 -52 0",
        "2 1 100 1 1 0 1 1 0",
        "2 1 100 1 1 1 1 2 0",
        "2 1 100 1 1 2 1 2 0",
        "2 1 100 1 1 3 1 1 0",
        "2 1 100 1 1 4 1 1 0",
        "2 1 100 1 1 5 1 1 0",
        "2 1 100 1 1 6 1 1 0",
        "2 1 100 1 53 0 4603225798139453 -51 0",
        "2 1 100 1 53 1 4603225798139454 -51 0",
        "2 1 100 1 53 2 4603225798139454 -51 0",
        "2 1 100 1 53 3 4603225798139453 -51 0",
        "2 1 100 1 53 4 4603225798139453 -51 0",
        "2 1 100 1 53 5 4603225798139453 -51 0",
        "2 1 100 1 53 6 4603225798139453 -51 0",
        "2 1 300 1 1 0 1 2 0",
        "2 1 300 1 1 1 1 3 0",
        "2 1 300 1 1 2 1 3 0",
        "2 1 300 1 1 3 1 2 0",
        "2 1 300 1 1 4 1 2 0",
        "2 1 300 1 1 5 1 2 0",
        "2 1 300 1 1 6 1 2 0",
        "2 1 300 1 53 0 5310023721080204 -50 0",
        "2 1 300 1 53 1 5310023721080205 -50 0",
        "2 1 300 1 53 2 5310023721080205 -50 0",
        "2 1 300 1 53 3 5310023721080204 -50 0",
        "2 1 300 1 53 4 5310023721080205 -50 0",
        "2 1 300 1 53 5 5310023721080205 -50 0",
        "2 1 300 1 53 6 5310023721080205 -50 0",
        "2 12345 487 14 1 0 1 0 1",
        "2 12345 487 14 1 1 1 1 1",
        "2 12345 487 14 1 2 1 0 1",
        "2 12345 487 14 1 3 1 1 1",
        "2 12345 487 14 1 4 1 0 1",
        "2 12345 487 14 1 5 1 0 1",
        "2 12345 487 14 1 6 1 0 1",
        "2 12345 487 14 53 0 4947835473960366 -52 1",
        "2 12345 487 14 53 1 4947835473960367 -52 1",
        "2 12345 487 14 53 2 4947835473960366 -52 1",
        "2 12345 487 14 53 3 4947835473960367 -52 1",
        "2 12345 487 14 53 4 4947835473960366 -52 1",
        "2 12345 487 14 53 5 4947835473960366 -52 1",
        "2 12345 487 14 53 6 4947835473960366 -52 1",
        "2 243068958312725669170431586 -87 88 1 0 1 87 0",
        "2 243068958312725669170431586 -87 88 1 1 1 88 0",
        "2 243068958312725669170431586 -87 88 1 2 1 88 0",
        "2 243068958312725669170431586 -87 88 1 3 1 87 0",
        "2 243068958312725669170431586 -87 88 1 4 1 88 0",
        "2 243068958312725669170431586 -87 88 1 5 1 88 0",
        "2 243068958312725669170431586 -87 88 1 6 1 88 0",
        "2 243068958312725669170431586 -87 88 53 0 8264471305592770 35 0",
        "2 243068958312725669170431586 -87 88 53 1 8264471305592771 35 0",
        "2 243068958312725669170431586 -87 88 53 2 8264471305592771 35 0",
        "2 243068958312725669170431586 -87 88 53 3 8264471305592770 35 0",
        "2 243068958312725669170431586 -87 88 53 4 8264471305592770 35 0",
        "2 243068958312725669170431586 -87 88 53 5 8264471305592770 35 0",
        "2 243068958312725669170431586 -87 88 53 6 8264471305592770 35 0",
        "2 1 -200 1 1 0 1 0 0",
        "2 1 -200 1 1 1 1 1 0",
        "2 1 -200 1 1 2 1 1 0",
        "2 1 -200 1 1 3 1 0 0",
        "2 1 -200 1 1 4 1 0 0",
        "2 1 -200 1 1 5 1 0 0",
        "2 1 -200 1 1 6 1 0 0",
        "2 1 -200 1 53 0 4503599627370496 -52 0",
        "2 1 -200 1 53 1 4503599627370497 -52 0",
        "2 1 -200 1 53 2 4503599627370497 -52 0",
        "2 1 -200 1 53 3 4503599627370496 -52 0",
        "2 1 -200 1 53 4 4503599627370496 -52 0",
        "2 1 -200 1 53 5 4503599627370496 -52 0",
        "2 1 -200 1 53 6 4503599627370496 -52 0",
    ]

    for row in cases:
        var field = row.split(" ")
        var x = BigFloat(
            significand=BigInt(String(field[1])),
            exponent=Int(String(field[2])),
            precision=Int(String(field[3])),
            sign=False,
        )
        var destination = Int(String(field[4]))
        var mode = modes[Int(String(field[5]))]
        var kind = Int(String(field[0]))
        var got = cot(x, destination, mode) if kind == 0 else (
            csc(x, destination, mode) if kind
            == 1 else sec(x, destination, mode)
        )
        var want = String("-") if field[8] == "1" else String("")
        want += (
            String(field[6])
            + "p"
            + String(field[7])
            + "@"
            + String(destination)
        )
        assert_equal(got.internal_representation(), want, String("case ") + row)


def test_each_is_the_reciprocal_it_is_named_for() raises:
    """`cot * tan`, `csc * sin` and `sec * cos` are all one.

    No reference is needed for this, and it reaches further than the table
    does: the two sides take different quotients of the same two series, so
    a quadrant handled the wrong way round shows up here even where the
    answer happens to be small.
    """
    var precision = 160
    var narrower = precision - 20
    var one = BigFloat.from_int(1, narrower).internal_representation()
    for text in ["0.5", "1", "2", "3", "-1.5", "100", "1e10", "0.0001"]:
        var x = BigFloat.from_string(text, precision)
        assert_equal(
            multiply(
                cot(x, precision), tan(x, precision), narrower
            ).internal_representation(),
            one,
            String("cot * tan at ") + text,
        )
        assert_equal(
            multiply(
                csc(x, precision), sin(x, precision), narrower
            ).internal_representation(),
            one,
            String("csc * sin at ") + text,
        )
        assert_equal(
            multiply(
                sec(x, precision), cos(x, precision), narrower
            ).internal_representation(),
            one,
            String("sec * cos at ") + text,
        )


def test_the_poles_and_the_special_values() raises:
    """A zero is the one pole a binary float lands on.

    `cot` and `csc` have one there and return an infinity of the zero's
    sign, which is what a float does where the decimal layer has to raise.
    `sec` has no pole at all and its value at zero is exactly one.
    """
    assert_true(cot(BigFloat.zero(53, False), 53).is_infinite())
    assert_true(cot(BigFloat.zero(53, True), 53).is_infinite())
    assert_true(cot(BigFloat.zero(53, True), 53).sign, "cot(-0) is negative")
    assert_true(csc(BigFloat.zero(53, False), 53).is_infinite())
    assert_true(csc(BigFloat.zero(53, True), 53).sign, "csc(-0) is negative")
    assert_equal(
        sec(BigFloat.zero(53, False), 53).internal_representation(),
        BigFloat.from_int(1, 53).internal_representation(),
        "sec(0) is one",
    )

    for value in [
        BigFloat.nan(53),
        BigFloat.infinity(53, False),
        BigFloat.infinity(53, True),
    ]:
        assert_true(cot(value, 53).is_nan(), "cot of a NaN or an infinity")
        assert_true(csc(value, 53).is_nan(), "csc of a NaN or an infinity")
        assert_true(sec(value, 53).is_nan(), "sec of a NaN or an infinity")


def test_a_tiny_argument_is_answered_not_iterated() raises:
    """Below a point, none of the three can be reached by widening.

    `sec(x)` is one to within a rounding, and a kernel that returns exactly
    one says nothing about which side of one the truth is on. `cot(x)` and
    `csc(x)` are `1/x` to within a rounding, and where `1/x` is a float --
    which is where `x` is a power of two -- the kernel lands exactly on a
    rounding boundary and no width moves it off. The deciding loop widens
    eight times and gives up, so all three cases are answered directly:
    `1 + x^2/2` for the secant, and the reciprocal moved a hair toward zero
    for the cotangent and away from it for the cosecant.

    `2^-2000` is past the point where widening could rescue any of them.
    Both directed modes are checked, because the whole content of these
    branches is which side of the boundary the true value lies on.
    """
    var tiny = BigFloat.power_of_two(-2000)

    assert_equal(
        sec(tiny, 53, RoundingMode.ROUND_HALF_EVEN).internal_representation(),
        "4503599627370496p-52@53",
        "sec to nearest is one",
    )
    assert_equal(
        sec(tiny, 53, RoundingMode.ROUND_UP).internal_representation(),
        "4503599627370497p-52@53",
        "sec upward is the value above one",
    )
    assert_equal(
        sec(tiny, 53, RoundingMode.ROUND_DOWN).internal_representation(),
        "4503599627370496p-52@53",
        "sec downward is one",
    )

    # `cot(x) = 1/x - x/3`, so downward it is the value below `2^2000`.
    assert_equal(
        cot(tiny, 53, RoundingMode.ROUND_DOWN).internal_representation(),
        "9007199254740991p1947@53",
        "cot downward is below the reciprocal",
    )
    assert_equal(
        cot(tiny, 53, RoundingMode.ROUND_UP).internal_representation(),
        "4503599627370496p1948@53",
        "cot upward is the reciprocal",
    )

    # `csc(x) = 1/x + x/6`, which is the other side.
    assert_equal(
        csc(tiny, 53, RoundingMode.ROUND_DOWN).internal_representation(),
        "4503599627370496p1948@53",
        "csc downward is the reciprocal",
    )
    assert_equal(
        csc(tiny, 53, RoundingMode.ROUND_UP).internal_representation(),
        "4503599627370497p1948@53",
        "csc upward is above the reciprocal",
    )


def test_a_tiny_argument_that_is_not_a_power_of_two_still_settles() raises:
    """The direct answer is only for a reciprocal that is a float.

    Everywhere else `1/x` falls between two of them and the deciding loop
    settles on its own, which is worth pinning: the branch above must not
    be the only thing holding a small argument up.
    """
    var x = BigFloat(
        significand=BigInt(12345), exponent=-30000, precision=14, sign=False
    )
    assert_equal(
        cot(x, 53, RoundingMode.ROUND_DOWN).internal_representation(),
        "5977073818941936p29934@53",
        "cot of 12345 * 2^-30000",
    )
    assert_equal(
        csc(x, 53, RoundingMode.ROUND_UP).internal_representation(),
        "5977073818941937p29934@53",
        "csc of 12345 * 2^-30000",
    )
    assert_equal(
        sec(x, 53, RoundingMode.ROUND_UP).internal_representation(),
        "4503599627370497p-52@53",
        "sec of 12345 * 2^-30000",
    )


def test_a_precision_must_be_positive() raises:
    for precision in [0, -1]:
        for kind in range(3):
            var raised = False
            try:
                var x = BigFloat.from_int(1, 53)
                _ = cot(x, precision) if kind == 0 else (
                    csc(x, precision) if kind == 1 else sec(x, precision)
                )
            except:
                raised = True
            assert_true(raised, String("precision ") + String(precision))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
