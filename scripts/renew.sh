#!/bin/bash
# Renew Pebble Remote on the paired iPhone. A free (Personal Team) signing profile lasts 7 days; building again with
# -allowProvisioningUpdates renews it, and installing over the old app keeps its data and Keychain items.
#
#   scripts/renew.sh              build this tree, install on the paired iPhone, print the new expiry date
#   scripts/renew.sh --commit REV build commit REV in a clean worktree instead, never a working tree (the menu-bar
#                                 renewer, Renewer/, runs this with the commit last installed)
#   scripts/renew.sh --force      the same even while a Pebble HOLD is active (timed benchmarks)
#   scripts/renew.sh --device ID  install on this devicectl identifier (when several iPhones are paired)
#   scripts/renew.sh --dry-run    print the steps and commands; build and install nothing
#
# Needs Xcode signed in with the person's Apple ID, PebbleRemote.xcodeproj (XcodeGen, project.yml), and the iPhone
# paired with this Mac (cable or the same Wi-Fi, Developer Mode on). Builds use Xcode through DEVELOPER_DIR (never the
# global xcode-select), at nice 19 with two jobs.
# After a successful install it records the build for the menu-bar renewer in an owner-only state file,
# ~/Library/Application Support/PebbleRemoteRenewer/state.json: the commit, the device, and the profile's dates (nothing
# else from the profile). The clean worktree for --commit lives in the same folder; PEBBLE_REMOTE_RENEWER_DIR moves both.
# Exit codes: 0 done, 64 usage, 66 no project, 69 no Xcode or no iPhone, 73 the clean worktree could not be prepared
# (unknown commit, or git failed), 75 HOLD or another renewal using the clean worktree, 1 no app or no expiry date
# found; otherwise the failing tool's own code.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GIT=/usr/bin/git
XCODE_DEV=/Applications/Xcode.app/Contents/Developer
RENEWER_DIR="${PEBBLE_REMOTE_RENEWER_DIR:-$HOME/Library/Application Support/PebbleRemoteRenewer}"
STATE="$RENEWER_DIR/state.json"
WORKTREE="$RENEWER_DIR/worktree"
LOCK="$RENEWER_DIR/worktree.lock"
force=0
dry=0
device=""
commit=""
sha=""
list=""
profile=""
locked=0

usage() { /usr/bin/awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }
say() { printf 'renew.sh: %s\n' "$*"; }
run() {
  if [ "$dry" -eq 1 ]; then
    printf 'renew.sh: would run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}
cleanup() {
  if [ -n "$list" ]; then /bin/rm -f "$list"; fi
  if [ -n "$profile" ]; then /bin/rm -f "$profile"; fi
  if [ "$locked" -eq 1 ]; then /bin/rm -rf "${LOCK:?}"; fi
}
trap cleanup EXIT

# Xcode for this run only, never through the global xcode-select, which Pebble's own builds read (as scripts/swift.sh).
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "$XCODE_DEV" ]; then
  export DEVELOPER_DIR="$XCODE_DEV"
fi

# The paired iPhone in a `devicectl list devices --json-output` file: the only paired one (a connected one first).
# (Here-documents live in functions, not inside $(...): macOS /bin/bash 3.2 mis-parses those.)
pick_iphone() {
  /usr/bin/python3 -I - "$1" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    devices = json.load(handle).get('result', {}).get('devices', [])


def field(item, *path):
    for key in path:
        item = item.get(key) if isinstance(item, dict) else None
    return item


phones = [d for d in devices
          if field(d, 'hardwareProperties', 'platform') == 'iOS'
          and field(d, 'hardwareProperties', 'deviceType') in (None, 'iPhone')
          and field(d, 'connectionProperties', 'pairingState') == 'paired']
connected = [d for d in phones if field(d, 'connectionProperties', 'tunnelState') == 'connected']
choice = connected or phones
if len(choice) != 1:
    if choice:
        names = ', '.join('%s (%s)' % (field(d, 'deviceProperties', 'name') or 'iPhone', d.get('identifier'))
                          for d in choice)
        print('several iPhones are paired: ' + names + '. Pass --device with one of them.', file=sys.stderr)
    else:
        print('no paired iPhone found. Connect it by cable once, turn on Developer Mode and trust this Mac.',
              file=sys.stderr)
    sys.exit(1)
print(choice[0]['identifier'])
PY
}

