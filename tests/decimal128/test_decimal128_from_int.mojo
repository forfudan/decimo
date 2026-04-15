"""
Test Decimal128.from_int() and Decimal128 component constructor including:

1. basic integer conversions (TOML)
2. large integer conversions (TOML)
3. from_int with scale (TOML)
4. operations with from_int (inline)
5. comparison with from_int (inline)
6. properties of from_int results (inline)
7. edge cases (inline)
8. from_int with scale - advanced (inline)
9. from_components (inline - 5-arg constructor)
"""

from std import testing
from decimo.toml.parser import TOMLDocument

from decimo import Dec128
from decimo import Decimal128
from decimo.tests import TestCase, parse_file, load_test_cases

comptime file_path = "tests/decimal128/test_data/decimal128_from_int.toml"


def _run_from_int_section(
    toml: TOMLDocument,
    section: String,
    mut count_wrong: Int,
) raises:
    """Helper to run a from_int unary test section."""
    var test_cases = load_test_cases[unary=True](toml, section)
    for test_case in test_cases:
        var result = Dec128.from_int(Int(test_case.a))
        try:
            testing.assert_equal(
                lhs=String(result),
                rhs=test_case.expected,
                msg=test_case.description,
            )
        except e:
            print(
                test_case.description,
                "\n  Expected:",
                test_case.expected,
                "\n  Got:",
                String(result),
                "\n",
            )
            count_wrong += 1


def test_from_int() raises:
    """Test from_int conversions using TOML data-driven test cases."""
    var toml = parse_file(file_path)
    var count_wrong = 0

    _run_from_int_section(toml, "basic_integer_tests", count_wrong)
    _run_from_int_section(toml, "large_integer_tests", count_wrong)

    # from_int with scale: use a=integer, b=scale
    var scale_cases = load_test_cases(toml, "from_int_with_scale_tests")
    for tc in scale_cases:
        var result = Dec128.from_int(Int(tc.a), UInt32(Int(tc.b)))
        try:
            testing.assert_equal(
                lhs=String(result),
                rhs=tc.expected,
                msg=tc.description,
            )
        except e:
            print(
                tc.description,
                "\n  Expected:",
                tc.expected,
                "\n  Got:",
                String(result),
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong,
        0,
        "Some from_int test cases failed. See above for details.",
    )


def test_operations_with_from_int() raises:
    """Test arithmetic operations using from_int results."""
    # Addition
    var result1 = Dec128.from_int(100) + Dec128.from_int(50)
    testing.assert_equal(String(result1), "150")

    # Subtraction
    var result2 = Dec128.from_int(100) - Dec128.from_int(30)
    testing.assert_equal(String(result2), "70")

    # Multiplication
    var result3 = Dec128.from_int(25) * Dec128.from_int(4)
    testing.assert_equal(String(result3), "100")

    # Division
    var result4 = Dec128.from_int(100) / Dec128.from_int(5)
    testing.assert_equal(String(result4), "20")

    # Mixed types
    var result5 = Dec128.from_int(10) * Dec128("3.5")
    testing.assert_equal(String(result5), "35.0")

    # Simple addition from basic test
    var result6 = Dec128.from_int(10) + Dec128.from_int(5)
    testing.assert_equal(String(result6), "15")


def test_comparison_with_from_int() raises:
    """Test comparison operations using from_int results."""
    # Equality with same value
    testing.assert_true(
        Dec128.from_int(100) == Dec128.from_int(100),
        "from_int(100) should equal from_int(100)",
    )

    # Equality with string constructor
    testing.assert_true(
        Dec128.from_int(123) == Dec128("123"),
        "from_int(123) should equal Decimal128('123')",
    )

    # Less than
    testing.assert_true(
        Dec128.from_int(50) < Dec128.from_int(100),
        "from_int(50) should be less than from_int(100)",
    )

    # Greater than
    testing.assert_true(
        Dec128.from_int(200) > Dec128.from_int(100),
        "from_int(200) should be greater than from_int(100)",
    )

    # Equality with negative values
    testing.assert_true(
        Dec128.from_int(-500) == Dec128("-500"),
        "from_int(-500) should equal Decimal128('-500')",
    )


def test_properties() raises:
    """Test properties of from_int results."""
    # Sign of positive
    testing.assert_false(
        Dec128.from_int(100).is_negative(),
        "from_int(100) should not be negative",
    )

    # Sign of negative
    testing.assert_true(
        Dec128.from_int(-100).is_negative(),
        "from_int(-100) should be negative",
    )

    # Scale of integer (should be 0)
    testing.assert_equal(Dec128.from_int(123).scale(), 0)

    # Is_integer test
    testing.assert_true(
        Dec128.from_int(42).is_integer(),
        "from_int result should satisfy is_integer()",
    )

    # Coefficient correctness
    testing.assert_equal(Dec128.from_int(9876).coefficient(), UInt128(9876))


