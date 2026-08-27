"""Decimal programs written once, run against either library.

Every function here takes the module to use -- `decimal` or `decimo` -- and
touches nothing that is not in both. That is the whole point: if decimo is a
drop-in replacement, this file should not need to know which one it got.
"""


def micro(mod, digits, rounds):
    """The four operators, on operands of `digits` digits."""
    Decimal = mod.Decimal
    mod.getcontext().prec = digits
    a = Decimal("1." + ("23456789" * (digits // 8 + 1))[: digits - 1])
    b = Decimal("9." + ("87654321" * (digits // 8 + 1))[: digits - 1])
    total = Decimal(0)
    for _ in range(rounds):
        total = a + b
        total = a - b
        total = a * b
        total = a / b
    return total


def compound_interest(mod, years):
    """A balance rolled forward, the way money code actually looks."""
    Decimal = mod.Decimal
    mod.getcontext().prec = 28
    balance = Decimal("10000.00")
    rate = Decimal("1.0425")
    cent = Decimal("0.01")
    for _ in range(years):
        balance = (balance * rate).quantize(cent)
    return balance


def exp_series(mod, terms, precision):
    """`e` from its series: a division and an addition per term."""
    Decimal = mod.Decimal
    mod.getcontext().prec = precision
    total = Decimal(1)
    term = Decimal(1)
    for n in range(1, terms + 1):
        term = term / Decimal(n)
        total = total + term
    return total


def sqrt_newton(mod, value, precision):
    """A square root by Newton's method, all in decimal."""
    Decimal = mod.Decimal
    mod.getcontext().prec = precision
    x = Decimal(value)
    guess = Decimal(1)
    half = Decimal("0.5")
    for _ in range(precision.bit_length() + 8):
        guess = (guess + x / guess) * half
    return guess


def pi_machin(mod, precision):
    """pi by Machin's formula, which is arctan by series: divide-heavy."""
    Decimal = mod.Decimal
    mod.getcontext().prec = precision + 10

    def arctan_inverse(n):
        # arctan(1/n) = 1/n - 1/(3 n^3) + 1/(5 n^5) - ...
        n = Decimal(n)
        n_squared = n * n
        term = Decimal(1) / n
        total = term
        divisor = 1
        sign = -1
        while True:
            term = term / n_squared
            divisor += 2
            addend = term / Decimal(divisor) * sign
            # Stop when the term no longer moves the sum. Waiting for the term
            # to reach exactly zero would work only for a library with a
            # smallest exponent; decimo has none, so it would never stop.
            if total + addend == total:
                break
            total += addend
            sign = -sign
        return total

    pi = (arctan_inverse(5) * 4 - arctan_inverse(239)) * 4
    mod.getcontext().prec = precision
    return +pi


def string_round_trip(mod, digits, rounds):
    """Parse and print, which is what a program does at its edges."""
    Decimal = mod.Decimal
    mod.getcontext().prec = digits
    text = "3." + "14159265" * (digits // 8)
    value = Decimal(0)
    for _ in range(rounds):
        value = Decimal(text)
        text = str(value)
    return value
