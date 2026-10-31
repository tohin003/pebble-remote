#!/bin/bash
# Removes Pebble Remote Renewer for this Mac user. See Renewer/README.md.
#
#   Renewer/uninstall.sh            stop it, and remove its login agent and the app. Keeps the state file (renew.sh
#                                   writes it too), the clean worktree (so a reinstall builds faster) and the log.
#   Renewer/uninstall.sh --all      also remove the clean worktree (through git), the renewer's files and its log
#   Renewer/uninstall.sh --dry-run  print what it would do; change nothing
# It never touches the iPhone, Pebble Remote's app, Xcode's profiles or the Keychain.
# Exit codes: 0 done, 64 usage; otherwise the failing tool's own code.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
LABEL=io.github.tohin003.PebbleRemoteRenewer
SUPPORT="$HOME/Library/Application Support/PebbleRemoteRenewer"
APP="$SUPPORT/Pebble Remote Renewer.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/PebbleRemoteRenewer.log"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DOMAIN="gui/$(/usr/bin/id -u)"
all=0
dry=0

say() { printf 'uninstall.sh: %s\n' "$*"; }
run() {
  if [ "$dry" -eq 1 ]; then
    printf 'uninstall.sh: would run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --all) all=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) /usr/bin/awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    *) say "unknown option: $1 (see --help)"; exit 64 ;;
  esac
  shift
done

# 1. Stop it and remove its login agent.
if /bin/launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  run /bin/launchctl bootout "$DOMAIN/$LABEL" || true
fi
if [ -e "$AGENT" ]; then run /bin/rm -f "$AGENT"; fi

# 2. The app.
if [ -e "$APP" ]; then
  run "$LSREGISTER" -u "$APP" || true
  run /bin/rm -rf "${APP:?}"
fi

# 3. With --all: the clean worktree (unregistered through git), the renewer's own files, its log.
if [ "$all" -eq 1 ]; then
  if [ -e "$SUPPORT/worktree" ]; then
    if ! run /usr/bin/git -C "$REPO" worktree remove --force "$SUPPORT/worktree"; then
      say "git couldn't remove the worktree; removing its folder and pruning git's record of it."
      run /bin/rm -rf "${SUPPORT:?}/worktree"
      run /usr/bin/git -C "$REPO" worktree prune
    fi
  fi
  for path in "$SUPPORT/state.json" "$SUPPORT/renewer.json" "$SUPPORT/renewer.lock" "$SUPPORT/worktree.lock" \
              "$SUPPORT"/.state-*.json "$SUPPORT"/.renewer.json.* "$LOG" "$LOG.1"; do
    if [ -e "$path" ]; then run /bin/rm -rf "$path"; fi
  done
  if [ -d "$SUPPORT" ] && ! run /bin/rmdir "$SUPPORT" 2>/dev/null; then
    say "left $SUPPORT in place: it holds files this script didn't make."
  fi
fi
if [ "$dry" -eq 1 ]; then say "dry run: nothing was changed."; else say "removed."; fi
