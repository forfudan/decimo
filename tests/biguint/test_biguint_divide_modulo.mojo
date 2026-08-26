"""Tests that division hands back a remainder consistent with its quotient."""

from std import testing

from decimo.biguint.biguint import BigUInt
from decimo.biguint import arithmetics as biguint_arithmetics


def build_digits(count: Int, seed: Int) -> String:
    """Builds a `count`-digit decimal string, without a leading zero."""
    var out = String("")
    var state = seed | 1
    for _ in range(count):
        state = (state * 31 + 17) % 9
        out += String(state + 1)
    return out^


def assert_divides(x: BigUInt, y: BigUInt, note: String) raises:
    """Checks the division identity `x = q * y + r` with `0 <= r < y`.

    This is the whole contract, and it is worth checking rather than comparing
    against a second implementation: the identity pins the quotient and the
    remainder to each other, so a remainder that is scaled wrong, truncated
    wrong, or left over from a previous block cannot satisfy it.
    """
    var remainder = BigUInt.zero()
    var quotient = biguint_arithmetics.floor_divide_modulo(x, y, remainder)

    testing.assert_true(
        remainder.compare(y) < 0,
        "remainder is not smaller than the divisor for " + note,
    )
    var rebuilt = biguint_arithmetics.multiply(quotient, y) + remainder
    testing.assert_equal(
        String(rebuilt), String(x), "q * y + r does not rebuild x for " + note
    )

    # The quotient must also be exactly what `floor_divide()` gives, or the two
    # entry points have drifted apart.
    testing.assert_equal(
        String(quotient),
        String(biguint_arithmetics.floor_divide(x, y)),
        "floor_divide_modulo() and floor_divide() disagree for " + note,
    )
    # And the remainder exactly what `floor_modulo()` gives.
    testing.assert_equal(
        String(remainder),
        String(biguint_arithmetics.floor_modulo(x, y)),
        "floor_divide_modulo() and floor_modulo() disagree for " + note,
    )


def assert_divides_digits(digits_x: Int, digits_y: Int) raises:
    """As `assert_divides()`, on generated operands of the given widths."""
    var x = BigUInt(build_digits(digits_x, 7))
    var y = BigUInt(build_digits(digits_y, 5))
    assert_divides(
        x, y, String(digits_x) + " digits by " + String(digits_y) + " digits"
    )


def test_edge_cases() raises:
    """Zero, equal operands, a dividend below the divisor, and a divisor of one.
    """
    assert_divides(BigUInt.zero(), BigUInt("7"), "zero dividend")
    assert_divides(BigUInt("12345"), BigUInt("12345"), "equal operands")
    assert_divides(BigUInt("12"), BigUInt("12345"), "dividend below divisor")
    assert_divides(BigUInt("12345"), BigUInt.one(), "divisor of one")


def test_division_by_zero_raises() raises:
    """A zero divisor must raise rather than return a bogus remainder."""
    var raised = False
    try:
        var _ignored = biguint_arithmetics.floor_divide_modulo(
            BigUInt("12345"), BigUInt.zero()
        )
    except:
        raised = True
    testing.assert_true(raised, "division by zero did not raise")


def test_short_divisors() raises:
    """One, two, and up-to-four word divisors take the scalar paths.

    Each of those keeps the remainder in a carry of a different width, so all
    three are worth walking.
    """
    var widths_of_divisor = [1, 5, 9, 10, 18, 19, 27, 36]
    var widths_of_dividend = [1, 9, 20, 100, 1000]
    for i in range(len(widths_of_divisor)):
        for j in range(len(widths_of_dividend)):
            assert_divides_digits(widths_of_dividend[j], widths_of_divisor[i])


def test_power_of_ten_divisors() raises:
    """A power of ten has its own branch, and the split is not word-aligned
    unless the exponent is a multiple of nine."""
    var exponents = [1, 5, 8, 9, 10, 17, 18, 27, 100, 101]
    var x = BigUInt(build_digits(300, 7))
    for i in range(len(exponents)):
        var y = biguint_arithmetics.multiply_by_power_of_ten(
            BigUInt.one(), exponents[i]
        )
        assert_divides(x, y, "10^" + String(exponents[i]))


def test_schoolbook_divisors() raises:
    """Divisors of five to thirty-two words go through Knuth D."""
    var widths_of_divisor = [45, 90, 180, 288]
    var widths_of_dividend = [50, 200, 400, 576]
    for i in range(len(widths_of_divisor)):
        for j in range(len(widths_of_dividend)):
            if widths_of_dividend[j] >= widths_of_divisor[i]:
                assert_divides_digits(
                    widths_of_dividend[j], widths_of_divisor[i]
                )


