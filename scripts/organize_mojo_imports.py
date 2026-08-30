#!/usr/bin/env python3
"""Groups, sorts and de-duplicates the imports in Mojo sources.

Imports are emitted in four blocks separated by one blank line, in this order:
the Mojo standard library, third-party packages, `decimo` itself, and modules
reached through `-I` (relative imports, `calculator`, `limo`, `bench_*`).
Within a block the statements are sorted by module path, with `from X import`
and `import X as` interleaved so that a family such as `decimo.bigdecimal.*`
stays together.

Usage:
    python3 scripts/organize_mojo_imports.py src tests benches examples python docs

The output is a fixed point of `pixi run mojo format`: a `from ... import`
that fits in 80 columns is written on one line, anything longer is
parenthesized with a trailing comma, and a statement the author already wrote
parenthesized keeps that shape because `mojo format` honours the magic
trailing comma. If the two tools disagree about one line they rewrite each
other's output on every run, so `scripts/check_import_fixed_point.sh` asserts
they do not.

Grouping and sorting are always safe. Dropping names that appear unused is
opt-in twice over (`--remove-unused --yes`), because "unused" is decided by a
text scan of the rest of the file rather than by the compiler.

A file is left alone entirely, and reported as skipped rather than clean,
whenever its imports are not safe to rewrite: a comment anywhere in the block
(between two statements, inside the parentheses, or trailing one), a backslash
continuation, a statement that will not parse, a carriage return, a byte-order
mark, or text that is not UTF-8. Sorting names around a comment attaches it to
the wrong one and buries a real name inside it; mangling imports is far worse
than skipping a file.
"""

from __future__ import annotations

import argparse
import difflib
import re
import sys
from dataclasses import dataclass, replace
from pathlib import Path

FROM_RE = re.compile(r"^from\s+(?P<module>\S+)\s+import\s+(?P<names>.+)$", re.DOTALL)
IMPORT_AS_RE = re.compile(r"^(?P<module>[^\s,]+)(?:\s+as\s+(?P<alias>\w+))?$")
IDENT_RE = re.compile(r"`[^`]+`|[A-Za-z_][A-Za-z0-9_]*")
# Plain words only. `IDENT_RE`'s backtick branch would swallow a whole
# ```mojo fence as one identifier, which is exactly what a docstring is
# full of here.
WORD_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
CONTINUATION_RE = re.compile(r"^[\s\w.,*()`]*$")
NAME_RE = re.compile(
    r"^(?:\*|`[^`]+`|[A-Za-z_]\w*)(?:\s+as\s+(?:`[^`]+`|[A-Za-z_]\w*))?$"
)

MOJO_SUFFIXES = (".mojo", ".\U0001f525")

# `mojo format` wraps at 80 columns; match it so the two tools agree.
MAX_LINE_LENGTH = 80

# Emission order. There are no titles -- one blank line separates the blocks,
# and the order itself carries the grouping.
GROUP_STDLIB = 0
GROUP_THIRD_PARTY = 1
GROUP_DECIMO = 2
GROUP_LOCAL = 3

# Sibling modules found through `-I`, not installed packages, so they belong
# with the relative imports rather than with the third-party ones.
LOCAL_ROOTS = frozenset({"calculator", "limo"})
LOCAL_ROOT_PREFIX = "bench_"

# These re-export on purpose, so nothing in them is ever "unused".
REEXPORTING_FILES = frozenset({"__init__.mojo", "prelude.mojo"})


@dataclass(frozen=True)
class ImportedName:
    """One name in an import, and the identifier it binds in this file."""

    raw: str
    bound: str


@dataclass(frozen=True)
class ImportStatement:
    kind: str
    module: str
    imported: tuple[ImportedName, ...]
    sortable: bool = True
    force_parenthesized: bool = False

    @property
    def has_wildcard(self) -> bool:
        return any(name.raw == "*" for name in self.imported)


def normalize_identifier(value: str) -> str:
    """Strips the backticks Mojo allows around a name used as an identifier."""
    value = value.strip()
    if value.startswith("`") and value.endswith("`"):
        return value[1:-1]
    return value


def split_top_level_commas(value: str) -> list[str]:
    """Splits on commas that are not inside parentheses."""
    parts: list[str] = []
    current: list[str] = []
    depth = 0
    for char in value:
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == "," and depth == 0:
            item = "".join(current).strip()
            if item:
                parts.append(item)
            current = []
            continue
        current.append(char)
    item = "".join(current).strip()
    if item:
        parts.append(item)
    return parts


