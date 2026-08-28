"""
Tests the constructors that take words directly: `from_list`, `from_list_unsafe`,
`from_words`, `from_slice` and the raw `raw_words=` initializer.

None of these had a test. They are the only entry points that let a caller hand
`BigUInt` a word that violates the representation invariant, so what they accept
and what they normalise is worth pinning.
"""

from std import testing

from decimo.biguint.biguint import BigUInt


def digits_of_word(word: BigUInt.Word) -> String:
    """Spells one word with leading zeros, as a word below the top one prints.
    """
    var text = String(word)
    var padding = BigUInt.DIGITS_PER_WORD - text.byte_length()
    var result = String("")
    for _ in range(padding):
        result += "0"
    return result + text


def value_of_words(words: List[BigUInt.Word]) -> String:
    """Spells the little-endian word list as a decimal string.

    Independent of the constructors: it walks the list from the top down,
    prints the leading word plainly and every word below it zero-padded.
    """
    var top = len(words) - 1
    while top > 0 and words[top] == 0:
        top -= 1
    var result = String(words[top])
    for i in reversed(range(top)):
        result += digits_of_word(words[i])
    return result


def test_from_words_and_from_list_agree_on_every_word_count() raises:
    """Sweeps word counts 1 to 6 over the interesting word values."""
    var interesting: List[BigUInt.Word] = [
        BigUInt.Word(0),
        BigUInt.Word(1),
        BigUInt.Word(2),
        BigUInt.Word(BigUInt.BASE_HALF),
        BigUInt.Word(BigUInt.BASE_MAX - 1),
        BigUInt.Word(BigUInt.BASE_MAX),
    ]

    for n_words in range(1, 7):
        for start in range(len(interesting)):
            var words = List[BigUInt.Word](capacity=n_words)
            for i in range(n_words):
                words.append(interesting[(start + i) % len(interesting)])

            var expected = value_of_words(words)
            var from_list = BigUInt.from_list(words.copy())
            var unsafe = BigUInt.from_list_unsafe(words.copy())

            testing.assert_equal(String(from_list), expected)
            testing.assert_equal(String(unsafe), expected)
            from_list.assert_invariant("from_list")
            unsafe.assert_invariant("from_list_unsafe")

            # `raw_words=` is the unsafe door: it keeps the list verbatim,
            # leading zero words included, so it is only equal to the others
            # once normalised.
            var raw = BigUInt(raw_words=words.copy())
            testing.assert_equal(len(raw.words), n_words)
            raw.remove_leading_empty_words()
            testing.assert_equal(String(raw), expected)
            raw.assert_invariant("raw_words, normalised")


def test_from_words_matches_from_list() raises:
    """`from_words` is variadic, so it is swept separately at fixed widths."""
    testing.assert_equal(
        String(BigUInt.from_words(BigUInt.Word(BigUInt.BASE_MAX))),
        String(BigUInt.BASE_MAX),
    )
    var two = BigUInt.from_words(BigUInt.Word(1), BigUInt.Word(2))
    testing.assert_equal(String(two), value_of_words([1, 2]))
    var three = BigUInt.from_words(
        BigUInt.Word(0), BigUInt.Word(BigUInt.BASE_MAX), BigUInt.Word(7)
    )
    testing.assert_equal(
        String(three), value_of_words([0, BigUInt.BASE_MAX, 7])
    )
    # `from_words` used to validate the word range and then skip the
    # normalisation its sibling `from_list` performs, so a leading zero word
    # survived into the result: `from_words(5, 0)` printed as
    # "000000000000000005" and `from_words(0, 0)` compared unequal to zero.
    var with_leading_zero = BigUInt.from_words(BigUInt.Word(5), BigUInt.Word(0))
    testing.assert_equal(String(with_leading_zero), "5")
    testing.assert_equal(len(with_leading_zero.words), 1)
    with_leading_zero.assert_invariant("from_words, leading zero word")

    for n_words in range(2, 5):
        var zeros = BigUInt.from_words(BigUInt.Word(0), BigUInt.Word(0))
        if n_words == 3:
            zeros = BigUInt.from_words(
                BigUInt.Word(0), BigUInt.Word(0), BigUInt.Word(0)
            )
        elif n_words == 4:
            zeros = BigUInt.from_words(
                BigUInt.Word(0),
                BigUInt.Word(0),
                BigUInt.Word(0),
                BigUInt.Word(0),
            )
        testing.assert_equal(String(zeros), "0")
        testing.assert_equal(len(zeros.words), 1)
        testing.assert_true(zeros == BigUInt.zero())
        testing.assert_equal(zeros.number_of_digits(), 1)
        zeros.assert_invariant("from_words, all zeros")


