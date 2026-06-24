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
#
# Implements special functions for the BigInt type
#
# ===----------------------------------------------------------------------=== #

"""Implements functions for special operations on BigInt objects."""

from decimo.bigint.bigint import BigInt
from decimo.errors import ValueError

# Largest argument accepted by `factorial`. 10^9 already needs ~10^9
# multiplications and produces a result with billions of digits, so anything
# beyond it is computationally infeasible. The cap also keeps the value within
# Mojo's `Int` range, so an out-of-range argument raises a clear error
# instead of an `Int` overflow.
comptime FACTORIAL_MAX_INPUT = 1_000_000_000


def factorial(x: BigInt) raises -> BigInt:
    """Calculates the factorial of a non-negative integer value.

    Args:
        x: The non-negative integer value to take the factorial of.

    Returns:
        `x!`, the product of all positive integers up to `x` (`0! == 1`).

    Raises:
        ValueError: If `x` is negative or larger than `FACTORIAL_MAX_INPUT`
            (10^9).

    Notes:

    The value must currently fit in a Mojo `Int`. Arbitrarily large
    arguments will be supported later.
    """
    if x < BigInt.zero():
        raise ValueError(
            message="Factorial is not defined for negative numbers.",
            function="factorial()",
        )
    if x > BigInt(FACTORIAL_MAX_INPUT):
        raise ValueError(
            message=(
                "Factorial argument is too large to compute (must be <= 10^9)."
            ),
            function="factorial()",
        )

    var n = Int(x)
    var result = BigInt.one()
    for i in range(2, n + 1):
        result *= BigInt(i)
    return result^