def strip_outer_parens(value: str) -> str:
    value = value.strip()
    if value.startswith("(") and value.endswith(")"):
        return value[1:-1]
    return value


def imported_bound_name(raw_name: str) -> str:
    """The identifier an imported name binds, honouring `as`."""
    name = raw_name.strip().rstrip(",")
    if " as " in name:
        return normalize_identifier(name.rsplit(" as ", 1)[1])
    return normalize_identifier(name)


def parse_from_import(text: str) -> ImportStatement | None:
    flattened = " ".join(line.strip() for line in text.splitlines())
    match = FROM_RE.match(flattened)
    if not match:
        return None
    names_text = strip_outer_parens(match.group("names"))
    names = []
    for item in split_top_level_commas(names_text):
        item = item.strip().rstrip(",")
        if item:
            # An unclosed parenthesis can pull real code this far. A name that
            # is not a name means the statement is not one either, and joining
            # the lines would delete whatever was caught in it.
            if not NAME_RE.match(item):
                return None
            names.append(ImportedName(item, imported_bound_name(item)))
    if not names:
        return None
    return ImportStatement(
        kind="from",
        module=match.group("module"),
        imported=tuple(names),
        # `mojo format` keeps a parenthesized import exploded only when the
        # trailing comma is there, so key off the comma rather than off the
        # line count. Otherwise organize-then-format and format-then-organize
        # settle on different shapes for the same input.
        force_parenthesized=names_text.rstrip().endswith(","),
    )


def parse_plain_import(text: str) -> ImportStatement | None:
    flattened = " ".join(line.strip() for line in text.splitlines())
    if not flattened.startswith("import "):
        return None
    names = []
    modules = []
    for item in split_top_level_commas(flattened[len("import ") :]):
        match = IMPORT_AS_RE.match(item.strip())
        if not match:
            return ImportStatement(
                kind="import",
                module=flattened,
                imported=(),
                sortable=False,
            )
        module = match.group("module")
        alias = match.group("alias")
        modules.append(module)
        names.append(ImportedName(item.strip(), alias or module.split(".")[0]))
    return ImportStatement(
        kind="import",
        # Sorted, because the renderer sorts the modules too. Keying the group
        # off whichever module happened to be written first would put the
        # statement in a different block on the next run.
        module=",".join(sorted(modules, key=str.lower)),
        imported=tuple(names),
    )


def parse_import_statement(text: str) -> ImportStatement | None:
    stripped = text.lstrip()
    if stripped.startswith("from "):
        return parse_from_import(text)
    if stripped.startswith("import "):
        return parse_plain_import(text)
    return None


def end_of_short_string(line: str, position: int, quote: str) -> int:
    """Index just past the single- or double-quoted string opened at `position`."""
    position += 1
    while position < len(line):
        if line[position] == "\\":
            position += 2
            continue
        if line[position] == quote:
            return position + 1
        position += 1
    return position


def lines_inside_triple_quoted_strings(lines: list[str]) -> set[int]:
    """Line indices that fall inside a triple-quoted string.

    Import-like text in a docstring -- decimo's docstrings are full of fenced
    examples showing `from decimo.prelude import *` -- is not an import.

    A triple quote only opens a string where one can actually open. Counting
    the one written inside a `#` comment, or inside an ordinary quoted string,
    would flip the tracker for the rest of the file and quietly classify every
    real import below it as docstring text, so the file would be reported
    clean without ever having been looked at.
    """
    inside: set[int] = set()
    triple: str | None = None
    for index, line in enumerate(lines):
        started_inside = triple is not None
        position = 0
        while position < len(line):
            if triple is not None:
                # Escapes count inside the string too: a backslash before
                # a triple quote does not close the docstring, and reading
                # it as a close makes every line below look like code.
                if line[position] == "\\":
                    position += 2
                    continue
                if line.startswith(triple, position):
                    triple = None
                    position += 3
                    continue
                position += 1
                continue
            char = line[position]
            if char == "\\":
                position += 2
                continue
            if char == "#":
                break
            if char in ("'", '"'):
                if line.startswith(char * 3, position):
                    triple = char * 3
                    position += 3
                    continue
                position = end_of_short_string(line, position, char)
                continue
            position += 1
        if started_inside or triple is not None:
            inside.add(index)
    return inside


def code_before_comment(line: str) -> str:
    """The line with any trailing `#` comment removed, quotes respected."""
    position = 0
    while position < len(line):
        char = line[position]
        if char == "\\":
            position += 2
            continue
        if char == "#":
            return line[:position]
        if char in ("'", '"'):
            position = end_of_short_string(line, position, char)
            continue
        position += 1
    return line


