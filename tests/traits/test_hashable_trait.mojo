"""
Test that Decimo's number types hash the way `Hashable` requires, and that
the hash is the one a dictionary needs.

The contract is one implication: `a == b` implies `hash(a) == hash(b)`. The
converse is not required and is not tested, since two different values are
allowed to land on the same sixty-four bits.

The implication is the whole difficulty here, because every one of these
types has values that are equal without being identical. A decimal written
with trailing zeros, a float at a precision wider than it needs, a zero
carrying a sign: each is one number held two ways, and the hash has to see
through the difference the way `==` does.

`_hash_of` goes through the trait alone, so a type reaches these tests only
if it conforms, and `_lookup` puts the type in a `Dict`, which is what the
conformance is for.
"""

from std import testing
from std.hashlib.hasher import default_hasher

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigint.bigint import BigInt, Magnitude
from decimo.biguint.biguint import BigUInt
from decimo.decimal128.decimal128 import Decimal128
from decimo.rational.rational import Rational


def _hash_of[T: Hashable](value: T) -> UInt64:
    """Returns the hash of `value`, naming no concrete type."""
    var hasher = default_hasher()
    value.__hash__(hasher)
    return hasher^.finish()


def _assert_same_hash[T: Hashable](a: T, b: T, message: StringSlice) raises:
    """Asserts that two values the type calls equal hash alike."""
    testing.assert_equal(_hash_of(a), _hash_of(b), String(message))


# ===----------------------------------------------------------------------=== #
# BigUInt
# ===----------------------------------------------------------------------=== #


def test_biguint_hash_follows_equality() raises:
    """One magnitude has one word list, so the two sides must agree."""
    testing.assert_true(BigUInt("123") == BigUInt(123))
    _assert_same_hash(BigUInt("123"), BigUInt(123), "123 from text and Int")
    _assert_same_hash(BigUInt("0"), BigUInt(0), "zero")

    # A value wider than one base-10^18 word, where the word split matters.
    var wide = BigUInt("123456789012345678901234567890")
    _assert_same_hash(
        wide, BigUInt("123456789012345678901234567890"), "thirty digits"
    )


# ===----------------------------------------------------------------------=== #
# BigInt
# ===----------------------------------------------------------------------=== #


def test_bigint_hash_follows_equality() raises:
    _assert_same_hash(BigInt("-123"), BigInt(-123), "-123 from text and Int")
    _assert_same_hash(
        BigInt("340282366920938463463374607431768211456"),
        BigInt(2) ** BigInt(128),
        "2^128, three words",
    )


def test_bigint_zero_hashes_alike_whatever_its_sign() raises:
    """A `BigInt` zero may carry `sign = True`, and still be zero.

    The sign of zero is not canonical in this type, as the struct says:
    `is_negative()` is `sign and not is_zero()`, so a hash that fed the
    field would break the contract on the one value where the field lies.
    The raw constructor is how such a value is reached, and is used here
    because the arithmetic and the parser both hand back `sign = False`.
    """
    var words = Magnitude(capacity=1)
    words.append(UInt64(0))
    var signed = BigInt(raw_words=words^, sign=True)
    testing.assert_true(signed.sign, "the field is set")
    testing.assert_false(signed.is_negative(), "and means nothing")
    testing.assert_true(signed == BigInt(0))
    _assert_same_hash(signed, BigInt(0), "a signed zero and a plain one")
    _assert_same_hash(-BigInt(0), BigInt(0), "-0 and 0")
    _assert_same_hash(BigInt("-0"), BigInt("0"), "-0 and 0, from text")


# ===----------------------------------------------------------------------=== #
# BigDecimal
# ===----------------------------------------------------------------------=== #


def test_bigdecimal_hash_ignores_trailing_zeros() raises:
    """`1.0 == 1.00`, so the two have to hash alike."""
    testing.assert_true(BigDecimal("1.0") == BigDecimal("1.00"))
    _assert_same_hash(BigDecimal("1.0"), BigDecimal("1.00"), "1.0 and 1.00")
    _assert_same_hash(BigDecimal("1"), BigDecimal("1.000000"), "1 and 1.000000")
    _assert_same_hash(
        BigDecimal("-1.5"), BigDecimal("-1.500"), "-1.5 and -1.500"
    )

    # Enough trailing zeros to cross a whole word of the coefficient, which
    # is where dropping them digit by digit and word by word must agree.
    _assert_same_hash(
        BigDecimal("3"),
        BigDecimal("3.000000000000000000000000"),
        "3 with twenty-four trailing zeros",
    )


def test_bigdecimal_hash_ignores_the_exponent_it_is_written_with() raises:
    """`100` and `1E+2` are one number held at two scales."""
    testing.assert_true(BigDecimal("100") == BigDecimal("1E+2"))
    _assert_same_hash(BigDecimal("100"), BigDecimal("1E+2"), "100 and 1E+2")
    _assert_same_hash(
        BigDecimal("0.00300"), BigDecimal("3E-3"), "0.00300 and 3E-3"
    )


def test_bigdecimal_every_zero_hashes_alike() raises:
    var zero = _hash_of(BigDecimal("0"))
    testing.assert_equal(zero, _hash_of(BigDecimal("0.0")), "0.0")
    testing.assert_equal(zero, _hash_of(BigDecimal("0.000000")), "0.000000")
    testing.assert_equal(zero, _hash_of(BigDecimal("-0")), "-0")
    testing.assert_equal(zero, _hash_of(BigDecimal("-0.00")), "-0.00")
    testing.assert_equal(zero, _hash_of(BigDecimal("0E+10")), "0E+10")


# ===----------------------------------------------------------------------=== #
# BigFloat
# ===----------------------------------------------------------------------=== #


