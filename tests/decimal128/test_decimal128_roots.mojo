"""
Tests for Decimal128 root operations: sqrt, root, power.

Consolidates test_decimal128_{sqrt, root_power}.mojo. The sqrt and
root_power TOML data files are each parsed exactly once per test (was 3
+ 3 separate parses across small test functions before consolidation).
"""

import decimo
from std import testing
from decimo.toml.parser import TOMLDocument

from decimo.decimal128.decimal128 import Decimal128, Dec128
from decimo.rounding_mode import RoundingMode
from decimo.decimal128.exponential import root, power
from decimo.tests import parse_file, load_test_cases


comptime sqrt_path = "tests/decimal128/test_data/decimal128_sqrt.toml"
comptime root_power_path = (
    "tests/decimal128/test_data/decimal128_root_power.toml"
)


# ─────────────────────────────────────────────────────────────────────────────
# sqrt() — TOML-driven, single parse + inline
# ─────────────────────────────────────────────────────────────────────────────


def test_decimal128_sqrt() raises:
    """Run sqrt_perfect, sqrt_decimal, and sqrt_edge in one parse."""
    var doc = parse_file(sqrt_path)
    var count_wrong = 0
    var sections = [
        String("sqrt_perfect"),
        String("sqrt_decimal"),
        String("sqrt_edge"),
    ]
    for section in sections:
        var cases = load_test_cases[unary=True](doc, section)
        for tc in cases:
            var result = Dec128(tc.a).sqrt()
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
    testing.assert_equal(count_wrong, 0, "Some sqrt cases failed.")


def test_sqrt_non_perfect() raises:
    """Non-perfect squares (startswith checks)."""

    def _check(input: String, prefix: String, desc: String) raises:
        testing.assert_true(
            String(Dec128(input).sqrt()).startswith(prefix), desc
        )

    _check("2", "1.414213562373095048801688724", "sqrt(2)")
    _check("3", "1.73205080756887729352744634", "sqrt(3)")
    _check("5", "2.23606797749978969640917366", "sqrt(5)")
    _check("10", "3.162277660168379331998893544", "sqrt(10)")
    _check("50", "7.071067811865475244008443621", "sqrt(50)")
    _check("99", "9.949874371066199547344798210", "sqrt(99)")
    _check("999", "31.6069612585582165452042139", "sqrt(999)")


def test_sqrt_edge_special() raises:
    var very_small = Decimal128(1, 28)
    testing.assert_equal(String(very_small.sqrt()), "0.00000000000001")

    var very_large = Decimal128.from_uint128(
        decimo.decimal128.utility.power_of_10[DType.uint128](27)
    )
    testing.assert_true(
        String(very_large.sqrt()).startswith("31622776601683.79331998893544")
    )

    var caught = False
    try:
        var _r = Decimal128(-1).sqrt()
    except:
        caught = True
    testing.assert_true(caught, "sqrt(-1) exception")


def test_sqrt_precision() raises:
    def _check(input: String, prefix: String, desc: String) raises:
        testing.assert_true(
            String(Dec128(input).sqrt()).startswith(prefix), desc
        )

    _check("2", "1.414213562373095048801688724", "sqrt(2) precision")

    var precise_two = Decimal128.from_uint128(
        UInt128(20000000000000000000000000), 25
    )
    testing.assert_true(
        String(precise_two.sqrt()).startswith("1.414213562373095048801688724")
    )

    _check(
        "1894128.128951235",
        "1376.27327553478091940498131",
        "sqrt(1894128.128951235)",
    )


def test_sqrt_identities() raises:
    def _check_squared(s: String) raises:
        var x = Dec128(s)
        testing.assert_true(
            round(x.sqrt() * x.sqrt(), 10) == round(x, 10),
            "sqrt(" + s + ")² ≈ " + s,
        )

    _check_squared("2")
    _check_squared("3")
    _check_squared("5")
    _check_squared("7")
    _check_squared("10")
    _check_squared("0.5")
    _check_squared("0.25")
    _check_squared("1.44")

    def _check_product(xs: String, ys: String) raises:
        var x = Dec128(xs)
        var y = Dec128(ys)
        testing.assert_true(
            round((x * y).sqrt(), 10) == round(x.sqrt() * y.sqrt(), 10),
            "sqrt(" + xs + "*" + ys + ") = sqrt(" + xs + ")*sqrt(" + ys + ")",
        )

    _check_product("4", "9")
    _check_product("16", "25")
    _check_product("2", "8")


