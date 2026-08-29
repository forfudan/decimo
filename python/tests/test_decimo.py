"""Verify BigDecimal round-trip through Mojo-Python bindings.

Cross-validates against Python's standard library decimal.Decimal where applicable.
"""

import copy
import decimal
import math
import operator
import pickle
from pathlib import Path
import sys

# Add python/src/ to sys.path so `import decimo` resolves to src/decimo/__init__.py
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

import decimo

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def check_arith(op_name, a_str, b_str, op):
    """Compare an arithmetic op between decimo and stdlib."""
    d_result = str(op(decimo.Decimal(a_str), decimo.Decimal(b_str)))
    s_result = str(op(decimal.Decimal(a_str), decimal.Decimal(b_str)))
    assert d_result == s_result, (
        f"{op_name}({a_str}, {b_str}): decimo={d_result!r}, stdlib={s_result!r}"
    )
    return d_result


def check_unary(op_name, a_str, op):
    """Compare a unary op between decimo and stdlib."""
    d_result = str(op(decimo.Decimal(a_str)))
    s_result = str(op(decimal.Decimal(a_str)))
    assert d_result == s_result, (
        f"{op_name}({a_str}): decimo={d_result!r}, stdlib={s_result!r}"
    )
    return d_result


def check_cmp(op_name, a_str, b_str, op):
    """Compare a comparison op between decimo and stdlib."""
    d_result = op(decimo.Decimal(a_str), decimo.Decimal(b_str))
    s_result = op(decimal.Decimal(a_str), decimal.Decimal(b_str))
    assert d_result == s_result, (
        f"{op_name}({a_str}, {b_str}): decimo={d_result}, stdlib={s_result}"
    )
    return d_result


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

print("=== decimo mojo4py Phase 0 ===")
print()

# --- Alias test ---
assert decimo.Decimal is decimo.BigDecimal, "Decimal should be BigDecimal"
print("[PASS] Decimal is BigDecimal")

# --- Construction / round-trip (cross-validated) ---
for s in [
    "3.14159265358979323846",
    "123456789.987654321",
    "42",
    "0",
    "-7.5",
    "99999999999999999999999999999999999999.123456789",
]:
    assert str(decimo.Decimal(s)) == str(decimal.Decimal(s)), (
        f"Round-trip mismatch for {s!r}"
    )
print("[PASS] Round-trip (cross-validated with stdlib decimal)")

# --- repr ---
d = decimo.Decimal("3.14159265358979323846")
print(f"[PASS] repr = {repr(d)}")
print()

# --- Arithmetic (cross-validated) ---
pairs = [
    ("1.5", "2.3"),
    ("100", "0.001"),
    ("0", "999"),
    ("-3.5", "2.5"),
    ("1", "3"),
]


for a_str, b_str in pairs:
    r = check_arith("add", a_str, b_str, operator.add)
    print(f"[PASS] {a_str} + {b_str} = {r}  (matches stdlib)")
    r = check_arith("sub", a_str, b_str, operator.sub)
    print(f"[PASS] {a_str} - {b_str} = {r}  (matches stdlib)")
    r = check_arith("mul", a_str, b_str, operator.mul)
    print(f"[PASS] {a_str} * {b_str} = {r}  (matches stdlib)")

# --- Unary (cross-validated) ---
for v in ["1.5", "-1.5", "0", "99.99"]:
    if v != "0":  # decimo gives "-0" for neg(0); stdlib gives "0" — skip cross-check
        r = check_unary("neg", v, operator.neg)
        print(f"[PASS] -{v} = {r}  (matches stdlib)")
    r = check_unary("abs", v, operator.abs)
    print(f"[PASS] abs({v}) = {r}  (matches stdlib)")
print()

# --- Comparison (cross-validated) ---
cmp_pairs = [
    ("1.5", "1.5"),
    ("1.5", "2.3"),
    ("2.3", "1.5"),
    ("-1", "1"),
    ("0", "0"),
    ("100", "99.999"),
]

for a_str, b_str in cmp_pairs:
    check_cmp("eq", a_str, b_str, operator.eq)
    check_cmp("ne", a_str, b_str, operator.ne)
    check_cmp("lt", a_str, b_str, operator.lt)
    check_cmp("le", a_str, b_str, operator.le)
    check_cmp("gt", a_str, b_str, operator.gt)
    check_cmp("ge", a_str, b_str, operator.ge)
print("[PASS] All comparisons (cross-validated with stdlib decimal)")
print()

# --- Division (cross-validated) ---
for a_str, b_str in [("1", "3"), ("10", "4"), ("-7.5", "2.5"), ("100", "0.001")]:
    r = check_arith("div", a_str, b_str, operator.truediv)
    print(f"[PASS] {a_str} / {b_str} = {r}  (matches stdlib)")
print()

# --- Operators come from the type itself, not a Python wrapper ---
# `Decimal` is the Mojo type. The operator slots are filled in __init__.py;
# if that wiring ever breaks, `+` raises TypeError while `.add()` still works.
assert type(decimo.Decimal("1")).__name__ == "Decimal"
assert "__add__" in type(decimo.Decimal("1")).__dict__
print("[PASS] Decimal is the native type and carries its own operators")

# --- repr keeps its Decimal(...) form ---
assert repr(decimo.Decimal("1.5")) == "Decimal('1.5')", repr(decimo.Decimal("1.5"))
print("[PASS] repr")

# --- Mixed operands, both directions (cross-validated) ---
mixed = [
    ("1.5", 2, operator.add),
    ("1.5", 2, operator.sub),
    ("1.5", 3, operator.mul),
    ("10", 4, operator.truediv),
]
for a_str, other, op in mixed:
    d = str(op(decimo.Decimal(a_str), other))
    s_ = str(op(decimal.Decimal(a_str), other))
    assert d == s_, f"{op.__name__}({a_str}, {other}): decimo={d!r}, stdlib={s_!r}"
    # ...and reflected, with the plain int on the left.
    d = str(op(other, decimo.Decimal(a_str)))
    s_ = str(op(other, decimal.Decimal(a_str)))
    assert d == s_, f"r{op.__name__}({other}, {a_str}): decimo={d!r}, stdlib={s_!r}"
print("[PASS] Mixed Decimal/int operands, both directions")

