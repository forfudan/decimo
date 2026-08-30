"""
Test BigInt10.from_python_int() method.
Tests conversion from Python integers to Mojo BigInt10.
"""

from std import testing
from std.python import Python

from decimo.bigint10.bigint10 import BigInt10
from decimo.biguint.biguint import BigUInt


def test_from_python_int_basic() raises:
    """Test basic Python int to BigInt10 conversion."""
    var py = Python.import_module("builtins")

    # Test zero
    var py_zero = py.int(0)
    var mojo_zero = BigInt10.from_python_int(py_zero)
    testing.assert_equal(String(mojo_zero), "0", "Zero conversion")

    # Test small positive integer
    var py_pos = py.int(123)
    var mojo_pos = BigInt10.from_python_int(py_pos)
    testing.assert_equal(String(mojo_pos), "123", "Small positive integer")

    # Test small negative integer
    var py_neg = py.int(-456)
    var mojo_neg = BigInt10.from_python_int(py_neg)
    testing.assert_equal(String(mojo_neg), "-456", "Small negative integer")


def test_from_python_int_large() raises:
    """Test large Python int to BigInt10 conversion."""
    var py = Python.import_module("builtins")

    # Test large positive integer (> 2^64)
    var large_pos_str = "123456789012345678901234567890"
    var py_large_pos = py.int(large_pos_str)
    var mojo_large_pos = BigInt10.from_python_int(py_large_pos)
    testing.assert_equal(
        String(mojo_large_pos), large_pos_str, "Large positive integer (> 2^64)"
    )

    # Test large negative integer
    var large_neg_str = "-987654321098765432109876543210"
    var py_large_neg = py.int(large_neg_str)
    var mojo_large_neg = BigInt10.from_python_int(py_large_neg)
    testing.assert_equal(
        String(mojo_large_neg), large_neg_str, "Large negative integer"
    )

    # Test very large integer (1000+ digits)
    var very_large_str = "1" + "0" * 1000
    var py_very_large = py.int(very_large_str)
    var mojo_very_large = BigInt10.from_python_int(py_very_large)
    testing.assert_equal(
        String(mojo_very_large),
        very_large_str,
        "Very large integer (1000+ digits)",
    )


def test_from_python_int_edge_cases() raises:
    """Test edge cases for Python int conversion."""
    var py = Python.import_module("builtins")

    # Test powers of 10
    var py_1e9 = py.int("1000000000")  # 10^9
    var mojo_1e9 = BigInt10.from_python_int(py_1e9)
    testing.assert_equal(String(mojo_1e9), "1000000000", "10^9")

    var py_1e18 = py.int("1000000000000000000")  # 10^18
    var mojo_1e18 = BigInt10.from_python_int(py_1e18)
    testing.assert_equal(String(mojo_1e18), "1000000000000000000", "10^18")

    # Test number with all 9's (boundary word values)
    var py_nines = py.int("999999999")
    var mojo_nines = BigInt10.from_python_int(py_nines)
    testing.assert_equal(String(mojo_nines), "999999999", "All 9's")

    var py_multi_word = py.int("999999999888888888")
    var mojo_multi_word = BigInt10.from_python_int(py_multi_word)
    testing.assert_equal(
        String(mojo_multi_word), "999999999888888888", "Multiple words with 9's"
    )


def test_from_python_int_arithmetic() raises:
    """Test that converted BigInt10 can perform arithmetic correctly."""
    var py = Python.import_module("builtins")

    # Convert two Python ints
    var py_a = py.int("123456789012345678901234567890")
    var py_b = py.int("987654321098765432109876543210")

    var mojo_a = BigInt10.from_python_int(py_a)
    var mojo_b = BigInt10.from_python_int(py_b)

    # Test addition
    var result_add = mojo_a + mojo_b
    var expected_add = String(py_a + py_b)
    testing.assert_equal(
        String(result_add), expected_add, "Addition after conversion"
    )

    # Test subtraction
    var result_sub = mojo_b - mojo_a
    var expected_sub = String(py_b - py_a)
    testing.assert_equal(
        String(result_sub), expected_sub, "Subtraction after conversion"
    )

    # Test multiplication
    var py_c = py.int("12345")
    var py_d = py.int("67890")
    var mojo_c = BigInt10.from_python_int(py_c)
    var mojo_d = BigInt10.from_python_int(py_d)
    var result_mul = mojo_c * mojo_d
    var expected_mul = String(py_c * py_d)
    testing.assert_equal(
        String(result_mul), expected_mul, "Multiplication after conversion"
    )


