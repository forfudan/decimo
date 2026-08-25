"""Regenerates `docs/benchmarks.md` from measurements taken right now.

    pixi run benchdoc

Every number in the generated document comes from this run; nothing is carried
over from a previous one. The document records the commit it was measured on,
so a reader can tell whether it is current, and a stale table is visibly stale
rather than quietly wrong.

Three comparisons, and they are not equally fair -- the document says so:

- `BigDecimal` against libmpdec, timed in C. CPython's `decimal` module *is*
  libmpdec, so this is an engine-to-engine comparison with no interpreter in
  the way.
- `BigInt` against CPython's `int`, which can only be reached through the
  interpreter. Those numbers include interpreter overhead and therefore
  flatter decimo; there is no way to remove it.
- `pi()` against mpmath and MPFR, each measured in a fresh process because
  both cache the constant.
"""

from __future__ import annotations

import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "benchmarks.md"
HERE = Path(__file__).resolve().parent
PRECISIONS = [100, 1000, 10000, 100000, 1000000]
PI_LIBRARIES = [
    ("decimo", "decimo"),
    ("mpmath_gmpy", "mpmath + GMP"),
    ("mpfr", "MPFR"),
    ("mpmath", "mpmath (pure Python)"),
]


def run(cmd: list[str], **kwargs) -> str:
    return subprocess.run(
        cmd, cwd=ROOT, capture_output=True, text=True, check=True, **kwargs
    ).stdout


