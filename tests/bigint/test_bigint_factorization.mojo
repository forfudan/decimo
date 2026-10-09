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

"""
Tests factorization for BigInt, and what a factorization decides.

Three things hold these tests down, and none of them is this library.

The expected values were computed in Python -- the factorizations, the
totients, the Moebius values, the divisor counts and sums, and the
multiplicative orders -- and pasted here. Nothing is recalled.

The product is checked back. A factorization is a claim about a product, so
every factorization found here is multiplied out and compared with the input,
and its parts are put to `is_prime`. That catches a wrong answer without
needing to know the right one.

And the one question this cannot answer is asked on purpose. The product of
two primes of a hundred places is given a budget of a thousand iterations,
which is nowhere near enough, and the test is that the call comes back and
says so -- the cofactor is the whole product and the factorization reports
itself incomplete. A function that hung there would be a worse failure than a
wrong answer, and it would not be caught by any test of right answers.
"""

from std import testing
from std.testing import assert_equal, assert_false, assert_true

from decimo.bigint.bigint import BigInt
from decimo.bigint.factorization import (
    Factorization,
    divisor_count,
    divisor_sum,
    divisors,
    euler_phi,
    factor,
    moebius,
    multiplicative_order,
)
from decimo.bigint.primality import is_prime


def _hard_semiprime_parts() raises -> Tuple[BigInt, BigInt]:
    """Two primes of ninety-seven places each, as Python found and checked them.

    Returns:
        The pair. Their product is the hardest input in this file: rho would
        need about `10^24` iterations to split it, so no budget anyone can
        wait for will.
    """
    var p = BigInt(
        "909360444017462602758551187017250289556232945419934964685121025139"
        "8573430055196042278771048950897"
    )
    var q = BigInt(
        "768477317880952896438020930410163402651535059186729639247944670786"
        "2254809605709568816898541422159"
    )
    return (p^, q^)


def _assert_rebuilds(parts: Factorization, x: BigInt, label: String) raises:
    """Checks that a factorization multiplies back to the value it came from.

    Args:
        parts: The factorization under test.
        x: The value it was taken of.
        label: What to say if it does not.

    Raises:
        Error: Propagated from the arithmetic, or from a failed assertion.
    """
    assert_equal(String(parts.value()), String(x), label + ": product")
    for i in range(len(parts.primes)):
        assert_true(
            is_prime(parts.primes[i]),
            label + ": " + parts.primes[i].to_string() + " is prime",
        )
        assert_true(parts.powers[i] >= 1, label + ": the exponent is positive")
    for i in range(1, len(parts.primes)):
        assert_true(
            parts.primes[i - 1] < parts.primes[i],
            label + ": the primes come out in order",
        )


# ===----------------------------------------------------------------------=== #
# factor
# ===----------------------------------------------------------------------=== #


def test_factor_of_the_small_values() raises:
    """Everything here falls to trial division alone."""
    assert_equal(String(factor(BigInt(1))), "1", "one has no prime factors")
    assert_equal(String(factor(BigInt(2))), "2", "2")
    assert_equal(String(factor(BigInt(4))), "2^2", "4")
    assert_equal(String(factor(BigInt(12))), "2^2 * 3", "12")
    assert_equal(String(factor(BigInt(20))), "2^2 * 5", "20")
    assert_equal(String(factor(BigInt(360))), "2^3 * 3^2 * 5", "360")
    assert_equal(String(factor(BigInt(97))), "97", "97, a prime")
    assert_equal(
        String(factor(BigInt(30030))),
        "2 * 3 * 5 * 7 * 11 * 13",
        "30030, the product of the first six primes",
    )


def test_factor_of_a_factorial() raises:
    """Twenty factorial, whose exponents are all different."""
    var x = BigInt("2432902008176640000")
    var parts = factor(x)
    assert_equal(
        String(parts),
        "2^18 * 3^8 * 5^4 * 7^2 * 11 * 13 * 17 * 19",
        "20!",
    )
    assert_true(parts.is_complete(), "20! is factored completely")
    assert_equal(len(parts), 8, "eight distinct primes")
    _assert_rebuilds(parts, x, "20!")


def test_factor_of_the_largest_sixty_four_bit_value() raises:
    """`2^64 - 1`, whose largest factor is past the trial division bound.

    The factors 65537 and 6700417 are both above 65 536, so this is the first
    case where rho has to do the work.
    """
    var x = (BigInt(1) << 64) - BigInt(1)
    var parts = factor(x)
    assert_equal(
        String(parts),
        "3 * 5 * 17 * 257 * 641 * 65537 * 6700417",
        "2^64 - 1",
    )
    _assert_rebuilds(parts, x, "2^64 - 1")


