# ===----------------------------------------------------------------------=== #
# decimo-python
# Mojo bindings for Python, exposing the BigDecimal type and basic operations.
# Because the Mojo-Python interop is still in early stages, this module is
# mainly an experiment to test the capabilities and ergonomics of the bindings,
# and to give me some experience writing Mojo Miji (https://mojo-lang.com/miji).
#
# I followed the official guide for writing a Mojo module for Python:
# https://docs.modular.com/mojo/manual/python/mojo-from-python
#
# Two things about the cost of a call from Python (measured 20260826, add of
# two 9-digit values, in nanoseconds):
#
#   call into Mojo and back        25
#   two `downcast_value_ptr`       44
#   the BigDecimal addition        47
#   wrapping the result            28
#
# The type check was the surprise: it cost as much as the addition. CPython
# already guarantees that `py_self` is an instance of the bound type before it
# ever reaches us, so `py_self` uses `unchecked_downcast_value_ptr`. The right
# operand is not guaranteed, so it is compared against the type of `py_self`
# first, which is about half the price of the checked downcast, and anything
# that is not a decimal goes down the conversion path instead.
# ===----------------------------------------------------------------------=== #

from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder
from std.os import abort

from decimo import BigDecimal


# ===----------------------------------------------------------------------=== #
# PyInit entry point
#
# The dunder names are registered next to the plain ones. Registering them is
# not enough to make `a + b` work: a type built from a spec keeps `__add__` in
# its dictionary but leaves the `nb_add` slot empty, so Python still reports an
# unsupported operand. `decimo/__init__.py` assigns each dunder back onto the
# type at import time, which is what fills the slot. See the comment there.
# ===----------------------------------------------------------------------=== #


@export
def PyInit__decimo() abi("C") -> PythonObject:
    try:
        var m = PythonModuleBuilder("_decimo")
        _ = (
            m.add_type[BigDecimal]("Decimal")
            .def_py_init[bigdecimal_py_init]()
            # Plain names, kept so the type is usable without the slot wiring.
            .def_method[bigdecimal_to_string]("to_string")
            .def_method[bigdecimal_to_repr]("to_repr")
            .def_method[bigdecimal_add]("add")
            .def_method[bigdecimal_sub]("sub")
            .def_method[bigdecimal_mul]("mul")
            .def_method[bigdecimal_div]("div")
            .def_method[bigdecimal_neg]("neg")
            .def_method[bigdecimal_abs]("abs_")
            .def_method[bigdecimal_eq]("eq")
            .def_method[bigdecimal_lt]("lt")
            .def_method[bigdecimal_le]("le")
            # Operator names.
            .def_method[bigdecimal_to_string]("__str__")
            .def_method[bigdecimal_add]("__add__")
            .def_method[bigdecimal_radd]("__radd__")
            .def_method[bigdecimal_sub]("__sub__")
            .def_method[bigdecimal_rsub]("__rsub__")
            .def_method[bigdecimal_mul]("__mul__")
            .def_method[bigdecimal_rmul]("__rmul__")
            .def_method[bigdecimal_div]("__truediv__")
            .def_method[bigdecimal_rdiv]("__rtruediv__")
            .def_method[bigdecimal_neg]("__neg__")
            .def_method[bigdecimal_pos]("__pos__")
            .def_method[bigdecimal_abs]("__abs__")
            .def_method[bigdecimal_bool]("__bool__")
            .def_method[bigdecimal_eq]("__eq__")
            .def_method[bigdecimal_ne]("__ne__")
            .def_method[bigdecimal_lt]("__lt__")
            .def_method[bigdecimal_le]("__le__")
            .def_method[bigdecimal_gt]("__gt__")
            .def_method[bigdecimal_ge]("__ge__")
        )
        return m.finalize()
    except e:
        abort(String("error creating _decimo Python module: ", e))


# ===----------------------------------------------------------------------=== #
# Helper functions
# ===----------------------------------------------------------------------=== #


@always_inline
def is_same_type(a: PythonObject, b: PythonObject) raises -> Bool:
    """Whether two objects have the very same Python type."""
    return Python.type(a) is Python.type(b)


def not_implemented() raises -> PythonObject:
    """Python's `NotImplemented`, so an unsupported operand reads as a normal
    `TypeError` from the operator rather than a parse error from deep inside
    decimo. Only ever reached on the slow path, so the lookup does not matter.
    """
    return Python.import_module("builtins").NotImplemented


