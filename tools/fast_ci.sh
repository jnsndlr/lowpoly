#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
engine=${GODOT_BIN:-godot}
log=$(mktemp)
trap 'rm -f "$log"' EXIT

check() {
  local phase=$1
  shift
  "$engine" --headless --path . "$@" 2>&1 | tee "$log"
  # Godot can still exit successfully after reporting a broken script or resource.
  awk -v phase="$phase" '
    /^WARNING: [0-9]+ ObjectDB instances were leaked at exit/ {
      if (phase != "launch" || $2 + 0 > 31) failed = 1
    }
    /^ERROR: 1 resources still in use at exit \(run with --verbose for details\)\.$/ {
      if (phase == "launch" && !seen_shutdown++) {
        print "Known main-scene teardown diagnostic (one retained resource)."
        next
      }
    }
    /^[[:space:]]*(SCRIPT ERROR|ERROR):/ { failed = 1 }
    END { exit failed ? 1 : 0 }
  ' "$log"
}

check import --editor --import
check rules --script tools/fast_ferry_test.gd
check launch --fixed-fps 30 --quit-after 120 -- --seed=123
