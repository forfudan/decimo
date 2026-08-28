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
from std.python._cpython import (
    PyObject,
    PyObjectPtr,
    Py_ssize_t,
    PyType_Slot,
    PyTypeObject,
    PyTypeObjectPtr,
    _fn_ptr_as_opaque,
)
from std.ffi import c_int
from std.python.bindings import (
    ExceptionType,
    PyMojoObject,
    PythonModuleBuilder,
    _set_python_error,
    lookup_py_type_object,
    raise_python_exception,
)
from std.python.python_object import (
    _unsafe_alloc,
    _unsafe_alloc_init,
    _unsafe_init,
)
from std.os import abort

from decimo import BigDecimal, RoundingMode
from decimo.biguint.biguint import BigUInt
from decimo.bigint.bigint import BigInt
import decimo.bigdecimal.spec as bigdecimal_spec
import decimo.bigdecimal.comparison as bigdecimal_comparison


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


struct _State(Defaultable, Movable):
    """The two things every operation needs, in one cell.

    Reaching a `_Global` costs about 14 ns, because the runtime hashes its
    name. Two of them per operation was 28 ns of a 139 ns addition, so both
    live here and one read serves both.

    `decimal_type` is the `PyTypeObject*` that a result is allocated against.
    The bindings will find it for you, but `lookup_py_type_object` re-reads
    its own global and then looks the type up in a dictionary keyed by the
    Mojo type's fully qualified *name* -- a string hash, per result. The
    pointer never changes once the module is imported, so it is found once and
    kept.
    """

    var precision: Int
    var rounding: RoundingMode
    """The context rounding mode, applied wherever an operation rounds."""
    var decimal_type: PyTypeObjectPtr
    var free_list: InlineArray[PyObjectPtr, FREE_LIST_SIZE]
    """Decimal objects that have been released and can be filled in again."""
    var free_count: Int

    def __init__(out self):
        self.precision = 28
        self.rounding = RoundingMode.ROUND_HALF_EVEN
        self.decimal_type = PyTypeObjectPtr()
        self.free_list = InlineArray[PyObjectPtr, FREE_LIST_SIZE](
            uninitialized=True
        )
        self.free_count = 0


comptime FREE_LIST_SIZE = 64
"""How many spent decimal objects to keep for reuse.

Every operation that returns a decimal allocates one `PyObject` and, a moment
later, some other decimal is released. CPython's own `_decimal` keeps a free
list for exactly this reason. Sixty-four is what CPython uses, and it is
enough: an expression only ever holds a handful of temporaries at once.
"""


def _new_state() -> _State:
    return _State()


comptime _STATE = _Global["decimo_python_state", _new_state]


@always_inline
def state() raises -> Pointer[_State, MutUntrackedOrigin]:
    """The module's mutable state. One runtime lookup."""
    return _STATE.get_or_create_ptr()


@always_inline
def decimal_type_ptr(mut cell: _State) raises -> PyTypeObjectPtr:
    """The type object results are allocated against, found once and kept."""
    if not cell.decimal_type:
        cell.decimal_type = lookup_py_type_object[
            BigDecimal
        ]()._obj_ptr.bitcast[PyTypeObject]()
    return cell.decimal_type


@always_inline
def new_decimal(mut cell: _State, var value: BigDecimal) raises -> PythonObject:
    """Wrap a result, reusing a spent object when there is one.

    The allocator was about 9 ns of a 40 ns operation, and every operation
    that makes a decimal is usually releasing one at about the same time. So
    `decimal_dealloc()` keeps the memory instead of returning it and this
    takes it back: the header is already the right type and the right size,
    and all that is needed is to put the reference count back to one.
    """
    if cell.free_count > 0:
        cell.free_count -= 1
        var reused = cell.free_list[cell.free_count]
        # The object reached `tp_dealloc` with a count of zero. Nothing else
        # refers to it, and its type pointer was never cleared.
        reused.bitcast[PyObject]().value()[].object_ref_count = 1
        _unsafe_init(reused, value^)
        return PythonObject(from_owned=reused)

    return _unsafe_alloc_init(decimal_type_ptr(cell), value^)


def decimal_dealloc(py_self: PyObjectPtr) abi("C"):
    """`tp_dealloc`: keep the memory rather than hand it back.

    Replaces the wrapper the bindings install, which frees immediately. The
    Mojo value is destroyed either way; the difference is whether the
    `PyObject` around it goes back to the allocator or onto the free list.
    """
    try:
        ref self = py_self.bitcast[PyMojoObject[BigDecimal]]().value()[]
        if self.is_initialized:
            Pointer(to=self.mojo_value).unsafe_deinit_pointee()
            self.is_initialized = False

        ref cell = state()[]
        if cell.free_count < FREE_LIST_SIZE:
            cell.free_list[cell.free_count] = py_self
            cell.free_count += 1
            return
    except:
        pass

    ref cpython = Python().cpython()
    cpython.PyObject_Free(py_self.bitcast[NoneType]())


@always_inline
def precision() raises -> Int:
    """The working precision, in significant digits."""
    return _STATE.get_or_create_ptr()[].precision


def get_precision() raises -> PythonObject:
    """Read the working precision. Called by `Context.prec`."""
    return PythonObject(precision())


def set_precision(value: PythonObject) raises -> PythonObject:
    """Set the working precision. Called by `Context.prec`."""
    var digits = Int(py=value)
    if digits < 1:
        raise Error("precision must be at least 1")
    _STATE.get_or_create_ptr()[].precision = digits
    return PythonObject(None)


def module_pi() raises -> PythonObject:
    """`pi()`: the constant to the context precision.

    `decimal` has no pi at all -- its documentation gives a recipe to write
    one -- so this is decimo's own. The Mojo side computes it by Chudnovsky
    with binary splitting, which is why a thousand digits costs milliseconds.
    """
    ref cell = state()[]
    return new_decimal(cell, BigDecimal.pi(cell.precision))


def module_e() raises -> PythonObject:
    """`e()`: the constant to the context precision."""
    ref cell = state()[]
    return new_decimal(cell, BigDecimal.e(cell.precision))


def get_rounding() raises -> PythonObject:
    """Read the context rounding mode as `decimal`'s string. Called by
    `Context.rounding`."""
    return PythonObject(rounding_name(_STATE.get_or_create_ptr()[].rounding))


def set_rounding(value: PythonObject) raises -> PythonObject:
    """Set the context rounding mode from `decimal`'s string. Called by
    `Context.rounding`."""
    _STATE.get_or_create_ptr()[].rounding = rounding_from(value)
    return PythonObject(None)


def rounding_name(mode: RoundingMode) -> String:
    """The `decimal` constant name of a rounding mode."""
    if mode == RoundingMode.ROUND_HALF_EVEN:
        return "ROUND_HALF_EVEN"
    if mode == RoundingMode.ROUND_HALF_UP:
        return "ROUND_HALF_UP"
    if mode == RoundingMode.ROUND_HALF_DOWN:
        return "ROUND_HALF_DOWN"
    if mode == RoundingMode.ROUND_DOWN:
        return "ROUND_DOWN"
    if mode == RoundingMode.ROUND_UP:
        return "ROUND_UP"
    if mode == RoundingMode.ROUND_CEILING:
        return "ROUND_CEILING"
    return "ROUND_FLOOR"


