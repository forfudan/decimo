"""Tests for BigInt number theory operations: GCD, Extended GCD, LCM,
modular exponentiation, and modular inverse."""

from std import testing
from decimo.bigint.bigint import BigInt
from decimo.bigint.number_theory import (
    gcd,
    extended_gcd,
    lcm,
    mod_pow,
    mod_inverse,
)


# ===----------------------------------------------------------------------=== #
# GCD tests
# ===----------------------------------------------------------------------=== #


def test_gcd_zero_cases() raises:
    """Tests gcd involving zeros follows Python convention."""
    testing.assert_equal(String(gcd(BigInt(0), BigInt(0))), "0")
    testing.assert_equal(String(gcd(BigInt(12), BigInt(0))), "12")
    testing.assert_equal(String(gcd(BigInt(0), BigInt(15))), "15")
    testing.assert_equal(String(gcd(BigInt(-7), BigInt(0))), "7")
    testing.assert_equal(String(gcd(BigInt(0), BigInt(-9))), "9")


def test_gcd_basic() raises:
    """Tests basic GCD of small positive integers."""
    testing.assert_equal(String(gcd(BigInt(12), BigInt(8))), "4")
    testing.assert_equal(String(gcd(BigInt(48), BigInt(18))), "6")
    testing.assert_equal(String(gcd(BigInt(100), BigInt(75))), "25")
    testing.assert_equal(String(gcd(BigInt(17), BigInt(13))), "1")
    testing.assert_equal(String(gcd(BigInt(7), BigInt(7))), "7")
    testing.assert_equal(String(gcd(BigInt(1), BigInt(100))), "1")
    testing.assert_equal(String(gcd(BigInt(54), BigInt(24))), "6")
    testing.assert_equal(String(gcd(BigInt(270), BigInt(192))), "6")


def test_gcd_negative() raises:
    """Tests GCD is always non-negative regardless of input signs."""
    testing.assert_equal(String(gcd(BigInt(-12), BigInt(8))), "4")
    testing.assert_equal(String(gcd(BigInt(12), BigInt(-8))), "4")
    testing.assert_equal(String(gcd(BigInt(-12), BigInt(-8))), "4")
    testing.assert_equal(String(gcd(BigInt(-48), BigInt(18))), "6")
    testing.assert_equal(String(gcd(BigInt(-48), BigInt(-18))), "6")


def test_gcd_commutativity() raises:
    """Tests gcd(a, b) == gcd(b, a)."""
    testing.assert_equal(
        String(gcd(BigInt(48), BigInt(18))),
        String(gcd(BigInt(18), BigInt(48))),
    )
    testing.assert_equal(
        String(gcd(BigInt(100), BigInt(75))),
        String(gcd(BigInt(75), BigInt(100))),
    )
    testing.assert_equal(
        String(gcd(BigInt(17), BigInt(13))),
        String(gcd(BigInt(13), BigInt(17))),
    )


def test_gcd_one() raises:
    """Tests gcd(1, n) = 1 and gcd(n, 1) = 1."""
    testing.assert_equal(String(gcd(BigInt(1), BigInt(999999))), "1")
    testing.assert_equal(String(gcd(BigInt(999999), BigInt(1))), "1")
    testing.assert_equal(String(gcd(BigInt(1), BigInt(1))), "1")


def test_gcd_same_value() raises:
    """Tests gcd(n, n) = |n|."""
    testing.assert_equal(String(gcd(BigInt(42), BigInt(42))), "42")
    testing.assert_equal(String(gcd(BigInt(-42), BigInt(42))), "42")
    testing.assert_equal(String(gcd(BigInt(-42), BigInt(-42))), "42")


def test_gcd_common_factor() raises:
    """Tests gcd(a*m, b*m) = m when gcd(a,b) = 1."""
    # gcd(17*m, 13*m) = m since gcd(17,13) = 1
    var m = BigInt(123456789)
    var a = m * BigInt(17)
    var b = m * BigInt(13)
    testing.assert_equal(String(gcd(a, b)), "123456789")


