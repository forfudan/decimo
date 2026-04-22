"""
Test Decimal128 multiplication operations including:

1. basic multiplication (TOML)
2. special cases - zero, one (TOML)
3. negative multiplication (TOML)
4. precision and scale (TOML + inline)
5. boundary cases (TOML + inline)
6. commutative property (TOML)
7. Granlund-Möller UInt256 / 10^k stress sweep (TOML, 61 cases covering
   every k ∈ [1, 29] of the GM divider plus large-int × small-frac,
   max-class, transcendental, and negative-product variants)
"""

from std.python import Python, PythonObject
from std import testing
from decimo.toml.parser import TOMLDocument

from decimo import Dec128
from decimo import Decimal128
from decimo.tests import TestCase, parse_file, load_test_cases

comptime file_path = "tests/decimal128/test_data/decimal128_multiply.toml"


def _run_multiply_section(
    toml: TOMLDocument,
    pydecimal: PythonObject,
    section: String,
    mut count_wrong: Int,
) raises:
    """Helper to run a binary multiply test section."""
    var test_cases = load_test_cases(toml, section)
    for tc in test_cases:
        var result = Dec128(tc.a) * Dec128(tc.b)
        try:
            testing.assert_equal(
                lhs=String(result), rhs=tc.expected, msg=tc.description
            )
        except e:
            print(
                tc.description,
                "\n  Expected:",
                tc.expected,
                "\n  Got:",
                String(result),
                "\n  Python decimal result:",
                String(pydecimal.Decimal(tc.a) * pydecimal.Decimal(tc.b)),
                "\n",
            )
            count_wrong += 1


def test_multiplication() raises:
    """Test multiplication using TOML data-driven test cases."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)
    var count_wrong = 0

    _run_multiply_section(toml, pydecimal, "basic_tests", count_wrong)
    _run_multiply_section(toml, pydecimal, "special_tests", count_wrong)
    _run_multiply_section(toml, pydecimal, "negative_tests", count_wrong)
    _run_multiply_section(toml, pydecimal, "precision_tests", count_wrong)
    _run_multiply_section(toml, pydecimal, "boundary_tests", count_wrong)
    _run_multiply_section(toml, pydecimal, "gm_stress_tests", count_wrong)

    testing.assert_equal(count_wrong, 0, "Some multiplication tests failed.")


def test_commutative_property() raises:
    """Test that a*b == b*a for all commutative test cases."""
    var toml = parse_file(file_path)
    var test_cases = load_test_cases(toml, "commutative_tests")
    var count_wrong = 0
    for tc in test_cases:
        var ab = Dec128(tc.a) * Dec128(tc.b)
        var ba = Dec128(tc.b) * Dec128(tc.a)
        try:
            testing.assert_equal(
                lhs=String(ab), rhs=tc.expected, msg=tc.description
            )
            testing.assert_equal(
                lhs=String(ab),
                rhs=String(ba),
                msg="Commutative: " + tc.description,
            )
        except e:
            print(
                tc.description,
                "\n  a*b:",
                String(ab),
                "  b*a:",
                String(ba),
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(count_wrong, 0, "Some commutative tests failed.")


def test_precision_scale_properties() raises:
    """Test scale and precision properties of multiplication results."""
    # Scale addition: scale(0.5) + scale(0.25) = 1 + 2 = 3
    var r1 = Dec128("0.5") * Dec128("0.25")
    testing.assert_equal(r1.scale(), 3)

    # High precision scale
    var r2 = Dec128("0.1234567890") * Dec128("0.9876543210")
    testing.assert_equal(r2.scale(), 20)

    # Scale 14+14 = 28 (at limit)
    var r3 = Dec128("0." + "1" * 14) * Dec128("0." + "9" * 14)
    testing.assert_equal(r3.scale(), 28)

    # Scale overflow: 15+15 = 30 -> capped at 28
    var r4 = Dec128("0." + "1" * 15) * Dec128("0." + "9" * 15)
    testing.assert_equal(r4.scale(), 28)

    # Rounding during scale adjustment
    var r5 = Dec128("0.123456789012345678901234567") * Dec128("0.2")
    testing.assert_equal(r5.scale(), 28)


def test_boundary_cases_inline() raises:
    """Test boundary cases that require assertions beyond simple equality."""
    # Near max value
    var near_max = Dec128("38614081257132168796771975168")
    var result1 = near_max * Dec128("1.9")
    testing.assert_true(result1 < Decimal128.MAX())

    # Very different scales
    var tiny = Dec128("0." + "0" * 20 + "1")
    var huge = Dec128("1" + "0" * 20)
    testing.assert_equal(String(tiny * huge), "0.100000000000000000000")

    # Max value times 0.01
    var max_dec = Decimal128.MAX()
    testing.assert_equal(
        String(max_dec * Dec128("0.01")),
        "792281625142643375935439503.35",
    )

    # Smallest representable times one
    var small = Dec128("0." + "0" * 27 + "1")
    var one = Dec128(1)
    testing.assert_equal(String(small * one), String(small))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
