import decimo.bigfloat.constants as bigfloat_constants
import decimo.bigfloat.trigonometric as bigfloat_trigonometric
from decimo.prelude import *


def main() raises:
    # === Construction: the precision is in bits, and is per value ===
    var a = BigFloat.from_string("1.1", 53)  # What a Float64 holds
    var b = BFlt.from_string("1.1", 200)  # 200 bits of it
    print(a.to_string(), b.to_string(20))
    # 1.1000000000000001 1.1000000000000000000

    # === The four operations, each correctly rounded ===
    var third = BigFloat.from_string("1", 200) / BigFloat.from_string("3", 200)
    print(third.to_string(20))  # 0.33333333333333333333
    print((a + a).to_string(), (b * b).to_string(20))
    # 2.2000000000000002 1.2100000000000000000

    # === Square root, logarithm, exponential, power ===
    var two = BigFloat.from_string("2", 200)
    print(two.sqrt().to_string(20))  # 1.4142135623730950488
    print(two.ln().to_string(20))  # 0.69314718055994530942
    print(two.exp().to_string(20))  # 7.3890560989306502272
    print(two.power(BigFloat.from_string("0.5", 200)).to_string(20))
    # 1.4142135623730950488

    # === Pi and the circular functions, at the width you ask for ===
    var pi = bigfloat_constants.pi(200)
    print(pi.to_string(20))  # 3.1415926535897932385
    print(bigfloat_trigonometric.sin(pi / two, 200).to_string(20))  # 1

    # === Seven rounding modes, and the neighbours of a value ===
    print(two.sqrt().to_string(5, ROUND_DOWN))  # 1.4142
    print(two.sqrt().to_string(5, ROUND_UP))  # 1.4143
    print(a.next_plus(53).to_string())  # 1.1000000000000003
    print(a.next_minus(53).to_string())  # 1.0999999999999999

    # === The classes IEEE 754 asks for ===
    print(BigFloat.infinity(53).number_class())  # +Infinity
    print(BigFloat.nan(53).is_nan())  # True
