"""decimo: Arbitrary-precision decimal arithmetic for Python, powered by Mojo.

Usage:
    from decimo import Decimal

    a = Decimal("1.5")
    b = Decimal("2.3")
    print(a + b)  # 3.8
"""

__version__ = "0.1.0.dev0"
__all__ = ["Decimal", "BigDecimal"]

try:
    from ._decimo import Decimal
except ImportError as _err:
    raise ImportError(
        "decimo requires a compiled Mojo extension (_decimo native module).\n"
        "This package does not yet include pre-built wheels.\n"
        "Build from source:\n"
        "  git clone https://github.com/forfudan/decimo && cd decimo\n"
        "  pixi run buildpy\n"
        "  pip install -e python/\n"
    ) from _err


# --- Operator wiring -------------------------------------------------------
#
# `Decimal` is the Mojo type itself, not a Python class wrapping one. That
# removes about 75 ns per operation, which used to be the largest single cost
# of calling decimo from Python -- more than the arithmetic.
#
# The one thing the Mojo bindings cannot do for us is fill the operator slots.
# A type built from a spec keeps `__add__` and friends in its dictionary, but
# CPython only fills `nb_add` (the slot the `+` operator actually reads) when
# the attribute is *assigned* on the type. So assign each one back onto itself:
# the value does not change, but the assignment makes CPython notice it and
# fill the matching slot. Without this loop, `a + b` reports an unsupported
# operand even though `a.__add__(b)` works.
#
# Once Mojo's `PythonModuleBuilder` grows a way to declare slots directly, this
# loop can go away and nothing else here needs to change.

for _name in (
    "__str__",
    "__add__",
    "__radd__",
    "__sub__",
    "__rsub__",
    "__mul__",
    "__rmul__",
    "__truediv__",
    "__rtruediv__",
    "__neg__",
    "__pos__",
    "__abs__",
    "__bool__",
    "__eq__",
    "__ne__",
    "__lt__",
    "__le__",
    "__gt__",
    "__ge__",
):
    setattr(Decimal, _name, Decimal.__dict__[_name])
del _name

# `__repr__` is the one operator the loop above cannot reach. The bindings
# install their own from Mojo's `Representable`, which prints the Mojo type
# name, so point it at our own text instead.
Decimal.__repr__ = Decimal.to_repr

# A type that defines `__eq__` must not keep an inherited hash based on
# identity: two equal decimals would land in different dictionary buckets.
# The previous Python wrapper was unhashable for the same reason. A real hash
# would have to agree with `int` and `float` the way `decimal.Decimal` does,
# which is a separate piece of work.
Decimal.__hash__ = None

# Also expose as BigDecimal for users who prefer the full name
BigDecimal = Decimal
