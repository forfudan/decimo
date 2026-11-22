# Mathematical Functions Plan

> Date of initial planning: 2026-09-24
> Author: Yuhao Zhu
> Scope: the function surface of `BigDecimal` — elementary, then special
> Target: decimo v0.16.0+

## 1. The problem

`BigDecimal`'s function surface stops at the elementary level, and it is
incomplete even there: `arctan` exists but `arcsin` does not, and there are no
hyperbolic functions at all. Beyond that there is nothing — no gamma, no error
function, no zeta — so a scientific calculation that needs one of them cannot
be written in decimo at all.

This plan closes the elementary set first, then adds the special functions in
the order they are asked for.

**The standard every function must meet: it decides its own last digit.** A
function takes the interval its error bound allows and checks that the whole
interval rounds to one answer, widening the working precision until it does.
This is what the existing transcendentals do, and it is the point of using an
arbitrary-precision library rather than `Float64`. A function that cannot
decide its last digit does not ship, however useful it would be.

Out of scope: matrices and linear algebra, plotting, ODE solvers, and interval
arithmetic as a public type.

## 2. Where we stand

Phase 0 is done (#321-#323, Python in #337), and `BigFloat` carries the same set in binary.

| group      | have                                                                |
| ---------- | ------------------------------------------------------------------- |
| powers     | `sqrt`, `cbrt`, `root`, `power`, `exp`, `expm1`                     |
| logarithms | `ln`, `log10`, `log(x, b)`, `log1p`                                 |
| circular   | `sin`, `cos`, `tan`, `sec`, `csc`, `cot`, their inverses, `arctan2` |
| hyperbolic | `sinh`, `cosh`, `tanh` and their inverses                           |
| other      | `hypot`, `factorial`, `permutation`, `pi`, `e`                      |

| group      | missing                                                  |
| ---------- | -------------------------------------------------------- |
| gamma      | `gamma`, `lgamma`, `digamma`, `beta`                      |
| error      | `erf`, `erfc`, `erfinv`                                   |
| zeta       | `zeta`, `polylog`                                         |
| deep end   | Bessel, Airy, elliptic, generalised hypergeometric `pFq`  |
| complex    | everything above, over `BigComplex`                       |
| numerics   | `findroot`, quadrature, series acceleration               |

## 3. Three prerequisites, in this order

Getting the order wrong means writing the same functions twice.

1. **Complex before special functions.** Most of what makes the gamma and zeta families worth having is their behaviour off the real line. A real-only `gamma` is rewritten when `BigComplex` arrives.

2. **An internal working type. Decided: binary.** A special function costs tens to hundreds of elementary operations per result, and `BigDecimal` is immutable, so a decimal series allocates per term. The kernels now run on `BigFloat`, which needs no system library, and convert at the boundary (#374-#383).

3. **One error framework. Done.** `BigFloat`'s Ziv loop (#338) carries the error bound and decides whether the interval rounds to one answer; the `BigDecimal` functions reach it through the binary kernels.

## 4. Phases

The items themselves are tracked in `docs/internal/todo.md`. This section keeps the method.

- **Phase 0 — the elementary set.** Done.
- **Phase 1 — the foundation.** Done; see prerequisites 2 and 3.
- **Phase 2 — complex.** `BigComplex` over two `BigDecimal`s: arithmetic, comparison, parsing, formatting, then the elementary set over it.
- **Phase 3 — special functions, by value.** `gamma` and `lgamma` by Lanczos or Spouge with a rigorous bound, after which a non-integer `factorial` follows. `erf` and `erfc` by series for small arguments and continued fraction for large. `beta` and incomplete gamma. `digamma` and `zeta` by Euler-Maclaurin, one engine for both. Then decide on a `pFq` evaluator: Bessel, Airy and elliptic are cheaper on top of one than written out separately, which is how mpmath covers them.
- **Phase 4 — numerics.** `findroot` (Newton with a bracketing fallback), tanh-sinh quadrature (the right default at high precision), and the series acceleration the above need.

## 5. Verification

Two independent references, both already available:

- **MPFR**, through decimo's own `MPF`, for the elementary functions it
  implements. MPFR is correctly rounded, so this checks the last digit rather
  than the value alone.
- **mpmath**, at a precision well above the one under test, for everything
  MPFR does not cover. It is already a dependency of the benchmark
  environment.

Each function also needs the cases a reference comparison does not reach: the
argument where the series and the asymptotic form meet, the branch points, the
poles of `gamma` at the non-positive integers, and a value engineered to sit
close to a rounding boundary, which is what catches a lazy guard-digit choice.

## 6. Open questions

1. Is `pFq` worth building, or are the four or five functions people actually
   ask for cheaper written directly?
2. Does the Python layer expose these on `Decimal`, or in a separate module?
   That layer's promise is `decimal` compatibility, and these go beyond it.
