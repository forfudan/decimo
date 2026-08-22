"""
Test that Decimo's number types are usable *through* the `Rootable` trait,
not merely declared to conform to it.

`_hypotenuse` is the shape the motivating consumer has: a Cholesky or QR
factorisation needs exactly one operation beyond arithmetic, and asks for it
as `T: Numeric & Rootable`. It compiles only if `sqrt` is present with the
declared signature, and it gives the right answer only if the conforming
type's own root is the one that runs.

`BigUInt` is here because it is the case that justifies the trait being
separate from `Numeric`: it has had a square root all along and, being
unsigned, has no `__neg__`, so it can never be `Numeric`. `BigFloat` is the
other such case and is exercised in the `bigfloat` suite, which is separate
because it needs MPFR at runtime.
"""

from std import testing

from decimo.traits import Numeric, Rootable
from decimo.bigint.bigint import BigInt
from decimo.biguint.biguint import BigUInt
from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.decimal128.decimal128 import Decimal128


def _hypotenuse[T: Numeric & Rootable](a: T, b: T) raises -> T:
    """Returns `sqrt(a*a + b*b)`, naming no concrete type."""
    return (a * a + b * b).sqrt()


def _root_of[T: Rootable](var x: T) raises -> T:
    """Returns `x.sqrt()` through the trait alone.

    The bound is `Rootable` unaccompanied, which is the point: it carries
    `Movable` and nothing else, so it reaches a type that moves without
    copying.
    """
    return x^.sqrt()


def test_bigint_through_rootable() raises:
    """`BigInt` rooted through the trait, past the range of any fixed width."""
    testing.assert_equal(_hypotenuse(BigInt(3), BigInt(4)), BigInt(5), "3-4-5")
    testing.assert_equal(
        _root_of(BigInt(2) ** BigInt(128)),
        BigInt(2) ** BigInt(64),
        "sqrt(2^128), one past what a 128-bit integer holds",
    )


def test_biguint_through_rootable() raises:
    """`BigUInt` conforms though it can never be `Numeric`.

    Compared as text because `BigUInt` has `__eq__` but does not declare
    `Equatable`, which is what `assert_equal` bounds on.
    """
    testing.assert_equal(String(_root_of(BigUInt(144))), "12", "sqrt(144)")


def test_bigdecimal_through_rootable() raises:
    """`BigDecimal` rooted through the trait, at the default precision."""
    testing.assert_equal(
        _hypotenuse(BigDecimal("3"), BigDecimal("4")), BigDecimal("5"), "3-4-5"
    )
    testing.assert_equal(
        _root_of(BigDecimal("2")),
        BigDecimal("1.414213562373095048801688724"),
        "sqrt(2) to the 28 significant digits `PRECISION` names",
    )


def test_decimal128_through_rootable() raises:
    """`Decimal128` rooted through the trait."""
    testing.assert_equal(
        _hypotenuse(Decimal128("3"), Decimal128("4")), Decimal128("5"), "3-4-5"
    )


def test_integral_root_truncates() raises:
    """On an integral type the root truncates, as `/` does there.

    Stated as a test because a generic routine bounded on
    `T: Numeric & Rootable` inherits this silently, and a caller who cannot
    accept it has to bound on a type that does not truncate.
    """
    testing.assert_equal(BigInt(10).sqrt(), BigInt(3), "sqrt(10) is 3")
    testing.assert_equal(String(BigUInt(10).sqrt()), "3", "sqrt(10) is 3")


def test_negative_root_raises() raises:
    """A negative value raises rather than returning a wrong root."""
    var raised = False
    try:
        _ = _root_of(BigInt(-1))
    except:
        raised = True
    testing.assert_true(raised, "BigInt(-1).sqrt()")

    raised = False
    try:
        _ = _root_of(BigDecimal("-1"))
    except:
        raised = True
    testing.assert_true(raised, "BigDecimal('-1').sqrt()")

    raised = False
    try:
        _ = _root_of(Decimal128("-1"))
    except:
        raised = True
    testing.assert_true(raised, "Decimal128('-1').sqrt()")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