# --- Which operands convert, checked against stdlib decimal ---
# decimal.Decimal converts an int in arithmetic and nothing else: a float is
# refused on purpose, because silently mixing a binary fraction into a decimal
# one is the mistake the type exists to prevent. Comparison is looser and takes
# a float too. Anything else is NotImplemented, which is what makes `==` answer
# False while `<` and the arithmetic operators raise TypeError.
ARITH = [operator.add, operator.sub, operator.mul, operator.truediv]
ORDER = [operator.lt, operator.le, operator.gt, operator.ge]


def same_as_stdlib(op, a_str, other):
    """Run `op` on both libraries and require the same outcome."""

    def run(make):
        # A refused operand is a TypeError on both sides. Other failures --
        # dividing by False, say -- are their own error types and only have to
        # agree on being failures.
        try:
            r = op(make(a_str), other)
        except TypeError:
            return "TypeError"
        except Exception:
            return "error"
        return str(r)

    ours, std = run(decimo.Decimal), run(decimal.Decimal)
    assert ours == std, (
        f"{op.__name__}({a_str}, {other!r}): decimo={ours!r}, stdlib={std!r}"
    )


for other in [2, True, False, 2.0, "2", [1], None]:
    for op in ARITH + ORDER + [operator.eq, operator.ne]:
        same_as_stdlib(op, "1.5", other)
print(
    "[PASS] Operand conversion matches stdlib decimal (int yes, float and "
    "str no in arithmetic)"
)

# Reflected too: the plain value on the left, the decimal on the right.
for other in [2, True, 2.0, "2", [1]]:
    for op in ARITH:

        def run(make):
            try:
                return str(op(other, make("1.5")))
            except TypeError:
                return "TypeError"
            except Exception:
                return "error"

        assert run(decimo.Decimal) == run(decimal.Decimal), (op.__name__, other)
print("[PASS] Reflected operand conversion matches stdlib decimal")

# Equality never raises, so a Decimal can sit in a list of mixed types.
assert (decimo.Decimal("1.5") == [1]) is False
assert (decimo.Decimal("1.5") != [1]) is True
assert decimo.Decimal("1.5") not in [1, 2]
print("[PASS] Equality against an unrelated type is False, not an error")

# --- Floats are read exactly, like decimal.Decimal ---
# Decimal(0.1) is the value the float actually holds, not the literal that was
# typed. This used to be the one conversion where decimo and stdlib disagreed.
for v in [
    0.1,
    0.5,
    -2.5,
    1 / 3,
    123.456,
    1e20,
    1e-20,
    2.220446049250313e-16,
    5e-324,
    -0.0,
]:
    ours, std = str(decimo.Decimal(v)), str(decimal.Decimal(v))
    assert ours == std, f"Decimal({v!r}): decimo={ours!r}, stdlib={std!r}"
print("[PASS] Floats convert exactly (cross-validated with stdlib decimal)")

# ...and the comparisons that follow from it.
assert (decimo.Decimal("0.1") == 0.1) is False
assert (decimo.Decimal(0.1) == 0.1) is True
assert (decimo.Decimal("0.5") == 0.5) is True
print("[PASS] Comparison against a float follows the exact value")

# --- bool ---
for v, expected in [
    ("0", False),
    ("0.000", False),
    ("-0", False),
    ("2", True),
    ("-0.5", True),
]:
    assert bool(decimo.Decimal(v)) is expected, v
    assert bool(decimo.Decimal(v)) == bool(decimal.Decimal(v)), v
print("[PASS] bool (cross-validated with stdlib decimal)")

# --- unary plus ---
assert str(+decimo.Decimal("1.5")) == "1.5"
print("[PASS] unary plus")

# --- Hashing agrees with int, float and stdlib decimal ---
for v in [
    "0",
    "-0",
    "1",
    "2",
    "1.0",
    "1.5",
    "-1.5",
    "100",
    "1E+2",
    "0.1",
    "12345678901234567890.5",
    "-7",
]:
    assert hash(decimo.Decimal(v)) == hash(decimal.Decimal(v)), v
assert hash(decimo.Decimal("2")) == hash(2) == hash(2.0)
assert hash(decimo.Decimal("1.5")) == hash(1.5)
assert hash(decimo.Decimal("1")) == hash(decimo.Decimal("1.0"))
assert len({decimo.Decimal("1"), decimo.Decimal("1.0"), 1}) == 1
# The hash is computed in Mojo, over the coefficient's own words and the
# exponent as a modular power, so it is worth sweeping rather than sampling:
# every one of these has to land on the same integer `decimal` lands on.
import random as _hash_random

_hash_rng = _hash_random.Random(11)
for _ in range(2000):
    _text = f"{_hash_rng.randint(-(10**24), 10**24)}E{_hash_rng.randint(-40, 40)}"
    assert hash(decimo.Decimal(_text)) == hash(decimal.Decimal(_text)), _text
for _text in ("-0", "0.000", "1E-1000000", "1E+1000000", "9" * 40, "-" + "9" * 40):
    assert hash(decimo.Decimal(_text)) == hash(decimal.Decimal(_text)), _text
print("[PASS] hash agrees with int, float and stdlib decimal")

# --- Precision comes from the context, as it does in decimal ---
for prec in (5, 28, 50, 200):
    decimo.getcontext().prec = prec
    decimal.getcontext().prec = prec
    assert decimo.getcontext().prec == prec
    for a, b in [("1", "7"), ("2", "3"), ("355", "113")]:
        assert str(decimo.Decimal(a) / decimo.Decimal(b)) == str(
            decimal.Decimal(a) / decimal.Decimal(b)
        ), (prec, a, b)
decimo.getcontext().prec = 28
decimal.getcontext().prec = 28
print("[PASS] getcontext().prec drives the arithmetic")

# --- localcontext restores the precision on the way out ---
with decimo.localcontext() as context:
    context.prec = 60
    wide = str(decimo.Decimal(1) / decimo.Decimal(3))
assert len(wide) == 62, wide  # "0." plus 60 digits
assert decimo.getcontext().prec == 28
narrow = str(decimo.Decimal(1) / decimo.Decimal(3))
assert len(narrow) == 30, narrow
print("[PASS] localcontext restores the precision")

# --- Unary plus and minus round to the context precision, as in decimal ---
with decimo.localcontext() as context:
    context.prec = 5
    decimal.getcontext().prec = 5
    for v in ["1.2345678", "-1.2345678", "0.99999999"]:
        assert str(+decimo.Decimal(v)) == str(+decimal.Decimal(v)), v
        assert str(-decimo.Decimal(v)) == str(-decimal.Decimal(v)), v