def test_edge_cases() raises:
    """Test edge cases for from_int."""
    # Zero remains zero
    testing.assert_equal(String(Dec128.from_int(0)), "0")

    # Negative zero handling
    var neg_zero = -0
    var dec_neg_zero = Dec128.from_int(neg_zero)
    testing.assert_false(
        dec_neg_zero.is_negative() and dec_neg_zero.is_zero(),
        "Negative zero should not preserve negative sign",
    )

    # INT64_MIN
    var int64_min = Dec128.from_int(-9223372036854775807 - 1)
    testing.assert_equal(String(int64_min), "-9223372036854775808")

    # from_int vs from_string equivalence
    testing.assert_true(
        Dec128.from_int(12345) == Dec128("12345"),
        "from_int and from_string should create equal Decimals",
    )

    # Powers of 10
    testing.assert_equal(String(Dec128.from_int(10**9)), "1000000000")


def test_from_int_with_scale_advanced() raises:
    """Test from_int with scale - advanced cases requiring inline assertions."""
    # Scale is correctly stored
    var r1 = Dec128.from_int(123, 2)
    testing.assert_equal(r1.scale(), 2)

    # Negative with scale stored correctly
    var r2 = Dec128.from_int(-456, 3)
    testing.assert_equal(r2.scale(), 3)

    # Zero with scale stored correctly
    var r3 = Dec128.from_int(0, 4)
    testing.assert_equal(r3.scale(), 4)

    # Large scale correctly stored
    var r5 = Dec128.from_int(1, 25)
    testing.assert_equal(r5.scale(), 25)

    # Max scale
    var r6 = Dec128.from_int(1, UInt32(Decimal128.MAX_SCALE))
    testing.assert_equal(r6.scale(), Decimal128.MAX_SCALE)

    # Arithmetic with scaled value: 1.0 / 0.03
    var a7 = Dec128.from_int(10, 1)
    var b7 = Dec128.from_int(3, 2)
    var result7 = a7 / b7
    testing.assert_equal(String(result7), "33.333333333333333333333333333")

    # Comparison with different scales but same value
    var a8 = Dec128.from_int(123, 0)
    var b8 = Dec128.from_int(123, 2)
    testing.assert_true(a8 != b8, "from_int(123, 0) != from_int(123, 2)")


def test_decimal_from_components() raises:
    """Test Decimal128 5-argument component constructor."""
    # Zero with zero scale
    testing.assert_equal(String(Decimal128(0, 0, 0, 0, False)), "0")

    # One with zero scale
    testing.assert_equal(String(Decimal128(1, 0, 0, 0, False)), "1")

    # Negative one
    testing.assert_equal(String(Decimal128(1, 0, 0, 0, True)), "-1")

    # Simple number with scale
    testing.assert_equal(String(Decimal128(12345, 0, 0, 2, False)), "123.45")

    # Negative number with scale
    testing.assert_equal(String(Decimal128(12345, 0, 0, 2, True)), "-123.45")

    # Larger number using mid
    var large = Decimal128(0xFFFFFFFF, 5, 0, 0, False)
    var expected_large = Decimal128(String(0xFFFFFFFF + 5 * 4294967296))
    testing.assert_equal(String(large), String(expected_large))

    # Scale correctly stored
    var high_scale = Decimal128(123, 0, 0, 10, False)
    testing.assert_equal(high_scale.scale(), 10)
    testing.assert_equal(String(high_scale), "0.0000000123")

    # Large scale with negative number
    testing.assert_equal(
        String(Decimal128(123, 0, 0, 10, True)), "-0.0000000123"
    )

    # Sign flag
    testing.assert_false(Decimal128(0, 0, 0, 0, False).is_negative())
    testing.assert_false(Decimal128(1, 0, 0, 0, False).is_negative())
    testing.assert_true(Decimal128(1, 0, 0, 0, True).is_negative())

    # With high component
    testing.assert_equal(
        String(Decimal128(0, 0, 3, 0, False)), "55340232221128654848"
    )

    # Maximum possible scale
    testing.assert_equal(Decimal128(123, 0, 0, 28, False).scale(), 28)

    # Overflow scale protection
    try:
        var _overflow_scale = Decimal128(123, 0, 0, 100, False)
    except:
        pass


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
