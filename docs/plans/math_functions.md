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

| group        | have                                                       |
| ------------ | ---------------------------------------------------------- |
| powers       | `sqrt`, `cbrt`, `root`, `power`, `exp`                      |
| logarithms   | `ln`, `log10`, `log(x, b)`                                  |
| circular     | `sin`, `cos`, `tan`, `sec`, `csc`, `cot`, `arctan`          |
| constants    | `pi`, `e`                                                   |
| combinatoric | `factorial`, `permutation`                                  |

| group      | missing                                                  |
| ---------- | -------------------------------------------------------- |
| circular   | `arcsin`, `arccos`, `arctan2`                             |
| hyperbolic | `sinh`, `cosh`, `tanh`, `arcsinh`, `arccosh`, `arctanh`   |
| numeric    | `expm1`, `log1p`, `hypot`                                 |
| gamma      | `gamma`, `lgamma`, `digamma`, `beta`                      |
| error      | `erf`, `erfc`, `erfinv`                                   |
| zeta       | `zeta`, `polylog`                                         |
| deep end   | Bessel, Airy, elliptic, generalised hypergeometric `pFq`  |
| complex    | everything above, over `BigComplex`                       |
| numerics   | `findroot`, quadrature, series acceleration               |

## 3. Three prerequisites, in this order

Getting the order wrong means writing the same functions twice.

1. **Complex before special functions.** Most of what makes the gamma and zeta
   families worth having is their behaviour off the real line. A real-only
   `gamma` is rewritten when `BigComplex` arrives.

2. **An internal working type.** A special function costs tens to hundreds of
   elementary operations per result. `BigDecimal` is immutable, so a series
   summation allocates per term — inline storage in `WordList` covers short
   values, not a thousand-digit accumulator. Either an internal mutable
   scratch type, or run the kernels in binary and convert at the boundary.
   Binary is faster for transcendentals, but `BigFloat` needs MPFR on the
   system, which the main package cannot require. **This gates phase 3 and is
   decided in phase 1.**

3. **The error framework becomes shared.** Each transcendental now derives its
   own guard digits and its own rounding decision. With a dozen more functions
   that has to be one facility: an error bound carried with a value, and one
   routine that decides whether the interval rounds to a single answer. An
   internal type, not a public one.

## 4. Phases

### Phase 0 — close the elementary set

Cheap, independent of every decision above, and the functions a caller looks
for first. Nothing here needs complex numbers.

- [ ] `arcsin`, `arccos` — from `arctan`, with the argument reduction that
      keeps them accurate near ±1.
- [ ] `arctan2` — the quadrant-aware two-argument form.
- [ ] `sinh`, `cosh`, `tanh` — from `exp`, watching cancellation in `sinh` for
      small arguments.
- [ ] `arcsinh`, `arccosh`, `arctanh` — from `ln`, same care near the branch
      points.
- [ ] `expm1`, `log1p` — the small-argument forms, which are why they exist
      separately.
- [ ] `hypot` — without the intermediate overflow.
- [ ] Python bindings and `python/README.md` rows for all of the above.

### Phase 1 — the foundation

- [ ] Decide the internal working type (prerequisite 2); record the decision
      here.
- [ ] Extract the guard-digit and rounding-decision machinery into one
      facility (prerequisite 3) and move the existing transcendentals onto it.

### Phase 2 — complex

- [ ] `BigComplex` over two `BigDecimal`s: arithmetic, comparison, parsing,
      formatting.
- [ ] The elementary set over `BigComplex`.

### Phase 3 — special functions, by value

- [ ] `gamma`, `lgamma` — Lanczos or Spouge with a rigorous bound;
      non-integer `factorial` follows.
- [ ] `erf`, `erfc` — series for small arguments, continued fraction for
      large.
- [ ] `beta`, incomplete gamma.
- [ ] `digamma`, `zeta` — Euler-Maclaurin, one engine for both.
- [ ] Decide whether to build a generalised hypergeometric `pFq` evaluator.
      Everything past this point (Bessel, Airy, elliptic) is cheaper on top of
      one than written out separately, which is how mpmath covers them.

### Phase 4 — numerics

- [ ] `findroot` — Newton with a bracketing fallback.
- [ ] Quadrature — tanh-sinh, the right default at high precision.
- [ ] Series acceleration for the summations the above need.

## 5. Verification

Two independent references, both already available:

- **MPFR**, through decimo's own `BigFloat`, for the elementary functions it
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

1. Does the internal kernel run in decimal or binary? Phase 1 decides.
2. Is `pFq` worth building, or are the four or five functions people actually
   ask for cheaper written directly?
3. Does the Python layer expose these on `Decimal`, or in a separate module?
   That layer's promise is `decimal` compatibility, and these go beyond it.