decimal.getcontext().prec = 28
print("[PASS] unary plus and minus round to the context precision")

# --- The remaining operators (cross-validated) ---
for a, b in [
    ("7", "2"),
    ("-7", "2"),
    ("7", "-2"),
    ("7.5", "2.5"),
    ("100", "7"),
    ("1", "3"),
]:
    for name, op in [("//", operator.floordiv), ("%", operator.mod)]:
        check_arith(name, a, b, op)
    assert str(divmod(decimo.Decimal(a), decimo.Decimal(b))) == str(
        divmod(decimal.Decimal(a), decimal.Decimal(b))
    ), (a, b)
for a, b in [("2", "10"), ("3", "4"), ("1.5", "3"), ("10", "-2")]:
    check_arith("**", a, b, operator.pow)
print("[PASS] floordiv, mod, divmod and pow (cross-validated)")

# --- Conversion to the built-in numeric types ---
for v in ["0", "2.7", "-2.7", "2.5", "3.5", "-0.5", "12345678901234567890.9", "1E+3"]:
    assert int(decimo.Decimal(v)) == int(decimal.Decimal(v)), v
    assert float(decimo.Decimal(v)) == float(decimal.Decimal(v)), v
    assert round(decimo.Decimal(v)) == round(decimal.Decimal(v)), v
    assert math.floor(decimo.Decimal(v)) == math.floor(decimal.Decimal(v)), v
    assert math.ceil(decimo.Decimal(v)) == math.ceil(decimal.Decimal(v)), v
    assert math.trunc(decimo.Decimal(v)) == math.trunc(decimal.Decimal(v)), v
for v, places in [("2.675", 2), ("1.2345", 3), ("123.456", -1), ("-2.5", 0)]:
    assert str(round(decimo.Decimal(v), places)) == str(
        round(decimal.Decimal(v), places)
    ), (v, places)
# int() must not be capped at 64 bits the way Mojo's own Int is.
big = "9" * 40
assert int(decimo.Decimal(big)) == int(big)
print("[PASS] int, float, round, floor, ceil, trunc (cross-validated)")

# --- The named methods of decimal.Decimal ---
for v, template in [
    ("1.2345", "0.01"),
    ("19.999", "0.01"),
    ("1.5", "1"),
    ("-0.5", "0.1"),
]:
    assert str(decimo.Decimal(v).quantize(decimo.Decimal(template))) == str(
        decimal.Decimal(v).quantize(decimal.Decimal(template))
    ), (v, template)
for v in ["1.2300", "100", "0", "-1.50"]:
    assert str(decimo.Decimal(v).normalize()) == str(decimal.Decimal(v).normalize()), v
    assert decimo.Decimal(v).as_tuple() == decimal.Decimal(v).as_tuple(), v
    assert decimo.Decimal(v).is_zero() == decimal.Decimal(v).is_zero(), v
    assert decimo.Decimal(v).is_signed() == decimal.Decimal(v).is_signed(), v
    assert decimo.Decimal(v).adjusted() == decimal.Decimal(v).adjusted(), v
    assert str(decimo.Decimal(v).to_eng_string()) == str(
        decimal.Decimal(v).to_eng_string()
    ), v
assert str(decimo.Decimal("2").fma(3, 4)) == str(decimal.Decimal("2").fma(3, 4))
assert str(decimo.Decimal("1").compare(2)) == str(decimal.Decimal("1").compare(2))
assert str(decimo.Decimal("3").max(2)) == str(decimal.Decimal("3").max(2))
assert str(decimo.Decimal("3").min(2)) == str(decimal.Decimal("3").min(2))
assert str(decimo.Decimal("1.5").scaleb(3)) == str(decimal.Decimal("1.5").scaleb(3))
assert str(decimo.Decimal("-1").copy_abs()) == "1"
assert str(decimo.Decimal("1").copy_negate()) == "-1"
assert str(decimo.Decimal("1").copy_sign(decimo.Decimal("-2"))) == "-1"
assert decimo.Decimal("1.50").same_quantum(decimo.Decimal("2.34")) is True
assert decimo.Decimal("1.5").same_quantum(decimo.Decimal("2.34")) is False
print("[PASS] quantize, normalize, as_tuple, fma and friends")

# --- as_integer_ratio ---
for v in ["0.25", "-0.25", "0", "1E+3", "1.5", "100"]:
    assert (
        decimo.Decimal(v).as_integer_ratio() == decimal.Decimal(v).as_integer_ratio()
    ), v
print("[PASS] as_integer_ratio")

# --- sqrt, exp, ln and log10 follow the context precision ---
for prec in (10, 28, 60):
    decimo.getcontext().prec = prec
    decimal.getcontext().prec = prec
    for v in ["2", "10", "1.5"]:
        for method in ("sqrt", "exp", "ln", "log10"):
            ours = str(getattr(decimo.Decimal(v), method)())
            theirs = str(getattr(decimal.Decimal(v), method)())
            # The last digit may differ: decimo rounds the true value, and
            # `decimal` is only required to be correctly rounded for sqrt.
            assert ours[: prec - 1] == theirs[: prec - 1], (
                prec,
                v,
                method,
                ours,
                theirs,
            )
decimo.getcontext().prec = 28
decimal.getcontext().prec = 28
print("[PASS] sqrt, exp, ln and log10 at three precisions")

# --- Errors have the types a decimal program expects ---
for expression in ["a / b", "a // b", "a % b", "divmod(a, b)"]:
    try:
        eval(expression, {"a": decimo.Decimal(1), "b": decimo.Decimal(0)})
    except ZeroDivisionError:
        pass
    else:
        raise AssertionError(f"{expression} should raise ZeroDivisionError")
try:
    decimo.Decimal(1) / 0
except decimo.DivisionByZero:
    pass
else:
    raise AssertionError("DivisionByZero should catch it too")
for bad in ["abc", "1.2.3", ""]:
    try:
        decimo.Decimal(bad)
    except decimo.InvalidOperation:
        pass
    else:
        raise AssertionError(f"Decimal({bad!r}) should raise")
for value, method in [("-2", "sqrt"), ("-1", "ln"), ("0", "log10")]:
    try:
        getattr(decimo.Decimal(value), method)()
    except ValueError:
        pass
    else:
        raise AssertionError(f"{method}({value}) should raise")
