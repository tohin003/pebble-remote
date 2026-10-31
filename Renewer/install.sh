#!/bin/bash
# Installs Pebble Remote Renewer, the menu-bar item that keeps Pebble Remote signed, for this Mac user. The lead runs
# it after review; it builds nothing itself. See Renewer/README.md.
#
#   Renewer/install.sh             put the app in place, add its login agent and start it
#   Renewer/install.sh --dry-run   print what it would do; change nothing
#
# Build it first, outside a Pebble HOLD:
#   scripts/swift.sh build --package-path Renewer -c release --product PebbleRemoteRenewer
# It writes:
#   ~/Library/Application Support/PebbleRemoteRenewer/Pebble Remote Renewer.app   (signed ad hoc: no identity, no Keychain)
#   ~/Library/LaunchAgents/io.github.tohin003.PebbleRemoteRenewer.plist             (starts it at every login)
# then loads the agent, which starts the app now. Run it again to update; Renewer/uninstall.sh removes it.
# Exit codes: 0 done, 64 usage, 66 the release build is missing; otherwise the failing tool's own code.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
LABEL=io.github.tohin003.PebbleRemoteRenewer
SUPPORT="$HOME/Library/Application Support/PebbleRemoteRenewer"
APP="$SUPPORT/Pebble Remote Renewer.app"
STAGE="$SUPPORT/.Pebble Remote Renewer.app.new"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
BINARY="$HERE/.build/release/PebbleRemoteRenewer"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DOMAIN="gui/$(/usr/bin/id -u)"
dry=0

say() { printf 'install.sh: %s\n' "$*"; }
run() {
  if [ "$dry" -eq 1 ]; then
    printf 'install.sh: would run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    -h|--help) /usr/bin/awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    *) say "unknown option: $1 (see --help)"; exit 64 ;;
  esac
  shift
done

if [ ! -x "$BINARY" ]; then
  say "no release build at $BINARY. Build it first, outside a Pebble HOLD:"
  say "  scripts/swift.sh build --package-path Renewer -c release --product PebbleRemoteRenewer"
  if [ "$dry" -eq 0 ]; then exit 66; fi
fi
if [ ! -f "$SUPPORT/state.json" ]; then
  say "note: no state file yet. Until scripts/renew.sh has installed Pebble Remote once (for example"
  say "      scripts/renew.sh --commit <the commit to install>), the item shows Xcode's newest profile date and can't renew."
fi

# 1. The folder (owner-only), and a running copy stopped.
run /bin/mkdir -p "$SUPPORT"
run /bin/chmod 700 "$SUPPORT"
if /bin/launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  say "stopping the running copy..."
  run /bin/launchctl bootout "$DOMAIN/$LABEL" || true
fi

# 2. The app bundle: the release binary, Info.plist naming this repository, an ad hoc signature. Assembled beside the
#    old copy, then swapped in, and registered with Launch Services so macOS lets it post notifications.
run /bin/rm -rf "${STAGE:?}"
run /bin/mkdir -p "$STAGE/Contents/MacOS"
run /bin/cp "$BINARY" "$STAGE/Contents/MacOS/PebbleRemoteRenewer"
run /bin/cp "$HERE/Support/Info.plist" "$STAGE/Contents/Info.plist"
run /usr/bin/plutil -replace PebbleRemoteRepository -string "$REPO" "$STAGE/Contents/Info.plist"
run /usr/bin/codesign --force --sign - --timestamp=none "$STAGE"
if [ -e "$APP" ]; then
  run "$LSREGISTER" -u "$APP" || true
  run /bin/rm -rf "${APP:?}"
fi
run /bin/mv "$STAGE" "$APP"
run "$LSREGISTER" -f "$APP"

# 3. The login agent: Support/LaunchAgent.plist with the app's executable filled in.
run /bin/mkdir -p "$HOME/Library/LaunchAgents"
if [ "$dry" -eq 1 ]; then
  say "would write $AGENT from $HERE/Support/LaunchAgent.plist, starting $APP/Contents/MacOS/PebbleRemoteRenewer"
else
  /usr/bin/python3 -I - "$HERE/Support/LaunchAgent.plist" "$AGENT" "$APP/Contents/MacOS/PebbleRemoteRenewer" <<'PY'
import os
import plistlib
import sys

template, agent, executable = sys.argv[1:4]
with open(template, 'rb') as handle:
    job = plistlib.load(handle)
job['ProgramArguments'] = [executable]
temporary = agent + '.new'
with open(temporary, 'wb') as handle:
    plistlib.dump(job, handle)
os.chmod(temporary, 0o644)
os.replace(temporary, agent)
PY
  /usr/bin/plutil -lint "$AGENT" >/dev/null
fi

# 4. Start it: launchd runs it now and at every login.
run /bin/launchctl bootstrap "$DOMAIN" "$AGENT"
if [ "$dry" -eq 1 ]; then
  say "dry run: nothing was changed."
  exit 0
fi
say "installed. The days left appear in the menu bar. The first time, macOS asks whether it may send notifications:"
say "allow them, so it can tell you when your iPhone needs connecting."
say "check it:  \"$APP/Contents/MacOS/PebbleRemoteRenewer\" --check"
say "its log:   ~/Library/Logs/PebbleRemoteRenewer.log"
