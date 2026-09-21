"""
Test `WordList` as a container.

A short `WordList` keeps its words inside the struct, so moving it moves the
words. These tests hold the list to that: words survive every kind of move,
the inline and heap cases switch at exactly `INLINE`, and the operations keep
`0 <= len <= capacity` and `capacity >= INLINE`. The block pool has its own
tests in `test_word_list_block_pool.mojo`.
"""

from std import testing

from decimo.word_list import WordList

comptime Words = WordList[DType.uint64, 5]
"""Pooled word size, `BigUInt`'s inline length."""

comptime SmallWords = WordList[DType.uint32, 3]
"""A word size the pool does not take, so the heap path is plain `alloc`."""


def _filled(length: Int, seed: UInt64) -> Words:
    """A list of `length` words, each carrying `seed` and its own index."""
    var values = Words()
    for index in range(length):
        values.append(seed * 1000 + UInt64(index))
    return values^


def _check(values: Words, length: Int, seed: UInt64, label: String) raises:
    testing.assert_equal(len(values), length, label + ": length")
    for index in range(length):
        testing.assert_equal(
            values[index], seed * 1000 + UInt64(index), label + ": word"
        )


def _check_invariant(values: Words, label: String) raises:
    testing.assert_true(len(values) >= 0, label + ": negative length")
    testing.assert_true(
        len(values) <= values.capacity(), label + ": length above capacity"
    )
    testing.assert_true(
        values.capacity() >= 5, label + ": capacity below INLINE"
    )


def _through_a_call(var values: Words) -> Words:
    """Takes a list by value and hands it back, so it moves twice."""
    return values^


def test_move_keeps_inline_words() raises:
    """Every kind of move carries the inline words with it."""
    for length in range(0, 6):
        var original = _filled(length, 3)
        testing.assert_equal(original.capacity(), 5, "should be inline")

        var moved = original^
        _check(moved, length, 3, "moved to a variable")

        var returned = _through_a_call(moved^)
        _check(returned, length, 3, "moved through a call")


def test_move_keeps_heap_words() raises:
    """A heap list moves by handing over its block, words untouched."""
    var original = _filled(40, 4)
    testing.assert_true(original.capacity() > 5, "should be on the heap")
    var moved = _through_a_call(original^)
    _check(moved, 40, 4, "heap list moved")


def test_lists_inside_a_growing_list() raises:
    """A `List` that grows moves its elements; inline words must follow."""
    var lists = List[Words]()
    for index in range(64):
        lists.append(_filled(index % 8, UInt64(index)))
    for index in range(64):
        _check(lists[index], index % 8, UInt64(index), "inside a List")


def test_pointer_taken_after_a_move_sees_the_words() raises:
    """The pointer of the moved-to list reads the words, inline or heap."""
    for length in [3, 5, 6, 40]:
        var original = _filled(length, 5)
        var moved = original^
        var pointer = moved.unsafe_ptr()
        for index in range(length):
            testing.assert_equal(
                pointer[unsafe_offset=index],
                UInt64(5 * 1000 + index),
                "pointer after move",
            )


def test_inline_to_heap_boundary() raises:
    """The words move to the heap at exactly `INLINE + 1`, and survive it."""
    var values = Words()
    for index in range(5):
        values.append(UInt64(index))
        testing.assert_equal(values.capacity(), 5, "still inline")
    values.append(UInt64(5))
    testing.assert_true(values.capacity() > 5, "now on the heap")
    for index in range(6):
        testing.assert_equal(values[index], UInt64(index), "crossed over")
    _check_invariant(values, "after crossing")


def test_inline_to_heap_boundary_without_the_pool() raises:
    """The same crossing for a word size the pool does not take."""
    var values = SmallWords()
    for index in range(100):
        values.append(UInt32(index))
        testing.assert_true(len(values) <= values.capacity(), "len <= cap")
        testing.assert_true(values.capacity() >= 3, "cap >= INLINE")
    for index in range(100):
        testing.assert_equal(values[index], UInt32(index), "uint32 words")
    var moved = values^
    testing.assert_equal(moved[99], UInt32(99), "uint32 heap move")


def test_copies_are_independent() raises:
    """Writing to a copy never changes the original, inline or heap."""
    for length in [1, 5, 6, 40]:
        var original = _filled(length, 6)
        var duplicate = original.copy()
        duplicate[0] = 12345
        _check(original, length, 6, "original after the copy was written")
        testing.assert_equal(duplicate[0], 12345, "the copy took the write")


def test_resize_shrink_and_clear() raises:
    """Length changes keep the words that stay and the invariant."""
    var values = _filled(3, 7)
    values.resize(8, 42)
    _check_invariant(values, "resize up")
    testing.assert_equal(len(values), 8)
    for index in range(3):
        testing.assert_equal(values[index], UInt64(7 * 1000 + index))
    for index in range(3, 8):
        testing.assert_equal(values[index], 42, "filled word")

    values.resize(2, 0)
    _check(values, 2, 7, "resize down")

    var capacity = values.capacity()
    values.shrink(1)
    _check(values, 1, 7, "shrink")

    values.clear()
    testing.assert_equal(len(values), 0, "clear")
    testing.assert_equal(values.capacity(), capacity, "clear keeps storage")

    values.resize(unsafe_uninit_length=30)
    testing.assert_equal(len(values), 30, "uninitialized resize")
    _check_invariant(values, "uninitialized resize")


def test_reserve_keeps_words() raises:
    """Reserving room moves the words once and keeps them."""
    var values = _filled(4, 8)
    values.reserve(100)
    testing.assert_true(values.capacity() >= 100, "reserved")
    _check(values, 4, 8, "after reserve")
    values.reserve(10)
    testing.assert_true(values.capacity() >= 100, "reserve never shrinks")


def test_constructors() raises:
    """Every constructor yields the words it was given, and the invariant."""
    var from_literal: Words = [UInt64(1), UInt64(2), UInt64(3)]
    testing.assert_equal(len(from_literal), 3)
    testing.assert_equal(from_literal[2], 3)
    _check_invariant(from_literal, "list literal")

    var source = List[UInt64]()
    for index in range(12):
        source.append(UInt64(index))
    var from_list = Words(source^)
    testing.assert_equal(len(from_list), 12)
    testing.assert_equal(from_list[11], 11)
    _check_invariant(from_list, "from List")

    var with_capacity = Words(capacity=0)
    testing.assert_equal(len(with_capacity), 0)
    _check_invariant(with_capacity, "capacity 0")

    var uninit = Words(unsafe_uninit_length=9)
    testing.assert_equal(len(uninit), 9)
    _check_invariant(uninit, "uninitialized length")


def test_iteration_by_reference() raises:
    """`for ref word in list` writes through, inline and heap alike."""
    for length in [4, 20]:
        var values = _filled(length, 9)
        for ref word in values:
            word += 1
        for index in range(length):
            testing.assert_equal(values[index], UInt64(9 * 1000 + index + 1))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