def convert_int_subclass(other: PythonObject) raises -> BigDecimal:
    """The tail of the two conversions below: an `int` that is not exactly an
    `int`, which in practice means a `bool`. Kept out of line because the
    common cases are settled by comparing types, and that is much cheaper than
    reaching into `builtins` for `isinstance`.
    """
    var builtins = Python.import_module("builtins")
    if not Bool(builtins.isinstance(other, builtins.int)):
        raise Error("no implicit conversion from this type")
    # `str(True)` is "True", so go through `int()` rather than the text.
    return BigDecimal(String(builtins.int(other)))


def convert_operand(other: PythonObject) raises -> BigDecimal:
    """Convert the right operand of an arithmetic operator, or refuse.

    `decimal.Decimal` allows exactly one implicit conversion in arithmetic,
    from `int`. A `float` is refused on purpose -- mixing binary and decimal
    fractions silently is the mistake the type exists to prevent -- and so is
    a `str`. The caller turns the refusal into `NotImplemented`, which is what
    makes the operator raise an ordinary `TypeError`.
    """
    if Python.type(other) is Python.type(PythonObject(0)):
        return BigDecimal(String(other))
    return convert_int_subclass(other)


def convert_comparand(other: PythonObject) raises -> BigDecimal:
    """Convert the right operand of a comparison, or refuse.

    Comparison is looser than arithmetic, again following `decimal.Decimal`:
    a `float` compares fine, because comparing is not the operation that
    quietly loses the distinction.

    The float goes through its shortest string form, the way the rest of
    decimo converts one. That is not what `decimal.Decimal` does, and it
    shows: `Decimal("0.1") == 0.1` answers True here and False there, because
    the float is not exactly one tenth. The fix belongs in
    `BigDecimal.from_float_scalar()`, not in this layer.
    """
    var other_type = Python.type(other)
    if other_type is Python.type(PythonObject(0)):
        return BigDecimal(String(other))
    if other_type is Python.type(PythonObject(Float64(0))):
        return BigDecimal(String(other))
    return convert_int_subclass(other)


# ===----------------------------------------------------------------------=== #
# Construction and text
# ===----------------------------------------------------------------------=== #


def bigdecimal_py_init(
    out self: BigDecimal, args: PythonObject, kwargs: PythonObject
) raises:
    """Construct a BigDecimal from a single argument (string, int, or float).

    Usage from Python:
        Decimal("3.14")
        Decimal(42)
        Decimal(3.14)   # via str() conversion
    """
    if len(args) != 1:
        raise Error(
            "Decimal() takes exactly 1 argument ("
            + String(len(args))
            + " given)"
        )
    # Convert any Python object to its string representation, then construct.
    # This handles str, int, and float gracefully.
    self = BigDecimal(String(args[0]))


def bigdecimal_to_string(py_self: PythonObject) raises -> PythonObject:
    """Return the decimal as a plain string, e.g. '3.14'."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject(String(self_ptr[]))


def bigdecimal_to_repr(py_self: PythonObject) raises -> PythonObject:
    """Return the repr string, e.g. 'Decimal(\"3.14\")'."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject('Decimal("' + String(self_ptr[]) + '")')


# ===----------------------------------------------------------------------=== #
# Arithmetic
#
# Each of these takes the same shape: trust `self`, and take the fast path for
# `other` only when it is the same type. The reflected forms are only ever
# reached when the left operand is not a decimal, so they always convert.
# ===----------------------------------------------------------------------=== #


