"""
Test BigDecimal rounding operations with various rounding modes and precision values.
"""

from std.python import Python
from std import testing

from decimo.bigdecimal.bigdecimal import BDec
from decimo.rounding_mode import RoundingMode
from decimo.tests import TestCase, parse_file, load_test_cases

comptime file_path = "tests/bigdecimal/test_data/bigdecimal_rounding.toml"


def test_bigdecimal_rounding() raises:
    # Load test cases from TOML file
    var pydecimal = Python.import_module("decimal")
    # Set high precision so Python's quantize doesn't raise InvalidOperation
    # for results that exceed the default 28 significant digits.
    pydecimal.getcontext().prec = 500
    var toml = parse_file(file_path)
    var test_cases: List[TestCase]

    # -------------------------------------------------------
    # Testing BigDecimal ROUND_DOWN mode
    # -------------------------------------------------------

    pydecimal.getcontext().rounding = pydecimal.ROUND_DOWN
    test_cases = load_test_cases(toml, "round_down_tests")
    var count_wrong = 0
    for test_case in test_cases:
        var precision = Int(test_case.b)
        var result = BDec(test_case.a).round(precision, RoundingMode.down())
        var mojo_str = String(result)
        # Use string construction to preserve exponent for quantize template:
        # Decimal("1E-2") has exponent -2 (0.01), Decimal("1E2") has exponent 2.
        var template = pydecimal.Decimal("1E" + String(-precision))
        var py_str = String(pydecimal.Decimal(test_case.a).quantize(template))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "ROUND_DOWN: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal ROUND_UP mode
    # -------------------------------------------------------

    pydecimal.getcontext().rounding = pydecimal.ROUND_UP
    test_cases = load_test_cases(toml, "round_up_tests")
    count_wrong = 0
    for test_case in test_cases:
        var precision = Int(test_case.b)
        var result = BDec(test_case.a).round(precision, RoundingMode.up())
        var mojo_str = String(result)
        var template = pydecimal.Decimal("1E" + String(-precision))
        var py_str = String(pydecimal.Decimal(test_case.a).quantize(template))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "ROUND_UP: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal ROUND_HALF_UP mode
    # -------------------------------------------------------

    pydecimal.getcontext().rounding = pydecimal.ROUND_HALF_UP
    test_cases = load_test_cases(toml, "round_half_up_tests")
    count_wrong = 0
    for test_case in test_cases:
        var precision = Int(test_case.b)
        var result = BDec(test_case.a).round(precision, RoundingMode.half_up())
        var mojo_str = String(result)
        var template = pydecimal.Decimal("1E" + String(-precision))
        var py_str = String(pydecimal.Decimal(test_case.a).quantize(template))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "ROUND_HALF_UP: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal ROUND_HALF_EVEN (banker's rounding) mode
    # -------------------------------------------------------

    pydecimal.getcontext().rounding = pydecimal.ROUND_HALF_EVEN
    test_cases = load_test_cases(toml, "round_half_even_tests")
    count_wrong = 0
    for test_case in test_cases:
        var precision = Int(test_case.b)
        var result = BDec(test_case.a).round(
            precision, RoundingMode.half_even()
        )
        var mojo_str = String(result)
        var template = pydecimal.Decimal("1E" + String(-precision))
        var py_str = String(pydecimal.Decimal(test_case.a).quantize(template))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "ROUND_HALF_EVEN: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal ROUND_HALF_DOWN mode
    # -------------------------------------------------------

    pydecimal.getcontext().rounding = pydecimal.ROUND_HALF_DOWN
    test_cases = load_test_cases(toml, "round_half_down_tests")
    count_wrong = 0
    for test_case in test_cases:
        var precision = Int(test_case.b)
        var result = BDec(test_case.a).round(
            precision, RoundingMode.half_down()
        )
        var mojo_str = String(result)
        var template = pydecimal.Decimal("1E" + String(-precision))
        var py_str = String(pydecimal.Decimal(test_case.a).quantize(template))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "ROUND_HALF_DOWN: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal rounding with extreme values (HALF_EVEN)
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "extreme_value_tests")
    count_wrong = 0
    for test_case in test_cases:
        var precision = Int(test_case.b)
        var result = BDec(test_case.a).round(
            precision, RoundingMode.half_even()
        )
        var mojo_str = String(result)
        var template = pydecimal.Decimal("1E" + String(-precision))
        var py_str = String(pydecimal.Decimal(test_case.a).quantize(template))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "Extreme values: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal rounding with special edge cases (HALF_EVEN)
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "edge_case_tests")
    count_wrong = 0
    for test_case in test_cases:
        var precision = Int(test_case.b)
        var result = BDec(test_case.a).round(
            precision, RoundingMode.half_even()
        )
        var mojo_str = String(result)
        var template = pydecimal.Decimal("1E" + String(-precision))
        var py_str = String(pydecimal.Decimal(test_case.a).quantize(template))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "Edge cases: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal rounding with negative precision (HALF_EVEN)
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "precision_tests")
    count_wrong = 0
    for test_case in test_cases:
        var precision = Int(test_case.b)
        var result = BDec(test_case.a).round(
            precision, RoundingMode.half_even()
        )
        var mojo_str = String(result)
        var template = pydecimal.Decimal("1E" + String(-precision))
        var py_str = String(pydecimal.Decimal(test_case.a).quantize(template))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "Precision tests: Mojo and Python results differ. See above.",
    )

    # -------------------------------------------------------
    # Testing BigDecimal rounding with scientific notation inputs
    # -------------------------------------------------------

    test_cases = load_test_cases(toml, "scientific_tests")
    count_wrong = 0
    for test_case in test_cases:
        var precision = Int(test_case.b)
        var result = BDec(test_case.a).round(
            precision, RoundingMode.half_even()
        )
        var mojo_str = String(result)
        var template = pydecimal.Decimal("1E" + String(-precision))
        var py_str = String(pydecimal.Decimal(test_case.a).quantize(template))
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1
    testing.assert_equal(
        count_wrong,
        0,
        "Scientific notation: Mojo and Python results differ. See above.",
    )


