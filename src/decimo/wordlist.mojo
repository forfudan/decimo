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

"""The word storage behind `BigUInt` and `BigInt`, with small values kept
inside the struct.

A small `BigUInt` operation is almost entirely allocation. Measured on arm64,
best of nine, `-D ASSERT=none`:

    add_inplace 4w += 1w (nothing allocated):   1.2 ns
    add         4w +  1w (one allocation)   :  40.0 ns

and the cost of `add` barely moves with size -- 36.7 ns at one word against
67.2 ns at sixty-four -- because what it is paying for is one call to the
allocator, not the addition.

`List[UInt32]` always goes to the heap. `WordList` keeps up to
`INLINE_WORDS` words in the struct itself and only allocates beyond that,
which is what CPython's `decimal` does: `PyDecObject` carries four 64-bit
words inline, so at the default precision of 28 digits libmpdec never calls
the allocator at all.

GMP pays this too, and has no inline buffer: an `mpz_t` addition of two
100-digit numbers takes about 15 ns into a fresh result and about 5 ns into a
reused one, so two thirds of it is `malloc` and `free`. An immutable value
type cannot use the reuse idiom, which makes inline storage the one place
where we can be ahead of GMP rather than behind it.

The API is the part of `List` that the number types use, spelled the
same way, so the eight hundred-odd `.words` sites did not have to change.
"""

from std.sys import size_of
from std.atomic import Atomic
from std.bit import bit_width
from std.ffi import _Global
from std.memory import Layout, ThinAllocation, alloc, dealloc
from std.memory import unsafe_memcpy
from std.os import abort

comptime INLINE_WORDS = 10
"""How many words live in a `BigUInt` before the heap is involved.

Also the default for `WordList`; `BigInt` passes its own.

It has to cover *results*, not operands. A 28-digit value is four words, but
adding two of them carries into a fifth and multiplying gives eight, so at
four this allocated on every operation and was slower than the plain `List` it
replaced -- the fatter struct with none of the benefit.

Ten, because that is what a division needs. A 28-digit division pads the
dividend out for the guard digits, normalizes it, and copies it with a guard
word on top: nine or ten words, every one of which allocated at eight.
Measured from Python at 28 digits, best of three runs (ns):

    inline words        8     10     12
    a + b            51.5   51.9   53.0
    a * b            70.5   71.5   71.3
    a / b             263    143    146

Addition and multiplication do not care between eight and ten, division cares
enormously, and twelve only makes the value bigger. At 1000 and 100 000 digits
ten is within noise of a plain `List` everywhere.
"""


# ===----------------------------------------------------------------------=== #
# A pool of heap blocks
#
# `alloc` and `dealloc` together cost about 36 nanoseconds and the number does
# not move with the size, so every operation whose result is longer than
# `INLINE` pays the same toll -- a six-word addition cost 44 nanoseconds, most
# of it there. Inline storage answers this for short values; for the rest, the
# block the last operation released is almost always the size the next one
# wants.
#
# So a released block goes on a stack instead of back to the allocator, and the
# next request of that size takes it. Reaching the pool is a global fetch
# (4.5 ns) and two atomic operations (3 ns), against 36 for the round trip it
# replaces. Measured through `BigUInt` and `BigDecimal`, best of seven runs
# (ns):
#
#     operation                before   after
#     6-word addition            43.8    22.0
#     56-word addition           63.0    41.3
#     200-word addition           126      96
#     3-by-3 multiplication      53.5    31.5
#     20-by-20 multiplication     239     205
#     200-word copy              54.3    28.5
#     200-by-20 division         3166    1976
#     60-digit BigDecimal /       262     177
#
# The work in a large multiplication dwarfs its own allocation, so 200-by-200
# barely moves. Values that fit inline never reach the pool, but they do pay
# for the branch that leads to it: about a nanosecond on a 28-digit
# `BigDecimal` addition, against the twenty a heap value saves.
#
# The atomic is what makes this safe to share. Blocks are handed out under a
# flag that a thread takes and releases; a thread that finds it taken goes to
# the allocator instead, so two threads never see the same block and the worst
# that concurrency costs is the pooling itself. The library has no other
# mutable global state, and this one cannot be observed except as speed.
#
# Sizes are rounded up to a power of two, which is what makes a released block
# fit a later request. It also means a list rarely has to grow twice. Blocks
# larger than `_POOL_MAX_SHIFT` words go to the allocator: they are rare, and
# the work done on them dwarfs the allocation anyway. Neither the depth nor the
# largest class matters to the measurements above -- four and sixteen deep, and
# a largest class of 1024 or 65536 words, all land within noise -- so they are
# set for what the pool is allowed to hold rather than for speed.
# ===----------------------------------------------------------------------=== #