@always_inline
def round_to_context(var value: BigDecimal) raises -> BigDecimal:
    """Round a value to the context precision with the context rounding.

    What `+x` does, and what every operation does to its result.
    """
    ref cell = state()[]
    value.round_to_precision_inplace(
        precision=cell.precision,
        rounding_mode=cell.rounding,
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return value^


comptime DIRECTED_GUARD_DIGITS = 9
"""Extra digits carried by `**` under a rounding mode other than HALF_EVEN.

`decimal` applies the context mode to `**` and ignores it for `sqrt`, `exp`,
`ln` and `log10`, which are always half to even; decimo follows it in both.
Those four therefore ask the library for exactly what it delivers, and only
`**` needs this: the value is computed nine digits wider and rounded once
more with the mode. That last digit is wrong when the true value lies within
`10^-9` relative of a rounding boundary. Arithmetic (`+ - * /`, `quantize`,
`%`) does not go through this -- it rounds exactly under every mode.
"""


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
        m.def_function[module_pi]("pi")
        m.def_function[module_e]("e")
        m.def_function[get_rounding]("get_rounding")
        m.def_function[set_rounding]("set_rounding")

        ref decimal_builder = m.add_type[BigDecimal]("Decimal")

        # `+`, `-`, `*` and `/` are real C slots rather than dictionary
        # entries. See the note above `slot_add` for why that is worth doing.
        decimal_builder._insert_slot(
            PyType_Slot(c_int(Py_nb_add), _fn_ptr_as_opaque(slot_add))
        )
        decimal_builder._insert_slot(
            PyType_Slot(c_int(Py_nb_subtract), _fn_ptr_as_opaque(slot_subtract))
        )
        decimal_builder._insert_slot(
            PyType_Slot(c_int(Py_nb_multiply), _fn_ptr_as_opaque(slot_multiply))
        )
        decimal_builder._insert_slot(
            PyType_Slot(
                c_int(Py_nb_true_divide), _fn_ptr_as_opaque(slot_true_divide)
            )
        )
        decimal_builder._insert_slot(
            PyType_Slot(
                c_int(Py_tp_richcompare), _fn_ptr_as_opaque(slot_richcompare)
            )
        )
        decimal_builder._insert_slot(
            PyType_Slot(
                c_int(Py_tp_dealloc), _fn_ptr_as_opaque(decimal_dealloc)
            )
        )

        _ = (
            decimal_builder.def_py_init[bigdecimal_py_init]()
            # --- text ---------------------------------------------------
            .def_method[bigdecimal_to_string]("to_string")
            .def_method[bigdecimal_to_repr]("to_repr")
            .def_method[bigdecimal_to_eng_string]("to_eng_string")
            .def_method[bigdecimal_to_string]("__str__")
            # --- arithmetic ---------------------------------------------
            .def_method[bigdecimal_floordiv]("__floordiv__")
            .def_method[bigdecimal_rfloordiv]("__rfloordiv__")
            .def_method[bigdecimal_mod]("__mod__")
            .def_method[bigdecimal_rmod]("__rmod__")
            .def_method[bigdecimal_divmod]("__divmod__")
            .def_method[bigdecimal_rdivmod]("__rdivmod__")
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
            .def_method[bigdecimal_components]("_components")
            # Methods with an optional argument. `def_py_method` would put
            # them on `METH_VARARGS`, which packs a tuple for every call --
            # measured at 44 ns, most of what `quantize` costs.
            .def_py_c_method[static_method=False](fastcall_pow, "__pow__")
            .def_py_c_method[static_method=False](fastcall_rpow, "__rpow__")
            .def_py_c_method[static_method=False](method_quantize, "quantize")
            .def_py_c_method[static_method=False](method_sqrt, "sqrt")
            .def_py_c_method[static_method=False](method_exp, "exp")
            .def_py_c_method[static_method=False](method_ln, "ln")
            .def_py_c_method[static_method=False](method_log10, "log10")
            .def_py_c_method[static_method=False](
                method_to_integral, "to_integral_value"
            )
            .def_py_c_method[static_method=False](
                method_to_integral, "to_integral"
            )
            .def_py_c_method[static_method=False](fastcall_round, "__round__")
            # --- comparison ---------------------------------------------
            .def_method[bigdecimal_compare]("compare")
            .def_method[bigdecimal_max]("max")
            .def_method[bigdecimal_min]("min")
            # --- the `decimal.Decimal` method surface -------------------
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
            # --- digits, neighbours and the total order -----------------
            .def_method[bigdecimal_remainder_near]("remainder_near")
            .def_method[bigdecimal_next_plus]("next_plus")
            .def_method[bigdecimal_next_minus]("next_minus")
            .def_method[bigdecimal_next_toward]("next_toward")
            .def_method[bigdecimal_shift]("shift")
            .def_method[bigdecimal_rotate]("rotate")
            .def_method[bigdecimal_logical_and]("logical_and")
            .def_method[bigdecimal_logical_or]("logical_or")
            .def_method[bigdecimal_logical_xor]("logical_xor")
            .def_method[bigdecimal_logical_invert]("logical_invert")
            .def_method[bigdecimal_logb]("logb")
            .def_method[bigdecimal_compare_total]("compare_total")
            .def_method[bigdecimal_compare_total_mag]("compare_total_mag")
            .def_method[bigdecimal_compare]("compare_signal")
            .def_method[bigdecimal_max_mag]("max_mag")
            .def_method[bigdecimal_min_mag]("min_mag")
            .def_method[bigdecimal_number_class]("number_class")
            .def_method[bigdecimal_is_qnan]("is_qnan")
            .def_method[bigdecimal_is_snan]("is_snan")
            .def_py_c_method[static_method=False](
                method_to_integral, "to_integral_exact"
            )
        )
        return m.finalize()
    except e:
        abort(String("error creating _decimo Python module: ", e))


# ===----------------------------------------------------------------------=== #
# Helper functions
# ===----------------------------------------------------------------------=== #


@always_inline
def is_same_type(a: PythonObject, b: PythonObject) raises -> Bool:
    """Whether two objects have the very same Python type.

    `Python.type()` calls `PyObject_Type`, which takes a new reference and
    wraps it in a `PythonObject` that has to be released again. Doing that
    twice per operation cost more than the addition underneath it. The type of
    an object is a plain field of its header, so read the field and compare the
    pointers: no refcount, no allocation, no call into CPython at all.
    """
    ref cpython = Python().cpython()
    return cpython.Py_TYPE(a._obj_ptr) == cpython.Py_TYPE(b._obj_ptr)


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


def convert_big_int(other: PythonObject) raises -> BigDecimal:
    """An `int` too wide for a machine word, or an `int` subclass such as
    `bool`. Off the hot path on purpose, so it can afford the text detour.
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

    Recognising the `int` is a pointer comparison against CPython's `int` type,
    and reading it is one call. It used to build a throwaway Python `0` just to
    ask what type it was, then format the operand as text and parse the text
    back -- which is why `d + 2` cost twice what `d + d` did.
    """
    ref cpython = Python().cpython()
    if cpython.PyLong_Check(other._obj_ptr):
        var value = cpython.PyLong_AsSsize_t(other._obj_ptr)
        # Anything wider than a machine word comes back as -1 with the error
        # indicator set. -1 is also a perfectly good integer, so the indicator
        # has to be consulted -- but only for that one value, and asking costs
        # a call into CPython.
        if value != -1:
            return BigDecimal.from_integral_scalar(Int64(value))
        if not cpython.PyErr_Occurred():
            return BigDecimal.from_integral_scalar(Int64(-1))
        cpython.PyErr_Clear()
    return convert_big_int(other)


def from_python_float(other: PythonObject) raises -> BigDecimal:
    """Read a Python float exactly, the way `decimal.Decimal(float)` does.

    What that produces is the number the float really is: `Decimal(0.1)` is
    the 55-digit value, not `0.1`.
    """
    ref cpython = Python().cpython()
    if cpython.PyFloat_CheckExact(other._obj_ptr):
        return BigDecimal.from_float_scalar(
            Float64(cpython.PyFloat_AsDouble(other._obj_ptr))
        )
    # A `float` subclass, or something that merely looks like one. `repr()` of
    # a float is by definition the shortest string that reads back as the same
    # double, so the text detour loses nothing.
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
    ref cpython = Python().cpython()
    if cpython.PyFloat_CheckExact(other._obj_ptr):
        return BigDecimal.from_float_scalar(
            Float64(cpython.PyFloat_AsDouble(other._obj_ptr))
        )
    if cpython.PyFloat_Check(other._obj_ptr):
        return from_python_float(other)
    return convert_operand(other)


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

    `None` means the context's current mode, as in `decimal`.
    """
    if py_mode is PythonObject(None):
        return state()[].rounding
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


def _from_components(components: PythonObject) raises -> BigDecimal:
    """Build a decimal from `(sign, digits, exponent)`, as `as_tuple()` gives.

    Args:
        components: The three-part tuple or list.

    Returns:
        The value it describes.

    Raises:
        Error: If it is not three parts, if a digit is not a digit, or if the
            exponent is one of `decimal`'s special strings -- `"F"`, `"n"`,
            `"N"` -- which stand for infinity and the NaNs that decimo does
            not have.
    """
    if len(components) != 3:
        raise Error(
            "a decimal built from a tuple needs three parts: sign, digits and"
            " exponent"
        )
    var exponent = components[2]
    var builtins = Python.import_module("builtins")
    if builtins.isinstance(exponent, builtins.str):
        raise Error(
            "decimo has no infinities or NaNs, and those are what an exponent"
            " of 'F', 'n' or 'N' asks for"
        )

    var text = String("")
    var digits = components[1]
    for digit in digits:
        var value = Int(py=digit)
        if value < 0 or value > 9:
            raise Error("a digit of a decimal must be between 0 and 9")
        text += String(value)
    if text == "":
        text = "0"

    var result = BigDecimal(
        BigUInt.from_string(text), -Int(py=exponent), Int(py=components[0]) != 0
    )
    return result^


def bigdecimal_py_init(
    out self: BigDecimal, args: PythonObject, kwargs: PythonObject
) raises:
    """Construct a BigDecimal from a single argument (string, int, or float).

    Usage from Python:
        Decimal("3.14")
        Decimal(42)
        Decimal(3.14)          # read exactly, like decimal.Decimal
        Decimal((0, (1, 2), -1))  # sign, digits, exponent -- as_tuple()'s form
        Decimal()              # zero
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
    ref cpython = Python().cpython()
    var argument = args[0]

    # An `int` without the text detour. `Decimal(n)` inside a loop is how
    # every series in `python/benchmarks/workload.py` is written, and
    # formatting the integer and parsing it back was most of what it cost.
    # `PyLong_Check` rather than `CheckExact`, so `Decimal(True)` is
    # `Decimal("1")` as it is in `decimal`. Formatting the operand as text and
    # parsing it back gave "True", which parsed as nothing at all.
    if cpython.PyLong_Check(argument._obj_ptr):
        var value = cpython.PyLong_AsSsize_t(argument._obj_ptr)
        if value != -1:
            self = BigDecimal.from_integral_scalar(Int64(value))
            return
        if not cpython.PyErr_Occurred():
            self = BigDecimal.from_integral_scalar(Int64(-1))
            return
        cpython.PyErr_Clear()

    if cpython.PyFloat_CheckExact(argument._obj_ptr):
        self = BigDecimal.from_float_scalar(
            Float64(cpython.PyFloat_AsDouble(argument._obj_ptr))
        )
        return

    if cpython.PyFloat_Check(argument._obj_ptr):
        self = from_python_float(argument)
        return

    # The Mojo error carries a whole traceback with terminal colours in it,
    # which is not what a Python programmer should see from a constructor.
    try:
        self = BigDecimal(String(argument))
    except:
        # `as_tuple()`'s own form, so that the round trip closes: sign, the
        # digits one by one, and the exponent. Asked here, where the parse
        # has already given up, rather than before it: `Decimal("10000.00")`
        # is the hottest constructor there is and must not pay for a check
        # that a tuple argument can pay for itself.
        var builtins = Python.import_module("builtins")
        if builtins.isinstance(
            argument, Python.tuple(builtins.tuple, builtins.list)
        ):
            self = _from_components(argument)
            return
        raise Error(String("could not parse as a decimal: ", argument))


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
# `+`, `-`, `*`, `/`, `**`, `%` and the remainder from `divmod` round to the
# context precision, which is what `decimal` does. `//` and the quotient from
# `divmod` do not: they are exact by definition, and where `decimal` raises
# InvalidOperation because that exact quotient has more digits than the
# context allows, decimo returns it.
# ===----------------------------------------------------------------------=== #


def bigdecimal_add(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self + other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    ref cell = state()[]
    var digits = cell.precision
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
    return new_decimal(cell, result^)


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
    return new_decimal(state()[], result^)


def bigdecimal_sub(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self - other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    ref cell = state()[]
    var digits = cell.precision
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
    return new_decimal(cell, result^)


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
    return new_decimal(state()[], result^)


def bigdecimal_mul(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self * other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    ref cell = state()[]
    var digits = cell.precision
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
    return new_decimal(cell, result^)


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
    return new_decimal(state()[], result^)


def bigdecimal_div(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self / other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    ref cell = state()[]
    var digits = cell.precision
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
    return new_decimal(cell, result^)


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
    return new_decimal(state()[], result^)


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
    return new_decimal(state()[], result^)


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
    return new_decimal(state()[], result^)


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
        result = round_to_context(self_ptr[] % converted)
    except:
        return raise_as["PyExc_ZeroDivisionError"]("division by zero")
    return new_decimal(state()[], result^)


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
        result = round_to_context(converted % self_ptr[])
    except:
        return raise_as["PyExc_ZeroDivisionError"]("division by zero")
    return new_decimal(state()[], result^)


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
    ref cell = state()[]
    return Python.tuple(
        new_decimal(cell, pair[0].copy()),
        new_decimal(cell, round_to_context(pair[1].copy())),
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
    ref cell = state()[]
    return Python.tuple(
        new_decimal(cell, pair[0].copy()),
        new_decimal(cell, round_to_context(pair[1].copy())),
    )


def fastcall_pow(
    py_self: PyObjectPtr,
    args: Pointer[PyObjectPtr, MutUntrackedOrigin],
    nargs: Py_ssize_t,
) abi("C") -> PyObjectPtr:
    """`self ** other`, or `pow(self, other, modulus)` with three arguments.

    Python passes the modulus to `__pow__` itself, so the method has to take
    one argument or two; a fixed arity cannot say that. It never passes a
    keyword, so this stays on the fast path.
    """
    try:
        if Int(nargs) < 1:
            return _raise_type_error(
                Error("__pow__() takes at least 1 argument (0 given)")
            )
        return _power(
            PythonObject(from_borrowed=py_self),
            PythonObject(from_borrowed=args[unsafe_offset=0]),
            _fastcall_argument(args, nargs, 1),
            False,
        ).steal_data()
    except e:
        # A modulus that is not a whole number, or a negative exponent:
        # `decimal` calls that InvalidOperation, which is ValueError here.
        return raise_python_exception(e, ExceptionType("PyExc_ValueError"))


def fastcall_rpow(
    py_self: PyObjectPtr,
    args: Pointer[PyObjectPtr, MutUntrackedOrigin],
    nargs: Py_ssize_t,
) abi("C") -> PyObjectPtr:
    """`other ** self`, reached when the left operand is not a decimal."""
    try:
        if Int(nargs) < 1:
            return _raise_type_error(
                Error("__rpow__() takes at least 1 argument (0 given)")
            )
        return _power(
            PythonObject(from_borrowed=py_self),
            PythonObject(from_borrowed=args[unsafe_offset=0]),
            _fastcall_argument(args, nargs, 1),
            True,
        ).steal_data()
    except e:
        # A modulus that is not a whole number, or a negative exponent:
        # `decimal` calls that InvalidOperation, which is ValueError here.
        return raise_python_exception(e, ExceptionType("PyExc_ValueError"))


def _power(
    py_self: PythonObject,
    other: PythonObject,
    modulus: PythonObject,
    reflected: Bool,
) raises -> PythonObject:
    """The shared body of `__pow__` and `__rpow__`.

    Args:
        py_self: The decimal the method was called on.
        other: The other operand.
        modulus: The third argument of `pow()`, or `None`.
        reflected: Whether `other` is the base rather than the exponent.

    Returns:
        The power, rounded to the context, or the modular power when a
        modulus is given.

    Raises:
        Error: If the operands cannot be converted, or if a modular power is
            asked for with something other than whole numbers.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var converted: BigDecimal
    if is_same_type(other, py_self):
        converted = other.unchecked_downcast_value_ptr[BigDecimal]()[].copy()
    else:
        try:
            converted = convert_operand(other)
        except:
            return not_implemented()
    var base = converted.copy() if reflected else self_ptr[].copy()
    var exponent = self_ptr[].copy() if reflected else converted.copy()
    if modulus is not PythonObject(None):
        var divisor: BigDecimal
        if is_same_type(modulus, py_self):
            divisor = modulus.unchecked_downcast_value_ptr[
                BigDecimal
            ]()[].copy()
        else:
            try:
                divisor = convert_operand(modulus)
            except:
                return not_implemented()
        return new_decimal(state()[], _modular_power(base, exponent, divisor))
    var result = _power_to_context(base, exponent)
    return new_decimal(state()[], result^)


def _modular_power(
    base: BigDecimal, exponent: BigDecimal, modulus: BigDecimal
) raises -> BigDecimal:
    """`pow(base, exponent, modulus)`, the three-argument form.

    Args:
        base: The base. It must be a whole number.
        exponent: The exponent. It must be a whole number, and not negative.
        modulus: The modulus. It must be a whole number, and not zero.

    Returns:
        `base ** exponent` reduced modulo `modulus`, computed by repeated
        squaring rather than by raising the base first, so the exponent may
        be as large as it likes.

    Raises:
        Error: If any of the three is not a whole number, if the exponent is
            negative, or if the modulus is zero. `decimal` refuses all of
            those too.
    """
    if (
        not base.is_integer()
        or not exponent.is_integer()
        or not modulus.is_integer()
    ):
        raise Error("pow() with three arguments needs whole numbers")
    if exponent.is_negative():
        raise Error("pow() with three arguments needs a non-negative exponent")
    if modulus.is_zero():
        raise Error("pow() with three arguments needs a non-zero modulus")
    var result = BigInt.from_string(base.to_string(force_plain=True)).mod_pow(
        BigInt.from_string(exponent.to_string(force_plain=True)),
        BigInt.from_string(modulus.to_string(force_plain=True)),
    )
    return BigDecimal(result.to_string())


def _power_to_context(
    base: BigDecimal, exponent: BigDecimal
) raises -> BigDecimal:
    """`base ** exponent` at the context precision and rounding.

    See `DIRECTED_GUARD_DIGITS` for how a mode other than HALF_EVEN is met.
    """
    ref cell = state()[]
    if cell.rounding == RoundingMode.ROUND_HALF_EVEN:
        return base.power(exponent, cell.precision)
    return round_to_context(
        base.power(exponent, cell.precision + DIRECTED_GUARD_DIGITS)
    )


def bigdecimal_neg(py_self: PythonObject) raises -> PythonObject:
    """Return -self, rounded to the context precision.

    Unary minus is an operation like any other in `decimal`, so it rounds.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = round_to_context(-(self_ptr[]))
    return new_decimal(state()[], result^)


def bigdecimal_pos(py_self: PythonObject) raises -> PythonObject:
    """Return +self, rounded to the context precision.

    This is not a no-op, and programs lean on that: `+value` is the usual way
    to bring a value computed at a wider working precision back to the one the
    context asks for. `decimal` behaves the same way.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = round_to_context(self_ptr[].copy())
    return new_decimal(state()[], result^)


def bigdecimal_abs(py_self: PythonObject) raises -> PythonObject:
    """Return abs(self), rounded to the context like `decimal`.

    `copy_abs()` is the one that does not round.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = round_to_context(abs(self_ptr[]))
    return new_decimal(state()[], result^)


def bigdecimal_bool(py_self: PythonObject) raises -> PythonObject:
    """Return whether self is non-zero."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject(not self_ptr[].is_zero())


def bigdecimal_copy(py_self: PythonObject) raises -> PythonObject:
    """Return a copy of self. Backs `copy.copy()` and `copy.deepcopy()`."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy()
    return new_decimal(state()[], result^)


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
    return new_decimal(state()[], result^)


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
    return new_decimal(state()[], result^)


def bigdecimal_max(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return the larger of self and other, rounded to the context."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = round_to_context(self_ptr[].max(as_decimal(py_self, other)))
    return new_decimal(state()[], result^)


def bigdecimal_min(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return the smaller of self and other, rounded to the context."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = round_to_context(self_ptr[].min(as_decimal(py_self, other)))
    return new_decimal(state()[], result^)


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
    return new_decimal(state()[], result^)


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
    return new_decimal(state()[], result^)


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
    return new_decimal(state()[], result^)


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
    return new_decimal(state()[], result^)


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
    return new_decimal(state()[], result^)


def bigdecimal_to_integral(
    mut py_self: PythonObject, mut args: PythonObject
) raises -> PythonObject:
    """Return self rounded to an integer, as a Decimal."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var mode = rounding_from(arg_or_none(args, 0))
    var result = self_ptr[].round(0, mode)
    return new_decimal(state()[], result^)


def bigdecimal_fma(
    py_self: PythonObject, other: PythonObject, third: PythonObject
) raises -> PythonObject:
    """Return self * other + third, rounded once at the end.

    `decimal` rounds an `fma` to the context, and only there -- the product
    is exact -- so the result goes through `round_to_context()`.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = round_to_context(
        self_ptr[].fma(as_decimal(py_self, other), as_decimal(py_self, third))
    )
    return new_decimal(state()[], result^)


def bigdecimal_normalize(py_self: PythonObject) raises -> PythonObject:
    """Return self rounded to the context, then stripped of trailing zeros.

    That order is `decimal`'s: at precision 3 `Decimal("9.99999")` rounds to
    `10.0` and reduces to `1E+1`.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = round_to_context(self_ptr[].copy()).normalize()
    return new_decimal(state()[], result^)


def bigdecimal_adjusted(py_self: PythonObject) raises -> PythonObject:
    """Return the adjusted exponent: the exponent of the leading digit."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    return PythonObject(self_ptr[].adjusted())


def bigdecimal_scaleb(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self * 10 ** other, by moving the exponent.

    Rounded to the context afterwards, as in `decimal`.
    """
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var builtins = Python.import_module("builtins")
    var result = round_to_context(
        self_ptr[].scaleb(Int(py=builtins.int(other)))
    )
    return new_decimal(state()[], result^)


def bigdecimal_copy_abs(py_self: PythonObject) raises -> PythonObject:
    """Return self with the sign cleared, without rounding."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy_abs()
    return new_decimal(state()[], result^)


def bigdecimal_copy_negate(py_self: PythonObject) raises -> PythonObject:
    """Return self with the sign flipped, without rounding."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy_negate()
    return new_decimal(state()[], result^)


def bigdecimal_copy_sign(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self with the sign of other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy_sign(as_decimal(py_self, other))
    return new_decimal(state()[], result^)


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
    return new_decimal(state()[], result^)


def bigdecimal_conjugate(py_self: PythonObject) raises -> PythonObject:
    """Return self. Present because `decimal` has it, for the numeric tower."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var result = self_ptr[].copy()
    return new_decimal(state()[], result^)


def bigdecimal_radix(py_self: PythonObject) raises -> PythonObject:
    """Return 10, the base this type works in."""
    var result = BigDecimal(10)
    return new_decimal(state()[], result^)


# ===----------------------------------------------------------------------=== #
# Operator slots
#
# `a + b` on a type built from a spec used to reach us the long way round:
# CPython's `nb_add` held `slot_nb_add`, which looks `__add__` up in the type
# dictionary and calls it as a Python method. Measured, that made the operator
# *more* expensive than calling the method directly -- 69.7 ns against
# 64.8 -- where for CPython's own `decimal` the operator is 18 ns *cheaper*
# than the method, because its `nb_add` is a plain C function pointer.
#
# So these are plain C function pointers, handed to `PyType_FromSpec` the way
# any C extension would. Nothing here writes into a type object; the slots go
# in the spec and CPython builds the type from them, which is also what gives
# us `__add__` in the dictionary for free.
#
# One consequence worth knowing: a binary slot is not one-sided. CPython calls
# `nb_add(v, w)` with the decimal on either side, which is why each of these
# begins by working out which operand is ours. That is also what makes
# `__radd__` unnecessary -- the reflected case is the same function.
# ===----------------------------------------------------------------------=== #

comptime Py_nb_add = 7
comptime Py_nb_multiply = 29
comptime Py_nb_subtract = 36
comptime Py_nb_true_divide = 37
comptime Py_tp_dealloc = 52
comptime Py_tp_richcompare = 67

comptime binaryfunc = def(PyObjectPtr, PyObjectPtr) thin abi("C") -> PyObjectPtr
comptime richcmpfunc = def(PyObjectPtr, PyObjectPtr, c_int) thin abi(
    "C"
) -> PyObjectPtr

comptime Py_LT = 0
comptime Py_LE = 1
comptime Py_EQ = 2
comptime Py_NE = 3
comptime Py_GT = 4
comptime Py_GE = 5


@always_inline
def _value_of(obj: PyObjectPtr) -> Pointer[BigDecimal, MutUntrackedOrigin]:
    """The `BigDecimal` inside a decimal object, without touching its refcount.

    `PythonObject(from_borrowed=)` fetches the CPython handle and increments a
    reference count, and undoes both when it goes out of scope. For a slot that
    is four global fetches and four refcount operations per operation, to
    borrow something CPython already guarantees stays alive for the length of
    the call. So read the value where it lies: a `PyMojoObject` is the object
    header followed by the Mojo value.

    Only call this after checking the type.
    """
    ref mojo_object = obj.bitcast[PyMojoObject[BigDecimal]]().value()[]
    return Pointer(to=mojo_object.mojo_value).unsafe_origin_cast[
        MutUntrackedOrigin
    ]()


def _not_implemented_ptr() raises -> PyObjectPtr:
    """A new reference to `NotImplemented`, which a slot must return owned."""
    return not_implemented().steal_data()


def _binary_slot[
    operation: def(
        BigDecimal, BigDecimal, Int, RoundingMode
    ) thin raises -> BigDecimal,
    is_division: Bool = False,
](left: PyObjectPtr, right: PyObjectPtr) abi("C") -> PyObjectPtr:
    """The shared body of every arithmetic slot.

    Works out which side is the decimal, converts the other, and applies
    `operation` in the order the expression was written.

    Parameters:
        operation: What to do with the two values.
        is_division: Whether a failure means division by zero. The slot has to
            name the exception itself; letting the error escape would surface
            as a bare `Exception`, which no `except ZeroDivisionError` catches.
    """
    try:
        ref cell = state()[]
        ref cpython = Python().cpython()
        var ours = decimal_type_ptr(cell)
        var left_is_ours = cpython.Py_TYPE(left) == ours
        var right_is_ours = cpython.Py_TYPE(right) == ours

        var result: BigDecimal
        if left_is_ours and right_is_ours:
            # The common case: no reference counting, no conversion.
            result = operation(
                _value_of(left)[],
                _value_of(right)[],
                cell.precision,
                cell.rounding,
            )
        elif left_is_ours:
            var converted: BigDecimal
            try:
                converted = convert_operand(PythonObject(from_borrowed=right))
            except:
                return _not_implemented_ptr()
            result = operation(
                _value_of(left)[], converted, cell.precision, cell.rounding
            )
        elif right_is_ours:
            var converted: BigDecimal
            try:
                converted = convert_operand(PythonObject(from_borrowed=left))
            except:
                return _not_implemented_ptr()
            result = operation(
                converted, _value_of(right)[], cell.precision, cell.rounding
            )
        else:
            return _not_implemented_ptr()

        return new_decimal(cell, result^).steal_data()
    except e:
        comptime if is_division:
            return raise_python_exception(
                Error("division by zero"),
                ExceptionType("PyExc_ZeroDivisionError"),
            )
        return raise_python_exception(e)


def _sign_of_zero_sum(sign1: Bool, sign2: Bool, mode: RoundingMode) -> Bool:
    """The sign `decimal` gives a sum that came out zero.

    Two negative operands give -0. Operands of opposite sign that cancel give
    +0, except under ROUND_FLOOR where they give -0. This is the decimal
    specification's rule and it is only here so that a program printing
    `-0.0` under `decimal` prints it here too; the Mojo library returns +0
    for a cancellation and is not made to carry the quirk.
    """
    if sign1 and sign2:
        return True
    return sign1 != sign2 and mode == RoundingMode.ROUND_FLOOR


def _do_add(
    x: BigDecimal, y: BigDecimal, digits: Int, mode: RoundingMode
) raises -> BigDecimal:
    var result = x.add(y, digits, mode)
    if result.coefficient.is_zero():
        result.sign = _sign_of_zero_sum(x.sign, y.sign, mode)
    return result^


def _do_subtract(
    x: BigDecimal, y: BigDecimal, digits: Int, mode: RoundingMode
) raises -> BigDecimal:
    var result = x.subtract(y, digits, mode)
    if result.coefficient.is_zero():
        # x - y is x + (-y).
        result.sign = _sign_of_zero_sum(x.sign, not y.sign, mode)
    return result^


def _do_multiply(
    x: BigDecimal, y: BigDecimal, digits: Int, mode: RoundingMode
) raises -> BigDecimal:
    return x.multiply(y, digits, mode)


def _do_divide(
    x: BigDecimal, y: BigDecimal, digits: Int, mode: RoundingMode
) raises -> BigDecimal:
    return x.true_divide(y, digits, mode)


def slot_add(left: PyObjectPtr, right: PyObjectPtr) abi("C") -> PyObjectPtr:
    """`nb_add`."""
    return _binary_slot[_do_add](left, right)


def slot_subtract(
    left: PyObjectPtr, right: PyObjectPtr
) abi("C") -> PyObjectPtr:
    """`nb_subtract`."""
    return _binary_slot[_do_subtract](left, right)


def slot_multiply(
    left: PyObjectPtr, right: PyObjectPtr
) abi("C") -> PyObjectPtr:
    """`nb_multiply`."""
    return _binary_slot[_do_multiply](left, right)


def slot_true_divide(
    left: PyObjectPtr, right: PyObjectPtr
) abi("C") -> PyObjectPtr:
    """`nb_true_divide`. Division by zero is a `ZeroDivisionError`."""
    return _binary_slot[_do_divide, is_division=True](left, right)


def slot_richcompare(
    left: PyObjectPtr, right: PyObjectPtr, operation: c_int
) abi("C") -> PyObjectPtr:
    """`tp_richcompare`: all six comparisons, one C function.

    Same reasoning as the arithmetic slots. Comparison is the cheapest thing
    the type does -- there is no result to allocate -- so the dispatch was
    most of its cost.

    A comparison accepts a `float` where arithmetic does not, because
    comparing is not the operation that quietly loses the distinction between
    a binary and a decimal fraction.
    """
    try:
        ref cpython = Python().cpython()
        # CPython always hands `tp_richcompare` the type that owns it as the
        # first argument -- `do_richcompare` calls `f(v, w, op)` for `v`'s slot
        # and `f(w, v, swapped)` for `w`'s. So `left` is ours, and two operands
        # of the same type are both ours. That settles the common case without
        # reading the module state at all: a comparison has no result to
        # allocate and no precision to apply, so the lookup was most of it.
        var left_type = cpython.Py_TYPE(left)
        var order: Int8
        if left_type == cpython.Py_TYPE(right):
            return _compare_answer(
                _value_of(left)[].compare(_value_of(right)[]), operation
            )

        ref cell = state()[]
        var ours = decimal_type_ptr(cell)
        var left_is_ours = left_type == ours
        var right_is_ours = cpython.Py_TYPE(right) == ours

        if left_is_ours:
            var converted: BigDecimal
            try:
                converted = convert_comparand(PythonObject(from_borrowed=right))
            except:
                return _not_implemented_ptr()
            order = _value_of(left)[].compare(converted)
        elif right_is_ours:
            var converted: BigDecimal
            try:
                converted = convert_comparand(PythonObject(from_borrowed=left))
            except:
                return _not_implemented_ptr()
            order = converted.compare(_value_of(right)[])
        else:
            return _not_implemented_ptr()

        return _compare_answer(order, operation)
    except e:
        return raise_python_exception(e)


@always_inline
def _compare_answer(order: Int8, operation: c_int) raises -> PyObjectPtr:
    """Turn a three-way ordering into the answer the comparison asked for."""
    var answer: Bool
    if operation == Py_LT:
        answer = order < 0
    elif operation == Py_LE:
        answer = order <= 0
    elif operation == Py_EQ:
        answer = order == 0
    elif operation == Py_NE:
        answer = order != 0
    elif operation == Py_GT:
        answer = order > 0
    else:
        answer = order >= 0
    return PythonObject(answer).steal_data()


# ===----------------------------------------------------------------------=== #
# Methods with an optional argument
#
# `def_py_method` registers a method as `METH_VARARGS`, and CPython packs the
# arguments into a tuple before every such call. Measured on `quantize`, that
# tuple cost 44 ns of a 106 ns call -- and the same method on the fastcall
# path came out at 61 ns, against 61 for CPython's own.
#
# `def_method` uses fastcall but fixes the arity, which does not fit a method
# whose second argument is optional. So these are written against the
# vectorcall signature directly: CPython hands over a plain array of arguments
# and a count, and the count is what says whether the optional one is there.
#
# `decimal` gives most of these a trailing `context` argument. We accept it
# and ignore it: there is one context here, and it is the one the value was
# going to use anyway.
#
# The ones a program actually writes with a keyword -- `quantize(exp,
# rounding=ROUND_HALF_UP)` above all, which is how money code spells itself --
# cannot use fastcall at all, since the binding offers keywords only on the
# tuple-packing path. Reading the tuple with `PyTuple_GetItem` instead of
# through `PythonObject`, which boxes the index, keeps that to 10 ns:
# `quantize` measures 62 ns against 52 on fastcall and 65 for CPython's own,
# which buys the keyword at a price still under the library we replace.
# `__round__` and `__pow__` stay on fastcall: Python never passes them one.
# ===----------------------------------------------------------------------=== #


@always_inline
def _positional(
    args: PythonObject, count: Int, index: Int
) raises -> PythonObject:
    """The argument at `index`, or `None` when it was not given.

    Args:
        args: The positional arguments.
        count: How many there are, read once by the caller.
        index: Which one is wanted.

    Returns:
        The argument, or `None`.
    """
    if count > index:
        return args[index]
    return PythonObject(None)


@always_inline
def _keyword_argument(
    args: PythonObject,
    kwargs: PyObjectPtr,
    index: Int,
    name: StaticString,
    var taken: Int,
) raises -> Tuple[PythonObject, Int]:
    """The argument at `index` or under `name`, and how many keywords were used.

    Args:
        args: The positional arguments, as CPython packed them.
        kwargs: The keyword arguments, which is null when there are none.
        index: Where the argument sits when it is given positionally.
        name: What it is called when it is given by keyword.
        taken: How many keywords earlier arguments have consumed.

    Returns:
        The value and the running count of keywords consumed, so that the
        caller can tell whether any keyword was left over.

    Raises:
        Error: If the same argument is given both ways.
    """
    var positional = PythonObject(None)
    var given = Int(len(args)) > index
    if given:
        positional = args[index]
    if not kwargs:
        return (positional^, taken)

    var mapping = PythonObject(from_borrowed=kwargs)
    var found = PythonObject(name) in mapping
    if not found:
        return (positional^, taken)
    if given:
        raise Error("argument given both by position and by keyword")
    return (mapping[PythonObject(name)], taken + 1)


@always_inline
def _no_other_keywords(kwargs: PyObjectPtr, taken: Int) raises:
    """Refuse a keyword this method does not have, as `decimal` does.

    Args:
        kwargs: The keyword arguments, null when there are none.
        taken: How many of them the method recognized.

    Raises:
        Error: If any keyword was not recognized.
    """
    if not kwargs:
        return
    if Int(len(PythonObject(from_borrowed=kwargs))) != taken:
        raise Error("unexpected keyword argument")


@always_inline
def _fastcall_argument(
    args: Pointer[PyObjectPtr, MutUntrackedOrigin],
    nargs: Py_ssize_t,
    index: Int,
) -> PythonObject:
    """The argument at `index`, or `None` when it was not given."""
    if Int(nargs) > index:
        return PythonObject(from_borrowed=args[unsafe_offset=index])
    return PythonObject(None)


def method_quantize(
    py_self: PyObjectPtr, py_args: PyObjectPtr, py_kwargs: PyObjectPtr
) abi("C") -> PyObjectPtr:
    """`quantize(exp, rounding=None, context=None)`.

    The arguments are read off the tuple with `PyTuple_GetItem` rather than
    through `PythonObject`, which would box the index and hold a reference:
    this is the one method on this path that a loop calls a hundred times.
    """
    try:
        ref cell = state()[]
        ref cpython = Python().cpython()
        var rounding = PyObjectPtr()
        try:
            var count = Int(cpython.PyObject_Length(py_args))
            if count < 1:
                raise Error("quantize() takes at least 1 argument (0 given)")
            if not py_kwargs:
                # The common call, and the one worth keeping cheap.
                if count > 1:
                    rounding = cpython.PyTuple_GetItem(py_args, 1)
            else:
                var args = PythonObject(from_borrowed=py_args)
                var taken = 0
                var named: PythonObject
                (named, taken) = _keyword_argument(
                    args, py_kwargs, 1, "rounding", taken
                )
                # The context argument is accepted and ignored; see above.
                (_, taken) = _keyword_argument(
                    args, py_kwargs, 2, "context", taken
                )
                _no_other_keywords(py_kwargs, taken)
                if named is not PythonObject(None):
                    rounding = named._obj_ptr
        except e:
            return _raise_type_error(e)
        var given = cpython.PyTuple_GetItem(py_args, 0)

        # The template is nearly always another decimal, and reading it in
        # place keeps its reference count out of it.
        var template: BigDecimal
        if cpython.Py_TYPE(given) == decimal_type_ptr(cell):
            template = _value_of(given)[].copy()
        else:
            template = convert_operand(PythonObject(from_borrowed=given))

        var mode = cell.rounding
        if rounding:
            var named = PythonObject(from_borrowed=rounding)
            if named is not PythonObject(None):
                try:
                    _ = _mode_or_none(named)
                except:
                    return _raise_not_implemented(
                        "decimo does not implement ROUND_05UP"
                    )
                mode = rounding_from(named)

        var result = _value_of(py_self)[].quantize(template, mode)
        # `decimal` refuses a quantize whose result needs more digits than
        # the context allows: InvalidOperation, which is ValueError here.
        if result.coefficient.number_of_digits() > cell.precision:
            return _raise_value_error(
                "quantize result has too many digits for current context"
            )
        return new_decimal(cell, result^).steal_data()
    except e:
        return raise_python_exception(e)


def _method_to_precision[
    operation: def(BigDecimal, Int) thin raises -> BigDecimal,
    message: StaticString,
](py_self: PyObjectPtr, py_args: PyObjectPtr, py_kwargs: PyObjectPtr) abi(
    "C"
) -> PyObjectPtr:
    """The shared body of `sqrt`, `exp`, `ln` and `log10`.

    Each takes an optional context that we ignore, and each can be handed a
    value outside its domain, which is a `ValueError` rather than a bare
    `Exception`.

    Always half to even, whatever the context rounding says, which is what
    `decimal` does with these four. See `DIRECTED_GUARD_DIGITS`.
    """
    try:
        if py_kwargs:
            try:
                var taken = 0
                (_, taken) = _keyword_argument(
                    PythonObject(from_borrowed=py_args),
                    py_kwargs,
                    0,
                    "context",
                    taken,
                )
                _no_other_keywords(py_kwargs, taken)
            except e:
                return _raise_type_error(e)
        ref cell = state()[]
        var result: BigDecimal
        try:
            result = operation(_value_of(py_self)[], cell.precision)
        except:
            return _raise_value_error(message)
        return new_decimal(cell, result^).steal_data()
    except e:
        return raise_python_exception(e)


def _raise_not_implemented(message: StaticString) raises -> PyObjectPtr:
    """Fail with `NotImplementedError`, for what decimo has chosen not to do."""
    return raise_python_exception(
        Error(message), ExceptionType("PyExc_NotImplementedError")
    )


def _mode_or_none(value: PythonObject) raises -> PythonObject:
    """Refuse ROUND_05UP by name, as the context setter does.

    Args:
        value: The rounding argument, which may be `None`.

    Returns:
        The value unchanged.

    Raises:
        Error: If it is ROUND_05UP, the one mode decimo does not implement.
    """
    if value == PythonObject("ROUND_05UP"):
        raise Error("decimo does not implement ROUND_05UP")
    return value


def _raise_type_error(error: Error) raises -> PyObjectPtr:
    """Fail with a `TypeError`, which is what a bad argument list is."""
    return raise_python_exception(error, ExceptionType("PyExc_TypeError"))


def _raise_value_error(message: StaticString) raises -> PyObjectPtr:
    """Fail with a `ValueError` carrying a message a caller can read."""
    return raise_python_exception(
        Error(message), ExceptionType("PyExc_ValueError")
    )


def _do_sqrt(value: BigDecimal, digits: Int) raises -> BigDecimal:
    return value.sqrt(digits)


def _do_exp(value: BigDecimal, digits: Int) raises -> BigDecimal:
    return value.exp(digits)


def _do_ln(value: BigDecimal, digits: Int) raises -> BigDecimal:
    return value.ln(digits)


def _do_log10(value: BigDecimal, digits: Int) raises -> BigDecimal:
    return value.log10(digits)


def method_sqrt(
    py_self: PyObjectPtr, py_args: PyObjectPtr, py_kwargs: PyObjectPtr
) abi("C") -> PyObjectPtr:
    """`sqrt(context=None)`, to the context precision."""
    return _method_to_precision[_do_sqrt, "square root of a negative value"](
        py_self, py_args, py_kwargs
    )


def method_exp(
    py_self: PyObjectPtr, py_args: PyObjectPtr, py_kwargs: PyObjectPtr
) abi("C") -> PyObjectPtr:
    """`exp(context=None)`, to the context precision."""
    return _method_to_precision[_do_exp, "exp() is undefined for this value"](
        py_self, py_args, py_kwargs
    )


def method_ln(
    py_self: PyObjectPtr, py_args: PyObjectPtr, py_kwargs: PyObjectPtr
) abi("C") -> PyObjectPtr:
    """`ln(context=None)`, to the context precision."""
    return _method_to_precision[_do_ln, "ln() needs a positive value"](
        py_self, py_args, py_kwargs
    )


def method_log10(
    py_self: PyObjectPtr, py_args: PyObjectPtr, py_kwargs: PyObjectPtr
) abi("C") -> PyObjectPtr:
    """`log10(context=None)`, to the context precision."""
    return _method_to_precision[_do_log10, "log10() needs a positive value"](
        py_self, py_args, py_kwargs
    )


def method_to_integral(
    py_self: PyObjectPtr, py_args: PyObjectPtr, py_kwargs: PyObjectPtr
) abi("C") -> PyObjectPtr:
    """`to_integral_value(rounding=None, context=None)`.

    `None` is the context mode.
    """
    try:
        ref cpython = Python().cpython()
        var rounding = PyObjectPtr()
        try:
            if not py_kwargs:
                if Int(cpython.PyObject_Length(py_args)) > 0:
                    rounding = cpython.PyTuple_GetItem(py_args, 0)
            else:
                var args = PythonObject(from_borrowed=py_args)
                var taken = 0
                var named: PythonObject
                (named, taken) = _keyword_argument(
                    args, py_kwargs, 0, "rounding", taken
                )
                (_, taken) = _keyword_argument(
                    args, py_kwargs, 1, "context", taken
                )
                _no_other_keywords(py_kwargs, taken)
                if named is not PythonObject(None):
                    rounding = named._obj_ptr
        except e:
            return _raise_type_error(e)
        var mode = state()[].rounding
        var given = PythonObject(
            from_borrowed=rounding
        ) if rounding else PythonObject(None)
        if given is not PythonObject(None):
            try:
                _ = _mode_or_none(given)
            except:
                return _raise_not_implemented(
                    "decimo does not implement ROUND_05UP"
                )
            mode = rounding_from(given)
        # A value with no fractional digits is returned as it is, exponent
        # and all: `decimal` gives `Decimal("1E+2")` back unchanged.
        ref value = _value_of(py_self)[]
        var result: BigDecimal
        if value.scale <= 0:
            result = value.copy()
        else:
            result = value.round(0, mode)
        return new_decimal(state()[], result^).steal_data()
    except e:
        return raise_python_exception(e)


def fastcall_round(
    py_self: PyObjectPtr,
    args: Pointer[PyObjectPtr, MutUntrackedOrigin],
    nargs: Py_ssize_t,
) abi("C") -> PyObjectPtr:
    """`round(self)` and `round(self, ndigits)`.

    With no argument Python expects an `int` back, and with one it expects the
    same type as the input -- which is what `decimal` does too. `round(x)` is
    HALF_EVEN whatever the context says; `round(x, n)` is a `quantize` and
    follows the context rounding, as in `decimal`.
    """
    try:
        var places = _fastcall_argument(args, nargs, 0)
        if places is PythonObject(None):
            var value = _value_of(py_self)[].round(
                0, RoundingMode.ROUND_HALF_EVEN
            )
            var builtins = Python.import_module("builtins")
            return builtins.int(
                PythonObject(value.to_string(force_plain=True))
            ).steal_data()
        ref cell = state()[]
        var result = _value_of(py_self)[].round(Int(py=places), cell.rounding)
        # `round(x, n)` is a quantize, with the same limit.
        if result.coefficient.number_of_digits() > cell.precision:
            return _raise_value_error(
                "quantize result has too many digits for current context"
            )
        return new_decimal(cell, result^).steal_data()
    except e:
        return raise_python_exception(e)


# ===----------------------------------------------------------------------=== #
# The rest of the specification's method surface
#
# Digit-wise logic, neighbours and `remainder_near` live in
# `decimo.bigdecimal.spec`, the total order in `decimo.bigdecimal.comparison`.
# The two things they need that decimo does not have -- `Emin`, and therefore
# `Etiny` and the word "subnormal" -- are added in the Python layer, where the
# rest of `decimal`'s context lives.
#
# Each of these catches what the library raises and sets the Python exception
# a `decimal` program expects: `InvalidOperation`, which decimo maps to
# `ValueError`, or `DivisionByZero`, which it maps to `ZeroDivisionError`.
# ===----------------------------------------------------------------------=== #


def bigdecimal_remainder_near(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self - other * n, with n the integer nearest self / other."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var divisor = as_decimal(py_self, other)
    if divisor.is_zero():
        # `decimal` calls this InvalidOperation rather than DivisionByZero:
        # the nearest multiple of zero is undefined, not infinite.
        return raise_as["PyExc_ValueError"](
            "remainder_near has no answer when the divisor is zero"
        )
    var result = round_to_context(
        bigdecimal_spec.remainder_near(self_ptr[], divisor)
    )
    return new_decimal(state()[], result^)


def bigdecimal_next_plus(py_self: PythonObject) raises -> PythonObject:
    """Return the smallest value larger than self at this precision.

    Zero is the Python layer's business: it has the `Emin` that says how
    small a step may be.
    """
    ref cell = state()[]
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    if self_ptr[].is_zero():
        return raise_as["PyExc_ValueError"]("no value is next to zero")
    var result = bigdecimal_spec.next_plus(self_ptr[], cell.precision)
    return new_decimal(cell, result^)


def bigdecimal_next_minus(py_self: PythonObject) raises -> PythonObject:
    """Return the largest value smaller than self at this precision."""
    ref cell = state()[]
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    if self_ptr[].is_zero():
        return raise_as["PyExc_ValueError"]("no value is next to zero")
    var result = bigdecimal_spec.next_minus(self_ptr[], cell.precision)
    return new_decimal(cell, result^)


def bigdecimal_next_toward(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return the value next to self in the direction of other."""
    ref cell = state()[]
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    var target = as_decimal(py_self, other)
    if self_ptr[].is_zero() and not (self_ptr[] == target):
        return raise_as["PyExc_ValueError"]("no value is next to zero")
    var result = bigdecimal_spec.next_toward(self_ptr[], target, cell.precision)
    return new_decimal(cell, result^)


def bigdecimal_shift(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self with its coefficient shifted, zeros filling in."""
    try:
        ref cell = state()[]
        var builtins = Python.import_module("builtins")
        var result = bigdecimal_spec.shift(
            py_self.unchecked_downcast_value_ptr[BigDecimal]()[],
            Int(py=builtins.int(other)),
            cell.precision,
        )
        return new_decimal(cell, result^)
    except:
        return raise_as["PyExc_ValueError"](
            "the shift must be an integer no larger than the precision"
        )


def bigdecimal_rotate(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return self with its coefficient rotated."""
    try:
        ref cell = state()[]
        var builtins = Python.import_module("builtins")
        var result = bigdecimal_spec.rotate(
            py_self.unchecked_downcast_value_ptr[BigDecimal]()[],
            Int(py=builtins.int(other)),
            cell.precision,
        )
        return new_decimal(cell, result^)
    except:
        return raise_as["PyExc_ValueError"](
            "the rotation must be an integer no larger than the precision"
        )


comptime _NOT_LOGICAL: StaticString = (
    "a logical operand must be a non-negative integer written with the"
    " digits 0 and 1 and an exponent of zero"
)


def bigdecimal_logical_and(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return the digit-wise `and` of self and other."""
    try:
        ref cell = state()[]
        var result = bigdecimal_spec.logical_and(
            py_self.unchecked_downcast_value_ptr[BigDecimal]()[],
            as_decimal(py_self, other),
            cell.precision,
        )
        return new_decimal(cell, result^)
    except:
        return raise_as["PyExc_ValueError"](_NOT_LOGICAL)


def bigdecimal_logical_or(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return the digit-wise `or` of self and other."""
    try:
        ref cell = state()[]
        var result = bigdecimal_spec.logical_or(
            py_self.unchecked_downcast_value_ptr[BigDecimal]()[],
            as_decimal(py_self, other),
            cell.precision,
        )
        return new_decimal(cell, result^)
    except:
        return raise_as["PyExc_ValueError"](_NOT_LOGICAL)


def bigdecimal_logical_xor(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return the digit-wise `xor` of self and other."""
    try:
        ref cell = state()[]
        var result = bigdecimal_spec.logical_xor(
            py_self.unchecked_downcast_value_ptr[BigDecimal]()[],
            as_decimal(py_self, other),
            cell.precision,
        )
        return new_decimal(cell, result^)
    except:
        return raise_as["PyExc_ValueError"](_NOT_LOGICAL)


def bigdecimal_logical_invert(py_self: PythonObject) raises -> PythonObject:
    """Return the digit-wise inverse of self, in `prec` digits."""
    try:
        ref cell = state()[]
        var result = bigdecimal_spec.logical_invert(
            py_self.unchecked_downcast_value_ptr[BigDecimal]()[],
            cell.precision,
        )
        return new_decimal(cell, result^)
    except:
        return raise_as["PyExc_ValueError"](_NOT_LOGICAL)


def bigdecimal_logb(py_self: PythonObject) raises -> PythonObject:
    """Return the exponent of the leading digit, as a Decimal."""
    var self_ptr = py_self.unchecked_downcast_value_ptr[BigDecimal]()
    if self_ptr[].is_zero():
        # `decimal` answers `-Infinity` and raises DivisionByZero with it.
        return raise_as["PyExc_ZeroDivisionError"](
            "logb(0) has no answer without an infinity to give"
        )
    var result = round_to_context(bigdecimal_spec.logb(self_ptr[]))
    return new_decimal(state()[], result^)


def bigdecimal_compare_total(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Compare self and other in the specification's total order."""
    var order = bigdecimal_comparison.compare_total(
        py_self.unchecked_downcast_value_ptr[BigDecimal]()[],
        as_decimal(py_self, other),
    )
    return new_decimal(state()[], BigDecimal(Int(order)))


def bigdecimal_compare_total_mag(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Compare the magnitudes of self and other in the total order."""
    var order = bigdecimal_comparison.compare_total_absolute(
        py_self.unchecked_downcast_value_ptr[BigDecimal]()[],
        as_decimal(py_self, other),
    )
    return new_decimal(state()[], BigDecimal(Int(order)))


def bigdecimal_max_mag(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return the operand with the larger magnitude."""
    var result = round_to_context(
        bigdecimal_spec.max_absolute(
            py_self.unchecked_downcast_value_ptr[BigDecimal]()[],
            as_decimal(py_self, other),
        )
    )
    return new_decimal(state()[], result^)


def bigdecimal_min_mag(
    py_self: PythonObject, other: PythonObject
) raises -> PythonObject:
    """Return the operand with the smaller magnitude."""
    var result = round_to_context(
        bigdecimal_spec.min_absolute(
            py_self.unchecked_downcast_value_ptr[BigDecimal]()[],
            as_decimal(py_self, other),
        )
    )
    return new_decimal(state()[], result^)


def bigdecimal_number_class(py_self: PythonObject) raises -> PythonObject:
    """Return what kind of number self is, as `decimal` names it.

    Never "Subnormal" here: that word needs an `Emin`, which the Python
    layer applies on top of this answer.
    """
    return PythonObject(
        bigdecimal_spec.number_class(
            py_self.unchecked_downcast_value_ptr[BigDecimal]()[]
        )
    )


def bigdecimal_is_qnan(py_self: PythonObject) raises -> PythonObject:
    """Always False: decimo has no NaNs."""
    return PythonObject(False)


def bigdecimal_is_snan(py_self: PythonObject) raises -> PythonObject:
    """Always False: decimo has no NaNs."""
    return PythonObject(False)
