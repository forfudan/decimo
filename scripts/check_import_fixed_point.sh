#!/bin/bash
# ===----------------------------------------------------------------------=== #
# Asserts that `organize_mojo_imports.py` and `mojo format` agree.
#
# The two tools both rewrite import statements. If they disagree about even
# one line -- a width computed rather than measured, a magic trailing comma
# collapsed -- each undoes the other's work on every run, and the repository
# never reaches a stable state. The check is a fixed point:
#
#     organize -> mojo format -> organize --check
#
# The last step must find nothing to do, and the tree must be byte-identical
# to what the first step produced.
#
# Runs over a scratch copy of the whole tree, never over the working copy.
#
# Usage:
#   bash scripts/check_import_fixed_point.sh
# ===----------------------------------------------------------------------=== #

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH" "$SCRATCH.after-organize" "$SCRATCH.diff"' EXIT

TARGETS=(src tests benches examples python docs)
ORGANIZE="python3 $REPO/scripts/organize_mojo_imports.py"

echo ">>> copying the tree to $SCRATCH"
for target in "${TARGETS[@]}"; do
    cp -R "$REPO/$target" "$SCRATCH/"
done

cd "$SCRATCH"

echo ">>> 1. organize"
$ORGANIZE "${TARGETS[@]}"
cp -R "$SCRATCH" "$SCRATCH.after-organize"

echo ">>> 2. mojo format"
(cd "$REPO" && for target in "${TARGETS[@]}"; do
    pixi run mojo format "$SCRATCH/$target" >/dev/null
done)

echo ">>> 3. organize --check"
if ! $ORGANIZE "${TARGETS[@]}" --check; then
    echo "FAIL: mojo format changed something the organizer wants back." >&2
    exit 1
fi

echo ">>> 4. byte-identical to step 1"
if ! diff -r "$SCRATCH.after-organize" "$SCRATCH" >"$SCRATCH.diff" 2>&1; then
    echo "FAIL: mojo format rewrote the organizer's output:" >&2
    head -40 "$SCRATCH.diff" >&2
    exit 1
fi
echo ">>> 5. organizing twice is a no-op"
$ORGANIZE "${TARGETS[@]}" >/dev/null
if ! $ORGANIZE "${TARGETS[@]}" --check; then
    echo "FAIL: the organizer is not idempotent." >&2
    exit 1
fi

echo ">>> 6. the remaining invariants"
python3 - "$REPO" <<'PYEOF'
import subprocess
import sys
import tempfile
from pathlib import Path

repo = Path(sys.argv[1])
tool = repo / "scripts" / "organize_mojo_imports.py"