# The expiry date in a decoded profile (security cms -D), in local time, with the days left.
expiry_text() {
  /usr/bin/python3 -I - "$1" <<'PY'
import datetime
import plistlib
import sys

with open(sys.argv[1], 'rb') as handle:
    end = plistlib.load(handle)['ExpirationDate']
if end.tzinfo is None:
    end = end.replace(tzinfo=datetime.timezone.utc)  # plistlib gives naive UTC dates
days = (end - datetime.datetime.now(datetime.timezone.utc)).total_seconds() / 86400
print(end.astimezone().strftime('%a %d %b %Y, %H:%M') + ' (in %.1f days)' % days)
PY
}

# What is on the iPhone now, for the menu-bar renewer: the commit built (and whether its tree was clean), the device,
# and the decoded profile's dates and app id. Owner-only folder (0700) and file (0600), replaced in one step.
record_state() {
  local built_commit="" clean="" from="tree"
  if [ -n "$sha" ]; then
    built_commit="$sha"
    clean=1
    from="worktree"
  elif "$GIT" -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    built_commit=$("$GIT" -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
    if [ -z "$("$GIT" -C "$ROOT" status --porcelain 2>/dev/null)" ]; then clean=1; else clean=0; fi
  fi
  /usr/bin/python3 -I - "$1" "$STATE" "$built_commit" "$clean" "$from" "$device" <<'PY'
import datetime
import json
import os
import plistlib
import sys
import tempfile

profile_path, state_path, commit, clean, built_from, device = sys.argv[1:7]
with open(profile_path, 'rb') as handle:
    profile = plistlib.load(handle)


def iso(moment):
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=datetime.timezone.utc)  # plistlib gives naive UTC dates
    return moment.astimezone(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


# Only the profile's dates and its app id's bundle part are kept; never its certificates, devices or team name.
app_id = (profile.get('Entitlements') or {}).get('application-identifier') or ''
state = {
    'version': 1,
    'installedAt': iso(datetime.datetime.now(datetime.timezone.utc)),
    'commit': commit or None,
    'treeWasClean': {'1': True, '0': False}.get(clean),
    'builtFrom': built_from,
    'device': device or None,
    'bundleId': app_id.split('.', 1)[1] if '.' in app_id else None,
    'profileCreated': iso(profile['CreationDate']),
    'profileExpires': iso(profile['ExpirationDate']),
}
folder = os.path.dirname(state_path)
os.makedirs(folder, mode=0o700, exist_ok=True)
os.chmod(folder, 0o700)
handle, temporary = tempfile.mkstemp(dir=folder, prefix='.state-', suffix='.json')  # created 0600
with os.fdopen(handle, 'w') as out:
    json.dump(state, out, indent=2, sort_keys=True)
    out.write('\n')
os.replace(temporary, state_path)
PY
}

# One renewal at a time in the clean worktree (the menu-bar renewer and a run by hand could meet there).
take_lock() {
  local holder
  /bin/mkdir -p "$RENEWER_DIR"
  /bin/chmod 700 "$RENEWER_DIR"
  until /bin/mkdir "$LOCK" 2>/dev/null; do
    holder=$(/bin/cat "$LOCK/pid" 2>/dev/null || true)
    if [ -z "$holder" ]; then
      /bin/sleep 2  # its owner may be writing its pid right now
      holder=$(/bin/cat "$LOCK/pid" 2>/dev/null || true)
    fi
    if [ -z "$holder" ] || ! kill -0 "$holder" 2>/dev/null; then
      /bin/rm -rf "${LOCK:?}"
      continue
    fi
    say "another renewal is using the clean worktree (pid $holder); try again when it is done."
    exit 75
  done
  locked=1
  echo $$ > "$LOCK/pid"
}

# The clean worktree at commit $1: created once (git worktree add), then moved to each commit with local changes and
# untracked files dropped. Ignored build products (build/) stay, so later builds are incremental. Called in an `if`,
# so every step is chained: set -e does not apply here.
prepare_worktree() {
  local common_repo common_tree top_tree
  common_repo=$("$GIT" -C "$ROOT" rev-parse --path-format=absolute --git-common-dir) || return 1
  if [ -e "$WORKTREE" ]; then
    common_tree=$("$GIT" -C "$WORKTREE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    # Git searches upwards from a folder that is not a worktree itself, so a plain folder (or a link) inside the main
    # checkout passes the check above, and checkout --force and clean would then run there. Its own top level must be
    # the folder itself.
    top_tree=$("$GIT" -C "$WORKTREE" rev-parse --show-toplevel 2>/dev/null || true)
    if [ "$common_tree" != "$common_repo" ] || [ -z "$top_tree" ] \
      || [ "$(cd "$top_tree" && pwd -P)" != "$(cd "$WORKTREE" && pwd -P)" ]; then
      say "$WORKTREE exists but is not a worktree of this repository. Move it away, then run this again."
      return 1
    fi
    "$GIT" -C "$WORKTREE" checkout --quiet --force --detach "$sha" && "$GIT" -C "$WORKTREE" clean -fdq
  else
    "$GIT" -C "$ROOT" worktree add --force --detach "$WORKTREE" "$sha"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
    --dry-run) dry=1 ;;
    --device)
      if [ $# -lt 2 ] || [ -z "$2" ]; then say "--device needs a devicectl identifier"; exit 64; fi
      device="$2"
      shift
      ;;
    --commit)
      if [ $# -lt 2 ] || [ -z "$2" ]; then say "--commit needs a commit (a hash, tag or branch)"; exit 64; fi
      commit="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) say "unknown option: $1 (see --help)"; exit 64 ;;
  esac
  shift
done

# 1. Pebble's timed runs come first: no build during a HOLD unless the person says so.
hold=0
"$ROOT/scripts/hold-status.sh" || hold=$?
if [ "$hold" -eq 3 ]; then
  if [ "$force" -eq 1 ]; then
    say "a Pebble HOLD is active; going ahead because of --force."
  elif [ "$dry" -eq 1 ]; then
    say "a Pebble HOLD is active: a real run would stop here (pass --force to override)."
  else
    say "a Pebble HOLD is active (timed benchmarks), so nothing was built. Run this again after it lifts, or pass --force."
    exit 75
  fi
fi

# 2. Xcode.
if ! /usr/bin/xcode-select -p 2>/dev/null | /usr/bin/grep -q '\.app/'; then
  if [ "$dry" -eq 1 ]; then
    say "Xcode is not installed or not selected: a real run would stop here."
  else
    say "Xcode is not installed or not selected (xcode-select -p). Install it and sign in with your Apple ID first."
    exit 69
  fi
fi

# 3. With --commit, build that commit in the clean worktree, never in a working tree: a half-done change then never
#    reaches the iPhone.
if [ -n "$commit" ]; then
  if [ "$(cd "$WORKTREE" 2>/dev/null && pwd -P)" = "$(pwd -P)" ]; then
    say "run scripts/renew.sh from the repository, not from the clean worktree it builds in."
    exit 64
  fi
  if ! sha=$("$GIT" -C "$ROOT" rev-parse --verify --quiet "${commit}^{commit}"); then
    say "commit $commit is not in this repository."
    exit 73
  fi
  if ! "$GIT" -C "$ROOT" cat-file -e "$sha:PebbleRemote.xcodeproj/project.pbxproj" 2>/dev/null; then
    say "commit ${sha:0:7} has no PebbleRemote.xcodeproj, so it can't be built here."
    exit 66
  fi
  if [ "$dry" -eq 1 ]; then
    say "would build commit ${sha:0:7} in the clean worktree $WORKTREE:"
    if [ -e "$WORKTREE" ]; then
      run "$GIT" -C "$WORKTREE" checkout --quiet --force --detach "$sha"
      run "$GIT" -C "$WORKTREE" clean -fdq
    else
      run "$GIT" -C "$ROOT" worktree add --force --detach "$WORKTREE" "$sha"
    fi
  else
    take_lock
    say "preparing the clean worktree at commit ${sha:0:7}..."
    if ! prepare_worktree; then
      say "could not prepare the clean worktree in $WORKTREE (see above)."
      exit 73
    fi
    cd "$WORKTREE"
  fi
fi

# 4. The project.
if [ ! -d "PebbleRemote.xcodeproj" ]; then
  if [ "$dry" -eq 1 ]; then
    say "PebbleRemote.xcodeproj is missing: a real run would stop here (generate it from project.yml)."
  else
    say "PebbleRemote.xcodeproj is missing. Generate it from project.yml (XcodeGen) first."
    exit 66
  fi
fi

# 5. Build. -allowProvisioningUpdates lets Xcode renew the 7-day profile for the person's Personal Team. Nice 19 and two
#    jobs: the Mac has 8 GB, and Pebble's timed runs may be going.
say "building for iOS (this renews the signing profile)..."
run nice -n 19 xcodebuild -project PebbleRemote.xcodeproj -scheme PebbleRemote -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates -derivedDataPath build/ -jobs 2 build

if [ "$dry" -eq 1 ]; then
  app="build/Build/Products/Debug-iphoneos/PebbleRemote.app"
else
  app=$(/usr/bin/find build/Build/Products -maxdepth 2 -type d -name 'PebbleRemote.app' -path '*-iphoneos/*' \
        2>/dev/null | /usr/bin/head -1)
  if [ -z "$app" ]; then
    say "the build finished, but no PebbleRemote.app was found under build/Build/Products/*-iphoneos/."
    exit 1
  fi
fi

# 6. The paired iPhone, unless --device names it.
if [ -z "$device" ]; then
  if [ "$dry" -eq 1 ]; then
    say "would choose the paired iPhone from: xcrun devicectl list devices --json-output <file>"
    device="<paired iPhone>"
  else
    list=$(/usr/bin/mktemp -t pebble-remote-devices)
    xcrun devicectl list devices --json-output "$list" >/dev/null
    if ! device=$(pick_iphone "$list"); then
      say "could not choose an iPhone (see above)."
      exit 69
    fi
  fi
fi

# 7. Install. A first install can fail with IXRemoteErrorDomain 6; a second try has always worked so far.
say "installing on $device..."
if ! run xcrun devicectl device install app --device "$device" "$app"; then
  say "the install failed; trying once more in 10 seconds."
  /bin/sleep 10
  run xcrun devicectl device install app --device "$device" "$app"
fi

# 8. The new expiry date, read from the profile inside the app that was just installed, and the state file.
if [ "$dry" -eq 1 ]; then
  say "would print the expiry date from $app/embedded.mobileprovision"
  say "would record this build in $STATE"
  exit 0
fi
profile=$(/usr/bin/mktemp -t pebble-remote-profile)
if ! /usr/bin/security cms -D -i "$app/embedded.mobileprovision" > "$profile" 2>/dev/null \
  || ! expiry=$(expiry_text "$profile"); then
  say "installed, but the expiry date could not be read from $app/embedded.mobileprovision."
  exit 1
fi
say "installed. This build expires $expiry. Run scripts/renew.sh again before then."
if record_state "$profile"; then
  say "recorded this build for the menu-bar renewer in $STATE."
else
  say "could not record this build in $STATE, so the menu-bar renewer still shows the one before."
fi
