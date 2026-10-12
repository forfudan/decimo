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


"""Keeping the decimal constants that have already been computed.

A constant costs the same whether it is wanted once or a thousand times, and
the answer to a wide request answers every narrower one as well. What is
computed is therefore kept, process-wide, at the widest precision it has been
asked for, and a later request is a rounding of what is already here rather
than a series summed again.

Rounding a kept value is not simply trusting it. A value good to a unit in
the last place of the width it was computed at does not say what the digit at
a narrower precision should be when the digits in between sit on a rounding
boundary, so the rounding is decided the way every other rounding in this
package is decided: the interval the value could cover is rounded at both
ends, and the answer stands only when both ends agree. When they do not, the
constant is computed again, wider, and kept. Nothing is ever returned that
the arithmetic has not settled.

Two things are different here from the binary layer's cache next door in
`bigfloat.constants`, and both come from the base. A decimal value carries
its digits in base-10^18 words, so cutting a wide one down to a narrow
precision drops whole words and costs a microsecond whatever the width it is
cut from -- 100,000 digits down to 1,100 costs the same microsecond as 10,000
down to 1,100 does. The binary layer walks a significand to truncate it, and
so has to keep a second narrow copy of each constant to stop one very wide
request making every later narrow one expensive. Here one copy is enough.
The cut is still taken before the interval test rather than after, because
the two additions that test costs are the one part of the work that does grow
with the width it is given.
"""

from std.atomic import Atomic
from std.ffi import _Global

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigdecimal.exponential import _settled_answer
from decimo.rounding_mode import RoundingMode


comptime PI = 0
"""The slot holding pi."""

comptime E = 1
"""The slot holding Euler's number."""

comptime _SLOTS = 2
"""How many constants the cache has room for."""

comptime FLOOR = 64
"""The precision below which a constant is computed rather than kept.

A constant of a few dozen digits costs about what this cache's own copy and
interval test cost, so there is nothing to win below here and a lock to take.
"""

comptime MARGIN = 16
"""Digits a kept value must carry beyond a request before it can answer it.

The interval test needs room to be decided in: a value carrying only the
digits asked for says nothing about the digit after them. Sixteen is two
words of nothing in particular -- the test does not need many, it needs a
few, and a kept value is wide enough to spare them.
"""


struct _ConstantCache(Movable):
    """The constants, each at the widest precision it has been asked for.

    A value computed at `d` digits answers any request for `d - MARGIN` or
    fewer, when the interval test settles. The widths only ever grow.
    """

    var busy: Atomic[Int64]
    """Nought when no thread is inside the cache."""

    var value: List[BigDecimal]
    """Pi and Euler's number.

    Empty until the first store, because a `BigDecimal` to hold a place
    cannot be built without a precision to build it at, and the global's
    factory cannot raise.
    """

    var digits: List[Int]
    """What each was computed at; nought for one never computed."""

    def __init__(out self):
        """An empty cache."""
        self.busy = Atomic[Int64](0)
        self.value = List[BigDecimal]()
        self.digits = [0, 0]


def _make_constant_cache() -> _ConstantCache:
    """Builds the process-wide cache.

    Returns:
        An empty cache.
    """
    return _ConstantCache()


comptime _KEPT = _Global["decimo_bigdecimal_kept", _make_constant_cache]
"""One cache for the whole process.

Mojo has no module-level `var`; `std.ffi._Global` is how this package already
holds process-wide state, in the binary layer's constants, in `MathCache` and
in the word list's block pool.

A thread that finds the cache busy computes its own answer and keeps nothing,
which is the block pool's try-lock and the binary cache's: correctness never
waits on the lock, only the saving does. That is the difference from
`MathCache`, which rewrites a list-backed value in place and so says in its
own documentation that it cannot be used from two threads at once.
"""


struct Kept(Copyable, Movable):
    """A constant as the cache holds it, with the width it was computed at."""

    var value: BigDecimal
    """The value."""

    var digits: Int
    """The precision it was computed at."""

    def __init__(out self, var value: BigDecimal, digits: Int):
        """Holds a value and its width.

        Args:
            value: The value.
            digits: The precision it was computed at.
        """
        self.value = value^
        self.digits = digits


