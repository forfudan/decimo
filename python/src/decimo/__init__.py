"""decimo: Arbitrary-precision decimal arithmetic for Python, powered by Mojo.

A drop-in replacement for the standard library's `decimal`:

    from decimo import Decimal, getcontext

    getcontext().prec = 50
    print(Decimal(1) / Decimal(7))

The rule this package follows is that anything it cannot do exactly the way
`decimal` does it should refuse, not answer differently. Where a feature is
missing you get an explicit error; you never get a quietly different number.

What is not here yet: NaN and infinity, the signal/trap machinery, and any
rounding mode other than ROUND_HALF_EVEN.
"""

from ._version import __version__ as __version__

try:
    from ._decimo import Decimal, get_precision as _get_precision
    from ._decimo import set_precision as _set_precision
except ImportError as _err:
    raise ImportError(
        "decimo requires a compiled Mojo extension (_decimo native module).\n"
        "This package does not yet include pre-built wheels.\n"
        "Build from source:\n"
        "  git clone https://github.com/forfudan/decimo && cd decimo\n"
        "  pixi run buildpy\n"
        "  pip install -e python/\n"
    ) from _err

import sys as _sys
from collections import namedtuple as _namedtuple


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

# The comparisons and `+`, `-`, `*`, `/` are not in this list. They are registered as real
# CPython number slots by the Mojo module, so the operator calls a C function
# directly instead of looking `__add__` up in the type dictionary on every
# operation. Assigning them here would undo that: `type.__setattr__` puts
# `slot_nb_add` back in the slot, which is exactly the indirection being
# avoided.
for _name in (
    "__str__",
    "__floordiv__",
    "__rfloordiv__",
    "__mod__",
    "__rmod__",
    "__divmod__",
    "__rdivmod__",
    "__pow__",
    "__rpow__",
    "__neg__",
    "__pos__",
    "__abs__",
    "__bool__",
    "__int__",
    "__float__",
):
    setattr(Decimal, _name, Decimal.__dict__[_name])
del _name

# `__repr__` is the one operator the loop above cannot reach. The bindings
# install their own from Mojo's `Representable`, which prints the Mojo type
# name, so point it at our own text instead.
Decimal.__repr__ = Decimal.to_repr


# --- Hashing ---------------------------------------------------------------
#
# A number's hash has to agree with every other numeric type that compares
# equal to it: `hash(Decimal("2")) == hash(2) == hash(2.0)`. CPython gets that
# by hashing every number as a rational modulo a prime, and `decimal` follows
# the same recipe. So do we, in Python, because `pow(base, exp, modulus)` is
# already there and this is not on anyone's hot path.

_MODULUS = _sys.hash_info.modulus
_TEN_INVERSE = pow(10, _MODULUS - 2, _MODULUS)


def _decimal_hash(self):
    negative, digits, exponent = self._components()
    if exponent >= 0:
        exponent_hash = pow(10, exponent, _MODULUS)
    else:
        exponent_hash = pow(_TEN_INVERSE, -exponent, _MODULUS)
    value = int(digits) * exponent_hash % _MODULUS
    if negative:
        value = -value
    # -1 is reserved by CPython to mean "an error happened".
    return -2 if value == -1 else value


Decimal.__hash__ = _decimal_hash


# --- The parts of the API that are easier to write in Python ---------------

DecimalTuple = _namedtuple("DecimalTuple", "sign digits exponent")


def _as_tuple(self):
    """Return `(sign, digits, exponent)`, as `decimal.Decimal.as_tuple` does."""
    negative, digits, exponent = self._components()
    return DecimalTuple(int(negative), tuple(int(d) for d in digits), exponent)


