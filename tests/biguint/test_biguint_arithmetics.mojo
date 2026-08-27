"""
Test BigUInt arithmetic operations including addition, subtraction, and multiplication.
BigUInt is an unsigned integer type, so it doesn't support negative values.
"""


from std.python import Python
from std import testing
from std.testing import assert_equal, assert_true
from decimo.biguint.biguint import BigUInt
from decimo.biguint.arithmetics import (
    add,
    add_inplace,
    floor_divide_by_word_inplace,
    floor_divide_by_uint64_inplace,
    subtract,
    subtract_inplace,
    subtract_no_check_inplace,
)
from decimo.tests import (
    TestCase,
    load_test_cases,
    parse_file,
    random_decimal_string,
)

comptime file_path_arithmetics = (
    "tests/biguint/test_data/biguint_arithmetics.toml"
)
comptime file_path_truncate_divide = (
    "tests/biguint/test_data/biguint_truncate_divide.toml"
)


def _set_max_str_digits(limit: Int) raises:
    """Set Python's int-to-string digit limit (Python 3.11+). No-op if unavailable.
    """
    try:
        Python.import_module("sys").set_int_max_str_digits(limit)
    except:
        pass


def test_biguint_arithmetics() raises:
    # Load test cases from TOML file
    _set_max_str_digits(500000)

    var toml = parse_file(file_path_arithmetics)
    var test_cases: List[TestCase]

    # -------------------------------------------------------
    # Testing BigUInt addition
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "addition_tests")
    assert_true(len(test_cases) > 0, "No addition test cases found")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigUInt(test_case.a) + BigUInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) + Python.int(test_case.b))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    assert_equal(
        count_wrong,
        0,
        "Addition: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigUInt inplace addition
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "addition_tests")
    assert_true(len(test_cases) > 0, "No inplace addition test cases found")
    count_wrong = 0
    for test_case in test_cases:
        var result = BigUInt(test_case.a)
        result += BigUInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) + Python.int(test_case.b))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    assert_equal(
        count_wrong,
        0,
        "Inplace addition: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigUInt subtraction
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "subtraction_tests")
    assert_true(len(test_cases) > 0, "No subtraction test cases found")
    count_wrong = 0
    for test_case in test_cases:
        var result = BigUInt(test_case.a) - BigUInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) - Python.int(test_case.b))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    assert_equal(
        count_wrong,
        0,
        "Subtraction: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigUInt multiplication
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "multiplication_tests")
    assert_true(len(test_cases) > 0, "No multiplication test cases found")
    count_wrong = 0
    for test_case in test_cases:
        var result = BigUInt(test_case.a) * BigUInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) * Python.int(test_case.b))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    assert_equal(
        count_wrong,
        0,
        "Multiplication: Mojo and Python results differ. See above.",
    )

    # Special case: Test underflow handling
    test_cases = load_test_cases(toml, "subtraction_underflow")
    assert_true(len(test_cases) > 0, "No underflow test cases found")
    for test_case in test_cases:
        try:
            var result = BigUInt(test_case.a) - BigUInt(test_case.b)
            print(
                "Implementation allows underflow, result is: " + String(result)
            )
        except:
            print("Implementation correctly throws error on underflow")


def test_biguint_truncate_divide() raises:
    # Load test cases from TOML file
    _set_max_str_digits(500000)

    var toml = parse_file(file_path_truncate_divide)
    var test_cases: List[TestCase]

    # -------------------------------------------------------
    # Testing BigUInt truncate division
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "truncate_divide_tests")
    assert_true(len(test_cases) > 0, "No truncate division test cases found")
    var count_wrong = 0
    for test_case in test_cases:
        var result = BigUInt(test_case.a) // BigUInt(test_case.b)
        var mojo_str = String(result)
        var py_str = String(Python.int(test_case.a) // Python.int(test_case.b))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    assert_equal(
        count_wrong,
        0,
        "Truncate divide: Mojo and Python results differ. See above.",
    )


