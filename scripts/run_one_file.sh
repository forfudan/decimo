#!/bin/bash
# Run one off-tree Mojo file against the working tree in `src/`.
#
# Usage:
#   pixi run one path/to/file.mojo [mojo flags...]
#
# `mojo run` puts the file's own directory on the import path ahead of any
# `-I`, so a `decimo.mojoc` sitting beside the file silently stands in for
# `src/decimo`, and the run then reports on code that is not there. The
# programs that get run this way -- a sweep against a reference, a
# measurement, a quick probe -- are usually written outside the repository,
# where nothing cleans up after them. So the packages beside the file go
# first, and the run is told where the source is.
#
# The same hazard, from the other direction, is why `package_decimo` writes
# into `tests/` rather than into the repository root.

set -eo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

if [[ -z $1 ]]; then
    echo "usage: pixi run one <file.mojo> [mojo flags...]" >&2
    exit 2
fi

FILE=$1
shift

if [[ ! -f $FILE ]]; then
    echo "run_one_file.sh: no such file: $FILE" >&2
    exit 2
fi

FILE=$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")
DIR=$(dirname "$FILE")

shopt -s nullglob
for package in "$DIR"/*.mojoc "$DIR"/*.mojopkg; do
    echo "run_one_file.sh: removing $package, which would shadow src/"
    rm -f "$package"
done
shopt -u nullglob

cd "$REPO_ROOT"
exec pixi run mojo run -I src "$@" "$FILE"
