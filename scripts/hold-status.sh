#!/bin/bash
# Prints Pebble's current HOLD state from the shared status file. Exit 0 = no hold, 3 = a Pebble-side HOLD is active.
# During a HOLD: code, docs and scripts/swift.sh only. No Xcode builds, simulators, installs or other heavy jobs.
# The state is the word right after the line's time ("- **HH:MM HOLD ..." or "- **HH:MM Hold lifted ..."), never a
# phrase later in the line: "HOLD continues ... until our "Hold lifted" line" is still a HOLD.
# The status file is the author's own coordination file, named by PEBBLE_HOLD_STATUS_FILE. Without it there is never
# a HOLD, so this prints nothing and exits 0.
STATUS="${PEBBLE_HOLD_STATUS_FILE:-}"
{ [ -n "$STATUS" ] && [ -f "$STATUS" ]; } || exit 0
last=$(/usr/bin/grep -E '^- \*\*[0-9]{2}:[0-9]{2} (HOLD|Hold lifted)' "$STATUS" | tail -1)
if [[ $last =~ ^-\ \*\*[0-9]{2}:[0-9]{2}\ Hold\ lifted ]]; then
  echo "hold-status: no Pebble HOLD (last: ${last:4:60}...)"; exit 0
fi
if [[ $last =~ ^-\ \*\*[0-9]{2}:[0-9]{2}\ HOLD ]]; then
  echo "hold-status: Pebble HOLD active -> light work only (${last:4:100}...)"; exit 3
fi
exit 0
