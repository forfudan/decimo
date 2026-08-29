"""
Test the block pool behind `WordList`.

Heap blocks are kept in a process-wide pool and handed out again instead of
being freed, so the tests here are about what that reuse must never break: a
block must never be shared by two live lists, and a reused block must be at
least as large as the request it comes back for.
"""


from std import testing
from decimo.wordlist import WordList

comptime Words = WordList[DType.uint64, 5]


def _filled(length: Int, seed: UInt64) -> Words:
    """A list of `length` words, each carrying `seed` and its own index."""
    var values = Words(capacity=length)
    for index in range(length):
        values.append(seed * 1000 + UInt64(index))
    return values^


def _check(values: Words, length: Int, seed: UInt64, label: String) raises:
    testing.assert_equal(len(values), length, label + ": length")
    for index in range(length):
        testing.assert_equal(
            values[index], seed * 1000 + UInt64(index), label + ": word"
        )


def test_reused_blocks_keep_their_own_words() raises:
    """Lists built and dropped in rounds must never read each other's words."""
    for round in range(8):
        var lists = List[Words]()
        for size in range(6, 40):
            lists.append(_filled(size, UInt64(round * 100 + size)))
        for index in range(len(lists)):
            var size = index + 6
            _check(
                lists[index],
                size,
                UInt64(round * 100 + size),
                "round " + String(round),
            )


def test_live_lists_do_not_share_a_block() raises:
    """Same-sized lists held at once must sit in different blocks."""
    var lists = List[Words]()
    for index in range(16):
        lists.append(_filled(6, UInt64(index)))
    var addresses = List[Int]()
    for index in range(len(lists)):
        addresses.append(Int(lists[index].unsafe_ptr()))
    for first in range(len(addresses)):
        for second in range(first + 1, len(addresses)):
            testing.assert_not_equal(
                addresses[first], addresses[second], "two lists, one block"
            )


def test_growth_across_size_classes() raises:
    """A list that grows word by word keeps its words through every move."""
    for start in range(1, 4):
        var list = Words(capacity=start)
        for index in range(2000):
            list.append(UInt64(index))
        testing.assert_equal(len(list), 2000)
        for index in range(2000):
            testing.assert_equal(list[index], UInt64(index), "after growth")


def test_capacity_is_at_least_what_was_asked_for() raises:
    """A pooled block may be larger than the request, never smaller."""
    for _ in range(4):
        for size in range(6, 300):
            var list = Words(capacity=size)
            testing.assert_true(
                list.capacity() >= size, "capacity below the request"
            )


def test_copies_own_their_storage() raises:
    """A copy must not end up pointing at the block the original holds."""
    for _ in range(8):
        var original = _filled(20, 7)
        var duplicate = original.copy()
        testing.assert_not_equal(
            Int(original.unsafe_ptr()),
            Int(duplicate.unsafe_ptr()),
            "a copy shares the block",
        )
        duplicate[0] = 99
        testing.assert_equal(original[0], 7 * 1000, "the copy wrote through")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