def held(which: Int, wanted: Int) raises -> Optional[Kept]:
    """A copy of a kept constant, when it carries `wanted` digits or more.

    Args:
        which: The slot, `PI` or `E`.
        wanted: The precision the caller needs it to carry.

    Returns:
        The kept value and its width, or nothing when the slot is empty, too
        narrow, or another thread is inside the cache.

    Raises:
        Error: Propagated from the copy.
    """
    var cache = _KEPT.get_or_create_ptr()
    if cache[].busy.fetch_add(1) != 0:
        _ = cache[].busy.fetch_sub(1)
        return None

    var answer = Optional[Kept](None)
    if cache[].digits[which] >= wanted:
        answer = Kept(cache[].value[which].copy(), cache[].digits[which])
    _ = cache[].busy.fetch_sub(1)
    return answer^


def keep(which: Int, digits: Int, value: BigDecimal) raises:
    """Keeps a constant, when it is wider than what is kept already.

    Args:
        which: The slot, `PI` or `E`.
        digits: The precision `value` was computed at.
        value: The value.

    Raises:
        Error: Propagated from the copy.
    """
    var cache = _KEPT.get_or_create_ptr()
    if cache[].busy.fetch_add(1) != 0:
        _ = cache[].busy.fetch_sub(1)
        return

    if len(cache[].value) == 0:
        # The slots are filled on the first store, since the cache cannot
        # build a placeholder without a precision to build it at. A slot
        # whose width is still nought is never read.
        for _ in range(_SLOTS):
            cache[].value.append(value.copy())
    if digits > cache[].digits[which]:
        cache[].value[which] = value.copy()
        cache[].digits[which] = digits
    _ = cache[].busy.fetch_sub(1)


def _settled_from(
    var value: BigDecimal,
    digits: Int,
    slack: Int,
    precision: Int,
    rounding_mode: RoundingMode,
) raises -> Optional[BigDecimal]:
    """The answer a kept value settles on, if it settles on one.

    Args:
        value: The kept value.
        digits: The precision it was computed at.
        slack: Units in the last place of that width it may be off by.
        precision: The precision wanted.
        rounding_mode: How to round.

    Returns:
        The rounded value when the interval the kept value could cover rounds
        to one answer at both ends, and nothing when it straddles a boundary.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    A value wider than the test needs is cut down first, with the digits
    truncated rather than rounded, which costs a unit in the last place of
    the narrower width and so one more unit of slack. The cut costs a
    microsecond at any width; the two additions the test makes would cost
    more than that at a width far beyond what was asked for.
    """
    var width = digits
    var reach = slack
    var cut_to = precision + MARGIN
    if digits > cut_to:
        value.round_to_precision_inplace(
            precision=cut_to,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        width = cut_to
        reach = slack + 1
    return _settled_answer(value, width, reach, precision, rounding_mode)


def rounded[
    kernel: def(Int) thin raises -> BigDecimal, slack: Int
](which: Int, precision: Int, rounding_mode: RoundingMode) raises -> BigDecimal:
    """A constant rounded to `precision` digits, kept between calls.

    Parameters:
        kernel: Computes the constant to the precision it is given, within
            `slack` units of the last place of that precision.
        slack: Units in the last place `kernel` may be off by.

    Args:
        which: The slot to keep it in, `PI` or `E`.
        precision: The number of significant digits wanted.
        rounding_mode: How to round.

    Returns:
        The constant rounded to `precision` digits, which is the digits
        `kernel` gives at that precision.

    Raises:
        Error: Propagated from the kernel or the arithmetic.

    Notes:

    What is kept is computed at the width the request needs and no wider, so
    that a caller who asks once pays nothing for the keeping: sixteen digits
    on top of its own precision is a fraction of a percent of the work. A
    request wider than what is kept doubles instead, so a caller walking
    upward -- a rounding loop, or a series of wider and wider requests --
    recomputes a handful of times rather than at every step.

    A kept value that does not settle is not trusted: the constant is
    computed again at the wider width and kept, and if that does not settle
    either the kernel answers the request itself, which is what it did before
    there was a cache here.
    """
    if precision < FLOOR:
        return kernel(precision)

    var wanted = precision + MARGIN
    var widest = 0
    var kept = held(which, wanted)
    if kept:
        var mine = kept.take()
        widest = mine.digits
        var answer = _settled_from(
            mine.value.copy(), widest, slack, precision, rounding_mode
        )
        if answer:
            return answer.take()

    var target = wanted
    if widest >= target:
        target = widest * 2
    var fresh = kernel(target)
    keep(which, target, fresh)
    var answer = _settled_from(
        fresh.copy(), target, slack, precision, rounding_mode
    )
    if answer:
        return answer.take()
    return kernel(precision)
