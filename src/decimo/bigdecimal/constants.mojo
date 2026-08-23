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
# Implements functions for calculating common constants.
"""

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.errors import ValueError
from decimo.bigint.bigint import BigInt
from decimo.biguint.biguint import BigUInt
from decimo.rounding_mode import RoundingMode
import decimo.bigdecimal.trigonometric as bigdecimal_trigonometric

comptime PI_1024 = BigDecimal(
    coefficient=BigUInt(
        raw_words=[
            UInt32(858632789),
            UInt32(572010654),
            UInt32(989380952),
            UInt32(92164201),
            UInt32(766111959),
            UInt32(130019278),
            UInt32(712268066),
            UInt32(577805321),
            UInt32(519577818),
            UInt32(537875937),
            UInt32(628638823),
            UInt32(687311595),
            UInt32(904287554),
            UInt32(35982534),
            UInt32(776691473),
            UInt32(814206171),
            UInt32(875332083),
            UInt32(387528865),
            UInt32(100031378),
            UInt32(311881710),
            UInt32(850352619),
            UInt32(82533446),
            UInt32(26425223),
            UInt32(553469083),
            UInt32(950244594),
            UInt32(160963185),
            UInt32(597317328),
            UInt32(780499510),
            UInt32(999983729),
            UInt32(72113499),
            UInt32(99605187),
            UInt32(297747713),
            UInt32(181598136),
            UInt32(608640344),
            UInt32(121290219),
            UInt32(420199561),
            UInt32(892589235),
            UInt32(507922796),
            UInt32(495853710),
            UInt32(534301465),
            UInt32(409012249),
            UInt32(787214684),
            UInt32(91736371),
            UInt32(427577896),
            UInt32(277857713),
            UInt32(452635608),
            UInt32(5681271),
            UInt32(694051320),
            UInt32(748184676),
            UInt32(767523846),
            UInt32(171762931),
            UInt32(27705392),
            UInt32(798609437),
            UInt32(371907021),
            UInt32(463952247),
            UInt32(860213949),
            UInt32(406566430),
            UInt32(336733624),
            UInt32(119491298),
            UInt32(279381830),
            UInt32(527248912),
            UInt32(673518857),
            UInt32(799627495),
            UInt32(480744623),
            UInt32(931051185),
            UInt32(819326117),
            UInt32(921861173),
            UInt32(595919530),
            UInt32(572703657),
            UInt32(116094330),
            UInt32(469519415),
            UInt32(665213841),
            UInt32(305488204),
            UInt32(600113305),
            UInt32(678925903),
            UInt32(917153643),
            UInt32(628292540),
            UInt32(815209209),
            UInt32(155881748),
            UInt32(870066063),
            UInt32(412737245),
            UInt32(72602491),
            UInt32(482133936),
            UInt32(104543266),
            UInt32(234603486),
            UInt32(456485669),
            UInt32(712019091),
            UInt32(867831652),
            UInt32(756482337),
            UInt32(334461284),
            UInt32(109756659),
            UInt32(819644288),
            UInt32(489549303),
            UInt32(596446229),
            UInt32(385211055),
            UInt32(841027019),
            UInt32(811174502),
            UInt32(594081284),
            UInt32(822317253),
            UInt32(446095505),
            UInt32(66470938),
            UInt32(865132823),
            UInt32(679821480),
            UInt32(253421170),
            UInt32(986280348),
            UInt32(62862089),
            UInt32(923078164),
            UInt32(209749445),
            UInt32(993751058),
            UInt32(841971693),
            UInt32(832795028),
            UInt32(384626433),
            UInt32(535897932),
            UInt32(31415926),
        ],
    ),
    scale=1024,
    sign=False,
)
"""Pi to 1024 digits of precision."""


# TODO: When Mojo support global variables,
# we save the value of π to a certain precision in the global scope.
# This will allow us to use it everywhere without recalculating it
# if the required precision is the same or lower.
# Everytime when user calls pi(precision),
# we check whether the precision is higher than the current precision.
# If yes, then we save it into the global scope as cached value.
def pi(precision: Int) raises -> BigDecimal:
    """Calculates π using the fastest available algorithm.

    Args:
        precision: The number of significant digits to compute.

    Returns:
        The value of π to the specified precision.

    Raises:
        ValueError: If the precision is negative.
    """

    if precision < 0:
        raise ValueError(
            message="Precision must be non-negative", function="pi()"
        )

    # TODO: When global variables are supported,
    # we can check if we have a cached value for the requested precision.
    # if precision <= 1024:
    #     var result = PI_1024
    #     result.round_to_precision_inplace(
    #         precision,
    #         RoundingMode.ROUND_HALF_EVEN,
    #         remove_extra_digit_due_to_rounding=True,
    #         fill_zeros_to_precision=False,
    #     )
    #     return result^

    # Use Chudnovsky with binary splitting for maximum speed
    return pi_chudnovsky_binary_split(precision)


struct _ChudnovskyPartialSum:
    """Partial sum of the Chudnovsky series over a range, in `P`/`Q`/`T` form.

    Binary splitting a hypergeometric series carries three integers per range
    `[a, b)` rather than one fraction. Writing the ratio of consecutive terms
    as `-P(k)/Q(k)` with

    - `P(k) = (6k-5)(2k-1)(6k-1)`,
    - `Q(k) = k^3 * 640320^3 / 24`,

    the three values for a range are the two running products and the sum:

    - `p` is `P(a+1) * ... * P(b-1)`,
    - `q` is `Q(a+1) * ... * Q(b-1)`,
    - `t` is chosen so that the partial sum over `[a, b)` equals `t / q`.

    Carrying `p` as well as `q` is what makes the leaves O(1). The previous
    formulation stored each term as an already-evaluated fraction, so every
    leaf `k` had to rebuild `(6k)!/(3k)!`, `(k!)^3` and `C^k` from scratch -
    O(k) big-integer multiplications per leaf, O(n^2) over the whole tree, and
    a `q` that was the *product* of all the individual denominators. Here those
    factors telescope through `combine()` instead: `q` at the root is the
    denominator of a single term rather than the product of `n` of them, which
    is the difference between O(n^2 log n) and O(n log n) bits at the top.

    Note on reduction: `combine()` deliberately does no cancelling. Scaling all
    three fields of a subrange by a common factor does propagate correctly
    (the recurrence is homogeneous of degree one in each child), so the common
    powers of two that the old `_UnreducedFraction.combine()` divided out
    *could* be divided out here - but `p` is a product of odd numbers and is
    therefore always odd, so the common factor is always one. There is nothing
    left to strip.
    """

    var p: BigInt
    """The running product of the term-ratio numerators over the range."""
    var q: BigInt
    """The running product of the term-ratio denominators over the range."""
    var t: BigInt
    """The partial sum over the range, scaled by `q`."""

    def __init__(out self, var p: BigInt, var q: BigInt, var t: BigInt):
        """Initializes a partial sum from its three components.

        Args:
            p: The running product of the term-ratio numerators.
            q: The running product of the term-ratio denominators.
            t: The partial sum over the range, scaled by `q`.
        """
        self.p = p^
        self.q = q^
        self.t = t^

    @staticmethod
    def combine(left: Self, right: Self) raises -> Self:
        """Joins the partial sums of two adjacent ranges.

        With `left` covering `[a, m)` and `right` covering `[m, b)`, the sum
        over `[a, b)` is `left.t / left.q + (left.p / left.q) * right.t /
        right.q`, which clears denominators to the three products below. Four
        big-integer multiplications per node, none of them growing faster than
        the operands themselves.

        Args:
            left: The partial sum over the lower half of the range.
            right: The partial sum over the upper half of the range.

        Returns:
            The partial sum over the union of the two ranges.
        """
        var p = left.p * right.p
        var q = left.q * right.q
        var t = left.t * right.q + left.p * right.t
        return Self(p^, q^, t^)


def pi_chudnovsky_binary_split(precision: Int) raises -> BigDecimal:
    """Calculates π using Chudnovsky algorithm with binary splitting.

    Notes:

    Use the formula:
    π = 426880 * √10005 / Σ(k=0 to ∞) [M(k) * L(k) / X(k)],
    where:
    (1) M(k) = (6k)! / ((3k)! * (k!)³)
    (2) L(k) = 545140134*k + 13591409
    (3) X(k) = (-262537412640768000)^k

    The series is evaluated with the `P`/`Q`/`T` binary splitting recurrence
    (see `_ChudnovskyPartialSum`), which never forms `M(k)` or `X(k)` for any
    individual `k`: the sum over the whole range comes back as the single exact
    fraction `T / Q`, and π = 426880 * √10005 * Q / T.

    Args:
        precision: The number of significant digits to compute.

    Returns:
        The value of π to the specified precision.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """

    var working_precision = precision + 9  # 1 words
    var iterations = (
        precision // 14
    ) + 9  # ~14.18 digits per iteration + safety margin

    var bdec_10005 = BigDecimal.from_raw_components(UInt32(10005))
    var bdec_426880 = BigDecimal.from_raw_components(UInt32(426880))

    # Binary splitting to compute the series sum as a single rational number
    var series = chudnovsky_split(0, iterations)

    # Convert rational result to BigDecimal: q/t.
    #
    # Binary splitting hands back two operands of tens of thousands of digits,
    # of which only `working_precision` survive the division. Shifting both by
    # the same number of bits leaves the ratio unchanged to within a relative
    # error of 2^-guard_bits, and keeps the base-2^32 to base-10^9 conversion
    # proportional to the digits actually wanted rather than to the digits the
    # splitting happened to produce.
    var guard_bits = (working_precision + 32) * 10 // 3  # 10/3 > log2(10)
    var shared_bits = min(series.q.bit_length(), series.t.bit_length())
    var numerator = series.q.copy()
    var denominator = series.t.copy()
    if shared_bits > guard_bits:
        var shift = shared_bits - guard_bits
        numerator = numerator >> shift
        denominator = denominator >> shift

    var sum_series = BigDecimal(numerator).true_divide(
        BigDecimal(denominator), working_precision
    )

    # Final formula: π = 426880 * √10005 * (q / t)
    var result = bdec_426880.multiply(
        bdec_10005.sqrt(working_precision)
    ).multiply(sum_series)

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def chudnovsky_split(a: Int, b: Int) raises -> _ChudnovskyPartialSum:
    """Conducts binary splitting for Chudnovsky series from term a to b-1.

    Args:
        a: The start index of the splitting range (inclusive).
        b: The end index of the splitting range (exclusive).

    Returns:
        A `_ChudnovskyPartialSum` holding the partial sum over `[a, b)`.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """

    if b - a == 1:
        # Base case. Everything here is O(1): a handful of multiplications of
        # machine-sized values, no factorials and no powers.
        if a == 0:
            # P(0) and Q(0) are empty products; the sum is just L(0).
            return _ChudnovskyPartialSum(BigInt(1), BigInt(1), BigInt(13591409))

        # P(a) = (6a-5) * (2a-1) * (6a-1). Built out of `BigInt` rather than
        # `Int` so that the product cannot overflow for very large `a`.
        var p = BigInt(6 * a - 5) * BigInt(2 * a - 1) * BigInt(6 * a - 1)

        # Q(a) = a^3 * 640320^3 / 24, and 640320^3 / 24 = 10939058860032000.
        var bint_a = BigInt(a)
        var q = bint_a * bint_a * bint_a * BigInt(10939058860032000)

        # T(a) = (-1)^a * P(a) * L(a), with L(a) = 545140134*a + 13591409.
        var l = BigInt(545140134) * bint_a + BigInt(13591409)
        var t = p * l
        if a % 2 == 1:
            t = -t

        return _ChudnovskyPartialSum(p^, q^, t^)

    # Recursive case: split range in half
    var mid = (a + b) // 2
    var left = chudnovsky_split(a, mid)
    var right = chudnovsky_split(mid, b)

    return _ChudnovskyPartialSum.combine(left, right)


def pi_machin(precision: Int) raises -> BigDecimal:
    """Fallback π calculation using Machin's formula.

    Args:
        precision: The number of significant digits to compute.

    Returns:
        The value of π to the specified precision.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """

    var working_precision = precision + 9

    var bdec_1 = BigDecimal.from_raw_components(UInt32(1))
    var bdec_4 = BigDecimal.from_raw_components(UInt32(4))
    var bdec_5 = BigDecimal.from_raw_components(UInt32(5))
    var bdec_239 = BigDecimal.from_raw_components(UInt32(239))

    # Calculate 4 * arctan(1/5)
    var one_fifth = bdec_1.true_divide(bdec_5, working_precision)
    var term1 = bdec_4.multiply(
        bigdecimal_trigonometric.arctan_taylor_series(
            one_fifth, working_precision
        )
    )

    # Calculate arctan(1/239)
    var one_239 = bdec_1.true_divide(bdec_239, working_precision)
    var term2 = bigdecimal_trigonometric.arctan_taylor_series(
        one_239, working_precision
    )

    # π/4 = 4*arctan(1/5) - arctan(1/239)
    var pi_over_4 = term1.subtract(term2)
    var result = bdec_4.multiply(pi_over_4)

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^
