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
Implements functions for comparison operations on BigInt10 objects.
"""

from decimo.bigint10.bigint10 import BigInt10
from decimo.biguint.biguint import BigUInt


def compare_magnitudes(x1: BigInt10, x2: BigInt10) -> Int8:
    """Compares the magnitudes of two numbers and returns the result.

    Args:
        x1: First number.
        x2: Second number.

    Returns:
        Ternary value indicating the comparison result:
        (1)  1 if |x1| > |x2|.
        (2)  0 if |x1| = |x2|.
        (3) -1 if |x1| < |x2|.
    """
    return x1.magnitude.compare(x2.magnitude)


def compare(x1: BigInt10, x2: BigInt10) -> Int8:
    """Compares two BigInt10 objects and returns the result.

    Args:
        x1: First number.
        x2: Second number.

    Returns:
        Ternary value indicating the comparison result:
        (1)  1 if x1 > x2.
        (2)  0 if x1 = x2.
        (3) -1 if x1 < x2.
    """
    if x1.is_zero() and x2.is_zero():
        return 0

    # Different signs: negative < positive
    if x1.sign != x2.sign:
        return Int8(-1) if x1.sign else Int8(1)

    # Same signs: compare magnitudes
    var magnitude_comparison = compare_magnitudes(x1, x2)

    # If both negative, reverse the comparison result
    return magnitude_comparison if not x1.sign else -magnitude_comparison


def greater(x1: BigInt10, x2: BigInt10) -> Bool:
    """Checks if the first number is greater than the second.

    Args:
        x1: First signed integer.
        x2: Second signed integer.

    Returns:
        True if x1 > x2, False otherwise.
    """
    return compare(x1, x2) > 0


def greater_equal(x1: BigInt10, x2: BigInt10) -> Bool:
    """Checks if the first number is greater than or equal to the second.

    Args:
        x1: First signed integer.
        x2: Second signed integer.

    Returns:
        True if x1 >= x2, False otherwise.
    """
    return compare(x1, x2) >= 0


def less(x1: BigInt10, x2: BigInt10) -> Bool:
    """Checks if the first number is less than the second.

    Args:
        x1: First signed integer.
        x2: Second signed integer.

    Returns:
        True if x1 < x2, False otherwise.
    """
    return compare(x1, x2) < 0


def less_equal(x1: BigInt10, x2: BigInt10) -> Bool:
    """Checks if the first number is less than or equal to the second.

    Args:
        x1: First signed integer.
        x2: Second signed integer.

    Returns:
        True if x1 <= x2, False otherwise.
    """
    return compare(x1, x2) <= 0


def equal(x1: BigInt10, x2: BigInt10) -> Bool:
    """Checks if two numbers are equal.

    Args:
        x1: First signed integer.
        x2: Second signed integer.

    Returns:
        True if x1 == x2, False otherwise.
    """
    return compare(x1, x2) == 0


def not_equal(x1: BigInt10, x2: BigInt10) -> Bool:
    """Checks if two numbers are not equal.

    Args:
        x1: First signed integer.
        x2: Second signed integer.

    Returns:
        True if x1 != x2, False otherwise.
    """
    return compare(x1, x2) != 0