def test_biguint_truncate_divide_random_numbers_against_python() raises:
    # print("------------------------------------------------------")
    # print("Testing BigUInt truncate division on random numbers with python...")

    _set_max_str_digits(500000)

    var number_a: String
    var number_b: String
    var decimo_result: String
    var python_result: String

    for _test_case in range(10):
        number_a = random_decimal_string(123)
        number_b = random_decimal_string(45)
        decimo_result = String(BigUInt(number_a) // BigUInt(number_b))
        python_result = String(Python.int(number_a) // Python.int(number_b))
        assert_equal(
            lhs=decimo_result,
            rhs=python_result,
            msg="Python int division does not match BigUInt division\n"
            + "number a: \n"
            + number_a
            + "\n\nnumber b: \n"
            + number_b
            + "\n\nDecimo BigUInt division: \n"
            + decimo_result
            + "\n\nPython int division: \n"
            + python_result,
        )
    # print("BigUInt truncate division tests passed!")


def test_biguint_divide_across_the_dispatch_boundaries_against_python() raises:
    """Cross-checks `//` against Python across every size the dispatch splits on.

    `floor_divide()` picks a different routine for a divisor of one word, two
    words, three-or-four words, and anything larger, and the three-or-four-word
    routine additionally behaves differently for each residue of the dividend
    word count mod four. The two random cross-checks in this file use 2 214
    digits over 810 and 200 000 over 14 000 — both far above the
    Burnikel-Ziegler cutoff, so neither ever reaches the small-divisor paths.
    That is how a three-word divisor could lose a factor of 10^9 for over a
    year without a red test.

    This walks the divisor from 1 to 40 digits and the dividend from the
    divisor's length up to 90 digits, which crosses every boundary in the
    dispatch, and compares against Python at each step.
    """
    _set_max_str_digits(500000)

    for divisor_digits in range(1, 41):
        for dividend_digits in range(divisor_digits, 91, 7):
            var number_b = _bz_digit_run(divisor_digits, 7 * divisor_digits + 3)
            var number_a = _bz_digit_run(
                dividend_digits, 13 * dividend_digits + divisor_digits
            )
            var case_label = (
                String("a=")
                + String(dividend_digits)
                + " digits, b="
                + String(divisor_digits)
                + " digits"
            )
            assert_equal(
                lhs=String(BigUInt(number_a) // BigUInt(number_b)),
                rhs=String(Python.int(number_a) // Python.int(number_b)),
                msg="floor division differs from Python for " + case_label,
            )
            assert_equal(
                lhs=String(BigUInt(number_a) % BigUInt(number_b)),
                rhs=String(Python.int(number_a) % Python.int(number_b)),
                msg="modulo differs from Python for " + case_label,
            )


def test_biguint_truncate_divide_huge_random_numbers_against_python() raises:
    # Some two hundred thousand digits over a divisor of some fourteen
    # thousand. The smaller random cases above already clear
    # `CUTOFF_BURNIKEL_ZIEGLER` (32 words, 288 digits) and so take the
    # Burnikel-Ziegler path too; what this size adds is the depth. A divisor
    # of ~1,570 words recurses six levels deep on blocks of n = 2048 words,
    # against two levels on n = 128 for the cases above, and the dividend
    # splits into thirteen blocks, so the remainder is carried across twelve
    # iterations of the outer loop rather than two. At that block size the
    # multiplications *inside* the division cross `CUTOFF_KARATSUBA` (64) and
    # `CUTOFF_TOOM3` (256), which the smaller cases never reach. One case
    # rather than ten: the size is what is being covered, and it costs a
    # fraction of a second.

    _set_max_str_digits(500000)

    var decimo_result: String
    var python_result: String

    var number_a = random_decimal_string(12345)
    var number_b = random_decimal_string(789)
    decimo_result = String(BigUInt(number_a) // BigUInt(number_b))
    python_result = String(Python.int(number_a) // Python.int(number_b))
    assert_equal(
        lhs=decimo_result,
        rhs=python_result,
        msg="Python int division does not match BigUInt division\n"
        + "number a: \n"
        + number_a
        + "\n\nnumber b: \n"
        + number_b
        + "\n\nDecimo BigUInt division: \n"
        + decimo_result
        + "\n\nPython int division: \n"
        + python_result,
    )


def _bz_digit_run(count: Int, seed: Int) -> String:
    """Builds a `count`-digit decimal string with no leading zero."""
    var out = String(1 + seed % 9)
    var x = seed
    for j in range(count - 1):
        x = (x * 1103515245 + 12345 + j) % 2147483647
        out += String(x % 10)
    return out^


def test_biguint_divide_short_operands_of_every_word_count() raises:
    """`//` and `%` are correct for every small dividend/divisor word count.

    `floor_divide()` routes any divisor of three or four words to
    `floor_divide_by_uint128()`, which consumes the dividend four words at a
    time. A dividend whose word count is not a multiple of four leaves a short
    leading group, and that group's own quotient used to be discarded: a
    seven-word dividend over a three-word divisor came back a factor of 10^9
    too small, and a three-word dividend - where the leading group *is* the
    whole number - produced a `BigUInt` with no words at all, which faults the
    next operation that reads `words[len(words) - 1]`.

    Neither shape is exotic: `23334504672441144935 // 1854056525350022197`
    crashed. The sweep below walks every dividend length from one to nine
    words against every divisor length from one to five, which covers all four
    residues of the group size, and pins each result with `q * b + r == a`
    and `0 <= r < b`.
    """
    for divisor_words in range(1, 6):
        for dividend_words in range(1, 10):
            if dividend_words < divisor_words:
                continue
            var b = BigUInt(
                _bz_digit_run(9 * divisor_words, 30 * divisor_words + 7)
            )
            var a = BigUInt(
                _bz_digit_run(
                    9 * dividend_words, 91 * dividend_words + divisor_words
                )
            )
            var case_label = (
                String("a=")
                + String(dividend_words)
                + " words, b="
                + String(divisor_words)
                + " words"
            )
            var q = a // b
            var r = a % b
            assert_equal(
                String(q * b + r), String(a), "q*b+r != a for " + case_label
            )
            assert_true(r < b, "remainder not below divisor for " + case_label)
            assert_true(
                len(q.words) > 0, "quotient has no words for " + case_label
            )

    # The exact pair that crashed, and one that came back 10^9 too small.
    assert_equal(
        String(
            BigUInt("23334504672441144935") // BigUInt("1854056525350022197")
        ),
        "12",
    )
    assert_equal(
        String(
            BigUInt("807907260199438794337606998415891117067948916721663647060")
            // BigUInt("2822897927280927212")
        ),
        "286197829681228157267625044899046282569",
    )


def test_biguint_divide_bz_block_padding_sizes() raises:
    """Burnikel-Ziegler stays correct at every divisor block padding.

    The divisor is padded to `n = j * 2^k` words, with `2^k` the smallest
    power of two that brings the block size `j` down to the cutoff, so that
    halving `n` stays even all the way down to `j` - the recursion falls back
    to schoolbook the moment it meets an odd block size. `j` is derived from
    the divisor rather than pinned at the cutoff, which is what keeps the
    padding small; the sizes below land on different `(j, k)` pairs, including
    ones needing almost none and ones needing almost a whole block.

    `q * b + r == a` with `r < b` pins each result without a stored expected
    value.
    """
    var divisor_digits = [400, 600, 900, 1800, 3600]
    var dividend_scales = [2, 3]

    for i in range(len(divisor_digits)):
        var nb = divisor_digits[i]
        var b = BigUInt(_bz_digit_run(nb, 20260823 + i))
        for j in range(len(dividend_scales)):
            var na = nb * dividend_scales[j] // 2 + 7 * j
            var a = BigUInt(_bz_digit_run(na, 27182818 + i * 3 + j))

            var q = a // b
            var r = a - q * b
            var case_label = (
                String("a=")
                + String(na)
                + " digits, b="
                + String(nb)
                + " digits"
            )
            assert_equal(
                String(q * b + r), String(a), "q*b+r != a for " + case_label
            )
            assert_true(r < b, "remainder out of range for " + case_label)


def test_biguint_divide_dividend_on_a_block_boundary() raises:
    """Burnikel-Ziegler stays correct when the dividend fills its blocks.

    `a = b * (10^9)^k` puts the dividend's top block exactly on the divisor,
    so the first 2-by-1 division inside the recursion returns a quotient of
    `n + 1` words instead of `n`. That is the case an "add one more block"
    guard used to try to prevent, by incrementing the block count without
    lengthening the dividend - which left the first 2-by-1 division a block
    short of its 2n words and produced a wrong quotient. `k` is swept across
    the block size so that some dividends land exactly on `t * n` words and
    others just miss.

    The maximal case is included separately: an all-nines dividend over a
    divisor whose leading word is the smallest normalization allows, which is
    what makes that first quotient use its full extra word.
    """
    for words_b in [33, 34, 40, 48, 64, 65, 70, 96, 129]:
        var b = BigUInt(_bz_digit_run(words_b * 9, 5_000_003 + words_b))
        for k in range(words_b - 1, words_b + 4):
            var shifted = BigUInt(String("1") + String("0") * (9 * k))
            var exact = b * shifted
            for offset in range(3):
                var a = exact + BigUInt(offset) * (b - BigUInt(1))
                var q = a // b
                var r = a - q * b
                var case_label = (
                    String("b=")
                    + String(words_b)
                    + " words, k="
                    + String(k)
                    + ", offset="
                    + String(offset)
                )
                assert_equal(
                    String(q * b + r),
                    String(a),
                    "q*b+r != a for " + case_label,
                )
                assert_true(r < b, "remainder out of range for " + case_label)

        # Widest possible first quotient: dividend all nines, divisor's
        # leading word just over the 500_000_000 normalization threshold.
        var small_lead = BigUInt(
            String("5") + String("0") * (words_b * 9 - 2) + "1"
        )
        for extra_words in range(3):
            var wide = BigUInt(String("9") * ((2 * words_b + extra_words) * 9))
            var q_wide = wide // small_lead
            var r_wide = wide - q_wide * small_lead
            var wide_label = (
                String("maximal b=")
                + String(words_b)
                + " words, extra="
                + String(extra_words)
            )
            assert_equal(
                String(q_wide * small_lead + r_wide),
                String(wide),
                "q*b+r != a for " + wide_label,
            )
            assert_true(
                r_wide < small_lead,
                "remainder out of range for " + wide_label,
            )


def test_biguint_inplace_arithmetics_match_out_of_place() raises:
    """Every in-place operation agrees with its out-of-place twin.

    `subtract_inplace()` used to fall through its equal-operands branch: it set
    `x` to a single zero word and then, without returning, ran the vectorized
    subtraction anyway, over `len(y.words)` words of a value now one word long.
    That read and wrote past the end of `x` and `normalize_borrows()` turned
    the result into a plausible number - `x -= x` returned `877910460` for one
    18-word operand, and was wrong at every width from one word up.

    It was reached far beyond `-=`: the Burnikel-Ziegler base case computes its
    remainder as `a_slice -= q * b_slice`, and a block that divides exactly
    makes those operands equal, so long division returned wrong quotients for a
    whole class of dividends.

    The in-place single-word divisions had their own faults: both left a value
    with no words at all when the quotient was zero, and the `UInt32` one read
    its loop bound from the already-shortened list, skipping a word.
    """
    var widths = [1, 2, 3, 4, 8, 17, 18, 33, 64, 65, 100]
    var by_uint32 = UInt32(999_999_937)
    var by_uint64 = UInt64(999_999_999_999_999_989)
    var as_biguint_32 = BigUInt(String("999999937"))
    var as_biguint_64 = BigUInt(String("999999999999999989"))

    for i in range(len(widths)):
        var wx = widths[i]
        var x = BigUInt(_bz_digit_run(wx * 9, 900_001 + wx))

        for j in range(len(widths)):
            var wy = widths[j]
            if wy > wx:
                continue
            # `equal = 1` is the case that used to fail: x and y the same value.
            for equal in range(2):
                var y = x.copy() if equal == 1 else BigUInt(
                    _bz_digit_run(wy * 9, 700_003 + wy)
                )
                if y > x:
                    continue
                var case_label = (
                    String("x=")
                    + String(wx)
                    + " words, y="
                    + String(wy)
                    + " words, equal="
                    + String(equal)
                )

                var summed = x.copy()
                add_inplace(summed, y)
                assert_equal(
                    String(summed),
                    String(add(x, y)),
                    "add_inplace " + case_label,
                )

                var expected_difference = String(subtract(x, y))

                var difference = x.copy()
                subtract_inplace(difference, y)
                assert_equal(
                    String(difference),
                    expected_difference,
                    "subtract_inplace " + case_label,
                )
                assert_equal(
                    len(difference.words) > 0,
                    True,
                    "subtract_inplace left no words for " + case_label,
                )

                var unchecked = x.copy()
                subtract_no_check_inplace(unchecked, y)
                assert_equal(
                    String(unchecked),
                    expected_difference,
                    "subtract_no_check_inplace " + case_label,
                )

                var operator_form = x.copy()
                operator_form -= y
                assert_equal(
                    String(operator_form),
                    expected_difference,
                    "__isub__ " + case_label,
                )

        # The in-place single-word divisions, including the quotient-is-zero
        # case that used to leave the value with no words.
        var quotient_32 = x.copy()
        floor_divide_by_word_inplace(quotient_32, by_uint32)
        assert_equal(
            String(quotient_32),
            String(x // as_biguint_32),
            "floor_divide_by_word_inplace at " + String(wx) + " words",
        )

        var quotient_64 = x.copy()
        floor_divide_by_uint64_inplace(quotient_64, by_uint64)
        assert_equal(
            String(quotient_64),
            String(x // as_biguint_64),
            "floor_divide_by_uint64_inplace at " + String(wx) + " words",
        )


def _digit_run(digit: String, count: Int) -> String:
    var out = String("")
    for _ in range(count):
        out += digit
    return out^


def test_biguint_add_subtract_carry_chains() raises:
    """Carry and borrow cascades that run the whole length of the operand.

    `10^n - 1` is a run of `999_999_999` words, so adding to it carries through
    every one of them and subtracting borrows back through every one. The digit
    counts sweep across the word boundary at every multiple of nine, and the
    second operand is short so that the carry has to leave the common region
    and walk the rest of the accumulator on its own.
    """
    _set_max_str_digits(500000)

    for n_digits in range(1, 120):
        var nines = _digit_run("9", n_digits)
        var x = BigUInt(nines)
        var py_x = Python.int(nines)
        var label = " at " + String(n_digits) + " digits"

        for n_short in range(1, 4):
            var short = _digit_run("9", n_short)
            var y = BigUInt(short)
            var py_y = Python.int(short)
            var py_sum = String(py_x + py_y)
            var py_difference = String(py_x - py_y)

            assert_equal(String(add(x, y)), py_sum, "add" + label)
            var accumulator = x.copy()
            add_inplace(accumulator, y)
            assert_equal(String(accumulator), py_sum, "add_inplace" + label)

            if py_x >= py_y:
                assert_equal(
                    String(subtract(x, y)), py_difference, "subtract" + label
                )
                var minuend = x.copy()
                subtract_inplace(minuend, y)
                assert_equal(
                    String(minuend), py_difference, "subtract_inplace" + label
                )
                var minuend_unchecked = x.copy()
                subtract_no_check_inplace(minuend_unchecked, y)
                assert_equal(
                    String(minuend_unchecked),
                    py_difference,
                    "subtract_no_check_inplace" + label,
                )

        # x + x doubles every word at once; x - x is the equal-operands path.
        assert_equal(String(add(x, x)), String(py_x + py_x), "x + x" + label)
        var self_sum = x.copy()
        add_inplace(self_sum, x)
        assert_equal(String(self_sum), String(py_x + py_x), "x += x" + label)
        var self_difference = x.copy()
        subtract_inplace(self_difference, x)
        assert_equal(String(self_difference), "0", "x -= x" + label)


def main() raises:
    # test_biguint_arithmetics()
    # test_biguint_truncate_divide()
    # test_biguint_truncate_divide_random_numbers_against_python()
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
    # print("All BigUInt arithmetic tests passed!")
    # print("------------------------------------------------------")
