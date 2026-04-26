# ===----------------------------------------------------------------------=== #
# Copyright 2025 Yuhao Zhu
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
#
# Implements special functions for the Decimal128 type
#
# ===----------------------------------------------------------------------=== #

"""Implements functions for special operations on Decimal128 objects."""

from decimo.errors import ValueError, OverflowError


def factorial(n: Int) raises -> Decimal128:
    """Calculates the factorial of a non-negative integer.

    Args:
        n: The non-negative integer to calculate the factorial of.

    Returns:
        The factorial of n.

    Raises:
        ValueError: If n is negative.
        OverflowError: If n > 27.

    Notes:

    27! is the largest factorial that can be represented by Decimal128.
    An error will be raised if n is greater than 27.
    """

    if n < 0:
        raise ValueError(
            message="Factorial is not defined for negative numbers.",
            function="factorial()",
        )

    if n > 27:
        raise OverflowError(
            message=String(
                "{}! is too large to be represented by Decimal128."
            ).format(n),
            function="factorial()",
        )

    # Directly return the factorial for n = 0 to 27
    if n == 0 or n == 1:
        return Decimal128.from_words(1, 0, 0, 0)  # 1
    elif n == 2:
        return Decimal128.from_words(2, 0, 0, 0)  # 2
    elif n == 3:
        return Decimal128.from_words(6, 0, 0, 0)  # 6
    elif n == 4:
        return Decimal128.from_words(24, 0, 0, 0)  # 24
    elif n == 5:
        return Decimal128.from_words(120, 0, 0, 0)  # 120
    elif n == 6:
        return Decimal128.from_words(720, 0, 0, 0)  # 720
    elif n == 7:
        return Decimal128.from_words(5040, 0, 0, 0)  # 5040
    elif n == 8:
        return Decimal128.from_words(40320, 0, 0, 0)  # 40320
    elif n == 9:
        return Decimal128.from_words(362880, 0, 0, 0)  # 362880
    elif n == 10:
        return Decimal128.from_words(3628800, 0, 0, 0)  # 3628800
    elif n == 11:
        return Decimal128.from_words(39916800, 0, 0, 0)  # 39916800
    elif n == 12:
        return Decimal128.from_words(479001600, 0, 0, 0)  # 479001600
    elif n == 13:
        return Decimal128.from_words(1932053504, 1, 0, 0)  # 6227020800
    elif n == 14:
        return Decimal128.from_words(1278945280, 20, 0, 0)  # 87178291200
    elif n == 15:
        return Decimal128.from_words(2004310016, 304, 0, 0)  # 1307674368000
    elif n == 16:
        return Decimal128.from_words(2004189184, 4871, 0, 0)  # 20922789888000
    elif n == 17:
        return Decimal128.from_words(4006445056, 82814, 0, 0)  # 355687428096000
    elif n == 18:
        return Decimal128.from_words(
            3396534272, 1490668, 0, 0
        )  # 6402373705728000
    elif n == 19:
        return Decimal128.from_words(
            109641728, 28322707, 0, 0
        )  # 121645100408832000
    elif n == 20:
        return Decimal128.from_words(
            2192834560, 566454140, 0, 0
        )  # 2432902008176640000
    elif n == 21:
        return Decimal128.from_words(
            3099852800, 3305602358, 2, 0
        )  # 51090942171709440000
    elif n == 22:
        return Decimal128.from_words(
            3772252160, 4003775155, 60, 0
        )  # 1124000727777607680000
    elif n == 23:
        return Decimal128.from_words(
            862453760, 1892515369, 1401, 0
        )  # 25852016738884976640000
    elif n == 24:
        return Decimal128.from_words(
            3519021056, 2470695900, 33634, 0
        )  # 620448401733239439360000
    elif n == 25:
        return Decimal128.from_words(
            2076180480, 1637855376, 840864, 0
        )  # 15511210043330985984000000
    elif n == 26:
        return Decimal128.from_words(
            2441084928, 3929534124, 21862473, 0
        )  # 403291461126605650322784000
    else:
        return Decimal128.from_words(
            1484783616, 3018206259, 590286795, 0
        )  # 10888869450418352160768000000