def test_gcd_powers_of_two() raises:
    """Tests GCD of powers of two uses the binary GCD fast path."""
    # gcd(2^16, 2^8) = 2^8 = 256
    var a = BigInt(1) << 16
    var b = BigInt(1) << 8
    testing.assert_equal(String(gcd(a, b)), "256")

    # gcd(2^32, 2^16) = 2^16 = 65536
    var c = BigInt(1) << 32
    var d = BigInt(1) << 16
    testing.assert_equal(String(gcd(c, d)), "65536")

    # gcd(2^64, 2^32) = 2^32 = 4294967296
    var e = BigInt(1) << 64
    var f = BigInt(1) << 32
    testing.assert_equal(String(gcd(e, f)), "4294967296")


def test_gcd_large_coprime() raises:
    """Tests large coprime primes."""
    var p = BigInt(1000000007)
    var q = BigInt(999999937)
    testing.assert_equal(String(gcd(p, q)), "1")


# ===----------------------------------------------------------------------=== #
# Extended GCD tests
# ===----------------------------------------------------------------------=== #


def test_extended_gcd_basic() raises:
    """Tests extended GCD with known Bézout coefficients."""
    # gcd(35, 15) = 5, with 35*1 + 15*(-2) = 5
    var r = extended_gcd(BigInt(35), BigInt(15))
    testing.assert_equal(String(r[0]), "5")
    # Verify Bézout identity: a*x + b*y = gcd
    var check = BigInt(35) * r[1] + BigInt(15) * r[2]
    testing.assert_equal(String(check), "5")


def test_extended_gcd_240_46() raises:
    """Tests extended GCD(240, 46) = 2."""
    var r = extended_gcd(BigInt(240), BigInt(46))
    testing.assert_equal(String(r[0]), "2")
    var check = BigInt(240) * r[1] + BigInt(46) * r[2]
    testing.assert_equal(String(check), "2")


def test_extended_gcd_coprime() raises:
    """Tests extended GCD of coprime numbers gives gcd=1."""
    var r = extended_gcd(BigInt(17), BigInt(13))
    testing.assert_equal(String(r[0]), "1")
    var check = BigInt(17) * r[1] + BigInt(13) * r[2]
    testing.assert_equal(String(check), "1")


def test_extended_gcd_zero_cases() raises:
    """Tests extended GCD with zero arguments."""
    var r1 = extended_gcd(BigInt(0), BigInt(5))
    testing.assert_equal(String(r1[0]), "5")
    var check1 = BigInt(0) * r1[1] + BigInt(5) * r1[2]
    testing.assert_equal(String(check1), "5")

    var r2 = extended_gcd(BigInt(7), BigInt(0))
    testing.assert_equal(String(r2[0]), "7")
    var check2 = BigInt(7) * r2[1] + BigInt(0) * r2[2]
    testing.assert_equal(String(check2), "7")

    var r3 = extended_gcd(BigInt(0), BigInt(0))
    testing.assert_equal(String(r3[0]), "0")


def test_extended_gcd_negative() raises:
    """Tests extended GCD correctly adjusts signs for negative inputs."""
    var r1 = extended_gcd(BigInt(-35), BigInt(15))
    testing.assert_equal(String(r1[0]), "5")
    var check1 = BigInt(-35) * r1[1] + BigInt(15) * r1[2]
    testing.assert_equal(String(check1), "5")

    var r2 = extended_gcd(BigInt(35), BigInt(-15))
    testing.assert_equal(String(r2[0]), "5")
    var check2 = BigInt(35) * r2[1] + BigInt(-15) * r2[2]
    testing.assert_equal(String(check2), "5")

    var r3 = extended_gcd(BigInt(-35), BigInt(-15))
    testing.assert_equal(String(r3[0]), "5")
    var check3 = BigInt(-35) * r3[1] + BigInt(-15) * r3[2]
    testing.assert_equal(String(check3), "5")


