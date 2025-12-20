#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cp -r audit "$ROOT/"
cp -r docs "$ROOT/"
cp -r certora "$ROOT/"
cp -r scribble "$ROOT/"
cp -r contracts "$ROOT/audit-contracts"
mkdir -p "$ROOT/.github/workflows"
cp .github/workflows/formal.yml "$ROOT/.github/workflows/formal.yml"
echo "Installed audit bundle into repo root."
