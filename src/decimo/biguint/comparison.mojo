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
Implements functions for comparison operations on BigUInt objects.
"""

from decimo.biguint.biguint import BigUInt


def compare(x1: BigUInt, x2: BigUInt) -> Int8:
    """Compares the values of two unsigned integers and returns the result.

    Args:
        x1: First unsigned integer.
        x2: Second unsigned integer.

    Returns:
        Terinary value indicating the comparison result:
        (1)  1 if x1 > x2.
        (2)  0 if x1 = x2.
        (3) -1 if x1 < x2.
    """
    debug_assert[assert_mode="none"](
        (len(x1.words) == 1) or (x1.words[-1] != 0),
        "biguint.comparison.compare(): ",
        "BigUInt x1 contains leading zero words.",
    )
    debug_assert[assert_mode="none"](
        (len(x2.words) == 1) or (x2.words[-1] != 0),
        "biguint.comparison.compare(): ",
        "BigUInt x2 contains leading zero words.",
    )

    # Compare the number of words
    if len(x1.words) > len(x2.words):
        # for i in range(len(x2.words), len(x1.words)):
        #     # Check if the extra words in x1 are non-zero
        #     if x1.words[i] != 0:
        return Int8(1)
    if len(x1.words) < len(x2.words):
        # for i in range(len(x1.words), len(x2.words)):
        #     # Check if the extra words in x2 are non-zero
        #     if x2.words[i] != 0:
        return Int8(-1)

    # If the number of words that are not leading zeros are equal,
    # compare the words from the most significant to the least significant.
    var ith = min(len(x1.words), len(x2.words)) - 1
    while ith >= 0:
        if x1.words[ith] > x2.words[ith]:
            return Int8(1)
        if x1.words[ith] < x2.words[ith]:
            return Int8(-1)
        ith -= 1

    # All words are equal
    return Int8(0)


def greater(x1: BigUInt, x2: BigUInt) -> Bool:
    """Checks if the first number is greater than the second.

    Args:
        x1: First unsigned integer.
        x2: Second unsigned integer.

    Returns:
        True if x1 > x2, False otherwise.
    """
    return compare(x1, x2) > 0


def greater_equal(x1: BigUInt, x2: BigUInt) -> Bool:
    """Checks if the first number is greater than or equal to the second.

    Args:
        x1: First unsigned integer.
        x2: Second unsigned integer.

    Returns:
        True if x1 >= x2, False otherwise.
    """
    return compare(x1, x2) >= 0


def less(x1: BigUInt, x2: BigUInt) -> Bool:
    """Checks if the first number is less than the second.

    Args:
        x1: First unsigned integer.
        x2: Second unsigned integer.

    Returns:
        True if x1 < x2, False otherwise.
    """
    return compare(x1, x2) < 0


def less_equal(x1: BigUInt, x2: BigUInt) -> Bool:
    """Checks if the first number is less than or equal to the second.

    Args:
        x1: First unsigned integer.
        x2: Second unsigned integer.

    Returns:
        True if x1 <= x2, False otherwise.
    """
    return compare(x1, x2) <= 0


def equal(x1: BigUInt, x2: BigUInt) -> Bool:
    """Checks if two numbers are equal.

    Args:
        x1: First unsigned integer.
        x2: Second unsigned integer.

    Returns:
        True if x1 == x2, False otherwise.
    """
    return compare(x1, x2) == 0


def not_equal(x1: BigUInt, x2: BigUInt) -> Bool:
    """Checks if two numbers are not equal.

    Args:
        x1: First unsigned integer.
        x2: Second unsigned integer.

    Returns:
        True if x1 != x2, False otherwise.
    """
    return compare(x1, x2) != 0
