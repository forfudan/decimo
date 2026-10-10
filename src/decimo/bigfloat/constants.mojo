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


"""Pi, the natural logarithms of two and of ten, and Euler's number, in binary.

Each is computed rather than quoted, by a series whose terms are integers in
a fixed-point scale of two. Working in integers is what makes the error
countable: every term is one truncating division, so each costs less than a
unit in the last place of the scale, and the scale carries enough bits beyond
what is asked for to leave the total well under a unit of that.

The series are the classical ones. Pi is Machin's, sixteen arctangents of a
fifth less four of a two-hundred-and-thirty-ninth, which costs about a term
for every five bits. The logarithm of two is twice the inverse hyperbolic
tangent of a third, about a term for every three. The logarithm of ten is
`3 ln 2 + 2 atanh(1/9)`, since `10` is `8 * 5/4` and `atanh(1/9)` is half the
logarithm of `5/4`; the second series costs a term for every six bits, so the
whole constant costs little more than the logarithm of two does. Euler's
number is the sum of the reciprocal factorials, which costs fewer terms than
either because the terms fall away faster.

Each is cached process-wide at the widest width it has been asked for, which
is what keeps the exponential and the logarithm from recomputing the
logarithm of two on every call and at every step of the loop that decides a
rounding.
"""

from std.atomic import Atomic
from std.bit import bit_width
from std.ffi import _Global

from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.exponential import round_by_deciding
from decimo.bigfloat.rounding import checked_precision
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


comptime _CONSTANT_SLACK = 2
"""Units in the last place a constant's kernel may be off by.

Each kernel works in a scale wide enough that the whole series contributes
less than a unit of what it returns, and the one rounding into that width
costs half of one more.
"""


def _series_scale(width: Int) -> Int:
    """How many bits the fixed-point scale carries.

    Args:
        width: The bits wanted in the answer.

    Returns:
        The width plus enough to absorb the series.

    Notes:

    A series of `n` terms, each one truncating division, is off by a few
    units of the scale per term and so by fewer than `3n` in total. A
    truncation costs one unit, and the error already in the running power or
    term is divided down with it at every step -- by `d^2` in the two
    arctangent series, and by `k` in the factorials, which is one for the
    first step and grows from there -- so no term's error reaches three.

    The term count is below the width in all three series, so `3 * width`
    units is a bound, and `bit_width(width) + 8` extra bits of scale leaves
    that below a hundredth of a unit of what is returned.

    Eight and not the dozen `rounding.working_width()` carries, and under a
    different name, because this is not that margin: these series are summed
    in integers, where a term costs one truncation, while a kernel widened by
    that one is absorbing a rounding on every operation.
    """
    return width + Int(bit_width(UInt(width))) + 8


def _arctangent_of_reciprocal(denominator: Int, width: Int) raises -> BigInt:
    """`arctan(1 / denominator)` as an integer scaled by `2^width`.

    Args:
        denominator: The reciprocal's denominator, at least two.
        width: The scale, in bits.

    Returns:
        The scaled value, within a few units of the true one on either side.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The series is `1/d - 1/(3 d^3) + 1/(5 d^5) - ...`, which the running power
    of `1/d^2` walks through. The power is kept apart from the division by the
    odd number so that the two errors do not compound: the power's own error
    is divided by `d^2` at every step and so stays below one unit, and each
    term adds at most one more of its own.

    The bound is two-sided, unlike the hyperbolic one next door. These terms
    alternate, so stopping between two of them can leave the sum above the
    true value as easily as below: at a width of two bits and a denominator
    of two the sum stops after its first term and is above. The callers ask
    for a scale far wider than the answer they keep, so a unit here is
    nothing there, but the claim has to say which way it can go.
    """
    var square = BigInt(denominator * denominator)
    var power = (BigInt.one() << width).truncate_divide(BigInt(denominator))
    var total = power.copy()
    var k = 1
    while True:
        power = power.truncate_divide(square)
        if power.is_zero():
            return total^
        var term = power.truncate_divide(BigInt(2 * k + 1))
        if term.is_zero():
            return total^
        if k & 1 != 0:
            total -= term
        else:
            total += term
        k += 1


