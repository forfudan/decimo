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
    # Two traps here. `gh pr list` shows only open pull requests, so a merged
    # one reads as none. And `gh pr view <branch>` matches on branch *name*
    # alone -- an old merged pull request that reused this branch name will be
    # returned, with an unrelated head commit. So the head commit must match
    # what is actually being measured, or no number is reported at all.
    pull_request = None
    pull_request_state = None
    if shutil.which("gh"):
        try:
            found = (
                subprocess.run(
                    [
                        "gh",
                        "pr",
                        "view",
                        branch,
                        "--json",
                        "number,state,headRefOid",
                        "--jq",
                        r'"\(.number) \(.state) \(.headRefOid)"',
                    ],
                    cwd=ROOT,
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                .stdout.strip()
                .split()
            )
            if len(found) == 3 and found[0].isdigit() and found[2] == commit:
                pull_request = int(found[0])
                pull_request_state = found[1].lower()
        except Exception:
            pull_request = None
    return {
        "commit": commit,
        "short": commit[:7],
        "branch": branch,
        "subject": subject,
        "dirty": dirty,
        "pull_request": pull_request,
        "pull_request_state": pull_request_state,
    }


def libmpdec_flags() -> list[str]:
    """Include and library flags for libmpdec, however it is installed.

    `platforms` covers Linux as well as macOS, so this cannot assume Homebrew.
    Tries pkg-config, then Homebrew, then the usual prefixes.
    """
    if shutil.which("pkg-config"):
        probe = subprocess.run(
            ["pkg-config", "--cflags", "--libs", "libmpdec"],
            capture_output=True,
            text=True,
        )
        if probe.returncode == 0 and probe.stdout.strip():
            return probe.stdout.split()
    candidates = []
    if shutil.which("brew"):
        found = subprocess.run(
            ["brew", "--prefix", "mpdecimal"], capture_output=True, text=True
        ).stdout.strip()
        if found:
            candidates.append(found)
    candidates += ["/opt/homebrew", "/usr/local", "/usr"]
    for prefix in candidates:
        if (Path(prefix) / "include" / "mpdecimal.h").exists():
            return [f"-I{prefix}/include", f"-L{prefix}/lib", "-lmpdec"]
    raise SystemExit(
        "libmpdec headers not found. Install mpdecimal (macOS: "
        "`brew install mpdecimal`; Debian/Ubuntu: `apt install libmpdec-dev`)."
    )


def build_libmpdec() -> Path:
    binary = Path(os.environ.get("TMPDIR", "/tmp")) / "decimo_bench_libmpdec"
    subprocess.run(
        [
            "cc",
            "-O2",
            *libmpdec_flags(),
            str(HERE / "bench_libmpdec.c"),
            "-o",
            str(binary),
        ],
        check=True,
    )
    return binary


def pi_cold(library: str, precision: int) -> float | None:
    """Minimum over several cold measurements, each in its own process.

    One sample is not enough. A single descheduled process produced a
    10 000-digit reading fifty times too slow, which is exactly the kind of
    number that would sit in a published table looking plausible. Taking the
    minimum of a few costs a little wall-clock and removes the whole class of
    error.
    """
    if library == "decimo":
        return None  # taken from the Mojo run, which is already cold per call
    env = dict(os.environ)
    if library == "mpmath":
        env["MPMATH_NOGMPY"] = "1"
    samples = 1 if precision >= 1_000_000 else 3
    best = None
    for _ in range(samples):
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
            value = float(tail[-1])
        except ValueError:
            return None
        best = value if best is None else min(best, value)
    return best


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
    if 0.95 <= value <= 1.05:
        return "parity"
    if value > 1.0:
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
    pr_text = (
        f" · PR [#{pr}](https://github.com/forfudan/decimo/pull/{pr})" if pr else ""
    )
    lines: list[str] = []
    add = lines.append

    add("# Benchmarks")
    add("")
    add("<!-- Generated by `pixi run benchdoc`. Do not edit: the next run")
    add("     overwrites this file. See benches/doc/generate.py. -->")
    add("")
    add(
        f"{date.today().isoformat()} · commit [`{context['short']}`]"
        f"(https://github.com/forfudan/decimo/commit/{context['commit']})"
        f"{pr_text} · {cpython['machine']}, {cpython['platform']}"
    )
    add("")
    add(
        f"Mojo {mojo_version().replace('Mojo ', '')} · CPython "
        f"{cpython['python']} · libmpdec {libmpdec['version']}, linked from C"
    )
    add("")
    add("Each figure is the minimum over several rounds, on an idle machine.")
    add("Regenerate with `pixi run benchdoc`.")
    add("")

    add("## BigDecimal")
    add("")
    add("9-digit operands, precision 28. libmpdec is the C library behind")
    add("CPython's `decimal`, timed without the interpreter.")
    add("")
    add("| Operation | decimo | libmpdec | CPython `decimal` | |")
    add("|---|---|---|---|---|")
    for key, label in [
        ("add", "add"),
        ("subtract", "subtract"),
        ("multiply", "multiply"),
        ("divide", "divide"),
        ("round", "round"),
        ("from_string", "parse"),
    ]:
        ours_ns = decimo["bigdecimal"][key]
        add(
            f"| {label} | {human(ours_ns)} | {human(libmpdec['fresh'][key])} | "
            f"{human(cpython['cpython_decimal'][key])} | "
            f"{ratio(ours_ns, libmpdec['fresh'][key])} |"
        )
    add("")
    add("In place, where neither side allocates a result:")
    add("")
    add("| | decimo | libmpdec | |")
    add("|---|---|---|---|")
    for key, label in [
        ("add", "`x += y`"),
        ("subtract", "`x -= y`"),
        ("multiply", "`x *= y`"),
    ]:
        ours_ns = decimo["bigdecimal_inplace"][key]
        add(
            f"| {label} | {human(ours_ns)} | {human(libmpdec['inplace'][key])} "
            f"| {ratio(ours_ns, libmpdec['inplace'][key])} |"
        )
    add("")

    add("## BigDecimal across operand sizes")
    add("")
    add("| Digits | add | | multiply | | divide | |")
    add("|---|---|---|---|---|---|---|")
    add("| | decimo | libmpdec | decimo | libmpdec | decimo | libmpdec |")
    for width in ("9", "100", "1000", "10000", "100000"):
        row = [f"| {int(width):,} "]
        for op in ("add", "multiply", "divide"):
            row.append(f"| {human(decimo['sweep'][width][op])} ")
            row.append(f"| {human(libmpdec['sweep'][width][op])} ")
        add("".join(row) + "|")
    add("")

    add("## BigInt against CPython's int")
    add("")
    add("CPython's integers can only be reached through the interpreter, so")
    add("these include its overhead — read the large sizes as the real ones.")
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

    add("## pi()")
    add("")
    add("Each measurement in a fresh process, since mpmath and MPFR cache the")
    add("constant. Includes conversion to a decimal string, for every library.")
    add("")
    header = "| Digits | " + " | ".join(label for _, label in PI_LIBRARIES) + " |"
    add(header)
    add("|" + "---|" * (len(PI_LIBRARIES) + 1))
    for precision in PRECISIONS:
        cells = [
            human(pi_table.get(library, {}).get(precision))
            for library, _label in PI_LIBRARIES
        ]
        add(f"| {precision:,} | " + " | ".join(cells) + " |")
    add("")
    if not agree:
        add("> **Cross-check failed.** decimo's pi(100) did not match mpmath in")
        add("> this run. Treat the table above as unverified.")
        add(">")
        add(f"> decimo: `{ours[:60]}`")
        add(f"> mpmath: `{reference[:60]}`")
        add("")
    if any(
        v is None
        for lib in ("mpmath", "mpmath_gmpy", "mpfr")
        for v in pi_table.get(lib, {}).values()
    ):
        add("Entries shown as — need the optional environment:")
        add("`pixi install -e benchdoc`.")
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