def _as_integer_ratio(self):
    """Return the value as an exact `(numerator, denominator)` pair."""
    negative, digits, exponent = self._components()
    numerator = int(digits)
    if negative:
        numerator = -numerator
    if exponent >= 0:
        return (numerator * 10**exponent, 1)
    denominator = 10**-exponent
    from math import gcd as _gcd

    common = _gcd(numerator, denominator)
    return (numerator // common, denominator // common)


def _format(self, specification=""):
    """Format the value, following `decimal.Decimal.__format__`.

    The empty specification -- what an f-string with no `:` uses, and by far
    the common case -- is `str()`, and is answered here. Everything else is
    handed to the standard library, which has the whole mini-language for
    thousands separators, alignment, `%` and the rest. The detour is exact:
    building a `decimal.Decimal` from our text loses nothing, and formatting
    does not depend on the context precision.
    """
    if specification == "":
        return self.to_string()
    import decimal as _stdlib

    return format(_stdlib.Decimal(self.to_string()), specification)


def _reduce(self):
    return (Decimal, (self.to_string(),))


def _copy(self):
    return self.copy()


def _deepcopy(self, memo=None):
    return self.copy()


def _from_float(cls, value):
    """Build a Decimal from a float exactly, like `decimal.Decimal.from_float`."""
    return cls(float(value))


def _real(self):
    return self


def _imaginary(self):
    return Decimal(0)


Decimal.as_tuple = _as_tuple
Decimal.as_integer_ratio = _as_integer_ratio
Decimal.__format__ = _format
Decimal.__reduce__ = _reduce
Decimal.__copy__ = _copy
Decimal.__deepcopy__ = _deepcopy
Decimal.from_float = classmethod(_from_float)
Decimal.real = property(_real)
Decimal.imag = property(_imaginary)


# --- Rounding modes --------------------------------------------------------
#
# The names exist so that code written against `decimal` imports cleanly. Only
# ROUND_HALF_EVEN is actually available: setting the context to any of the
# others raises, rather than silently rounding a different way.

ROUND_DOWN = "ROUND_DOWN"
ROUND_HALF_UP = "ROUND_HALF_UP"
ROUND_HALF_EVEN = "ROUND_HALF_EVEN"
ROUND_CEILING = "ROUND_CEILING"
ROUND_FLOOR = "ROUND_FLOOR"
ROUND_UP = "ROUND_UP"
ROUND_HALF_DOWN = "ROUND_HALF_DOWN"
ROUND_05UP = "ROUND_05UP"


# --- Exceptions ------------------------------------------------------------
#
# `decimal` raises its own signal classes. decimo raises the built-in ones,
# because a Mojo error can only be turned into a CPython global exception type
# and a module-level Python class is not one of those.
#
# So the two names that decimo actually raises are aliases for what it raises,
# and `except DivisionByZero` and `except ZeroDivisionError` both work. The
# rest are real classes, present so that code written against `decimal`
# imports cleanly; decimo has no signals, so it never raises them.

DivisionByZero = ZeroDivisionError
"""Raised by `/`, `//`, `%` and `divmod` when the divisor is zero."""

InvalidOperation = ValueError
"""Raised by the constructor on a string that is not a decimal, and by
`sqrt`, `ln` and `log10` on a value outside their domain."""


class DecimalException(ArithmeticError):
    """Base class for the decimal signals decimo does not raise."""


class Clamped(DecimalException):
    """Exponent adjusted to fit the representable range."""


class ConversionSyntax(DecimalException):
    """A string that is not a valid decimal."""


class DivisionImpossible(DecimalException):
    """The integer part of a division has too many digits."""


class DivisionUndefined(DecimalException, ZeroDivisionError):
    """Zero divided by zero."""


class Inexact(DecimalException):
    """A result had to be rounded."""


class InvalidContext(DecimalException):
    """The context itself is invalid."""


class Rounded(DecimalException):
    """Digits were discarded, whether or not the value changed."""


class Subnormal(DecimalException):
    """A result was subnormal before rounding."""


class Overflow(Inexact, Rounded):
    """A result was too large to represent."""


class Underflow(Inexact, Rounded, Subnormal):
    """A result was too small to represent."""


class FloatOperation(DecimalException, TypeError):
    """A float and a Decimal were mixed where that is not allowed."""


# --- Context ---------------------------------------------------------------
#
# `decimal` reads its precision out of a per-thread context, and so do we. The
# value itself lives in Mojo -- see the comment at the top of
# `python/decimo_module.mojo` -- because that is where the arithmetic reads it.
# This class is the same interface over it.
#
# One context, not one per thread: Mojo's global is process-wide. That is a
# real difference from `decimal`, and it is written down rather than hidden.


class Context:
    """The working precision and rounding mode, as `decimal.Context` has them.

    Only `prec` is settable. The other attributes are here so that code copied
    from a `decimal` program still reads, and they refuse any value that would
    change the answer.
    """

    __slots__ = ("_Emin", "_Emax", "_capitals", "_clamp", "flags", "traps")

    def __init__(
        self,
        prec=None,
        rounding=None,
        Emin=None,
        Emax=None,
        capitals=None,
        clamp=None,
        flags=None,
        traps=None,
    ):
        if prec is not None:
            self.prec = prec
        if rounding is not None:
            self.rounding = rounding
        self._Emin = Emin if Emin is not None else -999999
        self._Emax = Emax if Emax is not None else 999999
        self._capitals = 1 if capitals is None else capitals
        self._clamp = 0 if clamp is None else clamp
        self.flags = {} if flags is None else flags
        self.traps = {} if traps is None else traps

    # `prec` is the whole point: it reads and writes the value the Mojo side
    # consults on every operation.
    @property
    def prec(self):
        return _get_precision()

    @prec.setter
    def prec(self, value):
        value = int(value)
        if value < 1:
            raise ValueError("prec must be at least 1")
        _set_precision(value)

    @property
    def rounding(self):
        return ROUND_HALF_EVEN

    @rounding.setter
    def rounding(self, value):
        if value != ROUND_HALF_EVEN:
            raise NotImplementedError(
                "decimo rounds ROUND_HALF_EVEN only; "
                f"{value!r} would give different answers"
            )

    @property
    def Emin(self):
        return self._Emin

    @property
    def Emax(self):
        return self._Emax

    @property
    def capitals(self):
        return self._capitals

    @property
    def clamp(self):
        return self._clamp

    def copy(self):
        return Context(prec=self.prec)

    __copy__ = copy

    def clear_flags(self):
        self.flags = {}

    def clear_traps(self):
        self.traps = {}

    def create_decimal(self, value="0"):
        """Build a Decimal, then round it to this context's precision."""
        return +Decimal(value)

    def create_decimal_from_float(self, value):
        return +Decimal(float(value))

    def __repr__(self):
        return (
            f"Context(prec={self.prec}, rounding={self.rounding}, "
            f"Emin={self.Emin}, Emax={self.Emax}, "
            f"capitals={self.capitals}, clamp={self.clamp})"
        )


_CONTEXT = Context()


def getcontext():
    """Return the current context."""
    return _CONTEXT


def setcontext(context):
    """Adopt `context`'s precision as the current one."""
    _CONTEXT.prec = context.prec


class _LocalContext:
    """What `localcontext()` returns: restores the precision on the way out."""

    __slots__ = ("_context", "_saved")

    def __init__(self, context):
        self._context = context
        self._saved = None

    def __enter__(self):
        self._saved = _CONTEXT.prec
        if self._context is not None:
            _CONTEXT.prec = self._context.prec
        return _CONTEXT

    def __exit__(self, *exception):
        _CONTEXT.prec = self._saved
        return False


def localcontext(ctx=None, **kwargs):
    """Use a different precision inside a `with` block, then put it back.

    with localcontext() as context:
        context.prec = 100
        ...
    """
    if kwargs:
        ctx = Context(prec=ctx.prec if ctx is not None else _CONTEXT.prec)
        for key, value in kwargs.items():
            setattr(ctx, key, value)
    return _LocalContext(ctx)


# `decimal` exposes these two; a program that prints them should still work.
DefaultContext = Context()
BasicContext = Context()

MAX_PREC = 999999999999999999
MAX_EMAX = 999999999999999999
MIN_EMIN = -999999999999999999
MIN_ETINY = MIN_EMIN - (MAX_PREC - 1)
HAVE_THREADS = False
HAVE_CONTEXTVAR = False

# Also expose as BigDecimal for users who prefer the full name.
BigDecimal = Decimal

__all__ = [
    "Decimal",
    "BigDecimal",
    "DecimalTuple",
    "Context",
    "getcontext",
    "setcontext",
    "localcontext",
    "DefaultContext",
    "BasicContext",
    "ROUND_DOWN",
    "ROUND_HALF_UP",
    "ROUND_HALF_EVEN",
    "ROUND_CEILING",
    "ROUND_FLOOR",
    "ROUND_UP",
    "ROUND_HALF_DOWN",
    "ROUND_05UP",
    "DecimalException",
    "Clamped",
    "InvalidOperation",
    "ConversionSyntax",
    "DivisionByZero",
    "DivisionImpossible",
    "DivisionUndefined",
    "Inexact",
    "InvalidContext",
    "Rounded",
    "Subnormal",
    "Overflow",
    "Underflow",
    "FloatOperation",
    "MAX_PREC",
    "MAX_EMAX",
    "MIN_EMIN",
    "MIN_ETINY",
    "HAVE_THREADS",
    "HAVE_CONTEXTVAR",
]