def _arctangent_hyperbolic_of_reciprocal(
    denominator: Int, width: Int
) raises -> BigInt:
    """`arctanh(1 / denominator)` as an integer scaled by `2^width`.

    Args:
        denominator: The reciprocal's denominator, at least two.
        width: The scale, in bits.

    Returns:
        The scaled value, below the true one by less than two units.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The same series as the arctangent with every sign positive, which is what
    the hyperbolic one is. Here the bound really is one-sided: every term
    left out is positive and every division truncates, so both errors pull
    the sum the same way, down.
    """
    var square = BigInt(denominator * denominator)
    var power = (BigInt.one() << width).truncate_divide(BigInt(denominator))
    var total = power.copy()
    var k = 1
    while True:
        power = power.truncate_divide(square)
        if power.is_zero():
            return total^
        var term = power.truncate_divide(BigInt(2 * k + 1))
        if term.is_zero():
            return total^
        total += term
        k += 1


def _pi_computed(width: Int) raises -> BigFloat:
    """Pi to `width` bits, by Machin's formula.

    Args:
        width: The bits wanted.

    Returns:
        Pi, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var scale = _series_scale(width)
    var total = BigInt(16) * _arctangent_of_reciprocal(5, scale) - BigInt(
        4
    ) * _arctangent_of_reciprocal(239, scale)
    return BigFloat.from_rounded_parts(total, -scale, width, False)


def _ln2_computed(width: Int) raises -> BigFloat:
    """The natural logarithm of two to `width` bits.

    Args:
        width: The bits wanted.

    Returns:
        The logarithm, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var scale = _series_scale(width)
    var total = BigInt(2) * _arctangent_hyperbolic_of_reciprocal(3, scale)
    return BigFloat.from_rounded_parts(total, -scale, width, False)


def _ln10_computed(width: Int) raises -> BigFloat:
    """The natural logarithm of ten to `width` bits.

    Args:
        width: The bits wanted.

    Returns:
        The logarithm, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    `ln 10` is `3 ln 2 + ln(5/4)`, because ten is eight times five quarters,
    and both logarithms are inverse hyperbolic tangents of a reciprocal:
    `ln 2` is `2 atanh(1/3)` and `ln(5/4)` is `2 atanh(1/9)`. So the whole
    constant is `6 atanh(1/3) + 2 atanh(1/9)`.

    Writing it that way rather than as `ln 2 + ln 5` is what keeps the
    denominators large. A series on a reciprocal of `d` gains `2 log2(d)`
    bits a term, so the ninth costs a term for every six bits where `ln 5`
    taken directly would need an argument of `2/3` and no series at all.

    The two kernels each come in below the true value by less than two units
    of the working scale, so the combination is below by less than sixteen,
    and the scale carries `bit_width(width) + 8` bits beyond what is returned
    -- so those sixteen units are at most a sixteenth of one unit of the last
    place here, and the one rounding on the way out is what the stated bound
    is really for.
    """
    var scale = _series_scale(width)
    var total = BigInt(6) * _arctangent_hyperbolic_of_reciprocal(
        3, scale
    ) + BigInt(2) * _arctangent_hyperbolic_of_reciprocal(9, scale)
    return BigFloat.from_rounded_parts(total, -scale, width, False)


def _e_computed(width: Int) raises -> BigFloat:
    """Euler's number to `width` bits, as the sum of the reciprocal factorials.

    Args:
        width: The bits wanted.

    Returns:
        The number, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var scale = _series_scale(width)
    var term = BigInt.one() << scale
    var total = term.copy()
    var k = 1
    while True:
        term = term.truncate_divide(BigInt(k))
        if term.is_zero():
            return BigFloat.from_rounded_parts(total, -scale, width, False)
        total += term
        k += 1


# ===----------------------------------------------------------------------=== #
# Keeping what was computed
# ===----------------------------------------------------------------------=== #


comptime _CACHE_FLOOR = 256
"""The narrowest width a constant is ever computed at.

