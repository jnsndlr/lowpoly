#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
engine=${GODOT_BIN:-godot}
log=$(mktemp)
trap 'rm -f "$log"' EXIT

check() {
  "$engine" --headless --path . "$@" 2>&1 | tee "$log"
  # Godot can still exit successfully after reporting a broken script or resource.
  if grep -Eq '^[[:space:]]*(SCRIPT ERROR|ERROR):' "$log"; then
    return 1
  fi
}

check --editor --import
check --script tools/fast_ferry_test.gd
check --fixed-fps 30 --quit-after 120 -- --seed=123