def git_context() -> dict:
    commit = run(["git", "rev-parse", "HEAD"]).strip()
    dirty = bool(run(["git", "status", "--porcelain"]).strip())
    branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"]).strip()
    subject = run(["git", "log", "-1", "--format=%s"]).strip()
    pull_request = None
    if shutil.which("gh"):
        try:
            listed = subprocess.run(
                [
                    "gh",
                    "pr",
                    "list",
                    "--head",
                    branch,
                    "--json",
                    "number",
                    "--jq",
                    ".[0].number",
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=30,
            ).stdout.strip()
            pull_request = int(listed) if listed.isdigit() else None
        except Exception:
            pull_request = None
    return {
        "commit": commit,
        "short": commit[:7],
        "branch": branch,
        "subject": subject,
        "dirty": dirty,
        "pull_request": pull_request,
    }


def build_libmpdec() -> Path:
    prefix = (
        subprocess.run(
            ["brew", "--prefix", "mpdecimal"], capture_output=True, text=True
        ).stdout.strip()
        or "/opt/homebrew"
    )
    binary = Path(os.environ.get("TMPDIR", "/tmp")) / "decimo_bench_libmpdec"
    subprocess.run(
        [
            "cc",
            "-O2",
            f"-I{prefix}/include",
            f"-L{prefix}/lib",
            "-lmpdec",
            str(HERE / "bench_libmpdec.c"),
            "-o",
            str(binary),
        ],
        check=True,
    )
    return binary


def pi_cold(library: str, precision: int) -> float | None:
    """One cold measurement, in its own process. None when unavailable."""
    if library == "decimo":
        return None  # taken from the Mojo run, which is already cold per call
    env = dict(os.environ)
    if library == "mpmath":
        env["MPMATH_NOGMPY"] = "1"
    proc = subprocess.run(
        [
            "pixi",
            "run",
            "-e",
            "benchdoc",
            "python",
            str(HERE / "bench_python.py"),
            "--pi",
            library,
            str(precision),
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        env=env,
    )
    tail = proc.stdout.strip().splitlines()
    if not tail or tail[-1] == "null":
        return None
    try:
        return float(tail[-1])
    except ValueError:
        return None


def human(nanoseconds: float | None) -> str:
    if nanoseconds is None:
        return "—"
    if nanoseconds < 1_000:
        return f"{nanoseconds:.1f} ns"
    if nanoseconds < 1_000_000:
        return f"{nanoseconds / 1_000:.2f} µs"
    if nanoseconds < 1_000_000_000:
        return f"{nanoseconds / 1_000_000:.2f} ms"
    return f"{nanoseconds / 1_000_000_000:.3f} s"


def ratio(ours: float | None, theirs: float | None) -> str:
    if not ours or not theirs:
        return "—"
    value = theirs / ours
    if value >= 1.0:
        return f"**{value:.2f}× faster**"
    return f"{1.0 / value:.2f}× slower"


def main() -> int:
    context = git_context()
    if context["dirty"]:
        print(
            "refusing to generate: the working tree has uncommitted changes, "
            "so the recorded commit would not describe what was measured.\n"
            "Commit or stash first.",
            file=sys.stderr,
        )
        return 1

    print("building libmpdec benchmark ...", file=sys.stderr)
    libmpdec_binary = build_libmpdec()
    print("running libmpdec ...", file=sys.stderr)
    libmpdec = json.loads(run([str(libmpdec_binary)]))

    print("running decimo ...", file=sys.stderr)
    decimo = json.loads(
        run(
            [
                "pixi",
                "run",
                "mojo",
                "run",
                "-I",
                "src",
                "-D",
                "ASSERT=none",
                str(HERE / "bench_decimo.mojo"),
            ]
        )
    )

    print("running CPython ...", file=sys.stderr)
    cpython = json.loads(run(["pixi", "run", "python", str(HERE / "bench_python.py")]))

    pi_table: dict[str, dict[int, float | None]] = {
        "decimo": {int(k): v for k, v in decimo["pi"].items()}
    }
    for library, _label in PI_LIBRARIES:
        if library == "decimo":
            continue
        pi_table[library] = {}
        for precision in PRECISIONS:
            print(f"  pi: {library} at {precision} ...", file=sys.stderr)
            pi_table[library][precision] = pi_cold(library, precision)

    print("cross-checking pi against mpmath ...", file=sys.stderr)
    reference = subprocess.run(
        [
            "pixi",
            "run",
            "-e",
            "benchdoc",
            "python",
            "-c",
            "import mpmath; mpmath.mp.dps=110; print(mpmath.nstr(+mpmath.pi, 100))",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
    ).stdout.strip()
    ours = decimo.get("pi_digits_100", "")
    agree = bool(reference) and ours[:101] == reference[:101]

    DOC.parent.mkdir(parents=True, exist_ok=True)
    DOC.write_text(
        render(context, decimo, libmpdec, cpython, pi_table, agree, ours, reference)
    )
    print(f"wrote {DOC.relative_to(ROOT)}", file=sys.stderr)
    return 0


def render(context, decimo, libmpdec, cpython, pi_table, agree, ours, reference) -> str:
    pr = context["pull_request"]
    pr_text = f"[#{pr}](https://github.com/forfudan/decimo/pull/{pr})" if pr else "—"
    lines: list[str] = []
    add = lines.append

    add("# Benchmarks")
    add("")
    add("<!-- Generated by `pixi run benchdoc`. Do not edit by hand: the next")
    add("     run overwrites this file. See benches/doc/generate.py. -->")
    add("")
    add("Every number here was measured in a single run on one machine, and the")
    add("commit it was measured on is recorded below. Timings are the **minimum**")
    add("over several rounds rather than the mean: noise on a latency benchmark")
    add("only ever adds time, so the minimum is the stable estimator.")
    add("")
    add("| | |")
    add("|---|---|")
    add(f"| Measured | {date.today().isoformat()} |")
    add(f"| Commit | `{context['short']}` — {context['subject']} |")
    add(f"| Branch | `{context['branch']}` |")
    add(f"| Pull request | {pr_text} |")
    add(f"| Machine | {cpython['machine']}, {cpython['platform']} |")
    add(f"| Mojo | {mojo_version()} |")
    add(f"| CPython | {cpython['python']} |")
    add(f"| libmpdec | {libmpdec['version']} (linked directly from C) |")
    add("")

    add("## BigDecimal against libmpdec")
    add("")
    add("CPython's `decimal` module *is* libmpdec, so timing it from Python")
    add("measures libmpdec plus interpreter overhead. The column below links the")
    add("C library directly instead, which is the comparison that says something")
    add("about the arithmetic rather than about CPython.")
    add("")
    add("Both allocate a fresh result per operation, which is what decimo's API")
    add("does and what CPython's `decimal` does. Small operands, precision 28.")
    add("")
    add("| Operation | decimo | libmpdec (C) | |")
    add("|---|---|---|---|")
    for key, label in [
        ("add", "add"),
        ("subtract", "subtract"),
        ("multiply", "multiply"),
        ("divide", "divide"),
        ("round", "round to 10 places"),
        ("from_string", "parse from string"),
    ]:
        ours_ns = decimo["bigdecimal"][key]
        theirs = libmpdec["fresh"][key]
        add(
            f"| {label} | {human(ours_ns)} | {human(theirs)} | {ratio(ours_ns, theirs)} |"
        )
    add("")
    add("For reference, the same operations in CPython (`decimal` through the")
    add("interpreter), and libmpdec writing into a result allocated once instead")
    add("of a fresh one. The second column is what tight C code does; the gap")
    add("between it and the table above is what allocation costs libmpdec, and")
    add("it is the same cost decimo pays.")
    add("")
    add("| Operation | CPython `decimal` | libmpdec, result reused |")
    add("|---|---|---|")
    for key, label in [
        ("add", "add"),
        ("subtract", "subtract"),
        ("multiply", "multiply"),
        ("divide", "divide"),
        ("round", "round to 10 places"),
        ("from_string", "parse from string"),
    ]:
        add(
            f"| {label} | {human(cpython['cpython_decimal'][key])} | {human(libmpdec['reuse'][key])} |"
        )
    add("")

    add("## BigInt against CPython's int")
    add("")
    add("**This comparison is not like the one above.** CPython's integers can")
    add("only be reached through the interpreter, so these numbers include")
    add("interpreter overhead and flatter decimo — most visibly at the smallest")
    add("size, where the overhead is a large share of a very short operation.")
    add("There is no way to remove it, so read the large sizes, where the")
    add("arithmetic dominates, as the meaningful ones.")
    add("")
    add(
        "| Digits | decimo add | CPython add | | decimo multiply | CPython multiply | |"
    )
    add("|---|---|---|---|---|---|---|")
    for size in ("100", "1000", "10000", "100000"):
        ours_add = decimo["bigint"][size]["add"]
        theirs_add = cpython["cpython_int"][size]["add"]
        ours_mul = decimo["bigint"][size]["multiply"]
        theirs_mul = cpython["cpython_int"][size]["multiply"]
        add(
            f"| {int(size):,} | {human(ours_add)} | {human(theirs_add)} | "
            f"{ratio(ours_add, theirs_add)} | {human(ours_mul)} | "
            f"{human(theirs_mul)} | {ratio(ours_mul, theirs_mul)} |"
        )
    add("")

    add("## pi() against mpmath and MPFR")
    add("")
    add("Each measurement runs in a **fresh process**. Both mpmath and MPFR cache")
    add("the constant, so a second call at the same precision would measure the")
    add("cache rather than the algorithm. The timing includes conversion to a")
    add("decimal string, for every library.")
    add("")
    add("mpmath uses Chudnovsky binary splitting; MPFR uses the Brent–Salamin AGM.")
    add("")
    header = "| Digits | " + " | ".join(label for _, label in PI_LIBRARIES) + " |"
    add(header)
    add("|" + "---|" * (len(PI_LIBRARIES) + 1))
    for precision in PRECISIONS:
        cells = []
        for library, _label in PI_LIBRARIES:
            cells.append(human(pi_table.get(library, {}).get(precision)))
        add(f"| {precision:,} | " + " | ".join(cells) + " |")
    add("")
    if agree:
        add("decimo's first 100 digits of pi were checked against mpmath in this")
        add("run and agree exactly.")
    else:
        add("> **Cross-check failed.** decimo's pi(100) did not match mpmath in")
        add("> this run. Treat the table above as unverified.")
        add(">")
        add(f"> decimo:  `{ours[:60]}`")
        add(f"> mpmath:  `{reference[:60]}`")
    add("")
    if any(
        v is None
        for lib in ("mpmath", "mpmath_gmpy", "mpfr")
        for v in pi_table.get(lib, {}).values()
    ):
        add("Entries shown as — were unavailable in this run. `mpmath` and")
        add("`gmpy2` live in the optional `benchdoc` environment; install them")
        add("with `pixi install -e benchdoc`.")
        add("")

    add("## Reproducing")
    add("")
    add("```bash")
    add("pixi run benchdoc")
    add("```")
    add("")
    add("This rebuilds the C benchmark, runs all three suites, and rewrites this")
    add("file. It refuses to run with a dirty working tree, so the commit")
    add("recorded above always describes exactly what was measured.")
    add("")
    return "\n".join(lines)


def mojo_version() -> str:
    try:
        return (
            subprocess.run(
                ["pixi", "run", "mojo", "--version"],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            .stdout.strip()
            .splitlines()[-1]
        )
    except Exception:
        return "unknown"


if __name__ == "__main__":
    sys.exit(main())