A call for 53 bits costs about what a call for 256 costs, and the answer to
the wider one answers every narrower one as well. The loop that decides a
rounding walks a width upward -- 65 bits, then 130, then 260 -- so without a
floor and a doubling it would recompute the constant at every step.
"""


struct _ConstantCache(Movable):
    """The four constants, each held at a wide width and at a narrow one.

    A value held at `w` bits answers any request for `w` or fewer: truncating
    it costs less than a unit in the last place of the narrower width, and a
    kernel is allowed two.

    Truncating is cheap only against the held width, though, so a single
    request for a very wide constant would otherwise make every later narrow
    request walk that whole width. Each constant therefore keeps a second,
    narrow copy, cut from the wide one and wide enough for the narrow
    requests that have come in. Both copies grow and neither shrinks.
    """

    var busy: Atomic[Int64]
    """Nought when no thread is inside the cache."""
    var value: List[BigFloat]
    """Pi, the logarithm of two, the number, and the logarithm of ten.

    The logarithm of ten sits last rather than beside the logarithm of two,
    so that the three slots that were here before keep the indices they had.

    Empty until the first constant is stored, because building a `BigFloat`
    to hold a place can raise and the global's factory cannot.
    """
    var width: List[Int]
    """What each was computed at; nought for one never computed."""
    var narrow: List[BigFloat]
    """The same four, cut down for the narrow requests.

    Empty alongside `value`, and a slot whose `narrow_width` is nought holds
    a placeholder that is never read.
    """
    var narrow_width: List[Int]
    """What each narrow copy was cut to; nought for one never cut."""

    def __init__(out self):
        """An empty cache."""
        self.busy = Atomic[Int64](0)
        self.value = List[BigFloat]()
        self.width = [0, 0, 0, 0]
        self.narrow = List[BigFloat]()
        self.narrow_width = [0, 0, 0, 0]


def _make_constant_cache() -> _ConstantCache:
    """Builds the process-wide cache.

    Returns:
        An empty cache.
    """
    return _ConstantCache()


comptime _SHARED_CONSTANTS = _Global[
    "decimo_bigfloat_constants", _make_constant_cache
]
"""One cache for the whole process.

Mojo has no module-level `var`; `std.ffi._Global` is how this package already
holds process-wide state, both in the decimal layer's `MathCache` and in the
word list's block pool.

A thread that finds the cache busy computes its own answer and does not store
it, which is the block pool's try-lock: correctness never waits on the lock,
only the saving does. That is a deliberate difference from the decimal cache,
which documents itself as unsafe to use from two threads at once.
"""


def _computed(which: Int, width: Int) raises -> BigFloat:
    """One of the four constants, computed rather than remembered.

    Args:
        which: Nought for pi, one for the logarithm of two, two for the
            number, three for the logarithm of ten.
        width: The bits wanted.

    Returns:
        The value, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.
    """
    if which == 0:
        return _pi_computed(width)
    if which == 1:
        return _ln2_computed(width)
    if which == 2:
        return _e_computed(width)
    return _ln10_computed(width)


def _truncated(value: BigFloat, width: Int) raises -> BigFloat:
    """A held constant cut down to a narrower width.

    Args:
        value: The held value, which is positive.
        width: The bits wanted, no more than the value already has.

    Returns:
        The value truncated to `width` bits, which costs less than a unit in
        the last place of that width.

    Raises:
        Error: Propagated from the rounding.

    Notes:

    Truncating twice -- once into the narrow copy, once out of it -- drops
    low bits twice and so lands on the same bits as truncating once, which
    is why a narrow copy answers exactly as the wide one would.
    """
    return BigFloat.from_rounded_parts(
        value.significand,
        value.exponent,
        width,
        False,
        RoundingMode.ROUND_DOWN,
    )


def _narrow_target(width: Int) -> Int:
    """How wide a narrow copy that answers `width` should be cut.

    Args:
        width: The bits asked for.

    Returns:
        The width to cut to, never under `_CACHE_FLOOR` so that the narrow
        copy serves the whole band of small requests.
    """
    var target = width + 64
    if _CACHE_FLOOR > target:
        target = _CACHE_FLOOR
    return target


def _cached(which: Int, width: Int) raises -> BigFloat:
    """One of the four constants, from the cache where the cache has it.

    Args:
        which: Nought for pi, one for the logarithm of two, two for the
            number, three for the logarithm of ten.
        width: The bits wanted.

    Returns:
        The value, within `_CONSTANT_SLACK` units of the last place. A stored
        value is truncated to `width`, which costs less than one of them,
        while the stored value's own error is a unit at a width further out
        and so nothing here.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var cache = _SHARED_CONSTANTS.get_or_create_ptr()
    if cache[].busy.fetch_add(1) != 0:
        _ = cache[].busy.fetch_sub(1)
        return _computed(which, width)

    try:
        if cache[].narrow_width[which] >= width:
            var answer = _truncated(cache[].narrow[which], width)
            _ = cache[].busy.fetch_sub(1)
            return answer^

        if cache[].width[which] >= width:
            var answer = _truncated(cache[].value[which], width)
            var target = _narrow_target(width)
            if target < cache[].width[which]:
                cache[].narrow[which] = _truncated(cache[].value[which], target)
                cache[].narrow_width[which] = target
            _ = cache[].busy.fetch_sub(1)
            return answer^

        var target = _narrow_target(width)
        if cache[].width[which] * 2 > target:
            target = cache[].width[which] * 2
        var fresh = _computed(which, target)
        if len(cache[].value) == 0:
            # The four slots are filled on the first store, since the cache
            # cannot build a placeholder without a precision to build it at.
            var placeholder = _truncated(fresh, _CACHE_FLOOR)
            for _ in range(len(cache[].width)):
                cache[].value.append(fresh.copy())
                cache[].narrow.append(placeholder.copy())
        cache[].value[which] = fresh.copy()
        cache[].width[which] = target
        var answer = _truncated(fresh, width)
        var narrow = _narrow_target(width)
        if narrow < target:
            cache[].narrow[which] = _truncated(fresh, narrow)
            cache[].narrow_width[which] = narrow
        _ = cache[].busy.fetch_sub(1)
        return answer^
    except error:
        _ = cache[].busy.fetch_sub(1)
        raise error


