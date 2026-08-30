from bench_biguint_add import main as bench_add
from bench_biguint_divide_complexity import main as bench_div_complexity
from bench_biguint_from_string import main as bench_from_string
from bench_biguint_multiply import main as bench_multiply
from bench_biguint_multiply_complexity import main as bench_mul_complexity
from bench_biguint_sqrt import main as bench_sqrt
from bench_biguint_subtraction import main as bench_subtraction
from bench_biguint_truncate_divide import main as bench_truncate_divide
from bench_scale_up_by_power_of_10 import main as bench_scale_up


def main() raises:
    while True:
        print(
            """
=========================================
This is the BigUInt Benchmarks
=========================================
add:         Add
sub:         Subtract
mul:         Multiply
div:         Truncate divide (//)
sqrt:        Square root
fromstr:     From string
scaleup:     Scale up by power of 10
divcomp:     Division complexity analysis
mulcomp:     Multiplication complexity analysis
all:         Run all benchmarks
q:           Exit
=========================================
"""
        )
        var command = input("Type name of bench you want to run: ")
        if command == "add":
            bench_add()
        elif command == "sub":
            bench_subtraction()
        elif command == "mul":
            bench_multiply()
        elif command == "div":
            bench_truncate_divide()
        elif command == "sqrt":
            bench_sqrt()
        elif command == "fromstr":
            bench_from_string()
        elif command == "scaleup":
            bench_scale_up()
        elif command == "divcomp":
            bench_div_complexity()
        elif command == "mulcomp":
            bench_mul_complexity()
        elif command == "all":
            bench_add()
            bench_subtraction()
            bench_multiply()
            bench_truncate_divide()
            bench_sqrt()
            bench_from_string()
            bench_scale_up()
        elif command == "q":
            return
        else:
            print("Invalid input")