def test_factor_of_a_prime_past_the_trial_division_bound() raises:
    """A prime is returned whole, with no budget spent on splitting it."""
    assert_equal(String(factor(BigInt(1000003))), "1000003", "1000003")
    assert_equal(String(factor(BigInt(65537))), "65537", "65537")
    assert_equal(
        String(factor(BigInt("618970019642690137449562111"))),
        "618970019642690137449562111",
        "2^89 - 1, a Mersenne prime above 2^64",
    )


def test_factor_of_a_semiprime_needs_rho() raises:
    """Products of primes that trial division cannot reach."""
    var cases: List[String] = [
        "1000036000099",
        "4295229443",
        "1000073001431003663",
    ]
    var expected: List[String] = [
        "1000003 * 1000033",
        "65537 * 65539",
        "1000003 * 1000033 * 1000037",
    ]
    for i in range(len(cases)):
        var x = BigInt(cases[i])
        var parts = factor(x)
        assert_equal(String(parts), expected[i], cases[i])
        _assert_rebuilds(parts, x, cases[i])


def test_factor_of_a_cube_of_a_large_prime() raises:
    """Rho has to return the same prime three times over.

    A square or a cube of a prime is the case where rho hands back a factor
    it has already found, and the exponent has to be raised rather than a
    second entry made.
    """
    var x = BigInt("1000009000027000027")
    var parts = factor(x)
    assert_equal(String(parts), "1000003^3", "1000003^3")
    assert_equal(len(parts), 1, "one distinct prime")
    _assert_rebuilds(parts, x, "1000003^3")


def test_factor_gives_up_rather_than_hangs() raises:
    """The product of two primes of ninety-seven places, under a tiny budget.

    This is the question nobody can answer. What is tested is not an answer
    but the shape of the refusal: the call returns, the factorization says it
    is incomplete, and the cofactor is exactly the part that was not split --
    so the caller can tell this from a value that really has no factors.
    """
    var pair = _hard_semiprime_parts()
    assert_true(is_prime(pair[0]), "the first part is prime")
    assert_true(is_prime(pair[1]), "the second part is prime")
    var x = pair[0] * pair[1]

    var parts = factor(x, budget=1000)
    assert_false(parts.is_complete(), "the budget did not reach it")
    assert_equal(len(parts), 0, "and no prime was found at all")
    assert_equal(
        String(parts.cofactor), String(x), "the cofactor is the whole value"
    )
    assert_equal(String(parts.value()), String(x), "which still rebuilds it")
    assert_true(
        String(parts).find("unfactored") >= 0,
        "and it says so when written out",
    )


def test_factor_spends_no_budget_on_the_small_factors() raises:
    """A budget of zero still gets everything trial division can reach."""
    var parts = factor(BigInt(360), budget=0)
    assert_equal(String(parts), "2^3 * 3^2 * 5", "360 at no budget")
    assert_true(parts.is_complete(), "complete without a single rho step")

    # And what trial division cannot reach is left in the cofactor rather
    # than guessed at.
    var x = BigInt("1000036000099")
    var halted = factor(x, budget=0)
    assert_false(halted.is_complete(), "1000036000099 at no budget")
    assert_equal(String(halted.cofactor), String(x), "nothing of it was split")


def test_factor_refuses_what_has_no_factorization() raises:
    """Zero, the negatives, and a negative budget."""
    var raised_zero = False
    try:
        _ = factor(BigInt(0))
    except:
        raised_zero = True
    assert_true(raised_zero, "factor(0)")

    var raised_negative = False
    try:
        _ = factor(BigInt(-12))
    except:
        raised_negative = True
    assert_true(raised_negative, "factor(-12)")

    var raised_budget = False
    try:
        _ = factor(BigInt(12), budget=-1)
    except:
        raised_budget = True
    assert_true(raised_budget, "a negative budget")


# ===----------------------------------------------------------------------=== #
# euler_phi
# ===----------------------------------------------------------------------=== #


def test_euler_phi() raises:
    """The totient, against Python's."""
    var cases: List[String] = [
        "1",
        "2",
        "6",
        "360",
        "1000003",
        "18446744073709551615",
        "1000036000099",
    ]
    var expected: List[String] = [
        "1",
        "1",
        "2",
        "96",
        "1000002",
        "9208981628670443520",
        "1000034000064",
    ]
    for i in range(len(cases)):
        assert_equal(
            String(euler_phi(BigInt(cases[i]))),
            expected[i],
            "euler_phi(" + cases[i] + ")",
        )


