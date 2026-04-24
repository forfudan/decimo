"""
Tests for Decimal128 rounding: round() with various rounding modes and
quantize() against Python's decimal module.

Consolidates test_decimal128_round.mojo and test_decimal128_quantize.mojo.
The round-TOML data file is parsed exactly once per run (was 5 separate
parses across small test functions before consolidation).
quantize tests have no TOML; they cross-check against Python's decimal.
"""

from std import testing
from std.python import Python, PythonObject
from decimo.toml.parser import TOMLDocument

from decimo.decimal128.decimal128 import Decimal128, Dec128
from decimo.rounding_mode import RoundingMode
from decimo.tests import parse_file, load_test_cases


comptime round_path = "tests/decimal128/test_data/decimal128_round.toml"


# ─────────────────────────────────────────────────────────────────────────────
# round() — TOML-driven, single parse
# ─────────────────────────────────────────────────────────────────────────────


def test_decimal128_round() raises:
    """Run all round TOML sections in a single parse: default (banker's),
    down, up, half_up, half_even."""
    var doc = parse_file(round_path)
    var count_wrong = 0

    # Default uses builtin round() (banker's rounding)
    var default_cases = load_test_cases(doc, "round_default")
    for tc in default_cases:
        var result = round(Dec128(tc.a), Int(tc.b))
        try:
            testing.assert_equal(String(result), tc.expected, tc.description)
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

    var modes = [
        ("round_down", RoundingMode.down()),
        ("round_up", RoundingMode.up()),
        ("round_half_up", RoundingMode.half_up()),
        ("round_half_even", RoundingMode.half_even()),
    ]
    for entry in modes:
        var cases = load_test_cases(doc, String(entry[0]))
        for tc in cases:
            var result = Dec128(tc.a).round(Int(tc.b), entry[1])
            try:
                testing.assert_equal(
                    String(result), tc.expected, tc.description
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

    testing.assert_equal(count_wrong, 0, "Some round cases failed.")


def test_round_small_value() raises:
    """Round a dynamically-constructed very small number."""
    var small_value = Decimal128("0." + "0" * 27 + "1")
    testing.assert_equal(
        String(round(small_value, 27)),
        "0." + "0" * 27,
        "Rounding tiny number to 27 places",
    )


def test_rounding_consistency() raises:
    """Consistency across constructors and sequential rounding."""
    var d1 = Decimal128("123.45")
    var d2 = Decimal128(123.45)
    testing.assert_equal(
        String(round(d1, 1))[byte=:3],
        String(round(d2, 1))[byte=:3],
        "Rounding consistency across different constructors",
    )

    var start = Decimal128("123.456789")
    var round_twice = round(round(start, 4), 2)
    var direct = round(start, 2)
    testing.assert_equal(
        String(round_twice),
        String(direct),
        "Consistency with sequential rounding",
    )


# ─────────────────────────────────────────────────────────────────────────────
# quantize() — cross-checked against Python's decimal
# ─────────────────────────────────────────────────────────────────────────────


def test_quantize_basic() raises:
    """Test basic quantization with different scales."""
    var pydecimal = Python.import_module("decimal")
    pydecimal.getcontext().prec = 28

    var pairs = [
        ("3.14159", "0.01"),
        ("42.7", "1"),
        ("5.5", "0.001"),
        ("123.456789", "0.01"),
        ("9.876", "1.00"),
    ]
    for p in pairs:
        var v = Decimal128(String(p[0]))
        var q = Decimal128(String(p[1]))
        var pyv = pydecimal.Decimal(String(p[0]))
        var pyq = pydecimal.Decimal(String(p[1]))
        testing.assert_equal(
            String(v.quantize(q)),
            String(pyv.quantize(pyq)),
            "Quantizing " + String(p[0]) + " to " + String(p[1]),
        )


def test_quantize_rounding_modes() raises:
    """Test quantization with different rounding modes."""
    var pydecimal = Python.import_module("decimal")
    pydecimal.getcontext().prec = 28

    var test_value = Decimal128("3.5")
    var quantizer = Decimal128("1")
    var py_value = pydecimal.Decimal("3.5")
    var py_quantizer = pydecimal.Decimal("1")

    testing.assert_equal(
        String(test_value.quantize(quantizer, RoundingMode.half_even())),
        String(
            py_value.quantize(py_quantizer, rounding=pydecimal.ROUND_HALF_EVEN)
        ),
        "ROUND_HALF_EVEN",
    )
    testing.assert_equal(
        String(test_value.quantize(quantizer, RoundingMode.half_up())),
        String(
            py_value.quantize(py_quantizer, rounding=pydecimal.ROUND_HALF_UP)
        ),
        "ROUND_HALF_UP",
    )
    testing.assert_equal(
        String(test_value.quantize(quantizer, RoundingMode.down())),
        String(py_value.quantize(py_quantizer, rounding=pydecimal.ROUND_DOWN)),
        "ROUND_DOWN",
    )
    testing.assert_equal(
        String(test_value.quantize(quantizer, RoundingMode.up())),
        String(py_value.quantize(py_quantizer, rounding=pydecimal.ROUND_UP)),
        "ROUND_UP",
    )

    var neg = Decimal128("-3.5")
    var py_neg = pydecimal.Decimal("-3.5")
    testing.assert_equal(
        String(neg.quantize(quantizer, RoundingMode.down())),
        String(py_neg.quantize(py_quantizer, rounding=pydecimal.ROUND_DOWN)),
        "ROUND_DOWN with negative",
    )
    testing.assert_equal(
        String(neg.quantize(quantizer, RoundingMode.up())),
        String(py_neg.quantize(py_quantizer, rounding=pydecimal.ROUND_UP)),
        "ROUND_UP with negative",
    )


def test_quantize_edge_cases() raises:
    """Edge cases for quantization."""
    var pydecimal = Python.import_module("decimal")
    pydecimal.getcontext().prec = 28

    var pairs = [
        ("0", "0.001"),
        ("123.45", "0.01"),
        ("9.9999", "1"),
        ("0.0000001", "0.001"),
    ]
    for p in pairs:
        var v = Decimal128(String(p[0]))
        var q = Decimal128(String(p[1]))
        var pyv = pydecimal.Decimal(String(p[0]))
        var pyq = pydecimal.Decimal(String(p[1]))
        testing.assert_equal(
            String(v.quantize(q)),
            String(pyv.quantize(pyq)),
            "Quantize edge: " + String(p[0]) + " -> " + String(p[1]),
        )

    # -1.5 with HALF_EVEN
    var v5 = Decimal128("-1.5")
    var q5 = Decimal128("1")
    testing.assert_equal(
        String(v5.quantize(q5, RoundingMode.half_even())),
        String(
            pydecimal.Decimal("-1.5").quantize(
                pydecimal.Decimal("1"), rounding=pydecimal.ROUND_HALF_EVEN
            )
        ),
        "Quantizing -1.5 with HALF_EVEN",
    )


def test_quantize_special_cases() raises:
    """Special quantization cases."""
    var pydecimal = Python.import_module("decimal")
    pydecimal.getcontext().prec = 28

    var pairs = [
        ("12.34", "0.0000"),
        ("123.456", "10"),
        ("3.1415926535", "0.00000001"),
        ("123.456", "1"),
    ]
    for p in pairs:
        var v = Decimal128(String(p[0]))
        var q = Decimal128(String(p[1]))
        var pyv = pydecimal.Decimal(String(p[0]))
        var pyq = pydecimal.Decimal(String(p[1]))
        testing.assert_equal(
            String(v.quantize(q)),
            String(pyv.quantize(pyq)),
            "Special quantize: " + String(p[0]) + " -> " + String(p[1]),
        )

    # 2.5 banker's rounding
    var v2 = Decimal128("2.5")
    var q2 = Decimal128("1")
    testing.assert_equal(
        String(v2.quantize(q2, RoundingMode.half_even())),
        String(
            pydecimal.Decimal("2.5").quantize(
                pydecimal.Decimal("1"), rounding=pydecimal.ROUND_HALF_EVEN
            )
        ),
        "Banker's rounding for 2.5",
    )


def test_quantize_exceptions() raises:
    """Quantize exception parity with Python's decimal."""
    var pydecimal = Python.import_module("decimal")
    pydecimal.getcontext().prec = 28

    var caught = False
    try:
        var _r = Decimal128("123.456").quantize(Decimal128("1000"))
    except:
        caught = True

    var py_caught = False
    try:
        var _r = pydecimal.Decimal("123.456").quantize(
            pydecimal.Decimal("1000")
        )
    except:
        py_caught = True

    testing.assert_equal(
        caught, py_caught, "Exception parity for invalid quantization"
    )


def _check_quantize_case(
    value_str: String,
    quant_str: String,
    mojo_mode: RoundingMode,
    py_mode: PythonObject,
    pydecimal: PythonObject,
) raises:
    """Cross-check a single quantize case.

    Computes the Mojo and Python results independently and only catches
    errors raised by the operations themselves (not assertion failures).
    Behaviour matrix:
      * both succeed -> string results must match
      * both raise   -> acceptable parity (Python and Mojo agree it's invalid)
      * only one raises -> test fails
    """
    var mr_str: String
    var mojo_raised = False
    try:
        mr_str = String(
            Decimal128(value_str).quantize(Decimal128(quant_str), mojo_mode)
        )
    except:
        mr_str = String("")
        mojo_raised = True

    var pr_str: String
    var py_raised = False
    try:
        pr_str = String(
            pydecimal.Decimal(value_str).quantize(
                pydecimal.Decimal(quant_str), rounding=py_mode
            )
        )
    except:
        pr_str = String("")
        py_raised = True

    # Assertions live outside the try blocks so failures propagate.
    testing.assert_equal(
        mojo_raised,
        py_raised,
        String("Quantize exception parity for {} to {}").format(
            value_str, quant_str
        ),
    )
    if not mojo_raised:
        testing.assert_equal(
            mr_str,
            pr_str,
            String("Quantize {} to {}").format(value_str, quant_str),
        )


def test_quantize_comprehensive() raises:
    """Wide-range comparison against Python's decimal across rounding modes."""
    var pydecimal = Python.import_module("decimal")
    pydecimal.getcontext().prec = 28

    var mhe = RoundingMode.half_even()
    var mhu = RoundingMode.half_up()
    var md = RoundingMode.down()
    var mu = RoundingMode.up()
    var phe = pydecimal.ROUND_HALF_EVEN
    var phu = pydecimal.ROUND_HALF_UP
    var pd = pydecimal.ROUND_DOWN
    var pu = pydecimal.ROUND_UP

    var triples = [
        ("0", "1"),
        ("1.23456", "0.01"),
        ("9.999", "0.1"),
        ("-0.5", "1"),
        ("0.0001", "0.01"),
        ("1234.5678", "1"),
        ("99.99", "100"),
        ("0.0000001", "0.00001"),
        ("987654.321", "0.1"),
        ("10000", "1000"),
        ("0.999999", "1"),
        ("-999.9", "1"),
    ]
    for t in triples:
        _check_quantize_case(String(t[0]), String(t[1]), mhe, phe, pydecimal)
        _check_quantize_case(String(t[0]), String(t[1]), mhu, phu, pydecimal)
        _check_quantize_case(String(t[0]), String(t[1]), md, pd, pydecimal)
        _check_quantize_case(String(t[0]), String(t[1]), mu, pu, pydecimal)

    # Singletons
    _check_quantize_case(
        "3.14159265358979323", "0.00000000001", mhe, phe, pydecimal
    )
    _check_quantize_case("0.0", "0.0000", mhe, phe, pydecimal)
    _check_quantize_case("123", "1", mhe, phe, pydecimal)
    _check_quantize_case("1.5", "1", mhe, phe, pydecimal)
    _check_quantize_case("2.5", "1", mhe, phe, pydecimal)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