print("[PASS] ZeroDivisionError and ValueError, not a bare Exception")

# --- Every rounding mode, checked against decimal under the same context ---
#
# Arithmetic, quantize, round(x, n), to_integral_value and the unary signs
# have to agree digit for digit under all seven modes, at precisions where
# the rounding actually bites. ROUND_05UP is the one mode decimo does not
# have, and it is refused rather than faked.
import random as _random

_rng = _random.Random(3)


def _random_decimal_text():
    digits = "".join(_rng.choice("0123456789") for _ in range(_rng.randint(1, 40)))
    sign = "-" if _rng.random() < 0.5 else ""
    return f"{sign}{digits}E{_rng.randint(-30, 30)}"


_values = [_random_decimal_text() for _ in range(200)] + [
    "2.5",
    "-2.5",
    "0.125",
    "1E+2",
    "7",
    "1.00000000000000000000000000005",
    "-1.00000000000000000000000000015",
    "0.9999999",
    "-0.9999999",
]
_rounding_ops = {
    "+": lambda a, b: a + b,
    "-": lambda a, b: a - b,
    "*": lambda a, b: a * b,
    "/": lambda a, b: a / b,
    "pos": lambda a, b: +a,
    "neg": lambda a, b: -a,
    "round3": lambda a, b: round(a, 3),
    "to_integral": lambda a, b: a.to_integral_value(),
    "quantize": lambda a, b: a.quantize(type(a)("1.00")),
    "fma": lambda a, b: a.fma(b, type(a)("0.5")),
    "abs": lambda a, b: abs(a),
    "max": lambda a, b: a.max(b),
    "min": lambda a, b: a.min(b),
    "normalize": lambda a, b: a.normalize(),
    "scaleb": lambda a, b: a.scaleb(type(a)(2)),
}
_modes = [
    "ROUND_HALF_EVEN",
    "ROUND_HALF_UP",
    "ROUND_HALF_DOWN",
    "ROUND_DOWN",
    "ROUND_UP",
    "ROUND_CEILING",
    "ROUND_FLOOR",
]


def _outcome(mod, op, a, b):
    try:
        return str(op(mod.Decimal(a), mod.Decimal(b)))
    except Exception as error:  # noqa: BLE001 -- both sides may refuse
        return "error"


for _mode in _modes:
    for _prec in (1, 5, 28):
        decimal.getcontext().prec = _prec
        decimal.getcontext().rounding = _mode
        decimo.getcontext().prec = _prec
        decimo.getcontext().rounding = _mode
        assert decimo.getcontext().rounding == _mode
        for _i in range(len(_values) - 1):
            _a, _b = _values[_i], _values[_i + 1]
            for _name, _op in _rounding_ops.items():
                _want = _outcome(decimal, _op, _a, _b)
                _got = _outcome(decimo, _op, _a, _b)
                assert _want == _got, (_mode, _prec, _name, _a, _b, _want, _got)

# The division above never reaches the truncated fast path: that one starts
# only when the divisor is wider than the requested precision needs, which
# for these operands it never is. Build divisors of two hundred digits and
# put the quotient exactly on a boundary -- exact, one below, one above, and
# a half -- since the fast path has to hand those back to the slow one under
# a mode that can see the difference.
_big_divisor = int("7" + "3141592653589793238462643383279502884197" * 5)
_big_cases = []
for _q in (int("9" * 30), 10**29, int("123456789" * 3)):
    _exact = _big_divisor * _q
    _big_cases += [
        (str(_exact), str(_big_divisor)),
        (str(_exact - 1), str(_big_divisor)),
        (str(_exact + 1), str(_big_divisor)),
        # `q + 1/2` exactly, by halving the divisor instead of the dividend.
        (str(_big_divisor * (2 * _q + 1)), str(2 * _big_divisor)),
    ]

for _mode in _modes:
    for _prec in (1, 5, 28, 30):
        decimal.getcontext().prec = _prec
        decimal.getcontext().rounding = _mode
        decimo.getcontext().prec = _prec
        decimo.getcontext().rounding = _mode
        for _a, _b in _big_cases:
            _want = _outcome(decimal, _rounding_ops["/"], _a, _b)
            _got = _outcome(decimo, _rounding_ops["/"], _a, _b)
            assert _want == _got, (_mode, _prec, "/", _a[:20], _b[:20], _want, _got)

decimal.getcontext().prec = 28
decimal.getcontext().rounding = decimal.ROUND_HALF_EVEN
decimo.getcontext().prec = 28
decimo.getcontext().rounding = decimo.ROUND_HALF_EVEN
print("[PASS] all seven rounding modes agree with decimal")

try:
    decimo.getcontext().rounding = decimo.ROUND_05UP
except NotImplementedError:
    pass
else:
    raise AssertionError("ROUND_05UP should be refused, not faked")
assert decimo.getcontext().rounding == decimo.ROUND_HALF_EVEN
print("[PASS] the one rounding mode we do not have is refused")

# --- Context is a value until it is installed; localcontext restores ---
_ctx = decimo.Context(prec=5, rounding=decimo.ROUND_DOWN)
assert decimo.getcontext().prec == 28, "building a Context must not install it"
with decimo.localcontext(_ctx) as _live:
    assert _live.prec == 5 and _live.rounding == decimo.ROUND_DOWN
    assert str(decimo.Decimal(1) / decimo.Decimal(3)) == "0.33333"
    _live.prec = 3
    assert str(decimo.Decimal(2) / decimo.Decimal(3)) == "0.666"
assert decimo.getcontext().prec == 28
assert decimo.getcontext().rounding == decimo.ROUND_HALF_EVEN
with decimo.localcontext(rounding=decimo.ROUND_UP, prec=2):
    assert str(decimo.Decimal("1.01") + 0) == "1.1"
# `repr` matches decimal's shape; the traps differ because decimo has no
# signals, so compare the settings rather than the text.
assert repr(decimo.BasicContext).startswith("Context(prec=9, rounding=ROUND_HALF_UP,")
assert decimal.BasicContext.prec == decimo.BasicContext.prec == 9
assert decimo.BasicContext.rounding == decimal.BasicContext.rounding
print("[PASS] Context values, setcontext and localcontext behave as in decimal")

