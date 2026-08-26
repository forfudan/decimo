# ===----------------------------------------------------------------------=== #
# decimo-python
# Mojo bindings for Python, exposing the BigDecimal type as `decimo.Decimal`.
#
# The aim is a drop-in replacement for `decimal.Decimal`: the same names, the
# same coercion rules, the same results. Anything this module cannot yet do,
# it should refuse rather than answer differently.
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

from std.ffi import _Global
from std.python import Python, PythonObject
from std.python._cpython import PyObjectPtr
from std.python.bindings import (
    ExceptionType,
    PythonModuleBuilder,
    _set_python_error,
)
from std.os import abort

from decimo import BigDecimal, RoundingMode


# ===----------------------------------------------------------------------=== #
# The working precision
#
# `decimal` keeps its precision in a context object, and every operator reads
# it. Mojo has no global variables, so `BigDecimal`'s own operators round to a
# compile-time constant of 28 instead. `std.ffi._Global` is the way around
# that: it hands out a pointer to one heap cell that outlives every call, which
# is exactly a global by another name.
#
# So the precision lives here, and `decimo/__init__.py` puts a `Context` in
# front of it that looks like the one in `decimal`. Reading it costs 4.8 ns,
# measured -- a hash lookup on the name -- against roughly 110 ns for the
# cheapest operation, so it is paid once per operation and not thought about
# again.
# ===----------------------------------------------------------------------=== #


def _initial_precision() -> Int:
    return 28


comptime _PRECISION = _Global["decimo_python_precision", _initial_precision]


@always_inline
def precision() raises -> Int:
    """The working precision, in significant digits."""
    return _PRECISION.get_or_create_ptr()[]


def get_precision() raises -> PythonObject:
    """Read the working precision. Called by `Context.prec`."""
    return PythonObject(precision())