def test_sqrt_convergence() raises:
    var tol = Dec128("0.00001")

    def _check_rel(s: String, tol: Dec128) raises:
        var x = Dec128(s)
        var sq = x.sqrt()
        var diff = sq * sq - x
        diff = -diff if diff.is_negative() else diff
        var rel = diff / x
        testing.assert_true(rel < tol, "sqrt(" + s + ")² convergence")

    _check_rel("0.0001", tol)
    _check_rel("0.01", tol)
    _check_rel("1", tol)
    _check_rel("10", tol)
    _check_rel("10000", tol)
    _check_rel("10000000000", tol)
    _check_rel("3.999999999", tol)
    _check_rel("4.000000001", tol)

    testing.assert_true(
        String(Dec128("0.999999999").sqrt()).startswith(
            "0.99999999949999999987"
        )
    )
    testing.assert_true(
        String(Dec128("1.000000001").sqrt()).startswith(
            "1.000000000499999999875"
        )
    )


# ─────────────────────────────────────────────────────────────────────────────
# root() and power() — TOML-driven (single parse) + inline
# ─────────────────────────────────────────────────────────────────────────────


def test_decimal128_root_power() raises:
    """Run root_exact, power_int, and power_decimal sections in one parse."""
    var doc = parse_file(root_power_path)
    var count_wrong = 0

    var root_cases = load_test_cases(doc, "root_exact")
    for tc in root_cases:
        var result = root(Dec128(tc.a), atol(tc.b))
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

    var pi_cases = load_test_cases(doc, "power_int")
    for tc in pi_cases:
        var result = power(Dec128(tc.a), atol(tc.b))
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

    var pd_cases = load_test_cases(doc, "power_decimal")
    for tc in pd_cases:
        var result = power(Dec128(tc.a), Dec128(tc.b))
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

    testing.assert_equal(count_wrong, 0, "Some root/power cases failed.")


def test_root_approximate() raises:
    def _check(a: String, n: Int, prefix: String, desc: String) raises:
        testing.assert_true(String(root(Dec128(a), n)).startswith(prefix), desc)

    _check("2", 2, "1.4142135623730950488", "√2")
    _check("10", 3, "2.154434690031883721", "∛10")
    _check("1.44", 2, "1.2", "√1.44")
    _check("0.5", 2, "0.7071067811865475", "√0.5")
    _check("10", 100, "1.02329299228075413096627517", "100th root of 10")


def test_root_exceptions() raises:
    var caught = False
    try:
        var _r = root(Dec128(10), 0)
    except:
        caught = True
    testing.assert_true(caught, "0th root exception")

    caught = False
    try:
        var _r = root(Dec128(10), -2)
    except:
        caught = True
    testing.assert_true(caught, "negative root exception")

    caught = False
    try:
        var _r = root(Dec128(-4), 2)
    except:
        caught = True
    testing.assert_true(caught, "even root of negative exception")


def test_root_precision() raises:
    def _check(a: String, n: Int, prefix: String, desc: String) raises:
        testing.assert_true(String(root(Dec128(a), n)).startswith(prefix), desc)

    _check("2", 2, "1.414213562373095048801688724", "√2 high precision")
    _check("2", 3, "1.25992104989487316476721060", "∛2 high precision")
    _check("5", 2, "2.236067977499789696", "√5 high precision")


def test_root_identities() raises:
    var tol = Dec128("0.0000000001")

    var x1 = Dec128(7)
    var sq = root(x1, 2)
    testing.assert_true(abs(sq * sq - x1) < tol, "(√7)² ≈ 7")

    var x2 = Dec128(3)
    var cubed = x2 * x2 * x2
    testing.assert_true(abs(root(cubed, 3) - x2) < tol, "∛(3³) ≈ 3")

    var a = Dec128(4)
    var b = Dec128(9)
    testing.assert_true(
        abs(root(a * b, 2) - root(a, 2) * root(b, 2)) < tol,
        "√(4*9) = √4 * √9",
    )

    var x4 = Dec128(5)
    testing.assert_true(
        abs(power(x4, Dec128(1) / Dec128(3)) - root(x4, 3)) < tol,
        "5^(1/3) = ∛5",
    )