def test_euler_phi_raises_when_the_factorization_does_not_finish() raises:
    """No totient is returned for a value whose primes are not known."""
    var pair = _hard_semiprime_parts()
    var raised = False
    try:
        _ = euler_phi(pair[0] * pair[1], budget=1000)
    except:
        raised = True
    assert_true(raised, "euler_phi of an unfactorable product")


# ===----------------------------------------------------------------------=== #
# moebius
# ===----------------------------------------------------------------------=== #


def test_moebius() raises:
    """The Moebius function, against Python's."""
    var cases: List[String] = [
        "1",
        "2",
        "4",
        "6",
        "30",
        "360",
        "1000003",
        "30030",
    ]
    var expected: List[Int] = [1, -1, 0, 1, -1, 0, -1, 1]
    for i in range(len(cases)):
        assert_equal(
            moebius(BigInt(cases[i])),
            expected[i],
            "moebius(" + cases[i] + ")",
        )


# ===----------------------------------------------------------------------=== #
# divisor_count and divisor_sum
# ===----------------------------------------------------------------------=== #


def test_divisor_count() raises:
    """How many divisors, against Python's count."""
    var cases: List[String] = [
        "1",
        "2",
        "12",
        "360",
        "1000003",
        "18446744073709551615",
    ]
    var expected: List[String] = ["1", "2", "6", "24", "2", "128"]
    for i in range(len(cases)):
        assert_equal(
            String(divisor_count(BigInt(cases[i]))),
            expected[i],
            "divisor_count(" + cases[i] + ")",
        )


def test_divisor_sum() raises:
    """The divisors summed, and summed after squaring and cubing.

    The three powers are checked on the same values, because a wrong
    geometric series is easy to write in a way that happens to be right at
    one power.
    """
    var cases: List[String] = [
        "1",
        "2",
        "12",
        "360",
        "1000003",
        "18446744073709551615",
    ]
    var first: List[String] = [
        "1",
        "3",
        "28",
        "1170",
        "1000004",
        "31421980989189888768",
    ]
    var second: List[String] = [
        "1",
        "5",
        "210",
        "201110",
        "1000006000010",
        "394582720119343612458379271559442000000",
    ]
    var third: List[String] = [
        "1",
        "9",
        "2044",
        "55798470",
        "1000009000027000028",
        "6562999663963156580498976583164496958739615059396145582336",
    ]
    for i in range(len(cases)):
        var x = BigInt(cases[i])
        assert_equal(
            String(divisor_sum(x)), first[i], "sigma_1(" + cases[i] + ")"
        )
        assert_equal(
            String(divisor_sum(x, 2)), second[i], "sigma_2(" + cases[i] + ")"
        )
        assert_equal(
            String(divisor_sum(x, 3)), third[i], "sigma_3(" + cases[i] + ")"
        )
        assert_equal(
            String(divisor_sum(x, 0)),
            String(divisor_count(x)),
            "sigma_0 counts the divisors (" + cases[i] + ")",
        )


def test_divisor_sum_refuses_a_negative_power() raises:
    """A sum of reciprocals is not an integer, so it is not returned as one."""
    var raised = False
    try:
        _ = divisor_sum(BigInt(12), -1)
    except:
        raised = True
    assert_true(raised, "divisor_sum(12, -1)")


# ===----------------------------------------------------------------------=== #
# divisors
# ===----------------------------------------------------------------------=== #


def test_divisors_of_small_values() raises:
    """The whole list, in order, as Python produced it."""
    var one = divisors(BigInt(1))
    assert_equal(len(one), 1, "one has one divisor")
    assert_equal(String(one[0]), "1", "and it is one")

    var twelve = divisors(BigInt(12))
    var expected: List[String] = ["1", "2", "3", "4", "6", "12"]
    assert_equal(len(twelve), 6, "twelve has six divisors")
    for i in range(len(expected)):
        assert_equal(String(twelve[i]), expected[i], "divisors(12)")


def test_divisors_of_a_value_with_three_primes() raises:
    """360, where the merge has to interleave three runs."""
    var found = divisors(BigInt(360))
    var expected: List[String] = [
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "8",
        "9",
        "10",
        "12",
        "15",
        "18",
        "20",
        "24",
        "30",
        "36",
        "40",
        "45",
        "60",
        "72",
        "90",
        "120",
        "180",
        "360",
    ]
    assert_equal(len(found), 24, "360 has twenty-four divisors")
    for i in range(len(expected)):
        assert_equal(String(found[i]), expected[i], "divisors(360)")


