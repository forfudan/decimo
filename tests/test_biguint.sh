#!/bin/bash
set -e

for f in tests/biguint/*.mojo; do
    pixi run mojo run -I src -D ASSERT=all --debug-level=full "$f"
done
