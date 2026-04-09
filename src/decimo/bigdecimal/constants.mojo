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
"""
# Implements functions for calculating common constants.
"""

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.errors import ValueError
from decimo.bigint10.bigint10 import BigInt10
from decimo.rounding_mode import RoundingMode

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
    """

    if precision < 0:
        raise ValueError(
            message="Precision must be non-negative", function="pi()"
        )

    # TODO: When global variables are supported,
    # we can check if we have a cached value for the requested precision.
    # if precision <= 1024:
    #     var result = PI_1024
    #     result.round_to_precision(
    #         precision,
    #         RoundingMode.ROUND_HALF_EVEN,
    #         remove_extra_digit_due_to_rounding=True,
    #         fill_zeros_to_precision=False,
    #     )
    #     return result^

    # Use Chudnovsky with binary splitting for maximum speed
    return pi_chudnovsky_binary_split(precision)


struct Rational:
    """Represents a rational number p/q for exact arithmetic."""

    var p: BigInt10  # numerator
    """The numerator of the rational number."""
    var q: BigInt10  # denominator
    """The denominator of the rational number."""

    def __init__(out self, p: BigInt10, q: BigInt10):
        """Initializes a rational number from a numerator and denominator.

        Args:
            p: The numerator.
            q: The denominator.
        """
        self.p = p.copy()
        self.q = q.copy()


def pi_chudnovsky_binary_split(precision: Int) raises -> BigDecimal:
    """Calculates π using Chudnovsky algorithm with binary splitting.

    Notes:

    Use the formula:
    π = 426880 * √10005 / Σ(k=0 to ∞) [M(k) * L(k) / X(k)],
    where:
    (1) M(k) = (6k)! / ((3k)! * (k!)³)
    (2) L(k) = 545140134*k + 13591409
    (3) X(k) = (-262537412640768000)^k

    Args:
        precision: The number of significant digits to compute.

    Returns:
        The value of π to the specified precision.
    """

    var working_precision = precision + 9  # 1 words
    var iterations = (
        precision // 14
    ) + 9  # ~14.18 digits per iteration + safety margin

    var bdec_10005 = BigDecimal.from_raw_components(UInt32(10005))
    var bdec_426880 = BigDecimal.from_raw_components(UInt32(426880))

    # Binary splitting to compute the series sum as a single rational number
    var result_fraction = chudnovsky_split(0, iterations, working_precision)

    # Convert rational result to BigDecimal: q/p
    var sum_series = BigDecimal(result_fraction.q).true_divide(
        BigDecimal(result_fraction.p), working_precision
    )

    # Final formula: π = 426880 * √10005 / sum_series
    var result = bdec_426880 * bdec_10005.sqrt(working_precision) * sum_series

    result.round_to_precision(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def chudnovsky_split(a: Int, b: Int, precision: Int) raises -> Rational:
    """Conducts binary splitting for Chudnovsky series from term a to b-1.

    Args:
        a: The start index of the splitting range (inclusive).
        b: The end index of the splitting range (exclusive).
        precision: The working precision for intermediate calculations.

    Returns:
        A `Rational` representing the partial sum of the Chudnovsky series.
    """

    var bint_1 = BigInt10(1)
    var bint_13591409 = BigInt10(13591409)
    var bint_545140134 = BigInt10(545140134)
    var bint_262537412640768000 = BigInt10(262537412640768000)

    if b - a == 1:
        # Base case: compute single term as exact rational
        if a == 0:
            # Special case for k=0: M(0)=1, L(0)=13591409, X(0)=1
            return Rational(bint_13591409, bint_1)

        # For k > 0: compute M(k), L(k), X(k)
        var m_k_rational = compute_m_k_rational(a)
        var l_k = bint_545140134 * BigInt10(a) + bint_13591409

        # X(k) = (-262537412640768000)^k
        var x_k = bint_1^
        for _ in range(a):
            x_k *= bint_262537412640768000

        # Apply sign: (-1)^k
        if a % 2 == 1:
            x_k = -x_k

        # Term = M(k) * L(k) / X(k) = (m_k_p * l_k) / (m_k_q * x_k)
        var term_p = m_k_rational.p * l_k
        var term_q = m_k_rational.q * x_k

        return Rational(term_p^, term_q^)

    # Recursive case: split range in half
    var mid = (a + b) // 2
    var left = chudnovsky_split(a, mid, precision)
    var right = chudnovsky_split(mid, b, precision)

    # Combine fractions: left.p/left.q + right.p/right.q
    var combined_p = left.p * right.q + right.p * left.q
    var combined_q = left.q * right.q

    return Rational(combined_p^, combined_q^)


def compute_m_k_rational(k: Int) raises -> Rational:
    """Computes M(k) = (6k)! / ((3k)! * (k!)³) as exact rational.

    Args:
        k: The term index in the Chudnovsky series.

    Returns:
        A `Rational` with numerator (6k)!/(3k)! and denominator (k!)³.
    """

    var bint_1 = BigInt10(1)

    if k == 0:
        return Rational(bint_1, bint_1)

    # Compute numerator: (6k)! / (3k)! = (3k+1) * (3k+2) * ... * (6k)
    var numerator = bint_1.copy()
    for i in range(3 * k + 1, 6 * k + 1):
        numerator *= BigInt10(i)

    # Compute denominator: (k!)³
    var k_factorial = bint_1.copy()
    for i in range(1, k + 1):
        k_factorial *= BigInt10(i)

    var denominator = k_factorial * k_factorial * k_factorial

    return Rational(numerator, denominator)


def pi_machin(precision: Int) raises -> BigDecimal:
    """Fallback π calculation using Machin's formula.

    Args:
        precision: The number of significant digits to compute.

    Returns:
        The value of π to the specified precision.
    """

    var working_precision = precision + 9

    var bdec_1 = BigDecimal.from_raw_components(UInt32(1))
    var bdec_4 = BigDecimal.from_raw_components(UInt32(4))
    var bdec_5 = BigDecimal.from_raw_components(UInt32(5))
    var bdec_239 = BigDecimal.from_raw_components(UInt32(239))

    # Calculate 4 * arctan(1/5)
    var one_fifth = bdec_1.true_divide(bdec_5, working_precision)
    var term1 = bdec_4 * decimo.bigdecimal.trigonometric.arctan_taylor_series(
        one_fifth, working_precision
    )

    # Calculate arctan(1/239)
    var one_239 = bdec_1.true_divide(bdec_239, working_precision)
    var term2 = decimo.bigdecimal.trigonometric.arctan_taylor_series(
        one_239, working_precision
    )

    # π/4 = 4*arctan(1/5) - arctan(1/239)
    var pi_over_4 = term1 - term2
    var result = bdec_4 * pi_over_4

    result.round_to_precision(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^