def test_divisors_agree_with_the_count_and_the_sum() raises:
    """The list, the count and the sum are three routes to the same thing.

    `2^64 - 1` has a hundred and twenty-eight divisors, which is enough for
    the merge to have somewhere to go wrong, and small enough to hold.
    """
    var x = (BigInt(1) << 64) - BigInt(1)
    var found = divisors(x)
    assert_equal(
        String(BigInt(len(found))),
        String(divisor_count(x)),
        "as many divisors as the count says",
    )
    var total = BigInt(0)
    for i in range(len(found)):
        total = total + found[i]
    assert_equal(
        String(total), String(divisor_sum(x)), "and they sum to sigma_1"
    )
    assert_equal(String(found[0]), "1", "the first divisor is one")
    assert_equal(
        String(found[len(found) - 1]), String(x), "and the last is the value"
    )
    for i in range(1, len(found)):
        assert_true(found[i - 1] < found[i], "strictly ascending")
        assert_true(
            (x % found[i]).is_zero(),
            "and every one of them divides (" + found[i].to_string() + ")",
        )


# ===----------------------------------------------------------------------=== #
# multiplicative_order
# ===----------------------------------------------------------------------=== #


def test_multiplicative_order() raises:
    """Orders against Python's, including a composite and a prime modulus."""
    var residues: List[String] = ["3", "2", "10", "2", "7", "1", "2", "5"]
    var moduli: List[String] = [
        "7",
        "7",
        "7",
        "341",
        "360",
        "97",
        "18446744073709551615",
        "2147483647",
    ]
    var expected: List[String] = [
        "6",
        "3",
        "6",
        "10",
        "12",
        "1",
        "64",
        "195225786",
    ]
    for i in range(len(residues)):
        assert_equal(
            String(
                multiplicative_order(BigInt(residues[i]), BigInt(moduli[i]))
            ),
            expected[i],
            "the order of " + residues[i] + " modulo " + moduli[i],
        )


def test_multiplicative_order_of_a_negative_residue() raises:
    """A residue is taken modulo the modulus first, sign and all.

    Minus one has order two modulo anything above two, and the order of a
    residue is the order of what it is congruent to.
    """
    assert_equal(
        String(multiplicative_order(BigInt(-1), BigInt(7))),
        "2",
        "the order of -1 modulo 7",
    )
    assert_equal(
        String(multiplicative_order(BigInt(-5), BigInt(7))),
        String(multiplicative_order(BigInt(2), BigInt(7))),
        "-5 and 2 are the same residue modulo 7",
    )


def test_multiplicative_order_refuses_what_has_no_order() raises:
    """A residue sharing a factor with the modulus, and a modulus of zero."""
    var raised_shared = False
    try:
        _ = multiplicative_order(BigInt(2), BigInt(6))
    except:
        raised_shared = True
    assert_true(raised_shared, "2 and 6 share a factor")

    var raised_modulus = False
    try:
        _ = multiplicative_order(BigInt(2), BigInt(0))
    except:
        raised_modulus = True
    assert_true(raised_modulus, "a modulus of zero")

    assert_equal(
        String(multiplicative_order(BigInt(5), BigInt(1))),
        "1",
        "everything is congruent modulo one",
    )


# ===----------------------------------------------------------------------=== #
# A wide factorization
# ===----------------------------------------------------------------------=== #


def test_the_product_of_the_primes_below_a_hundred() raises:
    """Twenty-five distinct primes, and a divisor count of two to the 25th.

    Every factor is below the trial division bound, so this tests the width
    of the bookkeeping rather than the search: a factorization this wide has
    to stay in order, and the count and the totient are products of
    twenty-five terms each.
    """
    var x = BigInt("2305567963945518424753102147331756070")
    var parts = factor(x)
    assert_true(parts.is_complete(), "complete")
    assert_equal(len(parts), 25, "twenty-five distinct primes")
    _assert_rebuilds(parts, x, "the primorial of 97")
    assert_equal(String(divisor_count(x)), "33554432", "2^25 divisors")
    assert_equal(
        String(euler_phi(x)),
        "277399690427737839953078806118400000",
        "its totient",
    )
    assert_equal(moebius(x), -1, "squarefree with an odd number of primes")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
