"""
Tests the predicates on `BigInt`: squares, powers, divisibility, congruence.

Every expected value here was computed with CPython -- `math.isqrt`, an
integer power, `%` -- and never recalled. The interesting cases are the ones
where a predicate could be right by accident: a non-square whose low bits
look like a square's, a perfect power whose exponent is composite and so has
more than one reading, and a divisor or modulus of zero, where the definition
has an answer but the division does not.
"""

from std import testing
from std.testing import assert_equal, assert_false, assert_true

from decimo.bigint.bigint import BigInt
from decimo.bigint.exponential import (
    is_perfect_power,
    is_perfect_square,
    perfect_power,
)
from decimo.bigint.number_theory import congruent, divisible_by


def test_the_squares_and_the_values_next_to_them() raises:
    """Squares pass, their neighbours do not.

    A square and the values one either side of it are the tightest pair of
    cases a square test has, because nothing but the remainder separates
    them.
    """
    for value in ["0", "1", "4", "9", "16", "25", "144", "1048576"]:
        assert_true(
            is_perfect_square(BigInt(value)),
            value + " is a square",
        )
    for value in ["2", "3", "5", "8", "10", "15", "1048575", "1048577"]:
        assert_false(
            is_perfect_square(BigInt(value)),
            value + " is not a square",
        )

    # (10^40)^2, which is eighty digits, and the two values beside it.
    var big = BigInt("10000000000000000000000000000000000000000")
    var square = big * big
    assert_true(is_perfect_square(square), "a forty-digit root squared")
    assert_false(is_perfect_square(square + BigInt.one()), "one past a square")
    assert_false(
        is_perfect_square(square - BigInt.one()), "one short of a square"
    )


def test_a_non_square_can_pass_the_low_bit_filter() raises:
    """The filter is a filter, not the answer.

    Squares modulo 64 take twelve of the sixty-four residues, so a value in
    one of those twelve still has to go to the square root. `105` and
    `10^80 + 64` are both in them and neither is a square, which is what
    makes them worth a test: a filter mistaken for a decision would call
    them squares.
    """
    assert_false(is_perfect_square(BigInt("105")), "105 is not a square")
    assert_false(is_perfect_square(BigInt("113")), "113 is not a square")
    assert_false(
        is_perfect_square(
            BigInt(
                "10000000000000000000000000000000000000000000000000000000000"
                "000000000000000000000064"
            )
        ),
        "10^80 + 64 is not a square",
    )


def test_a_negative_value_is_no_square() raises:
    """No integer squares to a negative value, so the answer is no.

    It is an answer rather than a refusal: the question is about the
    integers, and over the integers it has one.
    """
    for value in ["-1", "-4", "-9", "-1048576"]:
        assert_false(
            is_perfect_square(BigInt(value)),
            value + " is not a square",
        )


def test_the_powers_and_their_largest_exponents() raises:
    """A perfect power comes back with the largest exponent it has.

    `6^10` is the case that separates "an exponent" from "the largest one":
    it is also `(6^5)^2` and `(6^2)^5`, so a decomposition that stopped at
    the first exponent it found could answer 2 or 5. `2^64` is the case that
    needs every prime factor of the exponent divided out in turn.

    The negative values are there because only an odd exponent can reach
    them, and because the sign goes with the base and not with the power:
    `-(7^31)` is not a value with no decomposition, it is `(-7)^31`.
    """
    var cases = [
        ["157775382034845806615042743", "7", "31"],
        ["18446744073709551616", "2", "64"],
        ["60466176", "6", "10"],
        ["1048576", "2", "20"],
        ["144", "12", "2"],
        ["-343", "-7", "3"],
        ["-2147483648", "-2", "31"],
        ["-157775382034845806615042743", "-7", "31"],
    ]
    for row in cases:
        var value = BigInt(row[0])
        var decomposition = perfect_power(value)
        assert_equal(
            String(decomposition[0]),
            row[1],
            "the base of " + row[0],
        )
        assert_equal(
            String(decomposition[1]),
            row[2],
            "the exponent of " + row[0],
        )
        assert_true(is_perfect_power(value), row[0] + " is a power")
        # The pair has to multiply back out to what went in.
        assert_equal(
            String(decomposition[0].power(decomposition[1])),
            row[0],
            "the pair rebuilds " + row[0],
        )


def test_what_is_not_a_power_says_so() raises:
    """A value with no exponent above one comes back as itself to the first.

    The neighbours of `7^31` are the cases that matter: a value one away from
    a high power is not a power at all, and only the roots can tell. The
    negative one is a neighbour too, since the sign alone never rules a
    decomposition out -- an odd exponent carries it.
    """
    for value in [
        "2",
        "3",
        "12",
        "1000003",
        "157775382034845806615042742",
        "157775382034845806615042744",
        "-12",
        "-157775382034845806615042742",
    ]:
        var decomposition = perfect_power(BigInt(value))
        assert_equal(
            String(decomposition[0]), value, value + " is its own base"
        )
        assert_equal(String(decomposition[1]), "1", value + " has no exponent")
        assert_false(is_perfect_power(BigInt(value)), value + " is not a power")


