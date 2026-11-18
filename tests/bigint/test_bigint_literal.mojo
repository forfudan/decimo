"""
Test BigInt construction from integer literals of any size: the words worked
out at compile time must match what the string constructor builds, around
every word boundary and for both signs.
"""

from std import testing

from decimo.bigint.bigint import BigInt


def _takes_bigint(x: BigInt) -> BigInt:
    return x.copy()


def test_literal_zero() raises:
    """Zero gets its one word and a non-negative sign."""
    var z: BigInt = 0
    z.assert_invariant()
    testing.assert_equal(len(z.words), 1)
    testing.assert_equal(z.words[0], 0)
    testing.assert_false(z.sign)
    testing.assert_equal(String(z), "0")

    var nz: BigInt = -0
    nz.assert_invariant()
    testing.assert_false(nz.sign)
    testing.assert_equal(String(nz), "0")


def test_literal_small() raises:
    """Small literals give the same value as before."""
    var a: BigInt = 1
    var b: BigInt = -1
    var c: BigInt = 42
    var d: BigInt = -1000000
    testing.assert_equal(String(a), "1")
    testing.assert_equal(String(b), "-1")
    testing.assert_equal(String(c), "42")
    testing.assert_equal(String(d), "-1000000")
    testing.assert_equal(len(c.words), 1)


def test_literal_word_boundaries() raises:
    """Literals on each side of 2^64 and 2^128 have the right words."""
    var m: BigInt = 18446744073709551615  # 2^64 - 1
    m.assert_invariant()
    testing.assert_equal(len(m.words), 1)
    testing.assert_equal(m.words[0], UInt64.MAX)

    var p: BigInt = 18446744073709551616  # 2^64
    p.assert_invariant()
    testing.assert_equal(len(p.words), 2)
    testing.assert_equal(p.words[0], 0)
    testing.assert_equal(p.words[1], 1)

    var q: BigInt = 340282366920938463463374607431768211457  # 2^128 + 1
    q.assert_invariant()
    testing.assert_equal(len(q.words), 3)
    testing.assert_equal(q.words[0], 1)
    testing.assert_equal(q.words[1], 0)
    testing.assert_equal(q.words[2], 1)


def test_literal_negative_boundaries() raises:
    """Negative literals past `Int.MIN` keep every word and the sign."""
    var a: BigInt = -9223372036854775808  # Int.MIN
    var b: BigInt = -9223372036854775809  # Int.MIN - 1
    var c: BigInt = -18446744073709551616  # -(2^64)
    a.assert_invariant()
    b.assert_invariant()
    c.assert_invariant()
    testing.assert_true(a.sign and b.sign and c.sign)
    testing.assert_equal(String(a), "-9223372036854775808")
    testing.assert_equal(String(b), "-9223372036854775809")
    testing.assert_equal(String(c), "-18446744073709551616")
    testing.assert_equal(len(c.words), 2)


def test_literal_matches_string() raises:
    """Wide literals equal the same digits given as a string."""
    var a: BigInt = 12345678901234567890123456789012345678901234567890
    var b: BigInt = -98765432109876543210987654321098765432109876543210
    testing.assert_equal(
        a, BigInt("12345678901234567890123456789012345678901234567890")
    )
    testing.assert_equal(
        b, BigInt("-98765432109876543210987654321098765432109876543210")
    )
    a.assert_invariant()
    b.assert_invariant()


def test_literal_comptime_expressions() raises:
    """A literal expression is evaluated exactly before conversion."""
    testing.assert_equal(BigInt(2**200), BigInt(1) << 200)
    testing.assert_equal(BigInt(-(2**1000) + 7), -(BigInt(1) << 1000) + 7)
    var big = BigInt(2**4096 - 1)
    big.assert_invariant()
    testing.assert_equal(len(big.words), 64)
    for i in range(64):
        testing.assert_equal(big.words[i], UInt64.MAX)


def test_literal_implicit_conversion() raises:
    """Wide literals convert implicitly into arguments and operands."""
    testing.assert_equal(
        _takes_bigint(100000000000000000000000000000),
        BigInt("100000000000000000000000000000"),
    )
    var x: BigInt = 5
    testing.assert_equal(
        x + 99999999999999999999999, BigInt("100000000000000000000004")
    )
    testing.assert_true(x < 99999999999999999999999)


def test_literal_does_not_shadow_int_or_scalar() raises:
    """`Int` and `Scalar` values still use their own constructors."""
    var n: Int = -42
    var u = UInt128(1) << 100
    var a: BigInt = n
    var b: BigInt = u
    testing.assert_equal(String(a), "-42")
    testing.assert_equal(b, BigInt(1) << 100)


def test_literal_split_in_halves() raises:
    """Long literals, with zero words inside and none, have the right words."""
    var a: BigInt = 2**320 + 1  # six words, four zeros between
    testing.assert_equal(len(a.words), 6)
    testing.assert_equal(a.words[0], 1)
    for i in range(1, 5):
        testing.assert_equal(a.words[i], 0)
    testing.assert_equal(a.words[5], 1)
    var b: BigInt = 3**2000  # 50 words, none of them zero
    testing.assert_equal(len(b.words), 50)
    testing.assert_equal(b, BigInt(3).power(2000))
    var c: BigInt = -(2**4096 - 1)  # exactly 64 words, all ones
    testing.assert_equal(len(c.words), 64)
    testing.assert_equal(c, -(BigInt(2).power(4096) - BigInt(1)))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
