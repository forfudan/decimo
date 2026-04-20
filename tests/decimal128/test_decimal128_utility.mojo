"""
Tests for utility functions: number_of_digits, fit_to_max_coefficient,
round_coefficient, round_to_keep_first_n_digits, and bitcast.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.decimal128.decimal128 import Decimal128
from decimo.rounding_mode import RoundingMode
from decimo.decimal128.utility import (
    fit_to_max_coefficient,
    number_of_digits,
    round_coefficient,
    round_to_keep_first_n_digits,
    bitcast,
)


def test_number_of_digits() raises:
    """Tests for number_of_digits function."""
    # UInt128
    assert_equal(number_of_digits(UInt128(0)), 0)
    assert_equal(number_of_digits(UInt128(1)), 1)
    assert_equal(number_of_digits(UInt128(9)), 1)
    assert_equal(number_of_digits(UInt128(10)), 2)
    assert_equal(number_of_digits(UInt128(123)), 3)
    assert_equal(number_of_digits(UInt128(9999)), 4)
    assert_equal(number_of_digits(UInt128(10**6)), 7)
    assert_equal(number_of_digits(UInt128(10**12)), 13)
    assert_equal(number_of_digits(UInt128(Decimal128.MAX_AS_UINT128)), 29)

    # UInt256
    assert_equal(number_of_digits(UInt256(0)), 0)
    assert_equal(number_of_digits(UInt256(123456789)), 9)
    assert_equal(number_of_digits(UInt256(10) ** 20), 21)
    assert_equal(
        number_of_digits(UInt256(Decimal128.MAX_AS_UINT128) * UInt256(10)), 30
    )


def test_fit_to_max_below() raises:
    """Fit_to_max_coefficient with values at or below MAX — no truncation."""
    var r1 = fit_to_max_coefficient(UInt128(123456))
    assert_equal(r1[0], UInt128(123456))
    assert_equal(r1[1], 0)

    var r2 = fit_to_max_coefficient(UInt256(7654321))
    assert_equal(r2[0], UInt256(7654321))
    assert_equal(r2[1], 0)

    var r3 = fit_to_max_coefficient(UInt128(Decimal128.MAX_AS_UINT128))
    assert_equal(r3[0], UInt128(Decimal128.MAX_AS_UINT128))
    assert_equal(r3[1], 0)

    var r4 = fit_to_max_coefficient(UInt256(Decimal128.MAX_AS_UINT128))
    assert_equal(r4[0], UInt256(Decimal128.MAX_AS_UINT128))
    assert_equal(r4[1], 0)


def test_fit_to_max_above() raises:
    """Fit_to_max_coefficient with values above MAX — should be truncated."""
    # MAX + 1: 30 digits → needs 1 digit removed
    var max_plus_1 = UInt256(Decimal128.MAX_AS_UINT128) + UInt256(1)
    var r1 = fit_to_max_coefficient(max_plus_1)
    assert_true(r1[0] <= UInt256(Decimal128.MAX_AS_UINT128))
    assert_equal(r1[1], 1)

    # Round down (last truncated digit < 5): digits_removed = 1
    var r2 = fit_to_max_coefficient(UInt256(79228162514264337593543950354))
    assert_equal(r2[0], UInt256(7922816251426433759354395035))
    assert_equal(r2[1], 1)

    # Round up (last truncated digit >= 6): digits_removed = 1
    var r3 = fit_to_max_coefficient(UInt256(79228162514264337593543950356))
    assert_equal(r3[0], UInt256(7922816251426433759354395036))
    assert_equal(r3[1], 1)

    # Much larger value: truncate multiple digits, digits_removed = 4
    var much_larger = UInt256(Decimal128.MAX_AS_UINT128) * UInt256(
        1000
    ) + UInt256(555)
    var r4 = fit_to_max_coefficient(much_larger)
    assert_true(r4[0] <= UInt256(Decimal128.MAX_AS_UINT128))
    assert_equal(r4[1], 4)

    # Banker's rounding: MAX + 20 (trailing 5, preceding digit even → round up)
    var r5 = fit_to_max_coefficient(
        UInt256(Decimal128.MAX_AS_UINT128) + UInt256(20)
    )
    assert_equal(r5[0], UInt256(7922816251426433759354395036))
    assert_equal(r5[1], 1)

    # Banker's rounding: constructed trailing 5 with preceding even
    var base = UInt256(79228162514264337593543950330)
    var banker = base * UInt256(10) + UInt256(5)
    var r6 = fit_to_max_coefficient(banker)
    assert_equal(r6[0], base + UInt256(0))
    assert_equal(r6[1], 1)


def test_fit_to_max_banker_rounding() raises:
    """Banker's rounding edge cases in fit_to_max_coefficient."""
    # Round down to even (5 as rounding digit, preceding even)
    var r1 = fit_to_max_coefficient(UInt256(7922816251426433759354395033250))
    assert_equal(r1[0], UInt256(79228162514264337593543950332))
    assert_equal(r1[1], 2)

    # Round up to even (5 as rounding digit, preceding odd)
    var r2 = fit_to_max_coefficient(UInt256(7922816251426433759354395033150))
    assert_equal(r2[0], UInt256(79228162514264337593543950332))
    assert_equal(r2[1], 2)

    # Round up: 5 followed by non-zero (preceding even)
    var r3 = fit_to_max_coefficient(UInt256(79228162514264337593543950332501))
    assert_equal(r3[0], UInt256(79228162514264337593543950333))
    assert_equal(r3[1], 3)

    # Round up: 5 followed by non-zero (preceding odd)
    var r4 = fit_to_max_coefficient(UInt256(79228162514264337593543950331501))
    assert_equal(r4[0], UInt256(79228162514264337593543950332))
    assert_equal(r4[1], 3)

    # Rounding digit > 5
    var r5 = fit_to_max_coefficient(UInt256(7922816251426433759354395033207))
    assert_equal(r5[0], UInt256(79228162514264337593543950332))
    assert_equal(r5[1], 2)

    # Rounding digit < 5
    var r6 = fit_to_max_coefficient(UInt256(7922816251426433759354395033204))
    assert_equal(r6[0], UInt256(79228162514264337593543950332))
    assert_equal(r6[1], 2)