def test_bigfloat_hash_ignores_precision() raises:
    """A half is a half at any width, with zeros filling the rest.

    The significand holds exactly `precision` bits, so the same number at
    two precisions is two different significands. Shifting it down to an
    odd number is what makes them one.
    """
    var narrow = BigFloat.from_string("0.5", 53)
    var wide = BigFloat.from_string("0.5", 500)
    testing.assert_true(narrow == wide)
    _assert_same_hash(narrow, wide, "0.5 at 53 and at 500 bits")

    var small = BigFloat.from_string("-3.25", 10)
    var large = BigFloat.from_string("-3.25", 1000)
    testing.assert_true(small == large)
    _assert_same_hash(small, large, "-3.25 at 10 and at 1000 bits")


def test_bigfloat_both_zeros_hash_alike() raises:
    """`+0 == -0` in this type, so their hashes cannot differ."""
    var positive = BigFloat.zero(53, False)
    var negative = BigFloat.zero(53, True)
    testing.assert_true(positive == negative)
    _assert_same_hash(positive, negative, "+0 and -0")
    _assert_same_hash(positive, BigFloat.zero(900, False), "+0 at two widths")


def test_bigfloat_infinity_and_nan_hash() raises:
    """An infinity keeps its sign; a NaN is equal to nothing and hashes flat.

    Nothing is required of a NaN's hash, since no two NaNs are equal. What
    is required is that asking for it does not reach the significand, which
    an infinity and a NaN do not have.
    """
    _assert_same_hash(
        BigFloat.infinity(53, False),
        BigFloat.infinity(900, False),
        "+inf at two widths",
    )
    _assert_same_hash(
        BigFloat.infinity(53, True),
        BigFloat.infinity(900, True),
        "-inf at two widths",
    )
    _assert_same_hash(BigFloat.nan(53), BigFloat.nan(900), "nan at two widths")


# ===----------------------------------------------------------------------=== #
# Rational
# ===----------------------------------------------------------------------=== #


def test_rational_hash_follows_equality() raises:
    """A fraction arrives in lowest terms, however it was written."""
    testing.assert_true(Rational(2, 4) == Rational(1, 2))
    _assert_same_hash(Rational(2, 4), Rational(1, 2), "2/4 and 1/2")
    _assert_same_hash(
        Rational(-1, 2), Rational(1, -2), "-1/2 and 1/-2, the sign moved"
    )
    _assert_same_hash(Rational(0, 5), Rational(0, 1), "0/5 and 0/1")
    _assert_same_hash(
        Rational(String("3/7")), Rational(3, 7), "3/7 from text and from parts"
    )


# ===----------------------------------------------------------------------=== #
# The point of it: a dictionary
# ===----------------------------------------------------------------------=== #


def test_bigdecimal_as_a_dictionary_key() raises:
    """A key put in as `1.0` comes back out under `1.00`.

    This is the reason the contract matters. `Dict` finds a key by its
    hash first and `==` second, so a hash that saw the trailing zero would
    send the lookup to the wrong bucket and the entry would be lost.
    """
    var prices = Dict[BigDecimal, String]()
    prices[BigDecimal("1.0")] = String("one")
    prices[BigDecimal("2.50")] = String("two and a half")
    testing.assert_equal(prices[BigDecimal("1.00")], "one")
    testing.assert_equal(prices[BigDecimal("1")], "one")
    testing.assert_equal(prices[BigDecimal("2.5")], "two and a half")
    testing.assert_equal(len(prices), 2, "no key was duplicated")

    # Writing under an equal key replaces rather than adds.
    prices[BigDecimal("1.000")] = String("still one")
    testing.assert_equal(len(prices), 2, "still two keys")
    testing.assert_equal(prices[BigDecimal("1.0")], "still one")


def test_biguint_as_a_dictionary_key() raises:
    """`BigUInt` also gained `Equatable`, which a key needs beside the hash.

    It had `__eq__` all along and only lacked the declaration, so nothing
    about equality changed; what changed is that `Dict` will now take it.
    """
    var counts = Dict[BigUInt, Int]()
    counts[BigUInt("123456789012345678901234567890")] = 3
    testing.assert_equal(
        counts[BigUInt("123456789012345678901234567890")], 3, "thirty digits"
    )


def test_bigint_as_a_dictionary_key() raises:
    var counts = Dict[BigInt, Int]()
    counts[BigInt(2) ** BigInt(100)] = 7
    counts[-BigInt(0)] = 1
    testing.assert_equal(
        counts[BigInt("1267650600228229401496703205376")], 7, "2^100"
    )
    testing.assert_equal(counts[BigInt(0)], 1, "zero found under either sign")


def test_rational_as_a_dictionary_key() raises:
    var seen = Dict[Rational, String]()
    seen[Rational(2, 4)] = String("a half")
    testing.assert_equal(seen[Rational(1, 2)], "a half")
    testing.assert_equal(len(seen), 1)


def test_bigfloat_as_a_dictionary_key() raises:
    var seen = Dict[BigFloat, String]()
    seen[BigFloat.from_string("0.5", 53)] = String("a half")
    testing.assert_equal(seen[BigFloat.from_string("0.5", 400)], "a half")
    testing.assert_equal(len(seen), 1)


def test_decimal128_still_follows_the_same_contract() raises:
    """The one type that already hashed, through the same helper.

    It is here so that the five new conformances and the old one are read
    against one statement of the rule rather than two.
    """
    _assert_same_hash(Decimal128("1.0"), Decimal128("1.00"), "1.0 and 1.00")
    _assert_same_hash(Decimal128("-0"), Decimal128("0.000"), "the zeros")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
