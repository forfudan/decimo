"""
Test that `BigInt`, `BigDecimal`, `Decimal128` and `BigFloat` are usable *through* the
`Parsable` trait, not merely declared to conform to it.

`_parse_all` is written once, against the trait alone, and is the shape every
real consumer has: text goes in, a container of some number type comes out,
and the code doing the filling never names the type. It compiles only if
`from_string` is present with the declared signature, and it produces the right
answer only if the conforming type's own parser is the one that runs.

The values are chosen so a binary float cannot stand in for the result. `0.1`
has no exact `Float64`, so a type that quietly went through one would fail the
sum below rather than merely lose a digit somewhere invisible.
"""

from std import testing

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigint.bigint import BigInt
from decimo.decimal128.decimal128 import Decimal128
from decimo.traits import Parsable


def _parse_all[
    T: Movable & Deinitable & Parsable
](tokens: List[String]) raises -> List[T]:
    """Parses every token into `T`, naming no concrete type.

    The bound is `Movable` rather than `Copyable` because nothing here
    copies, and because `Parsable` is meant to reach types like
    `MPF` that move without copying.
    """
    var out = List[T](capacity=len(tokens))
    for token in tokens:
        out.append(T.from_string(token))
    return out^


def test_bigint_through_parsable() raises:
    """`BigInt` parsed through the trait, past the range of any fixed width."""
    var tokens: List[String] = [
        "0",
        "-42",
        "170141183460469231731687303715884105728",
    ]
    var values = _parse_all[BigInt](tokens)

    testing.assert_equal(values[0], BigInt(0), "0")
    testing.assert_equal(values[1], BigInt(-42), "-42")
    testing.assert_equal(
        values[2],
        BigInt(2) ** BigInt(127),
        "2^127, one past what a 128-bit signed integer holds",
    )


def test_bigfloat_through_parsable() raises:
    """`BigFloat` filled from text through the trait alone.

    A float has to be told how many bits to keep, and the trait's call has no
    way to say, so the one-argument overload lands at the default precision --
    the fifty-three bits a double holds.
    """
    var tokens: List[String] = ["0.5", "-2.5", "1024", "1e300"]
    var values = _parse_all[BigFloat](tokens)
    testing.assert_equal(len(values), 4, "all four parsed")
    testing.assert_equal(
        String(values[1]), "-2.5", "and the signs came through"
    )
    testing.assert_equal(values[0].precision, 53, "at the default precision")


def test_bigdecimal_through_parsable() raises:
    """`BigDecimal` parsed through the trait, with the digits kept exactly."""
    var tokens: List[String] = ["0.1", "0.2", "1e-3"]
    var values = _parse_all[BigDecimal](tokens)

    testing.assert_equal(
        values[0] + values[1], BigDecimal("0.3"), "0.1 + 0.2 is exactly 0.3"
    )
    testing.assert_equal(values[2], BigDecimal("0.001"), "1e-3")


def test_decimal128_through_parsable() raises:
    """`Decimal128` parsed through the trait."""
    var tokens: List[String] = ["0.1", "0.2", "-7.25"]
    var values = _parse_all[Decimal128](tokens)

    testing.assert_equal(
        values[0] + values[1], Decimal128("0.3"), "0.1 + 0.2 is exactly 0.3"
    )
    testing.assert_equal(values[2], Decimal128("-7.25"), "-7.25")


def test_parsable_rejects_nonsense() raises:
    """A token that is not a number raises rather than parsing to zero."""
    var raised = False
    try:
        _ = BigInt.from_string("not a number")
    except:
        raised = True
    testing.assert_true(raised, "BigInt.from_string('not a number')")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