def test_fit_to_max_cascade_rounding() raises:
    """Edge cases where rounding cascades (all-nines overflow both tries)."""

    # 32 nines: try-29 rounds 29 nines up to 10^29 > MAX, retry-28 rounds
    # 28 nines up to 10^28 ≤ MAX. digits_removed = 3 + 1 = 4.
    var r1 = fit_to_max_coefficient(
        UInt256(99999999999999999999999999999999)  # 32 nines
    )
    assert_equal(r1[0], UInt256(10000000000000000000000000000))  # 10^28
    assert_equal(r1[1], 4)
    assert_true(r1[0] <= UInt256(Decimal128.MAX_AS_UINT128))

    # 30 nines: try-29 rounds 29 nines up to 10^29 > MAX, retry-28 rounds
    # 28 nines up to 10^28 ≤ MAX. digits_removed = 1 + 1 = 2.
    var r2 = fit_to_max_coefficient(
        UInt256(999999999999999999999999999999)  # 30 nines
    )
    assert_equal(r2[0], UInt256(10000000000000000000000000000))  # 10^28
    assert_equal(r2[1], 2)

    # 29 nines: exactly 29 digits of all nines. 29 nines > MAX (since
    # MAX = 7922...335 < 9999...999). try-29 keeps all 29 digits unchanged
    # (no rounding needed), but 29 nines > MAX → retry-28 rounds away 1 digit:
    # 28 nines + round up → 10^28. digits_removed = 0 + 1 = 1.
    var r3 = fit_to_max_coefficient(
        UInt256(99999999999999999999999999999)  # 29 nines
    )
    assert_equal(r3[0], UInt256(10000000000000000000000000000))  # 10^28
    assert_equal(r3[1], 1)

    # 40 nines: very large, digits_removed = 40 - 29 + 1 = 12.
    var r4 = fit_to_max_coefficient(
        UInt256(9999999999999999999999999999999999999999)  # 40 nines
    )
    assert_equal(r4[0], UInt256(10000000000000000000000000000))  # 10^28
    assert_equal(r4[1], 12)

    # Exactly MAX + 1 with all-nines flavor: 79228162514264337593543950336
    # try-29 → ndigits=29, digits_to_remove=0, keep 29 digits → unchanged →
    # still > MAX → retry-28: remove 1 digit, truncated = 7922816251426433759354395034,
    # remainder = 6, rounding digit 6 > 5 → round up → 7922816251426433759354395034.
    # Wait, let me reconsider. value = MAX+1 = 79228162514264337593543950336.
    # ndigits = 29, digits_to_remove = 0.
    # try-29: round_to_keep_first_n_digits(value, 29) → ndigits_of_x=29, ndigits=29,
    # so ndigits >= ndigits_of_x → return value unchanged = MAX+1.
    # MAX+1 > MAX → retry.
    # try-28: round_to_keep_first_n_digits(value, 28) → remove 1 digit.
    # truncated = 7922816251426433759354395033, remainder = 6.
    # 6 > 5 → round up → 7922816251426433759354395034.
    # digits_to_remove = 0 + 1 = 1.
    var r5 = fit_to_max_coefficient(
        UInt256(79228162514264337593543950336)  # MAX + 1
    )
    assert_equal(r5[0], UInt256(7922816251426433759354395034))
    assert_equal(r5[1], 1)
    assert_true(r5[0] <= UInt256(Decimal128.MAX_AS_UINT128))

    # UInt128 path: a value just barely above MAX
    var r6 = fit_to_max_coefficient(
        UInt128(79228162514264337593543950340)  # MAX + 5
    )
    assert_true(r6[0] <= UInt128(Decimal128.MAX_AS_UINT128))
    assert_equal(r6[1], 1)


