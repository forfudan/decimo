"""Run the same decimal code against `decimal` and `decimo`, and time it.

    python python/benchmarks/compare.py

Every program lives in `workload.py` and is written against the API the two
libraries share. This file hands each one both libraries in turn, checks that
they agree on the answer, and reports how long each took.

An answer that does not match is reported as a mismatch and its timing is not
shown: being fast is not interesting if the number is wrong.
"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import decimal  # noqa: E402
import workload  # noqa: E402

import decimo  # noqa: E402


def measure(function, rounds):
    """The fastest of `rounds` runs, in seconds. Fastest, not mean: a slow run
    means the machine was busy, and that says nothing about the code."""
    best = float("inf")
    for _ in range(rounds):
        start = time.perf_counter()
        result = function()
        best = min(best, time.perf_counter() - start)
    return best, result


def show_time(seconds):
    if seconds < 1e-6:
        return f"{seconds * 1e9:.1f} ns"
    if seconds < 1e-3:
        return f"{seconds * 1e6:.2f} us"
    if seconds < 1:
        return f"{seconds * 1e3:.2f} ms"
    return f"{seconds:.3f} s"


def compare(name, call, rounds=5, per_call=1):
    """Time one program under both libraries and print the row."""
    stdlib_time, stdlib_result = measure(lambda: call(decimal), rounds)
    decimo_time, decimo_result = measure(lambda: call(decimo), rounds)

    left, right = str(stdlib_result), str(decimo_result)
    if left != right:
        at = next(
            (i for i, (x, y) in enumerate(zip(left, right)) if x != y),
            min(len(left), len(right)),
        )
        window = slice(max(0, at - 20), at + 20)
        print(f"{name:<34} MISMATCH at character {at}")
        print(f"    decimal: ...{left[window]}...")
        print(f"    decimo : ...{right[window]}...")
        return False

    stdlib_time /= per_call
    decimo_time /= per_call
    ratio = stdlib_time / decimo_time
    if ratio >= 1.05:
        verdict = f"decimo {ratio:.2f}x faster"
    elif ratio <= 0.95:
        verdict = f"decimo {1 / ratio:.2f}x slower"
    else:
        verdict = "about the same"
    print(
        f"{name:<34} {show_time(decimo_time):>10} "
        f"{show_time(stdlib_time):>10}   {verdict}"
    )
    return True


def main():
    print(f"CPython {sys.version.split()[0]} on {sys.platform}")
    print(
        f"decimal {decimal.__version__ if hasattr(decimal, '__version__') else ''} "
        f"(libmpdec {getattr(decimal, '__libmpdec_version__', '?')})"
    )
    print(f"decimo  {decimo.__version__}")
    print()
    print(f"{'':<34} {'decimo':>10} {'decimal':>10}")
    print("-" * 76)

    agreed = True

    # One operator at a time, so the table says which one is fast.
    for digits in (28, 200, 1000):
        rounds = 2000 if digits <= 200 else 500
        agreed &= compare(
            f"add/sub/mul/div, {digits} digits",
            lambda mod, d=digits, r=rounds: workload.micro(mod, d, r),
            per_call=rounds * 4,
        )

    print("-" * 76)

    # Whole programs, which is what anyone actually runs.
    agreed &= compare(
        "compound interest, 150 years",
        lambda mod: workload.compound_interest(mod, 150),
    )
    agreed &= compare(
        "e from its series, 500 digits",
        lambda mod: workload.exp_series(mod, 300, 500),
    )
    agreed &= compare(
        "sqrt by Newton, 1000 digits",
        lambda mod: workload.sqrt_newton(mod, 2, 1000),
    )
    agreed &= compare(
        "pi by Machin, 500 digits",
        lambda mod: workload.pi_machin(mod, 500),
    )
    agreed &= compare(
        "parse and print, 1000 digits",
        lambda mod: workload.string_round_trip(mod, 1000, 2000),
        per_call=2000,
    )

    print("-" * 76)
    if agreed:
        print("Every program gave the same answer under both libraries.")
    else:
        print("At least one program disagreed -- see above.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
