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
Tests the exponential and the logarithm of `BigFloat`.

The reference is CPython's `decimal`, whose `exp` and `ln` are correctly
rounded to the context's precision. Each expectation is taken at eighty
digits more than the answer needs and then rounded to the bits asked for by a
short program working in exact rationals, so the table is the correctly
rounded answer and not a transcription of one.

Three checks need no reference at all. The two functions are inverses, so
`exp(ln(x))` has to come back as `x` to the bits a round trip can keep.
`ln(2)` and `exp(1)` have to agree with the two constants, which are computed
by different code with different error. And the laws -- the logarithm of a
product is the sum of the logarithms, the exponential of a sum is the product
of the exponentials -- have to hold to the last few bits.
"""

from std import testing
from std.testing import assert_equal, assert_false, assert_true

from decimo.bigfloat.arithmetics import add, multiply, subtract
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.comparison import compare_absolute
from decimo.bigfloat.constants import e, ln2
from decimo.bigfloat.exponential import exp, ln
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


def _assert_close(
    left: BigFloat, right: BigFloat, units: Int, what: String
) raises:
    """Asserts that two values differ by at most `units` of the last place.

    Args:
        left: The first value.
        right: The second value.
        units: How many units in the last place to allow.
        what: What is being compared, for the message.

    Raises:
        Error: If they differ by more, or from the arithmetic.
    """
    var difference = subtract(left, right, left.precision + 4)
    if difference.is_zero():
        return
    # One unit in the last place of the larger value, times the allowance.
    var allowance = BigFloat(
        significand=BigInt(units),
        exponent=left.exponent,
        precision=BigInt(units).bit_length(),
        sign=False,
    )
    if compare_absolute(difference, allowance) > 0:
        raise Error(
            what
            + " differed by more than "
            + String(units)
            + " units in the last place: "
            + difference.internal_representation()
        )


def test_the_values_are_what_the_reference_rounds_to() raises:
    """Sixteen arguments at three precisions in all seven modes.

    The arguments include the powers of two at both ends of where the
    argument reduction bites, a value below the width's last place where the
    answer is one plus a sticky bit, and the arguments whose answers are the
    two constants.
    """
    var modes = _modes()
    # kind significand exponent precision destination mode expected_significand expected_exponent negative
    var cases = [
        "0 1 0 1 1 0 1 1 0",
        "0 1 0 1 1 1 1 2 0",
        "0 1 0 1 1 2 1 2 0",
        "0 1 0 1 1 3 1 1 0",
        "0 1 0 1 1 4 1 1 0",
        "0 1 0 1 1 5 1 1 0",
        "0 1 0 1 1 6 1 1 0",
        "0 1 0 1 53 0 6121026514868073 -51 0",
        "0 1 0 1 53 1 6121026514868074 -51 0",
        "0 1 0 1 53 2 6121026514868074 -51 0",
        "0 1 0 1 53 3 6121026514868073 -51 0",
        "0 1 0 1 53 4 6121026514868073 -51 0",
        "0 1 0 1 53 5 6121026514868073 -51 0",
        "0 1 0 1 53 6 6121026514868073 -51 0",
        "0 1 0 1 113 0 7057063099260103890616691862818426 -111 0",
        "0 1 0 1 113 1 7057063099260103890616691862818427 -111 0",
        "0 1 0 1 113 2 7057063099260103890616691862818427 -111 0",
        "0 1 0 1 113 3 7057063099260103890616691862818426 -111 0",
        "0 1 0 1 113 4 7057063099260103890616691862818426 -111 0",
        "0 1 0 1 113 5 7057063099260103890616691862818426 -111 0",
        "0 1 0 1 113 6 7057063099260103890616691862818426 -111 0",
        "0 1 -1 1 1 0 1 0 0",
        "0 1 -1 1 1 1 1 1 0",
        "0 1 -1 1 1 2 1 1 0",
        "0 1 -1 1 1 3 1 0 0",
        "0 1 -1 1 1 4 1 1 0",
        "0 1 -1 1 1 5 1 1 0",
        "0 1 -1 1 1 6 1 1 0",
        "0 1 -1 1 53 0 7425180500362907 -52 0",
        "0 1 -1 1 53 1 7425180500362908 -52 0",
        "0 1 -1 1 53 2 7425180500362908 -52 0",
        "0 1 -1 1 53 3 7425180500362907 -52 0",
        "0 1 -1 1 53 4 7425180500362908 -52 0",
        "0 1 -1 1 53 5 7425180500362908 -52 0",
        "0 1 -1 1 53 6 7425180500362908 -52 0",
        "0 1 -1 1 113 0 8560650274455824524395948105195315 -112 0",
        "0 1 -1 1 113 1 8560650274455824524395948105195316 -112 0",
        "0 1 -1 1 113 2 8560650274455824524395948105195316 -112 0",
        "0 1 -1 1 113 3 8560650274455824524395948105195315 -112 0",
        "0 1 -1 1 113 4 8560650274455824524395948105195316 -112 0",
        "0 1 -1 1 113 5 8560650274455824524395948105195316 -112 0",
        "0 1 -1 1 113 6 8560650274455824524395948105195316 -112 0",
        "0 3 -1 2 1 0 1 2 0",
        "0 3 -1 2 1 1 1 3 0",
        "0 3 -1 2 1 2 1 3 0",
        "0 3 -1 2 1 3 1 2 0",
        "0 3 -1 2 1 4 1 2 0",
        "0 3 -1 2 1 5 1 2 0",
        "0 3 -1 2 1 6 1 2 0",
        "0 3 -1 2 53 0 5045933306791233 -50 0",
        "0 3 -1 2 53 1 5045933306791234 -50 0",
        "0 3 -1 2 53 2 5045933306791234 -50 0",
        "0 3 -1 2 53 3 5045933306791233 -50 0",
        "0 3 -1 2 53 4 5045933306791233 -50 0",
        "0 3 -1 2 53 5 5045933306791233 -50 0",
        "0 3 -1 2 53 6 5045933306791233 -50 0",
        "0 3 -1 2 113 0 5817565020211551528374232979405431 -110 0",
        "0 3 -1 2 113 1 5817565020211551528374232979405432 -110 0",
        "0 3 -1 2 113 2 5817565020211551528374232979405432 -110 0",
        "0 3 -1 2 113 3 5817565020211551528374232979405431 -110 0",
        "0 3 -1 2 113 4 5817565020211551528374232979405432 -110 0",
        "0 3 -1 2 113 5 5817565020211551528374232979405432 -110 0",
        "0 3 -1 2 113 6 5817565020211551528374232979405432 -110 0",
        "0 1 1 1 1 0 1 2 0",
        "0 1 1 1 1 1 1 3 0",
        "0 1 1 1 1 2 1 3 0",
        "0 1 1 1 1 3 1 2 0",
        "0 1 1 1 1 4 1 3 0",
        "0 1 1 1 1 5 1 3 0",
        "0 1 1 1 1 6 1 3 0",
        "0 1 1 1 53 0 8319337573440941 -50 0",
        "0 1 1 1 53 1 8319337573440942 -50 0",
        "0 1 1 1 53 2 8319337573440942 -50 0",
        "0 1 1 1 53 3 8319337573440941 -50 0",
        "0 1 1 1 53 4 8319337573440942 -50 0",
        "0 1 1 1 53 5 8319337573440942 -50 0",
        "0 1 1 1 53 6 8319337573440942 -50 0",
        "0 1 1 1 113 0 9591543192503805921303853669987978 -110 0",
        "0 1 1 1 113 1 9591543192503805921303853669987979 -110 0",
        "0 1 1 1 113 2 9591543192503805921303853669987979 -110 0",
        "0 1 1 1 113 3 9591543192503805921303853669987978 -110 0",
        "0 1 1 1 113 4 9591543192503805921303853669987979 -110 0",
        "0 1 1 1 113 5 9591543192503805921303853669987979 -110 0",
        "0 1 1 1 113 6 9591543192503805921303853669987979 -110 0",
        "0 1 -100 1 1 0 1 0 0",
        "0 1 -100 1 1 1 1 1 0",
        "0 1 -100 1 1 2 1 1 0",
        "0 1 -100 1 1 3 1 0 0",
        "0 1 -100 1 1 4 1 0 0",
        "0 1 -100 1 1 5 1 0 0",
        "0 1 -100 1 1 6 1 0 0",
        "0 1 -100 1 53 0 4503599627370496 -52 0",
        "0 1 -100 1 53 1 4503599627370497 -52 0",
        "0 1 -100 1 53 2 4503599627370497 -52 0",
        "0 1 -100 1 53 3 4503599627370496 -52 0",
        "0 1 -100 1 53 4 4503599627370496 -52 0",
        "0 1 -100 1 53 5 4503599627370496 -52 0",
        "0 1 -100 1 53 6 4503599627370496 -52 0",
        "0 1 -100 1 113 0 5192296858534827628530496329224192 -112 0",
        "0 1 -100 1 113 1 5192296858534827628530496329224193 -112 0",
        "0 1 -100 1 113 2 5192296858534827628530496329224193 -112 0",
        "0 1 -100 1 113 3 5192296858534827628530496329224192 -112 0",
        "0 1 -100 1 113 4 5192296858534827628530496329224192 -112 0",
        "0 1 -100 1 113 5 5192296858534827628530496329224192 -112 0",
        "0 1 -100 1 113 6 5192296858534827628530496329224192 -112 0",
        "0 25 2 5 1 0 1 144 0",
        "0 25 2 5 1 1 1 145 0",
        "0 25 2 5 1 2 1 145 0",
        "0 25 2 5 1 3 1 144 0",
        "0 25 2 5 1 4 1 144 0",
        "0 25 2 5 1 5 1 144 0",
        "0 25 2 5 1 6 1 144 0",
        "0 25 2 5 53 0 5428609335892980 92 0",
        "0 25 2 5 53 1 5428609335892981 92 0",
        "0 25 2 5 53 2 5428609335892981 92 0",
        "0 25 2 5 53 3 5428609335892980 92 0",
        "0 25 2 5 53 4 5428609335892981 92 0",
        "0 25 2 5 53 5 5428609335892981 92 0",
        "0 25 2 5 53 6 5428609335892981 92 0",
        "0 25 2 5 113 0 6258760443460511622048508263146536 32 0",
        "0 25 2 5 113 1 6258760443460511622048508263146537 32 0",
        "0 25 2 5 113 2 6258760443460511622048508263146537 32 0",
        "0 25 2 5 113 3 6258760443460511622048508263146536 32 0",
        "0 25 2 5 113 4 6258760443460511622048508263146536 32 0",
        "0 25 2 5 113 5 6258760443460511622048508263146536 32 0",
        "0 25 2 5 113 6 6258760443460511622048508263146536 32 0",
        "0 1 4 1 1 0 1 23 0",
        "0 1 4 1 1 1 1 24 0",
        "0 1 4 1 1 2 1 24 0",
        "0 1 4 1 1 3 1 23 0",
        "0 1 4 1 1 4 1 23 0",
        "0 1 4 1 1 5 1 23 0",
        "0 1 4 1 1 6 1 23 0",
        "0 1 4 1 53 0 4770694259277856 -29 0",
        "0 1 4 1 53 1 4770694259277857 -29 0",
        "0 1 4 1 53 2 4770694259277857 -29 0",
        "0 1 4 1 53 3 4770694259277856 -29 0",
        "0 1 4 1 53 4 4770694259277856 -29 0",
        "0 1 4 1 53 5 4770694259277856 -29 0",
        "0 1 4 1 53 6 4770694259277856 -29 0",
        "0 1 4 1 113 0 5500236003425873407443993490893662 -89 0",
        "0 1 4 1 113 1 5500236003425873407443993490893663 -89 0",
        "0 1 4 1 113 2 5500236003425873407443993490893663 -89 0",
        "0 1 4 1 113 3 5500236003425873407443993490893662 -89 0",
        "0 1 4 1 113 4 5500236003425873407443993490893663 -89 0",
        "0 1 4 1 113 5 5500236003425873407443993490893663 -89 0",
        "0 1 4 1 113 6 5500236003425873407443993490893663 -89 0",
        "0 1 -70 1 1 0 1 0 0",
        "0 1 -70 1 1 1 1 1 0",
        "0 1 -70 1 1 2 1 1 0",
        "0 1 -70 1 1 3 1 0 0",
        "0 1 -70 1 1 4 1 0 0",
        "0 1 -70 1 1 5 1 0 0",
        "0 1 -70 1 1 6 1 0 0",
        "0 1 -70 1 53 0 4503599627370496 -52 0",
        "0 1 -70 1 53 1 4503599627370497 -52 0",
        "0 1 -70 1 53 2 4503599627370497 -52 0",
        "0 1 -70 1 53 3 4503599627370496 -52 0",
        "0 1 -70 1 53 4 4503599627370496 -52 0",
        "0 1 -70 1 53 5 4503599627370496 -52 0",
        "0 1 -70 1 53 6 4503599627370496 -52 0",
        "0 1 -70 1 113 0 5192296858534827628534894375731200 -112 0",
        "0 1 -70 1 113 1 5192296858534827628534894375731201 -112 0",
        "0 1 -70 1 113 2 5192296858534827628534894375731201 -112 0",
        "0 1 -70 1 113 3 5192296858534827628534894375731200 -112 0",
        "0 1 -70 1 113 4 5192296858534827628534894375731200 -112 0",
        "0 1 -70 1 113 5 5192296858534827628534894375731200 -112 0",
        "0 1 -70 1 113 6 5192296858534827628534894375731200 -112 0",
        "1 1 1 1 1 0 1 -1 0",
        "1 1 1 1 1 1 1 0 0",
        "1 1 1 1 1 2 1 0 0",
        "1 1 1 1 1 3 1 -1 0",
        "1 1 1 1 1 4 1 -1 0",
        "1 1 1 1 1 5 1 -1 0",
        "1 1 1 1 1 6 1 -1 0",
        "1 1 1 1 53 0 6243314768165359 -53 0",
        "1 1 1 1 53 1 6243314768165360 -53 0",
        "1 1 1 1 53 2 6243314768165360 -53 0",
        "1 1 1 1 53 3 6243314768165359 -53 0",
        "1 1 1 1 53 4 6243314768165359 -53 0",
        "1 1 1 1 53 5 6243314768165359 -53 0",
        "1 1 1 1 53 6 6243314768165359 -53 0",
        "1 1 1 1 113 0 7198051856247353947080814903691237 -113 0",
        "1 1 1 1 113 1 7198051856247353947080814903691238 -113 0",
        "1 1 1 1 113 2 7198051856247353947080814903691238 -113 0",
        "1 1 1 1 113 3 7198051856247353947080814903691237 -113 0",
        "1 1 1 1 113 4 7198051856247353947080814903691238 -113 0",
        "1 1 1 1 113 5 7198051856247353947080814903691238 -113 0",
        "1 1 1 1 113 6 7198051856247353947080814903691238 -113 0",
        "1 5 -2 3 1 0 1 -3 0",
        "1 5 -2 3 1 1 1 -2 0",
        "1 5 -2 3 1 2 1 -2 0",
        "1 5 -2 3 1 3 1 -3 0",
        "1 5 -2 3 1 4 1 -2 0",
        "1 5 -2 3 1 5 1 -2 0",
        "1 5 -2 3 1 6 1 -2 0",
        "1 5 -2 3 53 0 8039593716390433 -55 0",
        "1 5 -2 3 53 1 8039593716390434 -55 0",
        "1 5 -2 3 53 2 8039593716390434 -55 0",
        "1 5 -2 3 53 3 8039593716390433 -55 0",
        "1 5 -2 3 53 4 8039593716390434 -55 0",
        "1 5 -2 3 53 5 8039593716390434 -55 0",
        "1 5 -2 3 53 6 8039593716390434 -55 0",
        "1 5 -2 3 113 0 9269020483928611375916266407590810 -115 0",
        "1 5 -2 3 113 1 9269020483928611375916266407590811 -115 0",
        "1 5 -2 3 113 2 9269020483928611375916266407590811 -115 0",
        "1 5 -2 3 113 3 9269020483928611375916266407590810 -115 0",
        "1 5 -2 3 113 4 9269020483928611375916266407590810 -115 0",
        "1 5 -2 3 113 5 9269020483928611375916266407590810 -115 0",
        "1 5 -2 3 113 6 9269020483928611375916266407590810 -115 0",
        "1 1 -1 1 1 0 1 -1 1",
        "1 1 -1 1 1 1 1 0 1",
        "1 1 -1 1 1 2 1 -1 1",
        "1 1 -1 1 1 3 1 0 1",
        "1 1 -1 1 1 4 1 -1 1",
        "1 1 -1 1 1 5 1 -1 1",
        "1 1 -1 1 1 6 1 -1 1",
        "1 1 -1 1 53 0 6243314768165359 -53 1",
        "1 1 -1 1 53 1 6243314768165360 -53 1",
        "1 1 -1 1 53 2 6243314768165359 -53 1",
        "1 1 -1 1 53 3 6243314768165360 -53 1",
        "1 1 -1 1 53 4 6243314768165359 -53 1",
        "1 1 -1 1 53 5 6243314768165359 -53 1",
        "1 1 -1 1 53 6 6243314768165359 -53 1",
        "1 1 -1 1 113 0 7198051856247353947080814903691237 -113 1",
        "1 1 -1 1 113 1 7198051856247353947080814903691238 -113 1",
        "1 1 -1 1 113 2 7198051856247353947080814903691237 -113 1",
        "1 1 -1 1 113 3 7198051856247353947080814903691238 -113 1",
        "1 1 -1 1 113 4 7198051856247353947080814903691238 -113 1",
        "1 1 -1 1 113 5 7198051856247353947080814903691238 -113 1",
        "1 1 -1 1 113 6 7198051856247353947080814903691238 -113 1",
        "1 1 0 1 1 0 0 0 0",
        "1 1 0 1 1 1 0 0 0",
        "1 1 0 1 1 2 0 0 0",
        "1 1 0 1 1 3 0 0 0",
        "1 1 0 1 1 4 0 0 0",
        "1 1 0 1 1 5 0 0 0",
        "1 1 0 1 1 6 0 0 0",
        "1 1 0 1 53 0 0 0 0",
        "1 1 0 1 53 1 0 0 0",
        "1 1 0 1 53 2 0 0 0",
        "1 1 0 1 53 3 0 0 0",
        "1 1 0 1 53 4 0 0 0",
        "1 1 0 1 53 5 0 0 0",
        "1 1 0 1 53 6 0 0 0",
        "1 1 0 1 113 0 0 0 0",
        "1 1 0 1 113 1 0 0 0",
        "1 1 0 1 113 2 0 0 0",
        "1 1 0 1 113 3 0 0 0",
        "1 1 0 1 113 4 0 0 0",
        "1 1 0 1 113 5 0 0 0",
        "1 1 0 1 113 6 0 0 0",
        "1 1 100 1 1 0 1 6 0",
        "1 1 100 1 1 1 1 7 0",
        "1 1 100 1 1 2 1 7 0",
        "1 1 100 1 1 3 1 6 0",
        "1 1 100 1 1 4 1 6 0",
        "1 1 100 1 1 5 1 6 0",
        "1 1 100 1 1 6 1 6 0",
        "1 1 100 1 53 0 4877589662629186 -46 0",
        "1 1 100 1 53 1 4877589662629187 -46 0",
        "1 1 100 1 53 2 4877589662629187 -46 0",
        "1 1 100 1 53 3 4877589662629186 -46 0",
        "1 1 100 1 53 4 4877589662629187 -46 0",
        "1 1 100 1 53 5 4877589662629187 -46 0",
        "1 1 100 1 53 6 4877589662629187 -46 0",
        "1 1 100 1 113 0 5623478012693245271156886643508779 -106 0",
        "1 1 100 1 113 1 5623478012693245271156886643508780 -106 0",
        "1 1 100 1 113 2 5623478012693245271156886643508780 -106 0",
        "1 1 100 1 113 3 5623478012693245271156886643508779 -106 0",
        "1 1 100 1 113 4 5623478012693245271156886643508780 -106 0",
        "1 1 100 1 113 5 5623478012693245271156886643508780 -106 0",
        "1 1 100 1 113 6 5623478012693245271156886643508780 -106 0",
        "1 1 -100 1 1 0 1 6 1",
        "1 1 -100 1 1 1 1 7 1",
        "1 1 -100 1 1 2 1 6 1",
        "1 1 -100 1 1 3 1 7 1",
        "1 1 -100 1 1 4 1 6 1",
        "1 1 -100 1 1 5 1 6 1",
        "1 1 -100 1 1 6 1 6 1",
        "1 1 -100 1 53 0 4877589662629186 -46 1",
        "1 1 -100 1 53 1 4877589662629187 -46 1",
        "1 1 -100 1 53 2 4877589662629186 -46 1",
        "1 1 -100 1 53 3 4877589662629187 -46 1",
        "1 1 -100 1 53 4 4877589662629187 -46 1",
        "1 1 -100 1 53 5 4877589662629187 -46 1",
        "1 1 -100 1 53 6 4877589662629187 -46 1",
        "1 1 -100 1 113 0 5623478012693245271156886643508779 -106 1",
        "1 1 -100 1 113 1 5623478012693245271156886643508780 -106 1",
        "1 1 -100 1 113 2 5623478012693245271156886643508779 -106 1",
        "1 1 -100 1 113 3 5623478012693245271156886643508780 -106 1",
        "1 1 -100 1 113 4 5623478012693245271156886643508780 -106 1",
        "1 1 -100 1 113 5 5623478012693245271156886643508780 -106 1",
        "1 1 -100 1 113 6 5623478012693245271156886643508780 -106 1",
        "1 3 -1 2 1 0 1 -2 0",
        "1 3 -1 2 1 1 1 -1 0",
        "1 3 -1 2 1 2 1 -1 0",
        "1 3 -1 2 1 3 1 -2 0",
        "1 3 -1 2 1 4 1 -1 0",
        "1 3 -1 2 1 5 1 -1 0",
        "1 3 -1 2 1 6 1 -1 0",
        "1 3 -1 2 53 0 7304210039150667 -54 0",
        "1 3 -1 2 53 1 7304210039150668 -54 0",
        "1 3 -1 2 53 2 7304210039150668 -54 0",
        "1 3 -1 2 53 3 7304210039150667 -54 0",
        "1 3 -1 2 53 4 7304210039150668 -54 0",
        "1 3 -1 2 53 5 7304210039150668 -54 0",
        "1 3 -1 2 53 6 7304210039150668 -54 0",
        "1 3 -1 2 113 0 8421180828302024747653200799335714 -114 0",
        "1 3 -1 2 113 1 8421180828302024747653200799335715 -114 0",
        "1 3 -1 2 113 2 8421180828302024747653200799335715 -114 0",
        "1 3 -1 2 113 3 8421180828302024747653200799335714 -114 0",
        "1 3 -1 2 113 4 8421180828302024747653200799335714 -114 0",
        "1 3 -1 2 113 5 8421180828302024747653200799335714 -114 0",
        "1 3 -1 2 113 6 8421180828302024747653200799335714 -114 0",
        "1 7 0 3 1 0 1 0 0",
        "1 7 0 3 1 1 1 1 0",
        "1 7 0 3 1 2 1 1 0",
        "1 7 0 3 1 3 1 0 0",
        "1 7 0 3 1 4 1 1 0",
        "1 7 0 3 1 5 1 1 0",
        "1 7 0 3 1 6 1 1 0",
        "1 7 0 3 53 0 8763600222181975 -52 0",
        "1 7 0 3 53 1 8763600222181976 -52 0",
        "1 7 0 3 53 2 8763600222181976 -52 0",
        "1 7 0 3 53 3 8763600222181975 -52 0",
        "1 7 0 3 53 4 8763600222181975 -52 0",
        "1 7 0 3 53 5 8763600222181975 -52 0",
        "1 7 0 3 53 6 8763600222181975 -52 0",
        "1 7 0 3 113 0 10103743153930941452656796255594011 -112 0",
        "1 7 0 3 113 1 10103743153930941452656796255594012 -112 0",
        "1 7 0 3 113 2 10103743153930941452656796255594012 -112 0",
        "1 7 0 3 113 3 10103743153930941452656796255594011 -112 0",
        "1 7 0 3 113 4 10103743153930941452656796255594012 -112 0",
        "1 7 0 3 113 5 10103743153930941452656796255594012 -112 0",
        "1 7 0 3 113 6 10103743153930941452656796255594012 -112 0",
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
        var got = exp(x, destination, mode) if field[0] == "0" else ln(
            x, destination, mode
        )
        var want = String("-") if field[8] == "1" else String("")
        want += (
            String(field[6])
            + "p"
            + String(field[7])
            + "@"
            + String(destination)
        )
        assert_equal(
            got.internal_representation(),
            want,
            String("case ") + row,
        )


def test_the_two_are_inverses() raises:
    """`exp(ln(x))` is `x`, to the bits the round trip can keep.

    Two roundings and two series stand between the two ends, so the
    comparison is at ten bits below the working precision. This is the check
    that does not depend on any reference: it only says the two functions
    agree about what the other one did.
    """
    for text in ["2", "7", "0.5", "1.25", "1e10", "1e-10", "1234.5678"]:
        var x = BigFloat.from_string(text, 160)
        var back = exp(ln(x, 160), 160)
        assert_equal(
            BigFloat.from_rounded_parts(
                back.significand, back.exponent, 150, back.sign
            ).internal_representation(),
            BigFloat.from_rounded_parts(
                x.significand, x.exponent, 150, x.sign
            ).internal_representation(),
            String("the round trip of ") + text,
        )


def test_the_logarithm_of_two_agrees_with_the_constant() raises:
    """Two implementations of the same number, which have to agree.

    The constant sums the inverse hyperbolic tangent in fixed-point integers;
    `ln` runs the same series in correctly rounded float operations on
    `(x-1)/(x+1)`. Different code, different error, same answer.
    """
    for precision in [1, 2, 53, 113, 300]:
        for mode in _modes():
            assert_equal(
                ln(
                    BigFloat.from_int(2), precision, mode
                ).internal_representation(),
                ln2(precision, mode).internal_representation(),
                String("ln(2) at ") + String(precision) + " bits",
            )

    # And `exp(1)` is the other constant, by the same argument.
    for precision in [1, 53, 113, 300]:
        assert_equal(
            exp(BigFloat.from_int(1), precision).internal_representation(),
            e(precision).internal_representation(),
            String("exp(1) at ") + String(precision) + " bits",
        )


def test_the_laws_hold_to_the_precision_asked_for() raises:
    """`ln(xy) = ln x + ln y` and `exp(x+y) = exp(x)exp(y)`.

    Each side is correctly rounded and then combined, so the two sides can
    differ in their last bits but not more. The tolerance is three units of
    the last place, which is what two roundings and one more operation allow.
    """
    var precision = 120
    var pairs = [
        [String("3"), String("5")],
        [String("0.25"), String("1e8")],
        [String("1.5"), String("1.5")],
        [String("1e-5"), String("7")],
    ]
    for p in range(len(pairs)):
        var a = BigFloat.from_string(pairs[p][0], precision)
        var b = BigFloat.from_string(pairs[p][1], precision)

        var product = multiply(a, b, precision)
        var sum_of_logs = add(ln(a, precision), ln(b, precision), precision)
        _assert_close(
            ln(product, precision), sum_of_logs, 3, "the logarithm of a product"
        )

        var total = add(a, b, precision)
        var product_of_exps = multiply(
            exp(a, precision), exp(b, precision), precision
        )
        _assert_close(
            exp(total, precision),
            product_of_exps,
            3,
            "the exponential of a sum",
        )


def test_the_special_values_follow_ieee() raises:
    """An infinity, a NaN, a zero, and the one argument with no logarithm."""
    assert_true(exp(BigFloat.nan(), 53).is_nan(), "exp of a NaN")
    assert_true(
        exp(BigFloat.infinity(), 53).is_infinite(), "exp of an infinity"
    )
    assert_true(
        exp(-BigFloat.infinity(), 53).is_zero(),
        "exp of a negative infinity is a zero",
    )
    assert_equal(
        exp(BigFloat.zero(), 53).internal_representation(),
        BigFloat.from_int(1, 53).internal_representation(),
        "exp of a zero is one",
    )

    assert_true(ln(BigFloat.nan(), 53).is_nan(), "the logarithm of a NaN")
    assert_true(
        ln(BigFloat.from_int(-2), 53).is_nan(),
        "a negative value has no logarithm",
    )
    assert_true(
        ln(BigFloat.zero(), 53).is_infinite(),
        "the logarithm of a zero is an infinity",
    )
    assert_true(ln(BigFloat.zero(), 53).sign, "which runs to negative infinity")
    assert_true(ln(BigFloat.infinity(), 53).is_infinite(), "and of an infinity")
    assert_true(
        ln(BigFloat.from_int(1), 53).is_zero(), "the logarithm of one is zero"
    )
    assert_false(ln(BigFloat.from_int(1), 53).sign, "and it is a positive zero")
    assert_equal(
        ln(BigFloat.from_int(1), 53).precision,
        53,
        "and it comes back at the precision asked for",
    )


def test_the_range_ends_exactly_where_the_exponent_does() raises:
    """`exp(x)` has an answer exactly while `x / ln 2` has an `Int`.

    There is no overflow to an infinity here, because this type's exponent is
    as wide as an `Int` rather than eleven bits: an argument that asks for
    more is refused rather than answered with an infinity it did not earn.

    Where the refusal starts is the point. It is not a power of two: the
    largest answer has an exponent of `Int.MAX`, so the largest argument is
    `Int.MAX * ln 2`, about `6.39e18`. An earlier version compared bit
    lengths instead and refused every argument from `2^62` up, which threw
    away a third of the range for nothing -- `exp(4e18)` is a perfectly good
    float with an exponent of about `5.77e18`.
    """
    var accepted = exp(BigFloat.from_string("4e18", 60), 53)
    assert_true(accepted.is_finite(), "4e18 has an answer")
    assert_true(
        accepted.exponent > 5_000_000_000_000_000_000,
        "and its exponent is about 5.77e18",
    )
    assert_true(
        exp(BigFloat.from_string("6.3e18", 60), 53).is_finite(),
        "and so does an argument just inside the end of the range",
    )

    for text in ["6.4e18", "1e19", "1e30", "-1e30"]:
        var raised = False
        try:
            _ = exp(BigFloat.from_string(text, 60), 53)
        except:
            raised = True
        assert_true(raised, String("exp of ") + text + " invented an exponent")


def test_a_precision_must_fit_the_guard_bits() raises:
    for precision in [0, -1, Int.MAX, Int.MAX // 4 + 1]:
        for which in [0, 1]:
            var raised = False
            try:
                if which == 0:
                    _ = exp(BigFloat.from_int(1), precision)
                else:
                    _ = ln(BigFloat.from_int(2), precision)
            except:
                raised = True
            assert_true(
                raised,
                String("a precision of ") + String(precision) + " was taken",
            )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