def set_precision(value: PythonObject) raises -> PythonObject:
    """Set the working precision. Called by `Context.prec`."""
    var digits = Int(py=value)
    if digits < 1:
        raise Error("precision must be at least 1")
    _PRECISION.get_or_create_ptr()[] = digits
    return PythonObject(None)


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

        m.def_function[get_precision]("get_precision")
        m.def_function[set_precision]("set_precision")

        _ = (
            m.add_type[BigDecimal]("Decimal")
            .def_py_init[bigdecimal_py_init]()
            # --- text ---------------------------------------------------
            .def_method[bigdecimal_to_string]("to_string")
            .def_method[bigdecimal_to_repr]("to_repr")
            .def_method[bigdecimal_to_eng_string]("to_eng_string")
            .def_method[bigdecimal_to_string]("__str__")
            # --- arithmetic ---------------------------------------------
            .def_method[bigdecimal_add]("__add__")
            .def_method[bigdecimal_radd]("__radd__")
            .def_method[bigdecimal_sub]("__sub__")
            .def_method[bigdecimal_rsub]("__rsub__")
            .def_method[bigdecimal_mul]("__mul__")
            .def_method[bigdecimal_rmul]("__rmul__")
            .def_method[bigdecimal_div]("__truediv__")
            .def_method[bigdecimal_rdiv]("__rtruediv__")
            .def_method[bigdecimal_floordiv]("__floordiv__")
            .def_method[bigdecimal_rfloordiv]("__rfloordiv__")
            .def_method[bigdecimal_mod]("__mod__")
            .def_method[bigdecimal_rmod]("__rmod__")
            .def_method[bigdecimal_divmod]("__divmod__")
            .def_method[bigdecimal_rdivmod]("__rdivmod__")
            .def_method[bigdecimal_pow]("__pow__")
            .def_method[bigdecimal_rpow]("__rpow__")
            .def_method[bigdecimal_neg]("__neg__")
            .def_method[bigdecimal_pos]("__pos__")
            .def_method[bigdecimal_abs]("__abs__")
            .def_method[bigdecimal_bool]("__bool__")
            # --- conversion ---------------------------------------------
            .def_method[bigdecimal_int]("__int__")
            .def_method[bigdecimal_float]("__float__")
            .def_method[bigdecimal_trunc]("__trunc__")
            .def_method[bigdecimal_floor]("__floor__")
            .def_method[bigdecimal_ceil]("__ceil__")
            .def_py_method[bigdecimal_round]("__round__")
            .def_method[bigdecimal_components]("_components")
            # --- comparison ---------------------------------------------
            .def_method[bigdecimal_eq]("__eq__")
            .def_method[bigdecimal_ne]("__ne__")
            .def_method[bigdecimal_lt]("__lt__")
            .def_method[bigdecimal_le]("__le__")
            .def_method[bigdecimal_gt]("__gt__")
            .def_method[bigdecimal_ge]("__ge__")
            .def_method[bigdecimal_compare]("compare")
            .def_method[bigdecimal_max]("max")
            .def_method[bigdecimal_min]("min")
            # --- the `decimal.Decimal` method surface -------------------
            .def_py_method[bigdecimal_quantize]("quantize")
            .def_py_method[bigdecimal_sqrt]("sqrt")
            .def_py_method[bigdecimal_exp]("exp")
            .def_py_method[bigdecimal_ln]("ln")
            .def_py_method[bigdecimal_log10]("log10")
            .def_py_method[bigdecimal_to_integral]("to_integral_value")
            .def_py_method[bigdecimal_to_integral]("to_integral")
            .def_method[bigdecimal_fma]("fma")
            .def_method[bigdecimal_normalize]("normalize")
            .def_method[bigdecimal_adjusted]("adjusted")
            .def_method[bigdecimal_scaleb]("scaleb")
            .def_method[bigdecimal_copy_abs]("copy_abs")
            .def_method[bigdecimal_copy_negate]("copy_negate")
            .def_method[bigdecimal_copy_sign]("copy_sign")
            .def_method[bigdecimal_same_quantum]("same_quantum")
            .def_method[bigdecimal_is_zero]("is_zero")
            .def_method[bigdecimal_is_signed]("is_signed")
            .def_method[bigdecimal_is_finite]("is_finite")
            .def_method[bigdecimal_is_nan]("is_nan")
            .def_method[bigdecimal_is_infinite]("is_infinite")
            .def_method[bigdecimal_is_canonical]("is_canonical")
            .def_method[bigdecimal_canonical]("canonical")
            .def_method[bigdecimal_conjugate]("conjugate")
            .def_method[bigdecimal_radix]("radix")
            .def_method[bigdecimal_copy]("copy")
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


def raise_as[
    exception: StaticString
](message: StaticString) raises -> PythonObject:
    """Fail with a particular Python exception type.

    The binding wrapper turns any Mojo `Error` that escapes into a plain
    `Exception`, which is no use to a caller writing
    `except ZeroDivisionError`. So set the error indicator here and hand
    CPython a null pointer, which is exactly what a failing C function does.
    The wrapper only overwrites the indicator when an error escapes, and here
    none does.

    The message is written out rather than taken from the Mojo error, whose
    text is a whole traceback with terminal colours in it.
    """
    _set_python_error(Error(message), ExceptionType(exception))
    return PythonObject(from_owned=PyObjectPtr())


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


def from_python_float(other: PythonObject) raises -> BigDecimal:
    """Read a Python float exactly, the way `decimal.Decimal(float)` does.

    The text detour is lossless: `repr()` of a float is by definition the
    shortest string that parses back to the same double, so the value handed
    to `from_float_scalar()` is bit-for-bit the one Python holds. What that
    then produces is the number the float really is --
    `Decimal(0.1)` is the 55-digit value, not `0.1`.
    """
    return BigDecimal.from_float_scalar(Float64(String(other)))


def convert_comparand(other: PythonObject) raises -> BigDecimal:
    """Convert the right operand of a comparison, or refuse.

    Comparison is looser than arithmetic, again following `decimal.Decimal`:
    a `float` compares fine, because comparing is not the operation that
    quietly loses the distinction.

    The float is converted exactly, so `Decimal("0.1") == 0.1` is False --
    the float is not one tenth, and saying so is the whole point of a decimal
    type.
    """
    var other_type = Python.type(other)
    if other_type is Python.type(PythonObject(0)):
        return BigDecimal(String(other))
    if other_type is Python.type(PythonObject(Float64(0))):
        return from_python_float(other)
    return convert_int_subclass(other)


def as_decimal(
    py_self: PythonObject, py_value: PythonObject
) raises -> BigDecimal:
    """The operand of a named method, which is a decimal or an int.

    Named methods (`quantize`, `compare`, `fma`, ...) accept the same operands
    as the operators do, but they raise rather than returning `NotImplemented`,
    because there is no reflected form for Python to fall back to. `py_self` is
    only there to name the type: comparing against it is how the fast path
    recognises another decimal without a checked downcast.
    """
    if is_same_type(py_value, py_self):
        return py_value.unchecked_downcast_value_ptr[BigDecimal]()[].copy()
    return convert_operand(py_value)


def rounding_from(py_mode: PythonObject) raises -> RoundingMode:
    """Turn `decimal`'s rounding-mode string into a `RoundingMode`.

    `None` means "use the context default", which for us is always
    ROUND_HALF_EVEN -- the same default `decimal` starts with.
    """
    if py_mode is PythonObject(None):
        return RoundingMode.ROUND_HALF_EVEN
    var name = String(py_mode)
    if name == "ROUND_HALF_EVEN":
        return RoundingMode.ROUND_HALF_EVEN
    if name == "ROUND_HALF_UP":
        return RoundingMode.ROUND_HALF_UP
    if name == "ROUND_HALF_DOWN":
        return RoundingMode.ROUND_HALF_DOWN
    if name == "ROUND_DOWN":
        return RoundingMode.ROUND_DOWN
    if name == "ROUND_UP":
        return RoundingMode.ROUND_UP
    if name == "ROUND_CEILING":
        return RoundingMode.ROUND_CEILING
    if name == "ROUND_FLOOR":
        return RoundingMode.ROUND_FLOOR
    raise Error(String("unknown rounding mode: ", name))


@always_inline
def arg_or_none(args: PythonObject, index: Int) raises -> PythonObject:
    """The positional argument at `index`, or `None` if it was not given."""
    if len(args) > index:
        return args[index]
    return PythonObject(None)


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
        Decimal(3.14)   # read exactly, like decimal.Decimal
        Decimal()       # zero
    """
    if len(args) == 0:
        self = BigDecimal.zero()
        return
    if len(args) != 1:
        raise Error(
            "Decimal() takes at most 1 argument ("
            + String(len(args))
            + " given)"
        )
    # A float is read exactly, like `decimal.Decimal(float)`. Everything else
    # -- str, int, another Decimal -- goes through its string form.
    if Python.type(args[0]) is Python.type(PythonObject(Float64(0))):
        self = from_python_float(args[0])
        return
    # The Mojo error carries a whole traceback with terminal colours in it,
    # which is not what a Python programmer should see from a constructor.
    try:
        self = BigDecimal(String(args[0]))
    except:
        raise Error(String("could not parse as a decimal: ", args[0]))


def bigdecimal_to_string(py_self: PythonObject) raises -> PythonObject:
    """Return the decimal as a plain string, e.g. '3.14'."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject(String(self_ptr[]))


def bigdecimal_to_repr(py_self: PythonObject) raises -> PythonObject:
    """Return the repr string: `Decimal('3.14')`.

    Single quotes, because that is what `decimal.Decimal` prints and a repr
    turns up in doctests, logs and error messages where the difference shows.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject("Decimal('" + String(self_ptr[]) + "')")


def bigdecimal_to_eng_string(py_self: PythonObject) raises -> PythonObject:
    """Return the value in engineering notation."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject(self_ptr[].to_eng_string())


def bigdecimal_components(py_self: PythonObject) raises -> PythonObject:
    """Return `(sign, coefficient_digits, exponent)` as plain Python values.

    The building block for everything `decimo/__init__.py` does in Python:
    `as_tuple()`, `as_integer_ratio()` and `__hash__` are all a few lines once
    they have the three parts. The coefficient comes back as a string rather
    than a tuple of digits because Python turns it into an `int` in one step,
    which is what two of those three want.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var parts = self_ptr[].as_tuple()
    var text = String(capacity=len(parts[1]) + 1)
    for digit in parts[1]:
        text += String(digit)
    return Python.tuple(
        PythonObject(parts[0]), PythonObject(text), PythonObject(parts[2])
    )


# ===----------------------------------------------------------------------=== #
# Arithmetic
#
# Each of these takes the same shape: trust `self`, and take the fast path for
# `other` only when it is the same type. The reflected forms are only ever
# reached when the left operand is not a decimal, so they always convert.
#
# `+`, `-`, `*`, `/` and `**` round to the context precision, which is what
# `decimal` does. `//`, `%` and `divmod` do not: they are exact by definition.
# ===----------------------------------------------------------------------=== #


def bigdecimal_add(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self + other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var digits = precision()
    var result: BigDecimal
    if is_same_type(other, py_self):
        result = self_ptr[].add(
            other.unchecked_downcast_value_ptr[BigDecimal]()[], digits
        )
    else:
        var converted: BigDecimal
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
        result = self_ptr[].add(converted, digits)
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
    var result = converted.add(self_ptr[], precision())
    return PythonObject(alloc=result^)


def bigdecimal_sub(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self - other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var digits = precision()
    var result: BigDecimal
    if is_same_type(other, py_self):
        result = self_ptr[].subtract(
            other.unchecked_downcast_value_ptr[BigDecimal]()[], digits
        )
    else:
        var converted: BigDecimal
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
        result = self_ptr[].subtract(converted, digits)
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
    var result = converted.subtract(self_ptr[], precision())
    return PythonObject(alloc=result^)


def bigdecimal_mul(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self * other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var digits = precision()
    var result: BigDecimal
    if is_same_type(other, py_self):
        result = self_ptr[].multiply(
            other.unchecked_downcast_value_ptr[BigDecimal]()[], digits
        )
    else:
        var converted: BigDecimal
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
        result = self_ptr[].multiply(converted, digits)
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
    var result = converted.multiply(self_ptr[], precision())
    return PythonObject(alloc=result^)


def bigdecimal_div(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self / other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var digits = precision()
    var result: BigDecimal
    if is_same_type(other, py_self):
        try:
            result = self_ptr[].true_divide(
                other.unchecked_downcast_value_ptr[BigDecimal]()[], digits
            )
        except:
            return raise_as["PyExc_ZeroDivisionError"]("division by zero")
    else:
        var converted: BigDecimal
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
        try:
            result = self_ptr[].true_divide(converted, digits)
        except:
            return raise_as["PyExc_ZeroDivisionError"]("division by zero")
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
    var result: BigDecimal
    try:
        result = converted.true_divide(self_ptr[], precision())
    except:
        return raise_as["PyExc_ZeroDivisionError"]("division by zero")
    return PythonObject(alloc=result^)


def bigdecimal_floordiv(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self // other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    if is_same_type(other, py_self):
        converted = other.unchecked_downcast_value_ptr[BigDecimal]()[].copy()
    else:
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
    var result: BigDecimal
    try:
        result = self_ptr[] // converted
    except:
        return raise_as["PyExc_ZeroDivisionError"]("division by zero")
    return PythonObject(alloc=result^)


def bigdecimal_rfloordiv(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return other // self."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    try:
        converted = convert_operand(other)
    except:
        return not_implemented()
    var result: BigDecimal
    try:
        result = converted // self_ptr[]
    except:
        return raise_as["PyExc_ZeroDivisionError"]("division by zero")
    return PythonObject(alloc=result^)


def bigdecimal_mod(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self % other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    if is_same_type(other, py_self):
        converted = other.unchecked_downcast_value_ptr[BigDecimal]()[].copy()
    else:
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
    var result: BigDecimal
    try:
        result = self_ptr[] % converted
    except:
        return raise_as["PyExc_ZeroDivisionError"]("division by zero")
    return PythonObject(alloc=result^)


def bigdecimal_rmod(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return other % self."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    try:
        converted = convert_operand(other)
    except:
        return not_implemented()
    var result: BigDecimal
    try:
        result = converted % self_ptr[]
    except:
        return raise_as["PyExc_ZeroDivisionError"]("division by zero")
    return PythonObject(alloc=result^)


def bigdecimal_divmod(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return divmod(self, other)."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    if is_same_type(other, py_self):
        converted = other.unchecked_downcast_value_ptr[BigDecimal]()[].copy()
    else:
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
    var pair: Tuple[BigDecimal, BigDecimal]
    try:
        pair = self_ptr[].__divmod__(converted)
    except:
        return raise_as["PyExc_ZeroDivisionError"]("division by zero")
    return Python.tuple(
        PythonObject(alloc=pair[0].copy()), PythonObject(alloc=pair[1].copy())
    )


def bigdecimal_rdivmod(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return divmod(other, self)."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    try:
        converted = convert_operand(other)
    except:
        return not_implemented()
    var pair: Tuple[BigDecimal, BigDecimal]
    try:
        pair = converted.__divmod__(self_ptr[])
    except:
        return raise_as["PyExc_ZeroDivisionError"]("division by zero")
    return Python.tuple(
        PythonObject(alloc=pair[0].copy()), PythonObject(alloc=pair[1].copy())
    )


def bigdecimal_pow(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self ** other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    if is_same_type(other, py_self):
        converted = other.unchecked_downcast_value_ptr[BigDecimal]()[].copy()
    else:
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
    var result = self_ptr[].power(converted, precision())
    return PythonObject(alloc=result^)


def bigdecimal_rpow(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return other ** self."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    try:
        converted = convert_operand(other)
    except:
        return not_implemented()
    var result = converted.power(self_ptr[], precision())
    return PythonObject(alloc=result^)


def bigdecimal_neg(py_self: PythonObject) raises -> PythonObject:
    """Return -self, rounded to the context precision.

    Unary minus is an operation like any other in `decimal`, so it rounds.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = (-(self_ptr[])).round_to_precision(precision())
    return PythonObject(alloc=result^)


def bigdecimal_pos(py_self: PythonObject) raises -> PythonObject:
    """Return +self, rounded to the context precision.

    This is not a no-op, and programs lean on that: `+value` is the usual way
    to bring a value computed at a wider working precision back to the one the
    context asks for. `decimal` behaves the same way.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].round_to_precision(precision())
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


def bigdecimal_copy(py_self: PythonObject) raises -> PythonObject:
    """Return a copy of self. Backs `copy.copy()` and `copy.deepcopy()`."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy()
    return PythonObject(alloc=result^)


# ===----------------------------------------------------------------------=== #
# Conversion to the built-in numeric types
# ===----------------------------------------------------------------------=== #


def bigdecimal_int(py_self: PythonObject) raises -> PythonObject:
    """Return int(self), truncating towards zero.

    Built from the text rather than `BigDecimal.__int__`, which goes through a
    64-bit `Int` and so cannot carry a value with more than nineteen digits.
    Python's `int` has no such limit, and neither does `decimal`.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var truncated = self_ptr[].truncate()
    var builtins = Python.import_module("builtins")
    return builtins.int(PythonObject(truncated.to_string(force_plain=True)))


def bigdecimal_float(py_self: PythonObject) raises -> PythonObject:
    """Return float(self).

    Also built from the text: `float(str)` in CPython is correctly rounded, and
    it accepts any number of digits, where `BigDecimal.__float__` currently
    does not.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var builtins = Python.import_module("builtins")
    return builtins.float(PythonObject(String(self_ptr[])))


def bigdecimal_trunc(py_self: PythonObject) raises -> PythonObject:
    """Return math.trunc(self): the integer part, towards zero."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var truncated = self_ptr[].truncate()
    var builtins = Python.import_module("builtins")
    return builtins.int(PythonObject(truncated.to_string(force_plain=True)))


def bigdecimal_floor(py_self: PythonObject) raises -> PythonObject:
    """Return math.floor(self)."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var value = self_ptr[].__floor__()
    var builtins = Python.import_module("builtins")
    return builtins.int(PythonObject(value.to_string(force_plain=True)))


def bigdecimal_ceil(py_self: PythonObject) raises -> PythonObject:
    """Return math.ceil(self)."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var value = self_ptr[].__ceil__()
    var builtins = Python.import_module("builtins")
    return builtins.int(PythonObject(value.to_string(force_plain=True)))


def bigdecimal_round(
    mut py_self: PythonObject, mut args: PythonObject
) raises -> PythonObject:
    """Return round(self) or round(self, ndigits).

    With no argument Python expects an `int` back, and with one it expects the
    same type as the input -- which is what `decimal` does too.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    if len(args) == 0 or args[0] is PythonObject(None):
        var value = self_ptr[].round(0, RoundingMode.ROUND_HALF_EVEN)
        var builtins = Python.import_module("builtins")
        return builtins.int(PythonObject(value.to_string(force_plain=True)))
    var result = self_ptr[].round(Int(py=args[0]), RoundingMode.ROUND_HALF_EVEN)
    return PythonObject(alloc=result^)


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


def bigdecimal_compare(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return -1, 0 or 1 as a Decimal, like `decimal.Decimal.compare`."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted = as_decimal(py_self, other)
    var result = BigDecimal(Int(self_ptr[].compare(converted)))
    return PythonObject(alloc=result^)


def bigdecimal_max(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return the larger of self and other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].max(as_decimal(py_self, other))
    return PythonObject(alloc=result^)


def bigdecimal_min(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return the smaller of self and other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].min(as_decimal(py_self, other))
    return PythonObject(alloc=result^)


# ===----------------------------------------------------------------------=== #
# The rest of the `decimal.Decimal` method surface
#
# `decimal` gives most of these an optional trailing `context` argument. We
# accept it positionally and ignore it: there is one context here, and it is
# the one the value was going to use anyway.
# ===----------------------------------------------------------------------=== #


def bigdecimal_quantize(
    mut py_self: PythonObject, mut args: PythonObject
) raises -> PythonObject:
    """Return self rounded to the scale of `exp`."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    if len(args) == 0:
        raise Error("quantize() takes at least 1 argument (0 given)")
    var template = as_decimal(py_self, args[0])
    var mode = rounding_from(arg_or_none(args, 1))
    var result = self_ptr[].quantize(template, mode)
    return PythonObject(alloc=result^)


def bigdecimal_sqrt(
    mut py_self: PythonObject, mut args: PythonObject
) raises -> PythonObject:
    """Return the square root of self, to the context precision."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result: BigDecimal
    try:
        result = self_ptr[].sqrt(precision())
    except:
        return raise_as["PyExc_ValueError"]("square root of a negative value")
    return PythonObject(alloc=result^)


def bigdecimal_exp(
    mut py_self: PythonObject, mut args: PythonObject
) raises -> PythonObject:
    """Return e ** self, to the context precision."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result: BigDecimal
    try:
        result = self_ptr[].exp(precision())
    except:
        return raise_as["PyExc_ValueError"]("exp() is undefined for this value")
    return PythonObject(alloc=result^)


def bigdecimal_ln(
    mut py_self: PythonObject, mut args: PythonObject
) raises -> PythonObject:
    """Return the natural logarithm of self, to the context precision."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result: BigDecimal
    try:
        result = self_ptr[].ln(precision())
    except:
        return raise_as["PyExc_ValueError"]("ln() needs a positive value")
    return PythonObject(alloc=result^)


def bigdecimal_log10(
    mut py_self: PythonObject, mut args: PythonObject
) raises -> PythonObject:
    """Return the base-10 logarithm of self, to the context precision."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result: BigDecimal
    try:
        result = self_ptr[].log10(precision())
    except:
        return raise_as["PyExc_ValueError"]("log10() needs a positive value")
    return PythonObject(alloc=result^)


def bigdecimal_to_integral(
    mut py_self: PythonObject, mut args: PythonObject
) raises -> PythonObject:
    """Return self rounded to an integer, as a Decimal."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var mode = rounding_from(arg_or_none(args, 0))
    var result = self_ptr[].round(0, mode)
    return PythonObject(alloc=result^)


def bigdecimal_fma(
    py_self: PythonObject, other: PythonObject, third: PythonObject
) raises -> PythonObject:
    """Return self * other + third, with no rounding in between."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].fma(
        as_decimal(py_self, other), as_decimal(py_self, third)
    )
    return PythonObject(alloc=result^)


def bigdecimal_normalize(py_self: PythonObject) raises -> PythonObject:
    """Return self with trailing zeros of the coefficient removed."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].normalize()
    return PythonObject(alloc=result^)


def bigdecimal_adjusted(py_self: PythonObject) raises -> PythonObject:
    """Return the adjusted exponent: the exponent of the leading digit."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject(self_ptr[].adjusted())


def bigdecimal_scaleb(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self * 10 ** other, by moving the exponent."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var builtins = Python.import_module("builtins")
    var result = self_ptr[].scaleb(Int(py=builtins.int(other)))
    return PythonObject(alloc=result^)


def bigdecimal_copy_abs(py_self: PythonObject) raises -> PythonObject:
    """Return self with the sign cleared, without rounding."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy_abs()
    return PythonObject(alloc=result^)


def bigdecimal_copy_negate(py_self: PythonObject) raises -> PythonObject:
    """Return self with the sign flipped, without rounding."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy_negate()
    return PythonObject(alloc=result^)


def bigdecimal_copy_sign(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self with the sign of other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy_sign(as_decimal(py_self, other))
    return PythonObject(alloc=result^)


def bigdecimal_same_quantum(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return whether self and other have the same exponent."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject(self_ptr[].same_quantum(as_decimal(py_self, other)))


def bigdecimal_is_zero(py_self: PythonObject) raises -> PythonObject:
    """Return whether self is zero."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject(self_ptr[].is_zero())


def bigdecimal_is_signed(py_self: PythonObject) raises -> PythonObject:
    """Return whether the sign bit is set, negative zero included."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject(self_ptr[].is_negative())


def bigdecimal_is_finite(py_self: PythonObject) raises -> PythonObject:
    """Always True: decimo has no infinities or NaNs."""
    return PythonObject(True)


def bigdecimal_is_nan(py_self: PythonObject) raises -> PythonObject:
    """Always False: decimo has no NaNs."""
    return PythonObject(False)


def bigdecimal_is_infinite(py_self: PythonObject) raises -> PythonObject:
    """Always False: decimo has no infinities."""
    return PythonObject(False)


def bigdecimal_is_canonical(py_self: PythonObject) raises -> PythonObject:
    """Always True: every decimo value is in its canonical form."""
    return PythonObject(True)


def bigdecimal_canonical(py_self: PythonObject) raises -> PythonObject:
    """Return self, which is already canonical."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy()
    return PythonObject(alloc=result^)


def bigdecimal_conjugate(py_self: PythonObject) raises -> PythonObject:
    """Return self. Present because `decimal` has it, for the numeric tower."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy()
    return PythonObject(alloc=result^)


def bigdecimal_radix(py_self: PythonObject) raises -> PythonObject:
    """Return 10, the base this type works in."""
    var result = BigDecimal(10)
    return PythonObject(alloc=result^)
