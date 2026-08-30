"""
Tests for Decimal128 exponential, logarithmic, and factorial functions:
exp, ln, log(base), log10, factorial, factorial_reciprocal.

Consolidates test_decimal128_{exp_ln, logarithm, factorial}.mojo. The
logarithm and factorial TOML data files are each parsed exactly once
per test. exp/ln tests have no TOML (they rely on startswith checks).
"""

from std import testing

from decimo.decimal128.decimal128 import Dec128, Decimal128
from decimo.decimal128.exponential import _exp_at, _ln_at, exp, ln, log, log10
from decimo.decimal128.special import factorial, factorial_reciprocal
from decimo.rounding_mode import RoundingMode
from decimo.tests import load_test_cases, parse_file
from decimo.toml.parser import TOMLDocument


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
    # Not one: the argument is `e` rounded to 28 digits, and the logarithm of
    # that is 0.99999999999999999999999999987..., which rounds to the value
    # below. This used to answer exactly `1` through a special case that
    # compared the argument with the stored `E()`, which is the same rounded
    # value and not `e`.
    testing.assert_equal(
        String(Decimal128("2.718281828459045235360287471").ln()),
        "0.9999999999999999999999999999",
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


def test_exponential_last_digit() raises:
    """The last digit of `exp`, `ln` and `log10` is the correctly rounded one.

    Every value here was checked against CPython's `decimal` at 70 digits,
    rounded half-even to the exponent our answer carries. Summing the series
    in `Decimal128` arithmetic rounded at every term, which left `ln` one to
    three units out on 108 of 200 random arguments, `log10` on 126 of 200,
    and `exp` up to four units out.
    """

    def _check_ln(argument: String, expected: String) raises:
        testing.assert_equal(String(ln(Decimal128(argument))), expected)

    def _check_log10(argument: String, expected: String) raises:
        testing.assert_equal(String(log10(Decimal128(argument))), expected)

    def _check_exp(argument: String, expected: String) raises:
        testing.assert_equal(String(exp(Decimal128(argument))), expected)

    _check_ln("2.75418858096677", "1.0131228732587128905702822980")
    _check_ln("230530420.12094788948185", "19.255893386187460799821632687")
    _check_ln("7015765.33870412123024", "15.763670365881893093897028026")
    _check_ln("29.88302941156153", "3.3972907410545113427119154405")
    _check_ln("10.55828499794678", "2.3569108595914505776137467763")
    _check_ln("4.78340403550129", "1.5651524343693196285331875240")

    _check_log10("2.75418858096677", "0.4399936733462265804443260079")
    _check_log10("7015765.33870412123024", "6.8460750544443209369842541009")
    _check_log10("29.88302941156153", "1.4754246222609834672114299731")
    _check_log10("10.55828499794678", "1.0235933806584169421786834025")
    _check_log10("297.20299815629379", "2.4730531862331090471126515535")
    _check_log10("6102.77086491489747", "3.7855270642100435986852514547")

    _check_exp("48.937484653331", "1791758787774364200668.9398320")
    _check_exp("3.112874479482", "22.485585950080698301915058640")
    _check_exp("3.729434379105", "41.655540255445860472722899403")
    _check_exp("18.271222522080", "86117441.55228067575146277518")
    _check_exp("17.560219388215", "42296689.909114876594363483851")
    _check_exp("20.846923952754", "1131628918.8175081235006184687")


def test_exponential_rational_points() raises:
    """Arguments with a short answer keep it short."""
    testing.assert_equal(String(exp(Decimal128("0"))), "1")
    testing.assert_equal(String(ln(Decimal128("1"))), "0")
    testing.assert_equal(String(log10(Decimal128("1000"))), "3")
    testing.assert_equal(String(log10(Decimal128("0.001"))), "-3")
    testing.assert_equal(String(log(Decimal128("8"), Decimal128("2"))), "3")


def test_exp_negative_matches_reciprocal() raises:
    """A negative argument is the reciprocal of the positive one."""

    def _check(argument: String, expected: String) raises:
        testing.assert_equal(String(exp(Decimal128(argument))), expected)

    _check("-1", "0.3678794411714423215955237702")
    _check("-12.5", "0.0000037266531720786709929249")
    _check("-0.005", "0.9950124791926823133525642462")


def test_logarithm_on_a_rounding_boundary() raises:
    """Arguments whose answer sits on the boundary between two results.

    Found by searching three million arguments for one whose thirtieth digit
    onward reads `5000...` or `4999...`: at that point the first width's own
    error is wider than the distance to the boundary, so it refuses to round
    and the computation runs again at 75 digits. Each value below was checked
    against CPython's `decimal` at 60 digits.
    """
    # ...0245000017266..., so the digits below the answer carry it up.
    testing.assert_equal(
        String(ln(Decimal128("6215888314.385201"))),
        "22.550374482409092836854714025",
    )
    # ...2254999986937..., just short of the boundary, so it stays put.
    testing.assert_equal(
        String(ln(Decimal128("387478688945552.51569"))),
        "33.590681966940057717836817225",
    )
    testing.assert_equal(
        String(log10(Decimal128("927967429054051.8189"))),
        "14.967532733082721117334088637",
    )
    testing.assert_equal(
        String(log10(Decimal128("5120760.203168846"))),
        "6.7093344390097680154396662144",
    )


def test_first_width_refuses_a_boundary() raises:
    """The first width says it cannot round these, rather than guessing."""
    var boundary = _ln_at[38](Decimal128("6215888314.385201"))
    testing.assert_false(
        Bool(boundary[0].to_decimal_decided(boundary[1])),
        "38 digits cannot place this answer and should not claim to",
    )
    var ordinary = _ln_at[38](Decimal128("123.456"))
    testing.assert_true(
        Bool(ordinary[0].to_decimal_decided(ordinary[1])),
        "an ordinary argument is settled at the first width",
    )
    # The wider one settles it, and both widths agree on the ordinary case.
    var wider = _ln_at[75](Decimal128("6215888314.385201"))
    testing.assert_true(Bool(wider[0].to_decimal_decided(wider[1])))
    testing.assert_equal(
        String(_ln_at[75](Decimal128("123.456"))[0].to_decimal()),
        String(ordinary[0].to_decimal()),
    )


def test_logarithm_close_to_one() raises:
    """Arguments a hair from one, where the answer is far smaller than the
    terms that make it.

    Taking the series directly on `[0.5, 2)` is what keeps these exact: the
    reduction would add `p * ln(2) + q * ln(10)` and then cancel them back
    out, spending fourteen of the digits carried to do it.
    """

    def _check_ln(argument: String, expected: String) raises:
        testing.assert_equal(String(ln(Decimal128(argument))), expected)

    _check_ln("0.99999999999999", "-0.0000000000000100000000000001")
    _check_ln(
        "0.9999999999999999999999999999", "-0.0000000000000000000000000001"
    )
    _check_ln(
        "1.0000000000000000000000000001", "0.0000000000000000000000000001"
    )
    _check_ln("0.999999999", "-0.0000000010000000005000000003")
    _check_ln("1.000000001", "0.0000000009999999995000000003")
    # Below the smallest scale the type has, and it still rounds rather than
    # collapsing to zero.
    testing.assert_equal(
        String(log10(Decimal128("0.9999999999999999999999999999"))),
        "-0.0000000000000000000000000000",
    )


def test_exponential_at_the_second_width() raises:
    """The wider pass of `exp` runs without reaching past a table.

    Shifting a 75-digit mantissa asks for powers of ten up to `10^74`, where
    the reciprocal divider's table stops at `10^48`. Nothing exercised that
    until `power` started calling the wider exponential, and it aborted
    rather than answering.
    """

    def _check(argument: String) raises:
        var narrow = _exp_at[38](Decimal128(argument))
        var wide = _exp_at[75](Decimal128(argument))
        testing.assert_equal(
            String(wide[0].to_decimal()), String(narrow[0].to_decimal())
        )

    _check("2.5")
    _check("-12.5")
    _check("40.123456789")
    _check("0.001")
    _check("66.5")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
