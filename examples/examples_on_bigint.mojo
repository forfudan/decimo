from decimo.prelude import *


def main() raises:
    # === Construction ===
    var a = Integer("12345678901234567890")  # From string
    var b = Integer(12345)  # From integer
    var c = Integer("1991_10,18")  # From string with separators and spaces
    print(a, b, c)

    # === Basic Arithmetic ===
    print(a + b)  # Addition: 12345678901234580235
    print(a - b)  # Subtraction: 12345678901234555545
    print(a * b)  # Multiplication: 152415787814108380241050

    # === Division Operations ===
    print(a // b)  # Floor division: 999650944609516
    print(a.truncate_divide(b))  # Truncate division: 999650944609516
    print(a % b)  # Modulo: 9615

    # === Power Operation ===
    print(Integer(2).power(10))  # Power: 1024
    print(Integer(2) ** 10)  # Power (using ** operator): 1024

    # === Comparison ===
    print(a > b)  # Greater than: True
    print(a == Integer("12345678901234567890"))  # Equality: True
    print(a.is_zero())  # Check for zero: False

    # === Type Conversions ===
    print(String(a))  # To string: "12345678901234567890"

    # === Sign Handling ===
    print(-a)  # Negation: -12345678901234567890
    print(
        abs(Integer("-12345678901234567890"))
    )  # Absolute value: 12345678901234567890
    print(a.is_negative())  # Check if negative: False

    # === Extremely large numbers ===
    # 3600 digits // 1800 digits
    print(Integer("123456789" * 400) // Integer("987654321" * 200))

    # === Greatest common divisor ===
    print(a.gcd(b))  # Greatest common divisor: 15
    print(a.gcd(c))  # Greatest common divisor: 6