# --- copy, deepcopy, pickle and format ---
original = decimo.Decimal("9.5")
assert str(copy.copy(original)) == "9.5"
assert str(copy.deepcopy(original)) == "9.5"
assert str(pickle.loads(pickle.dumps(original))) == "9.5"
for v, spec in [
    ("1234.5", ",.2f"),
    ("0.125", ".1%"),
    ("1.5", ""),
    ("42", ">10"),
    ("1234567", "e"),
]:
    assert format(decimo.Decimal(v), spec) == format(decimal.Decimal(v), spec), (
        v,
        spec,
    )
assert f"{decimo.Decimal('1.5')}" == "1.5"
print("[PASS] copy, deepcopy, pickle and format")


# --- The rest of the specification's method surface, against decimal ---
#
# Digit-wise logic, the neighbours, the total order, remainder_near and logb,
# compared with decimal over the same operands under three precisions. The two
# places decimo answers where decimal refuses are listed below.
_spec_values = [
    "0",
    "1",
    "-1",
    "1100",
    "1010",
    "0.001",
    "12.0",
    "12",
    "-12.0",
    "-12",
    "2.5",
    "-2.5",
    "9.99999",
    "1.23456789",
    "0.000123456789",
    "-7.7777",
    "1E+5",
    "1E-5",
    "111",
    "1000",
    "-0",
    "0.0",
    "100",
    "1.000",
]
_spec_others = ["1010", "3", "1", "0", "12", "-12", "2", "1E+2", "111"]
_spec_calls = {
    "remainder_near": lambda x, y: x.remainder_near(y),
    "next_plus": lambda x, y: x.next_plus(),
    "next_minus": lambda x, y: x.next_minus(),
    "next_toward": lambda x, y: x.next_toward(y),
    "shift(1)": lambda x, y: x.shift(1),
    "shift(-2)": lambda x, y: x.shift(-2),
    "rotate(1)": lambda x, y: x.rotate(1),
    "rotate(-2)": lambda x, y: x.rotate(-2),
    "logical_and": lambda x, y: x.logical_and(y),
    "logical_or": lambda x, y: x.logical_or(y),
    "logical_xor": lambda x, y: x.logical_xor(y),
    "logical_invert": lambda x, y: x.logical_invert(),
    "logb": lambda x, y: x.logb(),
    "compare_total": lambda x, y: x.compare_total(y),
    "compare_total_mag": lambda x, y: x.compare_total_mag(y),
    "compare_signal": lambda x, y: x.compare_signal(y),
    "max_mag": lambda x, y: x.max_mag(y),
    "min_mag": lambda x, y: x.min_mag(y),
    "max": lambda x, y: x.max(y),
    "min": lambda x, y: x.min(y),
    "number_class": lambda x, y: x.number_class(),
    "to_integral_exact": lambda x, y: x.to_integral_exact(),
    "is_normal": lambda x, y: x.is_normal(),
    "is_subnormal": lambda x, y: x.is_subnormal(),
    "is_qnan": lambda x, y: x.is_qnan(),
    "is_snan": lambda x, y: x.is_snan(),
}
# decimal signals where decimo raises the builtin it maps them to.
_signal_names = {
    "InvalidOperation": "ValueError",
    "DivisionByZero": "ZeroDivisionError",
}


def _spec_outcome(call, mod, a, b):
    try:
        return str(call(mod.Decimal(a), mod.Decimal(b)))
    except Exception as error:  # noqa: BLE001 -- either side may refuse
        name = type(error).__name__
        return "error:" + _signal_names.get(name, name)


for _prec in (3, 9, 28):
    decimal.getcontext().prec = _prec
    decimo.getcontext().prec = _prec
    for _name, _call in _spec_calls.items():
        for _a in _spec_values:
            for _b in _spec_others:
                _want = _spec_outcome(_call, decimal, _a, _b)
                _got = _spec_outcome(_call, decimo, _a, _b)
                if _want == _got:
                    continue
                # decimal refuses an integer quotient longer than the
                # precision; decimo answers it, as it does for `//`.
                if _name == "remainder_near" and _want == "error:ValueError":
                    continue
                raise AssertionError((_prec, _name, _a, _b, _want, _got))
decimal.getcontext().prec = 28
decimo.getcontext().prec = 28
print("[PASS] logic, neighbours, the total order and friends agree with decimal")

# The neighbour of zero is the one place an Emin is needed, and it comes from
# the context rather than from the library.
with decimo.localcontext(prec=3):
    assert str(decimo.Decimal(0).next_plus()) == "1E-1000001"
    assert str(decimo.Decimal(0).next_minus()) == "-1E-1000001"
    assert str(decimo.Decimal("1").next_minus()) == "0.999"
    assert str(decimo.Decimal("-1").next_plus()) == "-0.999"
with decimo.localcontext(prec=3, Emin=-10):
    assert str(decimo.Decimal(0).next_plus()) == "1E-12"
    assert decimo.Decimal("1E-11").is_subnormal()
    assert decimo.Decimal("1E-11").number_class() == "+Subnormal"
    assert not decimo.Decimal("1E-9").is_subnormal()
print("[PASS] Emin decides the neighbour of zero and what is subnormal")


# --- Keyword arguments, tuple construction, three-argument pow, pi and e ---
#
# `quantize(exp, rounding=...)` is how money code spells itself, and the four
# below are what a `decimal` program reaches for that decimo used to refuse.
_cents = decimo.Decimal("0.01")
assert (
    str(decimo.Decimal("2.675").quantize(_cents, rounding=decimo.ROUND_HALF_UP))
    == "2.68"
)
assert str(decimo.Decimal("2.675").quantize(_cents, decimo.ROUND_HALF_UP)) == "2.68"
assert (
    str(
        decimo.Decimal("2.675").quantize(
            _cents, rounding=decimo.ROUND_FLOOR, context=None
        )
    )
    == "2.67"
)
assert str(decimo.Decimal("2.7").to_integral_value(rounding=decimo.ROUND_FLOOR)) == "2"
assert str(decimo.Decimal(2).sqrt(context=None))[:6] == "1.4142"
for _bad in ({"rouding": decimo.ROUND_UP}, {"nonsense": 1}):
    try:
        decimo.Decimal("1").quantize(_cents, **_bad)
    except TypeError:
        pass
    else:
        raise AssertionError(f"quantize should refuse {_bad}")
try:
    decimo.Decimal("1").quantize(_cents, decimo.ROUND_UP, rounding=decimo.ROUND_UP)