comptime _POOL_MIN_SHIFT = 3
"""The smallest class, `2^3` words. Below this a list is inline anyway."""

comptime _POOL_MAX_SHIFT = 12
"""The largest class, `2^12` words -- 4096 of them, 32 KB."""

comptime _POOL_CLASSES = _POOL_MAX_SHIFT - _POOL_MIN_SHIFT + 1

comptime _POOL_DEPTH = 8
"""Blocks kept per class. Eight is enough for the temporaries an expression
holds at once, and bounds what the pool keeps at about 500 KB."""


struct _BlockPool(Defaultable, Movable):
    """Released blocks, by size class, waiting to be handed out again."""

    var blocks: InlineArray[Int, _POOL_CLASSES * _POOL_DEPTH]
    var counts: InlineArray[Int, _POOL_CLASSES]
    var busy: Atomic[DType.int64]

    def __init__(out self):
        self.blocks = InlineArray[Int, _POOL_CLASSES * _POOL_DEPTH](
            uninitialized=True
        )
        self.counts = InlineArray[Int, _POOL_CLASSES](uninitialized=True)
        for index in range(_POOL_CLASSES):
            self.counts[index] = 0
        self.busy = Atomic[DType.int64](0)


def _make_pool() -> _BlockPool:
    return _BlockPool()


comptime _POOL = _Global["decimo_wordlist_block_pool", _make_pool]


@always_inline
def _pool_class(words: Int) -> Int:
    """Returns the size class that holds `words`, or -1 for none.

    Args:
        words: How many words are wanted.

    Returns:
        The class index, whose blocks hold `2^(index + _POOL_MIN_SHIFT)`
        words, or -1 when the request is larger than the pool keeps.
    """
    if words <= (1 << _POOL_MIN_SHIFT):
        return 0
    if words > (1 << _POOL_MAX_SHIFT):
        return -1
    # The class of a value above the smallest is the bit length of one less
    # than it: nine words through sixteen all have `bit_width(words - 1) == 4`.
    return Int(bit_width(UInt64(words - 1))) - _POOL_MIN_SHIFT


def _pool_take(class_index: Int) -> Int:
    """Takes the address of a block of the given class, or zero.

    Args:
        class_index: Which class, from `_pool_class`.

    Returns:
        The address of a block of `2^(class_index + _POOL_MIN_SHIFT)` words,
        or zero when the class is empty. Addresses rather than pointers:
        `Pointer` cannot hold a null, and zero is the natural "nothing".
    """
    # The pool is a process global, which the comptime interpreter cannot
    # reach. Constants such as `PI_1024` are built there, so it says "empty"
    # and lets the caller allocate.
    if __is_run_in_comptime_interpreter:
        return 0
    try:
        ref pool = _POOL.get_or_create_ptr()[]
        if pool.busy.fetch_add(1) != 0:
            _ = pool.busy.fetch_sub(1)
            return 0
        var taken = 0
        var count = pool.counts[class_index]
        if count > 0:
            taken = pool.blocks[class_index * _POOL_DEPTH + count - 1]
            pool.counts[class_index] = count - 1
        _ = pool.busy.fetch_sub(1)
        return taken
    except:
        return 0


