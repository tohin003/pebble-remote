#!/bin/bash
# Serialized, low-priority Swift builds for this package. Every lane builds through this script.
#   scripts/swift.sh build [--target X]      scripts/swift.sh test [--filter X]
# - One build at a time (an atomic mkdir lock; a dead holder's lock is taken over), nice 19, two compile jobs:
#   the Mac has 8 GB and Pebble's timed runs may be going (see scripts/hold-status.sh).
# - With Command Line Tools only (no Xcode yet), Swift Testing needs its framework path added by hand.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/.build-lock"
CLT_FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
cd "$ROOT"
"$ROOT/scripts/hold-status.sh" || true
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  holder=$(cat "$LOCK/pid" 2>/dev/null || echo "")
  if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then rm -rf "${LOCK:?}"; continue; fi
  [ $waited -eq 0 ] && echo "swift.sh: waiting for another lane's build (pid ${holder:-?})..."
  waited=$((waited+1)); sleep 2
  [ $waited -gt 450 ] && { echo "swift.sh: gave up after 15 minutes"; exit 75; }
done
echo $$ > "$LOCK/pid"
trap 'rm -rf "${LOCK:?}"' EXIT
extra=()
XCODE_DEV=/Applications/Xcode.app/Contents/Developer
if [ -d "$XCODE_DEV" ]; then
  # Xcode is chosen here, never through the global xcode-select, which Pebble's own builds also read.
  export DEVELOPER_DIR="$XCODE_DEV"
else
  # CLT ships _Testing_Foundation without its .swiftmodule, so "import Testing" next to "import Foundation" fails
  # unless cross-import overlays are off. Not needed with Xcode.
  extra=(-Xswiftc -F -Xswiftc "$CLT_FW" -Xlinker -F -Xlinker "$CLT_FW" -Xlinker -rpath -Xlinker "$CLT_FW"
         -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays)
fi
cmd="$1"; shift
nice -n 19 swift "$cmd" -j 2 ${extra[@]+"${extra[@]}"} "$@"
