#!/usr/bin/env python3
"""Fails if a `debug_assert` builds its message instead of passing it in pieces.

Mojo evaluates a call's arguments before `debug_assert`'s own `comptime if`
can discard them, so anything that allocates in an argument -- `String(n)`,
`"a" + b`, `.format(...)` -- runs on every call even in a build compiled with
`-D ASSERT=none`. In decimo this was measured at ~59 ns per call inside
`floor_divide_by_power_of_ten_inplace()`, which is more than the operation it
was guarding.

`debug_assert` is variadic, so the fix is always to pass the pieces
separately: `debug_assert(cond, "n was ", n)` rather than
`debug_assert(cond, "n was " + String(n))`.

Upstream bug, still open as of Mojo 1.0.0:
https://github.com/modular/modular/issues/6439 -- when it is fixed this check
can go away.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

CALL = re.compile(r"debug_assert(?:\[[^\]]*\])?\(")
ALLOCATING = (
    (re.compile(r"\.format\("), "`.format(...)` builds a String"),
    (re.compile(r"\bString\("), "`String(...)` allocates"),
    (re.compile(r'"\s*\+|\+\s*String|\+\s*"'), "string concatenation allocates"),
    (re.compile(r"\.join\("), "`.join(...)` allocates"),
)


def spans(text: str):
    """Yields (line_number, argument_text) for every `debug_assert` call."""
    for match in CALL.finditer(text):
        start = match.end()
        depth, i = 1, start
        while i < len(text) and depth:
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
            i += 1
        yield text.count("\n", 0, match.start()) + 1, text[start : i - 1]


MOJO_SUFFIXES = (".mojo", ".\U0001f525")


def discover() -> list[Path]:
    """Every Mojo source under `src`, in either spelling of the suffix."""
    found: list[Path] = []
    for suffix in MOJO_SUFFIXES:
        found.extend(Path("src").rglob("*" + suffix))
    return sorted(found)


def main(argv: list[str]) -> int:
    paths = [Path(a) for a in argv[1:]] or discover()
    failures = []
    for path in paths:
        if path.suffix not in MOJO_SUFFIXES or not path.exists():
            continue
        text = path.read_text()
        for line, args in spans(text):
            for pattern, why in ALLOCATING:
                if pattern.search(args):
                    failures.append(f"{path}:{line}: {why}")
                    break

    if failures:
        print("debug_assert messages must be passed as pieces, not built:\n")
        for failure in failures:
            print("  " + failure)
        print(
            '\nUse the variadic form:  debug_assert(cond, "n was ", n)'
            "\nWhy: https://github.com/modular/modular/issues/6439"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
