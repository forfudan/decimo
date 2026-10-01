# ===----------------------------------------------------------------------=== #
# Copyright 2025-2026 Yuhao Zhu
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===----------------------------------------------------------------------=== #


"""Hyperbolic functions for BigDecimal, and their inverses.

Each is written in terms of `expm1()` or `log1p()` rather than of `exp()` or
`ln()`. The textbook forms lose their answer near zero -- `(exp(x) -
exp(-x))/2` subtracts two values that agree to as many digits as `x` is small,
and `ln(x + sqrt(x^2 + 1))` rounds its argument to one before the logarithm
sees it -- while the forms used here keep every digit. `sinh(1E-60)` is
`1E-60`, not zero.

The functions, with the identity each is computed from (`u = expm1(|x|)`):

- sinh(x: BigDecimal, precision: Int) -> BigDecimal     u(u + 2) / (2(u + 1))
- cosh(x: BigDecimal, precision: Int) -> BigDecimal     (e^|x| + e^-|x|) / 2
- tanh(x: BigDecimal, precision: Int) -> BigDecimal     v / (v + 2), v at 2|x|
- arcsinh(x: BigDecimal, precision: Int) -> BigDecimal  log1p of x + x^2/(...)
- arccosh(x: BigDecimal, precision: Int) -> BigDecimal  log1p of t + sqrt(...)
- arctanh(x: BigDecimal, precision: Int) -> BigDecimal  log1p of 2x/(1 - x)/2

and one `*_rounded()` for each, whose rounding is decided rather than assumed.
"""

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigdecimal.exponential import _round_by_deciding
import decimo.bigdecimal.exponential as bigdecimal_exponential
from decimo.biguint.biguint import BigUInt
from decimo.errors import ValueError
from decimo.rounding_mode import RoundingMode

comptime HYPERBOLIC_SLACK = 4
"""Units in the last place any function here may be off at the width it was
asked for.

Each is a handful of rounded steps -- one `expm1()` or `log1p()`, a square root
at most, and a division -- carried at nine guard digits, which leaves the final
rounding as the only error that survives. Four is what the functions these are
built from state for themselves.
"""


def _one() raises -> BigDecimal:
    """The constant one, which every identity here needs."""
    return BigDecimal.from_raw_components(BigUInt.Word(1), scale=0, sign=False)


def _two() raises -> BigDecimal:
    """The constant two."""
    return BigDecimal.from_raw_components(BigUInt.Word(2), scale=0, sign=False)


def _saturation_magnitude(working_precision: Int) raises -> BigDecimal:
    """The `|x|` beyond which `exp(-2|x|)` cannot reach the last digit.

    Args:
        working_precision: The precision the caller is carrying.

    Returns:
        A bound on `|x|`: past it, `tanh(x)` is one and `cosh(x)` is
        `exp(|x|)/2`, both to the working precision.

    Raises:
        Error: Propagated from the construction of the bound.

    Notes:

    `exp(-2|x|) < 10^-working` holds once `2|x| > working * ln(10)`, so the
    bound is `working * 1.1513...`, rounded up. Without it, `tanh(1E6)` would
    reach for `exp(2E6)`, a number of 868589 digits, to answer `1`.
    """
    var digits = Int(Float64(working_precision + 2) * 1.16) + 1
    return BigDecimal.from_raw_components(
        BigUInt.Word(digits), scale=0, sign=False
    )


