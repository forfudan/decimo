"""The arbitrary-precision binary float.

Modules:
- bigfloat: Core struct with constructors, conversions, dunders and methods
- arithmetics: add, subtract, multiply, divide
- comparison: compare, compare_total, the six operators, min, max
- constants: pi, ln2, ln10, e
- conversion: the bridge to and from the decimal side
- exponential: sqrt, root, cbrt, exp, ln, and the other bases -- exp2,
  exp10, log2,
  log10, log, expm1, log1p -- with the loop that decides a rounding
- hyperbolic: sinh, cosh, tanh, arcsinh, arccosh, arctanh
- ieee: the IEEE 754 companion operations -- the neighbours, logb, scaleb,
  the sign copies, number_class, the roundings to a whole number, fma and
  the two remainders
- power: x ** y, with the exact answers found before the series runs
- rounding: round_to_precision and the fixed-point helpers the series use
- trigonometric: sin, cos, tan, arcsin, arccos, arctan

The exponentials, the logarithms and the IEEE companions are re-exported
here, so that the functions whose names say what they do can be reached
without naming the module they live in.
"""

from .constants import ln10, ln2
from .exponential import (
    cbrt,
    exp,
    exp10,
    exp2,
    expm1,
    ln,
    log,
    log10,
    log1p,
    log2,
    root,
    sqrt,
)
from .ieee import (
    ceil,
    copy_abs,
    copy_negate,
    copy_sign,
    floor,
    fma,
    fmod,
    is_integer,
    logb,
    next_minus,
    next_plus,
    next_toward,
    number_class,
    remainder,
    round_to_integer,
    scaleb,
    truncate,
)
from .power import power