def test_power_approximate() raises:
    testing.assert_true(
        String(power(Dec128(2), Dec128("1.5"))).startswith(
            "2.828427124746190097603377448"
        )
    )
    testing.assert_true(
        String(power(Dec128("2.5"), Dec128("0.5"))).startswith(
            "1.5811388300841896659994467722"
        )
    )


def test_power_exceptions() raises:
    var caught = False
    try:
        var _r = power(Dec128(0), Dec128(-2))
    except:
        caught = True
    testing.assert_true(caught, "0^-2 exception")

    caught = False
    try:
        var _r = power(Dec128(-2), Dec128("0.5"))
    except:
        caught = True
    testing.assert_true(caught, "(-2)^0.5 exception")


# ===----------------------------------------------------------------------=== #
# cbrt - convenience wrapper for root(3)
# ===----------------------------------------------------------------------=== #


def test_cbrt_basic() raises:
    """Cube root must agree with `root(3)` and handle perfect cubes."""
    testing.assert_equal(
        String(Dec128("8").cbrt()), String(Dec128("8").root(3))
    )
    testing.assert_equal(
        String(Dec128("27").cbrt()), String(Dec128("27").root(3))
    )
    testing.assert_equal(String(Dec128("0").cbrt()), "0")
    testing.assert_equal(String(Dec128("1").cbrt()), "1")


def test_cbrt_negative() raises:
    """Cube root of a negative value is well-defined (unlike sqrt)."""
    # `root(3)` already supports odd roots of negatives; cbrt inherits that.
    testing.assert_equal(
        String(Dec128("-8").cbrt()), String(Dec128("-8").root(3))
    )
    testing.assert_true(
        Dec128("-27").cbrt().is_negative(), "cbrt(-27) is negative"
    )


def test_cbrt_approximate() raises:
    """Spot-check the prefix of an irrational cube root."""
    testing.assert_true(
        String(Dec128("10").cbrt()).startswith("2.154434690031883721"),
        "cbrt(10) prefix",
    )


def test_sqrt_last_digit() raises:
    """The last digit of `sqrt` is the correctly rounded one.

    Every value here was checked against CPython's `decimal` at 70 digits,
    rounded half-even to the exponent our answer carries. The integer square
    root path replaced a Newton iteration in `Decimal128` arithmetic, which
    was one unit out on 75 of 200 random arguments.
    """

    def _check(argument: String, expected: String) raises:
        testing.assert_equal(String(Decimal128(argument).sqrt()), expected)

    _check("47.8162940917854", "6.9149326888831969309272301033")
    _check("29.88302941156153", "5.4665372413952811193190728724")
    _check("4.78340403550129", "2.1870994571581078420465727157")
    _check("6102.77086491489747", "78.120233390043692764369492694")
    _check("46100527.63169216965921", "6789.7369339093079224740531713")
    _check("159368.68817974381539", "399.21008025818162622965613478")


def test_sqrt_keeps_exact_roots_exact() raises:
    """A square root that comes out exactly is not rounded or padded."""
    testing.assert_equal(String(Decimal128("4").sqrt()), "2")
    testing.assert_equal(String(Decimal128("0.25").sqrt()), "0.5")
    testing.assert_equal(String(Decimal128("1e-28").sqrt()), "0.00000000000001")
    testing.assert_equal(String(Decimal128("1522756").sqrt()), "1234")
    # Not exact, and the digits that survive say so: the true root is
    # 123456789012345.6788999999999979..., which carries to ...6789 at the
    # fourteenth decimal, all that fits beside fifteen integral digits.
    testing.assert_equal(
        String(Decimal128("15241578753238836750190519987").sqrt()),
        "123456789012345.67890000000000",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
