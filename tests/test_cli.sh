#!/bin/bash
set -e  # Exit immediately if any command fails

for f in tests/cli/*.mojo; do
    pixi run mojo run -I src -I src/cli -D ASSERT=all -debug-level=line-tables "$f"
done
