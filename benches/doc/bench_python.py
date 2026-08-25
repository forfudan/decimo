"""Times CPython and the reference libraries for `docs/benchmarks.md`.

Emits JSON on stdout. Reports the minimum over several rounds, matching
`bench_decimo.mojo` and `bench_libmpdec.c`.

Two things worth knowing when reading the output:

- CPython's `int` can only be measured through the interpreter, so those
  numbers include interpreter overhead. There is no way to call the integer
  engine without it, unlike libmpdec, which is timed directly in C.
- `mpmath` and `gmpy2` are optional. When they are missing the corresponding
  entries are reported as null rather than omitted, so the generated document
  can say so explicitly instead of quietly dropping a column.
"""

from __future__ import annotations

import json
import platform
import sys
import time

ROUNDS = 7
ITERS = 200_000


def best_ns(fn, iterations: int, rounds: int = ROUNDS) -> float:
    """Nanoseconds per call, minimum over `rounds`."""
    best = float("inf")
    for _ in range(rounds):
        start = time.perf_counter_ns()
        for _ in range(iterations):
            fn()
        elapsed = time.perf_counter_ns() - start
        best = min(best, elapsed / iterations)
    return round(best, 3)


def digits(count: int) -> str:
    """Same sequence as `_digits()` in `bench_decimo.mojo`."""
    out = []
    state = 7
    for _ in range(count):
        state = (state * 31 + 17) % 9
        out.append(str(state + 1))
    return "".join(out)


def bench_cpython_int() -> dict:
    # CPython caps int(str) at 4300 digits by default (CVE-2020-10735); this
    # benchmark is not parsing untrusted input, and the parse is not timed.
    sys.set_int_max_str_digits(200_000)
    result = {}
    for n_digits in (100, 1000, 10000, 100000):
        x = int(digits(n_digits))
        y = int(digits(n_digits - 1))
        reps = max(3, 20_000_000 // (n_digits * 4))
        result[str(n_digits)] = {
            "add": best_ns(lambda: x + y, reps),
            "multiply": best_ns(lambda: x * y, reps),
        }
    return result


def bench_decimal_via_python() -> dict:
    """CPython's `decimal`, i.e. libmpdec seen through the interpreter."""
    import decimal

    decimal.getcontext().prec = 28
    decimal.getcontext().rounding = decimal.ROUND_HALF_EVEN
    a = decimal.Decimal("12345.6789")
    b = decimal.Decimal("9876.54321")
    wide = decimal.Decimal("1234.56789012345678901234567890")
    quantum = decimal.Decimal("1E-10")
    return {
        "add": best_ns(lambda: a + b, ITERS),
        "subtract": best_ns(lambda: a - b, ITERS),
        "multiply": best_ns(lambda: a * b, ITERS),
        "divide": best_ns(lambda: a / b, ITERS),
        "round": best_ns(lambda: wide.quantize(quantum), ITERS),
        "from_string": best_ns(lambda: decimal.Decimal("12345.6789"), ITERS),
    }


def bench_pi_once(library: str, precision: int) -> float | None:
    """Nanoseconds for one cold computation of pi to `precision` digits.

    Cold matters: mpmath memoises `pi_fixed` and MPFR keeps its own cached
    constant, so a second call at the same precision measures the cache rather
    than the algorithm. This is why the generator runs each measurement in a
    fresh process instead of looping in one.
    """
    if library in ("mpmath", "mpmath_gmpy"):
        try:
            import mpmath
        except ImportError:
            return None
        backend = mpmath.libmp.BACKEND
        if library == "mpmath_gmpy" and backend != "gmpy":
            return None
        if library == "mpmath" and backend == "gmpy":
            return None
        mpmath.mp.dps = precision + 10
        start = time.perf_counter_ns()
        text = mpmath.nstr(+mpmath.pi, precision)
        elapsed = time.perf_counter_ns() - start
        assert text.startswith("3.14"), text[:8]
        return round(float(elapsed), 3)
    if library == "mpfr":
        try:
            import gmpy2
        except ImportError:
            return None
        bits = int(precision * 3.3219280948873626) + 32
        start = time.perf_counter_ns()
        value = gmpy2.const_pi(bits)
        # `gmpy2.digits` returns (mantissa_digits, exponent, precision); the
        # decimal conversion is part of what is being timed, as it is for
        # every other library in the table.
        mantissa = gmpy2.digits(value, 10, precision)[0]
        elapsed = time.perf_counter_ns() - start
        assert mantissa.startswith("314159"), mantissa[:10]
        return round(float(elapsed), 3)
    return None


def main() -> int:
    import decimal

    payload = {
        "python": sys.version.split()[0],
        "libmpdec_via_python": getattr(decimal, "__libmpdec_version__", None),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "rounds": ROUNDS,
        "cpython_int": bench_cpython_int(),
        "cpython_decimal": bench_decimal_via_python(),
    }
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    # `--pi <library> <precision>` measures one cold pi in this fresh process
    # and prints a single number; the generator invokes it that way.
    if len(sys.argv) == 4 and sys.argv[1] == "--pi":
        value = bench_pi_once(sys.argv[2], int(sys.argv[3]))
        print("null" if value is None else repr(value))
        sys.exit(0)
    sys.exit(main())
