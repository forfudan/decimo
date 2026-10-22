# ===----------------------------------------------------------------------=== #
# Decimo: A Mojo library for arbitrary-precision decimal and integer types
# ===----------------------------------------------------------------------=== #
"""Tests for an argument sitting a hair from a limit the destination holds.

Every function here has arguments whose true value is so close to a float
that the loop deciding the rounding cannot place it at any width it reaches.
It widens to its limit and raises, which is the bug these tests pin: the
three nearest modes settle by luck, and the four directed ones do not settle
at all.

The reference is a CPython program, `local/gen_binary_limit.py`, which forms
the value with `decimal` at four thousand digits and rounds it to the bits
asked for with exact rational arithmetic.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigfloat.arithmetics import add as bigfloat_add
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.exponential import (
    exp10,
    exp2,
    expm1,
    ln,
    log10,
    log1p,
    log2,
)
from decimo.bigfloat.hyperbolic import arcsinh, arctanh, sinh, tanh
from decimo.bigfloat.trigonometric import arcsin, arctan, sin, tan
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


def _modes() -> List[RoundingMode]:
    """All seven of them, in the order the rounding primitive documents.

    Returns:
        The modes.
    """
    return [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]


def _beside(whole: BigInt, offset: Int, shift: Int) raises -> BigFloat:
    """The value `whole + offset * 2^-shift`, held exactly.

    Args:
        whole: The number the argument sits beside.
        offset: Which side, as plus or minus one.
        shift: How far off, as a power of two.

    Returns:
        The value, with its precision set to the bits it actually needs.

    Raises:
        Error: Propagated from the construction.

    Notes:

    The precision is the significand's own bit length and not a round number,
    so these arguments carry no padding. The padding is the subject of its
    own test below, which is where it belongs: a value and the same value
    written with spare bits have to be answered alike.
    """
    var scaled = (whole << shift) + BigInt(offset)
    var negative = scaled.is_negative()
    var magnitude = -scaled if negative else scaled.copy()
    return BigFloat(
        significand=magnitude,
        exponent=-shift,
        precision=magnitude.bit_length(),
        sign=negative,
    )


def _call(
    name: String, x: BigFloat, precision: Int, mode: RoundingMode
) raises -> BigFloat:
    """Dispatches a row's function by name.

    Args:
        name: The function.
        x: The argument.
        precision: The bits the answer keeps.
        mode: Which way to round.

    Returns:
        The answer.

    Raises:
        Error: For an unknown name, or propagated from the function.
    """
    if name == "ln":
        return ln(x, precision, mode)
    if name == "log2":
        return log2(x, precision, mode)
    if name == "log10":
        return log10(x, precision, mode)
    if name == "exp2":
        return exp2(x, precision, mode)
    if name == "exp10":
        return exp10(x, precision, mode)
    if name == "expm1":
        return expm1(x, precision, mode)
    if name == "log1p":
        return log1p(x, precision, mode)
    raise Error(String("the test has no function named ") + name)


@no_inline
def _rows() -> List[String]:
    """The reference table.

    Returns:
        One row per function, argument and mode. The fields are the function,
        the whole number the argument sits beside, which side it sits on, the
        power of two it sits off by, the destination precision, the mode's
        index, and the expected significand, exponent and sign.

    Notes:

    `@no_inline` is not decoration. A table this size materialized inside a
    caller hangs the Mojo compiler.
    """
    return [
        "ln 1 1 2000 28 0 268435455 -2028 0",
        "ln 1 1 2000 28 1 134217728 -2027 0",
        "ln 1 1 2000 28 2 134217728 -2027 0",
        "ln 1 1 2000 28 3 268435455 -2028 0",
        "ln 1 1 2000 28 4 134217728 -2027 0",
        "ln 1 1 2000 28 5 134217728 -2027 0",
        "ln 1 1 2000 28 6 134217728 -2027 0",
        "ln 1 -1 2000 28 0 134217728 -2027 1",
        "ln 1 -1 2000 28 1 134217729 -2027 1",
        "ln 1 -1 2000 28 2 134217728 -2027 1",
        "ln 1 -1 2000 28 3 134217729 -2027 1",
        "ln 1 -1 2000 28 4 134217728 -2027 1",
        "ln 1 -1 2000 28 5 134217728 -2027 1",
        "ln 1 -1 2000 28 6 134217728 -2027 1",
        "ln 1 1 2000 20 0 1048575 -2020 0",
        "ln 1 1 2000 20 1 524288 -2019 0",
        "ln 1 1 2000 20 2 524288 -2019 0",
        "ln 1 1 2000 20 3 1048575 -2020 0",
        "ln 1 1 2000 20 4 524288 -2019 0",
        "ln 1 1 2000 20 5 524288 -2019 0",
        "ln 1 1 2000 20 6 524288 -2019 0",
        "ln 1 -1 2000 20 0 524288 -2019 1",
        "ln 1 -1 2000 20 1 524289 -2019 1",
        "ln 1 -1 2000 20 2 524288 -2019 1",
        "ln 1 -1 2000 20 3 524289 -2019 1",
        "ln 1 -1 2000 20 4 524288 -2019 1",
        "ln 1 -1 2000 20 5 524288 -2019 1",
        "ln 1 -1 2000 20 6 524288 -2019 1",
        "log2 2 1 2000 28 0 134217728 -27 0",
        "log2 2 1 2000 28 1 134217729 -27 0",
        "log2 2 1 2000 28 2 134217729 -27 0",
        "log2 2 1 2000 28 3 134217728 -27 0",
        "log2 2 1 2000 28 4 134217728 -27 0",
        "log2 2 1 2000 28 5 134217728 -27 0",
        "log2 2 1 2000 28 6 134217728 -27 0",
        "log2 2 -1 2000 28 0 268435455 -28 0",
        "log2 2 -1 2000 28 1 134217728 -27 0",
        "log2 2 -1 2000 28 2 134217728 -27 0",
        "log2 2 -1 2000 28 3 268435455 -28 0",
        "log2 2 -1 2000 28 4 134217728 -27 0",
        "log2 2 -1 2000 28 5 134217728 -27 0",
        "log2 2 -1 2000 28 6 134217728 -27 0",
        "log2 4 1 2000 28 0 134217728 -26 0",
        "log2 4 1 2000 28 1 134217729 -26 0",
        "log2 4 1 2000 28 2 134217729 -26 0",
        "log2 4 1 2000 28 3 134217728 -26 0",
        "log2 4 1 2000 28 4 134217728 -26 0",
        "log2 4 1 2000 28 5 134217728 -26 0",
        "log2 4 1 2000 28 6 134217728 -26 0",
        "log2 4 -1 2000 28 0 268435455 -27 0",
        "log2 4 -1 2000 28 1 134217728 -26 0",
        "log2 4 -1 2000 28 2 134217728 -26 0",
        "log2 4 -1 2000 28 3 268435455 -27 0",
        "log2 4 -1 2000 28 4 134217728 -26 0",
        "log2 4 -1 2000 28 5 134217728 -26 0",
        "log2 4 -1 2000 28 6 134217728 -26 0",
        "log2 8 1 2000 28 0 201326592 -26 0",
        "log2 8 1 2000 28 1 201326593 -26 0",
        "log2 8 1 2000 28 2 201326593 -26 0",
        "log2 8 1 2000 28 3 201326592 -26 0",
        "log2 8 1 2000 28 4 201326592 -26 0",
        "log2 8 1 2000 28 5 201326592 -26 0",
        "log2 8 1 2000 28 6 201326592 -26 0",
        "log2 8 -1 2000 28 0 201326591 -26 0",
        "log2 8 -1 2000 28 1 201326592 -26 0",
        "log2 8 -1 2000 28 2 201326592 -26 0",
        "log2 8 -1 2000 28 3 201326591 -26 0",
        "log2 8 -1 2000 28 4 201326592 -26 0",
        "log2 8 -1 2000 28 5 201326592 -26 0",
        "log2 8 -1 2000 28 6 201326592 -26 0",
        "log2 1024 1 2000 28 0 167772160 -24 0",
        "log2 1024 1 2000 28 1 167772161 -24 0",
        "log2 1024 1 2000 28 2 167772161 -24 0",
        "log2 1024 1 2000 28 3 167772160 -24 0",
        "log2 1024 1 2000 28 4 167772160 -24 0",
        "log2 1024 1 2000 28 5 167772160 -24 0",
        "log2 1024 1 2000 28 6 167772160 -24 0",
        "log2 1024 -1 2000 28 0 167772159 -24 0",
        "log2 1024 -1 2000 28 1 167772160 -24 0",
        "log2 1024 -1 2000 28 2 167772160 -24 0",
        "log2 1024 -1 2000 28 3 167772159 -24 0",
        "log2 1024 -1 2000 28 4 167772160 -24 0",
        "log2 1024 -1 2000 28 5 167772160 -24 0",
        "log2 1024 -1 2000 28 6 167772160 -24 0",
        "log10 10 1 2000 28 0 134217728 -27 0",
        "log10 10 1 2000 28 1 134217729 -27 0",
        "log10 10 1 2000 28 2 134217729 -27 0",
        "log10 10 1 2000 28 3 134217728 -27 0",
        "log10 10 1 2000 28 4 134217728 -27 0",
        "log10 10 1 2000 28 5 134217728 -27 0",
        "log10 10 1 2000 28 6 134217728 -27 0",
        "log10 10 -1 2000 28 0 268435455 -28 0",
        "log10 10 -1 2000 28 1 134217728 -27 0",
        "log10 10 -1 2000 28 2 134217728 -27 0",
        "log10 10 -1 2000 28 3 268435455 -28 0",
        "log10 10 -1 2000 28 4 134217728 -27 0",
        "log10 10 -1 2000 28 5 134217728 -27 0",
        "log10 10 -1 2000 28 6 134217728 -27 0",
        "log10 100 1 2000 28 0 134217728 -26 0",
        "log10 100 1 2000 28 1 134217729 -26 0",
        "log10 100 1 2000 28 2 134217729 -26 0",
        "log10 100 1 2000 28 3 134217728 -26 0",
        "log10 100 1 2000 28 4 134217728 -26 0",
        "log10 100 1 2000 28 5 134217728 -26 0",
        "log10 100 1 2000 28 6 134217728 -26 0",
        "log10 100 -1 2000 28 0 268435455 -27 0",
        "log10 100 -1 2000 28 1 134217728 -26 0",
        "log10 100 -1 2000 28 2 134217728 -26 0",
        "log10 100 -1 2000 28 3 268435455 -27 0",
        "log10 100 -1 2000 28 4 134217728 -26 0",
        "log10 100 -1 2000 28 5 134217728 -26 0",
        "log10 100 -1 2000 28 6 134217728 -26 0",
        "log10 1000 1 2000 28 0 201326592 -26 0",
        "log10 1000 1 2000 28 1 201326593 -26 0",
        "log10 1000 1 2000 28 2 201326593 -26 0",
        "log10 1000 1 2000 28 3 201326592 -26 0",
        "log10 1000 1 2000 28 4 201326592 -26 0",
        "log10 1000 1 2000 28 5 201326592 -26 0",
        "log10 1000 1 2000 28 6 201326592 -26 0",
        "log10 1000 -1 2000 28 0 201326591 -26 0",
        "log10 1000 -1 2000 28 1 201326592 -26 0",
        "log10 1000 -1 2000 28 2 201326592 -26 0",
        "log10 1000 -1 2000 28 3 201326591 -26 0",
        "log10 1000 -1 2000 28 4 201326592 -26 0",
        "log10 1000 -1 2000 28 5 201326592 -26 0",
        "log10 1000 -1 2000 28 6 201326592 -26 0",
        "log10 100000 1 2000 28 0 167772160 -25 0",
        "log10 100000 1 2000 28 1 167772161 -25 0",
        "log10 100000 1 2000 28 2 167772161 -25 0",
        "log10 100000 1 2000 28 3 167772160 -25 0",
        "log10 100000 1 2000 28 4 167772160 -25 0",
        "log10 100000 1 2000 28 5 167772160 -25 0",
        "log10 100000 1 2000 28 6 167772160 -25 0",
        "log10 100000 -1 2000 28 0 167772159 -25 0",
        "log10 100000 -1 2000 28 1 167772160 -25 0",
        "log10 100000 -1 2000 28 2 167772160 -25 0",
        "log10 100000 -1 2000 28 3 167772159 -25 0",
        "log10 100000 -1 2000 28 4 167772160 -25 0",
        "log10 100000 -1 2000 28 5 167772160 -25 0",
        "log10 100000 -1 2000 28 6 167772160 -25 0",
        "exp2 1 1 2000 28 0 134217728 -26 0",
        "exp2 1 1 2000 28 1 134217729 -26 0",
        "exp2 1 1 2000 28 2 134217729 -26 0",
        "exp2 1 1 2000 28 3 134217728 -26 0",
        "exp2 1 1 2000 28 4 134217728 -26 0",
        "exp2 1 1 2000 28 5 134217728 -26 0",
        "exp2 1 1 2000 28 6 134217728 -26 0",
        "exp10 1 1 2000 28 0 167772160 -24 0",
        "exp10 1 1 2000 28 1 167772161 -24 0",
        "exp10 1 1 2000 28 2 167772161 -24 0",
        "exp10 1 1 2000 28 3 167772160 -24 0",
        "exp10 1 1 2000 28 4 167772160 -24 0",
        "exp10 1 1 2000 28 5 167772160 -24 0",
        "exp10 1 1 2000 28 6 167772160 -24 0",
        "exp2 1 -1 2000 28 0 268435455 -27 0",
        "exp2 1 -1 2000 28 1 134217728 -26 0",
        "exp2 1 -1 2000 28 2 134217728 -26 0",
        "exp2 1 -1 2000 28 3 268435455 -27 0",
        "exp2 1 -1 2000 28 4 134217728 -26 0",
        "exp2 1 -1 2000 28 5 134217728 -26 0",
        "exp2 1 -1 2000 28 6 134217728 -26 0",
        "exp10 1 -1 2000 28 0 167772159 -24 0",
        "exp10 1 -1 2000 28 1 167772160 -24 0",
        "exp10 1 -1 2000 28 2 167772160 -24 0",
        "exp10 1 -1 2000 28 3 167772159 -24 0",
        "exp10 1 -1 2000 28 4 167772160 -24 0",
        "exp10 1 -1 2000 28 5 167772160 -24 0",
        "exp10 1 -1 2000 28 6 167772160 -24 0",
        "exp2 2 1 2000 28 0 134217728 -25 0",
        "exp2 2 1 2000 28 1 134217729 -25 0",
        "exp2 2 1 2000 28 2 134217729 -25 0",
        "exp2 2 1 2000 28 3 134217728 -25 0",
        "exp2 2 1 2000 28 4 134217728 -25 0",
        "exp2 2 1 2000 28 5 134217728 -25 0",
        "exp2 2 1 2000 28 6 134217728 -25 0",
        "exp10 2 1 2000 28 0 209715200 -21 0",
        "exp10 2 1 2000 28 1 209715201 -21 0",
        "exp10 2 1 2000 28 2 209715201 -21 0",
        "exp10 2 1 2000 28 3 209715200 -21 0",
        "exp10 2 1 2000 28 4 209715200 -21 0",
        "exp10 2 1 2000 28 5 209715200 -21 0",
        "exp10 2 1 2000 28 6 209715200 -21 0",
        "exp2 2 -1 2000 28 0 268435455 -26 0",
        "exp2 2 -1 2000 28 1 134217728 -25 0",
        "exp2 2 -1 2000 28 2 134217728 -25 0",
        "exp2 2 -1 2000 28 3 268435455 -26 0",
        "exp2 2 -1 2000 28 4 134217728 -25 0",
        "exp2 2 -1 2000 28 5 134217728 -25 0",
        "exp2 2 -1 2000 28 6 134217728 -25 0",
        "exp10 2 -1 2000 28 0 209715199 -21 0",
        "exp10 2 -1 2000 28 1 209715200 -21 0",
        "exp10 2 -1 2000 28 2 209715200 -21 0",
        "exp10 2 -1 2000 28 3 209715199 -21 0",
        "exp10 2 -1 2000 28 4 209715200 -21 0",
        "exp10 2 -1 2000 28 5 209715200 -21 0",
        "exp10 2 -1 2000 28 6 209715200 -21 0",
        "exp2 3 1 2000 28 0 134217728 -24 0",
        "exp2 3 1 2000 28 1 134217729 -24 0",
        "exp2 3 1 2000 28 2 134217729 -24 0",
        "exp2 3 1 2000 28 3 134217728 -24 0",
        "exp2 3 1 2000 28 4 134217728 -24 0",
        "exp2 3 1 2000 28 5 134217728 -24 0",
        "exp2 3 1 2000 28 6 134217728 -24 0",
        "exp10 3 1 2000 28 0 262144000 -18 0",
        "exp10 3 1 2000 28 1 262144001 -18 0",
        "exp10 3 1 2000 28 2 262144001 -18 0",
        "exp10 3 1 2000 28 3 262144000 -18 0",
        "exp10 3 1 2000 28 4 262144000 -18 0",
        "exp10 3 1 2000 28 5 262144000 -18 0",
        "exp10 3 1 2000 28 6 262144000 -18 0",
        "exp2 3 -1 2000 28 0 268435455 -25 0",
        "exp2 3 -1 2000 28 1 134217728 -24 0",
        "exp2 3 -1 2000 28 2 134217728 -24 0",
        "exp2 3 -1 2000 28 3 268435455 -25 0",
        "exp2 3 -1 2000 28 4 134217728 -24 0",
        "exp2 3 -1 2000 28 5 134217728 -24 0",
        "exp2 3 -1 2000 28 6 134217728 -24 0",
        "exp10 3 -1 2000 28 0 262143999 -18 0",
        "exp10 3 -1 2000 28 1 262144000 -18 0",
        "exp10 3 -1 2000 28 2 262144000 -18 0",
        "exp10 3 -1 2000 28 3 262143999 -18 0",
        "exp10 3 -1 2000 28 4 262144000 -18 0",
        "exp10 3 -1 2000 28 5 262144000 -18 0",
        "exp10 3 -1 2000 28 6 262144000 -18 0",
        "exp2 7 1 2000 28 0 134217728 -20 0",
        "exp2 7 1 2000 28 1 134217729 -20 0",
        "exp2 7 1 2000 28 2 134217729 -20 0",
        "exp2 7 1 2000 28 3 134217728 -20 0",
        "exp2 7 1 2000 28 4 134217728 -20 0",
        "exp2 7 1 2000 28 5 134217728 -20 0",
        "exp2 7 1 2000 28 6 134217728 -20 0",
        "exp10 7 1 2000 28 0 160000000 -4 0",
        "exp10 7 1 2000 28 1 160000001 -4 0",
        "exp10 7 1 2000 28 2 160000001 -4 0",
        "exp10 7 1 2000 28 3 160000000 -4 0",
        "exp10 7 1 2000 28 4 160000000 -4 0",
        "exp10 7 1 2000 28 5 160000000 -4 0",
        "exp10 7 1 2000 28 6 160000000 -4 0",
        "exp2 7 -1 2000 28 0 268435455 -21 0",
        "exp2 7 -1 2000 28 1 134217728 -20 0",
        "exp2 7 -1 2000 28 2 134217728 -20 0",
        "exp2 7 -1 2000 28 3 268435455 -21 0",
        "exp2 7 -1 2000 28 4 134217728 -20 0",
        "exp2 7 -1 2000 28 5 134217728 -20 0",
        "exp2 7 -1 2000 28 6 134217728 -20 0",
        "exp10 7 -1 2000 28 0 159999999 -4 0",
        "exp10 7 -1 2000 28 1 160000000 -4 0",
        "exp10 7 -1 2000 28 2 160000000 -4 0",
        "exp10 7 -1 2000 28 3 159999999 -4 0",
        "exp10 7 -1 2000 28 4 160000000 -4 0",
        "exp10 7 -1 2000 28 5 160000000 -4 0",
        "exp10 7 -1 2000 28 6 160000000 -4 0",
        "expm1 0 1 2000 28 0 134217728 -2027 0",
        "expm1 0 1 2000 28 1 134217729 -2027 0",
        "expm1 0 1 2000 28 2 134217729 -2027 0",
        "expm1 0 1 2000 28 3 134217728 -2027 0",
        "expm1 0 1 2000 28 4 134217728 -2027 0",
        "expm1 0 1 2000 28 5 134217728 -2027 0",
        "expm1 0 1 2000 28 6 134217728 -2027 0",
        "log1p 0 1 2000 28 0 268435455 -2028 0",
        "log1p 0 1 2000 28 1 134217728 -2027 0",
        "log1p 0 1 2000 28 2 134217728 -2027 0",
        "log1p 0 1 2000 28 3 268435455 -2028 0",
        "log1p 0 1 2000 28 4 134217728 -2027 0",
        "log1p 0 1 2000 28 5 134217728 -2027 0",
        "log1p 0 1 2000 28 6 134217728 -2027 0",
        "expm1 0 -1 2000 28 0 268435455 -2028 1",
        "expm1 0 -1 2000 28 1 134217728 -2027 1",
        "expm1 0 -1 2000 28 2 268435455 -2028 1",
        "expm1 0 -1 2000 28 3 134217728 -2027 1",
        "expm1 0 -1 2000 28 4 134217728 -2027 1",
        "expm1 0 -1 2000 28 5 134217728 -2027 1",
        "expm1 0 -1 2000 28 6 134217728 -2027 1",
        "log1p 0 -1 2000 28 0 134217728 -2027 1",
        "log1p 0 -1 2000 28 1 134217729 -2027 1",
        "log1p 0 -1 2000 28 2 134217728 -2027 1",
        "log1p 0 -1 2000 28 3 134217729 -2027 1",
        "log1p 0 -1 2000 28 4 134217728 -2027 1",
        "log1p 0 -1 2000 28 5 134217728 -2027 1",
        "log1p 0 -1 2000 28 6 134217728 -2027 1",
    ]


def test_the_values_are_what_the_reference_rounds_to() raises:
    """Every row, against CPython's own rounding of the true value."""
    var modes = _modes()
    for row in _rows():
        var field = row.split(" ")
        var name = String(field[0])
        var whole = BigInt(String(field[1]))
        var offset = Int(String(field[2]))
        var shift = Int(String(field[3]))
        var precision = Int(String(field[4]))
        var mode = modes[Int(String(field[5]))]

        var got = _call(name, _beside(whole, offset, shift), precision, mode)
        var sign = String("-") if String(field[8]) == "1" else String("")
        assert_equal(
            got.internal_representation(),
            sign
            + String(field[6])
            + "p"
            + String(field[7])
            + "@"
            + String(precision),
            String("case ") + row,
        )


