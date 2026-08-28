"""
Test the digit-level operations on `BigUInt`: shifting by powers of ten,
addressing individual digits, and removing trailing digits with rounding.

These are the operations that convert between a digit position and a word
position, and they are where a change of base does its damage. Two of them
were built as `if` chains that stopped at eight -- every case a nine-digit
word could produce -- and folded every larger shift into the last branch when
the word grew to eighteen digits. Neither had a test.

The sweeps below are exhaustive over the shift amount rather than
spot-checked, because the failures were at specific amounts (nine through
seventeen) rather than at the extremes.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.biguint.biguint import BigUInt
import decimo.biguint.arithmetics as biguint_arithmetics
from decimo.rounding_mode import RoundingMode


def _operands() -> List[String]:
    """Values either side of the word boundary, and one spanning two words."""
    return [
        String("1"),
        String("7"),
        String("123456789"),
        String("999999999999999999"),
        String("1000000000000000000"),
        String("123456789012345678901234567890"),
    ]


def _shifted_up(text: String, n: Int) -> String:
    """`text * 10^n`, as a string, without going through `BigUInt`."""
    var result = String(text)
    for _ in range(n):
        result += "0"
    return result^


def test_multiply_by_power_of_ten_every_shift() raises:
    """`x * 10^n` for every `n` up to three words' worth of digits.

    Both the out-of-place and the in-place form. The in-place one had the
    same capped `if` chain as its sibling.
    """
    comptime LIMIT = 3 * BigUInt.DIGITS_PER_WORD + 6
    for operand in _operands():
        for n in range(LIMIT + 1):
            var expected = _shifted_up(operand, n)

            var out_of_place = biguint_arithmetics.multiply_by_power_of_ten(
                BigUInt(operand), n
            )
            assert_equal(
                String(out_of_place),
                expected,
                "multiply_by_power_of_ten(" + operand + ", " + String(n) + ")",
            )

            var in_place = BigUInt(operand)
            biguint_arithmetics.multiply_by_power_of_ten_inplace(in_place, n)
            assert_equal(
                String(in_place),
                expected,
                "multiply_by_power_of_ten_inplace("
                + operand
                + ", "
                + String(n)
                + ")",
            )


def test_floor_divide_and_modulo_by_power_of_ten_every_shift() raises:
    """`x // 10^n` and `x % 10^n` for every `n` past the operand's width.

    Dividing by more digits than the value has must give zero and leave a
    valid single-word `BigUInt`, not one with no words at all.
    """
    comptime LIMIT = 3 * BigUInt.DIGITS_PER_WORD + 6
    for operand in _operands():
        var digits = operand.byte_length()
        for n in range(LIMIT + 1):
            # The quotient's digits are what is left after dropping `n` from
            # the right; the remainder is the `n` that were dropped.
            var quotient_text: String
            if n >= digits:
                quotient_text = String("0")
            else:
                quotient_text = String(operand[byte = 0 : digits - n])

            var quotient = biguint_arithmetics.floor_divide_by_power_of_ten(
                BigUInt(operand), n
            )
            assert_equal(
                String(quotient),
                quotient_text,
                "floor_divide_by_power_of_ten("
                + operand
                + ", "
                + String(n)
                + ")",
            )

            var in_place = BigUInt(operand)
            biguint_arithmetics.floor_divide_by_power_of_ten_inplace(
                in_place, n
            )
            assert_equal(
                String(in_place),
                quotient_text,
                "floor_divide_by_power_of_ten_inplace("
                + operand
                + ", "
                + String(n)
                + ")",
            )
            in_place.assert_invariant("floor_divide_by_power_of_ten_inplace")

            # quotient * 10^n + remainder == operand, which pins the modulo
            # against the division without restating the arithmetic.
            var remainder = biguint_arithmetics.floor_modulo_by_power_of_ten(
                BigUInt(operand), n
            )
            var rebuilt = (
                biguint_arithmetics.multiply_by_power_of_ten(quotient, n)
                + remainder
            )
            assert_equal(
                String(rebuilt),
                operand,
                "q * 10^n + r != x for " + operand + ", n = " + String(n),
            )


def test_ith_digit_addresses_every_digit() raises:
    """Digit 0 is the least significant, and past the end reads zero."""
    var text = String("9876543210123456789098765432101234567890")
    var value = BigUInt(text)

    var rebuilt = String("")
    for i in range(text.byte_length() - 1, -1, -1):
        rebuilt += String(value.ith_digit(i))
    assert_equal(rebuilt, text, "ith_digit does not spell the value back")

    # Reading past the top is zero, not a fault, at the word boundary and well
    # beyond it.
    for i in [
        text.byte_length(),
        text.byte_length() + 1,
        len(value.words) * BigUInt.DIGITS_PER_WORD,
        1000,
    ]:
        assert_equal(value.ith_digit(i), 0, "ith_digit past the end")


def test_is_power_of_10_across_the_word_boundary() raises:
    """True only for `10^k`, including `k = 0`, and never for zero."""
    assert_true(not BigUInt("0").is_power_of_10())
    assert_true(BigUInt("1").is_power_of_10())

    var power = String("1")
    for k in range(1, 3 * BigUInt.DIGITS_PER_WORD + 4):
        power += "0"
        assert_true(
            BigUInt(power).is_power_of_10(),
            "10^" + String(k) + " should be a power of ten",
        )
        # One more and one less are not.
        assert_true(
            not BigUInt(
                String(power[byte = 0 : power.byte_length() - 1]) + "1"
            ).is_power_of_10(),
            "a trailing one is not a power of ten",
        )


def test_remove_trailing_digits_with_rounding_across_the_boundary() raises:
    """Down, up and half-even agree with integer arithmetic.

    Swept across the word boundary because the digits removed and the digits
    kept can land in different words.
    """
    for operand in _operands():
        var digits = operand.byte_length()
        for n in range(1, digits):
            var value = BigUInt(operand)
            var kept = String(operand[byte = 0 : digits - n])
            var dropped = String(operand[byte = digits - n : digits])

            var down = value.remove_trailing_digits_with_rounding(
                n,
                rounding_mode=RoundingMode.down(),
                remove_extra_digit_due_to_rounding=False,
            )
            assert_equal(String(down), kept, "round down " + operand)

            var up = value.remove_trailing_digits_with_rounding(
                n,
                rounding_mode=RoundingMode.up(),
                remove_extra_digit_due_to_rounding=False,
            )
            var expected_up = kept
            var any_dropped_nonzero = False
            for i in range(dropped.byte_length()):
                if String(dropped[byte = i : i + 1]) != String("0"):
                    any_dropped_nonzero = True
                    break
            if any_dropped_nonzero:
                expected_up = String(BigUInt(kept) + BigUInt("1"))
            assert_equal(String(up), expected_up, "round up " + operand)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