def test_extended_gcd_bezout_various() raises:
    """Tests Bézout identity for a range of input pairs."""

    # (a, b) pairs
    def _check(a_val: Int, b_val: Int) raises:
        var a = BigInt(a_val)
        var b = BigInt(b_val)
        var r = extended_gcd(a, b)
        var check = BigInt(a_val) * r[1] + BigInt(b_val) * r[2]
        testing.assert_equal(
            String(check),
            String(r[0]),
            "Bézout identity failed for ("
            + String(a_val)
            + ", "
            + String(b_val)
            + ")",
        )

    _check(6, 4)
    _check(100, 35)
    _check(1024, 768)
    _check(999, 111)
    _check(1, 1)
    _check(2, 3)


# ===----------------------------------------------------------------------=== #
# LCM tests
# ===----------------------------------------------------------------------=== #


def test_lcm_basic() raises:
    """Tests basic LCM of small integers."""
    testing.assert_equal(String(lcm(BigInt(12), BigInt(18))), "36")
    testing.assert_equal(String(lcm(BigInt(4), BigInt(6))), "12")
    testing.assert_equal(String(lcm(BigInt(7), BigInt(13))), "91")
    testing.assert_equal(String(lcm(BigInt(6), BigInt(6))), "6")
    testing.assert_equal(String(lcm(BigInt(1), BigInt(100))), "100")


def test_lcm_zero() raises:
    """Tests lcm(0, n) = lcm(n, 0) = 0."""
    testing.assert_equal(String(lcm(BigInt(0), BigInt(5))), "0")
    testing.assert_equal(String(lcm(BigInt(5), BigInt(0))), "0")
    testing.assert_equal(String(lcm(BigInt(0), BigInt(0))), "0")


def test_lcm_negative() raises:
    """Tests LCM is always non-negative."""
    testing.assert_equal(String(lcm(BigInt(-4), BigInt(6))), "12")
    testing.assert_equal(String(lcm(BigInt(4), BigInt(-6))), "12")
    testing.assert_equal(String(lcm(BigInt(-4), BigInt(-6))), "12")


def test_lcm_gcd_product_identity() raises:
    """Tests gcd(a,b) * lcm(a,b) = |a * b| for non-zero a, b."""
    var a = BigInt(48)
    var b = BigInt(18)
    var g = gcd(a, b)
    var l = lcm(a, b)
    testing.assert_equal(String(g * l), String(a * b))

    var c = BigInt(100)
    var d = BigInt(75)
    testing.assert_equal(String(gcd(c, d) * lcm(c, d)), String(c * d))


# ===----------------------------------------------------------------------=== #
# Modular exponentiation tests
# ===----------------------------------------------------------------------=== #


def test_mod_pow_basic() raises:
    """Basic modular exponentiation."""
    # 2^10 mod 1000 = 1024 mod 1000 = 24
    testing.assert_equal(
        String(mod_pow(BigInt(2), BigInt(10), BigInt(1000))), "24"
    )
    # 3^13 mod 100 = 1594323 mod 100 = 23
    testing.assert_equal(
        String(mod_pow(BigInt(3), BigInt(13), BigInt(100))), "23"
    )
    # 5^1 mod 3 = 5 mod 3 = 2
    testing.assert_equal(String(mod_pow(BigInt(5), BigInt(1), BigInt(3))), "2")
    # 7^2 mod 10 = 49 mod 10 = 9
    testing.assert_equal(String(mod_pow(BigInt(7), BigInt(2), BigInt(10))), "9")


def test_mod_pow_edge_cases() raises:
    """Edge cases: zero exponent, zero base, modulus 1."""
    # base^0 = 1 (for mod > 1)
    testing.assert_equal(String(mod_pow(BigInt(5), BigInt(0), BigInt(3))), "1")
    # 0^n = 0 for n > 0
    testing.assert_equal(String(mod_pow(BigInt(0), BigInt(10), BigInt(7))), "0")
    # x mod 1 = 0 always
    testing.assert_equal(String(mod_pow(BigInt(5), BigInt(10), BigInt(1))), "0")
    # 0^0 mod m = 1 for m > 1 (convention: 0^0 = 1)
    testing.assert_equal(String(mod_pow(BigInt(0), BigInt(0), BigInt(5))), "1")
    # Any^Any mod 1 = 0
    testing.assert_equal(String(mod_pow(BigInt(0), BigInt(0), BigInt(1))), "0")


