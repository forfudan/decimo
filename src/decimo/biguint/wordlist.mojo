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

"""The word storage behind `BigUInt`, with small values kept inside the struct.

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

The API is the part of `List[UInt32]` that `BigUInt` uses, spelled the same
way, so the eight hundred-odd `.words` sites did not have to change.
"""

from std.memory import Layout, ThinAllocation, alloc, dealloc
from std.memory import unsafe_memcpy
from std.os import abort

comptime INLINE_WORDS = 8
"""How many words live in the struct before the heap is involved.

It has to cover *results*, not operands. A 28-digit value is four words, but
adding two of them can carry into a fifth and multiplying gives eight, so at
four this setting allocated on every operation and was slower than the plain
`List` it replaced -- the fatter struct with none of the benefit.

Measured at 28 digits, against `List[UInt32]` (ns):

    inline words        4      8     10     12    List
    BigDecimal add   58.4   18.2   17.7   18.4    46.7
    BigDecimal mul   72.6   35.7   35.7   35.8    61.5
    BigDecimal div    428    312    294    178     407

and against the same baseline at 100 000 digits, where the only thing the
inline array does is make every value bigger to copy:

    inline words        8     10     12    List
    multiply       2.60ms 2.56ms 2.78ms  2.58ms
    divide         11.2ms 11.2ms 11.3ms  11.1ms

Eight is the settled answer: it takes essentially all of the small-size win,
costs about one percent at large sizes where twelve costs seven, and wastes
32 bytes per value rather than 48. Division would still rather have twelve --
it pads a 28-digit dividend out to ten words -- but that padding is wider than
it needs to be, and narrowing it is the better fix.
"""