def test_from_python_int_sign() raises:
    """Test sign handling in Python int conversion."""
    var py = Python.import_module("builtins")

    # Test positive sign
    var py_pos = py.int("123456")
    var mojo_pos = BigInt10.from_python_int(py_pos)
    testing.assert_false(mojo_pos.sign, "Positive number has sign=False")

    # Test negative sign
    var py_neg = py.int("-123456")
    var mojo_neg = BigInt10.from_python_int(py_neg)
    testing.assert_true(mojo_neg.sign, "Negative number has sign=True")

    # Test zero sign
    var py_zero = py.int(0)
    var mojo_zero = BigInt10.from_python_int(py_zero)
    testing.assert_false(mojo_zero.sign, "Zero has sign=False")


def test_from_python_int_constructor() raises:
    """Test the py= constructor syntax."""
    var py = Python.import_module("builtins")

    # Test with py= constructor
    var py_int = py.int("123456789012345678901234567890")
    var mojo_int = BigInt10(py=py_int)
    testing.assert_equal(
        String(mojo_int),
        "123456789012345678901234567890",
        "Constructor with py= keyword",
    )

    # Test negative with py= constructor
    var py_neg = py.int("-987654321")
    var mojo_neg = BigInt10(py=py_neg)
    testing.assert_equal(
        String(mojo_neg), "-987654321", "Negative with py= constructor"
    )


def test_from_python_int_roundtrip() raises:
    """Test Python -> Mojo -> Python roundtrip."""
    var py = Python.import_module("builtins")

    # Create Python int
    var original_str = "123456789012345678901234567890123456789"
    var py_original = py.int(original_str)

    # Convert to Mojo BigInt10
    var mojo_int = BigInt10.from_python_int(py_original)

    # Convert back to Python (via string)
    var roundtrip_str = String(mojo_int)
    var py_roundtrip = py.int(roundtrip_str)

    # Compare
    testing.assert_equal(
        String(py_roundtrip),
        original_str,
        "Roundtrip conversion preserves value",
    )


def test_from_words_normalises_leading_zero_words() raises:
    """`from_words` validated the word range and then skipped normalising.

    Its sibling `from_list()` goes through `BigUInt.from_list()`, which strips
    leading zero words; `from_words` built the magnitude with `raw_words=`,
    which by contract does not. So `from_words(5, 0)` printed as
    "000000000000000005", `from_words(0, 0)` compared unequal to zero, and
    `from_words(0, 0, sign=True)` printed as a negative zero -- which every
    other constructor in this type normalises away, because the sign is only
    dropped when the magnitude reads as zero.

    This is the same defect, in the same shape, as the one fixed in
    `BigUInt.from_words()`.
    """
    var with_a_zero_on_top = BigInt10.from_words(
        BigUInt.Word(5), BigUInt.Word(0), sign=False
    )
    testing.assert_equal(String(with_a_zero_on_top), "5")
    testing.assert_equal(len(with_a_zero_on_top.magnitude.words), 1)

    for sign in [False, True]:
        var zeros = BigInt10.from_words(
            BigUInt.Word(0), BigUInt.Word(0), sign=sign
        )
        testing.assert_equal(String(zeros), "0")
        testing.assert_equal(len(zeros.magnitude.words), 1)
        testing.assert_true(zeros == BigInt10())

    # Negative values keep their sign, and the two constructors agree.
    var negative = BigInt10.from_words(
        BigUInt.Word(7), BigUInt.Word(0), sign=True
    )
    testing.assert_equal(String(negative), "-7")
    testing.assert_true(
        negative == BigInt10.from_list([BigUInt.Word(7)], sign=True)
    )

    # A word at the base is still rejected.
    with testing.assert_raises():
        _ = BigInt10.from_words(BigUInt.Word(BigUInt.BASE_MAX) + 1, sign=False)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