def test_a_word_at_the_base_is_rejected() raises:
    """`BASE` itself is the first word value that does not fit."""
    var too_large: List[BigUInt.Word] = [BigUInt.Word(BigUInt.BASE_MAX) + 1]
    with testing.assert_raises():
        _ = BigUInt.from_list(too_large.copy())
    with testing.assert_raises():
        _ = BigUInt.from_words(BigUInt.Word(BigUInt.BASE_MAX) + 1)
    with testing.assert_raises():
        _ = BigUInt.from_words(
            BigUInt.Word(1), BigUInt.Word(BigUInt.BASE_MAX) + 1
        )
    # The largest word that is still accepted.
    _ = BigUInt.from_list([BigUInt.Word(BigUInt.BASE_MAX)])
    _ = BigUInt.from_words(BigUInt.Word(BigUInt.BASE_MAX))


def test_empty_and_all_zero_word_lists_give_a_canonical_zero() raises:
    var empty = List[BigUInt.Word]()
    var from_empty = BigUInt.from_list(empty.copy())
    testing.assert_equal(String(from_empty), "0")
    testing.assert_equal(len(from_empty.words), 1)
    from_empty.assert_invariant("from_list, empty")

    testing.assert_equal(String(BigUInt(raw_words=empty.copy())), "0")
    testing.assert_equal(len(BigUInt(raw_words=empty.copy()).words), 1)

    for n_words in range(1, 6):
        var zeros = List[BigUInt.Word](capacity=n_words)
        for _ in range(n_words):
            zeros.append(BigUInt.Word(0))
        var value = BigUInt.from_list(zeros.copy())
        testing.assert_equal(String(value), "0")
        testing.assert_equal(len(value.words), 1)
        value.assert_invariant("from_list, all zeros")

        var unsafe = BigUInt.from_list_unsafe(zeros.copy())
        testing.assert_equal(String(unsafe), "0")
        testing.assert_equal(len(unsafe.words), 1)
        unsafe.assert_invariant("from_list_unsafe, all zeros")


def test_from_slice_over_every_pair_of_bounds() raises:
    """Every start and end over a five-word value, out-of-range bounds included.
    """
    var words: List[BigUInt.Word] = [
        BigUInt.Word(1),
        BigUInt.Word(BigUInt.BASE_MAX),
        BigUInt.Word(0),
        BigUInt.Word(BigUInt.BASE_HALF),
        BigUInt.Word(9),
    ]
    var value = BigUInt.from_list(words.copy())

    for start in range(-2, 8):
        for end in range(-2, 8):
            var sliced = BigUInt.from_slice(value, (start, end))
            sliced.assert_invariant("from_slice")

            var lo = 0 if start < 0 else start
            var hi = len(words) if end > len(words) else end
            var expected: String
            if hi - lo <= 0:
                expected = "0"
            else:
                var part = List[BigUInt.Word](capacity=hi - lo)
                for i in range(lo, hi):
                    part.append(words[i])
                expected = value_of_words(part)
            testing.assert_equal(
                String(sliced),
                expected,
                "from_slice(" + String(start) + ", " + String(end) + ")",
            )


def test_from_slice_of_the_whole_value_round_trips() raises:
    for n_words in range(1, 7):
        var words = List[BigUInt.Word](capacity=n_words)
        for i in range(n_words):
            words.append(BigUInt.Word(BigUInt.BASE_MAX - i))
        var value = BigUInt.from_list(words.copy())
        var whole = BigUInt.from_slice(value, (0, n_words))
        testing.assert_equal(String(whole), String(value))
        whole.assert_invariant("from_slice, whole value")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
