from decimo.prelude import *


def main() raises:
    # === Construction ===
    var a = Dec128("123.45")  # From string
    var b = Dec128(123)  # From integer
    var c = Dec128(123, 2)  # Integer with scale (1.23)
    var d = Dec128.from_float(3.14159)  # From floating-point

    # === Basic Arithmetic ===
    print(a + b)  # Addition: 246.45
    print(a - b)  # Subtraction: 0.45
    print(a * b)  # Multiplication: 15184.35
    print(a / b)  # Division: 1.0036585365853658536585365854

    # === Rounding & Precision ===
    print(a.round(1))  # Round to 1 decimal place: 123.5
    print(a.quantize(Dec128("0.01")))  # Format to 2 decimal places: 123.45
    print(a.round(0, RoundingMode.ROUND_DOWN))  # Round down to integer: 123

    # === Comparison ===
    print(a > b)  # Greater than: True
    print(a == Dec128("123.45"))  # Equality: True
    print(a.is_zero())  # Check for zero: False
    print(Dec128("0").is_zero())  # Check for zero: True

    # === Type Conversions ===
    print(Float64(a))  # To float: 123.45
    print(a.to_int())  # To integer: 123
    print(a.to_str())  # To string: "123.45"
    print(a.coefficient())  # Get coefficient: 12345
    print(a.scale())  # Get scale: 2

    # === Mathematical Functions ===
    print(Dec128("2").sqrt())  # Square root: 1.4142135623730950488016887242
    print(Dec128("100").root(3))  # Cube root: 4.641588833612778892410076351
    print(Dec128("2.71828").ln())  # Natural log: 0.9999993273472820031578910056
    print(Dec128("10").log10())  # Base-10 log: 1
    print(
        Dec128("16").log(Dec128("2"))
    )  # Log base 2: 3.9999999999999999999999999999
    print(Dec128("10").exp())  # e^10: 22026.465794806716516957900645
    print(Dec128("2").power(10))  # Power: 1024

    # === Sign Handling ===
    print(-a)  # Negation: -123.45
    print(abs(Dec128("-123.45")))  # Absolute value: 123.45
    print(Dec128("123.45").is_negative())  # Check if negative: False

    # === Special Values ===
    print(Dec128.PI())  # π constant: 3.1415926535897932384626433833
    print(Dec128.E())  # e constant: 2.7182818284590452353602874714
    print(Dec128.ONE())  # Value 1: 1
    print(Dec128.ZERO())  # Value 0: 0
    print(Dec128.MAX())  # Maximum value: 79228162514264337593543950335

    # === Convenience Methods ===
    print(Dec128("123.400").is_integer())  # Check if integer: False
    print(a.number_of_significant_digits())  # Count significant digits: 5
    print(Dec128("12.34").to_str_scientific())  # Scientific notation: 1.234E+1
