#!/bin/bash
# Shared test helpers. Sourced by every tests/*_test.sh; no network, no root.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HELPERS_DIR="${REPO_ROOT}/docker/helpers"
export SECTIONS_DIR="${REPO_ROOT}/docker/sections"
export DEFAULTS_DIR="${REPO_ROOT}/docker/defaults"
WORKROOT="$(mktemp -d)"
trap 'rm -rf "$WORKROOT"' EXIT
export CONTAINER_HOME="${WORKROOT}/home"
mkdir -p "$CONTAINER_HOME"
FAILED=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILED=1; }

# check <description> <expected> <actual>
check() {
    if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

finish() {
    if [[ "$FAILED" == "0" ]]; then echo "All tests passed."; exit 0; fi
    exit 1
}
