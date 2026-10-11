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


"""Implements the Chudnovsky series for pi, split binarily over integers.

The series is all integer arithmetic, and both decimal and binary ask for it,
so it lives here rather than in either of them. What comes back is the exact
fraction `T / Q` over a range of terms; the caller scales it into whatever
base it keeps its digits in and multiplies by the irrational factor.

Nothing here is specific to a precision. The caller decides how many terms it
needs -- each is worth 14.18 digits -- and the splitting is over that range.
"""

from decimo.bigint.bigint import BigInt, Magnitude


struct ChudnovskyPartialSum:
    """Partial sum of the Chudnovsky series over a range, in `P`/`Q`/`T` form.

    Binary splitting a hypergeometric series carries three integers per range
    `[a, b)` rather than one fraction. Writing the ratio of consecutive terms
    as `-P(k)/Q(k)` with

    - `P(k) = (6k-5)(2k-1)(6k-1)`,
    - `Q(k) = k^3 * 640320^3 / 24`,

    the three values for a range are the two running products and the sum:

    - `p` is `P(a) * ... * P(b-1)`,
    - `q` is `Q(a) * ... * Q(b-1)`,
    - `t` is chosen so that the partial sum over `[a, b)` equals `t / q`.

    Index `0` has no predecessor to form a ratio with, so `P(0)` and `Q(0)`
    are taken to be `1` and the leaf at `0` contributes `t = L(0)` alone.

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

        Raises:
            Error: Propagated from the arithmetic.
        """
        var p = left.p * right.p
        var q = left.q * right.q
        var t = left.t * right.q + left.p * right.t
        return Self(p^, q^, t^)


comptime CHUDNOVSKY_LEAF_LIMIT = 4_000_000
"""Largest term index whose Chudnovsky leaf values still fit in a `UInt128`.

The largest of the three is `T(k) = P(k) * L(k)`, which grows like
`3.9e10 * k^4` and crosses `2^128` just above `k = 5.4e6`; `Q(k)`, growing like
`1.1e16 * k^3`, does not cross until `k = 3.1e7`. Four million leaves leaves a
comfortable margin and covers precisions up to about 56 million digits. Beyond
it the leaves fall back to `BigInt` arithmetic, which cannot overflow.
"""


def _from_uint128(value: UInt128, sign: Bool) -> BigInt:
    """Packs a machine-sized magnitude and a sign into a `BigInt`.

    Args:
        value: The magnitude, as an unsigned 128-bit integer.
        sign: `True` if the result is negative.

    Returns:
        The corresponding `BigInt`.
    """
    var words = Magnitude(capacity=2)
    var remaining = value
    while remaining != 0:
        words.append(UInt64(remaining))
        remaining >>= UInt128(64)
    if len(words) == 0:
        words.append(UInt64(0))
    return BigInt(raw_words=words^, sign=sign)


def chudnovsky_split_dropping_p(a: Int, b: Int) raises -> Tuple[BigInt, BigInt]:
    """Binary splitting over `[a, b)`, returning only `Q` and `T`.

    The root of the evaluation reads `left.p`, `left.q`, `left.t`, `right.q`
    and `right.t` - never `right.p`. Letting the right subtree build it anyway
    costs one multiplication of two half-width operands, which at 100 000
    digits is around 1.3 ms.

    The same argument then applies to that subtree's own right child, and so
    on down the right spine, so this recurses into itself rather than into
    `chudnovsky_split`. The left child still needs its `p`.

    Args:
        a: The start index of the splitting range (inclusive).
        b: The end index of the splitting range (exclusive).

    Returns:
        `(Q, T)` over `[a, b)`.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """
    if b - a <= 1:
        # A single leaf is a handful of words; copying it out is free, and
        # moving a field out of the struct would leave it undestroyable.
        var leaf = chudnovsky_split(a, b)
        return (leaf.q.copy(), leaf.t.copy())

    var mid = (a + b) // 2
    var left = chudnovsky_split(a, mid)
    var right = chudnovsky_split_dropping_p(mid, b)
    var q = left.q * right[0]
    var t = left.t * right[0] + left.p * right[1]
    return (q^, t^)


def chudnovsky_split(a: Int, b: Int) raises -> ChudnovskyPartialSum:
    """Conducts binary splitting for Chudnovsky series from term a to b-1.

    Args:
        a: The start index of the splitting range (inclusive).
        b: The end index of the splitting range (exclusive).

    Returns:
        A `ChudnovskyPartialSum` holding the partial sum over `[a, b)`.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """

    if b - a == 1:
        # Base case. Everything here is O(1): a handful of multiplications of
        # machine-sized values, no factorials and no powers.
        if a == 0:
            # P(0) and Q(0) are empty products; the sum is just L(0).
            return ChudnovskyPartialSum(BigInt(1), BigInt(1), BigInt(13591409))

        if a <= CHUDNOVSKY_LEAF_LIMIT:
            # All three leaf values fit in a `UInt128`, so compute them in
            # machine arithmetic and pack the words directly. Composing them
            # out of `BigInt` operands instead costs about ten small
            # allocations per leaf, and there are `precision / 14` leaves: at
            # 1 000 digits that allocation traffic is half of the entire
            # binary splitting, and still a fifth of it at 10 000 digits.
            var k = UInt128(a)
            var p128 = (
                (UInt128(6) * k - UInt128(5))
                * (UInt128(2) * k - UInt128(1))
                * (UInt128(6) * k - UInt128(1))
            )
            var q128 = k * k * k * UInt128(10939058860032000)
            var l128 = UInt128(545140134) * k + UInt128(13591409)
            return ChudnovskyPartialSum(
                _from_uint128(p128, False),
                _from_uint128(q128, False),
                _from_uint128(p128 * l128, a % 2 == 1),
            )

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

        return ChudnovskyPartialSum(p^, q^, t^)

    # Recursive case: split range in half
    var mid = (a + b) // 2
    var left = chudnovsky_split(a, mid)
    var right = chudnovsky_split(mid, b)

    return ChudnovskyPartialSum.combine(left, right)