def organize(text: str, *flags: str) -> tuple[str, str]:
    """Runs the organizer over one file, returning (stdout, file contents)."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "sample.mojo"
        path.write_text(text)
        done = subprocess.run(
            [sys.executable, str(tool), str(path), *flags],
            capture_output=True,
            text=True,
        )
        return done.stdout, path.read_text()


def check(name: str, condition: bool) -> None:
    print(f"    {'ok  ' if condition else 'FAIL'} {name}")
    if not condition:
        sys.exit(1)


messy = (
    '"""Doc."""\n\n'
    "from decimo.b import Two\n"
    "from std.sys import size_of\n"
    "from decimo.a import One\n"
    "import decimo.biguint.arithmetics as biguint_arithmetics\n"
    "\n\nstruct S:\n    pass\n"
)

_, unchanged = organize(messy, "--check")
check("--check writes nothing", unchanged == messy)

diff_out, unchanged = organize(messy, "--diff")
check("--diff writes nothing", unchanged == messy)
check("--diff prints a diff", diff_out.startswith("---"))

_, organized = organize(messy)
check(
    "aliased import round-trips verbatim",
    "import decimo.biguint.arithmetics as biguint_arithmetics\n" in organized,
)
check("stdlib comes first", organized.index("std.sys") < organized.index("decimo.a"))
check("body is untouched", organized.endswith("\n\nstruct S:\n    pass\n"))

_, again = organize(organized)
check("an already-correct file is not rewritten", again == organized)

interleaved = (
    "from std.sys import size_of\n"
    "# a comment between two imports\n"
    "from decimo.a import One\n"
    "\n\nstruct S:\n    pass\n"
)
_, left_alone = organize(interleaved)
check("a comment between imports means hands off", left_alone == interleaved)

fenced = (
    '"""Doc.\n\n```mojo\nfrom decimo.prelude import *\n```\n"""\n\n'
    "from std.sys import size_of\n"
    "\n\nstruct S:\n    pass\n"
)
_, kept = organize(fenced)
check("an import inside a docstring is not an import", kept == fenced)

# Inputs that a fuzzer showed could corrupt an earlier version of the tool.
# Each must now come back either untouched or correctly organized -- never
# with a lost name, a swallowed body, or a different result on the second run.
hostile = {
    "unclosed parenthesis, code below": (
        "from decimo.a import (\n    Alpha,\n    Beta,\n\n\n"
        "fn main():\n    print(Alpha, Beta)\n"
    ),
    "unclosed parenthesis, balanced by a later line": (
        "from decimo.a import (\n    Alpha,\n\nfn main():\n    call(1)\n"
    ),
    "file ends inside the parentheses": "from decimo.a import (\n    Alpha,\n",
    "empty name list": "from decimo.a import ()\n\ncomptime X = 1\n",
    "unbalanced paren in a trailing comment": (
        "from decimo import Foo  # see bar(\n"
        "import std\n\n\nfn main():\n    var x = 1\n"
    ),
    "trailing comment beside two names": (
        "from decimo import Zeta, Alpha  # drop Zeta\n\n\nfn main():\n    pass\n"
    ),
    "comment inside the parentheses": (
        "from decimo import (\n    Bar,  # this one\n    Foo,\n)\n"
        "\n\nfn main():\n    pass\n"
    ),
    "closing paren inside a comment": (
        "from decimo import (\n    Bar,  # a ) here\n    Foo,\n)\n"
        "\n\nfn main():\n    pass\n"
    ),
    "backslash continuation": (
        "from decimo import Bar, \\\n    Foo\n\n\nfn main():\n    pass\n"
    ),
    "escaped triple quote in a docstring": (
        '\"\"\"Doc \\\"\"\" not the end.\n\nfrom zzz import Later\n'
        'from std import Early\n\"\"\"\n\n\nfn main():\n    pass\n'
    ),
}


def body_lines(text: str) -> list[str]:
    return [
        line
        for line in text.splitlines()
        if line.strip() and not line.startswith(("from ", "import "))
    ]


# Byte-identical, not merely body-preserving. Comparing only the non-import
# lines passes vacuously here: the import lines are exactly what would move.
for label, source in hostile.items():
    _, once = organize(source)
    check(f"untouched: {label}", once == source)

organizable = {
    "multi-module plain import": (
        "import unknownpkg, decimo\nimport argmojo\n\n\nfn main():\n    pass\n"
    ),
}
for label, source in organizable.items():
    _, once = organize(source)
    _, twice = organize(once)
    check(
        f"organized: {label}",
        body_lines(once) == body_lines(source) and once == twice,
    )

no_yes = subprocess.run(
    [sys.executable, str(tool), str(repo / "src"), "--remove-unused"],
    capture_output=True,
    text=True,
)
check("--remove-unused refuses to write without --yes", no_yes.returncode == 2)
PYEOF


echo ">>> 7. the skip list is exactly the two known files"
EXPECTED="src/decimo/__init__.mojo src/decimo/biguint/ntt.mojo"
ACTUAL="$($ORGANIZE "${TARGETS[@]}" --check 2>&1 \
    | sed -n 's/^skipped, imports not safe to rewrite: //p' | sort | tr '\n' ' ')"
if [ "$ACTUAL" != "$EXPECTED " ]; then
    echo "FAIL: the set of skipped files changed." >&2
    echo "  expected: $EXPECTED" >&2
    echo "  actual:   $ACTUAL" >&2
    echo "A skipped file never fails --check, so a new one must fail here." >&2
    exit 1
fi

echo ">>> 8. the 80-column boundary is the one mojo format uses"
# Steps 3 to 5 cannot see MAX_LINE_LENGTH: a parenthesized import carries a
# trailing comma, which `mojo format` honours, so a wrong width is stable and
# invisible. Give both tools the same one-line import instead and check they
# make the same choice about wrapping it.
WIDTH="$SCRATCH/width"
mkdir -p "$WIDTH"
python3 - "$WIDTH" <<'PYEOF'
import sys
from pathlib import Path

out = Path(sys.argv[1])
prefix = "from decimo.w import "
for columns in (79, 80, 81):
    line = prefix + "N" * (columns - len(prefix)) + "\n"
    assert len(line.rstrip("\n")) == columns, len(line.rstrip("\n"))
    for who in ("organized", "formatted"):
        (out / f"{who}_{columns}.mojo").write_text(line + "\n\ncomptime X = 1\n")
PYEOF
$ORGANIZE "$WIDTH"/organized_*.mojo >/dev/null
(cd "$REPO" && pixi run mojo format "$WIDTH" >/dev/null)
for columns in 79 80 81; do
    if ! diff -q "$WIDTH/organized_$columns.mojo" "$WIDTH/formatted_$columns.mojo" \
        >/dev/null; then
        echo "FAIL: at $columns columns the organizer and mojo format disagree." >&2
        diff "$WIDTH/organized_$columns.mojo" "$WIDTH/formatted_$columns.mojo" >&2
        exit 1
    fi
done

echo "OK: every invariant holds."