def test_round_coefficient() raises:
    """Tests for round_coefficient (the optimized replacement)."""

    # Remove 0 digits → unchanged
    assert_equal(
        round_coefficient(UInt128(12345), ndigits_to_remove=0), UInt128(12345)
    )

    # Remove 1 digit, half-even: 12345 → remove 5, preceding 4 is even → 1234
    assert_equal(
        round_coefficient(UInt128(12345), ndigits_to_remove=1), UInt128(1234)
    )

    # Remove 1 digit, half-even: 12355 → remove 5, preceding 5 is odd → 1236
    assert_equal(
        round_coefficient(UInt128(12355), ndigits_to_remove=1), UInt128(1236)
    )

    # Remove 1 digit, round down (< 5): 12342 → 1234
    assert_equal(
        round_coefficient(UInt128(12342), ndigits_to_remove=1), UInt128(1234)
    )

    # Remove 1 digit, round up (> 5): 12347 → 1235
    assert_equal(
        round_coefficient(UInt128(12347), ndigits_to_remove=1), UInt128(1235)
    )

    # Remove 3 digits from 123456: 123|456, half is 500, 456 < 500 → 123
    assert_equal(
        round_coefficient(UInt128(123456), ndigits_to_remove=3), UInt128(123)
    )

    # Remove 3 digits from 123556: 123|556, 556 > 500 → 124
    assert_equal(
        round_coefficient(UInt128(123556), ndigits_to_remove=3), UInt128(124)
    )

    # Remove 3 digits from 123500: exactly half, 123 is odd → round up to 124
    assert_equal(
        round_coefficient(UInt128(123500), ndigits_to_remove=3), UInt128(124)
    )

    # Remove 3 digits from 124500: exactly half, 124 is even → 124
    assert_equal(
        round_coefficient(UInt128(124500), ndigits_to_remove=3), UInt128(124)
    )

    # Rounding mode: UP (non-negative)
    assert_equal(
        round_coefficient(
            UInt128(12301), ndigits_to_remove=2, rounding_mode=RoundingMode.up()
        ),
        UInt128(124),
    )

    # Rounding mode: DOWN
    assert_equal(
        round_coefficient(
            UInt128(12399),
            ndigits_to_remove=2,
            rounding_mode=RoundingMode.down(),
        ),
        UInt128(123),
    )

    # Rounding mode: HALF_UP (>= 0.5 rounds away from zero)
    assert_equal(
        round_coefficient(
            UInt128(12350),
            ndigits_to_remove=2,
            rounding_mode=RoundingMode.half_up(),
        ),
        UInt128(124),
    )

    # Rounding mode: HALF_DOWN (> 0.5 rounds away from zero)
    assert_equal(
        round_coefficient(
            UInt128(12350),
            ndigits_to_remove=2,
            rounding_mode=RoundingMode.half_down(),
        ),
        UInt128(123),
    )

    # Remove all digits from 997: 997 / 1000 = 0, remainder 997, 2*997=1994 > 1000 → 1
    assert_equal(
        round_coefficient(UInt128(997), ndigits_to_remove=3), UInt128(1)
    )

    # Zero input
    assert_equal(round_coefficient(UInt128(0), ndigits_to_remove=5), UInt128(0))

    # Single digit, remove 1: 7 / 10 = 0, remainder 7, 2*7=14 > 10 → 1
    assert_equal(round_coefficient(UInt128(7), ndigits_to_remove=1), UInt128(1))

    # UInt256 path
    assert_equal(
        round_coefficient(UInt256(9876543210987654321), ndigits_to_remove=1),
        UInt256(987654321098765432),
    )

    # CEILING mode: positive → acts like UP
    assert_equal(
        round_coefficient(
            UInt128(12301),
            ndigits_to_remove=2,
            sign=False,
            rounding_mode=RoundingMode.ceiling(),
        ),
        UInt128(124),
    )

    # CEILING mode: negative → acts like DOWN
    assert_equal(
        round_coefficient(
            UInt128(12399),
            ndigits_to_remove=2,
            sign=True,
            rounding_mode=RoundingMode.ceiling(),
        ),
        UInt128(123),
    )

    # FLOOR mode: positive → acts like DOWN
    assert_equal(
        round_coefficient(
            UInt128(12399),
            ndigits_to_remove=2,
            sign=False,
            rounding_mode=RoundingMode.floor(),
        ),
        UInt128(123),
    )

    # FLOOR mode: negative → acts like UP
    assert_equal(
        round_coefficient(
            UInt128(12301),
            ndigits_to_remove=2,
            sign=True,
            rounding_mode=RoundingMode.floor(),
        ),
        UInt128(124),
    )