def test_the_three_values_that_are_every_power() raises:
    """Zero, one and minus one have no largest exponent, so the smallest shows.

    `0^k` is 0 and `1^k` is 1 for every `k`, and `(-1)^k` is -1 for every odd
    `k`. There is no largest, so the pair gives the smallest that works, and
    the one for minus one is 3 rather than 2 because an even power cannot be
    negative.
    """
    var cases = [["0", "2"], ["1", "2"], ["-1", "3"]]
    for row in cases:
        var decomposition = perfect_power(BigInt(row[0]))
        assert_equal(String(decomposition[0]), row[0], "the base of " + row[0])
        assert_equal(
            String(decomposition[1]),
            row[1],
            "the exponent of " + row[0],
        )
        assert_equal(
            String(decomposition[0].power(decomposition[1])),
            row[0],
            "and it rebuilds " + row[0],
        )
        assert_true(is_perfect_power(BigInt(row[0])), row[0] + " is a power")


def test_divisibility_reads_both_signs() raises:
    """A sign changes nothing about whether one value divides another."""
    assert_true(divisible_by(BigInt(12), BigInt(3)), "3 divides 12")
    assert_true(divisible_by(BigInt(-12), BigInt(3)), "and divides -12")
    assert_true(divisible_by(BigInt(12), BigInt(-3)), "as does -3")
    assert_true(divisible_by(BigInt(-12), BigInt(-3)), "both negative")
    assert_false(divisible_by(BigInt(13), BigInt(3)), "3 does not divide 13")
    assert_false(divisible_by(BigInt(-13), BigInt(3)), "nor -13")

    assert_true(divisible_by(BigInt(12), BigInt.one()), "one divides all")
    assert_true(divisible_by(BigInt(12), BigInt(12)), "and so does itself")
    assert_true(divisible_by(BigInt.zero(), BigInt(7)), "zero is a multiple")

    # A fifty-digit factor, where the division is the real work.
    var factor = BigInt("1" + "0" * 50 + "7")
    assert_true(
        divisible_by(factor * BigInt(997), factor), "a long multiple divides"
    )
    assert_false(
        divisible_by(factor * BigInt(997) + BigInt.one(), factor),
        "and one past it does not",
    )


def test_a_divisor_of_zero_divides_zero_alone() raises:
    """The only multiple of zero is zero, so that is all it divides.

    The question is answered instead of refused, because nothing is divided:
    `0 == 0 * k` holds for every `k`, and `x == 0 * k` holds for no other `x`.
    """
    assert_true(divisible_by(BigInt.zero(), BigInt.zero()), "zero divides zero")
    for value in ["1", "-1", "7", "-1048576"]:
        assert_false(
            divisible_by(BigInt(value), BigInt.zero()),
            "zero does not divide " + value,
        )


def test_congruence_is_divisibility_of_the_difference() raises:
    """Everything congruence says is a statement about the difference."""
    assert_true(
        congruent(BigInt(17), BigInt(5), BigInt(12)), "17 and 5 modulo 12"
    )
    assert_true(
        congruent(BigInt(5), BigInt(17), BigInt(12)), "and the other way"
    )
    assert_false(
        congruent(BigInt(17), BigInt(6), BigInt(12)), "17 and 6 are not"
    )

    # A negative value against a positive one, where a remainder's sign would
    # be the easy thing to get wrong: -7 and 5 differ by 12.
    assert_true(
        congruent(BigInt(-7), BigInt(5), BigInt(12)), "-7 and 5 modulo 12"
    )
    assert_true(congruent(BigInt(-7), BigInt(-19), BigInt(12)), "both negative")

    # A negative modulus divides what its magnitude divides.
    assert_true(
        congruent(BigInt(17), BigInt(5), BigInt(-12)), "a negative modulus"
    )

    # Every value is congruent to every other modulo one.
    assert_true(
        congruent(BigInt(17), BigInt(5), BigInt.one()), "modulo one, all agree"
    )


def test_a_modulus_of_zero_asks_for_equality() raises:
    """Modulo zero, congruence is equality, which the definition gives.

    The multiples of zero are zero alone, so `a - b` being one of them means
    `a == b`. That keeps `congruent(a, b, m)` equal to
    `divisible_by(a - b, m)` for every modulus, zero included.
    """
    assert_true(
        congruent(BigInt(17), BigInt(17), BigInt.zero()),
        "a value agrees with itself",
    )
    assert_false(
        congruent(BigInt(17), BigInt(5), BigInt.zero()),
        "and with nothing else",
    )
    assert_true(
        congruent(BigInt(-17), BigInt(-17), BigInt.zero()),
        "negative values too",
    )


def test_the_methods_answer_as_the_functions_do() raises:
    """The thin wrappers on the type have to say the same thing."""
    var square = BigInt("1048576")
    assert_true(square.is_perfect_square(), "the method finds the square")
    assert_true(square.is_perfect_power(), "and the power")
    var decomposition = square.perfect_power()
    assert_equal(String(decomposition[0]), "2", "with the same base")
    assert_equal(String(decomposition[1]), "20", "and the same exponent")
    assert_true(BigInt(12).divisible_by(BigInt(3)), "and divides")
    assert_true(BigInt(17).congruent(BigInt(5), BigInt(12)), "and is congruent")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
