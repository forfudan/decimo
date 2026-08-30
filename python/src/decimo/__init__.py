"""decimo: Arbitrary-precision decimal arithmetic for Python, powered by Mojo.

A drop-in replacement for the standard library's `decimal`:

    from decimo import Decimal, getcontext

    getcontext().prec = 50
    print(Decimal(1) / Decimal(7))

The rule this package follows is that anything it cannot do exactly the way
`decimal` does it should refuse, not answer differently. Where a feature is
missing you get an explicit error; you never get a quietly different number.

What is not here yet: NaN and infinity, the signal/trap machinery, and
ROUND_05UP.
"""

from ._version import __version__ as __version__

try:
    from ._decimo import Decimal, Decimal128 as _Decimal128
    from ._decimo import decimal128_max_value as _decimal128_max_value
    from ._decimo import decimal128_min_value as _decimal128_min_value
    from ._decimo import get_precision as _get_precision
    from ._decimo import set_precision as _set_precision
    from ._decimo import pi as _pi
    from ._decimo import e as _e
    from ._decimo import get_rounding as _get_rounding
    from ._decimo import set_rounding as _set_rounding
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

# `__str__` is not in this list: `tp_str` is a real slot in the Mojo
# module, and assigning the dunder here would put CPython's dispatcher back
# in front of it.
#
# The comparisons and `+`, `-`, `*`, `/`, `**` are not in this list. They are
# registered as real CPython number slots by the Mojo module, so the operator
# calls a C function directly instead of looking `__add__` up in the type
# dictionary on every operation. Assigning them here would undo that:
# `type.__setattr__` puts `slot_nb_add` back in the slot, which is exactly the
# indirection being avoided -- and for `**` it would also lose
# `pow(3, x, 7)`, which that dispatcher refuses before Python 3.14.
for _name in (
    "__floordiv__",
    "__rfloordiv__",
    "__mod__",
    "__rmod__",
    "__divmod__",
    "__rdivmod__",
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


# --- The fixed-width type --------------------------------------------------
#
# `Decimal128` is 96 bits of coefficient and a scale from 0 to 28, in sixteen
# bytes that own nothing -- the layout .NET's `System.Decimal` and Rust's
# `rust_decimal` use. `Decimal` is the arbitrary-precision one and is what a
# program reaching for `decimal.Decimal` wants; this is the one to reach for
# when the values are money and the shape of them is known.
#
# Its dunders need the same assignment as `Decimal`'s, and for the same
# reason. `+`, `-`, `*`, `/` and the comparisons are real slots in the Mojo
# module and are left alone.
Decimal128 = _Decimal128

for _name in (
    "__neg__",
    "__pos__",
    "__abs__",
    "__bool__",
    "__int__",
    "__float__",
    "__floordiv__",
    "__rfloordiv__",
    "__mod__",
    "__rmod__",
    "__divmod__",
    "__pow__",
):
    setattr(Decimal128, _name, Decimal128.__dict__[_name])
del _name

Decimal128.__repr__ = Decimal128.to_repr


def _decimal128_round(self, ndigits=None):
    """`round(x)` and `round(x, n)`.

    With no argument Python expects an `int` back, and with one it expects
    the same type as the input, which is what `decimal` does too.
    """
    if ndigits is None:
        return int(self._round(0))
    return self._round(ndigits)


def _decimal128_as_tuple(self):
    """Return `(sign, digits, exponent)`, as `decimal.Decimal.as_tuple` does."""
    text = str(self)
    negative = text.startswith("-")
    if negative:
        text = text[1:]
    point = text.find(".")
    if point < 0:
        digits, exponent = text, 0
    else:
        digits, exponent = text[:point] + text[point + 1 :], -(len(text) - point - 1)
    return DecimalTuple(int(negative), tuple(int(d) for d in digits), exponent)


def _decimal128_to_ieee754(self):
    """The sixteen bytes of the IEEE 754 decimal128 interchange format.

    Little-endian, which is the order BSON and Intel's library store them in.
    """
    return bytes.fromhex(self._to_ieee754_hex())[::-1]


def _decimal128_from_ieee754(data):
    """Read sixteen little-endian bytes of IEEE 754 decimal128."""
    if len(data) != 16:
        raise ValueError("a decimal128 is sixteen bytes")
    return Decimal128()._from_ieee754_hex(bytes(data)[::-1].hex())


def _decimal128_reduce(self):
    return (Decimal128, (str(self),))


def _decimal128_copy(self, memo=None):
    """A `Decimal128` is a value; there is nothing to share, so a copy is
    itself."""
    return self


def _decimal128_format(self, specification=""):
    """Format the value, following `decimal.Decimal.__format__`.

    The empty specification -- what an f-string with no `:` uses -- is
    `str()`. Everything else goes to the standard library's mini-language
    through `decimal.Decimal`, which is exact: the text this type produces
    parses back into the same digits.
    """
    if specification == "":
        return str(self)
    import decimal as _stdlib

    return format(_stdlib.Decimal(str(self)), specification)


def _decimal128_compare(self, other):
    """-1, 0 or 1, as `decimal.Decimal.compare` gives it."""
    other = other if isinstance(other, Decimal128) else Decimal128(other)
    if self < other:
        return Decimal128(-1)
    if self > other:
        return Decimal128(1)
    return Decimal128(0)


def _decimal128_copy_sign(self, other):
    """Self with the sign of other, as `decimal.Decimal.copy_sign` does."""
    other = other if isinstance(other, Decimal128) else Decimal128(other)
    magnitude = abs(self)
    return -magnitude if other.is_signed() else magnitude


def _decimal128_copy_abs(self):
    """The magnitude, without rounding."""
    return abs(self)


def _decimal128_copy_negate(self):
    """The negation, without rounding."""
    return -self


def _decimal128_to_integral_value(self, rounding=None):
    """The value rounded to a whole number, keeping the type."""
    if rounding is None:
        return self._round(0)
    with localcontext() as context:
        context.rounding = rounding
        return self._round(0)


def _decimal128_as_integer_ratio(self):
    """The value as an exact `(numerator, denominator)` pair."""
    negative, digits, exponent = self.as_tuple()
    numerator = int("".join(str(d) for d in digits) or "0")
    if negative:
        numerator = -numerator
    if exponent >= 0:
        return (numerator * 10**exponent, 1)
    denominator = 10**-exponent
    from math import gcd as _gcd

    common = _gcd(numerator, denominator)
    return (numerator // common, denominator // common)


def _decimal128_from_float(cls, value):
    """Build one from a float, as `decimal.Decimal.from_float` does."""
    return cls(float(value))


def _decimal128_is_finite(self):
    """True. This type has no infinities and no NaNs."""
    return True


def _decimal128_is_nan(self):
    """False. This type has no NaNs."""
    return False


def _decimal128_is_infinite(self):
    """False. This type has no infinities."""
    return False


def _decimal128_to_eng_string(self):
    """The value in engineering notation, as `decimal.to_eng_string` gives it.

    Which is not always exponential: the rule is the specification's, and it
    reads the exponent the value already carries, so `Decimal128("123456")`
    is `123456` and `Decimal128("1.23E+5")` -- the same number with a
    different exponent -- is `123E+3`. The Mojo method is unconditional, so
    the rule is applied here.
    """
    import decimal as _stdlib

    return _stdlib.Decimal(self.as_tuple()).to_eng_string()


def _decimal128_to_scientific_string(self):
    """The value in scientific notation, as `decimal`'s `str` gives it."""
    import decimal as _stdlib

    return str(_stdlib.Decimal(self.as_tuple()))


Decimal128.to_eng_string = _decimal128_to_eng_string
Decimal128.to_scientific_string = _decimal128_to_scientific_string
Decimal128.compare = _decimal128_compare
Decimal128.copy_sign = _decimal128_copy_sign
Decimal128.copy_abs = _decimal128_copy_abs
Decimal128.copy_negate = _decimal128_copy_negate
Decimal128.to_integral_value = _decimal128_to_integral_value
Decimal128.to_integral = _decimal128_to_integral_value
Decimal128.as_integer_ratio = _decimal128_as_integer_ratio
Decimal128.from_float = classmethod(_decimal128_from_float)
Decimal128.is_finite = _decimal128_is_finite
Decimal128.is_nan = _decimal128_is_nan
Decimal128.is_infinite = _decimal128_is_infinite
Decimal128.__round__ = _decimal128_round
Decimal128.__reduce__ = _decimal128_reduce
Decimal128.__copy__ = _decimal128_copy
Decimal128.__deepcopy__ = _decimal128_copy
Decimal128.__format__ = _decimal128_format
Decimal128.as_tuple = _decimal128_as_tuple
Decimal128.to_ieee754 = _decimal128_to_ieee754
Decimal128.from_ieee754 = staticmethod(_decimal128_from_ieee754)

try:
    # The type says it lives in the extension module otherwise, which is an
    # implementation detail, and pickle needs a name it can find again.
    Decimal128.__module__ = "decimo"
except (AttributeError, TypeError):  # pragma: no cover -- older bindings
    pass

#: The largest and smallest values the type holds, which are fixed rather
#: than a matter of context.
Decimal128.MAX = _decimal128_max_value()
Decimal128.MIN = _decimal128_min_value()

#: A shorter name for the same type, as the Mojo library has. `Decimal128`
#: is the name it answers to: `repr` and `__name__` both say that one.
Dec128 = Decimal128


# Hashing is a `tp_hash` slot in the Mojo module: a number's hash has to agree
# with every other numeric type that compares equal to it, and doing that here
# -- `pow(10, exponent, modulus)` over the digits as text -- cost 493 ns
# against `decimal`'s 27. Assigning `__hash__` here would put CPython's own
# dispatcher back in the slot, so nothing does.


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


def _from_number(cls, value):
    """Build a Decimal from an int, float or Decimal, as in Python 3.14."""
    if isinstance(value, (int, float, Decimal)):
        return cls(value)
    raise TypeError(
        f"conversion from {type(value).__name__} to Decimal is not supported"
    )


def _complex(self):
    return complex(float(self))


# --- What needs an Emin ----------------------------------------------------
#
# decimo has unbounded exponents, so the Mojo library has no smallest value to
# step to and no idea what "subnormal" would mean. `decimal` answers these
# from `Emin`, which lives on the context here, so the methods that need
# it are finished off in Python. Everything else in this file's surface is the
# native method as it comes.

_next_plus = Decimal.next_plus
_next_minus = Decimal.next_minus
_next_toward = Decimal.next_toward
_number_class = Decimal.number_class


def _etiny():
    context = getcontext()
    return context.Emin - context.prec + 1


def _wrapped_next_plus(self):
    """The smallest value larger than self, `decimal`'s Etiny above zero."""
    if self.is_zero():
        return Decimal(f"1E{_etiny()}")
    return _next_plus(self)


def _wrapped_next_minus(self):
    """The largest value smaller than self, `decimal`'s -Etiny below zero."""
    if self.is_zero():
        return Decimal(f"-1E{_etiny()}")
    return _next_minus(self)


def _wrapped_next_toward(self, other):
    """The value next to self towards other."""
    if self.is_zero() and self != other:
        sign = "-" if other < 0 else ""
        return Decimal(f"{sign}1E{_etiny()}")
    return _next_toward(self, other)


def _is_normal(self):
    """Whether self is non-zero and no smaller than the context allows."""
    return not self.is_zero() and self.adjusted() >= getcontext().Emin


def _is_subnormal(self):
    """Whether self is non-zero and below the context's smallest exponent."""
    return not self.is_zero() and self.adjusted() < getcontext().Emin


def _wrapped_number_class(self):
    """The kind of number self is; `Emin` is what makes one subnormal."""
    name = _number_class(self)
    if name.endswith("Normal") and self.adjusted() < getcontext().Emin:
        return name[0] + "Subnormal"
    return name


Decimal.as_tuple = _as_tuple
Decimal.as_integer_ratio = _as_integer_ratio
Decimal.__format__ = _format
Decimal.__reduce__ = _reduce
Decimal.__copy__ = _copy
Decimal.__deepcopy__ = _deepcopy
Decimal.__complex__ = _complex
Decimal.from_float = classmethod(_from_float)
Decimal.from_number = classmethod(_from_number)
Decimal.real = property(_real)
Decimal.imag = property(_imaginary)
Decimal.next_plus = _wrapped_next_plus
Decimal.next_minus = _wrapped_next_minus
Decimal.next_toward = _wrapped_next_toward
Decimal.number_class = _wrapped_number_class
Decimal.is_normal = _is_normal
Decimal.is_subnormal = _is_subnormal
try:
    # `decimal.Decimal.__module__` is "decimal"; without this the type says
    # it lives in the extension module, which is an implementation detail.
    Decimal.__module__ = "decimo"
except (AttributeError, TypeError):  # pragma: no cover -- older bindings
    pass


# --- Rounding modes --------------------------------------------------------
#
# All of `decimal`'s modes except ROUND_05UP, which nothing in the Mojo
# library implements; setting it raises rather than rounding a different way.
# Arithmetic, `quantize`, `round(x, n)` and `to_integral_value` are exact under
# every mode. `sqrt`, `exp`, `ln`, `log10` and `**` are exact too: the Mojo
# library widens until the whole interval its own error allows rounds one
# way, rather than adding a fixed number of guard digits.

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


_ROUNDING_MODES = (
    "ROUND_HALF_EVEN",
    "ROUND_HALF_UP",
    "ROUND_HALF_DOWN",
    "ROUND_DOWN",
    "ROUND_UP",
    "ROUND_CEILING",
    "ROUND_FLOOR",
)


def _checked_prec(value):
    value = int(value)
    if value < 1:
        raise ValueError("prec must be at least 1")
    return value


def _checked_rounding(value):
    if value not in _ROUNDING_MODES:
        if value == "ROUND_05UP":
            raise NotImplementedError("decimo does not implement ROUND_05UP")
        raise TypeError(f"invalid rounding mode: {value!r}")
    return value


class Context:
    """The working precision and rounding mode, as `decimal.Context` has them.

    `prec` and `rounding` are what an operation consults. The other attributes
    are here so that code copied from a `decimal` program still reads; `Emin`,
    `Emax`, `flags` and `traps` are stored and never acted on, since decimo has
    unbounded exponents and no signals.

    A `Context` you build yourself is a value: it changes nothing until you
    hand it to `setcontext()` or `localcontext()`. The one `getcontext()`
    returns is live -- its `prec` and `rounding` are the process-wide state
    every operation reads.
    """

    __slots__ = (
        "_prec",
        "_rounding",
        "_Emin",
        "_Emax",
        "_capitals",
        "_clamp",
        "flags",
        "traps",
    )

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
        self._prec = 28 if prec is None else _checked_prec(prec)
        self._rounding = (
            ROUND_HALF_EVEN if rounding is None else _checked_rounding(rounding)
        )
        self._Emin = Emin if Emin is not None else -999999
        self._Emax = Emax if Emax is not None else 999999
        self._capitals = 1 if capitals is None else capitals
        self._clamp = 0 if clamp is None else clamp
        self.flags = {} if flags is None else dict(flags)
        self.traps = {} if traps is None else dict(traps)

    @property
    def prec(self):
        return self._prec

    @prec.setter
    def prec(self, value):
        self._prec = _checked_prec(value)

    @property
    def rounding(self):
        return self._rounding

    @rounding.setter
    def rounding(self, value):
        self._rounding = _checked_rounding(value)

    @property
    def Emin(self):
        return self._Emin

    @Emin.setter
    def Emin(self, value):
        self._Emin = int(value)

    @property
    def Emax(self):
        return self._Emax

    @Emax.setter
    def Emax(self, value):
        self._Emax = int(value)

    @property
    def capitals(self):
        return self._capitals

    @capitals.setter
    def capitals(self, value):
        self._capitals = int(value)

    @property
    def clamp(self):
        return self._clamp

    @clamp.setter
    def clamp(self, value):
        self._clamp = int(value)

    def copy(self):
        return Context(
            prec=self.prec,
            rounding=self.rounding,
            Emin=self.Emin,
            Emax=self.Emax,
            capitals=self.capitals,
            clamp=self.clamp,
            flags=self.flags,
            traps=self.traps,
        )

    __copy__ = copy

    def clear_flags(self):
        self.flags = {}

    def clear_traps(self):
        self.traps = {}

    def create_decimal(self, value="0"):
        """Build a Decimal, then round it to this context's precision."""
        with localcontext(self):
            return +Decimal(value)

    def create_decimal_from_float(self, value):
        with localcontext(self):
            return +Decimal(float(value))

    def Etiny(self):
        return self.Emin - self.prec + 1

    def Etop(self):
        return self.Emax - self.prec + 1

    def __repr__(self):
        return (
            f"Context(prec={self.prec}, rounding={self.rounding}, "
            f"Emin={self.Emin}, Emax={self.Emax}, "
            f"capitals={self.capitals}, clamp={self.clamp}, "
            f"flags={sorted(self.flags)}, traps={sorted(self.traps)})"
        )


class _CurrentContext(Context):
    """What `getcontext()` returns: `prec` and `rounding` live in the Mojo
    module, where every operation reads them without a Python call."""

    __slots__ = ()

    @property
    def prec(self):
        return _get_precision()

    @prec.setter
    def prec(self, value):
        _set_precision(_checked_prec(value))

    @property
    def rounding(self):
        return _get_rounding()

    @rounding.setter
    def rounding(self, value):
        _set_rounding(_checked_rounding(value))


_CONTEXT = _CurrentContext()


def getcontext():
    """Return the current context. One per process, not per thread."""
    return _CONTEXT


def setcontext(context):
    """Make `context`'s settings the current ones."""
    _CONTEXT.prec = context.prec
    _CONTEXT.rounding = context.rounding
    _CONTEXT.Emin = context.Emin
    _CONTEXT.Emax = context.Emax
    _CONTEXT.capitals = context.capitals
    _CONTEXT.clamp = context.clamp
    _CONTEXT.flags = dict(context.flags)
    _CONTEXT.traps = dict(context.traps)


class _LocalContext:
    """What `localcontext()` returns: restores the settings on the way out."""

    __slots__ = ("_context", "_saved")

    def __init__(self, context):
        self._context = context
        self._saved = None

    def __enter__(self):
        self._saved = _CONTEXT.copy()
        if self._context is not None:
            setcontext(self._context)
        return _CONTEXT

    def __exit__(self, *exception):
        setcontext(self._saved)
        return False


def localcontext(ctx=None, **kwargs):
    """Use different settings inside a `with` block, then put them back.

    with localcontext() as context:
        context.prec = 100
        ...

    with localcontext(rounding=ROUND_DOWN):
        ...
    """
    base = (ctx if ctx is not None else _CONTEXT).copy()
    for key, value in kwargs.items():
        if key not in (
            "prec",
            "rounding",
            "Emin",
            "Emax",
            "capitals",
            "clamp",
            "flags",
            "traps",
        ):
            raise TypeError(f"'{key}' is an invalid keyword argument for this function")
        setattr(base, key, value)
    return _LocalContext(base)


# `decimal` exposes these; a program that prints them should still work.
# Same settings as in `decimal`: BasicContext and ExtendedContext are nine
# digits, and BasicContext rounds half up.
DefaultContext = Context()
BasicContext = Context(prec=9, rounding=ROUND_HALF_UP)
ExtendedContext = Context(prec=9, rounding=ROUND_HALF_EVEN)

MAX_PREC = 999999999999999999
MAX_EMAX = 999999999999999999
MIN_EMIN = -999999999999999999
MIN_ETINY = MIN_EMIN - (MAX_PREC - 1)
HAVE_THREADS = False
HAVE_CONTEXTVAR = False

# Also expose as BigDecimal for users who prefer the full name.
BigDecimal = Decimal


def pi(prec=None):
    """Return pi, to `prec` digits or to the context precision.

    `decimal` has no pi; its documentation gives a recipe to write one. This
    is computed in Mojo by Chudnovsky with binary splitting, so a thousand
    digits is a fraction of a millisecond.

    >>> import decimo
    >>> decimo.pi(30)
    Decimal('3.14159265358979323846264338328')
    """
    if prec is None:
        return _pi()
    with localcontext(prec=prec):
        return _pi()


def e(prec=None):
    """Return e, to `prec` digits or to the context precision."""
    if prec is None:
        return _e()
    with localcontext(prec=prec):
        return _e()


# --- Context as `decimal` has it: an object you can compute with ------------
#
# `ctx.divide(x, y)` is `x / y` under `ctx`, without disturbing the current
# context. Every one of these is that same sentence, so they are built from
# one table rather than written out sixty times: the operator ones by the
# operator, the rest by the method of the same name on `Decimal`.

_CONTEXT_OPERATORS = {
    "add": lambda x, y: x + y,
    "subtract": lambda x, y: x - y,
    "multiply": lambda x, y: x * y,
    "divide": lambda x, y: x / y,
    "divide_int": lambda x, y: x // y,
    "remainder": lambda x, y: x % y,
    "divmod": divmod,
    "minus": lambda x: -x,
    "plus": lambda x: +x,
    "abs": abs,
    "copy_decimal": lambda x: x.copy(),
    "to_sci_string": str,
    "radix": lambda: Decimal(10),
}

_CONTEXT_METHODS = (
    "compare compare_signal compare_total compare_total_mag copy_abs"
    " copy_negate copy_sign exp fma is_canonical is_finite is_infinite is_nan"
    " is_normal is_qnan is_signed is_snan is_subnormal is_zero ln log10 logb"
    " logical_and logical_invert logical_or logical_xor max max_mag min"
    " min_mag next_minus next_plus next_toward normalize number_class"
    " quantize remainder_near rotate same_quantum scaleb shift sqrt"
    " to_eng_string to_integral to_integral_exact to_integral_value canonical"
).split()


def _as_operand(value):
    """What a context method accepts: a decimal, or anything that becomes one."""
    return value if isinstance(value, Decimal) else Decimal(value)


def _install_context_methods():
    def make_operator(operation):
        def method(self, *operands):
            with localcontext(self):
                return operation(*(_as_operand(x) for x in operands))

        return method

    def make_method(name):
        def method(self, value, *rest):
            with localcontext(self):
                return getattr(_as_operand(value), name)(
                    *(_as_operand(x) for x in rest)
                )

        return method

    for name, operation in _CONTEXT_OPERATORS.items():
        function = make_operator(operation)
        function.__name__ = name
        function.__doc__ = (
            f"`{name}` under this context, leaving the current one alone."
        )
        setattr(Context, name, function)

    for name in _CONTEXT_METHODS:
        function = make_method(name)
        function.__name__ = name
        function.__doc__ = (
            f"`Decimal.{name}` under this context, leaving the current one alone."
        )
        setattr(Context, name, function)

    def power(self, a, b, modulo=None):
        """`a ** b` under this context, or `pow(a, b, modulo)` with three."""
        with localcontext(self):
            if modulo is None:
                return _as_operand(a) ** _as_operand(b)
            return pow(_as_operand(a), _as_operand(b), _as_operand(modulo))

    Context.power = power


_install_context_methods()


__all__ = [
    "Decimal",
    "pi",
    "e",
    "BigDecimal",
    "DecimalTuple",
    "Context",
    "getcontext",
    "setcontext",
    "localcontext",
    "DefaultContext",
    "BasicContext",
    "ExtendedContext",
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
