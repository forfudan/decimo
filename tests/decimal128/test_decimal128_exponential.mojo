"""
Tests for Decimal128 exponential, logarithmic, and factorial functions:
exp, ln, log(base), log10, factorial, factorial_reciprocal.

Consolidates test_decimal128_{exp_ln, logarithm, factorial}.mojo. The
logarithm and factorial TOML data files are each parsed exactly once
per test. exp/ln tests have no TOML (they rely on startswith checks).
"""

from std import testing
from decimo.toml.parser import TOMLDocument

from decimo.decimal128.decimal128 import Decimal128, Dec128
from decimo.rounding_mode import RoundingMode
from decimo.decimal128.exponential import exp, ln
from decimo.decimal128.special import factorial, factorial_reciprocal
from decimo.tests import parse_file, load_test_cases


comptime log_path = "tests/decimal128/test_data/decimal128_logarithm.toml"
comptime factorial_path = "tests/decimal128/test_data/decimal128_factorial.toml"


# ─────────────────────────────────────────────────────────────────────────────
# exp() — inline (no TOML)
# ─────────────────────────────────────────────────────────────────────────────


def test_exp_values() raises:
    """Tests e^x for basic, negative, fractional, and high-precision inputs."""
    testing.assert_equal(String(exp(Decimal128("0"))), "1", "e^0 should be 1")
    testing.assert_true(
        String(exp(Decimal128("1"))).startswith("2.71828182845904523536028"),
    )
    testing.assert_true(
        String(exp(Decimal128("2"))).startswith("7.38905609893065022723042"),
    )
    testing.assert_true(
        String(exp(Decimal128("3"))).startswith("20.0855369231876677409285"),
    )
    testing.assert_true(
        String(exp(Decimal128("5"))).startswith("148.413159102576603421115"),
    )
    testing.assert_true(
        String(exp(Decimal128("-1"))).startswith("0.36787944117144232159552"),
    )
    testing.assert_true(
        String(exp(Decimal128("-2"))).startswith("0.13533528323661269189399"),
    )
    testing.assert_true(
        String(exp(Decimal128("-5"))).startswith("0.00673794699908546709663"),
    )
    testing.assert_true(
        String(exp(Decimal128("0.5"))).startswith("1.64872127070012814684865"),
    )
    testing.assert_true(
        String(exp(Decimal128("0.1"))).startswith("1.10517091807564762481170"),
    )
    testing.assert_true(
        String(exp(Decimal128("-0.5"))).startswith("0.60653065971263342360379"),
    )
    testing.assert_true(
        String(exp(Decimal128("1.5"))).startswith("4.48168907033806482260205"),
    )
    testing.assert_true(
        String(
            exp(Decimal128("3.14159265358979323846264338327950288"))
        ).startswith("23.1406926327792690057290"),
    )
    testing.assert_true(
        String(exp(Decimal128("2.71828"))).startswith(
            "15.1542345325567272110572"
        ),
    )


def test_exp_identities() raises:
    """Tests that e^(a+b) = e^a * e^b and e^(-x) = 1/e^x."""
    var a = Decimal128("2")
    var b = Decimal128("3")
    var diff1 = abs(exp(a + b) - exp(a) * exp(b)) / exp(a + b)
    testing.assert_true(diff1 < Decimal128("0.0000001"))

    var x = Decimal128("1.5")
    var diff2 = abs(exp(-x) - Decimal128("1") / exp(x)) / exp(-x)
    testing.assert_true(diff2 < Decimal128("0.0000001"))

    testing.assert_equal(String(exp(Decimal128("0"))), "1")


def test_exp_extreme() raises:
    testing.assert_true(
        String(exp(Decimal128("0.0000001"))).startswith("1.0000001")
    )
    testing.assert_true(
        String(exp(Decimal128("-0.0000001"))).startswith("0.9999999")
    )
    testing.assert_true(exp(Decimal128("20")) > Decimal128("100000000"))
    var result = exp(Decimal128("1.23456789012345678901234567"))
    testing.assert_true(String(result).byte_length() > 15)