def test_default_rounding_mode() raises:
    """Test that the default rounding mode is ROUND_HALF_EVEN."""

    var value = BDec("2.5")
    var result = value.round(0)
    var expected = BDec("2")  # HALF_EVEN rounds 2.5 to 2 (nearest even)

    testing.assert_equal(
        String(result),
        String(expected),
        "Default rounding mode should be ROUND_HALF_EVEN",
    )

    value = BDec("3.5")
    result = round(value, 0)  # No rounding mode specified
    expected = BDec("4")  # HALF_EVEN rounds 3.5 to 4 (nearest even)

    testing.assert_equal(
        String(result),
        String(expected),
        "Default rounding mode should be ROUND_HALF_EVEN",
    )


def test_quantize_basic() raises:
    """Test basic quantize() functionality."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)

    pydecimal.getcontext().rounding = pydecimal.ROUND_HALF_EVEN
    var test_cases = load_test_cases(toml, "quantize_basic_tests")
    var count_wrong = 0

    for test_case in test_cases:
        var result = BDec(test_case.a).quantize(BDec(test_case.b))
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a).quantize(
                pydecimal.Decimal(test_case.b)
            )
        )
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong,
        0,
        "quantize_basic: Mojo and Python results differ. See above.",
    )


def test_quantize_financial() raises:
    """Test quantize() for financial calculations."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)

    pydecimal.getcontext().rounding = pydecimal.ROUND_HALF_EVEN
    var test_cases = load_test_cases(toml, "quantize_financial_tests")
    var count_wrong = 0

    for test_case in test_cases:
        var result = BDec(test_case.a).quantize(BDec(test_case.b))
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a).quantize(
                pydecimal.Decimal(test_case.b)
            )
        )
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong,
        0,
        "quantize_financial: Mojo and Python results differ. See above.",
    )


def test_quantize_scientific() raises:
    """Test quantize() for scientific measurements."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)

    pydecimal.getcontext().rounding = pydecimal.ROUND_HALF_EVEN
    var test_cases = load_test_cases(toml, "quantize_scientific_tests")
    var count_wrong = 0

    for test_case in test_cases:
        var result = BDec(test_case.a).quantize(BDec(test_case.b))
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a).quantize(
                pydecimal.Decimal(test_case.b)
            )
        )
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong,
        0,
        "quantize_scientific: Mojo and Python results differ. See above.",
    )


def test_quantize_negative_scale() raises:
    """Test quantize() with negative scale (scientific notation)."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)

    pydecimal.getcontext().rounding = pydecimal.ROUND_HALF_EVEN
    var test_cases = load_test_cases(toml, "quantize_negative_scale_tests")
    var count_wrong = 0

    for test_case in test_cases:
        var result = BDec(test_case.a).quantize(BDec(test_case.b))
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a).quantize(
                pydecimal.Decimal(test_case.b)
            )
        )
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong,
        0,
        "quantize_negative_scale: Mojo and Python results differ. See above.",
    )


