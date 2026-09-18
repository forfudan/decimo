#!/bin/bash
# ===----------------------------------------------------------------------=== #
# Make the `argmojo` CLI-parsing package available for the Decimo CLI build.
#
# Two sources, tried in order:
#
#   1. The conda package `argmojo` from the modular-community channel
#      (declared in pixi.toml's [dependencies]).  If the environment already
#      provides argmojo, nothing else is done.
#
#   2. Fallback: the upstream git repository, pinned at $ARGMOJO_COMMIT
#      (= release v0.8.0).  The sources are cloned into temp/argmojo and
#      precompiled to temp/argmojo.mojoc, which the CLI build picks up
#      through its `-I temp` include path.
#
# Usage:
#   bash src/cli/ensure_argmojo.sh          # auto-detect (used by `pixi run buildcli`)
#
# Environment overrides:
#   DECIMO_ARGMOJO=conda   require the environment-provided package (no git fallback)
#   DECIMO_ARGMOJO=git     force the pinned git checkout, ignoring any conda package
#   ARGMOJO_COMMIT=<sha>   use a different upstream commit
#   ARGMOJO_REPO=<url>     use a different upstream repository
# ===----------------------------------------------------------------------=== #

set -euo pipefail

ARGMOJO_REPO="${ARGMOJO_REPO:-https://github.com/forfudan/argmojo.git}"
# https://github.com/forfudan/argmojo/releases#release-v0.8.0
ARGMOJO_COMMIT="${ARGMOJO_COMMIT:-2ba77c1be364e49fe7db88c724dd0f9a25ed3a44}"
MODE="${DECIMO_ARGMOJO:-auto}"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
mkdir -p temp

CLONE_DIR="temp/argmojo"
PKG="temp/argmojo.mojoc"
STAMP="temp/.argmojo.commit"

# --- 1. Is argmojo already importable from the environment? ---------------- #
# Compile a two-line probe *without* `-I temp`, so only a package provided by
# the environment (i.e. the conda one) can satisfy the import.
env_has_argmojo() {
    # The probe lives in its own directory: Mojo also searches the source
    # file's directory, so a probe in temp/ would find temp/argmojo.mojoc.
    local dir
    dir="$(mktemp -d)"
    printf 'from argmojo import Command\n\ndef main():\n    pass\n' >"$dir/probe.mojo"
    local ok=0
    pixi run mojo build -o "$dir/probe" "$dir/probe.mojo" >/dev/null 2>&1 || ok=1
    rm -rf "$dir"
    return $ok
}

if [[ "$MODE" != "git" ]]; then
    if env_has_argmojo; then
        # A stale fallback build would shadow the conda package via `-I temp`.
        rm -f "$PKG" "$STAMP"
        echo "argmojo: using the package provided by the environment (conda)."
        exit 0
    fi
    if [[ "$MODE" == "conda" ]]; then
        echo "argmojo: DECIMO_ARGMOJO=conda, but no argmojo package is installed." >&2
        echo "         Add it to pixi.toml [dependencies] or unset DECIMO_ARGMOJO." >&2
        exit 1
    fi
fi

# --- 2. Fallback: pinned git checkout -------------------------------------- #
# The stamp holds the commit and the compiler version, so a compiler upgrade
# rebuilds the package instead of reusing an incompatible one.
STAMP_VALUE="$ARGMOJO_COMMIT $(pixi run mojo --version)"
if [[ -f "$PKG" && -f "$STAMP" && "$(cat "$STAMP")" == "$STAMP_VALUE" ]]; then
    echo "argmojo: reusing $PKG (commit ${ARGMOJO_COMMIT:0:8})."
    exit 0
fi

echo "argmojo: not provided by the environment, falling back to"
echo "         $ARGMOJO_REPO @ ${ARGMOJO_COMMIT:0:8}"

if [[ ! -d "$CLONE_DIR/.git" ]]; then
    rm -rf "$CLONE_DIR"
    git clone --quiet "$ARGMOJO_REPO" "$CLONE_DIR"
fi
if ! git -C "$CLONE_DIR" cat-file -e "$ARGMOJO_COMMIT^{commit}" 2>/dev/null; then
    git -C "$CLONE_DIR" fetch --quiet --all --tags --prune
fi
git -C "$CLONE_DIR" checkout --quiet --detach "$ARGMOJO_COMMIT"

pixi run mojo precompile "$CLONE_DIR/src/argmojo" -o "$PKG"
echo "$STAMP_VALUE" >"$STAMP"
echo "argmojo: built $PKG from ${ARGMOJO_COMMIT:0:8}."