def test_schoolbook_normalization() raises:
    """The remainder comes back scaled when the operands were normalized.

    A divisor whose leading word is small is scaled up before Knuth D runs, and
    the remainder is scaled with it. A leading word of 1 forces the largest
    shift, a leading word of 999_999_999 forces none.
    """
    var small_lead = BigUInt("1" + build_digits(199, 3))
    var large_lead = BigUInt("999999999" + build_digits(191, 3))
    var x = BigUInt(build_digits(500, 7))
    assert_divides(x, small_lead, "divisor with a leading word of 1")
    assert_divides(x, large_lead, "divisor with a full leading word")


def test_burnikel_ziegler_divisors() raises:
    """Above the cutoff the recursion carries the remainder between blocks,
    and normalization has to be undone on the way out."""
    var widths_of_divisor = [300, 600, 1200]
    var widths_of_dividend = [700, 1500, 3000]
    for i in range(len(widths_of_divisor)):
        for j in range(len(widths_of_dividend)):
            if widths_of_dividend[j] >= widths_of_divisor[i]:
                assert_divides_digits(
                    widths_of_dividend[j], widths_of_divisor[i]
                )


def test_exact_divisions() raises:
    """An exact division must report a remainder of exactly zero.

    This is what `BigDecimal.__truediv__()` reads to decide whether it may
    drop trailing zeros, so a remainder that is merely small is not enough.
    """
    var widths = [10, 100, 400, 1000]
    for i in range(len(widths)):
        var y = BigUInt(build_digits(widths[i], 5))
        var multiplier = BigUInt(build_digits(widths[i] // 2 + 1, 3))
        var x = biguint_arithmetics.multiply(y, multiplier)
        var remainder = BigUInt.zero()
        var quotient = biguint_arithmetics.floor_divide_modulo(x, y, remainder)
        testing.assert_true(
            remainder.is_zero(),
            "an exact division reported a non-zero remainder at "
            + String(widths[i])
            + " digits",
        )
        testing.assert_equal(String(quotient), String(multiplier))


def test_floor_modulo_by_power_of_ten() raises:
    """The helper keeps the low n digits, whatever the word alignment."""
    var x = BigUInt("123456789987654321000000000111222333")
    testing.assert_equal(
        String(biguint_arithmetics.floor_modulo_by_power_of_ten(x, 0)), "0"
    )
    testing.assert_equal(
        String(biguint_arithmetics.floor_modulo_by_power_of_ten(x, 3)), "333"
    )
    testing.assert_equal(
        String(biguint_arithmetics.floor_modulo_by_power_of_ten(x, 9)),
        "111222333",
    )
    testing.assert_equal(
        String(biguint_arithmetics.floor_modulo_by_power_of_ten(x, 12)),
        "111222333",
    )
    testing.assert_equal(
        String(biguint_arithmetics.floor_modulo_by_power_of_ten(x, 18)),
        "111222333",
    )
    testing.assert_equal(
        String(biguint_arithmetics.floor_modulo_by_power_of_ten(x, 21)),
        "321000000000111222333",
    )
    # Asking for more digits than the number has keeps all of them.
    testing.assert_equal(
        String(biguint_arithmetics.floor_modulo_by_power_of_ten(x, 1000)),
        String(x),
    )


def test_ceil_modulo_still_agrees() raises:
    """`ceil_modulo()` is derived from the same remainder."""
    var x = BigUInt(build_digits(200, 7))
    var y = BigUInt(build_digits(60, 5))
    var floor_remainder = biguint_arithmetics.floor_modulo(x, y)
    var ceil_remainder = biguint_arithmetics.ceil_modulo(x, y)
    if floor_remainder.is_zero():
        testing.assert_true(ceil_remainder.is_zero())
    else:
        testing.assert_equal(
            String(biguint_arithmetics.add(floor_remainder, ceil_remainder)),
            String(y),
        )


def test_tuple_form_matches() raises:
    """The two-argument form is the public `divmod`, and must agree."""
    var x = BigUInt(build_digits(400, 7))
    var y = BigUInt(build_digits(90, 5))
    var pair = biguint_arithmetics.floor_divide_modulo(x, y)

    var remainder = BigUInt.zero()
    var quotient = biguint_arithmetics.floor_divide_modulo(x, y, remainder)

    testing.assert_equal(String(pair[0]), String(quotient))
    testing.assert_equal(String(pair[1]), String(remainder))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