# ─────────────────────────────────────────────────────────────────────────────
# ln() — inline (no TOML)
# ─────────────────────────────────────────────────────────────────────────────


def test_ln_values() raises:
    """Tests ln(x) for basic, fractional, and high-precision inputs."""
    testing.assert_equal(String(ln(Decimal128(1))), "0", "ln(1) should be 0")
    testing.assert_true(
        String(Decimal128("2.718281828459045235360287471").ln()).startswith(
            "1.00000000000000000000"
        ),
    )
    testing.assert_true(
        String(ln(Decimal128(10))).startswith("2.30258509299404568401799145"),
    )
    testing.assert_true(
        String(ln(Decimal128("0.1"))).startswith(
            "-2.302585092994045684017991454"
        ),
    )
    testing.assert_true(
        String(ln(Decimal128("0.5"))).startswith(
            "-0.693147180559945309417232121"
        ),
    )
    testing.assert_true(
        String(ln(Decimal128(2))).startswith("0.693147180559945309417232121"),
    )
    testing.assert_true(
        String(ln(Decimal128(5))).startswith("1.609437912434100374600759333"),
    )


def test_ln_identities() raises:
    """Tests that ln(a*b)=ln(a)+ln(b), ln(a/b)=ln(a)-ln(b), ln(e^x)=x."""
    var a = Decimal128(2)
    var b = Decimal128(3)
    testing.assert_true(
        abs(ln(a * b) - (ln(a) + ln(b))) < Decimal128("0.0000000001")
    )
    testing.assert_true(
        abs(ln(a / b) - (ln(a) - ln(b))) < Decimal128("0.0000000001")
    )
    var x = Decimal128(5)
    testing.assert_true(abs(ln(x.exp()) - x) < Decimal128("0.0000000001"))


def test_ln_edge_cases() raises:
    var caught = False
    try:
        var _r = ln(Decimal128(0))
    except:
        caught = True
    testing.assert_true(caught, "ln(0) should raise")

    caught = False
    try:
        var _r = ln(Decimal128(-1))
    except:
        caught = True
    testing.assert_true(caught, "ln(-1) should raise")

    testing.assert_true(
        String(ln(Decimal128("0.000000000000000000000000001"))).startswith(
            "-62.16979751083923346848576927"
        )
    )
    testing.assert_true(
        String(ln(Decimal128("10000000000000000000000000000"))).startswith(
            "64.4723"
        )
    )


def test_ln_properties() raises:
    testing.assert_true(Decimal128(3).ln() > Decimal128(0))
    testing.assert_true(Decimal128(10).ln() > Decimal128(2))
    testing.assert_true(Decimal128("0.1").ln() < Decimal128(0))
    testing.assert_true(Decimal128("0.9").ln() < Decimal128(0))

    testing.assert_equal(String(ln(Decimal128(1))), "0")

    var e = Decimal128("2.718281828459045235360287471")
    testing.assert_true(abs(ln(e) - Decimal128(1)) < Decimal128("0.0000000001"))


# ─────────────────────────────────────────────────────────────────────────────
# log(base) and log10() — TOML-driven (single parse) + inline
# ─────────────────────────────────────────────────────────────────────────────


def test_decimal128_logarithm() raises:
    """Run all logarithm TOML sections (log_exact, log10_exact) in one parse."""
    var doc = parse_file(log_path)
    var count_wrong = 0

    var log_cases = load_test_cases(doc, "log_exact")
    for tc in log_cases:
        var result = Dec128(tc.a).log(Dec128(tc.b))
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

    var log10_cases = load_test_cases[unary=True](doc, "log10_exact")
    for tc in log10_cases:
        var result = Dec128(tc.a).log10()
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

    testing.assert_equal(count_wrong, 0, "Some logarithm TOML cases failed.")