def paren_delta(line: str) -> int:
    """Net parenthesis depth of a line, ignoring anything in a comment.

    Counting a `(` written inside a comment makes the collector below run to
    the end of the file and swallow the whole program into one statement.
    """
    code = code_before_comment(line)
    return code.count("(") - code.count(")")


def collect_import_statement(lines: list[str], start: int) -> tuple[str, int, bool]:
    """The statement at `start`, the index after it, and whether it is plain.

    "Plain" means it carries no comment and no backslash continuation. Both
    would be sorted along with the imported names, which buries a real name
    inside comment text or orphans it on its own line.
    """
    collected = [lines[start]]
    depth = paren_delta(lines[start])
    index = start + 1
    while depth > 0 and index < len(lines):
        # Inside an import's parentheses there are only names, `as`, commas,
        # backticks and parens. Anything else means the parenthesis never
        # closed -- a file caught mid-edit or mid-merge -- and without this
        # the collector eats the rest of the program into one statement.
        if not CONTINUATION_RE.match(lines[index]):
            return "".join(collected), index, False
        collected.append(lines[index])
        depth += paren_delta(lines[index])
        index += 1
    text = "".join(collected)
    plain = depth == 0 and all(
        code_before_comment(line) == line
        and not code_before_comment(line).rstrip().endswith("\\")
        for line in collected
    )
    return text, index, plain


def starts_import(line: str) -> bool:
    return line.startswith("from ") or line.startswith("import ")


def find_import_block(lines: list[str]) -> tuple[int, int, list[str]] | None:
    """Returns (start, end, statement texts), or None to leave the file alone.

    `end` is the line after the *last* import, never the line after the first
    thing that is not one. A comment below the last import belongs to the code
    that follows and must stay exactly where the author put it; only a comment
    inside the block itself is ambiguous, and that is what makes this function
    give up.
    """
    in_string = lines_inside_triple_quoted_strings(lines)
    start = None
    for index, line in enumerate(lines):
        if index not in in_string and starts_import(line):
            start = index
            break
    if start is None:
        return None

    # Walk over everything that could plausibly be part of an import block,
    # remembering where the last real import ended and whether a comment was
    # seen before it.
    statements: list[str] = []
    comment_before: list[int] = []
    index = start
    end = start
    while index < len(lines):
        stripped = lines[index].strip()
        if stripped == "":
            index += 1
            continue
        if stripped.startswith("#"):
            comment_before.append(index)
            index += 1
            continue
        if index not in in_string and starts_import(lines[index]):
            text, index, plain = collect_import_statement(lines, index)
            if not plain:
                return None
            statements.append(text)
            end = index
            continue
        break

    if any(position < end for position in comment_before):
        return None
    return start, end, statements


def import_group(module: str) -> int:
    """Which of the four blocks a module belongs to."""
    if module.startswith("."):
        return GROUP_LOCAL
    root = module.split(".", 1)[0].split(",", 1)[0]
    if root == "std":
        return GROUP_STDLIB
    if root == "decimo":
        return GROUP_DECIMO
    if root in LOCAL_ROOTS or root.startswith(LOCAL_ROOT_PREFIX):
        return GROUP_LOCAL
    return GROUP_THIRD_PARTY


def name_kind(raw: str) -> int:
    """0 for a SCREAMING constant, 1 for a Type, 2 for a function.

    The `as` clause does not decide anything -- what the name refers to does.
    """
    base = raw.split(" as ")[0].strip().strip("`")
    if len(base) > 1 and base.isupper():
        return 0
    if base[:1].isupper():
        return 1
    return 2


def sort_imported_names(names: tuple[ImportedName, ...]) -> tuple[ImportedName, ...]:
    """Constants, then types, then functions; alphabetical inside each.

    This is isort's `order-by-type`, which is what `ruff` already applies to
    this repository's Python. Sorting on the name alone interleaves the three
    kinds -- six ANSI colour constants with two functions between them, in the
    worst case here. The cost is that a type no longer sits beside the
    functions sharing its stem: `Wide` leaves `wide_multiply`. The functions
    themselves stay together, so the stem is still readable.
    """
    return tuple(
        sorted(
            names, key=lambda item: (name_kind(item.raw), item.raw.strip("`").lower())
        )
    )


def render_parenthesized(module: str, names: tuple[ImportedName, ...]) -> str:
    body = "".join(f"    {name.raw},\n" for name in names)
    return f"from {module} import (\n{body})\n"