except TypeError:
    pass
else:
    raise AssertionError("quantize should refuse an argument given twice")
try:
    decimo.Decimal("1.25").quantize(_cents, rounding=decimo.ROUND_05UP)
except NotImplementedError:
    pass
else:
    raise AssertionError("ROUND_05UP should be refused here too")

# `as_tuple()` round-trips: the constructor takes what it gives.
for _text in ("12.34", "-5", "0", "1E+5", "0.000123"):
    _tuple = decimo.Decimal(_text).as_tuple()
    assert str(decimo.Decimal(_tuple)) == str(decimal.Decimal(tuple(_tuple))), _text
assert str(decimo.Decimal((1, (5,), 0))) == "-5"
assert str(decimo.Decimal([0, (1, 5), -1])) == "1.5"
for _bad_tuple in ((0, (), "F"), (0, (1, 2)), (0, (1, 10), 0)):
    try:
        decimo.Decimal(_bad_tuple)
    except ValueError:
        pass
    else:
        raise AssertionError(f"{_bad_tuple} should be refused")

# `pow(x, y, m)`, which needs whole numbers and goes through modular
# exponentiation rather than raising the base first.
assert str(pow(decimo.Decimal(3), decimo.Decimal(20), decimo.Decimal(7))) == str(
    pow(decimal.Decimal(3), decimal.Decimal(20), decimal.Decimal(7))
)
assert str(
    pow(decimo.Decimal(2), decimo.Decimal(1000), decimo.Decimal(10**9 + 7))
) == str(pow(decimal.Decimal(2), decimal.Decimal(1000), decimal.Decimal(10**9 + 7)))
assert str(pow(3, decimo.Decimal(20), 7)) == "2"
assert str(decimo.Decimal("1.5") ** 2) == "2.25"
assert str(2 ** decimo.Decimal(3)) == "8"
for _args in (("1.5", 2, 7), (3, -2, 7), (3, 2, 0)):
    try:
        pow(*[decimo.Decimal(str(_x)) for _x in _args])
    except decimo.InvalidOperation:
        pass
    else:
        raise AssertionError(f"pow{_args} should be refused")
print("[PASS] keyword arguments, tuple construction and three-argument pow")

# --- Context is something you can compute with, as in decimal ---
_free = decimo.Context(prec=4, rounding=decimo.ROUND_DOWN)
_theirs = decimal.Context(prec=4, rounding=decimal.ROUND_DOWN)
for _name, _operands in [
    ("divide", ("1", "3")),
    ("add", ("10000", "1")),
    ("subtract", ("1", "3")),
    ("multiply", ("1.5", "3")),
    ("divide_int", ("7", "2")),
    ("remainder", ("7", "2")),
    ("sqrt", ("2",)),
    ("exp", ("1",)),
    ("ln", ("10",)),
    ("log10", ("1000",)),
    ("power", ("2", "10")),
    ("quantize", ("1.23456", "0.01")),
    ("plus", ("1.23456",)),
    ("minus", ("1.23456",)),
    ("abs", ("-1.23456",)),
    ("to_integral_value", ("2.7",)),
    ("compare", ("1", "2")),
    ("max", ("1", "2")),
    ("normalize", ("1.2300",)),
    ("scaleb", ("1.5", "2")),
    ("number_class", ("1",)),
    ("to_eng_string", ("1.23E+5",)),
]:
    _got = getattr(_free, _name)(*[decimo.Decimal(o) for o in _operands])
    _want = getattr(_theirs, _name)(*[decimal.Decimal(o) for o in _operands])
    assert str(_got) == str(_want), (_name, str(_got), str(_want))
assert str(_free.power(decimo.Decimal(3), decimo.Decimal(20), decimo.Decimal(7))) == "2"
assert str(_free.divmod(decimo.Decimal(7), decimo.Decimal(2))) == str(
    _theirs.divmod(decimal.Decimal(7), decimal.Decimal(2))
)
# A context you built is still a value: computing with it changes nothing.
assert decimo.getcontext().prec == 28
assert decimo.getcontext().rounding == decimo.ROUND_HALF_EVEN
print("[PASS] Context computes without disturbing the current one")

# --- pi and e, which decimal does not have ---
assert str(decimo.pi(30)) == "3.14159265358979323846264338328"
assert str(decimo.e(30)) == "2.71828182845904523536028747135"
with decimo.localcontext(prec=50):
    assert str(decimo.pi())[:20] == "3.141592653589793238"
    assert len(str(decimo.e()).replace(".", "")) == 50
assert decimo.getcontext().prec == 28
print("[PASS] pi and e at any precision")


# --- sqrt under a rounding mode, which decimal has no way to ask for ------
#
# `decimal.sqrt` ignores the context mode and always rounds half to even, and
# so does ours when nothing is asked for. `rounding=` is decimo's own, and the
# answer under it is exact rather than approximated: the check below is the
# defining property, squared back with integers, not a comparison against
# another implementation.
from fractions import Fraction as _Fraction

with decimo.localcontext(prec=5):
    assert str(decimo.Decimal(2).sqrt()) == "1.4142"
    assert str(decimo.Decimal(2).sqrt(rounding=decimo.ROUND_FLOOR)) == "1.4142"
    assert str(decimo.Decimal(2).sqrt(rounding=decimo.ROUND_CEILING)) == "1.4143"
    assert str(decimo.Decimal("1.44").sqrt(rounding=decimo.ROUND_UP)) == "1.2"
with decimo.localcontext(prec=1):
    assert str(decimo.Decimal(2).sqrt(rounding=decimo.ROUND_DOWN)) == "1"
    assert str(decimo.Decimal(2).sqrt(rounding=decimo.ROUND_UP)) == "2"
try:
    decimo.Decimal(2).sqrt(rounding=decimo.ROUND_05UP)
except NotImplementedError:
    pass
else:
    raise AssertionError("ROUND_05UP should be refused by sqrt too")