def _pi_kernel(width: Int) raises -> BigFloat:
    """Pi to `width` bits, from the cache where it is there.

    Args:
        width: The bits wanted.

    Returns:
        The value, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.
    """
    return _cached(0, width)


def _ln2_kernel(width: Int) raises -> BigFloat:
    """The natural logarithm of two to `width` bits, from the cache.

    Args:
        width: The bits wanted.

    Returns:
        The value, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.
    """
    return _cached(1, width)


def _ln10_kernel(width: Int) raises -> BigFloat:
    """The natural logarithm of ten to `width` bits, from the cache.

    Args:
        width: The bits wanted.

    Returns:
        The value, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.
    """
    return _cached(3, width)


def _e_kernel(width: Int) raises -> BigFloat:
    """Euler's number to `width` bits, from the cache.

    Args:
        width: The bits wanted.

    Returns:
        The value, within `_CONSTANT_SLACK` units of the last place.

    Raises:
        Error: Propagated from the arithmetic.
    """
    return _cached(2, width)


def pi(
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """Pi, correctly rounded.

    Args:
        precision: The number of bits wanted. Must be positive.
        rounding_mode: How to round.

    Returns:
        The float of `precision` bits nearest pi.

    Raises:
        ValueError: If `precision` is not positive, or above
            `MAX_PRECISION`.
        Error: Propagated from the arithmetic.
    """
    _ = checked_precision(precision, "pi()")
    return round_by_deciding[_pi_kernel, _CONSTANT_SLACK](
        precision, rounding_mode
    )


def ln2(
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The natural logarithm of two, correctly rounded.

    Args:
        precision: The number of bits wanted. Must be positive.
        rounding_mode: How to round.

    Returns:
        The float of `precision` bits nearest the logarithm.

    Raises:
        ValueError: If `precision` is not positive, or above
            `MAX_PRECISION`.
        Error: Propagated from the arithmetic.

    Notes:

    This is the constant the exponential and the logarithm reduce their
    arguments by, so it is the one whose cost will show first.
    """
    _ = checked_precision(precision, "ln2()")
    return round_by_deciding[_ln2_kernel, _CONSTANT_SLACK](
        precision, rounding_mode
    )


def e(
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """Euler's number, correctly rounded.

    Args:
        precision: The number of bits wanted. Must be positive.
        rounding_mode: How to round.

    Returns:
        The float of `precision` bits nearest the number.

    Raises:
        ValueError: If `precision` is not positive, or above
            `MAX_PRECISION`.
        Error: Propagated from the arithmetic.
    """
    _ = checked_precision(precision, "e()")
    return round_by_deciding[_e_kernel, _CONSTANT_SLACK](
        precision, rounding_mode
    )


def ln10(
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigFloat:
    """The natural logarithm of ten, correctly rounded.

    Args:
        precision: The number of bits wanted. Must be positive.
        rounding_mode: How to round.

    Returns:
        The float of `precision` bits nearest the logarithm.

    Raises:
        ValueError: If `precision` is not positive, or above
            `MAX_PRECISION`.
        Error: Propagated from the arithmetic.

    Notes:

    This is what `log10()` divides by, as `ln2()` is what `log2()` divides
    by. It is here rather than computed inside that function so that it is
    cached with the others and so that it can be asked for on its own.
    """
    _ = checked_precision(precision, "ln10()")
    return round_by_deciding[_ln10_kernel, _CONSTANT_SLACK](
        precision, rounding_mode
    )