def test_mod_pow_fermat_little_theorem() raises:
    """Fermat: a^(p-1) ≡ 1 (mod p) for prime p, gcd(a,p)=1."""
    # 3^6 mod 7 = 1
    testing.assert_equal(String(mod_pow(BigInt(3), BigInt(6), BigInt(7))), "1")
    # 5^12 mod 13 = 1
    testing.assert_equal(
        String(mod_pow(BigInt(5), BigInt(12), BigInt(13))), "1"
    )
    # 2^16 mod 17 = 1
    testing.assert_equal(
        String(mod_pow(BigInt(2), BigInt(16), BigInt(17))), "1"
    )


def test_mod_pow_larger_exponent() raises:
    """Larger exponents that benefit from binary exponentiation."""
    # 7^256 mod 13 = 9
    testing.assert_equal(
        String(mod_pow(BigInt(7), BigInt(256), BigInt(13))), "9"
    )
    # 2^32 mod 1000000007 = 294967268
    testing.assert_equal(
        String(mod_pow(BigInt(2), BigInt(32), BigInt(1000000007))),
        "294967268",
    )


def test_mod_pow_negative_base() raises:
    """Negative base is reduced via floor modulo first."""
    # (-2)^3 mod 5 = (-8) mod 5 = 2
    testing.assert_equal(String(mod_pow(BigInt(-2), BigInt(3), BigInt(5))), "2")
    # (-3)^2 mod 7 = 9 mod 7 = 2
    testing.assert_equal(String(mod_pow(BigInt(-3), BigInt(2), BigInt(7))), "2")
    # (-1)^1000 mod 7 = 1
    testing.assert_equal(
        String(mod_pow(BigInt(-1), BigInt(1000), BigInt(7))), "1"
    )
    # (-1)^999 mod 7 = 6 (since -1 mod 7 = 6, 6^odd mod 7 = 6)
    testing.assert_equal(
        String(mod_pow(BigInt(-1), BigInt(999), BigInt(7))), "6"
    )


def test_mod_pow_int_overload() raises:
    """Convenience overload with Int exponent."""
    testing.assert_equal(String(mod_pow(BigInt(2), 10, BigInt(1000))), "24")
    testing.assert_equal(String(mod_pow(BigInt(3), 13, BigInt(100))), "23")


def test_mod_pow_errors() raises:
    """Tests mod_pow raises on negative exponent or non-positive modulus."""
    var raised = False

    # Negative exponent
    try:
        var _ = mod_pow(BigInt(2), BigInt(-1), BigInt(5))
    except:
        raised = True
    testing.assert_true(raised, "Should raise on negative exponent")

    # Zero modulus
    raised = False
    try:
        var _ = mod_pow(BigInt(2), BigInt(3), BigInt(0))
    except:
        raised = True
    testing.assert_true(raised, "Should raise on zero modulus")

    # Negative modulus
    raised = False
    try:
        var _ = mod_pow(BigInt(2), BigInt(3), BigInt(-5))
    except:
        raised = True
    testing.assert_true(raised, "Should raise on negative modulus")


# ===----------------------------------------------------------------------=== #
# Modular inverse tests
# ===----------------------------------------------------------------------=== #


def test_mod_inverse_basic() raises:
    """Known modular inverses."""
    # 3 * 5 = 15 ≡ 1 (mod 7)
    testing.assert_equal(String(mod_inverse(BigInt(3), BigInt(7))), "5")
    # 7 * 8 = 56 ≡ 1 (mod 11)
    testing.assert_equal(String(mod_inverse(BigInt(7), BigInt(11))), "8")
    # 3 * 4 = 12 ≡ 1 (mod 11)
    testing.assert_equal(String(mod_inverse(BigInt(3), BigInt(11))), "4")


def test_mod_inverse_one() raises:
    """Inverse of 1 is always 1."""
    testing.assert_equal(String(mod_inverse(BigInt(1), BigInt(7))), "1")
    testing.assert_equal(String(mod_inverse(BigInt(1), BigInt(100))), "1")