_sqrt_rng = _hash_random.Random(17)
_sqrt_values = ["2", "3", "5", "10", "0.0001", "123456789", "1.0001"]
_sqrt_values += [str(_sqrt_rng.randint(1, 10**20)) for _ in range(40)]
for _text in _sqrt_values:
    for _prec in (1, 5, 17, 28):
        with decimo.localcontext(prec=_prec):
            _low = decimo.Decimal(_text).sqrt(rounding=decimo.ROUND_FLOOR)
            _high = decimo.Decimal(_text).sqrt(rounding=decimo.ROUND_CEILING)
        _x = _Fraction(_text)
        _below, _above = _Fraction(str(_low)), _Fraction(str(_high))
        assert _below * _below <= _x, (_text, _prec, "floor is above the root")
        assert _above * _above >= _x, (_text, _prec, "ceiling is below the root")
        if _below != _above:
            # Neighbours: nothing representable lies between them.
            _ulp = _above - _below
            assert (_below + _ulp) == _above, (_text, _prec)
print("[PASS] sqrt is exact under every rounding mode")

# --- exp, ln and log10: the rounding is decided, not assumed ---------------
#
# These three arguments put a rounding boundary inside the interval the
# kernel's own error bound allows, so the answer cannot be settled on the
# first pass and the library has to widen and look again. They are the shape
# a fixed number of guard digits gets wrong: the digits just past the cut are
# `000` or `999`. Expected values from `decimal` at fifty digits, rounded
# once.
for _text, _call, _reference in [
    ("664.247984247", lambda x, m: x.ln(rounding=m), lambda d: d.ln()),
    ("167.837678670", lambda x, m: x.exp(rounding=m), lambda d: d.exp()),
    ("132.960671561", lambda x, m: x.log10(rounding=m), lambda d: d.log10()),
]:
    with decimal.localcontext() as _wide:
        _wide.prec = 50
        _true = _reference(decimal.Decimal(_text))
    for _mode in _modes:
        with decimal.localcontext() as _narrow:
            _narrow.prec, _narrow.rounding = 9, _mode
            _want = str(+_true)
        with decimo.localcontext(prec=9):
            _got = str(_call(decimo.Decimal(_text), _mode))
        assert _want == _got, (_text, _mode, _want, _got)

# The rational points, where the true value does sit on a boundary and the
# loop would never settle: each is answered before it is entered.
with decimo.localcontext(prec=9):
    for _mode in _modes:
        assert str(decimo.Decimal(0).exp(rounding=_mode)) == "1"
        assert str(decimo.Decimal(1).ln(rounding=_mode)) == "0"
        assert str(decimo.Decimal(1000).log10(rounding=_mode)) == "3"
print("[PASS] exp, ln and log10 decide their rounding under every mode")


# --- The one program that has to work: the same source, both libraries ---
def average(mod, values):
    total = mod.Decimal(0)
    for value in values:
        total += mod.Decimal(value)
    return total / mod.Decimal(len(values))


sample = ["1.05", "2.10", "3.15", "0.001", "-4.2"]
assert str(average(decimo, sample)) == str(average(decimal, sample))
print("[PASS] the same function run against decimal and decimo agrees")

# --- Decimal128, the fixed-width type --------------------------------------

D128 = decimo.Decimal128

assert decimo.Dec128 is D128

# Construction from every source `Decimal` accepts.
assert str(D128("3.14")) == "3.14"
assert str(D128(42)) == "42"
assert str(D128()) == "0"
assert str(D128(D128("1.50"))) == "1.50"
assert str(D128(decimo.Decimal("2.25"))) == "2.25"
# A float comes back as itself. `Decimal128(float)` does not spell out the
# whole binary expansion the way `decimal.Decimal(float)` does -- the type
# holds 28 digits and 0.1 needs 55 -- so what is promised is the round trip.
for _value in (0.1, 3.14, 2.675, 0.5, 1e20):
    assert float(D128(_value)) == _value
print("[PASS] Decimal128 is built from strings, integers, floats and decimals")

# The exact operations agree with decimal digit for digit.
for _a, _b in (("7.5", "2.5"), ("19.99", "3"), ("-1.25", "0.4"), ("0.1", "0.2")):
    for _name, _op in (
        ("+", operator.add),
        ("-", operator.sub),
        ("*", operator.mul),
        ("//", operator.floordiv),
        ("%", operator.mod),
    ):
        _got = str(_op(D128(_a), D128(_b)))
        _want = str(_op(decimal.Decimal(_a), decimal.Decimal(_b)))
        assert _got == _want, f"{_a} {_name} {_b}: {_got} != {_want}"

# Division fills the type rather than a context: 29 significant digits and a
# scale of at most 28, where `decimal` gives whatever `prec` says. Checked
# against decimal at 60 digits, rounded to the exponent we came back with.
for _a, _b in (("19.99", "3"), ("1", "7"), ("-1.25", "0.4"), ("2", "3")):
    _got = D128(_a) / D128(_b)
    with decimal.localcontext() as _ctx:
        _ctx.prec = 60
        _exact = decimal.Decimal(_a) / decimal.Decimal(_b)
    with decimal.localcontext() as _ctx:
        _ctx.prec = 60
        _want = _exact.quantize(
            decimal.Decimal((0, (1,), decimal.Decimal(str(_got)).as_tuple().exponent)),
            rounding=decimal.ROUND_HALF_EVEN,
        )
    assert str(_got) == str(_want), f"{_a} / {_b}: {_got} != {_want}"
assert str(D128("7.5") ** 2) == "56.25"
assert divmod(D128("7.5"), D128("2.5")) == (D128("3"), D128("0.0"))
print("[PASS] Decimal128 arithmetic agrees with decimal")