def _pool_give(address: Int, class_index: Int) -> Bool:
    """Offers a block back to the pool.

    Args:
        address: The block, which must be of exactly this class's size.
        class_index: Which class, from `_pool_class`.

    Returns:
        True when the pool took it, and the caller must not free it. False
        when the class is full or another thread holds the pool, and the
        caller frees it as before.
    """
    if __is_run_in_comptime_interpreter:
        return False
    try:
        ref pool = _POOL.get_or_create_ptr()[]
        if pool.busy.fetch_add(1) != 0:
            _ = pool.busy.fetch_sub(1)
            return False
        var count = pool.counts[class_index]
        var kept = False
        if count < _POOL_DEPTH:
            pool.blocks[class_index * _POOL_DEPTH + count] = address
            pool.counts[class_index] = count + 1
            kept = True
        _ = pool.busy.fetch_sub(1)
        return kept
    except:
        return False


struct WordList[dtype: DType = DType.uint32, INLINE: Int = INLINE_WORDS](
    Copyable, Movable, Sized
):
    """A list of unsigned words that keeps small ones inside itself.

    What the words mean is the number type's business: `BigUInt` reads them as
    base-billion digits in `uint32` and `BigInt` as a base-2^64 magnitude in
    `uint64`. The container only knows how wide a word is, how many there are,
    and where they live.

    Only the `List` surface that the number types actually use is provided:
    `len()`, indexing, iteration, `unsafe_ptr()`, `append`, `resize`,
    `shrink`, `clear`, `reserve`, `copy` and `capacity`.

    Invariant: `_capacity >= INLINE` always, and the words live in `_inline`
    exactly when `_capacity == INLINE`. So there is one test for "where is the
    data", and it is on a field already in cache.

    Parameters:
        dtype: The word type. Both number types use `uint64`: `BigInt`
            because that is the widest product the hardware gives in one
            instruction, `BigUInt` because its base is 10^18.
        INLINE: How many words fit inside the struct before the heap is
            involved. The two number types have different sweet spots, so
            each picks its own; see `INLINE_WORDS` for how to choose.
    """

    comptime _PointerType = Pointer[Scalar[Self.dtype], MutUntrackedOrigin]

    var _heap: Self._PointerType
    """Allocated storage. Only meaningful when `_capacity > INLINE`."""
    var _len: Int
    var _capacity: Int
    var _inline: InlineArray[Scalar[Self.dtype], Self.INLINE]

    # ===------------------------------------------------------------------=== #
    # Life cycle
    # ===------------------------------------------------------------------=== #

    @staticmethod
    @no_inline
    def _acquire(capacity: Int) -> Tuple[Self._PointerType, Int]:
        """Returns a heap block of at least `capacity` words, and its size.

        A block of the right class is taken from the pool when one is there,
        and allocated otherwise. It is deliberately kept out of line: the
        callers are inlined into every list that is built, and the branch
        that leads here is not taken by the inline ones.

        Args:
            capacity: How many words are wanted.

        Returns:
            The block and how many words it holds, which is at least
            `capacity`.

        Notes:
            The pool is only for 64-bit words, which is what both number
            types use. The pool holds raw blocks and a class is a number of
            words, so a second word width would have to be a second pool.
        """
        var wanted = capacity
        comptime if size_of[Scalar[Self.dtype]]() == 8:
            var class_index = _pool_class(capacity)
            if class_index >= 0:
                # Round up to the class, so the block can be handed out again
                # later: a block of exactly six words fits no class, so it
                # would be freed rather than kept and the pool would stay
                # empty.
                wanted = 1 << (class_index + _POOL_MIN_SHIFT)
                var address = _pool_take(class_index)
                if address != 0:
                    return (
                        Self._PointerType(unsafe_from_address=address),
                        wanted,
                    )
        return (
            alloc(Layout[Scalar[Self.dtype]](count=wanted)).unsafe_leak(),
            wanted,
        )

    @staticmethod
    @no_inline
    def _release(deinit_heap: Self._PointerType, capacity: Int):
        """Returns a block to the pool, or frees it.

        Args:
            deinit_heap: The block.
            capacity: How many words it holds.
        """
        comptime if size_of[Scalar[Self.dtype]]() == 8:
            var class_index = _pool_class(capacity)
            if (
                class_index >= 0
                and capacity == 1 << (class_index + _POOL_MIN_SHIFT)
                and _pool_give(Int(deinit_heap), class_index)
            ):
                return
        dealloc(
            ThinAllocation(unsafe_owned_ptr=deinit_heap).unsafe_with_layout(
                Layout[Scalar[Self.dtype]](count=capacity)
            )
        )

    @always_inline
    def __init__(out self):
        """An empty list, with room for `INLINE` words and no allocation."""
        self._heap = Self._PointerType.unsafe_dangling()
        self._len = 0
        self._capacity = Self.INLINE
        self._inline = InlineArray[Scalar[Self.dtype], Self.INLINE](
            uninitialized=True
        )

    @always_inline
    def __init__(out self, *, capacity: Int):
        """Room for `capacity` words, length zero.

        Args:
            capacity: How many words to make room for.
        """
        self._len = 0
        self._inline = InlineArray[Scalar[Self.dtype], Self.INLINE](
            uninitialized=True
        )
        if capacity > Self.INLINE:
            var block = Self._acquire(capacity)
            self._heap = block[0]
            self._capacity = block[1]
        else:
            self._capacity = Self.INLINE
            self._heap = Self._PointerType.unsafe_dangling()

    @always_inline
    def __init__(out self, *, unsafe_uninit_length: Int):
        """Room for `unsafe_uninit_length` words, and that length, uninitialized.

        Args:
            unsafe_uninit_length: The length to claim.
        """
        self = Self(capacity=unsafe_uninit_length)
        self._len = unsafe_uninit_length

    def __init__(
        out self, var *values: Scalar[Self.dtype], __list_literal__: NoneType
    ):
        """Build from a list literal, so `[Scalar[Self.dtype](0)]` still works.

        Args:
            values: The words.
            __list_literal__: Marks this as the list-literal constructor.
        """
        self = Self(capacity=len(values))
        for value in values:
            self.append(value)

    def as_span[
        origin: Origin, //
    ](ref[origin] self) -> Span[Scalar[Self.dtype], origin]:
        """A view over the words.

        Parameters:
            origin: The origin of `self`.

        Returns:
            A span covering every word.
        """
        return Span[Scalar[Self.dtype], origin](
            unsafe_ptr=self.unsafe_ptr(), length=self._len
        )

    def __init__(out self, var other: List[Scalar[Self.dtype]]):
        """Copy the contents of a `List[Scalar[Self.dtype]]`.

        The words are copied, not adopted: a `List` owns a heap buffer and a
        `WordList` may keep its words inline, so there is nothing to hand over.
        Callers on a hot path should build into a `WordList` directly rather
        than fill a `List` and pass it here.

        Args:
            other: The list to copy the words from.
        """
        self = Self(capacity=len(other))
        self._len = len(other)
        if self._len > 0:
            var count = self._len
            unsafe_memcpy(
                dest=self.unsafe_ptr(), src=other.unsafe_ptr(), count=count
            )

    def __init__(out self, *, copy: Self):
        """A copy that owns its own storage.

        Args:
            copy: The list to copy.
        """
        self = Self(capacity=copy._capacity)
        self._len = copy._len
        if self._len > 0:
            var count = self._len
            unsafe_memcpy(
                dest=self.unsafe_ptr(), src=copy.unsafe_ptr(), count=count
            )

    def __init__(out self, *, deinit move: Self):
        """Take over another list's storage.

        The inline words are copied and the heap pointer is taken. Nothing
        points into the old struct afterwards, which is the reason the inline
        case is found by a test on `_capacity` rather than by a `_data` field
        that would have to be repaired on every move.

        Args:
            move: The list to move from.
        """
        self._heap = move._heap
        self._len = move._len
        self._capacity = move._capacity
        self._inline = InlineArray[Scalar[Self.dtype], Self.INLINE](
            uninitialized=True
        )
        # Only the inline case has anything worth carrying over, and it is a
        # fixed number of words, so it goes as one vector load and store.
        # Spelling this as a scalar `for` loop instead cost 60% of an addition
        # -- moves are everywhere, and the compiler did not unroll it.
        if move._capacity == Self.INLINE:
            # A fixed count on purpose. Copying only `move._len` words looks
            # like less work and is not: a constant size inlines to a couple of
            # vector moves, while a variable one becomes a call to `memcpy`,
            # which cost 60% of an addition.
            unsafe_memcpy(
                dest=Pointer(to=self._inline).unsafe_bitcast[
                    Scalar[Self.dtype]
                ](),
                src=Pointer(to=move._inline).unsafe_bitcast[
                    Scalar[Self.dtype]
                ](),
                count=Self.INLINE,
            )

    def __deinit__(deinit self):
        """Release the storage, if any was ever taken."""
        if self._capacity > Self.INLINE:
            Self._release(self._heap, self._capacity)

    # ===------------------------------------------------------------------=== #
    # Access
    # ===------------------------------------------------------------------=== #

    @always_inline
    def unsafe_ptr[
        origin: Origin, //
    ](ref[origin] self) -> Pointer[Scalar[Self.dtype], origin]:
        """A pointer to the words, wherever they live.

        The branch is the price of not allocating. It predicts perfectly in any
        loop that stays one side of the threshold, and callers hoist this out
        of their loops anyway.

        Parameters:
            origin: The origin of `self`.

        Returns:
            A pointer to the first word.
        """
        if self._capacity == Self.INLINE:
            return (
                Pointer(to=self._inline)
                .unsafe_bitcast[Scalar[Self.dtype]]()
                .unsafe_mut_cast[origin.mut]()
                .unsafe_origin_cast[origin]()
            )
        return self._heap.unsafe_mut_cast[origin.mut]().unsafe_origin_cast[
            origin
        ]()

    @always_inline
    def __len__(self) -> Int:
        """The number of words.

        Returns:
            The length.
        """
        return self._len

    @always_inline
    def capacity(self) -> Int:
        """How many words fit before the storage has to grow.

        Returns:
            The capacity.
        """
        return self._capacity

    @always_inline
    def __getitem__(ref self, index: Int) -> ref[self] Scalar[Self.dtype]:
        """The word at `index`.

        Args:
            index: Which word.

        Returns:
            A reference to the word.
        """
        return self.unsafe_ptr().unsafe_offset(index)[]

    @always_inline
    def unsafe_set(mut self, idx: Int, var value: Scalar[Self.dtype]):
        """Write a word without checking the index.

        Args:
            idx: Which word.
            value: The value to write.
        """
        self.unsafe_ptr().unsafe_offset(idx).unsafe_store(value)

    @always_inline
    def unsafe_get(self, idx: Int) -> Scalar[Self.dtype]:
        """Read a word without checking the index.

        Args:
            idx: Which word.

        Returns:
            The word.
        """
        return self.unsafe_ptr().unsafe_offset(idx).unsafe_load()

    def __iter__[
        origin: Origin, //
    ](ref[origin] self) -> _WordListIterator[Self.dtype, origin]:
        """Iterate over the words, by reference.

        Parameters:
            origin: The origin of `self`.

        Returns:
            An iterator over the words.
        """
        return _WordListIterator[Self.dtype, origin](
            0, self.unsafe_ptr(), self._len
        )

    def copy(self) -> Self:
        """A copy that owns its own storage.

        Returns:
            The copy.
        """
        return Self(copy=self)

    # ===------------------------------------------------------------------=== #
    # Growing and shrinking
    # ===------------------------------------------------------------------=== #

    def _grow(mut self, capacity: Int):
        """Move the words to a heap block of at least `capacity` words."""
        var wanted = max(capacity, self._capacity * 2)
        var previous_heap = self._heap
        var previous_capacity = self._capacity
        var block = Self._acquire(wanted)
        self._heap = block[0]
        self._capacity = block[1]
        if self._len > 0:
            unsafe_memcpy(
                dest=self._heap,
                src=previous_heap if previous_capacity
                > Self.INLINE else Pointer(to=self._inline).unsafe_bitcast[
                    Scalar[Self.dtype]
                ](),
                count=self._len,
            )
        if previous_capacity > Self.INLINE:
            Self._release(previous_heap, previous_capacity)

    @always_inline
    def reserve(mut self, capacity: Int):
        """Make room for `capacity` words.

        Args:
            capacity: The capacity wanted.
        """
        if capacity > self._capacity:
            self._grow(capacity)

    @always_inline
    def append(mut self, var value: Scalar[Self.dtype]):
        """Add a word to the end.

        Args:
            value: The word to add.
        """
        var index = self._len
        if index == self._capacity:
            self._grow(index + 1)
        self.unsafe_ptr().unsafe_offset(index).unsafe_store(value)
        self._len = index + 1

    @always_inline
    def shrink(mut self, new_length: Int):
        """Drop words from the end.

        Args:
            new_length: The length to keep, which must not be larger than the
                current one.
        """
        if new_length > self._len:
            abort("WordList.shrink() cannot make the list longer")
        self._len = new_length

    @always_inline
    def resize(mut self, length: Int, fill: Scalar[Self.dtype]):
        """Set the length, filling any new words with `fill`.

        Args:
            length: The new length.
            fill: The value for any words added.
        """
        if length <= self._len:
            self._len = length
            return
        self.reserve(length)
        var start = self._len
        var pointer = self.unsafe_ptr()
        for i in range(start, length):
            pointer.unsafe_offset(i).unsafe_store(fill)
        self._len = length

    @always_inline
    def resize(mut self, *, unsafe_uninit_length: Int):
        """Set the length, leaving any new words uninitialized.

        Args:
            unsafe_uninit_length: The new length.
        """
        self.reserve(unsafe_uninit_length)
        self._len = unsafe_uninit_length

    @always_inline
    def clear(mut self):
        """Drop every word, keeping the storage."""
        self._len = 0


