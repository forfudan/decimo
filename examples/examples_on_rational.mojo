from std.math import ceil, floor

from decimo import Frac, Rational
from decimo.prelude import *


def main() raises:
    # === Construction ===
    var a = Rational("3/7")  # From a ratio of two literals
    var b = Rational("1.5")  # Read exactly: 3/2
    var c = Rational(BigInt(22), BigInt(-8))  # Reduced and signed: -11/4
    print(a, b, c)  # 3/7 3/2 -11/4

    # === Exact arithmetic ===
    print(Rational("1/3") + Rational("1/6"))  # 1/2
    print(a * b)  # 9/14
    print(a / b)  # 2/7
    print(Rational("1/3") ** 5)  # 1/243

    # === Nothing rounds, so the thirds come back whole ===
    print(Rational("1/3") * Rational(BigInt(3)) == Rational.one())  # True

    # === Comparison ===
    print(a < b, a == Rational("6/14"))  # True True

    # === Rounding, where you ask for it ===
    print(round(Rational("7/2")), round(Rational("-7/2")))  # 4 -4
    print(round(Rational("22/7"), 4))  # 31429/10000
    print(floor(Rational("7/2")), ceil(Rational("7/2")))  # 3 4

    # === Conversions ===
    print(Rational("22/7").to_bigdecimal(30))  # 3.14285714285714285714285714286
    print(Rational(BigDecimal("0.125")))  # 1/8
    print(Rational("22/7").to_float())  # 3.142857142857143

    # === The closest value with a denominator you can live with ===
    print(
        Rational(BigDecimal("3.141592653589793")).limit_denominator(
            BigInt(1000)
        )
    )  # 355/113