def test_log_rounded() raises:
    """Log results that are exact after rounding."""
    testing.assert_equal(String(Decimal128(27).log(Decimal128(3)).round()), "3")
    testing.assert_equal(
        String(Decimal128(125).log(Decimal128(5)).round()), "3"
    )
    testing.assert_equal(
        String(Decimal128("0.001").log(Decimal128("0.1")).round()), "3"
    )
    testing.assert_equal(
        String(Decimal128(1024).log(Decimal128(2)).round()), "10"
    )
    testing.assert_equal(String(Decimal128.E().log(Decimal128.E())), "1")
    testing.assert_equal(
        String(Decimal128("3.14159").log(Decimal128("3.14159"))), "1"
    )


def test_log_non_integer() raises:
    testing.assert_true(
        String(Decimal128(10).log(Decimal128(2))).startswith(
            "3.321928094887362347"
        )
    )
    testing.assert_true(
        String(Decimal128(10).log(Decimal128(3))).startswith(
            "2.0959032742893846"
        )
    )
    testing.assert_true(
        String(Decimal128(2).log(Decimal128(10))).startswith(
            "0.301029995663981195"
        )
    )
    testing.assert_true(
        String(Decimal128(10).log(Decimal128.E())).startswith(
            "2.302585092994045684"
        )
    )
    testing.assert_true(
        String(Decimal128(19).log(Decimal128(7))).startswith("1.5131423106")
    )
    testing.assert_true(
        String(Decimal128("0.125").log(Decimal128(3))).startswith("-1.89278926")
    )
    testing.assert_true(
        String(Decimal128("1.5").log(Decimal128("2.5"))).startswith(
            "0.4425070493497599"
        )
    )


def test_log_exceptions() raises:
    var caught = False
    try:
        var _r = Decimal128(-10).log(Decimal128(10))
    except:
        caught = True
    testing.assert_true(caught, "log(negative) exception")

    caught = False
    try:
        var _r = Decimal128(0).log(Decimal128(10))
    except:
        caught = True
    testing.assert_true(caught, "log(0) exception")

    caught = False
    try:
        var _r = Decimal128(10).log(Decimal128(1))
    except:
        caught = True
    testing.assert_true(caught, "log base 1 exception")

    caught = False
    try:
        var _r = Decimal128(10).log(Decimal128(0))
    except:
        caught = True
    testing.assert_true(caught, "log base 0 exception")

    caught = False
    try:
        var _r = Decimal128(10).log(Decimal128(-2))
    except:
        caught = True
    testing.assert_true(caught, "log negative base exception")


def test_log_properties() raises:
    var tol = Decimal128("0.000000000001")
    var x = Decimal128(3)
    var y = Decimal128(4)
    var a = Decimal128(5)
    testing.assert_true(abs((x * y).log(a) - (x.log(a) + y.log(a))) < tol)

    testing.assert_true(
        abs(
            Decimal128(20).log(Decimal128(2))
            - Decimal128(5).log(Decimal128(2))
            - (Decimal128(20) / Decimal128(5)).log(Decimal128(2))
        )
        < tol
    )

    testing.assert_true(
        abs(
            (Decimal128(3) ** 4).log(Decimal128(7))
            - Decimal128(4) * Decimal128(3).log(Decimal128(7))
        )
        < tol
    )

    testing.assert_true(
        abs(
            (Decimal128(1) / Decimal128(7)).log(Decimal128(3))
            + Decimal128(7).log(Decimal128(3))
        )
        < tol
    )

    var direct = Decimal128(7).log(Decimal128(3))
    var changed = Decimal128(7).log(Decimal128(10)) / Decimal128(3).log(
        Decimal128(10)
    )
    testing.assert_true(abs(direct - changed) < tol)

    testing.assert_true(
        abs(Decimal128(7).log(Decimal128(10)) - Decimal128(7).log10()) < tol
    )

    testing.assert_true(
        abs(Decimal128(5).log(Decimal128.E()) - Decimal128(5).ln()) < tol
    )


def test_log10_non_powers() raises:
    testing.assert_true(
        String(Decimal128(2).log10()).startswith("0.301029995663981")
    )
    testing.assert_true(
        String(Decimal128(5).log10()).startswith("0.698970004336018")
    )
    testing.assert_true(
        String(Decimal128(3).log10()).startswith("0.477121254719662")
    )
    testing.assert_true(
        String(Decimal128(7).log10()).startswith("0.845098040014256")
    )
    testing.assert_true(
        String(Decimal128("0.5").log10()).startswith("-0.301029995663981")
    )