def bigdecimal_add(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self + other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result: BigDecimal
    if is_same_type(other, py_self):
        result = self_ptr[] + other.unchecked_downcast_value_ptr[BigDecimal]()[]
    else:
        var converted: BigDecimal
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
        result = self_ptr[] + converted
    return PythonObject(alloc=result^)


def bigdecimal_radd(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return other + self."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    try:
        converted = convert_operand(other)
    except:
        return not_implemented()
    var result = converted + self_ptr[]
    return PythonObject(alloc=result^)


def bigdecimal_sub(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self - other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result: BigDecimal
    if is_same_type(other, py_self):
        result = self_ptr[] - other.unchecked_downcast_value_ptr[BigDecimal]()[]
    else:
        var converted: BigDecimal
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
        result = self_ptr[] - converted
    return PythonObject(alloc=result^)


def bigdecimal_rsub(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return other - self."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    try:
        converted = convert_operand(other)
    except:
        return not_implemented()
    var result = converted - self_ptr[]
    return PythonObject(alloc=result^)


def bigdecimal_mul(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self * other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result: BigDecimal
    if is_same_type(other, py_self):
        result = self_ptr[] * other.unchecked_downcast_value_ptr[BigDecimal]()[]
    else:
        var converted: BigDecimal
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
        result = self_ptr[] * converted
    return PythonObject(alloc=result^)


def bigdecimal_rmul(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return other * self."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    try:
        converted = convert_operand(other)
    except:
        return not_implemented()
    var result = converted * self_ptr[]
    return PythonObject(alloc=result^)


def bigdecimal_div(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self / other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result: BigDecimal
    if is_same_type(other, py_self):
        result = self_ptr[] / other.unchecked_downcast_value_ptr[BigDecimal]()[]
    else:
        var converted: BigDecimal
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
        result = self_ptr[] / converted
    return PythonObject(alloc=result^)


def bigdecimal_rdiv(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return other / self."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    try:
        converted = convert_operand(other)
    except:
        return not_implemented()
    var result = converted / self_ptr[]
    return PythonObject(alloc=result^)


def bigdecimal_neg(py_self: PythonObject) raises -> PythonObject:
    """Return -self."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = -(self_ptr[])
    return PythonObject(alloc=result^)


def bigdecimal_pos(py_self: PythonObject) raises -> PythonObject:
    """Return +self, which is a copy of self."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy()
    return PythonObject(alloc=result^)


def bigdecimal_abs(py_self: PythonObject) raises -> PythonObject:
    """Return abs(self)."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = abs(self_ptr[])
    return PythonObject(alloc=result^)


def bigdecimal_bool(py_self: PythonObject) raises -> PythonObject:
    """Return whether self is non-zero."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject(not self_ptr[].is_zero())


# ===----------------------------------------------------------------------=== #
# Comparison
# ===----------------------------------------------------------------------=== #


def bigdecimal_eq(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self == other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    if is_same_type(other, py_self):
        return PythonObject(
            self_ptr[] == other.unchecked_downcast_value_ptr[BigDecimal]()[]
        )
    var converted: BigDecimal
    try:
        converted = convert_comparand(other)
    except:
        return not_implemented()
    return PythonObject(self_ptr[] == converted)


def bigdecimal_ne(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self != other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    if is_same_type(other, py_self):
        return PythonObject(
            self_ptr[] != other.unchecked_downcast_value_ptr[BigDecimal]()[]
        )
    var converted: BigDecimal
    try:
        converted = convert_comparand(other)
    except:
        return not_implemented()
    return PythonObject(self_ptr[] != converted)


def bigdecimal_lt(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self < other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    if is_same_type(other, py_self):
        return PythonObject(
            self_ptr[] < other.unchecked_downcast_value_ptr[BigDecimal]()[]
        )
    var converted: BigDecimal
    try:
        converted = convert_comparand(other)
    except:
        return not_implemented()
    return PythonObject(self_ptr[] < converted)


def bigdecimal_le(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self <= other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    if is_same_type(other, py_self):
        return PythonObject(
            self_ptr[] <= other.unchecked_downcast_value_ptr[BigDecimal]()[]
        )
    var converted: BigDecimal
    try:
        converted = convert_comparand(other)
    except:
        return not_implemented()
    return PythonObject(self_ptr[] <= converted)


def bigdecimal_gt(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self > other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    if is_same_type(other, py_self):
        return PythonObject(
            self_ptr[] > other.unchecked_downcast_value_ptr[BigDecimal]()[]
        )
    var converted: BigDecimal
    try:
        converted = convert_comparand(other)
    except:
        return not_implemented()
    return PythonObject(self_ptr[] > converted)


def bigdecimal_ge(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self >= other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    if is_same_type(other, py_self):
        return PythonObject(
            self_ptr[] >= other.unchecked_downcast_value_ptr[BigDecimal]()[]
        )
    var converted: BigDecimal
    try:
        converted = convert_comparand(other)
    except:
        return not_implemented()
    return PythonObject(self_ptr[] >= converted)