def test_round_to_keep_first_n_digits() raises:
    """Tests for round_to_keep_first_n_digits."""
    # Keep 0 digits (round to nearest power of 10)
    assert_equal(
        round_to_keep_first_n_digits(UInt128(997), False, 0), UInt128(1)
    )

    # Truncate one digit
    assert_equal(
        round_to_keep_first_n_digits(UInt128(234567), False, 5), UInt128(23457)
    )

    # Fewer digits than n → unchanged
    assert_equal(
        round_to_keep_first_n_digits(UInt128(234567), False, 29),
        UInt128(234567),
    )

    # Banker's rounding: trailing 5 with even preceding digit
    assert_equal(
        round_to_keep_first_n_digits(UInt128(12345), False, 4), UInt128(1234)
    )

    # Banker's rounding: trailing 5 with odd preceding digit → round up
    assert_equal(
        round_to_keep_first_n_digits(UInt128(23455), False, 4), UInt128(2346)
    )

    # Round down (< 5)
    assert_equal(
        round_to_keep_first_n_digits(UInt128(12342), False, 4), UInt128(1234)
    )

    # Round up (> 5)
    assert_equal(
        round_to_keep_first_n_digits(UInt128(12347), False, 4), UInt128(1235)
    )

    # Zero input
    assert_equal(round_to_keep_first_n_digits(UInt128(0), False, 5), UInt128(0))

    # Single digit
    assert_equal(round_to_keep_first_n_digits(UInt128(7), False, 1), UInt128(7))
    assert_equal(round_to_keep_first_n_digits(UInt128(7), False, 0), UInt128(1))

    # Large UInt256
    assert_equal(
        round_to_keep_first_n_digits(UInt256(9876543210987654321), False, 18),
        UInt256(987654321098765432),
    )


def test_bitcast() raises:
    """Test bitcast returns coefficient bits."""

    def _check(d: Decimal128) raises:
        assert_equal(d.coefficient(), bitcast[DType.uint128](d))

    _check(Decimal128("123.456"))
    _check(Decimal128(0))
    _check(Decimal128.MAX())
    _check(Decimal128("-987.654321"))
    _check(Decimal128("0.000000000123456789"))
    _check(Decimal128(12345, 67890, 0xABCDEF, 0x55))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