def test_mod_inverse_verify_roundtrip() raises:
    """Verify (a * inv(a)) mod m == 1."""
    var a = BigInt(17)
    var m = BigInt(100)
    var inv = mod_inverse(a, m)
    testing.assert_equal(String((a * inv) % m), "1")

    var a2 = BigInt(37)
    var m2 = BigInt(1000)
    var inv2 = mod_inverse(a2, m2)
    testing.assert_equal(String((a2 * inv2) % m2), "1")


def test_mod_inverse_negative_input() raises:
    """Modular inverse of a negative number."""
    # (-3) mod 7 = 4, inv(4) mod 7: 4*2=8≡1 mod 7 → inv=2
    var inv = mod_inverse(BigInt(-3), BigInt(7))
    testing.assert_equal(String((BigInt(-3) * inv) % BigInt(7)), "1")


def test_mod_inverse_not_exists() raises:
    """Tests mod_inverse raises when gcd(a, m) != 1."""
    var raised = False
    try:
        var _ = mod_inverse(BigInt(2), BigInt(6))
    except:
        raised = True
    testing.assert_true(raised, "mod_inverse(2, 6) should raise")

    raised = False
    try:
        var _ = mod_inverse(BigInt(4), BigInt(8))
    except:
        raised = True
    testing.assert_true(raised, "mod_inverse(4, 8) should raise")

    raised = False
    try:
        var _ = mod_inverse(BigInt(0), BigInt(5))
    except:
        raised = True
    testing.assert_true(raised, "mod_inverse(0, 5) should raise")


def test_gcd_unbalanced_operands() raises:
    """Test GCD where one operand is vastly larger than the other.

    The binary (Stein) loop makes about one bit of progress per full-width
    subtraction, so this shape is where it is at its worst and where `gcd()`
    takes Euclidean steps instead. Correctness must not depend on which of the
    two paths a given pair happens to take, so each case is checked against a
    value whose factorisation is known by construction.

    Every case is also checked with the arguments reversed. `gcd()` orders its
    operands by magnitude before measuring the bit-length gap, and a
    regression there is invisible to the result - both orders still return the
    right answer, but the reversed one silently falls back to the quadratic
    binary loop. `gcd(97, 10^5400)` cost 2.4 ms against 0.002 ms for the
    forward order before that ordering step was added.
    """
    # 10^400 = 2^400 * 5^400, so gcd(10^400, 2^k) = 2^k for k <= 400.
    var big = BigInt(10) ** BigInt(400)
    testing.assert_equal(
        String(gcd(big, BigInt(1) << 40)), String(BigInt(1) << 40)
    )
    testing.assert_equal(
        String(gcd(BigInt(1) << 40, big)), String(BigInt(1) << 40)
    )

    # A large value built to be a multiple of a small one.
    var multiple = big * BigInt(97)
    testing.assert_equal(String(gcd(multiple, BigInt(97))), "97")
    testing.assert_equal(String(gcd(BigInt(97), multiple)), "97")

    # Coprime: 10^400 has only the factors 2 and 5.
    testing.assert_equal(String(gcd(big, BigInt(2187))), "1")  # 3^7
    testing.assert_equal(String(gcd(BigInt(2187), big)), "1")

    # A gap far wider than the balance threshold, in both orders.
    var huge = BigInt(10) ** BigInt(1800)
    testing.assert_equal(String(gcd(huge, BigInt(97))), "1")
    testing.assert_equal(String(gcd(BigInt(97), huge)), "1")

    # Crossing the balance threshold in both directions must agree.
    var a = (BigInt(3) ** BigInt(200)) * (BigInt(7) ** BigInt(50))
    var b = BigInt(7) ** BigInt(50)
    testing.assert_equal(String(gcd(a, b)), String(b))
    testing.assert_equal(String(gcd(b, a)), String(b))

    # One Euclidean step lands exactly on zero.
    testing.assert_equal(String(gcd(big, big)), String(big))


# ===----------------------------------------------------------------------=== #
# Main
# ===----------------------------------------------------------------------=== #


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
