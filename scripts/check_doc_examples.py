#!/usr/bin/env python3
"""Runs the Mojo examples in the documentation and checks what they print.

Every fenced ```mojo block is compiled and run against the working tree, and
each `print(...)` whose trailing comment names a value is compared with the
line that print actually produced. A comment that only describes the result
in prose is left alone, so this checks the facts and not the wording.

Usage:
    python3 scripts/check_doc_examples.py README.md docs/user_manual.md ...

A block with no `def main` is a fragment: it gets `decimo.prelude`, every
`decimo` import that appeared earlier in the same file, and a `main` to sit
in. That is what a reader does when they work through a section from the top,
and it is why the imports accumulate rather than resetting at each block.
Only Decimo's own imports carry forward, because one line that will not
resolve would otherwise break every block after it.

The exit status is non-zero when a value disagrees or an example that was not
marked as raising fails to run, so this can gate a release. It is not in the
test suite because each block is a separate compile and the whole manual
takes minutes.
"""

import os
import re
import subprocess
import sys
import tempfile

# A claim worth checking looks like a value: a number, a bool, a quoted
# string, one of the special values. Anything else is prose about the result.
_VALUE = re.compile(
    r"^(?:[-+]?[0-9][0-9_.,]*(?:[eE][-+]?[0-9]+)?|True|False|NaN|"
    r"[-+]?Infinity|\"[^\"]*\"|[-+]?0)$"
)

# Prose that happens to start with a digit, or a value written as an
# expression rather than as the digits the program prints.
_NOT_A_VALUE = re.compile(r"\.\.\.|\^|digits|bits|places|significant")


def blocks_of(path):
    """Yields `(line number, body lines)` for each fenced Mojo block."""
    lines = open(path, encoding="utf-8").read().split("\n")
    i = 0
    while i < len(lines):
        if lines[i].strip() == "```mojo":
            j = i + 1
            while j < len(lines) and lines[j].strip() != "```":
                j += 1
            yield i + 2, lines[i + 1 : j]
            i = j
        i += 1


def claims_of(body):
    """The trailing comment of each `print(...)`, in the order they run."""
    out = []
    k = 0
    while k < len(body):
        if re.match(r"\s*print\(", body[k]):
            depth = body[k].count("(") - body[k].count(")")
            j = k
            while depth > 0 and j + 1 < len(body):
                j += 1
                depth += body[j].count("(") - body[j].count(")")
            m = re.search(r"#\s*(.*)$", body[j])
            out.append(m.group(1).strip() if m else "")
            k = j + 1
        else:
            k += 1
    return out


def value_of(claim):
    """The value a claim names, or None where it only describes the result."""
    if not claim or _NOT_A_VALUE.search(claim):
        return None
    candidate = claim.split(": ")[-1].strip().rstrip(".")
    if not _VALUE.match(candidate):
        return None
    return candidate.strip('"')


def source_of(body, carried):
    """The runnable program for one block, and whether it was a fragment."""
    text = "\n".join(body)
    if "def main" in text:
        return text, False
    head = [l for l in body if l.startswith(("from ", "import "))]
    rest = [l for l in body if not l.startswith(("from ", "import "))]
    return (
        "from decimo.prelude import *\n"
        + "\n".join(carried + head)
        + "\n\n\ndef main() raises:\n"
        + "\n".join("    " + l for l in rest),
        True,
    )


def check(path, directory):
    """Checks one file. Returns the number of disagreements."""
    carried = []
    wrong = 0
    for start, body in blocks_of(path):
        claims = claims_of(body)
        text, fragment = source_of(body, carried)
        carried += [l for l in body if l.startswith("from decimo")]
        if not any(value_of(c) for c in claims):
            continue
        name = os.path.join(
            directory, "%s_%d.mojo" % (os.path.basename(path)[:-3], start)
        )
        with open(name, "w", encoding="utf-8") as f:
            f.write(text + "\n")
        try:
            run = subprocess.run(
                ["pixi", "run", "one", name],
                capture_output=True,
                text=True,
                timeout=600,
            )
        except subprocess.TimeoutExpired:
            print("%s:%d: the example did not finish" % (path, start))
            wrong += 1
            continue
        if run.returncode != 0:
            if "raises" in "\n".join(body):
                continue
            errors = [l for l in run.stderr.split("\n") if "error:" in l]
            print(
                "%s:%d: the example did not run -- %s"
                % (path, start, errors[0][:120] if errors else "see above")
            )
            wrong += 1
            continue
        got = [l for l in run.stdout.split("\n") if not l.startswith("\N{SPARKLES}")]
        while got and got[-1] == "":
            got.pop()
        for k, claim in enumerate(claims):
            value = value_of(claim)
            if value is None:
                continue
            line = got[k] if k < len(got) else "<nothing printed>"
            if value not in line and line not in value:
                print(
                    "%s:%d: print %d claims %r and prints %r"
                    % (path, start, k, value, line)
                )
                wrong += 1
    return wrong


def main():
    paths = sys.argv[1:]
    if not paths:
        print(__doc__)
        return 2
    wrong = 0
    with tempfile.TemporaryDirectory() as directory:
        for path in paths:
            wrong += check(path, directory)
    if wrong:
        print("%d claim(s) in the documentation do not hold" % wrong)
        return 1
    print("every value the documentation claims is the value it prints")
    return 0


if __name__ == "__main__":
    sys.exit(main())