def test_none_of_them_raises_where_all_of_them_used_to() raises:
    """The seven functions, both sides, every mode.

    Before the direct answers these all widened to the loop's limit and
    raised in the four directed modes, and agreed with the truth in the three
    nearest ones only because the value they could not place happened to
    round the same way from either side of it.
    """
    var modes = _modes()
    var cases = [
        "ln 1",
        "log2 2",
        "log2 1024",
        "log10 10",
        "log10 100000",
        "exp2 1",
        "exp2 7",
        "exp10 1",
        "exp10 3",
        "expm1 0",
        "log1p 0",
    ]
    for spec in cases:
        var field = spec.split(" ")
        var name = String(field[0])
        var whole = BigInt(String(field[1]))
        for offset in [1, -1]:
            if whole.is_zero() and offset == -1 and name == "log2":
                continue
            var x = _beside(whole, offset, 2000)
            for mode in modes:
                var answer = _call(name, x, 28, mode)
                assert_true(
                    answer.is_finite(),
                    String("non-finite answer for ") + spec,
                )


def test_a_padded_argument_answers_as_the_same_value_written_leanly() raises:
    """A significand's trailing zeros are not its last place.

    `2^-2000` written with one bit and the same number written with four
    thousand are the same point on the line, so every function has to answer
    them alike. The gates read the last place, and a padded significand's
    last place is far below the last one that carries a bit, so before
    `tightened()` the padded form went to the loop and raised.
    """
    var modes = _modes()
    var lean = BigFloat(
        significand=BigInt.one(), exponent=-2000, precision=1, sign=False
    )
    for extra in [1, 2101, 4200]:
        var padded = BigFloat(
            significand=BigInt.one() << extra,
            exponent=-2000 - extra,
            precision=extra + 1,
            sign=False,
        )
        for mode in modes:
            for name in [
                "sin",
                "tan",
                "arcsin",
                "arctan",
                "sinh",
                "tanh",
                "arcsinh",
                "arctanh",
                "expm1",
                "log1p",
            ]:
                var want = _small_argument_call(name, lean, 28, mode)
                var got = _small_argument_call(name, padded, 28, mode)
                assert_equal(
                    got.internal_representation(),
                    want.internal_representation(),
                    String("padded by ")
                    + String(extra)
                    + " bits disagrees for "
                    + name,
                )