def render_from_import(module: str, names: tuple[ImportedName, ...]) -> str:
    """One line if it fits in 80 columns, parenthesized if it does not.

    The rendered line is measured, not approximated: `from `, ` import ` and
    every `, ` count against the budget `mojo format` enforces.
    """
    names = sort_imported_names(names)
    joined = ", ".join(name.raw for name in names)
    one_line = f"from {module} import {joined}\n"
    if len(one_line.rstrip("\n")) <= MAX_LINE_LENGTH:
        return one_line
    return render_parenthesized(module, names)


def render_import_statement(statement: ImportStatement) -> str:
    if statement.kind == "from":
        # A statement the author wrote parenthesized keeps that shape: the
        # trailing comma is a magic trailing comma that `mojo format` honours,
        # so collapsing it here would only be re-expanded on the next run.
        if statement.force_parenthesized:
            return render_parenthesized(
                statement.module, sort_imported_names(statement.imported)
            )
        return render_from_import(statement.module, statement.imported)
    modules = ", ".join(name.raw for name in sort_imported_names(statement.imported))
    return f"import {modules}\n"


def strip_strings_and_comments(text: str) -> str:
    """Blanks out string and comment content, keeping the newlines.

    A backslash escapes the next character, so a string holding an escaped
    quote is one string. Without that the scanner ends it early and starts
    reading code as string content, or the reverse.
    """
    result: list[str] = []
    index = 0
    quote: str | None = None
    triple = False
    while index < len(text):
        char = text[index]
        if quote:
            if triple and text.startswith(quote * 3, index):
                quote = None
                triple = False
                index += 3
                result.append(" ")
                continue
            if char == "\\":
                result.append("  ")
                index += 2
                continue
            if not triple and char == quote:
                quote = None
            result.append("\n" if char == "\n" else " ")
            index += 1
            continue
        if char == "#":
            while index < len(text) and text[index] != "\n":
                result.append(" ")
                index += 1
            continue
        if char in ("'", '"'):
            quote = char
            triple = text.startswith(char * 3, index)
            index += 3 if triple else 1
            result.append(" ")
            continue
        result.append(char)
        index += 1
    return "".join(result)


def used_identifiers(text: str) -> set[str]:
    stripped = strip_strings_and_comments(text)
    return {
        normalize_identifier(match.group(0)) for match in IDENT_RE.finditer(stripped)
    }


def remove_unused_imports(
    statements: list[ImportStatement], head: str, body: str
) -> list[ImportStatement]:
    """Drops names that appear nowhere else in the file.

    `head` is the module docstring, whose fenced examples name the imports they
    demonstrate. It is scanned raw rather than through
    `strip_strings_and_comments`, which would blank the whole of it -- so a
    name used only by an example still counts, and the docs cannot end up
    referring to an import the file no longer has.
    """
    used = used_identifiers(body) | set(WORD_RE.findall(head))
    kept: list[ImportStatement] = []
    for statement in statements:
        if statement.has_wildcard or not statement.imported:
            kept.append(statement)
            continue
        names = tuple(name for name in statement.imported if name.bound in used)
        if not names:
            continue
        if names == statement.imported:
            kept.append(statement)
        else:
            kept.append(replace(statement, imported=names))
    return kept


def merge_from_imports(statements: list[ImportStatement]) -> list[ImportStatement]:
    """Folds repeated `from X import ...` for the same X into one statement.

    What cannot be folded -- a plain `import X as Y`, a wildcard -- is still
    de-duplicated when the same statement was written twice.
    """
    merged: dict[str, ImportStatement] = {}
    verbatim: set[str] = set()
    output: list[ImportStatement] = []

    for statement in statements:
        if statement.kind != "from" or statement.has_wildcard:
            rendered = render_import_statement(statement)
            if rendered not in verbatim:
                verbatim.add(rendered)
                output.append(statement)
            continue

        existing = merged.get(statement.module)
        if existing is None:
            merged[statement.module] = statement
            output.append(statement)
            continue

        seen = {name.raw for name in existing.imported}
        names = list(existing.imported)
        for name in statement.imported:
            if name.raw not in seen:
                names.append(name)
                seen.add(name.raw)

        combined = replace(
            existing,
            imported=tuple(names),
            force_parenthesized=(
                existing.force_parenthesized or statement.force_parenthesized
            ),
        )
        merged[statement.module] = combined
        output[output.index(existing)] = combined

    return output


