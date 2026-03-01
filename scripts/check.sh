#!/bin/bash
# Quality checks for md-ts-mode — run before commits

set -e

cd "$(dirname "$0")/.."

make check
make clean