def _small_argument_call(
    name: String, x: BigFloat, precision: Int, mode: RoundingMode
) raises -> BigFloat:
    """Dispatches the functions whose correction to a small argument is its own.

    Args:
        name: The function.
        x: The argument.
        precision: The bits the answer keeps.
        mode: Which way to round.

    Returns:
        The answer.

    Raises:
        Error: For an unknown name, or propagated from the function.
    """
    if name == "sin":
        return sin(x, precision, mode)
    if name == "tan":
        return tan(x, precision, mode)
    if name == "arcsin":
        return arcsin(x, precision, mode)
    if name == "arctan":
        return arctan(x, precision, mode)
    if name == "sinh":
        return sinh(x, precision, mode)
    if name == "tanh":
        return tanh(x, precision, mode)
    if name == "arcsinh":
        return arcsinh(x, precision, mode)
    if name == "arctanh":
        return arctanh(x, precision, mode)
    if name == "expm1":
        return expm1(x, precision, mode)
    if name == "log1p":
        return log1p(x, precision, mode)
    raise Error(String("the test has no function named ") + name)


def test_the_branch_leaves_an_ordinary_argument_alone() raises:
    """Arguments nowhere near a limit, answered by the loop as before.

    These are the values the gates have to refuse. `exp2(-96.4453125)` is the
    one that caught a gate written a single bit too loose: its distance to the
    whole number below it is nearly a half, the gate let it through, and the
    answer came back as the power of two rather than as the value.
    """
    var modes = _modes()

    # `exp2` of -12345/128, which is 96.4453125 below nought.
    var caught = BigFloat(
        significand=BigInt(12345), exponent=-7, precision=14, sign=True
    )
    assert_equal(exp2(caught, 1, modes[4]).internal_representation(), "1p-97@1")

    # Three bits, so the loop has to do the work and a stray branch would show.
    var three = BigFloat(
        significand=BigInt(3), exponent=-1, precision=2, sign=False
    )
    assert_equal(exp2(three, 2, modes[0]).internal_representation(), "2p0@2")
    assert_equal(exp10(three, 2, modes[0]).internal_representation(), "3p3@2")

    # `log2` and `log10` of values between the powers, not beside them.
    var seven = BigFloat(
        significand=BigInt(7), exponent=0, precision=3, sign=False
    )
    assert_equal(log2(seven, 8, modes[0]).internal_representation(), "179p-6@8")
    assert_equal(
        log10(seven, 8, modes[0]).internal_representation(), "216p-8@8"
    )

    # `ln` of two: nowhere near one, so the pre-filter must not pay for a
    # subtraction and the answer must come from the series.
    var two = BigFloat(
        significand=BigInt.one(), exponent=1, precision=1, sign=False
    )
    assert_equal(ln(two, 8, modes[0]).internal_representation(), "177p-8@8")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