struct WordList(Copyable, Movable, Sized):
    """A list of base-billion words that keeps small ones inside itself.

    Only the `List[UInt32]` surface that `BigUInt` actually uses is provided:
    `len()`, indexing, iteration, `unsafe_ptr()`, `append`, `resize`, `shrink`,
    `clear`, `reserve`, `copy` and `capacity`.

    Invariant: `_capacity >= INLINE_WORDS` always, and the words live in
    `_inline` exactly when `_capacity == INLINE_WORDS`. So there is one test
    for "where is the data", and it is on a field already in cache.
    """

    comptime _PointerType = Pointer[UInt32, MutUntrackedOrigin]

    var _heap: Self._PointerType
    """Allocated storage. Only meaningful when `_capacity > INLINE_WORDS`."""
    var _len: Int
    var _capacity: Int
    var _inline: InlineArray[UInt32, INLINE_WORDS]

    # ===------------------------------------------------------------------=== #
    # Life cycle
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __init__(out self):
        """An empty list, with room for `INLINE_WORDS` words and no allocation.
        """
        self._heap = Self._PointerType.unsafe_dangling()
        self._len = 0
        self._capacity = INLINE_WORDS
        self._inline = InlineArray[UInt32, INLINE_WORDS](uninitialized=True)

    @always_inline
    def __init__(out self, *, capacity: Int):
        """Room for `capacity` words, length zero.

        Args:
            capacity: How many words to make room for.
        """
        self._len = 0
        self._inline = InlineArray[UInt32, INLINE_WORDS](uninitialized=True)
        if capacity > INLINE_WORDS:
            self._capacity = capacity
            self._heap = alloc(Layout[UInt32](count=capacity)).unsafe_leak()
        else:
            self._capacity = INLINE_WORDS
            self._heap = Self._PointerType.unsafe_dangling()

    @always_inline
    def __init__(out self, *, unsafe_uninit_length: Int):
        """Room for `unsafe_uninit_length` words, and that length, uninitialized.

        Args:
            unsafe_uninit_length: The length to claim.
        """
        self = Self(capacity=unsafe_uninit_length)
        self._len = unsafe_uninit_length

    def __init__(out self, var *values: UInt32, __list_literal__: NoneType):
        """Build from a list literal, so `[UInt32(0)]` still works.

        Args:
            values: The words.
            __list_literal__: Marks this as the list-literal constructor.
        """
        self = Self(capacity=len(values))
        for value in values:
            self.append(value)

    def as_span[origin: Origin, //](ref[origin] self) -> Span[UInt32, origin]:
        """A view over the words.

        Parameters:
            origin: The origin of `self`.

        Returns:
            A span covering every word.
        """
        return Span[UInt32, origin](
            unsafe_ptr=self.unsafe_ptr(), length=self._len
        )

    def __init__(out self, var other: List[UInt32]):
        """Adopt the contents of a `List[UInt32]`.

        Args:
            other: The list to take the words from.
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
        self._inline = InlineArray[UInt32, INLINE_WORDS](uninitialized=True)
        # `InlineArray` is not implicitly copyable, and the bound is a
        # compile-time constant, so this unrolls to a fixed-size copy.
        for i in range(INLINE_WORDS):
            self._inline[i] = move._inline[i]

    def __deinit__(deinit self):
        """Release the storage, if any was ever taken."""
        if self._capacity > INLINE_WORDS:
            dealloc(
                ThinAllocation(unsafe_owned_ptr=self._heap).unsafe_with_layout(
                    Layout[UInt32](count=self._capacity)
                )
            )

    # ===------------------------------------------------------------------=== #
    # Access
    # ===------------------------------------------------------------------=== #

    @always_inline
    def unsafe_ptr[
        origin: Origin, //
    ](ref[origin] self) -> Pointer[UInt32, origin]:
        """A pointer to the words, wherever they live.

        The branch is the price of not allocating. It predicts perfectly in any
        loop that stays one side of the threshold, and callers hoist this out
        of their loops anyway.

        Parameters:
            origin: The origin of `self`.

        Returns:
            A pointer to the first word.
        """
        if self._capacity == INLINE_WORDS:
            return (
                Pointer(to=self._inline)
                .unsafe_bitcast[UInt32]()
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
    def __getitem__(ref self, index: Int) -> ref[self] UInt32:
        """The word at `index`.

        Args:
            index: Which word.

        Returns:
            A reference to the word.
        """
        return self.unsafe_ptr().unsafe_offset(index)[]

    @always_inline
    def unsafe_set(mut self, idx: Int, var value: UInt32):
        """Write a word without checking the index.

        Args:
            idx: Which word.
            value: The value to write.
        """
        self.unsafe_ptr().unsafe_offset(idx).unsafe_store(value)

    @always_inline
    def unsafe_get(self, idx: Int) -> UInt32:
        """Read a word without checking the index.

        Args:
            idx: Which word.

        Returns:
            The word.
        """
        return self.unsafe_ptr().unsafe_offset(idx).unsafe_load()

    def __iter__[
        origin: Origin, //
    ](ref[origin] self) -> _WordListIterator[origin]:
        """Iterate over the words, by reference.

        Parameters:
            origin: The origin of `self`.

        Returns:
            An iterator over the words.
        """
        return _WordListIterator[origin](0, self.unsafe_ptr(), self._len)

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
        var block = alloc(Layout[UInt32](count=wanted)).unsafe_leak()
        if self._len > 0:
            unsafe_memcpy(dest=block, src=self.unsafe_ptr(), count=self._len)
        if self._capacity > INLINE_WORDS:
            dealloc(
                ThinAllocation(unsafe_owned_ptr=self._heap).unsafe_with_layout(
                    Layout[UInt32](count=self._capacity)
                )
            )
        self._heap = block
        self._capacity = wanted

    @always_inline
    def reserve(mut self, capacity: Int):
        """Make room for `capacity` words.

        Args:
            capacity: The capacity wanted.
        """
        if capacity > self._capacity:
            self._grow(capacity)

    @always_inline
    def append(mut self, var value: UInt32):
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
    def resize(mut self, length: Int, fill: UInt32):
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
struct _WordListIterator[mut: Bool, //, origin: Origin[mut=mut]](
    ImplicitlyCopyable, Iterable, Iterator
):
    """Walks a `WordList` word by word, yielding references.

    The same shape as `List`'s own iterator, so `for word in x.words` and
    `for ref word in x.words` both mean what they meant before.

    Parameters:
        mut: Whether the words can be written through.
        origin: The origin of the list being walked.
    """

    comptime Element = UInt32

    comptime IteratorType[
        iterable_mut: Bool, //, iterable_origin: Origin[mut=iterable_mut]
    ]: Iterator = Self

    var _index: Int
    var _data: Pointer[UInt32, Self.origin]
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