def organized_import_block(statements: list[ImportStatement]) -> str:
    statements = merge_from_imports(statements)
    grouped: dict[int, list[ImportStatement]] = {}
    for statement in statements:
        grouped.setdefault(import_group(statement.module), []).append(statement)

    blocks: list[str] = []
    for group in sorted(grouped):
        ordered = sorted(
            grouped[group],
            key=lambda statement: (
                statement.module.replace("`", "").lower(),
                render_import_statement(statement).lower(),
            ),
        )
        blocks.append("".join(render_import_statement(item) for item in ordered))
    return "\n".join(blocks)


def read_source(path: Path) -> str | None:
    """The file's text, or None when it is not something to rewrite.

    A carriage return or a byte-order mark would be normalised away on the way
    back out, rewriting every line of a file this tool was only asked to sort
    the imports of. Text that is not UTF-8 is not ours to touch either.
    """
    try:
        with path.open(encoding="utf-8", newline="") as handle:
            text = handle.read()
    except (UnicodeDecodeError, OSError):
        return None
    if "\r" in text or text.startswith("﻿"):
        return None
    return text


def organize_file(path: Path, *, remove_unused: bool) -> tuple[str, str | None]:
    """Returns (status, new text).

    Status is `unchanged`, `changed`, `no-imports`, or `skipped` when the
    import block holds a comment or a statement that cannot be parsed.
    """
    original = read_source(path)
    if original is None:
        return "skipped", None
    lines = original.splitlines(keepends=True)
    block = find_import_block(lines)
    if block is None:
        in_string = lines_inside_triple_quoted_strings(lines)
        has_import = any(
            starts_import(line)
            for index, line in enumerate(lines)
            if index not in in_string
        )
        return ("skipped" if has_import else "no-imports"), None

    start, end, raw_statements = block
    statements = []
    for text in raw_statements:
        statement = parse_import_statement(text)
        if statement is None or not statement.sortable:
            return "skipped", None
        statements.append(statement)

    head = "".join(lines[:start])
    tail = "".join(lines[end:])
    if remove_unused and path.name not in REEXPORTING_FILES and tail.strip():
        statements = remove_unused_imports(statements, head, tail)

    new_block = organized_import_block(statements)
    if not new_block:
        tail = tail.lstrip("\n")
    updated = head + new_block + tail
    if updated == original:
        return "unchanged", None
    return "changed", updated


def iter_mojo_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_dir():
            for suffix in MOJO_SUFFIXES:
                files.extend(path.rglob("*" + suffix))
        elif path.suffix in MOJO_SUFFIXES and path.exists():
            files.append(path)
    return sorted(set(files))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "paths",
        nargs="+",
        type=Path,
        help="Directories or files to organize recursively.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit non-zero if any file needs organizing. Writes nothing.",
    )
    parser.add_argument(
        "--diff", action="store_true", help="Print unified diffs. Writes nothing."
    )
    parser.add_argument(
        "--remove-unused",
        action="store_true",
        help=(
            "Also drop imported names that no longer appear in the file. "
            "Decided by a text scan, not by the compiler, so this only writes "
            "when --yes is given as well."
        ),
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Confirm that --remove-unused may write to disk.",
    )
    return parser


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv[1:])

    dry_run = args.check or args.diff
    if args.remove_unused and not dry_run and not args.yes:
        print(
            "--remove-unused decides 'unused' by a text scan, not by the "
            "compiler.\nReview it first:\n\n"
            f"    {Path(argv[0]).name} --remove-unused --diff <paths>\n\n"
            "then re-run with --yes to write.",
            file=sys.stderr,
        )
        return 2

    changed: list[Path] = []
    skipped: list[Path] = []
    for path in iter_mojo_files(args.paths):
        status, updated = organize_file(path, remove_unused=args.remove_unused)
        if status == "skipped":
            skipped.append(path)
            continue
        if status != "changed" or updated is None:
            continue
        changed.append(path)
        if args.diff:
            before = read_source(path) or ""
            sys.stdout.writelines(
                difflib.unified_diff(
                    before.splitlines(keepends=True),
                    updated.splitlines(keepends=True),
                    fromfile=str(path),
                    tofile=str(path),
                )
            )
        elif not args.check:
            with path.open("w", encoding="utf-8", newline="\n") as handle:
                handle.write(updated)

    if args.check:
        for path in changed:
            print(f"imports need organizing: {path}", file=sys.stderr)
        if changed:
            print("\nRun: pixi run organize_imports", file=sys.stderr)
        for path in skipped:
            print(f"skipped, imports not safe to rewrite: {path}", file=sys.stderr)
        return 1 if changed else 0

    if not args.diff:
        print(f"organized imports in {len(changed)} file(s)")
    for path in skipped:
        print(f"skipped, imports not safe to rewrite: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
