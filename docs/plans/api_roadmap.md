# Decimo API Roadmap

> Started 2026-02-23, rewritten 2026-08-30.
> Author: Yuhao Zhu
> Scope: `BigDecimal` (`Decimal`) and `BigInt` (`BInt`).

The numeric core is in place. This document is about the API surface. The goal
is that a Python user finds the names and the behaviour they expect, while the
Mojo side keeps what a static compiled language can offer.

`Decimal128` is not tracked here. It is a fixed-width type with its own scope,
and its API work was done separately. `BigUInt` is not tracked either, because
it is an implementation detail of `BigDecimal` rather than a type users reach
for.

## Part 0: The shape of the API

Decimo carries two APIs over one engine, and they are meant to stay distinct:

- **The `decimal` layer.** A context holds the working precision, and the
  operators read it. This is what `decimo.Decimal` gives Python, and the
  target is exact agreement with `decimal.Decimal` -- same names, same
  coercion rules, same digits.
- **The MPFR layer.** Every operation also exists in a form that takes the
  precision as an argument: `add(other, precision)`, `sqrt(precision)`,
  `ln(precision)`. No global state, nothing implicit, which is what a static
  compiled language wants and what MPFR does.

The context layer is built on the precision layer, not beside it: the Python
binding reads the context once per call and passes the number down. So the
Mojo API stays explicit, and Python still gets `getcontext().prec`.

Where the two disagree about behaviour, `decimal` wins and the Mojo core moves
to match -- that is the direction settled on 2026-08-26. Where decimo does
*more* than `decimal` (unbounded exponents, larger operands, faster
multiplication), that is an extension, and it goes in the "what does not
match" list in `python/README.md` rather than being quietly different.

Mojo's lack of global variables used to block a real context. It no longer
does: `std.ffi._Global` hands out a pointer to one heap cell that outlives the
call, which is a global by another name, and the Python binding uses it. It
costs about 14 ns per operation to read, measured.

## What is settled

Two rounds of work closed most of the original list, and the details are in
`docs/changelog.md` rather than here.

- **Naming.** The comparison free functions are `equal`, `not_equal`, `less`,
  `greater`, `less_equal`, `greater_equal` on both types; the old longer
  spellings are gone.
- **The `decimal` surface.** `BigDecimal` carries the whole method surface a
  `decimal` program touches, including the `logical_*` family, `rotate`,
  `shift`, `next_plus`, `next_minus`, `next_toward`, `number_class`,
  `remainder_near`, `logb`, `max_mag`, `min_mag`, `to_integral_exact` and the
  predicates. They live in `src/decimo/bigdecimal/spec.mojo` and are bound to
  Python. Every one is cross-checked against `decimal` in
  `python/tests/test_decimo.py`.
- **Dunders.** Arithmetic, reflected, in-place, comparison, conversion,
  `__divmod__`, `__round__`, `__hash__`, `__format__` and the pickle protocol
  are all present.
- **Rounding modes.** Seven of Python's eight are implemented. `ROUND_05UP` is
  deliberately refused; the Python layer raises `NotImplementedError` for it.
- **Context.** `getcontext()` carries `prec` and `rounding` and the arithmetic
  methods. `Emin` decides `is_normal`, `is_subnormal` and `number_class`.
  `Emax`, `capitals`, `clamp`, `flags` and `traps` are stored and reported but
  do not affect a result, because decimo's exponents are unbounded. There is
  one context per process, not one per thread.

## What is open

Ranked. Nothing here blocks a release.

1. **Accessors for `BigDecimal`'s internal state.** `scale`, `coefficient` and
   `sign` are public fields. An `exponent()` and a `significand()` method would
   let the representation change without breaking callers. `is_negative()`
   already covers the sign.
2. **`signum()` and `clamp()` on `BigDecimal` and `BigInt`.** Both exist on
   `Decimal128` and neither exists on the arbitrary-precision types.
3. **`is_integer()`, `as_integer_ratio()` and `conjugate()` on `BigInt`.**
   `as_integer_ratio()` exists in the Python layer only.
4. **`is_close(other, rel_tol, abs_tol)`.** Useful in tests and numerical code,
   and it has no `decimal` counterpart to copy, so the signature is a design
   question.
5. **`from_fraction(numerator, denominator, precision)`.** Now that `Rational`
   exists, this is the conversion between the two.
6. **`numbers.Number` registration in the Python package**, which puts
   `Decimal` into Python's numeric tower.
7. **A `divide()` alias for `true_divide()`.** Cosmetic; `true_divide` is named
   after `__truediv__` and is not wrong.

## Ergonomics still worth considering

These came out of the original static-language survey and none has been
decided.

- **Builders.** `with_precision(n)` and `with_scale(n)` returning a new value,
  so a chain can set precision without threading an argument through every
  call.
- **Digit access.** An iterator over the coefficient's decimal digits, which
  financial formatting wants and `as_tuple()` currently serves clumsily.
- **Named constructors** beyond `zero()` and `one()`, for the values that come
  up repeatedly in tests.

## Appendix: coverage against `decimal.Decimal`

The authoritative check is `python/tests/test_decimo.py`, which compares
decimo's answer with `decimal`'s for every method the two share. A hand-kept
table here went stale twice; the test suite does not.

What decimo does not have: `__complex__`, and NaN and infinity. The last two
are a difference in the number model, not a missing method, and they are
written up in `python/README.md`.
