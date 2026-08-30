"""
Test BigInt10 conversion methods: to_int() and __int__
for different numerical cases.
"""

from std import testing

import decimo.bigint10.arithmetics as arithmetics
from decimo.bigint10.bigint10 import BigInt10


def test_int_conversion() raises:
    # Test positive integer
    var b1 = BigInt10("123")
    var i1 = b1.to_int()
    testing.assert_equal(i1, 123)

    # Test through __int__() operator
    var i1b = Int(b1)
    testing.assert_equal(i1b, 123)

    # Test negative integer
    var b2 = BigInt10("-456")
    var i2 = b2.to_int()
    testing.assert_equal(i2, -456)

    # Test zero
    var b3 = BigInt10("0")
    var i3 = b3.to_int()
    testing.assert_equal(i3, 0)

    # Test large positive number within Int range
    var b4 = BigInt10("9999999999")  # 10 billion is within Int64 range
    var i4 = b4.to_int()
    testing.assert_equal(i4, 9999999999)

    # Test large negative number within Int range
    var b5 = BigInt10("-9999999999")
    var i5 = b5.to_int()
    testing.assert_equal(i5, -9999999999)

    # Test Int.MAX edge case
    var b6 = BigInt10(String(Int.MAX))
    var i6 = b6.to_int()
    testing.assert_equal(i6, Int.MAX)

    # Test Int.MIN edge case
    var b7 = BigInt10(String(Int.MIN))
    var i7 = b7.to_int()
    testing.assert_equal(i7, Int.MIN)


def test_error_cases() raises:
    # Test number larger than Int.MAX
    var b1 = BigInt10(String(Int.MAX)) + BigInt10("1")
    var exception_caught = False
    try:
        var _b1 = b1.to_int()
    except:
        exception_caught = True
    testing.assert_true(
        exception_caught, "Expected error for value exceeding Int.MAX"
    )

    # Test number smaller than Int.MIN
    var b2 = BigInt10(String(Int.MIN)) - BigInt10("1")
    exception_caught = False
    try:
        var _b2 = b2.to_int()
    except:
        exception_caught = True
    testing.assert_true(
        exception_caught, "Expected error for value less than Int.MIN"
    )

    # Test very large number
    var b3 = BigInt10("99999999999999999999999999999")  # Way beyond Int64 range
    exception_caught = False
    try:
        var _b3 = b3.to_int()
    except:
        exception_caught = True
    testing.assert_true(
        exception_caught, "Expected error for very large BigInt10"
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