def test_quantize_add_zeros() raises:
    """Test quantize() adding trailing zeros."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)

    pydecimal.getcontext().rounding = pydecimal.ROUND_HALF_EVEN
    var test_cases = load_test_cases(toml, "quantize_add_zeros_tests")
    var count_wrong = 0

    for test_case in test_cases:
        var result = BDec(test_case.a).quantize(BDec(test_case.b))
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a).quantize(
                pydecimal.Decimal(test_case.b)
            )
        )
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong,
        0,
        "quantize_add_zeros: Mojo and Python results differ. See above.",
    )


def test_quantize_same_scale() raises:
    """Test quantize() when scales are already the same."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)

    pydecimal.getcontext().rounding = pydecimal.ROUND_HALF_EVEN
    var test_cases = load_test_cases(toml, "quantize_same_scale_tests")
    var count_wrong = 0

    for test_case in test_cases:
        var result = BDec(test_case.a).quantize(BDec(test_case.b))
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a).quantize(
                pydecimal.Decimal(test_case.b)
            )
        )
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong,
        0,
        "quantize_same_scale: Mojo and Python results differ. See above.",
    )


def test_quantize_normalization() raises:
    """Test quantize() with normalized templates ('3.1E+2' vs '31E1')."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)

    pydecimal.getcontext().rounding = pydecimal.ROUND_HALF_EVEN
    var test_cases = load_test_cases(toml, "quantize_normalization_tests")
    var count_wrong = 0

    for test_case in test_cases:
        var result = BDec(test_case.a).quantize(BDec(test_case.b))
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a).quantize(
                pydecimal.Decimal(test_case.b)
            )
        )
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong,
        0,
        "quantize_normalization: Mojo and Python results differ. See above.",
    )


def test_quantize_edge_cases() raises:
    """Test quantize() edge cases with banker's rounding."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)

    pydecimal.getcontext().rounding = pydecimal.ROUND_HALF_EVEN
    var test_cases = load_test_cases(toml, "quantize_edge_cases_tests")
    var count_wrong = 0

    for test_case in test_cases:
        var result = BDec(test_case.a).quantize(BDec(test_case.b))
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a).quantize(
                pydecimal.Decimal(test_case.b)
            )
        )
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong,
        0,
        "quantize_edge_cases: Mojo and Python results differ. See above.",
    )


def test_quantize_rounding_modes() raises:
    """Test quantize() with different rounding modes."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(file_path)

    var test_cases = load_test_cases(toml, "quantize_rounding_mode_tests")
    var count_wrong = 0

    # Set up rounding modes based on test order
    var rounding_modes = List[RoundingMode]()
    rounding_modes.append(RoundingMode.half_even())
    rounding_modes.append(RoundingMode.half_up())
    rounding_modes.append(RoundingMode.down())
    rounding_modes.append(RoundingMode.up())

    var py_rounding_modes = [
        pydecimal.ROUND_HALF_EVEN,
        pydecimal.ROUND_HALF_UP,
        pydecimal.ROUND_DOWN,
        pydecimal.ROUND_UP,
    ]

    for i in range(len(test_cases)):
        ref test_case = test_cases[i]
        var rounding_mode = rounding_modes[i % 4]
        pydecimal.getcontext().rounding = py_rounding_modes[i % 4]

        var result = BDec(test_case.a).quantize(
            BDec(test_case.b), rounding_mode
        )
        var mojo_str = String(result)
        var py_str = String(
            pydecimal.Decimal(test_case.a).quantize(
                pydecimal.Decimal(test_case.b)
            )
        )
        if mojo_str != py_str:
            print(
                test_case.description,
                "\n  Mojo:   ",
                mojo_str,
                "\n  Python: ",
                py_str,
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong,
        0,
        "quantize_rounding_modes: Mojo and Python results differ. See above.",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