# TODO: Use binary splitting method to speed up the search.
def factorial_reciprocal(n: Int) raises -> Decimal128:
    """Calculates the reciprocal of factorial of a non-negative integer (1/n!).

    Args:
        n: The non-negative integer to calculate the reciprocal factorial of.

    Returns:
        The reciprocal of factorial of n (1/n!).

    Raises:
        ValueError: If n is negative.

    Notes:
        This function is optimized for Taylor series calculations.
        The function uses pre-computed values for speed.
        For n > 27, the result is effectively 0 at Decimal128 precision.
    """

    # 1/0! = 1, Decimal128.from_words(0x1, 0x0, 0x0, 0x0)
    # 1/1! = 1, Decimal128.from_words(0x1, 0x0, 0x0, 0x0)
    # 1/2! = 0.5, Decimal128.from_words(0x5, 0x0, 0x0, 0x10000)
    # 1/3! = 0.1666666666666666666666666667, Decimal128.from_words(0x82aaaaab, 0xa5b8065, 0x562a265, 0x1c0000)
    # 1/4! = 0.0416666666666666666666666667, Decimal128.from_words(0x60aaaaab, 0x4296e019, 0x158a899, 0x1c0000)
    # 1/5! = 0.0083333333333333333333333333, Decimal128.from_words(0x13555555, 0xd516005, 0x44ee85, 0x1c0000)
    # 1/6! = 0.0013888888888888888888888889, Decimal128.from_words(0x2de38e39, 0x2ce2e556, 0xb7d16, 0x1c0000)
    # 1/7! = 0.0001984126984126984126984127, Decimal128.from_words(0xe1fbefbf, 0xbd44fc30, 0x1a427, 0x1c0000)
    # 1/8! = 0.0000248015873015873015873016, Decimal128.from_words(0x1c3f7df8, 0xf7a89f86, 0x3484, 0x1c0000)
    # 1/9! = 0.0000027557319223985890652557, Decimal128.from_words(0xca3ff18d, 0xe2a0f547, 0x5d5, 0x1c0000)
    # 1/10! = 0.0000002755731922398589065256, Decimal128.from_words(0x94399828, 0x63767eed, 0x95, 0x1c0000)
    # 1/11! = 0.0000000250521083854417187751, Decimal128.from_words(0xb06253a7, 0x94adae72, 0xd, 0x1c0000)
    # 1/12! = 0.0000000020876756987868098979, Decimal128.from_words(0xe40831a3, 0x21b923de, 0x1, 0x1c0000)
    # 1/13! = 0.0000000001605904383682161460, Decimal128.from_words(0x4c9e2b34, 0x16495187, 0x0, 0x1c0000)
    # 1/14! = 0.0000000000114707455977297247, Decimal128.from_words(0xce9d955f, 0x19785d2, 0x0, 0x1c0000)
    # 1/15! = 0.0000000000007647163731819816, Decimal128.from_words(0xdc63d28, 0x1b2b0e, 0x0, 0x1c0000)
    # 1/16! = 0.0000000000000477947733238739, Decimal128.from_words(0xe0dc63d3, 0x1b2b0, 0x0, 0x1c0000)
    # 1/17! = 0.0000000000000028114572543455, Decimal128.from_words(0xef1c05df, 0x1991, 0x0, 0x1c0000)
    # 1/18! = 0.0000000000000001561920696859, Decimal128.from_words(0xa9ba721b, 0x16b, 0x0, 0x1c0000)
    # 1/19! = 0.0000000000000000082206352466, Decimal128.from_words(0x23e16452, 0x13, 0x0, 0x1c0000)
    # 1/20! = 0.0000000000000000004110317623, Decimal128.from_words(0xf4fe7837, 0x0, 0x0, 0x1c0000)
    # 1/21! = 0.0000000000000000000195729411, Decimal128.from_words(0xbaa9803, 0x0, 0x0, 0x1c0000)
    # 1/22! = 0.0000000000000000000008896791, Decimal128.from_words(0x87c117, 0x0, 0x0, 0x1c0000)
    # 1/23! = 0.0000000000000000000000386817, Decimal128.from_words(0x5e701, 0x0, 0x0, 0x1c0000)
    # 1/24! = 0.0000000000000000000000016117, Decimal128.from_words(0x3ef5, 0x0, 0x0, 0x1c0000)
    # 1/25! = 0.0000000000000000000000000645, Decimal128.from_words(0x285, 0x0, 0x0, 0x1c0000)
    # 1/26! = 0.0000000000000000000000000025, Decimal128.from_words(0x19, 0x0, 0x0, 0x1c0000)
    # 1/27! = 0.0000000000000000000000000001, Decimal128.from_words(0x1, 0x0, 0x0, 0x1c0000)

    if n < 0:
        raise ValueError(
            message="Factorial reciprocal is not defined for negative numbers.",
            function="factorial_reciprocal()",
        )

    # For n > 27, 1/n! is essentially 0 at Decimal128 precision
    # Return 0 with max scale
    if n > 27:
        return Decimal128.from_words(0, 0, 0, 0x001C0000)

    # Directly return pre-computed reciprocal factorials
    if n == 0 or n == 1:
        return Decimal128.from_words(0x1, 0x0, 0x0, 0x0)  # 1
    elif n == 2:
        return Decimal128.from_words(0x5, 0x0, 0x0, 0x10000)  # 0.5
    elif n == 3:
        return Decimal128.from_words(
            0x82AAAAAB, 0xA5B8065, 0x562A265, 0x1C0000
        )  # 0.1666...
    elif n == 4:
        return Decimal128.from_words(
            0x60AAAAAB, 0x4296E019, 0x158A899, 0x1C0000
        )  # 0.0416...
    elif n == 5:
        return Decimal128.from_words(
            0x13555555, 0xD516005, 0x44EE85, 0x1C0000
        )  # 0.0083...
    elif n == 6:
        return Decimal128.from_words(
            0x2DE38E39, 0x2CE2E556, 0xB7D16, 0x1C0000
        )  # 0.0013...
    elif n == 7:
        return Decimal128.from_words(
            0xE1FBEFBF, 0xBD44FC30, 0x1A427, 0x1C0000
        )  # 0.0001...
    elif n == 8:
        return Decimal128.from_words(
            0x1C3F7DF8, 0xF7A89F86, 0x3484, 0x1C0000
        )  # 0.0000248...
    elif n == 9:
        return Decimal128.from_words(
            0xCA3FF18D, 0xE2A0F547, 0x5D5, 0x1C0000
        )  # 0.0000027...
    elif n == 10:
        return Decimal128.from_words(
            0x94399828, 0x63767EED, 0x95, 0x1C0000
        )  # 0.00000027...
    elif n == 11:
        return Decimal128.from_words(
            0xB06253A7, 0x94ADAE72, 0xD, 0x1C0000
        )  # 0.000000025...
    elif n == 12:
        return Decimal128.from_words(
            0xE40831A3, 0x21B923DE, 0x1, 0x1C0000
        )  # 0.0000000020...
    elif n == 13:
        return Decimal128.from_words(
            0x4C9E2B34, 0x16495187, 0x0, 0x1C0000
        )  # 0.0000000001...
    elif n == 14:
        return Decimal128.from_words(
            0xCE9D955F, 0x19785D2, 0x0, 0x1C0000
        )  # 0.00000000001...
    elif n == 15:
        return Decimal128.from_words(
            0xDC63D28, 0x1B2B0E, 0x0, 0x1C0000
        )  # 0.0000000000007...
    elif n == 16:
        return Decimal128.from_words(
            0xE0DC63D3, 0x1B2B0, 0x0, 0x1C0000
        )  # 0.00000000000004...
    elif n == 17:
        return Decimal128.from_words(
            0xEF1C05DF, 0x1991, 0x0, 0x1C0000
        )  # 0.000000000000002...
    elif n == 18:
        return Decimal128.from_words(
            0xA9BA721B, 0x16B, 0x0, 0x1C0000
        )  # 0.0000000000000001...
    elif n == 19:
        return Decimal128.from_words(
            0x23E16452, 0x13, 0x0, 0x1C0000
        )  # 0.0000000000000000082...
    elif n == 20:
        return Decimal128.from_words(
            0xF4FE7837, 0x0, 0x0, 0x1C0000
        )  # 0.0000000000000000004...
    elif n == 21:
        return Decimal128.from_words(
            0xBAA9803, 0x0, 0x0, 0x1C0000
        )  # 0.0000000000000000000195...
    elif n == 22:
        return Decimal128.from_words(
            0x87C117, 0x0, 0x0, 0x1C0000
        )  # 0.0000000000000000000008...
    elif n == 23:
        return Decimal128.from_words(
            0x5E701, 0x0, 0x0, 0x1C0000
        )  # 0.0000000000000000000000386...
    elif n == 24:
        return Decimal128.from_words(
            0x3EF5, 0x0, 0x0, 0x1C0000
        )  # 0.0000000000000000000000016...
    elif n == 25:
        return Decimal128.from_words(
            0x285, 0x0, 0x0, 0x1C0000
        )  # 0.0000000000000000000000000645
    elif n == 26:
        return Decimal128.from_words(
            0x19, 0x0, 0x0, 0x1C0000
        )  # 0.0000000000000000000000000025
    else:  # n == 27
        return Decimal128.from_words(
            0x1, 0x0, 0x0, 0x1C0000
        )  # 0.0000000000000000000000000001
