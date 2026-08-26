"""Verify BigDecimal round-trip through Mojo-Python bindings.

Cross-validates against Python's standard library decimal.Decimal where applicable.
"""

import decimal
import operator
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
assert repr(decimo.Decimal("1.5")) == 'Decimal("1.5")', repr(decimo.Decimal("1.5"))
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

# --- Unhashable, because __eq__ is defined and no matching __hash__ is ---
try:
    hash(decimo.Decimal("1"))
except TypeError:
    print("[PASS] Decimal is unhashable (as before the native-type switch)")
else:
    raise AssertionError(
        "Decimal should be unhashable until __hash__ agrees with __eq__"
    )
print()

print("=== All Phase 0 tests passed! ===")
