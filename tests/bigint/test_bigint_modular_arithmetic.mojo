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
Tests for the quadratic residue symbols, modular square roots and the Chinese
remainder theorem.

Every expectation below was computed by a Python reference that works from the
definitions rather than from the algorithms under test: it factors the modulus
and takes a product of Legendre symbols by Euler's criterion, where `jacobi`
walks the binary reciprocity loop and never factors anything. The two share no
algorithm, so agreement is evidence rather than a tautology.

That reference was itself checked against properties it does not encode --
quadratic reciprocity between distinct odd primes, both supplementary laws,
multiplicativity in each argument, and Euler's criterion against simply
counting the squares modulo a prime. A sweep of 5,607 cases was run against
it, of which the tables here are a readable subset: dense small grids, the
boundary conventions one at a time, and a few multi-word values to exercise
the parts of the reduction that a single-word operand never reaches.

Each row is one string rather than a tuple of numbers, because `mojo format`
expands a list of numbers to one element per line.
"""

from std import testing

from decimo.bigint.bigint import BigInt
from decimo.bigint.number_theory import (
    crt,
    jacobi,
    kronecker,
    legendre,
    sqrt_mod,
)


def _parts(row: String) raises -> List[String]:
    """Splits a table row on spaces.

    Args:
        row: The row, whose fields are separated by single spaces.

    Returns:
        The fields, as owned strings.

    Raises:
        Error: Propagated from the split.
    """
    var out = List[String]()
    for piece in row.split(" "):
        out.append(String(piece))
    return out^


def _numbers(field: String) raises -> List[BigInt]:
    """Parses a comma-separated field, where `-` means the empty list.

    Args:
        field: The field to parse.

    Returns:
        The values, or an empty list for `-`.

    Raises:
        Error: Propagated from the parse.
    """
    var out = List[BigInt]()
    if field == "-":
        return out^
    for piece in field.split(","):
        out.append(BigInt.from_string(String(piece)))
    return out^


# ===----------------------------------------------------------------------=== #
# Jacobi
# ===----------------------------------------------------------------------=== #


def test_jacobi_table() raises:
    """The Jacobi symbol over a grid of numerators and odd positive moduli.

    The moduli include composites -- 9, 15, 21, 25, 45, 105 -- because that is
    where the symbol stops being a statement about squares and becomes a
    product of Legendre symbols, and where a dropped reciprocity step shows.
    Negative numerators are included because they are reduced by a floor
    modulo before the loop sees them.
    """
    var table: List[String] = [
        "-7 1 1",
        "-4 1 1",
        "-3 1 1",
        "-1 1 1",
        "0 1 1",
        "1 1 1",
        "2 1 1",
        "3 1 1",
        "4 1 1",
        "5 1 1",
        "8 1 1",
        "11 1 1",
        "13 1 1",
        "-7 3 -1",
        "-4 3 -1",
        "-3 3 0",
        "-1 3 -1",
        "0 3 0",
        "1 3 1",
        "2 3 -1",
        "3 3 0",
        "4 3 1",
        "5 3 -1",
        "8 3 -1",
        "11 3 -1",
        "13 3 1",
        "-7 5 -1",
        "-4 5 1",
        "-3 5 -1",
        "-1 5 1",
        "0 5 0",
        "1 5 1",
        "2 5 -1",
        "3 5 -1",
        "4 5 1",
        "5 5 0",
        "8 5 -1",
        "11 5 1",
        "13 5 -1",
        "-7 7 0",
        "-4 7 -1",
        "-3 7 1",
        "-1 7 -1",
        "0 7 0",
        "1 7 1",
        "2 7 1",
        "3 7 -1",
        "4 7 1",
        "5 7 -1",
        "8 7 1",
        "11 7 1",
        "13 7 -1",
        "-7 9 1",
        "-4 9 1",
        "-3 9 0",
        "-1 9 1",
        "0 9 0",
        "1 9 1",
        "2 9 1",
        "3 9 0",
        "4 9 1",
        "5 9 1",
        "8 9 1",
        "11 9 1",
        "13 9 1",
        "-7 11 1",
        "-4 11 -1",
        "-3 11 -1",
        "-1 11 -1",
        "0 11 0",
        "1 11 1",
        "2 11 -1",
        "3 11 1",
        "4 11 1",
        "5 11 1",
        "8 11 -1",
        "11 11 0",
        "13 11 -1",
        "-7 15 1",
        "-4 15 -1",
        "-3 15 0",
        "-1 15 -1",
        "0 15 0",
        "1 15 1",
        "2 15 1",
        "3 15 0",
        "4 15 1",
        "5 15 0",
        "8 15 1",
        "11 15 -1",
        "13 15 -1",
        "-7 21 0",
        "-4 21 1",
        "-3 21 0",
        "-1 21 1",
        "0 21 0",
        "1 21 1",
        "2 21 -1",
        "3 21 0",
        "4 21 1",
        "5 21 1",
        "8 21 -1",
        "11 21 -1",
        "13 21 -1",
        "-7 25 1",
        "-4 25 1",
        "-3 25 1",
        "-1 25 1",
        "0 25 0",
        "1 25 1",
        "2 25 1",
        "3 25 1",
        "4 25 1",
        "5 25 0",
        "8 25 1",
        "11 25 1",
        "13 25 1",
        "-7 45 -1",
        "-4 45 1",
        "-3 45 0",
        "-1 45 1",
        "0 45 0",
        "1 45 1",
        "2 45 -1",
        "3 45 0",
        "4 45 1",
        "5 45 0",
        "8 45 -1",
        "11 45 1",
        "13 45 -1",
        "-7 105 0",
        "-4 105 1",
        "-3 105 0",
        "-1 105 1",
        "0 105 0",
        "1 105 1",
        "2 105 1",
        "3 105 0",
        "4 105 1",
        "5 105 0",
        "8 105 1",
        "11 105 -1",
        "13 105 1",
    ]
    for row in table:
        var f = _parts(row)
        testing.assert_equal(
            jacobi(BigInt.from_string(f[0]), BigInt.from_string(f[1])),
            Int(f[2]),
            "jacobi(" + f[0] + "/" + f[1] + ")",
        )


def test_jacobi_multiword() raises:
    """The Jacobi symbol where both operands run past a single 64-bit word.

    The moduli are products of known primes, so the reference could take the
    product of Legendre symbols without factoring anything. The last row has a
    numerator sharing a factor with the modulus, where the answer is zero.
    """
    var table: List[String] = [
        "18446744073709551617 1000000000000000009 1",
        "-1180591620717411303427 2305843009213693951 -1",
        "1000000000000000000000000000000 100000000000000000039 1",
        "157775382034845806615042743 618970019642690137449562111 1",
        (
            "-9999999999999999999999999999999999999993"
            " 10000000000000000000000000000033 -1"
        ),
        "12345678901234567890 2305843009213693971752587082923245559 1",
        "-98765432109876543211 230584300921369395189927877359334064089 1",
        "3 230584300921369397265186585651658620798350896234006576801 1",
        (
            "1267650600228229401496703205383"
            " 10000000000000000007800000000000000001521 1"
        ),
        "5000000000000000045 2305843009213693971752587082923245559 0",
    ]
    for row in table:
        var f = _parts(row)
        testing.assert_equal(
            jacobi(BigInt.from_string(f[0]), BigInt.from_string(f[1])),
            Int(f[2]),
            "jacobi(" + f[0] + "/" + f[1] + ")",
        )


def test_jacobi_rejects_bad_denominator() raises:
    """An even or non-positive denominator raises rather than answering."""
    var bad: List[String] = ["2", "4", "0", "-3", "-8"]
    for text in bad:
        var raised = False
        try:
            _ = jacobi(BigInt(3), BigInt.from_string(text))
        except:
            raised = True
        testing.assert_true(raised, "jacobi(3/" + text + ") must raise")


# ===----------------------------------------------------------------------=== #
# Legendre
# ===----------------------------------------------------------------------=== #


def test_legendre_matches_jacobi_on_odd_primes() raises:
    """Over a prime the two symbols are the same function.

    This is the whole reason `legendre` shares the implementation, so it is
    worth pinning rather than assuming.
    """
    var primes: List[Int] = [3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 97, 101]
    for p in primes:
        for a in range(-20, 21):
            testing.assert_equal(
                legendre(BigInt(a), BigInt(p)),
                jacobi(BigInt(a), BigInt(p)),
                "legendre vs jacobi at " + String(a) + "/" + String(p),
            )


def test_legendre_counts_squares() raises:
    """A `1` from `legendre` really does mean a square modulo that prime.

    The squares are found by squaring every residue, which is the definition
    and shares nothing with the symbol's own computation.
    """
    var primes: List[Int] = [3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41]
    for p in primes:
        var squares = List[Bool](length=p, fill=False)
        for x in range(1, p):
            squares[(x * x) % p] = True
        for a in range(p):
            var expected = 0 if a == 0 else (1 if squares[a] else -1)
            testing.assert_equal(
                legendre(BigInt(a), BigInt(p)),
                expected,
                "legendre(" + String(a) + "/" + String(p) + ")",
            )


def test_legendre_rejects_two_and_even() raises:
    """Two and the even moduli raise: the symbol is undefined there.

    A composite odd modulus does not raise. Primality is a documented
    precondition and verifying it would cost more than the symbol, so the
    answer there is the Jacobi symbol, which this pins so the choice is not
    changed by accident.
    """
    var bad: List[String] = ["2", "1", "0", "-7", "8"]
    for text in bad:
        var raised = False
        try:
            _ = legendre(BigInt(3), BigInt.from_string(text))
        except:
            raised = True
        testing.assert_true(raised, "legendre(3/" + text + ") must raise")

    # Composite but odd: answers, and answers the Jacobi symbol.
    testing.assert_equal(
        legendre(BigInt(2), BigInt(9)), jacobi(BigInt(2), BigInt(9)), "2/9"
    )


# ===----------------------------------------------------------------------=== #
# Kronecker
# ===----------------------------------------------------------------------=== #


def test_kronecker_table() raises:
    """The Kronecker symbol over every shape of modulus.

    The grid spans negative, zero, even and odd moduli, and includes a
    numerator of zero and of plus or minus one, which is where the boundary
    conventions differ from one another.
    """
    var table: List[String] = [
        "-5 -12 -1",
        "-3 -12 0",
        "-1 -12 1",
        "0 -12 0",
        "1 -12 1",
        "2 -12 0",
        "3 -12 0",
        "7 -12 1",
        "8 -12 0",
        "-5 -8 1",
        "-3 -8 1",
        "-1 -8 -1",
        "0 -8 0",
        "1 -8 1",
        "2 -8 0",
        "3 -8 -1",
        "7 -8 1",
        "8 -8 0",
        "-5 -7 -1",
        "-3 -7 -1",
        "-1 -7 1",
        "0 -7 0",
        "1 -7 1",
        "2 -7 1",
        "3 -7 -1",
        "7 -7 0",
        "8 -7 1",
        "-5 -4 -1",
        "-3 -4 -1",
        "-1 -4 -1",
        "0 -4 0",
        "1 -4 1",
        "2 -4 0",
        "3 -4 1",
        "7 -4 1",
        "8 -4 0",
        "-5 -3 -1",
        "-3 -3 0",
        "-1 -3 1",
        "0 -3 0",
        "1 -3 1",
        "2 -3 -1",
        "3 -3 0",
        "7 -3 1",
        "8 -3 -1",
        "-5 -2 1",
        "-3 -2 1",
        "-1 -2 -1",
        "0 -2 0",
        "1 -2 1",
        "2 -2 0",
        "3 -2 -1",
        "7 -2 1",
        "8 -2 0",
        "-5 -1 -1",
        "-3 -1 -1",
        "-1 -1 -1",
        "0 -1 1",
        "1 -1 1",
        "2 -1 1",
        "3 -1 1",
        "7 -1 1",
        "8 -1 1",
        "-5 0 0",
        "-3 0 0",
        "-1 0 1",
        "0 0 0",
        "1 0 1",
        "2 0 0",
        "3 0 0",
        "7 0 0",
        "8 0 0",
        "-5 1 1",
        "-3 1 1",
        "-1 1 1",
        "0 1 1",
        "1 1 1",
        "2 1 1",
        "3 1 1",
        "7 1 1",
        "8 1 1",
        "-5 2 -1",
        "-3 2 -1",
        "-1 2 1",
        "0 2 0",
        "1 2 1",
        "2 2 0",
        "3 2 -1",
        "7 2 1",
        "8 2 0",
        "-5 3 1",
        "-3 3 0",
        "-1 3 -1",
        "0 3 0",
        "1 3 1",
        "2 3 -1",
        "3 3 0",
        "7 3 1",
        "8 3 -1",
        "-5 4 1",
        "-3 4 1",
        "-1 4 1",
        "0 4 0",
        "1 4 1",
        "2 4 0",
        "3 4 1",
        "7 4 1",
        "8 4 0",
        "-5 6 -1",
        "-3 6 0",
        "-1 6 -1",
        "0 6 0",
        "1 6 1",
        "2 6 0",
        "3 6 0",
        "7 6 1",
        "8 6 0",
        "-5 8 -1",
        "-3 8 -1",
        "-1 8 1",
        "0 8 0",
        "1 8 1",
        "2 8 0",
        "3 8 -1",
        "7 8 1",
        "8 8 0",
        "-5 12 1",
        "-3 12 0",
        "-1 12 -1",
        "0 12 0",
        "1 12 1",
        "2 12 0",
        "3 12 0",
        "7 12 1",
        "8 12 0",
        "-5 24 -1",
        "-3 24 0",
        "-1 24 -1",
        "0 24 0",
        "1 24 1",
        "2 24 0",
        "3 24 0",
        "7 24 1",
        "8 24 0",
    ]
    for row in table:
        var f = _parts(row)
        testing.assert_equal(
            kronecker(BigInt.from_string(f[0]), BigInt.from_string(f[1])),
            Int(f[2]),
            "kronecker(" + f[0] + "/" + f[1] + ")",
        )


def test_kronecker_multiword() raises:
    """The Kronecker symbol over large negative and even moduli."""
    var table: List[String] = [
        "18446744073709551617 -256000000000000002304 1",
        "-18446744073709551617 -256000000000000002304 -1",
        "1000000000000000000001 4611686018427387902 -1",
        "1000000000000000000000 4611686018427387902 0",
        "-7 -214748364800000000083751862272 1",
    ]
    for row in table:
        var f = _parts(row)
        testing.assert_equal(
            kronecker(BigInt.from_string(f[0]), BigInt.from_string(f[1])),
            Int(f[2]),
            "kronecker(" + f[0] + "/" + f[1] + ")",
        )


def test_kronecker_extends_jacobi() raises:
    """On an odd positive modulus the Kronecker symbol is the Jacobi symbol.

    That is what makes it an extension rather than a different function.
    """
    for n in range(1, 60, 2):
        for a in range(-25, 26):
            testing.assert_equal(
                kronecker(BigInt(a), BigInt(n)),
                jacobi(BigInt(a), BigInt(n)),
                "kronecker vs jacobi at " + String(a) + "/" + String(n),
            )


def test_kronecker_conventions() raises:
    """The boundary conventions, one at a time.

    These are choices rather than consequences, so each is stated here
    separately from the grid above: a reader changing one should see exactly
    which rule broke.
    """
    # (a/0) is 1 for a = +-1 and 0 otherwise.
    testing.assert_equal(kronecker(BigInt(1), BigInt(0)), 1, "1/0")
    testing.assert_equal(kronecker(BigInt(-1), BigInt(0)), 1, "-1/0")
    testing.assert_equal(kronecker(BigInt(0), BigInt(0)), 0, "0/0")
    testing.assert_equal(kronecker(BigInt(7), BigInt(0)), 0, "7/0")

    # (a/-1) is -1 exactly when a is negative.
    testing.assert_equal(kronecker(BigInt(5), BigInt(-1)), 1, "5/-1")
    testing.assert_equal(kronecker(BigInt(0), BigInt(-1)), 1, "0/-1")
    testing.assert_equal(kronecker(BigInt(-5), BigInt(-1)), -1, "-5/-1")

    # (a/2) is read off a modulo 8, and is 0 for even a.
    testing.assert_equal(kronecker(BigInt(1), BigInt(2)), 1, "1/2")
    testing.assert_equal(kronecker(BigInt(7), BigInt(2)), 1, "7/2")
    testing.assert_equal(kronecker(BigInt(3), BigInt(2)), -1, "3/2")
    testing.assert_equal(kronecker(BigInt(5), BigInt(2)), -1, "5/2")
    testing.assert_equal(kronecker(BigInt(4), BigInt(2)), 0, "4/2")

    # And (a/1) is the empty product.
    for a in range(-6, 7):
        testing.assert_equal(
            kronecker(BigInt(a), BigInt(1)), 1, String(a) + "/1"
        )


def test_kronecker_second_supplementary_law() raises:
    """`(2/n)` is `1` exactly when `n` is one or seven modulo eight.

    The implementation never writes this law down for an odd modulus -- it
    falls out of the reciprocity loop -- so checking it is a real test.
    """
    var n = 1
    while n < 200:
        var expected = 1 if (n % 8 == 1 or n % 8 == 7) else -1
        testing.assert_equal(
            kronecker(BigInt(2), BigInt(n)), expected, "2/" + String(n)
        )
        n += 2


# ===----------------------------------------------------------------------=== #
# Modular square root
# ===----------------------------------------------------------------------=== #


def test_sqrt_mod_table() raises:
    """Square roots modulo primes of each shape.

    The moduli cover two, the `3 mod 4` primes that need one exponentiation,
    and the `1 mod 4` primes that need the full Tonelli-Shanks loop --
    including 41, 97 and 257, where `p - 1` holds 8, 32 and 256 as its power
    of two and the loop runs several passes. `none` marks a non-residue.
    """
    var table: List[String] = [
        "0 2 0",
        "1 2 1",
        "0 3 0",
        "1 3 1",
        "2 3 none",
        "0 7 0",
        "1 7 1",
        "2 7 3",
        "3 7 none",
        "4 7 2",
        "5 7 none",
        "6 7 none",
        "0 11 0",
        "1 11 1",
        "2 11 none",
        "3 11 5",
        "4 11 2",
        "5 11 4",
        "6 11 none",
        "7 11 none",
        "8 11 none",
        "9 11 3",
        "10 11 none",
        "0 13 0",
        "1 13 1",
        "2 13 none",
        "3 13 4",
        "4 13 2",
        "5 13 none",
        "6 13 none",
        "7 13 none",
        "8 13 none",
        "9 13 3",
        "10 13 6",
        "11 13 none",
        "12 13 5",
        "0 17 0",
        "1 17 1",
        "2 17 6",
        "3 17 none",
        "4 17 2",
        "5 17 none",
        "6 17 none",
        "7 17 none",
        "8 17 5",
        "9 17 3",
        "10 17 none",
        "11 17 none",
        "12 17 none",
        "13 17 8",
        "0 41 0",
        "1 41 1",
        "2 41 17",
        "3 41 none",
        "4 41 2",
        "5 41 13",
        "6 41 none",
        "7 41 none",
        "8 41 7",
        "9 41 3",
        "10 41 16",
        "11 41 none",
        "12 41 none",
        "13 41 none",
        "0 97 0",
        "1 97 1",
        "2 97 14",
        "3 97 10",
        "4 97 2",
        "5 97 none",
        "6 97 43",
        "7 97 none",
        "8 97 28",
        "9 97 3",
        "10 97 none",
        "11 97 37",
        "12 97 20",
        "13 97 none",
        "0 257 0",
        "1 257 1",
        "2 257 60",
        "3 257 none",
        "4 257 2",
        "5 257 none",
        "6 257 none",
        "7 257 none",
        "8 257 120",
        "9 257 3",
        "10 257 none",
        "11 257 36",
        "12 257 none",
        "13 257 28",
    ]
    for row in table:
        var f = _parts(row)
        var a = BigInt.from_string(f[0])
        var p = BigInt.from_string(f[1])
        var got = sqrt_mod(a, p)
        if f[2] == "none":
            testing.assert_false(
                Bool(got), f[0] + " is no square modulo " + f[1]
            )
        else:
            testing.assert_true(Bool(got), f[0] + " is a square modulo " + f[1])
            var root = got.value().copy()
            testing.assert_equal(
                String(root),
                f[2],
                "sqrt_mod(" + f[0] + ", " + f[1] + ")",
            )
            # The smaller root is promised, so the other one must not be it
            # unless they coincide.
            testing.assert_true(
                root + root <= p,
                "the smaller root is returned for " + f[0] + " modulo " + f[1],
            )


def test_sqrt_mod_squares_back() raises:
    """Over large primes the answer is checked by squaring it, not by a table.

    Squaring needs no oracle, which is the point: the expectation here cannot
    be wrong. Whether a root exists at all comes from Euler's criterion in the
    reference.
    """
    var table: List[String] = [
        "2 1000000000000000009 yes",
        "3 1000000000000000009 yes",
        "5 1000000000000000009 yes",
        "7 1000000000000000009 no",
        "11 1000000000000000009 no",
        "1234567 1000000000000000009 no",
        "1000000000000000008 1000000000000000009 yes",
        "1000000000000000007 1000000000000000009 yes",
        "2 2305843009213693951 yes",
        "3 2305843009213693951 no",
        "5 2305843009213693951 yes",
        "7 2305843009213693951 no",
        "11 2305843009213693951 no",
        "1234567 2305843009213693951 no",
        "2305843009213693950 2305843009213693951 no",
        "2305843009213693949 2305843009213693951 no",
        "2 100000000000000000039 yes",
        "3 100000000000000000039 no",
        "5 100000000000000000039 yes",
        "7 100000000000000000039 yes",
        "11 100000000000000000039 yes",
        "1234567 100000000000000000039 yes",
        "100000000000000000038 100000000000000000039 no",
        "100000000000000000037 100000000000000000039 no",
        "2 618970019642690137449562111 yes",
        "3 618970019642690137449562111 no",
        "5 618970019642690137449562111 yes",
        "7 618970019642690137449562111 yes",
        "11 618970019642690137449562111 no",
        "1234567 618970019642690137449562111 no",
        "618970019642690137449562110 618970019642690137449562111 no",
        "618970019642690137449562109 618970019642690137449562111 no",
    ]
    for row in table:
        var f = _parts(row)
        var a = BigInt.from_string(f[0])
        var p = BigInt.from_string(f[1])
        var got = sqrt_mod(a, p)
        if f[2] == "no":
            testing.assert_false(
                Bool(got), f[0] + " is no square modulo " + f[1]
            )
        else:
            testing.assert_true(Bool(got), f[0] + " is a square modulo " + f[1])
            var root = got.value().copy()
            testing.assert_equal(
                String((root * root) % p),
                String(a % p),
                "the root of " + f[0] + " modulo " + f[1] + " squares back",
            )


def test_sqrt_mod_zero_and_two() raises:
    """Zero has the single root zero, and squaring is the identity modulo two.
    """
    var primes: List[Int] = [2, 3, 5, 7, 11, 13, 17, 41, 97]
    for p in primes:
        var root = sqrt_mod(BigInt(0), BigInt(p))
        testing.assert_true(Bool(root), "zero is a square modulo " + String(p))
        testing.assert_equal(
            String(root.value().copy()), "0", "the root of zero is zero"
        )

    for a in range(-4, 5):
        var root = sqrt_mod(BigInt(a), BigInt(2))
        testing.assert_true(Bool(root), "everything is a square modulo two")
        testing.assert_equal(
            String(root.value().copy()),
            String(((a % 2) + 2) % 2),
            "modulo two the root is the value itself",
        )


def test_sqrt_mod_rejects_small_modulus() raises:
    """A modulus below two raises: there is no prime there."""
    var bad: List[String] = ["1", "0", "-7"]
    for text in bad:
        var raised = False
        try:
            _ = sqrt_mod(BigInt(4), BigInt.from_string(text))
        except:
            raised = True
        testing.assert_true(raised, "sqrt_mod(4, " + text + ") must raise")


def test_sqrt_mod_non_residue_returns_nothing() raises:
    """A non-residue is answered with nothing, not with an exception.

    Half the residues modulo an odd prime are non-residues, so this is the
    ordinary path and not an error. The count is checked too: a prime field
    has exactly `(p - 1) / 2` non-zero squares.
    """
    var primes: List[Int] = [3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 97]
    for p in primes:
        var found = 0
        for a in range(1, p):
            if sqrt_mod(BigInt(a), BigInt(p)):
                found += 1
        testing.assert_equal(
            found,
            (p - 1) // 2,
            "half the non-zero residues modulo " + String(p) + " are squares",
        )


# ===----------------------------------------------------------------------=== #
# Chinese remainder theorem
# ===----------------------------------------------------------------------=== #


def test_crt_table() raises:
    """Congruence systems, coprime and not, consistent and not.

    The reference solved each one by scanning every residue below the least
    common multiple, which is as independent of the merge loop as an oracle
    can be. `none none` marks a system with no solution.
    """
    var table: List[String] = [
        "- - 0 1",
        "0 1 0 1",
        "5 7 5 7",
        "-3 7 4 7",
        "2,3,2 3,5,7 23 105",
        "1,4,6 3,5,7 34 105",
        "3,4 4,5 19 20",
        "1,3 2,4 3 4",
        "1,2 2,4 none none",
        "2,8 6,12 8 12",
        "2,9 6,12 none none",
        "0,0,0 2,3,5 0 30",
        "-1,-1,-1 3,4,5 59 60",
        "6,6 10,15 6 30",
        "6,7 10,15 none none",
        "7,7,7 1,1,1 0 1",
    ]
    for row in table:
        var f = _parts(row)
        var residues = _numbers(f[0])
        var moduli = _numbers(f[1])
        var got = crt(residues, moduli)
        if f[2] == "none":
            testing.assert_false(
                Bool(got), "no solution for " + f[0] + " mod " + f[1]
            )
        else:
            testing.assert_true(
                Bool(got), "a solution for " + f[0] + " mod " + f[1]
            )
            var pair = got.value().copy()
            testing.assert_equal(
                String(pair[0]), f[2], "the residue for " + f[0] + "/" + f[1]
            )
            testing.assert_equal(
                String(pair[1]), f[3], "the modulus for " + f[0] + "/" + f[1]
            )


def test_crt_solution_satisfies_every_congruence() raises:
    """The answer is put back into each congruence it came from.

    This checks the property the function promises rather than a stored
    number, so it would catch a merge that produced some other valid-looking
    pair.
    """
    var systems: List[String] = [
        "2,3,2 3,5,7",
        "1,4,6 3,5,7",
        "1,3 2,4",
        "2,8 6,12",
        "6,6 10,15",
        "-1,-1,-1 3,4,5",
        "11,13,17,19 12,13,17,19",
    ]
    for system in systems:
        var f = _parts(system)
        var residues = _numbers(f[0])
        var moduli = _numbers(f[1])
        var got = crt(residues, moduli)
        testing.assert_true(Bool(got), "solvable: " + system)
        var pair = got.value().copy()
        for i in range(len(moduli)):
            testing.assert_equal(
                String(pair[0] % moduli[i]),
                String(((residues[i] % moduli[i]) + moduli[i]) % moduli[i]),
                "congruence " + String(i) + " of " + system,
            )
            testing.assert_true(
                (pair[1] % moduli[i]).is_zero(),
                "the modulus is a multiple of " + String(moduli[i]),
            )
        testing.assert_true(
            not pair[0].is_negative() and pair[0] < pair[1],
            "the solution is reduced into range for " + system,
        )


def test_crt_large_coprime_system() raises:
    """A system of three multi-word coprime moduli."""
    var f = _parts(
        "123456789,987654321,555555555"
        " 1000000000000000009,2305843009213693951,100000000000000000039"
        " 63022131411641227102579207683584299360420224809442801667"
        " 230584300921369397265186585651658620798350896234006576801"
    )
    var residues = _numbers(f[0])
    var moduli = _numbers(f[1])
    var got = crt(residues, moduli)
    testing.assert_true(Bool(got), "the large system is solvable")
    var pair = got.value().copy()
    testing.assert_equal(String(pair[0]), f[2], "the large solution")
    testing.assert_equal(String(pair[1]), f[3], "the large modulus")


def test_crt_empty_system() raises:
    """The empty system is solved by zero modulo one.

    Every integer is congruent modulo one, so the empty intersection is all of
    them. That also makes the function foldable from an empty start.
    """
    var residues = List[BigInt]()
    var moduli = List[BigInt]()
    var got = crt(residues, moduli)
    testing.assert_true(Bool(got), "the empty system has a solution")
    var pair = got.value().copy()
    testing.assert_equal(String(pair[0]), "0", "zero")
    testing.assert_equal(String(pair[1]), "1", "modulo one")


def test_crt_rejects_malformed_input() raises:
    """Mismatched lengths and a non-positive modulus raise.

    An inconsistent system returns nothing, but these are not systems at all,
    so they are errors rather than answers.
    """
    var raised = False
    try:
        var residues: List[BigInt] = [BigInt(1), BigInt(2)]
        var moduli: List[BigInt] = [BigInt(3)]
        _ = crt(residues, moduli)
    except:
        raised = True
    testing.assert_true(raised, "two residues and one modulus must raise")

    for bad in [0, -5]:
        raised = False
        try:
            var residues: List[BigInt] = [BigInt(1), BigInt(2)]
            var moduli: List[BigInt] = [BigInt(3), BigInt(bad)]
            _ = crt(residues, moduli)
        except:
            raised = True
        testing.assert_true(
            raised, "a modulus of " + String(bad) + " must raise"
        )


# ===----------------------------------------------------------------------=== #
# The methods on BigInt
# ===----------------------------------------------------------------------=== #


def test_methods_match_free_functions() raises:
    """The `BigInt` methods are wrappers and must not drift from the functions.
    """
    for a in range(-12, 13):
        for n in range(-12, 13):
            testing.assert_equal(
                BigInt(a).kronecker(BigInt(n)),
                kronecker(BigInt(a), BigInt(n)),
                "kronecker method at " + String(a) + "/" + String(n),
            )
        for n in range(1, 26, 2):
            testing.assert_equal(
                BigInt(a).jacobi(BigInt(n)),
                jacobi(BigInt(a), BigInt(n)),
                "jacobi method at " + String(a) + "/" + String(n),
            )

    var primes: List[Int] = [3, 5, 7, 11, 13, 17, 41, 97]
    for p in primes:
        for a in range(-12, 13):
            testing.assert_equal(
                BigInt(a).legendre(BigInt(p)),
                legendre(BigInt(a), BigInt(p)),
                "legendre method at " + String(a) + "/" + String(p),
            )
            var method = BigInt(a).sqrt_mod(BigInt(p))
            var plain = sqrt_mod(BigInt(a), BigInt(p))
            testing.assert_equal(
                Bool(method),
                Bool(plain),
                "sqrt_mod method agrees on existence",
            )
            if method:
                testing.assert_equal(
                    String(method.value().copy()),
                    String(plain.value().copy()),
                    "sqrt_mod method agrees on the root",
                )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