@fieldwise_init
struct _WordListIterator[mut: Bool, //, dtype: DType, origin: Origin[mut=mut]](
    ImplicitlyCopyable, Iterable, Iterator
):
    """Walks a `WordList` word by word, yielding references.

    The same shape as `List`'s own iterator, so `for word in x.words` and
    `for ref word in x.words` both mean what they meant before.

    Parameters:
        mut: Whether the words can be written through.
        dtype: The word type.
        origin: The origin of the list being walked.
    """

    comptime Element = Scalar[Self.dtype]

    comptime IteratorType[
        iterable_mut: Bool, //, iterable_origin: Origin[mut=iterable_mut]
    ]: Iterator = Self

    var _index: Int
    var _data: Pointer[Scalar[Self.dtype], Self.origin]
    var _length: Int

    @always_inline
    def __iter__(ref self) -> Self.IteratorType[origin_of(self)]:
        """This iterator is its own iterable.

        Returns:
            A copy of itself.
        """
        return self.copy()

    def __next__(
        mut self,
    ) raises StopIteration -> ref[Self.origin] Self.Element:
        """The next word.

        Returns:
            A reference to the word.
        """
        if self._index >= self._length:
            raise StopIteration()
        self._index += 1
        return self._data[unsafe_offset=self._index - 1]

    @always_inline
    def bounds(self) -> Tuple[Int, Optional[Int]]:
        """How many words are left.

        Returns:
            The exact count remaining, twice.
        """
        var remaining = self._length - self._index
        return (remaining, {remaining})
