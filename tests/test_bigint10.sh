#!/bin/bash
set -e

for f in tests/bigint10/*.mojo; do
    pixi run mojo run -I src -D ASSERT=all -debug-level=line-tables "$f"
done
