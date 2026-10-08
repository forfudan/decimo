"""
Tests the sequences on `BigInt`: Fibonacci, Lucas and the double factorial.

Fast doubling reaches `F(n)` in about `log2(n)` steps rather than `n`, which
is what makes a large index possible and also what makes it worth testing:
the identities it uses are easy to write down one term out, and an index
whose bits are all ones exercises every branch of the descent. So the values
below come from CPython -- an independent fast doubling for the two
sequences, a loop for the double factorial -- and the indices include the
places where the arithmetic changes size.

Two identities check the large values that are too long to write out:
`L(n)^2 - 5*F(n)^2 == 4*(-1)^n` ties the two sequences together, and
`(2m)!! == 2^m * m!` ties the double factorial to the factorial already in
the library.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigint.bigint import BigInt
from decimo.bigint.special import double_factorial, factorial, fibonacci, lucas


def test_the_fibonacci_numbers_at_the_indices_that_matter() raises:
    """Zero, one, two, ten, ninety and a thousand.

    Ninety is where a Fibonacci number outgrows 64 bits, so it is the index
    an implementation carrying its state in a machine word would answer
    wrongly. A thousand is long enough that the doubling has to be right at
    every step, since one slip changes every digit after it.
    """
    var cases = [
        ["0", "0"],
        ["1", "1"],
        ["2", "1"],
        ["3", "2"],
        ["4", "3"],
        ["10", "55"],
        ["90", "2880067194370816120"],
        [
            "1000",
            (
                "4346655768693745643568852767504062580256466051737178040248172908"
                "9536555417949051890403879840079255169295922593080322634775209689"
                "623239873322471161642996440906533187938298969649928516003704476"
                "137795166849228875"
            ),
        ],
    ]
    for row in cases:
        assert_equal(
            String(fibonacci(BigInt(row[0]))),
            row[1],
            "F(" + row[0] + ")",
        )


def test_the_lucas_numbers_at_the_same_indices() raises:
    """`L(0)` is two, not one, which is the whole difference from Fibonacci.

    Starting at two is what a Lucas number is, and computing it as
    `2*F(n+1) - F(n)` has to reproduce that at the bottom of the sequence as
    well as the top.
    """
    var cases = [
        ["0", "2"],
        ["1", "1"],
        ["2", "3"],
        ["3", "4"],
        ["10", "123"],
        ["90", "6440026026380244498"],
        [
            "1000",
            (
                "9719417773590817520798198207932647373779787915534568508272808108"
                "4772518818444815269080619149045968297679578305403209347401163036"
                "907660573971740862463751801641201490284097309096322681531675707"
                "666695323797578127"
            ),
        ],
    ]
    for row in cases:
        assert_equal(
            String(lucas(BigInt(row[0]))),
            row[1],
            "L(" + row[0] + ")",
        )


def test_the_two_sequences_satisfy_their_identity() raises:
    """`L(n)^2 - 5*F(n)^2 == 4*(-1)^n`, over the first forty indices.

    This ties the two together without a table: if the doubling were one
    term out in either, the identity would fail, and it holds for no other
    pair of sequences. It also covers the odd and even branches of the
    descent at every index rather than at the chosen ones.
    """
    for n in range(40):
        var f = fibonacci(BigInt(n))
        var l = lucas(BigInt(n))
        var expected = BigInt(4) if n % 2 == 0 else BigInt(-4)
        assert_equal(
            String(l * l - BigInt(5) * f * f),
            String(expected),
            "the identity at " + String(n),
        )


def test_the_recurrence_holds_where_the_doubling_is_used() raises:
    """Each value is the sum of the two before it, at indices far apart.

    The doubling never adds consecutive terms, so this checks it against the
    definition it is standing in for. The indices are chosen so that some
    are reached through the even branch and some through the odd.
    """
    for n in [2, 3, 7, 8, 63, 64, 90, 127, 128, 500, 1000]:
        var previous = fibonacci(BigInt(n - 1))
        var two_back = fibonacci(BigInt(n - 2))
        assert_equal(
            String(fibonacci(BigInt(n))),
            String(previous + two_back),
            "F(" + String(n) + ") is the sum of the two before",
        )
        var l_previous = lucas(BigInt(n - 1))
        var l_two_back = lucas(BigInt(n - 2))
        assert_equal(
            String(lucas(BigInt(n))),
            String(l_previous + l_two_back),
            "L(" + String(n) + ") likewise",
        )


def test_a_ten_thousandth_index_is_the_right_size() raises:
    """`F(10000)` is 2090 digits, and the identity still holds there.

    Writing the value out would be two thousand characters of test, so the
    claim is made in two pieces instead: the digit count, which no wrong
    answer of a different magnitude would match, and the identity, which no
    wrong answer of the same magnitude would satisfy.
    """
    var f = fibonacci(BigInt(10000))
    var l = lucas(BigInt(10000))
    assert_equal(String(f).byte_length(), 2090, "F(10000) has 2090 digits")
    assert_equal(String(l).byte_length(), 2090, "L(10000) has 2090 digits")
    assert_equal(
        String(l * l - BigInt(5) * f * f),
        "4",
        "and the identity holds at an even index",
    )
    # The first and last few digits, which pin the value rather than its size.
    assert_true(
        String(f).startswith("33644764876431783266"), "the leading digits"
    )
    assert_true(
        String(f).endswith("66073310059947366875"), "and the trailing ones"
    )


def test_a_negative_index_alternates_in_sign() raises:
    """`F(-n)` is `(-1)^(n+1) F(n)` and `L(-n)` is `(-1)^n L(n)`.

    The recurrence runs backwards as readily as forwards, so the sequence
    continues to the left of zero rather than stopping there. These are the
    values that keep `F(n-1) = F(n+1) - F(n)` true across zero, which is why
    they are answered instead of refused.
    """
    var cases = [
        ["-1", "1", "-1"],
        ["-2", "-1", "3"],
        ["-3", "2", "-4"],
        ["-10", "-55", "123"],
    ]
    for row in cases:
        assert_equal(
            String(fibonacci(BigInt(row[0]))),
            row[1],
            "F(" + row[0] + ")",
        )
        assert_equal(
            String(lucas(BigInt(row[0]))),
            row[2],
            "L(" + row[0] + ")",
        )

    # The backwards recurrence, which is what those signs are for.
    for n in range(-12, 2):
        assert_equal(
            String(fibonacci(BigInt(n))),
            String(fibonacci(BigInt(n + 2)) - fibonacci(BigInt(n + 1))),
            "F(" + String(n) + ") from the two above it",
        )


def test_the_double_factorial_against_a_loop() raises:
    """Every other integer multiplied, from a table CPython produced."""
    var cases = [
        ["-1", "1"],
        ["0", "1"],
        ["1", "1"],
        ["2", "2"],
        ["3", "3"],
        ["4", "8"],
        ["5", "15"],
        ["9", "945"],
        ["10", "3840"],
        ["20", "3715891200"],
        ["21", "13749310575"],
        ["50", "520469842636666622693081088000000"],
        [
            "100",
            (
                "3424322470251197624824643289520818597511867505371919882791565446"
                "3488000000000000"
            ),
        ],
    ]
    for row in cases:
        assert_equal(
            String(double_factorial(BigInt(row[0]))),
            row[1],
            row[0] + "!!",
        )


def test_an_even_double_factorial_is_a_factorial_and_a_shift() raises:
    """`(2m)!! == 2^m * m!`, which is how the even case is computed.

    Checking it against `factorial()` is checking the shortcut against the
    long way round, for every `m` up to sixty rather than for the one value a
    table would hold.
    """
    for m in range(60):
        var expected = factorial(BigInt(m)) << m
        assert_equal(
            String(double_factorial(BigInt(2 * m))),
            String(expected),
            "(2*" + String(m) + ")!!",
        )


def test_an_odd_double_factorial_is_the_factorial_over_the_even_part() raises:
    """`(2m+1)!! == (2m+1)! / (2^m * m!)`, the other half of the same pair.

    The odd case has its own product, so it needs its own check: the odd
    factors are what is left of a factorial once the even ones are divided
    out.
    """
    for m in range(40):
        var whole = factorial(BigInt(2 * m + 1))
        var even_part = factorial(BigInt(m)) << m
        assert_equal(
            String(double_factorial(BigInt(2 * m + 1))),
            String(whole.truncate_divide(even_part)),
            "(2*" + String(m) + "+1)!!",
        )


def test_a_long_double_factorial_is_the_right_size() raises:
    """`200!!` is 189 digits, and the leading ones are what they are."""
    var value = double_factorial(BigInt(200))
    assert_equal(String(value).byte_length(), 189, "200!! has 189 digits")
    assert_true(
        String(value).startswith("118305033024544"), "and starts as computed"
    )


def test_the_arguments_that_are_refused() raises:
    """The caps and the one argument that leaves the integers.

    `(-3)!!` is -1 under the usual extension but `(-5)!!` is a third, so the
    sequence stops being integral below -1 and the type says so rather than
    inventing a value. The two caps turn an argument that would exhaust
    memory into an error.
    """
    for argument in ["-2", "-3", "-1000"]:
        var raised = False
        try:
            _ = double_factorial(BigInt(argument))
        except:
            raised = True
        assert_true(raised, argument + "!! was answered")

    var raised = False
    try:
        _ = double_factorial(BigInt("1000001"))
    except:
        raised = True
    assert_true(raised, "a double factorial past the cap was answered")

    for index in ["10000001", "-10000001"]:
        raised = False
        try:
            _ = fibonacci(BigInt(index))
        except:
            raised = True
        assert_true(raised, "F(" + index + ") was answered")

        raised = False
        try:
            _ = lucas(BigInt(index))
        except:
            raised = True
        assert_true(raised, "L(" + index + ") was answered")


def test_the_methods_answer_as_the_functions_do() raises:
    """The thin wrappers on the type have to say the same thing."""
    assert_equal(String(BigInt(10).fibonacci()), "55", "the method for F(10)")
    assert_equal(String(BigInt(10).lucas()), "123", "and for L(10)")
    assert_equal(String(BigInt(10).double_factorial()), "3840", "and for 10!!")
    assert_equal(
        String(BigInt(-10).fibonacci()), "-55", "and for a negative index"
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