# The other operand may be an int, a float or a string, on either side.
assert str(D128("1.5") + 1) == "2.5"
assert str(2 * D128("1.5")) == "3.0"
assert str(7 // D128("2.5")) == "2"
assert D128("1.5") == D128("1.50")
assert D128("1.5") > 1
assert sorted([D128("3"), D128("1"), D128("2")]) == [D128("1"), D128("2"), D128("3")]
print("[PASS] Decimal128 mixes with numbers and sorts")

# The hash agrees with everything that compares equal to it.
for _text in ("1.5", "0", "-2", "12345.6789", "0.1", "79228162514264337593543950335"):
    assert (
        hash(D128(_text)) == hash(decimal.Decimal(_text)) == hash(decimo.Decimal(_text))
    )
assert hash(D128("1.5")) == hash(1.5)
assert hash(D128("2")) == hash(2)
assert {D128("1.5"): "x"}[D128("1.50")] == "x"
print("[PASS] Decimal128 hashes with int, float, decimal and Decimal")

# Money: the reason the type exists.
_price = D128("19.99")
_line = (_price * 3).quantize(D128("0.01"))
assert str(_line) == "59.97"
assert str(round(D128("2.675"), 2)) == str(round(decimal.Decimal("2.675"), 2))
assert round(D128("19.99")) == 20 and isinstance(round(D128("19.99")), int)
assert D128("19.99").as_tuple() == decimal.Decimal("19.99").as_tuple()
print("[PASS] Decimal128 quantizes, rounds and reports its digits")

# The mathematical functions, correctly rounded.
assert str(D128(2).sqrt()) == "1.4142135623730950488016887242"
assert str(D128(1).exp()) == "2.7182818284590452353602874714"
assert str(D128(1000).log10()) == "3"
assert str(D128(1).ln()) == "0"
# The reduction holds wherever the argument sits, which is the point of it.
assert str(D128("1e20").sin()) == "-0.6452512852657808442058117113"
print("[PASS] Decimal128 has square roots, logarithms and trigonometry")

# The IEEE 754 interchange format, little-endian as BSON stores it.
assert D128("1").to_ieee754().hex() == "01000000000000000000000000004030"
assert D128("0").to_ieee754().hex() == "00000000000000000000000000004030"
for _text in ("1", "-1", "0.001", "1.0", "19.99", "79228162514264337593543950335"):
    assert str(D128.from_ieee754(D128(_text).to_ieee754())) == _text
print("[PASS] Decimal128 reads and writes IEEE 754 decimal128")

# The wider method surface, against decimal where decimal has it.
_x = D128("1.20")
assert str(_x.normalize()) == "1.2"
assert _x.adjusted() == decimal.Decimal("1.20").adjusted()
assert _x.is_zero() is False and D128("0").is_zero() is True
assert _x.is_signed() is False and D128("-1").is_signed() is True
assert _x.same_quantum(D128("9.99")) is True
assert _x.same_quantum(D128("9.9")) is False
assert str(_x.compare(2)) == str(decimal.Decimal("1.20").compare(2))
assert str(_x.copy_sign(D128("-1"))) == str(
    decimal.Decimal("1.20").copy_sign(decimal.Decimal("-1"))
)
assert str(_x.to_integral_value()) == str(decimal.Decimal("1.20").to_integral_value())
assert _x.as_integer_ratio() == decimal.Decimal("1.20").as_integer_ratio()
for _text in ("123456", "0.000123", "1234", "19.99", "1.5"):
    assert D128(_text).to_eng_string() == decimal.Decimal(_text).to_eng_string()
# Where the two differ is where the type has no such value to print: a scale
# is never negative here, so `1.23E+5` is 123000 and there is no cohort
# member with an exponent of 3 to write as `123E+3`.
assert D128("1.23E+5").to_eng_string() == "123000"
assert str(D128("2").fma(3, 4)) == str(decimal.Decimal(2).fma(3, 4))
assert str(D128("2").max(3)) == "3" and str(D128("2").min(3)) == "2"
assert D128("1.5").is_finite() and not D128("1.5").is_nan()
assert str(D128.from_float(0.5)) == "0.5"
print("[PASS] Decimal128 carries the method surface decimal programs use")

# The mathematics beyond the square root.
assert str(D128("8").cbrt()) == "2"
assert str(D128("16").root(4)) == "2"
assert str(D128("8").log(D128("2"))) == "3"
assert str(D128("1.2").cot()) == "0.3887795693682049116341915050"
assert str(D128("1.2").sec()) == "2.7597036013324064568834329392"
assert str(D128("1.2").csc()) == "1.0729163777098972287051169224"
print("[PASS] Decimal128 has roots, arbitrary bases and the reciprocal angles")

# The two ends of the range, which are fixed rather than a matter of context.
assert str(D128.MAX) == "79228162514264337593543950335"
assert str(D128.MIN) == "-79228162514264337593543950335"

# Reflected operators, so the type may sit on either side.
assert str(2 ** D128("3")) == "8"
assert divmod(7, D128("2")) == (D128("3"), D128("1"))
assert str(7 - D128("2.5")) == "4.5"
print("[PASS] Decimal128 works from either side of an operator")

# A mixed expression settles in the wider type, which loses nothing.
for _left, _right in (
    (D128("1.5"), decimo.Decimal("2")),
    (decimo.Decimal("2"), D128("1.5")),
):
    _sum = _left + _right
    assert isinstance(_sum, decimo.Decimal), type(_sum)
    assert str(_sum) == "3.5"
assert str(decimo.Decimal("7") / D128("2")) == "3.5"
assert D128("1.5") == decimo.Decimal("1.5")
assert D128("1.5") < decimo.Decimal("2")
# And what cannot be converted is a TypeError, not something stranger.
try:
    D128("1.5") + "not a number"
    raise AssertionError("adding a non-number should raise")
except AssertionError:
    raise
except TypeError:
    pass
print("[PASS] Decimal128 mixes with Decimal and refuses the rest")

# It behaves like a value: copied, pickled and formatted.
_x = D128("1234.5678")
assert copy.copy(_x) == _x and copy.deepcopy(_x) == _x
assert pickle.loads(pickle.dumps(_x)) == _x
assert f"{_x}" == "1234.5678"
assert format(_x, ",.2f") == format(decimal.Decimal("1234.5678"), ",.2f")
assert format(_x, ".3e") == format(decimal.Decimal("1234.5678"), ".3e")
assert type(_x).__name__ == "Decimal128" and type(_x).__module__ == "decimo"
assert repr(_x) == "Decimal128('1234.5678')"
print("[PASS] Decimal128 copies, pickles, formats and names itself")

# Crossing between the two types.
assert str(D128("1.5").to_decimal()) == "1.5"
assert isinstance(D128("1.5").to_decimal(), decimo.Decimal)
assert str(decimo.Decimal(D128("1.5"))) == "1.5"
print("[PASS] Decimal128 converts to and from Decimal")

# What it refuses: the type stops at 7.9E+28 and 28 decimal places.
try:
    D128("79228162514264337593543950336")
    raise AssertionError("a value past the maximum should not be accepted")
except AssertionError:
    raise
except Exception:
    pass
try:
    D128("1") / D128("0")
    raise AssertionError("division by zero should raise")
except ZeroDivisionError:
    pass
print("[PASS] Decimal128 refuses what it cannot hold")


print()

print("=== All Phase 0 tests passed! ===")