def test_log10_exceptions() raises:
    var caught = False
    try:
        var _r = Decimal128(-10).log10()
    except:
        caught = True
    testing.assert_true(caught, "log10(negative) exception")

    caught = False
    try:
        var _r = Decimal128(0).log10()
    except:
        caught = True
    testing.assert_true(caught, "log10(0) exception")


def test_log10_precision() raises:
    testing.assert_true(
        String(Decimal128("3.14159265358979323846").log10()).startswith(
            "0.497149872694133"
        )
    )
    testing.assert_true(
        String(Decimal128.E().log10()).startswith("0.434294481903251")
    )
    testing.assert_true(
        abs(Decimal128(2).log10() - Decimal128("0.301029995663981"))
        < Decimal128("0.000000000000001")
    )
    testing.assert_true(
        abs(Decimal128("1.0000000001").log10()) < Decimal128("0.0000001")
    )
    testing.assert_true(
        String(Decimal128("9.999999999").log10()).startswith("0.999999999")
    )


def test_log10_properties() raises:
    var tol = Decimal128("0.000000000001")
    testing.assert_true(
        abs(
            (Decimal128(2) * Decimal128(5)).log10()
            - (Decimal128(2).log10() + Decimal128(5).log10())
        )
        < tol
    )
    testing.assert_true(
        abs(
            (Decimal128(8) / Decimal128(2)).log10()
            - (Decimal128(8).log10() - Decimal128(2).log10())
        )
        < tol
    )
    testing.assert_true(
        abs(
            (Decimal128(3) ** 4).log10() - Decimal128(4) * Decimal128(3).log10()
        )
        < tol
    )
    testing.assert_true(
        abs((Decimal128(1) / Decimal128(7)).log10() + Decimal128(7).log10())
        < tol
    )
    testing.assert_true(
        abs(Decimal128(7).log10() - Decimal128(7).ln() / Decimal128(10).ln())
        < tol
    )
    testing.assert_true(
        abs(Decimal128(5).log10() - Decimal128(5).log(Decimal128(10))) < tol
    )


# ─────────────────────────────────────────────────────────────────────────────
# factorial() and factorial_reciprocal() — TOML-driven (single parse) + inline
# ─────────────────────────────────────────────────────────────────────────────


def test_decimal128_factorial() raises:
    """Run all factorial TOML sections in a single parse."""
    var doc = parse_file(factorial_path)
    var count_wrong = 0
    var cases = load_test_cases[unary=True](doc, "factorial")
    for tc in cases:
        var result = factorial(atol(tc.a))
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
    testing.assert_equal(count_wrong, 0, "Some factorial cases failed.")


def test_factorial_properties() raises:
    """Mathematical property: (n+1)! = (n+1) * n! for n = 0..26."""
    for n in range(0, 26):
        var n_fact = factorial(n)
        var n_plus_1_fact = factorial(n + 1)
        var calculated = n_fact * Decimal128(String(n + 1))
        testing.assert_equal(
            String(n_plus_1_fact),
            String(calculated),
            "(n+1)! = (n+1)*n! failed for n=" + String(n),
        )


def test_factorial_exceptions() raises:
    var caught = False
    try:
        var _f = factorial(-1)
    except:
        caught = True
    testing.assert_true(caught, "factorial(-1) exception")

    caught = False
    try:
        var _f = factorial(28)
    except:
        caught = True
    testing.assert_true(caught, "factorial(28) exception")


def test_factorial_reciprocal() raises:
    """Tests that factorial_reciprocal(n) should equal 1/factorial(n) for n in 0..27.
    """
    var all_equal = True
    for i in range(28):
        var a = Decimal128(1) / factorial(i)
        var b = factorial_reciprocal(i)
        if a != b:
            all_equal = False
            print(
                "Mismatch at "
                + String(i)
                + ": 1/"
                + String(i)
                + "! = "
                + String(a)
                + ", reciprocal = "
                + String(b)
            )
    testing.assert_true(all_equal)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