def sinh(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the hyperbolic sine of the number.

    Args:
        x: The argument.
        precision: The number of significant digits for the result.

    Returns:
        The hyperbolic sine of x.

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:

    With `u = expm1(|x|)`, so that `e^|x| = u + 1`:

        sinh(|x|) = ((u + 1) - 1/(u + 1)) / 2 = u(u + 2) / (2(u + 1))

    which is the subtraction done in advance. For a small `x` every term is
    proportional to `u`, and `u` is `x` to within its own square, so nothing
    cancels. The sign comes back at the end: `sinh` is odd.
    """
    comptime BUFFER_DIGITS = 9  # guard digits, not a word width
    var working_precision = precision + BUFFER_DIGITS

    if x.is_zero():
        # `sinh(0)` is exactly zero.
        return BigDecimal.zero()

    var magnitude = abs(x)
    var result: BigDecimal

    if magnitude.compare_absolute(_saturation_magnitude(working_precision)) > 0:
        # `e^-|x|` is below the last digit, so the difference is `e^|x|`.
        result = bigdecimal_exponential.exp(
            magnitude, working_precision
        ).true_divide(_two(), precision=working_precision)
    else:
        var u = bigdecimal_exponential.expm1(magnitude, working_precision)
        var numerator = u.multiply(u.add(_two()), precision=working_precision)
        var denominator = _two().multiply(
            u.add(_one()), precision=working_precision
        )
        result = numerator.true_divide(denominator, precision=working_precision)

    if x.sign:
        result = -result

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def cosh(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the hyperbolic cosine of the number.

    Args:
        x: The argument.
        precision: The number of significant digits for the result.

    Returns:
        The hyperbolic cosine of x, which is never below one.

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:

    `(e^|x| + e^-|x|) / 2` as it reads. Both terms are positive, so there is
    nothing to cancel and no need for `expm1()`: near zero the answer is one
    and the digits that matter are the ones `e^|x|` already has. `cosh` is
    even, so the sign of the argument is dropped.
    """
    comptime BUFFER_DIGITS = 9  # guard digits, not a word width
    var working_precision = precision + BUFFER_DIGITS

    var magnitude = abs(x)
    var exponential = bigdecimal_exponential.exp(magnitude, working_precision)
    var result: BigDecimal

    if magnitude.compare_absolute(_saturation_magnitude(working_precision)) > 0:
        # `e^-|x|` is below the last digit of `e^|x|`.
        result = exponential.true_divide(_two(), precision=working_precision)
    else:
        var reciprocal = _one().true_divide(
            exponential, precision=working_precision
        )
        result = exponential.add(reciprocal).true_divide(
            _two(), precision=working_precision
        )

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def tanh(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the hyperbolic tangent of the number.

    Args:
        x: The argument.
        precision: The number of significant digits for the result.

    Returns:
        The hyperbolic tangent of x, in `(-1, 1)`.

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:

    With `v = expm1(2|x|)`:

        tanh(|x|) = (e^2|x| - 1) / (e^2|x| + 1) = v / (v + 2)

    and `v` is `2x` for a small argument, which leaves `tanh(x) = x` as it
    should be. Past `_saturation_magnitude()` the answer is one to the last
    digit asked for, and is returned without reaching for `e^2|x|`.
    """
    comptime BUFFER_DIGITS = 9  # guard digits, not a word width
    var working_precision = precision + BUFFER_DIGITS

    if x.is_zero():
        # `tanh(0)` is exactly zero.
        return BigDecimal.zero()

    var magnitude = abs(x)
    var result: BigDecimal

    if magnitude.compare_absolute(_saturation_magnitude(working_precision)) > 0:
        result = _one()
    else:
        var v = bigdecimal_exponential.expm1(
            magnitude.multiply(_two()), working_precision
        )
        result = v.true_divide(v.add(_two()), precision=working_precision)

    if x.sign:
        result = -result

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def arcsinh(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the inverse hyperbolic sine of the number.

    Args:
        x: The argument, which may be anything.
        precision: The number of significant digits for the result.

    Returns:
        The inverse hyperbolic sine of x.

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:

    `arcsinh(x) = ln(x + sqrt(x^2 + 1))`, and for `|x| <= 1` that argument is
    one plus something small, which `log1p()` takes without forming the sum:

        x + sqrt(x^2 + 1) = 1 + x + x^2 / (1 + sqrt(1 + x^2))

    The rearranged tail is what keeps a tiny argument. Written as
    `sqrt(1 + x^2) - 1` it would cancel to nothing; written as a quotient it
    does not. Beyond one the logarithm is far enough from zero to be taken as
    it reads. `arcsinh` is odd.
    """
    comptime BUFFER_DIGITS = 9  # guard digits, not a word width
    var working_precision = precision + BUFFER_DIGITS

    if x.is_zero():
        # `arcsinh(0)` is exactly zero.
        return BigDecimal.zero()

    var magnitude = abs(x)
    var one_plus_square = _one().add(magnitude.multiply(magnitude))
    var root = bigdecimal_exponential.sqrt_via_reciprocal_iteration(
        one_plus_square, working_precision
    )
    var result: BigDecimal

    if magnitude.compare_absolute(_one()) <= 0:
        var tail = magnitude.multiply(magnitude).true_divide(
            _one().add(root), precision=working_precision
        )
        result = bigdecimal_exponential.log1p(
            magnitude.add(tail), working_precision
        )
    else:
        result = bigdecimal_exponential.ln(
            magnitude.add(root), working_precision
        )

    if x.sign:
        result = -result

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def arccosh(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the inverse hyperbolic cosine of the number.

    Args:
        x: The argument, which must be at least one.
        precision: The number of significant digits for the result.

    Returns:
        The inverse hyperbolic cosine of x, which is never negative.

    Raises:
        ValueError: If `x < 1`, where the result would not be real.
        Error: Propagated from underlying arithmetic operations.

    Notes:

    `arccosh(x) = ln(x + sqrt(x^2 - 1))`. Near one the answer is small and the
    logarithm's argument is one plus something small, so with `t = x - 1`,
    which is exact:

        x + sqrt(x^2 - 1) = 1 + t + sqrt(t(t + 2))

    and `log1p()` takes the tail. The square root of the exact product is
    where the accuracy near one comes from: `arccosh(1 + 1E-40)` is about
    `1.4E-20`, and every digit of it survives.
    """
    comptime BUFFER_DIGITS = 9  # guard digits, not a word width
    var working_precision = precision + BUFFER_DIGITS

    if x.compare(_one()) < 0:
        raise ValueError(
            message="arccosh() is defined for x >= 1.",
            function="arccosh()",
        )

    var t = x.subtract(_one())
    if t.is_zero():
        # `arccosh(1)` is exactly zero.
        return BigDecimal.zero()

    var result: BigDecimal
    if x.compare(_two()) <= 0:
        var root = bigdecimal_exponential.sqrt_via_reciprocal_iteration(
            t.multiply(t.add(_two())), working_precision
        )
        result = bigdecimal_exponential.log1p(t.add(root), working_precision)
    else:
        var root = bigdecimal_exponential.sqrt_via_reciprocal_iteration(
            x.multiply(x).subtract(_one()), working_precision
        )
        result = bigdecimal_exponential.ln(x.add(root), working_precision)

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def arctanh(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the inverse hyperbolic tangent of the number.

    Args:
        x: The argument, strictly inside `(-1, 1)`.
        precision: The number of significant digits for the result.

    Returns:
        The inverse hyperbolic tangent of x.

    Raises:
        ValueError: If `|x| >= 1`, where the result is unbounded.
        Error: Propagated from underlying arithmetic operations.

    Notes:

    `arctanh(x) = ln((1 + x) / (1 - x)) / 2`, and the quotient is one plus
    `2x/(1 - x)`, which `log1p()` takes directly:

        arctanh(x) = log1p(2x / (1 - x)) / 2

    `1 - x` is exact, so for a small `x` the argument is `2x` to its own
    square and nothing is lost. Nearer the ends the quotient grows without
    bound and the plain logarithm is the better form. `arctanh` is odd.
    """
    comptime BUFFER_DIGITS = 9  # guard digits, not a word width
    var working_precision = precision + BUFFER_DIGITS

    if x.compare_absolute(_one()) >= 0:
        raise ValueError(
            message="arctanh() is defined on (-1, 1).",
            function="arctanh()",
        )

    if x.is_zero():
        # `arctanh(0)` is exactly zero.
        return BigDecimal.zero()

    var magnitude = abs(x)
    var bdec_0d5 = BigDecimal.from_raw_components(
        BigUInt.Word(5), scale=1, sign=False
    )
    var result: BigDecimal

    if magnitude.compare_absolute(bdec_0d5) <= 0:
        var tail = (
            _two()
            .multiply(magnitude)
            .true_divide(
                _one().subtract(magnitude), precision=working_precision
            )
        )
        result = bigdecimal_exponential.log1p(tail, working_precision)
    else:
        result = bigdecimal_exponential.ln(
            _one()
            .add(magnitude)
            .true_divide(
                _one().subtract(magnitude), precision=working_precision
            ),
            working_precision,
        )

    result = result.true_divide(_two(), precision=working_precision)

    if x.sign:
        result = -result

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def sinh_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `sinh(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The argument.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `sinh()`.
    """
    if x.is_zero():
        return sinh(x, precision)
    return _round_by_deciding[sinh, HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )


def cosh_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `cosh(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The argument.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `cosh()`.
    """
    if x.is_zero():
        # `cosh(0)` is exactly one, which the loop could not settle on.
        return cosh(x, precision)
    return _round_by_deciding[cosh, HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )


def tanh_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `tanh(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The argument.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `tanh()`.

    Notes:

    A saturated argument returns exactly one, which sits on a boundary rather
    than beside one, so it is answered by the kernel directly.
    """
    if x.is_zero():
        return tanh(x, precision)
    var saturated = tanh(x, precision)
    if (
        saturated.compare_absolute(
            BigDecimal.from_raw_components(BigUInt.Word(1), scale=0, sign=False)
        )
        == 0
    ):
        return saturated^
    return _round_by_deciding[tanh, HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )


def arcsinh_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `arcsinh(x)` rounded to `precision` digits, decided.

    Args:
        x: The argument.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `arcsinh()`.
    """
    if x.is_zero():
        return arcsinh(x, precision)
    return _round_by_deciding[arcsinh, HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )


def arccosh_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `arccosh(x)` rounded to `precision` digits, decided.

    Args:
        x: The argument.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `arccosh()`.
    """
    return _round_by_deciding[arccosh, HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )


def arctanh_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `arctanh(x)` rounded to `precision` digits, decided.

    Args:
        x: The argument.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `arctanh()`.
    """
    if x.is_zero():
        return arctanh(x, precision)
    return _round_by_deciding[arctanh, HYPERBOLIC_SLACK](
        x, precision, rounding_mode
    )
